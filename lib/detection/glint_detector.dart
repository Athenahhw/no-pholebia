import 'package:image/image.dart' as img;
import 'detection_result.dart';
import 'dart:math' as math;

class GlintDetector {
  final int threshold;
  final int minBlobSize;
  final int maxBlobSize;

  GlintDetector({
    this.threshold = 235,
    this.minBlobSize = 3,
    this.maxBlobSize = 300,
  });

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

        final radius = (math.sqrt(blob.length / math.pi)).clamp(1, 999).round();

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

  /// 量測整張影像的平均亮度(0~255),給自動開燈判斷使用。
  /// 用降採樣(每隔幾個像素取樣一次)加快速度,不用整張逐像素算。
  static double averageBrightness(img.Image frame, {int sampleStep = 8}) {
    final gray = img.grayscale(frame);
    double total = 0;
    int count = 0;
    for (int y = 0; y < gray.height; y += sampleStep) {
      for (int x = 0; x < gray.width; x += sampleStep) {
        total += img.getLuminance(gray.getPixel(x, y));
        count++;
      }
    }
    if (count == 0) return 0;
    return total / count;
  }

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

class _Track {
  final List<GlintCandidate> history = [];
}

class GlintTracker {
  final int maxTrackDistance;
  final List<_Track> _tracks = [];

  GlintTracker({this.maxTrackDistance = 20});

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

    for (final c in unmatched) {
      _tracks.add(_Track()..history.add(c));
    }
  }

  double _distance(GlintCandidate a, GlintCandidate b) {
    final dx = (a.x - b.x).toDouble();
    final dy = (a.y - b.y).toDouble();
    return (dx * dx + dy * dy);
  }

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
      final stdDev = variance <= 0 ? 0.0 : math.sqrt(variance);

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