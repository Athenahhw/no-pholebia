import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:sensors_plus/sensors_plus.dart';

import 'camera_service.dart';
import 'glint_detector.dart';
import 'object_detector_service.dart';
import 'network_scan_service.dart';
import 'bluetooth_scan_service.dart';
import 'detection_backend_client.dart';
import 'detection_result.dart';
import '../services/location_service.dart';
import 'image_converter.dart'; // 匯入轉換工具
import 'scan_countdown.dart';

class ScanScreen extends StatefulWidget {
  final String? environmentContext;
  final void Function(
    DetectionSessionSummary summary,
    Map<String, dynamic>? backendResult,
  )
  onScanComplete;

  // 修正：使用 super.key 解決 lint 提示
  const ScanScreen({
    super.key,
    this.environmentContext,
    required this.onScanComplete,
  });

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  // --- 服務實例 ---
  final CameraService _cameraService = CameraService();
  final ObjectDetectorService _objectDetector = ObjectDetectorService();
  final NetworkScanService _networkScanner = NetworkScanService();
  final BluetoothScanService _bluetoothScanner = BluetoothScanService();
  final GlintDetector _glintDetector = GlintDetector();
  final GlintTracker _glintTracker = GlintTracker();
  final DetectionBackendClient _backendClient = DetectionBackendClient();

  // --- 狀態變數 ---
  int _elapsedSeconds = 0;
  bool _isProcessing = false;
  bool _objectDetectCallInFlight = false;
  bool _glintCaptureInFlight = false;
  bool _autoFinishTriggered = false;

  // --- 收集到的資料 ---
  List<BoundingBox> _allBoundingBoxes = [];
  double _ambientBrightnessAtStart = 0.0;
  bool _isFirstFrame = true;
  DateTime? _scanStartedAt;
  img.Image? _lastFrame;
  final List<String> _glintScreenshotsBase64 = [];
  final Set<String> _capturedGlintKeys = {};

  Timer? _scanTimer;
  Timer? _scanBeamTimer;
  StreamSubscription<UserAccelerometerEvent>? _accelSubscription;
  bool _showShakeWarning = false;
  bool _warningAcknowledged = false;
  double _scanBeamY = 0.0;

  // 用來保存背景任務的 Future，方便重置時不中斷它們
  Future<List<NetworkDevice>>? _networkFuture;
  Future<List<BluetoothDeviceInfo>>? _bluetoothFuture;

  @override
  void initState() {
    super.initState();
    _initAndStartScan();
  }

  Future<void> _initAndStartScan() async {
    try {
      await _cameraService.initialize();
      await _cameraService.setTorch(true);
      if (!mounted) return;
      setState(() {});

      _scanStartedAt = DateTime.now(); // 記錄掃描開始時間

      _networkFuture = _networkScanner.scan();
      _bluetoothFuture = _bluetoothScanner.scan();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showCaptureWarningDialog();
      });
    } catch (e) {
      debugPrint("相機初始化失敗: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('無法存取相機，請確認權限')));
        Navigator.pop(context);
      }
    }
  }

  void _showCaptureWarningDialog() {
    if (!mounted || _warningAcknowledged) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          title: Row(
            children: [
              const Expanded(
                child: Text(
                  '攝影機預警',
                  style: TextStyle(
                    color: Color(0xFF395938),
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                  ),
                ),
              ),
              IconButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _startScanAfterWarning();
                },
                tooltip: '開始掃描',
                icon: const Icon(Icons.close, color: Color(0xFF395938)),
              ),
            ],
          ),
          content: const Text(
            '系統會在拍攝途中截取鏡頭影像作為反光點與異常特徵分析。這些截圖僅用於本機判斷與結果展示，並不會外流，請放心使用。',
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              color: Color(0xFF49454F),
            ),
          ),
        );
      },
    );
  }

  Future<void> _startScanAfterWarning() async {
    if (_warningAcknowledged) return;
    _warningAcknowledged = true;

    await _cameraService.startImageStream(_processFrame);
    _startMotionDetection();
    _startElapsedTimer();
    _startScanBeamAnimation();
  }

  /// 顯示倒數 6 秒，倒數結束時自動結束，且結束按鈕仍保留可點擊。
  void _startElapsedTimer() {
    _scanTimer?.cancel();
    _scanTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _isProcessing || !_warningAcknowledged) {
        timer.cancel();
        return;
      }

      setState(() {
        _elapsedSeconds++;
        if (ScanCountdown.shouldFinish(_elapsedSeconds) && !_autoFinishTriggered) {
          _autoFinishTriggered = true;
          unawaited(_finishScanByUser());
        }
      });
    });
  }

  Future<void> _finishScanByUser() async {
    if (_isProcessing) return;
    _scanTimer?.cancel();
    _accelSubscription?.cancel();
    setState(() {
      _isProcessing = true;
    });
    await _stopScanAndSubmit(_networkFuture!, _bluetoothFuture!);
  }

  void _startScanBeamAnimation() {
    _scanBeamTimer?.cancel();
    _scanBeamTimer = Timer.periodic(const Duration(milliseconds: 32), (timer) {
      if (!mounted || _isProcessing) return;
      setState(() {
        _scanBeamY += 0.025;
        if (_scanBeamY > 1.0) {
          _scanBeamY = 0.0;
        }
      });
    });
  }

  /// 📍 啟動手機晃動偵測
  void _startMotionDetection() {
    // userAccelerometerEventStream 排除了重力影響，只抓取使用者施加的加速度
    _accelSubscription = userAccelerometerEventStream().listen((
      UserAccelerometerEvent event,
    ) {
      if (_isProcessing) return; // 如果已經在分析了就不管晃動

      // 計算三軸加速度的向量長度 (總搖晃力道)
      double acceleration = math.sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z,
      );

      // 門檻值：8.0 大約是明顯的快速手抖或移動
      // 門檻提高：允許緩慢移動鏡頭掃描，只有明顯甩動才提示
      if (acceleration > 14.0 && !_showShakeWarning) {
        _handleShakeDetected();
      }
    });
  }

  /// 移動鏡頭是允許的；過大晃動只提示，不重置掃描。
  void _handleShakeDetected() {
    setState(() {
      _showShakeWarning = true;
    });

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && !_isProcessing) {
        setState(() => _showShakeWarning = false);
      }
    });
  }

  /// 處理每一幀畫面
  Future<void> _processFrame(CameraImage cameraImage) async {
    if (_showShakeWarning) return;

    // 修正：直接呼叫頂層函式 convertCameraImage
    final img.Image? frameImage = convertCameraImage(cameraImage);
    if (frameImage == null) return;

    _lastFrame = frameImage;

    if (_isFirstFrame) {
      _ambientBrightnessAtStart = GlintDetector.averageBrightness(frameImage);
      _isFirstFrame = false;
    }

    // --- A. 高頻任務：反光點追蹤 ---
    final candidates = _glintDetector.detect(frameImage);
    if (candidates.isNotEmpty) {
      _glintTracker.addFrame(candidates);
      unawaited(
        _captureGlintCrops(frameImage, candidates, forceHighRisk: true),
      );
    }

    // --- B. 低頻任務：物件偵測與截圖 ---
    if (!_objectDetectCallInFlight) {
      _objectDetectCallInFlight = true;

      try {
        final jpegBytes = img.encodeJpg(frameImage, quality: 70);
        final tempFile = await writeTempJpeg(jpegBytes);

        try {
          final boxes = await _objectDetector.detectFromFile(
            tempFile.file.path,
            frameImage.width,
            frameImage.height,
          );

          if (boxes.isNotEmpty) {
            _allBoundingBoxes = boxes;
          }
        } finally {
          await tempFile.cleanup();
        }
      } catch (e) {
        debugPrint("ML Kit 分析發生錯誤: $e");
      } finally {
        _objectDetectCallInFlight = false;
      }
    }
  }

  /// 掃描結束，彙整資料並打 API
  Future<void> _stopScanAndSubmit(
    Future<List<NetworkDevice>> networkFuture,
    Future<List<BluetoothDeviceInfo>> bluetoothFuture,
  ) async {
    await _cameraService.stopImageStream();
    var waitGuard = 0;
    while (_glintCaptureInFlight && waitGuard < 20) {
      await Future.delayed(const Duration(milliseconds: 40));
      waitGuard++;
    }

    final finalGlints = _glintTracker.computeFlickerScores(minFrames: 3);
    final highRiskGlints = finalGlints
        .where((g) => (g.flickerScore ?? 0) > 5.0)
        .length;

    if (_lastFrame != null && finalGlints.isNotEmpty) {
      await _captureGlintCrops(_lastFrame!, finalGlints, forceHighRisk: true);
    }

    final userLocation = await LocationService.getCurrentLocation();
    final networkDevices = await networkFuture;
    final bluetoothDevices = await bluetoothFuture;
    final overviewShot = _lastFrame == null
        ? null
        : _encodeJpegBase64(_lastFrame!, maxWidth: 480, quality: 55);

    final summary = DetectionSessionSummary(
      environmentContext: _normaliseEnvironmentContext(widget.environmentContext),
      glints: finalGlints,
      totalGlintCount: finalGlints.length,
      highRiskGlintCount: highRiskGlints,
      boundingBoxes: _allBoundingBoxes,
      ambientBrightnessAtStart: _ambientBrightnessAtStart,
      torchUsedDuringScan: _cameraService.isTorchOn,
      remoteYoloAvailable: true,
      networkDevices: networkDevices,
      bluetoothDevices: bluetoothDevices,
      latitude: userLocation?.latitude,
      longitude: userLocation?.longitude,
      screenshotBase64: overviewShot,
      glintScreenshotsBase64: List<String>.from(_glintScreenshotsBase64),
      scanStartedAt: _scanStartedAt ?? DateTime.now(),
      scanEndedAt: DateTime.now(),
    );

    final backendResult = await _backendClient.submitScan(summary);

    debugPrint(
      '📦 scan summary => totalGlint=${summary.totalGlintCount}, highRisk=${summary.highRiskGlintCount}, boxes=${summary.boundingBoxes.length}',
    );
    debugPrint('📤 backendResult => $backendResult');

    if (!mounted) return;

    widget.onScanComplete(summary, backendResult);
  }

  String _normaliseEnvironmentContext(String? value) {
    final context = value?.trim() ?? '';
    if (context.isEmpty || context.contains('未提供')) {
      return '目前掃描現場';
    }
    return context;
  }

  Future<void> _captureGlintCrops(
    img.Image frame,
    List<GlintCandidate> candidates, {
    bool forceHighRisk = false,
  }) async {
    if (_glintCaptureInFlight || _glintScreenshotsBase64.length >= 4) return;
    _glintCaptureInFlight = true;
    try {
      for (final candidate in candidates) {
        if (_glintScreenshotsBase64.length >= 4) break;

        final shouldInclude = forceHighRisk
            ? (candidate.flickerScore ?? 0) > 0 || _glintScreenshotsBase64.isEmpty
            : true;
        if (!shouldInclude) continue;

        final key = '${candidate.x ~/ 24}_${candidate.y ~/ 24}';
        if (_capturedGlintKeys.contains(key)) continue;
        _capturedGlintKeys.add(key);

        final crop = _cropAroundGlint(frame, candidate);
        img.drawCircle(
          crop,
          x: crop.width ~/ 2,
          y: crop.height ~/ 2,
          radius: math.max(8, candidate.radius + 6),
          color: img.ColorRgb8(255, 51, 204),
        );
        _glintScreenshotsBase64.add(
          base64Encode(img.encodeJpg(crop, quality: 62)),
        );
      }
    } catch (e) {
      debugPrint('glint 截圖失敗: $e');
    } finally {
      _glintCaptureInFlight = false;
    }
  }

  img.Image _cropAroundGlint(img.Image frame, GlintCandidate candidate) {
    const size = 180;
    final left = (candidate.x - size ~/ 2).clamp(0, math.max(0, frame.width - 1)).toInt();
    final top = (candidate.y - size ~/ 2).clamp(0, math.max(0, frame.height - 1)).toInt();
    final width = math.min(size, frame.width - left).clamp(1, frame.width).toInt();
    final height = math.min(size, frame.height - top).clamp(1, frame.height).toInt();
    return img.copyCrop(
      frame,
      x: left,
      y: top,
      width: width,
      height: height,
    );
  }

  String _encodeJpegBase64(img.Image frame, {int maxWidth = 480, int quality = 55}) {
    var output = frame;
    if (frame.width > maxWidth) {
      output = img.copyResize(frame, width: maxWidth);
    }
    return base64Encode(img.encodeJpg(output, quality: quality));
  }

  @override
  void dispose() {
    _scanTimer?.cancel(); // 退出頁面時取消計時器
    _scanBeamTimer?.cancel();
    _accelSubscription?.cancel(); // 退出頁面時取消感測器監聽
    _cameraService.dispose();
    _objectDetector.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_cameraService.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.green)),
      );
    }

    final screenSize = MediaQuery.of(context).size;
    final inset = 12.0;
    final scanRect = Rect.fromLTWH(
      inset,
      120,
      screenSize.width - inset * 2,
      screenSize.height - 220,
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_cameraService.controller!),

          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: ScanOverlayPainter(
                  scanRect: scanRect,
                  beamYRatio: _scanBeamY,
                  showShakeWarning: _showShakeWarning,
                ),
              ),
            ),
          ),

          // 👈 新增：晃動警告提示覆蓋層
          if (_showShakeWarning)
            Positioned(
              top: 180,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 20,
                ),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(color: Colors.black54, blurRadius: 8),
                  ],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                    SizedBox(width: 8),
                    Text(
                      "晃動過大，請放慢移動速度",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          Positioned(
            top: 54,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                '可移動鏡頭說明\n請緩慢移動鏡頭掃描插座、掛勾、煙霧偵測器等位置，完成後按下下方結束鍵，如同手機錄影結束。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

          Positioned(
            bottom: 36,
            left: 0,
            right: 0,
            child: Column(
              children: [
                if (!_isProcessing) ...[
                  Text(
                    '倒數 ${ScanCountdown.remainingSeconds(_elapsedSeconds).toString().padLeft(2, '0')} 秒',
                    style: const TextStyle(
                      fontSize: 28,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '掃描進行中，可移動鏡頭',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  const SizedBox(height: 18),
                  GestureDetector(
                    onTap: _finishScanByUser,
                    child: Container(
                      width: 78,
                      height: 78,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                      ),
                      child: Center(
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '結束掃描',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ] else ...[
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 16),
                  const Text(
                    "正在進行多模態 AI 綜合分析...",
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ScanOverlayPainter extends CustomPainter {
  final Rect scanRect;
  final double beamYRatio;
  final bool showShakeWarning;

  const ScanOverlayPainter({
    required this.scanRect,
    required this.beamYRatio,
    required this.showShakeWarning,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Paint()..color = Colors.black.withValues(alpha: 0.25);
    final overlayPath = Path.combine(
      PathOperation.difference,
      Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
      Path()..addRect(scanRect),
    );
    canvas.drawPath(overlayPath, outer);

    const strokeWidth = 4.0;
    final cornerLength = 28.0;
    final whiteFill = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // 左上
    canvas.drawRect(
      Rect.fromLTWH(scanRect.left, scanRect.top, cornerLength, strokeWidth),
      whiteFill,
    );
    canvas.drawRect(
      Rect.fromLTWH(scanRect.left, scanRect.top, strokeWidth, cornerLength),
      whiteFill,
    );
    // 右上
    canvas.drawRect(
      Rect.fromLTWH(
        scanRect.right - cornerLength,
        scanRect.top,
        cornerLength,
        strokeWidth,
      ),
      whiteFill,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        scanRect.right - strokeWidth,
        scanRect.top,
        strokeWidth,
        cornerLength,
      ),
      whiteFill,
    );
    // 左下
    canvas.drawRect(
      Rect.fromLTWH(
        scanRect.left,
        scanRect.bottom - strokeWidth,
        cornerLength,
        strokeWidth,
      ),
      whiteFill,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        scanRect.left,
        scanRect.bottom - cornerLength,
        strokeWidth,
        cornerLength,
      ),
      whiteFill,
    );
    // 右下
    canvas.drawRect(
      Rect.fromLTWH(
        scanRect.right - cornerLength,
        scanRect.bottom - strokeWidth,
        cornerLength,
        strokeWidth,
      ),
      whiteFill,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        scanRect.right - strokeWidth,
        scanRect.bottom - cornerLength,
        strokeWidth,
        cornerLength,
      ),
      whiteFill,
    );

    final beamY = scanRect.top + (scanRect.height * beamYRatio);
    final beamRect = Rect.fromLTWH(scanRect.left, beamY - 4, scanRect.width, 8);

    final beamPaint = Paint()
      ..color = const Color(0xFFFFD727)
      ..style = PaintingStyle.fill;
    canvas.drawRect(beamRect, beamPaint);

    if (showShakeWarning) {
      final warnPaint = Paint()
        ..color = Colors.redAccent.withValues(alpha: 0.6);
      canvas.drawRect(scanRect, warnPaint);
    }
  }

  @override
  bool shouldRepaint(covariant ScanOverlayPainter oldDelegate) {
    return oldDelegate.beamYRatio != beamYRatio ||
        oldDelegate.scanRect != scanRect ||
        oldDelegate.showShakeWarning != showShakeWarning;
  }
}
