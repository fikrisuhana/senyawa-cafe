import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/models.dart';

/// Konstanta tipe kas. Pakai Bahasa Indonesia supaya konsisten dengan
/// header & rumus Dashboard di Google Sheet (MASUK / KELUAR).
class CashType {
  static const String in_ = 'MASUK';
  static const String out = 'KELUAR';
}

class DbHelper {
  static final DbHelper _instance = DbHelper._internal();
  factory DbHelper() => _instance;
  DbHelper._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    String dbPath = await getDatabasesPath();
    String path = join(dbPath, 'ruang_senyawa_pos.db');

    return await openDatabase(
      path,
      version: 4,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // v1 → v2: skema masih kasar → drop & recreate (reseed).
    if (oldVersion < 2) {
      final tables = [
        'packaging', 'menu_items', 'variant_groups', 'variant_options',
        'menu_stocks', 'variant_option_stocks', 'vouchers', 'employees',
        'attendances', 'transactions', 'transaction_items', 'cash_entries',
        'settings',
      ];
      for (final t in tables) {
        await db.execute('DROP TABLE IF EXISTS $t');
      }
      await _onCreate(db, newVersion);
      return;
    }
    // v2 → v3: tambah kolom modal transaksi (non-destruktif).
    if (oldVersion < 3) {
      try {
        await db.execute('ALTER TABLE transactions ADD COLUMN cost_total INTEGER DEFAULT 0');
      } catch (_) {}
    }
    // v3 → v4: konsistensi skema.
    //  - Rename kolom menu_items.sortOrder (camelCase) → sort_order (snake_case).
    //  - Buang duplikat data varian/resep sisa versi lama (sekali jalan saat upgrade).
    if (oldVersion < 4) {
      await _normalizeMenuItemsColumns(db);
      await _dedupeVariantData(db);
    }
  }

  /// v3→v4: rename `sortOrder` → `sort_order` di menu_items.
  /// SQLite < 3.35 ga support RENAME COLUMN, jadi fallback: drop+add+copy.
  Future<void> _normalizeMenuItemsColumns(Database db) async {
    final cols = await db.rawQuery('PRAGMA table_info(menu_items)');
    final hasCamel = cols.any((c) => c['name'] == 'sortOrder');
    final hasSnake = cols.any((c) => c['name'] == 'sort_order');
    if (!hasCamel) return; // sudah snake (DB baru) atau ga ada kolomnya

    if (!hasSnake) {
      await db.execute('ALTER TABLE menu_items ADD COLUMN sort_order INTEGER DEFAULT 0');
    }
    await db.execute('UPDATE menu_items SET sort_order = COALESCE(sortOrder, 0)');
    // Catatan: drop column baru didukung SQLite 3.35+ (Android API 30+).
    // Untuk amannya, bungkus try; kalau gagal, kolom lama tetap ada tapi ga dipakai.
    try {
      await db.execute('ALTER TABLE menu_items DROP COLUMN sortOrder');
    } catch (_) {}
  }

  /// v3→v4: bersihkan duplikat varian/resep sisa insert tanpa UNIQUE versi lama.
  Future<void> _dedupeVariantData(Database db) async {
    await db.execute('DELETE FROM variant_groups WHERE id NOT IN (SELECT MIN(id) FROM variant_groups GROUP BY menu_name, group_name)');
    await db.execute('DELETE FROM variant_options WHERE id NOT IN (SELECT MIN(id) FROM variant_options GROUP BY menu_name, group_name, option_name)');
    await db.execute('DELETE FROM variant_option_stocks WHERE id NOT IN (SELECT MIN(id) FROM variant_option_stocks GROUP BY menu_name, group_name, option_name, packaging_name)');
    await db.execute('DELETE FROM menu_stocks WHERE id NOT IN (SELECT MIN(id) FROM menu_stocks GROUP BY menu_name, packaging_name)');
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE packaging (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE, unit TEXT DEFAULT 'pcs',
        stock INTEGER DEFAULT 0, min_stock INTEGER DEFAULT 0
      )''');

    await db.execute('''
      CREATE TABLE menu_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE, category TEXT,
        price INTEGER DEFAULT 0, cost INTEGER DEFAULT 0,
        active INTEGER DEFAULT 1, sort_order INTEGER DEFAULT 0
      )''');

    await db.execute('''
      CREATE TABLE variant_groups (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        menu_name TEXT, group_name TEXT, type TEXT DEFAULT 'SINGLE',
        required INTEGER DEFAULT 0, sort_order INTEGER DEFAULT 0
      )''');

    await db.execute('''
      CREATE TABLE variant_options (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        menu_name TEXT, group_name TEXT, option_name TEXT,
        price_delta INTEGER DEFAULT 0, sort_order INTEGER DEFAULT 0
      )''');

    // Resep: bahan base per menu
    await db.execute('''
      CREATE TABLE menu_stocks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        menu_name TEXT, packaging_name TEXT, qty INTEGER DEFAULT 1
      )''');

    // Bahan khusus per opsi varian (Dingin -> cup plastik, dst)
    await db.execute('''
      CREATE TABLE variant_option_stocks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        menu_name TEXT, group_name TEXT, option_name TEXT,
        packaging_name TEXT, qty INTEGER DEFAULT 1
      )''');

    // Voucher + kuota + periode + terpakai
    await db.execute('''
      CREATE TABLE vouchers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE, type TEXT DEFAULT 'PERCENT', value INTEGER DEFAULT 0,
        active INTEGER DEFAULT 1, kuota INTEGER, used_count INTEGER DEFAULT 0,
        valid_from TEXT, valid_until TEXT
      )''');

    await db.execute('''
      CREATE TABLE employees (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE, active INTEGER DEFAULT 1, shift_status TEXT DEFAULT ''
      )''');

    // Absensi presence-only historis
    await db.execute('''
      CREATE TABLE attendances (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        employee_name TEXT, business_date TEXT, shift TEXT,
        created_at TEXT, synced INTEGER DEFAULT 0
      )''');

    await db.execute('''
      CREATE TABLE transactions (
        id TEXT PRIMARY KEY, code TEXT UNIQUE, created_at TEXT, business_date TEXT,
        cashier_name TEXT, order_type TEXT, payment_method TEXT,
        subtotal INTEGER, discount_amount INTEGER, voucher_name TEXT,
        total_amount INTEGER, cash_received INTEGER, change_amount INTEGER,
        cost_total INTEGER DEFAULT 0,
        status TEXT DEFAULT 'ACTIVE', void_reason TEXT, synced INTEGER DEFAULT 0
      )''');

    // Detail item per transaksi
    await db.execute('''
      CREATE TABLE transaction_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        trx_id TEXT, name TEXT, variants TEXT, note TEXT,
        qty INTEGER, price INTEGER, subtotal INTEGER
      )''');

    // Kas & pengeluaran
    await db.execute('''
      CREATE TABLE cash_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT, amount INTEGER, category TEXT, note TEXT,
        business_date TEXT, by_name TEXT, created_at TEXT, synced INTEGER DEFAULT 0
      )''');

    await db.execute('''
      CREATE TABLE settings ( key TEXT PRIMARY KEY, value TEXT )''');
  }

  // ---------------- CATALOG ----------------
  Future<List<MenuItemModel>> getMenuItems() async {
    final db = await database;
    final res = await db.query('menu_items', orderBy: 'sort_order ASC, name ASC');
    return res.map((m) => MenuItemModel.fromMap(m)).toList();
  }

  Future<List<PackagingModel>> getPackagings() async {
    final db = await database;
    final res = await db.query('packaging', orderBy: 'name ASC');
    return res.map((m) => PackagingModel.fromMap(m)).toList();
  }

  Future<List<VariantGroupModel>> getVariantGroupsForMenu(String menuName) async {
    final db = await database;
    final res = await db.query('variant_groups', where: 'menu_name = ?', whereArgs: [menuName]);
    return res.map((m) => VariantGroupModel.fromMap(m)).toList();
  }

  Future<List<VariantOptionModel>> getVariantOptions(String menuName, String groupName) async {
    final db = await database;
    final res = await db.query('variant_options', where: 'menu_name = ? AND group_name = ?', whereArgs: [menuName, groupName]);
    return res.map((m) => VariantOptionModel.fromMap(m)).toList();
  }

  Future<void> insertMenuItem(MenuItemModel item) async {
    final db = await database;
    await db.insert('menu_items', item.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateMenuItem(MenuItemModel item) async {
    final db = await database;
    await db.update('menu_items', item.toMap(), where: 'id = ?', whereArgs: [item.id]);
  }

  Future<void> deleteMenuItem(int id) async {
    final db = await database;
    await db.delete('menu_items', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------- STOK & BAHAN ----------------
  Future<void> insertPackaging(String name, String unit, int stock, int minStock) async {
    final db = await database;
    await db.insert('packaging', {
      'name': name,
      'unit': unit,
      'stock': stock,
      'min_stock': minStock,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updatePackagingStock(int id, int addedStock) async {
    final db = await database;
    await db.rawUpdate('UPDATE packaging SET stock = stock + ? WHERE id = ?', [addedStock, id]);
  }

  /// Kurangi stok bahan berdasar nama (dipakai saat jual).
  Future<void> reducePackagingByName(String name, int qty) async {
    final db = await database;
    await db.rawUpdate('UPDATE packaging SET stock = stock - ? WHERE name = ?', [qty, name]);
  }

  /// Tambah stok bahan berdasar nama (dipakai saat void / batalkan transaksi).
  Future<void> addPackagingByName(String name, int qty) async {
    final db = await database;
    await db.rawUpdate('UPDATE packaging SET stock = stock + ? WHERE name = ?', [qty, name]);
  }

  /// Ambil 1 baris packaging by name (null kalau ga ada). Dipakai buat cek stok.
  Future<PackagingModel?> getPackagingByName(String name) async {
    final db = await database;
    final res = await db.query('packaging', where: 'name = ?', whereArgs: [name]);
    if (res.isEmpty) return null;
    return PackagingModel.fromMap(res.first);
  }

  /// Estimasi berapa porsi menu ini masih bisa dibuat berdasar stok bahan base.
  /// Kembali null kalau menu tak punya resep (tidak terbatas / tak terukur).
  /// Dipakai buat tampilan "sisa" di grid kasir.
  Future<int?> estimateMenuPortions(String menuName) async {
    final stocks = await getMenuStocks(menuName);
    if (stocks.isEmpty) return null;
    int? minPortions;
    for (final row in stocks) {
      final pkgName = (row['packaging_name'] ?? '').toString();
      final qty = toInt(row['qty']);
      if (qty <= 0 || pkgName.isEmpty) continue;
      final pkg = await getPackagingByName(pkgName);
      final available = pkg?.stock ?? 0;
      final portions = available ~/ qty;
      if (minPortions == null || portions < minPortions) {
        minPortions = portions;
      }
    }
    return minPortions;
  }

  /// Cek apakah semua bahan (resep base + bahan opsi varian) cukup untuk keranjang.
  /// Kembali null kalau aman, atau pesan alasan stok kurang.
  Future<String?> validateStockForCart(Iterable<CartItem> items) async {
    // Akumulasi kebutuhan per bahan: { namaBahan: totalQty }
    final Map<String, int> need = {};

    for (final item in items) {
      // Resep base menu.
      final baseStocks = await getMenuStocks(item.menu.name);
      for (final row in baseStocks) {
        final pkg = (row['packaging_name'] ?? '').toString();
        final qty = toInt(row['qty']) * item.quantity;
        if (pkg.isNotEmpty) need[pkg] = (need[pkg] ?? 0) + qty;
      }
      // Bahan khusus tiap opsi varian terpilih.
      for (final sv in item.selectedVariants) {
        final optName = sv.replaceAll(RegExp(r'\(.*?\)'), '').trim();
        final optStocks = await getOptionStocks(item.menu.name, optName);
        for (final row in optStocks) {
          final pkg = (row['packaging_name'] ?? '').toString();
          final qty = toInt(row['qty']) * item.quantity;
          if (pkg.isNotEmpty) need[pkg] = (need[pkg] ?? 0) + qty;
        }
      }
    }

    // Bandingkan kebutuhan vs stok tersedia.
    final List<String> kurang = [];
    for (final entry in need.entries) {
      final pkg = await getPackagingByName(entry.key);
      final available = pkg?.stock ?? 0;
      if (available < entry.value) {
        kurang.add('${entry.key} (butuh ${entry.value}, sisa $available)');
      }
    }
    if (kurang.isEmpty) return null;
    return 'Stok bahan kurang: ${kurang.join("; ")}';
  }

  /// Kembalikan stok bahan (base + opsi varian) untuk satu transaksi yang di-void.
  /// Ambil item dari tabel transaction_items. Dipakai oleh voidTransaction.
  Future<void> restoreStockForTransaction(String trxId) async {
    final items = await getTransactionItems(trxId);
    for (final item in items) {
      final baseStocks = await getMenuStocks(item.menu.name);
      for (final row in baseStocks) {
        final pkg = (row['packaging_name'] ?? '').toString();
        final qty = toInt(row['qty']) * item.quantity;
        if (pkg.isNotEmpty) await addPackagingByName(pkg, qty);
      }
      for (final sv in item.selectedVariants) {
        final optName = sv.replaceAll(RegExp(r'\(.*?\)'), '').trim();
        final optStocks = await getOptionStocks(item.menu.name, optName);
        for (final row in optStocks) {
          final pkg = (row['packaging_name'] ?? '').toString();
          final qty = toInt(row['qty']) * item.quantity;
          if (pkg.isNotEmpty) await addPackagingByName(pkg, qty);
        }
      }
    }
  }

  /// Ambil voucher yang dipakai sebuah transaksi (berdasar voucher_name). Null kalau tak pakai.
  Future<VoucherModel?> getVoucherByName(String? name) async {
    if (name == null || name.isEmpty) return null;
    final db = await database;
    final res = await db.query('vouchers', where: 'name = ?', whereArgs: [name]);
    if (res.isEmpty) return null;
    return VoucherModel.fromMap(res.first);
  }

  /// Bahan base sebuah menu (resep).
  Future<List<Map<String, dynamic>>> getMenuStocks(String menuName) async {
    final db = await database;
    return db.query('menu_stocks', where: 'menu_name = ?', whereArgs: [menuName]);
  }

  Future<void> insertMenuStock(String menuName, String packagingName, int qty) async {
    final db = await database;
    await db.insert('menu_stocks', {
      'menu_name': menuName,
      'packaging_name': packagingName,
      'qty': qty,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteMenuStock(int id) async {
    final db = await database;
    await db.delete('menu_stocks', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteMenuStocksByMenu(String menuName) async {
    final db = await database;
    await db.delete('menu_stocks', where: 'menu_name = ?', whereArgs: [menuName]);
  }

  /// Upsert grup varian (tak ada UNIQUE di tabel → cek manual biar tak dobel).
  Future<void> insertVariantGroup(String menuName, String groupName, String type, bool required) async {
    final db = await database;
    final existing = await db.query('variant_groups',
        where: 'menu_name = ? AND group_name = ?', whereArgs: [menuName, groupName]);
    if (existing.isNotEmpty) {
      await db.update('variant_groups', {'type': type, 'required': required ? 1 : 0},
          where: 'menu_name = ? AND group_name = ?', whereArgs: [menuName, groupName]);
    } else {
      await db.insert('variant_groups', {
        'menu_name': menuName,
        'group_name': groupName,
        'type': type,
        'required': required ? 1 : 0,
        'sort_order': 0,
      });
    }
  }

  /// Upsert opsi varian (dedupe manual per menu+grup+opsi).
  Future<void> insertVariantOption(String menuName, String groupName, String optionName, int priceDelta) async {
    final db = await database;
    final existing = await db.query('variant_options',
        where: 'menu_name = ? AND group_name = ? AND option_name = ?',
        whereArgs: [menuName, groupName, optionName]);
    if (existing.isNotEmpty) {
      await db.update('variant_options', {'price_delta': priceDelta},
          where: 'menu_name = ? AND group_name = ? AND option_name = ?',
          whereArgs: [menuName, groupName, optionName]);
    } else {
      await db.insert('variant_options', {
        'menu_name': menuName,
        'group_name': groupName,
        'option_name': optionName,
        'price_delta': priceDelta,
        'sort_order': 0,
      });
    }
  }

  Future<List<Map<String, dynamic>>> getOptionStocks(String menuName, String optionName) async {
    final db = await database;
    return db.query('variant_option_stocks', where: 'menu_name = ? AND option_name = ?', whereArgs: [menuName, optionName]);
  }

  Future<List<Map<String, dynamic>>> getOptionStocksByGroup(String menuName, String groupName, String optionName) async {
    final db = await database;
    return db.query('variant_option_stocks',
        where: 'menu_name = ? AND group_name = ? AND option_name = ?',
        whereArgs: [menuName, groupName, optionName]);
  }

  /// Upsert bahan per opsi (dedupe manual per menu+grup+opsi+bahan).
  Future<void> insertVariantOptionStock(String menuName, String groupName, String optionName, String packagingName, int qty) async {
    final db = await database;
    final existing = await db.query('variant_option_stocks',
        where: 'menu_name = ? AND group_name = ? AND option_name = ? AND packaging_name = ?',
        whereArgs: [menuName, groupName, optionName, packagingName]);
    if (existing.isNotEmpty) {
      await db.update('variant_option_stocks', {'qty': qty},
          where: 'menu_name = ? AND group_name = ? AND option_name = ? AND packaging_name = ?',
          whereArgs: [menuName, groupName, optionName, packagingName]);
    } else {
      await db.insert('variant_option_stocks', {
        'menu_name': menuName,
        'group_name': groupName,
        'option_name': optionName,
        'packaging_name': packagingName,
        'qty': qty,
      });
    }
  }

  /// Hapus 1 baris bahan-opsi berdasar id (buat edit bahan per opsi).
  Future<void> deleteVariantOptionStockById(int id) async {
    final db = await database;
    await db.delete('variant_option_stocks', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteVariantGroup(String menuName, String groupName) async {
    final db = await database;
    await db.delete('variant_groups', where: 'menu_name = ? AND group_name = ?', whereArgs: [menuName, groupName]);
    await db.delete('variant_options', where: 'menu_name = ? AND group_name = ?', whereArgs: [menuName, groupName]);
    await db.delete('variant_option_stocks', where: 'menu_name = ? AND group_name = ?', whereArgs: [menuName, groupName]);
  }

  /// Hapus satu opsi (+bahannya) tanpa membuang grupnya.
  Future<void> deleteVariantOption(String menuName, String groupName, String optionName) async {
    final db = await database;
    await db.delete('variant_options',
        where: 'menu_name = ? AND group_name = ? AND option_name = ?',
        whereArgs: [menuName, groupName, optionName]);
    await db.delete('variant_option_stocks',
        where: 'menu_name = ? AND group_name = ? AND option_name = ?',
        whereArgs: [menuName, groupName, optionName]);
  }

  /// Muat struktur varian lengkap satu menu: [{group, options:[{option, stocks}]}].
  Future<List<Map<String, dynamic>>> getVariantTree(String menuName) async {
    final groups = await getVariantGroupsForMenu(menuName);
    final result = <Map<String, dynamic>>[];
    for (final g in groups) {
      final opts = await getVariantOptions(menuName, g.groupName);
      final optList = <Map<String, dynamic>>[];
      for (final o in opts) {
        final stocks = await getOptionStocksByGroup(menuName, g.groupName, o.optionName);
        optList.add({'option': o, 'stocks': stocks});
      }
      result.add({'group': g, 'options': optList});
    }
    return result;
  }

  // ---- Getter "semua" untuk push ke Google Sheet ----
  Future<List<Map<String, dynamic>>> getAllMenuStocks() async {
    final db = await database;
    return db.query('menu_stocks', orderBy: 'menu_name, packaging_name');
  }

  Future<List<Map<String, dynamic>>> getAllVariantOptionStocks() async {
    final db = await database;
    return db.query('variant_option_stocks', orderBy: 'menu_name, group_name, option_name');
  }

  Future<List<VariantGroupModel>> getAllVariantGroups() async {
    final db = await database;
    final res = await db.query('variant_groups', orderBy: 'menu_name, sort_order');
    return res.map((m) => VariantGroupModel.fromMap(m)).toList();
  }

  Future<List<VariantOptionModel>> getAllVariantOptions() async {
    final db = await database;
    final res = await db.query('variant_options', orderBy: 'menu_name, group_name, sort_order');
    return res.map((m) => VariantOptionModel.fromMap(m)).toList();
  }

  // ---------------- VOUCHER ----------------
  Future<List<VoucherModel>> getVouchers({bool onlyActive = true}) async {
    final db = await database;
    final res = onlyActive
        ? await db.query('vouchers', where: 'active = 1', orderBy: 'name ASC')
        : await db.query('vouchers', orderBy: 'name ASC');
    return res.map((m) => VoucherModel.fromMap(m)).toList();
  }

  Future<void> insertVoucher(VoucherModel v) async {
    final db = await database;
    await db.insert('vouchers', v.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateVoucher(VoucherModel v) async {
    final db = await database;
    await db.update('vouchers', v.toMap(), where: 'id = ?', whereArgs: [v.id]);
  }

  Future<void> deleteVoucher(int id) async {
    final db = await database;
    await db.delete('vouchers', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> incrementVoucherUsage(int id, {int delta = 1}) async {
    final db = await database;
    await db.rawUpdate('UPDATE vouchers SET used_count = MAX(0, used_count + ?) WHERE id = ?', [delta, id]);
  }

  // ---------------- TRANSAKSI ----------------
  Future<void> insertTransaction(TransactionModel trx, {List<CartItem> items = const []}) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert('transactions', trx.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      for (final it in items) {
        await txn.insert('transaction_items', {
          'trx_id': trx.id,
          'name': it.menu.name,
          'variants': it.variantDescription,
          'note': it.note,
          'qty': it.quantity,
          'price': it.unitPrice,
          'subtotal': it.totalPrice,
        });
      }
    });
  }

  Future<void> voidTransaction(String trxId, String reason) async {
    final db = await database;
    await db.update('transactions', {'status': 'VOID', 'void_reason': reason},
        where: 'id = ?', whereArgs: [trxId]);
  }

  Future<List<TransactionModel>> getUnsyncedTransactions() async {
    final db = await database;
    final res = await db.query('transactions', where: 'synced = 0');
    return res.map((m) => TransactionModel.fromMap(m)).toList();
  }

  Future<void> markTransactionSynced(String id) async {
    final db = await database;
    await db.update('transactions', {'synced': 1}, where: 'id = ?', whereArgs: [id]);
  }

  /// Baris item mentah (buat push ke Sheet: name/qty/price/subtotal).
  Future<List<Map<String, dynamic>>> getTransactionItemRows(String trxId) async {
    final db = await database;
    return db.query('transaction_items', where: 'trx_id = ?', whereArgs: [trxId]);
  }

  Future<List<CartItem>> getTransactionItems(String trxId) async {
    final db = await database;
    final rows = await db.query('transaction_items', where: 'trx_id = ?', whereArgs: [trxId]);
    return rows.map((r) {
      final menuName = (r['name'] ?? '').toString();
      final price = toInt(r['price']);
      final qty = toInt(r['qty']);
      final varsStr = (r['variants'] as String?) ?? '';
      final note = (r['note'] as String?) ?? '';
      final varsList = varsStr.isEmpty ? <String>[] : varsStr.split(', ');

      return CartItem(
        menu: MenuItemModel(id: 0, name: menuName, category: 'MENU', price: price, cost: 0, active: true, sortOrder: 0),
        selectedVariants: varsList,
        quantity: qty,
        note: note,
      );
    }).toList();
  }

  // ---------------- SETTINGS ----------------
  Future<Map<String, String>> getSettingsMap() async {
    final db = await database;
    final rows = await db.query('settings');
    return {for (final r in rows) r['key'] as String: (r['value'] ?? '').toString()};
  }

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---------------- EMPLOYEES & ATTENDANCE ----------------
  Future<List<Map<String, dynamic>>> getEmployees() async {
    final db = await database;
    return db.query('employees', orderBy: 'name ASC');
  }

  Future<void> insertEmployee(String name) async {
    final db = await database;
    await db.insert('employees', {'name': name, 'active': 1, 'shift_status': ''},
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> updateEmployeeShift(String name, String shiftStatus) async {
    final db = await database;
    await db.update('employees', {'shift_status': shiftStatus},
        where: 'name = ?', whereArgs: [name]);
  }

  /// Catat absen satu karyawan+shift per hari usaha (upsert: ga dobel kalau sudah ada).
  Future<void> recordAttendance(String employeeName, String businessDate, String shift) async {
    final db = await database;
    final existing = await db.query('attendances',
        where: 'employee_name = ? AND business_date = ? AND shift = ?',
        whereArgs: [employeeName, businessDate, shift]);
    if (existing.isNotEmpty) return; // sudah ada, jangan insert dobel
    await db.insert('attendances', {
      'employee_name': employeeName,
      'business_date': businessDate,
      'shift': shift,
      'created_at': DateTime.now().toIso8601String(),
      'synced': 0,
    });
  }

  /// Hapus record absen satu karyawan+shift per hari usaha (dipakai saat un-toggle).
  Future<void> removeAttendance(String employeeName, String businessDate, String shift) async {
    final db = await database;
    await db.delete('attendances',
        where: 'employee_name = ? AND business_date = ? AND shift = ?',
        whereArgs: [employeeName, businessDate, shift]);
  }

  Future<List<Map<String, dynamic>>> getTodayAttendances(String businessDate) async {
    final db = await database;
    return db.query('attendances', where: 'business_date = ?', whereArgs: [businessDate]);
  }

  // ---------------- KAS / CASH ENTRIES ----------------
  Future<void> insertCashEntry({
    required String type, // IN | OUT
    required int amount,
    required String category,
    required String note,
    required String businessDate,
    required String byName,
  }) async {
    final db = await database;
    await db.insert('cash_entries', {
      'type': type,
      'amount': amount,
      'category': category,
      'note': note,
      'business_date': businessDate,
      'by_name': byName,
      'created_at': DateTime.now().toIso8601String(),
      'synced': 0,
    });
  }

  Future<List<Map<String, dynamic>>> getCashEntries(String businessDate) async {
    final db = await database;
    return db.query('cash_entries', where: 'business_date = ?', whereArgs: [businessDate], orderBy: 'id DESC');
  }

  // ---------------- TRANSACTIONS & REKAP ----------------
  Future<List<TransactionModel>> getTodayTransactions(String businessDate) async {
    final db = await database;
    final res = await db.query('transactions',
        where: 'business_date = ? AND status = ?',
        whereArgs: [businessDate, 'ACTIVE'],
        orderBy: 'created_at DESC');
    return res.map((m) => TransactionModel.fromMap(m)).toList();
  }

  /// Pivot item terjual hari ini: group by nama menu, sum qty & subtotal.
  /// Hanya transaksi ACTIVE. Dipakai buat seksi "Item Terjual" di Recap.
  Future<List<Map<String, dynamic>>> getTodayItemSales(String businessDate) async {
    final db = await database;
    final res = await db.rawQuery('''
      SELECT ti.name AS menu,
             SUM(ti.qty) AS total_qty,
             SUM(ti.subtotal) AS total_omzet
      FROM transaction_items ti
      INNER JOIN transactions t ON t.id = ti.trx_id
      WHERE t.business_date = ? AND t.status = 'ACTIVE'
      GROUP BY ti.name
      ORDER BY total_qty DESC
    ''', [businessDate]);
    return res;
  }

  Future<Map<String, dynamic>> getTodaySummary(String businessDate) async {
    final db = await database;
    final trxs = await db.query('transactions',
        where: 'business_date = ? AND status = ?',
        whereArgs: [businessDate, 'ACTIVE']);

    int totalOmzet = 0;
    int trxCount = trxs.length;
    int totalTunai = 0;
    int totalQrisTransfer = 0;

    for (final t in trxs) {
      final amt = (t['total_amount'] as num?)?.toInt() ?? 0;
      totalOmzet += amt;
      final method = (t['payment_method'] as String?) ?? 'CASH';
      if (method == 'CASH') {
        totalTunai += amt;
      } else {
        totalQrisTransfer += amt;
      }
    }

    final cashInRows = await db.rawQuery(
      "SELECT SUM(amount) as s FROM cash_entries WHERE business_date = ? AND type = ?",
      [businessDate, CashType.in_]);
    final cashOutRows = await db.rawQuery(
      "SELECT SUM(amount) as s FROM cash_entries WHERE business_date = ? AND type = ?",
      [businessDate, CashType.out]);

    int cashIn = (cashInRows.first['s'] as num?)?.toInt() ?? 0;
    int cashOut = (cashOutRows.first['s'] as num?)?.toInt() ?? 0;
    int kasAwalDefault = 250000; // Modal awal laci harian default Rp 250.000

    return {
      'omzet': totalOmzet,
      'trxCount': trxCount,
      'tunai': totalTunai,
      'qrisTransfer': totalQrisTransfer,
      'cashIn': cashIn + kasAwalDefault,
      'cashOut': cashOut,
      'expectedCashInDrawer': kasAwalDefault + totalTunai + cashIn - cashOut,
    };
  }
}
