import 'package:flutter/material.dart';
import 'enroll_screen.dart';

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
            label: const Text('Enrolar usuario'),
          ),
          const SizedBox(height: 24),
          const Text(
            'Modelo',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('MobileFaceNet.tflite'),
            subtitle: const Text('Cargado desde assets/models'),
            trailing: const Icon(Icons.check_circle, color: Colors.green),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}


