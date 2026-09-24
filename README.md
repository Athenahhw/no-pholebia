# No Pholebia

Agentic AI 競賽專案：利用手機鏡頭、區域網路偵測與 AI 多模態推理，判斷特定場域中是否存在可疑的針孔攝影機或隱藏式監控設備。

## 專案概述

本專案整合了前端 Flutter App、Python 後端推理服務，以及輔助風險評估邏輯，目的在於協助使用者檢查環境中是否存在具隱匿性與高風險特徵的攝影機裝置。

- 前端：Flutter / Dart
- 後端：Python
- 偵測維度：影像反光點、物件辨識、Wi‑Fi / 藍牙 異常訊號、環境上下文
- 主要目標：辨識可疑隱藏鏡頭與提供實務建議

## 分工

- 分工表：https://docs.google.com/spreadsheets/d/11aaLYlLb2Qhr9XcGZi8ooJzOMi5sjpJhBM2vwVsZs4U/edit?usp=sharing

## 架構說明

- 詳細架構請見 `docs/ARCHITECTURE.md`
- 開發前請先查看 main 分支中的 Git 使用規範

## 啟動方式

### Flutter 前端

```bash
flutter run --debug --dart-define=AI_ENDPOINT=http://192.168.1.13:8000/api/v1/analyze
```

### Python 後端

```bash
cd /Users/wangxuanhan/Desktop/no\ pholebia/pinhole_detector/backend
source .venv/bin/activate
python main.py
```

## Demo / Backdoor Override

在 backend 目錄中執行：

```bash
python admin_override.py 12.3 --note demo
```

這會讓下一次掃描直接略過 Gemini，立即回傳 12.3% 的風險值，並在下一次正常計算時恢復原本 AI 邏輯。

查詢目前是否已經 armed：

```bash
python admin_override.py --status
```

取消 override：

```bash
python admin_override.py --clear
```

### 注意事項

- override 是一次性，且必須打到同一個後端資料庫。
- 若 App 無法連上後端（例如逾時、IP 不正確），則會退回手機本地評估，這會讓畫面看起來像後門沒有生效。
- armed 後會跳過 Gemini，目的是避免分析過久導致 App 逾時，進而改走本地算分。

## 演示建議流程

### 演示前 10 分鐘

1. 啟動後端（含 `.venv`）
2. 啟動 Flutter App
3. 先做一筆試掃描，確認結果頁顯示「分數來源：後端 AI 回傳」

### 若要保證 demo 劇本分數

每次要固定分數前，先輸入一次 override 指令：

```bash
python admin_override.py 12.3 --note demo
```

再做下一次掃描；該次掃描只會生效一次。

### 演示時保底

- 若網路抖動，結果頁會標示本地估算
- 講解時可直接指出目前狀態，以避免被問到數字不一致
- 建議後端與手機位於同一穩定 Wi‑Fi，避免逾時

### 演示後

- 不輸入 override 就會回到正常模式
- 因為這是一次性設定，不會持續影響後續掃描

## 補充說明

Athena 開發小提示：

```bash
flutter run --debug --dart-define=AI_ENDPOINT=http://192.168.1.13:8000/api/v1/analyze
```

這個專案的設計之一，是在網路與後端服務穩定時，透過後端 AI 推理取得更可靠的風險判斷；在部分情況下，前端也保留了本地估算機制，作為容錯與演示說明之用。yes
