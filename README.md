# POS Cafe Mobile — Ruang Senyawa POS

Aplikasi kasir **Android (APK)** untuk Ruang Senyawa. **Local-first, tanpa server.**
Data operasional disimpan **lokal di HP** (SQLite); **Google Sheet** dipakai sebagai
**hub sinkronisasi + laporan** yang dibaca owner di PC.

> **STATUS: SUDAH DIBANGUN & JALAN** (bukan lagi rencana). Fase 1–3 sebagian besar beres:
> POS + varian + checkout + potong stok, admin CRUD (menu/bahan-inline/varian/voucher/PIN),
> Google Sheet sync (auto-create/push/pull/append). Sisa dummy: Rekap, Absen, Kas, printer BT.
> **Dokumen ini = rencana/arsitektur awal (cetak-biru).** Untuk **status real + peta kode + cara build**,
> baca **`PROGRESS.md`** dan **`HANDOFF.md`** (lebih update dari README ini).
> App web `pos-cafe` (Next.js) = blueprint logika & data model.

---

## 1. Konsep inti
- **Kasir tetap jalan walau internet/​server mati** — semua transaksi masuk SQLite lokal dulu.
- **Tidak ada server** untuk dibayar/diurus. Google Sheet = titik sinkron & sumber laporan.
- **1 alat kasir** (selamanya) → tidak perlu sinkronisasi antar-device yang rumit.
- **Owner cukup buka Google Sheet** (bikin grafik/laporan sendiri). Opsional buka app di HP sendiri (mode admin via PIN).

## 2. Arsitektur
```
        ┌─────────────────────── HP KASIR (APK) ───────────────────────┐
        │  UI Kasir/Admin  ──  Logika (stok, varian, harga)  ──  SQLite │  ← sumber kebenaran operasional, OFFLINE
        └───────────────▲───────────────────────────────┬──────────────┘
                        │ tarik katalog (15 mnt/manual) │ dorong transaksi (15 mnt/manual, append)
                        │                                ▼
                 ┌──────┴────────────────────────────────────────┐
                 │        GOOGLE SHEET (punya owner)              │  ← hub sync + laporan
                 │  tab: Menu, Bahan, Stok, Varian, Voucher,      │
                 │       Karyawan, Pengaturan, Transaksi, Absensi,│
                 │       Kas                                      │
                 └──────▲─────────────────────────────────────────┘
                        │ baca / bikin grafik & pivot
                 ┌──────┴──────┐        ┌─────────────────────────┐
                 │ Owner di PC │        │ (opsional) Owner di HP  │
                 └─────────────┘        │  app + PIN admin        │
                                        └─────────────────────────┘
```

## 3. Aturan sinkronisasi (paling penting)
**Prinsip: sebisa mungkin _append-only_ (nambah baris), biar tak ada tabrakan tulis.**

**Turun (Sheet → HP)** — katalog, master di Sheet, ditarik saat refresh/15-menit:
`Menu, Bahan, Varian (+bahan opsi), Voucher, Karyawan, Pengaturan`, dan baris **Stok MASUK**.

**Naik (HP → Sheet)** — operasional, dihasilkan HP, di-append saat sync:
`Transaksi, TransaksiItem, Absensi, Kas`, dan baris **Stok KELUAR** (dari penjualan).

**Stok = buku besar (ledger):**
`stok sekarang(bahan) = Σ MASUK − Σ KELUAR`.
Owner menambah **MASUK** (belanja/restock) di Sheet; HP menulis **KELUAR** otomatis tiap jual.
Keduanya hanya menambah baris → **aman, tak rebutan.**

**Edit katalog dari HP (PIN admin):** boleh, hasil edit ikut di-push ke Sheet.
Karena 1 alat + 1 owner, bentrok nyaris mustahil → pakai **last-write-wins** (baris ada
kolom `updatedAt`; yang terbaru menang saat refresh).

**Anti-dobel:** tiap record punya **UUID**; sync hanya mendorong record yang `synced=false`,
lalu menandainya. Offline → antre; begitu online → kirim. **Jualan tak pernah nunggu jaringan.**

**Interval:** auto tiap **15 menit** (saat online) + tombol **"Sync sekarang"** di Setelan.

## 4. Peran & login
- **HP kasir**: auto masuk sebagai **KASIR**. Tak perlu ketik password tiap buka.
- **PIN admin**: buka mode admin di alat yang sama (atur menu/stok/setelan, lihat laporan).
- **Akun Google (owner)**: dipakai **sekali** saat setup untuk memberi izin app menulis ke
  Sheet milik owner. Scope **`drive.file`** saja (app hanya menyentuh file yang ia buat).
  Token disimpan di HP. Ini **izin ke Sheet**, bukan identitas per-orang.
- **Owner di HP sendiri (opsional)**: install app, masuk mode admin via PIN → lihat/atur,
  sinkron lewat Sheet yang sama.

## 5. Menu / fitur aplikasi
Mengikuti app web yang sudah jadi (tanpa sisi server admin):

**A. Kasir (POS)** — default
- Grid menu per kategori + cari.
- Klik menu → **popup varian** (Suhu Panas/Dingin, Shot, dll) + catatan per item.
- Keranjang: ubah qty / **ubah varian** / hapus item.
- **Makan di tempat / Bungkus**.
- Bayar: **Tunai** (uang diterima + kembalian + tombol nominal), **QRIS/Transfer** (tanpa kembalian).
- **Diskon/voucher** (mis. "Owner Gratis").
- **Struk** → cetak ke **printer thermal Bluetooth** (plugin native) + simpan.
- **Batalkan (void)** transaksi → stok balik.

**B. Rekap (hari ini, lokal)**
- Omzet, jumlah transaksi, per kategori/metode.
- **Kas & Pengeluaran**: catat beli es dll (kasir bisa input).
- **Kas awal + Uang di laci (estimasi)** untuk rekonsiliasi tutup.

**C. Absen** — presence-only
- Tiap karyawan tombol shift (Sore/Malam). **Klik = masuk** (toggle). Tanpa jam pulang.

**D. Admin (buka pakai PIN)**
- Menu & harga, Varian (+ bahan per opsi: Panas→cup panas, Dingin→cup plastik),
  Stok/Bahan (tambah MASUK), Karyawan.
- **Voucher (ditingkatkan):** selain aktif/nonaktif, tambah **kuota pemakaian**
  (mis. maks 50×) & **periode berlaku** (dari tanggal – sampai tanggal). Saat jual, voucher
  ditolak kalau kuota habis / di luar periode. (Fitur ini juga bakal ditambahkan ke app web.)
- Pengaturan: nama cafe, **logo**, jam buka/tutup + pemisah hari usaha, shift, kas awal,
  header/footer struk, lebar kertas.

**E. Sinkronisasi / Setelan data**
- Pilih/hubungkan **Google Sheet** (login Google owner).
- **Refresh sekarang** (tarik katalog terbaru) + status "terakhir sync".
- On/off **auto-sync 15 menit**.
- Backup DB ke Drive (opsional).

## 6. Struktur Google Sheet (rancangan tab)
| Tab | Arah | Kolom inti |
|-----|------|-----------|
| Pengaturan | ⇅ | key, value |
| Bahan | ⬇ | nama, satuan, stok_min |
| Stok | ⬇ MASUK / ⬆ KELUAR | uuid, waktu, bahan, tipe, jumlah, sumber, catatan |
| Menu | ⬇ (edit HP ⬆) | uuid, nama, kategori, harga, modal, aktif, urutan, updatedAt |
| Varian | ⬇ | uuid, menu, grup, tipe, wajib, opsi, priceDelta, updatedAt |
| VarianBahan | ⬇ | uuid, opsi, bahan, qty |
| Voucher | ⬇ | uuid, nama, tipe, nilai, aktif, kuota, terpakai, berlaku_dari, berlaku_sampai |
| Karyawan | ⬇ | uuid, nama, aktif |
| Transaksi | ⬆ | kode, waktu, hariUsaha, kasir, tipe, metode, subtotal, diskon, voucher, total, status, catatan |
| TransaksiItem | ⬆ | kodeTransaksi, menu, varian, catatan, qty, harga, subtotal |
| Absensi | ⬆ | uuid, hariUsaha, karyawan, shift |
| Kas | ⬆ | uuid, waktu, hariUsaha, tipe, kategori, nominal, catatan, oleh |

## 7. Kendala & risiko (+ mitigasi)
1. **HP hilang/rusak** → data ≤15 menit belum sync bisa hilang. → sync 15 mnt + backup DB ke Drive; Sheet = arsip permanen penjualan.
2. **Sheet bukan database** → aman selama pola *append-only* + 1 penulis penjualan. Katalog dijaga kecil; edit katalog pakai last-write-wins.
3. **OAuth Google** → butuh Google Cloud project + consent screen; scope `drive.file`; owner sebagai test user (hindari verifikasi ribet). Muncul peringatan "unverified" sekali saat setup (wajar).
4. **Kuota Sheets API** → aman di skala ini (append tiap 15 menit).
5. **Printer thermal Bluetooth** → butuh plugin native + tes per-merk printer.
6. **Jam / hari usaha** → dihitung di HP (TZ Asia/Jakarta), buka 07:00–03:00 pakai pemisah hari.
7. **Distribusi APK** → sideload (tanpa Play Store); perlu tanda-tangan APK; update manual (atau pakai layanan OTA).
8. **Konsistensi stok** → kalau owner ubah stok manual di Sheet, pakai baris OPNAME (set nilai) biar ledger tetap benar.

## 8. Teknologi — **Flutter** (DIPUTUSKAN)
Flutter + Dart, DB lokal **`drift`/`sqflite`** (SQLite), dibungkus jadi APK Android
(**dan siap ke iOS nanti** tanpa tulis ulang — alasan utama dipilih Flutter).
Paling rapi & 1 codebase lintas platform.

- **Reuse dari app web `pos-cafe`**: bukan komponen UI, tapi **logika & data model** —
  aturan potong stok, varian, harga, hari-usaha, voucher (kuota/periode) semuanya sudah
  teruji di web → jadi **spesifikasi persis** yang tinggal diport ke Dart.
- **Printer thermal:** dukung **banyak merek** via **ESC/POS over Bluetooth**
  (paket Flutter mis. `esc_pos_bluetooth`/`print_bluetooth_thermal`) — satu protokol umum
  yang jalan di mayoritas printer thermal; tambah handler khusus bila ada printer rewel.
  Layar Setelan → scan, pilih & tes printer.
- **Sync Google Sheet:** paket `googleapis` + `google_sign_in` (scope `drive.file`).

> Trade-off yang diterima: UI ditulis dari nol di Flutter (lebih lama dari Capacitor),
> ditukar dengan hasil **paling rapi + siap iOS**. Sesuai keputusan owner.

## 9. Rencana bertahap (fase)
- **Fase 0 — Plan (sekarang):** dokumen ini + sepakati struktur Sheet & teknologi.
- **Fase 1 — Kasir offline:** POS + varian + stok ledger + struk, **100% lokal** (belum sync). Bisa langsung dipakai jualan.
- **Fase 2 — Sync Sheet:** login Google, push transaksi + tarik katalog, auto 15 menit + manual.
- **Fase 3 — Admin/PIN & laporan:** edit katalog di HP, rekap, absen, kas.
- **Fase 4 — Poles:** printer Bluetooth, backup DB, template Sheet siap-pakai buat owner (grafik).

## 10. Keputusan (sudah diambil)
1. **Teknologi = Flutter** (siap iOS, paling rapi). ✔
2. **Printer** = banyak merek via ESC/POS Bluetooth (+ plugin tambahan bila perlu). ✔
3. **Template Sheet owner** = dibuat, siap pakai — tab **Dashboard, Rekap, Penjualan Harian,
   Stok, Voucher, Absensi, Kas** + grafik/pivot. Owner tinggal buka. ✔
4. **PIN = 1 PIN global**, bisa di-set dari Sheet (tab Pengaturan). ✔
   ⚠️ Catatan: PIN di Sheet = teks biasa (keamanan ringan, sekadar cegah utak-atik di alat;
   bukan password beneran). Bisa di-hash kalau mau lebih aman.
5. **Data awal** = di-ekspor dari **data live di dev server** sekarang (menu/varian/stok/
   voucher/karyawan/pengaturan R Senyawa) → jadi isi awal Sheet. Seeder valid & langsung pakai. ✔
6. **Nama/ikon**: app **"Ruang Senyawa POS"**, ikon = **logo IG @r_senyawa** (yang sudah dipakai),
   package id **`id.ruangsenyawa.pos`** (JANGAN diubah — OAuth Android dimatch pakai package+SHA-1). ✔

## 11. Kinerja & retensi data (jawab: "app berat kalau lama dipakai?")
Aman, asalkan 2 aturan ini diterapkan:
- **Katalog di-REPLACE, bukan ditumpuk.** Menu/stok/varian/voucher/karyawan/pengaturan
  di-*upsert* tiap sync (data terbaru menimpa). Jadi **tidak numpuk** — ukurannya tetap.
- **Transaksi lokal pakai jendela retensi.** Tiap jual nambah baris lokal, tapi:
  - SQLite santai megang ratusan ribu–jutaan baris (100 trx/hari × setahun ≈ 36rb baris → enteng).
  - Yang sudah **ter-sync ke Sheet** dan lebih tua dari mis. **30 hari** → **di-prune** dari HP.
    Riwayat penuh tetap ada di Sheet. Rekap "hari ini/minggu ini" di HP → instan; riwayat lama
    → owner lihat di Sheet.
  → **App tetap ringan selamanya.**
- **Sisi Sheet**: numpuk permanen (memang arsip). Batas ~10 juta sel; kalau sudah bertahun-tahun,
  **rotasi per tahun** (tab `Transaksi-2026`, `Transaksi-2027`, …). Tidak mempengaruhi kecepatan app.

Jadi soal "login kasir ambil sheet harian" — betul arahnya: HP hanya butuh **katalog terbaru +
transaksi hari berjalan**, sisanya diarsipkan di Sheet. Nggak numpuk di app. 👍
```
