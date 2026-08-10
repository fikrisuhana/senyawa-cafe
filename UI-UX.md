# POS Cafe Mobile — Rancangan UI/UX (Flutter)

Rancangan tampilan & alur aplikasi **Ruang Senyawa POS**. Turunan gaya dari app web `pos-cafe` (nama brand: **Ruang Senyawa**), diadaptasi untuk **HP Kasir & Tablet Meja Kasir**.

---

## 1. Prinsip Desain
- **Nama Store & Brand**: **Ruang Senyawa** (Logo & Footer Struk presisi dari seeder database web).
- **Kasir-First**: Layar jualan paling gampang, tombol **besar**, minim ketik.
- **Pengaturan Ukuran Teks di Dalam Aplikasi**:
  - Di layar **Setelan App (Screen 15)**, kasir bisa mengatur skala teks: `Ringkas (88%)`, `Normal (100%)`, `Besar / Tablet (115%)`.
  - Sangat berguna saat app dijalankan di Tablet 7" / 10" agar teks & tombol dapat membesar sesuai kebutuhan mata kasir.
- **Minim Scroll (Low Friction Layout)**:
  - **Di HP**: Layar ringkas + Bottom Sheet keranjang cepat.
  - **Di Tablet / Meja Kasir**: Layar **Dual-Pane Split-View** (Katalog Menu di kiri + Keranjang Permanen di kanan). Kasir **bebas dari buka-tutup popup atau geser-geser panjang**.
- **Selalu Tahu Status**: Indikator **online/offline** & **terakhir sync** kelihatan terus.
- **Bayar Cepat (Quick Cash)**: Chip nominal pas, 20k, 50k, 100k untuk hitung kembalian cepat tanpa ketik manual.
- **Keamanan Admin**: Mode Admin dengan **Auto-Lock 3 menit** inaktivitas.

---

## 2. Dynamic Font Scaling & Layout Responsif
- **Ukuran Teks App (Settings)**:
  - `MediaQuery.of(context).textScaler` / `var(--font-scale)` diset via menu Setelan App.
- **Responsif Split View (Tablet vs HP)**:
  - `width < 600dp` → Single Pane HP + Bottom Sheet Keranjang.
  - `width ≥ 600dp` → Dual Pane Tablet (Katalog Kiri + Keranjang Permanen Kanan).

---

## 3. Wireframe Layar Tablet / POS (Split View — Dual Pane)
```
┌─────────────────────────────────────────────────────────────────────────────┐
│ (logo) Ruang Senyawa POS — Mode Tablet     ● Online (2m lalu) · Shift Sore  │
├──────────────────────────────────────────┬──────────────────────────────────┤
│ KIRI: KATALOG MENU & FILTER              │ KANAN: KERANJANG PERMANEN        │
│ [🔍 Cari menu cepat…                   ✕] │ Pesanan (3 item)          [Reset]│
│ [ALL] [☕ KOPI] [🍵 NON-KOPI] [🍟 MAKAN] │ [🍽️ Di tempat] [🥡 Bungkus]     │
│ ┌──────────────┐ ┌──────────────┐        │ ──────────────────────────────── │
│ │ Kopi Susu Oat│ │ Americano    │        │ Kopi Susu Oat         Rp21.000   │
│ │ Rp15.000     │ │ Rp13.000     │        │  • Dingin, Extra Shot   − 1 +    │
│ └──────────────┘ └──────────────┘        │ Americano             Rp13.000   │
│ ┌──────────────┐ ┌──────────────┐        │  • Dingin             − 1 +    │
│ │ Indomie Grmg │ │ Lemon Mint   │        │ ──────────────────────────────── │
│ │ ⚠️ sisa 4    │ │ Rp15.000     │        │ Subtotal              Rp34.000   │
│ └──────────────┘ └──────────────┘        │ Diskon                −Rp4.000   │
│                                          │ TOTAL BAYAR           Rp30.000   │
│                                          │ [✓ TUNAI] [QRIS] [TRANSFER]      │
│                                          │ Quick Cash: [Pas] [50k] [✓ 100k] │
│                                          │ ┌──────────────────────────────┐ │
│                                          │ │   Bayar Rp30.000 (Kembali 70k) │ │
│                                          │ └──────────────────────────────┘ │
└──────────────────────────────────────────┴──────────────────────────────────┘
```

---

## 4. Pengaturan Teks di Layar Setelan App (Screen 15)
```
┌───────────────────────────────────────┐
│ Setelan Aplikasi                      │
│ 🗚 Ukuran Teks Aplikasi               │
│ [ Ringkas (88%) ] [ ✓ Normal ] [ Besar (Tablet) ]│
│ ───────────────────────────────────── │
│ 📱 Tampilan & Layout                  │
│ Tema: [ Terang ] [ Gelap ]            │
│ Mode Tablet Split-View: (ON/OFF)      │
└───────────────────────────────────────┘
```
