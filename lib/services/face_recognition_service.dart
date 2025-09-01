import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

class FaceRecognitionService {
  late Interpreter interpreter;
  late FaceDetector faceDetector;

  FaceRecognitionService() {
    faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableContours: false,
        enableClassification: false,
        enableLandmarks: false,
        enableTracking: false,
        minFaceSize: 0.1,
        performanceMode: FaceDetectorMode.accurate,
      ),
    );
  }

  Future<void> loadModel() async {
    try {
      interpreter = await Interpreter.fromAsset('lib/assets/models/mobile_face_net.tflite');
      print('Model loaded successfully');
    } catch (e) {
      print('Error loading model: $e');
      throw Exception('Failed to load face recognition model');
    }
  }

  Future<List<double>?> extractFaceEmbedding(String imagePath) async {
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final faces = await faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        return null; // Tidak ada wajah yang terdeteksi
      }

      // Ambil wajah pertama yang terdeteksi
      final face = faces.first;

      // Crop dan resize wajah
      final croppedFace = await _cropAndResizeFace(imagePath, face);
      if (croppedFace == null) return null;

      // Konversi ke format input model (112x112x3)
      final input = _preprocessImage(croppedFace);

      // Output model (512 dimensional embedding)
      final output = List.filled(192, 0.0).reshape([1, 192]);

      // Run inference
      interpreter.run(input, output);

      return output[0].cast<double>();
    } catch (e) {
      print('Error extracting face embedding: $e');
      return null;
    }
  }

  Future<Uint8List?> _cropAndResizeFace(String imagePath, Face face) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return null;

      final boundingBox = face.boundingBox;

      // Crop wajah dengan margin
      final margin = 20;
      final left = max(0, boundingBox.left.toInt() - margin);
      final top = max(0, boundingBox.top.toInt() - margin);
      final right = min(image.width, boundingBox.right.toInt() + margin);
      final bottom = min(image.height, boundingBox.bottom.toInt() + margin);

      final croppedImage = img.copyCrop(
        image,
        x: left,
        y: top,
        width: right - left,
        height: bottom - top,
      );

      // Resize ke 112x112
      final resizedImage = img.copyResize(croppedImage, width: 112, height: 112);

      return img.encodePng(resizedImage);
    } catch (e) {
      print('Error cropping face: $e');
      return null;
    }
  }

  List<List<List<List<double>>>> _preprocessImage(Uint8List imageBytes) {
    final image = img.decodeImage(imageBytes)!;
    final resizedImage = img.copyResize(image, width: 112, height: 112);

    final input = List.generate(
      1,
          (b) => List.generate(
        112,
            (y) => List.generate(
          112,
              (x) => List.generate(3, (c) {
            final pixel = resizedImage.getPixel(x, y);
            late double value;
            switch (c) {
              case 0:
              // Red channel
                value = ((pixel.r) * 255).toDouble();
                break;
              case 1:
              // Green channel
                value = ((pixel.g) * 255).toDouble();
                break;
              case 2:
              // Blue channel
                value = ((pixel.b) * 255).toDouble();
                break;
            }
            // Normalisasi ke [-1, 1]
            return (value - 127.5) / 127.5;
          }),
        ),
      ),
    );

    return input;
  }

  double calculateSimilarity(List<double> embedding1, List<double> embedding2) {
    if (embedding1.length != embedding2.length) return 0.0;

    double dotProduct = 0.0;
    double norm1 = 0.0;
    double norm2 = 0.0;

    for (int i = 0; i < embedding1.length; i++) {
      dotProduct += embedding1[i] * embedding2[i];
      norm1 += embedding1[i] * embedding1[i];
      norm2 += embedding2[i] * embedding2[i];
    }

    norm1 = sqrt(norm1);
    norm2 = sqrt(norm2);

    if (norm1 == 0.0 || norm2 == 0.0) return 0.0;

    return dotProduct / (norm1 * norm2);
  }

  bool isSamePerson(List<double> embedding1, List<double> embedding2, {double threshold = 0.7}) {
    final similarity = calculateSimilarity(embedding1, embedding2);
    return similarity >= threshold;
  }

  void dispose() {
    interpreter.close();
    faceDetector.close();
  }
}