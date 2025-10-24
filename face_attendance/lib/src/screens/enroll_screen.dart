import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';

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
  int _collectedFrames = 0;
  static const int _requiredFrames = 12;
  List<double>? _embeddingSum;
  img.Image? _lastCropped;
  bool _completed = false;
  bool _recording = false;
  bool _facePresent = false;
  Uint8List? _thumbPng;

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
    if (!ServiceLocator.embedder.isLoaded) {
      setState(() {
        _status = 'Error cargando modelo: ${ServiceLocator.embedder.lastError ?? ''}';
      });
    }
    await _controller!.startImageStream(_onImage);
  }

  void _onImage(CameraImage image) async {
    if (_busy) return;
    _busy = true;
    try {
      final InputImage input = inputImageFromCameraImage(image, _controller!.description);
      final List<Face> faces = await ServiceLocator.faceDetector.detectFaces(input);
      if (faces.isEmpty) {
        _facePresent = false;
        if (mounted) {
          setState(() => _status = 'Acerque su rostro a la cámara');
        }
      } else {
        _facePresent = true;
        if (!_recording) {
          if (mounted) {
            setState(() => _status = 'Rostro detectado. Presione "Iniciar registro"');
          }
          return;
        }
        final img.Image full = yuv420ToImage(image);
        final Face first = faces.first;
        final Rect box = first.boundingBox;
        final int x = box.left.clamp(0, full.width - 1).toInt();
        final int y = box.top.clamp(0, full.height - 1).toInt();
        final int w = box.width.clamp(1, full.width - x).toInt();
        final int h = box.height.clamp(1, full.height - y).toInt();
        final img.Image cropped = img.copyCrop(full, x: x, y: y, width: w, height: h);
        final data = preprocessTo112Rgb(cropped);
        final embedding = ServiceLocator.embedder.runEmbedding(data);

        // Acumular embeddings y progreso
        if (_embeddingSum == null) {
          _embeddingSum = List<double>.filled(embedding.length, 0);
        }
        for (int i = 0; i < embedding.length; i++) {
          _embeddingSum![i] += embedding[i];
        }
        _collectedFrames = (_collectedFrames + 1).clamp(0, _requiredFrames);
        _lastCropped = cropped;
        // Actualizar thumbnail pequeño (reducido a 72px para rendimiento)
        final img.Image thumb = img.copyResize(cropped, width: 72, height: 72);
        _thumbPng = Uint8List.fromList(img.encodePng(thumb));
        if (mounted) {
          setState(() {
            _status = 'Registrando rostro ${_collectedFrames}/$_requiredFrames';
          });
        }

        if (_collectedFrames >= _requiredFrames && !_completed) {
          _completed = true;
          // Promediar embedding
          final List<double> avg = List<double>.from(_embeddingSum!);
          for (int i = 0; i < avg.length; i++) {
            avg[i] = avg[i] / _collectedFrames;
          }
          // Detener stream para evitar múltiples diálogos
          await _controller?.stopImageStream();
          final String? savedPath = _lastCropped != null ? await _saveFaceImage(_lastCropped!) : null;
          if (!mounted) return;
          await _showSaveDialog(avg, imagePath: savedPath);
          // Reiniciar estado para permitir otro registro
          _recording = false;
          _completed = false;
          _collectedFrames = 0;
          _embeddingSum = null;
          _lastCropped = null;
          _status = 'Listo para registrar';
          _thumbPng = null;
          await _controller?.startImageStream(_onImage);
        }
      }
    } catch (e) {
      setState(() => _status = 'Error: $e');
    } finally {
      _busy = false;
    }
  }

  void _startRecording() {
    if (_recording) return;
    _recording = true;
    _completed = false;
    _collectedFrames = 0;
    _embeddingSum = null;
    _lastCropped = null;
    _thumbPng = null;
    setState(() {
      _status = 'Iniciando registro...';
    });
  }

  Future<void> _showSaveDialog(List<double> embedding, {String? imagePath}) async {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController docController = TextEditingController();
    final TextEditingController cargoController = TextEditingController();
    final TextEditingController telController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Guardar empleado'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            TextField(
              controller: docController,
              decoration: const InputDecoration(labelText: 'Documento'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: cargoController,
              decoration: const InputDecoration(labelText: 'Cargo'),
            ),
            TextField(
              controller: telController,
              decoration: const InputDecoration(labelText: 'Teléfono'),
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              // ID autoincremental se genera en la BD; validamos que haya al menos nombre o documento
              if (nameController.text.trim().isEmpty && docController.text.trim().isEmpty) return;
              final String personId = docController.text.trim().isNotEmpty
                  ? docController.text.trim()
                  : (nameController.text.trim().isNotEmpty
                      ? nameController.text.trim()
                      : DateTime.now().millisecondsSinceEpoch.toString());
              await ServiceLocator.recognition.saveIdentity(
                personId,
                embedding,
                imagePath: imagePath,
                name: nameController.text.trim().isEmpty ? null : nameController.text.trim(),
                document: docController.text.trim().isEmpty ? null : docController.text.trim(),
                cargo: cargoController.text.trim().isEmpty ? null : cargoController.text.trim(),
                telefono: telController.text.trim().isEmpty ? null : telController.text.trim(),
              );
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

  Future<String?> _saveFaceImage(img.Image imgImage) async {
    try {
      final Directory appDir = await getApplicationDocumentsDirectory();
      final Directory facesDir = Directory('${appDir.path}/faces');
      if (!await facesDir.exists()) {
        await facesDir.create(recursive: true);
      }
      final String filePath = '${facesDir.path}/face_${DateTime.now().millisecondsSinceEpoch}.png';
      // Convertir a PNG
      final bytes = img.encodePng(imgImage);
      final file = File(filePath);
      await file.writeAsBytes(bytes, flush: true);
      return filePath;
    } catch (_) {
      return null;
    }
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
              // Barra de progreso de registro
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_thumbPng != null)
                        Align(
                          alignment: Alignment.center,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(
                              _thumbPng!,
                              width: 72,
                              height: 72,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      if (_thumbPng != null) const SizedBox(height: 8),
                      if (!ServiceLocator.embedder.isLoaded) ...[
                        const Text(
                          'Modelo no cargado. Selecciona un archivo .tflite válido para continuar.',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: _pickAndLoadModel,
                          icon: const Icon(Icons.upload_file),
                          label: const Text('Cargar modelo TFLite'),
                        ),
                        const SizedBox(height: 12),
                      ],
                      LinearProgressIndicator(
                        value: _requiredFrames == 0 ? null : _collectedFrames / _requiredFrames,
                        backgroundColor: Colors.white24,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _status ?? 'Listo para registrar',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: (!_recording && _facePresent && ServiceLocator.embedder.isLoaded) ? _startRecording : null,
                        icon: const Icon(Icons.fiber_manual_record),
                        label: Text(_recording ? 'Registrando...' : 'Iniciar registro'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _pickAndLoadModel() async {
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
      if (!mounted) return;
      setState(() {
        _status = ServiceLocator.embedder.isLoaded
            ? 'Modelo cargado. Puede iniciar el registro.'
            : 'Error cargando modelo: ${ServiceLocator.embedder.lastError ?? ''}';
      });
    }
  }
}


