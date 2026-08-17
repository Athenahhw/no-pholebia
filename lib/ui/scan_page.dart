import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'result_page.dart';
import 'ai_assistant_page.dart';
import 'case_map_page.dart';
import '../detection/scan_screen.dart';
import '../detection/detection_result.dart';

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage>
    with SingleTickerProviderStateMixin {
  final Color baseGreen = const Color(0xFF395938);
  final Color lightBackground = const Color(0xFFF0EEDC);

  final TextEditingController _environmentController = TextEditingController();
  final FocusNode _environmentFocusNode = FocusNode();

  bool _showCheckIcon = false;

  late AnimationController _animationController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _environmentFocusNode.addListener(() {
      if (!_environmentFocusNode.hasFocus) {
        setState(() {
          _showCheckIcon = _environmentController.text.trim().isNotEmpty;
        });
      }
    });

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 290 / 260).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _animationController.repeat();
  }

  @override
  void dispose() {
    _environmentController.dispose();
    _environmentFocusNode.dispose();
    _animationController.dispose();
    super.dispose();
  }

  double _environmentMultiplier(String? environmentContext) {
    final normalized = (environmentContext ?? '').trim().toLowerCase();

    final highPrivacyKeywords = [
      '廁',
      '洗手間',
      '便所',
      '試衣',
      '更衣',
      '淋浴',
      '浴室',
      '湯屋',
      'restroom',
      'bathroom',
      'fitting',
      'wc',
      'changing',
    ];

    final mediumPrivacyKeywords = [
      '飯店',
      '旅館',
      '民宿',
      '房間',
      '臥室',
      '套房',
      'ktv',
      '包廂',
      '按摩',
      'hotel',
      'room',
      'airbnb',
      'suite',
    ];

    final lowPrivacyKeywords = [
      '辦公',
      '會議',
      '教室',
      '圖書館',
      '大廳',
      '咖啡廳',
      '辦公室',
      'office',
      'meeting',
      'classroom',
      'library',
      'cafe',
    ];

    if (highPrivacyKeywords.any(normalized.contains)) return 1.4;
    if (mediumPrivacyKeywords.any(normalized.contains)) return 1.1;
    if (lowPrivacyKeywords.any(normalized.contains)) return 0.7;
    return 1.0;
  }

  (RiskLevel, int) _buildResultFrom(
    DetectionSessionSummary summary,
    Map<String, dynamic>? backendResult,
  ) {
    if (backendResult != null && backendResult['riskLevel'] != null) {
      final riskLevelRaw = backendResult['riskLevel'].toString().toLowerCase();
      final level = switch (riskLevelRaw) {
        'high' => RiskLevel.high,
        'medium' => RiskLevel.medium,
        _ => RiskLevel.low,
      };
      final score = ((backendResult['riskPercentage'] as num?)?.round() ?? 0)
          .clamp(0, 35);
      return (level, score);
    }

    // 與 backend/tms_engine.py 保持一致的本地估算公式。
    // 只有明確疑似攝影機 / 可疑藍牙才算高風險，避免家裡普通 Wi‑Fi 或藍牙設備被誤判。
    final wifiDetected = summary.networkDevices.any((d) => d.looksLikeCamera);
    final bluetoothDetected = summary.bluetoothDevices.any((d) => d.suspicious);
    final opticalGlintScore = (summary.highRiskGlintCount * 0.5).clamp(
      0.0,
      1.0,
    );

    const wifiWeight = 4.0;
    const bluetoothWeight = 3.5;
    const glintWeight = 2.5;
    const bias = -2.5;

    final rawScore =
        (wifiDetected ? wifiWeight : 0.0) +
        (bluetoothDetected ? bluetoothWeight : 0.0) +
        (opticalGlintScore * glintWeight) +
        bias;

    final adjustedScore =
        rawScore * _environmentMultiplier(summary.environmentContext);
    final probability = 1 / (1 + math.exp(-adjustedScore));
    final score = (probability * 100).round().clamp(0, 35);

    final level = score >= 20
        ? RiskLevel.high
        : score >= 8
        ? RiskLevel.medium
        : RiskLevel.low;

    return (level, score);
  }

  void _startScan(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ScanScreen(
          environmentContext: _environmentController.text.trim().isEmpty
              ? null
              : _environmentController.text.trim(),
          onScanComplete: (summary, backendResult) {
            final result = _buildResultFrom(summary, backendResult);
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    ResultPage(riskLevel: result.$1, score: result.$2),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 1. 背景
            Positioned.fill(child: Container(color: baseGreen)),
            Positioned.fill(
              child: CustomPaint(
                painter: AngularBackgroundPainter(lightColor: lightBackground),
              ),
            ),

            // 2. 主要內容
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.only(top: 54.0, bottom: 34.0),
                child: Column(
                  children: [
                    const SizedBox(height: 85),

                    // [元件 A] 頂部輸入框區塊
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '請輸入您所在環境',
                            style: TextStyle(
                              fontSize: 16,
                              color: Color(0xFF395938),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: TextField(
                              controller: _environmentController,
                              focusNode: _environmentFocusNode,
                              readOnly: false,
                              keyboardType: TextInputType.text,
                              textInputAction: TextInputAction.done,
                              style: const TextStyle(
                                color: Color(0xFF395938),
                                fontSize: 16,
                              ),
                              decoration: InputDecoration(
                                hintText: '例如：廁所',
                                hintStyle: TextStyle(
                                  color: Colors.grey.shade400,
                                  fontSize: 15,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                border: InputBorder.none,
                                suffixIcon: _showCheckIcon
                                    ? Padding(
                                        padding: const EdgeInsets.all(12.0),
                                        child: Image.asset(
                                          'assets/images/Check.png',
                                          width: 20,
                                          height: 20,
                                        ),
                                      )
                                    : null,
                              ),
                              onSubmitted: (value) {
                                FocusScope.of(context).unfocus();
                              },
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Spacer(),

                    // [元件 B] 中間按鈕與靜態文案
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 260,
                          height: 260,
                          child: Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.center,
                            children: [
                              AnimatedBuilder(
                                animation: _pulseAnimation,
                                builder: (context, child) {
                                  return Container(
                                    width: 260 * _pulseAnimation.value,
                                    height: 260 * _pulseAnimation.value,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: const Color(0xFFFFFEC3)
                                            .withValues(
                                              alpha:
                                                  (1.0 -
                                                          _animationController
                                                              .value)
                                                      .clamp(0.0, 1.0),
                                            ),
                                        width: 1.5,
                                      ),
                                    ),
                                  );
                                },
                              ),
                              GestureDetector(
                                onTap: () => _startScan(context),
                                child: SizedBox(
                                  width: 260,
                                  height: 260,
                                  child: Image.asset(
                                    'assets/images/logo.png',
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        const Text(
                          '”按下按鈕，開始偵測”',
                          style: TextStyle(
                            color: Color(0xFFF0EED3),
                            fontSize: 20,
                            letterSpacing: 1.2,
                            fontFamily: 'Jacques Francois',
                          ),
                        ),
                      ],
                    ),

                    const Spacer(),
                    const SizedBox(height: 110),
                  ],
                ),
              ),
            ),

            // 3. 底部導覽列
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 110,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.topCenter,
                children: [
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0EED3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
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
                        // 一鍵掃描 (當前頁面)
                        _buildNavItem(
                          icon: 'assets/images/scan.png',
                          label: '一鍵掃描',
                          isSelected: true,
                          onTap: () => _startScan(context),
                        ),
                        const SizedBox(width: 61.0),

                        // AI 助理
                        _buildNavItem(
                          icon: 'assets/images/AI.png',
                          label: 'AI助理',
                          isSelected: false,
                          onTap: () {
                            Navigator.pushReplacement(
                              context,
                              PageRouteBuilder(
                                pageBuilder: (context, anim1, anim2) =>
                                    const AIAssistantPage(),
                                transitionDuration: Duration.zero,
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 61.0),

                        // 案件地圖
                        _buildNavItem(
                          icon: 'assets/images/map.png',
                          label: '案件地圖',
                          isSelected: false,
                          onTap: () {
                            Navigator.pushReplacement(
                              context,
                              PageRouteBuilder(
                                pageBuilder: (context, anim1, anim2) =>
                                    const CaseMapPage(),
                                transitionDuration: Duration.zero,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required String icon,
    required String label,
    required bool isSelected,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
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
                        color: Colors.black.withValues(alpha: 0.18),
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
                child: Image.asset(icon, fit: BoxFit.contain),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: const Color(0xFF395938),
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

class AngularBackgroundPainter extends CustomPainter {
  final Color lightColor;

  AngularBackgroundPainter({required this.lightColor});

  @override
  void paint(Canvas canvas, Size size) {
    final double centerY = size.height * 0.5;

    final pathLight = Path();
    pathLight.moveTo(0, 0);
    pathLight.lineTo(0, centerY - 40);
    pathLight.lineTo(size.width, centerY + 50);
    pathLight.lineTo(size.width, 0);
    pathLight.close();
    canvas.drawPath(pathLight, Paint()..color = lightColor);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
