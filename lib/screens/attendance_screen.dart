import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:hive/hive.dart';
import '../models/user_model.dart';
import '../main.dart';
import 'camera_screen.dart';

class AttendanceScreen extends StatefulWidget {
  @override
  _AttendanceScreenState createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  bool isProcessing = false;
  String? capturedImagePath;
  UserModel? recognizedUser;
  bool showResult = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Absensi Harian'),
        centerTitle: true,
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Info Card
            Card(
              color: Colors.orange[50],
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(Icons.camera_alt, color: Colors.orange[600], size: 32),
                    SizedBox(height: 8),
                    Text(
                      'Absensi Face Recognition',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange[800],
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Ambil foto wajah untuk melakukan absensi.\nPastikan wajah terlihat jelas dan pencahayaan cukup.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.orange[700]),
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 32),

            // Captured Image Preview
            if (capturedImagePath != null && !showResult) ...[
              Text(
                'Foto yang Diambil:',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 12),
              Container(
                height: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset(
                    capturedImagePath!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Colors.grey[200],
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.image, size: 50, color: Colors.grey[500]),
                            Text('Foto tidak dapat ditampilkan'),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              SizedBox(height: 24),
            ],

            // Result Section
            if (showResult) ...[
              Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: recognizedUser != null ? Colors.green[50] : Colors.red[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: recognizedUser != null ? Colors.green[200]! : Colors.red[200]!,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      recognizedUser != null ? Icons.check_circle : Icons.error,
                      size: 64,
                      color: recognizedUser != null ? Colors.green[600] : Colors.red[600],
                    ),
                    SizedBox(height: 16),
                    Text(
                      recognizedUser != null ? 'ABSENSI BERHASIL!' : 'PENGGUNA TIDAK DITEMUKAN',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: recognizedUser != null ? Colors.green[800] : Colors.red[800],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 12),
                    if (recognizedUser != null) ...[
                      Text(
                        'Selamat datang, ${recognizedUser!.name}!',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.green[700],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Waktu: ${_formatDateTime(DateTime.now())}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.green[600],
                        ),
                      ),
                      if (recognizedUser!.hasAttendanceToday()) ...[
                        SizedBox(height: 8),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.blue[100],
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Anda sudah absen hari ini',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ] else ...[
                      Text(
                        'Wajah tidak dikenali dalam sistem.\nSilakan lakukan registrasi terlebih dahulu.',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.red[700],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(height: 24),
            ],

            Spacer(),

            // Action Buttons
            if (!showResult) ...[
              if (capturedImagePath == null)
                ElevatedButton.icon(
                  onPressed: _takePhoto,
                  icon: Icon(Icons.camera_alt),
                  label: Text(
                    'AMBIL FOTO',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[600],
                    padding: EdgeInsets.symmetric(vertical: 16),
                  ),
                )
              else ...[
                ElevatedButton.icon(
                  onPressed: isProcessing ? null : _processAttendance,
                  icon: isProcessing
                      ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                      : Icon(Icons.face_retouching_natural),
                  label: Text(
                    isProcessing ? 'MEMPROSES...' : 'PROSES ABSENSI',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[600],
                    padding: EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                SizedBox(height: 12),
                TextButton.icon(
                  onPressed: isProcessing ? null : _retakePhoto,
                  icon: Icon(Icons.refresh),
                  label: Text('Ambil Foto Ulang'),
                ),
              ],
            ] else ...[
              ElevatedButton.icon(
                onPressed: _resetAttendance,
                icon: Icon(Icons.refresh),
                label: Text(
                  'ABSENSI LAGI',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[600],
                  padding: EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.home),
                label: Text('Kembali ke Beranda'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _takePhoto() async {
    if (cameras.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kamera tidak tersedia')),
      );
      return;
    }

    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => CameraScreen(
          title: 'Ambil Foto untuk Absensi',
        ),
      ),
    );

    if (result != null) {
      setState(() {
        capturedImagePath = result;
        showResult = false;
        recognizedUser = null;
      });
    }
  }

  void _retakePhoto() {
    setState(() {
      capturedImagePath = null;
      showResult = false;
      recognizedUser = null;
    });
  }

  void _resetAttendance() {
    setState(() {
      capturedImagePath = null;
      showResult = false;
      recognizedUser = null;
      isProcessing = false;
    });
  }

  Future<void> _processAttendance() async {
    if (capturedImagePath == null) return;

    setState(() {
      isProcessing = true;
    });

    try {
      // Extract face embedding dari foto
      final embedding = await faceRecognitionService.extractFaceEmbedding(capturedImagePath!);

      if (embedding == null) {
        throw Exception('Wajah tidak terdeteksi pada foto');
      }

      // Cari pengguna yang cocok
      final userBox = Hive.box<UserModel>('users');
      UserModel? matchedUser;
      double bestSimilarity = 0.0;

      for (final user in userBox.values) {
        for (final userEmbedding in user.faceEmbeddings) {
          final similarity = faceRecognitionService.calculateSimilarity(embedding, userEmbedding);
          if (similarity > bestSimilarity &&
              faceRecognitionService.isSamePerson(embedding, userEmbedding)) {
            bestSimilarity = similarity;
            matchedUser = user;
          }
        }
      }

      setState(() {
        recognizedUser = matchedUser;
        showResult = true;
      });

      // Jika pengguna ditemukan, tambahkan absensi
      if (matchedUser != null) {
        matchedUser.addAttendance();

        // Tampilkan notifikasi sukses
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Absensi berhasil dicatat untuk ${matchedUser.name}'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        // Tampilkan notifikasi error
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Wajah tidak dikenali. Silakan registrasi terlebih dahulu.'),
            backgroundColor: Colors.red,
          ),
        );
      }

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );

      setState(() {
        showResult = true;
        recognizedUser = null;
      });
    } finally {
      setState(() {
        isProcessing = false;
      });
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.year} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}