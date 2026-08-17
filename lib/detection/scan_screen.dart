import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

import 'camera_service.dart';
import 'glint_detector.dart';
import 'object_detector_service.dart';
import 'network_scan_service.dart';
import 'bluetooth_scan_service.dart';
import 'detection_backend_client.dart';
import 'detection_result.dart';
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
  String? _finalScreenshotBase64;
  double _ambientBrightnessAtStart = 0.0;
  bool _isFirstFrame = true;
  DateTime? _scanStartedAt;

  @override
  void initState() {
    super.initState();
    _initAndStartScan();
  }

  Future<void> _initAndStartScan() async {
    try {
      await _cameraService.initialize();
      if (!mounted) return;
      setState(() {});

      _scanStartedAt = DateTime.now(); // 記錄掃描開始時間

      // 1. 同時啟動背景的 Wi-Fi 與藍牙掃描
      final networkFuture = _networkScanner.scan();
      final bluetoothFuture = _bluetoothScanner.scan();

      // 2. 啟動相機影像串流
      await _cameraService.startImageStream(_processFrame);

      // 3. 啟動 6 秒倒數計時器
      Timer.periodic(const Duration(seconds: 1), (timer) async {
        if (!mounted) {
          timer.cancel();
          return;
        }

        setState(() {
          _timeLeft--;
        });

        if (_timeLeft <= 0) {
          timer.cancel();
          setState(() {
            _isProcessing = true; // 進入等待後端回應狀態
          });
          // 掃描時間到，停止串流並彙整資料送後端
          await _stopScanAndSubmit(networkFuture, bluetoothFuture);
        }
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

  /// 處理每一幀畫面
  Future<void> _processFrame(CameraImage cameraImage) async {
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
          _finalScreenshotBase64 = base64Encode(jpegBytes);
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
      screenshotBase64: _finalScreenshotBase64,
      networkDevices: networkDevices,
      bluetoothDevices: bluetoothDevices,
      latitude: null,
      longitude: null,
      scanStartedAt: _scanStartedAt ?? DateTime.now(),
      scanEndedAt: DateTime.now(),
    );

    final backendResult = await _backendClient.submitScan(summary);

    if (!mounted) return;

    widget.onScanComplete(summary, backendResult);
  }

  @override
  void dispose() {
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

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_cameraService.controller!),
          Center(
            child: Container(
              width: 300,
              height: 400,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.green.withValues(alpha: 0.5),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(16),
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
                    style: const TextStyle(
                      fontSize: 80,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(color: Colors.black, blurRadius: 10)],
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
