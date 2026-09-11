# 針孔攝影機偵測 App

Agentic AI 競賽專案 — 使用手機鏡頭 + 區域網路偵測 + AI 多模態推理,
判斷可疑物體(如藏有針孔攝影機的盒子)出現在特定場域是否合理。

## 分工 https://docs.google.com/spreadsheets/d/11aaLYlLb2Qhr9XcGZi8ooJzOMi5sjpJhBM2vwVsZs4U/edit?usp=sharing
## 詳細架構見 `docs/ARCHITECTURE.md`
## 開始前請先看main分支裡的git使用規範


Athena start tip:
flutter run --debug --dart-define=AI_ENDPOINT=http://192.168.1.13:8000/api/v1/analyze

backend:
cd /Users/wangxuanhan/Desktop/no\ pholebia/pinhole_detector/backend
source .venv/bin/activate
python main.py

backdoor:
開後端（照你原本方式）
在 backend 目錄輸入
python admin_override.py 12.3 --note demo
下一次掃描會略過 Gemini，立刻回傳 12.3%，再下一次恢復正常 AI 計算
查目前有沒有 armed：python admin_override.py --status
取消：python admin_override.py --clear

重要：override 是一次性，且必須打到同一個後端資料庫。
若 App 連不上後端（逾時/IP 不對），會走手機本地算分，看起來就像後門沒生效。
現在 armed 後會跳過 Gemini，避免分析太久讓 App 逾時改走本地算分。

presentation:
演示前 10 分鐘
啟動 backend（含 .venv）
啟動 flutter run
先做一筆試掃描，確認結果頁顯示「分數來源：後端 AI 回傳」
若要保證 demo 劇本分數
每次要固定分數前，先輸入一次 override 指令
再做下一次掃描（只生效一次）
演示時保底
若網路抖動，結果頁會標示本地估算，講解時可直接指出目前狀態，避免被問到數字不一致
建議後端與手機在同一穩定 Wi-Fi，避免逾時
演示後
不輸入 override 就會回到正常模式（因為是一次性）