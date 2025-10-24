import 'package:shared_preferences/shared_preferences.dart';

import 'attendance_service.dart';
import 'embedding_service.dart';
import 'face_detector_service.dart';
import 'recognition_service.dart';
import 'sync_service.dart'; // <-- AÑADIDO: Importar el nuevo servicio

class ServiceLocator {
  static SharedPreferences? _prefs;
  static FaceDetectorService? _faceDetectorService;
  static EmbeddingService? _embeddingService;
  static RecognitionService? _recognitionService;
  static AttendanceService? _attendanceService;
  static SyncService? _syncService; // <-- AÑADIDO: Variable para el SyncService

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    _faceDetectorService ??= FaceDetectorService();
    _embeddingService ??= EmbeddingService();

    // ===================================================================
    // ====================== SECCIÓN MODIFICADA =======================
    // ===================================================================
    // Asegurarse que RecognitionService se inicialice PRIMERO porque
    // otros servicios dependen de su conexión a la BD.
    _recognitionService ??= RecognitionService(_prefs!);
    await _recognitionService!.init();

    _attendanceService ??= AttendanceService(_prefs!);
    await _attendanceService!.init(); // AttendanceService usa la BD de Recognition

    _syncService ??= SyncService();    // <-- AÑADIDO: Crear instancia de SyncService
    await _syncService!.init();        // <-- AÑADIDO: Inicializar SyncService (empieza a escuchar red)
    // ===================================================================
    // ==================== FIN DE SECCIÓN MODIFICADA ==================
    // ===================================================================

    // Intento de carga por defecto desde assets (si existe y aún no se ha cargado otro modelo)
    if (!(_embeddingService?.isLoaded ?? false)) {
      final String? path = _prefs!.getString('custom_model_path');
      if (path != null && path.isNotEmpty) {
        await _embeddingService!.loadModelFromFile(path);
      }
      if (!(_embeddingService?.isLoaded ?? false)) {
        // Priorizar el modelo 112x112_128d si existe
        await _embeddingService!.loadModelFromAsset('assets/models/mobilefacenet_112x112_128d.tflite');
      }
      if (!(_embeddingService?.isLoaded ?? false)) {
        // Fallback al modelo anterior
        await _embeddingService!.loadModelFromAsset('assets/models/mobilefacenet.tflite');
      }
    }
  }

  static Future<void> setCustomModelPath(String? path) async {
    if (path == null || path.isEmpty) {
      await _prefs!.remove('custom_model_path');
      return;
    }
    await _prefs!.setString('custom_model_path', path);
  }

  static SharedPreferences get prefs => _prefs!;
  static FaceDetectorService get faceDetector => _faceDetectorService!;
  static EmbeddingService get embedder => _embeddingService!;
  static RecognitionService get recognition => _recognitionService!;
  static AttendanceService get attendance => _attendanceService!;
  static SyncService get sync => _syncService!; // <-- AÑADIDO: Getter para SyncService
}