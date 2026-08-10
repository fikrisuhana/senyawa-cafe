import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:googleapis/sheets/v4.dart' as gs;
import 'package:googleapis/drive/v3.dart' as gd;
import 'package:shared_preferences/shared_preferences.dart';
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
  }

  /// Tulis DASHBOARD ringkasan owner — board KPI bersekat + rumus LIVE + format
  /// (currency/persen/warna). Kolom Transaksi: B hari_usaha, D kasir, E tipe,
  /// F metode, H diskon, J total, K status. Kas: A hari_usaha, B tipe, C nominal.
  Future<void> pushDashboard(String id) async {
    if (_api == null) return;
    const h = 'TEXT(TODAY(),"yyyy-mm-dd")';           // hari ini (teks)
    const b = 'TEXT(TODAY(),"yyyy-mm")&"*"';          // prefix bulan, mis "2026-07*"
    final omzetH = 'SUMIFS(Transaksi!J:J,Transaksi!B:B,$h,Transaksi!K:K,"ACTIVE")';
    final trxH = 'COUNTIFS(Transaksi!B:B,$h,Transaksi!K:K,"ACTIVE")';
    String metode(String m) => 'SUMIFS(Transaksi!J:J,Transaksi!B:B,$h,Transaksi!F:F,"$m",Transaksi!K:K,"ACTIVE")';
    String tipeVal(String tp) => 'SUMIFS(Transaksi!J:J,Transaksi!B:B,$h,Transaksi!E:E,"$tp",Transaksi!K:K,"ACTIVE")';
    String tipeCnt(String tp) => 'COUNTIFS(Transaksi!B:B,$h,Transaksi!E:E,"$tp",Transaksi!K:K,"ACTIVE")';
    final omzetB = 'SUMIFS(Transaksi!J:J,Transaksi!B:B,$b,Transaksi!K:K,"ACTIVE")';
    final trxB = 'COUNTIFS(Transaksi!B:B,$b,Transaksi!K:K,"ACTIVE")';

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
    sub('Terisi otomatis dari tab Transaksi · Kas · Absensi. Jangan diedit manual.');
    gap();

    sec('▌ RINGKASAN HARI INI');
    kv('Omzet hari ini', omzetH, note: 'penjualan ACTIVE');
    kv('Jumlah transaksi', trxH, bfmt: 'int');
    kv('Rata-rata / transaksi', 'IFERROR($omzetH/$trxH,0)');
    kv('Diskon diberikan', 'SUMIFS(Transaksi!H:H,Transaksi!B:B,$h,Transaksi!K:K,"ACTIVE")', note: 'potongan voucher');
    gap();

    sec('▌ METODE PEMBAYARAN — HARI INI');
    kv('Tunai (CASH)', metode('CASH'), cFormula: 'IFERROR(${metode('CASH')}/$omzetH,0)', cfmt: 'pct');
    kv('QRIS', metode('QRIS'), cFormula: 'IFERROR(${metode('QRIS')}/$omzetH,0)', cfmt: 'pct');
    kv('Transfer', metode('TRANSFER'), cFormula: 'IFERROR(${metode('TRANSFER')}/$omzetH,0)', cfmt: 'pct');
    gap();

    sec('▌ KAS & UANG LACI — HARI INI');
    kv('Kas masuk', 'SUMIFS(Kas!C:C,Kas!A:A,$h,Kas!B:B,"MASUK")', note: 'kas awal + pemasukan');
    kv('Pengeluaran', 'SUMIFS(Kas!C:C,Kas!A:A,$h,Kas!B:B,"KELUAR")');
    kv('Uang di laci (estimasi)', '${metode('CASH')}+SUMIFS(Kas!C:C,Kas!A:A,$h,Kas!B:B,"MASUK")-SUMIFS(Kas!C:C,Kas!A:A,$h,Kas!B:B,"KELUAR")', note: 'tunai + masuk − keluar');
    gap();

    sec('▌ TIPE PESANAN — HARI INI');
    kv('Makan di tempat', tipeVal('DINE_IN'), cFormula: '${tipeCnt('DINE_IN')}&" transaksi"', cfmt: '');
    kv('Bungkus', tipeVal('TAKEAWAY'), cFormula: '${tipeCnt('TAKEAWAY')}&" transaksi"', cfmt: '');
    gap();

    // Kinerja kasir — dinamis dari daftar karyawan aktif.
    final emps = await _activeEmployeeNames();
    if (emps.isNotEmpty) {
      sec('▌ KINERJA KASIR — HARI INI');
      for (final name in emps) {
        final safe = name.replaceAll('"', '');
        kv('   $safe', 'SUMIFS(Transaksi!J:J,Transaksi!B:B,$h,Transaksi!D:D,"$safe",Transaksi!K:K,"ACTIVE")',
            cFormula: 'COUNTIFS(Transaksi!B:B,$h,Transaksi!D:D,"$safe",Transaksi!K:K,"ACTIVE")&" trx"');
      }
      gap();
    }

    sec('▌ BULAN INI');
    kv('Omzet bulan ini', omzetB, note: 'bulan berjalan');
    kv('Transaksi bulan ini', trxB, bfmt: 'int');
    kv('Rata-rata / transaksi', 'IFERROR($omzetB/$trxB,0)');
    gap();

    sec('▌ SEPANJANG WAKTU');
    kv('Total omzet (ACTIVE)', 'SUMIF(Transaksi!K:K,"ACTIVE",Transaksi!J:J)');
    kv('Total transaksi tercatat', 'COUNTA(Transaksi!A2:A)', bfmt: 'int');
    kv('Transaksi dibatalkan (VOID)', 'COUNTIF(Transaksi!K:K,"VOID")', bfmt: 'int');
    kv('Tingkat pembatalan', 'IFERROR(COUNTIF(Transaksi!K:K,"VOID")/COUNTA(Transaksi!A2:A),0)', bfmt: 'pct');
    gap();

    // TOP 5 MENU HARI INI — dari tab Transaksi_Item (menu + qty) join kode hari ini.
    sec('▌ TOP 5 MENU — HARI INI');
    // QUERY langsung return 5 baris (menu, total qty) utk trx yg kodenya diawali prefix hari ini.
    // Ditulis di 1 sel; Sheet akan tumpah ke bawah (array formula).
    final kodePrefixHari = 'TRX-TEXT(TODAY(),"yyyyMMdd")';
    kv('Lihat 5 terlaris di bawah ↓',
      'IFERROR(QUERY(Transaksi_Item!A2:F,"SELECT B, SUM(D) WHERE A STARTS WITH \'$kodePrefixHari\' GROUP BY B LABEL SUM(D) \'Qty\' ORDER BY SUM(D) DESC LIMIT 5",0),"belum ada data")',
      bfmt: 'int', note: 'menu + total qty terjual hari ini');
    gap();

    // JAM SIBUK HARI INI — omzet per jam (07-23). Dipakai juga buat chart bar.
    sec('▌ JAM SIBUK — HARI INI (omzet per jam)');
    for (int jam = 7; jam <= 23; jam++) {
      final jamStr = jam.toString().padLeft(2, '0');
      kv('$jamStr:00 - ${((jam + 1) % 24).toString().padLeft(2, '0')}:00',
        'SUMPRODUCT((TEXT(Transaksi!C2:C,"yyyy-mm-dd")=$h)*(HOUR(Transaksi!C2:C)=$jam)*(Transaksi!K2:K="ACTIVE")*Transaksi!J2:J)',
        bfmt: 'rp', note: '');
    }
    gap();

    // AUDIT VOID — tracking transaksi dibatalkan hari ini & bulan ini.
    sec('▌ AUDIT VOID — TRANSAKSI DIBATALKAN');
    kv('Jumlah VOID hari ini', 'COUNTIFS(Transaksi!B:B,$h,Transaksi!K:K,"VOID")', bfmt: 'int');
    kv('Nilai VOID hari ini', 'SUMIFS(Transaksi!J:J,Transaksi!B:B,$h,Transaksi!K:K,"VOID")', note: 'estimasi nilai');
    kv('Jumlah VOID bulan ini', 'COUNTIFS(Transaksi!B:B,$b,Transaksi!K:K,"VOID")', bfmt: 'int');
    kv('Nilai VOID bulan ini', 'SUMIFS(Transaksi!J:J,Transaksi!B:B,$b,Transaksi!K:K,"VOID")');
    gap();

    sec('▌ KATALOG & STAF');
    kv('Menu aktif', 'COUNTIF(Menu_Resep!E2:E,1)', bfmt: 'int', note: 'aktif = 1');
    kv('Voucher aktif', 'COUNTIF(Voucher!D2:D,1)', bfmt: 'int');
    kv('Karyawan hadir hari ini', 'COUNTIF(Absensi!A2:A,$h)', bfmt: 'int', note: 'dari tab Absensi');

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
      await _api!.spreadsheets.values.clear(gs.ClearValuesRequest(), id, "'Dashboard'!A1:C200");
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

    // Format biar josjis (judul, seksi, currency, persen, lebar kolom).
    try {
      final sid = await _sheetId(id, 'Dashboard');
      if (sid != null) await _formatDashboard(id, sid, values.length, sectionRows, rpRows, pctB, pctC);
    } catch (e) {
      debugPrint('Format dashboard gagal: $e');
    }
    debugPrint('📊 Dashboard diperbarui (josjis, rumus live).');

    // Tambah chart native (bar/pie) — idempotent: hapus chart lama dulu.
    try {
      await addDashboardCharts(id);
    } catch (e) {
      debugPrint('Chart dashboard gagal: $e');
    }
  }

  /// Tambah 3 chart native di tab Dashboard: (1) bar omzet 7 hari,
  /// (2) pie metode pembayaran hari ini, (3) bar jam sibuk.
  /// Idempotent: hapus semua embedded object (chart) lama dulu supaya tak numpuk.
  Future<void> addDashboardCharts(String id) async {
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
      chartId: 1001,
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

    // --- CHART 2: Pie metode pembayaran hari ini ---
    // Sumber: tabel kecil H1:I4 (label metode + omzet) — ditulis dulu.
    try {
      await _api!.spreadsheets.values.update(
        gs.ValueRange(values: [
          ['Metode', 'Omzet'],
          ['Tunai', '=SUMIFS(Transaksi!J:J,Transaksi!B:B,TEXT(TODAY(),"yyyy-mm-dd"),Transaksi!F:F,"CASH",Transaksi!K:K,"ACTIVE")'],
          ['QRIS', '=SUMIFS(Transaksi!J:J,Transaksi!B:B,TEXT(TODAY(),"yyyy-mm-dd"),Transaksi!F:F,"QRIS",Transaksi!K:K,"ACTIVE")'],
          ['Transfer', '=SUMIFS(Transaksi!J:J,Transaksi!B:B,TEXT(TODAY(),"yyyy-mm-dd"),Transaksi!F:F,"TRANSFER",Transaksi!K:K,"ACTIVE")'],
        ]),
        id, "'Dashboard'!H1", valueInputOption: 'USER_ENTERED',
      );
    } catch (e) {
      debugPrint('Tabel metode gagal: $e');
    }
    reqs.add(gs.Request(addChart: gs.AddChartRequest(chart: gs.EmbeddedChart(
      chartId: 1002,
      position: gs.EmbeddedObjectPosition(
        overlayPosition: gs.OverlayPosition(
          anchorCell: gs.GridCoordinate(sheetId: sid, rowIndex: 12, columnIndex: 6),
          widthPixels: 380,
          heightPixels: 220,
        ),
      ),
      spec: gs.ChartSpec(
        title: 'Metode Pembayaran — Hari Ini',
        pieChart: gs.PieChartSpec(
          domain: dataOf('Dashboard!H1:H4'),
          series: dataOf('Dashboard!I1:I4'),
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
      chartId: 1003,
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

    // Lebar kolom A/B/C.
    void colW(int col, int px) => reqs.add(gs.Request(updateDimensionProperties: gs.UpdateDimensionPropertiesRequest(
          range: gs.DimensionRange(sheetId: sid, dimension: 'COLUMNS', startIndex: col, endIndex: col + 1),
          properties: gs.DimensionProperties(pixelSize: px),
          fields: 'pixelSize',
        )));
    colW(0, 230); colW(1, 140); colW(2, 230);

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
    final header = _tabs['Rekap_Bulanan']!;

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
      // Kolom mengacu: Transaksi B=hari_usaha, F=metode, G=subtotal, H=diskon,
      // I=voucher, J=total, K=status. Transaksi_Item: B=menu, D=qty, F=subtotal.
      // modal di-estimasi via SUMIFS cost total tidak ada di tab; pakai subtotal? →
      // sekarang cost_total belum dikirim ke Sheet, jadi modal dikosongkan (0) sampai ditambahkan.
      values.add([
        b, // bulan (YYYY-MM)
        '=SUMIFS(Transaksi!J:J,Transaksi!B:B,"$bm",Transaksi!K:K,"ACTIVE")', // omzet
        '=COUNTIFS(Transaksi!B:B,"$bm",Transaksi!K:K,"ACTIVE")', // transaksi
        '=IFERROR(SUMIFS(Transaksi!J:J,Transaksi!B:B,"$bm",Transaksi!K:K,"ACTIVE")/COUNTIFS(Transaksi!B:B,"$bm",Transaksi!K:K,"ACTIVE"),0)', // rata_rata
        '=SUMIFS(Transaksi!J:J,Transaksi!B:B,"$bm",Transaksi!F:F,"CASH",Transaksi!K:K,"ACTIVE")', // tunai
        '=SUMIFS(Transaksi!J:J,Transaksi!B:B,"$bm",Transaksi!F:F,"QRIS",Transaksi!K:K,"ACTIVE")', // qris
        '=SUMIFS(Transaksi!J:J,Transaksi!B:B,"$bm",Transaksi!F:F,"TRANSFER",Transaksi!K:K,"ACTIVE")', // transfer
        '=SUMIFS(Transaksi!H:H,Transaksi!B:B,"$bm",Transaksi!K:K,"ACTIVE")', // diskon
        '=SUMIFS(Transaksi!L:L,Transaksi!B:B,"$bm",Transaksi!K:K,"ACTIVE")', // modal (kolom L cost_total)
        '=SUMIFS(Transaksi!M:M,Transaksi!B:B,"$bm",Transaksi!K:K,"ACTIVE")', // laba_kotor (kolom M = total-modal)
        '=SUMIFS(Kas!C:C,Kas!A:A,"$bm*",Kas!B:B,"MASUK")', // kas_masuk
        '=SUMIFS(Kas!C:C,Kas!A:A,"$bm*",Kas!B:B,"KELUAR")', // kas_keluar
      ]);
    }

    // Tulis ulang tabel (clear dulu lalu update).
    try {
      await _api!.spreadsheets.values.clear(gs.ClearValuesRequest(), id, "'Rekap_Bulanan'!A1:L200");
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
      if (sid != null) await _formatRekapBulanan(id, sid);
    } catch (e) {
      debugPrint('Format Rekap_Bulanan gagal: $e');
    }
    debugPrint('📅 Rekap_Bulanan diperbarui: ${bulans.length} bulan.');
  }

  /// Format tab Rekap_Bulanan: freeze header, lebar kolom, currency.
  Future<void> _formatRekapBulanan(String id, int sid) async {
    final reqs = <gs.Request>[];
    final range = gs.GridRange(sheetId: sid, startRowIndex: 1, endRowIndex: 2, startColumnIndex: 0, endColumnIndex: 12);
    // Header bold + background coklat.
    reqs.add(gs.Request(repeatCell: gs.RepeatCellRequest(
      range: gs.GridRange(sheetId: sid, startRowIndex: 0, endRowIndex: 1, startColumnIndex: 0, endColumnIndex: 12),
      cell: gs.CellData(userEnteredFormat: gs.CellFormat(
          backgroundColor: _rgb(0x7A5540),
          textFormat: gs.TextFormat(bold: true, foregroundColor: _rgb(0xFFFFFF)))),
      fields: 'userEnteredFormat(backgroundColor,textFormat)',
    )));
    // Currency untuk kolom omzet..kas_keluar (B,D,E,F,G,H,I,J,K,L = index 1,3,4,5,6,7,8,9,10,11). C(count)=2 skip.
    final rpCols = [1, 3, 4, 5, 6, 7, 8, 9, 10, 11];
    for (final c in rpCols) {
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
    // Suppress unused warning for `range` (placeholder untuk extend format kalau perlu).
    // ignore: unused_local_variable
    final _ = range;
    await _api!.spreadsheets.batchUpdate(gs.BatchUpdateSpreadsheetRequest(requests: reqs), id);
  }

  /// Tulis tab Absensi_Matriks: tanggal × karyawan (1 kolom per orang), bulan berjalan.
  /// Format presence-only: isi ✓ kalau hadir, kosong kalau tidak.
  /// Sumber: tab Absensi (kolom hadir = Y). Backward-compat: shift Pagi/Sore lama dihitung hadir.
  Future<void> pushAbsensiMatriks(String id) async {
    if (_api == null) return;
    final emps = await _activeEmployeeNames();
    final now = DateTime.now();
    final year = now.year;
    final month = now.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final ym = '$year-${month.toString().padLeft(2, '0')}';

    // Header: tgl | <Nama> | <Nama> | ...
    final header = <Object?>['tgl'];
    for (final name in emps) {
      header.add(name);
    }

    final values = <List<Object?>>[header];
    for (int d = 1; d <= daysInMonth; d++) {
      final dateStr = '$ym-${d.toString().padLeft(2, '0')}';
      final row = <Object?>[d];
      for (final name in emps) {
        // Hadir kalau: ada baris Y baru (hadir=Y) ATAU ada absen lama (shift Pagi/Sore).
        // COUNTIFS gabungan: hadir=Y, atau shift Pagi, atau shift Sore, atau shift Hadir.
        row.add(
          '=IF(OR('
          'COUNTIFS(Absensi!A:A,"$dateStr",Absensi!B:B,"$name",Absensi!C:C,"Y")>0,'
          'COUNTIFS(Absensi!A:A,"$dateStr",Absensi!B:B,"$name",Absensi!C:C,"Hadir")>0,'
          'COUNTIFS(Absensi!A:A,"$dateStr",Absensi!B:B,"$name",Absensi!C:C,"Pagi")>0,'
          'COUNTIFS(Absensi!A:A,"$dateStr",Absensi!B:B,"$name",Absensi!C:C,"Sore")>0'
          '),"✓","")',
        );
      }
      values.add(row);
    }
    // Baris TOTAL hadir per karyawan (COUNTA kolom ✓).
    final totalRow = <Object?>['TOTAL'];
    final lastRow = daysInMonth + 1;
    for (int i = 0; i < emps.length; i++) {
      final col = _colLetter(1 + i); // karyawan ke-i mulai kolom B (index 1)
      totalRow.add('=COUNTA(${col}2:${col}$lastRow)');
    }
    values.add(totalRow);

    try {
      await _api!.spreadsheets.values.clear(
          gs.ClearValuesRequest(), id, "'Absensi_Matriks'!A1:ZZ100");
    } catch (_) {}
    await _api!.spreadsheets.values.update(
      gs.ValueRange(values: values),
      id,
      "'Absensi_Matriks'!A1",
      valueInputOption: 'USER_ENTERED',
    );

    // Format: freeze header + total row bold.
    try {
      final sid = await _sheetId(id, 'Absensi_Matriks');
      if (sid != null) await _formatAbsensiMatriks(id, sid, values.length, values.first.length);
    } catch (e) {
      debugPrint('Format Absensi_Matriks gagal: $e');
    }
    debugPrint('🧮 Absensi_Matriks diperbarui: $daysInMonth hari × ${emps.length} karyawan.');
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
  Future<void> _formatAbsensiMatriks(String id, int sid, int nRows, int nCols) async {
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
    // Baris terakhir (TOTAL) bold.
    reqs.add(gs.Request(repeatCell: gs.RepeatCellRequest(
      range: gs.GridRange(sheetId: sid, startRowIndex: nRows - 1, endRowIndex: nRows, startColumnIndex: 0, endColumnIndex: nCols),
      cell: gs.CellData(userEnteredFormat: gs.CellFormat(
          backgroundColor: _rgb(0xF5F3F0),
          textFormat: gs.TextFormat(bold: true))),
      fields: 'userEnteredFormat(backgroundColor,textFormat)',
    )));
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
  /// Format presence-only: hadir = 'Y' / tidak = 'N'.
  Future<void> appendAttendance(String id, String businessDate, String employeeName, bool hadir) async {
    if (_api == null) return;
    await _api!.spreadsheets.values.append(
      gs.ValueRange(values: [
        [
          businessDate,
          employeeName,
          hadir ? 'Y' : 'N',
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

  /// Pull absensi dari tab Absensi (Sheet) → SQLite, untuk bulan berjalan.
  /// Owner bisa tandai hadir langsung di Sheet (kolom hadir = Y/N) → app ikut.
  /// Return jumlah baris disinkronkan. Hanya isi 'Y' yang dicatat sebagai hadir.
  Future<int> pullAttendance(String id) async {
    if (_api == null) return 0;
    // Ambil semua baris Absensi (A=hari_usaha, B=karyawan, C=hadir).
    final res = await _api!.spreadsheets.values.get(id, "'Absensi'!A2:C");
    final rows = res.values ?? [];
    final db = DbHelper();
    int n = 0;
    for (final r in rows) {
      if (r.length < 3) continue;
      final bDate = r[0].toString();
      final name = r[1].toString();
      final hadirFlag = r[2].toString().trim().toUpperCase();
      final bool hadir = hadirFlag == 'Y' || hadirFlag == 'TRUE' || hadirFlag == '1' || hadirFlag == '✓';
      if (hadir) {
        await db.recordAttendance(name, bDate, 'Hadir');
      } else {
        await db.removeAttendance(name, bDate, 'Hadir');
      }
      n++;
    }
    debugPrint('⬇️ Pull absensi dari Sheet: $n baris.');
    return n;
  }
}
