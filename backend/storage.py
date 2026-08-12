import sqlite3
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

DB_PATH = Path(__file__).parent / "scan_records.db"


def _get_connection():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    conn = _get_connection()
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS scan_records (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            created_at TEXT NOT NULL,
            environment_context TEXT,
            risk_level TEXT,
            risk_percentage REAL,
            total_glint_count INTEGER,
            high_risk_glint_count INTEGER,
            network_device_count INTEGER,
            bluetooth_device_count INTEGER,
            has_screenshot INTEGER,
            latitude REAL,
            longitude REAL,
            review_status TEXT NOT NULL DEFAULT 'pending',
            reviewed_at TEXT,
            reviewed_note TEXT,
            raw_request_json TEXT NOT NULL,
            raw_response_json TEXT NOT NULL
        )
        """
    )
    existing_cols = {row["name"] for row in conn.execute("PRAGMA table_info(scan_records)")}
    for col, col_type in [
        ("review_status", "TEXT NOT NULL DEFAULT 'pending'"),
        ("reviewed_at", "TEXT"),
        ("reviewed_note", "TEXT"),
        ("latitude", "REAL"),
        ("longitude", "REAL"),
    ]:
        if col not in existing_cols:
            conn.execute(f"ALTER TABLE scan_records ADD COLUMN {col} {col_type}")
    conn.commit()
    conn.close()


def save_record(payload, result: dict) -> int:
    conn = _get_connection()

    request_dict = payload.model_dump(by_alias=True)
    has_screenshot = bool(request_dict.get("screenshotBase64"))
    request_dict["screenshotBase64"] = None if not has_screenshot else "(已省略,未儲存於資料庫)"

    latitude = getattr(payload, "latitude", None)
    longitude = getattr(payload, "longitude", None)

    cursor = conn.execute(
        """
        INSERT INTO scan_records (
            created_at, environment_context, risk_level, risk_percentage,
            total_glint_count, high_risk_glint_count,
            network_device_count, bluetooth_device_count,
            has_screenshot, latitude, longitude, review_status,
            raw_request_json, raw_response_json
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?)
        """,
        (
            datetime.now(timezone.utc).isoformat(),
            payload.environment_context,
            result.get("riskLevel"),
            result.get("riskPercentage"),
            payload.total_glint_count,
            payload.high_risk_glint_count,
            len(payload.network_devices),
            len(payload.bluetooth_devices),
            1 if has_screenshot else 0,
            latitude,
            longitude,
            json.dumps(request_dict, ensure_ascii=False),
            json.dumps(result, ensure_ascii=False),
        ),
    )
    conn.commit()
    record_id = cursor.lastrowid
    conn.close()
    return record_id


def list_records(limit: int = 50, offset: int = 0, risk_level: Optional[str] = None,
                  review_status: Optional[str] = None):
    conn = _get_connection()

    query = """
        SELECT id, created_at, environment_context, risk_level, risk_percentage,
               total_glint_count, high_risk_glint_count,
               network_device_count, bluetooth_device_count, has_screenshot,
               latitude, longitude, review_status, reviewed_at, reviewed_note
        FROM scan_records
    """
    conditions = []
    params = []
    if risk_level:
        conditions.append("risk_level = ?")
        params.append(risk_level.lower())
    if review_status:
        conditions.append("review_status = ?")
        params.append(review_status.lower())
    if conditions:
        query += " WHERE " + " AND ".join(conditions)

    query += " ORDER BY id DESC LIMIT ? OFFSET ?"
    params.extend([limit, offset])

    rows = conn.execute(query, params).fetchall()
    conn.close()
    return {"records": [dict(r) for r in rows], "limit": limit, "offset": offset}


def get_record(record_id: int):
    conn = _get_connection()
    row = conn.execute("SELECT * FROM scan_records WHERE id = ?", (record_id,)).fetchone()
    conn.close()

    if row is None:
        return None

    record = dict(row)
    record["raw_request"] = json.loads(record.pop("raw_request_json"))
    record["raw_response"] = json.loads(record.pop("raw_response_json"))
    return record


def review_record(record_id: int, decision: str, note: Optional[str] = None) -> bool:
    if decision not in ("approved", "rejected"):
        raise ValueError("decision 必須是 'approved' 或 'rejected'")

    conn = _get_connection()
    cursor = conn.execute(
        """
        UPDATE scan_records
        SET review_status = ?, reviewed_at = ?, reviewed_note = ?
        WHERE id = ?
        """,
        (decision, datetime.now(timezone.utc).isoformat(), note, record_id),
    )
    conn.commit()
    updated = cursor.rowcount > 0
    conn.close()
    return updated


def list_approved_for_map():
    """
    取得所有已核准的紀錄,輸出格式對齊 assets/json/cases.json 的 schema:
    id / title / location_name / latitude / longitude / start_date / end_date /
    category / source_type / verified

    註: latitude/longitude 如果前端沒有成功取得GPS(定位失敗/拒絕權限),
    這裡會是 None,案件地圖那邊要處理這種資料不完整、無法定位的情況
    (例如不畫在地圖上,或畫在一個「未知位置」的分類清單裡)。
    """
    conn = _get_connection()
    rows = conn.execute(
        """
        SELECT id, created_at, environment_context, risk_level, risk_percentage,
               latitude, longitude
        FROM scan_records
        WHERE review_status = 'approved'
        ORDER BY id DESC
        """
    ).fetchall()
    conn.close()

    cases = []
    for r in rows:
        row = dict(r)
        date_str = row["created_at"][:10] if row["created_at"] else None
        risk_label = {"high": "高風險", "medium": "中風險", "low": "低風險"}.get(
            (row["risk_level"] or "").lower(), "未知風險"
        )
        cases.append({
            "id": row["id"],
            "title": f"{row['environment_context'] or '未知地點'} 疑似針孔攝影機案件({risk_label})",
            "location_name": row["environment_context"] or "地點未提供",
            "latitude": row["latitude"],
            "longitude": row["longitude"],
            "start_date": date_str,
            "end_date": date_str,
            "category": "App使用者回報",
            "source_type": "APP_SCAN",
            "verified": True,  # 一定是true,因為只有審核核准過的才會出現在這裡
        })
    return cases


def get_stats():
    conn = _get_connection()

    total = conn.execute("SELECT COUNT(*) AS c FROM scan_records").fetchone()["c"]
    by_level = conn.execute(
        "SELECT risk_level, COUNT(*) AS c FROM scan_records GROUP BY risk_level"
    ).fetchall()
    by_review = conn.execute(
        "SELECT review_status, COUNT(*) AS c FROM scan_records GROUP BY review_status"
    ).fetchall()
    recent = conn.execute(
        "SELECT COUNT(*) AS c FROM scan_records WHERE created_at >= datetime('now', '-1 day')"
    ).fetchone()["c"]

    conn.close()
    return {
        "total_scans": total,
        "scans_last_24h": recent,
        "by_risk_level": {r["risk_level"]: r["c"] for r in by_level},
        "by_review_status": {r["review_status"]: r["c"] for r in by_review},
    }