// ============================================================
// glint_detector.dart
// 負責人: 前端 - YOLO物理特徵/反光偵測 組
// 功能: 從相機影格中偵測可疑亮點(反光候選區),用 flood-fill 做
//       簡易 blob detection,過濾雜訊與大片過曝區域。
// ============================================================
import 'package:image/image.dart' as img;
import 'detection_result.dart';

class GlintDetector {
  /// 亮度門檻(0~255),高於此值視為候選亮點
  final int threshold;

  /// blob 面積過濾範圍,避免抓到雜訊(太小)或整片過曝(太大)
  final int minBlobSize;
  final int maxBlobSize;

  GlintDetector({
    this.threshold = 235,
    this.minBlobSize = 3,
    this.maxBlobSize = 300,
  });

  /// 從單張影像找出所有超過亮度門檻的候選亮點
  List<GlintCandidate> detect(img.Image frame) {
    final gray = img.grayscale(frame);
    final width = gray.width;
    final height = gray.height;

    final visited = List.generate(height, (_) => List.filled(width, false));
    final candidates = <GlintCandidate>[];

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        if (visited[y][x]) continue;

        final lum = img.getLuminance(gray.getPixel(x, y));
        if (lum <= threshold) {
          visited[y][x] = true;
          continue;
        }

        final blob = _floodFill(gray, x, y, threshold, visited);
        if (blob.length < minBlobSize || blob.length > maxBlobSize) continue;

        final cx = blob.map((p) => p.$1).reduce((a, b) => a + b) ~/ blob.length;
        final cy = blob.map((p) => p.$2).reduce((a, b) => a + b) ~/ blob.length;
        final avgBrightness = blob
                .map((p) => img.getLuminance(gray.getPixel(p.$1, p.$2)))
                .reduce((a, b) => a + b) /
            blob.length;

        // 用 blob 面積概估半徑(視為近似圓形)
        final radius = (blob.length / 3.14159).clamp(1, 999).round();

        candidates.add(GlintCandidate(
          x: cx,
          y: cy,
          radius: radius,
          brightness: avgBrightness.toDouble(),
        ));
      }
    }

    return candidates;
  }

  /// 用迭代式(非遞迴,避免大圖 stack overflow)flood-fill 找出連通的高亮度區域
  List<(int, int)> _floodFill(
    img.Image gray,
    int startX,
    int startY,
    int threshold,
    List<List<bool>> visited,
  ) {
    final stack = <(int, int)>[(startX, startY)];
    final blob = <(int, int)>[];

    while (stack.isNotEmpty) {
      final (x, y) = stack.removeLast();

      if (x < 0 || y < 0 || x >= gray.width || y >= gray.height) continue;
      if (visited[y][x]) continue;

      final lum = img.getLuminance(gray.getPixel(x, y));
      if (lum <= threshold) {
        visited[y][x] = true;
        continue;
      }

      visited[y][x] = true;
      blob.add((x, y));

      stack.add((x + 1, y));
      stack.add((x - 1, y));
      stack.add((x, y + 1));
      stack.add((x, y - 1));
    }

    return blob;
  }
}

// ============================================================
// GlintTracker
// 功能: 多幀追蹤同一亮點,計算閃爍分數(flickerScore)。
//       針孔鏡頭反光具方向性(retroreflection),角度微幅改變時
//       亮度會明顯變化;一般反光物(金屬、油漆)則相對穩定。
// ============================================================
class _Track {
  final List<GlintCandidate> history = [];
}

class GlintTracker {
  final int maxTrackDistance; // 判定為同一顆亮點的座標容忍距離(px)
  final List<_Track> _tracks = [];

  GlintTracker({this.maxTrackDistance = 20});

  /// 每拿到新一幀的候選點就呼叫一次,內部自動配對到既有 track 或建立新 track
  void addFrame(List<GlintCandidate> candidatesInFrame) {
    final unmatched = List<GlintCandidate>.from(candidatesInFrame);

    for (final track in _tracks) {
      if (track.history.isEmpty) continue;
      final last = track.history.last;

      GlintCandidate? closest;
      double closestDist = double.infinity;
      for (final c in unmatched) {
        final dist = _distance(last, c);
        if (dist < maxTrackDistance && dist < closestDist) {
          closest = c;
          closestDist = dist;
        }
      }

      if (closest != null) {
        track.history.add(closest);
        unmatched.remove(closest);
      }
    }

    // 沒配對到既有 track 的候選點,視為新的 track 起點
    for (final c in unmatched) {
      _tracks.add(_Track()..history.add(c));
    }
  }

  double _distance(GlintCandidate a, GlintCandidate b) {
    final dx = (a.x - b.x).toDouble();
    final dy = (a.y - b.y).toDouble();
    return (dx * dx + dy * dy);
  }

  /// 蒐集夠幀數後呼叫,回傳每條 track 的閃爍分數(亮度標準差,越高越可疑)
  /// 只回傳幀數 >= minFrames 的 track(太短的追蹤不具統計意義)
  List<GlintCandidate> computeFlickerScores({int minFrames = 5}) {
    final results = <GlintCandidate>[];

    for (final track in _tracks) {
      if (track.history.length < minFrames) continue;

      final brightnesses = track.history.map((g) => g.brightness).toList();
      final mean = brightnesses.reduce((a, b) => a + b) / brightnesses.length;
      final variance = brightnesses
              .map((b) => (b - mean) * (b - mean))
              .reduce((a, b) => a + b) /
          brightnesses.length;
      final stdDev = variance <= 0 ? 0.0 : (variance).abs();

      final last = track.history.last;
      results.add(GlintCandidate(
        x: last.x,
        y: last.y,
        radius: last.radius,
        brightness: mean,
        flickerScore: stdDev,
      ));
    }

    return results;
  }

  void reset() => _tracks.clear();
}
