import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

// 👈 載入剛才建立的 Services
import '../services/location_service.dart';
import '../services/police_service.dart';

enum RiskLevel { low, medium, high }

class ResultPage extends StatefulWidget {
  final RiskLevel riskLevel;
  final int score;

  const ResultPage({
    super.key,
    this.riskLevel = RiskLevel.low,
    required this.score,
  });

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> {
  final GlobalKey _lineKey = GlobalKey();
  double _lineY = 0.0;

  late RiskLevel _currentRisk;
  late int _currentScore;

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
        _fetchNearestPolice(); // 進入如果是高風險，立刻抓警局
      }
    });
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
      // 1. 抓取手機目前 GPS 座標
      LatLng? userPos = await LocationService.getCurrentLocation();

      // 如果抓不到 GPS（例如測試器中或未給權限），給予預設台北市立圖書館/大安區座標
      userPos ??= const LatLng(25.0381, 121.5401);

      // 2. 算距離並找出最近的 1 間警局
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

  void _toggleNextRisk() {
    setState(() {
      if (_currentRisk == RiskLevel.low) {
        _currentRisk = RiskLevel.medium;
        _currentScore = 45;
      } else if (_currentRisk == RiskLevel.medium) {
        _currentRisk = RiskLevel.high;
        _currentScore = 88;
        _fetchNearestPolice(); // 切到高風險時觸發搜尋警局
      } else {
        _currentRisk = RiskLevel.low;
        _currentScore = 4;
      }
      _reportState = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateLineY());
    });
  }

  /// 📞 點擊電話號碼撥號
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

  // 報案敘述 Bottom Sheet
  void _showReportBottomSheet(BuildContext context) {
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
                                  width: 22,
                                  height: 22,
                                ),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    '請參考此報案敘述提供警方訊息',
                                    style: TextStyle(
                                      fontSize: 20,
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
                                    '你好，我要報案。\n'
                                    '我現在在國立臺北教育大學內，發現疑似遭人安裝針孔攝影機。\n\n'
                                    '・ 【具體位置】位於 [請補充實際場館與樓層等地點細節]。\n'
                                    '・ 【異常物體】門板上的一面常規塑膠掛鉤。\n'
                                    '・ 【異常細節】該掛鉤外殼雖為一般塑料，但上面的固定螺絲有明顯異常。其中一顆十字螺絲的中心深度與光線吸收率遠高於正常金屬螺絲，且經檢測含有異常訊號。\n'
                                    '・ 【推薦報案單位】${_nearestPolice?.name ?? '臺北市政府警察局大安分局敦化南路派出所'} (${_nearestPolice?.phone ?? '02-2772-0400'})',
                                    style: const TextStyle(
                                      fontSize: 20,
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
        : (isMedium ? 'assets/images/Alert triangle.png' : 'assets/images/Alert circle.png');

    const Color textContentColor = Color(0xFF49454F);
    const double contentWidth = 280.0;

    return Scaffold(
      body: Stack(
        children: [
          // 1. 動態背景
          Positioned.fill(
            child: CustomPaint(
              painter: RiskBackgroundPainter(
                lineY: _lineY,
                isHighRisk: isHigh,
              ),
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
                          child: GestureDetector(
                            onTap: _toggleNextRisk,
                            behavior: HitTestBehavior.opaque,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      titleText,
                                      style: TextStyle(
                                        fontSize: 32,
                                        color: themeColor,
                                        fontWeight: FontWeight.w900,
                                        height: 1.0,
                                      ),
                                    ),
                                    Image.asset(iconPath, width: 20, height: 20),
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
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: contentWidth,
                          height: 140,
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
                                  '$_currentScore%',
                                  style: TextStyle(
                                    fontSize: 48,
                                    color: themeColor,
                                    fontFamily: 'Jacques Francois',
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: contentWidth,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildListItem(isLow ? '未偵測到紅外線與反光點,' : '偵測到可疑藍芽與 Wi-Fi 訊號較強,', true, textContentColor),
                              _buildListItem(isLow ? '未偵測到藍芽與 Wi-Fi,' : '建議檢查周遭可疑插座或延長線,', true, textContentColor),
                              _buildListItem(isLow ? '未偵測到異常磁場,' : '未發現紅外線異常點,', true, textContentColor),
                              _buildListItem('綜合評估危險指數：$_currentScore%', false, textContentColor),
                              _buildListItem(isLow ? '您所在環境無隱藏針孔攝影機, 請安心使用。' : '環境存在潛在風險，請謹慎使用。', false, textContentColor),
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
                                child: GestureDetector(
                                  onTap: _toggleNextRisk,
                                  behavior: HitTestBehavior.opaque,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            titleText,
                                            style: TextStyle(
                                              fontSize: 32,
                                              color: themeColor,
                                              fontWeight: FontWeight.w900,
                                              height: 1.0,
                                            ),
                                          ),
                                          Image.asset(iconPath, width: 20, height: 20),
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
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: contentWidth,
                                height: 140,
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
                                        '$_currentScore%',
                                        style: TextStyle(
                                          fontSize: 48,
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
                            Image.asset('assets/images/chevron_backward.png', width: 24, height: 24),
                            const SizedBox(width: 4),
                            const Text('返回', style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w500)),
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

  // 高風險詳細內容 (動態渲染警局與電話)
  Widget _buildHighRiskContent(Color textColor) {
    // 📍 預設警局備案（抓取中或無資料時使用）
    final String policeName = _nearestPolice?.name ?? '臺北市政府警察局大安分局敦化南路派出所';
    final String policePhone = _nearestPolice?.phone ?? '02-2772-0400';
    final String policeDistance = _nearestPolice?.formattedDistance.isNotEmpty == true 
        ? ' (距離 ${_nearestPolice!.formattedDistance})' 
        : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '偵測到非對稱的幾何小黑孔與微光特徵，該掛鉤外殼雖為常規塑料，但其中一顆十字螺絲的中心深度與光線吸收率，遠高於正常金屬螺絲，疑似為「螺絲型微型鏡頭」之偽裝。\n綜合評估危險指數：88%\n\n請勿慌張或破壞犯罪現場，使用衛生紙或衣物遮蔽該處即可。',
          style: TextStyle(fontSize: 20, color: textColor, height: 1.45),
        ),
        const SizedBox(height: 20),

        // 證據圖
        Container(
          width: double.infinity,
          height: 180,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            image: const DecorationImage(
              image: AssetImage('assets/images/evidence.png'),
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(height: 25),

        // PDF 下載區
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: '已為您生成偵測報告，點按可下載PDF檔 ',
                style: TextStyle(fontSize: 20, color: textColor, height: 1.4),
              ),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Image.asset(
                  'assets/images/Download.png',
                  width: 20,
                  height: 20,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // 📍 警局與電話（動態渲染）
        Text(
          '附近有 $policeName$policeDistance，您可以考慮報案。\n電話：',
          style: TextStyle(fontSize: 20, color: textColor),
        ),
        GestureDetector(
          onTap: () => _makePhoneCall(policePhone),
          child: Text(
            policePhone,
            style: const TextStyle(
              fontSize: 20,
              color: Colors.blue,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
        const SizedBox(height: 30),

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
                  if (_reportState == 1) ...[
                    Image.asset('assets/images/Loader.png', width: 20, height: 20),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    _reportState == 2 ? '查看報案敘述' : '生成報案敘述',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500),
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
          if (showDot) const Text('・ ', style: TextStyle(fontSize: 20, color: Color(0xFF395938), fontWeight: FontWeight.bold)),
          if (!showDot) const SizedBox(width: 18),
          Expanded(child: Text(text, style: TextStyle(fontSize: 20, color: contentColor, height: 1.35))),
        ],
      ),
    );
  }
}

// ------------------------------------------------
// 背景畫筆
// ------------------------------------------------
class RiskBackgroundPainter extends CustomPainter {
  final double lineY;
  final bool isHighRisk;
  RiskBackgroundPainter({required this.lineY, required this.isHighRisk});

  @override
  void paint(Canvas canvas, Size size) {
    if (isHighRisk) {
      final paint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFE1E0D6), Color(0xFFF0EEDC)],
        ).createShader(Offset.zero & size);
      canvas.drawRect(Offset.zero & size, paint);
    } else {
      if (lineY <= 0) return;
      final Color leftColor = const Color(0xFFF5F5F5);
      final Color rightColor = const Color(0xFFF0EEDC);

      canvas.drawRect(Rect.fromLTWH(size.width * 0.5, lineY, size.width * 0.5, size.height - lineY), Paint()..color = rightColor);
      canvas.drawRect(Rect.fromLTWH(0, lineY, size.width * 0.5, size.height - lineY), Paint()..color = leftColor);

      final topRect = Rect.fromLTWH(0, 0, size.width, lineY);
      canvas.drawRect(topRect, Paint()..shader = LinearGradient(colors: [leftColor, rightColor]).createShader(topRect));
      canvas.save();
      canvas.drawRect(topRect, Paint()..color = Colors.white.withOpacity(0.4)..imageFilter = ImageFilter.blur(sigmaX: 10, sigmaY: 10));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(RiskBackgroundPainter oldDelegate) => oldDelegate.lineY != lineY || oldDelegate.isHighRisk != isHighRisk;
}

// 圓弧畫筆
class UniformGaugePainter extends CustomPainter {
  final int score;
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
  bool shouldRepaint(UniformGaugePainter oldDelegate) => oldDelegate.score != score || oldDelegate.color != color;
}