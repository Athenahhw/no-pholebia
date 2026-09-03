import 'dart:async';
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
  int _timeLeft = 6;
  bool _isProcessing = false;
  bool _objectDetectCallInFlight = false;

  // --- 收集到的資料 ---
  List<BoundingBox> _allBoundingBoxes = [];
  double _ambientBrightnessAtStart = 0.0;
  bool _isFirstFrame = true;
  DateTime? _scanStartedAt;

  Timer? _scanTimer;
  Timer? _scanBeamTimer;
  StreamSubscription<UserAccelerometerEvent>? _accelSubscription;
  bool _showShakeWarning = false;
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

      await _cameraService.startImageStream(_processFrame);

      _startMotionDetection();
      _startTimer();
      _startScanBeamAnimation();
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

  /// 📍 啟動倒數計時器 (獨立出來以便重啟)
  void _startTimer() {
    _scanTimer?.cancel(); // 確保不會有重複的 Timer

    _scanTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        _timeLeft--;
      });

      if (_timeLeft <= 0) {
        timer.cancel();
        _accelSubscription?.cancel(); // 掃描時間到，關閉晃動偵測

        setState(() {
          _isProcessing = true; // 進入等待後端回應狀態
        });

        // 掃描時間到，停止串流並彙整資料送後端
        await _stopScanAndSubmit(_networkFuture!, _bluetoothFuture!);
      }
    });
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
      if (acceleration > 8.0 && !_showShakeWarning) {
        _handleShakeDetected();
      }
    });
  }

  /// 📍 處理晃動事件：重置所有掃描進度
  void _handleShakeDetected() {
    setState(() {
      _showShakeWarning = true;
      _timeLeft = 6; // 重置時間

      // 清空之前因為晃動可能產生的「錯誤反光點」與「殘影物件」
      _glintTracker.reset();
      _allBoundingBoxes.clear();
      _isFirstFrame = true;
    });

    _startTimer(); // 重啟計時器

    // 顯示警告 2 秒後自動隱藏
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

    if (_isFirstFrame) {
      _ambientBrightnessAtStart = GlintDetector.averageBrightness(frameImage);
      _isFirstFrame = false;
    }

    // --- A. 高頻任務：反光點追蹤 ---
    final candidates = _glintDetector.detect(frameImage);
    _glintTracker.addFrame(candidates);

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

    final finalGlints = _glintTracker.computeFlickerScores(minFrames: 3);
    final highRiskGlints = finalGlints
        .where((g) => (g.flickerScore ?? 0) > 5.0)
        .length;

    final userLocation = await LocationService.getCurrentLocation();
    final networkDevices = await networkFuture;
    final bluetoothDevices = await bluetoothFuture;

    // 修正：補齊時間參數，刪除未定義的參數
    final summary = DetectionSessionSummary(
      environmentContext: widget.environmentContext ?? "未提供",
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
      screenshotBase64: null,
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
              top: 120,
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
                      "晃動過大！掃描已重置",
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
            bottom: 100,
            left: 0,
            right: 0,
            child: Column(
              children: [
                if (!_isProcessing) ...[
                  Text(
                    '$_timeLeft',
                    style: TextStyle(
                      fontSize: 80,
                      color: _showShakeWarning
                          ? Colors.redAccent
                          : Colors.white,
                      fontWeight: FontWeight.bold,
                      shadows: const [
                        Shadow(color: Colors.black, blurRadius: 10),
                      ],
                    ),
                  ),
                  const Text(
                    "掃描進行中...",
                    style: TextStyle(color: Colors.white, fontSize: 18),
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
