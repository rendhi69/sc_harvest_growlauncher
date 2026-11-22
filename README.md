# BOREN STORE - AUTO HARVEST PRO

Skrip otomatisasi Auto Harvest Pro untuk Growlauncher dengan Multi-World Farm & Save List, Auto Magni & Fuel Guard, Gear Equip, dan Console ImGui.

## Repository Khusus
Repository ini dikhususkan **HANYA** untuk skrip dan loader **Harvest**.
Tidak ada file dari skrip lain (Plant, Dirt Farm, Soil Builder, Transfer, Harvest) yang tercampur di sini.

## File Utama
- `auto_harvest.lua`: Skrip mandiri lengkap (Full Engine & UI)
- `loader.lua`: Loader langsung untuk `auto_harvest.lua` dengan auto-fetch & auto-update dari GitHub
- `loader_harvest.lua`: Loader Console ImGui khusus fitur Harvest
- `mod_harvest.lua`: Modul ImGui Console
- `imgui_hub/`: Direktori bootloader dan dependensi runtime Console ImGui mandiri

## Cara Menjalankan di Growlauncher
1. **Menggunakan Loader Otomatis:**
   Eksekusi kode berikut di executor Growlauncher:
   ```lua
   fetch("https://raw.githubusercontent.com/rendhi69/sc_harvest_growlauncher/main/loader.lua?v=" .. os.time())()
   ```
   atau jalankan file `loader.lua` yang tersimpan di perangkat Anda.

2. **Menggunakan Console ImGui:**
   Jalankan `loader_harvest.lua`.

---
Dikembangkan oleh **Boren Store** / **rendhi69**.
