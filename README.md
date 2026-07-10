# 針孔攝影機偵測 App

Agentic AI 競賽專案 — 使用手機鏡頭 + 區域網路偵測 + AI 多模態推理,
判斷可疑物體(如藏有針孔攝影機的盒子)出現在特定場域是否合理。

## 分工
| 模組 | 資料夾 | 負責人 |
|---|---|---|
| YOLO物理特徵/反光偵測 | lib/detection | 你 |
| 風險評估 | lib/risk | TBD |
| GPS報案/地圖/法務 | lib/report | TBD |
| 介面 | lib/ui | TBD |
| 多模態/語義推理(後端) | lib/agent | TBD |
| 案件地圖資料來源/知識庫 | (後端另建 repo?) | TBD |

詳細架構見 `docs/ARCHITECTURE.md`
