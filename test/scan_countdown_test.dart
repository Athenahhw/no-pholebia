import 'package:flutter_test/flutter_test.dart';
import 'package:pinhole_detector/detection/scan_countdown.dart';

void main() {
  group('ScanCountdown', () {
    test('start at six seconds', () {
      expect(ScanCountdown.remainingSeconds(0), 6);
      expect(ScanCountdown.shouldFinish(0), isFalse);
    });

    test('finishes at six seconds while keeping button available', () {
      expect(ScanCountdown.remainingSeconds(5), 1);
      expect(ScanCountdown.remainingSeconds(6), 0);
      expect(ScanCountdown.shouldFinish(6), isTrue);
      expect(ScanCountdown.shouldFinish(7), isTrue);
    });
  });
}
