import os
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from typing import List, Optional

from pipeline import run_anti_pinhole_inference

# 初始化 FastAPI 應用程式
app = FastAPI(
    title="隱私防護與安全評估 API",
    description="結合多模態感測數據與 Google Gemini 雲端 AI 語意推理之 API 服務",
    version="1.0.0"
)

# 設定 CORS (跨域資源共享)，允許前端網頁或手機 App (如 Flutter) 順利呼叫 API
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # 開發階段允許所有來源連線
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 2. 定義前端傳入的 Request 資料格式 (新增可疑物品與紅外線欄位)
class AnalyzeRequest(BaseModel):
    environment_type: str = Field(..., description="使用者輸入的空間名稱", example="台北101 3樓女廁")
    suspicious_item: str = Field("牆面異常裝置", description="可疑物品名稱或位置", example="牆面雙孔掛衣鉤")  
    glint_score: float = Field(0.0, description="光學反光顯著度分數 (0.0 ~ 1.0)", example=0.85)
    wifi_detected: bool = Field(False, description="是否發現可疑 Wi-Fi 串流訊號", example=True)
    infrared_detected: bool = Field(False, description="是否發現紅外線補光訊號", example=False)         
    user_lat: float = Field(25.0501, description="使用者當前 GPS 緯度", example=25.0501)
    user_lng: float = Field(121.5132, description="使用者當前 GPS 經度", example=121.5132)

@app.get("/")
def read_root():
    return {
        "message": " 隱私安全防護 API 服務正常運作中！",
        "docs": "http://127.0.0.1:8000/docs"
    }

@app.post("/api/v1/analyze")
def analyze_privacy_risk(payload: AnalyzeRequest):
    """
    主要分析端點：接收感測特徵、可疑物品與空間名稱，經由 Pipeline 算出威脅機率並由 Gemini LLM 生成處置小抄
    """
    try:
        # 呼叫一鍵推理流水線 (內部會交給 tms_engine 算分，再交給 llm_agent 產出文字)
        final_result = run_anti_pinhole_inference(
            environment_type=payload.environment_type,
            suspicious_item=payload.suspicious_item,
            optical_glint_score=payload.glint_score,
            wifi_camera_detected=payload.wifi_detected,
            infrared_detected=payload.infrared_detected,
            user_lat=payload.user_lat,
            user_lng=payload.user_lng
        )

        return final_result

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"伺服器運算異常: {str(e)}")

# 當直接執行 python3 main.py 時自動啟動伺服器
if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="127.0.0.1", port=8000, reload=True)
