import 'package:flutter_test/flutter_test.dart';

import 'package:pinhole_detector/main.dart';

void main() {
  testWidgets('App 啟動時顯示主選單', (WidgetTester tester) async {
    await tester.pumpWidget(const NoPholebiaApp());
    expect(find.text('No Pholebia 不再孔怖'), findsOneWidget);
  });
}