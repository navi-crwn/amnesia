<p align="center">🌐 <a href="README.md">English</a> · <a href="https://navi-crwn.github.io/amnesia/zh-cn/">简体中文</a> · <a href="https://navi-crwn.github.io/amnesia/de/">Deutsch</a> · <a href="https://navi-crwn.github.io/amnesia/id/">Bahasa Indonesia</a> · <a href="https://navi-crwn.github.io/amnesia/ja/">日本語</a> · <a href="https://navi-crwn.github.io/amnesia/pt-br/">Português (Brasil)</a> · <a href="https://navi-crwn.github.io/amnesia/es/">Español</a></p>

<p align="center"><picture><source media="(prefers-color-scheme: light)" srcset="docs/readme/hero-id-light.webp"><img src="docs/readme/hero-id-dark.webp" alt="Amnesia: Mac kamu lupa segalanya, kecuali yang kamu simpan" width="100%"></picture></p>

<p align="center">
  <b>Setiap kali kamu logout, Mac kamu lupa semuanya.<br>Kecuali yang memang kamu mau simpan.</b>
</p>

<p align="center"><a href="https://navi-crwn.github.io/amnesia/#film"><img src="docs/media/teaser.gif" alt="Klip paper craft 15 detik: mata-mata login ke Mac dan tidak menemukan apa pun" width="720"></a><br><sub>▶ Tonton cerita lengkap 54 detik, dengan suara, di <a href="https://navi-crwn.github.io/amnesia/#film">website</a></sub></p>

<p align="center">
  <a href="../../releases/latest"><b>Download app</b></a> ·
  <a href="https://navi-crwn.github.io/amnesia/">Website</a> ·
  <a href="https://navi-crwn.github.io/amnesia/win/">Windows</a> ·
  <a href="#cara-pasang">Cara pasang</a> ·
  <a href="#pertanyaan-umum">FAQ</a> ·
  <a href="#cara-hapus">Cara hapus</a> ·
  <a href="CHANGELOG.id.md">Changelog</a> ·
  <a href="TERMS.id.md">Ketentuan</a>
</p>

<p align="center"><sub>Terbaru: <b>Mac v5.26.0</b> · <b>Windows v0.11.0</b> · gratis dan open source (MIT)</sub></p>

> [!WARNING]
> **Amnesia benar-benar menghapus data.** Setelah aktif, semua yang ada di luar folder Keep dan Keep List dihapus setiap logout, restart dan shutdown. Tidak masuk Trash dan tidak bisa dibatalkan. Baca dulu [ketentuan & peringatan](TERMS.id.md) yang singkat ini sebelum memasang.

---

## Apa itu Amnesia?

Bayangkan Mac kamu seperti meja kerja. Setiap selesai kerja, Amnesia **membereskan mejanya sampai bersih**: riwayat browser, cookie, file download, cache, riwayat Terminal, semuanya hilang. Besok kamu mulai lagi dari meja yang rapi, tanpa jejak kemarin.

Kalau semua hilang, kamu harus login ulang Gmail, WhatsApp, Telegram, dan lain-lain setiap hari, dan itu makan 15 sampai 20 menit. Karena itu Amnesia punya **Profile Vault**: brankas terkunci yang menyimpan login-login kamu. Habis login ke Mac, cukup ketik **1 password**, dan semua login kembali seperti semula.

**Cocok untuk kamu yang:**
- memakai Mac (atau PC Windows) bersama orang lain, atau di tempat umum,
- tidak mau ada jejak kerja yang tertinggal,
- ingin Mac tetap ringan dan bersih setiap hari.

<p align="center"><picture><source media="(prefers-color-scheme: light)" srcset="docs/readme/features-id-light.webp"><img src="docs/readme/features-id-dark.webp" alt="Semua yang bisa dilakukan Amnesia" width="100%"></picture></p>

<p align="center"><picture><source media="(prefers-color-scheme: light)" srcset="docs/readme/app-id-light.webp"><img src="docs/readme/app-id-dark.webp" alt="Jendela utama Amnesia" width="46%"></picture></p>

Cerita lengkap, tutorial yang bisa diikuti, dan FAQ ada di website: [navi-crwn.github.io/amnesia](https://navi-crwn.github.io/amnesia/)

<details>
<summary><b>Lihat lebih dekat</b></summary>

<p align="center"><picture><source media="(prefers-color-scheme: light)" srcset="docs/readme/vault-id-light.webp"><img src="docs/readme/vault-id-dark.webp" alt="Profile Vault" width="100%"></picture></p>
<p align="center"><picture><source media="(prefers-color-scheme: light)" srcset="docs/readme/backup-id-light.webp"><img src="docs/readme/backup-id-dark.webp" alt="Backup ke mana saja" width="100%"></picture></p>
<p align="center"><picture><source media="(prefers-color-scheme: light)" srcset="docs/readme/popups-id-light.webp"><img src="docs/readme/popups-id-dark.webp" alt="Popup Amnesia dengan kotak berwarna" width="100%"></picture></p>
<p align="center"><picture><source media="(prefers-color-scheme: light)" srcset="docs/readme/private-id-light.webp"><img src="docs/readme/private-id-dark.webp" alt="Buat kamu yang malas ditanya-tanya" width="100%"></picture></p>

</details>

## Apa yang dihapus, apa yang aman?

| Dihapus setiap logout | Tetap aman |
|---|---|
| Riwayat & cookie browser | Isi **folder Keep** kamu (bawaannya `~/Keep`; boleh di mana saja, nama apa saja) |
| Isi Desktop, Downloads, Documents, Pictures | Login yang disimpan di **Profile Vault** |
| Cache, log, riwayat Terminal | Semua yang ada di **Keep List** (VPN, kunci SSH, setting Terminal, dll.) |
| Data app yang tidak kamu pilih | App yang terpasang di `/Applications` dan Homebrew (kecuali kamu menyalakan *Hapus app yang dipasang belakangan* di Lanjutan) |
| Isi Trash | Akun Apple, Notes, Mail, Messages dan lainnya (kartu **Akun & data Apple**, menyala secara default). Foto: peringatan dan tombol Keep |
| | Mesin virtual (UTM, Parallels, VirtualBox, VMware Fusion), setelah kamu menekan Keep di peringatan |
| | Desktop dan Documents kalau **iCloud Desktop & Documents** nyala (menghapusnya berarti ikut menghapus dari iCloud) |

Mau tahu persis apa yang akan dihapus **tanpa menghapus apa pun**? Di app, tekan **Yang Akan Dihapus** di halaman utama. Atau jalankan:

```bash
bash ~/.amnesia/clean.sh logout --dry-run
```

## Fitur

- **Bersih otomatis.** Pembersihan berjalan **sebelum** Mac logout, restart, atau shutdown. Saat login berikutnya Amnesia mengecek ulang, jadi kalau ada yang terlewat, ikut dibersihkan.
- **Profile Vault.** Login Chrome (Gmail, WhatsApp Web, Telegram Web), Claude, WhatsApp, dan alat coding seperti Claude Code, OpenCode, Gemini CLI, GitHub CLI disimpan dalam brankas terenkripsi (AES-256). Untuk memulihkan, cukup 1 password. Halamannya punya 3 langkah bernomor sesuai urutan pakai: pilih app, simpan (Snapshot Sekarang), lalu kembalikan setelah login (Restore Profil). Browser Chromium lain (Brave, Edge, Vivaldi, Arc, Opera) bisa ditambahkan dengan 1 klik, begitu juga Signal, Session, Element, Telegram, Obsidian, Notion, Zoom dan Bitwarden. Amnesia juga menyarankan app lain yang kelihatannya menyimpan login.
- **Restore bertanya dulu sebelum memundurkan data.** Kalau data sebuah app di Mac lebih baru dari snapshot-nya, kamu ditanya dulu. Yang ada di Keep List tidak pernah ditimpa restore. Dan sampai logout berikutnya, tombol **Kembalikan data sebelum restore** di halaman vault mengembalikan data sebelumnya.
- **Snapshot ringan, per browser.** Di Profile Vault, langkah 1 → **Ubah…** punya tombol **Snapshot ringan** untuk tiap browser. Nyala (bawaan): cache browser dan file program extension dari Web Store tidak ikut disimpan, jadi snapshot jauh lebih kecil dan cepat; login, bookmark dan pengaturan tetap tersimpan, dan setelah Restore kamu tinggal tekan *Repair* di tiap extension. Mati: semuanya disimpan. Simpan & Logout dan snapshot otomatis mengikuti tombol yang sama.
- **Simpan & Logout.** 1 klik: login kamu disimpan dulu ke vault, baru Mac logout. Kalau penyimpanannya gagal, logout dibatalkan, jadi tidak ada yang hilang.
- **Jeda 1 Sesi.** Butuh Mac tidak dibersihkan sekali saja? Tekan Jeda. Setelah 1x logout dan login, Amnesia aktif lagi sendiri.
- **Keep List.** Pilih folder atau app yang tidak boleh ikut dihapus, langsung dari app. Nyalakan sebuah app dan kamu lihat persis apa yang disimpan (data app, setting, ukurannya). Menyimpan **Claude** ikut menyimpan chat Claude Code (`~/.claude`, `~/.claude.json`).
- **Kunci Keep.** Finder dan app lain tidak bisa membuka atau mengubah folder Keep sampai kamu mengetik password Keep di Amnesia. Terkunci lagi setelah 5 sampai 60 menit, saat layar terkunci, dan setiap logout. Kunci ini memakai izin macOS, bukan enkripsi, dan nama file langsung di dalam Keep tetap terlihat. Mati secara default.
- **Brankas (eksperimen).** Disk terenkripsi (APFS, AES-256) di dalam folder Keep untuk file yang benar-benar rahasia. Amnesia menutupnya sebelum setiap pembersihan, dan memberi tahu kalau gagal. Lupa password-nya, file di dalamnya hilang.
- **Cek kesehatan.** Satu halaman di Pengaturan: Amnesia nyala atau tidak, Akses Disk Penuh, iCloud Desktop & Documents, folder symlink, mesin virtual, file besar yang akan dihapus, backup terakhir, Kunci Keep, Brankas, FileVault, sisa ruang disk, memori dan kondisi baterai. Kebanyakan baris punya tombol perbaikan. Di sebelahnya, **Batasan** menjelaskan apa yang tidak bisa dihapus Amnesia (Time Machine, Spotlight, iCloud, swap, log sistem, akun lain).
- **Perawatan.** Halaman untuk mengosongkan ruang kapan saja, selalu dengan daftar untuk dicek dulu: **Ringkasan disk** (hanya dibaca), **Bersihkan sekarang** (cache, log, tempat sampah Amnesia; cache app yang sedang terbuka dilewati), **Hapus app** (ke Trash, data pribadi tetap ada kecuali kamu centang), **Folder build project** (node_modules, target, build, dist dan lainnya; folder yang dipakai 7 hari terakhir atau dilacak git tidak disentuh), **Installer lama** (.dmg, .pkg; image disk dan mesin virtual tidak pernah dipilihkan) dan **Perawatan ringan** tanpa password admin. Tidak ada yang berisiko dicentang untukmu, dan setiap Perawatan tercatat di Riwayat beserta ruang yang dikosongkan. Amnesia sudah menghapus sebagian besar folder home saat logout, jadi Perawatan terutama membantu untuk folder Keep, app yang disimpan dan file besar dari sesi ini.
- **Berhenti kalau ragu.** Kalau Keep List tidak bisa dibaca atau hilang, pembersihan tidak menghapus apa pun dan dicatat di Riwayat. Salinan Keep List terakhir yang baik disimpan untuk memulihkannya. Kalau pengecekan tidak yakin (cloud, iCloud, link, pemilik), item disimpan.
- **Mode Amnesia.** Pilih seberapa banyak yang dilupakan setiap logout. **Retrograde Amnesia** seperti akun baru setiap login: hanya folder Keep kamu dan yang dibutuhkan Amnesia yang tetap ada. **Selective Amnesia** (disarankan) adalah daftar dasar untuk instalasi baru: folder Keep, login app dari vault, kunci SSH, pengaturan Git dan shell. App kamu sendiri kamu tambahkan sendiri. **Partial Amnesia** membiarkan app tetap menyimpan pengaturan dan loginnya, sedangkan file kamu, Downloads, Desktop, cache, log, Trash dan riwayat terminal dihapus. Riwayat dan cookie browser di dalam folder browser itu sendiri juga tetap ada, karena foldernya disimpan. **Custom Amnesia** adalah Keep List buatan kamu sendiri. Setiap ganti mode ada pratinjau dulu (apa yang mulai dihapus, apa yang mulai disimpan), ada peringatan kalau yang dihapus lebih banyak, dan berlaku mulai logout berikutnya. Mode hanya mengubah bagiannya sendiri yang ditandai di Keep List, jadi baris kamu sendiri tetap ada. File mode yang hilang atau rusak tidak pernah mengosongkan Keep List.
- **Profil vault.** Restore hanya yang kamu perlukan, misalnya **Kerja** atau **Santai**, atau semuanya. Profil bisa diganti nama, ditambah dan dihapus. Kalau satu app ada di dua profil, Amnesia memberi tahu: satu browser menyimpan satu kumpulan login, jadi browser kedua (atau profil browser terpisah) membuat pemakaian pribadi tetap terpisah.
- **Tanya AI.** Minta saran tanpa membagikan file kamu. Amnesia membuat laporan tanpa isi file dan tanpa nama file kamu (nama folder juga bisa disembunyikan), plus prompt siap pakai. Salin atau simpan ke folder Keep, tempel ke AI pilihanmu, lalu tempel jawabannya kembali. Setiap perubahan yang disarankan punya kotak centang dan pratinjau yang sama seperti ganti mode; tidak ada yang diterapkan sebelum kamu konfirmasi, dan baris milik Amnesia tidak bisa dihapus lewat cara ini. Amnesia tidak memakai internet untuk ini.
- **Perintah Terminal.** Nyalakan di Pengaturan dan kamu dapat perintah `amnesia` yang hanya membaca: `amnesia status`, `amnesia preview`, `amnesia report` (`--json`, `--hide-names`), `amnesia keep`, `amnesia history`. Tidak pernah menghapus atau mengubah apa pun.
- **Folder Keep milikmu.** File di dalamnya tidak pernah dihapus. Taruh di mana saja (bahkan di drive eksternal) dan beri nama apa saja.
- **Backup ke mana saja.** Folder pilihan dikunci jadi 1 file `.7z` (AES-256), lalu dikirim ke:
  - **Flashdisk / SSD** yang tercolok,
  - **Server sendiri / VPS** lewat SSH + rsync. Ketik password server sekali, Amnesia yang menyiapkan kuncinya. Tanpa Terminal.
  - **Cloud**: Google Drive, Dropbox, OneDrive, Box atau pCloud. Login lewat browser, tanpa Terminal. (S3, WebDAV dan 40+ lainnya lewat rclone.)
- **Backup terjadwal.** Harian atau mingguan, jalan sendiri selama ikon Amnesia ada di menu bar. Tombol **Jalankan backup terjadwal sekarang** untuk langsung mengetesnya.
- **Cek file backup.** Pilih file backup `.7z`, lalu Amnesia membukanya di folder sementara untuk memastikan vault di dalamnya bisa dipulihkan. Vault kamu yang sekarang tidak berubah sama sekali. Kalau password salah atau file-nya tidak berisi vault, pesannya bilang dengan jelas.
- **Pulihkan File.** Pilih file atau folder dari backup, lalu Amnesia mengembalikannya ke tempat asalnya. File yang sudah ada di sana dipindah dulu ke `~/.amnesia/before-restore`, tidak pernah ditimpa. Mau taruh di tempat lain? Tekan **Ke Folder Lain**.
- **Riwayat.** Halaman yang mencatat setiap pembersihan, snapshot, restore dan backup, dikelompokkan per hari. Isinya hanya waktu dan nama app, tidak pernah nama file kamu.
- **Pindah Mac.** Bawa semua login ke Mac baru: kunci Keychain ikut disimpan ke vault, vault ikut ke backup, lalu dipulihkan di Mac baru.
- **Tur perkenalan.** Saat pertama dibuka, Amnesia mengajak kamu keliling, cek semua sudah siap, mendeteksi app kamu, lalu tanya mana yang datanya mau disimpan.
- **Tombol darurat.** Kalau password vault salah 3x, atau kamu mengetik *kata panik* yang sudah kamu atur, vault langsung dimusnahkan.
- **Cek dulu sebelum logout.** Logout atau restart lewat menu Apple ditahan sebentar, lalu kamu lihat dulu apa saja yang akan dihapus. Lanjut atau batal, kamu yang pilih. Daftarnya disiapkan di background, jadi langsung tampil.
- **Offline & privat.** Tanpa server, tanpa akun, tanpa pelacakan, tanpa pengumpulan data. Tidak ada yang keluar dari Mac kamu kecuali kamu sendiri yang mengatur backup. Satu-satunya yang ditanyakan Amnesia ke internet adalah nomor versi terbaru di GitHub (seminggu, 2 minggu atau sebulan sekali, kamu yang pilih), dan itu bisa dimatikan.
- **Aman untuk iCloud dan symlink.** Kalau iCloud Desktop & Documents nyala, kedua folder itu dilewati, jadi tidak ada yang terhapus dari iCloud atau perangkat Apple lain. Folder yang berupa symlink tidak pernah dikosongkan lewat link-nya. File yang gagal dihapus dihitung "tidak bisa dihapus", bukan "bersih".
- **Snapshot otomatis.** Lupa menekan Simpan & Logout? Saat logout, restart atau shutdown biasa, Amnesia tetap menyimpan app yang datanya **berubah** sejak snapshot terakhirnya (maksimal 150 detik, supaya Mac tidak tertahan lama). App yang kamu matikan di vault dilewati. Kalau waktunya habis, snapshot lama app itu tetap aman. Snapshot ini tetap jalan walaupun kamu baru snapshot beberapa menit sebelumnya, jadi pekerjaan sesudah snapshot manual tidak hilang.
- **Peringatan yang jelas.** Setiap popup dibagi jadi kotak berwarna: *Yang akan terjadi* (biru), *Yang akan dihapus* (merah), *Berikut ini tetap tersimpan (tidak dihapus)* (hijau) dan *Yang perlu kamu lakukan* (ungu).
- **Notifikasi.** Setelah login, Amnesia memberi tahu bahwa Mac sudah bersih dan mengingatkan untuk restore profil.
- **Pengaturan.** Semua fitur di atas bisa dinyalakan atau dimatikan sesukamu. **Jalan di background** membuat Amnesia hanya muncul sebagai ikon menu bar saat login, tanpa jendela. Alias Keep di Desktop dan Keep di sidebar Finder dipasang lagi setiap selesai membersihkan (keduanya bisa dimatikan), dan panel menu bar punya **Buka Keep**.
- **Lanjutan.** Pengaturan yang perlu dipikir dulu dikumpulkan di satu halaman: **logout otomatis kalau Mac ditinggal** (5 sampai 60 menit, dengan hitung mundur 60 detik yang batal kalau kamu menyentuh apa saja), **hapus app yang dipasang belakangan** (app yang kamu pasang setelah fitur ini nyala dihapus saat logout, kecuali kamu tekan Simpan; app yang dipasang dengan password admin tidak disentuh), kata panik, dan Pindah Mac.
- **Update bertanda tangan dari app.** Amnesia cek GitHub sesuai jadwal pilihanmu, mengunduh versi baru, mencocokkannya dengan `SHA256SUMS.txt` **dan** tanda tangan developer atas file itu (`SHA256SUMS.txt.sig`, ECDSA P-256), lalu memasangnya saat kamu tekan **Pasang & Buka Lagi**. Kalau tanda tangannya tidak sah, tidak ada yang dipasang dan yang dibuka halaman rilis. Pakai Homebrew? Update tetap lewat `brew upgrade`.
- **Cek FileVault.** Cek kesehatan menunjukkan apakah enkripsi disk sudah nyala. Amnesia hanya membersihkan saat logout dan folder Keep tidak dienkripsi, jadi FileVault sangat disarankan.
- **2 bahasa.** English atau Bahasa Indonesia, tinggal pilih di Pengaturan.
- **Ikon di menu bar.** Status Amnesia selalu terlihat di pojok kanan atas: hijau aktif, oranye jeda, merah mati. Tombol besar **Aktifkan / Matikan** ada langsung di kartu status halaman utama.

## Amnesia untuk Windows

Amnesia juga jalan di **Windows 10 dan 11** (x64 dan ARM). Sekarang sudah rilis resmi, **v0.11.0**, dari folder `windows/`. Idenya sama, dibuat khusus untuk Windows:

- membersihkan folder user dan jejak Windows (file terakhir, jump list, riwayat Explorer dan pencarian, riwayat clipboard, dan lainnya) saat **sign out, restart dan shutdown**, lalu dicek lagi saat sign in
- folder Keep dan Keep List dengan ikon app, **Simpan app** sekali klik, dan tempat sampah 3 hari untuk app yang dihapus
- Profile Vault, backup, Cek kesehatan, Kunci Keep, brankas (eksperimen), hotkey panik, kunci USB, sign out saat ditinggal
- folder cloud (OneDrive, Dropbox, Google Drive, iCloud Drive, dan lainnya) dan mesin virtual tidak pernah dihapus
- **Perawatan**: kosongkan ruang dengan daftar untuk dicek dulu (Temp, cache app, folder build, installer lama ke Recycle Bin, hapus program yang dipasang khusus untukmu)
- **Mode Amnesia** (Retrograde Amnesia, Selective Amnesia, Partial Amnesia, Custom Amnesia) dengan pratinjau sebelum setiap ganti mode, **profil vault** untuk restore hanya yang kamu perlukan, dan **Tanya AI** untuk minta saran tanpa membagikan file kamu
- dipasang khusus untuk akunmu (tanpa admin), update bertanda tangan dari dalam app

Ambil `Amnesia-Setup-<versi>-x64.exe` (atau `-arm64.exe`) dari rilis **Windows** (tag-nya diawali `win-v`) di halaman [Releases](../../releases), lalu cocokkan dengan `SHA256SUMS.txt`. Belum ada sertifikat code signing berbayar, jadi SmartScreen memberi peringatan pertama kali: **More info → Run anyway**.

Selengkapnya: [website Windows](https://navi-crwn.github.io/amnesia/win/) dan [windows/README.md](windows/README.md).

## Cara pasang

**Yang dibutuhkan:** macOS 15 atau lebih baru. Sisanya sudah ada di dalam app (termasuk 7-Zip). Kalau Command Line Tools Apple (gratis) belum ada, tur perkenalan bantu memasangnya, dan minta **Akses Disk Penuh** sekali saja (supaya macOS tidak tanya per folder).

**Ambil Amnesia hanya dari** [github.com/navi-crwn/amnesia](https://github.com/navi-crwn/amnesia), websitenya [navi-crwn.github.io/amnesia](https://navi-crwn.github.io/amnesia/) (GitHub Pages) atau Homebrew tap `navi-crwn/tap`. Salinan di tempat lain bukan dari kami. Menemukan masalah keamanan? Lihat [SECURITY.md](SECURITY.md).

**Sebelum apa pun:** baca [ketentuan & peringatan](TERMS.id.md). App juga meminta kamu mencentang bahwa kamu sudah membacanya.

**Cara 1: Homebrew** (paling gampang, update cukup `brew upgrade`)

```bash
brew install navi-crwn/tap/amnesia
```

**Cara 2: Installer (.dmg)**

1. Ambil `Amnesia-vX.dmg` dari [Releases](../../releases/latest), buka, lalu seret **Amnesia** ke folder **Applications**. Di dalamnya ada file `READ ME FIRST` berisi peringatan singkat.
2. App ini belum ditandatangani Apple, jadi macOS memblokirnya pertama kali. Buka sekali, lalu ke **System Settings → Privacy & Security** dan klik **Open Anyway**.
   Atau lewat Terminal: `xattr -dr com.apple.quarantine /Applications/Amnesia.app`
3. Mau mengecek file-nya? Setiap rilis punya `SHA256SUMS.txt` (dan tanda tangannya `SHA256SUMS.txt.sig`). Bandingkan dengan `shasum -a 256 ~/Downloads/Amnesia-v*.dmg`.

**Cara 3: Build sendiri** (butuh Command Line Tools)

```bash
git clone https://github.com/navi-crwn/amnesia.git ~/.amnesia
bash ~/.amnesia/app/build.sh
```

**Mau uninstall:** buka Pengaturan lalu tekan *Hapus Amnesia*. Lihat bagian [Cara hapus](#cara-hapus) di bawah.

## Cara pakai pertama kali

Tur perkenalan akan memandu kamu, tapi singkatnya begini:

1. **Buat vault.** Buka *Profile Vault*, isi password (minimal 12 karakter), lalu tekan *Buat Vault*. Password ini **tidak bisa dipulihkan** kalau lupa, jadi simpan baik-baik.
2. **Simpan login.** Login ke Chrome, WhatsApp, dan app lain seperti biasa. Di Profile Vault, centang app di langkah 1, lalu tekan *Snapshot Sekarang* di langkah 2.
3. **Amankan file.** Pindahkan file yang penting ke folder Keep kamu (`~/Keep`, atau di mana pun kamu menaruhnya).
4. **Cek dulu.** Buka Pengaturan (⚙️) → **Lihat yang akan dihapus sekarang**, pastikan tidak ada yang penting di daftar.
5. **Aktifkan.** Tekan *Aktifkan* di kartu status halaman utama. Mulai logout berikutnya, Mac kamu akan selalu bersih.

**Sehari-hari:** logout lewat tombol **Simpan & Logout**. Saat login lagi, buka Profile Vault, ketik password di langkah 3 dan tekan **Restore Profil**.

## Glosarium

Istilah ini hanya dipakai di teks ini dan di website. Tombol di app tetap memakai nama biasanya.

- **Selective Amnesia**: pembersihan normal saat logout. Semua dihapus kecuali Keep List, folder Keep dan Profile Vault.
- **Global Amnesia**: semuanya hilang tanpa jalan kembali. Ini terjadi lewat tombol panik (Doomsday), lewat Uninstall kalau kamu mencentang *hapus vault juga*, atau saat dibersihkan padahal tidak punya snapshot maupun backup.
- **Memory Recall**: mengembalikan yang tersimpan. Yaitu Restore Profil, Ambil Vault dari Backup, Pindah Mac dan Pulihkan File.

## Pertanyaan umum

**Apa bedanya Keep List dan Profile Vault?**
Keep List untuk hal yang tidak rahasia dan boleh tetap ada (misalnya setting VPN). Profile Vault untuk login dan data pribadi: disimpan terkunci, dan baru bisa dibuka dengan password.

**Kalau saya logout lewat menu Apple, bagaimana?**
Aman. Amnesia menahan sebentar untuk menunjukkan apa yang akan dihapus, lalu menyimpan login kamu ke vault secara otomatis sebelum membersihkan. Kedua fitur ini bisa dimatikan di Pengaturan.

**Apakah folder Keep dienkripsi?**
Tidak oleh Amnesia. Kunci Keep membuat Finder dan app lain tidak bisa membukanya, tapi itu izin macOS, bukan enkripsi. Nyalakan FileVault supaya seluruh disk terenkripsi, dan simpan file yang benar-benar rahasia di Brankas.

**Saya terlanjur restore dan data yang lebih baru jadi mundur. Bagaimana?**
Tekan **Kembalikan data sebelum restore** di halaman Profile Vault, kapan saja sebelum logout. Sejak v5.23 Amnesia juga bertanya dulu kalau data sebuah app lebih baru dari snapshot-nya.

**Kalau lupa password vault?**
Vault tidak bisa dibuka siapa pun, termasuk kamu. Hapus vault, buat yang baru, lalu login ulang ke app-app kamu.
Kalau masih ingat dan cuma mau ganti: Profile Vault → **Password**. Snapshot tetap aman.

**Snapshot minta password?**
Tidak. Vault mengunci snapshot dengan kunci yang hanya bisa dibuka password kamu, jadi menyimpan tidak perlu password; yang perlu hanya **Restore**. Setiap app punya snapshot sendiri, jadi menyimpan satu app tidak menimpa app lain; yang disimpan hanya yang terbaru per app. App (dan folder) mana yang ikut disimpan bisa kamu pilih di halaman Profile Vault, lengkap dengan ukurannya. Ikon tempat sampah di samping snapshot menghapus snapshot itu saja; **Hapus Semua Snapshot** menghapus semuanya tapi vault dan password tetap. Snapshot, Restore dan Backup bisa dibatalkan; yang sebelumnya tetap aman.

**Apakah data saya dikirim ke internet?**
Tidak. Amnesia tidak punya server, tidak pakai akun, tidak melacak dan tidak mengumpulkan data, jadi memang tidak ada yang dikirim. Satu-satunya pengecualian: backup ke server atau cloud yang **kamu** atur sendiri, dan itu pun cuma file `.7z` terkunci, langsung dari Mac kamu ke tempat yang kamu pilih. Vault, Keep List dan pengaturan kamu juga tidak ikut ke GitHub.

**Kenapa minta Akses Disk Penuh?**
Untuk membersihkan Desktop, Documents dan Downloads, macOS biasanya minta izin per folder (dan tidak bisa bertanya saat logout). Izinkan sekali di **System Settings → Privacy & Security → Full Disk Access**, selesai. Kalau kamu build sendiri, `build.sh` menandatangani app dengan sertifikat lokal supaya izinnya tidak hilang saat update (build pertama mungkin minta password Mac sekali: tekan **Always Allow**). Pembersihan saat logout juga lewat app, jadi izin yang sama ikut berlaku.

**Backup online, apa yang perlu disiapkan?**
- *Flashdisk atau folder:* pilih flashdisk atau folder mana saja (misalnya drive jaringan).
- *Server SSH:* isi `user@alamat` atau `user@alamat:folder` (port lain: isi kolom Port, atau tulis `user@alamat:port`), ketik password server **sekali**, tekan **Hubungkan**. Amnesia membuat kunci SSH dan memasangnya di server, tanpa Terminal. Password tidak disimpan; sesudahnya backup login pakai kunci. Sudah punya kunci yang jalan? Kosongkan saja password-nya. Tanpa folder, backup masuk ke `~/amnesia-backup` di server. Hubungkan mengecek folder itu bisa ditulis, menampilkan path lengkapnya, dan mengukur kecepatan supaya kamu tahu kira-kira berapa lama backup.
- *Cloud:* 1. pilih layanannya (Dropbox, OneDrive, Box atau pCloud), 2. tekan **Hubungkan**: halaman login terbuka di browser bawaan (Safari kalau belum memilih browser). Login lalu tekan Allow / Izinkan, 3. tulis nama folder. Kalau browser tidak terbuka, layar tunggu punya tombol untuk membuka halaman login. Amnesia memasang rclone sendiri (butuh Homebrew).
- *Google Drive:* paling mudah lewat app gratis **Google Drive for Desktop**: Amnesia menyalin backup ke foldernya dan app itu yang mengunggah. Mau langsung tanpa app? Pakai client ID Google milikmu sendiri di **Lanjutan** (ada panduan langkah demi langkah di app).

**Cara kerja backup (panduan)** di halaman Backup menjelaskan tiap tujuan, folder yang aman, dan cara mengecek file backup.

Kalau nanti password server diganti, backup tetap jalan (pakai kunci). Backup baru gagal kalau server diinstal ulang atau kuncinya dihapus, dan pesannya akan menyuruh tekan **Hubungkan** lagi.

Setiap backup dikirim utuh, karena filenya terenkripsi dan tidak bisa diperbarui sebagian. Backup lama tidak dihapus otomatis, jadi sesekali bersihkan sendiri di tujuan.

**Cara membuka file backup?**
Kalau di-klik dua kali, yang terbuka adalah Archive Utility, dan app itu tidak bisa membuka `.7z` terkunci seperti ini. Pakai **Keka** (gratis), atau Terminal: `~/.amnesia/bin/7zz x amnesia_backup_xxx.7z`, lalu ketik password backup saat diminta (jangan tulis password di perintahnya). Lebih gampang lagi: Backup → **Pulihkan File** di app.

**Cara mengambil beberapa file saja dari backup?**
Backup → **Pulihkan File…**: pilih file `.7z`, ketik password backup, centang yang mau dikembalikan, lalu tekan **Pulihkan ke Lokasi Asal**. File yang sudah ada di sana dipindah dulu ke `~/.amnesia/before-restore/`. Kalau tempat asalnya drive eksternal yang tidak tercolok, Amnesia minta kamu memilih folder lain. Catatan: selama Amnesia nyala, file yang dipulihkan di luar Keep List akan terhapus lagi saat logout berikutnya, jadi pindahkan ke folder Keep.

**Cek file backup bilang "tidak berisi Profile Vault". Backup saya rusak?**
Tidak. File-nya bisa dibuka; hanya saja dibuat saat *Sertakan Profile Vault* mati (atau sebelum v5.13). File kamu ada di dalamnya, vault-nya saja yang tidak. Kalau pesannya password tidak cocok, file-nya juga baik-baik saja, hanya password-nya beda.

**Backup terjadwal minta password Mac. Kenapa?**
Password backup disimpan di Keychain, dan yang menyimpannya versi app yang lama. Ketik password Mac sekali dan tekan **Always Allow**; Amnesia lalu menyimpannya ulang atas nama versi sekarang, jadi tidak ditanya lagi.

**Pindah ke Mac baru, langkahnya?**
Buka Profile Vault → **Pindah Mac** (atau dari Pengaturan). Halamannya memandu langkah demi langkah:
1. Di Mac lama: **Siapkan Pindah** (klik *Always Allow* di dialog macOS).
2. Backup dengan **Sertakan Profile Vault** dicentang.
3. Di Mac baru: pasang Amnesia, buka halaman Pindah Mac → **Ambil Vault dari Backup**.
4. **Restore Profil**, lalu **Pulihkan Kunci**. Chrome, Claude, dan WhatsApp terbuka dengan login lama.

**Bisa cek apakah backup benar-benar bisa dipakai?**
Bisa. Backup → **Cek file backup**: pilih file `.7z`, ketik password backup, lalu Amnesia membuka vault-nya di folder sementara, menampilkan ukuran, tanggal dan daftar app-nya, lalu menghapus salinan sementara itu. Vault kamu yang sekarang tidak disentuh.

**Di mana saya bisa lihat apa yang sudah dilakukan Amnesia?**
Halaman utama → **Riwayat**. Isinya pembersihan (berapa item), jeda, snapshot, restore, backup dan tombol darurat, per hari. Nama file tidak pernah dicatat.

**Bagaimana mematikannya?**
Tekan *Matikan* di kartu status halaman utama. Mac berhenti dibersihkan sampai kamu aktifkan lagi.

## Cara hapus

Cara paling gampang: buka **Pengaturan** di app lalu tekan **Hapus Amnesia**. Prosesnya bertahap:
1. Popup menjelaskan apa yang akan terjadi dan apa saja yang masih tersimpan (vault, snapshot di dalamnya, Keep List dan pengaturan).
2. Ada kotak centang **Hapus juga vault, snapshot, Keep List, dan pengaturan** (bawaannya tidak dicentang). Biarkan kosong kalau mau disimpan untuk nanti.
3. Kalau kamu mencentangnya, ada konfirmasi kedua sekali lagi. File-file itu dipindah ke Trash, tidak langsung hilang.
4. Amnesia dimatikan untuk seterusnya dan app-nya dipindah ke Trash. Folder Keep kamu tidak pernah disentuh.

Kunci Keep nyala? Amnesia meminta password Keep dan membuka kunci Keep dulu. Tanpa password, Keep tetap terkunci dan kamu diberi perintah untuk membukanya: `chmod -RN ~/Keep`.

Terlanjur menyeret Amnesia ke Trash? Itu juga aman: Amnesia tahu, mematikan dirinya sendiri dan tidak membersihkan apa pun lagi.

Lebih suka Terminal? Tempel ini:

```bash
bash ~/.amnesia/uninstall.sh
```

Script ini mematikan agent login lebih dulu (supaya waktu dihentikan tidak ada yang terhapus), menghentikan Amnesia, menghapus app, lalu mengecek tidak ada yang tersisa. Vault dan pengaturan di `~/.amnesia` tetap disimpan, kalau nanti mau pasang lagi. Folder Keep kamu tidak pernah disentuh.

- Mau hapus semuanya, termasuk vault? Pakai `bash ~/.amnesia/uninstall.sh --all` (kamu diminta mengetik `HAPUS` dulu).
- Pasang lewat Homebrew? `brew uninstall amnesia` menjalankan langkah aman yang sama.
- Tidak ada folder `~/.amnesia`? Berarti Amnesia belum pernah jalan, jadi script tidak perlu: hapus app-nya saja.

## Untuk yang penasaran (teknis)

| File | Fungsinya |
|---|---|
| `clean.sh` | Penghapus utama. Membaca `keep.conf` (Keep List milikmu). |
| `agent.sh` | Dijalankan macOS saat login, lalu "berjaga" untuk membersihkan saat logout. |
| `vault.py` | Profile Vault: kunci RSA-4096 + 7-Zip AES-256. |
| `backup.sh` | Backup terenkripsi ke flashdisk, server SSH, atau cloud (rclone). |
| `keep.example.conf` | Contoh Keep List. `build.sh` menyalinnya jadi `keep.conf` saat pertama dipasang. |
| `app/` | Kode app SwiftUI, ikon, dan script build/rilis. `app/screenshots.sh` memotret app asli dengan data contoh (opsional). |
| `docs/` | Website (GitHub Pages). `docs/readme/` berisi gambar README yang diambil dari website. |
| `presets/` | Mode Amnesia: `full.conf`, `balanced.conf`, `light.conf`. Sebuah mode menyalin salah satunya ke bagian bertanda di atas `keep.conf`. |
| `report.py`, `bin/amnesia` | Laporan Tanya AI (tanpa isi file, tanpa nama file) dan perintah Terminal `amnesia` yang hanya membaca. |
| `keeplock.sh` | Kunci Keep dan Brankas (disk terenkripsi di dalam Keep). |
| `windows/` | Versi Windows (**v0.11.0**): app tray C# .NET 8 + halaman HTML, vault, backup, Cek kesehatan dan Setup.exe dengan update bertanda tangan dari dalam app. Benar-benar menghapus setelah diaktifkan, jadi cek dulu Yang akan dihapus. Di-build dan dites oleh GitHub Actions (`.github/workflows/windows.yml`); tag `win-v*` membuat release Windows. |
| `SECURITY.md`, `llms.txt` | Cara melaporkan masalah keamanan, dan panduan singkat untuk asisten AI yang membantu orang memasang Amnesia. |
| `test_clean.sh`, `test_vault.py`, `test_backup.sh`, `test_report.py` | Tes otomatis di "home palsu", aman dijalankan kapan saja. |

---

<p align="center">Lisensi MIT · <a href="TERMS.id.md">Ketentuan & peringatan</a> · Amnesia benar-benar menghapus data.</p>
