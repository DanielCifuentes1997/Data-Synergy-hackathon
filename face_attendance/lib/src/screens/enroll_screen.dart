import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../services/locator.dart';
import '../utils/mlkit_image.dart';
import '../utils/preprocess.dart';
import '../utils/yuv_to_rgb.dart';

class EnrollScreen extends StatefulWidget {
  const EnrollScreen({super.key});

  @override
  State<EnrollScreen> createState() => _EnrollScreenState();
}

class _EnrollScreenState extends State<EnrollScreen> {
  CameraController? _controller;
  Future<void>? _init;
  bool _busy = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _init = _initialize();
  }

  Future<void> _initialize() async {
    final List<CameraDescription> cams = await availableCameras();
    final CameraDescription cam = cams.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cams.first,
    );
    _controller = CameraController(
      cam,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await _controller!.initialize();
    await ServiceLocator.embedder.loadModelFromAsset('assets/models/mobilefacenet.tflite');
    await _controller!.startImageStream(_onImage);
  }

  void _onImage(CameraImage image) async {
    if (_busy) return;
    _busy = true;
    try {
      final InputImage input = inputImageFromCameraImage(image, _controller!.description);
      final List<Face> faces = await ServiceLocator.faceDetector.detectFaces(input);
      if (faces.isEmpty) {
        setState(() => _status = 'Acerque su rostro a la cámara');
      } else {
        final imgImage = yuv420ToImage(image);
        final data = preprocessTo112Rgb(imgImage);
        final embedding = ServiceLocator.embedder.runEmbedding(data);
        if (!mounted) return;
        await _showSaveDialog(embedding);
      }
    } catch (e) {
      setState(() => _status = 'Error: $e');
    } finally {
      _busy = false;
    }
  }

  Future<void> _showSaveDialog(List<double> embedding) async {
    final TextEditingController controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Guardar usuario'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Identificador (ej. nombre)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              final String id = controller.text.trim();
              if (id.isEmpty) return;
              await ServiceLocator.recognition.saveIdentity(id, embedding);
              if (!mounted) return;
              Navigator.of(context).pop();
              if (!mounted) return;
              Navigator.of(context).maybePop();
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Enrolar usuario')),
      body: FutureBuilder<void>(
        future: _init,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return Stack(
            children: [
              Positioned.fill(child: CameraPreview(_controller!)),
              if (_status != null)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _status!,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}


