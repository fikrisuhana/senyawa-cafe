import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../services/db_helper.dart';
import '../services/seed_importer.dart';
import '../services/google_sheet_service.dart';

class PosProvider extends ChangeNotifier {
  List<MenuItemModel> _menuItems = [];
  List<PackagingModel> _packagings = [];
  List<VoucherModel> _vouchers = [];
  final List<CartItem> _cartItems = [];

  String _searchQuery = '';
  String _selectedCategory = 'SEMUA';
  String _orderType = 'DINE_IN'; // DINE_IN | TAKEAWAY
  String _paymentMethod = 'CASH'; // CASH | QRIS | TRANSFER
  VoucherModel? _selectedVoucher;
  int _cashReceived = 0;
  bool _isLoading = true;
  List<String> _shifts = ['Pagi', 'Sore']; // daftar shift (dari Sheet tab Setup)

  Timer? _syncTimer;
  DateTime _lastSyncTime = DateTime.now();
  bool _isSyncing = false;
  bool _lastSyncFailed = false;
  String _activeCashier = 'Andi';
  bool _googleConnected = false; // true setelah login Google (fase terakhir)
  String? _checkoutError;

  String get activeCashier => _activeCashier;
  String get activeCashierDisplay => _activeCashier;
  bool get googleConnected => _googleConnected;
  String? get checkoutError => _checkoutError;

  void setActiveCashier(String name) {
    _activeCashier = name;
    notifyListeners();
  }

  List<MenuItemModel> get menuItems => _menuItems;
  List<PackagingModel> get packagings => _packagings;
  List<VoucherModel> get vouchers => _vouchers;
  List<CartItem> get cartItems => _cartItems;
  String get searchQuery => _searchQuery;
  String get selectedCategory => _selectedCategory;
  String get orderType => _orderType;
  String get paymentMethod => _paymentMethod;
  VoucherModel? get selectedVoucher => _selectedVoucher;
  int get cashReceived => _cashReceived;
  bool get isLoading => _isLoading;
  bool get isSyncing => _isSyncing;
  List<String> get shifts => _shifts;

  String get syncStatusText {
    if (!_googleConnected) return 'Lokal · Google belum tersambung';
    if (_isSyncing) return 'Sinkron…';
    if (_lastSyncFailed) return 'Sync gagal · ketuk untuk coba lagi';
    final diff = DateTime.now().difference(_lastSyncTime).inMinutes;
    if (diff <= 0) return 'Sinkron <1m lalu';
    return 'Sinkron ${diff}m lalu';
  }
  bool get lastSyncFailed => _lastSyncFailed;

  PosProvider() {
    initData();
  }

  Future<void> initData() async {
    _isLoading = true;
    notifyListeners();

    // Import seeder jika first boot. Dedup varian/resep lama sudah jalan
    // di migration DB v3→v4 (lihat db_helper._onUpgrade).
    await SeedImporter.importSeederIfNeeded();
    await loadCatalog();

    final prefs = await SharedPreferences.getInstance();
    final sheetId = prefs.getString('spreadsheet_id') ?? '';
    if (sheetId.isNotEmpty) {
      _googleConnected = true;
    } else {
      if (!_googleConnected) {
        try {
          final acc = await GoogleSheetService().signIn(interactive: false);
          if (acc != null) _googleConnected = true;
        } catch (e) {
          debugPrint('Silent Google reconnect gagal: $e');
        }
      }
    }

    _isLoading = false;
    _startPeriodicSync();
    performSync(); // ekspor transaksi pending + sinkronkan catalog
    notifyListeners();
  }

  void _startPeriodicSync() {
    _syncTimer?.cancel();
    // Auto-sync tiap 15 menit HANYA kalau Google tersambung (hemat baterai/network).
    if (!_googleConnected) return;
    _syncTimer = Timer.periodic(const Duration(minutes: 15), (_) => performSync());
  }

  /// Dipanggil dari splash/settings setelah login Google berhasil.
  void setGoogleConnected(bool v) {
    _googleConnected = v;
    _startPeriodicSync();
    if (v) performSync();
    notifyListeners();
  }

  Future<void> performSync() async {
    if (_isSyncing) return;
    _isSyncing = true;
    notifyListeners();

    try {
      final db = DbHelper();
      final svc = GoogleSheetService();

      if (!svc.isConnected) {
        await svc.signIn(interactive: false);
      }
      if (!svc.isConnected) {
        // Belum bisa login (mis. belum setup) → bukan error, cuma skip.
        _lastSyncFailed = false;
        return;
      }

      final targetSheetId = await svc.ensureSpreadsheet();

      if (targetSheetId != null && targetSheetId.isNotEmpty) {
        _googleConnected = true;
        final unsynced = await db.getUnsyncedTransactions();
        final hadNewTrx = unsynced.isNotEmpty;
        for (final trx in unsynced) {
          await svc.appendTransaction(targetSheetId, trx.toMap());
          // Kirim juga item-item transaksi (buat laporan menu terlaris di Sheet).
          final itemRows = await db.getTransactionItemRows(trx.id);
          await svc.appendTransactionItems(targetSheetId, trx.code, itemRows);
          await db.markTransactionSynced(trx.id);
        }
        // Pull perubahan menu & karyawan dari Sheet (2 arah: owner bisa edit di Sheet).
        await svc.pullMenuFromSheet(targetSheetId);
        try {
          await svc.pullEmployees(targetSheetId);
          // Pull daftar shift dulu (dipakai normalisasi absen backward-compat).
          final newShifts = await svc.pullShifts(targetSheetId);
          if (newShifts.isNotEmpty && !_listEq(newShifts, _shifts)) {
            _shifts = newShifts;
            notifyListeners();
          }
          await svc.pullAttendance(targetSheetId, validShifts: _shifts);
        } catch (e) {
          debugPrint('Pull karyawan/absen/shift dari Sheet gagal: $e');
        }
        await loadCatalog();

        // Segarkan laporan Sheet: Dashboard + Rekap_Bulanan + Absensi_Matriks.
        // Lakukan kalau ada transaksi baru (data berubah) — hindari hammer API
        // kalau sync periodik tanpa aktivitas.
        if (hadNewTrx) {
          try {
            await svc.pushRekapBulanan(targetSheetId);
            await svc.pushAbsensiMatriks(targetSheetId);
            await svc.pushDashboard(targetSheetId);
          } catch (e) {
            debugPrint('Refresh laporan Sheet gagal: $e');
          }
        }
      }

      _lastSyncTime = DateTime.now();
      _lastSyncFailed = false;
    } catch (e) {
      debugPrint('Auto Sync Error: $e');
      _lastSyncFailed = true;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> loadCatalog() async {
    final db = DbHelper();
    _menuItems = await db.getMenuItems();
    _packagings = await db.getPackagings();
    _vouchers = await db.getVouchers();
    notifyListeners();
  }

  /// Simpan katalog lokal LALU push ke Google Sheet (dipanggil setelah admin edit
  /// menu/voucher/stok). Biar perubahan dari APP masuk ke Sheet, bukan cuma lokal.
  Future<void> syncCatalogUp() async {
    await loadCatalog();
    if (!_googleConnected) return;
    try {
      final svc = GoogleSheetService();
      final id = await svc.ensureSpreadsheet();
      if (id != null) await svc.pushCatalog(id);
    } catch (e) {
      debugPrint('Push katalog ke Sheet gagal: $e');
    }
  }

  // --- FILTER & SEARCH ---
  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setSelectedCategory(String cat) {
    _selectedCategory = cat;
    notifyListeners();
  }

  List<MenuItemModel> get filteredMenuItems {
    return _menuItems.where((item) {
      final matchesSearch = item.name.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesCat = (_selectedCategory == 'SEMUA') || (item.category.toUpperCase() == _selectedCategory.toUpperCase());
      return matchesSearch && matchesCat;
    }).toList();
  }

  // --- CART MANAGEMENT ---
  void addToCart(MenuItemModel menu, {List<String>? selectedVariants, int extraPrice = 0, String note = ''}) {
    final existingIndex = _cartItems.indexWhere((c) =>
        c.menu.name == menu.name &&
        c.variantDescription == (selectedVariants?.join(', ') ?? '') &&
        c.note == note);

    if (existingIndex >= 0) {
      _cartItems[existingIndex].quantity += 1;
    } else {
      _cartItems.add(CartItem(
        menu: menu,
        quantity: 1,
        selectedVariants: selectedVariants ?? [],
        variantExtraPrice: extraPrice,
        note: note,
      ));
    }
    notifyListeners();
  }

  void updateQuantity(int index, int delta) {
    if (index >= 0 && index < _cartItems.length) {
      _cartItems[index].quantity += delta;
      if (_cartItems[index].quantity <= 0) {
        _cartItems.removeAt(index);
      }
      notifyListeners();
    }
  }

  void clearCart() {
    _cartItems.clear();
    _selectedVoucher = null;
    _cashReceived = 0;
    notifyListeners();
  }

  void setOrderType(String type) {
    _orderType = type;
    notifyListeners();
  }

  void setPaymentMethod(String method) {
    _paymentMethod = method;
    notifyListeners();
  }

  void setSelectedVoucher(VoucherModel? v) {
    _selectedVoucher = v;
    notifyListeners();
  }

  void setCashReceived(int amount) {
    _cashReceived = amount;
    notifyListeners();
  }

  // --- CALCULATIONS ---
  int get subtotal => _cartItems.fold(0, (sum, item) => sum + item.totalPrice);

  int get discountAmount {
    if (_selectedVoucher == null) return 0;
    if (_selectedVoucher!.type == 'PERCENT') {
      return (subtotal * (_selectedVoucher!.value / 100)).round();
    } else {
      return _selectedVoucher!.value;
    }
  }

  int get totalAmount {
    final t = subtotal - discountAmount;
    return t < 0 ? 0 : t;
  }

  int get changeAmount {
    if (_paymentMethod != 'CASH') return 0;
    final diff = _cashReceived - totalAmount;
    return diff < 0 ? 0 : diff;
  }

  // --- CHECKOUT TRANSACTION ---
  /// Kunci hari usaha (buka 07:00–03:00, pemisah jam 6 → jual 00:30 = hari kemarin).
  String _businessDateKey(DateTime d, {int cutoffHour = 6}) {
    return DateFormat('yyyy-MM-dd').format(d.subtract(Duration(hours: cutoffHour)));
  }

  Future<TransactionModel?> checkout(String cashierName) async {
    _checkoutError = null;
    if (_cartItems.isEmpty) return null;
    final now = DateTime.now();

    // Validasi voucher (aktif / periode / kuota)
    if (_selectedVoucher != null) {
      final reason = _selectedVoucher!.invalidReason(now);
      if (reason != null) {
        _checkoutError = '$reason: ${_selectedVoucher!.name}';
        notifyListeners();
        return null;
      }
    }

    // TUNAI wajib cukup — tolak kalau uang diterima < total.
    if (_paymentMethod == 'CASH' && _cashReceived < totalAmount) {
      final kurang = totalAmount - _cashReceived;
      _checkoutError = 'Uang tunai kurang Rp$kurang dari total. Transaksi belum bisa diselesaikan.';
      notifyListeners();
      return null;
    }

    // VALIDASI STOK: cek semua bahan (resep base + opsi varian) cukup.
    final stockReason = await DbHelper().validateStockForCart(_cartItems);
    if (stockReason != null) {
      _checkoutError = stockReason;
      notifyListeners();
      return null;
    }

    final String trxCode =
        'TRX-${DateFormat('yyyyMMdd').format(now)}-${now.millisecondsSinceEpoch.toString().substring(7)}';
    // Total modal/HPP = Σ (modal menu × qty) → buat hitung untung kotor di laporan.
    final int costTotal = _cartItems.fold<int>(0, (s, it) => s + it.menu.cost * it.quantity);
    final trx = TransactionModel(
      id: 'trx_${now.millisecondsSinceEpoch}',
      code: trxCode,
      createdAt: now,
      businessDate: _businessDateKey(now),
      cashierName: cashierName,
      orderType: _orderType,
      paymentMethod: _paymentMethod,
      subtotal: subtotal,
      discountAmount: discountAmount,
      voucherName: _selectedVoucher?.name,
      totalAmount: totalAmount,
      cashReceived: _paymentMethod == 'CASH' ? _cashReceived : totalAmount,
      changeAmount: changeAmount,
      costTotal: costTotal,
      synced: false,
    );

    final db = DbHelper();
    await db.insertTransaction(trx, items: List<CartItem>.from(_cartItems));

    // Potong stok: bahan base menu + bahan khusus opsi varian terpilih
    for (final item in _cartItems) {
      for (final row in await db.getMenuStocks(item.menu.name)) {
        final pkg = (row['packaging_name'] ?? '').toString();
        final qty = (row['qty'] as num).toInt() * item.quantity;
        if (pkg.isNotEmpty) await db.reducePackagingByName(pkg, qty);
      }
      for (final sv in item.selectedVariants) {
        final optName = sv.replaceAll(RegExp(r'\(.*?\)'), '').trim();
        for (final row in await db.getOptionStocks(item.menu.name, optName)) {
          final pkg = (row['packaging_name'] ?? '').toString();
          final qty = (row['qty'] as num).toInt() * item.quantity;
          if (pkg.isNotEmpty) await db.reducePackagingByName(pkg, qty);
        }
      }
    }

    // Naikkan pemakaian voucher
    if (_selectedVoucher?.id != null) {
      await db.incrementVoucherUsage(_selectedVoucher!.id!);
    }

    // Auto-sync segera ke Google Sheet (background)
    performSync();

    await loadCatalog(); // segarkan stok & voucher
    clearCart();
    return trx;
  }

  Future<bool> voidTransaction(String trxId, String reason) async {
    final db = DbHelper();
    // Kembalikan stok bahan yang tadi dipotong saat checkout.
    await db.restoreStockForTransaction(trxId);
    // Turunkan pemakaian voucher (kembalikan kuota).
    final trxRows = await (await db.database)
        .query('transactions', where: 'id = ?', whereArgs: [trxId]);
    if (trxRows.isNotEmpty) {
      final voucherName = (trxRows.first['voucher_name'] as String?) ?? '';
      if (voucherName.isNotEmpty) {
        final v = await db.getVoucherByName(voucherName);
        if (v?.id != null) {
          await db.incrementVoucherUsage(v!.id!, delta: -1);
        }
      }
    }
    await db.voidTransaction(trxId, reason);
    await loadCatalog();
    notifyListeners();
    return true;
  }

  /// Bandingkan 2 list string (urutan penting). Dipakai cek apakah shifts berubah.
  bool _listEq(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }
}
