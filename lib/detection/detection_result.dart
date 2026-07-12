// ============================================================
// detection_result.dart
// 定義偵測結果的資料結構,給後端/agent層使用
// ============================================================

/// 高風險物件類別(女廁場域常見的偽裝位置)
enum RiskObjectClass {
  hook,       // 掛鉤
  trashBin,   // 垃圾桶
  vent,       // 通風口
  glintOnly,  // 只有反光點,YOLO 未分類出具體物件外觀
}

extension RiskObjectClassLabel on RiskObjectClass {
  String get label {
    switch (this) {
      case RiskObjectClass.hook:
        return '掛鉤';
      case RiskObjectClass.trashBin:
        return '垃圾桶';
      case RiskObjectClass.vent:
        return '通風口';
      case RiskObjectClass.glintOnly:
        return '不明反光點';
    }
  }
}

/// 單一 bounding box(YOLO 輸出座標,已正規化到 0~1,方便配合任意畫面尺寸繪製)
class BoundingBox {
  final double x, y, width, height; // 左上角 x,y + 寬高,皆為 0~1 比例
  final double confidence;
  final RiskObjectClass objectClass;

  BoundingBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.confidence,
    required this.objectClass,
  });

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'confidence': confidence,
        'class': objectClass.name,
      };
}

/// 反光候選點(來自 glint_detector,尚未經過 YOLO 分類)
class GlintCandidate {
  final int x, y, radius;
  final double brightness;
  final double? flickerScore; // 多幀晃動追蹤後才會有值,null 代表尚未做多幀分析

  GlintCandidate({
    required this.x,
    required this.y,
    required this.radius,
    required this.brightness,
    this.flickerScore,
  });
}

/// 整合一次分析(單一影格或單一場景掃描)的完整結果,往上交給 Agent 層做多模態推理
class DetectionResult {
  final List<BoundingBox> boundingBoxes; // YOLO 物理特徵偵測結果
  final List<GlintCandidate> glints;     // 反光點偵測結果
  final DateTime timestamp;

  DetectionResult({
    required this.boundingBoxes,
    required this.glints,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'boundingBoxes': boundingBoxes.map((b) => b.toJson()).toList(),
        'glints': glints
            .map((g) => {
                  'x': g.x,
                  'y': g.y,
                  'radius': g.radius,
                  'brightness': g.brightness,
                  'flickerScore': g.flickerScore,
                })
            .toList(),
        'timestamp': timestamp.toIso8601String(),
      };
}