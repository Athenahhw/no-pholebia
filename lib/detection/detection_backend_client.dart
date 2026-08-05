// 功能: 把一次掃描的彙整結果(DetectionSessionSummary)送給後端 AI
// (多模態推理/語義推理組),取得風險評估結果。
// endpoint 網址等後端那組確定 API 規格後再填進來。
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'detection_result.dart';

class DetectionBackendClient {
  /// 後端 API 網址,等後端組確定後在這裡填,或改成從設定畫面讀取
  final String endpoint;
  final Duration timeout;

  DetectionBackendClient({
    this.endpoint = 'http://192.168.1.100:8000/api/detection/analyze', // TODO: 換成實際後端網址
    this.timeout = const Duration(seconds: 10),
  });

  /// 送出掃描結果,回傳後端的分析結果(Map)。
  /// 回傳 null 代表連線失敗/逾時,呼叫端應該顯示錯誤,不要假裝成功。
  ///
  /// 預期後端回應格式(實際欄位以後端組定義為準,這裡先假設一個合理格式):
  /// {
  ///   "riskLevel": "high" | "low",
  ///   "riskPercentage": 88,
  ///   "description": "偵測到非對稱的幾何小黑孔與微光特徵...",
  ///   "reportId": "xxxx"   // 給後續報案敘述/PDF下載用
  /// }
  Future<Map<String, dynamic>?> submitScan(DetectionSessionSummary summary) async {
    try {
      final response = await http
          .post(
            Uri.parse(endpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(summary.toJson()),
          )
          .timeout(timeout);

      if (response.statusCode != 200) return null;
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }
}