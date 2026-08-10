# PROGRESS — Ruang Senyawa POS (Flutter)

Tracker build + peta kode. **Baca file ini dulu tiap lanjut** biar nggak perlu baca semua source.
Tujuan akhir: aplikasi Android local-first yang **mirror fungsi web `pos-cafe`** + sync Google Sheet.

---

## ⚡ Cheat-sheet lanjutan (resume)
- Flutter: `C:\src\flutter\bin\flutter.bat` (belum di PATH). Dart SDK 3.44.8.
- Device HP: **`7e7d962`** (POCO/Redmi peridot, Android 16). Jalankan: `flutter run -d 7e7d962`.
- Cek error CEPAT (bukan build APK): `flutter analyze --no-pub` di folder ini.
- Android SDK ada di `C:\Users\Dell\android-sdk` (adb di `platform-tools\adb.exe`).
- Seed data (ekspor dari web): `assets/seed/seed.raw.json` (+ `logo.jpg`).
- **ATURAN**: JANGAN auto-build APK berulang — user testing sendiri (makan waktu).
  Cukup `flutter analyze` untuk verifikasi. Build APK hanya kalau user minta.
- Google login **ditambahkan paling akhir**; user review setelah itu.

## 🧾 Update log
- **2026-08-10 (Bug-fix besar + redesign Splash & Tablet):**
  1. **VALIDASI STOK saat checkout** (`pos_provider.checkout` → `DbHelper.validateStockForCart`):
     akumulasi kebutuhan semua bahan (resep base + opsi varian) → tolak transaksi kalau ada
     bahan kurang, kasih alasan "Stok bahan kurang: X (butuh N, sisa M)". Anti jual minus.
  2. **VOID transaksi sekarang benar** (`pos_provider.voidTransaction` → `DbHelper.restoreStockForTransaction`):
     kembalikan stok bahan yang tadi dipotong + turunkan `used_count` voucher. Sesuai teks UI
     yang udah bilang "stok dikembalikan".
  3. **CAST AMAN**: semua `row['qty'] as int` / `r['price'] as int` diganti helper `toInt()`
     (di `models.dart`) — anti crash `TypeError` di checkout & cetak ulang struk.
  4. **TAMPILAN STOK ASLI**: tile menu "sisa 298" hardcode diganti `DbHelper.estimateMenuPortions`
     (min porsi dari stok bahan). Tampil "sisa N" / "⚠️ habis" / "stok ∞" (tak ada resep).
  5. **KAS KONSISTEN MASUK/KELUAR** (`CashType` konstan di `db_helper`): app simpen & dashboard
     Sheet rumus `SUMIFS(...,"MASUK"/"KELUAR")` sekarang cocok. recap_screen pake konstan +
     sync kas ke tab `Kas` lewat `appendKas`.
  6. **RESTOK_LOG ke Sheet**: `logRestokToSheet` (dulunya dead code) sekarang dipanggil di
     admin `_showRestokDialog`. Tab Restok_Log di Sheet terisi tiap restok bahan.
  7. **ABSEN ANTI-DOBEL**: `recordAttendance` jadi upsert; `_toggleShift` OFF → `removeAttendance`
     (hapus baris). Tidak ada lagi 2 baris absen untuk orang+shift yang sama.
  8. **PULL MENU + MODAL/URUTAN**: `pullMenuFromSheet` sekarang tarik `price, cost, active, urutan`.
  9. **SYNC FAILURE INDIKATOR**: `performSync` track `_lastSyncFailed` → status "Sync gagal ·
     ketuk coba lagi". Timer 15mnt cuma jalan kalau `_googleConnected` (hemat baterai).
  10. **REDESIGN SPLASH** (`splash_setup_screen`): flow baru = (1) login pilih akun Google,
      (2) load daftar Spreadsheet existing via **Drive API** (`listSpreadsheets`), (3) user pilih
      file existing **ATAU** buat baru (`createSpreadsheetByName`). Fallback "ketik email manual"
      yang menyesatkan dihapus. Tambah `googleapis/drive/v3.dart`.
  11. **TABELT**: grid menu adaptif 2/3/4 kolom (HP/tablet kecil/tablet besar), rasio split-view
      disesuaikan.
  12. **DB v3→v4 migration**: rename kolom `menu_items.sortOrder` (camelCase) → `sort_order`
      (snake_case, konsisten); dedup data varian lama dipindah ke migration (sekali jalan,
      bukan tiap `initData`).
  13. **SEED idempoten**: insert varian/resep pake `ConflictAlgorithm.ignore` — aman kalau seed
      ke-import 2x.
  `flutter analyze` = **0 error** (27 info kosmetik: deprecation API Flutter baru).
- **2026-07-31 (Kelola Menu & Varian — DIBIKIN MIRIP WEB + FIX BUG):**
  1. **Bahan/resep sekarang INLINE di form Tambah/Edit Menu** (`admin_hub._showMenuDialog`), persis web:
     nama/kategori/harga/modal + section "Bahan/Stok dipakai" (multi-baris: dropdown bahan + qty − / +
     + hapus + "Tambah bahan"). Simpan → `deleteMenuStocksByMenu(nama lama & baru)` lalu `insertMenuStock`
     tiap baris + `syncCatalogUp()`. Tombol 📦 terpisah **dihapus** (metode `_showManageRecipeDialog` dibuang).
  2. **Atur Varian (🎛️) dirombak jadi guided** (`_showManageVariantsDialog` pakai `DbHelper.getVariantTree`):
     tiap grup = kartu sendiri; di dalamnya daftar pilihan (bisa **hapus per-opsi**) + form "Tambah pilihan"
     (nama + **+harga** + **bahan** + qty). Bawah = "Buat grup baru" (nama + tipe Pilih1/Boleh-banyak + Wajib).
  3. **BUG DEDUPE:** `variant_groups/variant_options/variant_option_stocks/menu_stocks` **tak punya UNIQUE**,
     jadi `ConflictAlgorithm.replace` bikin **baris dobel** tiap insert. Fix: `insertVariantGroup/Option/OptionStock`
     diubah jadi **upsert manual** (cek dulu → update/insert) + `deleteVariantGroup` ikut hapus option-stocks +
     `cleanupDuplicateVariants()` (buang dobel lama, dipanggil sekali di `pos_provider.initData`). **Tanpa reset DB.**
  4. **BUG KASIR — varian tak muncul:** di `variant_sheet._loadVariants`, opsi DB **cuma di-load di dalam blok
     `if (groups.isEmpty)`** → menu yang PUNYA grup asli malah `optionsMap` kosong → `validGroups` habis → varian
     hilang. Fix: **selalu load opsi asli** tiap grup; fallback Suhu default hanya kalau menu belum punya grup.
     `_formatGroupTitle/_formatOptionLabel` disederhanakan → tampil **apa adanya** sesuai ketikan admin (harga full, tak dibulatin "k").
  `flutter analyze` = **0 error/warning**. APK debug rebuild + install ke `7e7d962` OK.
- **2026-07-31 (Google Sheet sync — DIMAJUKAN & IMPLEMENTED):** OAuth Cloud beres (lihat OAUTH-SETUP.md).
  `google_sheet_service.dart` sekarang **ASLI** (bukan stub): login via `google_sign_in` +
  `extension_google_sign_in_as_googleapis_auth`, **auto-create spreadsheet** ("Ruang Senyawa — Laporan POS")
  kalau ID kosong, **push katalog** (Menu/Bahan/Voucher), **append transaksi** tiap checkout,
  **pull menu** (harga/aktif) dari Sheet → SQLite (edit Sheet → app berubah). Reconnect diam-diam
  saat relaunch. Sync periodik 15 mnt aktif setelah login. Tambah dep: `extension_google_sign_in_as_googleapis_auth`, `http`.
  `flutter analyze` = 0 error. **Belum:** pull lengkap semua tab, push absensi/kas, dedupe transaksi.
- **2026-07-31 (fondasi data-layer):** DB versi 2 + migrasi (drop→recreate→reseed).
  Tabel baru: `variant_option_stocks, transaction_items, cash_entries, attendances`;
  kolom baru: voucher `used_count/valid_from/valid_until`, transaksi `business_date/status/voucher_name/void_reason`.
  Seed importer sekarang impor `menuBahan`→resep & `varianBahan`→stok-opsi & voucher-periode.
  **Checkout diupgrade:** hari usaha (cutoff 6), simpan item transaksi, **potong stok base + opsi varian**,
  validasi voucher (aktif/periode/kuota) + naikkan `used_count`. Sync timer 15 mnt & **status jujur**
  ("Google belum tersambung"). `flutter analyze` = 0 error.
- **Catatan penting:** Spreadsheet kosong itu **wajar** — Google Sheet sync butuh Google Login
  yang **belum dibuat** (fase P4, sengaja terakhir). `google_sheet_service.dart` = rangka; sync
  periodik dimatikan sampai login aktif (biar tak nyesatin).

## 🗂️ Peta file (lib/)
| File | Tanggung jawab |
|---|---|
| `main.dart` | Root `RuangSenyawaApp`, MultiProvider, tema, auto-lock listener |
| `models/models.dart` | Semua model data (Packaging, Menu, Variant*, Voucher, Cart, Transaction, StoreSetting) |
| `services/db_helper.dart` | Schema SQLite + query (singleton) |
| `services/seed_importer.dart` | Impor `seed.raw.json` → DB saat pertama |
| `services/google_sheet_service.dart` | (rangka) sync ke Google Sheet |
| `providers/pos_provider.dart` | State POS: keranjang, katalog, checkout, stok |
| `providers/settings_provider.dart` | Font-scale, tema, **PIN admin** (dari prefs, tak ditampilkan), auto-lock 3 mnt |
| `ui/screens/` | splash_setup, pos, recap, absen, admin_hub, receipt |
| `ui/widgets/variant_sheet.dart` | Popup pilih varian |
| `ui/theme/app_theme.dart` | Tema Material (light/dark, font-scale) |

---

## ✅ SUDAH JADI
- [x] Struktur project Flutter + Material 3 (light/dark, font-scale Ringkas/Normal/Besar).
- [x] SQLite schema dasar + seed importer dari `seed.raw.json` (ekspor data web).
- [x] Katalog: menu_items, variant_groups, variant_options, **menu_stocks (resep)**, packaging.
- [x] POS: keranjang, popup varian, dine-in/bungkus, quick-cash, kembalian.
- [x] Struk (preview + logo). Absen (status shift inline). Admin hub (tab).
- [x] PIN admin: dari prefs, **tidak ditampilkan**, backdoor `0000` dihapus, bisa diganti (`setAdminPin`).
- [x] Fix test error `MyApp` → smoke test. `flutter analyze` = **0 error** (sisa lint kosmetik).
- [x] **Admin — Kelola Menu CRUD** (tambah/edit/hapus) + **bahan/resep INLINE di form** (mirip web).
- [x] **Admin — Atur Varian** guided: grup → pilihan (+harga + bahan + qty), hapus per-opsi, dedupe fix.
- [x] **Admin — Voucher CRUD** (kuota + periode). **Ganti PIN** di admin.
- [x] **Kasir — varian muncul & bisa dipilih** dari grup asli DB (fix `variant_sheet`), harga nambah benar.
- [x] **Edit katalog di app → push ke Google Sheet** (`syncCatalogUp`), admin list refresh reaktif.

## 🔨 TODO — biar SESUAI RENCANA (urut prioritas)
> Status: [ ] belum · [~] lagi digarap · [x] selesai

### P1 — keluhan user (dulukan)
- [ ] **Voucher periode + kuota + terpakai**: kolom `valid_from,valid_until,used_count` di tabel `vouchers`; model; **CRUD di admin** (tambah/edit/hapus + kuota + tanggal); validasi saat jual (tolak kalau nonaktif/di luar periode/kuota habis); `used_count++` saat pakai.
- [ ] **Setelan Printer**: layar pilih lebar kertas (58/80), nama printer, tombol tes. (Cetak BT asli butuh plugin `print_bluetooth_thermal` — tambah nanti; sekarang simpan setelan + stub.)

### P2 — inti stok & transaksi
- [ ] **Stok per opsi varian** (Hot→cup panas, Dingin→cup plastik): tabel `variant_option_stocks(menu,grup,opsi,bahan,qty)`; impor dari seed `varianBahan`; potong saat jual.
- [ ] **Potong stok saat jual**: kurangi `menu_stocks` (base) + `variant_option_stocks` (opsi terpilih) per transaksi.
- [ ] **Detail item transaksi**: tabel `transaction_items` (kode, menu, varian, catatan, qty, harga, subtotal) — supaya struk lama, rekap detail, & sync item ke Sheet ada datanya.
- [ ] **Hari usaha (`business_date`)** di transaksi (buka 07:00–03:00, pemisah jam 6) → rekap harian akurat.
- [ ] **Void/batalkan transaksi**: kolom `status,voided_at,void_reason`; kembalikan stok + kuota voucher.

### P3 — keuangan & absensi
- [ ] **Kas & Pengeluaran**: tabel `cash_entries(type,amount,category,note,business_date,by)`; input di rekap (kasir bisa); "uang di laci" = kas awal + tunai + masuk − keluar.
- [ ] **Absensi historis**: tabel `attendances(employee,business_date,shift)` presence-only (toggle); rekap admin siapa×shift + jumlah masuk. (Sekarang cuma `employees.shift_status` inline.)

### P4 — sinkronisasi (paling akhir)
- [ ] Google Sign-In (owner) scope `drive.file`, pilih Spreadsheet.
- [ ] Sync turun (katalog) + naik (transaksi/absensi/kas/stok) tiap 15 mnt + manual. Anti-dobel via UUID. Prune transaksi lokal >30 hari.
- [ ] Cetak thermal Bluetooth (plugin) — printer asli.

## 🖥️ UI yang MASIH DUMMY / belum ke-wire (dari test HP 2026-07-31)
> Banyak layar dibikin tool lain pakai data hardcode — perlu disambung ke DB.
- [x] **Crash absen & rekap** (`DateFormat 'id_ID'` locale belum init) → FIX di `main.dart` (`initializeDateFormatting`).
- [ ] **Rekap** (`recap_screen.dart`): angka masih **dummy** (Rp640.000 dst). Wire ke DB:
      omzet/trx hari usaha, tunai vs QRIS, kas awal + pengeluaran + uang di laci. Tombol "Tutup Kasir" beneran.
- [ ] **Absen** (`absen_screen.dart`): karyawan & shift masih **hardcode** (Andi/Budi, tombol nggak nyimpan).
      Wire: ambil `employees` dari DB, shift dari setting, simpan ke tabel `attendances` (toggle presence).
- [x] **Admin — Tambah/Edit Menu**: CRUD + bahan/resep inline (mirip web). ✔
- [x] **Admin — Atur Varian**: grup + pilihan (+harga/bahan), hapus per-opsi, dedupe. ✔
- [x] **Admin — Voucher CRUD** (kuota + periode). ✔  · **Ganti PIN** di admin. ✔
- [ ] **Admin — Setelan Printer**: layar ada tapi cetak BT masih **stub** (channel `id.ruangsenyawa.pos/printer`
      belum diimplement native). Tambah plugin thermal + implement native `getPairedDevices`/print.
- [ ] **Ganti PIN dari Sheet**: baca PIN dari tab Pengaturan (sekarang baru dari prefs lokal).
- [ ] **Kas/Pengeluaran**: input "beli es" (kasir) → tabel `cash_entries` (belum ke-wire).

## 🧭 Keputusan terkunci
Flutter · Material 3 light-first · local-first SQLite · Sheet sebagai hub sync (nanti) ·
1 alat kasir · PIN global dari setelan (tak ditulis) · presence-only absensi · dine-in/bungkus ·
data awal = ekspor web (seed.raw.json) · nama "Ruang Senyawa POS" · id **`id.ruangsenyawa.pos`** (JANGAN ubah — OAuth pecah).

## 📝 Catatan migrasi DB
Saat nambah tabel/kolom: naikkan `version` di `db_helper._initDb` + `onUpgrade` (dev: drop & recreate
lalu reseed, karena data = seed + test, belum ada data produksi). Reseed dipicu `seed_importer`.
