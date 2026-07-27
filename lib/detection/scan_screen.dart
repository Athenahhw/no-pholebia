import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'camera_service.dart';
import 'detection_backend_client.dart';
import 'detection_result.dart';
import 'glint_detector.dart';
import 'image_converter.dart';

/// 掃描完成後的回呼:summary 是本機偵測到的原始資料,
/// backendResult 是送給後端 AI 分析後拿到的結果(可能是 null,代表連線失敗)。
typedef ScanCompleteCallback = void Function(
  DetectionSessionSummary summary,
  Map<String, dynamic>? backendResult,
);

class ScanScreen extends StatefulWidget {
  /// 掃描持續時間,預設 6 秒。時間到就自動結束、送出資料。
  final Duration scanDuration;

  /// 掃描完成後要做什麼(通常是導頁到結果畫面)。
  /// 不傳的話,預設會導到一個簡單的除錯畫面顯示原始 JSON,方便你自己先測試。
  final ScanCompleteCallback? onScanComplete;

  /// 環境亮度低於這個值就自動開手電筒(0~255,數字越小代表環境越暗)
  final double autoTorchBrightnessThreshold;

  const ScanScreen({
    super.key,
    this.scanDuration = const Duration(seconds: 6),
    this.onScanComplete,
    this.autoTorchBrightnessThreshold = 90,
  });

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with SingleTickerProviderStateMixin {
  final CameraService _cameraService = CameraService();
  final GlintDetector _glintDetector = GlintDetector();
  final GlintTracker _glintTracker = GlintTracker();
  final DetectionBackendClient _backendClient = DetectionBackendClient();

  late final AnimationController _scanLineController;

  bool _isProcessing = false;
  bool _isReady = false;
  bool _isFinishing = false; // 掃描時間到,正在整理資料送後端
  String? _errorMessage;

  double? _ambientBrightnessAtStart;
  bool _hasSampledBrightness = false;
  DateTime? _scanStartedAt;
  Timer? _scanTimer;

  @override
  void initState() {
    super.initState();
    // 掃描線動畫:由上往下單向移動,跑到底後瞬間重置回頂端再跑一次(不會往回跑)
    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _setup();
  }

  Future<void> _setup() async {
    try {
      await _cameraService.initialize();
      await _cameraService.startImageStream(_onFrame);
      setState(() => _isReady = true);

      _scanStartedAt = DateTime.now();
      // 掃描時間到,自動結束
      _scanTimer = Timer(widget.scanDuration, _finishScan);
    } catch (e) {
      setState(() => _errorMessage = '初始化失敗: $e');
    }
  }

  void _onFrame(CameraImage cameraImage) {
    if (_isProcessing || _isFinishing) return;
    _isProcessing = true;
    _processFrame(cameraImage).whenComplete(() => _isProcessing = false);
  }

  Future<void> _processFrame(CameraImage cameraImage) async {
    final image = convertCameraImage(cameraImage);

    // ---- 第一幀:量測環境亮度,決定要不要自動開手電筒 ----
    // 註: 這裡用「拍到的影像平均亮度」當作環境光的替代量測方式,
    // 不是手機的硬體環境光感測器(那個 Flutter 沒有內建 API,要另外裝套件)。
    // 這個門檻值(90)是先抓一個合理的起始值,還沒辦法實機測試校準,
    // 之後拿真手機在不同亮度環境測過,可能需要調整這個數字。
    if (!_hasSampledBrightness) {
      _hasSampledBrightness = true;
      final brightness = GlintDetector.averageBrightness(image);
      _ambientBrightnessAtStart = brightness;
      if (brightness < widget.autoTorchBrightnessThreshold) {
        await _cameraService.setTorch(true);
      }
      if (mounted) setState(() {});
    }

    final glintCandidates = _glintDetector.detect(image);
    _glintTracker.addFrame(glintCandidates);
  }

  Future<void> _finishScan() async {
    if (_isFinishing) return;
    setState(() => _isFinishing = true);

    await _cameraService.stopImageStream();

    // 掃描時間短,幀數可能不多,minFrames 放寬一點,避免全部被濾掉
    final trackedGlints = _glintTracker.computeFlickerScores(minFrames: 3);
    final highRiskCount =
        trackedGlints.where((g) => (g.flickerScore ?? 0) > 8.0).length;

    final summary = DetectionSessionSummary(
      glints: trackedGlints,
      totalGlintCount: trackedGlints.length,
      highRiskGlintCount: highRiskCount,
      ambientBrightnessAtStart: _ambientBrightnessAtStart ?? 0,
      torchUsedDuringScan: _cameraService.isTorchOn,
      scanStartedAt: _scanStartedAt ?? DateTime.now(),
      scanEndedAt: DateTime.now(),
    );

    final backendResult = await _backendClient.submitScan(summary);

    await _cameraService.setTorch(false); // 掃描結束關燈,省電

    if (!mounted) return;

    if (widget.onScanComplete != null) {
      widget.onScanComplete!(summary, backendResult);
    } else {
      // 沒有接上後端畫面時,先導到一個除錯用畫面,顯示原始資料,方便你自己驗證整條流程
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => _DebugResultScreen(summary: summary, backendResult: backendResult),
        ),
      );
    }
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _scanLineController.dispose();
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
            child: Text(_errorMessage!,
                style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
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
          Positioned.fill(child: CameraPreview(_cameraService.controller!)),
          Positioned.fill(child: _buildScanOverlay()),
          _buildBackButton(),
        ],
      ),
    );
  }

  Widget _buildScanOverlay() {
    return Column(
      children: [
        const SizedBox(height: 60),
        const Text(
          '掃描中,請稍後',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            shadows: [Shadow(blurRadius: 4, color: Colors.black)],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    // 四角掃描框
                    _corner(Alignment.topLeft),
                    _corner(Alignment.topRight),
                    _corner(Alignment.bottomLeft),
                    _corner(Alignment.bottomRight),
                    // 已掃過區域(黃線以上)變暗 + 移動的掃描線
                    AnimatedBuilder(
                      animation: _scanLineController,
                      builder: (context, child) {
                        final lineY = _scanLineController.value * constraints.maxHeight;
                        return Stack(
                          children: [
                            // 已掃過的區域蓋上一層半透明黑色遮罩
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              height: lineY,
                              child: Container(color: Colors.black.withValues(alpha: 0.45)),
                            ),
                            // 掃描線本身,加一點發光效果比較明顯
                            Positioned(
                              top: lineY,
                              left: 0,
                              right: 0,
                              child: Container(
                                height: 2.5,
                                decoration: BoxDecoration(
                                  color: Colors.yellowAccent,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.yellowAccent.withValues(alpha: 0.7),
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _corner(Alignment alignment) {
    final isTop = alignment.y < 0;
    final isLeft = alignment.x < 0;
    return Align(
      alignment: alignment,
      child: SizedBox(
        width: 32,
        height: 32,
        child: CustomPaint(
          painter: _CornerPainter(isTop: isTop, isLeft: isLeft),
        ),
      ),
    );
  }

  Widget _buildBackButton() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 24,
      child: SafeArea(
        child: Center(
          child: ElevatedButton.icon(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.chevron_left, size: 18),
            label: const Text('返回'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B5D50),
              foregroundColor: Colors.white,
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ),
      ),
    );
  }
}

/// 四角 L 形掃描框繪製
class _CornerPainter extends CustomPainter {
  final bool isTop;
  final bool isLeft;

  _CornerPainter({required this.isTop, required this.isLeft});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final path = Path();
    final double x = isLeft ? 0 : size.width;
    final double y = isTop ? 0 : size.height;
    final double dx = isLeft ? size.width : -size.width;
    final double dy = isTop ? size.height : -size.height;

    path.moveTo(x, y + dy * 0.6);
    path.lineTo(x, y);
    path.lineTo(x + dx * 0.6, y);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CornerPainter oldDelegate) => false;
}

/// 除錯用暫時結果畫面 —— 之後由介面/後端組的正式結果畫面取代。
/// 只是讓你在還沒接上正式流程前,能親眼確認「掃描 → 送後端 → 拿到回應」這條路有沒有通。
class _DebugResultScreen extends StatelessWidget {
  final DetectionSessionSummary summary;
  final Map<String, dynamic>? backendResult;

  const _DebugResultScreen({required this.summary, required this.backendResult});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('掃描結果(除錯用,非正式畫面)')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('反光點總數: ${summary.totalGlintCount}'),
            Text('高風險反光點: ${summary.highRiskGlintCount}'),
            Text('掃描時開始環境亮度: ${summary.ambientBrightnessAtStart.toStringAsFixed(1)}'),
            Text('是否有開手電筒: ${summary.torchUsedDuringScan}'),
            const Divider(height: 32),
            Text(
              backendResult == null
                  ? '⚠️ 後端連線失敗或尚未設定 endpoint(這是預期中的,因為後端 API 網址還沒接上)'
                  : '後端回應: $backendResult',
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
              child: const Text('回到主選單'),
            ),
          ],
        ),
      ),
    );
  }
}