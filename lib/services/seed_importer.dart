import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'db_helper.dart';

class SeedImporter {
  /// Ambil bagian tanggal "YYYY-MM-DD" dari nilai apa pun (ISO/timestamp/null).
  static String? _dateOnly(dynamic v) {
    if (v == null) return null;
    final s = v.toString();
    if (s.isEmpty) return null;
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  static Future<bool> importSeederIfNeeded() async {
    final db = await DbHelper().database;

    // Cek apakah seeder sudah pernah di-import
    final check = await db.query('settings', where: 'key = ?', whereArgs: ['seeder_imported']);
    if (check.isNotEmpty && check.first['value'] == 'true') {
      debugPrint('⚡ Seeder database sudah pernah di-import.');
      return false;
    }

    try {
      debugPrint('📦 Membaca assets/seed/seed.raw.json...');
      final jsonString = await rootBundle.loadString('assets/seed/seed.raw.json');
      final Map<String, dynamic> data = jsonDecode(jsonString);

      await db.transaction((txn) async {
        // 1. Import Packaging (Bahan)
        if (data['bahan'] != null) {
          for (var item in data['bahan']) {
            await txn.insert('packaging', {
              'name': item['name'],
              'unit': item['unit'] ?? 'pcs',
              'stock': item['stock'] ?? 0,
              'min_stock': item['min_stock'] ?? item['minStock'] ?? 0,
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }

        // 2. Import MenuItem (Menu)
        if (data['menu'] != null) {
          for (var item in data['menu']) {
            await txn.insert('menu_items', {
              'name': item['name'],
              'category': item['category'] ?? 'KOPI',
              'price': item['price'] ?? 0,
              'cost': item['cost'] ?? 0,
              'active': (item['active'] == true) ? 1 : 0,
              'sortOrder': item['urutan'] ?? item['sortOrder'] ?? 0,
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }

        // 3. Import VariantGroup
        if (data['varianGrup'] != null) {
          for (var item in data['varianGrup']) {
            await txn.insert('variant_groups', {
              'menu_name': item['menu'],
              'group_name': item['grup'] ?? item['name'],
              'type': item['tipe'] ?? item['type'] ?? 'SINGLE',
              'required': (item['wajib'] == true || item['required'] == true) ? 1 : 0,
              'sort_order': item['urutan'] ?? 0,
            });
          }
        }

        // 4. Import VariantOption
        if (data['varianOpsi'] != null) {
          for (var item in data['varianOpsi']) {
            await txn.insert('variant_options', {
              'menu_name': item['menu'],
              'group_name': item['grup'],
              'option_name': item['opsi'] ?? item['name'],
              'price_delta': item['tambahan'] ?? item['priceDelta'] ?? 0,
              'sort_order': item['urutan'] ?? 0,
            });
          }
        }

        // 4b. Import MenuStock (resep bahan base)
        final menuBahan = data['menuBahan'] ?? data['menu_bahan'];
        if (menuBahan != null) {
          for (var item in menuBahan) {
            await txn.insert('menu_stocks', {
              'menu_name': item['menu'],
              'packaging_name': item['bahan'],
              'qty': item['qty'] ?? 1,
            });
          }
        }

        // 4c. Import VariantOptionStock (bahan khusus per opsi, mis. Dingin->cup plastik)
        final varianBahan = data['varianBahan'] ?? data['varian_bahan'];
        if (varianBahan != null) {
          for (var item in varianBahan) {
            await txn.insert('variant_option_stocks', {
              'menu_name': item['menu'],
              'group_name': item['grup'],
              'option_name': item['opsi'],
              'packaging_name': item['bahan'],
              'qty': item['qty'] ?? 1,
            });
          }
        }

        // 5. Import Voucher (+ kuota + periode)
        if (data['voucher'] != null) {
          for (var item in data['voucher']) {
            await txn.insert('vouchers', {
              'name': item['name'],
              'type': item['type'] ?? 'PERCENT',
              'value': item['value'] ?? 0,
              'active': (item['active'] == true) ? 1 : 0,
              'kuota': item['kuota'],
              'used_count': 0,
              'valid_from': _dateOnly(item['berlaku_dari'] ?? item['valid_from']),
              'valid_until': _dateOnly(item['berlaku_sampai'] ?? item['valid_until']),
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }

        // 6. Import Employees (Karyawan)
        if (data['karyawan'] != null) {
          for (var item in data['karyawan']) {
            await txn.insert('employees', {
              'name': item['name'],
              'active': (item['active'] == true) ? 1 : 0,
              'shift_status': '',
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }

        // 7. Import Pengaturan (Store Settings)
        if (data['pengaturan'] != null) {
          final Map<String, dynamic> p = Map<String, dynamic>.from(data['pengaturan']);
          for (final entry in p.entries) {
            await txn.insert('settings', {
              'key': entry.key,
              'value': entry.value.toString(),
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }

        // Tandai seeder sudah di-import
        await txn.insert('settings', {
          'key': 'seeder_imported',
          'value': 'true',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      });

      debugPrint('✅ Database SQLite lokal berhasil di-seed 100% dari seed.raw.json!');
      return true;
    } catch (e, stack) {
      debugPrint('❌ Error seeding database: $e\n$stack');
      return false;
    }
  }
}
