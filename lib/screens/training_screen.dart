import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../models/session.dart';
import '../services/database_service.dart';
import '../services/pose_detector_service.dart';
import '../theme/app_theme.dart';
import '../widgets/camera_overlay.dart';
import '../widgets/count_display.dart';

class TrainingScreen extends StatefulWidget {
  const TrainingScreen({super.key});

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  CameraController? _cameraController;
  final PoseDetectorService _poseService = PoseDetectorService();

  bool _cameraReady = false;
  bool _cameraPermissionDenied = false;
  bool _paused = false;

  // Timer
  int _elapsedSeconds = 0;
  Timer? _timer;

  // Counting
  int _currentSetCount = 0;
  final List<int> _sets = [];

  final DateTime _startTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _initCamera();
    _startTimer();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      // Prefer front camera
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();

      // Start image stream for pose detection
      await _cameraController!.startImageStream((image) {
        if (!_paused) {
          _poseService.processImage(
            image,
            _rotationForCamera(front.sensorOrientation),
          );
        }
      });

      // Listen to count updates from pose service
      _poseService.countStream.listen((count) {
        if (mounted && !_paused) {
          HapticFeedback.mediumImpact();
          setState(() => _currentSetCount = count);
        }
      });

      if (mounted) setState(() => _cameraReady = true);
    } on CameraException catch (e) {
      if (e.code == 'CameraAccessDenied') {
        setState(() => _cameraPermissionDenied = true);
      }
    }
  }

  InputImageRotation _rotationForCamera(int sensorOrientation) {
    switch (sensorOrientation) {
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        return InputImageRotation.rotation0deg;
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_paused && mounted) {
        setState(() => _elapsedSeconds++);
      }
    });
  }

  String get _elapsedFormatted {
    final m = _elapsedSeconds ~/ 60;
    final s = _elapsedSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _increment() {
    HapticFeedback.mediumImpact();
    _poseService.incrementManual();
    setState(() => _currentSetCount = _poseService.count);
  }

  void _decrement() {
    _poseService.decrementManual();
    setState(() => _currentSetCount = _poseService.count);
  }

  void _nextSet() {
    if (_currentSetCount == 0) return;
    setState(() {
      _sets.add(_currentSetCount);
      _currentSetCount = 0;
    });
    _poseService.resetCount();
    HapticFeedback.lightImpact();
  }

  void _togglePause() {
    setState(() => _paused = !_paused);
  }

  int get _totalReps =>
      _sets.fold(0, (sum, s) => sum + s) + _currentSetCount;

  String get _setsDisplay {
    final all = [..._sets, if (_currentSetCount > 0) _currentSetCount];
    return all.join('+');
  }

  Future<void> _endTraining() async {
    final allSets = [..._sets, if (_currentSetCount > 0) _currentSetCount];
    if (allSets.isEmpty) {
      Navigator.pop(context);
      return;
    }

    final total = allSets.fold(0, (sum, s) => sum + s);
    final best = allSets.reduce((a, b) => a > b ? a : b);

    final session = Session(
      date: _startTime,
      totalReps: total,
      duration: _elapsedSeconds,
      bestSet: best,
      sets: allSets,
    );

    await DatabaseService.instance.insertSession(session);
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<bool> _onWillPop() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Exit Training', style: TextStyle(color: AppColors.text)),
        content: const Text('Are you sure? Current training data will be lost.',
            style: TextStyle(color: AppColors.textDim)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep Going', style: TextStyle(color: AppColors.accent)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child:
                const Text('Exit', style: TextStyle(color: AppColors.warning)),
          ),
        ],
      ),
    );
    return confirm ?? false;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _poseService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) {
          final should = await _onWillPop();
          if (!should || !mounted) return;
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              _buildCameraSection(),
              _buildCountSection(),
              _buildControlButtons(),
              _buildBottomButtons(),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraSection() {
    return Expanded(
      flex: 7,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildCameraPreview(),
          CameraOverlay(
            elapsed: _elapsedFormatted,
            setNumber: _sets.length + 1,
            paused: _paused,
          ),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (_cameraPermissionDenied) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off, color: AppColors.textDim, size: 48),
            SizedBox(height: 12),
            Text('Camera permission denied.\nPlease enable it in Settings.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textDim)),
          ],
        ),
      );
    }

    if (!_cameraReady || _cameraController == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }

    // previewSize is reported in landscape (e.g. 1280×960).
    // Swap width/height to get the correct portrait dimensions,
    // then use FittedBox(cover) so the preview fills the area
    // without any stretching or distortion.
    final previewSize = _cameraController!.value.previewSize!;
    final portraitW = previewSize.height;
    final portraitH = previewSize.width;

    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: portraitW,
            height: portraitH,
            child: Transform.scale(
              scaleX: -1.0, // Mirror horizontally for front camera
              child: CameraPreview(_cameraController!),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCountSection() {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Current Set',
              style: TextStyle(color: AppColors.textDim, fontSize: 11)),
          CountDisplay(count: _currentSetCount),
          Text(
            'Total: $_totalReps reps${_setsDisplay.isNotEmpty ? ' ($_setsDisplay)' : ''}',
            style: const TextStyle(color: AppColors.textDim, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Decrement
          _iconBtn(Icons.remove, _decrement, size: 44),
          // Big +1 button
          GestureDetector(
            onTap: _increment,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accent,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accent.withAlpha(80),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Center(
                child: Text(
                  '+1',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.background,
                  ),
                ),
              ),
            ),
          ),
          // Next set
          TextButton(
            onPressed: _nextSet,
            style: TextButton.styleFrom(
              backgroundColor: AppColors.surfaceAlt,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppColors.border),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: const Text('Next Set',
                style: TextStyle(color: AppColors.text, fontSize: 14)),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _togglePause,
              icon: Icon(_paused ? Icons.play_arrow : Icons.pause, size: 18),
              label: Text(_paused ? 'Resume' : 'Pause'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.text,
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _endTraining,
              icon: const Icon(Icons.stop_circle_outlined, size: 18),
              label: const Text('End Training'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap, {double size = 48}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icon, color: AppColors.text, size: 22),
      ),
    );
  }
}
