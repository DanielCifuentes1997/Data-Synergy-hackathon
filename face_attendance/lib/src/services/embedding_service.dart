import 'dart:typed_data';

import 'package:tflite_flutter/tflite_flutter.dart' as tfl;

class EmbeddingService {
  EmbeddingService();

  tfl.Interpreter? _interpreter;

  Future<void> loadModelFromAsset(String assetPath) async {
    _interpreter ??= await tfl.Interpreter.fromAsset(assetPath);
  }

  // input: imagen preprocesada 112x112 RGB normalizada [-1,1]
  // output: vector embedding (p.ej. 192)
  List<double> runEmbedding(List<List<List<double>>> input) {
    final tfl.Interpreter? interpreter = _interpreter;
    if (interpreter == null) {
      throw StateError('Interpreter not loaded');
    }
    final outputShape = interpreter.getOutputTensor(0).shape;
    final int embeddingSize = outputShape.last;
    final List<double> output = List<double>.filled(embeddingSize, 0);
    interpreter.run(input, output);
    return output;
  }

  Future<void> close() async {
    _interpreter?.close();
    _interpreter = null;
  }
}


