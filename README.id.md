<p align="center"><a href="README.md">English</a> · <b>Bahasa Indonesia</b></p>

<p align="center"><img src="docs/banner.id.png" alt="Amnesia" width="100%"></p>

<p align="center">
  <b>Setiap kali kamu logout, Mac kamu lupa semuanya.<br>Kecuali yang memang kamu mau simpan.</b>
</p>

<p align="center">
  <a href="../../releases/latest"><b>⬇️ Download app</b></a> ·
  <a href="https://navi-crwn.github.io/amnesia-mac/">Website</a> ·
  <a href="#cara-pasang">Cara pasang</a> ·
  <a href="#pertanyaan-umum">FAQ</a> ·
  <a href="#cara-hapus">Cara hapus</a> ·
  <a href="CHANGELOG.id.md">Changelog</a> ·
  <a href="TERMS.id.md">Ketentuan</a>
</p>

> [!WARNING]
> **Amnesia benar-benar menghapus data.** Setelah aktif, semua yang ada di luar folder Keep dan Keep List dihapus setiap logout, restart dan shutdown. Tidak masuk Trash dan tidak bisa dibatalkan. Baca dulu [ketentuan & peringatan](TERMS.id.md) yang singkat ini sebelum memasang.

---

## Apa itu Amnesia?

Bayangkan Mac kamu seperti meja kerja. Setiap selesai kerja, Amnesia **membereskan mejanya sampai bersih**: riwayat browser, cookie, file download, cache, riwayat Terminal, semuanya hilang. Besok kamu mulai lagi dari meja yang rapi, tanpa jejak kemarin.

Masalahnya, kalau semua hilang, kamu harus login ulang Gmail, WhatsApp, Telegram, dan lain-lain setiap hari. Itu bisa makan 15–20 menit. Karena itu Amnesia punya **Profile Vault**: brankas terkunci yang menyimpan login-login kamu. Habis login ke Mac, cukup ketik **1 password**, dan semua login kembali seperti semula.

**Cocok untuk kamu yang:**
- memakai Mac bersama orang lain, atau di tempat umum,
- tidak mau ada jejak kerja yang tertinggal,
- ingin Mac tetap ringan dan bersih setiap hari.

<p align="center"><img src="docs/fitur.png" alt="Fitur Amnesia" width="100%"></p>

<p align="center">
  <img src="docs/screens/id/home.png" alt="Home" width="32%">
  <img src="docs/screens/id/keep-setup.png" alt="Pilih yang disimpan" width="32%">
  <img src="docs/screens/id/backup.png" alt="Backup" width="32%">
</p>

<details>
<summary><b>Screenshot lainnya</b></summary>
<p align="center">
  <img src="docs/screens/id/tour-welcome.png" alt="Tur perkenalan" width="32%">
  <img src="docs/screens/id/tour-terms.png" alt="Baca ini dulu" width="32%">
  <img src="docs/screens/id/tour-check.png" alt="Cek dulu" width="32%">
  <img src="docs/screens/id/vault.png" alt="Profile Vault" width="32%">
  <img src="docs/screens/id/keep.png" alt="Keep List" width="32%">
  <img src="docs/screens/id/preview.png" alt="Yang akan dihapus" width="32%">
  <img src="docs/screens/id/settings.png" alt="Pengaturan" width="32%">
  <img src="docs/screens/id/home-dark.png" alt="Mode gelap" width="32%">
  <img src="docs/screens/id/menu.png" alt="Menu bar" width="32%">
</p>
</details>

## Apa yang dihapus, apa yang aman?

| 🗑️ Dihapus setiap logout | ✅ Tetap aman |
|---|---|
| Riwayat & cookie browser | Isi **folder Keep** kamu (bawaannya `~/Keep`; boleh di mana saja, nama apa saja) |
| Isi Desktop, Downloads, Documents, Pictures | Login yang disimpan di **Profile Vault** |
| Cache, log, riwayat Terminal | Semua yang ada di **Keep List** (VPN, kunci SSH, setting Terminal, dll.) |
| Data app yang tidak kamu pilih | App yang terpasang di `/Applications` dan Homebrew |

Mau tahu persis apa yang akan dihapus **tanpa menghapus apa pun**? Jalankan:

```bash
bash ~/.amnesia/clean.sh logout --dry-run
```

## Fitur

- **🛡️ Bersih otomatis.** Pembersihan berjalan **sebelum** Mac logout, restart, atau shutdown. Saat login berikutnya Amnesia mengecek ulang, jadi kalau ada yang terlewat, ikut dibersihkan.
- **🔐 Profile Vault.** Login Chrome (Gmail, WhatsApp Web, Telegram Web), Claude, WhatsApp, dan alat coding seperti Claude Code, OpenCode, Gemini CLI, GitHub CLI disimpan dalam brankas terenkripsi (AES-256). Untuk memulihkan, cukup 1 password.
- **⏏️ Simpan & Logout.** 1 klik: login kamu disimpan dulu ke vault, baru Mac logout. Kalau penyimpanannya gagal, logout dibatalkan, jadi tidak ada yang hilang.
- **⏸️ Jeda 1 Sesi.** Butuh Mac tidak dibersihkan sekali saja? Tekan Jeda. Setelah 1x logout dan login, Amnesia aktif lagi sendiri.
- **📌 Keep List.** Pilih folder atau app yang tidak boleh ikut dihapus, langsung dari app. Nyalakan sebuah app dan kamu lihat persis apa yang disimpan (data app, setting, ukurannya).
- **🗂️ Folder Keep milikmu.** File di dalamnya tidak pernah dihapus. Taruh di mana saja (bahkan di drive eksternal) dan beri nama apa saja.
- **💾 Backup ke mana saja.** Folder pilihan dikunci jadi 1 file `.7z` (AES-256), lalu dikirim ke:
  - **Flashdisk / SSD** yang tercolok,
  - **Server sendiri / VPS** lewat SSH + rsync. Ketik password server sekali, Amnesia yang menyiapkan kuncinya. Tanpa Terminal.
  - **Cloud**: Google Drive, Dropbox, OneDrive, Box atau pCloud. Login di jendela kecil, tanpa Terminal dan tanpa Chrome. (S3, WebDAV dan 40+ lainnya lewat rclone.)
- **⏰ Backup terjadwal.** Harian atau mingguan, jalan sendiri selama ikon Amnesia ada di menu bar.
- **🚚 Pindah Mac.** Bawa semua login ke Mac baru: kunci Keychain ikut disimpan ke vault, vault ikut ke backup, lalu dipulihkan di Mac baru.
- **👋 Tur perkenalan.** Saat pertama dibuka, Amnesia mengajak kamu keliling, cek semua sudah siap, mendeteksi app kamu, lalu tanya mana yang datanya mau disimpan.
- **🔥 Tombol darurat.** Kalau password vault salah 3x, atau kamu mengetik *kata panik* yang sudah kamu atur, vault langsung dimusnahkan.
- **👀 Cek dulu sebelum logout.** Logout atau restart lewat menu Apple ditahan sebentar, lalu kamu lihat dulu apa saja yang akan dihapus. Lanjut atau batal, kamu yang pilih. Daftarnya disiapkan di background, jadi langsung tampil.
- **🏠 Offline & privat.** Tanpa server, tanpa akun, tanpa pelacakan, tanpa pengumpulan data. Tidak ada yang keluar dari Mac kamu kecuali kamu sendiri yang mengatur backup.
- **📸 Snapshot otomatis.** Lupa menekan Simpan & Logout? Login kamu tetap disimpan ke vault saat logout biasa.
- **🔔 Notifikasi.** Setelah login, Amnesia memberi tahu bahwa Mac sudah bersih dan mengingatkan untuk restore profil.
- **⚙️ Pengaturan.** Semua fitur di atas bisa dinyalakan atau dimatikan sesukamu.
- **🌐 2 bahasa.** English atau Bahasa Indonesia, tinggal pilih di Pengaturan.
- **🟢 Ikon di menu bar.** Status Amnesia selalu terlihat di pojok kanan atas: hijau aktif, oranye jeda, merah mati.

## Cara pasang

**Yang dibutuhkan:** macOS 15 atau lebih baru. Sisanya sudah ada di dalam app (termasuk 7-Zip). Kalau Command Line Tools Apple (gratis) belum ada, tur perkenalan bantu memasangnya, dan minta **Akses Disk Penuh** sekali saja (supaya macOS tidak tanya per folder).

**Sebelum apa pun:** baca [ketentuan & peringatan](TERMS.id.md). App juga meminta kamu mencentang bahwa kamu sudah membacanya.

**Cara 1: Homebrew** (paling gampang, update cukup `brew upgrade`)

```bash
brew install --cask navi-crwn/tap/amnesia
```

**Cara 2: Installer (.dmg)**

1. Ambil `Amnesia-vX.dmg` dari [Releases](../../releases/latest), buka, lalu seret **Amnesia** ke folder **Applications**. Di dalamnya ada file `READ ME FIRST` berisi peringatan singkat.
2. App ini belum ditandatangani Apple, jadi macOS memblokirnya pertama kali. Buka sekali, lalu ke **System Settings → Privacy & Security** dan klik **Open Anyway**.
   Atau lewat Terminal: `xattr -dr com.apple.quarantine /Applications/Amnesia.app`

**Cara 3: Build sendiri** (butuh Command Line Tools)

```bash
git clone https://github.com/navi-crwn/amnesia-mac.git ~/.amnesia
bash ~/.amnesia/app/build.sh
```

**Mau uninstall:** tekan *Matikan* di app dulu, baru hapus app-nya. Vault dan setting kamu ada di `~/.amnesia`.

## Cara pakai pertama kali

Tur perkenalan akan memandu kamu, tapi singkatnya begini:

1. **Buat vault.** Buka *Profile Vault*, isi password (minimal 12 karakter), lalu tekan *Buat Vault*. Password ini **tidak bisa dipulihkan** kalau lupa, jadi simpan baik-baik.
2. **Simpan login.** Login ke Chrome, WhatsApp, dan app lain seperti biasa, lalu tekan *Snapshot*.
3. **Amankan file.** Pindahkan file yang penting ke folder Keep kamu (`~/Keep`, atau di mana pun kamu menaruhnya).
4. **Cek dulu.** Buka Pengaturan (⚙️) → **Lihat yang akan dihapus sekarang**, pastikan tidak ada yang penting di daftar.
5. **Aktifkan.** Tekan *Aktifkan*. Mulai logout berikutnya, Mac kamu akan selalu bersih.

**Sehari-hari:** logout lewat tombol **Simpan & Logout**. Saat login lagi, buka Profile Vault dan tekan **Restore Profil**.

## Pertanyaan umum

**Apa bedanya Keep List dan Profile Vault?**
Keep List untuk hal yang tidak rahasia dan boleh tetap ada (misalnya setting VPN). Profile Vault untuk login dan data pribadi: disimpan terkunci, dan baru bisa dibuka dengan password.

**Kalau saya logout lewat menu Apple, bagaimana?**
Aman. Amnesia menahan sebentar untuk menunjukkan apa yang akan dihapus, lalu menyimpan login kamu ke vault secara otomatis sebelum membersihkan. Kedua fitur ini bisa dimatikan di Pengaturan.

**Kalau lupa password vault?**
Vault tidak bisa dibuka siapa pun, termasuk kamu. Hapus vault, buat yang baru, lalu login ulang ke app-app kamu.
Kalau masih ingat dan cuma mau ganti: Profile Vault → **Password**. Snapshot tetap aman.

**Snapshot minta password?**
Tidak. Vault mengunci snapshot dengan kunci yang hanya bisa dibuka password kamu, jadi menyimpan tidak perlu password; yang perlu hanya **Restore**. Hanya snapshot terbaru yang disimpan. App mana yang ikut disimpan bisa kamu pilih lewat centang di halaman Profile Vault.

**Apakah data saya dikirim ke internet?**
Tidak. Amnesia tidak punya server, tidak pakai akun, tidak melacak dan tidak mengumpulkan data, jadi memang tidak ada yang dikirim. Satu-satunya pengecualian: backup ke server atau cloud yang **kamu** atur sendiri, dan itu pun cuma file `.7z` terkunci, langsung dari Mac kamu ke tempat yang kamu pilih. Vault dan Keep List pribadi kamu juga tidak ikut ke GitHub.

**Kenapa minta Akses Disk Penuh?**
Untuk membersihkan Desktop, Documents dan Downloads, macOS biasanya minta izin per folder (dan tidak bisa bertanya saat logout). Izinkan sekali di **System Settings → Privacy & Security → Full Disk Access**, selesai. Pembersihan saat logout juga lewat app, jadi izin yang sama ikut berlaku.

**Backup online, apa yang perlu disiapkan?**
- *Server SSH:* isi `user@alamat` atau `user@alamat:folder`, ketik password server **sekali**, tekan **Hubungkan**. Amnesia membuat kunci SSH dan memasangnya di server, tanpa Terminal. Password tidak disimpan; sesudahnya backup login pakai kunci. Sudah punya kunci yang jalan? Kosongkan saja password-nya. Tanpa folder, backup masuk ke `~/amnesia-backup` di server (app menampilkan path lengkapnya setelah terhubung).
- *Cloud:* pilih dulu layanannya (Google Drive, Dropbox, OneDrive, Box atau pCloud) di daftar, lalu tekan **Hubungkan**, login di jendela kecil, selesai. Tidak memakai Chrome atau cookie browser kamu. Amnesia memasang rclone sendiri (butuh Homebrew).

Kalau nanti password server diganti, backup tetap jalan (pakai kunci). Backup baru gagal kalau server diinstal ulang atau kuncinya dihapus, dan pesannya akan menyuruh tekan **Hubungkan** lagi.

Catatan jujur: setiap backup dikirim utuh (bukan hanya bagian yang berubah), karena filenya terenkripsi. Backup lama tidak dihapus otomatis, jadi sesekali bersihkan sendiri di tujuan.

**Cara membuka file backup?**
Pakai app seperti Keka, atau Terminal: `7zz x amnesia_backup_xxx.7z`, lalu ketik password backup.

**Pindah ke Mac baru, langkahnya?**
Buka Profile Vault → **Pindah Mac** (atau dari Pengaturan). Halamannya memandu langkah demi langkah:
1. Di Mac lama: **Siapkan Pindah** (klik *Always Allow* di dialog macOS).
2. Backup dengan **Sertakan Profile Vault** dicentang.
3. Di Mac baru: pasang Amnesia, buka halaman Pindah Mac → **Ambil Vault dari Backup**.
4. **Restore Profil**, lalu **Pulihkan Kunci**. Chrome, Claude, dan WhatsApp terbuka dengan login lama.

**Bagaimana mematikannya?**
Tekan *Matikan* di app. Mac berhenti dibersihkan sampai kamu aktifkan lagi.

## Cara hapus

> [!IMPORTANT]
> Jangan cuma buang Amnesia ke Trash. Agent login-nya akan tertinggal dan tetap jalan setiap login.

Tempel ini di Terminal:

```bash
bash ~/.amnesia/uninstall.sh
```

Script ini mematikan agent login lebih dulu (supaya waktu dihentikan tidak ada yang terhapus), menghentikan Amnesia, menghapus app, lalu mengecek tidak ada yang tersisa. Vault dan pengaturan di `~/.amnesia` tetap disimpan, kalau nanti mau pasang lagi. Folder Keep kamu tidak pernah disentuh.

- Mau hapus semuanya, termasuk vault? Pakai `bash ~/.amnesia/uninstall.sh --all` (kamu diminta mengetik `HAPUS` dulu).
- Pasang lewat Homebrew? `brew uninstall --cask amnesia` menjalankan langkah aman yang sama.
- Tidak ada folder `~/.amnesia`? Berarti Amnesia belum pernah jalan, jadi script tidak perlu: hapus app-nya saja.

## Untuk yang penasaran (teknis)

| File | Fungsinya |
|---|---|
| `clean.sh` | Penghapus utama. Membaca `keep.conf` (Keep List milikmu). |
| `agent.sh` | Dijalankan macOS saat login, lalu "berjaga" untuk membersihkan saat logout. |
| `vault.py` | Profile Vault: kunci RSA-4096 + 7-Zip AES-256. |
| `backup.sh` | Backup terenkripsi ke flashdisk, server SSH, atau cloud (rclone). |
| `keep.example.conf` | Contoh Keep List. `build.sh` menyalinnya jadi `keep.conf` saat pertama dipasang. |
| `app/` | Kode app SwiftUI, ikon, dan script build/rilis. `app/screenshots.sh` membuat semua screenshot dengan data contoh. |
| `docs/` | Gambar, screenshot, dan website (GitHub Pages). |
| `test_clean.sh`, `test_vault.py`, `test_backup.sh` | Tes otomatis di "home palsu", aman dijalankan kapan saja. |

---

<p align="center">Lisensi MIT · <a href="TERMS.id.md">Ketentuan & peringatan</a> · Pakai dengan bijak: Amnesia benar-benar menghapus data.</p>
