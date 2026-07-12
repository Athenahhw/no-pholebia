// ============================================================
// image_converter.dart
// 功能: 把 camera 套件的 CameraImage(YUV420格式)轉成
//       image 套件的 img.Image,供 glint_detector / yolo_inference 使用
// ============================================================
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

img.Image convertCameraImage(CameraImage cameraImage) {
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

      // YUV -> RGB 標準轉換公式
      final r = (yValue + 1.402 * (vValue - 128)).clamp(0, 255).toInt();
      final g = (yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128))
          .clamp(0, 255)
          .toInt();
      final b = (yValue + 1.772 * (uValue - 128)).clamp(0, 255).toInt();

      image.setPixelRgb(x, y, r, g, b);
    }
  }

  return image;
}
