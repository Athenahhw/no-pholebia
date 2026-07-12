// detection_screen.dart  (MVP 簡化版)
// 負責人: 前端 - YOLO物理特徵/反光偵測 組
//
// 這版拿掉 YOLO(因為自訂類別模型還沒訓練完成,接上會直接 crash)。
// 目標:先讓「相機開啟 → 手電筒控制 → 反光點偵測 → 畫面圈出來」
// 這條最基本的路能動,之後 YOLO 模型訓練好了,把 _yoloDetector 那幾行
// 取消註解接回去就好,其他架構不用大改。
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'camera_service.dart';
import 'detection_result.dart';
import 'glint_detector.dart';
import 'image_converter.dart';

class DetectionScreen extends StatefulWidget {
  const DetectionScreen({super.key});

  @override
  State<DetectionScreen> createState() => _DetectionScreenState();
}

class _DetectionScreenState extends State<DetectionScreen> {
  final CameraService _cameraService = CameraService();
  final GlintDetector _glintDetector = GlintDetector();
  final GlintTracker _glintTracker = GlintTracker();

  List<GlintCandidate> _glints = [];
  Size _lastImageSize = Size.zero;

  bool _isProcessing = false;
  bool _isReady = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    try {
      await _cameraService.initialize();
      await _cameraService.startImageStream(_onFrame);
      setState(() => _isReady = true);
    } catch (e) {
      setState(() => _errorMessage = '初始化失敗: $e');
    }
  }

  void _onFrame(CameraImage cameraImage) {
    if (_isProcessing) return; // 上一幀還沒處理完,跳過,避免堆積卡頓
    _isProcessing = true;
    _processFrame(cameraImage).whenComplete(() => _isProcessing = false);
  }

  Future<void> _processFrame(CameraImage cameraImage) async {
    final image = convertCameraImage(cameraImage);
    _lastImageSize = Size(image.width.toDouble(), image.height.toDouble());

    final glintCandidates = _glintDetector.detect(image);
    _glintTracker.addFrame(glintCandidates);
    final trackedGlints = _glintTracker.computeFlickerScores();

    if (mounted) {
      setState(() {
        _glints = trackedGlints.isNotEmpty ? trackedGlints : glintCandidates;
      });
    }

    // ---- YOLO 之後接回這裡 ----
    // final boxes = await _yoloDetector.detect(image);
    // setState(() => _boxes = boxes);
  }

  @override
  void dispose() {
    _cameraService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    if (!_isReady || _cameraService.controller == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: CameraPreview(_cameraService.controller!),
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: _GlintPainter(
                glints: _glints,
                imageSize: _lastImageSize,
              ),
            ),
          ),
          _buildTopBar(),
          _buildBottomStatusBar(),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            IconButton(
              icon: Icon(
                _cameraService.isTorchOn ? Icons.flash_on : Icons.flash_off,
                color: Colors.white,
              ),
              onPressed: () async {
                await _cameraService.toggleTorch();
                setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomStatusBar() {
    final suspiciousGlints = _glints.where((g) => (g.flickerScore ?? 0) > 8.0).length;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '偵測到 ${_glints.length} 個反光點・$suspiciousGlints 個可疑閃爍',
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ),
      ),
    );
  }
}

/// 簡化版繪圖器,只畫反光點(拿掉 bounding_box_painter.dart 裡 YOLO 那半部)
class _GlintPainter extends CustomPainter {
  final List<GlintCandidate> glints;
  final Size imageSize;

  _GlintPainter({required this.glints, required this.imageSize});

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize.width == 0 || imageSize.height == 0) return;

    final scaleX = size.width / imageSize.width;
    final scaleY = size.height / imageSize.height;

    for (final glint in glints) {
      final isFlickering = (glint.flickerScore ?? 0) > 8.0;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = isFlickering ? Colors.redAccent : Colors.cyanAccent.withValues(alpha: 0.7);

      canvas.drawCircle(
        Offset(glint.x * scaleX, glint.y * scaleY),
        (glint.radius * scaleX).clamp(8, 40),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GlintPainter oldDelegate) => true;
}