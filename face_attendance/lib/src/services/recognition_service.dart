import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'dart:typed_data';

import '../models/recognized_person.dart';

class RecognitionService {
  RecognitionService(this._prefs);

  final SharedPreferences _prefs; // Conservado por compatibilidad, ya no se usa para identidades
  Database? _db;

  static const String _dbName = 'reconocimiento_biometrico.sqlite';
  static const String _tableEmployees = 'empleados';
  static const String _tableBiometrics = 'datos_biometricos';
  List<_CacheEntry>? _cache; // id, vector, metadatos

  Future<void> init() async {
    if (_db != null) return;
    final String dbDir = await getDatabasesPath();
    final String path = p.join(dbDir, _dbName);
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_tableEmployees (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            nombre TEXT NOT NULL,
            documento TEXT,
            cargo TEXT,
            telefono TEXT,
            imagePath TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE $_tableBiometrics (
            id_biometrico INTEGER PRIMARY KEY AUTOINCREMENT,
            id_empleado INTEGER NOT NULL,
            tipo_biometria TEXT NOT NULL DEFAULT 'rostro',
            vector_biometrico BLOB,
            fecha_registro TEXT DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY(id_empleado) REFERENCES $_tableEmployees(id) ON DELETE CASCADE
          )
        ''');
      },
    );
    await _warmCache();
  }

  Future<void> _warmCache() async {
    final Database useDb = _db!;
    final String sql = '''
      SELECT b.id_empleado, b.vector_biometrico, e.nombre, e.documento, e.cargo, e.telefono, e.imagePath
      FROM $_tableBiometrics b
      JOIN $_tableEmployees e ON e.id = b.id_empleado
      GROUP BY b.id_empleado
    ''';
    final List<Map<String, Object?>> rows = await useDb.rawQuery(sql);
    final List<_CacheEntry> list = <_CacheEntry>[];
    for (final r in rows) {
      final Uint8List blob = (r['vector_biometrico'] as Uint8List);
      final Float64List v = blob.buffer.asByteData().buffer.asFloat64List();
      list.add(
        _CacheEntry(
          idEmpleado: r['id_empleado'] as int,
          vector: v.toList(growable: false),
          nombre: r['nombre'] as String?,
          documento: r['documento'] as String?,
          cargo: r['cargo'] as String?,
          telefono: r['telefono'] as String?,
          imagePath: r['imagePath'] as String?,
        ),
      );
    }
    _cache = list;
  }

  // Inserta/actualiza empleado por documento si existe; retorna id del empleado
  Future<int> upsertEmployee({
    required String nombre,
    String? documento,
    String? cargo,
    String? telefono,
    String? imagePath,
  }) async {
    final db = _db; if (db == null) { await init(); }
    final Database useDb = _db!;
    int? foundId;
    if (documento != null && documento.isNotEmpty) {
      final rows = await useDb.query(
        _tableEmployees,
        columns: ['id'],
        where: 'documento = ?',
        whereArgs: <Object?>[documento],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        foundId = rows.first['id'] as int;
        await useDb.update(
          _tableEmployees,
          {
            'nombre': nombre,
            'cargo': cargo,
            'telefono': telefono,
            'imagePath': imagePath,
          },
          where: 'id = ?',
          whereArgs: <Object?>[foundId],
        );
      }
    }
    if (foundId != null) return foundId;
    return await useDb.insert(
      _tableEmployees,
      <String, Object?>{
        'nombre': nombre,
        'documento': documento,
        'cargo': cargo,
        'telefono': telefono,
        'imagePath': imagePath,
      },
    );
  }

  // Guarda embedding para el empleado
  Future<void> saveIdentityForEmployee({
    required int empleadoId,
    required List<double> embedding,
  }) async {
    final db = _db; if (db == null) { await init(); }
    final Database useDb = _db!;
    final Float64List vec = Float64List.fromList(embedding);
    final Uint8List blob = vec.buffer.asUint8List();
    await useDb.insert(
      _tableBiometrics,
      <String, Object?>{
        'id_empleado': empleadoId,
        'tipo_biometria': 'rostro',
        'vector_biometrico': blob,
      },
    );
    // Refrescar/unir entrada en caché
    _cache ??= <_CacheEntry>[];
    final int idx = _cache!.indexWhere((e) => e.idEmpleado == empleadoId);
    final rows = await useDb.query(
      _tableEmployees,
      where: 'id = ?',
      whereArgs: <Object?>[empleadoId],
      limit: 1,
    );
    String? nombre;
    String? documento;
    String? cargo;
    String? telefono;
    String? imagePath;
    if (rows.isNotEmpty) {
      nombre = rows.first['nombre'] as String?;
      documento = rows.first['documento'] as String?;
      cargo = rows.first['cargo'] as String?;
      telefono = rows.first['telefono'] as String?;
      imagePath = rows.first['imagePath'] as String?;
    }
    final _CacheEntry entry = _CacheEntry(
      idEmpleado: empleadoId,
      vector: embedding,
      nombre: nombre,
      documento: documento,
      cargo: cargo,
      telefono: telefono,
      imagePath: imagePath,
    );
    if (idx >= 0) {
      _cache![idx] = entry;
    } else {
      _cache!.add(entry);
    }
  }

  // API compatible para pantallas actuales: crea/actualiza empleado y guarda biométrico
  Future<void> saveIdentity(
    String personId,
    List<double> embedding, {
    String? imagePath,
    String? name,
    String? document,
    String? cargo,
    String? telefono,
  }) async {
    final int empId = await upsertEmployee(
      nombre: name ?? personId,
      documento: document,
      cargo: cargo,
      telefono: telefono,
      imagePath: imagePath,
    );
    await saveIdentityForEmployee(empleadoId: empId, embedding: embedding);
  }

  Future<Map<String, dynamic>> readAll() async {
    final db = _db; if (db == null) { await init(); }
    final Database useDb = _db!;
    final String sql = '''
      SELECT e.id, e.nombre, e.documento, e.cargo, e.telefono, e.imagePath
      FROM $_tableEmployees e
      ORDER BY e.id ASC
    ''';
    final List<Map<String, Object?>> rows = await useDb.rawQuery(sql);
    final Map<String, dynamic> out = <String, dynamic>{};
    for (final r in rows) {
      final String key = (r['id'] as int).toString();
      out[key] = <String, Object?>{
        'name': r['nombre'] as String?,
        'document': r['documento'] as String?,
        'cargo': r['cargo'] as String?,
        'telefono': r['telefono'] as String?,
        'imagePath': r['imagePath'] as String?,
      };
    }
    return out;
  }

  Future<void> deleteIdentity(String personId, {bool deleteImage = true}) async {
    final db = _db; if (db == null) { await init(); }
    final Database useDb = _db!;
    final int id = int.tryParse(personId) ?? -1;
    if (id <= 0) return;
    String? imagePath;
    try {
      final rows = await useDb.query(
        _tableEmployees,
        where: 'id = ?',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        imagePath = rows.first['imagePath'] as String?;
      }
    } catch (_) {}
    await useDb.delete(_tableBiometrics, where: 'id_empleado = ?', whereArgs: <Object?>[id]);
    await useDb.delete(_tableEmployees, where: 'id = ?', whereArgs: <Object?>[id]);
    _cache?.removeWhere((e) => e.idEmpleado == id);
    if (deleteImage && imagePath != null) {
      try {
        final File f = File(imagePath);
        if (await f.exists()) {
          await f.delete();
        }
      } catch (_) {}
    }
  }

  Future<RecognizedPerson?> identify(List<double> embedding, {double threshold = 1.05}) async {
    final db = _db; if (db == null) { await init(); }
    if (_cache == null) {
      await _warmCache();
    }
    String? bestId;
    double bestDist = double.infinity;
    String? bestImagePath;
    String? bestName;
    String? bestDocument;
    String? bestCargo;
    String? bestTelefono;
    for (final _CacheEntry e in _cache ?? const <_CacheEntry>[]) {
      final double dist = _euclidean(embedding, e.vector);
      if (dist < bestDist) {
        bestDist = dist;
        bestId = e.idEmpleado.toString();
        bestImagePath = e.imagePath;
        bestName = e.nombre;
        bestDocument = e.documento;
        bestCargo = e.cargo;
        bestTelefono = e.telefono;
      }
    }
    if (bestId != null && bestDist <= threshold) {
      return RecognizedPerson(
        id: bestId!,
        name: bestName,
        document: bestDocument,
        cargo: bestCargo,
        telefono: bestTelefono,
        imagePath: bestImagePath,
        distance: bestDist,
      );
    }
    return null;
  }

  double _euclidean(List<double> a, List<double> b) {
    final int n = a.length;
    double sum = 0;
    for (int i = 0; i < n; i++) {
      final double d = a[i] - b[i];
      sum += d * d;
    }
    return sum.sqrt();
  }
}

class _CacheEntry {
  _CacheEntry({
    required this.idEmpleado,
    required this.vector,
    this.nombre,
    this.documento,
    this.cargo,
    this.telefono,
    this.imagePath,
  });

  final int idEmpleado;
  final List<double> vector;
  final String? nombre;
  final String? documento;
  final String? cargo;
  final String? telefono;
  final String? imagePath;
}

extension on double {
  double sqrt() => this <= 0 ? 0 : (this).toDouble()._sqrtNewton();
}

extension on double {
  double _sqrtNewton() {
    double x = this;
    double g = this / 2.0;
    for (int i = 0; i < 8; i++) {
      g = 0.5 * (g + x / g);
    }
    return g;
  }
}


