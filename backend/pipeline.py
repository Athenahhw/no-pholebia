import json
from tms_engine import calculate_threat_score
from llm_agent import generate_safety_plan_with_prompt

def _summarize_suspicious_item(payload) -> str:
    """
    從 boundingBoxes 挑一個信心度最高的候選物件,組成給LLM看的文字描述。
    ML Kit的分類很粗略(例如"Home good"),這裡只是給LLM一個參考起點,
    真正的辨識要靠LLM自己看screenshot判斷,不是依賴這個字串。
    """
    bounding_boxes = getattr(payload, "bounding_boxes", getattr(payload, "boundingBoxes", []))
    if not bounding_boxes:
        return "牆面異常裝置(未偵測到明確候選物件,請直接依畫面判斷)"

    top_box = max(bounding_boxes, key=lambda b: getattr(b, "confidence", 0))
    object_class = getattr(top_box, "object_class", getattr(top_box, "class_name", "未知物件"))
    confidence = getattr(top_box, "confidence", 0.0)
    
    return f"{object_class}(ML Kit初步分類,信心度{confidence:.0%},非最終判斷)"


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

    GPS座標(user_lat/user_lng)現在讀取前端實際定位結果(payload.latitude/
    payload.longitude)。前端定位失敗或使用者拒絕權限時會是None,這裡
    用預設值(台北101座標)當保底,避免police_cheat_sheet出現None字樣,
    但這種情況下報案小抄的座標是不準確的,只是避免顯示錯誤,不是真的位置。

    """
    print("正在接收前端傳入的完整掃描資料...")

    # 相容性提取 payload 屬性 (同時支援 snake_case 與 camelCase)
    env_context = getattr(payload, "environment_context", getattr(payload, "environmentContext", "未提供"))
    high_risk_glint_count = getattr(payload, "high_risk_glint_count", getattr(payload, "highRiskGlintCount", 0))
    total_glint_count = getattr(payload, "total_glint_count", getattr(payload, "totalGlintCount", 0))
    network_devices = getattr(payload, "network_devices", getattr(payload, "networkDevices", []))
    bluetooth_devices = getattr(payload, "bluetooth_devices", getattr(payload, "bluetoothDevices", []))
    screenshot_b64 = getattr(payload, "screenshot_base64", getattr(payload, "screenshotBase64", None))

    # ---- 1. 算輔助訊號分數(給LLM參考,不是最終依據) ----
    glint_score = min(1.0, high_risk_glint_count / 3.0) if high_risk_glint_count else 0.0
    
    wifi_camera_detected = any(
        getattr(d, "looks_like_camera", getattr(d, "looksLikeCamera", False)) 
        for d in network_devices
    )
    suspicious_network_device_count = sum(
        1 for d in network_devices 
        if getattr(d, "looks_like_camera", getattr(d, "looksLikeCamera", False))
    )
    suspicious_bluetooth_device_count = sum(
        1 for d in bluetooth_devices 
        if getattr(d, "suspicious", False)
    )
    bluetooth_suspicious_detected = suspicious_bluetooth_device_count > 0

    # 修正參數名稱，對齊 tms_engine.py 的定義
    threat_result = calculate_threat_score(
        environment_context=env_context or "未提供",
        high_risk_glint_count=high_risk_glint_count,
        wifi_camera_detected=wifi_camera_detected,
        bluetooth_suspicious_detected=bluetooth_suspicious_detected,
    )
    print(f"輔助訊號分數計算完成(僅供LLM參考): {threat_result['risk_percentage']}% ({threat_result['risk_level']})")

    # ---- 2. 交給 Gemini 做真正的多模態語意推理 ----
    print("正在調用 Gemini 進行多模態語意推理(含截圖分析)...")
    suspicious_item_summary = _summarize_suspicious_item(payload)

# 讀取前端實際定位結果,定位失敗時用台北101座標當保底(避免None顯示錯誤)
    user_lat = payload.latitude if payload.latitude is not None else 25.0501
    user_lng = payload.longitude if payload.longitude is not None else 121.5132

    llm_result = generate_safety_plan_with_prompt(
        environment_type=env_context or "未提供",
        suspicious_item=suspicious_item_summary,
        aux_risk_percentage=threat_result["risk_percentage"],
        aux_risk_level=threat_result["risk_level"],
        glint_score=glint_score,
        high_risk_glint_count=high_risk_glint_count,
        total_glint_count=total_glint_count,
        wifi_detected=wifi_camera_detected,
        network_device_count=len(network_devices),
        suspicious_network_device_count=suspicious_network_device_count,
        bluetooth_device_count=len(bluetooth_devices),
        suspicious_bluetooth_device_count=suspicious_bluetooth_device_count,
        user_lat=user_lat,
        user_lng=user_lng,
        screenshot_base64=screenshot_b64,
    )

    # 提取文案 (優先使用新 Key，並提供 fallback 保底)
    risk_assessment = llm_result.get("risk_assessment_summary") or llm_result.get("plausibility_reasoning", "")
    ai_summary = llm_result.get("ai_assistant_summary", "")

    llm_risk_percentage = float(llm_result.get("risk_percentage", threat_result["risk_percentage"]))
    final_risk_percentage = min(llm_risk_percentage, 35.0)
    final_risk_level = "high" if final_risk_percentage >= 20.0 else "medium" if final_risk_percentage >= 8.0 else "low"

    # ---- 3. 打包最終回傳格式 ----
    final_output = {
        "status": "success",
        "riskLevel": final_risk_level,
        "riskPercentage": round(final_risk_percentage, 1),
        "threat_assessment": {
            "auxiliary_signal_percentage": threat_result["risk_percentage"],
            "auxiliary_signal_level": threat_result["risk_level"],
            "env_category": threat_result["env_category"],
        },
        "ai_reasoning_and_actions": {
            "risk_assessment_summary": risk_assessment,
            "plausibility_reasoning": risk_assessment,  # 提供舊 Key 向下相容
            "police_cheat_sheet": llm_result.get("police_cheat_sheet", ""),
            "ai_assistant_summary": ai_summary,
            "action_cards": llm_result.get("action_cards", []),
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
        screenshotBase64=None,
    )

    output = run_anti_pinhole_inference(mock_payload)

    print("\n" + "=" * 50)
    print("最終 AI 推理輸出結果 JSON (將回傳給 Flutter App):")
    print("=" * 50)
    print(json.dumps(output, ensure_ascii=False, indent=2))
