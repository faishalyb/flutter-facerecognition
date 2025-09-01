import 'dart:io';

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:hive/hive.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../models/user_model.dart';
import '../main.dart';
import 'camera_screen.dart';



class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  _RegistrationScreenState createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final TextEditingController _nameController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  List<String> capturedImages = [];
  List<String> imageLabels = ['Foto Depan', 'Foto Kiri', 'Foto Kanan'];
  bool isProcessing = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registrasi Pengguna'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Info Card
            Card(
              color: Colors.blue[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[600], size: 32),
                    const SizedBox(height: 8),
                    Text(
                      'Petunjuk Registrasi',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[800],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '1. Masukkan nama lengkap\n2. Ambil 3 foto: depan, kiri, kanan\n3. Pastikan wajah terlihat jelas\n4. Simpan untuk menyelesaikan registrasi',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.blue[700]),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Input Nama
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Nama Lengkap',
                prefixIcon: const Icon(Icons.person),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              textCapitalization: TextCapitalization.words,
            ),

            const SizedBox(height: 24),

            // Photo Capture Section
            Text(
              'Ambil Foto Wajah (${capturedImages.length}/3)',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 16),

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
                    const SizedBox(height: 8),
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
              const Text(
                'Foto yang Sudah Diambil:',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
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
                              child: Image.file(
                                File(capturedImages[index]),
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
                          const SizedBox(height: 4),
                          Text(
                            imageLabels[index],
                            style: const TextStyle(fontSize: 10),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Action Buttons
            if (capturedImages.length < 3)
              ElevatedButton.icon(
                onPressed: _showImageSourceDialog,
                icon: const Icon(Icons.add_a_photo),
                label: Text(
                  'Tambah ${imageLabels[capturedImages.length]}',
                  style: const TextStyle(fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple[600],
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton.icon(
                    onPressed: isProcessing ? null : _saveRegistration,
                    icon: isProcessing
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Icon(Icons.save),
                    label: Text(
                      isProcessing ? 'Menyimpan...' : 'SIMPAN REGISTRASI',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[600],
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: isProcessing ? null : _resetCapture,
                    child: const Text('Ambil Ulang Semua Foto'),
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
        const SnackBar(content: Text('Kamera tidak tersedia')),
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

  Future<void> _pickFromGallery() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 80,
      );

      if (image != null) {
        // Copy image to app directory
        final appDir = await getApplicationDocumentsDirectory();
        final fileName = 'gallery_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final savedImage = await File(image.path).copy('${appDir.path}/$fileName');

        setState(() {
          capturedImages.add(savedImage.path);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${imageLabels[capturedImages.length - 1]} berhasil dipilih dari galeri'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error memilih foto dari galeri: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Container(
                      width: 50,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Pilih Sumber ${imageLabels[capturedImages.length]}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        GestureDetector(
                          onTap: () {
                            Navigator.pop(context);
                            _takePhoto();
                          },
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(color: Colors.blue[200]!),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.camera_alt,
                                  size: 40,
                                  color: Colors.blue[600],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Kamera',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blue[800],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            Navigator.pop(context);
                            _pickFromGallery();
                          },
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.green[50],
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(color: Colors.green[200]!),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.photo_library,
                                  size: 40,
                                  color: Colors.green[600],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Galeri',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.green[800],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _resetCapture() {
    setState(() {
      capturedImages.clear();
    });
  }

  Future<void> _saveRegistration() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nama tidak boleh kosong')),
      );
      return;
    }

    if (capturedImages.length != 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Semua foto harus diambil')),
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
        const SnackBar(
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