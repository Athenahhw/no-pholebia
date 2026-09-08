import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

// 定義風險等級的顏色與內容
class RiskLevel {
  static const Color high = Color(0xFFFF45D7);        // 高風險 #FF45D7
  static const Color medium = Color(0xFFFFFF45);      // 中風險 #FFFF45
  static const Color low = Color(0xFF4583FF);         // 低風險 #4583FF

  // 標題顏色定義
  static const Color mediumTitleColor = Color(0xFFFFFF45); // 中風險文字用黃色

  static const String highContent = '高風險區域 - 請加倍小心並採取防護措施';
  static const String mediumContent = '中風險區域 - 建議提高警覺';
  static const String lowContent = '低風險區域 - 目前無特殊安全疑慮';
}

class RiskMarkerData {
  final LatLng position;
  final Color riskColor;      // 光圈顏色
  final Color titleColor;     // 標題與叉叉顏色
  final String title;
  final String content;

  RiskMarkerData({
    required this.position,
    required this.riskColor,
    required this.titleColor,
    required this.title,
    required this.content,
  });
}

// 預設的風險點資料清單
List<RiskMarkerData> defaultRiskMarkers = [];
