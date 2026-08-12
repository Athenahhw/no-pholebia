from __future__ import annotations
import os
import json
import base64
from typing import Optional
from dotenv import load_dotenv
from google import genai
from google.genai import types

# 1. 讀取 .env 中的 GEMINI_API_KEY
load_dotenv()
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")

if not GEMINI_API_KEY:
    raise ValueError("⚠️ 找不到 GEMINI_API_KEY！請檢查 backend/.env 檔案。")

client = genai.Client(api_key=GEMINI_API_KEY)


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
    呼叫 Google Gemini API 生成包含風險評估、報案敘述與 AI 助理查詢文案的 JSON 報告。
    """
    system_instruction = """
    你是一名專業的治安防護與隱私安全 AI 專家。
    請根據傳入的現場感測數據與畫面截圖，生成精準的風險評估報告與防護建議。

    判斷原則：
    1. 有畫面截圖時，以視覺影像為主；無截圖時，依據數據做保守判斷。
    2. 無線裝置偵測為加分項，無偵測到不代表完全安全。

    你必須 strictly 回傳標準 JSON 格式，包含以下 6 個 Key：
    1. "risk_level": "high" | "medium" | "low"
    2. "risk_percentage": 數字 (0 ~ 100)
    3. "risk_assessment_summary": 【風險評估】詳細分析為何此環境與物品有此風險，說明反光與無線訊號特徵。
    4. "police_cheat_sheet": 【報案敘述】50 字以內，方便使用者直接唸給警察聽。需提及座標 (lat, lng) 與具體物品位置。
    5. "action_cards": 陣列，包含 3 點具體實體處置建議（例如遮蔽、檢查）。
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
        return {
            "risk_level": aux_risk_level.lower(),
            "risk_percentage": aux_risk_percentage,
            "risk_assessment_summary": f"初步評估於 {environment_type} 的「{suspicious_item}」發現異常光學反光訊號，系統算分機率為 {aux_risk_percentage}%。",
            "police_cheat_sheet": f"報案小抄：我在座標 ({user_lat}, {user_lng}) 的 {environment_type}，發現【{suspicious_item}】有疑似針孔裝置，請派員協助處理。",
            "ai_assistant_summary": f"在 {environment_type} 掃描到疑慮物品「{suspicious_item}」，當前風險等級判定為 {aux_risk_level}，請優先採取遮蔽防護動作。",
            "action_cards": [
                f"1. 請使用不透明膠帶或貼紙遮蔽 {suspicious_item}",
                "2. 保持冷靜並注意自身隱私安全",
                "3. 攜帶個人貴重物品並視情況聯絡場所管理員"
            ]
        }


# ==========================================
# 本地獨立測試區塊
# ==========================================
if __name__ == "__main__":
    print("正在測試 llm_agent.py 獨立連線與 API 回傳格式...")

    test_result = generate_safety_plan_with_prompt(
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

    print("\n" + "="*50)
    print(" Gemini AI 回傳 JSON 測試結果：")
    print("="*50)
    print(json.dumps(test_result, ensure_ascii=False, indent=2))
