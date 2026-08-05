import os
import json
from dotenv import load_dotenv
from google import genai
from google.genai import types

# 1. 自動讀取 backend/.env 裡面的 GEMINI_API_KEY
load_dotenv()
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")

if not GEMINI_API_KEY:
    raise ValueError("⚠️ 找不到 GEMINI_API_KEY！請檢查 backend/.env 檔案是否正確建立。")

# 2. 初始化 Gemini 雲端 Client
client = genai.Client(api_key=GEMINI_API_KEY)

def generate_safety_plan_with_prompt(
    environment_type: str,
    risk_percentage: float,
    risk_level: str,
    glint_score: float,
    wifi_detected: bool,
    user_lat: float,
    user_lng: float,
    suspicious_item: str = "牆面異常裝置"  
) -> dict:
    """
    呼叫 Google Gemini API 進行真實的多模態語意推理與法務生成
    """
    system_instruction = """
    你是一名專業的治安防護與隱私安全 AI 專家。
    請根據傳入的數據，進行嚴謹的情境合理性分析，並生成應急處置與報案資訊。
    你必須 strictly 回傳標準 JSON 格式，包含以下 4 個 Key：
    1. "plausibility_reasoning": 簡短分析為何在此空間與特定物品會出現此風險等級。
    2. "action_cards": 一個字串陣列，包含 3 點當下的實體處置建議（例如對該物品進行遮蔽或檢查）。
    3. "police_cheat_sheet": 一段 50 字以內、方便使用者驚慌時直接朗讀給警察聽的報案小抄。內容必須明確提及地點座標與【懷疑藏有針孔的具體物品/位置】。
    4. "report_letter": 一封正式的檢舉/舉證通知函範本。
    """

    prompt_content = f"""
    【當前檢測數據】
    - 使用者輸入的空間名稱: "{environment_type}"
    - 現場發現的異常物品/位置: "{suspicious_item}"
    - 系統判定威脅機率: {risk_percentage}% (等級: {risk_level})
    - 光學反光分數: {glint_score}
    - 是否發現可疑 Wi-Fi 串流: {wifi_detected}
    - 當前 GPS 座標: ({user_lat}, {user_lng})
    """

    try:
        response = client.models.generate_content(
            model="gemini-2.5-flash",
            contents=prompt_content,
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
            "plausibility_reasoning": f"於 {environment_type} 的「{suspicious_item}」檢測出 {risk_percentage}% 的異常威脅。",
            "action_cards": [f"1. 請保持冷靜，嘗試用遮蔽物蓋住{suspicious_item}。", "2. 攜帶隨身物品離開該區域。"],
            "police_cheat_sheet": f"報案小抄：我在座標 ({user_lat}, {user_lng}) 的{environment_type}，發現【{suspicious_item}】有異常針孔偷拍設備，請派員協助。",
            "report_letter": f"緊急檢舉函：於座標 ({user_lat}, {user_lng}) 的 {suspicious_item} 發現異常偷拍訊號。"
        }

# ==========================================
# 本地測試區塊
# ==========================================
if __name__ == "__main__":
    print(" 正在連線至 Google 雲端 Gemini API ...")
    
    # 測試傳入具體物品
    result = generate_safety_plan_with_prompt(
        environment_type="浴室隔間",
        suspicious_item="黑色雙孔牆面插座", 
        risk_percentage=98.5,
        risk_level="HIGH",
        glint_score=0.9,
        wifi_detected=True,
        user_lat=25.0501,
        user_lng=121.5132
    )
    
    print("\n" + "="*40)
    print(" Gemini AI 產出結果：")
    print("="*40)
    print(json.dumps(result, ensure_ascii=False, indent=2))
