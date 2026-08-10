# Setup Google OAuth — Ruang Senyawa POS

Kode `google_sign_in` sudah ada, TAPI Google tidak mengizinkan login/akses Sheet
sampai app didaftarkan. Ikuti langkah ini **sekali** (dilakukan pemilik/owner).

## ✅ STATUS: SEMUA SYARAT GOOGLE CLOUD SUDAH BERES (2026-07-31)
| Item | Nilai / Status |
|---|---|
| Project name | **Ruang-Senyawa** |
| Project ID | `ruang-senyawa` |
| Project number | `766450411641` |
| OAuth Consent Screen | **External**, mode Testing ✅ |
| Test user | email owner sudah ditambahkan ✅ |
| OAuth Client (Android) | nama "Ruang Senyawa" ✅ |
| → Client ID | `766450411641-27868gu4f4l988a0v922p91fsgifjqii.apps.googleusercontent.com` |
| → Package name | `id.ruangsenyawa.pos` |
| → SHA-1 (debug) | `93:C0:B4:83:DE:93:17:6B:23:7C:92:AD:4B:B2:60:25:B6:A8:69:69` |
| Google Sheets API | **Enabled** ✅ |
| Google Drive API | **Enabled** ✅ |
| Spreadsheet | **auto-create** saat login (tak perlu bikin manual) |

> Client ID **tidak** perlu ditempel di kode (Android dicocokkan via package + SHA-1).
> Client "Desktop" (kalau sempat kebikin) boleh dihapus/diabaikan — yang dipakai = **Android**.
> SHA-1 **release** (untuk APK sebar) beda dari debug → daftarkan lagi nanti kalau bikin APK rilis.

**Sisa (bagian aku):** implementasi `GoogleSheetService` asli (auto-create sheet + push katalog +
push transaksi + pull perubahan) menggantikan stub. Lalu test di HP: login → transaksi masuk Sheet.

---
## (Arsip) Langkah setup — kalau perlu ulang di HP/keystore lain

## Data app kamu (buat diisi ke Google Cloud)
- **Package name / applicationId:** `id.ruangsenyawa.pos`
- **SHA-1 (debug — untuk `flutter run` & tes):**
  `93:C0:B4:83:DE:93:17:6B:23:7C:92:AD:4B:B2:60:25:B6:A8:69:69`
- SHA-1 **release** (untuk APK yang disebar) beda — daftarkan juga nanti kalau bikin APK rilis.

## Langkah di Google Cloud Console (console.cloud.google.com)
1. **Buat Project** baru, mis. "Ruang Senyawa POS".
2. **APIs & Services → Enable APIs**: aktifkan **Google Sheets API** dan **Google Drive API**.
3. **OAuth consent screen**:
   - User type: **External**. Isi nama app + email support.
   - Scopes: tambah `.../auth/spreadsheets` dan `.../auth/drive.file`.
   - **Test users**: tambahkan **email Gmail owner** (biar app "unverified" tetap bisa dipakai owner).
   - Status: **Testing** (nggak perlu verifikasi ribet buat 1 cafe).
4. **Credentials → Create Credentials → OAuth client ID**:
   - Application type: **Android**
   - Package name: `id.ruangsenyawa.pos`
   - SHA-1: (paste yang di atas)
   - Simpan.
5. **Buat Spreadsheet laporan**: owner bikin Google Sheet kosong, buka, salin **ID** dari URL
   (`docs.google.com/spreadsheets/d/<INI_ID_NYA>/edit`). ID ini diisi di layar setup app.

> Catatan: untuk `google_sign_in` Android, client ID **tidak** perlu ditempel di kode —
> Google mencocokkan lewat **package + SHA-1**. Yang penting OAuth client Android terdaftar.

## Setelah setup selesai
1. Kabari aku → aku **implementasi GoogleSheetService beneran** (sekarang masih stub):
   - Pull katalog (menu/stok/varian/voucher) dari Sheet → SQLite HP.
   - Push transaksi/absensi/kas → Sheet (append).
   - Aktifkan `_googleConnected` + sync 15 menit.
2. Baru bisa dites: **edit data di Sheet → app ikut berubah** (dan sebaliknya).

## Kenapa spreadsheet masih kosong sekarang?
Karena `google_sheet_service.dart` **masih rangka/stub** (cuma log, belum panggil Sheets API).
Jadi bukan bug — memang belum diimplementasi. Butuh: (a) OAuth di atas (kamu), (b) coding Sheets (aku).
