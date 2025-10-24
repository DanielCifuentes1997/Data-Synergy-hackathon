import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AttendanceService {
  AttendanceService(this._prefs);

  static const String _kLogKey = 'attendance_log_v1';
  final SharedPreferences _prefs;

  Future<void> registerIngress(String personId) async {
    await _appendLog('INGRESO', personId);
  }

  Future<void> registerEgress(String personId) async {
    await _appendLog('SALIDA', personId);
  }

  Future<List<String>> readLog() async {
    return _prefs.getStringList(_kLogKey) ?? <String>[];
  }

  Future<void> _appendLog(String type, String personId) async {
    final List<String> log = await readLog();
    final String ts = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    log.add('$ts,$type,$personId');
    await _prefs.setStringList(_kLogKey, log);
  }
}


