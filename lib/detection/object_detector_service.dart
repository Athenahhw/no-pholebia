// 功能: 在地端(手機本身)偵測畫面中的物件,框出可疑位置。
// 用 Google ML Kit 取代原本需要另外架伺服器的 YOLO 方案:
//   - 完全在手機上運算,不需要網路、不需要伺服器、不需要訓練資料
//   - 分類是粗略類別(家用品/其他等),不會精準到"掛鉤"這種程度

import 'dart:io';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'detection_result.dart';

class ObjectDetectorService {
  late final ObjectDetector _detector;

  ObjectDetectorService() {
    _detector = ObjectDetector(
      options: ObjectDetectorOptions(
        mode: DetectionMode.single, // 單張圖片模式(對應我們是定期拍一張分析,不是逐幀連續追蹤)
        classifyObjects: true, // 開啟粗略分類(家用品/食物/植物...)
        multipleObjects: true, // 一張圖裡可能不只一個可疑物件
      ),
    );
  }

  /// 對一個暫存圖片檔案做物件偵測,回傳框出的候選物件清單(座標已正規化成0~1比例)
  Future<List<BoundingBox>> detectFromFile(
    String imagePath,
    int imageWidth,
    int imageHeight,
  ) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final objects = await _detector.processImage(inputImage);

    final boxes = <BoundingBox>[];
    for (final obj in objects) {
      final rect = obj.boundingBox;
      final label = obj.labels.isNotEmpty ? obj.labels.first.text : 'unknown';
      final confidence = obj.labels.isNotEmpty ? obj.labels.first.confidence : 0.0;

      boxes.add(BoundingBox(
        x: (rect.left / imageWidth).clamp(0.0, 1.0),
        y: (rect.top / imageHeight).clamp(0.0, 1.0),
        width: (rect.width / imageWidth).clamp(0.0, 1.0),
        height: (rect.height / imageHeight).clamp(0.0, 1.0),
        confidence: confidence,
        objectClass: label,
      ));
    }
    return boxes;
  }

  void dispose() {
    _detector.close();
  }
}

/// 把 img.Image 暫時寫成一個檔案,給 InputImage.fromFilePath 用,
/// 用完記得呼叫回傳的 cleanup() 刪掉暫存檔,避免手機空間被塞滿垃圾檔案。
class TempImageFile {
  final File file;
  TempImageFile(this.file);

  Future<void> cleanup() async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // 刪除失敗不影響主流程,靜默忽略
    }
  }
}

Future<TempImageFile> writeTempJpeg(List<int> jpegBytes) async {
  final tempDir = Directory.systemTemp;
  final path =
      '${tempDir.path}/scan_frame_${DateTime.now().millisecondsSinceEpoch}.jpg';
  final file = await File(path).writeAsBytes(jpegBytes);
  return TempImageFile(file);
}