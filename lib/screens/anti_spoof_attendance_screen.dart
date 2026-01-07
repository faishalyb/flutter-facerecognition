// ignore_for_file: unused_field

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:hive/hive.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'package:presensi/services/spoof_service_native.dart';

import '../main.dart';
import '../models/user_model.dart';

class FastAntiSpoofAttendanceScreen extends StatefulWidget {
  const FastAntiSpoofAttendanceScreen({super.key});

  @override
  State<FastAntiSpoofAttendanceScreen> createState() =>
      _FastAntiSpoofAttendanceScreenState();
}

class _FastAntiSpoofAttendanceScreenState
    extends State<FastAntiSpoofAttendanceScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  CameraDescription? _activeCamera;
  late final FaceDetector _faceDetector;

  bool _isInitialized = false;
  bool _isProcessing = false;
  String? _error;

  CameraLensDirection _preferredLens = CameraLensDirection.back;

  DateTime _lastProcess = DateTime.fromMillisecondsSinceEpoch(0);
  static const int _processEveryMs = 150;

  int _frameRotation = 90;
  String _status = 'Posisikan wajah Anda';

  bool showResult = false;
  UserModel? recognizedUser;

  DateTime? _faceStableStart;
  static const int _stableTimeMs = 800;

  final SpoofNativeService _spoofNative = SpoofNativeService();
  bool _nativeSpoofReady = true;
  String? _nativeSpoofError;

  ui.Rect? _lastFaceRect;
  int _stableFrameCount = 0;
  static const int _minStableFrames = 4;
  static const double _movementThreshold = 20.0;

  List<_UserEmbedding>? _cachedUsers;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableContours: false,
        enableLandmarks: false,
        enableTracking: false,
        enableClassification: false,
        minFaceSize: 0.12,
      ),
    );

    _initializeCamera();
    _preloadUserEmbeddings();
  }

  void _preloadUserEmbeddings() {
    try {
      final userBox = Hive.box<UserModel>('users');
      _cachedUsers = [];

      for (final user in userBox.values) {
        for (final emb in user.faceEmbeddings) {
          _cachedUsers!.add(_UserEmbedding(user: user, embedding: emb));
        }
      }

      if (kDebugMode) {
        print('✅ Cached ${_cachedUsers!.length} embeddings');
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Failed to cache embeddings: $e');
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopStreamSafe();
    _controller?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      _stopStreamSafe();
      c.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    try {
      if (cameras.isEmpty) {
        setState(() => _error = 'Tidak ada kamera tersedia');
        return;
      }

      final selected = _pickCamera(_preferredLens) ?? cameras.first;
      _activeCamera = selected;
      _frameRotation = selected.sensorOrientation;

      final controller = CameraController(
        selected,
        ResolutionPreset.max,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await controller.initialize();

      setState(() {
        _controller = controller;
        _isInitialized = true;
        _error = null;
        showResult = false;
        recognizedUser = null;
        _status = 'Posisikan wajah Anda';
      });

      await _startStream();
    } catch (e) {
      setState(() => _error = 'Error init camera: $e');
    }
  }

  CameraDescription? _pickCamera(CameraLensDirection lens) {
    for (final cam in cameras) {
      if (cam.lensDirection == lens) return cam;
    }
    return null;
  }

  Future<void> _switchCamera() async {
    _preferredLens = (_preferredLens == CameraLensDirection.front)
        ? CameraLensDirection.back
        : CameraLensDirection.front;

    setState(() {
      _isInitialized = false;
      _error = null;
      _status = 'Mengganti kamera...';
    });

    await _stopStreamSafe();
    await _controller?.dispose();
    _controller = null;

    await _initializeCamera();
  }

  Future<void> _startStream() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isStreamingImages) return;

    await c.startImageStream((CameraImage image) async {
      if (_isProcessing) return;

      final now = DateTime.now();
      if (now.difference(_lastProcess).inMilliseconds < _processEveryMs) return;
      _lastProcess = now;

      try {
        final input = _cameraImageToInputImage(image);
        final faces = await _faceDetector.processImage(input);
        if (!mounted) return;

        if (faces.isEmpty) {
          _resetStability();
          _setStatus('👤 Wajah tidak terdeteksi');
          return;
        }

        if (faces.length > 1) {
          _resetStability();
          _setStatus('⚠️ Lebih dari 1 wajah');
          return;
        }

        final face = faces.first;

        if (!_isFaceLargeEnough(face, image.width, image.height)) {
          _resetStability();
          _setStatus('🔍 Dekatkan wajah');
          return;
        }

        if (_isFaceStable(face)) {
          _stableFrameCount++;

          if (_stableFrameCount >= _minStableFrames) {
            if (_faceStableStart == null) {
              _faceStableStart = now;
              _setStatus('✅ Tahan...');
            } else {
              final elapsed = now.difference(_faceStableStart!).inMilliseconds;

              if (elapsed >= _stableTimeMs) {
                await _captureAndProcess();
              } else {
                _setStatus('⏳ Tahan...');
              }
            }
          } else {
            _setStatus('📸 Tahan posisi...');
          }
        } else {
          _resetStability();
          _setStatus('🎯 Hadapkan wajah');
        }

        _lastFaceRect = face.boundingBox;
      } catch (e) {
        if (kDebugMode) {
          print('Processing error: $e');
        }
      }
    });
  }

  void _resetStability() {
    _faceStableStart = null;
    _stableFrameCount = 0;
    _lastFaceRect = null;
  }

  bool _isFaceStable(Face face) {
    if (_lastFaceRect == null) return true;

    final currentRect = face.boundingBox;
    final dx = (currentRect.center.dx - _lastFaceRect!.center.dx).abs();
    final dy = (currentRect.center.dy - _lastFaceRect!.center.dy).abs();
    final movement = dx + dy;

    return movement < _movementThreshold;
  }

  Future<void> _stopStreamSafe() async {
    final c = _controller;
    if (c == null) return;
    if (!c.value.isStreamingImages) return;
    try {
      await c.stopImageStream();
    } catch (_) {}
  }

  void _setStatus(String msg) {
    if (!mounted) return;
    setState(() => _status = msg);
  }

  bool _isFaceLargeEnough(Face face, int imgW, int imgH) {
    final bb = face.boundingBox;
    final faceArea = max(0.0, bb.width) * max(0.0, bb.height);
    final frameArea = imgW.toDouble() * imgH.toDouble();
    final ratio = faceArea / frameArea;
    return ratio >= 0.10;
  }

  InputImage _cameraImageToInputImage(CameraImage image) {
    final WriteBuffer allBytes = WriteBuffer();
    for (final plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    final metadata = InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: _inputImageRotation(_frameRotation),
      format: InputImageFormat.yuv420,
      bytesPerRow: image.planes.first.bytesPerRow,
    );

    return InputImage.fromBytes(bytes: bytes, metadata: metadata);
  }

  InputImageRotation _inputImageRotation(int rotation) {
    switch (rotation) {
      case 0:
        return InputImageRotation.rotation0deg;
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        return InputImageRotation.rotation90deg;
    }
  }

  Future<void> _captureAndProcess() async {
    if (_isProcessing) return;
    final c = _controller;
    if (c == null) return;

    setState(() {
      _isProcessing = true;
      _status = '📸 Memproses...';
      showResult = false;
      recognizedUser = null;
    });

    try {
      await _stopStreamSafe();

      final dir = await getApplicationDocumentsDirectory();
      final filePath =
          '${dir.path}/att_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final XFile photo = await c.takePicture();
      await File(photo.path).copy(filePath);

      final stillFaces =
          await _faceDetector.processImage(InputImage.fromFilePath(filePath));

      if (stillFaces.isEmpty) {
        throw Exception('Wajah tidak terdeteksi');
      }
      if (stillFaces.length > 1) {
        throw Exception('Lebih dari 1 wajah');
      }

      final face = stillFaces.first;
      final faceRect = face.boundingBox;

      // === Enhanced Native Spoof Check ===
      try {
        final spoofRes = await _spoofNative.detectSpoof(
          imagePath: filePath,
          faceRect: faceRect,
        );

        setState(() {
          _nativeSpoofReady = true;
          _nativeSpoofError = null;
        });

        if (kDebugMode) {
          print('🔍 Spoof Check: ${spoofRes.detailMsg}');
        }

        if (spoofRes.isSpoof) {
          await _showSpoofAlert(
            'Spoof terdeteksi!\n\n'
            '${spoofRes.detailMsg}\n\n'
            'Gunakan wajah asli untuk absen.',
          );
          // ignore: use_build_context_synchronously
          return Navigator.pop(context);
        }
      } catch (e) {
        setState(() {
          _nativeSpoofReady = false;
          _nativeSpoofError = e.toString();
        });
        throw Exception('Anti-spoof error: $e');
      }

      // === Enhanced Face Recognition ===
      final embedding = await _extractFaceNetEmbeddingFromFile(
        filePath,
        faceRect: faceRect,
      );

      if (embedding == null) {
        throw Exception('Gagal membuat embedding');
      }

      // ✅ FIXED: Improved matching algorithm
      UserModel? matchedUser;
      double bestSim = -1;
      const threshold = 0.65; // ✅ Naikin threshold dari 0.58 ke 0.65

      // ✅ NEW: Multi-embedding averaging untuk akurasi lebih tinggi
      if (_cachedUsers != null && _cachedUsers!.isNotEmpty) {
        // Group by user
        final userScores = <String, List<double>>{};

        for (final cached in _cachedUsers!) {
          final sim = _cosineSimilarity(embedding, cached.embedding);

          final userId = cached.user.name;
          if (!userScores.containsKey(userId)) {
            userScores[userId] = [];
          }
          userScores[userId]!.add(sim);
        }

        // ✅ Calculate average similarity per user
        for (final entry in userScores.entries) {
          final userId = entry.key;
          final similarities = entry.value;

          // Ambil top 3 similarity (jika ada multiple embeddings)
          similarities.sort((a, b) => b.compareTo(a));
          final topSimilarities = similarities.take(3).toList();
          final avgSim =
              topSimilarities.reduce((a, b) => a + b) / topSimilarities.length;

          if (kDebugMode) {
            final user =
                _cachedUsers!.firstWhere((c) => c.user.name == userId).user;
            print(
                '📊 ${user.name}: avg=${avgSim.toStringAsFixed(3)} (top ${topSimilarities.length})');
          }

          if (avgSim > bestSim) {
            bestSim = avgSim;
            if (avgSim >= threshold) {
              matchedUser =
                  _cachedUsers!.firstWhere((c) => c.user.name == userId).user;
            }
          }
        }
      } else {
        // Fallback ke Hive jika cache gagal
        final userBox = Hive.box<UserModel>('users');
        for (final user in userBox.values) {
          final similarities = <double>[];

          for (final ue in user.faceEmbeddings) {
            final sim = _cosineSimilarity(embedding, ue);
            similarities.add(sim);
          }

          if (similarities.isNotEmpty) {
            similarities.sort((a, b) => b.compareTo(a));
            final topSimilarities = similarities.take(3).toList();
            final avgSim = topSimilarities.reduce((a, b) => a + b) /
                topSimilarities.length;

            if (avgSim > bestSim) {
              bestSim = avgSim;
              matchedUser = (avgSim >= threshold) ? user : null;
            }
          }
        }
      }

      if (kDebugMode) {
        print(
            '🎯 Best match: ${matchedUser?.name ?? "Unknown"} (${bestSim.toStringAsFixed(3)})');
      }

      setState(() {
        recognizedUser = matchedUser;
        showResult = true;
        _status = matchedUser != null
            ? '✅ ${matchedUser.name} ' // kalau mau pake persen (${(bestSim * 100).toStringAsFixed(1)}%)
            : '❌ Tidak dikenali'; // kalau mau pake persen (${(bestSim * 100).toStringAsFixed(1)}%)f
      });

      if (matchedUser != null) {
        matchedUser.addAttendance();
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ ${matchedUser.name} berhasil absen!'),
            backgroundColor: Colors.green,
            duration: const Duration(milliseconds: 2000),
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '❌ Wajah tidak dikenali (similarity: ${(bestSim * 100).toStringAsFixed(1)}%)'),
            backgroundColor: Colors.red,
            duration: const Duration(milliseconds: 2000),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        recognizedUser = null;
        showResult = true;
        _status = '❌ Error: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(milliseconds: 2000),
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() => _isProcessing = false);

      Future.delayed(const Duration(milliseconds: 2000), () {
        if (mounted) {
          setState(() {
            showResult = false;
            recognizedUser = null;
            _status = 'Posisikan wajah Anda';
          });
          _resetStability();
          _startStream();
        }
      });
    }
  }

  Future<void> _showSpoofAlert(String message) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.block, color: Colors.red, size: 24),
            SizedBox(width: 8),
            Text('SPOOFING ALERT', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(message, style: TextStyle(fontSize: 13)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    if (mounted) {
      setState(() {
        showResult = false;
        recognizedUser = null;
        _status = 'Posisikan wajah Anda';
      });
      _resetStability();
      _startStream();
    }
  }

  Future<List<double>?> _extractFaceNetEmbeddingFromFile(
    String imagePath, {
    required ui.Rect faceRect,
  }) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      // ✅ FIXED: Margin yang konsisten dengan registration
      final marginX = (faceRect.width * 0.25).round(); // 0.15 → 0.25
      final marginY = (faceRect.height * 0.25).round();

      int left = (faceRect.left.round() - marginX).clamp(0, decoded.width - 1);
      int top = (faceRect.top.round() - marginY).clamp(0, decoded.height - 1);
      int right = (faceRect.right.round() + marginX).clamp(0, decoded.width);
      int bottom = (faceRect.bottom.round() + marginY).clamp(0, decoded.height);

      final w = max(1, right - left);
      final h = max(1, bottom - top);

      if (w < 50 || h < 50) return null;

      final cropped =
          img.copyCrop(decoded, x: left, y: top, width: w, height: h);

      // ✅ Service sekarang sudah handle pre-processing + normalization
      final emb =
          await faceRecognitionService.extractEmbeddingFromImage(cropped);
      return emb;
    } catch (_) {
      return null;
    }
  }

  double _cosineSimilarity(List<double> e1, List<double> e2) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Absensi Cepat'),
        centerTitle: true,
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Ganti Kamera',
            onPressed: _isProcessing ? null : _switchCamera,
            icon: const Icon(Icons.flip_camera_ios),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _nativeSpoofReady ? Icons.shield_outlined : Icons.warning,
                    size: 16,
                    color: _nativeSpoofReady ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Mode Enhanced • ${_cachedUsers?.length ?? 0} pengguna',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue[900],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: _buildPreview(),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.blue[600],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _status,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: Colors.white,
                ),
              ),
            ),
            if (showResult) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: recognizedUser != null
                      ? Colors.green[50]
                      : Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: recognizedUser != null
                        ? Colors.green[300]!
                        : Colors.red[300]!,
                    width: 2,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      recognizedUser != null ? Icons.check_circle : Icons.error,
                      color: recognizedUser != null ? Colors.green : Colors.red,
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        recognizedUser != null
                            ? recognizedUser!.name
                            : 'Tidak Dikenali',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: recognizedUser != null
                              ? Colors.green[800]
                              : Colors.red[800],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    if (_error != null) {
      return Container(
        color: Colors.grey[200],
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 40, color: Colors.grey[400]),
              const SizedBox(height: 8),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
      );
    }

    if (!_isInitialized || _controller == null) {
      return Container(
        color: Colors.grey[200],
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(_controller!),
        Center(
          child: Container(
            width: 200,
            height: 260,
            decoration: BoxDecoration(
              border:
                  Border.all(color: Colors.white.withOpacity(0.8), width: 2),
              borderRadius: BorderRadius.circular(130),
            ),
          ),
        ),
      ],
    );
  }
}

class _UserEmbedding {
  final UserModel user;
  final List<double> embedding;

  _UserEmbedding({required this.user, required this.embedding});
}
