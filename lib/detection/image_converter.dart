// image_converter.dart
// 功能: 把 camera 套件的 CameraImage(YUV420格式)轉成
//       image 套件的 img.Image,供 glint_detector / object_detector_service 使用
//
// 同時支援兩種常見的YUV420變體格式:
//   - 3個plane(YUV420 Planar):Y、U、V各自獨立陣列,Android常見
//   - 2個plane(NV12/NV21):Y獨立,U跟V交錯存在同一個陣列裡,iOS常見
// 不能只假設其中一種,兩個平台實際輸出的格式不一定一樣,要動態判斷。

import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

img.Image convertCameraImage(CameraImage cameraImage) {
  if (cameraImage.planes.isEmpty) {
    throw StateError('相機影格沒有任何plane資料,無法轉換。');
  }

  if (cameraImage.planes.length >= 3) {
    return _convertYuv420ThreePlane(cameraImage);
  } else if (cameraImage.planes.length == 2) {
    return _convertYuv420TwoPlane(cameraImage);
  } else {
    throw StateError(
      '相機影格格式不支援(只有${cameraImage.planes.length}個plane,'
      '需要2個或3個)。請確認 camera_service.dart 的 imageFormatGroup 設定為 yuv420。',
    );
  }
}

/// 標準 YUV420 Planar 格式:Y、U、V 各自獨立的陣列(Android常見)
img.Image _convertYuv420ThreePlane(CameraImage cameraImage) {
  final width = cameraImage.width;
  final height = cameraImage.height;

  final yPlane = cameraImage.planes[0];
  final uPlane = cameraImage.planes[1];
  final vPlane = cameraImage.planes[2];

  final image = img.Image(width: width, height: height);

  final yRowStride = yPlane.bytesPerRow;
  final uvRowStride = uPlane.bytesPerRow;
  final uvPixelStride = uPlane.bytesPerPixel ?? 1;

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final yIndex = y * yRowStride + x;
      final uvIndex = (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;

      final yValue = yPlane.bytes[yIndex];
      final uValue = uPlane.bytes[uvIndex];
      final vValue = vPlane.bytes[uvIndex];

      _writeYuvPixel(image, x, y, yValue, uValue, vValue);
    }
  }

  return image;
}

/// NV12/NV21 格式:Y獨立一個plane,U跟V交錯存在第二個plane裡(iOS常見)
img.Image _convertYuv420TwoPlane(CameraImage cameraImage) {
  final width = cameraImage.width;
  final height = cameraImage.height;

  final yPlane = cameraImage.planes[0];
  final uvPlane = cameraImage.planes[1];

  final image = img.Image(width: width, height: height);

  final yRowStride = yPlane.bytesPerRow;
  final uvRowStride = uvPlane.bytesPerRow;
  // 交錯格式的pixel stride通常是2(例如 U,V,U,V... 或 V,U,V,U...)
  final uvPixelStride = uvPlane.bytesPerPixel ?? 2;

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final yIndex = y * yRowStride + x;
      final uvIndex = (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;

      final yValue = yPlane.bytes[yIndex];

      // NV12是U在前V在後,NV21是V在前U在後。iOS(BiPlanar)實務上多為NV12。
      // 這裡假設NV12排列,如果實測顏色偏色(例如整個畫面偏綠/偏紫),
      // 代表實際是NV21,把下面兩行的 uValue/vValue 對調即可。
      final uValue = uvPlane.bytes[uvIndex];
      final vValue = uvIndex + 1 < uvPlane.bytes.length
          ? uvPlane.bytes[uvIndex + 1]
          : 128;

      _writeYuvPixel(image, x, y, yValue, uValue, vValue);
    }
  }

  return image;
}

/// YUV -> RGB 標準轉換公式,兩種格式共用同一套換算邏輯
void _writeYuvPixel(
  img.Image image,
  int x,
  int y,
  int yValue,
  int uValue,
  int vValue,
) {
  final r = (yValue + 1.402 * (vValue - 128)).clamp(0, 255).toInt();
  final g = (yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128))
      .clamp(0, 255)
      .toInt();
  final b = (yValue + 1.772 * (uValue - 128)).clamp(0, 255).toInt();
  image.setPixelRgb(x, y, r, g, b);
}
