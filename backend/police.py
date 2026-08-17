import json
import os
from fastapi import APIRouter

router = APIRouter(prefix="/api/police-stations", tags=["Police Stations"])

CURRENT_VERSION = 1  # 未來如果有更新 JSON 檔案，就把版本號改成 2, 3...
JSON_PATH = os.path.join(os.path.dirname(__file__), "data", "police_stations.json")

@router.get("")
def get_police_stations():
    """回傳最新版本號與全台警局清單"""
    try:
        with open(JSON_PATH, "r", encoding="utf-8") as f:
            stations = json.load(f)
        return {
            "version": CURRENT_VERSION,
            "data": stations
        }
    except Exception as e:
        return {"error": f"無法讀取警局資料: {str(e)}"}