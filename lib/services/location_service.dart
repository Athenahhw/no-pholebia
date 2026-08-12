import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class LocationService {
  /// 獲取使用者目前的經緯度 (LatLng)
  /// 如果權限被拒絕或定位未開，會拋出 Exception 或回傳 null
  static Future<LatLng?> getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    // 1. 檢查手機定位服務 (GPS) 是否開啟
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // 定位服務未開啟
      return null;
    }

    // 2. 檢查並請求定位權限
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // 使用者拒絕給予權限
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // 使用者永久拒絕權限 (需要去設定手動開啟)
      return null;
    }

    // 3. 取得目前精確位置
    Position position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );

    return LatLng(position.latitude, position.longitude);
  }
}