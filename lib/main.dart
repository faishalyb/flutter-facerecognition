import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:camera/camera.dart';
import 'package:presensi/services/face_recognition_service.dart';
import 'models/user_model.dart';
import 'screens/home_screen.dart';

List<CameraDescription> cameras = [];
late FaceRecognitionService faceRecognitionService;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive
  await Hive.initFlutter();
  Hive.registerAdapter(UserModelAdapter());
  await Hive.openBox<UserModel>('users');

  // Initialize Camera
  cameras = await availableCameras();

  // Initialize Face Recognition Service
  faceRecognitionService = FaceRecognitionService();
  await faceRecognitionService.loadModel();

  final b1 = await rootBundle
      .load('android/app/src/main/assets/models/spoof_model_scale_2_7.tflite');
  final b2 = await rootBundle
      .load('android/app/src/main/assets/models/spoof_model_scale_4_0.tflite');
  print('scale_2_7 bytes: ${b1.lengthInBytes}');
  print('scale_4_0 bytes: ${b2.lengthInBytes}');

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Absensi App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.blue[600],
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue[600],
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
      home: HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
