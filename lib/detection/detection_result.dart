class BoundingBox {
  final double x, y, width, height;
  final double confidence;
  final String objectClass;

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

class BluetoothDeviceInfo {
  final String name;
  final String deviceId;
  final int rssi;
  final bool suspicious;

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

class DetectionSessionSummary {
  final List<GlintCandidate> glints;
  final List<BoundingBox> boundingBoxes;
  final int totalGlintCount;
  final int highRiskGlintCount;
  final double ambientBrightnessAtStart;
  final bool torchUsedDuringScan;
  final bool remoteYoloAvailable;
  final String? environmentContext;
  final String? screenshotBase64;
  final List<NetworkDevice> networkDevices;
  final List<BluetoothDeviceInfo> bluetoothDevices;
  final double? latitude; // 新增:掃描當下的GPS緯度,可能是null(定位失敗/被拒絕權限)
  final double? longitude; // 新增:掃描當下的GPS經度
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
    this.latitude,
    this.longitude,
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
    'latitude': latitude,
    'longitude': longitude,
    'scanStartedAt': scanStartedAt.toIso8601String(),
    'scanEndedAt': scanEndedAt.toIso8601String(),
    'scanDurationMs': scanEndedAt.difference(scanStartedAt).inMilliseconds,
  };
}
