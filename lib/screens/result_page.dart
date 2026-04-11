import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../services/pose_compare.dart';
import '../widgets/pose_painter.dart';

/// Shows the snapshot captured from the camera together with the pose
/// comparison score and a per-joint breakdown.
///
/// When navigated to directly from the home menu (no parameters),
/// it displays a placeholder prompt instead.
class ResultPage extends StatelessWidget {
  const ResultPage({
    super.key,
    this.snapshotPath,
    this.compareResult,
    this.livePose,
  });

  final String? snapshotPath;
  final CompareResult? compareResult;
  final Pose? livePose;

  bool get _hasData => snapshotPath != null && compareResult != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Result')),
      body: _hasData ? _ResultView(this) : const _PlaceholderView(),
    );
  }
}

// ── result view (navigated from camera) ──────────────────────────────────────

class _ResultView extends StatefulWidget {
  const _ResultView(this.page);
  final ResultPage page;

  @override
  State<_ResultView> createState() => _ResultViewState();
}

class _ResultViewState extends State<_ResultView> {
  Size? _imageSize;

  @override
  void initState() {
    super.initState();
    _loadImageSize();
  }

  Future<void> _loadImageSize() async {
    final bytes = await File(widget.page.snapshotPath!).readAsBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final size =
        Size(descriptor.width.toDouble(), descriptor.height.toDouble());
    descriptor.dispose();
    buffer.dispose();
    if (mounted) setState(() => _imageSize = size);
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.page.compareResult!;
    final pose = widget.page.livePose;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── snapshot with optional skeleton overlay ─────────────────────
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(
                    File(widget.page.snapshotPath!),
                    fit: BoxFit.cover,
                  ),
                  if (pose != null && _imageSize != null)
                    CustomPaint(
                      painter: PosePainter(
                        pose: pose,
                        imageSize: _imageSize!,
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── overall score card ──────────────────────────────────────────
          _ScoreCard(result: result),

          const SizedBox(height: 20),

          // ── joint breakdown ─────────────────────────────────────────────
          if (result.joints.isNotEmpty) ...[
            Text(
              'Joint Breakdown',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...result.joints.map((j) => _JointRow(joint: j)),
          ],

          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

// ── score card ────────────────────────────────────────────────────────────────

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.result});
  final CompareResult result;

  Color _scoreColor(BuildContext context) {
    if (result.score >= 80) return const Color(0xFF22C55E);
    if (result.score >= 55) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  String get _label {
    if (result.score >= 80) return 'Excellent match!';
    if (result.score >= 55) return 'Good — keep refining';
    if (result.score >= 35) return 'Fair — needs adjustment';
    return 'Keep practising';
  }

  @override
  Widget build(BuildContext context) {
    final color = _scoreColor(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // circle progress indicator
          SizedBox(
            width: 80,
            height: 80,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: result.score / 100,
                  strokeWidth: 8,
                  backgroundColor: const Color(0xFFE5E7EB),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
                Center(
                  child: Text(
                    '${result.score.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pose Similarity',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF6B7280),
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  _label,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${result.joints.length} joints analysed',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF9CA3AF),
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── joint row ─────────────────────────────────────────────────────────────────

class _JointRow extends StatelessWidget {
  const _JointRow({required this.joint});
  final JointResult joint;

  Color get _color {
    if (joint.isGood) return const Color(0xFF22C55E);
    if (joint.isFair) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: _color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              joint.label,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF374151),
              ),
            ),
          ),
          Text(
            'Ref: ${joint.refAngle.toStringAsFixed(1)}°',
            style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
          ),
          const SizedBox(width: 8),
          Text(
            'You: ${joint.liveAngle.toStringAsFixed(1)}°',
            style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
          ),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '±${joint.diff.toStringAsFixed(0)}°',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── placeholder (opened from home menu with no data) ─────────────────────────

class _PlaceholderView extends StatelessWidget {
  const _PlaceholderView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(
                  Icons.assessment_outlined,
                  size: 40,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'No result yet',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Upload a reference image, then use the Camera page to capture '
                'your pose. Results will appear here after you take a snapshot.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: Color(0xFF6B7280),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
