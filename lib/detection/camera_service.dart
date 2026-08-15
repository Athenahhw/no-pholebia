import 'package:camera/camera.dart';

class CameraService {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isTorchOn = false;

  CameraController? get controller => _controller;
  bool get isTorchOn => _isTorchOn;
  bool get isInitialized => _controller?.value.isInitialized ?? false;

  /// 初始化相機,預設使用後鏡頭(掃描環境用)
  Future<void> initialize() async {
    _cameras = await availableCameras();
    if (_cameras.isEmpty) {
      throw CameraException('noCameraFound', '找不到可用的相機');
    }

    final backCamera = _cameras.firstWhere(
      (cam) => cam.lensDirection == CameraLensDirection.back,
      orElse: () => _cameras.first,
    );

    _controller = CameraController(
      backCamera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await _controller!.initialize();
  }

  /// 開關手電筒(閃光燈常亮模式,用於反光偵測的輔助光源)
  Future<void> toggleTorch() async {
    if (_controller == null || !isInitialized) return;
    _isTorchOn = !_isTorchOn;
    await _controller!.setFlashMode(
      _isTorchOn ? FlashMode.torch : FlashMode.off,
    );
  }

  Future<void> setTorch(bool on) async {
    if (_controller == null || !isInitialized) return;
    _isTorchOn = on;
    await _controller!.setFlashMode(on ? FlashMode.torch : FlashMode.off);
  }

  /// 拍照瞬間閃燈,用於「開燈/不開燈」差異比對法
  /// 回傳兩張照片: [不開燈那張, 開燈那張]
  Future<(XFile, XFile)> captureFlashComparisonPair() async {
    if (_controller == null || !isInitialized) {
      throw CameraException('notInitialized', '相機尚未初始化');
    }

    // 先確保燈是關的,拍第一張
    await setTorch(false);
    await Future.delayed(const Duration(milliseconds: 150));
    final withoutFlash = await _controller!.takePicture();

    // 開燈拍第二張
    await setTorch(true);
    await Future.delayed(const Duration(milliseconds: 150));
    final withFlash = await _controller!.takePicture();

    // 拍完恢復關燈,避免一直耗電
    await setTorch(false);

    return (withoutFlash, withFlash);
  }

  /// 啟動即時影像串流,給 glint_detector / yolo_inference 逐幀分析用
  Future<void> startImageStream(void Function(CameraImage image) onFrame) async {
    if (_controller == null || !isInitialized) return;
    await _controller!.startImageStream(onFrame);
  }

  Future<void> stopImageStream() async {
    if (_controller == null) return;
    if (_controller!.value.isStreamingImages) {
      await _controller!.stopImageStream();
    }
  }

  Future<void> dispose() async {
    await stopImageStream();
    await _controller?.dispose();
    _controller = null;
  }
}
