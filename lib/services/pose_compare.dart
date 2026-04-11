import 'dart:math' as math;

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// The result of comparing a live pose against a reference pose.
class CompareResult {
  const CompareResult({required this.score, required this.joints});

  /// Overall similarity score 0–100 (higher = better match).
  final double score;

  /// Per-joint angle differences in degrees.
  final List<JointResult> joints;
}

class JointResult {
  const JointResult({
    required this.label,
    required this.refAngle,
    required this.liveAngle,
  });

  final String label;
  final double refAngle;
  final double liveAngle;

  double get diff => (refAngle - liveAngle).abs();

  /// Green / yellow / red threshold.
  bool get isGood => diff <= 20;
  bool get isFair => diff <= 40;
}

/// Compares two [Pose] objects using joint-angle differences.
/// Uses 6 key angles (both elbows, both knees, both hip-torso-angles).
class PoseCompare {
  PoseCompare._();

  static const _joints = [
    _JointSpec(
      label: 'Left Elbow',
      a: PoseLandmarkType.leftShoulder,
      b: PoseLandmarkType.leftElbow,
      c: PoseLandmarkType.leftWrist,
    ),
    _JointSpec(
      label: 'Right Elbow',
      a: PoseLandmarkType.rightShoulder,
      b: PoseLandmarkType.rightElbow,
      c: PoseLandmarkType.rightWrist,
    ),
    _JointSpec(
      label: 'Left Knee',
      a: PoseLandmarkType.leftHip,
      b: PoseLandmarkType.leftKnee,
      c: PoseLandmarkType.leftAnkle,
    ),
    _JointSpec(
      label: 'Right Knee',
      a: PoseLandmarkType.rightHip,
      b: PoseLandmarkType.rightKnee,
      c: PoseLandmarkType.rightAnkle,
    ),
    _JointSpec(
      label: 'Left Hip',
      a: PoseLandmarkType.leftShoulder,
      b: PoseLandmarkType.leftHip,
      c: PoseLandmarkType.leftKnee,
    ),
    _JointSpec(
      label: 'Right Hip',
      a: PoseLandmarkType.rightShoulder,
      b: PoseLandmarkType.rightHip,
      c: PoseLandmarkType.rightKnee,
    ),
  ];

  static CompareResult compare(Pose reference, Pose live) {
    final results = <JointResult>[];

    for (final spec in _joints) {
      final refA = reference.landmarks[spec.a];
      final refB = reference.landmarks[spec.b];
      final refC = reference.landmarks[spec.c];
      final liveA = live.landmarks[spec.a];
      final liveB = live.landmarks[spec.b];
      final liveC = live.landmarks[spec.c];

      if (refA == null ||
          refB == null ||
          refC == null ||
          liveA == null ||
          liveB == null ||
          liveC == null) {
        continue;
      }

      results.add(JointResult(
        label: spec.label,
        refAngle: _angleDeg(refA, refB, refC),
        liveAngle: _angleDeg(liveA, liveB, liveC),
      ));
    }

    if (results.isEmpty) {
      return const CompareResult(score: 0, joints: []);
    }

    final avgDiff =
        results.map((r) => r.diff).reduce((a, b) => a + b) / results.length;

    // 0° diff → 100, 90° diff → 0; clamp to [0, 100].
    final score = (100 - avgDiff / 90 * 100).clamp(0.0, 100.0);

    return CompareResult(score: score, joints: results);
  }

  /// Angle at landmark [b] formed by the vectors b→a and b→c, in degrees.
  static double _angleDeg(
      PoseLandmark a, PoseLandmark b, PoseLandmark c) {
    final bax = a.x - b.x;
    final bay = a.y - b.y;
    final bcx = c.x - b.x;
    final bcy = c.y - b.y;

    final dot = bax * bcx + bay * bcy;
    final magBA = math.sqrt(bax * bax + bay * bay);
    final magBC = math.sqrt(bcx * bcx + bcy * bcy);

    if (magBA == 0 || magBC == 0) return 0;

    final cosTheta = (dot / (magBA * magBC)).clamp(-1.0, 1.0);
    return math.acos(cosTheta) * 180 / math.pi;
  }
}

class _JointSpec {
  const _JointSpec({
    required this.label,
    required this.a,
    required this.b,
    required this.c,
  });

  final String label;
  final PoseLandmarkType a;
  final PoseLandmarkType b;
  final PoseLandmarkType c;
}
