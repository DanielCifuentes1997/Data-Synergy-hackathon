import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../theme/app_theme.dart';
import '../services/locator.dart';
import '../utils/mlkit_image.dart';
import '../utils/preprocess.dart';
import '../utils/yuv_to_rgb.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  Future<void>? _initFuture;
  List<CameraDescription> _cameras = const [];
  bool _isProcessing = false;
  String? _lastDetectedId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initFuture = _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _controller;
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _reinitializeCamera();
    }
  }

  Future<void> _initialize() async {
    await Permission.camera.request();
    _cameras = await availableCameras();
    final CameraDescription camera = _cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => _cameras.first,
    );
    _controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await _controller!.initialize();
    await ServiceLocator.init();
    await ServiceLocator.embedder.loadModelFromAsset('assets/models/mobilefacenet.tflite');
    await _controller!.startImageStream(_onCameraImage);
  }

  Future<void> _reinitializeCamera() async {
    final CameraDescription camera = _cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => _cameras.first,
    );
    _controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await _controller!.initialize();
    await _controller!.startImageStream(_onCameraImage);
    setState(() {});
  }

  void _onCameraImage(CameraImage image) {
    if (_isProcessing) return;
    _isProcessing = true;
    () async {
      try {
        final InputImage input = inputImageFromCameraImage(image, _controller!.description);
        final faces = await ServiceLocator.faceDetector.detectFaces(input);
        if (faces.isNotEmpty) {
          final rgb = yuv420ToImage(image);
          final data = preprocessTo112Rgb(rgb);
          final embedding = ServiceLocator.embedder.runEmbedding(data);
          final match = await ServiceLocator.recognition.identify(embedding);
          if (match != null) {
            _lastDetectedId = match;
            // Mostrar coincidencia momentánea
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Detectado: $match'), duration: const Duration(milliseconds: 600)),
              );
            }
          }
        }
      } catch (_) {
        // Silenciar errores de frame
      } finally {
        _isProcessing = false;
      }
    }();
  }

  void _onRegisterIngress() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Intentando identificar para ingreso...')),
    );
    _registerAttendance(isIngress: true);
  }

  void _onRegisterEgress() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Intentando identificar para salida...')),
    );
    _registerAttendance(isIngress: false);
  }

  Future<void> _registerAttendance({required bool isIngress}) async {
    final String? id = _lastDetectedId;
    if (id == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se detectó identidad reciente')),
        );
      }
      return;
    }
    if (isIngress) {
      await ServiceLocator.attendance.registerIngress(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ingreso registrado para $id')),
        );
      }
    } else {
      await ServiceLocator.attendance.registerEgress(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Salida registrada para $id')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Asistencia Facial'),
        actions: [
          IconButton(
            onPressed: widget.onOpenSettings,
            icon: const Icon(Icons.settings),
            tooltip: 'Configuración',
          ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _initFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final CameraController? ctrl = _controller;
          if (ctrl == null || !ctrl.value.isInitialized) {
            return const Center(child: Text('Cámara no disponible'));
          }
          return Stack(
            children: [
              Positioned.fill(
                child: CameraPreview(ctrl),
              ),
              // Overlay simple con borde
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: kPrimaryColor.withOpacity(0.5), width: 6),
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _onRegisterIngress,
                              icon: const Icon(Icons.login),
                              label: const Text('Registrar ingreso'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _onRegisterEgress,
                              icon: const Icon(Icons.logout),
                              label: const Text('Registrar salida'),
                            ),
                          ),
                        ],
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
}


