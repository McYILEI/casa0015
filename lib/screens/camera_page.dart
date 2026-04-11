import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../services/pose_compare.dart';
import '../services/pose_detector_service.dart';
import '../services/pose_store.dart';
import '../widgets/pose_painter.dart';
import 'result_page.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage>
    with WidgetsBindingObserver {
  List<CameraDescription>? _cameras;
  CameraController? _controller;
  int _cameraIndex = 0;

  bool _initializing = true;
  String? _error;

  List<Pose> _poses = [];
  CompareResult? _compareResult;
  int _frameCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      ctrl.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  // ── initialisation ────────────────────────────────────────────────────────

  Future<void> _initCamera() async {
    setState(() {
      _initializing = true;
      _error = null;
    });

    try {
      _cameras = await availableCameras();
    } on CameraException catch (e) {
      _setError('Could not list cameras: ${e.description}');
      return;
    }

    if (_cameras == null || _cameras!.isEmpty) {
      _setError('No camera found on this device.');
      return;
    }

    // Prefer the back camera.
    final backIdx = _cameras!.indexWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
    );
    _cameraIndex = backIdx >= 0 ? backIdx : 0;

    await _startController();
  }

  Future<void> _startController() async {
    final camera = _cameras![_cameraIndex];
    final ctrl = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup:
          Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );
    _controller = ctrl;

    try {
      await ctrl.initialize();
    } on CameraException catch (e) {
      if (e.code == 'CameraAccessDenied') {
        _setError(
          'Camera permission denied.\n'
          'Please grant access in your device settings.',
        );
      } else {
        _setError('Camera error: ${e.description}');
      }
      return;
    }

    if (!mounted) return;

    await ctrl.startImageStream(_onFrame);
    setState(() => _initializing = false);
  }

  // ── frame processing ──────────────────────────────────────────────────────

  void _onFrame(CameraImage image) async {
    // Process every 3rd frame to reduce CPU usage.
    _frameCount++;
    if (_frameCount % 3 != 0) return;

    final camera = _cameras![_cameraIndex];
    final poses = await PoseDetectorService.instance.detectFromCameraImage(
      image: image,
      sensorOrientation: camera.sensorOrientation,
      lensDirection: camera.lensDirection,
      deviceOrientation: _controller!.value.deviceOrientation,
    );
    if (poses == null || !mounted) return;

    CompareResult? result;
    if (poses.isNotEmpty && PoseStore.instance.hasReference) {
      result = PoseCompare.compare(
        PoseStore.instance.referencePose!,
        poses.first,
      );
    }

    setState(() {
      _poses = poses;
      _compareResult = result;
    });
  }

  // ── actions ───────────────────────────────────────────────────────────────

  Future<void> _switchCamera() async {
    if (_cameras == null || _cameras!.length < 2) return;
    await _controller?.stopImageStream();
    await _controller?.dispose();
    _controller = null;
    _cameraIndex = (_cameraIndex + 1) % _cameras!.length;
    setState(() => _initializing = true);
    await _startController();
  }

  Future<void> _captureAndCompare() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;

    try {
      await ctrl.stopImageStream();
      final xfile = await ctrl.takePicture();

      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => ResultPage(
            snapshotPath: xfile.path,
            compareResult: _compareResult,
            livePose: _poses.isNotEmpty ? _poses.first : null,
          ),
        ),
      );

      // Resume stream after returning.
      if (mounted) await ctrl.startImageStream(_onFrame);
    } on CameraException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Snapshot failed: ${e.description}')),
        );
        await _controller?.startImageStream(_onFrame);
      }
    }
  }

  void _setError(String msg) {
    if (mounted) setState(() { _error = msg; _initializing = false; });
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Camera'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        actions: [
          if ((_cameras?.length ?? 0) > 1)
            IconButton(
              icon: const Icon(Icons.cameraswitch_outlined),
              tooltip: 'Switch camera',
              onPressed: _switchCamera,
            ),
        ],
      ),
      body: _buildBody(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: (!_initializing && _error == null)
          ? FloatingActionButton.large(
              onPressed: _captureAndCompare,
              tooltip: 'Capture & compare',
              child: const Icon(Icons.camera),
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (_initializing) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Initialising camera…',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _error!,
            style: const TextStyle(color: Colors.redAccent, fontSize: 15),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final ctrl = _controller!;
    final camera = _cameras![_cameraIndex];
    final isFront = camera.lensDirection == CameraLensDirection.front;

    // The preview size reported by the controller is in landscape sensor space;
    // swap width/height to get portrait logical size.
    final previewSize = ctrl.value.previewSize;
    final imageSize = previewSize != null
        ? Size(previewSize.height, previewSize.width)
        : const Size(480, 640);

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── live camera preview ──────────────────────────────────────────
        CameraPreview(ctrl),

        // ── reference ghost skeleton ─────────────────────────────────────
        if (PoseStore.instance.hasReference)
          CustomPaint(
            painter: PosePainter(
              pose: PoseStore.instance.referencePose!,
              imageSize: PoseStore.instance.referenceImageSize!,
              isMirrored: false,
              boneColor: Colors.white.withValues(alpha: 0.35),
              dotColor: Colors.lightBlueAccent.withValues(alpha: 0.5),
            ),
          ),

        // ── live pose skeleton overlay ───────────────────────────────────
        if (_poses.isNotEmpty)
          CustomPaint(
            painter: PosePainter(
              pose: _poses.first,
              imageSize: imageSize,
              isMirrored: isFront,
            ),
          ),

        // ── comparison score badge ───────────────────────────────────────
        if (_compareResult != null)
          Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: Center(child: _ScoreBadge(result: _compareResult!)),
          ),

        // ── "upload reference first" hint ────────────────────────────────
        if (!PoseStore.instance.hasReference)
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: _InfoBanner(
              icon: Icons.info_outline,
              text:
                  'Upload a reference image first to enable pose comparison.',
            ),
          ),

        // ── detection status chip ────────────────────────────────────────
        Positioned(
          bottom: 110,
          left: 0,
          right: 0,
          child: Center(
            child: _StatusChip(detected: _poses.isNotEmpty),
          ),
        ),
      ],
    );
  }
}

// ── helper widgets ────────────────────────────────────────────────────────────

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({required this.result});
  final CompareResult result;

  Color get _color {
    if (result.score >= 80) return Colors.greenAccent;
    if (result.score >= 55) return Colors.yellowAccent;
    return Colors.redAccent;
  }

  String get _label {
    if (result.score >= 80) return 'Excellent';
    if (result.score >= 55) return 'Good';
    if (result.score >= 35) return 'Fair';
    return 'Keep going';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: _color, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${result.score.toStringAsFixed(0)}%',
            style: TextStyle(
              color: _color,
              fontSize: 30,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 10),
          Text(_label, style: TextStyle(color: _color, fontSize: 16)),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.detected});
  final bool detected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            detected ? Icons.accessibility_new : Icons.person_search,
            size: 16,
            color: detected ? Colors.greenAccent : Colors.white38,
          ),
          const SizedBox(width: 6),
          Text(
            detected ? 'Person detected' : 'No person detected',
            style: TextStyle(
              color: detected ? Colors.greenAccent : Colors.white38,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
