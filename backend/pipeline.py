import json
from tms_engine import calculate_threat_score
from llm_agent import generate_safety_plan_with_prompt

def run_anti_pinhole_inference(
    environment_type: str,
    optical_glint_score: float,
    wifi_camera_detected: bool,
    infrared_detected: bool,
    user_lat: float,
    user_lng: float,
    suspicious_item: str = "牆面異常裝置"
) -> dict:
    """
    一鍵執行的 AI 推理流水線 (Full Inference Pipeline)
    """
    print(" 正在接收前端傳入特徵...")
    
    # 執行多模態機率加權演算法
    threat_result = calculate_threat_score(
        optical_glint_score=optical_glint_score,
        wifi_camera_detected=wifi_camera_detected,
        infrared_detected=infrared_detected,
        environment_type=environment_type
    )
    
    risk_percentage = threat_result["risk_percentage"]
    risk_level = threat_result["risk_level"]
    print(f" 機率演算法完成：風險機率 = {risk_percentage}% ({risk_level})")

    # 將算分結果、可疑物品細節與 GPS 座標給 LLM 進行情境推理與法務生成
    print(" 正在調用 LLM 生成安全指引與報案小抄...")
    llm_result = generate_safety_plan_with_prompt(
        environment_type=environment_type,
        suspicious_item=suspicious_item, 
        risk_percentage=risk_percentage,
        risk_level=risk_level,
        glint_score=optical_glint_score,
        wifi_detected=wifi_camera_detected,
        user_lat=user_lat,
        user_lng=user_lng
    )

    # 打包成最終要給前端 App 的完整 JSON 回傳格式
    final_output = {
        "status": "success",
        "threat_assessment": {
            "risk_percentage": risk_percentage,
            "risk_level": risk_level,
            "raw_score": threat_result["raw_score"]
        },
        "ai_reasoning_and_actions": {
            "plausibility_reasoning": llm_result["plausibility_reasoning"],
            "action_cards": llm_result["action_cards"],
            "police_cheat_sheet": llm_result["police_cheat_sheet"],
            "report_letter": llm_result["report_letter"]
        }
    }
    
    return final_output


# ==========================================
# 本地流水線測試
# ==========================================
if __name__ == "__main__":
    print("=== 開始測試完整 AI 後端推理流程 ===")
    
    # 模擬前端傳進來的數據
    mock_input_data = {
        "environment_type": "fitting_room", # 試衣間
        "suspicious_item": "牆面金屬掛衣鉤", # 傳入具體異常物品名稱
        "optical_glint_score": 0.85,        # 高反光
        "wifi_camera_detected": True,       # 發現異常 Wi-Fi
        "infrared_detected": False,         # 無紅外線
        "user_lat": 25.0339,               # 台北 101 附近座標
        "user_lng": 121.5645
    }

    # 執行完整推理
    output = run_anti_pinhole_inference(**mock_input_data)

    print("\n" + "="*40)
    print(" 最終 AI 推理輸出結果 JSON (將回傳給 Flutter App)：")
    print("="*40)
    print(json.dumps(output, ensure_ascii=False, indent=2))
