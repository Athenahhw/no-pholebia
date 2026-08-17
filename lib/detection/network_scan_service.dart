// 功能: 掃描目前連接的 WiFi 同網段,找出可能是攝影機的裝置,
// 作為額外的可信度佐證(跟反光偵測、物件偵測結果一起送給後端)。
//
// 原理: 用 TCP connect 嘗試連接攝影機常見會開放的通訊埠
// (80/8080網頁管理介面、554 RTSP串流、37777 DVR/NVR常見埠等)。
// 連得上代表該IP位址有裝置在監聽這些埠,提高是攝影機的可能性,
// 但無法100%確定(路由器、印表機等其他裝置也可能開放80埠)。
import 'dart:async';
import 'dart:io';
import 'package:network_info_plus/network_info_plus.dart';
import 'detection_result.dart';

/// 攝影機常見會開放的通訊埠
const List<int> _cameraCommonPorts = [80, 8080, 554, 8000, 8081, 37777];

class NetworkScanService {
  /// 掃描目前WiFi同網段,回傳偵測到的裝置清單。
  /// timeout: 整體掃描的時間上限,避免拖垮掃描流程的總時長。
  /// 回傳空清單代表:掃描失敗(例如沒有WiFi、權限被拒)或該網段沒有可疑裝置,
  /// 呼叫端無法區分這兩種情況,但因為這只是輔助佐證,失敗時保持空清單即可,
  /// 不影響反光偵測/物件偵測繼續運作。
  Future<List<NetworkDevice>> scan({Duration timeout = const Duration(seconds: 4)}) async {
    try {
      final info = NetworkInfo();
      final wifiIP = await info.getWifiIP(); // 例如 "192.168.1.23"
      if (wifiIP == null) return [];

      final subnet = _extractSubnet(wifiIP); // "192.168.1"
      if (subnet == null) return [];

      final devices = <NetworkDevice>[];
      final completer = Completer<List<NetworkDevice>>();
      final timer = Timer(timeout, () {
        if (!completer.isCompleted) completer.complete(devices);
      });

      // 並行掃描 1~254,但限制同時進行的數量,避免瞬間開太多socket
      const batchSize = 32;
      for (int start = 1; start <= 254; start += batchSize) {
        if (completer.isCompleted) break;
        final end = (start + batchSize - 1).clamp(1, 254);
        final batch = [
          for (int i = start; i <= end; i++) _scanHost('$subnet.$i'),
        ];
        final results = await Future.wait(batch);
        devices.addAll(results.whereType<NetworkDevice>());
      }

      if (!completer.isCompleted) completer.complete(devices);
      timer.cancel();
      return completer.future;
    } catch (e) {
      return [];
    }
  }

  /// 對單一IP嘗試連接常見攝影機通訊埠,有任何一個連得上就回傳NetworkDevice
  /// 對單一IP嘗試連接常見攝影機通訊埠,有任何一個連得上就回傳NetworkDevice
  Future<NetworkDevice?> _scanHost(String ip) async {
    final openPorts = <int>[];

    // 🚀 修正：將原本的循序 for-await 改成平行 Future.wait
    // 這樣一個死掉的 IP，最多也只需要 300 毫秒就會結束，而不是 1.8 秒！
    await Future.wait(_cameraCommonPorts.map((port) async {
      try {
        final socket = await Socket.connect(
          ip,
          port,
          timeout: const Duration(milliseconds: 300),
        );
        openPorts.add(port);
        socket.destroy();
      } catch (_) {
        // 連不上代表該埠沒開,正常情況,略過
      }
    }));

    if (openPorts.isEmpty) return null;

    final looksLikeCamera = openPorts.contains(554) || openPorts.contains(37777);
    return NetworkDevice(ip: ip, openPorts: openPorts, looksLikeCamera: looksLikeCamera);
  }

  String? _extractSubnet(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    return '${parts[0]}.${parts[1]}.${parts[2]}';
  }
}