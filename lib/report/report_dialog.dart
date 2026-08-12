// lib/report/report_dialog.dart

import 'package:flutter/material.dart';
import 'report_model.dart'; // 導入 UserReport 模型

class ReportCaseDialog extends StatefulWidget {
  const ReportCaseDialog({super.key});

  @override
  State<ReportCaseDialog> createState() => _ReportCaseDialogState();
}

class _ReportCaseDialogState extends State<ReportCaseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _locationController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _selectedCategory = '公廁/洗手間';

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('通報可疑/偷拍地點', style: TextStyle(fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: '事件標題',
                  hintText: '例：某公廁發現可疑螺絲孔',
                ),
                validator: (val) => val == null || val.isEmpty ? '請輸入標題' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _locationController,
                decoration: const InputDecoration(
                  labelText: '詳細地點/地址',
                  hintText: '例：國北教篤行樓3樓女廁',
                ),
                validator: (val) => val == null || val.isEmpty ? '請輸入地點' : null,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                decoration: const InputDecoration(labelText: '場域類型'),
                items: ['公廁/洗手間', '旅館/民宿', '醫療/診所', '學校', '其他']
                    .map((cat) => DropdownMenuItem(value: cat, child: Text(cat)))
                    .toList(),
                onChanged: (val) => setState(() => _selectedCategory = val!),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descriptionController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '可疑狀況描述',
                  hintText: '例：蓮蓬頭上方有金屬反光',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF395938)),
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              // 1. 建立通報物件
              final newReport = UserReport(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                title: _titleController.text,
                locationName: _locationController.text,
                latitude: 25.0263, // 可帶入預設/GPS座標
                longitude: 121.5435,
                date: DateTime.now().toString().split(' ')[0], // 今天日期 (YYYY-MM-DD)
                description: _descriptionController.text,
                category: _selectedCategory,
                verified: false,
              );

              // 2. 顯示提示並回傳給地圖頁面
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('通報成功！地點已即時新增至您的地圖。')),
              );

              Navigator.pop(context, newReport);
            }
          },
          child: const Text('提交通報', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}