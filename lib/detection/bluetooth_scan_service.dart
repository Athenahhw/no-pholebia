// 功能: 掃描附近的藍牙裝置,比對命名關鍵字,找出可能是針孔攝影機的裝置。
// 跟 network_scan_service.dart 是同一類「輔助佐證」性質——連得到訊號
// 才抓得到,不是決定性證據。
//
// 適用情境: 有些針孔攝影機用藍牙做設定/配對,即使主要功能是WiFi或
// 錄影,附近手機仍掃得到它在廣播。這個方法在iOS/Android都能用
// (跟WiFi SSID掃描不同,那個iOS系統層級直接不開放)。
//
// 侷限性:
//   - 裝置要開著藍牙廣播才抓得到,完全不用無線訊號的裝置(純SIM卡、
//     純有線)一樣抓不到
//   - 靠裝置名稱關鍵字比對,裝置命名不含可疑字樣的話會漏掉
//   - 這也是輔助佐證,要跟反光偵測/物件偵測/WiFi網段掃描結果
//     一起交給後端綜合判斷

import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'detection_result.dart';

/// 常見攝影機/監控裝置命名會出現的關鍵字(小寫比對)
const List<String> _suspiciousKeywords = [
  'cam',
  'ipc',
  'dvr',
  'nvr',
  'eye',
  'spy',
  'p2p',
  'wificam',
  'smartcam',
];

class BluetoothScanService {
  /// 掃描附近藍牙裝置,回傳偵測到的裝置清單(含是否命中可疑關鍵字)。
  /// 掃描失敗(藍牙關閉、權限被拒等)回傳空清單,不影響其他偵測邏輯繼續運作。
  Future<List<BluetoothDeviceInfo>> scan({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    try {
      final isSupported = await FlutterBluePlus.isSupported;
      if (!isSupported) return [];

      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) return [];

      final found = <String, BluetoothDeviceInfo>{}; // 用 id 去重複

      final subscription = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          final name = r.device.platformName;
          if (name.isEmpty) continue;

          final lowerName = name.toLowerCase();
          final suspicious = _suspiciousKeywords.any(
            (k) => lowerName.contains(k),
          );

          found[r.device.remoteId.str] = BluetoothDeviceInfo(
            name: name,
            deviceId: r.device.remoteId.str,
            rssi: r.rssi,
            suspicious: suspicious,
          );
        }
      });

      try {
        await FlutterBluePlus.startScan(timeout: timeout);
        await FlutterBluePlus.isScanning.where((s) => s == false).first;
      } finally {
        await subscription.cancel();
        await FlutterBluePlus.stopScan();
      }

      return found.values.toList();
    } catch (e) {
      return [];
    }
  }
}
