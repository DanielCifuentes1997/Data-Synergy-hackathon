import 'dart:math' as math;

import 'package:image/image.dart' as img;

// Recorta el rostro y construye un tensor 112x112x3 normalizado [-1,1]
List<List<List<double>>> preprocessTo112Rgb(img.Image image) {
  final img.Image rgb = img.copyResize(
    img.copyRotate(image, angle: 0),
    width: 112,
    height: 112,
    interpolation: img.Interpolation.average,
  );

  final List<List<List<double>>> result = List.generate(
    112,
    (_) => List.generate(112, (_) => List<double>.filled(3, 0)),
  );

  for (int y = 0; y < 112; y++) {
    for (int x = 0; x < 112; x++) {
      final int pixel = rgb.getPixel(x, y);
      final int r = img.getRed(pixel);
      final int g = img.getGreen(pixel);
      final int b = img.getBlue(pixel);
      result[y][x][0] = ((r / 127.5) - 1.0);
      result[y][x][1] = ((g / 127.5) - 1.0);
      result[y][x][2] = ((b / 127.5) - 1.0);
    }
  }
  return result;
}


