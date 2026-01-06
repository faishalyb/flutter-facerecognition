// ignore_for_file: unused_element

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:presensi/screens/live_registration_camera_screen.dart';

import '../models/user_model.dart';
import '../main.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  _RegistrationScreenState createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final TextEditingController _nameController = TextEditingController();

  String? capturedImage;
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
            Card(
              color: Colors.blue[50],
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(Icons.face, size: 32, color: Colors.blue),
                    SizedBox(height: 8),
                    Text(
                      'Registrasi 1 Foto',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '✓ Ambil 1 foto wajah depan\n'
                      '✓ Pastikan pencahayaan baik\n'
                      '✓ Tidak blur & hanya 1 wajah\n'
                      '✓ Hadap lurus ke kamera',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Nama Lengkap',
                prefixIcon: const Icon(Icons.person),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                filled: true,
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 24),
            if (capturedImage != null) ...[
              const Text(
                'Foto Anda:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    File(capturedImage!),
                    height: 200,
                    width: 200,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
            if (capturedImage == null)
              ElevatedButton.icon(
                onPressed: isProcessing ? null : _capturePhoto,
                icon: const Icon(Icons.camera_alt),
                label: const Text(
                  'AMBIL FOTO',
                  style: TextStyle(fontSize: 15),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[600],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
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
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save),
                    label: Text(
                      isProcessing ? 'Menyimpan...' : 'SIMPAN REGISTRASI',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[600],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: isProcessing ? null : _resetCapture,
                    child: const Text('Ambil Ulang Foto'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _capturePhoto() async {
    final name = _nameController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Masukkan nama terlebih dahulu')),
      );
      return;
    }

    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => const SimpleLiveCameraScreen(
          title: 'Ambil Foto Wajah',
          instruction: 'Hadap lurus ke depan - Natural',
        ),
      ),
    );

    if (result != null && result.isNotEmpty) {
      setState(() {
        capturedImage = result;
      });
    }
  }

  void _resetCapture() {
    setState(() {
      capturedImage = null;
    });
  }

  Future<void> _saveRegistration() async {
    final name = _nameController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nama tidak boleh kosong')),
      );
      return;
    }

    if (capturedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ambil foto dulu')),
      );
      return;
    }

    setState(() => isProcessing = true);

    try {
      final userBox = Hive.box<UserModel>('users');

      // Check duplicate name
      final exists =
          userBox.values.any((u) => u.name.toLowerCase() == name.toLowerCase());
      if (exists) {
        throw Exception('Nama sudah terdaftar. Gunakan nama lain.');
      }

      // Extract embedding
      final emb = await faceRecognitionService.extractFaceEmbedding(
        capturedImage!,
        rejectMultiFace: true,
      );

      if (emb == null) {
        throw Exception(
          'Gagal extract embedding!\n\n'
          'Kemungkinan:\n'
          '• Wajah tidak terdeteksi\n'
          '• Terdeteksi >1 wajah\n'
          '• Foto terlalu blur/gelap\n'
          '• Wajah terlalu kecil',
        );
      }

      // Save dengan 1 embedding saja
      final newUser = UserModel(
        name: name,
        faceEmbeddings: [emb], // Hanya 1 embedding
        registrationDate: DateTime.now(),
      );

      await userBox.add(newUser);

      if (!mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Registrasi berhasil!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }
}
