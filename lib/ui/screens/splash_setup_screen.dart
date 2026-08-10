import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/pos_provider.dart';
import '../../services/google_sheet_service.dart';
import 'pos_screen.dart';

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
  final TextEditingController _sheetIdController = TextEditingController();
  bool _isLoggedIn = false;
  String _userEmail = '';
  bool _isSaving = false;
  bool _isLoadingPrefs = true;

  @override
  void initState() {
    super.initState();
    _loadExistingSetup();
  }

  Future<void> _loadExistingSetup() async {
    final prefs = await SharedPreferences.getInstance();
    final savedSheetId = prefs.getString('spreadsheet_id') ?? '1RuangSenyawaLedger2026';
    final savedEmail = prefs.getString('owner_email') ?? '';
    final isDone = prefs.getBool('setup_completed') ?? false;

    // Jika dipanggil dari tombol Ganti Akun, bersihkan email lama agar user bisa login akun baru
    if (widget.isReconfiguring) {
      setState(() {
        _sheetIdController.text = savedSheetId;
        _isLoggedIn = false;
        _userEmail = '';
        _isLoadingPrefs = false;
      });
      return;
    }

    if (isDone && savedEmail.isNotEmpty && mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const PosScreen()));
      return;
    }

    setState(() {
      _sheetIdController.text = savedSheetId;
      if (savedEmail.isNotEmpty) {
        _isLoggedIn = true;
        _userEmail = savedEmail;
      }
      _isLoadingPrefs = false;
    });
  }

  Future<void> _handleGoogleSignIn() async {
    try {
      final svc = GoogleSheetService();
      await svc.signOut(); // biar bisa pilih akun (tidak auto-cache)
      final account = await svc.signIn();
      if (account != null) {
        setState(() {
          _isLoggedIn = true;
          _userEmail = account.email;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✓ Login Google berhasil: ${account.email}')),
          );
        }
      } else {
        _showManualEmailDialog();
      }
    } catch (e) {
      debugPrint('Google Sign-In Exception: $e');
      _showManualEmailDialog();
    }
  }

  void _showManualEmailDialog() {
    final emailCtrl = TextEditingController(text: _userEmail);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('📧 Auth Akun Google Owner'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ketikkan email akun Google yang ingin Anda gunakan untuk otentikasi Google Sheet:'),
            const SizedBox(height: 12),
            TextField(
              controller: emailCtrl,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email Google Anda',
                hintText: 'contoh: emailanda@gmail.com',
                filled: true,
                fillColor: Color(0xFFF1EFEB),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7A5540), foregroundColor: Colors.white),
            onPressed: () {
              final typed = emailCtrl.text.trim();
              if (typed.isEmpty) return;
              setState(() {
                _isLoggedIn = true;
                _userEmail = typed;
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('✓ Akun Google diset: $_userEmail')),
              );
            },
            child: const Text('Otentikasi & Simpan'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveAndProceed() async {
    // Wajibkan login Google
    if (!_isLoggedIn || _userEmail.isEmpty) {
      await _handleGoogleSignIn();
      if (!_isLoggedIn || _userEmail.isEmpty) return;
    }

    setState(() => _isSaving = true);

    final prefs = await SharedPreferences.getInstance();
    final oldEmail = prefs.getString('owner_email') ?? '';
    await prefs.setString('owner_email', _userEmail);
    await prefs.setBool('setup_completed', true);

    // Kalau ganti akun atau owner isi ID Sheet sendiri, update / reset SharedPreferences
    final typedId = _sheetIdController.text.trim();
    if (typedId.isNotEmpty && !typedId.startsWith('1RuangSenyawa')) {
      await prefs.setString('spreadsheet_id', typedId);
    } else if (widget.isReconfiguring || oldEmail != _userEmail) {
      // Jika email akun Google berubah & tidak memasukkan custom Sheet ID, reset spreadsheet_id agar buat baru untuk akun baru
      await prefs.remove('spreadsheet_id');
    }

    if (!mounted) return;
    final pos = Provider.of<PosProvider>(context, listen: false);
    await pos.initData();

    final svc = GoogleSheetService();
    try {
      final id = await svc.ensureSpreadsheet();
      if (id != null && id.isNotEmpty) {
        await prefs.setString('spreadsheet_id', id);
        await svc.pushCatalog(id); // push katalog & dashboard ke sheet baru
        await pos.loadCatalog();
      }
    } catch (e) {
      debugPrint('Setup Sheet error: $e');
    }

    pos.setGoogleConnected(svc.isConnected);
    await pos.performSync(); // Upload transaksi lokal ke sheet baru

    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const PosScreen()));
  }

  /// Masuk kasir tanpa Google (mode lokal) — untuk test jualan dulu.
  Future<void> _proceedLocalOnly() async {
    setState(() => _isSaving = true);
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
                  'Pilih/Login Akun Google Anda',
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
                                  '1. Login Akun Google Anda',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF7A5540)),
                                ),
                                Text(
                                  _isLoggedIn ? 'Tersambung: $_userEmail' : 'Klik tombol di bawah untuk memilih akun Gmail Anda.',
                                  style: TextStyle(fontSize: 11, color: _isLoggedIn ? const Color(0xFF356A58) : Colors.grey, fontWeight: _isLoggedIn ? FontWeight.bold : FontWeight.normal),
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
                                side: BorderSide(color: _isLoggedIn ? const Color(0xFF356A58) : const Color(0xFF7A5540), width: 1.5),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              onPressed: _handleGoogleSignIn,
                              icon: Icon(
                                _isLoggedIn ? Icons.check_circle : Icons.login,
                                color: _isLoggedIn ? const Color(0xFF356A58) : const Color(0xFF7A5540),
                              ),
                              label: Text(
                                _isLoggedIn ? 'Tersambung ($_userEmail)' : '🔑 Login Akun Google Anda',
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
                              onPressed: () {
                                setState(() {
                                  _isLoggedIn = false;
                                  _userEmail = '';
                                });
                                _handleGoogleSignIn();
                              },
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 20),

                      const Text(
                        '2. Tentukan Google Spreadsheet Laporan',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF7A5540)),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Masukkan ID Google Sheet laporan (atau gunakan ID default):',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      const SizedBox(height: 10),

                      TextField(
                        controller: _sheetIdController,
                        decoration: InputDecoration(
                          hintText: 'Masukkan Google Spreadsheet ID',
                          labelText: 'Spreadsheet ID Laporan',
                          filled: true,
                          fillColor: const Color(0xFFF1EFEB),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

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
                          onPressed: _isSaving ? null : _saveAndProceed,
                          child: _isSaving
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : Text(_isLoggedIn ? 'Mulai Gunakan Kasir ›' : '🔑 Select Google Account & Masuk Kasir ›', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Center(
                        child: TextButton(
                          onPressed: _isSaving ? null : _proceedLocalOnly,
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
