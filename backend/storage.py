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
    """啟動時建表,如果已存在就跳過。"""
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
            review_status TEXT NOT NULL DEFAULT 'pending',
            reviewed_at TEXT,
            reviewed_note TEXT,
            raw_request_json TEXT NOT NULL,
            raw_response_json TEXT NOT NULL
        )
        """
    )
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS runtime_controls (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
        """
    )
    # 相容舊資料庫:如果是從舊版升級上來,沒有 review_status 欄位的話補上
    existing_cols = {row["name"] for row in conn.execute("PRAGMA table_info(scan_records)")}
    if "review_status" not in existing_cols:
        conn.execute("ALTER TABLE scan_records ADD COLUMN review_status TEXT NOT NULL DEFAULT 'pending'")
    if "reviewed_at" not in existing_cols:
        conn.execute("ALTER TABLE scan_records ADD COLUMN reviewed_at TEXT")
    if "reviewed_note" not in existing_cols:
        conn.execute("ALTER TABLE scan_records ADD COLUMN reviewed_note TEXT")
    conn.commit()
    conn.close()


def arm_next_risk_override(risk_percentage: float, note: Optional[str] = None):
    """
    設定「下一筆」分析要強制使用的風險百分比。
    一旦被 consume，就會自動刪除，不會持續生效。
    """
    normalized = max(0.0, min(float(risk_percentage), 30.0))
    payload = {
        "risk_percentage": normalized,
        "note": note or "",
        "armed_at": datetime.now(timezone.utc).isoformat(),
    }

    conn = _get_connection()
    conn.execute(
        """
        INSERT INTO runtime_controls (key, value, updated_at)
        VALUES (?, ?, ?)
        ON CONFLICT(key) DO UPDATE SET
            value = excluded.value,
            updated_at = excluded.updated_at
        """,
        (
            "next_risk_override",
            json.dumps(payload, ensure_ascii=False),
            datetime.now(timezone.utc).isoformat(),
        ),
    )
    conn.commit()
    conn.close()
    return payload


def peek_next_risk_override() -> Optional[dict]:
    """讀取目前 armed 的 override，不刪除。"""
    conn = _get_connection()
    row = conn.execute(
        "SELECT value FROM runtime_controls WHERE key = ?",
        ("next_risk_override",),
    ).fetchone()
    conn.close()
    if row is None:
        return None
    try:
        parsed = json.loads(row["value"])
        if isinstance(parsed, dict):
            return parsed
    except Exception:
        pass
    return None


def clear_next_risk_override() -> bool:
    conn = _get_connection()
    cursor = conn.execute(
        "DELETE FROM runtime_controls WHERE key = ?",
        ("next_risk_override",),
    )
    conn.commit()
    deleted = cursor.rowcount > 0
    conn.close()
    return deleted


def consume_next_risk_override() -> Optional[dict]:
    """
    取出並刪除一次性 override；如果沒設定則回傳 None。
    """
    conn = _get_connection()
    row = conn.execute(
        "SELECT value FROM runtime_controls WHERE key = ?",
        ("next_risk_override",),
    ).fetchone()
    if row is None:
        conn.close()
        return None

    conn.execute("DELETE FROM runtime_controls WHERE key = ?", ("next_risk_override",))
    conn.commit()
    conn.close()

    try:
        parsed = json.loads(row["value"])
        if isinstance(parsed, dict):
            return parsed
    except Exception:
        pass
    return None


def save_record(payload, result: dict) -> int:
    """
    儲存一筆掃描紀錄,狀態預設為 'pending'(待審核)。
    **不會**自動進入案件地圖,要等 approve_record() 之後才算數。
    """
    conn = _get_connection()

    request_dict = payload.model_dump(by_alias=True)
    has_screenshot = bool(request_dict.get("screenshotBase64")) or bool(request_dict.get("glintScreenshotsBase64"))
    request_dict["screenshotBase64"] = None if not request_dict.get("screenshotBase64") else "(已省略,未儲存於資料庫)"
    if request_dict.get("glintScreenshotsBase64"):
        request_dict["glintScreenshotsBase64"] = f"(已省略 {len(request_dict['glintScreenshotsBase64'])} 張 glint 截圖)"

    cursor = conn.execute(
        """
        INSERT INTO scan_records (
            created_at, environment_context, risk_level, risk_percentage,
            total_glint_count, high_risk_glint_count,
            network_device_count, bluetooth_device_count,
            has_screenshot, review_status, raw_request_json, raw_response_json
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?)
        """,
        (
            datetime.now(timezone.utc).isoformat(),
            payload.environment_context,
            result.get("risk_level") or result.get("riskLevel"),
            result.get("risk_percentage") or result.get("riskPercentage"),
            payload.total_glint_count,
            payload.high_risk_glint_count,
            len(payload.network_devices),
            len(payload.bluetooth_devices),
            1 if has_screenshot else 0,
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
    """列出紀錄摘要。review_status 可篩選 'pending'/'approved'/'rejected'。"""
    conn = _get_connection()

    query = """
        SELECT id, created_at, environment_context, risk_level, risk_percentage,
               total_glint_count, high_risk_glint_count,
               network_device_count, bluetooth_device_count, has_screenshot,
               review_status, reviewed_at, reviewed_note
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
    """查詢單筆完整紀錄,含原始request/response JSON,給人工審核用。"""
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
    """
    人工審核一筆紀錄。decision 必須是 'approved' 或 'rejected'。
    回傳 True 代表更新成功,False 代表找不到這筆紀錄。
    """
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
    取得所有『已核准』的紀錄,格式對應案件地圖需要的資料。
    """
    conn = _get_connection()
    rows = conn.execute(
        """
        SELECT id, created_at, environment_context, risk_level, risk_percentage,
               raw_request_json, raw_response_json
        FROM scan_records
        WHERE review_status = 'approved'
        ORDER BY id DESC
        """
    ).fetchall()
    conn.close()

    results = []
    for r in rows:
        record = dict(r)
        record["raw_request"] = json.loads(record.pop("raw_request_json"))
        record["raw_response"] = json.loads(record.pop("raw_response_json"))
        results.append(record)
    return results


def search_cases_by_destination(destination: str) -> list:
    """
    根據目的地關鍵字從已核准 (approved) 案件中搜尋歷史紀錄。
    """
    all_approved = list_approved_for_map()
    if not destination:
        return []

    matched = []
    for case in all_approved:
        req = case.get("raw_request", {})
        resp = case.get("raw_response", {})

        loc_name = case.get("environment_context") or req.get("environmentContext", "")
        detail = resp.get("risk_assessment_summary") or resp.get("ai_assistant_summary", "")

        if destination in loc_name or loc_name in destination or destination in detail:
            matched.append({
                "location_name": loc_name or destination,
                "detail": detail
            })

    return matched


def get_stats():
    """簡易統計,給後台監控整體App運作狀況用。"""
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
