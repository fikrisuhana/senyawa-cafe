import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/pos_provider.dart';
import '../../services/db_helper.dart';
import '../../services/google_sheet_service.dart';

class AbsenScreen extends StatefulWidget {
  const AbsenScreen({super.key});

  @override
  State<AbsenScreen> createState() => _AbsenScreenState();
}

class _AbsenScreenState extends State<AbsenScreen> {
  List<Map<String, dynamic>> _employees = [];
  /// Map nama karyawan → shift yg dipilih hari ini ('' = belum absen).
  Map<String, String> _shiftToday = {};
  bool _isLoading = true;
  late String _bDateKey;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final bDate = now.hour < 6 ? now.subtract(const Duration(days: 1)) : now;
    _bDateKey = DateFormat('yyyy-MM-dd').format(bDate);
    _loadAbsenData();
  }

  Future<void> _loadAbsenData() async {
    setState(() => _isLoading = true);
    final db = DbHelper();

    var emps = await db.getEmployees();
    if (emps.isEmpty) {
      await db.insertEmployee('Andi');
      await db.insertEmployee('Budi');
      await db.insertEmployee('Citra');
      emps = await db.getEmployees();
    }
    final shiftMap = await db.getShiftMapForDate(_bDateKey);

    if (mounted) {
      setState(() {
        _employees = emps;
        _shiftToday = shiftMap;
        _isLoading = false;
      });
    }
  }

  /// Toggle karyawan di shift tertentu.
  /// Kalau karyawan SUDAH di shift ini → batal (set '').
  /// Kalau karyawan di shift LAIN → pindah ke shift ini (aturan 1 org 1 shift).
  Future<void> _toggleShift(String empName, String shift) async {
    final current = _shiftToday[empName] ?? '';
    final newShift = (current == shift) ? '' : shift;

    // Update lokal (atomic: 1 org 1 shift).
    await DbHelper().setEmployeeShiftAttendance(empName, _bDateKey, newShift);
    await DbHelper().updateEmployeeShift(empName, newShift);

    // Sync ke Sheet.
    final prefs = await SharedPreferences.getInstance();
    final sheetId = prefs.getString('spreadsheet_id') ?? '';
    if (sheetId.isNotEmpty) {
      try {
        final svc = GoogleSheetService();
        if (!svc.isConnected) await svc.signIn(interactive: false);
        await svc.appendAttendance(sheetId, _bDateKey, empName, newShift);
        await svc.pushAbsensiMatriks(sheetId);
      } catch (e) {
        debugPrint('Sync absen ke Sheet gagal: $e');
      }
    }

    setState(() {
      if (newShift.isEmpty) {
        _shiftToday.remove(empName);
      } else {
        _shiftToday[empName] = newShift;
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(newShift.isEmpty
            ? 'Absen $empName dibatalkan'
            : '✓ $empName → shift $newShift')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosProvider>();
    final shifts = pos.shifts;
    final todayStr = DateFormat('EEEE, d MMM yyyy', 'id_ID').format(DateTime.now());

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF1A73E8)));
    }

    if (shifts.isEmpty) {
      return const Center(child: Text('Daftar shift kosong. Atur di Spreadsheet (tab Setup).'));
    }

    final hadirCount = _shiftToday.length;
    final emps2 = _employees.where((e) => e['active'] == 1).toList();

    return DefaultTabController(
      length: shifts.length,
      child: Column(
        children: [
          // Header + info hari.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Absensi per Shift', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                      const SizedBox(height: 4),
                      Text(
                        '$todayStr • pilih tab shift, tap karyawan utk absen',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF1A73E8)),
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
          ),
          // TabBar shift (geser antar shift).
          TabBar(
            isScrollable: true,
            labelColor: const Color(0xFF1A73E8),
            unselectedLabelColor: Colors.grey,
            indicatorColor: const Color(0xFF1A73E8),
            tabs: shifts.map((s) => Tab(text: s)).toList(),
          ),
          // List karyawan per shift.
          Expanded(
            child: TabBarView(
              children: shifts.map((shift) => _buildShiftList(shift, emps2)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShiftList(String shift, List<Map<String, dynamic>> emps) {
    final inThisShift = emps.where((e) => (_shiftToday[e['name'] as String] ?? '') == shift).length;
    return RefreshIndicator(
      onRefresh: _loadAbsenData,
      color: const Color(0xFF1A73E8),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Shift $shift — $inThisShift orang',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF7A5540))),
          const SizedBox(height: 10),
          ...emps.map((emp) {
            final empName = emp['name'] as String;
            final currentShift = _shiftToday[empName] ?? '';
            final bool inThis = currentShift == shift;
            final bool inOther = currentShift.isNotEmpty && currentShift != shift;

            return Card(
              elevation: 1,
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: inThis ? const Color(0xFF356A58) : Colors.transparent,
                  width: inThis ? 1.5 : 0,
                ),
              ),
              color: inThis ? const Color(0xFFEAF7F1) : (inOther ? const Color(0xFFF5F3F0) : Colors.white),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _toggleShift(empName, shift),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: inThis ? const Color(0xFF356A58) : const Color(0xFFE0E0E0),
                        child: Icon(
                          inThis ? Icons.check : Icons.person_outline,
                          color: inThis ? Colors.white : const Color(0xFF7A5540),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(empName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            Text(
                              inThis
                                  ? 'Hadir shift $shift'
                                  : (inOther ? 'Sudah di shift $currentShift (tap utk pindah)' : 'Belum absen'),
                              style: TextStyle(
                                fontSize: 11,
                                color: inThis ? const Color(0xFF356A58) : (inOther ? Colors.orange : Colors.grey),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        inThis ? Icons.check_circle : (inOther ? Icons.swap_horiz : Icons.radio_button_unchecked),
                        color: inThis ? const Color(0xFF356A58) : (inOther ? Colors.orange : Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
