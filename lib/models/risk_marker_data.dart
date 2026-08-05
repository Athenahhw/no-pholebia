import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

// 定義風險等級的顏色與內容
class RiskLevel {
  static const Color high = Color(0xFFFF45D7);   // 桃粉色 #FF45D7
  static const Color medium = Color(0xFFFFFF45); // 👈 中風險光圈改回黃色 #FFFF45
  static const Color low = Color(0xFF4583FF);    // 藍色 #4583FF

  // 標題顏色定義 (中風險文字用綠色)
  static const Color mediumTitleColor = Color(0xFF395938);

  static const String highContent = '國立台北教育大學近一週會有針孔偷拍事件，地區如下：\n篤行樓3樓女廁\n篤行樓4樓女廁\n科學館3樓女廁\n\n請注意安全。';
  static const String mediumContent = '國立台灣大學近三月會有發現過一次針孔攝影機，被安置在綜合體育館，其餘使用者掃描無異常。請注意安全。';
  static const String lowContent = '台北市立大安高級工業職業學校近一週已有使用者提供安全回報，目前無安全疑慮。';
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
  // 2. 中風險 (黃色光圈 + 綠色標題/叉叉)
  RiskMarkerData(
    position: const LatLng(25.0210, 121.5350),
    riskColor: RiskLevel.medium, // 光圈是黃色
    titleColor: RiskLevel.mediumTitleColor, // 標題/叉叉是綠色
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