import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart' as commons;

InputImage inputImageFromCameraImage(CameraImage image, CameraDescription description) {
  final InputImageRotation rotation = _rotationFromCameraDescription(description);
  final InputImageFormat format = _formatFromRaw(image.format.raw);

  final Uint8List bytes = _concatenatePlanes(image.planes);
  final Size size = Size(image.width.toDouble(), image.height.toDouble());

  final List<commons.InputImagePlaneMetadata> planeData = image.planes
      .map(
        (Plane plane) => commons.InputImagePlaneMetadata(
          bytesPerRow: plane.bytesPerRow,
          height: plane.height,
          width: plane.width,
        ),
      )
      .toList();

  final commons.InputImageMetadata metadata = commons.InputImageMetadata(
    size: size,
    rotation: rotation,
    format: format,
    bytesPerRow: image.planes.first.bytesPerRow,
    planeData: planeData,
  );

  return InputImage.fromBytes(bytes: bytes, metadata: metadata);
}

Uint8List _concatenatePlanes(List<Plane> planes) {
  final WriteBuffer buffer = WriteBuffer();
  for (final Plane plane in planes) {
    buffer.putUint8List(plane.bytes);
  }
  return buffer.done().buffer.asUint8List();
}

InputImageRotation _rotationFromCameraDescription(CameraDescription description) {
  final int? rotationDegrees = description.sensorOrientation;
  final InputImageRotation? rotation = InputImageRotationValue.fromRawValue(rotationDegrees ?? 0);
  return rotation ?? InputImageRotation.rotation0deg;
}

InputImageFormat _formatFromRaw(int raw) {
  final InputImageFormat? format = InputImageFormatValue.fromRawValue(raw);
  return format ?? InputImageFormat.nv21;
}


