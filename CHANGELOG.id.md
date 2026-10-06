# Changelog

[English](CHANGELOG.md) · **Bahasa Indonesia**

Semua perubahan Amnesia dicatat di sini. Versi terbaru ada di paling atas.
Nomor versi juga terlihat di app (di samping judul dan di bawah menu bar).

## v5.8 — 2026-10-06

### Ditambahkan
- **Pilih yang disimpan, langsung setelah tur.** Begitu tur perkenalan selesai, halaman "Apa yang tetap disimpan?" menampilkan app yang ada di Mac kamu. Di dalam tur sekarang cuma contoh.
- **Lihat persis apa yang disimpan.** Nyalakan sebuah app dan detailnya terbuka: data apa saja yang disimpan (data app, data sandbox, data bersama, setting), lokasinya, dan ukurannya.
- **Tidak ada lagi app yang terkunci.** App yang diurus Profile Vault (Chrome, Claude, WhatsApp…) sekarang juga bisa dinyalakan, kalau kamu lebih suka menyimpannya utuh daripada lewat vault.
- **Folder Keep milikmu sendiri.** Pilih folder apa saja, di mana saja, nama apa saja (bahkan di drive eksternal): di halaman Keep List, di Pengaturan, atau di halaman "Apa yang tetap disimpan?". Amnesia bisa memindahkan file dari folder lama. Pembersih, kata panik dan backup semuanya ikut folder pilihanmu (`KEEP_DIR` di settings.conf).
- **Halaman "Baca ini dulu"** di tur: apa yang dihapus Amnesia, apa yang terjadi kalau lupa password, dan bahwa ini software gratis yang risikonya ada di kamu. Wajib dicentang sebelum bisa lanjut, dan sebelum tombol Aktifkan bisa dipakai.
- **`TERMS.md` / `TERMS.id.md`**: ketentuan & peringatan lengkap, ditautkan dari README, website, app, dan installer.
- **Catatan privasi** di halaman sambutan dan Pengaturan: tanpa server, tanpa pelacakan, tanpa pengumpulan data, tidak ada yang keluar dari Mac kecuali kamu atur backup.
- **Akses Disk Penuh, cukup sekali.** Cek kesiapan menunjukkan apakah Amnesia sudah punya izinnya, dengan tombol yang langsung membuka halaman Pengaturan yang tepat. Tidak ada lagi pop-up per folder.
- **Hubungkan server tanpa Terminal.** Ketik password server sekali lalu tekan Hubungkan. Amnesia membuat kunci SSH, memasangnya di server, dan memberi tahu folder persis tujuan backup. Password tidak pernah disimpan. Kalau kunci kamu sudah jalan, tidak perlu password sama sekali.
- **Login cloud di jendela kecil** di dalam app (jendela login aman milik Apple), bukan membuka Chrome atau browser kamu. Tidak memakai cookie browser.
- **Installer (.dmg)** untuk rilis: buka, lalu seret Amnesia ke Applications. Di dalamnya ada "READ ME FIRST" berisi peringatan singkat. Homebrew juga memasang dari .dmg.
- **Screenshot otomatis**: `app/screenshots.sh` memotret semua layar (tur, atur Keep, home, vault, Keep List, backup, yang akan dihapus, pengaturan, mode gelap, menu bar) dalam English dan Indonesia, pakai data contoh jadi tidak ada data pribadi yang terfoto.
- Backup juga bisa menyertakan folder di luar folder home (misalnya di drive lain).

### Diubah
- Halaman sambutan posisinya lebih naik, logo dan teks tidak terdorong ke bawah lagi.
- **"Yang akan dihapus" langsung terbuka.** Daftarnya disiapkan di background (20 detik setelah app jalan, lalu tiap 30 menit) dan langsung tampil, lengkap dengan "Diperbarui … lalu" dan tombol Muat ulang. Daftar yang tersimpan (`report.txt`) ikut dihapus setiap pembersihan sungguhan, jadi tidak meninggalkan jejak.
- Pembersih jauh lebih cepat: pengecekan Keep List tidak lagi menjalankan program tambahan untuk setiap folder.
- Saat login, macOS sekarang menjalankan pembersih lewat app Amnesia, jadi izin Akses Disk Penuh milik Amnesia juga berlaku untuk pembersihan saat logout. Pengaturan lama diperbarui otomatis saat app dibuka berikutnya.
- Pintasan folder Keep di Desktop ikut nama dan lokasi barunya.
- README dan website memakai screenshot baru (dua bahasa), peringatan, installer .dmg, dan jawaban FAQ baru (privasi, Akses Disk Penuh, backup tanpa Terminal).
- Server SSH bisa ditulis `user@alamat` (backup masuk ke `~/amnesia-backup` di server) atau `user@alamat:folder`.

### Dihapus
- Tombol "Siapkan Kunci SSH" yang membuka Terminal (diganti Hubungkan).
- Download zip (diganti .dmg).

## v5.7 — 2026-10-06

### Ditambahkan
- **Langsung siap pakai dari GitHub.** App sekarang membawa semua yang dibutuhkan: script Amnesia dan 7-Zip (versi resmi, dengan lisensinya). Saat pertama dibuka, app menyiapkan dirinya di `~/.amnesia`. Keep List, setting dan vault kamu tidak pernah ditimpa.
- **Tur perkenalan** saat app pertama kali dibuka:
  1. Sambutan + pilih bahasa.
  2. Cara kerja, 4 poin singkat.
  3. Cek kesiapan: mesin, 7-Zip dan Command Line Tools Apple, ada tombol pasang kalau belum ada.
  4. **App kamu**: Amnesia mendeteksi app di Mac, kamu tinggal nyalakan yang datanya mau disimpan. VPN dan password manager sudah dinyalakan. App yang diurus Profile Vault diberi gembok.
  5. Profile Vault dalam 3 langkah.
  6. Rutinitas harian.
  Tur bisa dibuka lagi dari Pengaturan.
- Tombol **Pilih App** di halaman Keep List (pemilih app yang sama dengan tur).
- **Backup: tambah folder apa saja** di dalam folder home, bukan cuma 7 folder standar.
- **Lebih banyak cloud, tanpa Terminal**: Google Drive, Dropbox, OneDrive, Box dan pCloud. Pilih, tekan Hubungkan, login di browser. Amnesia memasang rclone kalau perlu dan mengecek koneksinya. Token login tidak pernah ditampilkan.
- Tampil keterangan kalau cloud sudah terhubung, plus tombol Hubungkan ulang.
- **Website** (GitHub Pages, `docs/index.html`): English + Indonesia, mode terang + gelap, rapi di HP.
- **Homebrew**: `brew install --cask navi-crwn/tap/amnesia`. `github_backup.sh` membuat dan meng-update repo `homebrew-tap` setiap rilis.
- **Lisensi MIT** (`LICENSE`).
- Screenshot asli di README dan website.

### Diubah
- App muncul di **Cmd-Tab** dan Dock selama jendelanya terbuka, lalu kembali jadi ikon menu bar saja saat ditutup.
- Contoh SSH sekarang `user@remoteserv.er:backup`.
- Tagline di halaman utama tidak terpotong lagi.
- `vault.py` dan `backup.sh` memakai 7-Zip bawaan app dulu, baru Homebrew.
- `build.sh` memasukkan script dan 7-Zip ke dalam app.
- README: 3 cara pasang (Homebrew, download, build sendiri), cara melewati peringatan "developer tidak dikenal", dan cara uninstall yang aman.

### Keamanan
- Kalau kamu menghubungkan Google Drive di v5.6, tokennya tampil di jendela Terminal. Kalau screenshot-nya sempat dibagikan, cabut akses rclone di https://myaccount.google.com/connections lalu hubungkan ulang.

## v5.6 — 2026-10-06

### Ditambahkan
- **2 bahasa.** English sekarang jadi bahasa utama, Bahasa Indonesia tetap ada. Pilih di Pengaturan → Bahasa. Saat baru dipasang, Amnesia ikut bahasa Mac kamu.
- Semua ikut bahasa pilihan: app, notifikasi setelah login, pesan vault & backup, dan tulisan "Terakhir dibersihkan".
- `README.id.md` dan `CHANGELOG.id.md` (file ini): versi Indonesia. Halaman utama di GitHub pakai versi English.
- Gambar GitHub versi English (`docs/banner.png`, `docs/features.png`). Versi Indonesia: `docs/banner.id.png` dan `docs/fitur.png`.

### Diubah
- README ditulis ulang dalam English, tetap dengan gaya santai.
- Deskripsi repo GitHub sekarang English, plus topik `backup`.
- Pesan Terminal dari `build.sh`, `github_backup.sh`, `add_keep.sh` dan tes sekarang English.
- Komentar di `keep.example.conf` sekarang English.
- Pesan error dari script sekarang diawali `FAILED:` (sebelumnya `GAGAL:`).
- Kartu fitur "Backup & Panik" menyebut backup ke server dan cloud.

## v5.5 — 2026-10-06

### Ditambahkan
- **Backup online.** Halaman Backup sekarang punya 3 tujuan:
  - **Flashdisk / SSD**: drive yang tercolok otomatis terdeteksi (tombol ↻ untuk cari ulang).
  - **Server SSH**: kirim ke server/VPS sendiri lewat SSH + rsync (`user@alamat:folder`). Ada tombol **Tes Koneksi** dan **Siapkan Kunci SSH** (membuat kunci `~/.ssh/id_ed25519` lalu memasangnya ke server lewat Terminal).
  - **Cloud**: Google Drive, Dropbox, OneDrive, S3 lewat rclone. Tombol **Hubungkan Google Drive** memasang rclone (kalau belum ada) dan membuka login Google di browser.
- **Backup terjadwal**: Mati / Harian / Mingguan. Dicek 2 menit setelah app jalan lalu tiap 10 menit. Kalau tujuannya flashdisk, backup menunggu sampai flashdisk tercolok. Kalau gagal, dicoba lagi 1 jam kemudian. Hasilnya muncul sebagai notifikasi.
- **Simpan password backup di Keychain** (pilihan, wajib untuk backup terjadwal). Disimpan sebagai item `Amnesia Backup`.
- **Sertakan Profile Vault** di backup, untuk pindah Mac.
- **Pindah Mac** (di halaman Profile Vault):
  - **Siapkan Pindah Mac**: menyimpan kunci Keychain "… Safe Storage" (Chrome, Claude, WhatsApp, dll.) ke vault, terenkripsi seperti snapshot.
  - **Ambil Vault dari Backup** (muncul kalau vault belum ada): pilih file backup `.7z`, isi password backup, vault dipulihkan.
  - **Pulihkan Kunci**: memasang kunci tadi ke Keychain Mac baru, pakai password vault. Hanya jalan kalau tombolnya ditekan, tidak pernah otomatis.
- Status backup terakhir (berhasil/gagal) tampil di atas halaman Backup.
- `backup.sh` (mesin backup, dipakai app) dan `test_backup.sh` (tes otomatis di home palsu).
- `vault.py`: perintah `exportkeys` dan `importkeys`; `status` sekarang juga melaporkan kunci yang tersimpan.

### Diubah
- Pengaturan backup (tujuan, folder, jadwal) sekarang disimpan di `settings.conf`, jadi tidak perlu diisi ulang setiap kali.
- Keep List: tambah `keychain:Amnesia Backup` (password backup terjadwal) dan `.config/rclone` (login cloud) supaya tidak ikut terhapus saat logout. Ditambahkan otomatis oleh `add_keep.sh`.
- Kartu Backup di halaman utama: "Ke flashdisk, server atau cloud".
- `test_clean.sh` juga mengecek `.config/rclone` tetap aman.

### Catatan
- File backup terenkripsi dikirim utuh setiap kali (bukan hanya bagian yang berubah).
- Backup lama tidak dihapus otomatis.
- Setelah app di-build ulang, macOS bisa bertanya sekali lagi apakah Amnesia boleh membaca password backup di Keychain. Klik *Always Allow*.

## v5.4 — 2026-10-06

### Ditambahkan
- **Halaman Pengaturan** (ikon ⚙️ di kanan atas). Setiap fitur baru di bawah bisa dinyalakan atau dimatikan di sini, dan semuanya aktif secara bawaan.
- **Snapshot otomatis saat logout.** Logout, restart atau shutdown lewat menu Apple sekarang tetap menyimpan login ke vault sebelum Mac dibersihkan. Snapshot dilewati kalau vault belum dibuat, Amnesia sedang dijeda, atau baru saja ada snapshot (≤10 menit, misalnya dari tombol Simpan & Logout).
- **Notifikasi setelah login**: "Mac sudah bersih. Klik ikon Amnesia di menu bar untuk restore profil."
- **Cek dulu sebelum logout.** Saat logout, restart atau shutdown lewat menu Apple, Amnesia menahan sebentar dan menampilkan daftar yang akan dihapus, dikelompokkan (Desktop, Downloads, Keychain, dll.). Pilih **Lanjut** atau **Batal**.
- Tombol **"Lihat yang akan dihapus sekarang"** di Pengaturan: dry-run tanpa Terminal.

### Diubah
- Batas waktu pembersihan saat logout dinaikkan dari 120 menjadi 300 detik, supaya snapshot otomatis sempat selesai. Berlaku setelah Amnesia diaktifkan (atau dimatikan lalu diaktifkan lagi).
- Tombol Simpan & Logout tidak ikut ditahan oleh fitur "Cek dulu".

## v5.3 — 2026-10-06

### Ditambahkan
- `app/make_public.sh`: membuat repo **public** baru `amnesia-mac` dengan riwayat bersih. Repo private lama tidak dihapus dan tidak diubah.
- `keep.example.conf`: contoh Keep List untuk pemakai baru. `build.sh` menyalinnya jadi `keep.conf` kalau belum ada.

### Diubah
- README ditulis ulang dengan bahasa yang lebih santai dan jelas: apa itu Amnesia, apa yang dihapus vs aman, cara pakai pertama kali, dan FAQ.
- Deskripsi repo GitHub dibuat lebih jelas.
- `keep.conf` pribadi (berisi daftar app dan catatan server) tidak lagi ikut ke GitHub.
- `test_clean.sh` memakai `keep.example.conf`, jadi tes juga jalan di hasil clone orang lain.

### Diperbaiki
- Gambar fitur di README: ikon di setiap kartu sebelumnya kosong, sekarang ada ikonnya.

## v5.2 — 2026-10-06

### Ditambahkan
- Halaman GitHub baru: README lengkap dengan banner, gambar fitur, cara kerja, instalasi, dan batasan.
- `CHANGELOG.md` (file ini). Setiap pengerjaan berikutnya wajib menambah catatan di sini.
- App jadi diunggah ke **GitHub Releases** (`Amnesia-v5.2.zip`) oleh `app/github_backup.sh`.
- Keep List: kunci Keychain `gemini` (login Gemini CLI), `*.XAUTH` (password profil VPN), dan `.gitconfig` (setting git).

### Diubah
- `app/github_backup.sh` sekarang sekaligus: merapikan file, update deskripsi dan topik repo, commit, push, dan membuat release.

### Dihapus
- Script lama yang sudah tidak dipakai: `reset.sh`, `clean_keychain.sh`, `keep_apps.conf`, `amnesia_app.py` (app Tk), folder `templates/`.
- File catatan spek (`AMNESIA_SPEK.md`, `PROFILE_VAULT_SPEK.md`) tidak lagi ikut ke GitHub. File-nya tetap ada di Mac.

## v5.1 — 2026-10-06

### Ditambahkan
- App hanya bisa berjalan **1x**. Membuka Amnesia lagi akan memunculkan jendela yang sudah ada.
- Nomor versi tampil di samping judul "Amnesia" dan di bawah panel menu bar.
- Backup kode ke GitHub (repo private) lewat `app/github_backup.sh`.
- Profile Vault menyimpan juga: Claude Code, CodeBuddy, Gemini CLI, Kimi, GitHub CLI, Antigravity, WhatsApp, dan Windows App.
- Keep List: `.zshrc`, `.zprofile`, `.mitmproxy`, Shottr, Tailscale, dan kunci Keychain Claude Code & GitHub CLI (`app/add_keep.sh`, hanya menambah, tidak menimpa).

### Diubah
- App dipasang di `/Applications` (muncul di Launchpad). Desktop hanya berisi pintasan, bukan salinan.
- Build otomatis menghapus semua salinan Amnesia lama (penyebab 2 ikon di menu bar).
- Panel menu bar didesain ulang: kartu status berwarna, info snapshot & Keep List, dan 4 tombol warna-warni.

### Diperbaiki
- Teks "Tutup App (pembersihan tetap jalan)" yang terpotong.
- Centang "Kata panik juga mengosongkan ~/Keep" tampil aktif padahal kata panik kosong.

## v5.0 — 2026-10-06

### Ditambahkan
- App baru **SwiftUI** (asli Mac) menggantikan app Tk: tampilan warna-warni, ikon status di menu bar, berjalan di background.
- Logo baru: perisai dengan lubang kunci dan titik-titik memudar.
- Tombol Aktifkan sekarang minta konfirmasi dulu.

### Diperbaiki
- Mengaktifkan ulang Amnesia bisa memicu pembersihan di tengah sesi (urutan LaunchAgent).
- Profile Vault "tidak merespons" saat vault belum pernah dibuat.
- Folder sistem Apple (`group.com.apple.*`) muncul di daftar Tambah Keep List.

## v4.0 — 2026-10-06

### Ditambahkan
- Pembersihan **sebelum** logout/restart/shutdown, plus cek ulang saat login (`agent.sh` + `clean.sh`).
- **Profile Vault** (`vault.py`): snapshot & restore profil terenkripsi, 3x salah password = vault musnah, kata panik.
- Mode `--dry-run` untuk melihat apa yang akan dihapus.
- Keep List fleksibel (`keep.conf`) dengan pola `*` dan item Keychain.
- Tes otomatis: `test_clean.sh` dan `test_vault.py`.

### Diperbaiki
- Jendela app kosong (Tk 8.5 bawaan macOS) dengan memakai Python Homebrew.
- Jeda hanya berlaku untuk 1 sesi, lalu aktif lagi otomatis.
