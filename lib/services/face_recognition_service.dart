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

  // ✅ FIXED: Gunakan normalisasi standar MobileFaceNet
  static const bool USE_MEAN_STD_NORM = true; // Mean/Std normalization

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
      print('✅ MobileFaceNet loaded (Mean/Std normalization)');
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
      // ✅ ENHANCED: Pre-processing yang lebih baik
      final preprocessed = _preprocessFaceImage(faceImage);
      final resized = img.copyResize(
        preprocessed,
        width: _inputSize,
        height: _inputSize,
        interpolation: img.Interpolation.cubic,
      );

      final input = _imageToFloat32Input(resized);
      final output =
          List<double>.filled(_embeddingSize, 0).reshape([1, _embeddingSize]);

      _interpreter.run(input, output);

      final raw = List<double>.from(output[0]);

      // ✅ CRITICAL: L2 normalize HARUS dilakukan
      final normalized = _l2Normalize(raw);

      return normalized;
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

      // ✅ ENHANCED: Pre-processing yang konsisten
      final preprocessed = _preprocessFaceImage(faceImage);
      final input = _imageToFloat32Input(preprocessed);
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

  // ✅ NEW: Pre-processing untuk konsistensi
  img.Image _preprocessFaceImage(img.Image image) {
    // Resize jika belum
    final resized = (image.width == _inputSize && image.height == _inputSize)
        ? image
        : img.copyResize(
            image,
            width: _inputSize,
            height: _inputSize,
            interpolation: img.Interpolation.cubic,
          );

    // Histogram equalization untuk lighting consistency
    return _histogramEqualization(resized);
  }

  // ✅ NEW: Histogram Equalization
  img.Image _histogramEqualization(img.Image image) {
    final hist = List<int>.filled(256, 0);

    // Build histogram
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final gray =
            (pixel.r * 0.299 + pixel.g * 0.587 + pixel.b * 0.114).round();
        hist[gray.clamp(0, 255)]++;
      }
    }

    // Cumulative distribution
    final cdf = List<int>.filled(256, 0);
    cdf[0] = hist[0];
    for (int i = 1; i < 256; i++) {
      cdf[i] = cdf[i - 1] + hist[i];
    }

    final totalPixels = image.width * image.height;
    final cdfMin = cdf.firstWhere((v) => v > 0);

    // Create lookup table
    final lut = List<int>.generate(256, (i) {
      return ((cdf[i] - cdfMin) * 255 / (totalPixels - cdfMin))
          .round()
          .clamp(0, 255);
    });

    // Apply equalization
    final result = image.clone();
    for (int y = 0; y < result.height; y++) {
      for (int x = 0; x < result.width; x++) {
        final pixel = result.getPixel(x, y);
        final r = lut[pixel.r.toInt().clamp(0, 255)];
        final g = lut[pixel.g.toInt().clamp(0, 255)];
        final b = lut[pixel.b.toInt().clamp(0, 255)];
        result.setPixelRgba(x, y, r, g, b, 255);
      }
    }

    return result;
  }

  // ✅ FIXED: Cosine similarity dengan validasi
  double calculateSimilarity(List<double> e1, List<double> e2) {
    if (e1.length != e2.length) {
      print('⚠️ Embedding length mismatch: ${e1.length} vs ${e2.length}');
      return -1;
    }

    double dot = 0, n1 = 0, n2 = 0;
    for (int i = 0; i < e1.length; i++) {
      dot += e1[i] * e2[i];
      n1 += e1[i] * e1[i];
      n2 += e2[i] * e2[i];
    }

    final denom = sqrt(n1) * sqrt(n2);
    if (denom == 0) {
      print('⚠️ Zero vector detected');
      return -1;
    }

    final sim = dot / denom;

    // ✅ Cosine similarity harus dalam range [-1, 1]
    if (sim < -1.0 || sim > 1.0) {
      print('⚠️ Invalid similarity: $sim');
    }

    return sim.clamp(-1.0, 1.0);
  }

  bool isSamePerson(
    List<double> e1,
    List<double> e2, {
    double threshold = 0.65, // ✅ Naikin threshold dari 0.60 ke 0.65
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

      // ✅ FIXED: Margin yang konsisten
      final marginX = (bb.width * 0.25).round(); // Naikin dari 0.20 ke 0.25
      final marginY = (bb.height * 0.25).round();

      int left = (bb.left.round() - marginX).clamp(0, image.width - 1);
      int top = (bb.top.round() - marginY).clamp(0, image.height - 1);
      int right = (bb.right.round() + marginX).clamp(0, image.width);
      int bottom = (bb.bottom.round() + marginY).clamp(0, image.height);

      final w = max(1, right - left);
      final h = max(1, bottom - top);

      if (w < 50 || h < 50) return null; // Minimal face size

      final cropped = img.copyCrop(image, x: left, y: top, width: w, height: h);

      return cropped;
    } catch (e) {
      print('❌ Error crop/resize: $e');
      return null;
    }
  }

  List<List<List<List<double>>>> _imageToFloat32Input(img.Image image) {
    final resized = (image.width == _inputSize && image.height == _inputSize)
        ? image
        : img.copyResize(
            image,
            width: _inputSize,
            height: _inputSize,
            interpolation: img.Interpolation.cubic,
          );

    // ✅ CRITICAL: Normalisasi yang BENAR untuk MobileFaceNet
    // Standard: (pixel - mean) / std
    // MobileFaceNet biasanya: mean=127.5, std=128.0
    const mean = 127.5;
    const std = 128.0;

    final input = List.generate(
      1,
      (_) => List.generate(
        _inputSize,
        (y) => List.generate(
          _inputSize,
          (x) => List.generate(3, (c) {
            final p = resized.getPixel(x, y);

            double v;
            if (c == 0)
              v = p.r.toDouble();
            else if (c == 1)
              v = p.g.toDouble();
            else
              v = p.b.toDouble();

            // ✅ Normalisasi standar: (pixel - mean) / std
            return (v - mean) / std;
          }),
        ),
      ),
    );

    return input;
  }

  // ✅ CRITICAL: L2 Normalization yang benar
  List<double> _l2Normalize(List<double> v) {
    double sumSquares = 0.0;
    for (final x in v) {
      sumSquares += x * x;
    }
    final norm = sqrt(sumSquares);

    if (norm < 1e-10) {
      // Zero vector protection
      print('⚠️ Warning: Near-zero embedding detected');
      return v;
    }

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
