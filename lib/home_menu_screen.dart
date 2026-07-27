// 這是「臨時」主選單,先讓 detection 模組有個入口可以測試。
// 之後正式的介面(客服)模組做出來,這個檔案應該會被取代或整合進去,
// 到時候把 DetectionScreen 的 Navigator.push 那段邏輯搬過去就好,
// 這裡的按鈕清單就是預留給其他模組(風險評估/GPS報案/知識庫等)
// 未來掛上去的地方。
import 'package:flutter/material.dart';
import 'detection/scan_screen.dart';

class HomeMenuScreen extends StatelessWidget {
  const HomeMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('No Pholebia 不再孔怖')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MenuButton(
                icon: Icons.flashlight_on,
                label: '反光/閃光偵測',
                onTap: () {
                  Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => const ScanScreen()));
                },
              ),
              const SizedBox(height: 16),
              // ---- 以下為預留位置,等其他模組完成後接上 ----
              _MenuButton(
                icon: Icons.wifi_find,
                label: '區域網路異常偵測(尚未完成)',
                onTap: null,
              ),
              const SizedBox(height: 16),
              _MenuButton(icon: Icons.map, label: '聯防型案件地圖(尚未完成)', onTap: null),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _MenuButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = onTap != null;
    return SizedBox(
      width: double.infinity,
      height: 64,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: isEnabled ? null : Colors.grey.shade300,
          foregroundColor: isEnabled ? null : Colors.grey.shade600,
        ),
      ),
    );
  }
}
