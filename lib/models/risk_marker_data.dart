import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

// 定義風險等級的顏色與內容
class RiskLevel {
  static const Color high = Color(0xFFE63946);        // 深紅色 #E63946
  static const Color medium = Color(0xFFFFA500);      // 黃橘色 #FFA500
  static const Color low = Color(0xFF1E90FF);         // 道奇藍 #1E90FF

  // 標題顏色定義
  static const Color mediumTitleColor = Color(0xFFFFA500); // 中風險文字用黃橘色

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
List<RiskMarkerData> defaultRiskMarkers = [
  // 1. 高風險
  RiskMarkerData(
    position: const LatLng(25.0263, 121.5435),
    riskColor: RiskLevel.high,
    titleColor: RiskLevel.high,
    title: '高風險',
    content: RiskLevel.highContent,
  ),
  // 2. 中風險 (黃橘色光圈 + 黃橘色標題/叉叉)
  RiskMarkerData(
    position: const LatLng(25.0210, 121.5350),
    riskColor: RiskLevel.medium,
    titleColor: RiskLevel.mediumTitleColor,
    title: '中風險',
    content: RiskLevel.mediumContent,
  ),
  // 3. 低風險
  RiskMarkerData(
    position: const LatLng(25.0335, 121.5430),
    riskColor: RiskLevel.low,
    titleColor: RiskLevel.low,
    title: '低風險',
    content: RiskLevel.lowContent,
  ),
];
