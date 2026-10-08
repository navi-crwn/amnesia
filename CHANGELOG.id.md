# Changelog

[English](CHANGELOG.md) · **Bahasa Indonesia**

Semua yang berubah di Amnesia, yang terbaru di paling atas.
Sedikit cerita: tanggal 6 Oktober 2026 Amnesia masih berupa beberapa skrip. Dua hari (dan banyak kopi) kemudian, jadilah app Mac beneran, lengkap dengan vault, backup, dan website sendiri. Biar gampang dibaca, dua hari yang super sibuk itu dirangkum jadi tiga bab di bawah, bukan 30 catatan kecil.

Nomor versi kamu ada di samping judul Amnesia dan di bagian bawah panel menu bar.

## v5.18.1 · Sekarang tampilannya kayak website (7–8 Okt 2026)

Ini versi yang sebaiknya kamu unduh. Isinya v5.16 sampai v5.18.1, ditambah website baru dan video-videonya.

### Yang baru
- **Halaman Riwayat.** Tile baru di halaman utama yang menunjukkan apa saja yang dikerjakan Amnesia, per hari: pembersihan (berapa item), sesi yang dijeda, snapshot, restore, backup, dan kata panik. Yang dicatat cuma waktu, jumlah, dan nama app. Nama file kamu tidak pernah ditulis.
- **Pulihkan File.** Cuma butuh beberapa file dari backup? Backup → **Pulihkan File…**, pilih file `.7z`, ketik password, centang yang kamu mau. File kembali persis ke tempat asalnya. Tidak ada yang ditimpa: file yang sudah ada dipindah dulu ke `~/.amnesia/before-restore/`. Bisa juga dipulihkan ke folder lain.
- **Cek file backup.** Pilih backup, Amnesia mengintip isinya: ada Profile Vault atau tidak, berapa besar, app apa saja. Vault kamu yang asli tidak disentuh. Kalau ada masalah, dikasih tahu jelas: password salah, backup tanpa vault, atau file rusak.
- **Jalankan backup terjadwal sekarang.** Tes jadwal backup kamu langsung, tanpa harus menunggu sehari.
- **Snapshot ringan, per browser.** Di Profile Vault ada sakelar untuk tiap browser. Kalau nyala (bawaannya begitu), cache dan file ekstensi dari Web Store dilewati, jadi Chrome menyusut dari sekitar 1 GB ke 150 MB. Login, bookmark, dan pengaturan ekstensi selalu ikut tersimpan.
- **Lebih banyak browser di vault:** Brave, Edge, Vivaldi, Arc, dan Opera (muncul kalau terpasang saja).
- **"Baca selengkapnya…"** di bawah teks panjang, supaya halaman tidak terasa seperti tembok tulisan.

### Tampilan
- **App sekarang senada dengan website.** Gelap (atau putih lembut di mode terang, ikut setelan Mac kamu), kartu datar dengan garis tipis, warna fitur yang kalem, dan kartu status yang hijau saat Aktif, oranye saat Dijeda, dan netral saat Mati.
- **Aktifkan / Matikan** sekarang jadi tombol besar di kartu status paling atas halaman utama.
- **Popup lebih gampang dibaca.** Setiap peringatan dipecah jadi kotak berwarna: apa yang akan terjadi, apa yang dihapus, apa yang tetap aman, apa yang perlu kamu lakukan, hati-hati, dan info tambahan.
- **Uninstall dua langkah.** Vault dan pengaturan cuma ikut dihapus kalau kamu centang kotaknya dan konfirmasi sekali lagi (itu pun masuk Trash dulu, tidak langsung lenyap).
- **Status pakai bahasa biasa,** misalnya "Terakhir dibersihkan: hari ini 13:03, saat logout, 1284 item".
- Semua teks dicek ulang supaya nama tombol di penjelasan sama dengan tombol aslinya, di bahasa Inggris dan Indonesia.

### Yang diperbaiki
- Tombol utama popup (misalnya **Matikan**) tidak kelihatan di macOS 26. Sekarang sudah muncul lagi.
- Tile dan tombol di pinggir halaman garis atau bayangannya terpotong.
- Backup terjadwal terus minta password Mac (popup Keychain). Izinkan sekali, setelah itu diam.

### Website & README
- **Website baru** di [navi-crwn.github.io/amnesia-mac](https://navi-crwn.github.io/amnesia-mac/): animasi saat scroll, logo 3D, mode terang dan gelap, app dibongkar tombol per tombol, tutorial yang bisa diikuti, kartu instalasi, dan FAQ yang lengkap. Tetap enak dibaca walau animasi dimatikan. Tanpa pelacakan.
- **Dibuat secara terbuka:** bagian berisi info repo langsung dari GitHub dan grafik 3D setiap commit.
- **"Yang paham, paham" 😉** buat kamu yang malas ditanya-tanya: Mac dipinjam, Mac hilang, "coba buka sebentar", dan keluarga kepo. Dengan catatan jujur: perlindungannya berlaku setelah logout, dan kata panik tidak bisa dibatalkan.
- **Video paper craft.** Film stop motion 54 detik tepat di bawah bagian atas halaman, plus tiga klip vertikal 30 detik di kartu "Yang paham, paham". Main tanpa suara saat terlihat; ketuk untuk menonton dengan suara.
- **README** sekarang punya pratinjau bergerak 15 detik yang mengarah ke video lengkapnya.
- **README sekarang senada dengan website.** Gambarnya diambil langsung dari website (terang atau gelap, ikut tema GitHub kamu), menggantikan screenshot lama. Gambar WebP yang lebih ringan, pratinjau link baru saat repo dibagikan, dan deskripsi repo yang lebih segar.

### Di balik layar
- Tes baru untuk Pulihkan File, Cek file backup, dan snapshot ringan per browser.
- **Versi Windows: langkah pertama.** Versi awal banget ada di `windows/` (app di tray + halaman yang mirip website). Cuma menunjukkan apa yang *akan* dihapus, belum menghapus apa pun. GitHub otomatis build dan mengetesnya di Windows setiap ada perubahan.

Perubahan yang lebih lama: [changelog lengkap](https://github.com/navi-crwn/amnesia-mac/blob/main/CHANGELOG.id.md).

## v5.15 · Lebih cepat, lebih aman, lebih gampang dihapus (7 Okt 2026)

Isinya v5.10 sampai v5.15. Hari kedua penuh tes di dunia nyata, dan hasilnya kerasa.

### Lebih cepat
- **Logout nyaris instan.** Yang dihapus dipindah dulu ke `~/.amnesia-trash` (disk yang sama, jadi 1 GB atau 100 GB sama cepatnya) lalu benar-benar dihapus belakangan, diam-diam, setelah kamu login. Hasil ukur: sekitar 2 detik untuk 300-an item.
- **Cek saat login lebih ringan** kalau logout sebelumnya selesai dengan benar. Kalau Mac crash atau dimatikan paksa, pembersihan penuh tetap jalan.
- **Snapshot otomatis cuma menyimpan app yang berubah,** dan berhenti dengan rapi setelah 150 detik supaya pembersihan selalu kebagian waktu.

### Yang baru
- **Tombol uninstall** di Pengaturan. Tidak perlu Terminal. Vault, Keep List, pengaturan, dan folder Keep tetap ada kecuali kamu pilih sebaliknya.
- **App terlanjur diseret ke Trash?** Amnesia sadar dan langsung mematikan dirinya, dan agent login menolak menghapus apa pun kalau app-nya sudah tidak ada.
- **Buka saat login** (nyala dari awal): Amnesia langsung nongkrong di menu bar setiap kamu login.
- **Kartu "Akun & data Apple"** di paling atas Keep List: iCloud, Foto, Catatan, Mail, Kalender, Kontak, Pesan, dan lainnya tetap di tempat.
- **File atau folder apa pun bisa masuk Keep List,** pilih dari Finder atau ketik path-nya.
- **Snapshot per app,** jadi menyimpan satu app tidak pernah menimpa app lain. Snapshot satu app juga bisa dihapus sendiri.
- **Folder di vault** untuk dokumen, PDF, musik, atau video.
- **Tombol Batal** untuk Snapshot, Restore, dan Backup. Salinan sebelumnya tetap aman.
- **Cek setelah Restore:** ✅ atau ❌ untuk tiap app.
- **Progres backup di semua tujuan** (flashdisk, folder, server, cloud) lengkap dengan kecepatan dan sisa waktu. Bisa backup ke folder mana saja juga.
- **Backup ke server tanpa ribet:** kotak port, cek folder saat Hubungkan, dan tes kecepatan supaya kamu tahu kira-kira berapa lama.
- **Google Drive lewat app Google Drive** kalau sudah terpasang.
- **Peringatan "Percobaan terakhir"** kalau satu password salah lagi bakal menghapus vault.
- **Aktifkan mengecek vault sudah pernah di-backup,** dan memperingatkan kalau vault belum punya snapshot.
- **Snapshot Chrome ringan** (sekitar 1 GB jadi 150 MB). Ekstensi yang bukan dari Web Store tetap disimpan.

### Yang berubah
- **Backup sekarang ikut membawa Profile Vault.** Label lamanya bikin kesan cuma untuk pindah Mac, dan gara-gara itu ada vault yang hilang tanpa cadangan.
- **Login cloud dibuka di browser biasa kamu,** dengan tombol "browser tidak terbuka?".
- **"Yang akan dihapus" lebih gampang dibaca:** ikon app asli, nama yang jelas, dan kelompok yang masuk akal.
- **Vault baru mulai kosong.** Kamu sendiri yang pilih app-nya.
- Teks lebih besar di halaman utama dan tur. Kotak password dan kata panik langsung kasih tahu kalau ketikan keduanya tidak sama.

### Yang diperbaiki
- **Pasang update saat Amnesia AKTIF malah menghapus sesi** (installer menghentikan agent di latar belakang, dan agent mengira itu logout). Sudah diperbaiki. Tapi aturan emasnya tetap: **pasang update saat Amnesia sedang Mati.**
- Shutdown tetap jalan padahal Amnesia mencoba menahannya, kalau sedang ada popup Amnesia yang terbuka.
- Restore menghapus data app yang ada di Mac tepat sebelum restore. Sekarang dipindah ke samping, tidak dihapus.
- Full Disk Access hilang setiap habis update. Sekarang setiap build ditandatangani sertifikat lokal supaya macOS mengenali app-nya.
- Login ke Dropbox, OneDrive, Box, dan pCloud selalu gagal.
- Google Drive bilang "belum login" padahal masih sinkron.
- Progres Dropbox langsung loncat ke 100%.
- Tes kecepatan server menunjukkan angka yang kebesaran.
- Saat login, jendela utama ikut terbuka padahal harusnya cuma ikon menu bar.

### Di balik layar
- `~/.amnesia/trace.log` menyimpan beberapa ratus langkah terakhir (cuma waktu dan nama langkah) untuk melacak masalah. Laporan crash juga disimpan.
- Batas waktu untuk langkah pembersihan yang bisa macet.

## v5.9.1 · Dari skrip jadi app Mac beneran (6 Okt 2026)

Isinya v5.0 sampai v5.9.1. Hari ketika Amnesia akhirnya punya wajah.

### App-nya
- **App SwiftUI asli** dengan ikon di menu bar dan logo baru (perisai dengan lubang kunci dan titik yang memudar). Cuma bisa jalan satu, tinggal di `/Applications`, dan nomor versinya ada di samping judul.
- **Tur perkenalan:** bahasa, cara kerja, cek cepat, app kamu, setup Profile Vault, dan rutinitas harian. Ditutup dengan halaman "Apa yang mau disimpan?" dan halaman "Baca ini dulu" yang wajib dicentang.
- **Bahasa Inggris dan Indonesia.** Bahasa Inggris jadi bahasa utama; di instalasi baru Amnesia ikut bahasa Mac kamu.
- **Siap pakai langsung dari GitHub:** app membawa skrip dan 7-Zip sendiri, lalu menyiapkan dirinya di `~/.amnesia`. Pasang lewat .dmg atau `brew install --cask navi-crwn/tap/amnesia`.
- **Halaman Pengaturan** dengan snapshot otomatis saat logout, notifikasi setelah login, dan cek sebelum logout yang menunjukkan apa yang akan dihapus (Lanjut atau Batal).
- **Pilih apa yang tetap ada:** pemilih app, detail per app (apa yang disimpan, di mana, berapa besar), dan folder Keep kamu sendiri di mana saja.
- **Full Disk Access cukup diminta sekali,** dengan tombol yang langsung membuka halaman Pengaturan yang tepat.

### Profile Vault
- Snapshot login yang terenkripsi: Chrome, Claude, Claude Code, OpenCode, Gemini, Kimi, GitHub CLI, WhatsApp, dan lainnya.
- Pilih app yang masuk, ganti password vault, dan progress bar untuk Snapshot, Restore, serta Simpan & Logout.
- Kata panik diketik dua kali, supaya salah ketik tidak bikin kamu terkunci.
- **Pindah ke Mac baru** dalam 4 langkah gampang, kunci Keychain ikut terbawa.

### Backup
- **Flashdisk, server sendiri (SSH), atau cloud** (Google Drive, Dropbox, OneDrive, Box, pCloud), semua tanpa Terminal.
- **Backup terjadwal** (harian atau mingguan), password bisa disimpan di Keychain kalau mau.
- Tambah folder apa saja, termasuk di luar folder home.
- Pesan yang jelas kalau server tidak bisa dihubungi, lengkap dengan alasannya.

### Keamanan
- **Uninstall yang aman:** `bash ~/.amnesia/uninstall.sh` menghapus agent login lebih dulu, jadi tidak ada yang bisa memicu pembersihan. Jangan cuma buang app ke Trash.
- **Ketentuan & peringatan** (`TERMS.id.md`) ditautkan di mana-mana. Amnesia benar-benar menghapus data.
- Catatan privasi: tanpa server, tanpa pelacakan, tidak ada yang keluar dari Mac kamu kecuali kamu sendiri yang menyiapkan backup.

### Yang diperbaiki
- Mengaktifkan Amnesia lagi bisa memicu pembersihan di tengah sesi.
- Beberapa hal kecil: label yang terpotong, kotak centang yang kelihatan tercentang padahal tidak, folder sistem di pemilih Keep List, dan skrip screenshot yang suka tersendat.

## v4.0 dan sebelumnya · Masa-masa skrip (6 Okt 2026)

- Pembersihan **sebelum** logout, restart, dan shutdown, plus cek ulang saat login.
- Profile Vault pertama: snapshot terenkripsi, 3 kali salah password langsung vault hilang, dan kata panik.
- `--dry-run` untuk melihat apa yang akan dihapus, Keep List yang fleksibel, dan tes otomatis pertama.
- Jeda yang cuma berlaku satu sesi.
