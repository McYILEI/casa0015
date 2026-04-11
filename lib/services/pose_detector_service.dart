import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Wraps ML Kit pose detection for both static images and live camera frames.
class PoseDetectorService {
  PoseDetectorService._();
  static final PoseDetectorService instance = PoseDetectorService._();

  // Single-image detector for uploaded reference photos.
  final _staticDetector = PoseDetector(
    options: PoseDetectorOptions(mode: PoseDetectionMode.single),
  );

  // Stream detector (keeps model warm between frames) for live camera.
  final _streamDetector = PoseDetector(
    options: PoseDetectorOptions(mode: PoseDetectionMode.stream),
  );

  bool _isBusy = false;

  /// Detect pose in a static [File] (e.g. gallery image).
  Future<List<Pose>> detectFromFile(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    return _staticDetector.processImage(inputImage);
  }

  /// Detect pose in a [CameraImage] frame from the live camera stream.
  /// Returns null when the previous frame is still being processed.
  Future<List<Pose>?> detectFromCameraImage({
    required CameraImage image,
    required int sensorOrientation,
    required CameraLensDirection lensDirection,
    required DeviceOrientation deviceOrientation,
  }) async {
    if (_isBusy) return null;
    _isBusy = true;
    try {
      final inputImage = _buildInputImage(
        image: image,
        sensorOrientation: sensorOrientation,
        lensDirection: lensDirection,
        deviceOrientation: deviceOrientation,
      );
      if (inputImage == null) return null;
      return await _streamDetector.processImage(inputImage);
    } finally {
      _isBusy = false;
    }
  }

  InputImage? _buildInputImage({
    required CameraImage image,
    required int sensorOrientation,
    required CameraLensDirection lensDirection,
    required DeviceOrientation deviceOrientation,
  }) {
    final rotation =
        _rotation(sensorOrientation, lensDirection, deviceOrientation);
    if (rotation == null) return null;

    final imageSize =
        Size(image.width.toDouble(), image.height.toDouble());

    // Android with ImageFormatGroup.nv21 → single plane NV21.
    // iOS  with ImageFormatGroup.bgra8888 → single plane BGRA8888.
    if (image.planes.length == 1) {
      final format = InputImageFormatValue.fromRawValue(image.format.raw);
      if (format == null) return null;
      return InputImage.fromBytes(
        bytes: image.planes[0].bytes,
        metadata: InputImageMetadata(
          size: imageSize,
          rotation: rotation,
          format: format,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );
    }

    // Fallback: YUV_420_888 (3 planes) → manually pack into NV21.
    if (image.planes.length == 3) {
      return InputImage.fromBytes(
        bytes: _yuv420ToNv21(image),
        metadata: InputImageMetadata(
          size: imageSize,
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: image.width,
        ),
      );
    }

    return null;
  }

  /// Interleave YUV_420_888 planes into NV21 byte layout (Y‑plane then VU).
  Uint8List _yuv420ToNv21(CameraImage image) {
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final w = image.width;
    final h = image.height;
    final numPixels = w * h;
    final nv21 = Uint8List(numPixels + numPixels ~/ 2);

    // Copy Y rows (stride may add padding).
    for (int row = 0; row < h; row++) {
      nv21.setRange(
        row * w,
        row * w + w,
        yPlane.bytes,
        row * yPlane.bytesPerRow,
      );
    }

    // Interleave V then U (NV21 = Y + VU).
    int uvIdx = numPixels;
    final uvH = h ~/ 2;
    final uvW = w ~/ 2;
    final vStride = vPlane.bytesPerPixel ?? 2;
    final uStride = uPlane.bytesPerPixel ?? 2;
    for (int row = 0; row < uvH; row++) {
      for (int col = 0; col < uvW; col++) {
        final vIdx = row * vPlane.bytesPerRow + col * vStride;
        final uIdx = row * uPlane.bytesPerRow + col * uStride;
        nv21[uvIdx++] = vPlane.bytes[vIdx];
        nv21[uvIdx++] = uPlane.bytes[uIdx];
      }
    }

    return nv21;
  }

  InputImageRotation? _rotation(
    int sensorOrientation,
    CameraLensDirection lensDirection,
    DeviceOrientation deviceOrientation,
  ) {
    final deviceRotations = {
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };

    final deviceRot = deviceRotations[deviceOrientation] ?? 0;

    int compensated;
    if (Platform.isAndroid) {
      if (lensDirection == CameraLensDirection.front) {
        compensated = (sensorOrientation + deviceRot) % 360;
      } else {
        compensated = (sensorOrientation - deviceRot + 360) % 360;
      }
    } else {
      compensated = sensorOrientation;
    }

    return InputImageRotationValue.fromRawValue(compensated);
  }

  void dispose() {
    _staticDetector.close();
    _streamDetector.close();
  }
}
