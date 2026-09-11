// lib/risk/time_risk_service.dart

class TimeRiskService {
  /// 根據案件發生時間（YYYY-MM-DD），計算時間風險權重分數 (0.1 ~ 1.0)
  static double calculateTimeRiskWeight(String endDateStr) {
    try {
      // 確保能解析 YYYY-MM-DD 格式，若包含時間則也支援
      final DateTime eventDate = _parseDate(endDateStr);
      final DateTime now = DateTime.now();

      // 計算相差月數
      final int monthsDiff = (now.year - eventDate.year) * 12 + (now.month - eventDate.month);

      if (monthsDiff <= 3) {
        return 1.0; // 近 3 個月內發生的案件：極高風險
      } else if (monthsDiff <= 12) {
        return 0.7; // 1 年內發生的案件：高風險
      } else if (monthsDiff <= 36) {
        return 0.4; // 3 年內發生的案件：中風險
      } else {
        return 0.1; // 3 年以上歷史案件：低風險背景參考
      }
    } catch (e) {
      print('日期解析失敗: $e');
      return 0.5; // 若日期解析失敗，給予預設中等權重
    }
  }

  /// 解析日期字符串，支援 YYYY-MM-DD 及完整 ISO 8601 格式
  static DateTime _parseDate(String dateStr) {
    dateStr = dateStr.trim();
    
    // 如果只有 YYYY-MM-DD 格式（10 個字符），補充為 ISO 8601 格式
    if (dateStr.length == 10 && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dateStr)) {
      dateStr = '${dateStr}T00:00:00Z';
    }
    
    return DateTime.parse(dateStr);
  }

  /// 根據分數轉換風險等級標籤
  static String getRiskLevelString(double score) {
    if (score >= 0.8) return 'HIGH';
    if (score >= 0.4) return 'MEDIUM';
    return 'LOW';
  }
}
