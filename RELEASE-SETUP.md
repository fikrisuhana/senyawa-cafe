# Setup Release & Testing — Ruang Senyawa POS

Panduan buat owner: setup GitHub Actions auto-build APK + daftarin email tester biar bisa login Google.

---

## 1. Setup GitHub Secrets (WAJIB sekali, biar APK release jalan)

CI butuh keystore signing buat bikin APK release yg login Google-nya jalan.
Tanpa ini, APK tetap ke-build tapi **login Google akan gagal** (SHA-1 beda dgn yg terdaftar).

### Langkah:
1. **Encode keystore ke base64** di laptop (pakai Git Bash / WSL):
   ```bash
   cd C:\Users\Dell\pos-cafe-mobile\android\app
   base64 -w 0 ruang_senyawa.jks
   ```
   → copy seluruh output (string panjang base64).

2. **Buka GitHub** repo → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**.

3. Tambah 2 secret:
   | Name | Value |
   |---|---|
   | `KEYSTORE_BASE64` | (paste output base64 dari langkah 1) |
   | `KEYSTORE_PASSWORD` | `RuangSenyawa2026` |

4. Selesai. Build berikutnya (tiap push ke main) bakal pakai keystore ini → SHA-1 konsisten → OAuth jalan.

> **Catatan SHA-1:** SHA-1 dari `ruang_senyawa.jks` ini mungkin **BEDA** dgn SHA-1 debug (`93:C0:...`) yg sudah terdaftar di Google Cloud. Kalau tester login gagal dgn error "developer", jalankan:
> ```bash
> keytool -list -v -keystore android/app/ruang_senyawa.jks -alias ruangsenyawa -storepass RuangSenyawa2026 | grep SHA1
> ```
> Copy SHA-1 itu → tambahin di Google Cloud Console (Credentials → OAuth client → Android client → +SHA certificate). Lihat bagian 3.

---

## 2. Tambah Email Tester (OAuth Testing)

Aplikasi masih mode **"Testing"** di Google Cloud → hanya email terdaftar yg bisa login Google.

### Cara daftarin tester baru:
1. Buka [Google Cloud Console](https://console.cloud.google.com/) → pilih project **Ruang-Senyawa**.
2. Menu **APIs & Services** → **OAuth consent screen**.
3. Bagian **Test users** → **+ ADD USERS**.
4. Ketik email Gmail tester → **Save**.

Tester sekarang bisa login Google di app. Maksimal 100 email di mode Testing.

> Kalau mau **semua orang** bisa login tanpa daftar email → harus **publish** OAuth consent screen (submit verification ke Google, butuh privacy policy URL, proses 2-6 minggu). Buat testing/beta cukup daftar email manual.

---

## 3. Cek/Tambah SHA-1 ke Google Cloud (kalau login tester gagal)

Login Google gagal dgn error "developer" / `DEVELOPER_ERROR` artinya SHA-1 APK beda dgn yg terdaftar.

### Cek SHA-1 dari keystore release:
```bash
keytool -list -v -keystore android/app/ruang_senyawa.jks -alias ruangsenyawa -storepass RuangSenyawa2026 | grep SHA1
```

### Cek SHA-1 dari APK (kalau dari CI, download dulu APK-nya):
```bash
keytool -printcert -jarfile app-release.apk | grep SHA1
```

### Daftar SHA-1 baru:
1. Google Cloud Console → **APIs & Services** → **Credentials**.
2. Klik **OAuth client** (Android, nama "Ruang Senyawa").
3. Bagian **Package name**: `id.ruangsenyawa.pos` (sudah ada).
4. Bagian **SHA-1 certificate fingerprint** → **+ Add package / fingerprint** → paste SHA-1.
5. **Save**. Tunggu ~5 menit biar propagate.

---

## 4. Trigger Build Manual

Selain otomatis tiap push ke main, lo bisa trigger build manual:
1. Repo GitHub → tab **Actions**.
2. Pilih workflow **"Build & Release APK"**.
3. Klik **Run workflow** → pilih branch `main` → **Run workflow**.
4. Tunggu ~5-10 menit. APK muncul di:
   - **Artifacts** (download dari halaman run, retensi 90 hari)
   - **Releases** (halaman repo → Releases, tagged `v<run-number>`)

---

## 5. Troubleshooting Tester

| Masalah | Solusi |
|---|---|
| Login Google error "access blocked" | Email tester belum didaftarkan (lihat bagian 2) |
| Login Google error `DEVELOPER_ERROR` | SHA-1 APK beda, daftarin SHA-1 baru (lihat bagian 3) |
| APK tidak jalan / crash di install | Pastikan HP Android 5.0+ (minSdk), enable "Install unknown apps" |
| Spreadsheet kosong setelah login | Wajar, tab auto-generate saat pertama login. Lakukan transaksi → data muncul |
| Tester ga bisa lihat Sheet punya owner | Setiap tester punya Sheet sendiri (scope `drive.file`). Untuk share 1 Sheet: buka Sheet owner → **Share** → masukin email tester dgn akses Viewer/Editor |
