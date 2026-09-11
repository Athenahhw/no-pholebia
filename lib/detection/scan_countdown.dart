class ScanCountdown {
  static const int totalSeconds = 6;

  static int remainingSeconds(int elapsedSeconds) {
    final remaining = totalSeconds - elapsedSeconds;
    return remaining <= 0 ? 0 : remaining;
  }

  static bool shouldFinish(int elapsedSeconds) => elapsedSeconds >= totalSeconds;
}
