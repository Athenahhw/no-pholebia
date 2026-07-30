import 'package:flutter/material.dart';
import 'result_page.dart';
import '../detection/scan_screen.dart';
import '../detection/detection_result.dart';

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> with SingleTickerProviderStateMixin {
  final Color baseGreen = const Color(0xFF395938);
  final Color lightBackground = const Color(0xFFF0EEDC);

  final TextEditingController _environmentController = TextEditingController();
  // 👈 1. 新增 FocusNode 用來監聽鍵盤是否收起 (失去焦點)
  final FocusNode _environmentFocusNode = FocusNode();

  // 👈 控制勾勾顯示的狀態
  bool _showCheckIcon = false;

  late AnimationController _animationController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    // 👈 2. 監聽 FocusNode 狀態：當鍵盤按掉 (hasPrimaryFocus == false) 且有文字時才顯示勾勾
    _environmentFocusNode.addListener(() {
      if (!_environmentFocusNode.hasFocus) {
        // 鍵盤收起了 (失去焦點)
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
    _environmentFocusNode.dispose(); // 👈 記得銷毀 FocusNode
    _animationController.dispose();
    super.dispose();
  }

  /// 把掃描結果轉換成 ResultPage 要的格式。
  /// 優先用後端AI回傳的結果;後端還沒接上/連線失敗時,
  /// 先用本機資料做一個簡單的保底判斷,讓整條流程demo時能跑得通。
  (RiskLevel, int) _buildResultFrom(
    DetectionSessionSummary summary,
    Map<String, dynamic>? backendResult,
  ) {
    if (backendResult != null && backendResult['riskLevel'] != null) {
      final level = backendResult['riskLevel'] == 'high' ? RiskLevel.high : RiskLevel.low;
      final score = (backendResult['riskPercentage'] as num?)?.toInt() ?? 0;
      return (level, score);
    }

    // 保底邏輯(後端未接上時使用):有可疑閃爍反光點或遠端YOLO抓到物件,就判定高風險
    final hasRisk = summary.highRiskGlintCount > 0 || summary.boundingBoxes.isNotEmpty;
    return (
      hasRisk ? RiskLevel.high : RiskLevel.low,
      hasRisk ? 70 : 5, // 暫定數字,等後端有真的分數再換掉
    );
  }

  /// 進入相機掃描畫面,掃完後導到結果頁。
  /// 中間logo按鈕跟底部「一鍵掃描」導覽按鈕共用這段邏輯。
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
                builder: (context) => ResultPage(
                  riskLevel: result.$1,
                  score: result.$2,
                ),
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
      // 👈 讓使用者點擊空白處也能自動按掉鍵盤並觸發驗證
      body: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus(); // 收起鍵盤
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 1. 背景
            Positioned.fill(
              child: Container(color: baseGreen),
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: AngularBackgroundPainter(
                  lightColor: lightBackground,
                ),
              ),
            ),

            // 2. 主要內容
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.only(
                  top: 54.0,
                  bottom: 34.0,
                ),
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
                              focusNode: _environmentFocusNode, // 👈 綁定 FocusNode
                              readOnly: false,
                              keyboardType: TextInputType.text,
                              textInputAction: TextInputAction.done,
                              style: const TextStyle(
                                color: Color(0xFF395938),
                                fontSize: 16,
                              ),
                              decoration: InputDecoration(
                                hintText: '例如：廁所',
                                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 15),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                border: InputBorder.none,

                                // 👈 只有在鍵盤收起 (_showCheckIcon == true) 時才顯示 Check.png
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
                                FocusScope.of(context).unfocus(); // 按完成收起鍵盤
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
                                        color: const Color(0xFFFFFEC3).withValues(
                                          alpha: (1.0 - _animationController.value).clamp(0.0, 1.0),
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
                        _buildNavItem(
                          icon: 'assets/images/scan.png',
                          label: '一鍵掃描',
                          isSelected: true,
                          onTap: () => _startScan(context),
                        ),
                        const SizedBox(width: 61.0),
                        _buildNavItem(
                          icon: 'assets/images/AI.png',
                          label: 'AI助理',
                          isSelected: false,
                          onTap: null, // TODO: 等AI助理頁面做好再接上
                        ),
                        const SizedBox(width: 61.0),
                        _buildNavItem(
                          icon: 'assets/images/map.png',
                          label: '案件地圖',
                          isSelected: false,
                          onTap: null, // TODO: 等案件地圖頁面做好再接上
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
              child: Image.asset(
                icon,
                fit: BoxFit.contain,
              ),
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