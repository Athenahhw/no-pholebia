// ============================================================
// yolo_inference.dart
// 負責人: 前端 - YOLO物理特徵/反光偵測 組
// 功能: 對候選亮點裁切區域做 YOLO 分類,判斷是否像針孔鏡頭
// ============================================================
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

class YoloDetector {
  Interpreter? _interpreter;

  Future<void> loadModel() async {
    // TODO: 換成訓練好的 pinhole_yolo.tflite
    _interpreter = await Interpreter.fromAsset('assets/models/pinhole_yolo.tflite');
  }


  Future<double> classifyCandidate(img.Image cropped) async {
    // TODO: preprocess + run inference,回傳信心度 0~1
    return 0.0;
  }

  void dispose() {
    _interpreter?.close();
  }
}
