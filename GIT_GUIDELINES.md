# No Pholebia — Git 協作規範

適用對象：所有參與 `no-pholebia` repo 的組員。
目的：讓多人協作時分支不亂、commit 好追蹤、PR 好 review、demo 前不會因為衝突而崩潰。

---

## 1. 分支結構

```
main        ← 永遠是「可以上台展示」的穩定版本
  │
develop     ← 整合分支,所有 feature 合併到這裡先測試
  │
  ├── feature/detection        (YOLO物理特徵/反光偵測 — 你)
  ├── feature/network-scan     (區域網路異常偵測)
  ├── feature/agent-reasoning  (多模態推理/語義推理)
  ├── feature/risk-assessment  (風險評估與引導)
  ├── feature/report-map       (GPS報案/地圖/自動化法務)
  └── feature/ui               (介面)
以上舉例，可以參考
```

### 各分支角色

| 分支 | 用途 | 誰可以直接 push |
|---|---|---|
| `main` | 穩定、demo用,只接受從 `develop` 合併過來的 PR | 沒有人(只能透過 PR) |
| `develop` | 整合各功能,日常開發的匯集點 | 沒有人(只能透過 PR) |
| `feature/*` | 個人/單一功能開發用 | 該功能負責人 |

**重點：沒有人應該直接對 `main` 或 `develop` 下 `git push`,一律走 Pull Request。**
這樣才能保留 review 機會,不會有人一個手滑把壞掉的 code 推上主線。

---

## 2. 分支命名規則

格式：`類型/簡短描述`(全小寫、用連字號分隔,不要用中文或空格)

| 類型 | 用途 | 範例 |
|---|---|---|
| `feature/` | 新功能開發 | `feature/detection`、`feature/glint-flicker` |
| `fix/` | 修 bug | `fix/camera-permission-crash` |
| `docs/` | 只改文件 | `docs/update-architecture` |
| `refactor/` | 重構,不改變功能行為 | `refactor/detection-result-model` |
| `chore/` | 雜項(設定檔、依賴更新等) | `chore/update-pubspec` |

大功能底下如果要拆更細的子分支,可以用 `feature/detection-glint`、`feature/detection-yolo` 這樣命名,合併時再一起併回 `feature/detection` 或直接併回 `develop`,團隊討論決定即可。

---

## 3. Commit Message 規範

採用簡化版 **Conventional Commits** 格式：

```
<類型>: <簡短描述(50字以內,現在式動詞開頭)>

<可選的詳細說明,說明為什麼這樣改、有什麼副作用>
```

### 類型(type)對照表

| 類型 | 說明 |
|---|---|
| `feat` | 新增功能 |
| `fix` | 修 bug |
| `docs` | 只改文件/註解 |
| `style` | 格式調整(空白、縮排),不影響邏輯 |
| `refactor` | 重構程式碼,行為不變 |
| `test` | 新增/修改測試 |
| `chore` | 建置設定、套件依賴等雜項 |

### 範例

好的 commit message：
```
feat: 實作 glint_detector 的 flood-fill 亮點偵測

新增 blob detection 演算法,可從影格找出超過亮度門檻的候選點,
並過濾掉面積過小(雜訊)與過大(過曝)的區域。
```

```
fix: 修正相機權限被拒絕時 App 閃退的問題
```

```
docs: 更新 ARCHITECTURE.md 的資料合約格式
```

不好的 commit message(避免這樣寫)：
```
update          ← 太模糊,不知道改了什麼
修好了           ← 沒有類型前綴,也沒說修什麼
fix bug fix bug  ← 重複且無意義
```

**原則：一個 commit 只做一件事**。不要把「改 UI」跟「修偵測演算法」擠在同一個 commit 裡,拆開來 commit,之後要回溯或 revert 才不會牽一髮動全身。

---

## 4. 開發流程(Standard Workflow)

### Step 1 — 開始新工作前,先同步

```bash
git checkout develop
git pull origin develop
git checkout -b feature/你的功能名稱
```

### Step 2 — 開發中,常態性 commit

小步快跑,不要累積一大包才 commit：

```bash
git add .
git commit -m "feat: 完成 XXX 的初版邏輯"
```

### Step 3 — 推上遠端

```bash
git push -u origin feature/你的功能名稱
```
(第一次用 `-u`,之後同分支直接 `git push` 就好)

### Step 4 — 開 Pull Request

去 GitHub repo 頁面,對著 `develop` 開 PR(不是對 `main`!)：
- PR 標題格式同 commit message:`feat: 完成反光偵測模組雛形`
- PR 內容簡述:做了什麼、怎麼測試的、有沒有已知問題
- 指定至少 1 位 reviewer(團隊人少的話可以互相 review,或都給 PM/你 review)

### Step 5 — Review 通過後合併

用 **Squash and merge**(把整條分支的多個 commit 壓成一個乾淨的 commit 進 `develop`),保持 `develop` 的歷史紀錄清爽好讀。

### Step 6 — 合併後清理

```bash
git checkout develop
git pull origin develop
git branch -d feature/你的功能名稱          # 刪本地分支
git push origin --delete feature/你的功能名稱  # 刪遠端分支(可選,GitHub PR 頁面上也有按鈕可以按)
```

### 什麼時候 develop 併回 main?

只有在**要展示/繳交的重要節點**(初賽、複賽、決賽前)才把 `develop` 合併到 `main`,由你(PM)統一發這個 PR 並確認過整體可以正常執行後再合併。平常開發不要碰 `main`。

---

## 5. 處理衝突(Merge Conflict)

拉最新 `develop` 時如果跳出衝突：

```bash
git checkout feature/你的功能名稱
git pull origin develop
```

Git 會標出衝突的檔案,打開後會看到：

```
<<<<<<< HEAD
你自己的程式碼
=======
develop 上別人改的程式碼
>>>>>>> develop
```

手動決定要留哪段(或兩段都留、整合起來),刪掉 `<<<<<<<`、`=======`、`>>>>>>>` 這三行標記後：

```bash
git add .
git commit -m "chore: 解決與 develop 的合併衝突"
git push
```

**降低衝突機率的小技巧：** 各自的檔案盡量待在自己的資料夾(`lib/detection/`、`lib/agent/` 等),不要大家都改同一個檔案(尤其 `main.dart`、`pubspec.yaml`),真的要改共用檔案先在群組講一聲。

---

## 6. .gitignore 提醒

不要 commit 這些東西(標準 Flutter `.gitignore` 已經擋掉大部分,但特別提醒)：
- `.env`、任何含 API Key / LLM endpoint 金鑰的檔案
- `build/`、`.dart_tool/` 這些產出物
- 訓練用的大型資料集/模型檔(`.tflite` 模型檔如果很大,建議用 Git LFS 或放共用雲端硬碟,不要直接塞進 repo)

如果不小心 commit 了機密資訊(例如 API Key),不是刪掉重新 commit 就沒事——舊 commit 歷史裡還留著。發生的話立刻跟 PM(你)說,需要用 `git filter-repo` 或直接重新產生金鑰處理。

---

## 7. 常用指令速查

```bash
git status                          # 看目前狀態
git checkout develop                # 切換分支
git pull origin develop             # 拉最新
git checkout -b feature/xxx         # 建立並切換新分支
git add .                           # 加入所有變更
git commit -m "feat: xxx"           # 提交
git push -u origin feature/xxx      # 第一次推送
git push                            # 之後推送
git log --oneline --graph --all     # 看分支視覺化歷史(很好用)
git branch -a                       # 看所有分支(含遠端)
```

---

## 8. 給團隊的提醒

- Commit 前先想一句話:「這個 commit 在做什麼」,想不出來就代表改太多東西了,拆開。
- PR 不用等到「全部做完」才開,做到一個可以測試的段落就可以開 PR,方便早點抓問題。
- 遇到不確定要不要動的檔案(尤其別人資料夾裡的東西),先問過再動。
- 卡在 git 指令不會用,直接問,不要自己亂試指令怕把東西弄壞——`git reset --hard` 這類指令會真的刪掉東西,不確定就先問。
