import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/risk_marker_data.dart';
import '../services/location_service.dart';
import 'scan_page.dart';
import 'ai_assistant_page.dart';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../risk/time_risk_service.dart';
import 'package:http/http.dart' as http;

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

  // 存放動態從 cases.json 或後端取得的地圖標籤
  List<Marker> _jsonCaseMarkers = [];

  // API 基底位址，可由編譯參數覆寫
  final String _apiBase = const String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://192.168.1.13:8000',
  );

  @override
  void initState() {
    super.initState();
    _getUserLocation();
    _loadCasesFromJson();
  }

  /// 📍 獲取真實 GPS 座標並移動地圖
  Future<void> _getUserLocation() async {
    LatLng? userLatLng = await LocationService.getCurrentLocation();

    if (userLatLng != null && mounted) {
      setState(() {
        _currentPosition = userLatLng;
        _isLoadingLocation = false;
      });

      _mapController.move(_currentPosition, 16.0);
    } else if (mounted) {
      setState(() {
        _isLoadingLocation = false;
      });
    }
  }

  /// 根據風險等級返回中文名稱
  String _getRiskLevelChinese(String riskLevel) {
    switch (riskLevel) {
      case 'HIGH':
        return '高風險';
      case 'MEDIUM':
        return '中風險';
      case 'LOW':
        return '低風險';
      default:
        return '未知風險';
    }
  }

  /// 根據風險等級返回對應顏色
  Color _getRiskColor(String riskLevel) {
    switch (riskLevel) {
      case 'HIGH':
        return Color(0xFFE63946); // 高風險 - 深紅色
      case 'MEDIUM':
        return Color(0xFFFFA500); // 中風險 - 黃橘色
      case 'LOW':
        return Color(0xFF1E90FF); // 低風險 - 道奇藍
      default:
        return Colors.grey;
    }
  }

  /// 讀取後端已核准案件，若失敗則退回讀取 assets/json/cases.json
  Future<void> _loadCasesFromJson() async {
    List<Marker> loadedMarkers = [];

    // 1) 嘗試從後端抓取已核准案件
    try {
      final uri = Uri.parse(''
          '${_apiBase.replaceAll(RegExp(r"/+"), '')}/api/v1/records/approved-for-map'');
      final resp = await http.get(uri).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final Map<String, dynamic> body = json.decode(resp.body);
        final List<dynamic> cases = (body['cases'] as List<dynamic>?) ?? [];

        for (var item in cases) {
          try {
            // 優先使用原始 request 中的座標 (payload 使用 camelCase)
            final rawReq = (item['raw_request'] as Map?)?.cast<String, dynamic>() ?? {};
            final rawResp = (item['raw_response'] as Map?)?.cast<String, dynamic>() ?? {};

            final latVal = rawReq['latitude'] ?? rawReq['lat'] ?? item['latitude'];
            final lngVal = rawReq['longitude'] ?? rawReq['lng'] ?? item['longitude'];

            if (latVal == null || lngVal == null) continue; // 沒座標就略過

            final double lat = (latVal as num).toDouble();
            final double lng = (lngVal as num).toDouble();

            final String title = (item['environment_context'] as String?) ?? rawReq['environmentContext'] ?? '未命名案件';
            final String location = title;
            final String endDate = (item['created_at'] as String?) ?? item['createdAt'] ?? DateTime.now().toIso8601String();

            // 時間權重(沿用原本時間風險演算)
            final double riskWeight = TimeRiskService.calculateTimeRiskWeight(
              endDate,
            );
            String riskLevel = TimeRiskService.getRiskLevelString(riskWeight);

            // 若後端提供 risk_level, 以後端為準且轉為大寫
            final backendRisk = (item['risk_level'] as String?) ?? (rawResp['risk_level'] as String?) ?? (item['riskLevel'] as String?) ?? (rawResp['riskLevel'] as String?);
            if (backendRisk != null && backendRisk.trim().isNotEmpty) {
              riskLevel = backendRisk.toUpperCase();
            }

            final Color riskColor = _getRiskColor(riskLevel);

            loadedMarkers.add(
              Marker(
                point: LatLng(lat, lng),
                width: 74,
                height: 74,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _showHintCard = false;
                      _activeRiskMarker = RiskMarkerData(
                        position: LatLng(lat, lng),
                        riskColor: riskColor,
                        title: _getRiskLevelChinese(riskLevel),
                        titleColor: riskColor,
                        content: '地點：$location\n事件：$title\n發生時間：$endDate',
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
                  ),
                ),
              ),
            );
          } catch (e) {
            // 個別案件處理錯誤不應阻斷整體流程
            print('處理後端案件時發生錯誤: $e');
            continue;
          }
        }

        if (mounted) {
          setState(() {
            _jsonCaseMarkers = loadedMarkers;
          });
        }
        return;
      } else {
        print('從後端取得已核准案件失敗 (HTTP ${resp.statusCode})');
      }
    } catch (e) {
      print('從後端取得已核准案件失敗: $e');
    }

    // 2) 後端失敗 -> 回退使用內建 assets/json/cases.json
    try {
      final String jsonString = await rootBundle.loadString(
        'assets/json/cases.json',
      );
      final List<dynamic> data = json.decode(jsonString);

      for (var item in data) {
        final double lat = (item['latitude'] as num).toDouble();
        final double lng = (item['longitude'] as num).toDouble();
        final String title = item['title'] ?? '未命名案件';
        final String location = item['location_name'] ?? '未知地點';
        final String endDate = item['end_date'] ?? '2026-01-01';

        final double riskWeight = TimeRiskService.calculateTimeRiskWeight(
          endDate,
        );
        final String riskLevel = TimeRiskService.getRiskLevelString(riskWeight);

        final Color riskColor = _getRiskColor(riskLevel);

        loadedMarkers.add(
          Marker(
            point: LatLng(lat, lng),
            width: 74,
            height: 74,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _showHintCard = false;
                  _activeRiskMarker = RiskMarkerData(
                    position: LatLng(lat, lng),
                    riskColor: riskColor,
                    title: _getRiskLevelChinese(riskLevel),
                    titleColor: riskColor,
                    content: '地點：$location\n事件：$title\n發生時間：$endDate',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. 🗺️ FlutterMap 元件
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentPosition,
              initialZoom: 15.5,
              maxZoom: 18.0,
              minZoom: 10.0,
            ),
            children: [
              // (1) 底層地圖圖資
              TileLayer(
                urlTemplate:
                    'https://wmts.nlsc.gov.tw/wmts/EMAP/default/GoogleMapsCompatible/{z}/{y}/{x}',
                maxZoom: 20,
                maxNativeZoom: 19,
                userAgentPackageName: 'dev.daphne.nopholebia.app',
              ),

              // (2) 🖤 黑色質感遮罩
              IgnorePointer(
                child: Container(color: Colors.black.withOpacity(0.12)),
              ),

              // (3) 標記圖層
              MarkerLayer(
                markers: [
                  // 📍 您的位置地標
                  Marker(
                    point: _currentPosition,
                    width: 80,
                    height: 56,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.location_on, color: baseGreen, size: 32),
                        Text(
                          '您的位置',
                          style: TextStyle(
                            color: baseGreen,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            shadows: const [
                              Shadow(color: Colors.white, blurRadius: 4),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 高、中、低風險光暈圈
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
                ],
              ),
            ],
          ),

          // 🎯 定位重置按鈕
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
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
              children: [
                Expanded(
                  child: Text(
                    _activeRiskMarker!.title,
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _activeRiskMarker!.titleColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
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
                    pageBuilder: (context, anim1, anim2) =>
                        const AIAssistantPage(),
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

  Widget _buildStaticNavItem(
    String iconPath,
    String label,
    bool isSelected,
    VoidCallback? onTap,
  ) {
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
                child: Image.asset(iconPath, fit: BoxFit.contain),
              ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 72,
            child: Text(
              label,
              textAlign: TextAlign.center,
              softWrap: true,
              style: TextStyle(
                color: baseGreen,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
