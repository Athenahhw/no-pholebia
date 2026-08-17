// 功能: 把一次掃描的彙整結果(DetectionSessionSummary)送給後端 AI
// (多模態推理/語義推理組),取得風險評估結果。
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'detection_result.dart';

class DetectionBackendClient {
  /// 後端 API 網址
  /// 可用 --dart-define=AI_ENDPOINT=http://192.168.1.13:8000/api/v1/analyze 覆蓋
  final String endpoint;
  final Duration timeout;

  DetectionBackendClient({
    String? endpoint,
    this.timeout = const Duration(seconds: 10),
  }) : endpoint =
           endpoint ??
           const String.fromEnvironment(
             'AI_ENDPOINT',
             defaultValue: 'http://192.168.1.13:8000/api/v1/analyze',
           );

  /// 送出掃描結果,回傳後端的分析結果(Map)。
  /// 回傳 null 代表連線失敗/逾時,呼叫端應該顯示錯誤,不要假裝成功。
  Future<Map<String, dynamic>?> submitScan(
    DetectionSessionSummary summary,
  ) async {
    debugPrint('🔵 準備發送請求到: $endpoint');

    late final String jsonBody;
    try {
      jsonBody = jsonEncode(summary.toJson());
      debugPrint('🔵 資料打包成功,長度: ${jsonBody.length} 字元');
    } catch (e) {
      debugPrint('🔴 資料打包失敗(jsonEncode錯誤): $e');
      return null;
    }

    try {
      final response = await http
          .post(
            Uri.parse(endpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonBody,
          )
          .timeout(timeout);

      debugPrint('🟢 收到回應,狀態碼: ${response.statusCode}');

      if (response.statusCode != 200) {
        debugPrint('🔴 回應內容(非200): ${response.body}');
        return null;
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('🔴 連線失敗,詳細錯誤: $e');
      debugPrint('🔴 錯誤類型: ${e.runtimeType}');
      return null;
    }
  }
}
