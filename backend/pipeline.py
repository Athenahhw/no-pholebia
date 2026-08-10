import json

from tms_engine import calculate_threat_score
from llm_agent import generate_safety_plan_with_prompt


def _summarize_suspicious_item(payload) -> str:
    """
    從 boundingBoxes 挑一個信心度最高的候選物件,組成給LLM看的文字描述。
    ML Kit的分類很粗略(例如"Home good"),這裡只是給LLM一個參考起點,
    真正的辨識要靠LLM自己看screenshot判斷,不是依賴這個字串。
    """
    if not payload.bounding_boxes:
        return "牆面異常裝置(未偵測到明確候選物件,請直接依畫面判斷)"

    top_box = max(payload.bounding_boxes, key=lambda b: b.confidence)
    return f"{top_box.object_class}(ML Kit初步分類,信心度{top_box.confidence:.0%},非最終判斷)"


def run_anti_pinhole_inference(payload) -> dict:
    """
    一鍵執行的 AI 推理流水線。

    設計原則:
      1. tms_engine 算出的分數是「輔助訊號」,不是最終答案,原因是它是
         人工設定權重的公式,無法真的"看懂"畫面內容。
      2. 真正的風險判斷交給 Gemini 多模態推理(看截圖 + 所有輔助數據),
         這樣才符合"前端蒐證、後端AI綜合語意判斷"的分工設計。
      3. WiFi/藍牙偵測結果只能當加分項,沒偵測到不代表安全(這點在
         prompt裡也提醒LLM,不要誤用成減分依據)。

    ⚠️ TODO(重要): user_lat / user_lng 目前前端沒有實際蒐集GPS座標,
    這裡先用 payload 上的預設值(如果前端之後加上geolocator套件,
    在 AnalyzeRequest 補上 userLat/userLng 欄位即可直接接上)。
    在GPS真的接上之前,police_cheat_sheet 裡的座標是不準確的佔位值,
    這件事要讓團隊知道,不要在demo時誤以為座標是真的。
    """
    print("正在接收前端傳入的完整掃描資料...")

    # ---- 1. 算輔助訊號分數(給LLM參考,不是最終依據) ----
    glint_score = min(1.0, payload.high_risk_glint_count / 3.0) if payload.high_risk_glint_count else 0.0
    wifi_camera_detected = any(d.looks_like_camera for d in payload.network_devices)
    suspicious_network_device_count = sum(1 for d in payload.network_devices if d.looks_like_camera)
    suspicious_bluetooth_device_count = sum(1 for d in payload.bluetooth_devices if d.suspicious)
    bluetooth_suspicious_detected = suspicious_bluetooth_device_count > 0

    threat_result = calculate_threat_score(
        optical_glint_score=glint_score,
        wifi_camera_detected=wifi_camera_detected,
        bluetooth_suspicious_detected=bluetooth_suspicious_detected,
        environment_type=payload.environment_context or "未提供",
    )
    print(f"輔助訊號分數計算完成(僅供LLM參考): {threat_result['risk_percentage']}% ({threat_result['risk_level']})")

    # ---- 2. 交給 Gemini 做真正的多模態語意推理 ----
    print("正在調用 Gemini 進行多模態語意推理(含截圖分析)...")
    suspicious_item_summary = _summarize_suspicious_item(payload)

    # TODO: 換成前端真實GPS座標(目前前端未蒐集,見上方說明)
    user_lat = getattr(payload, "user_lat", 25.0501)
    user_lng = getattr(payload, "user_lng", 121.5132)

    llm_result = generate_safety_plan_with_prompt(
        environment_type=payload.environment_context or "未提供",
        suspicious_item=suspicious_item_summary,
        aux_risk_percentage=threat_result["risk_percentage"],
        aux_risk_level=threat_result["risk_level"],
        glint_score=glint_score,
        high_risk_glint_count=payload.high_risk_glint_count,
        total_glint_count=payload.total_glint_count,
        wifi_detected=wifi_camera_detected,
        network_device_count=len(payload.network_devices),
        suspicious_network_device_count=suspicious_network_device_count,
        bluetooth_device_count=len(payload.bluetooth_devices),
        suspicious_bluetooth_device_count=suspicious_bluetooth_device_count,
        user_lat=user_lat,
        user_lng=user_lng,
        screenshot_base64=payload.screenshot_base64,
    )

    # ---- 3. 打包最終回傳格式 ----
    # riskLevel / riskPercentage 放在最外層,對應 Flutter端 scan_page.dart
    # 的 _buildResultFrom() 解析邏輯,不需要前端另外改程式碼。
    final_output = {
        "status": "success",
        "riskLevel": str(llm_result.get("risk_level", threat_result["risk_level"])).lower(),
        "riskPercentage": llm_result.get("risk_percentage", threat_result["risk_percentage"]),
        "threat_assessment": {
            "auxiliary_signal_percentage": threat_result["risk_percentage"],
            "auxiliary_signal_level": threat_result["risk_level"],
            "env_category": threat_result["env_category"],
        },
        "ai_reasoning_and_actions": {
            "plausibility_reasoning": llm_result.get("plausibility_reasoning", ""),
            "action_cards": llm_result.get("action_cards", []),
            "police_cheat_sheet": llm_result.get("police_cheat_sheet", ""),
            "report_letter": llm_result.get("report_letter", ""),
        },
    }

    return final_output


# ==========================================
# 本地流水線測試
# ==========================================
if __name__ == "__main__":
    from main import AnalyzeRequest

    print("=== 開始測試完整 AI 後端推理流程 ===")

    mock_payload = AnalyzeRequest(
        environmentContext="試衣間",
        totalGlintCount=2,
        highRiskGlintCount=1,
        boundingBoxes=[
            {"x": 0.4, "y": 0.5, "width": 0.15, "height": 0.1, "confidence": 0.7, "class": "Home good"}
        ],
        networkDevices=[{"ip": "192.168.1.45", "openPorts": [80, 554], "looksLikeCamera": True}],
        bluetoothDevices=[],
        screenshotBase64=None,  # 本地測試先不帶截圖
    )

    output = run_anti_pinhole_inference(mock_payload)

    print("\n" + "=" * 40)
    print("最終 AI 推理輸出結果 JSON(將回傳給 Flutter App):")
    print("=" * 40)
    print(json.dumps(output, ensure_ascii=False, indent=2))