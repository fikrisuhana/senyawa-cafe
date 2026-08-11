import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:googleapis/sheets/v4.dart' as gs;
import 'package:googleapis/drive/v3.dart' as gd;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import 'db_helper.dart';

/// Model ringkas file Spreadsheet untuk dipilih di layar setup.
class SheetFileInfo {
  final String id;
  final String name;
  final DateTime? modifiedTime;
  SheetFileInfo({required this.id, required this.name, this.modifiedTime});
}

/// Sinkronisasi lokal ↔ Google Sheet (owner).
/// Spreadsheet auto-dibuat saat pertama login kalau belum ada.
class GoogleSheetService {
  static final GoogleSheetService _instance = GoogleSheetService._internal();
  factory GoogleSheetService() => _instance;
  GoogleSheetService._internal();

  final GoogleSignIn googleSignIn = GoogleSignIn(scopes: const [
    'email',
    gs.SheetsApi.spreadsheetsScope, // https://www.googleapis.com/auth/spreadsheets
    'https://www.googleapis.com/auth/drive.file',
  ]);

  GoogleSignInAccount? _account;
  gs.SheetsApi? _api;
  gd.DriveApi? _driveApi;

  // Tab & header yang ditulis ke Sheet
  // Tab & header yang ditulis ke Sheet.
  // Grup 1 (LAPORAN): Dashboard, Rekap_Bulanan, Absensi_Matriks — owner baca ini.
  // Grup 2 (SETUP): Menu_Resep, Varian, Bahan, Voucher — master data, boleh diedit.
  // Grup 3 (RAW DATA): Transaksi, Transaksi_Item, Kas, Restok_Log, Absensi — append-only.
  static const _tabs = <String, List<String>>{
    'Dashboard': ['Ringkasan Indikator POS', 'Nilai Hari Ini', 'Keterangan Auto-Formula'],
    'Rekap_Bulanan': ['bulan', 'omzet', 'transaksi', 'rata_rata', 'tunai', 'qris', 'transfer', 'diskon', 'modal', 'laba_kotor', 'kas_masuk', 'kas_keluar'],
    'Absensi_Matriks': ['tgl'],
    'Menu_Resep': ['nama', 'kategori', 'harga', 'modal', 'aktif', 'urutan', 'bahan', 'qty_bahan'],
    'Varian': ['menu', 'grup', 'tipe', 'wajib', 'opsi', 'tambahan_harga', 'bahan_opsi', 'qty_opsi'],
    'Bahan': ['nama', 'satuan', 'stok_utama', 'stok_min', 'total_penambahan_stok', 'total_stok_tersedia'],
    'Voucher': ['nama', 'tipe', 'nilai', 'aktif', 'kuota', 'terpakai', 'berlaku_dari', 'berlaku_sampai'],
    'Transaksi': ['kode', 'hari_usaha', 'waktu', 'kasir', 'tipe', 'metode', 'subtotal', 'diskon', 'voucher', 'total', 'status', 'modal', 'laba'],
    'Transaksi_Item': ['kode_trx', 'menu', 'varian', 'qty', 'harga', 'subtotal'],
    'Kas': ['hari_usaha', 'tipe', 'nominal', 'kategori', 'catatan', 'oleh', 'waktu'],
    'Restok_Log': ['waktu', 'nama_bahan', 'jumlah_tambah', 'satuan', 'stok_akhir'],
    'Absensi': ['hari_usaha', 'karyawan', 'hadir', 'waktu'],
    'Karyawan': ['nama', 'aktif', 'shift_status'],
    'Setup': ['key', 'value'],
    'Voucher_Log': ['kode_trx', 'hari_usaha', 'kasir', 'voucher', 'tipe', 'nilai_diskon', 'subtotal', 'total_setelah'],
    'Menu_Terlaris': ['menu', 'total_qty', 'total_omzet', 'qty_bulan_ini', 'omzet_bulan_ini'],
  };

  bool get isConnected => _account != null && _api != null;
  String get email => _account?.email ?? '';
  String get displayName => _account?.displayName ?? '';

  /// Login Google + siapkan API client (Sheets + Drive).
  Future<GoogleSignInAccount?> signIn({bool interactive = true}) async {
    _account = interactive
        ? await googleSignIn.signIn()
        : (await googleSignIn.signInSilently());
    if (_account == null) return null;
    final client = await googleSignIn.authenticatedClient();
    if (client != null) {
      _api = gs.SheetsApi(client);
      _driveApi = gd.DriveApi(client);
    }
    return _account;
  }

  Future<void> signOut() async {
    await googleSignIn.signOut();
    _account = null;
    _api = null;
    _driveApi = null;
  }

  /// Daftar file Spreadsheet yang dimiliki/dibuat oleh akun ini (via Drive API).
  /// Dipakai di layar setup: owner pilih file existing atau buat baru.
  Future<List<SheetFileInfo>> listSpreadsheets() async {
    if (_driveApi == null) return [];
    final res = await _driveApi!.files.list(
      q: "mimeType='application/vnd.google-apps.spreadsheet' and trashed=false",
      orderBy: 'modifiedByMeTime desc',
      pageSize: 50,
      $fields: 'files(id,name,modifiedTime)',
    );
    final files = res.files ?? [];
    return files
        .map((f) => SheetFileInfo(
              id: f.id ?? '',
              name: f.name ?? '(tanpa nama)',
              modifiedTime: f.modifiedTime,
            ))
        .where((f) => f.id.isNotEmpty)
        .toList();
  }

  /// Buat spreadsheet baru dengan nama tertentu, simpan ID-nya ke prefs,
  /// isi semua tab + push katalog. Kembali ke SheetFileInfo.
  Future<SheetFileInfo?> createSpreadsheetByName(String name) async {
    if (_api == null) return null;
    final prefs = await SharedPreferences.getInstance();
    final created = await _api!.spreadsheets.create(gs.Spreadsheet(
      properties: gs.SpreadsheetProperties(title: name, locale: 'en_US'),
      sheets: _tabs.keys
          .map((t) => gs.Sheet(properties: gs.SheetProperties(title: t)))
          .toList(),
    ));
    final newId = created.spreadsheetId ?? '';
    if (newId.isEmpty) return null;
    await prefs.setString('spreadsheet_id', newId);
    await _ensureTabsExist(newId);
    await pushCatalog(newId);
    debugPrint('📗 Spreadsheet baru dibuat: "$name" ($newId)');
    return SheetFileInfo(id: newId, name: name);
  }

  /// Pakai spreadsheet existing (hasil pilih dari list). Simpan ID + isi tab
  /// kalau perlu + push katalog kalau tab Menu masih kosong.
  Future<void> useExistingSpreadsheet(String id, String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('spreadsheet_id', id);
    await _ensureTabsExist(id);
    if (await _menuTabEmpty(id)) {
      await pushCatalog(id);
    } else {
      try {
        await pushDashboard(id);
      } catch (e) {
        debugPrint('Dashboard gagal diisi: $e');
      }
    }
    debugPrint('📎 Pakai Sheet existing: "$name" ($id)');
  }

  /// Pastikan spreadsheet ada. Kalau ID kosong → buat baru. Kalau tab Menu kosong → push katalog.
  Future<String?> ensureSpreadsheet() async {
    if (_api == null) return null;
    final prefs = await SharedPreferences.getInstance();
    String id = prefs.getString('spreadsheet_id') ?? '';
    if (id.isEmpty || id.startsWith('1RuangSenyawa')) {
      id = await _createNewSpreadsheet(prefs);
    }
    if (id.isEmpty) return null;

    // Pastikan tab ada & bisa diakses. Jika permission error (403/404), buat spreadsheet baru untuk akun ini.
    try {
      await _ensureTabsExist(id);
      if (await _menuTabEmpty(id)) {
        await pushCatalog(id);
      } else {
        try {
          await pushDashboard(id);
        } catch (e) {
          debugPrint('Dashboard gagal diisi: $e');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Tidak punya akses ke Sheet ID ($id), membuat Sheet baru di Drive akun ini... Err: $e');
      id = await _createNewSpreadsheet(prefs);
      if (id.isNotEmpty) {
        await _ensureTabsExist(id);
        await pushCatalog(id);
      }
    }
    return id;
  }

  Future<String> _createNewSpreadsheet(SharedPreferences prefs) async {
    final created = await _api!.spreadsheets.create(gs.Spreadsheet(
      properties: gs.SpreadsheetProperties(title: 'Ruang Senyawa — Laporan POS', locale: 'en_US'),
      sheets: _tabs.keys
          .map((t) => gs.Sheet(properties: gs.SheetProperties(title: t)))
          .toList(),
    ));
    final newId = created.spreadsheetId ?? '';
    if (newId.isNotEmpty) {
      await prefs.setString('spreadsheet_id', newId);
      debugPrint('📗 Spreadsheet baru dibuat untuk akun Google saat ini: $newId');
    }
    return newId;
  }

  /// Tambahkan tab yang belum ada (self-heal spreadsheet lama saat skema tab nambah).
  Future<void> _ensureTabsExist(String id) async {
    try {
      final ss = await _api!.spreadsheets.get(id);
      final existing = (ss.sheets ?? [])
          .map((s) => s.properties?.title)
          .whereType<String>()
          .toSet();
      final missing = _tabs.keys.where((t) => !existing.contains(t)).toList();
      if (missing.isEmpty) return;
      await _api!.spreadsheets.batchUpdate(
        gs.BatchUpdateSpreadsheetRequest(
          requests: missing
              .map((t) => gs.Request(addSheet: gs.AddSheetRequest(properties: gs.SheetProperties(title: t))))
              .toList(),
        ),
        id,
      );
      debugPrint('🧩 Tab baru dibuat di Sheet: ${missing.join(", ")}');
    } catch (e) {
      debugPrint('Cek/buat tab gagal: $e');
    }
  }

  Future<bool> _menuTabEmpty(String id) async {
    try {
      final res = await _api!.spreadsheets.values.get(id, "'Menu_Resep'!A2:A2");
      return res.values == null || res.values!.isEmpty;
    } catch (_) {
      return true;
    }
  }

  Future<void> _writeTab(String id, String tab, List<List<Object?>> rows) async {
    await _api!.spreadsheets.values.update(
      gs.ValueRange(values: rows),
      id,
      "'$tab'!A1",
      valueInputOption: 'RAW',
    );
  }

  /// Tulis katalog (Menu_Resep/Varian/Bahan/Voucher) + header semua tab.
  /// Menu & bahan base di-merge ke 1 tab Menu_Resep; Varian & bahan opsi di-merge ke Varian.
  Future<void> pushCatalog(String id) async {
    if (_api == null) return;
    final db = DbHelper();

    // Header dulu untuk semua tab (Dashboard/Rekap/Matriks di-handle method khusus).
    for (final e in _tabs.entries) {
      if (e.key == 'Dashboard' ||
          e.key == 'Rekap_Bulanan' ||
          e.key == 'Absensi_Matriks') {
        continue;
      }
      await _writeTab(id, e.key, [e.value]);
    }

    // --- Menu_Resep: menu + bahan base di-join (bahan dipisah ";") ---
    final menus = await db.getMenuItems();
    final menuStocks = await db.getAllMenuStocks();
    // Kelompokkan bahan per menu: { menuName: [{bahan, qty}, ...] }
    final Map<String, List<Map<String, dynamic>>> resepByMenu = {};
    for (final s in menuStocks) {
      final m = (s['menu_name'] ?? '').toString();
      resepByMenu.putIfAbsent(m, () => []).add({
        'bahan': s['packaging_name'],
        'qty': s['qty'],
      });
    }
    await _writeTab(id, 'Menu_Resep', [
      _tabs['Menu_Resep']!,
      ...menus.map((m) {
        final resep = resepByMenu[m.name] ?? [];
        final bahanStr = resep.map((r) => r['bahan']).join('; ');
        final qtyStr = resep.map((r) => r['qty']).join('; ');
        return [m.name, m.category, m.price, m.cost, m.active ? 1 : 0, m.sortOrder, bahanStr, qtyStr];
      }),
    ]);

    // --- Varian: grup+opsi + bahan opsi di-merge ---
    final groups = await db.getAllVariantGroups();
    final gMap = {for (final g in groups) '${g.menuName}||${g.groupName}': g};
    final options = await db.getAllVariantOptions();
    final vStocks = await db.getAllVariantOptionStocks();
    // Kelompokkan bahan per (menu|grup|opsi)
    String stkKey(String mn, String gn, String on) => '$mn|$gn|$on';
    final Map<String, List<Map<String, dynamic>>> bahanOpsi = {};
    for (final s in vStocks) {
      final k = stkKey(
        (s['menu_name'] ?? '').toString(),
        (s['group_name'] ?? '').toString(),
        (s['option_name'] ?? '').toString(),
      );
      bahanOpsi.putIfAbsent(k, () => []).add({
        'bahan': s['packaging_name'],
        'qty': s['qty'],
      });
    }
    await _writeTab(id, 'Varian', [
      _tabs['Varian']!,
      ...options.map((o) {
        final g = gMap['${o.menuName}||${o.groupName}'];
        final tipe = (g?.type == 'MULTI') ? 'Boleh banyak' : 'Pilih 1';
        final wajib = (g?.required ?? false) ? 'Ya' : 'Tidak';
        final bk = bahanOpsi[stkKey(o.menuName, o.groupName, o.optionName)] ?? [];
        final bahanStr = bk.map((r) => r['bahan']).join('; ');
        final qtyStr = bk.map((r) => r['qty']).join('; ');
        return [o.menuName, o.groupName, tipe, wajib, o.optionName, o.priceDelta, bahanStr, qtyStr];
      }),
    ]);

    // --- Bahan: 6 kolom (fix bug: sebelumnya cuma tulis 4) ---
    final bahan = await db.getPackagings();
    await _writeTab(id, 'Bahan', [
      _tabs['Bahan']!,
      ...bahan.map((b) => [
            b.name,
            b.unit,
            b.stock,           // stok_utama
            b.minStock,        // stok_min
            '',                // total_penambahan_stok (diisi via rumus opsional nanti)
            b.stock,           // total_stok_tersedia (= stok saat ini)
          ]),
    ]);

    final vouchers = await db.getVouchers(onlyActive: false);
    await _writeTab(id, 'Voucher', [
      _tabs['Voucher']!,
      ...vouchers.map((v) => [
            v.name, v.type, v.value, v.active ? 1 : 0,
            v.kuota ?? '', v.usedCount, v.validFrom ?? '', v.validUntil ?? '',
          ]),
    ]);
    debugPrint('⬆️ Katalog terkirim ke Sheet: ${menus.length} menu, ${bahan.length} bahan, ${vouchers.length} voucher.');

    // Push juga daftar karyawan (biar owner bisa lihat/edit di Sheet).
    try {
      await pushEmployees(id);
    } catch (e) {
      debugPrint('Push karyawan gagal: $e');
    }
    // Push tab Setup (default shifts) kalau belum ada.
    try {
      await pushSetup(id);
    } catch (e) {
      debugPrint('Push setup gagal: $e');
    }

    // Isi/segarkan tab laporan.
    try {
      await pushDashboard(id);
    } catch (e) {
      debugPrint('Dashboard gagal diisi: $e');
    }
    try {
      await pushRekapBulanan(id);
    } catch (e) {
      debugPrint('Rekap bulanan gagal: $e');
    }
    try {
      await pushAbsensiMatriks(id);
    } catch (e) {
      debugPrint('Absensi matriks gagal: $e');
    }
    try {
      await pushMenuTerlaris(id);
    } catch (e) {
      debugPrint('Menu terlaris gagal: $e');
    }
  }

  /// Tulis DASHBOARD ringkasan owner — board KPI bersekat + rumus LIVE + format
  /// (currency/persen/warna). Kolom Transaksi: B hari_usaha, D kasir, E tipe,
  /// Tulis DASHBOARD ringkasan owner — board KPI dengan FILTER DROPDOWN INTERAKTIF
  /// (Hari Ini, Kemarin, 7 Hari Terakhir, Bulan Ini, Bulan Lalu, 3 Bulan, Sepanjang Waktu).
  /// Semua formula otomatis live mengikuti pilihan di sel B3 tanpa perlu reload!
  Future<void> pushDashboard(String id) async {
    if (_api == null) return;

    // Sel referensi filter:
    // B3: Dropdown Pilihan Periode
    // C4: Tanggal Awal (string YYYY-MM-DD hasil formula)
    // B5: Tanggal Akhir (string YYYY-MM-DD hasil formula)
    const tAwal = r'$C$4';
    const tAkhir = r'$B$5';

    // Formula dinamis berdasarkan rentang tanggal terpilih
    const omzetFilter = 'SUMIFS(Transaksi!J:J,Transaksi!B:B,">="&$tAwal,Transaksi!B:B,"<="&$tAkhir,Transaksi!K:K,"ACTIVE")';
    const trxFilter = 'COUNTIFS(Transaksi!B:B,">="&$tAwal,Transaksi!B:B,"<="&$tAkhir,Transaksi!K:K,"ACTIVE")';
    String metode(String m) => 'SUMIFS(Transaksi!J:J,Transaksi!B:B,">="&$tAwal,Transaksi!B:B,"<="&$tAkhir,Transaksi!F:F,"$m",Transaksi!K:K,"ACTIVE")';
    String tipeVal(String tp) => 'SUMIFS(Transaksi!J:J,Transaksi!B:B,">="&$tAwal,Transaksi!B:B,"<="&$tAkhir,Transaksi!E:E,"$tp",Transaksi!K:K,"ACTIVE")';
    String tipeCnt(String tp) => 'COUNTIFS(Transaksi!B:B,">="&$tAwal,Transaksi!B:B,"<="&$tAkhir,Transaksi!E:E,"$tp",Transaksi!K:K,"ACTIVE")';

    // Susun baris + tandai jenis format tiap sel.
    final values = <List<Object?>>[];
    final sectionRows = <int>[]; // baris judul seksi
    final rpRows = <int>[];      // sel B format rupiah
    final pctB = <int>[];        // sel B format persen
    final pctC = <int>[];        // sel C format persen
    int r = 0;
    void title(String s) { values.add([s, '', '']); r++; }
    void sub(String s) { values.add([s, '', '']); r++; }
    void gap() { values.add(['', '', '']); r++; }
    void sec(String s) { values.add([s, '', '']); sectionRows.add(r); r++; }
    void kv(String label, String formula, {String note = '', String bfmt = 'rp', String? cFormula, String cfmt = ''}) {
      values.add([label, formula.isEmpty ? '' : '=$formula', cFormula != null ? '=$cFormula' : note]);
      if (bfmt == 'rp') rpRows.add(r);
      if (bfmt == 'pct') pctB.add(r);
      if (cfmt == 'pct') pctC.add(r);
      r++;
    }

    title('📊 RUANG SENYAWA — DASHBOARD POS');
    sub('Filter interaktif: Pilih periode pada dropdown B3 di bawah (laporan otomatis hitung live):');

    // Baca daftar metode dari Setup (dinamis, dipakai di banyak seksi + chart).
    final methodsRaw = await _pullSetupValue(id, 'payment_methods');
    final methods = (methodsRaw ?? 'Tunai,QRIS,Transfer')
        .split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final tunaiMethod = methods.where((m) {
      final low = m.toLowerCase();
      return low.contains('tunai') || low.contains('cash');
    }).followedBy(methods).first;

    // Baris 3: Dropdown Selector
    values.add(['🔍 PILIH PERIODE LAPORAN:', 'Hari Ini', r'="[ Rentang: "&$C$4&" s/d "&$B$5&" ]"']); r++;

    // Baris 4: Tanggal Awal formula
    values.add([
      '📅 Tgl Awal Filter (auto):',
      'Tanggal Awal:',
      '=IF(B3="Hari Ini",TEXT(TODAY(),"yyyy-mm-dd"),IF(B3="Kemarin",TEXT(TODAY()-1,"yyyy-mm-dd"),IF(B3="7 Hari Terakhir",TEXT(TODAY()-6,"yyyy-mm-dd"),IF(B3="30 Hari Terakhir",TEXT(TODAY()-29,"yyyy-mm-dd"),IF(B3="Bulan Ini",TEXT(DATE(YEAR(TODAY()),MONTH(TODAY()),1),"yyyy-mm-dd"),IF(B3="Bulan Lalu",TEXT(EDATE(DATE(YEAR(TODAY()),MONTH(TODAY()),1),-1),"yyyy-mm-dd"),IF(B3="3 Bulan Terakhir",TEXT(EDATE(TODAY(),-3),"yyyy-mm-dd"),"2020-01-01")))))))',
    ]); r++;
    // Baris 5: Tanggal Akhir formula
    values.add([
      '📅 Tgl Akhir Filter (auto):',
      '=IF(B3="Kemarin",TEXT(TODAY()-1,"yyyy-mm-dd"),IF(B3="Bulan Lalu",TEXT(DATE(YEAR(TODAY()),MONTH(TODAY()),1)-1,"yyyy-mm-dd"),TEXT(TODAY(),"yyyy-mm-dd")))',
      'Rumus otomatis aktif ✓',
    ]); r++;
    gap();

    sec('▌ RINGKASAN PERIODE TERPILIH');
    kv('Omzet Penjualan', omzetFilter, note: 'penjualan ACTIVE');
    kv('Jumlah Transaksi', trxFilter, bfmt: 'int');
    kv('Rata-rata / Transaksi', 'IFERROR($omzetFilter/$trxFilter,0)');
    kv('Diskon Diberikan', 'SUMIFS(Transaksi!H:H,Transaksi!B:B,">="&$tAwal,Transaksi!B:B,"<="&$tAkhir,Transaksi!K:K,"ACTIVE")', note: 'potongan voucher');
    gap();

    sec('▌ METODE PEMBAYARAN (PERIODE TERPILIH)');
    for (final m in methods) {
      kv(m, metode(m), cFormula: 'IFERROR(${metode(m)}/$omzetFilter,0)', cfmt: 'pct');
    }
    gap();

    sec('▌ KAS & UANG LACI (PERIODE TERPILIH)');
    kv('Kas Masuk', 'SUMIFS(Kas!C:C,Kas!A:A,">="&$tAwal,Kas!A:A,"<="&$tAkhir,Kas!B:B,"MASUK")', note: 'kas awal + pemasukan');
    kv('Pengeluaran Kas', 'SUMIFS(Kas!C:C,Kas!A:A,">="&$tAwal,Kas!A:A,"<="&$tAkhir,Kas!B:B,"KELUAR")');
    kv('Estimasi Arus Kas Bersih', '${metode(tunaiMethod)}+SUMIFS(Kas!C:C,Kas!A:A,">="&$tAwal,Kas!A:A,"<="&$tAkhir,Kas!B:B,"MASUK")-SUMIFS(Kas!C:C,Kas!A:A,">="&$tAwal,Kas!A:A,"<="&$tAkhir,Kas!B:B,"KELUAR")', note: 'tunai + masuk − keluar');
    gap();

    sec('▌ TIPE PESANAN (PERIODE TERPILIH)');
    kv('Makan di tempat', tipeVal('DINE_IN'), cFormula: '${tipeCnt('DINE_IN')}&" transaksi"', cfmt: '');
    kv('Bungkus (Takeaway)', tipeVal('TAKEAWAY'), cFormula: '${tipeCnt('TAKEAWAY')}&" transaksi"', cfmt: '');
    gap();

    // Kinerja kasir — dinamis dari daftar karyawan aktif.
    final emps = await _activeEmployeeNames();
    if (emps.isNotEmpty) {
      sec('▌ KINERJA KASIR (PERIODE TERPILIH)');
      for (final name in emps) {
        final safe = name.replaceAll('"', '');
        kv('   $safe', 'SUMIFS(Transaksi!J:J,Transaksi!B:B,">="&$tAwal,Transaksi!B:B,"<="&$tAkhir,Transaksi!D:D,"$safe",Transaksi!K:K,"ACTIVE")',
            cFormula: 'COUNTIFS(Transaksi!B:B,">="&$tAwal,Transaksi!B:B,"<="&$tAkhir,Transaksi!D:D,"$safe",Transaksi!K:K,"ACTIVE")&" trx"');
      }
      gap();
    }

    sec('▌ SEPANJANG WAKTU (TOTAL HISTORIS)');
    kv('Total Omzet (ACTIVE)', 'SUMIF(Transaksi!K:K,"ACTIVE",Transaksi!J:J)');
    kv('Total Transaksi Tercatat', 'COUNTA(Transaksi!A2:A)', bfmt: 'int');
    kv('Transaksi Dibatalkan (VOID)', 'COUNTIF(Transaksi!K:K,"VOID")', bfmt: 'int');
    kv('Tingkat Pembatalan', 'IFERROR(COUNTIF(Transaksi!K:K,"VOID")/COUNTA(Transaksi!A2:A),0)', bfmt: 'pct');
    gap();

    // TOP 5 MENU TERLARIS
    sec('▌ TOP 5 MENU TERLARIS (SEMUA WAKTU)');
    kv('Lihat 5 terlaris di bawah ↓',
      'IFERROR(QUERY(Transaksi_Item!A2:F,"SELECT B, SUM(D) WHERE A STARTS WITH \'TRX-\' GROUP BY B LABEL SUM(D) \'Qty\' ORDER BY SUM(D) DESC LIMIT 5",0),"belum ada data")',
      bfmt: 'int', note: 'menu + total qty terjual');
    gap();

    // JAM SIBUK — omzet per jam (07-23) untuk periode terpilih.
    sec('▌ JAM SIBUK (PERIODE TERPILIH)');
    for (int jam = 7; jam <= 23; jam++) {
      final jamStr = jam.toString().padLeft(2, '0');
      kv('$jamStr:00 - ${((jam + 1) % 24).toString().padLeft(2, '0')}:00',
        'SUMPRODUCT((Transaksi!B2:B>=$tAwal)*(Transaksi!B2:B<=$tAkhir)*(HOUR(Transaksi!C2:C)=$jam)*(Transaksi!K2:K="ACTIVE")*Transaksi!J2:J)',
        bfmt: 'rp', note: '');
    }
    gap();

    // AUDIT VOID
    sec('▌ AUDIT VOID (PERIODE TERPILIH)');
    kv('Jumlah VOID', 'COUNTIFS(Transaksi!B:B,">="&$tAwal,Transaksi!B:B,"<="&$tAkhir,Transaksi!K:K,"VOID")', bfmt: 'int');
    kv('Nilai VOID', 'SUMIFS(Transaksi!J:J,Transaksi!B:B,">="&$tAwal,Transaksi!B:B,"<="&$tAkhir,Transaksi!K:K,"VOID")', note: 'estimasi nilai');
    gap();

    sec('▌ KATALOG & MASTER DATA');
    kv('Menu Aktif', 'COUNTIF(Menu_Resep!E2:E,1)', bfmt: 'int', note: 'aktif = 1');
    kv('Voucher Aktif', 'COUNTIF(Voucher!D2:D,1)', bfmt: 'int');
    kv('Kehadiran Staf (Periode Terpilih)', 'COUNTIFS(Absensi!A:A,">="&$tAwal,Absensi!A:A,"<="&$tAkhir)', bfmt: 'int', note: 'dari tab Absensi');

    // Tabel mini di kolom E-G untuk chart: 7 hari terakhir (tanggal × omzet).
    final values7d = <List<Object?>>[];
    for (int i = 6; i >= 0; i--) {
      final dLabel = 'TEXT(TODAY()-$i,"yyyy-mm-dd")';
      values7d.add([
        '=TEXT(TODAY()-$i,"dd/mm")',
        '=SUMIFS(Transaksi!J:J,Transaksi!B:B,$dLabel,Transaksi!K:K,"ACTIVE")',
      ]);
    }

    // Bersihkan lalu tulis nilai.
    try {
      await _api!.spreadsheets.values.clear(gs.ClearValuesRequest(), id, "'Dashboard'!A1:C250");
    } catch (_) {}
    await _api!.spreadsheets.values.update(
      gs.ValueRange(values: values), id, "'Dashboard'!A1", valueInputOption: 'USER_ENTERED');

    // Tulis tabel 7 hari terakhir di kolom E-F (untuk chart).
    try {
      await _api!.spreadsheets.values.clear(gs.ClearValuesRequest(), id, "'Dashboard'!E1:F10");
      await _api!.spreadsheets.values.update(
        gs.ValueRange(values: [
          ['Tanggal', 'Omzet'],
          ...values7d,
        ]),
        id, "'Dashboard'!E1", valueInputOption: 'USER_ENTERED');
    } catch (e) {
      debugPrint('Tabel 7 hari gagal: $e');
    }

    // Format biar josjis (judul, seksi, dropdown B3, currency, persen, lebar kolom).
    try {
      final sid = await _sheetId(id, 'Dashboard');
      if (sid != null) await _formatDashboard(id, sid, values.length, sectionRows, rpRows, pctB, pctC);
    } catch (e) {
      debugPrint('Format dashboard gagal: $e');
    }
    debugPrint('📊 Dashboard diperbarui (interaktif filter dropdown, rumus live).');

    // Tambah chart native (bar/pie) — idempotent: hapus chart lama dulu.
    try {
      await addDashboardCharts(id, methods: methods);
    } catch (e) {
      debugPrint('Chart dashboard gagal: $e');
    }
  }


  /// Tambah 3 chart native di tab Dashboard: (1) bar omzet 7 hari,
  /// (2) pie metode pembayaran hari ini, (3) bar jam sibuk.
  /// Idempotent: hapus semua embedded object (chart) lama dulu supaya tak numpuk.
  Future<void> addDashboardCharts(String id, {List<String> methods = const ['Tunai', 'QRIS', 'Transfer']}) async {
    if (_api == null) return;
    final sid = await _sheetId(id, 'Dashboard');
    if (sid == null) return;

    // 1. Ambil daftar chart lama → hapus semua.
    final reqs = <gs.Request>[];
    final ss = await _api!.spreadsheets.get(id);
    final dashSheet = (ss.sheets ?? []).firstWhere(
      (s) => s.properties?.sheetId == sid,
      orElse: () => gs.Sheet(),
    );
    final existingCharts = dashSheet.charts ?? <gs.EmbeddedChart>[];
    for (final c in existingCharts) {
      if (c.chartId != null) {
        reqs.add(gs.Request(deleteEmbeddedObject: gs.DeleteEmbeddedObjectRequest(objectId: c.chartId)));
      }
    }

    // Helper: ChartData dari range A1-notation (di tab Dashboard sendiri).
    gs.ChartData dataOf(String rangeA1) => gs.ChartData(
          sourceRange: gs.ChartSourceRange(
            sources: [_gridRangeFromA1(sid, rangeA1)],
          ),
        );

    // --- CHART 1: Bar omzet 7 hari terakhir (sumber: E1:F8 tabel mini) ---
    reqs.add(gs.Request(addChart: gs.AddChartRequest(chart: gs.EmbeddedChart(
      position: gs.EmbeddedObjectPosition(
        overlayPosition: gs.OverlayPosition(
          anchorCell: gs.GridCoordinate(sheetId: sid, rowIndex: 0, columnIndex: 6),
          widthPixels: 380,
          heightPixels: 220,
        ),
      ),
      spec: gs.ChartSpec(
        title: 'Omzet 7 Hari Terakhir',
        basicChart: gs.BasicChartSpec(
          chartType: 'COLUMN',
          legendPosition: 'NO_LEGEND',
          headerCount: 1,
          domains: [gs.BasicChartDomain(domain: dataOf('Dashboard!E1:E8'))],
          series: [gs.BasicChartSeries(series: dataOf('Dashboard!F1:F8'), targetAxis: 'LEFT_AXIS')],
          axis: [
            gs.BasicChartAxis(position: 'BOTTOM_AXIS', title: 'Tanggal'),
            gs.BasicChartAxis(position: 'LEFT_AXIS', title: 'Omzet'),
          ],
        ),
      ),
    ))));

    // --- CHART 2: Pie metode pembayaran (dinamis dari Setup, pakai filter periode) ---
    // Sumber: tabel kecil H1:I(n) (label metode + omzet) — ditulis dulu.
    final pieRows = <List<Object?>>[['Metode', 'Omzet']];
    for (final m in methods) {
      pieRows.add([m, '=SUMIFS(Transaksi!J:J,Transaksi!B:B,">="&\$C\$4,Transaksi!B:B,"<="&\$B\$5,Transaksi!F:F,"$m",Transaksi!K:K,"ACTIVE")']);
    }
    final pieN = pieRows.length; // header + n metode
    try {
      await _api!.spreadsheets.values.clear(gs.ClearValuesRequest(), id, "'Dashboard'!H1:I50");
      await _api!.spreadsheets.values.update(
        gs.ValueRange(values: pieRows),
        id, "'Dashboard'!H1", valueInputOption: 'USER_ENTERED',
      );
    } catch (e) {
      debugPrint('Tabel metode gagal: $e');
    }
    final pieEnd = pieN; // baris terakhir (1-based)
    reqs.add(gs.Request(addChart: gs.AddChartRequest(chart: gs.EmbeddedChart(
      position: gs.EmbeddedObjectPosition(
        overlayPosition: gs.OverlayPosition(
          anchorCell: gs.GridCoordinate(sheetId: sid, rowIndex: 12, columnIndex: 6),
          widthPixels: 380,
          heightPixels: 220,
        ),
      ),
      spec: gs.ChartSpec(
        title: 'Metode Pembayaran (Periode Terpilih)',
        pieChart: gs.PieChartSpec(
          domain: dataOf("Dashboard!H1:H$pieEnd"),
          series: dataOf("Dashboard!I1:I$pieEnd"),
          legendPosition: 'BOTTOM_LEGEND',
        ),
      ),
    ))));

    // --- CHART 3: Bar jam sibuk hari ini (omzet per jam) ---
    // Sumber: tabel kecil K1:L18 (label jam 07-23 + omzet) — ditulis dulu.
    final jamRows = <List<Object?>>[['Jam', 'Omzet']];
    for (int jam = 7; jam <= 23; jam++) {
      jamRows.add([
        '$jam:00',
        '=SUMPRODUCT((TEXT(Transaksi!C2:C,"yyyy-mm-dd")=TEXT(TODAY(),"yyyy-mm-dd"))*(HOUR(Transaksi!C2:C)=$jam)*(Transaksi!K2:K="ACTIVE")*Transaksi!J2:J)',
      ]);
    }
    try {
      await _api!.spreadsheets.values.update(
        gs.ValueRange(values: jamRows),
        id, "'Dashboard'!K1", valueInputOption: 'USER_ENTERED',
      );
    } catch (e) {
      debugPrint('Tabel jam sibuk gagal: $e');
    }
    reqs.add(gs.Request(addChart: gs.AddChartRequest(chart: gs.EmbeddedChart(
      position: gs.EmbeddedObjectPosition(
        overlayPosition: gs.OverlayPosition(
          anchorCell: gs.GridCoordinate(sheetId: sid, rowIndex: 24, columnIndex: 6),
          widthPixels: 380,
          heightPixels: 260,
        ),
      ),
      spec: gs.ChartSpec(
        title: 'Jam Sibuk — Hari Ini',
        basicChart: gs.BasicChartSpec(
          chartType: 'BAR',
          legendPosition: 'NO_LEGEND',
          headerCount: 1,
          domains: [gs.BasicChartDomain(domain: dataOf('Dashboard!K1:K18'))],
          series: [gs.BasicChartSeries(series: dataOf('Dashboard!L1:L18'), targetAxis: 'LEFT_AXIS')],
          axis: [
            gs.BasicChartAxis(position: 'BOTTOM_AXIS', title: 'Omzet'),
            gs.BasicChartAxis(position: 'LEFT_AXIS', title: 'Jam'),
          ],
        ),
      ),
    ))));


    if (reqs.isNotEmpty) {
      await _api!.spreadsheets.batchUpdate(
        gs.BatchUpdateSpreadsheetRequest(requests: reqs), id);
    }
    debugPrint('📊 3 chart dashboard ditambahkan.');
  }

  /// Konversi range A1 sederhana (1 area, 1 sheet) → GridRange.
  /// Mendukung format "Sheet!A1:B8". Implementasi minimal sesuai kebutuhan chart.
  gs.GridRange _gridRangeFromA1(int sheetId, String a1) {
    // Pisahkan nama sheet (sebelum '!').
    String range;
    final bang = a1.indexOf('!');
    range = bang >= 0 ? a1.substring(bang + 1) : a1;

    final colon = range.indexOf(':');
    final startA1 = colon >= 0 ? range.substring(0, colon) : range;
    final endA1 = colon >= 0 ? range.substring(colon + 1) : range;

    final sc = _colNum(startA1);
    final sr = _rowNum(startA1);
    final ec = _colNum(endA1);
    final er = _rowNum(endA1);

    return gs.GridRange(
      sheetId: sheetId,
      startColumnIndex: sc,
      startRowIndex: sr,
      endColumnIndex: ec + 1,
      endRowIndex: er + 1,
    );
  }

  /// Ekstrak nomor kolom (0-based) dari A1 cell like "A1", "AB12".
  int _colNum(String cell) {
    var col = 0;
    var i = 0;
    while (i < cell.length && RegExp(r'[A-Za-z]').hasMatch(cell[i])) {
      col = col * 26 + (cell[i].toUpperCase().codeUnitAt(0) - 64);
      i++;
    }
    return col - 1; // 0-based
  }

  /// Ekstrak nomor baris (0-based) dari A1 cell.
  int _rowNum(String cell) {
    var num = '';
    for (final ch in cell.split('')) {
      if (RegExp(r'\d').hasMatch(ch)) num += ch;
    }
    return (int.tryParse(num) ?? 1) - 1; // 0-based
  }

  /// Ambil nama karyawan aktif (buat baris kinerja kasir dinamis).
  Future<List<String>> _activeEmployeeNames() async {
    final list = await DbHelper().getEmployees();
    return list.where((e) => e['active'] == 1).map((e) => (e['name'] ?? '').toString()).where((n) => n.isNotEmpty).toList();
  }

  Future<int?> _sheetId(String id, String title) async {
    final ss = await _api!.spreadsheets.get(id);
    for (final s in ss.sheets ?? <gs.Sheet>[]) {
      if (s.properties?.title == title) return s.properties?.sheetId;
    }
    return null;
  }

  gs.Color _rgb(int hex) => gs.Color(
        red: ((hex >> 16) & 0xFF) / 255.0,
        green: ((hex >> 8) & 0xFF) / 255.0,
        blue: (hex & 0xFF) / 255.0,
      );

  Future<void> _formatDashboard(String id, int sid, int nRows, List<int> sectionRows,
      List<int> rpRows, List<int> pctB, List<int> pctC) async {
    gs.GridRange range(int rStart, int rEnd, int cStart, int cEnd) => gs.GridRange(
        sheetId: sid, startRowIndex: rStart, endRowIndex: rEnd, startColumnIndex: cStart, endColumnIndex: cEnd);
    final reqs = <gs.Request>[];

    // Judul: merge A1:C1 + besar bold coklat.
    reqs.add(gs.Request(mergeCells: gs.MergeCellsRequest(range: range(0, 1, 0, 3), mergeType: 'MERGE_ALL')));
    reqs.add(gs.Request(repeatCell: gs.RepeatCellRequest(
      range: range(0, 1, 0, 3),
      cell: gs.CellData(userEnteredFormat: gs.CellFormat(
        textFormat: gs.TextFormat(bold: true, fontSize: 15, foregroundColor: _rgb(0x3B2A20)))),
      fields: 'userEnteredFormat.textFormat',
    )));

    // Baris seksi: teks putih di atas coklat, bold.
    for (final sr in sectionRows) {
      reqs.add(gs.Request(mergeCells: gs.MergeCellsRequest(range: range(sr, sr + 1, 0, 3), mergeType: 'MERGE_ALL')));
      reqs.add(gs.Request(repeatCell: gs.RepeatCellRequest(
        range: range(sr, sr + 1, 0, 3),
        cell: gs.CellData(userEnteredFormat: gs.CellFormat(
          backgroundColor: _rgb(0x7A5540),
          textFormat: gs.TextFormat(bold: true, foregroundColor: _rgb(0xFFFFFF)))),
        fields: 'userEnteredFormat(backgroundColor,textFormat)',
      )));
    }

    // Currency di kolom B.
    for (final rr in rpRows) {
      reqs.add(gs.Request(repeatCell: gs.RepeatCellRequest(
        range: range(rr, rr + 1, 1, 2),
        cell: gs.CellData(userEnteredFormat: gs.CellFormat(
          numberFormat: gs.NumberFormat(type: 'CURRENCY', pattern: '"Rp"#,##0'),
          textFormat: gs.TextFormat(bold: true))),
        fields: 'userEnteredFormat(numberFormat,textFormat)',
      )));
    }
    // Persen di kolom B.
    for (final rr in pctB) {
      reqs.add(gs.Request(repeatCell: gs.RepeatCellRequest(
        range: range(rr, rr + 1, 1, 2),
        cell: gs.CellData(userEnteredFormat: gs.CellFormat(numberFormat: gs.NumberFormat(type: 'PERCENT', pattern: '0.0%'))),
        fields: 'userEnteredFormat.numberFormat',
      )));
    }
    // Persen di kolom C.
    for (final rr in pctC) {
      reqs.add(gs.Request(repeatCell: gs.RepeatCellRequest(
        range: range(rr, rr + 1, 2, 3),
        cell: gs.CellData(userEnteredFormat: gs.CellFormat(numberFormat: gs.NumberFormat(type: 'PERCENT', pattern: '0.0%'))),
        fields: 'userEnteredFormat.numberFormat',
      )));
    }

    // Data Validation Dropdown di B3 (Pilihan Periode Filter)
    reqs.add(gs.Request(
      setDataValidation: gs.SetDataValidationRequest(
        range: range(2, 3, 1, 2), // Sel B3 (row index 2, col index 1)
        rule: gs.DataValidationRule(
          condition: gs.BooleanCondition(
            type: 'ONE_OF_LIST',
            values: [
              gs.ConditionValue(userEnteredValue: 'Hari Ini'),
              gs.ConditionValue(userEnteredValue: 'Kemarin'),
              gs.ConditionValue(userEnteredValue: '7 Hari Terakhir'),
              gs.ConditionValue(userEnteredValue: '30 Hari Terakhir'),
              gs.ConditionValue(userEnteredValue: 'Bulan Ini'),
              gs.ConditionValue(userEnteredValue: 'Bulan Lalu'),
              gs.ConditionValue(userEnteredValue: '3 Bulan Terakhir'),
              gs.ConditionValue(userEnteredValue: 'Sepanjang Waktu'),
            ],
          ),
          showCustomUi: true,
          strict: false,
        ),
      ),
    ));

    // Styling Khusus Dropdown B3 (tombol filter hijau lembut)
    reqs.add(gs.Request(repeatCell: gs.RepeatCellRequest(
      range: range(2, 3, 1, 2),
      cell: gs.CellData(userEnteredFormat: gs.CellFormat(
        backgroundColor: _rgb(0xE6F4EA),
        horizontalAlignment: 'CENTER',
        textFormat: gs.TextFormat(bold: true, fontSize: 11, foregroundColor: _rgb(0x137333)))),
      fields: 'userEnteredFormat(backgroundColor,horizontalAlignment,textFormat)',
    )));

    // Styling Baris Filter A3:C5 (banner abu-abu rapi)
    reqs.add(gs.Request(repeatCell: gs.RepeatCellRequest(
      range: range(2, 3, 0, 1), // A3
      cell: gs.CellData(userEnteredFormat: gs.CellFormat(
        textFormat: gs.TextFormat(bold: true, fontSize: 11, foregroundColor: _rgb(0x3B2A20)))),
      fields: 'userEnteredFormat.textFormat',
    )));
    reqs.add(gs.Request(repeatCell: gs.RepeatCellRequest(
      range: range(3, 5, 0, 3), // A4:C5 info formula tgl
      cell: gs.CellData(userEnteredFormat: gs.CellFormat(
        backgroundColor: _rgb(0xF8F9FA),
        textFormat: gs.TextFormat(italic: true, fontSize: 9, foregroundColor: _rgb(0x5F6368)))),
      fields: 'userEnteredFormat(backgroundColor,textFormat)',
    )));

    // Lebar kolom A/B/C.
    void colW(int col, int px) => reqs.add(gs.Request(updateDimensionProperties: gs.UpdateDimensionPropertiesRequest(
          range: gs.DimensionRange(sheetId: sid, dimension: 'COLUMNS', startIndex: col, endIndex: col + 1),
          properties: gs.DimensionProperties(pixelSize: px),
          fields: 'pixelSize',
        )));
    colW(0, 240); colW(1, 150); colW(2, 240);

    // Freeze 2 baris atas.
    reqs.add(gs.Request(updateSheetProperties: gs.UpdateSheetPropertiesRequest(
      properties: gs.SheetProperties(sheetId: sid, gridProperties: gs.GridProperties(frozenRowCount: 2)),
      fields: 'gridProperties.frozenRowCount',
    )));

    await _api!.spreadsheets.batchUpdate(gs.BatchUpdateSpreadsheetRequest(requests: reqs), id);
  }


  /// Tulis tab Rekap_Bulanan: 1 baris per bulan (auto-grow dari data Transaksi).
  /// Tiap baris berisi rumus SUMIFS/COUNTIFS ke tab Transaksi & Kas bulan tsb.
  /// Owner bisa lihat semua bulan lampau (data tak pernah dihapus).
  Future<void> pushRekapBulanan(String id) async {
    if (_api == null) return;
    // Baca metode pembayaran dinamis dari Setup.
    final methodsRaw = await _pullSetupValue(id, 'payment_methods');
    final methods = (methodsRaw ?? 'Tunai,QRIS,Transfer')
        .split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

    // Header dinamis: bulan, omzet, transaksi, rata_rata, <metode1>, <metode2>, ..., diskon, modal, laba, kas_masuk, kas_keluar.
    final header = <Object?>['bulan', 'omzet', 'transaksi', 'rata_rata', ...methods, 'diskon', 'modal', 'laba', 'kas_masuk', 'kas_keluar'];

    // Ambil semua hari_usaha unik dari tab Transaksi kolom B.
    final Set<String> bulanSet = {};
    try {
      final res = await _api!.spreadsheets.values.get(id, "'Transaksi'!B2:B");
      for (final row in res.values ?? <List<Object?>>[]) {
        if (row.isEmpty) continue;
        final v = row[0].toString();
        if (v.length >= 7) bulanSet.add(v.substring(0, 7)); // "YYYY-MM"
      }
    } catch (e) {
      debugPrint('Baca bulan unik gagal: $e');
    }
    final bulans = bulanSet.toList()..sort();

    final values = <List<Object?>>[header];
    for (final b in bulans) {
      final bm = '$b-*'; // wildcard bulan, mis. "2026-08-*"
      final row = <Object?>[
        b, // bulan (YYYY-MM)
        '=SUMIFS(Transaksi!J:J,Transaksi!B:B,"$bm",Transaksi!K:K,"ACTIVE")', // omzet
        '=COUNTIFS(Transaksi!B:B,"$bm",Transaksi!K:K,"ACTIVE")', // transaksi
        '=IFERROR(SUMIFS(Transaksi!J:J,Transaksi!B:B,"$bm",Transaksi!K:K,"ACTIVE")/COUNTIFS(Transaksi!B:B,"$bm",Transaksi!K:K,"ACTIVE"),0)', // rata_rata
      ];
      // Kolom per metode (dinamis).
      for (final m in methods) {
        row.add('=SUMIFS(Transaksi!J:J,Transaksi!B:B,"$bm",Transaksi!F:F,"$m",Transaksi!K:K,"ACTIVE")');
      }
      row.addAll([
        '=SUMIFS(Transaksi!H:H,Transaksi!B:B,"$bm",Transaksi!K:K,"ACTIVE")', // diskon
        '=SUMIFS(Transaksi!L:L,Transaksi!B:B,"$bm",Transaksi!K:K,"ACTIVE")', // modal (kolom L)
        '=SUMIFS(Transaksi!M:M,Transaksi!B:B,"$bm",Transaksi!K:K,"ACTIVE")', // laba (kolom M)
        '=SUMIFS(Kas!C:C,Kas!A:A,"$bm*",Kas!B:B,"MASUK")', // kas_masuk
        '=SUMIFS(Kas!C:C,Kas!A:A,"$bm*",Kas!B:B,"KELUAR")', // kas_keluar
      ]);
      values.add(row);
    }

    final lastCol = _colLetter(header.length - 1);
    // Tulis ulang tabel (clear dulu lalu update).
    try {
      await _api!.spreadsheets.values.clear(gs.ClearValuesRequest(), id, "'Rekap_Bulanan'!A1:${lastCol}200");
    } catch (_) {}
    await _api!.spreadsheets.values.update(
      gs.ValueRange(values: values),
      id,
      "'Rekap_Bulanan'!A1",
      valueInputOption: 'USER_ENTERED',
    );

    // Format: freeze header + currency kolom B,D,E,F,G,H,I,J,K,L.
    try {
      final sid = await _sheetId(id, 'Rekap_Bulanan');
      if (sid != null) await _formatRekapBulanan(id, sid, header.length);
    } catch (e) {
      debugPrint('Format Rekap_Bulanan gagal: $e');
    }
    debugPrint('📅 Rekap_Bulanan diperbarui: ${bulans.length} bulan.');
  }

  /// Format tab Rekap_Bulanan: freeze header, lebar kolom, currency.
  Future<void> _formatRekapBulanan(String id, int sid, int nCols) async {
    final reqs = <gs.Request>[];
    // Header bold + background coklat.
    reqs.add(gs.Request(repeatCell: gs.RepeatCellRequest(
      range: gs.GridRange(sheetId: sid, startRowIndex: 0, endRowIndex: 1, startColumnIndex: 0, endColumnIndex: nCols),
      cell: gs.CellData(userEnteredFormat: gs.CellFormat(
          backgroundColor: _rgb(0x7A5540),
          textFormat: gs.TextFormat(bold: true, foregroundColor: _rgb(0xFFFFFF)))),
      fields: 'userEnteredFormat(backgroundColor,textFormat)',
    )));
    // Currency semua kolom B onward KECUALI "transaksi" (index 2 = count).
    for (int c = 1; c < nCols; c++) {
      if (c == 2) continue; // skip kolom transaksi (count)
      reqs.add(gs.Request(repeatCell: gs.RepeatCellRequest(
        range: gs.GridRange(sheetId: sid, startRowIndex: 1, startColumnIndex: c, endColumnIndex: c + 1),
        cell: gs.CellData(userEnteredFormat: gs.CellFormat(
            numberFormat: gs.NumberFormat(type: 'CURRENCY', pattern: '"Rp"#,##0'))),
        fields: 'userEnteredFormat.numberFormat',
      )));
    }
    // Freeze header.
    reqs.add(gs.Request(updateSheetProperties: gs.UpdateSheetPropertiesRequest(
      properties: gs.SheetProperties(sheetId: sid, gridProperties: gs.GridProperties(frozenRowCount: 1)),
      fields: 'gridProperties.frozenRowCount',
    )));
    await _api!.spreadsheets.batchUpdate(gs.BatchUpdateSpreadsheetRequest(requests: reqs), id);
  }

  /// Tulis tab Absensi_Matriks: tanggal × karyawan (1 kolom per orang).
  /// SEMUA BULAN yg ada datanya ditampilkan (bulan berjalan + bulan lampau),
  /// masing-masing satu block dgn header & baris TOTAL sendiri.
  /// Format presence-only: isi ✓ kalau hadir, kosong kalau tidak.
  /// Sumber: tab Absensi (kolom hadir = Y). Backward-compat: shift Pagi/Sore lama dihitung hadir.
  Future<void> pushAbsensiMatriks(String id) async {
    if (_api == null) return;
    final emps = await _activeEmployeeNames();
    final now = DateTime.now();
    final currYm = '${now.year}-${now.month.toString().padLeft(2, '0')}';

    // Kumpulkan semua bulan unik dari tab Absensi kolom A (YYYY-MM-DD).
    final bulanSet = <String>{currYm};
    try {
      final res = await _api!.spreadsheets.values.get(id, "'Absensi'!A2:A");
      for (final row in res.values ?? <List<Object?>>[]) {
        if (row.isEmpty) continue;
        final v = row[0].toString();
        if (v.length >= 7) bulanSet.add(v.substring(0, 7));
      }
    } catch (e) {
      debugPrint('Baca bulan absen gagal: $e');
    }
    final bulans = bulanSet.toList()..sort();

    final values = <List<Object?>>[];
    final totalRows = <int>[]; // index baris TOTAL (buAT format bold)

    for (final ym in bulans) {
      final parts = ym.split('-');
      final year = int.tryParse(parts[0]) ?? now.year;
      final month = int.tryParse(parts[1]) ?? now.month;
      final daysInMonth = DateTime(year, month + 1, 0).day;
      final namaBulan = _namaBulan(month);

      // Judul seksi bulan.
      values.add(['📅 $namaBulan $year', '', '', '', '', '']);
      values.add(['', '', '', '', '', '']);

      // Header: tgl | <Nama> | <Nama> | ...
      final header = <Object?>['tgl'];
      for (final name in emps) {
        header.add(name);
      }
      values.add(header);
      final headerRowIdx = values.length; // 1-based

      for (int d = 1; d <= daysInMonth; d++) {
        final dateStr = '$ym-${d.toString().padLeft(2, '0')}';
        final row = <Object?>[d];
        for (final name in emps) {
          // Tampilkan shift yg ada utk org+tgl ini (TEXTJOIN semua nilai unik,
          // exclude "Y"/"Hadir"/kosong backward-compat). Kalau kosong → sel kosong.
          row.add(
            '=IFERROR(TEXTJOIN(", ",TRUE,UNIQUE(FILTER(Absensi!C2:C,'
            '(Absensi!A2:A="$dateStr")*(Absensi!B2:B="$name")*(Absensi!C2:C<>"")*(Absensi!C2:C<>"Y")*(Absensi!C2:C<>"N")))),"")',
          );
        }
        values.add(row);
      }
      // Baris TOTAL hadir per karyawan (COUNTA kolom ✓) — range dinamis per block.
      final totalRow = <Object?>['TOTAL'];
      final lastRowIdx = values.length; // 1-based, baris terakhir tgl
      for (int i = 0; i < emps.length; i++) {
        final col = _colLetter(1 + i);
        totalRow.add('=COUNTA($col$headerRowIdx:$col$lastRowIdx)');
      }
      values.add(totalRow);
      totalRows.add(values.length); // 1-based index baris TOTAL

      // Spasi antar bulan.
      values.add(['', '', '', '', '', '']);
      values.add(['', '', '', '', '', '']);
    }

    try {
      await _api!.spreadsheets.values.clear(
          gs.ClearValuesRequest(), id, "'Absensi_Matriks'!A1:ZZ500");
    } catch (_) {}
    await _api!.spreadsheets.values.update(
      gs.ValueRange(values: values),
      id,
      "'Absensi_Matriks'!A1",
      valueInputOption: 'USER_ENTERED',
    );

    // Format: judul seksi + baris TOTAL bold, freeze baris atas, lebar kolom tgl.
    try {
      final sid = await _sheetId(id, 'Absensi_Matriks');
      if (sid != null) await _formatAbsensiMatriks(id, sid, values.length, values.first.length, totalRows);
    } catch (e) {
      debugPrint('Format Absensi_Matriks gagal: $e');
    }
    debugPrint('🧮 Absensi_Matriks diperbarui: ${bulans.length} bulan × ${emps.length} karyawan.');
  }

  /// Nama bulan Indonesia.
  String _namaBulan(int m) {
    const names = [
      '', 'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
      'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
    ];
    return (m >= 1 && m <= 12) ? names[m] : '';
  }

  /// Konversi index kolom (0-based) → huruf kolom Sheet (A, B, …, Z, AA, …).
  String _colLetter(int index0) {
    var n = index0;
    var letters = '';
    while (n >= 0) {
      letters = String.fromCharCode((n % 26) + 65) + letters;
      n = (n ~/ 26) - 1;
    }
    return letters;
  }

  /// Format tab Absensi_Matriks: header & total bold, freeze, lebar kolom tgl.
  Future<void> _formatAbsensiMatriks(String id, int sid, int nRows, int nCols, List<int> totalRows) async {
    final reqs = <gs.Request>[];
    final lastCol = _colLetter(nCols - 1);
    // Header bold + background coklat.
    reqs.add(gs.Request(repeatCell: gs.RepeatCellRequest(
      range: gs.GridRange(sheetId: sid, startRowIndex: 0, endRowIndex: 1, startColumnIndex: 0, endColumnIndex: nCols),
      cell: gs.CellData(userEnteredFormat: gs.CellFormat(
          backgroundColor: _rgb(0x7A5540),
          textFormat: gs.TextFormat(bold: true, foregroundColor: _rgb(0xFFFFFF)))),
      fields: 'userEnteredFormat(backgroundColor,textFormat)',
    )));
    // Baris TOTAL bold.
    for (final tr in totalRows) {
      reqs.add(gs.Request(repeatCell: gs.RepeatCellRequest(
        range: gs.GridRange(sheetId: sid, startRowIndex: tr - 1, endRowIndex: tr, startColumnIndex: 0, endColumnIndex: nCols),
        cell: gs.CellData(userEnteredFormat: gs.CellFormat(
            backgroundColor: _rgb(0xF5F3F0),
            textFormat: gs.TextFormat(bold: true))),
        fields: 'userEnteredFormat(backgroundColor,textFormat)',
      )));
    }
    // Freeze baris header + kolom tgl.
    reqs.add(gs.Request(updateSheetProperties: gs.UpdateSheetPropertiesRequest(
      properties: gs.SheetProperties(sheetId: sid, gridProperties: gs.GridProperties(frozenRowCount: 1, frozenColumnCount: 1)),
      fields: 'gridProperties.frozenRowCount,gridProperties.frozenColumnCount',
    )));
    // Lebar kolom tgl.
    reqs.add(gs.Request(updateDimensionProperties: gs.UpdateDimensionPropertiesRequest(
      range: gs.DimensionRange(sheetId: sid, dimension: 'COLUMNS', startIndex: 0, endIndex: 1),
      properties: gs.DimensionProperties(pixelSize: 60),
      fields: 'pixelSize',
    )));
    // Suppress unused warning.
    // ignore: unused_local_variable
    final _ = lastCol;
    await _api!.spreadsheets.batchUpdate(gs.BatchUpdateSpreadsheetRequest(requests: reqs), id);
  }


  /// Tambah 1 baris transaksi ke tab Transaksi (append).
  Future<void> appendTransaction(String id, Map<String, dynamic> t) async {
    if (_api == null) return;
    // modal (cost_total) & laba = total − modal. Dikirim supaya Rekap_Bulanan akurat.
    final int modal = (t['cost_total'] as num?)?.toInt() ?? 0;
    final int total = (t['total_amount'] as num?)?.toInt() ?? 0;
    final int laba = total - modal;
    await _api!.spreadsheets.values.append(
      gs.ValueRange(values: [
        [
          t['code'], t['business_date'], t['created_at'], t['cashier_name'],
          t['order_type'], t['payment_method'], t['subtotal'], t['discount_amount'],
          t['voucher_name'] ?? '', t['total_amount'], t['status'] ?? 'ACTIVE',
          modal, laba,
        ]
      ]),
      id,
      "'Transaksi'!A1",
      valueInputOption: 'RAW',
    );
  }

  /// Append baris log voucher ke tab Voucher_Log saat transaksi pakai voucher.
  /// Param: t = map transaksi (ambil code, business_date, cashier_name, voucher_name,
  /// discount_amount, subtotal, total_amount). voucherType = 'PERCENT'/'FIXED'.
  Future<void> appendVoucherUsage(String id, Map<String, dynamic> t, String voucherType) async {
    if (_api == null) return;
    final voucher = (t['voucher_name'] ?? '').toString();
    if (voucher.isEmpty) return; // ga pakai voucher, skip
    await _api!.spreadsheets.values.append(
      gs.ValueRange(values: [
        [
          t['code'], t['business_date'], t['cashier_name'], voucher, voucherType,
          t['discount_amount'] ?? 0, t['subtotal'] ?? 0, t['total_amount'] ?? 0,
        ]
      ]),
      id, "'Voucher_Log'!A1",
      valueInputOption: 'RAW',
    );
  }

  /// Tambah baris item transaksi ke tab Transaksi_Item (append).
  /// Dipakai untuk laporan "menu terlaris" via QUERY di Dashboard.
  Future<void> appendTransactionItems(String id, String trxCode, List<Map<String, dynamic>> items) async {
    if (_api == null || items.isEmpty) return;
    final rows = items.map((it) => [
          trxCode,
          it['name'] ?? '',
          it['variants'] ?? '',
          it['qty'] ?? 0,
          it['price'] ?? 0,
          it['subtotal'] ?? 0,
        ]).toList();
    await _api!.spreadsheets.values.append(
      gs.ValueRange(values: rows),
      id,
      "'Transaksi_Item'!A1",
      valueInputOption: 'RAW',
    );
  }

  /// Catat penambahan stok ke tab terpisah Restok_Log (tanpa mengganggu data utama).
  Future<void> logRestokToSheet(String id, String packagingName, int addedQty, String unit, int finalStock) async {
    if (_api == null) return;
    await _api!.spreadsheets.values.append(
      gs.ValueRange(values: [
        [
          DateTime.now().toIso8601String(),
          packagingName,
          addedQty,
          unit,
          finalStock,
        ]
      ]),
      id,
      "'Restok_Log'!A1",
      valueInputOption: 'RAW',
    );
  }

  /// Export / append 1 baris absensi ke tab Absensi di Google Sheet.
  /// Kolom: hari_usaha, karyawan, hadir(=nama shift), waktu.
  /// Shift kosong ('') = batal/tidak hadir.
  Future<void> appendAttendance(String id, String businessDate, String employeeName, String shift) async {
    if (_api == null) return;
    await _api!.spreadsheets.values.append(
      gs.ValueRange(values: [
        [
          businessDate,
          employeeName,
          shift,
          DateTime.now().toIso8601String(),
        ]
      ]),
      id,
      "'Absensi'!A1",
      valueInputOption: 'RAW',
    );
  }

  /// Export / append 1 baris kas (MASUK/KELUAR) ke tab Kas di Google Sheet.
  Future<void> appendKas(String id, String businessDate, String type, int amount,
      {String category = '', String note = '', String by = ''}) async {
    if (_api == null) return;
    await _api!.spreadsheets.values.append(
      gs.ValueRange(values: [
        [
          businessDate,
          type, // MASUK / KELUAR
          amount,
          category,
          note,
          by,
          DateTime.now().toIso8601String(),
        ]
      ]),
      id,
      "'Kas'!A1",
      valueInputOption: 'RAW',
    );
  }

  /// Tarik harga/modal/aktif/urutan menu dari Sheet → update SQLite (edit Sheet → app berubah).
  Future<int> pullMenuFromSheet(String id) async {
    if (_api == null) return 0;
    final res = await _api!.spreadsheets.values.get(id, "'Menu_Resep'!A2:F");
    final rows = res.values ?? [];
    final db = await DbHelper().database;
    int updated = 0;
    for (final r in rows) {
      if (r.isEmpty) continue;
      final name = r[0].toString();
      if (name.isEmpty) continue;
      final price = r.length > 2 ? int.tryParse(r[2].toString()) : null;
      final cost = r.length > 3 ? int.tryParse(r[3].toString()) : null;
      final active = r.length > 4 ? (r[4].toString() == '1' || r[4].toString().toLowerCase() == 'true') : null;
      final sortOrder = r.length > 5 ? int.tryParse(r[5].toString()) : null;
      final data = <String, Object?>{};
      if (price != null) data['price'] = price;
      if (cost != null) data['cost'] = cost;
      if (active != null) data['active'] = active ? 1 : 0;
      if (sortOrder != null) data['sort_order'] = sortOrder;
      if (data.isNotEmpty) {
        updated += await db.update('menu_items', data, where: 'name = ?', whereArgs: [name]);
      }
    }
    debugPrint('⬇️ Pull dari Sheet: $updated menu diperbarui.');
    return updated;
  }

  /// Push daftar karyawan dari app → tab Karyawan (merge: nama ada → skip, ga ada → tambah).
  /// Setelah itu Sheet jadi source of truth daftar karyawan.
  Future<void> pushEmployees(String id) async {
    if (_api == null) return;
    final emps = await _activeEmployeeNames();
    final rows = <List<Object?>>[_tabs['Karyawan']!];
    for (final name in emps) {
      rows.add([name, 1, '']);
    }
    try {
      await _api!.spreadsheets.values.clear(gs.ClearValuesRequest(), id, "'Karyawan'!A1:C200");
    } catch (_) {}
    await _api!.spreadsheets.values.update(
      gs.ValueRange(values: rows), id, "'Karyawan'!A1", valueInputOption: 'RAW',
    );
    debugPrint('👥 Karyawan terkirim ke Sheet: ${emps.length} orang.');
  }

  /// Tulis tab Menu_Terlaris: pivot qty & omzet per menu (sepanjang waktu + bulan ini).
  /// Sumber: tab Transaksi_Item (B=menu, D=qty, F=subtotal). Kode transaksi
  /// berformat TRX-YYYYMMDD-... jadi filter bulan via prefix "TRX-YYYYMM".
  Future<void> pushMenuTerlaris(String id) async {
    if (_api == null) return;
    final now = DateTime.now();
    final ym = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final prefixBulan = 'TRX-${ym.replaceAll('-', '')}'; // "TRX-202608"

    final header = _tabs['Menu_Terlaris']!;
    // QUERY 1: total qty & omzet per menu (sepanjang waktu), order by qty desc.
    // QUERY 2: qty & omzet bulan ini (filter kode diawali prefix bulan).
    final values = <List<Object?>>[header];
    // Tambah 1 baris QUERY array yg men-spill ke bawah: menu, sum(qty), sum(subtotal).
    values.add([
      '=IFERROR(QUERY(Transaksi_Item!B2:F,"SELECT B, SUM(D), SUM(F) WHERE B IS NOT NULL GROUP BY B LABEL SUM(D) \'\', SUM(F) \'\' ORDER BY SUM(D) DESC",0),"")',
      '', '', '', '',
    ]);
    // Tabel kedua di kolom E-G: top menu bulan ini.
    final bulanHeader = <Object?>[
      '=CONCATENATE("Top Menu Bulan ",TEXT(TODAY(),"MMMM yyyy"))',
      '', '',
    ];
    // Tulis header bulan di kolom E-G baris 1 (sejajar header utama).
    // Karena update Values tulis per range, kita tulis header utama dulu (di atas),
    // lalu tabel bulan terpisah di H1.

    // Tulis ulang: gunakan struktur 2 area. Area 1 (A:D) total sepanjang waktu,
    // Area 2 (F:I) bulan ini.
    final mainValues = <List<Object?>>[
      header,
      [
        '=IFERROR(QUERY(Transaksi_Item!B2:F,"SELECT B, SUM(D), SUM(F) WHERE B IS NOT NULL GROUP BY B LABEL SUM(D) \'\', SUM(F) \'\' ORDER BY SUM(D) DESC",0),"")',
        '', '', '',
      ],
    ];

    // Clear dulu area luas.
    try {
      await _api!.spreadsheets.values.clear(gs.ClearValuesRequest(), id, "'Menu_Terlaris'!A1:Z500");
    } catch (_) {}
    await _api!.spreadsheets.values.update(
      gs.ValueRange(values: mainValues),
      id, "'Menu_Terlaris'!A1",
      valueInputOption: 'USER_ENTERED',
    );

    // Tulis area bulan ini di kolom F1.
    final bulanValues = <List<Object?>>[
      ['Menu (Bulan $ym)', 'Qty', 'Omzet'],
      [
        '=IFERROR(QUERY(Transaksi_Item!A2:F,"SELECT B, SUM(D), SUM(F) WHERE A STARTS WITH \'$prefixBulan\' GROUP BY B LABEL SUM(D) \'\', SUM(F) \'\' ORDER BY SUM(D) DESC",0),"")',
        '', '',
      ],
    ];
    try {
      await _api!.spreadsheets.values.update(
        gs.ValueRange(values: bulanValues),
        id, "'Menu_Terlaris'!F1",
        valueInputOption: 'USER_ENTERED',
      );
    } catch (e) {
      debugPrint('Tabel bulan ini gagal: $e');
    }

    // Format currency kolom C (omzet total) & I (omzet bulan), freeze header.
    try {
      final sid = await _sheetId(id, 'Menu_Terlaris');
      if (sid != null) await _formatMenuTerlaris(id, sid);
    } catch (e) {
      debugPrint('Format Menu_Terlaris gagal: $e');
    }
    debugPrint('🏆 Menu_Terlaris diperbarui.');
    // Suppress unused.
    // ignore: unused_local_variable
    final _ = bulanHeader;
  }

  /// Format tab Menu_Terlaris: header bold, currency kolom C & I.
  Future<void> _formatMenuTerlaris(String id, int sid) async {
    final reqs = <gs.Request>[];
    // Header utama (A1:D1) bold + coklat.
    reqs.add(gs.Request(repeatCell: gs.RepeatCellRequest(
      range: gs.GridRange(sheetId: sid, startRowIndex: 0, endRowIndex: 1, startColumnIndex: 0, endColumnIndex: 4),
      cell: gs.CellData(userEnteredFormat: gs.CellFormat(
          backgroundColor: _rgb(0x7A5540),
          textFormat: gs.TextFormat(bold: true, foregroundColor: _rgb(0xFFFFFF)))),
      fields: 'userEnteredFormat(backgroundColor,textFormat)',
    )));
    // Header bulan (F1:H1) bold + hijau.
    reqs.add(gs.Request(repeatCell: gs.RepeatCellRequest(
      range: gs.GridRange(sheetId: sid, startRowIndex: 0, endRowIndex: 1, startColumnIndex: 5, endColumnIndex: 8),
      cell: gs.CellData(userEnteredFormat: gs.CellFormat(
          backgroundColor: _rgb(0x356A58),
          textFormat: gs.TextFormat(bold: true, foregroundColor: _rgb(0xFFFFFF)))),
      fields: 'userEnteredFormat(backgroundColor,textFormat)',
    )));
    // Currency omzet kolom C (index 2) & H (index 7).
    for (final c in [2, 7]) {
      reqs.add(gs.Request(repeatCell: gs.RepeatCellRequest(
        range: gs.GridRange(sheetId: sid, startRowIndex: 1, startColumnIndex: c, endColumnIndex: c + 1),
        cell: gs.CellData(userEnteredFormat: gs.CellFormat(
            numberFormat: gs.NumberFormat(type: 'CURRENCY', pattern: '"Rp"#,##0'))),
        fields: 'userEnteredFormat.numberFormat',
      )));
    }
    // Freeze header.
    reqs.add(gs.Request(updateSheetProperties: gs.UpdateSheetPropertiesRequest(
      properties: gs.SheetProperties(sheetId: sid, gridProperties: gs.GridProperties(frozenRowCount: 1)),
      fields: 'gridProperties.frozenRowCount',
    )));
    await _api!.spreadsheets.batchUpdate(gs.BatchUpdateSpreadsheetRequest(requests: reqs), id);
  }

  /// Pull voucher dari tab Voucher (Sheet) → SQLite (upsert).
  /// Owner atur: nama, tipe, nilai, aktif, kuota, terpakai, periode berlaku.
  /// Return jumlah voucher diperbarui.
  Future<int> pullVouchers(String id) async {
    if (_api == null) return 0;
    final res = await _api!.spreadsheets.values.get(id, "'Voucher'!A2:H");
    final rows = res.values ?? [];
    final db = DbHelper();
    int n = 0;
    for (final r in rows) {
      if (r.isEmpty) continue;
      final name = r[0].toString().trim();
      if (name.isEmpty) continue;
      final type = r.length > 1 ? r[1].toString().trim() : 'PERCENT';
      final value = r.length > 2 ? (int.tryParse(r[2].toString()) ?? 0) : 0;
      final active = r.length > 3 ? (r[3].toString() == '1' || r[3].toString().toLowerCase() == 'true') : true;
      final kuotaStr = r.length > 4 ? r[4].toString().trim() : '';
      final kuota = (kuotaStr.isEmpty || kuotaStr.toLowerCase() == 'inf') ? null : int.tryParse(kuotaStr);
      final usedCount = r.length > 5 ? (int.tryParse(r[5].toString()) ?? 0) : 0;
      final validFrom = r.length > 6 ? r[6].toString().trim() : '';
      final validUntil = r.length > 7 ? r[7].toString().trim() : '';
      // used_count: APP authoritative (increment tiap checkout). Kalau voucher sudah
      // ada di app → pertahankan nilai app (jgn overwrite dgn Sheet, anti konflik
      // kalau owner salah edit). Kalau voucher baru → pakai nilai Sheet.
      final existing = await db.getVoucherByName(name);
      final appUsedCount = existing?.usedCount ?? usedCount;
      await db.upsertVoucher(VoucherModel(
        name: name,
        type: type,
        value: value,
        active: active,
        kuota: kuota,
        usedCount: appUsedCount,
        validFrom: validFrom.isEmpty ? null : validFrom,
        validUntil: validUntil.isEmpty ? null : validUntil,
      ));
      n++;
    }
    debugPrint('⬇️ Pull voucher dari Sheet: $n voucher.');
    return n;
  }

  /// Pull daftar karyawan dari tab Karyawan (Sheet) → SQLite (upsert).
  /// Owner tambah/edit karyawan di Sheet → app ikut. Return jumlah diperbarui.
  Future<int> pullEmployees(String id) async {
    if (_api == null) return 0;
    final res = await _api!.spreadsheets.values.get(id, "'Karyawan'!A2:C");
    final rows = res.values ?? [];
    final db = DbHelper();
    int n = 0;
    for (final r in rows) {
      if (r.isEmpty) continue;
      final name = r[0].toString().trim();
      if (name.isEmpty) continue;
      final active = r.length > 1 ? (r[1].toString() == '1' || r[1].toString().toLowerCase() == 'true') : true;
      final shiftStatus = r.length > 2 ? r[2].toString() : '';
      // Upsert: insert kalau baru, update shift_status kalau sudah ada.
      await db.insertEmployee(name);
      await db.updateEmployeeShift(name, shiftStatus);
      if (!active) {
        // Owner set aktif=0 di Sheet → tandai nonaktif di app.
        final dbConn = await db.database;
        await dbConn.update('employees', {'active': 0}, where: 'name = ?', whereArgs: [name]);
      }
      n++;
    }
    debugPrint('⬇️ Pull karyawan dari Sheet: $n orang.');
    return n;
  }

  /// Tulis tab Setup (key,value) — default shifts + payment_methods + popup konfirmasi.
  /// Idempotent per key: hanya tulis key yg belum ada di Sheet (jangan overwrite setting owner).
  Future<void> pushSetup(String id, {
    String defaultShifts = 'Pagi,Siang,Sore,Malam',
    String defaultPaymentMethods = 'Tunai,QRIS,Transfer',
    String defaultPopupConfirm = 'true',
    String defaultLiburKeywords = 'Libur,Cuti,Sakit,IZIN',
  }) async {
    if (_api == null) return;
    // Baca keys yg sudah ada.
    final Set<String> existingKeys = {};
    try {
      final res = await _api!.spreadsheets.values.get(id, "'Setup'!A2:A100");
      for (final r in res.values ?? <List<Object?>>[]) {
        if (r.isNotEmpty) existingKeys.add(r[0].toString());
      }
    } catch (_) {}

    // Daftar key + nilai default → hanya append yg belum ada.
    final defaults = <String, String>{
      'shifts': defaultShifts,
      'payment_methods': defaultPaymentMethods,
      'popup_konfirmasi_bayar': defaultPopupConfirm,
      'libur_keywords': defaultLiburKeywords,
    };
    final toAdd = <List<Object?>>[];
    for (final e in defaults.entries) {
      if (!existingKeys.contains(e.key)) toAdd.add([e.key, e.value]);
    }
    if (toAdd.isEmpty) return; // semua key sudah ada

    // Append (bukan overwrite) supaya setting owner aman.
    await _api!.spreadsheets.values.append(
      gs.ValueRange(values: toAdd),
      id, "'Setup'!A1",
      valueInputOption: 'RAW',
    );
    debugPrint('⚙️ Setup: ${toAdd.length} key default ditambahkan.');
  }

  /// Baca daftar shift dari tab Setup (key='shifts', value='Pagi,Siang,...').
  Future<List<String>> pullShifts(String id, {List<String> fallback = const ['Pagi', 'Sore']}) async {
    final v = await _pullSetupValue(id, 'shifts');
    if (v == null) return fallback;
    final list = v.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    return list.isEmpty ? fallback : list;
  }

  /// Baca daftar metode pembayaran dari tab Setup (key='payment_methods').
  Future<List<String>> pullPaymentMethods(String id, {List<String> fallback = const ['Tunai', 'QRIS', 'Transfer']}) async {
    final v = await _pullSetupValue(id, 'payment_methods');
    if (v == null) return fallback;
    final list = v.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    return list.isEmpty ? fallback : list;
  }

  /// Baca flag popup konfirmasi bayar dari Setup (key='popup_konfirmasi_bayar').
  Future<bool> pullPopupConfirm(String id, {bool fallback = true}) async {
    final v = await _pullSetupValue(id, 'popup_konfirmasi_bayar');
    if (v == null) return fallback;
    final low = v.trim().toLowerCase();
    return low == 'true' || low == '1' || low == 'ya' || low == 'y';
  }

  /// Helper: ambil 1 nilai dari tab Setup by key. Null kalau ga ada/error.
  Future<String?> _pullSetupValue(String id, String key) async {
    if (_api == null) return null;
    try {
      final res = await _api!.spreadsheets.values.get(id, "'Setup'!A2:B100");
      for (final r in res.values ?? <List<Object?>>[]) {
        if (r.isNotEmpty && r[0].toString().trim() == key) {
          return r.length > 1 ? r[1].toString() : '';
        }
      }
    } catch (e) {
      debugPrint('Pull Setup[$key] gagal: $e');
    }
    return null;
  }

  /// Pull absensi dari tab Absensi (Sheet) → SQLite.
  /// Aturan 1 karyawan 1 shift/hari: ambil baris TERBARU per (karyawan, tanggal)
  /// sebagai sumber kebenaran. Kalau baris terbaru shift kosong → anggap batal.
  /// AMAN: tidak hapus data app kalau Sheet error/kosong.
  Future<int> pullAttendance(String id, {List<String>? validShifts}) async {
    if (_api == null) return 0;
    final res = await _api!.spreadsheets.values.get(id, "'Absensi'!A2:D");
    final rows = res.values ?? [];
    final db = DbHelper();
    final knownEmps = <String>{};
    for (final e in await db.getEmployees()) {
      knownEmps.add((e['name'] ?? '').toString());
    }
    // Map key "name|bDate" → {shift, waktu} terbaru.
    final Map<String, _SheetAbsenRow> latest = {};
    for (final r in rows) {
      if (r.length < 3) continue;
      final bDate = r[0].toString().trim();
      final name = r[1].toString().trim();
      final shift = r[2].toString().trim();
      final waktu = r.length > 3 ? r[3].toString() : '';
      if (!knownEmps.contains(name)) continue;
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(bDate)) continue;
      // Backward-compat: nilai Y/Hadir/✓ lama → anggap 'Pagi' (default).
      String normShift = shift;
      final up = shift.toUpperCase();
      if (up == 'Y' || up == 'TRUE' || up == '1' || up == '✓' || up == 'HADIR') {
        normShift = (validShifts != null && validShifts.isNotEmpty) ? validShifts.first : 'Pagi';
      }
      final key = '$name|$bDate';
      final prev = latest[key];
      if (prev == null || waktu.compareTo(prev.waktu) > 0) {
        latest[key] = _SheetAbsenRow(shift: normShift, waktu: waktu);
      }
    }
    int n = 0;
    for (final entry in latest.entries) {
      final parts = entry.key.split('|');
      final name = parts[0];
      final bDate = parts[1];
      final shift = entry.value.shift;
      // setEmployeeShiftAttendance: 1 org 1 shift. shift='' = batal/hapus.
      await db.setEmployeeShiftAttendance(name, bDate, shift);
      if (shift.isNotEmpty) n++;
    }
    debugPrint('⬇️ Pull absensi dari Sheet: ${latest.length} record (1 org 1 shift).');
    return n;
  }
}

/// Helper internal buat pullAttendance.
class _SheetAbsenRow {
  final String shift;
  final String waktu;
  _SheetAbsenRow({required this.shift, required this.waktu});
}
