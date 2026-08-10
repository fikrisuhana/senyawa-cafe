import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  double _fontScale = 1.0; // 0.88 (Ringkas), 1.0 (Normal), 1.15 (Besar/Tablet)
  bool _isDarkMode = false;
  bool _isAdminUnlocked = false;
  String _adminPin = '1234'; // PIN awal; diganti admin di Setelan (TIDAK ditampilkan)
  Timer? _autoLockTimer;

  double get fontScale => _fontScale;
  bool get isDarkMode => _isDarkMode;
  bool get isAdminUnlocked => _isAdminUnlocked;
  bool get hasCustomPin => _adminPin != '1234';

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _fontScale = prefs.getDouble('font_scale') ?? 1.0;
    _isDarkMode = prefs.getBool('is_dark_mode') ?? false;
    _adminPin = prefs.getString('admin_pin') ?? '1234';
    notifyListeners();
  }

  /// Ganti PIN admin (mis. dari layar Setelan). Bebas digit/karakter (4, 6, 7, 8+ digit).
  Future<bool> setAdminPin(String newPin) async {
    final cleanPin = newPin.trim();
    if (cleanPin.isEmpty) return false;
    _adminPin = cleanPin;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('admin_pin', cleanPin);
    notifyListeners();
    return true;
  }

  Future<void> setFontScale(double scale) async {
    _fontScale = scale;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('font_scale', scale);
  }

  Future<void> toggleDarkMode(bool isDark) async {
    _isDarkMode = isDark;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_dark_mode', isDark);
  }

  // --- ADMIN PIN LOCK ---

  bool verifyPin(String inputPin) {
    if (inputPin == _adminPin) {
      _isAdminUnlocked = true;
      _resetAutoLockTimer();
      notifyListeners();
      return true;
    }
    return false;
  }

  void lockAdmin() {
    _isAdminUnlocked = false;
    _autoLockTimer?.cancel();
    notifyListeners();
  }

  void _resetAutoLockTimer() {
    _autoLockTimer?.cancel();
    // Auto-lock dalam 3 menit inaktivitas
    _autoLockTimer = Timer(const Duration(minutes: 3), () {
      lockAdmin();
    });
  }

  void userInteracted() {
    if (_isAdminUnlocked) {
      _resetAutoLockTimer();
    }
  }

  @override
  void dispose() {
    _autoLockTimer?.cancel();
    super.dispose();
  }
}
