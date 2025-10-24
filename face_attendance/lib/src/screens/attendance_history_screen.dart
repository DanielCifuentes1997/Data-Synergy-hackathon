import 'package:flutter/material.dart';

import '../services/locator.dart';

class AttendanceHistoryScreen extends StatelessWidget {
  const AttendanceHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historial de asistencia')),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: ServiceLocator.attendance.readLog(limit: 200),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final List<Map<String, Object?>> rows = snapshot.data ?? const <Map<String, Object?>>[];
          if (rows.isEmpty) {
            return const Center(child: Text('Sin registros'));
          }
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final r = rows[index];
              final String tipo = (r['tipo_evento'] as String?) ?? '';
              final String fecha = (r['fecha_hora'] as String?) ?? '';
              final String idEmpleado = (r['id_empleado']?.toString()) ?? '';
              final String dispositivo = (r['id_dispositivo'] as String?) ?? '';
              final bool ok = ((r['validado_biometricamente'] as int?) ?? 1) == 1;
              return ListTile(
                leading: Icon(
                  tipo == 'entrada' ? Icons.login : Icons.logout,
                  color: tipo == 'entrada' ? Colors.green : Colors.orange,
                ),
                title: Text('${tipo.toUpperCase()} · Empleado #$idEmpleado'),
                subtitle: Text('Fecha: $fecha · Dispositivo: $dispositivo'),
                trailing: Icon(ok ? Icons.verified : Icons.error_outline, color: ok ? Colors.green : Colors.red),
              );
            },
          );
        },
      ),
    );
  }
}


