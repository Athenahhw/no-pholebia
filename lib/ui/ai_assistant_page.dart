import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'scan_page.dart';
import 'case_map_page.dart'; // 👈 引入案件地圖頁面

class AIAssistantPage extends StatefulWidget {
  const AIAssistantPage({super.key});

  @override
  State<AIAssistantPage> createState() => _AIAssistantPageState();
}

class _AIAssistantPageState extends State<AIAssistantPage> {
  final Color baseGreen = const Color(0xFF395938);
  final Color cardWhite = const Color(0xFFF7F2FA);
  final String _assistantEndpoint = const String.fromEnvironment(
    'ASSISTANT_ENDPOINT',
    defaultValue: 'http://192.168.1.13:8000/api/v1/assistant/query',
  );

  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _placeController = TextEditingController();
  final FocusNode _placeFocusNode = FocusNode();

  bool _showHistory = false;
  bool _showResults = false;
  bool _isLoading = false;
  String? _errorMessage;
  String _locationSummary = '';
  List<Map<String, String>> _cautionItems = [];
  List<String> _historyList = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _placeFocusNode.addListener(() {
      setState(() {
        _showHistory = _placeFocusNode.hasFocus && _historyList.isNotEmpty;
      });
    });
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _historyList = prefs.getStringList('place_history') ?? ['國立台北教育大學'];
    });
  }

  Future<void> _saveHistory(String newPlace) async {
    if (newPlace.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _historyList.remove(newPlace);
      _historyList.insert(0, newPlace);
      if (_historyList.length > 5) _historyList = _historyList.sublist(0, 5);
    });
    await prefs.setStringList('place_history', _historyList);
  }

  Future<void> _queryAssistant() async {
    final String destination = _placeController.text.trim().isEmpty
        ? '國立台北教育大學'
        : _placeController.text.trim();
    final String targetDate = _dateController.text.trim().isEmpty
        ? DateFormat('MM/dd/yyyy').format(DateTime.now())
        : _dateController.text.trim();

    setState(() {
      _showResults = true;
      _isLoading = true;
      _errorMessage = null;
      _locationSummary = '';
      _cautionItems = [];
    });

    try {
      final response = await http
          .post(
            Uri.parse(_assistantEndpoint),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'targetDate': targetDate,
              'destination': destination,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }

      final Map<String, dynamic> payload =
          jsonDecode(response.body) as Map<String, dynamic>;
      final Map<String, dynamic> data =
          (payload['data'] as Map?)?.cast<String, dynamic>() ?? payload;

      final cautionItemsRaw = data['caution_items'];
      final List<Map<String, String>> parsedCautionItems =
          cautionItemsRaw is List
          ? cautionItemsRaw
                .whereType<Map>()
                .map((item) {
                  final map = item.cast<String, dynamic>();
                  return {
                    'title': map['title']?.toString() ?? '',
                    'detail': map['detail']?.toString() ?? '',
                  };
                })
                .where(
                  (item) =>
                      item['title']!.isNotEmpty || item['detail']!.isNotEmpty,
                )
                .toList()
          : <Map<String, String>>[];

      if (!mounted) return;
      setState(() {
        _locationSummary =
            data['location_summary']?.toString() ?? '暫時沒有取得 AI 建議。';
        _cautionItems = parsedCautionItems;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '查詢失敗，請稍後再試。\n$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _deleteHistoryItem(String targetPlace) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _historyList.remove(targetPlace);
      if (_historyList.isEmpty) _showHistory = false;
    });
    await prefs.setStringList('place_history', _historyList);
  }

  Future<void> _selectDate() async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            dialogBackgroundColor: cardWhite,
            colorScheme: ColorScheme.light(
              primary: baseGreen,
              onPrimary: Colors.white,
              onSurface: baseGreen,
              surface: cardWhite,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _dateController.text = DateFormat('MM/dd/yyyy').format(picked);
      });
    }
  }

  @override
  void dispose() {
    _dateController.dispose();
    _placeController.dispose();
    _placeFocusNode.dispose();
    super.dispose();
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
          children: [
            // 1. 背景漸層
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFE1E0D6), Color(0xFFF0EEDC)],
                  ),
                ),
              ),
            ),

            // 2. 主要內容區
            SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: _showResults
                        ? _buildResultView()
                        : _buildInputView(),
                  ),
                  const SizedBox(height: 100), // 留空給底部導覽列
                ],
              ),
            ),

            // 3. 底部導覽列
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 110,
              child: _buildBottomStaticNav(),
            ),
          ],
        ),
      ),
    );
  }

  // --- 模式 A: 輸入介面 ---
  Widget _buildInputView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 60),
          _buildOutlinedInputField(
            label: 'Date',
            controller: _dateController,
            hintText: 'MM/DD/YYYY',
            suffixIcon: Icons.calendar_month_outlined,
            onTap: _selectDate,
            readOnly: true,
          ),
          const SizedBox(height: 24),
          _buildOutlinedInputField(
            label: 'Place',
            controller: _placeController,
            focusNode: _placeFocusNode,
            hintText: '',
            suffixIcon: Icons.location_on_outlined,
          ),
          if (_showHistory)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                color: cardWhite,
                border: Border.all(color: baseGreen, width: 1.5),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _historyList
                    .map((placeText) => _buildHistoryRow(placeText))
                    .toList(),
              ),
            ),
          const SizedBox(height: 20),
          Text(
            '輸入您的差旅行程，系統即刻為您提供安全建議！',
            style: TextStyle(
              fontSize: 14,
              color: baseGreen,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 36),
          Center(
            child: _buildSearchButton(
              onTap: () async {
                _saveHistory(_placeController.text);
                FocusScope.of(context).unfocus();
                await _queryAssistant();
              },
            ),
          ),
        ],
      ),
    );
  }

  // --- 模式 B: 查詢結果介面 ---
  Widget _buildResultView() {
    final String placeTitle = _placeController.text.isEmpty
        ? '國立台北教育大學'
        : _placeController.text;

    final List<Widget> resultChildren = [const SizedBox(height: 40)];

    if (_isLoading) {
      resultChildren.add(
        const Padding(
          padding: EdgeInsets.only(top: 80),
          child: CircularProgressIndicator(color: Color(0xFF395938)),
        ),
      );
    } else if (_errorMessage != null) {
      resultChildren.add(
        _buildInfoCard(
          title: '查詢失敗',
          titleColor: Colors.white,
          content: _errorMessage!,
          contentColor: Colors.white.withOpacity(0.9),
          isDark: true,
        ),
      );
    } else {
      resultChildren.addAll([
        // 卡片 1: 地點簡述 (動態寬度：離兩側 45px)
        _buildInfoCard(
          title: placeTitle,
          titleColor: baseGreen,
          content: _locationSummary.isEmpty
              ? '目前暫無可顯示的地點摘要。'
              : _locationSummary,
          contentColor: const Color(0xFF49454F),
          isDark: false,
        ),
        const SizedBox(height: 30),
        // 卡片 2: 應著重檢查物 (動態寬度：離兩側 45px)
        _buildInfoCard(
          title: '請著重檢查以下物品',
          titleColor: const Color(0xFFF0EEDC),
          content: _cautionItems.isEmpty
              ? '目前沒有取得具體檢查項目，請留意插座、掛勾、芳香劑與煙霧偵測器等常見遮蔽物。'
              : _cautionItems
                    .map((item) {
                      final title = item['title'] ?? '';
                      final detail = item['detail'] ?? '';
                      if (title.isEmpty) return detail;
                      if (detail.isEmpty) return title;
                      return '$title\n$detail';
                    })
                    .join('\n\n'),
          contentColor: Colors.white.withOpacity(0.9),
          isDark: true,
        ),
        const SizedBox(height: 20),
        Text(
          '祝您旅途愉快，No Pholebia 關心您。',
          style: TextStyle(color: baseGreen, fontSize: 14),
        ),
        const SizedBox(height: 30),

        // 精確 96 * 33 的返回按鈕
        _buildReturnButton(
          onTap: () => setState(() {
            _showResults = false;
            _errorMessage = null;
            _isLoading = false;
          }),
        ),
        const SizedBox(height: 60),
      ]);
    }

    return ShaderMask(
      shaderCallback: (Rect bounds) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black, Colors.black, Colors.transparent],
          stops: [0.0, 0.85, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: SingleChildScrollView(child: Column(children: resultChildren)),
    );
  }

  // --- 通用元件：卡片設計 (兩側離 45px，底線上移，字體與內文同大粗體) ---
  Widget _buildInfoCard({
    required String title,
    required Color titleColor,
    required String content,
    required Color contentColor,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 45.0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? baseGreen : cardWhite,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: titleColor,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              height: 1,
              color: isDark ? Colors.white30 : Colors.black12,
            ),
            const SizedBox(height: 20),
            Text(
              content,
              style: TextStyle(fontSize: 15, height: 1.5, color: contentColor),
            ),
          ],
        ),
      ),
    );
  }

  // --- 通用元件：立即查詢按鈕 ---
  Widget _buildSearchButton({required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 12),
        decoration: BoxDecoration(
          color: baseGreen,
          borderRadius: BorderRadius.circular(25),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text(
              '立即查詢',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- 通用元件：精確 96 * 33 的返回按鈕 ---
  Widget _buildReturnButton({required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 96,
        height: 33,
        decoration: BoxDecoration(
          color: baseGreen,
          borderRadius: BorderRadius.circular(16.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Image.asset(
                'assets/images/chevron_backward.png',
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(
                    Icons.arrow_back,
                    size: 18,
                    color: Colors.white,
                  );
                },
              ),
            ),
            const SizedBox(width: 4),
            const Text(
              '返回',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- 歷史紀錄與導覽列元件 ---
  Widget _buildHistoryRow(String text) {
    return InkWell(
      onTap: () {
        _placeController.text = text;
        _placeFocusNode.unfocus();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
        child: Row(
          children: [
            SizedBox(
              width: 23,
              height: 23,
              child: Image.asset(
                'assets/images/History.png',
                errorBuilder: (context, error, stackTrace) =>
                    Icon(Icons.history, size: 20, color: baseGreen),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(color: Color(0xFF49454F), fontSize: 16),
              ),
            ),
            GestureDetector(
              onTap: () => _deleteHistoryItem(text),
              child: const Icon(Icons.close, size: 18, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOutlinedInputField({
    required String label,
    required TextEditingController controller,
    required String hintText,
    required IconData suffixIcon,
    FocusNode? focusNode,
    VoidCallback? onTap,
    bool readOnly = false,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      onTap: onTap,
      readOnly: readOnly,
      style: TextStyle(color: baseGreen, fontSize: 18),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: baseGreen, fontWeight: FontWeight.bold),
        hintText: hintText,
        hintStyle: const TextStyle(color: Colors.grey),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        filled: true,
        fillColor: Colors.transparent,
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: baseGreen, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: baseGreen, width: 2.5),
          borderRadius: BorderRadius.circular(8),
        ),
        suffixIcon: Icon(suffixIcon, color: const Color(0xFF49454F)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
      ),
    );
  }

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
              // 1. 一鍵掃描
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

              // 2. AI 助理 (當前頁面)
              _buildStaticNavItem('assets/images/AI.png', 'AI助理', true, null),
              const SizedBox(width: 61.0),

              // 👈 3. 案件地圖 (增加點擊跳轉事件)
              _buildStaticNavItem('assets/images/map.png', '案件地圖', false, () {
                Navigator.pushReplacement(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, anim1, anim2) => const CaseMapPage(),
                    transitionDuration: Duration.zero, // 無縫切換
                  ),
                );
              }),
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
      behavior: HitTestBehavior.opaque, // 確保點擊範圍包含空白處
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
