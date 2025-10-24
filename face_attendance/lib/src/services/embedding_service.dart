import 'dart:typed_data';
import 'dart:io';

import 'package:tflite_flutter/tflite_flutter.dart' as tfl;

class EmbeddingService {
  EmbeddingService();

  tfl.Interpreter? _interpreter;
  bool _loaded = false;
  String? _lastError;
  String _source = 'none'; // 'asset' | 'file' | 'none'

  Future<void> loadModelFromAsset(String assetPath) async {
    if (_interpreter != null) return;
    try {
      _interpreter = await tfl.Interpreter.fromAsset(assetPath);
      _loaded = true;
      _lastError = null;
      _source = 'asset';
    } catch (e) {
      _loaded = false;
      _lastError = e.toString();
    }
  }

  Future<void> loadModelFromFile(String filePath) async {
    try {
      await close();
      final tfl.InterpreterOptions options = tfl.InterpreterOptions();
      _interpreter = await tfl.Interpreter.fromFile(File(filePath), options: options);
      _loaded = true;
      _lastError = null;
      _source = 'file';
    } catch (e) {
      _loaded = false;
      _lastError = e.toString();
    }
  }

  // input: imagen preprocesada 112x112 RGB normalizada [-1,1]
  // output: vector embedding (p.ej. 128/192)
  List<double> runEmbedding(List<List<List<double>>> input) {
    final tfl.Interpreter? interpreter = _interpreter;
    if (interpreter == null || !_loaded) {
      throw StateError('Interpreter not loaded: ${_lastError ?? 'model not loaded'}');
    }
    try {
      final List<int> inputShape = interpreter.getInputTensor(0).shape;
      // Muchos modelos esperan [1, 112, 112, 3]. Si la primera dim es batch, envolver input.
      final bool expectsBatch = inputShape.length == 4;
      final dynamic modelInput = expectsBatch ? [input] : input;

      final List<int> outputShape = interpreter.getOutputTensor(0).shape;
      dynamic modelOutput;
      if (outputShape.length == 2) {
        // p.ej. [1, 128]
        modelOutput = List.generate(outputShape[0], (_) => List<double>.filled(outputShape[1], 0));
      } else if (outputShape.length == 1) {
        modelOutput = List<double>.filled(outputShape[0], 0);
      } else if (outputShape.length == 4 && outputShape[0] == 1) {
        // p.ej. [1,1,1,128]
        modelOutput = List.generate(outputShape[0], (_) =>
            List.generate(outputShape[1], (_) =>
                List.generate(outputShape[2], (_) => List<double>.filled(outputShape[3], 0))));
      } else {
        // Fallback genérico: vector del último tamaño
        modelOutput = List<double>.filled(outputShape.last, 0);
      }

      interpreter.run(modelInput, modelOutput);

      // Extraer como vector 1D
      if (modelOutput is List<double>) {
        return modelOutput;
      } else if (modelOutput is List && modelOutput.isNotEmpty) {
        dynamic out = modelOutput;
        // Desciende hasta encontrar List<double>
        while (out is List && out.isNotEmpty && out.first is List) {
          out = out.first;
        }
        if (out is List<double>) {
          return out;
        }
      }
      // Si no se pudo, intenta convertir a double
      final int size = outputShape.last;
      final List<double> flat = List<double>.filled(size, 0);
      int idx = 0;
      void flatten(dynamic v) {
        if (v is List) {
          for (final e in v) {
            flatten(e);
            if (idx >= size) return;
          }
        } else if (v is num && idx < size) {
          flat[idx++] = v.toDouble();
        }
      }
      flatten(modelOutput);
      return flat;
    } catch (e) {
      _lastError = e.toString();
      rethrow;
    }
  }

  Future<void> close() async {
    _interpreter?.close();
    _interpreter = null;
    _loaded = false;
    _lastError = null;
    _source = 'none';
  }

  bool get isLoaded => _loaded;
  String? get lastError => _lastError;
  String get source => _source;
}


