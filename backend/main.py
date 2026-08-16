import os
from datetime import datetime
from contextlib import asynccontextmanager
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field, ConfigDict
from typing import List, Optional

from pipeline import run_anti_pinhole_inference
import storage
from police import router as police_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    # 服務啟動時初始化資料庫
    storage.init_db()
    yield


app = FastAPI(
    title="隱私防護與安全評估 API",
    description="結合多模態感測數據與 Google Gemini 雲端 AI 語意推理之 API 服務",
    version="2.1.0",
    lifespan=lifespan,
)

app.include_router(police_router)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


class GlintCandidate(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    x: int
    y: int
    radius: int
    brightness: float
    flicker_score: Optional[float] = Field(None, alias="flickerScore")


class BoundingBox(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    x: float
    y: float
    width: float
    height: float
    confidence: float
    object_class: str = Field(..., alias="class")


class NetworkDevice(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    ip: str
    open_ports: List[int] = Field(default_factory=list, alias="openPorts")
    looks_like_camera: bool = Field(False, alias="looksLikeCamera")


class BluetoothDeviceInfo(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    name: str
    device_id: str = Field(..., alias="deviceId")
    rssi: int
    suspicious: bool


class AnalyzeRequest(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    glints: List[GlintCandidate] = Field(default_factory=list)
    bounding_boxes: List[BoundingBox] = Field(default_factory=list, alias="boundingBoxes")
    total_glint_count: int = Field(0, alias="totalGlintCount")
    high_risk_glint_count: int = Field(0, alias="highRiskGlintCount")
    ambient_brightness_at_start: float = Field(0.0, alias="ambientBrightnessAtStart")
    torch_used_during_scan: bool = Field(False, alias="torchUsedDuringScan")
    object_detection_available: bool = Field(False, alias="remoteYoloAvailable")
    environment_context: Optional[str] = Field(None, alias="environmentContext")
    screenshot_base64: Optional[str] = Field(None, alias="screenshotBase64")
    network_devices: List[NetworkDevice] = Field(default_factory=list, alias="networkDevices")
    bluetooth_devices: List[BluetoothDeviceInfo] = Field(default_factory=list, alias="bluetoothDevices")
    latitude: Optional[float] = Field(None, alias="latitude")
    longitude: Optional[float] = Field(None, alias="longitude")
    scan_started_at: Optional[str] = Field(None, alias="scanStartedAt")
    scan_ended_at: Optional[str] = Field(None, alias="scanEndedAt")
    scan_duration_ms: Optional[int] = Field(None, alias="scanDurationMs")


class ReviewDecision(BaseModel):
    decision: str = Field(..., description="'approved' 或 'rejected'")
    note: Optional[str] = Field(None, description="審核備註,選填")


@app.get("/")
def read_root():
    return {
        "message": "隱私安全防護 API 服務正常運作中！",
        "docs": "http://127.0.0.1:8000/docs",
    }


@app.post("/api/v1/analyze")
def analyze_privacy_risk(payload: AnalyzeRequest):
    """
    主要分析端點。收到的每一筆案件狀態都是 'pending'(待審核),
    不會自動出現在案件地圖上,要等後台人工審核核准後才算數。
    """
    try:
        final_result = run_anti_pinhole_inference(payload)
        record_id = storage.save_record(payload, final_result)
        final_result["record_id"] = record_id
        final_result["review_status"] = "pending"
        return final_result

    except Exception as e:
        print(f" 伺服器運算異常: {str(e)}")
        raise HTTPException(status_code=500, detail=f"伺服器運算異常: {str(e)}")


# ============================================================
# 後台監控 + 審核用的端點
# ============================================================

@app.get("/api/v1/records")
def list_records(
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
    risk_level: Optional[str] = Query(None, description="篩選風險等級: HIGH/MEDIUM/LOW"),
    review_status: Optional[str] = Query(None, description="篩選審核狀態: pending/approved/rejected"),
):
    """列出歷史掃描紀錄,給後台監控介面用。"""
    return storage.list_records(limit=limit, offset=offset, risk_level=risk_level, review_status=review_status)


@app.get("/api/v1/records/{record_id}")
def get_record(record_id: int):
    """查詢單筆紀錄的完整內容(含原始輸入資料),給人工審核用。"""
    record = storage.get_record(record_id)
    if record is None:
        raise HTTPException(status_code=404, detail="找不到這筆紀錄")
    return record


@app.post("/api/v1/records/{record_id}/review")
def review_record(record_id: int, payload: ReviewDecision):
    """
    人工審核一筆案件。decision 傳 'approved' 才會讓這筆案件之後出現在
    案件地圖上,'rejected' 就永遠不會。
    """
    if payload.decision not in ("approved", "rejected"):
        raise HTTPException(status_code=400, detail="decision 必須是 'approved' 或 'rejected'")

    updated = storage.review_record(record_id, payload.decision, payload.note)
    if not updated:
        raise HTTPException(status_code=404, detail="找不到這筆紀錄")

    return {"record_id": record_id, "review_status": payload.decision}


@app.get("/api/v1/records/approved-for-map")
def get_approved_for_map():
    """取得所有已核准的案件,格式給案件地圖功能使用。"""
    return {"cases": storage.list_approved_for_map()}


@app.get("/api/v1/stats")
def get_stats():
    """簡易統計資訊,給後台監控整體App運作狀況用。"""
    return storage.get_stats()


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
