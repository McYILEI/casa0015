import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:image_picker/image_picker.dart';

import '../services/pose_detector_service.dart';
import '../services/pose_store.dart';

class UploadPage extends StatefulWidget {
  const UploadPage({super.key});

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  final _picker = ImagePicker();

  File? _image;
  Size? _imageSize;
  Pose? _pose;

  bool _detecting = false;
  String? _detectionMsg;

  // ── pick + detect ─────────────────────────────────────────────────────────

  Future<void> _pickImage() async {
    final xfile = await _picker.pickImage(source: ImageSource.gallery);
    if (xfile == null) return;

    final file = File(xfile.path);

    setState(() {
      _image = file;
      _imageSize = null;
      _pose = null;
      _detectionMsg = null;
      _detecting = true;
    });

    // Decode image dimensions for the overlay painter (without full decode).
    final bytes = await file.readAsBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final size =
        Size(descriptor.width.toDouble(), descriptor.height.toDouble());
    descriptor.dispose();
    buffer.dispose();

    // Run on-device pose detection.
    final poses = await PoseDetectorService.instance.detectFromFile(file);

    if (!mounted) return;

    if (poses.isEmpty) {
      setState(() {
        _imageSize = size;
        _detecting = false;
        _detectionMsg = 'No person detected in this image. '
            'Try a photo where the full body is clearly visible.';
      });
      PoseStore.instance.clear();
      return;
    }

    final pose = poses.first;
    PoseStore.instance.setReference(pose, size, file);

    setState(() {
      _imageSize = size;
      _pose = pose;
      _detecting = false;
      _detectionMsg =
          '${pose.landmarks.length} keypoints detected — reference saved!';
    });
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upload Reference Image')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Select a full-body photo as the reference pose.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.5,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── preview box ────────────────────────────────────────
                  Container(
                    width: double.infinity,
                    height: 380,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border:
                          Border.all(color: const Color(0xFFD1D5DB)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: _buildPreview(),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── detection result message ───────────────────────────
                  if (_detecting)
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 10),
                        Text('Detecting pose…'),
                      ],
                    )
                  else if (_detectionMsg != null)
                    _DetectionBanner(
                      message: _detectionMsg!,
                      success: _pose != null,
                    ),

                  const SizedBox(height: 20),

                  // ── pick button ────────────────────────────────────────
                  ElevatedButton.icon(
                    onPressed: _detecting ? null : _pickImage,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: Text(
                      _image == null ? 'Choose Image' : 'Choose Another',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  if (_pose != null)
                    Text(
                      'Reference saved. Open the Camera page to compare.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    )
                  else
                    const Text(
                      'Only local preview — no data is uploaded to any server.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreview() {
    if (_image == null) return const _EmptyPreview();

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(_image!, fit: BoxFit.cover),

        // Skeleton overlay once we have both the pose and image dimensions.
        if (_pose != null && _imageSize != null)
          LayoutBuilder(
            builder: (_, constraints) {
              // Compute the portion of the widget actually covered by the
              // image when using BoxFit.cover.
              final widgetW = constraints.maxWidth;
              final widgetH = constraints.maxHeight;
              final imgAspect = _imageSize!.width / _imageSize!.height;
              final widgetAspect = widgetW / widgetH;

              // With cover, one axis fills exactly and the other is cropped.
              final double renderW, renderH;
              if (imgAspect > widgetAspect) {
                // Image wider than widget → height fills, width overflows.
                renderH = widgetH;
                renderW = widgetH * imgAspect;
              } else {
                renderW = widgetW;
                renderH = widgetW / imgAspect;
              }

              // Offset so the image is centred (matching BoxFit.cover alignment).
              final dx = (widgetW - renderW) / 2;
              final dy = (widgetH - renderH) / 2;

              return CustomPaint(
                painter: _OffsetPosePainter(
                  pose: _pose!,
                  imageSize: _imageSize!,
                  renderSize: Size(renderW, renderH),
                  offset: Offset(dx, dy),
                ),
              );
            },
          ),

        // Spinner while detecting.
        if (_detecting)
          Container(
            color: Colors.black38,
            child: const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
      ],
    );
  }
}

/// A [CustomPainter] that draws a pose skeleton accounting for the rendered
/// area of a BoxFit.cover image (which may not fill the whole widget).
class _OffsetPosePainter extends CustomPainter {
  const _OffsetPosePainter({
    required this.pose,
    required this.imageSize,
    required this.renderSize,
    required this.offset,
  });

  final Pose pose;
  final Size imageSize;
  final Size renderSize;
  final Offset offset;

  static const _bones = [
    [PoseLandmarkType.leftEar, PoseLandmarkType.leftEye],
    [PoseLandmarkType.leftEye, PoseLandmarkType.nose],
    [PoseLandmarkType.nose, PoseLandmarkType.rightEye],
    [PoseLandmarkType.rightEye, PoseLandmarkType.rightEar],
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow],
    [PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
    [PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist],
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder],
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip],
    [PoseLandmarkType.leftHip, PoseLandmarkType.rightHip],
    [PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee],
    [PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle],
    [PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee],
    [PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle],
  ];

  Offset _pt(PoseLandmark lm) => Offset(
        offset.dx + lm.x / imageSize.width * renderSize.width,
        offset.dy + lm.y / imageSize.height * renderSize.height,
      );

  @override
  void paint(Canvas canvas, Size size) {
    final bonePaint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final dotFill = Paint()..color = Colors.yellowAccent;
    final dotBorder = Paint()
      ..color = Colors.deepOrange
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (final bone in _bones) {
      final a = pose.landmarks[bone[0]];
      final b = pose.landmarks[bone[1]];
      if (a != null && b != null) canvas.drawLine(_pt(a), _pt(b), bonePaint);
    }
    for (final lm in pose.landmarks.values) {
      canvas.drawCircle(_pt(lm), 5, dotFill);
      canvas.drawCircle(_pt(lm), 5, dotBorder);
    }
  }

  @override
  bool shouldRepaint(_OffsetPosePainter old) =>
      old.pose != pose || old.renderSize != renderSize;
}

class _DetectionBanner extends StatelessWidget {
  const _DetectionBanner({required this.message, required this.success});
  final String message;
  final bool success;

  @override
  Widget build(BuildContext context) {
    final color =
        success ? const Color(0xFF22C55E) : const Color(0xFFF59E0B);
    final bg = success
        ? const Color(0xFFF0FDF4)
        : const Color(0xFFFFFBEB);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(
            success ? Icons.check_circle_outline : Icons.warning_amber,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyPreview extends StatelessWidget {
  const _EmptyPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF9FAFB),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_outlined, size: 72, color: Color(0xFF9CA3AF)),
          SizedBox(height: 16),
          Text(
            'No image selected',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF374151),
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Tap the button below to pick a full-body photo.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }
}
