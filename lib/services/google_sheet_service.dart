import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:googleapis/sheets/v4.dart' as gs;
import 'package:shared_preferences/shared_preferences.dart';
import 'db_helper.dart';

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

  bool get isConnected => _account != null && _api != null;
  String get email => _account?.email ?? '';

  // Tab & header yang ditulis ke Sheet
  static const _tabs = <String, List<String>>{
    'Dashboard': ['Ringkasan Indikator POS', 'Nilai Hari Ini', 'Keterangan Auto-Formula'],
    'Menu': ['nama', 'kategori', 'harga', 'modal', 'aktif', 'urutan'],
    'Menu_Bahan': ['menu', 'bahan', 'qty'],
    'Varian': ['menu', 'grup', 'tipe', 'wajib', 'opsi', 'tambahan_harga'],
    'Varian_Bahan': ['menu', 'grup', 'opsi', 'bahan', 'qty'],
    'Bahan': ['nama', 'satuan', 'stok_utama', 'stok_min', 'total_penambahan_stok', 'total_stok_tersedia'],
    'Restok_Log': ['waktu', 'nama_bahan', 'jumlah_tambah', 'satuan', 'stok_akhir'],
    'Voucher': ['nama', 'tipe', 'nilai', 'aktif', 'kuota', 'terpakai', 'berlaku_dari', 'berlaku_sampai'],
    'Transaksi': ['kode', 'hari_usaha', 'waktu', 'kasir', 'tipe', 'metode', 'subtotal', 'diskon', 'voucher', 'total', 'status'],
    'Absensi': ['hari_usaha', 'karyawan', 'shift', 'waktu'],
    'Kas': ['hari_usaha', 'tipe', 'nominal', 'kategori', 'catatan', 'oleh', 'waktu'],
  };

  /// Login Google + siapkan API client.
  Future<GoogleSignInAccount?> signIn({bool interactive = true}) async {
    _account = interactive
        ? await googleSignIn.signIn()
        : (await googleSignIn.signInSilently());
    if (_account == null) return null;
    final client = await googleSignIn.authenticatedClient();
    if (client != null) _api = gs.SheetsApi(client);
    return _account;
  }

  Future<void> signOut() async {
    await googleSignIn.signOut();
    _account = null;
    _api = null;
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
      final res = await _api!.spreadsheets.values.get(id, "'Menu'!A2:A2");
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

  /// Tulis katalog (Menu/Bahan/Voucher) + header semua tab.
  Future<void> pushCatalog(String id) async {
    if (_api == null) return;
    final db = DbHelper();

    // Header dulu untuk semua tab (Dashboard di-handle pushDashboard).
    for (final e in _tabs.entries) {
      if (e.key == 'Dashboard') continue;
      await _writeTab(id, e.key, [e.value]);
    }

    final menus = await db.getMenuItems();
    await _writeTab(id, 'Menu', [
      _tabs['Menu']!,
      ...menus.map((m) => [m.name, m.category, m.price, m.cost, m.active ? 1 : 0, m.sortOrder]),
    ]);

    // Resep bahan base per menu
    final menuStocks = await db.getAllMenuStocks();
    await _writeTab(id, 'Menu_Bahan', [
      _tabs['Menu_Bahan']!,
      ...menuStocks.map((s) => [s['menu_name'], s['packaging_name'], s['qty']]),
    ]);

    // Varian: 1 baris per opsi, plus tipe/wajib dari grupnya
    final groups = await db.getAllVariantGroups();
    final gMap = {for (final g in groups) '${g.menuName}||${g.groupName}': g};
    final options = await db.getAllVariantOptions();
    await _writeTab(id, 'Varian', [
      _tabs['Varian']!,
      ...options.map((o) {
        final g = gMap['${o.menuName}||${o.groupName}'];
        final tipe = (g?.type == 'MULTI') ? 'Boleh banyak' : 'Pilih 1';
        final wajib = (g?.required ?? false) ? 'Ya' : 'Tidak';
        return [o.menuName, o.groupName, tipe, wajib, o.optionName, o.priceDelta];
      }),
    ]);

    // Bahan khusus per opsi varian (mis. Dingin → cup plastik)
    final vStocks = await db.getAllVariantOptionStocks();
    await _writeTab(id, 'Varian_Bahan', [
      _tabs['Varian_Bahan']!,
      ...vStocks.map((s) => [s['menu_name'], s['group_name'], s['option_name'], s['packaging_name'], s['qty']]),
    ]);

    final bahan = await db.getPackagings();
    await _writeTab(id, 'Bahan', [
      _tabs['Bahan']!,
      ...bahan.map((b) => [b.name, b.unit, b.stock, b.minStock]),
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

    // Isi/segarkan tab Dashboard.
    try {
      await pushDashboard(id);
    } catch (e) {
      debugPrint('Dashboard gagal diisi: $e');
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

    sec('▌ KATALOG & STAF');
    kv('Menu aktif', 'COUNTIF(Menu!E2:E,1)', bfmt: 'int', note: 'aktif = 1');
    kv('Voucher aktif', 'COUNTIF(Voucher!D2:D,1)', bfmt: 'int');
    kv('Karyawan hadir hari ini', 'COUNTIF(Absensi!A2:A,$h)', bfmt: 'int', note: 'dari tab Absensi');

    // Bersihkan lalu tulis nilai.
    try {
      await _api!.spreadsheets.values.clear(gs.ClearValuesRequest(), id, "'Dashboard'!A1:C200");
    } catch (_) {}
    await _api!.spreadsheets.values.update(
      gs.ValueRange(values: values), id, "'Dashboard'!A1", valueInputOption: 'USER_ENTERED');

    // Format biar josjis (judul, seksi, currency, persen, lebar kolom).
    try {
      final sid = await _sheetId(id, 'Dashboard');
      if (sid != null) await _formatDashboard(id, sid, values.length, sectionRows, rpRows, pctB, pctC);
    } catch (e) {
      debugPrint('Format dashboard gagal: $e');
    }
    debugPrint('📊 Dashboard diperbarui (josjis, rumus live).');
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

  /// Tambah 1 baris transaksi ke tab Transaksi (append).
  Future<void> appendTransaction(String id, Map<String, dynamic> t) async {
    if (_api == null) return;
    await _api!.spreadsheets.values.append(
      gs.ValueRange(values: [
        [
          t['code'], t['business_date'], t['created_at'], t['cashier_name'],
          t['order_type'], t['payment_method'], t['subtotal'], t['discount_amount'],
          t['voucher_name'] ?? '', t['total_amount'], t['status'] ?? 'ACTIVE',
        ]
      ]),
      id,
      "'Transaksi'!A1",
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

  /// Tarik harga/aktif menu dari Sheet → update SQLite (edit Sheet → app berubah).
  Future<int> pullMenuFromSheet(String id) async {
    if (_api == null) return 0;
    final res = await _api!.spreadsheets.values.get(id, "'Menu'!A2:F");
    final rows = res.values ?? [];
    final db = await DbHelper().database;
    int updated = 0;
    for (final r in rows) {
      if (r.isEmpty) continue;
      final name = r[0].toString();
      final price = r.length > 2 ? int.tryParse(r[2].toString()) : null;
      final active = r.length > 4 ? (r[4].toString() == '1' || r[4].toString().toLowerCase() == 'true') : null;
      final data = <String, Object?>{};
      if (price != null) data['price'] = price;
      if (active != null) data['active'] = active ? 1 : 0;
      if (data.isNotEmpty) {
        updated += await db.update('menu_items', data, where: 'name = ?', whereArgs: [name]);
      }
    }
    debugPrint('⬇️ Pull dari Sheet: $updated menu diperbarui.');
    return updated;
  }
}
