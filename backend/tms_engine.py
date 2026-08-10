import math


def parse_environment_multiplier(user_input: str) -> tuple[float, str]:

    normalized_input = user_input.strip().lower()

    HIGH_PRIVACY_KEYWORDS = [
        "廁", "洗手間", "便所", "試衣", "更衣", "淋浴", "浴室", "湯屋",
        "restroom", "bathroom", "fitting", "wc", "changing"
    ]

    MEDIUM_PRIVACY_KEYWORDS = [
        "飯店", "旅館", "民宿", "房間", "臥室", "套房", "ktv", "包廂", "按摩",
        "hotel", "room", "airbnb", "suite"
    ]

    LOW_PRIVACY_KEYWORDS = [
        "辦公", "會議", "教室", "圖書館", "大廳", "咖啡廳", "辦公室",
        "office", "meeting", "classroom", "library", "cafe"
    ]

    for kw in HIGH_PRIVACY_KEYWORDS:
        if kw in normalized_input:
            return 1.4, "高度隱私場所"

    for kw in MEDIUM_PRIVACY_KEYWORDS:
        if kw in normalized_input:
            return 1.1, "中度隱私場所"

    for kw in LOW_PRIVACY_KEYWORDS:
        if kw in normalized_input:
            return 0.7, "低敏感公共/工作場所"

    return 1.0, "一般場所"


def calculate_threat_score(
    optical_glint_score: float,        # 光學反光分數 (0.0 ~ 1.0),由高風險反光點數量換算
    wifi_camera_detected: bool,        # 同網段是否偵測到疑似攝影機裝置
    bluetooth_suspicious_detected: bool,  # 附近是否偵測到命名可疑的藍牙裝置
    environment_type: str
) -> dict:
    """
    多模態威脅融合機率算分引擎 (TMS Engine)

    這個分數是「輔助訊號」,給LLM參考,不是最終判斷依據 —— 因為這是人工
    設定權重的公式,無法真的理解畫面內容。最終風險判斷由 llm_agent.py
    呼叫 Gemini 看截圖+完整數據後決定。

    註: 原本這裡的第二個特徵是 infrared_detected(紅外線偵測),但前端
    手機鏡頭實際上偵測不到真正的紅外線(討論過這個物理限制),所以改成
    bluetooth_suspicious_detected,對應前端真正會產生的資料。
    """
    W_WIFI = 4.0
    W_BLUETOOTH = 3.5
    W_GLINT = 2.5
    BIAS = -2.5

    wifi_score = 1.0 if wifi_camera_detected else 0.0
    bluetooth_score = 1.0 if bluetooth_suspicious_detected else 0.0

    raw_score = (
        (wifi_score * W_WIFI) +
        (bluetooth_score * W_BLUETOOTH) +
        (optical_glint_score * W_GLINT) +
        BIAS
    )

    multiplier, env_category = parse_environment_multiplier(environment_type)
    adjusted_raw_score = raw_score * multiplier

    probability = 1 / (1 + math.exp(-adjusted_raw_score))
    risk_percentage = round(probability * 100, 1)

    if risk_percentage >= 75.0:
        risk_level = "HIGH"
    elif risk_percentage >= 40.0:
        risk_level = "MEDIUM"
    else:
        risk_level = "LOW"

    return {
        "risk_percentage": risk_percentage,
        "risk_level": risk_level,
        "raw_score": round(adjusted_raw_score, 2),
        "env_category": env_category
    }


# ==========================================
# 本地測試區塊
# ==========================================
if __name__ == "__main__":
    print("--- 測試情境 1:「台北101 3樓女廁」(強烈反光 + 可疑WiFi) ---")
    result1 = calculate_threat_score(
        optical_glint_score=0.8,
        wifi_camera_detected=True,
        bluetooth_suspicious_detected=False,
        environment_type="台北101 3樓女廁"
    )
    print(f"辨識分類: {result1['env_category']}")
    print(f"風險機率: {result1['risk_percentage']}% | 等級: {result1['risk_level']}")

    print("\n--- 測試情境 2:「錢櫃 KTV 302包廂」(微弱反光 + 無WiFi) ---")
    result2 = calculate_threat_score(
        optical_glint_score=0.4,
        wifi_camera_detected=False,
        bluetooth_suspicious_detected=False,
        environment_type="錢櫃 KTV 302包廂"
    )
    print(f"辨識分類: {result2['env_category']}")
    print(f"風險機率: {result2['risk_percentage']}% | 等級: {result2['risk_level']}")

    print("\n--- 測試情境 3:「公司 4樓大會議室」(微弱反光) ---")
    result3 = calculate_threat_score(
        optical_glint_score=0.3,
        wifi_camera_detected=False,
        bluetooth_suspicious_detected=False,
        environment_type="公司 4樓大會議室"
    )
    print(f"辨識分類: {result3['env_category']}")
    print(f"風險機率: {result3['risk_percentage']}% | 等級: {result3['risk_level']}")