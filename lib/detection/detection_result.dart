// 註: 物件偵測改用 Google ML Kit,在地端(手機本身)運算,不需要
// 另外架伺服器。ML Kit 給的是粗略分類(家用品/食物/植物/其他),
// 不是精準的"掛鉤"、"面紙盒"這種細分類別,這是刻意的設計 ——
// 精準的語意判斷("這個東西出現在這裡合理嗎")交給後端的多模態LLM
// 去做,前端只負責"框出候選位置"這個較簡單的任務。


/// 單一 bounding box,座標為 0~1 正規化比例,方便配合任意畫面尺寸繪製
class BoundingBox {
  final double x, y, width, height;
  final double confidence;
  final String objectClass; // ML Kit 給的粗略分類,例如 "Home good"、"unknown"

  BoundingBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.confidence,
    required this.objectClass,
  });

  factory BoundingBox.fromJson(Map<String, dynamic> json) {
    return BoundingBox(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
      confidence: (json['confidence'] as num).toDouble(),
      objectClass: json['class'] as String? ?? 'unknown',
    );
  }

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'confidence': confidence,
        'class': objectClass,
      };
}

/// 藍牙掃描偵測到的裝置(來自 bluetooth_scan_service)
class BluetoothDeviceInfo {
  final String name;
  final String deviceId;
  final int rssi; // 訊號強度,數字越接近0代表越近
  final bool suspicious; // 裝置名稱是否命中可疑關鍵字

  BluetoothDeviceInfo({
    required this.name,
    required this.deviceId,
    required this.rssi,
    required this.suspicious,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'deviceId': deviceId,
        'rssi': rssi,
        'suspicious': suspicious,
      };
}

/// 區域網路掃描偵測到的裝置(來自 network_scan_service)
class NetworkDevice {
  final String ip;
  final List<int> openPorts;
  final bool looksLikeCamera;

  NetworkDevice({
    required this.ip,
    required this.openPorts,
    required this.looksLikeCamera,
  });

  Map<String, dynamic> toJson() => {
        'ip': ip,
        'openPorts': openPorts,
        'looksLikeCamera': looksLikeCamera,
      };
}

/// 反光候選點(來自 glint_detector,本機運算)
class GlintCandidate {
  final int x, y, radius;
  final double brightness;
  final double? flickerScore;

  GlintCandidate({
    required this.x,
    required this.y,
    required this.radius,
    required this.brightness,
    this.flickerScore,
  });

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'radius': radius,
        'brightness': brightness,
        'flickerScore': flickerScore,
      };
}

/// 一次完整掃描的彙整結果 —— 這就是工作二要的 .json,toJson() 直接輸出
/// 給後端的資料格式。結合兩種來源:
///   - glints: 本機反光偵測的結果
///   - boundingBoxes: 本機 ML Kit 物件偵測的結果(候選位置,語意判斷交給後端)
class DetectionSessionSummary {
  final List<GlintCandidate> glints;
  final List<BoundingBox> boundingBoxes;
  final int totalGlintCount;
  final int highRiskGlintCount;
  final double ambientBrightnessAtStart;
  final bool torchUsedDuringScan;
  final bool remoteYoloAvailable;
  final String? environmentContext;
  final String? screenshotBase64; // 掃描畫面截圖(JPEG, base64編碼),給後端LLM做多模態判斷用
  final List<NetworkDevice> networkDevices; // 同網段偵測到的可疑裝置(輔助佐證,非決定性)
  final List<BluetoothDeviceInfo> bluetoothDevices; // 附近藍牙裝置(輔助佐證,非決定性)
  final DateTime scanStartedAt;
  final DateTime scanEndedAt;

  DetectionSessionSummary({
    required this.glints,
    this.boundingBoxes = const [],
    required this.totalGlintCount,
    required this.highRiskGlintCount,
    required this.ambientBrightnessAtStart,
    required this.torchUsedDuringScan,
    this.remoteYoloAvailable = false,
    this.environmentContext,
    this.screenshotBase64,
    this.networkDevices = const [],
    this.bluetoothDevices = const [],
    required this.scanStartedAt,
    required this.scanEndedAt,
  });

  Map<String, dynamic> toJson() => {
        'glints': glints.map((g) => g.toJson()).toList(),
        'boundingBoxes': boundingBoxes.map((b) => b.toJson()).toList(),
        'totalGlintCount': totalGlintCount,
        'highRiskGlintCount': highRiskGlintCount,
        'ambientBrightnessAtStart': ambientBrightnessAtStart,
        'torchUsedDuringScan': torchUsedDuringScan,
        'remoteYoloAvailable': remoteYoloAvailable,
        'environmentContext': environmentContext,
        'screenshotBase64': screenshotBase64,
        'networkDevices': networkDevices.map((d) => d.toJson()).toList(),
        'bluetoothDevices': bluetoothDevices.map((d) => d.toJson()).toList(),
        'scanStartedAt': scanStartedAt.toIso8601String(),
        'scanEndedAt': scanEndedAt.toIso8601String(),
        'scanDurationMs': scanEndedAt.difference(scanStartedAt).inMilliseconds,
      };
}