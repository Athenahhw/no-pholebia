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


def build_fallback_police_cheat_sheet(
    environment_type: str,
    suspicious_item: str,
    glint_count: int,
    suspicious_network_device_count: int,
    suspicious_bluetooth_device_count: int,
    user_lat: float,
    user_lng: float,
) -> str:
    """當 Gemini 不可用時，依據偵測數據組出具體且可直接唸給警方的報案敘述。"""
    location = (environment_type or "").strip() or "目前掃描現場"
    object_desc = (suspicious_item or "").strip() or "畫面中的可疑位置"
    if object_desc.startswith("發現"):
        object_desc = object_desc[2:].lstrip(" ：:，,")

    glint_part = (
        f"偵測到{glint_count}個異常反光點，位置需要進一步確認是否有小孔或鏡頭"
        if glint_count > 0
        else "偵測到異常光學反光，位置需要進一步確認"
    )
    wifi_part = (
        f"，同時偵測到{suspicious_network_device_count}個可疑 Wi‑Fi 裝置"
        if suspicious_network_device_count > 0
        else ""
    )
    bluetooth_part = (
        f"，以及{suspicious_bluetooth_device_count}個可疑藍芽裝置"
        if suspicious_bluetooth_device_count > 0
        else ""
    )

    return (
        f"我在{location}掃描時，於{object_desc}附近{glint_part}{wifi_part}{bluetooth_part}。"
        f"這些影像與感測結果顯示該處可能存在可疑攝影裝置，請員警到場確認，"
        f"並檢查是否安裝隱藏式針孔攝影機。"
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
    glint_screenshots_base64: Optional[list] = None,
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
    2. 公共場所 Wi-Fi / 藍牙極為常見。無線訊號權重接近 0，不得因為掃到一般熱點或藍牙裝置而提高 risk_percentage。
    3. 只有光學反光（glint）或畫面中可見的可疑鏡頭結構，才能作為上調風險的依據。
    4. 如果附上了「閃光點特寫截圖」，這些是系統偵測到異常反光、且自動裁切放大的區域特寫，
       每張圖中央用粉紅色圓圈標記出反光點的確切位置。請仔細檢視每一張特寫圖，
       如果圖中粉紅圈標記處或周圍出現類似「相機鏡頭」、「方形/長方形盒狀裝置」、
       「不自然的小洞口」的視覺特徵，這是強烈的針孔攝影機偽裝跡象，請將這點列為
       risk_assessment_summary 的重點依據，並大幅提高 risk_percentage 評估。
       如果特寫圖裡只是一般反光物（螺絲、金屬邊角、水漬等），則不要因此提高風險。

    你必須 strictly 回傳標準 JSON 格式，包含以下 6 個 Key：
    1. "risk_level": "high" | "medium" | "low"，高風險是30%以上，低風險是15%以下，中風險介於兩者之間，請以低風險為主。
    2. "risk_percentage": 數字 (0 ~ 30)，做最保守的判斷，不要輕易提供高於 25% 的風險機率。
       但如果閃光點特寫截圖中明確看到相機/方盒/洞口特徵，可以提高到接近或達到30%上限。
    3. "risk_assessment_summary": 【風險評估文案】詳細分析為何此環境與物品有此風險，
       如果有閃光點特寫截圖，請明確描述你在圖中看到的具體視覺特徵。
    4. "police_cheat_sheet": 【報案敘述文案】請寫成 1~2 句可直接唸給警察的重點報案內容，長度約 80~140 字，
       必須明確提及：地點（例如環境/樓層/區域）、物品位置（例如牆面/門板/掛勾/插座）、異常特徵（例如反光、黑孔、鏡頭外殼、異常螺絲）
       以及請警察協助檢查是否安裝隱藏式攝影裝置。嚴禁寫成泛泛的「疑似針孔設備」一句話。
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
    - 整體畫面截圖: {"已附上" if screenshot_base64 else "無"}
    - 閃光點特寫截圖: {"已附上 " + str(len(glint_screenshots_base64)) + " 張,每張中央粉紅圈標記反光點位置,請逐張仔細檢視" if glint_screenshots_base64 else "無"}

    【報案敘述生成要求】
    請特別重視 police_cheat_sheet，這段應該像現場報警口語，不是機器摘要。
    必須包含：
    - 地點/場所/樓層/區域
    - 物品位置（牆面、門板、掛勾、插座、頂角、窗邊等）
    - 可疑異常（黑洞、反光、異常螺絲、方形外殼、鏡頭狀構造）
    - 請警方協助檢查是否有隱藏式攝影裝置
    - 可直接唸給警察聽的口語連貫表述
    """

    contents = []
    if screenshot_base64:
        try:
            clean_b64 = screenshot_base64.split(",")[-1] if "," in screenshot_base64 else screenshot_base64
            image_bytes = base64.b64decode(clean_b64)
            contents.append(types.Part.from_bytes(data=image_bytes, mime_type="image/jpeg"))
        except Exception as e:
            print(f"⚠️ 整體截圖解碼失敗: {e}")

    # 新增:把每張閃光點特寫截圖都加進去,讓Gemini逐張檢視
    if glint_screenshots_base64:
        for idx, glint_shot in enumerate(glint_screenshots_base64):
            try:
                clean_b64 = glint_shot.split(",")[-1] if "," in glint_shot else glint_shot
                image_bytes = base64.b64decode(clean_b64)
                contents.append(types.Part.from_bytes(data=image_bytes, mime_type="image/jpeg"))
            except Exception as e:
                print(f"⚠️ 第{idx+1}張閃光點截圖解碼失敗: {e}")

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
        fallback_report = build_fallback_police_cheat_sheet(
            environment_type=environment_type,
            suspicious_item=suspicious_item,
            glint_count=high_risk_glint_count,
            suspicious_network_device_count=suspicious_network_device_count,
            suspicious_bluetooth_device_count=suspicious_bluetooth_device_count,
            user_lat=user_lat,
            user_lng=user_lng,
        )
        return {
            "risk_level": aux_risk_level.lower(),
            "risk_percentage": safe_risk,
            "risk_assessment_summary": f"初步評估於 {environment_type} 的「{suspicious_item}」發現異常光學反光訊號，系統算分機率為 {safe_risk}%。",
            "police_cheat_sheet": fallback_report,
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
