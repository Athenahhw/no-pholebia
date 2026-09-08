from __future__ import annotations
import os
import json
import base64
from typing import Optional
from dotenv import load_dotenv
from google import genai
from google.genai import types

# 1. 讀取 .env 中的 GEMINI_API_KEY
load_dotenv(dotenv_path=os.path.join(os.path.dirname(__file__), ".env"))
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")

# Keep the API request shorter than the Flutter client's timeout so the backend
# can return its local fallback response when Gemini is unreachable.
client = (
    genai.Client(
        api_key=GEMINI_API_KEY,
        http_options=types.HttpOptions(
            timeout=15000,
            retry_options=types.HttpRetryOptions(attempts=1),
        ),
    )
    if GEMINI_API_KEY
    else None
)


def generate_safety_plan_with_prompt(
    environment_type: str,
    suspicious_item: str,
    aux_risk_percentage: float,
    aux_risk_level: str,
    glint_score: float,
    high_risk_glint_count: int,
    total_glint_count: int,
    wifi_detected: bool,
    network_device_count: int,
    suspicious_network_device_count: int,
    bluetooth_device_count: int,
    suspicious_bluetooth_device_count: int,
    user_lat: float,
    user_lng: float,
    screenshot_base64: Optional[str] = None,
) -> dict:
    """
    【針孔掃描 AI 推理】
    呼叫 Google Gemini API 生成包含風險評估、報案敘述與 AI 助理查詢文案的 JSON 報告。
    """
    system_instruction = """
    你是一名專業的治安防護與隱私安全 AI 專家。
    請根據傳入的現場感測數據與畫面截圖，生成精準的風險評估報告與防護建議。

    判斷原則：
    1. 有畫面截圖時，以視覺影像為主；無截圖時，依據數據做保守判斷。
    2. 無線裝置偵測為加分項，無偵測到不代表完全安全。

    你必須 strictly 回傳標準 JSON 格式，包含以下 6 個 Key：
    1. "risk_level": "high" | "medium" | "low"，高風險是30%以上，低風險是15%以下，中風險介於兩者之間，請以低風險為主。
    2. "risk_percentage": 數字 (0 ~ 30)，做最保守的判斷，不要輕易提供高於 25% 的風險機率。
    3. "risk_assessment_summary": 【風險評估文案】詳細分析為何此環境與物品有此風險，說明反光與無線訊號特徵。
    4. "police_cheat_sheet": 【報案敘述文案】50 字以內，方便使用者直接唸給警察聽。需提及地點與具體物品位置。
    5. "ai_assistant_summary": 【AI 助理查詢結果文案】給使用者的白話解答總結與防護情境說明。
    6. "action_cards": 陣列，包含 3 點具體實體處置建議（例如遮蔽、檢查）。
    """

    prompt_content = f"""
    【當前檢測數據】
    - 使用者輸入空間: "{environment_type}"
    - 現場發現的異常物品/位置: "{suspicious_item}"
    - 系統初步評估機率: {aux_risk_percentage}% (等級: {aux_risk_level})
    - 光學反光分數: {glint_score} (共 {total_glint_count} 個反光點, {high_risk_glint_count} 個高風險)
    - Wi-Fi 串流偵測: {wifi_detected} (同網段 {network_device_count} 個裝置, {suspicious_network_device_count} 個開放可疑 Port)
    - 藍牙掃描: {bluetooth_device_count} 個裝置 ({suspicious_bluetooth_device_count} 個命名可疑)
    - GPS 座標: ({user_lat}, {user_lng})
    - 畫面截圖: {"已附上，請看圖分析" if screenshot_base64 else "無"}
    """

    contents = []
    if screenshot_base64:
        try:
            clean_b64 = screenshot_base64.split(",")[-1] if "," in screenshot_base64 else screenshot_base64
            image_bytes = base64.b64decode(clean_b64)
            contents.append(types.Part.from_bytes(data=image_bytes, mime_type="image/jpeg"))
        except Exception as e:
            print(f"⚠️ 截圖解碼失敗: {e}")

    contents.append(prompt_content)

    try:
        if client is None:
            raise RuntimeError("GEMINI_API_KEY 未設定，使用本地保底建議")
        response = client.models.generate_content(
            model="gemini-flash-latest",
            contents=contents,
            config=types.GenerateContentConfig(
                system_instruction=system_instruction,
                response_mime_type="application/json",
                temperature=0.2
            )
        )
        return json.loads(response.text)

    except Exception as e:
        print(f"⚠️ Gemini API 連線異常: {e}")
        safe_risk = min(max(float(aux_risk_percentage), 0.0), 30.0)
        return {
            "risk_level": aux_risk_level.lower(),
            "risk_percentage": safe_risk,
            "risk_assessment_summary": f"初步評估於 {environment_type} 的「{suspicious_item}」發現異常光學反光訊號，系統算分機率為 {safe_risk}%。",
            "police_cheat_sheet": f"報案小抄：我在座標 ({user_lat}, {user_lng}) 的 {environment_type}，發現【{suspicious_item}】有疑似針孔裝置，請派員協助處理。",
            "ai_assistant_summary": f"在 {environment_type} 掃描到疑慮物品「{suspicious_item}」，當前風險等級判定為 {aux_risk_level}，請優先採取遮蔽防護動作。",
            "action_cards": [
                f"1. 請使用不透明膠帶或貼紙遮蔽 {suspicious_item}",
                "2. 保持冷靜並注意自身隱私安全",
                "3. 攜帶個人貴重物品並視情況聯絡場所管理員"
            ]
        }


def generate_travel_assistant_advice(
    destination: str,
    target_date: str,
    matched_cases: list
) -> dict:
    """
    【AI助理安全建議】
    根據使用者輸入的地點、日期與資料庫中的歷史案件，動態推論場景屬性並生成客製化防護建議。
    """
    cases_text = json.dumps(matched_cases, ensure_ascii=False) if matched_cases else "無相關歷史通報紀錄"

    system_instruction = """
    你是一個名為 "No Pholebia" 的專業防針孔與隱私安全 AI 助理。
    請根據使用者打算前往的地點、日期以及資料庫撈取出的歷史案件資料，生成一份親切、專業且具體的出遊/差旅防護建議。

    【動態場景推導原則】：
    請先根據「前往地點」名稱（例如：健身房淋浴間、五星級飯店、百貨公司試衣間、日租套房、溫泉湯屋、學校等）分析推論其空間場景類型，並針對該場景最容易被安裝偷拍設備的特定物品與死角，動態產出針對性的檢查建議。

    你必須嚴格回傳標準 JSON 格式，包含以下欄位：
    1. "location_summary": 【地點歷史案件摘要】若有歷史案件，說明歷史通報狀況；若無案件，則根據該場景類型給予溫馨提醒。
    2. "caution_items": 陣列，包含 2~3 項【高度符合該場景特性】最需著重檢查的隱蔽物品。每項需包含：
       - "title": 物品名稱（例如："1. 電視機上盒與插座" 或 "1. 牆面黏貼式掛勾"）
       - "detail": 針對該場景的具體檢查說明
    """

    prompt = f"""
    【行程資訊】
    - 預計日期: "{target_date}"
    - 前往地點: "{destination}"

    【案件地圖資料庫撈取結果】
    {cases_text}
    """

    try:
        if client is None:
            raise RuntimeError("GEMINI_API_KEY 未設定，使用本地保底建議")
        response = client.models.generate_content(
            model="gemini-flash-latest",
            contents=[prompt],
            config=types.GenerateContentConfig(
                system_instruction=system_instruction,
                response_mime_type="application/json",
                temperature=0.3
            )
        )
        return json.loads(response.text)

    except Exception as e:
        print(f"⚠️ AI 助理生成失敗: {e}")
        return {
            "location_summary": f"根據案件地圖資料庫，目前「{destination}」周邊尚無明確的歷史針孔通報，但仍建議留意周遭環境。",
            "caution_items": [
                {"title": "1. 掛勾與牆面飾品", "detail": "檢查更衣室或廁所門板上的黏貼式掛勾，注意是否有厚度異常或小孔洞。"},
                {"title": "2. 牆面插座與芳香劑", "detail": "檢查插座孔位或芳香劑噴霧口是否有不自然的黑色透光圓孔。"}
            ],
        }


# ==========================================
# 本地完整獨立測試區塊
# ==========================================
if __name__ == "__main__":
    print("==========================================")
    print("🚀 開始測試所有核心 AI 模組")
    print("==========================================")

    # ------------------------------------------
    # 測試項目 1：一鍵掃描AI推理模組
    # ------------------------------------------
    print("\n[測試 1/2] 正在測試【一鍵掃描 AI 推理】(generate_safety_plan_with_prompt)...")
    
    scan_result = generate_safety_plan_with_prompt(
        environment_type="試衣間",
        suspicious_item="牆角上方衣架勾勾",
        aux_risk_percentage=85.0,
        aux_risk_level="HIGH",
        glint_score=0.88,
        high_risk_glint_count=2,
        total_glint_count=3,
        wifi_detected=True,
        network_device_count=2,
        suspicious_network_device_count=1,
        bluetooth_device_count=1,
        suspicious_bluetooth_device_count=0,
        user_lat=25.0330,
        user_lng=121.5654,
        screenshot_base64=None
    )

    print("\n 模組一 (掃描推理) 回傳結果：")
    print(json.dumps(scan_result, ensure_ascii=False, indent=2))

    # ------------------------------------------
    # 測試項目 2：AI助理模組
    # ------------------------------------------
    print("\n------------------------------------------")
    print("[測試 2/2] 正在測試【AI 助理模組】(generate_travel_assistant_advice)...")

    # 模擬撈取出的歷史案件
    mock_cases = [
        {
            "location_name": "國立台北教育大學",
            "detail": "篤行樓3樓與4樓女廁、科學館3樓女廁近三月有被安裝過針孔攝影機的疑慮，目前已拆除。"
        }
    ]

    assistant_result = generate_travel_assistant_advice(
        destination="國立台北教育大學",
        target_date="08/17/2025",
        matched_cases=mock_cases
    )

    print("\n 模組二 (AI 助理) 回傳結果：")
    print(json.dumps(assistant_result, ensure_ascii=False, indent=2))

    print("\n==========================================")
    print(" 模組本地測試完成 ")
    print("==========================================")
