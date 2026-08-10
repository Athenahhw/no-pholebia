import os
import json
import base64
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
    screenshot_base64: str | None = None,
) -> dict:
    """
    呼叫 Google Gemini API 進行真實的多模態語意推理與法務生成。

    設計說明:
      - aux_risk_percentage / aux_risk_level 是 tms_engine 用公式算出來的
        「輔助訊號」,當作系統初步評估的參考值一併告訴LLM,但不直接當最終答案。
      - 如果有附上截圖(screenshot_base64),LLM會實際"看圖"重新評估,
        自己給出最終的 risk_level / risk_percentage,可能跟輔助訊號不同,
        以LLM實際看到的畫面內容為準。
      - wifi_detected / 藍牙偵測數量只能當加分項,系統指示裡已明確告知LLM
        不能因為沒偵測到無線裝置就判定為低風險。
    """
    system_instruction = """
    你是一名專業的治安防護與隱私安全 AI 專家。
    請根據傳入的數據(以及附上的畫面截圖,如果有的話),進行嚴謹的情境合理性分析,並生成應急處置與報案資訊。

    重要判斷原則:
    1. 如果有附上畫面截圖,請以你「實際看到的畫面內容」為主要判斷依據,不要只依賴文字數據。
       系統初步評估的威脅機率只是輔助參考,你可以依據截圖內容修正這個評估。
    2. 「可疑Wi-Fi串流」「同網段裝置」「藍牙裝置」的偵測結果只能當作加分項:
       偵測到可疑裝置可以提高風險評估的信心度,但沒有偵測到不代表安全,
       因為許多針孔攝影機不會連接使用者所在的無線網路,不要因為沒偵測到
       無線裝置就判定為低風險。
    3. 光學反光分數與高風險反光點數量,代表使用者晃動手機時反光的閃爍程度,
       數值越高越可能是鏡頭的方向性反光,一般反光物比較穩定。
    4. 如果沒有附上截圖,請基於文字數據做保守判斷,並在分析中註明這是在
       沒有畫面的情況下做的推測。

    你必須 strictly 回傳標準 JSON 格式，包含以下 6 個 Key：
    1. "risk_level": 字串，必須是 "high"、"medium"、"low" 三者之一，這是你根據所有資訊(含截圖)做出的最終判斷。
    2. "risk_percentage": 數字，0~100之間，代表你判斷的風險機率，這是最終判斷，可以跟系統初步評估不同。
    3. "plausibility_reasoning": 簡短分析為何在此空間與特定物品會出現此風險等級，如果有看截圖，請說明你在畫面中實際看到了什麼。
    4. "action_cards": 一個字串陣列，包含 3 點當下的實體處置建議（例如對該物品進行遮蔽或檢查）。
    5. "police_cheat_sheet": 一段 50 字以內、方便使用者驚慌時直接朗讀給警察聽的報案小抄。內容必須明確提及地點座標與【懷疑藏有針孔的具體物品/位置】。
    6. "report_letter": 一封正式的檢舉/舉證通知函範本。
    """

    prompt_content = f"""
    【當前檢測數據】
    - 使用者輸入的空間名稱: "{environment_type}"
    - 現場發現的異常物品/位置: "{suspicious_item}"
    - 系統初步評估威脅機率(輔助參考,非最終答案): {aux_risk_percentage}% (等級: {aux_risk_level})
    - 光學反光分數: {glint_score}(共{total_glint_count}個反光點,其中{high_risk_glint_count}個為高閃爍分數)
    - 是否發現可疑 Wi-Fi 串流: {wifi_detected}(同網段共{network_device_count}個裝置,{suspicious_network_device_count}個開放攝影機常見通訊埠)
    - 藍牙裝置掃描: 共{bluetooth_device_count}個裝置,{suspicious_bluetooth_device_count}個命名可疑
    - 當前 GPS 座標: ({user_lat}, {user_lng})
    - 是否附有畫面截圖: {"是,請以截圖內容為主要判斷依據" if screenshot_base64 else "否,請基於以上數據做保守判斷"}
    """

    # ---- 組成 contents:有截圖的話把圖片一起放進去做多模態分析 ----
    contents = []
    if screenshot_base64:
        try:
            image_bytes = base64.b64decode(screenshot_base64)
            contents.append(types.Part.from_bytes(data=image_bytes, mime_type="image/jpeg"))
        except Exception as e:
            print(f"⚠️ 截圖解碼失敗,將略過圖片,只用文字資料分析: {e}")
    contents.append(prompt_content)

    try:
        response = client.models.generate_content(
            model="gemini-2.5-flash",
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
        # 保底回應,確保API連線失敗時前端還是拿得到一個能顯示的結果,
        # 用輔助訊號分數當保底,並在原因裡註明是保底回應。
        return {
            "risk_level": aux_risk_level.lower(),
            "risk_percentage": aux_risk_percentage,
            "plausibility_reasoning": f"AI服務暫時連線異常,以下為根據感測數據的初步推估:於 {environment_type} 的「{suspicious_item}」檢測出 {aux_risk_percentage}% 的異常威脅,建議稍後重新掃描以取得完整分析。",
            "action_cards": [f"1. 請保持冷靜，嘗試用遮蔽物蓋住{suspicious_item}。", "2. 攜帶隨身物品離開該區域。", "3. 稍後重新掃描以取得AI完整分析。"],
            "police_cheat_sheet": f"報案小抄：我在座標 ({user_lat}, {user_lng}) 的{environment_type}，發現【{suspicious_item}】有異常針孔偷拍設備，請派員協助。",
            "report_letter": f"緊急檢舉函：於座標 ({user_lat}, {user_lng}) 的 {suspicious_item} 發現異常偷拍訊號。"
        }


# ==========================================
# 本地測試區塊
# ==========================================
if __name__ == "__main__":
    print(" 正在連線至 Google 雲端 Gemini API ...")

    # 測試傳入具體物品(不含截圖,測試純文字模式)
    result = generate_safety_plan_with_prompt(
        environment_type="浴室隔間",
        suspicious_item="黑色雙孔牆面插座",
        aux_risk_percentage=98.5,
        aux_risk_level="HIGH",
        glint_score=0.9,
        high_risk_glint_count=2,
        total_glint_count=3,
        wifi_detected=True,
        network_device_count=1,
        suspicious_network_device_count=1,
        bluetooth_device_count=0,
        suspicious_bluetooth_device_count=0,
        user_lat=25.0501,
        user_lng=121.5132,
        screenshot_base64=None,
    )

    print("\n" + "="*40)
    print(" Gemini AI 產出結果：")
    print("="*40)
    print(json.dumps(result, ensure_ascii=False, indent=2))