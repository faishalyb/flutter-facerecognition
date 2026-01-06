// ignore_for_file: unused_field

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path_provider/path_provider.dart';

import '../main.dart';

class SimpleLiveCameraScreen extends StatefulWidget {
  final String title;
  final String instruction;

  const SimpleLiveCameraScreen({
    super.key,
    required this.title,
    required this.instruction,
  });

  @override
  State<SimpleLiveCameraScreen> createState() => _SimpleLiveCameraScreenState();
}

class _SimpleLiveCameraScreenState extends State<SimpleLiveCameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _isInitialized = false;
  bool _isCapturing = false;
  String? _error;

  late final FaceDetector _faceDetector;

  String _status = 'Posisikan wajah di dalam frame';
  int _stableCount = 0;

  DateTime _lastProcess = DateTime.fromMillisecondsSinceEpoch(0);
  final int _processEveryMs = 200;

  int _frameRotation = 0;
  CameraDescription? _selectedCamera;

  // ✅ tambahan: lensa yang aktif (default: front)
  CameraLensDirection _currentLens = CameraLensDirection.front;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableLandmarks: false,
        enableContours: false,
        enableClassification: false,
        enableTracking: false,
        minFaceSize: 0.12,
      ),
    );

    _initializeCamera();
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

  CameraDescription? _getCamera(CameraLensDirection lens) {
    for (final cam in cameras) {
      if (cam.lensDirection == lens) return cam;
    }
    return null;
  }

  Future<void> _switchCamera() async {
    if (_isCapturing) return;

    final newLens = _currentLens == CameraLensDirection.front
        ? CameraLensDirection.back
        : CameraLensDirection.front;

    final nextCam = _getCamera(newLens);
    if (nextCam == null) {
      // device mungkin tidak punya kamera ini
      return;
    }

    setState(() {
      _isInitialized = false;
      _error = null;
      _status = 'Mengganti kamera...';
      _stableCount = 0;
    });

    try {
      await _stopStreamSafe();
      await _controller?.dispose();

      _selectedCamera = nextCam;
      _currentLens = newLens;

      final controller = CameraController(
        nextCam,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await controller.initialize();

      _controller = controller;
      _frameRotation = nextCam.sensorOrientation;

      setState(() {
        _isInitialized = true;
        _error = null;
        _status = 'Posisikan wajah di dalam frame';
      });

      await _startStream();
    } catch (e) {
      setState(() => _error = 'Error switch camera: $e');
    }
  }

  Future<void> _initializeCamera() async {
    try {
      if (cameras.isEmpty) {
        setState(() => _error = 'Tidak ada kamera tersedia');
        return;
      }

      // ✅ pilih kamera sesuai _currentLens, fallback ke cameras.first
      final selected = _getCamera(_currentLens) ?? cameras.first;
      _selectedCamera = selected;

      final controller = CameraController(
        selected,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await controller.initialize();

      _controller = controller;
      _frameRotation = selected.sensorOrientation;

      setState(() {
        _isInitialized = true;
        _error = null;
      });

      await _startStream();
    } catch (e) {
      setState(() => _error = 'Error init camera: $e');
    }
  }

  Future<void> _startStream() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isStreamingImages) return;

    _stableCount = 0;

    await c.startImageStream((CameraImage image) async {
      final now = DateTime.now();
      if (now.difference(_lastProcess).inMilliseconds < _processEveryMs) return;
      _lastProcess = now;

      if (_isCapturing) return;

      try {
        final inputImage = _cameraImageToInputImage(image);
        final faces = await _faceDetector.processImage(inputImage);

        if (!mounted) return;

        if (faces.isEmpty) {
          _setStatus('👤 Wajah tidak terdeteksi', stable: false);
          return;
        }

        if (faces.length > 1) {
          _setStatus('⚠️ Terdeteksi lebih dari 1 wajah', stable: false);
          return;
        }

        final face = faces.first;

        if (!_isFaceLargeEnough(face, image.width, image.height)) {
          _setStatus('🔍 Dekatkan wajah ke kamera', stable: false);
          return;
        }

        if (!_isFrontPose(face)) {
          _setStatus('↔️ Hadapkan wajah lurus ke depan', stable: false);
          return;
        }

        _stableCount++;
        _setStatus('✅ Bagus! Tahan... ($_stableCount/6)', stable: true);

        if (_stableCount >= 6) {
          await _captureAndReturn();
        }
      } catch (e) {
        if (!mounted) return;
        _setStatus('Memproses...', stable: false);
      }
    });
  }

  Future<void> _stopStreamSafe() async {
    final c = _controller;
    if (c == null) return;
    if (!c.value.isStreamingImages) return;
    try {
      await c.stopImageStream();
    } catch (_) {}
  }

  void _setStatus(String text, {required bool stable}) {
    if (!mounted) return;
    setState(() {
      _status = text;
      if (!stable) _stableCount = 0;
    });
  }

  bool _isFaceLargeEnough(Face face, int imgW, int imgH) {
    final bb = face.boundingBox;
    final faceArea = max(0.0, bb.width) * max(0.0, bb.height);
    final frameArea = imgW.toDouble() * imgH.toDouble();
    final ratio = faceArea / frameArea;
    return ratio >= 0.12;
  }

  bool _isFrontPose(Face face) {
    final yaw = face.headEulerAngleY ?? 0.0;
    final pitch = face.headEulerAngleX ?? 0.0;
    final roll = face.headEulerAngleZ ?? 0.0;

    return yaw.abs() <= 12 && pitch.abs() <= 15 && roll.abs() <= 15;
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

  Future<void> _captureAndReturn() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (_isCapturing) return;

    setState(() => _isCapturing = true);

    try {
      await _stopStreamSafe();

      final dir = await getApplicationDocumentsDirectory();
      final XFile photo = await c.takePicture();

      final fileName =
          'reg_${_currentLens.name}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final filePath = '${dir.path}/$fileName';

      await File(photo.path).copy(filePath);

      if (!mounted) return;
      Navigator.pop(context, filePath);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal capture: $e'),
          backgroundColor: Colors.red,
        ),
      );

      setState(() => _isCapturing = false);
      await _startStream();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        centerTitle: true,
        backgroundColor: Colors.black87,
        // ✅ optional: tombol switch camera (selain swipe)
        actions: [
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            onPressed: _isCapturing ? null : _switchCamera,
            tooltip: 'Ganti kamera',
          ),
        ],
      ),
      backgroundColor: Colors.black,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue[900]!.withOpacity(0.8),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                const Icon(Icons.face, color: Colors.white, size: 24),
                const SizedBox(height: 8),
                Text(
                  _status,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  widget.instruction,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: _buildPreview(),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.red[600],
                  child: IconButton(
                    icon:
                        const Icon(Icons.close, color: Colors.white, size: 30),
                    onPressed:
                        _isCapturing ? null : () => Navigator.pop(context),
                  ),
                ),
                CircleAvatar(
                  radius: 40,
                  backgroundColor: Colors.white,
                  child: CircleAvatar(
                    radius: 35,
                    backgroundColor:
                        _isCapturing ? Colors.grey : Colors.green[600],
                    child: IconButton(
                      icon: _isCapturing
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.camera_alt,
                              color: Colors.white, size: 28),
                      onPressed: _isCapturing ? null : _captureAndReturn,
                    ),
                  ),
                ),
                const SizedBox(width: 60),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    if (_error != null) {
      return Container(
        color: Colors.grey[900],
        child: Center(
          child: Text(_error!, style: const TextStyle(color: Colors.white70)),
        ),
      );
    }

    if (!_isInitialized || _controller == null) {
      return Container(
        color: Colors.grey[900],
        child: const Center(
          child: CircularProgressIndicator(color: Colors.blue),
        ),
      );
    }

    // ✅ swipe kiri/kanan untuk switch camera
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v.abs() > 200) {
          _switchCamera();
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_controller!),
          Center(
            child: Container(
              width: 250,
              height: 300,
              decoration: BoxDecoration(
                border:
                    Border.all(color: Colors.white.withOpacity(0.8), width: 2),
                borderRadius: BorderRadius.circular(150),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
