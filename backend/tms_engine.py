import math

def parse_environment_multiplier(user_input: str) -> tuple[float, str]:
    normalized_input = (user_input or "").strip().lower()

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
    environment_context: str = "",
    glints: list = None,
    high_risk_glint_count: int = 0,
    torch_used: bool = False,
    ambient_brightness: float = 128.0,
    network_devices: list = None,
    bluetooth_devices: list = None,
    wifi_camera_detected: bool = False,
    bluetooth_suspicious_detected: bool = False,
    **kwargs
) -> dict:
    """
    多模態威脅融合機率算分引擎 (TMS Engine)
    支援接收前端原始 List/Count 數據，並自動轉換為 Sigmoid 權重算分。
    """
    # 1. 自動判斷無線裝置狀態
    # 重要：僅有「疑似攝影機」或「可疑藍牙設備」才算高風險。
    # 直接把家裡一般的 Wi‑Fi/藍牙裝置當成針孔設備，會造成大量誤報。
    wifi_detected = bool(wifi_camera_detected)
    bt_detected = bool(bluetooth_suspicious_detected)

    # 2. 自動將高風險反光點數轉換為光學分數 (0.0 ~ 1.0)
    # 邏輯：1 個高風險反光點給 0.5 分，2 個以上給 1.0 滿分
    optical_glint_score = min(high_risk_glint_count * 0.5, 1.0)

    # 3. 計算平均 Flicker Score (供 LLM 參考)
    avg_flicker_score = 0.0
    if glints and len(glints) > 0:
        flicker_sum = sum(g.get("flickerScore", 0.0) for g in glints if isinstance(g, dict))
        avg_flicker_score = round(flicker_sum / len(glints), 2)
    elif high_risk_glint_count > 0:
        avg_flicker_score = 8.5  # 預設高於門檻之參考值

    # 4. 權重與偏置 (Sigmoid 邏輯)
    W_WIFI = 4.0
    W_BLUETOOTH = 3.5
    W_GLINT = 2.5
    BIAS = -2.5

    wifi_score = 1.0 if wifi_detected else 0.0
    bluetooth_score = 1.0 if bt_detected else 0.0

    raw_score = (
        (wifi_score * W_WIFI) +
        (bluetooth_score * W_BLUETOOTH) +
        (optical_glint_score * W_GLINT) +
        BIAS
    )

    multiplier, env_category = parse_environment_multiplier(environment_context)
    adjusted_raw_score = raw_score * multiplier

    probability = 1 / (1 + math.exp(-adjusted_raw_score))
    risk_percentage = min(round(probability * 100, 1), 35.0)

    if risk_percentage >= 20.0:
        risk_level = "HIGH"
    elif risk_percentage >= 8.0:
        risk_level = "MEDIUM"
    else:
        risk_level = "LOW"

    wireless_bonus = 0.0
    if wifi_detected:
        wireless_bonus += 20.0
    if bt_detected:
        wireless_bonus += 15.0

    return {
        "risk_percentage": risk_percentage,
        "risk_level": risk_level,
        "raw_score": round(adjusted_raw_score, 2),
        "env_category": env_category,
        "avg_flicker_score": avg_flicker_score,
        "wireless_bonus_applied": wireless_bonus
    }


if __name__ == "__main__":
    # 本地測試
    res = calculate_threat_score(
        environment_context="台北101 3樓女廁",
        high_risk_glint_count=2,
        wifi_camera_detected=True
    )
    print("測試結果：", res)
