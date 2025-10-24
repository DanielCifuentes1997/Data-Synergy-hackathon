import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image/image.dart' as img;

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
  String? _lastDetectedName;
  String? _lastDetectedDocument;
  Timer? _bannerTimer;
  bool _facePresent = false;
  List<double>? _lastEmbedding;

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
        final input = inputImageFromCameraImage(image, _controller!.description);
        final faces = await ServiceLocator.faceDetector.detectFaces(input);
        _facePresent = faces.isNotEmpty;
        if (!mounted) return;
        setState(() {});
        if (faces.isNotEmpty) {
          final rgb = yuv420ToImage(image);
          // Recortar la primera cara detectada para mejorar la calidad del embedding
          final Rect box = faces.first.boundingBox;
          final int x = box.left.clamp(0, rgb.width - 1).toInt();
          final int y = box.top.clamp(0, rgb.height - 1).toInt();
          final int w = box.width.clamp(1, rgb.width - x).toInt();
          final int h = box.height.clamp(1, rgb.height - y).toInt();
          final img.Image cropped = img.copyCrop(rgb, x: x, y: y, width: w, height: h);
          final data = preprocessTo112Rgb(cropped);
          final embedding = ServiceLocator.embedder.runEmbedding(data);
          _lastEmbedding = embedding;
          final match = await ServiceLocator.recognition.identify(embedding, threshold: 1.20);
          if (match != null) {
            _lastDetectedId = match.id;
            _lastDetectedName = match.name;
            _lastDetectedDocument = match.document;
            if (mounted) setState(() {});
            _bannerTimer?.cancel();
            _bannerTimer = Timer(const Duration(seconds: 2), () {
              if (!mounted) return;
              _lastDetectedId = null;
              _lastDetectedName = null;
              _lastDetectedDocument = null;
              setState(() {});
            });
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
    String? id = _lastDetectedId;
    if (id == null && _lastEmbedding != null) {
      try {
        final match = await ServiceLocator.recognition.identify(_lastEmbedding!, threshold: 1.20);
        if (match != null) {
          id = match.id;
          _lastDetectedId = match.id;
          _lastDetectedName = match.name;
          _lastDetectedDocument = match.document;
          if (mounted) setState(() {});
        }
      } catch (_) {}
    }
    if (id == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se detectó identidad reciente')),
        );
      }
      return;
    }
    try {
      if (isIngress) {
        await ServiceLocator.attendance.registerIngress(id);
        if (mounted) {
          final String label = _lastDetectedName ?? id;
          final String suffix = _lastDetectedDocument != null ? ' · ${_lastDetectedDocument}' : '';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ingreso registrado para $label$suffix')));
        }
      } else {
        await ServiceLocator.attendance.registerEgress(id);
        if (mounted) {
          final String label = _lastDetectedName ?? id;
          final String suffix = _lastDetectedDocument != null ? ' · ${_lastDetectedDocument}' : '';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Salida registrada para $label$suffix')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error registrando: $e')),
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
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  color: Colors.black.withOpacity(0.35),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: SafeArea(
                    bottom: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (_lastDetectedName != null)
                          Text(
                            _lastDetectedName!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          )
                        else
                          const Text(
                            'Acerque su rostro a la cámara',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                        if (_lastDetectedDocument != null)
                          Text(
                            _lastDetectedDocument!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70, fontSize: 14),
                          )
                        else if (!_facePresent)
                          const Text(
                            'Buscando rostro...',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white60, fontSize: 13),
                          ),
                      ],
                    ),
                  ),
                ),
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


