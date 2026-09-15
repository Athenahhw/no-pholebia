import 'package:flutter_test/flutter_test.dart';
import 'package:pinhole_detector/detection/detection_result.dart';
import 'package:pinhole_detector/detection/glint_detector.dart';

void main() {
  test('tracks a moving glint as one candidate', () {
    final tracker = GlintTracker(maxTrackDistance: 20);

    for (var frame = 0; frame < 5; frame++) {
      tracker.addFrame([
        GlintCandidate(
          x: 100 + frame * 10,
          y: 80,
          radius: 4,
          brightness: 240 + frame * 8,
        ),
      ]);
    }

    final trackedGlints = tracker.computeFlickerScores(minFrames: 3);

    expect(trackedGlints, hasLength(1));
    expect(trackedGlints.single.flickerScore, greaterThan(5));
  });
}