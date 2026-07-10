// ============================================================
// glint_detector.dart
// 負責人: 前端 - YOLO物理特徵/反光偵測 組
// 功能: 從相機影格中偵測可疑亮點(反光候選區)
// ============================================================
import 'package:image/image.dart' as img;

class GlintCandidate {
  final int x, y, radius;
  final double brightness;
  GlintCandidate(this.x, this.y, this.radius, this.brightness);
}

class GlintDetector {
  /// 從單張影像找出所有超過亮度門檻的候選亮點
  List<GlintCandidate> detect(img.Image frame, {int threshold = 240}) {
    // TODO: 實作 blob detection / flood fill
    // 參考: 之前討論的 flood-fill 版本
    return [];
  }
}
