import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// 警察局資料模型
class PoliceStation {
  final String name;      // 警局名稱
  final String phone;     // 聯絡電話
  final String address;   // 地址
  final LatLng location;  // 經緯度
  double? distanceInMeters; // 與使用者的距離 (公尺)

  PoliceStation({
    required this.name,
    required this.phone,
    required this.address,
    required this.location,
    this.distanceInMeters,
  });

  factory PoliceStation.fromJson(Map<String, dynamic> json) {
    return PoliceStation(
      name: json['name'] ?? '',
      phone: json['phone'] ?? '',
      address: json['address'] ?? '',
      location: LatLng(
        (json['latitude'] as num).toDouble(),
        (json['longitude'] as num).toDouble(),
      ),
    );
  }

  /// 格式化顯示距離 (例如: "350 m" 或 "2.4 km")
  String get formattedDistance {
    if (distanceInMeters == null) return '';
    if (distanceInMeters! < 1000) {
      return '${distanceInMeters!.round()} m';
    } else {
      return '${(distanceInMeters! / 1000).toStringAsFixed(1)} km';
    }
  }
}

class PoliceService {
  /// 從 assets/data/police_stations.json 讀取資料
  /// 並依據 userLocation 算出距離最近的前 count 間警察局
  static Future<List<PoliceStation>> getNearestStations({
    required LatLng userLocation,
    int count = 3,
  }) async {
    try {
      // 1. 讀取本機 JSON 檔案
      final String jsonString = await rootBundle.loadString('assets/json/police_stations.json');
      final List<dynamic> jsonList = json.decode(jsonString);

      List<PoliceStation> stations = [];

      // 2. 解析 JSON 並計算與使用者的距離
      for (var item in jsonList) {
        PoliceStation station = PoliceStation.fromJson(item);

        double distance = Geolocator.distanceBetween(
          userLocation.latitude,
          userLocation.longitude,
          station.location.latitude,
          station.location.longitude,
        );

        station.distanceInMeters = distance;
        stations.add(station);
      }

      // 3. 依距離由近到遠排序
      stations.sort((a, b) => (a.distanceInMeters ?? 0).compareTo(b.distanceInMeters ?? 0));

      // 4. 回傳前 N 間最近的警局
      return stations.take(count).toList();
    } catch (e) {
      print('讀取警局資料錯誤: $e');
      return [];
    }
  }
}