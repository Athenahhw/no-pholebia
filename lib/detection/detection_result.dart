/// 反光候選點(來自 glint_detector)
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

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'radius': radius,
        'brightness': brightness,
        'flickerScore': flickerScore,
      };
}

/// 一次完整掃描(從開始到結束)的彙整結果,這是要送給後端 AI 的資料格式。
/// 後端(多模態推理/語義推理組)拿到這包 JSON 後,再結合 LLM 判斷風險等級、
/// 產出像「低風險4%」「高風險88%」那種畫面用的資料。
class DetectionSessionSummary {
  final List<GlintCandidate> glints; // 本次掃描累積偵測到的所有反光點(含閃爍分數)
  final int totalGlintCount; // 反光點總數
  final int highRiskGlintCount; // 閃爍分數超過門檻的反光點數量
  final double ambientBrightnessAtStart; // 開始掃描時量測到的環境亮度(0~255)
  final bool torchUsedDuringScan; // 本次掃描是否有開啟手電筒
  final DateTime scanStartedAt;
  final DateTime scanEndedAt;

  DetectionSessionSummary({
    required this.glints,
    required this.totalGlintCount,
    required this.highRiskGlintCount,
    required this.ambientBrightnessAtStart,
    required this.torchUsedDuringScan,
    required this.scanStartedAt,
    required this.scanEndedAt,
  });

  Map<String, dynamic> toJson() => {
        'glints': glints.map((g) => g.toJson()).toList(),
        'totalGlintCount': totalGlintCount,
        'highRiskGlintCount': highRiskGlintCount,
        'ambientBrightnessAtStart': ambientBrightnessAtStart,
        'torchUsedDuringScan': torchUsedDuringScan,
        'scanStartedAt': scanStartedAt.toIso8601String(),
        'scanEndedAt': scanEndedAt.toIso8601String(),
        'scanDurationMs': scanEndedAt.difference(scanStartedAt).inMilliseconds,
      };
}