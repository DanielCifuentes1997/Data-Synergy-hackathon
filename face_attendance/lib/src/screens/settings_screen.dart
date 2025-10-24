import 'package:flutter/material.dart';
import 'dart:io';
import '../services/locator.dart';
import 'package:file_picker/file_picker.dart';
import 'enroll_screen.dart';
import 'attendance_history_screen.dart';
import 'attendance_history_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Gestión de usuarios',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const EnrollScreen()),
              );
            },
            icon: const Icon(Icons.person_add),
            label: const Text('Registrar rostro'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AttendanceHistoryScreen()),
              );
            },
            icon: const Icon(Icons.history),
            label: const Text('Historial'),
          ),
          const SizedBox(height: 24),
          const Text(
            'Usuarios enrolados',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          FutureBuilder<Map<String, dynamic>>(
            future: ServiceLocator.recognition.readAll(),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final Map<String, dynamic> db = snapshot.data ?? <String, dynamic>{};
              if (db.isEmpty) {
                return const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('No hay usuarios enrolados'),
                );
              }
              final entries = db.entries.toList();
              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: entries.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final e = entries[index];
                  String? imagePath;
                  String? name;
                  String? document;
                  String? cargo;
                  String? telefono;
                  if (e.value is Map) {
                    final map = (e.value as Map);
                    if (map['imagePath'] is String) imagePath = map['imagePath'] as String;
                    if (map['name'] is String) name = map['name'] as String;
                    if (map['document'] is String) document = map['document'] as String;
                    if (map['cargo'] is String) cargo = map['cargo'] as String;
                    if (map['telefono'] is String) telefono = map['telefono'] as String;
                  }
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: imagePath != null ? AssetImage('') : null,
                      child: imagePath == null ? const Icon(Icons.person) : null,
                      foregroundImage: imagePath != null ? FileImage(File(imagePath)) : null,
                    ),
                    title: Text(name ?? e.key),
                    subtitle: Text(
                      [
                        if (document != null) 'Doc: ' + document!,
                        if (cargo != null) 'Cargo: ' + cargo!,
                        if (telefono != null) 'Tel: ' + telefono!,
                        if (imagePath != null) imagePath!,
                      ].join(' · ').isEmpty
                          ? 'Sin datos cargados'
                          : [
                              if (document != null) 'Doc: ' + document!,
                              if (cargo != null) 'Cargo: ' + cargo!,
                              if (telefono != null) 'Tel: ' + telefono!,
                              if (imagePath != null) imagePath!,
                            ].join(' · '),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () async {
                        final bool? ok = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Eliminar usuario'),
                            content: Text('¿Deseas eliminar a "${e.key}"?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(false),
                                child: const Text('Cancelar'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.of(context).pop(true),
                                child: const Text('Eliminar'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) {
                          await ServiceLocator.recognition.deleteIdentity(e.key);
                          // Refrescar
                          (context as Element).markNeedsBuild();
                        }
                      },
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 24),
          const Text(
            'Modelo',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (ServiceLocator.embedder.source == 'asset')
            ListTile(
              leading: const Icon(Icons.check_circle, color: Colors.green),
              title: const Text('Modelo embebido'),
              subtitle: Text(
                ServiceLocator.embedder.isLoaded
                    ? 'Cargado desde assets/models/mobilefacenet_112x112_128d.tflite (o fallback)'
                    : 'No cargado',
              ),
            )
          else
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('Seleccionar modelo TFLite'),
              subtitle: Text(ServiceLocator.embedder.isLoaded
                  ? (ServiceLocator.embedder.source == 'file' ? 'Modelo cargado desde archivo' : 'Modelo cargado')
                  : (ServiceLocator.embedder.lastError != null
                      ? 'Error: ${ServiceLocator.embedder.lastError}'
                      : 'No cargado')),
              trailing: Icon(
                ServiceLocator.embedder.isLoaded ? Icons.check_circle : Icons.info_outline,
                color: ServiceLocator.embedder.isLoaded ? Colors.green : null,
              ),
              onTap: () async {
                final FilePickerResult? result = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['tflite', 'lite'],
                );
                if (result != null && result.files.single.path != null) {
                  final String path = result.files.single.path!;
                  await ServiceLocator.embedder.loadModelFromFile(path);
                  await ServiceLocator.setCustomModelPath(
                    ServiceLocator.embedder.isLoaded ? path : null,
                  );
                  if (context.mounted) {
                    (context as Element).markNeedsBuild();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(ServiceLocator.embedder.isLoaded ? 'Modelo cargado' : 'Error cargando modelo'),
                      ),
                    );
                  }
                }
              },
            ),
        ],
      ),
    );
  }
}


