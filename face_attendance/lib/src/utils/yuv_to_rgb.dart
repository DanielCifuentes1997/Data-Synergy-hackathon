import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

// Convierte YUV420 a imagen RGB para preprocesamiento
img.Image yuv420ToImage(CameraImage image) {
  final int width = image.width;
  final int height = image.height;
  final img.Image rgbImage = img.Image(width: width, height: height);

  final Plane planeY = image.planes[0];
  final Plane planeU = image.planes[1];
  final Plane planeV = image.planes[2];

  final Uint8List bytesY = planeY.bytes;
  final Uint8List bytesU = planeU.bytes;
  final Uint8List bytesV = planeV.bytes;

  final int bytesPerRowY = planeY.bytesPerRow;
  final int bytesPerRowU = planeU.bytesPerRow;
  final int bytesPerRowV = planeV.bytesPerRow;
  final int bytesPerPixelU = planeU.bytesPerPixel ?? 1;
  final int bytesPerPixelV = planeV.bytesPerPixel ?? 1;

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final int uvIndex = (y ~/ 2) * bytesPerRowU + (x ~/ 2) * bytesPerPixelU;
      final int indexY = y * bytesPerRowY + x;

      final int yp = bytesY[indexY];
      final int up = bytesU[uvIndex];
      final int vp = bytesV[uvIndex];

      final double yf = yp.toDouble();
      final double uf = up.toDouble() - 128.0;
      final double vf = vp.toDouble() - 128.0;

      int r = (yf + 1.370705 * vf).round();
      int g = (yf - 0.698001 * vf - 0.337633 * uf).round();
      int b = (yf + 1.732446 * uf).round();

      r = r.clamp(0, 255);
      g = g.clamp(0, 255);
      b = b.clamp(0, 255);

      rgbImage.setPixelRgba(x, y, r, g, b, 255);
    }
  }

  return rgbImage;
}


