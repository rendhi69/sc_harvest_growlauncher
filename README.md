# Auto Harvest Pro - Growlauncher (Boren Store)

Script Auto Harvest Growlauncher generasi terbaru dengan dukungan Multi-World Save Table (pilihan ALL / BLOCK / SEED), Event Mooncake Table dengan Limit Total, Unified Magni & Fuel, Gear Equip ID List, Ignore Gems, Mode 3-Zigzag, dan Take Floating.

## Pembaruan Fitur Terbaru (v1.2.0)
1. **Daftar Multi-World Save Berbasis Tabel Interaktif**:
   - Setiap Save World memiliki opsi tipe penyimpanan tersendiri: `ALL` (Block + Seed), `BLOCK` saja, atau `SEED` saja.
   - Dilengkapi tombol navigasi atas/bawah, hapus baris, dan penambahan cepat dari world aktif saat ini.
2. **Perbaikan Tampilan & Anti-Teks Terpotong**:
   - Label tombol disederhanakan (`[ Gabung ]`, `[ Block ]`, `[ Seed ]`) dan jarak layout dirapikan dengan `uiGap()`, mencegah teks terpotong di layar HP Android.
3. **Limit Item per World yang Fleksibel**:
   - Limit dapat diatur secara kustom via Input Angka atau tombol cepat (`10.000`, `20.000`, `50.000`, `Unlimited`).
4. **Default Drop Threshold 200 Block**:
   - Threshold tas default diset ke **200 block** untuk efisiensi drop maksimal.
5. **Daftar Multi-World Event dengan Limit Total**:
   - World event (Mooncake dll.) kini berbentuk tabel interaktif dengan limit total item per world.
   - Preset 5 jenis Mooncake (`1058,1094,1096,1098,1828`) siap pakai 1x klik.
6. **Integrasi Magni + Fuel & Gear Equip ID List**:
   - Restock **Magnifying Glass (1252)** dan **Fuel Pack (1746)** disatukan dalam 1 tombol praktis.
   - Peralatan panen (DCS, Harvester, dll.) kini berupa kolom daftar ID fleksibel (`gear_equip_ids`) dengan preset cepat: `DCS + Harvester (6840, 1966)`, `Harvester Saja (1966)`, `DCS Saja (6840)`.
7. **Standarisasi Tampilan Sesuai Skrip Modern**:
   - Tipografi rapi, pembatas visual jelas, palet warna serasi (Neon Cyan/Purple/Dark Glass), dan navigasi dual interface: Standalone Dear ImGui + Native Growlauncher 5-Tab Menu.

## Cara Pakai
Jalankan `loader_harvest.lua` di Growlauncher untuk mengunduh versi terbaru secara otomatis langsung dari GitHub.
