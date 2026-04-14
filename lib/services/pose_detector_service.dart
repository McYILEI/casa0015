import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Phase of a single pull-up repetition.
///
/// Coordinate note: ML Kit uses image-space Y (top = 0, increases downward).
/// - Hanging : noseY >> wristY  (nose far below the bar)
/// - At top  : noseY ≈ wristY  (chin clears the bar)
enum PullUpPhase { idle, hanging, ascending, atTop, descending }

class PoseDetectorService {
  // ── ML Kit detector ────────────────────────────────────────────────────────
  final PoseDetector _poseDetector = PoseDetector(
    options: PoseDetectorOptions(
      model: PoseDetectionModel.accurate,
      mode: PoseDetectionMode.stream,
    ),
  );

  // ── State ──────────────────────────────────────────────────────────────────
  PullUpPhase _phase = PullUpPhase.idle;
  int _count = 0;

  int get count => _count;
  PullUpPhase get phase => _phase;

  // ── Baseline (captured when hanging at bottom) ─────────────────────────────
  /// Average nose Y while hanging (image-space, so a larger number = lower).
  double? _baselineNoseY;

  /// Nose-to-bar distance at hang: baselineNoseY - wristY at hang.
  /// Used to normalise all thresholds so they scale with body size & camera
  /// distance automatically.
  double? _hangDistance;

  // ── Position smoothing (rolling average) ──────────────────────────────────
  final _noseYBuf = <double>[];
  final _wristYBuf = <double>[];
  static const _kBufSize = 5;

  // ── Anti-bounce ────────────────────────────────────────────────────────────
  DateTime? _lastCountTime;
  static const _kMinRepMs = 800;

  // ── Stream ─────────────────────────────────────────────────────────────────
  final _countController = StreamController<int>.broadcast();
  Stream<int> get countStream => _countController.stream;

  bool _isProcessing = false;

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<void> processImage(
      CameraImage image, InputImageRotation rotation) async {
    if (_isProcessing) return;
    _isProcessing = true;
    try {
      final inputImage = _buildInputImage(image, rotation);
      if (inputImage == null) return;
      final poses = await _poseDetector.processImage(inputImage);
      if (poses.isEmpty) return;
      _processPose(poses.first);
    } catch (_) {
      // silently ignore transient errors
    } finally {
      _isProcessing = false;
    }
  }

  void incrementManual() {
    _count++;
    _countController.add(_count);
  }

  void decrementManual() {
    if (_count > 0) {
      _count--;
      _countController.add(_count);
    }
  }

  void resetCount() {
    _count = 0;
    _phase = PullUpPhase.idle;
    _baselineNoseY = null;
    _hangDistance = null;
    _noseYBuf.clear();
    _wristYBuf.clear();
    _lastCountTime = null;
  }

  Future<void> dispose() async {
    await _poseDetector.close();
    await _countController.close();
  }

  // ── Core detection ─────────────────────────────────────────────────────────

  void _processPose(Pose pose) {
    // ── Landmark extraction ───────────────────────────────────────────────
    final nose = pose.landmarks[PoseLandmarkType.nose];
    final lWrist = pose.landmarks[PoseLandmarkType.leftWrist];
    final rWrist = pose.landmarks[PoseLandmarkType.rightWrist];
    final lShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    final lElbow = pose.landmarks[PoseLandmarkType.leftElbow];
    final rElbow = pose.landmarks[PoseLandmarkType.rightElbow];

    // Require sufficient confidence on the key points.
    if (nose == null || nose.likelihood < 0.65) return;
    if (lWrist == null || rWrist == null) return;
    if (lWrist.likelihood < 0.60 || rWrist.likelihood < 0.60) return;
    if (lShoulder == null || rShoulder == null) return;

    // ── Smoothed positions (reduces single-frame jitter) ─────────────────
    final noseY = _smooth(_noseYBuf, nose.y);
    final wristY = _smooth(_wristYBuf, (lWrist.y + rWrist.y) / 2.0);
    final shoulderY = (lShoulder.y + rShoulder.y) / 2.0;

    // ── Optional: average elbow angle (confirms full extension / full pull) ─
    final elbowAngle = _avgElbowAngle(
      lShoulder, lElbow, lWrist,
      rShoulder, rElbow, rWrist,
    );

    // ── State machine ─────────────────────────────────────────────────────
    switch (_phase) {
      // ────────────────────────────────────────────────────────────────────
      // IDLE → wait until both wrists are clearly above both shoulders.
      // This guards against counting from a non-bar-hanging position.
      case PullUpPhase.idle:
        if (wristY < shoulderY - 20) {
          _phase = PullUpPhase.hanging;
          _setBaseline(noseY, wristY);
        }

      // ────────────────────────────────────────────────────────────────────
      // HANGING (bottom of rep) → keep refreshing baseline while idle at
      // the bottom, then transition to ASCENDING once the nose has risen
      // at least 15 % of hang-distance above the baseline.
      case PullUpPhase.hanging:
        // Wrists must still be above shoulders to stay in hanging.
        if (wristY >= shoulderY) {
          _phase = PullUpPhase.idle;
          return;
        }

        // Continuously update baseline while the body stays near the bottom.
        // Stop updating once the upward movement starts.
        final hd = _hangDistance ?? 1.0;
        if (noseY >= _baselineNoseY! - hd * 0.10) {
          _setBaseline(noseY, wristY);
        }

        // Transition to ascending when nose has clearly moved upward.
        if (noseY < _baselineNoseY! - hd * 0.15) {
          _phase = PullUpPhase.ascending;
        }

      // ────────────────────────────────────────────────────────────────────
      // ASCENDING → count only once chin clears the bar.
      // "Bar level" = current wristY (the bar doesn't move).
      // Tolerance: 8 % of hang-distance above the bar counts as "at top".
      case PullUpPhase.ascending:
        final hd = _hangDistance ?? 1.0;

        // Chin over bar: nose Y ≤ wrist Y + small tolerance.
        if (noseY <= wristY + hd * 0.08) {
          _phase = PullUpPhase.atTop;
          break;
        }

        // Fell back to bottom without reaching top → reset, don't count.
        if (noseY >= _baselineNoseY! - hd * 0.05) {
          _phase = PullUpPhase.hanging;
          _setBaseline(noseY, wristY);
        }

      // ────────────────────────────────────────────────────────────────────
      // AT_TOP → wait for the descent to begin.
      // Hysteresis: need to drop 12 % of hang-distance below bar level
      // before switching to DESCENDING (prevents jitter at the top).
      case PullUpPhase.atTop:
        final hd = _hangDistance ?? 1.0;
        if (noseY > wristY + hd * 0.12) {
          _phase = PullUpPhase.descending;
        }

      // ────────────────────────────────────────────────────────────────────
      // DESCENDING → count the rep once the body returns to hang baseline
      // (within 10 % of hang-distance).  Also require arms to be
      // reasonably extended (elbow angle > 140°) when available.
      case PullUpPhase.descending:
        final hd = _hangDistance ?? 1.0;
        final armsExtended = elbowAngle == null || elbowAngle > 140.0;

        if (noseY >= _baselineNoseY! - hd * 0.10 && armsExtended) {
          final now = DateTime.now();
          final elapsed = _lastCountTime == null
              ? _kMinRepMs + 1
              : now.difference(_lastCountTime!).inMilliseconds;

          if (elapsed >= _kMinRepMs) {
            _count++;
            _lastCountTime = now;
            _countController.add(_count);
          }

          _phase = PullUpPhase.hanging;
          _setBaseline(noseY, wristY);
        }
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Capture the hanging baseline and derive [_hangDistance].
  void _setBaseline(double noseY, double wristY) {
    _baselineNoseY = noseY;
    // hangDistance > 0 means nose is below the wrists (correct for hanging).
    _hangDistance = max(noseY - wristY, 1.0);
  }

  /// Rolling average over the last [_kBufSize] values.
  double _smooth(List<double> buf, double value) {
    buf.add(value);
    if (buf.length > _kBufSize) buf.removeAt(0);
    return buf.reduce((a, b) => a + b) / buf.length;
  }

  /// Returns the average elbow angle in degrees, or null if landmarks are
  /// unavailable / low-confidence.
  double? _avgElbowAngle(
    PoseLandmark? lShoulder, PoseLandmark? lElbow, PoseLandmark? lWrist,
    PoseLandmark? rShoulder, PoseLandmark? rElbow, PoseLandmark? rWrist,
  ) {
    double? left;
    double? right;

    if (lShoulder != null && lElbow != null && lWrist != null &&
        lElbow.likelihood > 0.5) {
      left = _angleDeg(lShoulder, lElbow, lWrist);
    }
    if (rShoulder != null && rElbow != null && rWrist != null &&
        rElbow.likelihood > 0.5) {
      right = _angleDeg(rShoulder, rElbow, rWrist);
    }

    if (left != null && right != null) return (left + right) / 2.0;
    return left ?? right;
  }

  /// Angle (in degrees) at vertex B formed by points A–B–C.
  double _angleDeg(PoseLandmark a, PoseLandmark b, PoseLandmark c) {
    final abX = a.x - b.x, abY = a.y - b.y;
    final cbX = c.x - b.x, cbY = c.y - b.y;
    final dot = abX * cbX + abY * cbY;
    final magAB = sqrt(abX * abX + abY * abY);
    final magCB = sqrt(cbX * cbX + cbY * cbY);
    if (magAB == 0 || magCB == 0) return 0;
    final cosAngle = (dot / (magAB * magCB)).clamp(-1.0, 1.0);
    return acos(cosAngle) * 180.0 / pi;
  }

  // ── Input image builder ────────────────────────────────────────────────────

  InputImage? _buildInputImage(CameraImage image, InputImageRotation rotation) {
    if (image.planes.length < 3) return null;

    final int w = image.width;
    final int h = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    // NV21 exact size = w*h (Y) + w*h/2 (interleaved VU).
    // Simple plane concatenation includes row-stride padding and makes the
    // buffer larger than NV21 expects → "ByteBuffer size and format don't match".
    // We must copy row-by-row for Y, then interleave V,U pixel-by-pixel.
    final nv21 = Uint8List((w * h * 1.5).toInt());

    // Y plane – copy each row, stripping the row-stride padding.
    int dst = 0;
    for (int row = 0; row < h; row++) {
      nv21.setRange(dst, dst + w, yPlane.bytes, row * yPlane.bytesPerRow);
      dst += w;
    }

    // VU interleaved (NV21: V byte first, then U byte per 2×2 block).
    final int vPixStride = vPlane.bytesPerPixel ?? 1;
    final int uPixStride = uPlane.bytesPerPixel ?? 1;
    for (int row = 0; row < h ~/ 2; row++) {
      for (int col = 0; col < w ~/ 2; col++) {
        nv21[dst++] = vPlane.bytes[row * vPlane.bytesPerRow + col * vPixStride];
        nv21[dst++] = uPlane.bytes[row * uPlane.bytesPerRow + col * uPixStride];
      }
    }

    return InputImage.fromBytes(
      bytes: nv21,
      metadata: InputImageMetadata(
        size: Size(w.toDouble(), h.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: w, // no padding in our hand-built NV21
      ),
    );
  }
}
