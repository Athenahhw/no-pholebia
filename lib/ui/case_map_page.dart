import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/risk_marker_data.dart';
import '../services/location_service.dart'; // 👈 匯入 LocationService
import 'scan_page.dart';
import 'ai_assistant_page.dart';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../risk/time_risk_service.dart'; // 👈 導入你的時間風險算式
import '../report/report_model.dart';
import '../report/report_dialog.dart';

class CaseMapPage extends StatefulWidget {
  const CaseMapPage({super.key});

  @override
  State<CaseMapPage> createState() => _CaseMapPageState();
}

class _CaseMapPageState extends State<CaseMapPage> {
  // 地圖控制器，用來動態移動地圖視角
  final MapController _mapController = MapController();

  // 預設位置 (國北教大附近)，抓到 GPS 後會自動更新
  LatLng _currentPosition = const LatLng(25.0263, 121.5435);
  bool _isLoadingLocation = true;

  final Color baseGreen = const Color(0xFF395938);

  bool _showHintCard = true;
  RiskMarkerData? _activeRiskMarker;
  bool _showBottomCard = false;

// 存放動態從 cases.json 產生的地圖標籤
  List<Marker> _jsonCaseMarkers = [];

// 存放使用者剛通報的即時地圖標籤
  List<Marker> _userReportMarkers = [];

  @override
  void initState() {
    super.initState();
    _getUserLocation();
    _loadCasesFromJson(); // 👈 頁面初始化時載入案件資料
  }

  /// 📍 獲取真實 GPS 座標並移動地圖
  Future<void> _getUserLocation() async {
    LatLng? userLatLng = await LocationService.getCurrentLocation();
    
    if (userLatLng != null && mounted) {
      setState(() {
        _currentPosition = userLatLng; // 👈 更新使用者的真實座標
        _isLoadingLocation = false;
      });

      // 將地圖中心平滑移動至使用者當前位置
      _mapController.move(_currentPosition, 16.0);
    } else if (mounted) {
      setState(() {
        _isLoadingLocation = false;
      });
    }
  }

  /// 讀取 assets/json/cases.json 並結合時間風險演算[cite: 4, 7]
  Future<void> _loadCasesFromJson() async {
    try {
      final String jsonString = await rootBundle.loadString('assets/json/cases.json');
      final List<dynamic> data = json.decode(jsonString);

      List<Marker> loadedMarkers = [];

      for (var item in data) {
        final double lat = (item['latitude'] as num).toDouble();
        final double lng = (item['longitude'] as num).toDouble();
        final String title = item['title'] ?? '未命名案件';
        final String location = item['location_name'] ?? '未知地點';
        final String endDate = item['end_date'] ?? '2026-01-01';

        // 💡 呼叫時間風險演算[cite: 4, 8]
        final double riskWeight = TimeRiskService.calculateTimeRiskWeight(endDate);
        final String riskLevel = TimeRiskService.getRiskLevelString(riskWeight);

        // 根據風險等級設定光暈顏色
        Color riskColor = Colors.red;
        if (riskLevel == 'MEDIUM') {
          riskColor = Colors.orange;
        } else if (riskLevel == 'LOW') {
          riskColor = Colors.amber;
        }

        loadedMarkers.add(
          Marker(
            point: LatLng(lat, lng),
            width: 74,
            height: 74,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _showHintCard = false;
                  // 點擊案件在地圖下方顯示精美卡片[cite: 2, 7]
                  _activeRiskMarker = RiskMarkerData(
                    position: LatLng(lat, lng),
                    riskColor: riskColor,
                    title: title,
                    titleColor: riskColor,
                    content: '地點：$location\n發生時間：$endDate\n風險加權值：${(riskWeight * 100).toInt()}% ($riskLevel)',
                  );
                  _showBottomCard = true;
                });
              },
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      riskColor.withOpacity(0.9),
                      riskColor.withOpacity(0.1),
                    ],
                    stops: const [0.3, 1.0],
                  ),
                ),
                child: const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 28),
              ),
            ),
          ),
        );
      }

      if (mounted) {
        setState(() {
          _jsonCaseMarkers = loadedMarkers;
        });
      }
    } catch (e) {
      print('載入 cases.json 失敗: $e');
    }
  }

  /// 將使用者舉報的地點，動態轉為紫色警示地標加到地圖上[cite: 2, 5]
  void _addUserReportToMap(UserReport report) {
    final newMarker = Marker(
      point: LatLng(report.latitude, report.longitude),
      width: 74,
      height: 74,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _showHintCard = false;
            // 點擊即時舉報地點時顯示的底欄資訊卡片[cite: 2, 7]
            _activeRiskMarker = RiskMarkerData(
              position: LatLng(report.latitude, report.longitude),
              riskColor: Colors.deepPurple, // 使用紫色區隔即時通報點
              title: '【使用者舉報】${report.title}',
              titleColor: Colors.deepPurple,
              content: '地點：${report.locationName}\n通報時間：${report.date}\n說明：${report.description}\n(狀態：待審核通報)',
            );
            _showBottomCard = true;
          });
        },
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                Colors.deepPurple.withOpacity(0.9),
                Colors.deepPurple.withOpacity(0.1),
              ],
              stops: const [0.3, 1.0],
            ),
          ),
          child: const Icon(Icons.report_problem_rounded, color: Colors.white, size: 28),
        ),
      ),
    );

    setState(() {
      _userReportMarkers.add(newMarker);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. 🗺️ FlutterMap 元件
          FlutterMap(
            mapController: _mapController, // 👈 綁定地圖控制器
            options: MapOptions(
              initialCenter: _currentPosition,
              initialZoom: 15.5,
              maxZoom: 18.0,
              minZoom: 10.0,
            ),
            children: [
              // (1) 底層地圖圖資
              TileLayer(
  // 台灣通用電子地圖（WMTS 規範，極速且在台灣完全不跳 403）
  urlTemplate: 'https://wmts.nlsc.gov.tw/wmts/EMAP/default/GoogleMapsCompatible/{z}/{y}/{x}',
  maxZoom: 20,
  maxNativeZoom: 19, // 支援原生放大到 19 級（看得到小巷與門牌）
  userAgentPackageName: 'dev.daphne.nopholebia.app',
),

              // (2) 🖤 黑色質感遮罩
              IgnorePointer(
                child: Container(
                  color: Colors.black.withOpacity(0.12),
                ),
              ),

              // (3) 標記圖層
              MarkerLayer(
                markers: [
                  // 📍 您的位置地標 (動態顯示 _currentPosition)
                  Marker(
                    point: _currentPosition,
                    width: 80,
                    height: 56,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.location_on,
                          color: baseGreen,
                          size: 32,
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
                  ..._jsonCaseMarkers,
                  ..._userReportMarkers,
                ],
              ),
            ],
          ),

          // 🎯 定位重置按鈕 (右下角定位小圖示)
          Positioned(
            right: 20,
            bottom: 130,
            child: FloatingActionButton(
              mini: true,
              backgroundColor: Colors.white,
              elevation: 4,
              onPressed: () {
                _mapController.move(_currentPosition, 16.0);
              },
              child: _isLoadingLocation
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: baseGreen,
                      ),
                    )
                  : Icon(Icons.my_location, color: baseGreen),
            ),
          ),

          Positioned(
            right: 20,
            bottom: 190,
            child: FloatingActionButton.extended(
              heroTag: 'report_btn',
              backgroundColor: Colors.redAccent,
              elevation: 4,
              icon: const Icon(Icons.add_location_alt_rounded, color: Colors.white),
              label: const Text('通報偷拍點', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              onPressed: () async {
                final result = await showDialog<UserReport>(
                  context: context,
                  builder: (ctx) => const ReportCaseDialog(),
                );

                if (result != null) {
                  _addUserReportToMap(result);
                }
              },
            ),
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

          // 4. 底部彈出內容卡片
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