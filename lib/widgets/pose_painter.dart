import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Draws a skeleton overlay on top of a camera preview or a static image.
///
/// [imageSize] is the **original pixel dimensions** of the source image/frame.
/// [widgetSize] is resolved at paint time via [CustomPainter.size].
/// [isMirrored] should be true for the front-facing camera so the overlay
/// matches the mirrored preview.
class PosePainter extends CustomPainter {
  const PosePainter({
    required this.pose,
    required this.imageSize,
    this.isMirrored = false,
    this.boneColor = Colors.greenAccent,
    this.dotColor = Colors.yellowAccent,
  });

  final Pose pose;
  final Size imageSize;
  final bool isMirrored;
  final Color boneColor;
  final Color dotColor;

  // ── skeleton connections ──────────────────────────────────────────────────
  static const _bones = [
    // Face
    [PoseLandmarkType.leftEar, PoseLandmarkType.leftEye],
    [PoseLandmarkType.leftEye, PoseLandmarkType.nose],
    [PoseLandmarkType.nose, PoseLandmarkType.rightEye],
    [PoseLandmarkType.rightEye, PoseLandmarkType.rightEar],
    // Left arm
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow],
    [PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist],
    // Right arm
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
    [PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist],
    // Torso
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder],
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip],
    [PoseLandmarkType.leftHip, PoseLandmarkType.rightHip],
    // Left leg
    [PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee],
    [PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle],
    [PoseLandmarkType.leftAnkle, PoseLandmarkType.leftHeel],
    [PoseLandmarkType.leftHeel, PoseLandmarkType.leftFootIndex],
    // Right leg
    [PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee],
    [PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle],
    [PoseLandmarkType.rightAnkle, PoseLandmarkType.rightHeel],
    [PoseLandmarkType.rightHeel, PoseLandmarkType.rightFootIndex],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final bonePaint = Paint()
      ..color = boneColor
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final dotFill = Paint()..color = dotColor;
    final dotBorder = Paint()
      ..color = Colors.deepOrange
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    Offset toOffset(PoseLandmark lm) {
      double x = lm.x / imageSize.width * size.width;
      final double y = lm.y / imageSize.height * size.height;
      if (isMirrored) x = size.width - x;
      return Offset(x, y);
    }

    // Draw bones.
    for (final bone in _bones) {
      final a = pose.landmarks[bone[0]];
      final b = pose.landmarks[bone[1]];
      if (a != null && b != null) {
        canvas.drawLine(toOffset(a), toOffset(b), bonePaint);
      }
    }

    // Draw joint dots.
    for (final lm in pose.landmarks.values) {
      final pt = toOffset(lm);
      canvas.drawCircle(pt, 6, dotFill);
      canvas.drawCircle(pt, 6, dotBorder);
    }
  }

  @override
  bool shouldRepaint(PosePainter old) =>
      old.pose != pose ||
      old.imageSize != imageSize ||
      old.isMirrored != isMirrored;
}
