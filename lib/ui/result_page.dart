import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

// 載入 Services 與 Detection Models
import '../detection/detection_result.dart';
import '../services/location_service.dart';
import '../services/police_service.dart';

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

  // 滑動面板控制器與當前頁面索引
  final PageController _pageController = PageController();
  int _currentCardIndex = 0;

  // 0 = 初始(生成報案敘述), 1 = 載入中(顯示 Loader 3秒), 2 = 已完成(查看報案敘述)
  int _reportState = 0;

  // 📍 儲存目前抓取到的最近警察局資料
  PoliceStation? _nearestPolice;
  bool _isLoadingPolice = false;

  @override
  void initState() {
    super.initState();
    _currentRisk = widget.riskLevel;
    _currentScore = widget.score;
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

  bool get _isAdminDemoMode => widget.scoreSource == 'backend_admin_override';

  String _demoSummaryForRisk() {
    switch (_currentRisk) {
      case RiskLevel.high:
        return '偵測到非對稱的幾何小黑孔與微光特徵，該掛鉤外殼雖為常規塑料，但其中一顆十字螺絲的中心深度與光線吸收率，遠高於正常金屬螺絲，疑似為「螺絲型微型鏡頭」之偽裝。\n綜合評估危險指數：${_formatScore(_currentScore)}%\n\n請勿慌張或破壞犯罪現場，使用衛生紙或衣物遮蔽該處即可。';
      case RiskLevel.medium:
        return '偵測到可疑的幾何反光與周邊訊號干擾，該區域存在中度風險，需要進一步檢查。\n綜合評估危險指數：${_formatScore(_currentScore)}%\n\n請先確認環境內的插座、掛勾、芳香劑與煙霧偵測器。';
      case RiskLevel.low:
        return '目前未見明顯異常光點與可疑訊號，整體環境相對正常。\n綜合評估危險指數：${_formatScore(_currentScore)}%\n\n仍建議在進入陌生環境前做基本巡查，保持隱私安全。';
    }
  }

  List<Map<String, String>> _demoCardsForRisk() {
    switch (_currentRisk) {
      case RiskLevel.high:
        return [
          {'title': '可疑反光點', 'status': '偵測到高風險反光特徵'},
          {'title': 'Wi-Fi 連線', 'status': '偵測到可疑無線訊號'},
          {'title': '藍芽訊號', 'status': '偵測到可疑藍芽裝置'},
        ];
      case RiskLevel.medium:
        return [
          {'title': '可疑反光點', 'status': '出現中度異常反光'},
          {'title': 'Wi-Fi 連線', 'status': '附近有可疑 Wi-Fi 活動'},
          {'title': '藍芽訊號', 'status': '附近有可疑藍芽裝置'},
        ];
      case RiskLevel.low:
        return [
          {'title': '可疑反光點', 'status': '未偵測到可疑反光點'},
          {'title': 'Wi-Fi 連線', 'status': '未偵測到可疑 Wi-Fi'},
          {'title': '藍芽訊號', 'status': '未偵測到可疑藍芽'},
        ];
    }
  }

  List<Map<String, dynamic>> _riskChecklistEntries() {
    switch (_currentRisk) {
      case RiskLevel.high:
        return [
          {'text': '偵測到高風險異常訊號，請立即遮蔽可疑位置。', 'showDot': true},
          {'text': '優先檢查插座、掛勾、煙霧偵測器與延長線。', 'showDot': true},
          {'text': '保持現場完整，避免直接破壞可疑物。', 'showDot': true},
          {'text': '若需要，直接按下生成報案敘述。', 'showDot': false},
        ];
      case RiskLevel.medium:
        return [
          {'text': '偵測到中風險異常訊號，請先觀察周遭環境。', 'showDot': true},
          {'text': '優先檢查可疑插座、掛勾與遮蔽物。', 'showDot': true},
          {'text': '若有異常，先完成遮蔽再離開現場。', 'showDot': true},
          {'text': '必要時聯絡管理單位或警局。', 'showDot': false},
        ];
      case RiskLevel.low:
        return [
          {'text': '目前風險偏低，但仍建議留意周遭環境。', 'showDot': true},
          {'text': '進入陌生空間前可快速巡視插座與掛勾。', 'showDot': true},
          {'text': '若再發現異常，可重新啟動掃描。', 'showDot': true},
          {'text': '維持基本隱私保護即可。', 'showDot': false},
        ];
    }
  }

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
    if (_reportState == 0) {
      setState(() {
        _reportState = 1;
      });

      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _reportState = 2;
          });
        }
      });
    } else if (_reportState == 2) {
      _showReportBottomSheet(context);
    }
  }

  void _showReportBottomSheet(BuildContext context) {
    final String? policeCheatSheet =
        widget.backendResult?['policeCheatSheet']?.toString() ??
        widget.backendResult?['police_cheat_sheet']?.toString();
    final String reportBody =
        (policeCheatSheet != null && policeCheatSheet.trim().isNotEmpty)
        ? policeCheatSheet.trim()
        : '你好，我要報案。\n'
              '我現在在國立臺北教育大學內，發現疑似遭人安裝針孔攝影機。\n\n'
              '・ 【具體位置】位於 [請補充實際場館與樓層等地點細節]。\n'
              '・ 【異常物體】門板上的一面常規塑膠掛鉤。\n'
              '・ 【異常細節】該掛鉤外殼雖為一般塑料，但上面的固定螺絲有明顯異常。其中一顆十字螺絲的中心深度與光線吸收率遠高於正常金屬螺絲，且經檢測含有異常訊號。';

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
    if (_isAdminDemoMode) {
      return _demoSummaryForRisk();
    }

    final aiSection = widget.backendResult?['ai_reasoning_and_actions'];
    if (aiSection is Map) {
      final summary = aiSection['risk_assessment_summary']?.toString();
      if (summary != null && summary.trim().isNotEmpty) {
        return '${summary.trim()}\n綜合評估危險指數：${_formatScore(_currentScore)}%\n\n請勿慌張或破壞犯罪現場，使用衛生紙或衣物遮蔽該處即可。';
      }
    }
    return '偵測到非對稱的幾何小黑孔與微光特徵，該掛鉤外殼雖為常規塑料，但其中一顆十字螺絲的中心深度與光線吸收率，遠高於正常金屬螺絲，疑似為「螺絲型微型鏡頭」之偽裝。\n綜合評估危險指數：${_formatScore(_currentScore)}%\n\n請勿慌張或破壞犯罪現場，使用衛生紙或衣物遮蔽該處即可。';
  }

  @override
  Widget build(BuildContext context) {
    final bool isLow = _currentRisk == RiskLevel.low;
    final bool isMedium = _currentRisk == RiskLevel.medium;
    final bool isHigh = _currentRisk == RiskLevel.high;

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

    return Scaffold(
      body: Stack(
        children: [
          // 1. 動態背景
          Positioned.fill(
            child: CustomPaint(
              painter: RiskBackgroundPainter(lineY: _lineY, isHighRisk: isHigh),
            ),
          ),

          // 2. 主要內容
          SafeArea(
            child: Stack(
              children: [
                // 低 / 中風險
                if (!isHigh)
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

                        // 下方傳入文字列表
                        SizedBox(
                          width: contentWidth,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildListItem(
                                isLow ? '未偵測到紅外線與反光點,' : '偵測到可疑藍芽與 Wi-Fi 訊號較強,',
                                true,
                                textContentColor,
                              ),
                              _buildListItem(
                                isLow ? '未偵測到藍芽與 Wi-Fi,' : '建議檢查周遭可疑插座或延長線,',
                                true,
                                textContentColor,
                              ),
                              _buildListItem(
                                isLow ? '未偵測到異常磁場,' : '未發現紅外線異常點,',
                                true,
                                textContentColor,
                              ),
                              _buildListItem(
                                '綜合評估危險指數：${_currentScore.toStringAsFixed(2)}%',
                                false,
                                textContentColor,
                              ),
                              _buildListItem(
                                isLow
                                    ? '您所在環境無隱藏針孔攝影機, 請安心使用。'
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
                if (isHigh)
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
                                child: _buildHighRiskContent(textContentColor),
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
    if (_isAdminDemoMode) {
      final cardsData = _demoCardsForRisk();
      return Column(
        children: [
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
                      SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(
                          index == 0
                              ? Icons.light_mode_outlined
                              : index == 1
                              ? Icons.wifi
                              : Icons.bluetooth,
                          size: 32,
                          color: themeColor,
                        ),
                      ),
                      const SizedBox(width: 14),
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

    final summary = widget.scanSummary;
    final bool hasGlint =
        (summary != null &&
            (summary.highRiskGlintCount > 0 || summary.glints.isNotEmpty)) ||
        (_currentRisk == RiskLevel.medium);
    final bool hasSuspiciousWifi =
        (summary != null &&
            summary.networkDevices.any((d) => d.looksLikeCamera)) ||
        (_currentRisk == RiskLevel.medium);
    final bool hasSuspiciousBle =
        (summary != null &&
            summary.bluetoothDevices.any((d) => d.suspicious)) ||
        (_currentRisk == RiskLevel.medium);

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
  Widget _buildHighRiskContent(Color textColor) {
    if (_isAdminDemoMode) {
      final PoliceStation? policeStation = _nearestPolice;
      final String policeName = policeStation?.name ?? '附近警察單位';
      final String policePhone = policeStation?.phone ?? '110';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _demoSummaryForRisk(),
            style: TextStyle(fontSize: 16, color: textColor, height: 1.45),
          ),
          const SizedBox(height: 20),
          Text(
            '已根據目前偵測結果生成對應內容。',
            style: TextStyle(fontSize: 16, color: textColor, height: 1.35),
          ),
          const SizedBox(height: 16),
          ..._riskChecklistEntries().map(
            (entry) => _buildListItem(
              entry['text'] as String,
              entry['showDot'] as bool,
              textColor,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '附近有 $policeName，您可以考慮報案。\n電話：',
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF395938),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '生成報案敘述',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    final String policeName = _nearestPolice?.name ?? '附近警察單位';
    final String policePhone = _nearestPolice?.phone ?? '110';
    final String policeDistance =
        _nearestPolice?.formattedDistance.isNotEmpty == true
        ? ' (距離 ${_nearestPolice!.formattedDistance})'
        : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _riskSummaryText(),
          style: TextStyle(fontSize: 16, color: textColor, height: 1.45),
        ),
        const SizedBox(height: 16),

        const SizedBox(height: 20),

        // 📍 警局與電話
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

        // 報案按鈕
        Center(
          child: GestureDetector(
            onTap: _handleReportAction,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF395938),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _reportState == 2 ? '查看報案敘述' : '生成報案敘述',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
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
