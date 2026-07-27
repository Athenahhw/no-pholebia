import 'package:flutter/material.dart';
import 'ui/splash_page.dart';

void main() {
  runApp(const NoPholebiaApp());
}

class NoPholebiaApp extends StatelessWidget {
  const NoPholebiaApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'No Pholebia',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
        useMaterial3: true,
      ),
      home: const SplashPage(),
    );
  }
}
