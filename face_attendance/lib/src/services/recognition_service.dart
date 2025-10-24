import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecognitionService {
  RecognitionService(this._prefs);

  static const String _kDbKey = 'face_db_v1';
  final SharedPreferences _prefs;

  Future<void> saveIdentity(String personId, List<double> embedding) async {
    final Map<String, dynamic> db = await _readDb();
    db[personId] = embedding;
    await _prefs.setString(_kDbKey, jsonEncode(db));
  }

  Future<Map<String, dynamic>> _readDb() async {
    final String? json = _prefs.getString(_kDbKey);
    if (json == null) return <String, dynamic>{};
    return jsonDecode(json) as Map<String, dynamic>;
  }

  Future<String?> identify(List<double> embedding, {double threshold = 1.05}) async {
    final Map<String, dynamic> db = await _readDb();
    String? bestId;
    double bestDist = double.infinity;
    for (final MapEntry<String, dynamic> e in db.entries) {
      final List<dynamic> vector = e.value as List<dynamic>;
      final double dist = _euclidean(embedding, vector.cast<double>());
      if (dist < bestDist) {
        bestDist = dist;
        bestId = e.key;
      }
    }
    if (bestDist <= threshold) return bestId;
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


