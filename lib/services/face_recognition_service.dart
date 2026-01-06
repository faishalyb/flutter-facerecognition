import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class FaceRecognitionService {
  late final Interpreter _interpreter;
  late final FaceDetector _faceDetector;

  static const int _inputSize = 112;
  static const int _embeddingSize = 192;

  bool _modelLoaded = false;

  // 🔧 TOGGLE INI UNTUK TEST NORMALISASI
  static const bool USE_NEG1_TO_1 = true; // true = [-1,1], false = [0,1]

  FaceRecognitionService() {
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        enableContours: false,
        enableClassification: false,
        enableLandmarks: false,
        enableTracking: false,
        minFaceSize: 0.1,
      ),
    );
  }

  Future<void> loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset(
        'assets/models/mobile_face_net.tflite',
      );

      _modelLoaded = true;
      print(
          '✅ MobileFaceNet loaded (normalization: ${USE_NEG1_TO_1 ? "[-1,1]" : "[0,1]"})');
    } catch (e) {
      print('❌ Error loading model: $e');
      rethrow;
    }
  }

  Future<List<double>?> extractEmbeddingFromImage(img.Image faceImage) async {
    if (!_modelLoaded) {
      throw StateError('Model belum diload. Panggil loadModel() dulu.');
    }

    try {
      final resized = img.copyResize(faceImage, width: 112, height: 112);

      final input = _imageToFloat32Input(resized);
      final output =
          List<double>.filled(_embeddingSize, 0).reshape([1, _embeddingSize]);

      _interpreter.run(input, output);

      final raw = List<double>.from(output[0]);
      return _l2Normalize(raw); // service sudah normalize
    } catch (e) {
      print('❌ Error extracting embedding (from image): $e');
      return null;
    }
  }

  Future<List<double>?> extractFaceEmbedding(
    String imagePath, {
    bool rejectMultiFace = true,
  }) async {
    if (!_modelLoaded) {
      throw StateError('Model belum diload. Panggil loadModel() dulu.');
    }

    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) return null;
      if (rejectMultiFace && faces.length != 1) return null;

      final face = _pickBestFace(faces);
      final faceImage = await _cropAndResizeFace(imagePath, face);
      if (faceImage == null) return null;

      final input = _imageToFloat32Input(faceImage);
      final output =
          List<double>.filled(_embeddingSize, 0).reshape([1, _embeddingSize]);

      _interpreter.run(input, output);

      final raw = List<double>.from(output[0]);
      final normalized = _l2Normalize(raw);

      return normalized;
    } catch (e) {
      print('❌ Error extracting embedding: $e');
      return null;
    }
  }

  double calculateSimilarity(List<double> e1, List<double> e2) {
    if (e1.length != e2.length) return -1;

    double dot = 0, n1 = 0, n2 = 0;
    for (int i = 0; i < e1.length; i++) {
      dot += e1[i] * e2[i];
      n1 += e1[i] * e1[i];
      n2 += e2[i] * e2[i];
    }

    final denom = sqrt(n1) * sqrt(n2);
    if (denom == 0) return -1;

    return dot / denom;
  }

  bool isSamePerson(
    List<double> e1,
    List<double> e2, {
    double threshold = 0.60, // Turunkan jadi 0.60 untuk test
  }) {
    final sim = calculateSimilarity(e1, e2);
    return sim >= threshold;
  }

  Face _pickBestFace(List<Face> faces) {
    Face best = faces.first;
    double bestArea = _area(best.boundingBox);

    for (final f in faces.skip(1)) {
      final a = _area(f.boundingBox);
      if (a > bestArea) {
        best = f;
        bestArea = a;
      }
    }
    return best;
  }

  double _area(Rect r) => max(0.0, r.width) * max(0.0, r.height);

  Future<img.Image?> _cropAndResizeFace(String imagePath, Face face) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return null;

      final bb = face.boundingBox;

      // 🔧 MARGIN: Coba naikin kalau masih gagal (0.25 atau 0.30)
      final marginX = (bb.width * 0.20).round();
      final marginY = (bb.height * 0.20).round();

      int left = (bb.left.round() - marginX).clamp(0, image.width - 1);
      int top = (bb.top.round() - marginY).clamp(0, image.height - 1);
      int right = (bb.right.round() + marginX).clamp(0, image.width);
      int bottom = (bb.bottom.round() + marginY).clamp(0, image.height);

      final w = max(1, right - left);
      final h = max(1, bottom - top);

      if (w < 40 || h < 40) return null;

      final cropped = img.copyCrop(image, x: left, y: top, width: w, height: h);

      final resized = img.copyResize(
        cropped,
        width: _inputSize,
        height: _inputSize,
        interpolation: img.Interpolation.cubic, // 🔧 cubic lebih smooth
      );

      return resized;
    } catch (e) {
      print('❌ Error crop/resize: $e');
      return null;
    }
  }

  List<List<List<List<double>>>> _imageToFloat32Input(img.Image image) {
    final resized = (image.width == _inputSize && image.height == _inputSize)
        ? image
        : img.copyResize(image, width: _inputSize, height: _inputSize);

    final input = List.generate(
      1,
      (_) => List.generate(
        _inputSize,
        (y) => List.generate(
          _inputSize,
          (x) => List.generate(3, (c) {
            final p = resized.getPixel(x, y);

            final r = p.r.toDouble();
            final g = p.g.toDouble();
            final b = p.b.toDouble();

            double v;
            if (c == 0)
              v = r;
            else if (c == 1)
              v = g;
            else
              v = b;

            // 🔧 PILIH SALAH SATU NORMALISASI
            if (USE_NEG1_TO_1) {
              // Opsi 1: Range [-1, 1]
              return (v - 127.5) / 127.5;
            } else {
              // Opsi 2: Range [0, 1]
              return v / 255.0;
            }
          }),
        ),
      ),
    );

    return input;
  }

  List<double> _l2Normalize(List<double> v) {
    double sum = 0.0;
    for (final x in v) {
      sum += x * x;
    }
    final norm = sqrt(sum);
    if (norm == 0.0) return v;
    return v.map((x) => x / norm).toList();
  }

  void dispose() {
    if (_modelLoaded) {
      _interpreter.close();
    }
    _faceDetector.close();
  }
}

extension _ReshapeExt<T> on List<T> {
  List<List<T>> reshape(List<int> dims) {
    if (dims.length != 2) {
      throw ArgumentError('Only 2D reshape supported here');
    }
    final rows = dims[0];
    final cols = dims[1];
    if (length != rows * cols) {
      throw ArgumentError('Invalid reshape: $length != ${rows * cols}');
    }
    final out = <List<T>>[];
    for (int r = 0; r < rows; r++) {
      out.add(sublist(r * cols, (r + 1) * cols));
    }
    return out;
  }
}
