import 'package:flutter/foundation.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

/// Wrapper cetak thermal Bluetooth (plugin print_bluetooth_thermal).
/// Handle: cek permission, list paired devices, connect/disconnect, print bytes/string.
///
/// Printer terpilih disimpan MAC di SharedPreferences (key 'printer_mac').
class PrinterService {
  /// Cek apakah permission Bluetooth (BLUETOOTH_CONNECT Android 12+) sudah granted.
  /// Kalau belum → return false (caller harus minta permission / arahkan user ke setting).
  Future<bool> isPermissionGranted() async {
    try {
      return await PrintBluetoothThermal.isPermissionBluetoothGranted;
    } catch (e) {
      debugPrint('Cek permission BT gagal: $e');
      return false;
    }
  }

  /// Minta permission Bluetooth (Android 12+). Return true kalau granted.
  Future<bool> requestPermission() async {
    try {
      // Plugin otomatis request saat ambil paired devices; helper ini trigger eksplisit.
      final granted = await PrintBluetoothThermal.isPermissionBluetoothGranted;
      if (granted) return true;
      // Trigger dengan akses pairedBluetooths (plugin akan minta permission).
      await PrintBluetoothThermal.pairedBluetooths;
      return await PrintBluetoothThermal.isPermissionBluetoothGranted;
    } catch (e) {
      debugPrint('Request permission BT gagal: $e');
      return false;
    }
  }

  /// Ambil daftar perangkat Bluetooth tersanding (paired) di HP.
  /// Return list {name, macAddress}. Throw kalau BT mati / permission ditolak.
  Future<List<BluetoothInfo>> pairedDevices() async {
    return await PrintBluetoothThermal.pairedBluetooths;
  }

  /// Cek status koneksi printer saat ini.
  Future<bool> get isConnected => PrintBluetoothThermal.connectionStatus;

  /// Connect ke printer via MAC address. Return true kalau sukses.
  Future<bool> connect(String macAddress) async {
    try {
      return await PrintBluetoothThermal.connect(macPrinterAddress: macAddress);
    } catch (e) {
      debugPrint('Connect printer gagal: $e');
      return false;
    }
  }

  /// Disconnect printer.
  Future<void> disconnect() async {
    try {
      await PrintBluetoothThermal.disconnect;
    } catch (e) {
      debugPrint('Disconnect printer gagal: $e');
    }
  }

  /// Print raw bytes (ESC/POS). Pastikan sudah connect sebelum panggil.
  /// Return true kalau sukses kirim.
  Future<bool> printBytes(List<int> bytes) async {
    try {
      final connected = await isConnected;
      if (!connected) return false;
      return await PrintBluetoothThermal.writeBytes(bytes);
    } catch (e) {
      debugPrint('Print bytes gagal: $e');
      return false;
    }
  }

  /// Print teks biasa dgn ukuran (1=50% .. 5=400%). Helper simpel tanpa ESC/POS manual.
  Future<bool> printString(String text, {int size = 1}) async {
    try {
      final connected = await isConnected;
      if (!connected) return false;
      return await PrintBluetoothThermal.writeString(
        printText: PrintTextSize(size: size, text: text),
      );
    } catch (e) {
      debugPrint('Print string gagal: $e');
      return false;
    }
  }
}
