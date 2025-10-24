import 'dart:math';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

class AttendanceService {
  AttendanceService(this._prefs);

  static const String _kDeviceKey = 'device_id_v1';
  final SharedPreferences _prefs;
  Database? _db;

  static const String _dbName = 'reconocimiento_biometrico.sqlite';
  static const String _table = 'registros_asistencia';

  Future<void> init() async {
    if (_db != null) return;
    final String dir = await getDatabasesPath();
    final String path = p.join(dir, _dbName);
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, v) async {
        await _ensureTable(db);
      },
      onOpen: (db) async {
        // Garantizar que la tabla exista incluso si la BD ya existía
        await _ensureTable(db);
      },
    );
  }

  Future<void> _ensureTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_table (
        id_registro INTEGER PRIMARY KEY AUTOINCREMENT,
        id_empleado INTEGER NOT NULL,
        id_dispositivo TEXT NOT NULL,
        tipo_evento TEXT NOT NULL,
        fecha_hora TEXT DEFAULT CURRENT_TIMESTAMP,
        validado_biometricamente INTEGER DEFAULT 1,
        observaciones TEXT
      )
    ''');
  }

  Future<String> _getOrCreateDeviceId() async {
    String? id = _prefs.getString(_kDeviceKey);
    if (id != null && id.isNotEmpty) return id;
    // Generar ID simple estable
    final int rand = DateTime.now().millisecondsSinceEpoch ^ Random().nextInt(1 << 31);
    id = 'dev-${rand.toRadixString(36)}';
    await _prefs.setString(_kDeviceKey, id);
    return id;
  }

  Future<void> registerIngress(String personId) async {
    await _append('entrada', personId);
  }

  Future<void> registerEgress(String personId) async {
    await _append('salida', personId);
  }

  Future<List<Map<String, Object?>>> readLog({int limit = 100}) async {
    final db = _db; if (db == null) { await init(); }
    final Database useDb = _db!;
    return await useDb.query(_table, orderBy: 'fecha_hora DESC', limit: limit);
  }

  Future<void> _append(String type, String personId, {bool validated = true, String? notes}) async {
    final db = _db; if (db == null) { await init(); }
    final Database useDb = _db!;
    final String deviceId = await _getOrCreateDeviceId();
    final int empleadoId = int.tryParse(personId) ?? -1;
    if (empleadoId <= 0) return;
    await useDb.insert(
      _table,
      <String, Object?>{
        'id_empleado': empleadoId,
        'id_dispositivo': deviceId,
        'tipo_evento': type,
        'fecha_hora': DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now()),
        'validado_biometricamente': validated ? 1 : 0,
        'observaciones': notes,
      },
    );
  }
}


