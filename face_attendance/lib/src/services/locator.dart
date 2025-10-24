import 'package:shared_preferences/shared_preferences.dart';

import 'attendance_service.dart';
import 'embedding_service.dart';
import 'face_detector_service.dart';
import 'recognition_service.dart';

class ServiceLocator {
  static SharedPreferences? _prefs;
  static FaceDetectorService? _faceDetectorService;
  static EmbeddingService? _embeddingService;
  static RecognitionService? _recognitionService;
  static AttendanceService? _attendanceService;

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    _faceDetectorService ??= FaceDetectorService();
    _embeddingService ??= EmbeddingService();
    _recognitionService ??= RecognitionService(_prefs!);
    _attendanceService ??= AttendanceService(_prefs!);
  }

  static SharedPreferences get prefs => _prefs!;
  static FaceDetectorService get faceDetector => _faceDetectorService!;
  static EmbeddingService get embedder => _embeddingService!;
  static RecognitionService get recognition => _recognitionService!;
  static AttendanceService get attendance => _attendanceService!;
}


