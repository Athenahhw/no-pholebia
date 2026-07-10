// ============================================================
// detection_result.dart
// 定義偵測結果的資料結構,給後端/agent層使用
// ============================================================
class DetectionResult {
  final int x, y;
  final double glintScore;   // 反光異常程度
  final double yoloScore;    // YOLO 物理特徵信心度
  final DateTime timestamp;

  DetectionResult({
    required this.x,
    required this.y,
    required this.glintScore,
    required this.yoloScore,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'glintScore': glintScore,
        'yoloScore': yoloScore,
        'timestamp': timestamp.toIso8601String(),
      };
}
