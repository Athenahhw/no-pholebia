// ============================================================
// detection_result.dart
// 定義偵測結果的資料結構
//
// 註: 遠端物件偵測改用 YOLO-World(開放詞彙偵測),類別不是寫死的
// 固定列舉,而是由後端伺服器端的文字提示清單(prompt list)動態決定,
// 例如 ["hook", "tissue box", "electrical outlet", "vent", "trash can"]。
// 所以這裡 objectClass 直接用 String,不用 enum ——未來後端要新增/
// 調整偵測類別,只要改他們那邊的提示清單,前端完全不用改程式碼。
// ============================================================

/// 單一 bounding box,座標為 0~1 正規化比例,方便配合任意畫面尺寸繪製
class BoundingBox {
  final double x, y, width, height;
  final double confidence;
  final String objectClass; // 例如 "hook"、"tissue box"、"electrical outlet"

  BoundingBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.confidence,
    required this.objectClass,
  });

  factory BoundingBox.fromJson(Map<String, dynamic> json) {
    return BoundingBox(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
      confidence: (json['confidence'] as num).toDouble(),
      objectClass: json['class'] as String? ?? 'unknown',
    );
  }

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'confidence': confidence,
        'class': objectClass,
      };
}

/// 反光候選點(來自 glint_detector,本機運算)
class GlintCandidate {
  final int x, y, radius;
  final double brightness;
  final double? flickerScore;

  GlintCandidate({
    required this.x,
    required this.y,
    required this.radius,
    required this.brightness,
    this.flickerScore,
  });

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'radius': radius,
        'brightness': brightness,
        'flickerScore': flickerScore,
      };
}

/// 一次完整掃描的彙整結果,送給後端 AI 的資料格式。
/// 結合兩種來源:
///   - glints: 本機(手機端)反光偵測的結果
///   - boundingBoxes: 遠端(YOLO-World 伺服器)物件偵測的結果
class DetectionSessionSummary {
  final List<GlintCandidate> glints;
  final List<BoundingBox> boundingBoxes;
  final int totalGlintCount;
  final int highRiskGlintCount;
  final double ambientBrightnessAtStart;
  final bool torchUsedDuringScan;
  final bool remoteYoloAvailable;
  final DateTime scanStartedAt;
  final DateTime scanEndedAt;

  DetectionSessionSummary({
    required this.glints,
    this.boundingBoxes = const [],
    required this.totalGlintCount,
    required this.highRiskGlintCount,
    required this.ambientBrightnessAtStart,
    required this.torchUsedDuringScan,
    this.remoteYoloAvailable = false,
    required this.scanStartedAt,
    required this.scanEndedAt,
  });

  Map<String, dynamic> toJson() => {
        'glints': glints.map((g) => g.toJson()).toList(),
        'boundingBoxes': boundingBoxes.map((b) => b.toJson()).toList(),
        'totalGlintCount': totalGlintCount,
        'highRiskGlintCount': highRiskGlintCount,
        'ambientBrightnessAtStart': ambientBrightnessAtStart,
        'torchUsedDuringScan': torchUsedDuringScan,
        'remoteYoloAvailable': remoteYoloAvailable,
        'scanStartedAt': scanStartedAt.toIso8601String(),
        'scanEndedAt': scanEndedAt.toIso8601String(),
        'scanDurationMs': scanEndedAt.difference(scanStartedAt).inMilliseconds,
      };
}