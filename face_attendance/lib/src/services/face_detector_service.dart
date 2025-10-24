import 'dart:async';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceDetectorService {
  FaceDetectorService()
      : _detector = FaceDetector(
          options: FaceDetectorOptions(
            performanceMode: FaceDetectorMode.accurate,
            enableLandmarks: true,
            enableContours: false,
            enableClassification: true,
            enableTracking: true,
          ),
        );

  final FaceDetector _detector;

  Future<List<Face>> detectFaces(InputImage image) {
    return _detector.processImage(image);
  }

  Future<void> dispose() async {
    await _detector.close();
  }
}


