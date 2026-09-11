// 高風險頁之後若要「寫死介面」，把圖片放到下面路徑即可。
// 檔名必須完全一致。App 會優先顯示掃描當下的 glint 截圖；
// 沒有即時截圖時，才改顯示這裡的靜態圖。
//
// 放置步驟：
// 1. 把圖放到 pinhole_detector/assets/images/high_risk_static/
// 2. 檔名用下方常數（不要改檔名，除非連這裡一起改）
// 3. pubspec.yaml 已宣告整個資料夾，不必再加單檔
// 4. 熱重載不夠時請完整重跑 flutter run
//
// 建議出圖規格（才能跟一般掃描結果頁對齊）：
// - 背景色接近 #F0EEDC
// - 內容寬度視覺上對齊 280px
// - 高風險主題色 #FF33CC
// - 反光點截圖請裁成正方形、標出閃光點位置
class HighRiskStaticAssets {
  static const directory = 'assets/images/high_risk_static';

  /// 高風險頁「異常反光點截圖」第 1～3 張（對應一般模式偵測到 glint 時的裁切圖）
  static const glintCrops = [
    '$directory/glint_crop_1.jpg',
    '$directory/glint_crop_2.jpg',
    '$directory/glint_crop_3.jpg',
  ];

  /// 可選：整段高風險說明文案的截圖。有檔才顯示，沒檔就繼續用即時文字。
  static const summaryBlock = '$directory/summary_block.png';

  /// 可選：儀表板/分數區截圖。預設不啟用，避免分數跟真實 scan 對不起來。
  static const useFrozenGauge = false;
  static const gaugeBlock = '$directory/gauge_block.png';
}
