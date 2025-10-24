import 'dart:async'; // Para Streams y Timers
import 'dart:convert'; // Para codificar a JSON (jsonEncode)

// Asegúrate de que esta importación esté presente y sea correcta
import 'package:connectivity_plus/connectivity_plus.dart'; // Para detectar conexión
import 'package:http/http.dart' as http; // Para hacer peticiones web (envío API)
import 'package:sqflite/sqflite.dart'; // Para interactuar con la base de datos

import 'locator.dart'; // Para obtener la conexión a la BD centralizada

class SyncService {
  SyncService() {
    // El constructor ahora está vacío, la BD se obtiene en init()
  }

  Database? _db; // Variable para guardar la conexión a la BD
  // Variable para la suscripción a los cambios de conectividad
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isSyncing = false; // Bandera para evitar sincronizaciones simultáneas

  // Nombre de la tabla de asistencia (debe ser IGUAL al de recognition_service.dart)
  static const String _tableAttendance = 'registros_asistencia';
  // >>> ¡IMPORTANTE! Cambia esta URL por la URL REAL de la API de SIOMA <<<
  final String _apiUrl = 'https://webhook.site/60abfcfa-fbe3-4012-88b8-2ac35df2dc4c'; // URL de destino

  // Función de inicialización del servicio
  Future<void> init() async {
    // 1. Obtener la conexión a la BD desde el RecognitionService
    _db = ServiceLocator.recognition.database;

    // 2. Empezar a escuchar si el estado de la red cambia
    //    Especificamos el tipo <List<ConnectivityResult>> para claridad
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (List<ConnectivityResult> results) { // Asegúrate que el tipo aquí es List<ConnectivityResult>
        _handleConnectivityChange(results);
      }
    );

    // 3. Intenta sincronizar una vez al arrancar la app
    print('SyncService: Iniciado. Intentando sincronización inicial.');
    await _attemptSync();
  }

  // Función para liberar recursos
  void dispose() {
    _connectivitySubscription?.cancel(); // Dejar de escuchar cambios de red
  }

  // Esta función se ejecuta CADA VEZ que cambia el estado de la red
  // Asegúrate que el parámetro aquí sea List<ConnectivityResult>
  void _handleConnectivityChange(List<ConnectivityResult> results) {
    // Comprueba si en la lista de resultados está "mobile" (datos) o "wifi"
    final bool hasConnection = results.contains(ConnectivityResult.mobile) ||
                               results.contains(ConnectivityResult.wifi);

    if (hasConnection) {
      print('SyncService: Conexión detectada. Intentando sincronizar...');
      _attemptSync(); // Si hay conexión, intentar enviar pendientes
    } else {
      print('SyncService: Sin conexión.');
    }
  }

  // Función principal que orquesta el proceso de sincronización
  Future<void> _attemptSync() async {
    // Si ya se está ejecutando una sincronización, no hacer nada
    if (_isSyncing) {
      print('SyncService: Sincronización ya en progreso. Omitiendo.');
      return;
    }
    // Si la base de datos no está lista
    if (_db == null) {
      print('SyncService: Error - Base de datos no disponible.');
      return;
    }

    _isSyncing = true; // Marcar que estamos empezando a sincronizar
    print('SyncService: Iniciando ciclo de sincronización.');

    try {
      // 1. Buscar registros pendientes en la base de datos local
      final List<Map<String, Object?>> pendingRecords = await _getPendingRecords();
      print('SyncService: Se encontraron ${pendingRecords.length} registros pendientes.');

      // Si no hay nada pendiente, terminar
      if (pendingRecords.isEmpty) {
        print('SyncService: No hay registros para sincronizar.');
        _isSyncing = false; // Liberar la bandera
        return;
      }

      // 2. Procesar cada registro pendiente UNO POR UNO
      for (final record in pendingRecords) {
        final int recordId = record['id_registro'] as int;
        print('SyncService: Procesando registro ID: $recordId');

        // 3. Intentar enviar el registro a la API
        final bool success = await _sendRecordToApi(record);

        // 4. Si el envío fue exitoso...
        if (success) {
          // ...marcar el registro como sincronizado en la BD local
          await _markRecordAsSynced(recordId);
          print('SyncService: Registro ID: $recordId marcado como sincronizado.');
        } else {
          // Si falló el envío
          print('SyncService: Falló el envío del registro ID: $recordId. Se reintentará en el próximo ciclo.');
        }
      }
      print('SyncService: Ciclo de sincronización completado.');
    } catch (e) {
      // Capturar cualquier error inesperado
      print('SyncService: Error general durante la sincronización: $e');
    } finally {
      // Asegurarse de liberar la bandera SIEMPRE
      _isSyncing = false;
    }
  }

  // Función para obtener los registros pendientes de la BD
  Future<List<Map<String, Object?>>> _getPendingRecords({int limit = 50}) async {
    // Consulta la tabla de asistencia...
    return await _db!.query(
      _tableAttendance,
      where: 'sincronizado = ?', // ...donde la columna 'sincronizado' sea 0
      whereArgs: [0],
      limit: limit, // Traer máximo 50
      orderBy: 'fecha_hora ASC', // Opcional: Enviar los más antiguos primero
    );
  }

  // Función para enviar UN registro a la API
  Future<bool> _sendRecordToApi(Map<String, Object?> record) async {
    // >>> ¡IMPORTANTE! Adapta el 'body' a lo que la API de SIOMA espera <<<
    try {
      // 1. Preparar los datos en formato JSON
      final body = jsonEncode({
        'id_empleado': record['id_empleado'],
        'fecha_hora_registro': record['fecha_hora'],
        'tipo_evento': record['tipo_evento'],
        'identificador_dispositivo': record['id_dispositivo'],
        // ... añade aquí cualquier otro campo que necesites enviar ...
      });

      print('SyncService: Enviando a API: POST $_apiUrl');
      print('SyncService: Cuerpo JSON: $body');

      // 2. Hacer la petición POST a la API
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Content-Type': 'application/json; charset=UTF-8',
          // 'Authorization': 'Bearer TU_TOKEN_AQUI', // Si necesitas autenticación
        },
        body: body,
      ).timeout(const Duration(seconds: 20)); // Esperar máximo 20 segundos

      print('SyncService: Respuesta de API [${response.statusCode}] para registro ${record['id_registro']}: ${response.body}');

      // 3. Verificar si la respuesta fue exitosa (código 2xx)
      return response.statusCode >= 200 && response.statusCode < 300;

    } catch (e) {
      // Capturar errores de red, timeouts, etc.
      print('SyncService: Error de red/http enviando registro ${record['id_registro']}: $e');
      return false; // Indicar que el envío falló
    }
  }

  // Función para marcar un registro como sincronizado en la BD
  Future<void> _markRecordAsSynced(int recordId) async {
    // Actualiza la tabla de asistencia...
    await _db!.update(
      _tableAttendance,
      {'sincronizado': 1},   // ...poniendo la columna 'sincronizado' a 1
      where: 'id_registro = ?', // ...para el registro con este ID específico
      whereArgs: [recordId],
    );
  }
}