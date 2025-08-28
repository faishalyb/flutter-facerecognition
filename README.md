# Flutter Absensi Face Recognition MVP

Aplikasi absensi sederhana menggunakan Flutter dengan fitur face recognition berbasis Google ML Kit dan MobileFaceNet.

## Fitur

- ✅ **Registrasi Pengguna**: Ambil 3 foto wajah (depan, kiri, kanan)
- ✅ **Absensi Harian**: Face recognition untuk absensi
- ✅ **Penyimpanan Lokal**: Menggunakan Hive database
- ✅ **Real-time Preview**: Kamera dengan panduan wajah
- ✅ **Validasi Wajah**: Error handling jika wajah tidak ditemukan

## Struktur Project

```
lib/
├── main.dart                    # Entry point aplikasi
├── models/
│   └── user_model.dart         # Model data pengguna untuk Hive
├── screens/
│   ├── home_screen.dart        # Halaman utama
│   ├── registration_screen.dart # Halaman registrasi
│   ├── attendance_screen.dart   # Halaman absensi
│   └── camera_screen.dart      # Halaman kamera
└── services/
    └── face_recognition_service.dart # Service face recognition
```

## Setup Instructions

### 1. Dependencies

Tambahkan dependencies ke `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  google_mlkit_face_detection: ^0.10.0
  tflite_flutter: ^0.10.1
  camera: ^0.10.5+9
  image: ^4.0.17
  hive: ^2.2.3
  hive_flutter: ^1.1.0
  path_provider: ^2.1.1

dev_dependencies:
  hive_generator: ^2.0.1
  build_runner: ^2.4.7
```

### 2. Model TensorFlow Lite

1. **Rename model file**: Ganti nama `output_model.tflite` sesuai kebutuhan
2. **Copy ke assets**: Letakkan file di `assets/models/output_model.tflite`
3. **Update pubspec.yaml**:
   ```yaml
   flutter:
     assets:
       - assets/models/
   ```

### 3. Generate Hive Adapter

Jalankan command berikut untuk generate Hive adapter:

```bash
flutter packages pub run build_runner build
```

### 4. Android Permissions

Update file `android/app/src/main/AndroidManifest.xml` dengan permissions yang diperlukan:

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />

<uses-feature android:name="android.hardware.camera" android:required="false" />
<uses-feature android:name="android.hardware.camera.front" android:required="false" />
```

### 5. iOS Setup (Optional)

Tambahkan ke `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>This app needs access to camera for face recognition</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>This app needs access to photo library to save captured images</string>
```

## Cara Penggunaan

### 1. Registrasi Pengguna Baru

1. Buka aplikasi dan tap **"REGISTRASI"**
2. Masukkan nama lengkap pengguna
3. Ambil 3 foto wajah sesuai instruksi:
    - **Foto Depan**: Wajah menghadap langsung ke kamera
    - **Foto Kiri**: Kepala menghadap ke kiri (profile kiri)
    - **Foto Kanan**: Kepala menghadap ke kanan (profile kanan)
4. Pastikan wajah berada dalam frame guide dan pencahayaan cukup
5. Tap **"SIMPAN REGISTRASI"** untuk menyimpan data

### 2. Absensi Harian

1. Dari halaman utama, tap **"ABSENSI HARIAN"**
2. Tap **"AMBIL FOTO"** untuk mengambil foto wajah
3. Posisikan wajah dalam frame guide
4. Tap tombol capture (lingkaran biru besar)
5. Tap **"PROSES ABSENSI"** untuk menjalankan face recognition
6. Sistem akan menampilkan hasil:
    - ✅ **Berhasil**: Jika wajah dikenali dan absensi tercatat
    - ❌ **Gagal**: Jika wajah tidak ditemukan dalam database

### 3. Melihat Daftar Pengguna

- Halaman utama menampilkan semua pengguna yang terdaftar
- Status absensi hari ini ditampilkan untuk setiap pengguna
- Informasi tanggal registrasi dan total absensi

## Konfigurasi Face Recognition

### Threshold Similarity

Edit nilai threshold di `face_recognition_service.dart`:

```dart
bool isSamePerson(List<double> embedding1, List<double> embedding2, {double threshold = 0.7}) {
  // Nilai default: 0.7
  // Lebih rendah = lebih permissive (mudah match)
  // Lebih tinggi = lebih strict (sulit match)
}
```

### Model Input Size

Model MobileFaceNet menggunakan input size **112x112x3**:

```dart
final resizedImage = img.copyResize(croppedImage, width: 112, height: 112);
```

### Face Detection Settings

Konfigurasi Google ML Kit Face Detection:

```dart
FaceDetector(
  options: FaceDetectorOptions(
    enableContours: false,
    enableClassification: false,
    enableLandmarks: false,
    enableTracking: false,
    minFaceSize: 0.1,  // Minimum 10% dari image size
    performanceMode: FaceDetectorMode.accurate,
  ),
);
```

## Troubleshooting

### 1. Model tidak bisa load

**Error**: `Failed to load face recognition model`

**Solusi**:
- Pastikan file `output_model.tflite` ada di `assets/models/`
- Cek `pubspec.yaml` sudah include assets
- Jalankan `flutter clean` dan `flutter pub get`

### 2. Kamera tidak berfungsi

**Error**: `Camera not available`

**Solusi**:
- Pastikan permissions sudah ditambahkan di AndroidManifest.xml
- Test di device fisik (bukan emulator)
- Restart aplikasi setelah memberikan permission

### 3. Hive adapter error

**Error**: `No adapter registered for...`

**Solusi**:
```bash
flutter packages pub run build_runner build --delete-conflicting-outputs
```

### 4. Face recognition tidak akurat

**Solusi**:
- Pastikan pencahayaan cukup saat ambil foto
- Wajah harus jelas terlihat dalam frame
- Turunkan threshold similarity jika terlalu strict
- Gunakan foto registrasi yang berkualitas baik

### 5. Build error Android

**Error**: Build gagal di Android

**Solusi**:
- Update Android SDK dan build tools
- Set `minSdkVersion` minimal 21 di `android/app/build.gradle`:
```gradle
minSdkVersion 21
```

## File Structure Detail

### Models
- `UserModel`: Data class untuk menyimpan informasi pengguna
- `faceEmbeddings`: List embeddings dari 3 foto registrasi
- `attendanceDates`: Riwayat tanggal absensi

### Services
- `FaceRecognitionService`: Handle semua operasi ML
- `extractFaceEmbedding()`: Extract embedding dari foto
- `calculateSimilarity()`: Hitung cosine similarity
- `isSamePerson()`: Validasi apakah dua wajah sama

### Screens
- `HomeScreen`: Dashboard utama dengan tombol dan list pengguna
- `RegistrationScreen`: Form registrasi dengan 3 step foto
- `AttendanceScreen`: Proses absensi dengan hasil
- `CameraScreen`: Custom camera dengan face guide

## Performance Tips

1. **Optimize Image Size**: Foto di-resize ke 112x112 sebelum processing
2. **Face Cropping**: Hanya bagian wajah yang diproses, bukan full image
3. **Memory Management**: Dispose camera controller dengan benar
4. **Async Processing**: Semua ML operations dilakukan secara asynchronous

## Security Notes

- Data disimpan lokal menggunakan Hive (encrypted by default)
- Tidak ada data yang dikirim ke server external
- Face embeddings adalah representasi mathematical, bukan foto asli
- Foto hasil capture disimpan di app directory (private)

## Customization

### Mengubah Jumlah Foto Registrasi

Edit `registration_screen.dart`:

```dart
List<String> imageLabels = ['Foto Depan', 'Foto Kiri', 'Foto Kanan']; 
// Tambah/kurangi sesuai kebutuhan
```

### Mengubah UI Theme

Edit `main.dart`:

```dart
theme: ThemeData(
  primarySwatch: Colors.blue, // Ganti warna primary
  // Tambah kustomisasi lainnya
),
```

### Menambah Validasi

Tambah validasi di `attendance_screen.dart`:

```dart
// Contoh: Cek jam kerja
final now = DateTime.now();
if (now.hour < 8 || now.hour > 17) {
  // Show error: diluar jam kerja
}
```

## License

MIT License - bebas untuk dimodifikasi dan digunakan untuk project komersial.

---

**Developed with Flutter 💙**