import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:hive/hive.dart';
import '../models/user_model.dart';
import '../main.dart';
import 'camera_screen.dart';

class RegistrationScreen extends StatefulWidget {
  @override
  _RegistrationScreenState createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final TextEditingController _nameController = TextEditingController();
  List<String> capturedImages = [];
  List<String> imageLabels = ['Foto Depan', 'Foto Kiri', 'Foto Kanan'];
  bool isProcessing = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Registrasi Pengguna'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Info Card
            Card(
              color: Colors.blue[50],
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[600], size: 32),
                    SizedBox(height: 8),
                    Text(
                      'Petunjuk Registrasi',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[800],
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '1. Masukkan nama lengkap\n2. Ambil 3 foto: depan, kiri, kanan\n3. Pastikan wajah terlihat jelas\n4. Simpan untuk menyelesaikan registrasi',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.blue[700]),
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 24),

            // Input Nama
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Nama Lengkap',
                prefixIcon: Icon(Icons.person),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              textCapitalization: TextCapitalization.words,
            ),

            SizedBox(height: 24),

            // Photo Capture Section
            Text(
              'Ambil Foto Wajah (${capturedImages.length}/3)',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),

            SizedBox(height: 16),

            // Photo Progress
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(3, (index) {
                final isCompleted = index < capturedImages.length;
                return Column(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: isCompleted ? Colors.green[100] : Colors.grey[200],
                      child: Icon(
                        isCompleted ? Icons.check : Icons.camera_alt,
                        color: isCompleted ? Colors.green[700] : Colors.grey[500],
                        size: 30,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      imageLabels[index],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isCompleted ? Colors.green[700] : Colors.grey[600],
                      ),
                    ),
                  ],
                );
              }),
            ),

            SizedBox(height: 24),

            // Captured Images Preview
            if (capturedImages.isNotEmpty) ...[
              Text(
                'Foto yang Sudah Diambil:',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 12),
              Container(
                height: 100,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: capturedImages.length,
                  itemBuilder: (context, index) {
                    return Container(
                      margin: EdgeInsets.only(right: 12),
                      width: 80,
                      child: Column(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.asset(
                                capturedImages[index],
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    color: Colors.grey[300],
                                    child: Icon(Icons.image, color: Colors.grey[600]),
                                  );
                                },
                              ),
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            imageLabels[index],
                            style: TextStyle(fontSize: 10),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              SizedBox(height: 24),
            ],

            // Action Buttons
            if (capturedImages.length < 3)
              ElevatedButton.icon(
                onPressed: _takePhoto,
                icon: Icon(Icons.camera_alt),
                label: Text(
                  'Ambil ${imageLabels[capturedImages.length]}',
                  style: TextStyle(fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[600],
                  padding: EdgeInsets.symmetric(vertical: 16),
                ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton.icon(
                    onPressed: isProcessing ? null : _saveRegistration,
                    icon: isProcessing
                        ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : Icon(Icons.save),
                    label: Text(
                      isProcessing ? 'Menyimpan...' : 'SIMPAN REGISTRASI',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[600],
                      padding: EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                  SizedBox(height: 12),
                  TextButton(
                    onPressed: isProcessing ? null : _resetCapture,
                    child: Text('Ambil Ulang Semua Foto'),
                  ),
                ],
              ),
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
          title: 'Ambil ${imageLabels[capturedImages.length]}',
        ),
      ),
    );

    if (result != null) {
      setState(() {
        capturedImages.add(result);
      });
    }
  }

  void _resetCapture() {
    setState(() {
      capturedImages.clear();
    });
  }

  Future<void> _saveRegistration() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nama tidak boleh kosong')),
      );
      return;
    }

    if (capturedImages.length != 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Semua foto harus diambil')),
      );
      return;
    }

    setState(() {
      isProcessing = true;
    });

    try {
      // Extract face embeddings dari semua foto
      List<List<double>> embeddings = [];

      for (String imagePath in capturedImages) {
        final embedding = await faceRecognitionService.extractFaceEmbedding(imagePath);
        if (embedding == null) {
          throw Exception('Wajah tidak terdeteksi pada salah satu foto');
        }
        embeddings.add(embedding);
      }

      // Simpan ke Hive
      final userBox = Hive.box<UserModel>('users');
      final newUser = UserModel(
        name: _nameController.text.trim(),
        faceEmbeddings: embeddings,
        registrationDate: DateTime.now(),
      );

      await userBox.add(newUser);

      // Kembali ke home screen
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Registrasi berhasil!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        isProcessing = false;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }
}