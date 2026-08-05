import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../models/risk_marker_data.dart';
import 'scan_page.dart';
import 'ai_assistant_page.dart';

// 👈 獲取手機當前 GPS 位置的非同步函式
Future<LatLng?> _determinePosition() async {
  bool serviceEnabled;
  LocationPermission permission;

  // 1. 檢查手機 GPS 功能是否開啟
  serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    // 手機 GPS 未開啟，可引導使用者開啓
    return null;
  }

  // 2. 檢查權限狀態
  permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    // 向使用者請求權限
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      return null;
    }
  }

  if (permission == LocationPermission.deniedForever) {
    // 使用者永久拒絕授權，需手動到手機設定開啟
    return null;
  }

  // 3. 取得當前真實座標 (設定高精確度)
  Position position = await Geolocator.getCurrentPosition(
    desiredAccuracy: LocationAccuracy.high,
  );

  return LatLng(position.latitude, position.longitude);
}

class CaseMapPage extends StatefulWidget {
  const CaseMapPage({super.key});

  @override
  State<CaseMapPage> createState() => _CaseMapPageState();
}

class _CaseMapPageState extends State<CaseMapPage> {
  LatLng _currentPosition = const LatLng(25.0245, 121.5410); // 預設給一個座標

  @override
  void initState() {
    super.initState();
    _getUserLocation();
  }

  Future<void> _getUserLocation() async {
    LatLng? userLatLng = await _determinePosition();
    if (userLatLng != null) {
      setState(() {
        _currentPosition = userLatLng; // 👈 更新為手機實體 GPS 座標
      });
    }
  }
  final Color baseGreen = const Color(0xFF395938);

  bool _showHintCard = true;
  RiskMarkerData? _activeRiskMarker;
  bool _showBottomCard = false;

  final LatLng _ntuePosition = const LatLng(25.0263, 121.5435);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. 🗺️ 安全的單一 FlutterMap 元件（避免 GPU 重複初始化導致崩潰）
          FlutterMap(
            options: MapOptions(
              initialCenter: _ntuePosition,
              initialZoom: 15.5,
              maxZoom: 18.0,
              minZoom: 10.0,
            ),
            children: [
              // (1) 底層地圖圖資
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.app',
                maxZoom: 18,
                maxNativeZoom: 18,
              ),

              // (2) 🖤 黑色質感遮罩（位在地圖圖資之上、Marker圖層之下）
              IgnorePointer(
                child: Container(
                  color: Colors.black.withOpacity(0.12),
                ),
              ),

              // (3) 標記圖層（位在黑色遮罩之上，視覺最顯眼）
              MarkerLayer(
                markers: [
                  // 您的位置地標 (帶下方文字)
                  Marker(
                    point: const LatLng(25.0245, 121.5410),
                    width: 70,
                    height: 52,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.location_on,
                          color: baseGreen,
                          size: 30,
                        ),
                        Text(
                          '您的位置',
                          style: TextStyle(
                            color: baseGreen,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            shadows: const [
                              Shadow(
                                color: Colors.white,
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 高、中、低風險光暈圈 (74x74)
                  ...defaultRiskMarkers.map((riskData) {
                    return Marker(
                      point: riskData.position,
                      width: 74,
                      height: 74,
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _showHintCard = false;
                            _activeRiskMarker = riskData;
                            _showBottomCard = true;
                          });
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                riskData.riskColor.withOpacity(1.0),
                                riskData.riskColor.withOpacity(0.05),
                              ],
                              stops: const [0.3, 1.0],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ],
              ),
            ],
          ),

          // 2. 🟢 中央 Hint 操作提示卡片
          if (_showHintCard)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 78.0),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: baseGreen,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Hint:',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _showHintCard = false;
                              });
                            },
                            child: SizedBox(
                              width: 19,
                              height: 19,
                              child: Image.asset(
                                'assets/images/close.png',
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) {
                                  return const Icon(
                                    Icons.close,
                                    size: 19,
                                    color: Colors.white,
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '請使用手指放大縮小拖拽以瀏覽地圖，點擊可查看詳細資訊。',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          height: 1.5,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // 3. 底部固定導覽列
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 110,
            child: _buildBottomStaticNav(),
          ),

          // 4. 底部彈出內容卡片（蓋過導覽列，切齊底部）
          if (_showBottomCard && _activeRiskMarker != null)
            _buildBottomRiskCard(),
        ],
      ),
    );
  }

  // 底部風險卡片元件
  Widget _buildBottomRiskCard() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          left: 28,
          right: 28,
          top: 24,
          bottom: MediaQuery.of(context).padding.bottom + 28,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(28),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 16,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _activeRiskMarker!.title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _activeRiskMarker!.titleColor,
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _showBottomCard = false;
                    });
                  },
                  child: Icon(
                    Icons.close,
                    size: 22,
                    color: _activeRiskMarker!.titleColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              height: 1,
              color: _activeRiskMarker!.titleColor.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              _activeRiskMarker!.content,
              style: const TextStyle(
                fontSize: 15,
                height: 1.6,
                color: Color(0xFF49454F),
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 底部固定導覽列
  Widget _buildBottomStaticNav() {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF0EED3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          top: -20,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildStaticNavItem('assets/images/scan.png', '一鍵掃描', false, () {
                Navigator.pushReplacement(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, anim1, anim2) => const ScanPage(),
                    transitionDuration: Duration.zero,
                  ),
                );
              }),
              const SizedBox(width: 61.0),
              _buildStaticNavItem('assets/images/AI.png', 'AI助理', false, () {
                Navigator.pushReplacement(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, anim1, anim2) => const AIAssistantPage(),
                    transitionDuration: Duration.zero,
                  ),
                );
              }),
              const SizedBox(width: 61.0),
              _buildStaticNavItem('assets/images/map.png', '案件地圖', true, null),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStaticNavItem(String iconPath, String label, bool isSelected, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFF0EED3),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.18),
                        blurRadius: 8,
                        offset: const Offset(0, -4),
                      ),
                    ]
                  : [],
            ),
            child: Center(
              child: SizedBox(
                width: 54,
                height: 54,
                child: Image.asset(
                  iconPath,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: baseGreen,
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}