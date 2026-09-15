import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

// 載入 Services 與 Detection Models
import '../detection/detection_result.dart';
import '../services/location_service.dart';
import '../services/police_service.dart';
import 'high_risk_static_assets.dart';

enum RiskLevel { low, medium, high }

class ResultPage extends StatefulWidget {
  final RiskLevel riskLevel;
  final double score;
  final bool isBackendScore;
  final String? scoreSource;
  final DetectionSessionSummary? scanSummary;
  final Map<String, dynamic>? backendResult;

  const ResultPage({
    super.key,
    this.riskLevel = RiskLevel.low,
    required this.score,
    this.isBackendScore = false,
    this.scoreSource,
    this.scanSummary,
    this.backendResult,
  });

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> {
  final GlobalKey _lineKey = GlobalKey();
  double _lineY = 0.0;

  late RiskLevel _currentRisk;
  late double _currentScore;
  Uint8List? _selectedEvidenceImage;

  // 滑動面板控制器與當前頁面索引
  final PageController _pageController = PageController();
  int _currentCardIndex = 0;

  // 📍 儲存目前抓取到的最近警察局資料
  PoliceStation? _nearestPolice;
  bool _isLoadingPolice = false;

  @override
  void initState() {
    super.initState();
    _currentRisk = widget.riskLevel;
    _currentScore = widget.score;
    if (_isAdminDemoMode) {
      debugPrint('結果頁使用後門 override 分數，layout 與一般模式相同');
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateLineY();
      if (_currentRisk == RiskLevel.high) {
        _fetchNearestPolice();
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // 後門演示模式旗標，不要刪。介面與一般掃描結果共用同一套 layout。
  bool get _isAdminDemoMode => widget.scoreSource == 'backend_admin_override';

  bool get _shouldForceDemoHighRiskSignals =>
      _isAdminDemoMode && _currentRisk == RiskLevel.high;

  bool get _hasGlintEvidence =>
      _shouldForceDemoHighRiskSignals ||
      (widget.scanSummary?.glintScreenshotsBase64.isNotEmpty ?? false) ||
      (widget.scanSummary?.glints.isNotEmpty ?? false);

  void _updateLineY() {
    final renderBox = _lineKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      final position = renderBox.localToGlobal(Offset.zero);
      setState(() {
        _lineY = position.dy;
      });
    }
  }

  /// 📍 呼叫 LocationService 與 PoliceService 抓取最近警局
  Future<void> _fetchNearestPolice() async {
    if (_isLoadingPolice) return;
    setState(() {
      _isLoadingPolice = true;
    });

    try {
      LatLng? userPos;
      final scanLatitude = widget.scanSummary?.latitude;
      final scanLongitude = widget.scanSummary?.longitude;

      if (scanLatitude != null && scanLongitude != null) {
        userPos = LatLng(scanLatitude, scanLongitude);
      } else {
        userPos = await LocationService.getCurrentLocation();
      }

      userPos ??= const LatLng(25.0381, 121.5401);

      List<PoliceStation> nearestList = await PoliceService.getNearestStations(
        userLocation: userPos,
        count: 1,
      );

      if (nearestList.isNotEmpty && mounted) {
        setState(() {
          _nearestPolice = nearestList.first;
        });
      }
    } catch (e) {
      print('抓取最近警局失敗: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingPolice = false;
        });
      }
    }
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri launchUri = Uri(
      scheme: 'tel',
      path: phoneNumber.replaceAll('-', ''),
    );
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else {
      print('無法開啟撥號介面: $phoneNumber');
    }
  }

  void _handleReportAction() {
    _showReportBottomSheet(context);
  }

  String _buildFallbackPoliceReport() {
    final summary = widget.scanSummary;
    final suspiciousWifi = _getSuspiciousWifiDetails();
    final suspiciousBluetooth = _getSuspiciousBluetoothNames();
    final glintCount = summary?.highRiskGlintCount ?? widget.backendResult?['highRiskGlintCount'] ?? 0;
    final locationHint = summary?.environmentContext != null && summary!.environmentContext!.trim().isNotEmpty
      ? summary.environmentContext!
      : '目前掃描現場';

    final glintText = glintCount > 0
      ? '偵測到${glintCount}個異常反光點，位置需要進一步確認是否有小孔或鏡頭'
      : '偵測到異常光學反光，位置需要進一步確認';
    final wifiText = suspiciousWifi.isNotEmpty ? '，同時偵測到${suspiciousWifi.length}個可疑 Wi‑Fi 裝置' : '';
    final bluetoothText = suspiciousBluetooth.isNotEmpty ? '，以及${suspiciousBluetooth.length}個可疑藍芽裝置' : '';

    return '我在${locationHint}掃描時，偵測到${glintText}${wifiText}${bluetoothText}。這些影像與感測結果顯示現場可能存在可疑攝影裝置，請員警到場確認，並檢查是否安裝隱藏式針孔攝影機。';
  }

  String _getReportBody() {
    final aiSection = widget.backendResult?['ai_reasoning_and_actions'];
    if (aiSection is Map) {
      final policeCheatSheet = aiSection['police_cheat_sheet']?.toString() ??
          aiSection['policeCheatSheet']?.toString();
      if (policeCheatSheet != null && policeCheatSheet.trim().isNotEmpty) {
        return policeCheatSheet.trim();
      }
    }

    final directPoliceCheatSheet =
        widget.backendResult?['policeCheatSheet']?.toString() ??
        widget.backendResult?['police_cheat_sheet']?.toString();
    if (directPoliceCheatSheet != null && directPoliceCheatSheet.trim().isNotEmpty) {
      return directPoliceCheatSheet.trim();
    }

    return _buildFallbackPoliceReport();
  }

  void _showReportBottomSheet(BuildContext context) {
    final String reportBody = _getReportBody();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: DraggableScrollableSheet(
            initialChildSize: 0.65,
            minChildSize: 0.3,
            maxChildSize: 1.0,
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD3D3D3),
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Image.asset(
                                  'assets/images/Info.png',
                                  width: 20,
                                  height: 20,
                                  errorBuilder: (ctx, err, stack) => const Icon(
                                    Icons.info_outline,
                                    color: Color(0xFF395938),
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    '請參考此報案敘述提供警方訊息',
                                    style: TextStyle(
                                      fontSize: 18,
                                      color: Color(0xFF395938),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Expanded(
                              child: ShaderMask(
                                shaderCallback: (Rect bounds) {
                                  return const LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.black,
                                      Colors.black,
                                      Colors.transparent,
                                    ],
                                    stops: [0.0, 0.85, 1.0],
                                  ).createShader(bounds);
                                },
                                blendMode: BlendMode.dstIn,
                                child: SingleChildScrollView(
                                  controller: scrollController,
                                  child: Text(
                                    reportBody,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: Color(0xFF49454F),
                                      height: 1.45,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  String _formatScore(double score) {
    if ((score - score.roundToDouble()).abs() < 0.0001) {
      return score.toStringAsFixed(0);
    }
    return score.toStringAsFixed(1);
  }

  String _riskSummaryText() {
    final aiSection = widget.backendResult?['ai_reasoning_and_actions'];
    if (aiSection is Map) {
      final summary = aiSection['risk_assessment_summary']?.toString() ??
          aiSection['plausibility_reasoning']?.toString();
      if (summary != null && summary.trim().isNotEmpty) {
        return '${summary.trim()}\n\n請勿慌張或破壞犯罪現場，使用衛生紙或衣物遮蔽該處即可。';
      }
    }
    return '請依據下方證據與報案敘述資料進行判斷。';
  }

  List<String> _getSuspiciousWifiDetails() {
    final summary = widget.scanSummary;
    if (summary == null) return const [];

    return summary.networkDevices
        .where((device) => device.looksLikeCamera)
        .map((device) {
          final ports = device.openPorts.isNotEmpty
              ? '（通訊埠: ${device.openPorts.join(", ")}）'
              : '';
          return 'Wi‑Fi ${device.ip}$ports';
        })
        .toList();
  }

  List<String> _getSuspiciousBluetoothNames() {
    final summary = widget.scanSummary;
    if (summary == null) return const [];

    return summary.bluetoothDevices
        .where((device) => device.suspicious)
        .map((device) => device.name.trim().isNotEmpty ? device.name : '未命名藍芽裝置')
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final bool isLow = _currentRisk == RiskLevel.low;
    final bool isMedium = _currentRisk == RiskLevel.medium;
    final bool isHigh = _currentRisk == RiskLevel.high;
    final bool useDemoHighRiskLayout = isHigh && _isAdminDemoMode;

    final Color themeColor = isLow
        ? const Color(0xFF4583FF)
        : (isMedium ? const Color(0xFF395938) : const Color(0xFFFF33CC));

    final String titleText = isLow ? '低風險' : (isMedium ? '中風險' : '高風險');
    final String iconPath = isLow
        ? 'assets/images/Check.png'
        : (isMedium
              ? 'assets/images/Alert triangle.png'
              : 'assets/images/Alert circle.png');

    const Color textContentColor = Color(0xFF49454F);
    const double contentWidth = 280.0;

    final bool isPreviewing = _selectedEvidenceImage != null;

    return Scaffold(
      body: Stack(
        children: [
          // 1. 動態背景
          Positioned.fill(
            child: CustomPaint(
              painter: RiskBackgroundPainter(lineY: _lineY, isHighRisk: isHigh),
            ),
          ),

          // 2. 原本結果頁：在大圖預覽時暫時完全隱藏
          Opacity(
            opacity: isPreviewing ? 0.0 : 1.0,
            child: IgnorePointer(
              ignoring: isPreviewing,
              child: SafeArea(
                child: Stack(
                  children: [
                    // 低 / 中風險，並在 Demo 高風險時使用相同卡片式版型
                    if (!isHigh || useDemoHighRiskLayout)
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Spacer(flex: 2),
                            SizedBox(
                              width: contentWidth,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        titleText,
                                        style: TextStyle(
                                          fontSize: 26,
                                          color: themeColor,
                                          fontWeight: FontWeight.w900,
                                          height: 1.0,
                                        ),
                                      ),
                                      Image.asset(
                                        iconPath,
                                        width: 20,
                                        height: 20,
                                        errorBuilder: (ctx, err, stack) => Icon(
                                          isLow
                                              ? Icons.check_circle
                                              : Icons.warning_amber_rounded,
                                          color: themeColor,
                                          size: 20,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    key: _lineKey,
                                    height: 1.0,
                                    width: contentWidth,
                                    color: themeColor,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: contentWidth,
                              height: 130,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  CustomPaint(
                                    size: const Size(220, 110),
                                    painter: UniformGaugePainter(
                                      score: _currentScore,
                                      color: themeColor,
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 10,
                                    child: Text(
                                      '${_formatScore(_currentScore)}%',
                                      style: TextStyle(
                                        fontSize: 44,
                                        color: themeColor,
                                        fontFamily: 'Jacques Francois',
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),

                            // 📱 可滑動面板（寬度 280，5% 主題色底色）
                            _buildSwipeableDetectionCards(
                              contentWidth,
                              themeColor,
                              textContentColor,
                            ),

                            const SizedBox(height: 16),

                            if (useDemoHighRiskLayout) ...[
                              SizedBox(
                                width: contentWidth,
                                child: Center(
                                  child: GestureDetector(
                                    onTap: _handleReportAction,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF395938),
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                      child: const Text(
                                        '查看報案敘述',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                            ] else if (_hasGlintEvidence) ...[
                              SizedBox(
                                width: contentWidth,
                                child: _buildGlintEvidenceGallery(textContentColor),
                              ),
                              const SizedBox(height: 16),
                            ],

                            // 下方傳入文字列表
                            SizedBox(
                              width: contentWidth,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildListItem(
                                    '綜合評估危險指數：${_formatScore(_currentScore)}%',
                                    false,
                                    textContentColor,
                                  ),
                                  const SizedBox(height: 4),
                                  _buildListItem(
                                    isLow || useDemoHighRiskLayout
                                      ? (isLow
                                            ? '您所在環境無隱藏針孔攝影機，請安心使用。'
                                            : '環境存在潛在風險，請謹慎使用。')
                                      : '環境存在潛在風險，請謹慎使用。',
                                    false,
                                    textContentColor,
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(flex: 3),
                            const SizedBox(height: 80),
                          ],
                        ),
                      ),

                    // 高風險 (漸隱 + 滾動)
                    if (isHigh && !useDemoHighRiskLayout)
                      ShaderMask(
                        shaderCallback: (Rect bounds) {
                          return const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black,
                              Colors.black,
                              Colors.transparent,
                            ],
                            stops: [0.0, 0.82, 1.0],
                          ).createShader(bounds);
                        },
                        blendMode: BlendMode.dstIn,
                        child: Scrollbar(
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            child: Center(
                              child: Column(
                                children: [
                                  const SizedBox(height: 60),
                                  SizedBox(
                                    width: contentWidth,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              titleText,
                                              style: TextStyle(
                                                fontSize: 26,
                                                color: themeColor,
                                                fontWeight: FontWeight.w900,
                                                height: 1.0,
                                              ),
                                            ),
                                            Image.asset(
                                              iconPath,
                                              width: 20,
                                              height: 20,
                                              errorBuilder: (ctx, err, stack) =>
                                                  Icon(
                                                    Icons.error_outline,
                                                    color: themeColor,
                                                    size: 20,
                                                  ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Container(
                                          key: _lineKey,
                                          height: 1.0,
                                          width: contentWidth,
                                          color: themeColor,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  SizedBox(
                                    width: contentWidth,
                                    height: 130,
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        CustomPaint(
                                          size: const Size(220, 110),
                                          painter: UniformGaugePainter(
                                            score: _currentScore,
                                            color: themeColor,
                                          ),
                                        ),
                                        Positioned(
                                          bottom: 10,
                                          child: Text(
                                            '${_formatScore(_currentScore)}%',
                                            style: TextStyle(
                                              fontSize: 44,
                                              color: themeColor,
                                              fontFamily: 'Jacques Francois',
                                              fontWeight: FontWeight.w400,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  SizedBox(
                                    width: contentWidth,
                                    child: _buildHighRiskContent(
                                      textContentColor,
                                      themeColor,
                                      contentWidth,
                                    ),
                                  ),
                                  const SizedBox(height: 140),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                    // 返回按鈕
                    Positioned(
                      bottom: 50,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            width: 120,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFF395938),
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Image.asset(
                                  'assets/images/chevron_backward.png',
                                  width: 20,
                                  height: 20,
                                  errorBuilder: (ctx, err, stack) => const Icon(
                                    Icons.arrow_back_ios_new,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Text(
                                  '返回',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          if (isPreviewing) _buildEvidencePreviewOverlay(),
        ],
      ),
    );
  }

  // 📱 滑動面板 Widget（反光點 / WiFi / 藍芽）
  Widget _buildSwipeableDetectionCards(
    double width,
    Color themeColor,
    Color textColor,
  ) {
    final summary = widget.scanSummary;
    final backend = widget.backendResult;
    bool hasGlint = false;
    bool hasSuspiciousWifi = false;
    bool hasSuspiciousBle = false;

    if (_shouldForceDemoHighRiskSignals) {
      hasGlint = true;
      hasSuspiciousWifi = true;
      hasSuspiciousBle = true;
    } else {
      if (summary != null) {
        hasGlint = summary.highRiskGlintCount > 0 || summary.glints.isNotEmpty;
        hasSuspiciousWifi = summary.networkDevices.any((d) => d.looksLikeCamera);
        hasSuspiciousBle = summary.bluetoothDevices.any((d) => d.suspicious);
      }

      if (backend != null) {
        if (backend.containsKey('has_glint')) {
          hasGlint = backend['has_glint'] == true;
        }
        if (backend.containsKey('has_wifi_risk')) {
          hasSuspiciousWifi = backend['has_wifi_risk'] == true;
        }
        if (backend.containsKey('has_ble_risk')) {
          hasSuspiciousBle = backend['has_ble_risk'] == true;
        }
      }
    }

    final List<Map<String, dynamic>> cardsData = [
      {
        'title': '可疑反光點',
        'status': hasGlint ? '偵測到異常反光點' : '未偵測到可疑反光點',
        'icon': Icons.light_mode_outlined,
        'image': 'assets/images/reflection.png',
      },
      {
        'title': 'Wi-Fi 連線',
        'status': hasSuspiciousWifi ? '附近有可疑 WiFi' : '未偵測到可疑 WiFi',
        'icon': Icons.wifi,
        'image': 'assets/images/wifi.png',
      },
      {
        'title': '藍芽訊號',
        'status': hasSuspiciousBle ? '附近有可疑藍芽裝置' : '未偵測到可疑藍芽',
        'icon': Icons.bluetooth,
        'image': 'assets/images/bluetooth.png',
      },
    ];

    return Column(
      children: [
        // 圓角矩形容器（透明度 5%）
        Container(
          width: width,
          height: 80,
          decoration: BoxDecoration(
            color: themeColor.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
          ),
          child: PageView.builder(
            controller: _pageController,
            itemCount: cardsData.length,
            onPageChanged: (index) {
              setState(() {
                _currentCardIndex = index;
              });
            },
            itemBuilder: (context, index) {
              final card = cardsData[index];
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 12.0,
                ),
                child: Row(
                  children: [
                    // 左側圖片區塊（支援 Assets 與毀損 fallback 內建圖示）
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: Image.asset(
                        card['image'],
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(
                            card['icon'] as IconData,
                            size: 32,
                            color: themeColor,
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 14),
                    // 右側文字
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            card['title'] as String,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: themeColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            card['status'] as String,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),

        // 三個小圓點指示器
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (index) {
            final bool isSelected = _currentCardIndex == index;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: themeColor.withOpacity(isSelected ? 1.0 : 0.5),
              ),
            );
          }),
        ),
      ],
    );
  }

  // 高風險詳細內容
  Widget _buildHighRiskContent(Color textColor, Color themeColor, double contentWidth) {
    final String policeName = _nearestPolice?.name ?? '附近警察單位';
    final String policePhone = _nearestPolice?.phone ?? '110';
    final String policeDistance =
        _nearestPolice?.formattedDistance.isNotEmpty == true
        ? ' (距離 ${_nearestPolice!.formattedDistance})'
        : '';
    final suspiciousWifi = _getSuspiciousWifiDetails();
    final suspiciousBluetooth = _getSuspiciousBluetoothNames();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSwipeableDetectionCards(contentWidth, themeColor, textColor),
        const SizedBox(height: 20),
        Text(
          '綜合評估危險指數：${_formatScore(_currentScore)}%',
          style: TextStyle(
            fontSize: 16,
            color: textColor,
            fontWeight: FontWeight.w700,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _riskSummaryText(),
          style: TextStyle(fontSize: 16, color: textColor, height: 1.45),
        ),
        const SizedBox(height: 16),
        if (_hasGlintEvidence) ...[
          _buildGlintEvidenceGallery(textColor),
          const SizedBox(height: 20),
        ],
        if (suspiciousWifi.isNotEmpty || suspiciousBluetooth.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '可疑連線裝置',
            style: TextStyle(
              fontSize: 16,
              color: textColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          ...[
            for (final device in suspiciousWifi) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• $device',
                  style: TextStyle(fontSize: 15, color: textColor, height: 1.4),
                ),
              ),
            ],
            for (final device in suspiciousBluetooth) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• 藍芽 $device',
                  style: TextStyle(fontSize: 15, color: textColor, height: 1.4),
                ),
              ),
            ],
          ],
          const SizedBox(height: 20),
        ],
        Text(
          '附近有 $policeName$policeDistance，您可以考慮報案。\n電話：',
          style: TextStyle(fontSize: 16, color: textColor),
        ),
        GestureDetector(
          onTap: () => _makePhoneCall(policePhone),
          child: Text(
            policePhone,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.blue,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
        const SizedBox(height: 24),

        Center(
          child: GestureDetector(
            onTap: _handleReportAction,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF395938),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Text(
                '查看報案敘述',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGlintEvidenceGallery(Color textColor) {
    final liveBytes = <Uint8List>[];
    final summary = widget.scanSummary;
    if (summary != null) {
      for (final encoded in summary.glintScreenshotsBase64) {
        try {
          final normalized = encoded.contains(',') ? encoded.split(',').last : encoded;
          final bytes = base64Decode(normalized);
          if (bytes.isNotEmpty) {
            liveBytes.add(bytes);
          }
        } catch (_) {}
      }
    }

    final imageList = _shouldForceDemoHighRiskSignals
        ? <Uint8List>[]
        : (liveBytes.isNotEmpty
            ? liveBytes
            : List.generate(
                HighRiskStaticAssets.glintCrops.length,
                (index) => Uint8List(0),
              ));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '異常反光點截圖',
          style: TextStyle(
            fontSize: 16,
            color: textColor,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 112,
          child: _shouldForceDemoHighRiskSignals
              ? ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: 1,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedEvidenceImage = null;
                        });
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(
                          'assets/images/IMG_2381.jpeg',
                          width: 112,
                          height: 112,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              width: 112,
                              height: 112,
                              color: const Color(0xFFFF33CC).withOpacity(0.15),
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.warning_amber_rounded,
                                size: 40,
                                color: Color(0xFFFF33CC),
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  },
                )
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: imageList.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final imageBytes = imageList[index];
                    if (liveBytes.isNotEmpty) {
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedEvidenceImage = imageBytes;
                          });
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(
                            imageBytes,
                            width: 112,
                            height: 112,
                            fit: BoxFit.cover,
                          ),
                        ),
                      );
                    }

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedEvidenceImage = null;
                        });
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(
                          HighRiskStaticAssets.glintCrops[index],
                          width: 112,
                          height: 112,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            if (index != 0) return const SizedBox.shrink();
                            return Container(
                              width: 220,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '尚未截到反光點。之後可把 glint_crop_1.jpg 放到 assets/images/high_risk_static/',
                                style: TextStyle(fontSize: 13, color: textColor, height: 1.35),
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (_selectedEvidenceImage != null)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(),
            ),
          ),
      ],
    );
  }

  void _showImageViewer(Uint8List imageBytes) {
    setState(() {
      _selectedEvidenceImage = imageBytes;
    });
  }

  void _closeImageViewer() {
    setState(() {
      _selectedEvidenceImage = null;
    });
  }

  Widget _buildEvidencePreviewOverlay() {
    if (_selectedEvidenceImage == null) return const SizedBox.shrink();

    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.9),
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: IconButton(
                    onPressed: _closeImageViewer,
                    icon: const Icon(Icons.arrow_back, color: Colors.white, size: 30),
                    tooltip: '返回結果頁',
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.memory(
                        _selectedEvidenceImage!,
                        fit: BoxFit.contain,
                        width: MediaQuery.of(context).size.width * 0.9,
                        height: MediaQuery.of(context).size.height * 0.8,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 28),
                child: ElevatedButton.icon(
                  onPressed: _closeImageViewer,
                  icon: const Icon(Icons.close),
                  label: const Text('返回結果頁'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF395938),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListItem(String text, bool showDot, Color contentColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showDot)
            const Text(
              '・ ',
              style: TextStyle(
                fontSize: 16,
                color: Color(0xFF395938),
                fontWeight: FontWeight.bold,
              ),
            ),
          if (!showDot) const SizedBox(width: 14),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 16, color: contentColor, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------
// 背景畫筆（低、中、高皆採用上 F0EEDC 至下 E1E0D6 漸層）
// ------------------------------------------------
class RiskBackgroundPainter extends CustomPainter {
  final double lineY;
  final bool isHighRisk;
  RiskBackgroundPainter({required this.lineY, required this.isHighRisk});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFF0EEDC), Color(0xFFE1E0D6)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(RiskBackgroundPainter oldDelegate) =>
      oldDelegate.lineY != lineY || oldDelegate.isHighRisk != isHighRisk;
}

// 圓弧畫筆
class UniformGaugePainter extends CustomPainter {
  final double score;
  final Color color;
  UniformGaugePainter({required this.score, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.5, size.height);
    final radius = math.min(size.width * 0.5, size.height) - 10;

    final basePaint = Paint()
      ..color = color.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi,
      math.pi,
      false,
      basePaint,
    );

    final double sweepAngle = math.pi * (score / 100).clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi,
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(UniformGaugePainter oldDelegate) =>
      oldDelegate.score != score || oldDelegate.color != color;
}
