import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:presensi/screens/anti_spoof_attendance_screen.dart';
import '../models/user_model.dart';
import 'registration_screen.dart';

class HomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Absensi App'),
        centerTitle: true,
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.face,
                    size: 50,
                    color: Colors.blue[600],
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Sistem Absensi',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[800],
                    ),
                  ),
                  Text(
                    'Face Recognition',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.blue[600],
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 32),

            // Tombol Registrasi
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => RegistrationScreen()),
                );
              },
              icon: Icon(Icons.person_add),
              label: Text(
                'REGISTRASI',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[600],
                padding: EdgeInsets.symmetric(vertical: 16),
              ),
            ),

            SizedBox(height: 16),

            // Tombol Absensi Harian
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) =>
                          const FastAntiSpoofAttendanceScreen()),
                );
              },
              icon: Icon(Icons.camera_alt),
              label: Text(
                'ABSENSI HARIAN',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[600],
                padding: EdgeInsets.symmetric(vertical: 16),
              ),
            ),

            SizedBox(height: 32),

            // Divider
            Row(
              children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'PENGGUNA TERDAFTAR',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
                Expanded(child: Divider()),
              ],
            ),

            SizedBox(height: 16),

            // Daftar Pengguna Terdaftar
            Expanded(
              child: ValueListenableBuilder<Box<UserModel>>(
                valueListenable: Hive.box<UserModel>('users').listenable(),
                builder: (context, box, _) {
                  if (box.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.people_outline,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Belum ada pengguna terdaftar',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Gunakan tombol registrasi untuk menambah pengguna',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  final users = box.values.toList();

                  return ListView.builder(
                    itemCount: users.length,
                    itemBuilder: (context, index) {
                      final user = users[index];
                      final hasAttendanceToday = user.hasAttendanceToday();

                      return Card(
                        margin: EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: hasAttendanceToday
                                ? Colors.green[100]
                                : Colors.grey[200],
                            child: Icon(
                              Icons.person,
                              color: hasAttendanceToday
                                  ? Colors.green[700]
                                  : Colors.grey[600],
                            ),
                          ),
                          title: Text(
                            user.name,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Terdaftar: ${_formatDate(user.registrationDate)}',
                                style: TextStyle(fontSize: 12),
                              ),
                              Text(
                                'Total Absensi: ${user.attendanceDates.length} hari',
                                style: TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                          trailing: Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: hasAttendanceToday
                                  ? Colors.green[100]
                                  : Colors.grey[200],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              hasAttendanceToday ? 'Hadir' : 'Belum Absen',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: hasAttendanceToday
                                    ? Colors.green[700]
                                    : Colors.grey[600],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}
