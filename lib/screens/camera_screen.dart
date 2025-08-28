import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../main.dart';

class CameraScreen extends StatefulWidget {
  final String title;

  const CameraScreen({Key? key, required this.title}) : super(key: key);

  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? controller;
  bool isInitialized = false;
  bool isCapturing = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = controller;

    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    try {
      if (cameras.isEmpty) {
        setState(() {
          errorMessage = 'Tidak ada kamera yang tersedia';
        });
        return;
      }

      // Pilih front camera jika tersedia, jika tidak gunakan back camera
      CameraDescription selectedCamera = cameras.first;
      for (final camera in cameras) {
        if (camera.lensDirection == CameraLensDirection.front) {
          selectedCamera = camera;
          break;
        }
      }

      controller = CameraController(
        selectedCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await controller!.initialize();

      if (mounted) {
        setState(() {
          isInitialized = true;
          errorMessage = null;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Error initializing camera: ${e.toString()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        centerTitle: true,
        backgroundColor: Colors.black87,
      ),
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // Instruction Card
          Container(
            width: double.infinity,
            margin: EdgeInsets.all(16),
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue[900]!.withOpacity(0.8),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Icon(Icons.face, color: Colors.white, size: 24),
                SizedBox(height: 8),
                Text(
                  'Posisikan wajah di dalam frame',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Pastikan pencahayaan cukup dan wajah terlihat jelas',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          // Camera Preview
          Expanded(
            child: Container(
              margin: EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: _buildCameraPreview(),
              ),
            ),
          ),

          // Camera Controls
          Container(
            padding: EdgeInsets.all(24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Cancel Button
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.red[600],
                  child: IconButton(
                    icon: Icon(Icons.close, color: Colors.white, size: 30),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),

                // Capture Button
                CircleAvatar(
                  radius: 40,
                  backgroundColor: Colors.white,
                  child: CircleAvatar(
                    radius: 35,
                    backgroundColor: isCapturing ? Colors.grey : Colors.blue[600],
                    child: IconButton(
                      icon: isCapturing
                          ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                          : Icon(Icons.camera_alt, color: Colors.white, size: 30),
                      onPressed: isCapturing ? null : _takePicture,
                    ),
                  ),
                ),

                // Switch Camera Button (if multiple cameras available)
                CircleAvatar(
                  radius: 30,
                  backgroundColor: cameras.length > 1 ? Colors.blue[600] : Colors.grey,
                  child: IconButton(
                    icon: Icon(Icons.flip_camera_ios, color: Colors.white, size: 30),
                    onPressed: cameras.length > 1 ? _switchCamera : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (errorMessage != null) {
      return Container(
        color: Colors.grey[900],
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, color: Colors.red, size: 64),
              SizedBox(height: 16),
              Text(
                'Camera Error',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
              SizedBox(height: 8),
              Text(
                errorMessage!,
                style: TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 16),
              ElevatedButton(
                onPressed: _initializeCamera,
                child: Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (!isInitialized || controller == null) {
      return Container(
        color: Colors.grey[900],
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.blue),
              SizedBox(height: 16),
              Text(
                'Initializing Camera...',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(controller!),

        // Face Guide Overlay
        Center(
          child: Container(
            width: 250,
            height: 300,
            decoration: BoxDecoration(
              border: Border.all(
                color: Colors.white.withOpacity(0.8),
                width: 2,
              ),
              borderRadius: BorderRadius.circular(150),
            ),
            child: CustomPaint(
              painter: FaceGuidePainter(),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _takePicture() async {
    if (!isInitialized || controller == null || isCapturing) return;

    setState(() {
      isCapturing = true;
    });

    try {
      final XFile photo = await controller!.takePicture();

      // Save to app directory
      final Directory appDir = await getApplicationDocumentsDirectory();
      final String fileName = 'capture_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final String filePath = '${appDir.path}/$fileName';

      await File(photo.path).copy(filePath);

      // Return the file path
      Navigator.pop(context, filePath);

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error taking picture: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        isCapturing = false;
      });
    }
  }

  Future<void> _switchCamera() async {
    if (cameras.length <= 1) return;

    setState(() {
      isInitialized = false;
    });

    await controller?.dispose();

    // Find the next camera
    final currentLensDirection = controller!.description.lensDirection;
    CameraDescription newCamera = cameras.firstWhere(
          (camera) => camera.lensDirection != currentLensDirection,
      orElse: () => cameras.first,
    );

    controller = CameraController(
      newCamera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    try {
      await controller!.initialize();
      if (mounted) {
        setState(() {
          isInitialized = true;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Error switching camera: ${e.toString()}';
      });
    }
  }
}

class FaceGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final center = Offset(size.width / 2, size.height / 2);

    // Draw face guide lines
    canvas.drawOval(
      Rect.fromCenter(
        center: center,
        width: size.width * 0.6,
        height: size.height * 0.5,
      ),
      paint,
    );

    // Draw eye guides
    final eyeY = center.dy - size.height * 0.1;
    canvas.drawCircle(Offset(center.dx - 30, eyeY), 8, paint);
    canvas.drawCircle(Offset(center.dx + 30, eyeY), 8, paint);

    // Draw mouth guide
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + size.height * 0.1),
        width: 40,
        height: 20,
      ),
      0,
      3.14,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}