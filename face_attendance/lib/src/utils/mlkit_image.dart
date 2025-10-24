import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart' as commons;

commons.InputImage inputImageFromCameraImage(CameraImage image, CameraDescription description) {
  final commons.InputImageRotation rotation = _rotationFromCameraDescription(description);

  final Uint8List bytes = _yuv420ToNv21(image);
  final Size size = Size(image.width.toDouble(), image.height.toDouble());

  final commons.InputImageMetadata metadata = commons.InputImageMetadata(
    size: size,
    rotation: rotation,
    // Declaramos explícitamente NV21 porque construimos el buffer en ese formato
    format: commons.InputImageFormat.nv21,
    // Para NV21, bytesPerRow debe ser el ancho en píxeles
    bytesPerRow: image.width,
  );

  return commons.InputImage.fromBytes(bytes: bytes, metadata: metadata);
}

Uint8List _yuv420ToNv21(CameraImage image) {
  final int width = image.width;
  final int height = image.height;
  final int ySize = width * height;

  final Plane yPlane = image.planes[0];
  final Plane uPlane = image.planes[1];
  final Plane vPlane = image.planes[2];

  final int uvRowStrideU = uPlane.bytesPerRow;
  final int uvRowStrideV = vPlane.bytesPerRow;
  final int uvPixelStrideU = uPlane.bytesPerPixel ?? 1;
  final int uvPixelStrideV = vPlane.bytesPerPixel ?? 1;

  final Uint8List out = Uint8List(ySize + (ySize >> 1));

  // Copy Y
  int outIndex = 0;
  for (int y = 0; y < height; y++) {
    final int rowStart = y * yPlane.bytesPerRow;
    out.setRange(outIndex, outIndex + width, yPlane.bytes.sublist(rowStart, rowStart + width));
    outIndex += width;
  }

  // Copy interleaved VU
  int vuIndex = ySize;
  for (int y = 0; y < height ~/ 2; y++) {
    int uIndex = y * uvRowStrideU;
    int vIndex = y * uvRowStrideV;
    for (int x = 0; x < width ~/ 2; x++) {
      final int v = vPlane.bytes[vIndex];
      final int u = uPlane.bytes[uIndex];
      out[vuIndex++] = v;
      out[vuIndex++] = u;
      uIndex += uvPixelStrideU;
      vIndex += uvPixelStrideV;
    }
  }

  return out;
}

commons.InputImageRotation _rotationFromCameraDescription(CameraDescription description) {
  final int? rotationDegrees = description.sensorOrientation;
  final commons.InputImageRotation? rotation = commons.InputImageRotationValue.fromRawValue(rotationDegrees ?? 0);
  return rotation ?? commons.InputImageRotation.rotation0deg;
}

commons.InputImageFormat _formatFromRaw(int raw) {
  final commons.InputImageFormat? format = commons.InputImageFormatValue.fromRawValue(raw);
  return format ?? commons.InputImageFormat.nv21;
}


