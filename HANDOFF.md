# HANDOFF — Ruang Senyawa POS (Flutter) 📱

Dokumen serah-terima buat siapa pun yang lanjut ngoding. **Baca ini + PROGRESS.md dulu.**
Tujuan: aplikasi kasir Android **local-first** yang meniru fungsi web `pos-cafe` + sinkron Google Sheet.
**JANGAN keluar dari mapping di bawah** — semua keputusan sudah final.

Dokumen pendukung: `README.md` (arsitektur), `UI-UX.md` (desain), `PROGRESS.md` (checklist status),
`OAUTH-SETUP.md` (Google Cloud — SUDAH beres, kredensial lengkap).

## 1. Konsep inti (WAJIB)
- **Local-first, TANPA server.** Sumber kebenaran operasional = **SQLite di HP**. Jualan jalan **offline**.
- **Google Sheet = hub sync + laporan** (owner baca di PC). Bukan DB utama.
- **1 alat kasir.** Data awal = seed dari web (`assets/seed/seed.raw.json`) — jangan ganti isinya.

## 2. Tech stack (FINAL — jangan ganti)
Flutter + Material 3 (fokus terang) · sqflite (SQLite) · provider · shared_preferences ·
google_sign_in + googleapis + extension_google_sign_in_as_googleapis_auth + http · intl.
**WAJIB** `initializeDateFormatting('id_ID')` di `main()` (kalau lupa → crash locale di absen/rekap).

## 3. Peta file (lib/)
`main.dart` (root+init locale) · `models/models.dart` (semua model) ·
`services/db_helper.dart` (schema SQLite v2 — sumber kebenaran) · `services/seed_importer.dart` (impor seed) ·
`services/google_sheet_service.dart` (login + Sheets API: auto-create/push/pull/append) ·
`providers/pos_provider.dart` (katalog/keranjang/checkout/stok/sync) ·
`providers/settings_provider.dart` (font-scale, tema, PIN admin dari prefs **tak ditampilkan**, auto-lock 3mnt) ·
`ui/screens/*` (splash_setup, pos, recap, absen, admin_hub, receipt) · `ui/widgets/variant_sheet.dart`.

## 4. Tabel SQLite (patuhi)
`packaging` · `menu_items` · `variant_groups` · `variant_options` · `menu_stocks` (resep base) ·
`variant_option_stocks` (cup beda per Suhu) · `vouchers(+kuota,used_count,valid_from,valid_until)` ·
`employees` · `attendances` (presence historis) ·
`transactions(+business_date,status,voucher_name,void_reason)` · `transaction_items` · `cash_entries` · `settings`.

**Aturan bisnis:**
- Hari usaha 07:00–03:00, pemisah jam **6** (`pos_provider._businessDateKey`).
- Potong stok saat jual = `menu_stocks` (base) + `variant_option_stocks` (opsi terpilih).
- Voucher ditolak kalau nonaktif/di luar periode/kuota habis; `used_count++` saat pakai, `--` saat void.
- PIN admin dari prefs, **JANGAN ditampilkan**. Auto-lock 3 menit.

## 5. Sinkronisasi Google Sheet
1. Login Google (scope `spreadsheets`+`drive.file`).
2. `ensureSpreadsheet()`: ID kosong → **auto-create**; tab Menu kosong → **push katalog**.
3. Checkout → **append** baris ke tab Transaksi.
4. **Edit katalog di app** (menu/voucher/stok) → panggil `pos.syncCatalogUp()` → **push ke Sheet**.
5. `pullMenuFromSheet()` → tarik harga/aktif menu dari Sheet ke SQLite. Sync 15mnt + sekali saat buka.
> Urutan penting: **SEED dulu, baru push** (jangan kirim katalog kosong).

## 6. STATUS (per 2026-07-31)
**✅ Jalan:** POS (keranjang/varian/dine-in-bungkus/quick-cash/kembalian), checkout (hari usaha, item,
potong stok base+opsi, validasi voucher kuota/periode + used_count), **voucher selector di POS**,
Google sync (auto-create/push/append/pull), **admin CRUD** (menu/resep/varian/stok/voucher/karyawan/printer/ganti-PIN),
**edit app → push ke Sheet** (`syncCatalogUp`), admin refresh reaktif. APK debug build & install OK.
Fix crash locale id_ID (absen & rekap).

**❌ Masih DUMMY / belum ke-wire (lihat PROGRESS.md):**
1. **Rekap** — angka hardcode → wire ke transaksi asli (omzet/tunai-qris/kas/uang-di-laci + Tutup Kasir).
2. **Absen** — karyawan/shift hardcode → wire ke `employees` + simpan `attendances`.
3. **Kas/Pengeluaran** — belum ada input → `cash_entries`.
4. **Cetak thermal Bluetooth** — masih stub (channel `id.ruangsenyawa.pos/printer` belum diimplement native). Tambah plugin.
5. **Pull lengkap** semua tab + push absensi/kas + dedupe (UUID) + **ganti PIN baca dari Sheet**.
6. **Tablet split-view** (dual-pane) sesuai UI-UX.md.

## 7. Build & test (biar temen SAMA persis)
- Flutter: `C:\src\flutter\bin\flutter.bat` · Android SDK: `C:\Users\Dell\android-sdk` · Device `7e7d962`.
- Package/applicationId: **`id.ruangsenyawa.pos`** (JANGAN diubah — OAuth pecah).
- Cek cepat: `flutter analyze --no-pub`. **Build WAJIB `--debug`** (OAuth pakai SHA-1 debug):
  `flutter build apk --debug` → `build\app\outputs\flutter-apk\app-debug.apk`.
- Install: `adb install -r app-debug.apk` (ganti keystore → uninstall dulu). Log: `adb logcat -d -s flutter:V`.
- Google Cloud SUDAH setup (project `ruang-senyawa`, OAuth Android + SHA-1 + Sheets/Drive API + test user).
  **Ganti keystore/HP → daftarin SHA-1 baru.**

## 8. Definition of Done tiap batch
Layar **ambil/simpan ke SQLite** (bukan dummy) + edit katalog **push ke Sheet** + `flutter analyze` **0 error** +
**build APK sukses** + **teruji di HP** tanpa crash. Update `PROGRESS.md` tiap selesai.
