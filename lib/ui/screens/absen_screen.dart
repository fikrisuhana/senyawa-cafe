import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/db_helper.dart';
import '../../services/google_sheet_service.dart';

class AbsenScreen extends StatefulWidget {
  const AbsenScreen({super.key});

  @override
  State<AbsenScreen> createState() => _AbsenScreenState();
}

class _AbsenScreenState extends State<AbsenScreen> {
  List<Map<String, dynamic>> _employees = [];
  Set<String> _presentToday = {}; // nama karyawan yg hadir hari ini
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAbsenData();
  }

  Future<void> _loadAbsenData() async {
    setState(() => _isLoading = true);
    final db = DbHelper();

    // Default employees if empty
    var emps = await db.getEmployees();
    if (emps.isEmpty) {
      await db.insertEmployee('Andi');
      await db.insertEmployee('Budi');
      await db.insertEmployee('Citra');
      emps = await db.getEmployees();
    }

    final now = DateTime.now();
    final bDate = now.hour < 6 ? now.subtract(const Duration(days: 1)) : now;
    final bDateKey = DateFormat('yyyy-MM-dd').format(bDate);

    final atts = await db.getTodayAttendances(bDateKey);
    // Hadir = ada baris absen (apa pun shift-nya: Pagi/Sore/Hadir/Y lama).
    final present = <String>{};
    for (final row in atts) {
      final name = (row['employee_name'] ?? '').toString();
      if (name.isNotEmpty) present.add(name);
    }

    if (mounted) {
      setState(() {
        _employees = emps;
        _presentToday = present;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleHadir(String empName) async {
    final now = DateTime.now();
    final bDate = now.hour < 6 ? now.subtract(const Duration(days: 1)) : now;
    final bDateKey = DateFormat('yyyy-MM-dd').format(bDate);

    final bool wasPresent = _presentToday.contains(empName);
    if (!wasPresent) {
      // Tandai HADIR → catat (dedup anti dobel) + sync ke Sheet.
      await DbHelper().recordAttendance(empName, bDateKey, 'Hadir');
      await DbHelper().updateEmployeeShift(empName, 'Hadir');

      final prefs = await SharedPreferences.getInstance();
      final sheetId = prefs.getString('spreadsheet_id') ?? '';
      if (sheetId.isNotEmpty) {
        try {
          await GoogleSheetService().appendAttendance(sheetId, bDateKey, empName, true);
        } catch (e) {
          debugPrint('Append absensi ke Sheet gagal: $e');
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✓ $empName ditandai hadir & disinkron ke Sheet')),
        );
      }
    } else {
      // Batal hadir → hapus record (di app & abaikan di Sheet, append-only).
      await DbHelper().removeAttendance(empName, bDateKey, 'Hadir');
      await DbHelper().updateEmployeeShift(empName, '');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kehadiran $empName dibatalkan')),
        );
      }
    }

    setState(() {
      if (wasPresent) {
        _presentToday.remove(empName);
      } else {
        _presentToday.add(empName);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final todayStr = DateFormat('EEEE, d MMM yyyy', 'id_ID').format(DateTime.now());

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF1A73E8)));
    }

    final hadirCount = _employees.where((e) => _presentToday.contains(e['name'] as String)).length;

    return RefreshIndicator(
      onRefresh: _loadAbsenData,
      color: const Color(0xFF1A73E8),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Absensi Karyawan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                      const SizedBox(height: 4),
                      Text(
                        'Hari usaha: $todayStr',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF1A73E8)),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB7F1DC),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      Text('$hadirCount', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Color(0xFF00201A))),
                      const Text('hadir', style: TextStyle(fontSize: 11, color: Color(0xFF356A58))),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Ketuk kartu untuk tandai hadir. Daftar karyawan bisa diatur dari Admin atau Spreadsheet (tab Karyawan).',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 16),

            // Daftar karyawan — kartu tap-to-toggle hadir.
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _employees.length,
              itemBuilder: (context, index) {
                final emp = _employees[index];
                final empName = emp['name'] as String;
                final isActive = (emp['active'] == 1);
                final bool isPresent = _presentToday.contains(empName);

                return Card(
                  elevation: 1,
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: isPresent ? const Color(0xFF356A58) : Colors.transparent,
                      width: isPresent ? 1.5 : 0,
                    ),
                  ),
                  color: isPresent ? const Color(0xFFEAF7F1) : Colors.white,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: isActive ? () => _toggleHadir(empName) : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: isPresent ? const Color(0xFF356A58) : const Color(0xFFF5F3F0),
                            child: Icon(
                              isPresent ? Icons.check : Icons.person_outline,
                              color: isPresent ? Colors.white : const Color(0xFF7A5540),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(empName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                Text(
                                  isActive ? (isPresent ? 'Hadir hari ini' : 'Belum absen') : 'Nonaktif',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isPresent ? const Color(0xFF356A58) : Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Toggle switch besar biar gampang di-tap.
                          Switch(
                            value: isPresent,
                            activeThumbColor: const Color(0xFF356A58),
                            onChanged: isActive ? (v) => _toggleHadir(empName) : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
