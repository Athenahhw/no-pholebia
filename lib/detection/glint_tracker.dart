// ============================================================
// glint_tracker.dart
// 功能: 多幀反光點追蹤與晃動評分
// 暫時版本：提供基礎框架，實現簡單的帧間追蹤
// ============================================================
import 'detection_result.dart';

class GlintTracker {
  /// 保存最多 N 幀的反光點，用於晃動分析
  final int maxFrameHistory;

  /// 幀歷史 (每個元素是一幀的反光點列表)
  final List<List<GlintCandidate>> _frameHistory = [];

  /// 追蹤的反光點 ID → 晃動評分映射
  final Map<int, double> _glintFlickerScores = {};

  /// 全局反光點 ID 計數器
  int _nextGlintId = 0;

  GlintTracker({this.maxFrameHistory = 10});

  /// 添加新的一幀
  void addFrame(List<GlintCandidate> candidates) {
    _frameHistory.add(candidates);

    // 保持歷史大小在限制內
    if (_frameHistory.length > maxFrameHistory) {
      _frameHistory.removeAt(0);
    }
  }

  /// 計算並返回帶有晃動評分的反光點列表
  List<GlintCandidate> computeFlickerScores() {
    if (_frameHistory.isEmpty) return [];

    // 簡單實現：最後一幀的反光點
    final lastFrame = _frameHistory.last;

    // TODO: 實現多幀追蹤匹配算法
    // 1. 對比相鄰幀中的反光點位置
    // 2. 根據位移速度和頻率計算晃動評分
    // 3. 返回帶有 flickerScore 的候選對象

    // 臨時版本：返回無評分的候選
    return lastFrame;
  }

  /// 清空歷史（重置追蹤）
  void reset() {
    _frameHistory.clear();
    _glintFlickerScores.clear();
    _nextGlintId = 0;
  }

  /// 獲取歷史幀數
  int get frameCount => _frameHistory.length;
}
