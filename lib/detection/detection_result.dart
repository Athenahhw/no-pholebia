enum RiskObjectClass {
  hook,       // 掛鉤
  trashBin,   // 垃圾桶
  vent,       // 通風口
  glintOnly,  
}
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

class DetectionResult {
  final List<GlintCandidate> glints;    
  final DateTime timestamp;

  DetectionResult({
    required this.glints,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
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