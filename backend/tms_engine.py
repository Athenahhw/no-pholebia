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
    optical_glint_score: float,  # 傳入參數：光學/閃光燈反光分數 (範圍 0.0 ~ 1.0)
    wifi_camera_detected: bool,  # 傳入參數：是否偵測到可疑 Wi-Fi 針孔串流 (True/False)
    infrared_detected: bool,     # 傳入參數：是否偵測到紅外線補光燈 (True/False)
    environment_type: str        
) -> dict:                      
    """
    多模態威脅融合機率算分引擎 (TMS Engine) - 支援使用者自由輸入空間名稱
    """
    # ==========================================
    # 1. 設定特徵基礎權重與偏移量
    # ==========================================
    W_WIFI = 4.0      # 設定 Wi-Fi 異常訊號的權重為 4.0
    W_INFRARED = 3.5  # 設定紅外線補光燈的權重為 3.5
    W_GLINT = 2.5     # 設定光學/閃光燈反光的權重為 2.5
    BIAS = -2.5       # 設定基礎偏移量為 -2.5

    # ==========================================
    # 2. 將布林值特徵轉為數值，並計算線性加權總分
    # ==========================================
    wifi_score = 1.0 if wifi_camera_detected else 0.0 
    ir_score = 1.0 if infrared_detected else 0.0     
    
    raw_score = (
        (wifi_score * W_WIFI) +           
        (ir_score * W_INFRARED) +          
        (optical_glint_score * W_GLINT) + 
        BIAS                              
    )

    # ==========================================
    # 3. 解析使用者自由輸入的文字，並動態調整風險乘數
    # ==========================================
    # 呼叫關鍵字解析函式，取得對應的風險乘數與分類名稱
    multiplier, env_category = parse_environment_multiplier(environment_type)
    
    # 將原始加權分數乘以動態解析出的環境乘數，得到修正後的最終總分
    adjusted_raw_score = raw_score * multiplier

    # ==========================================
    # 4. 使用 Sigmoid 函數將分數壓縮至 0% ~ 100% 的機率值
    # ==========================================
    # 套用 Sigmoid 公式: S(x) = 1 / (1 + e^(-x))
    probability = 1 / (1 + math.exp(-adjusted_raw_score))
    
    # 將 0.0 ~ 1.0 的數值轉換為百分比，並四捨五入保留至小數點後第 1 位
    risk_percentage = round(probability * 100, 1)

    # ==========================================
    # 5. 根據百分比判定風險等級 (High / Medium / Low)
    # ==========================================
    if risk_percentage >= 75.0:     # 若風險機率大於等於 75.0%，判定為高風險
        risk_level = "HIGH"
    elif risk_percentage >= 40.0:   # 若風險機率介於 40.0% 至 74.9% 之間，判定為中風險
        risk_level = "MEDIUM"
    else:                           # 若風險機率小於 40.0%，判定為低風險
        risk_level = "LOW"

    # 將計算結果封裝成字典回傳給呼叫端
    return {
        "risk_percentage": risk_percentage,       # 威脅機率百分比 
        "risk_level": risk_level,                 # 威脅等級字串 
        "raw_score": round(adjusted_raw_score, 2),# 修正後的原始分數 (保留小數點後 2 位)
        "env_category": env_category              # 自動辨識出的空間分類 
    }

# ==========================================
# 本地測試區塊
# ==========================================
if __name__ == "__main__": 
    # 印出第一個測試情境
    print("--- 測試情境 1：自由輸入「台北101 3樓女廁」（強烈反光 + 可疑 Wi-Fi） ---")
    result1 = calculate_threat_score(
        optical_glint_score=0.8,              # 傳入光學反光分數 0.8
        wifi_camera_detected=True,            # 傳入已偵測到可疑 Wi-Fi (True)
        infrared_detected=False,              # 傳入未偵測到紅外線 (False)
        environment_type="台北101 3樓女廁"    # 使用者自由輸入的空間名稱
    )
    # 印出解析出的空間分類、風險機率與等級
    print(f"辨識分類: {result1['env_category']}")
    print(f"風險機率: {result1['risk_percentage']}% | 等級: {result1['risk_level']}")

    # 印出第二個測試情境
    print("\n--- 測試情境 2：自由輸入「錢櫃 KTV 302包廂」（微弱反光 + 無 Wi-Fi） ---")
    result2 = calculate_threat_score(
        optical_glint_score=0.4,              # 傳入微弱光學反光分數 0.4
        wifi_camera_detected=False,           # 傳入未偵測到 Wi-Fi (False)
        infrared_detected=False,              # 傳入未偵測到紅外線 (False)
        environment_type="錢櫃 KTV 302包廂"   # 使用者自由輸入的空間名稱
    )
    # 印出解析出的空間分類、風險機率與等級
    print(f"辨識分類: {result2['env_category']}")
    print(f"風險機率: {result2['risk_percentage']}% | 等級: {result2['risk_level']}")

    # 印出第三個測試情境
    print("\n--- 測試情境 3：自由輸入「公司 4樓大會議室」（微弱反光） ---")
    result3 = calculate_threat_score(
        optical_glint_score=0.3,              # 傳入微弱光學反光分數 0.3
        wifi_camera_detected=False,           # 傳入未偵測到 Wi-Fi (False)
        infrared_detected=False,              # 傳入未偵測到紅外線 (False)
        environment_type="公司 4樓大會議室"   # 使用者自由輸入的空間名稱
    )
    # 印出解析出的空間分類、風險機率與等級
    print(f"辨識分類: {result3['env_category']}")
    print(f"風險機率: {result3['risk_percentage']}% | 等級: {result3['risk_level']}")
