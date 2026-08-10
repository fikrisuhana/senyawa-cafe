import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/pos_provider.dart';
import '../../services/google_sheet_service.dart';
import 'pos_screen.dart';

/// Layar setup awal: (1) login pilih akun Google, (2) pilih file Spreadsheet
/// existing dari Drive owner atau buat baru. Setelah itu masuk ke POS.
class SplashSetupScreen extends StatefulWidget {
  final bool isReconfiguring;

  const SplashSetupScreen({
    super.key,
    this.isReconfiguring = false,
  });

  @override
  State<SplashSetupScreen> createState() => _SplashSetupScreenState();
}

class _SplashSetupScreenState extends State<SplashSetupScreen> {
  bool _isLoggedIn = false;
  String _userEmail = '';
  String _displayName = '';
  bool _isBusy = false; // loading global (login / proses)
  bool _isLoadingPrefs = true;
  bool _loadingSheets = false;

  // Daftar spreadsheet existing owner + pilihan yang aktif.
  List<SheetFileInfo> _sheets = [];
  String? _selectedSheetId; // null = belum pilih (akan di-auto-create kalau lanjut)

  @override
  void initState() {
    super.initState();
    _loadExistingSetup();
  }

  Future<void> _loadExistingSetup() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString('owner_email') ?? '';
    final isDone = prefs.getBool('setup_completed') ?? false;
    final savedSheetId = prefs.getString('spreadsheet_id') ?? '';

    // Reconfigure (dari Admin "Ganti Akun"): reset state, mulai dari login.
    if (widget.isReconfiguring) {
      setState(() {
        _isLoggedIn = false;
        _userEmail = '';
        _displayName = '';
        _isLoadingPrefs = false;
      });
      return;
    }

    // Sudah setup sebelumnya + ada email → langsung ke POS.
    if (isDone && savedEmail.isNotEmpty && mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const PosScreen()));
      return;
    }

    setState(() {
      if (savedEmail.isNotEmpty) {
        _isLoggedIn = true;
        _userEmail = savedEmail;
      }
      _selectedSheetId = savedSheetId.isEmpty ? null : savedSheetId;
      _isLoadingPrefs = false;
    });
  }

  /// Login Google interaktif (pilih akun). Setelah berhasil, load daftar Sheet.
  Future<void> _handleGoogleSignIn() async {
    setState(() => _isBusy = true);
    try {
      final svc = GoogleSheetService();
      await svc.signOut(); // biar bisa pilih akun (tidak auto-cache)
      final account = await svc.signIn();
      if (account != null) {
        setState(() {
          _isLoggedIn = true;
          _userEmail = account.email;
          _displayName = account.displayName ?? '';
        });
        await _loadSheets();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✓ Login Google berhasil: ${account.email}')),
          );
        }
      } else {
        // User batal pilih akun — jangan lanjut.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Login Google dibatalkan.')),
          );
        }
      }
    } catch (e) {
      debugPrint('Google Sign-In Exception: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('⚠️ Login gagal: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  /// Ambil daftar Spreadsheet yang dimiliki akun (via Drive API).
  Future<void> _loadSheets() async {
    setState(() => _loadingSheets = true);
    try {
      final sheets = await GoogleSheetService().listSpreadsheets();
      setState(() => _sheets = sheets);
    } catch (e) {
      debugPrint('Load sheets gagal: $e');
    } finally {
      if (mounted) setState(() => _loadingSheets = false);
    }
  }

  /// Buat spreadsheet baru dengan nama dari dialog, pakai, lalu masuk POS.
  Future<void> _createNewSheet() async {
    final nameCtrl = TextEditingController(text: 'Ruang Senyawa — Laporan POS');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('📁 Buat Spreadsheet Baru'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nama file Spreadsheet',
            filled: true,
            fillColor: Color(0xFFF1EFEB),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7A5540), foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
            child: const Text('Buat'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await _proceed(sheetName: name);
  }

  /// Lanjut: pakai Sheet yang dipilih, atau auto-create kalau belum pilih.
  Future<void> _proceed({String? sheetName}) async {
    if (!_isLoggedIn || _userEmail.isEmpty) {
      await _handleGoogleSignIn();
      if (!_isLoggedIn || _userEmail.isEmpty) return;
    }

    setState(() => _isBusy = true);
    final prefs = await SharedPreferences.getInstance();
    final oldEmail = prefs.getString('owner_email') ?? '';
    await prefs.setString('owner_email', _userEmail);
    await prefs.setBool('setup_completed', true);

    final svc = GoogleSheetService();

    try {
      // Pastikan terhubung (sign-in silent cukup; seharusnya sudah ada dari login).
      if (!svc.isConnected) {
        await svc.signIn(interactive: false);
      }

      String? sheetId;
      if (sheetName != null && sheetName.isNotEmpty) {
        // Buat baru.
        final created = await svc.createSpreadsheetByName(sheetName);
        sheetId = created?.id;
      } else if (_selectedSheetId != null && _selectedSheetId!.isNotEmpty) {
        // Pakai yang dipilih / yang sudah tersimpan.
        await svc.useExistingSpreadsheet(_selectedSheetId!, sheetName ?? 'Sheet');
        sheetId = _selectedSheetId;
      } else {
        // Default: auto-create dengan nama baku.
        final created = await svc.createSpreadsheetByName('Ruang Senyawa — Laporan POS');
        sheetId = created?.id;
      }

      if (sheetId != null && sheetId.isNotEmpty) {
        await prefs.setString('spreadsheet_id', sheetId);
        // Reconfigure / ganti akun & tanpa pilih file eksplisit → reset flag lama
        if (widget.isReconfiguring || oldEmail != _userEmail) {
          // spreadsheet_id sudah diset di atas; tidak perlu remove.
        }
      }

      if (!mounted) return;
      final pos = Provider.of<PosProvider>(context, listen: false);
      pos.setGoogleConnected(svc.isConnected);
      await pos.initData();

      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const PosScreen()));
    } catch (e) {
      debugPrint('Setup Sheet error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('⚠️ Gagal menyiapkan Spreadsheet: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  /// Masuk kasir tanpa Google (mode lokal) — untuk test jualan dulu.
  Future<void> _proceedLocalOnly() async {
    setState(() => _isBusy = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('setup_completed', true);
    await prefs.setString('owner_email', prefs.getString('owner_email')?.isNotEmpty == true
        ? prefs.getString('owner_email')!
        : 'lokal');
    if (!mounted) return;
    final pos = Provider.of<PosProvider>(context, listen: false);
    await pos.initData();
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const PosScreen()));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingPrefs) {
      return const Scaffold(
        backgroundColor: Color(0xFF7A5540),
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF7A5540),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo Circular Badge
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 16, offset: Offset(0, 4))],
                    border: Border.all(color: Colors.white, width: 3),
                    image: const DecorationImage(
                      image: AssetImage('assets/seed/logo.jpg'),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                const Text(
                  'Ruang Senyawa POS',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Sambungkan ke Akun Google & Spreadsheet',
                  style: TextStyle(fontSize: 12, color: Color(0xFFFFDCC1), fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 32),

                // Form Container Card
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFFFF),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, 8))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // === STEP 1: Login Google ===
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: _isLoggedIn ? const Color(0xFFB7F1DC) : const Color(0xFFFFDEA1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _isLoggedIn ? Icons.check : Icons.lock,
                              size: 16,
                              color: _isLoggedIn ? const Color(0xFF356A58) : const Color(0xFF7C5800),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '1. Pilih Akun Google',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF7A5540)),
                                ),
                                Text(
                                  _isLoggedIn
                                      ? (_displayName.isNotEmpty
                                            ? '$_displayName ($_userEmail)'
                                            : _userEmail)
                                      : 'Klik tombol di bawah untuk memilih akun Gmail Anda.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _isLoggedIn ? const Color(0xFF356A58) : Colors.grey,
                                    fontWeight: _isLoggedIn ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                side: BorderSide(
                                  color: _isLoggedIn ? const Color(0xFF356A58) : const Color(0xFF7A5540),
                                  width: 1.5,
                                ),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              onPressed: _isBusy ? null : _handleGoogleSignIn,
                              icon: Icon(
                                _isLoggedIn ? Icons.check_circle : Icons.login,
                                color: _isLoggedIn ? const Color(0xFF356A58) : const Color(0xFF7A5540),
                              ),
                              label: Text(
                                _isLoggedIn ? 'Tersambung' : '🔑 Pilih Akun Google',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _isLoggedIn ? const Color(0xFF356A58) : const Color(0xFF7A5540),
                                ),
                              ),
                            ),
                          ),
                          if (_isLoggedIn) ...[
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: 'Ganti Akun Google',
                              icon: const Icon(Icons.swap_horiz, color: Color(0xFF7A5540)),
                              onPressed: _isBusy ? null : _handleGoogleSignIn,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 20),

                      // === STEP 2: Pilih / Buat Spreadsheet ===
                      const Text(
                        '2. Pilih atau Buat Spreadsheet Laporan',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF7A5540)),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Pilih file Spreadsheet yang sudah ada di Drive Anda, atau buat file baru.',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      const SizedBox(height: 10),

                      if (!_isLoggedIn)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            '👉 Login dulu untuk melihat daftar file Anda.',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                          ),
                        )
                      else ...[
                        // Tombol Buat Baru
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF356A58),
                              side: const BorderSide(color: Color(0xFF356A58), width: 1.5),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: _isBusy ? null : _createNewSheet,
                            icon: const Icon(Icons.add_circle_outline),
                            label: const Text('Buat Spreadsheet Baru', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Daftar Sheet existing
                        if (_loadingSheets)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
                          )
                        else if (_sheets.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'Belum ada file Spreadsheet di Drive akun ini. Buat baru di atas, atau ketuk "Sinkron" untuk muat ulang.',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                            ),
                          )
                        else
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 220),
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: _sheets.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (ctx, i) {
                                final s = _sheets[i];
                                return RadioListTile<String>(
                                  value: s.id,
                                  groupValue: _selectedSheetId,
                                  activeColor: const Color(0xFF356A58),
                                  dense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                                  title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  subtitle: Text(
                                    s.modifiedTime != null
                                        ? 'Diubah: ${s.modifiedTime!.year}-${s.modifiedTime!.month.toString().padLeft(2, '0')}-${s.modifiedTime!.day.toString().padLeft(2, '0')}'
                                        : s.id,
                                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onChanged: (v) => setState(() => _selectedSheetId = v),
                                );
                              },
                            ),
                          ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _isBusy ? null : _loadSheets,
                            icon: const Icon(Icons.refresh, size: 14),
                            label: const Text('Muat ulang daftar', style: TextStyle(fontSize: 11)),
                          ),
                        ),
                      ],

                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF7A5540),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 2,
                          ),
                          onPressed: _isBusy ? null : () => _proceed(),
                          child: _isBusy
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : Text(
                                  _isLoggedIn ? 'Mulai Gunakan Kasir ›' : '🔑 Pilih Akun & Lanjut ›',
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Center(
                        child: TextButton(
                          onPressed: _isBusy ? null : _proceedLocalOnly,
                          child: const Text(
                            'Lewati dulu — Mode Lokal (tanpa Google)',
                            style: TextStyle(fontSize: 12, color: Color(0xFF7A5540), fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
