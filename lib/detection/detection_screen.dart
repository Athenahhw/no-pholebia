import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  // ---- 高風險提醒的閾值與冷卻控制 ----
  static const double _flickerAlertThreshold = 8.0;
  static const Duration _alertCooldown = Duration(seconds: 2);
  DateTime? _lastAlertTime;
  bool _justAlerted = false; // 給 UI 做短暫的視覺強調用

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

    final currentGlints = trackedGlints.isNotEmpty ? trackedGlints : glintCandidates;

    _maybeTriggerAlert(currentGlints);

    if (mounted) {
      setState(() => _glints = currentGlints);
    }
  }

  /// 有高風險反光點,且已經過了冷卻時間,才觸發震動+音效
  void _maybeTriggerAlert(List<GlintCandidate> glints) {
    final hasHighRisk = glints.any((g) => (g.flickerScore ?? 0) > _flickerAlertThreshold);
    if (!hasHighRisk) return;

    final now = DateTime.now();
    if (_lastAlertTime != null && now.difference(_lastAlertTime!) < _alertCooldown) {
      return; // 還在冷卻時間內,不重複提醒
    }
    _lastAlertTime = now;

    HapticFeedback.heavyImpact(); // 震動(iOS/Android都支援,不需要額外套件)
    SystemSound.play(SystemSoundType.alert); // 系統提示音

    if (mounted) {
      setState(() => _justAlerted = true);
      // 短暫顯示視覺強調後恢復
      Timer(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _justAlerted = false);
      });
    }
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
          // 觸發警報瞬間,螢幕邊緣閃一下紅色外框,加強視覺提示
          if (_justAlerted)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.redAccent, width: 8),
                  ),
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
    final suspiciousGlints =
        _glints.where((g) => (g.flickerScore ?? 0) > _flickerAlertThreshold).length;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: suspiciousGlints > 0 ? Colors.red.withValues(alpha: 0.55) : Colors.black54,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            suspiciousGlints > 0
                ? '⚠️ 偵測到 $suspiciousGlints 個可疑反光點,建議仔細檢查'
                : '偵測到 ${_glints.length} 個反光點・目前無明顯異常',
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ),
      ),
    );
  }
}

/// 簡化版繪圖器,只畫反光點
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