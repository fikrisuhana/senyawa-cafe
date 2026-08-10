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
  Map<String, List<String>> _attendanceMap = {};
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
    final Map<String, List<String>> attMap = {};
    for (final row in atts) {
      final name = row['employee_name'] as String;
      final shift = row['shift'] as String;
      attMap.putIfAbsent(name, () => []).add(shift);
    }

    if (mounted) {
      setState(() {
        _employees = emps;
        _attendanceMap = attMap;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleShift(String empName, String shiftName) async {
    final now = DateTime.now();
    final bDate = now.hour < 6 ? now.subtract(const Duration(days: 1)) : now;
    final bDateKey = DateFormat('yyyy-MM-dd').format(bDate);

    final currentShifts = List<String>.from(_attendanceMap[empName] ?? []);
    if (!currentShifts.contains(shiftName)) {
      // Toggle ON → catat absen (dedup anti dobel) + sync ke Sheet.
      currentShifts.add(shiftName);
      await DbHelper().recordAttendance(empName, bDateKey, shiftName);
      await DbHelper().updateEmployeeShift(empName, currentShifts.join(', '));

      // Export ke Google Sheet (fire-and-forget; idempoten karena append kasat manual).
      final prefs = await SharedPreferences.getInstance();
      final sheetId = prefs.getString('spreadsheet_id') ?? '';
      if (sheetId.isNotEmpty) {
        try {
          await GoogleSheetService().appendAttendance(sheetId, bDateKey, empName, shiftName);
        } catch (e) {
          debugPrint('Append absensi ke Sheet gagal: $e');
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✓ $empName dicatat masuk shift $shiftName & disinkron ke Sheet')),
        );
      }
    } else {
      // Toggle OFF → hapus record absen (biar konsisten) + update status.
      currentShifts.remove(shiftName);
      await DbHelper().removeAttendance(empName, bDateKey, shiftName);
      await DbHelper().updateEmployeeShift(empName, currentShifts.join(', '));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Absen shift $shiftName $empName dibatalkan')),
        );
      }
    }

    setState(() {
      _attendanceMap[empName] = currentShifts;
    });
  }

  @override
  Widget build(BuildContext context) {
    final todayStr = DateFormat('EEEE, d MMM yyyy', 'id_ID').format(DateTime.now());

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF1A73E8)));
    }

    return RefreshIndicator(
      onRefresh: _loadAbsenData,
      color: const Color(0xFF1A73E8),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Absensi Karyawan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            const SizedBox(height: 4),
            Text(
              'Hari usaha: $todayStr • klik shift = tandai masuk',
              style: const TextStyle(fontSize: 12, color: Color(0xFF1A73E8)),
            ),
            const SizedBox(height: 16),

            // Employee Absen List Card
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _employees.length,
              itemBuilder: (context, index) {
                final emp = _employees[index];
                final empName = emp['name'] as String;
                final activeShifts = _attendanceMap[empName] ?? [];

                return Card(
                  elevation: 1,
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(empName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        Row(
                          children: ['Pagi', 'Sore'].map((shift) {
                            final bool isPresent = activeShifts.contains(shift);
                            return Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isPresent ? const Color(0xFF356A58) : const Color(0xFFFFFFFF),
                                  foregroundColor: isPresent ? Colors.white : const Color(0xFF51443B),
                                  side: BorderSide(
                                    color: isPresent ? const Color(0xFF356A58) : const Color(0xFFD6C7BB),
                                  ),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                onPressed: () => _toggleShift(empName, shift),
                                icon: isPresent
                                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                                    : const Icon(Icons.circle_outlined, size: 14, color: Colors.grey),
                                label: Text(shift, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
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
