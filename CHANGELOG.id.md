# Changelog

[English](CHANGELOG.md) · **Bahasa Indonesia**

Semua yang berubah di Amnesia, yang terbaru di paling atas.
Sedikit cerita: tanggal 6 Oktober 2026 Amnesia masih berupa beberapa skrip. Dua hari (dan banyak kopi) kemudian, jadilah app Mac beneran, lengkap dengan vault, backup, dan website sendiri. Biar gampang dibaca, dua hari yang super sibuk itu dirangkum jadi tiga bab di bawah, bukan 30 catatan kecil.

Nomor versi kamu ada di samping judul Amnesia dan di bagian bawah panel menu bar.

## v5.25.0 · Mode Amnesia, profil vault dan Tanya AI (26 Okt 2026)

Rilis ini juga berisi semua perubahan v5.24.0 di bawah, yang tidak pernah dirilis sendiri.

**Matikan** Amnesia dulu sebelum memasang, lalu nyalakan lagi.

### Baru
- **Mode Amnesia: pilih seberapa banyak yang dilupakan setiap logout.** Retrograde Amnesia, Selective Amnesia (disarankan), Partial Amnesia atau Custom Amnesia.
  - **Retrograde Amnesia** seperti akun baru setiap login. Hanya folder Keep kamu dan yang dibutuhkan Amnesia yang tetap ada. Snapshot otomatis saat logout dimatikan; snapshot kamu tetap ada dan masih bisa di-restore manual.
  - **Selective Amnesia** adalah daftar dasar untuk instalasi baru: folder Keep, login app dari vault, kunci SSH, pengaturan Git dan shell. Daftar bawaan tidak lagi berisi app milik pembuatnya (app VPN, alat terminal); app kamu sendiri kamu tambahkan di Keep List. Keep List kamu yang sudah ada tidak diubah.
  - **Partial Amnesia** membiarkan app tetap menyimpan pengaturan dan loginnya. File kamu, Downloads, Desktop, cache, log, Trash dan riwayat terminal dihapus. Catatan jujur: riwayat dan cookie browser di dalam folder browser itu sendiri juga tetap ada, karena foldernya disimpan.
  - **Custom Amnesia** adalah Keep List buatan kamu sendiri. Dipilih otomatis saat kamu mengubah baris dari sebuah mode.
- **Setiap ganti mode ada pratinjau dulu**: apa yang mulai dihapus dan apa yang mulai disimpan, dengan peringatan kalau yang dihapus lebih banyak. Berlaku mulai logout berikutnya.
- **Baris Keep List kamu sendiri tetap ada**: mode hanya mengubah bagiannya sendiri yang ditandai.
- **Profil vault: restore hanya yang kamu perlukan**, misalnya Kerja atau Santai, atau semuanya. Profil bisa diganti nama, ditambah dan dihapus. Kalau satu app ada di dua profil, Amnesia memberi tahu: satu browser menyimpan satu kumpulan login, jadi browser kedua (atau profil browser terpisah) membuat pemakaian pribadi tetap terpisah.
- **Tanya AI: saran tanpa membagikan file kamu.** Amnesia membuat laporan tanpa isi file dan tanpa nama file kamu, plus prompt siap pakai. Kamu tempel ke AI pilihanmu, lalu tempel jawabannya kembali dan centang perubahan yang kamu mau. Nama folder juga bisa disembunyikan, dan laporannya bisa disimpan ke folder Keep.
- **Perintah Terminal `amnesia`**: status, preview, report, keep, history. Hanya membaca, tidak pernah menghapus apa pun. Nyalakan di Pengaturan.

### Lebih aman
- **Tanya AI tidak memakai internet**: tidak ada yang keluar dari komputer kecuali kamu menempelnya sendiri.
- **File mode yang hilang atau rusak tidak pernah mengosongkan Keep List**; modenya saja yang tidak diganti.
- **Saran AI tidak diterapkan tanpa centang dan konfirmasi kamu**; baris milik Amnesia tidak bisa dihapus lewat cara ini.

### Lebih sederhana dan diperbaiki setelah uji coba
- **Virtual machine dan Foto tidak lagi ditambahkan sendiri ke Keep List.** Kalau Amnesia menemukan virtual machine (UTM, Parallels, VirtualBox, VMware Fusion) atau library Foto yang belum disimpan, halaman Keep List dan Yang Akan Dihapus menampilkan peringatan dengan ukurannya dan dua tombol: **Keep** atau **Jangan Simpan**. Baris yang sudah ada tetap seperti semula.
- **Pengaturan dikelompokkan**: Logout, Keep, App, serta Keamanan & cek. Yang jarang dipakai (perintah Terminal, Brankas, logout otomatis, hapus app baru, kata panik, pindah Mac) ada di **Tampilkan pengaturan lanjutan**, tertutup sampai kamu membukanya. Pencarian tetap menemukan semuanya.
- **Pencarian Pengaturan menampilkan hasil pertama di atas**, tidak tersembunyi di luar jendela.
- **Membuka halaman Keep List tidak lagi menulis mode ke settings.conf**; mode hanya ditulis saat kamu benar-benar menggantinya. Memilih **Semua** di Memory Recall tidak lagi membuat `profiles.json`.
- **Pratinjau mode tidak lagi menyebut `.zshrc`, `.zprofile` atau `.gitconfig` akan dihapus.** Amnesia tidak pernah menghapus file itu di folder home; baris yang keluar dari Keep List tanpa menghapus apa pun ditampilkan terpisah.
- **Snapshot kecil menampilkan ukuran aslinya** (GitHub CLI tadinya "0 KB").
- **Cek kesehatan tidak lagi menyebut app di Profile Vault (misalnya Chrome) sebagai file besar yang ikut dihapus**: app itu kembali lewat Restore Profil.
- **Satuan ukuran sama di semua tempat** (1 MB = 1000 KB, seperti Finder): app, perintah Terminal dan laporan Tanya AI.
- **Tanya AI: "Jangan tampilkan lagi"** di pesan Disalin.
- **Aksesibilitas**: setiap sakelar, pilihan dan tombol ikon punya nama untuk VoiceOver, dan ada tes yang mengeceknya.

### Website dan README
- **Kedua website dan README** punya bagian untuk mode, profil vault dan Tanya AI, dan mencantumkan Mac v5.25.0 dan Windows v0.10.0.
- **`SECURITY.md`** menjelaskan isi laporan Tanya AI dan bahwa laporan itu tetap di komputer kecuali kamu menempelnya sendiri.
- **`llms.txt`** menjelaskan ke asisten AI cara memakai `amnesia report` dan format sarannya.

## Windows v0.10.0 · Mode Amnesia, profil vault dan Tanya AI (26 Okt 2026)

Belum dirilis. Ikut rilis Windows berikutnya.

Rilis ini juga berisi semua perubahan v0.9.0 di bawah, yang tidak pernah dirilis sendiri.

### Baru
- **Mode Amnesia: pilih seberapa banyak yang dilupakan setiap sign out.** Retrograde Amnesia, Selective Amnesia (disarankan, sama seperti sebelumnya), Partial Amnesia atau Custom Amnesia.
  - **Retrograde Amnesia** seperti akun baru setiap sign in. Hanya folder Keep kamu dan yang dibutuhkan Amnesia yang tetap ada. Snapshot otomatis vault saat sign out dimatikan; snapshot kamu tetap ada dan masih bisa di-restore manual.
  - **Selective Amnesia** menyimpan folder Keep dan mengembalikan login app dari vault, sama seperti sebelumnya.
  - **Partial Amnesia** membiarkan app tetap menyimpan pengaturan dan loginnya: semua isi AppData tetap ada. File kamu, Desktop, Documents dan Downloads dihapus. Catatan jujur: karena seluruh AppData disimpan, riwayat dan cookie browser di dalam folder browser itu sendiri (Edge juga), file Temp, daftar file terakhir dan riwayat PowerShell juga tetap ada. Cache thumbnail dan ikon, riwayat notifikasi, Recycle Bin, clipboard dan daftar terakhir di registry tetap dihapus.
  - **Custom Amnesia** adalah Keep List buatan kamu sendiri. Dipilih otomatis saat kamu mengubah baris dari sebuah mode.
- **Setiap ganti mode ada pratinjau dulu**: apa yang mulai dihapus dan apa yang mulai disimpan, dengan peringatan kalau yang dihapus lebih banyak. Berlaku mulai sign out berikutnya.
- **Baris Keep List kamu sendiri tetap ada**: mode hanya mengubah bagiannya sendiri yang ditandai.
- **Profil vault: restore hanya yang kamu perlukan**, misalnya Kerja atau Santai, atau semuanya. Profil bisa diganti nama, ditambah dan dihapus. Kalau satu app ada di dua profil, Amnesia memberi tahu: satu browser menyimpan satu kumpulan login, jadi browser kedua (atau profil browser terpisah) membuat pemakaian pribadi tetap terpisah.
- **Tanya AI: saran tanpa membagikan file kamu.** Amnesia membuat laporan tanpa isi file dan tanpa nama file kamu, plus prompt siap pakai. Kamu tempel ke AI pilihanmu, lalu tempel jawabannya kembali dan centang perubahan yang kamu mau. Nama folder juga bisa disembunyikan, dan laporannya bisa disimpan ke folder Keep.

### Lebih aman
- **Tanya AI tidak memakai internet**: tidak ada yang keluar dari komputer kecuali kamu menempelnya sendiri.
- **Daftar mode yang hilang atau rusak tidak pernah mengosongkan Keep List**; modenya saja yang tidak diganti.
- **Saran AI tidak diterapkan tanpa centang dan konfirmasi kamu.**

### Lebih sederhana dan diperbaiki setelah uji coba
- **Pengaturan dikelompokkan**: Keep (pintasan dan Kunci Keep), Yang tetap aman, dan App. Pengaturan lanjutan tertutup sampai kamu membukanya; pencarian tetap menemukan semuanya dan menampilkan hasil pertama di atas.
- **Membuka halaman Keep List tidak lagi menulis mode ke pengaturan**; mode hanya ditulis saat kamu benar-benar menggantinya. Memilih **Semua** untuk restore tidak lagi membuat `profiles.json`.
- **Pratinjau mode menampilkan terpisah baris yang keluar dari Keep List tanpa menghapus apa pun**, bukan di bawah "mulai sekarang dihapus".
- **Ukuran di laporan Tanya AI memakai satuan yang sama dengan app** (1 MB = 1000 KB).
- **Aksesibilitas**: tombol Keluarkan, Keep, Hapus dan Uninstall di daftar, serta kotak centang dan pilihan tanpa judul yang terlihat, sekarang memberi tahu pembaca layar item mana yang dimaksud.

## v5.24.0 · Halaman Perawatan, dan pembersihan yang berhenti kalau ragu (26 Okt 2026)

**Matikan** Amnesia dulu sebelum memasang, lalu nyalakan lagi.

Amnesia sudah menghapus sebagian besar folder home di setiap logout, jadi Perawatan terutama berguna untuk folder Keep, app yang kamu simpan dan file besar yang dibuat di sesi ini.

### Baru
- **Perawatan: halaman baru untuk mengosongkan ruang kapan saja, selalu dengan daftar untuk dicek dulu.** Tidak ada yang berisiko dicentang untukmu, dan kamu mengonfirmasi jumlah, ukuran dan tujuannya sebelum ada yang dipindah.
- **Ringkasan disk** menunjukkan apa yang memakan ruang: folder Keep, vault, tempat sampah, cache, folder dan file terbesar, unduhan lama. Hanya dibaca.
- **Bersihkan sekarang** mengosongkan cache, log dan tempat sampah Amnesia; cache app yang sedang terbuka dilewati. Mengosongkan Trash macOS juga ada di daftar, tapi tidak pernah dicentang untukmu, karena itu permanen.
- **Hapus app** memindahkan app yang kamu pasang beserta cachenya ke Trash; data pribadinya tetap ada kecuali kamu centang.
- **Folder build project** (node_modules, target, build, dist dan lainnya) bisa dipindah ke Trash; folder yang dipakai 7 hari terakhir atau dilacak git tidak disentuh.
- **Installer lama** (.dmg, .pkg) dipindah ke Trash; image disk dan mesin virtual tidak pernah dipilihkan.
- **Perawatan ringan** tanpa password admin: segarkan thumbnail Quick Look, mulai ulang Dock.
- **Cek kesehatan** menampilkan sisa ruang disk, memori dan kondisi baterai.
- **Setiap Perawatan tercatat di Riwayat** beserta ruang yang dikosongkan.

### Diperbaiki
- **Kolom cari di Pengaturan tetap di atas** saat kamu scroll pengaturan.

### Lebih aman
- **Pembersihan berhenti dan tidak menghapus apa pun kalau Keep List tidak bisa dibaca atau hilang**, dan dicatat di Riwayat.
- **Salinan Keep List terakhir yang baik disimpan** dan dipakai untuk memulihkannya.
- **Setiap penghapusan lewat satu pengecekan** yang menolak folder home, folder Keep, `~/.amnesia` dan apa pun di luar folder home (kecuali app baru yang Anda minta dihapus Amnesia).
- **Kalau pengecekan tidak yakin** (cloud, iCloud, link, pemilik), item disimpan.
- **Saat login dan Bersihkan Sekarang, folder yang masih dipakai app yang terbuka dilewati** dan dibersihkan lain kali.

### Website dan README
- **Kedua website dan README** punya bagian Perawatan dan mencantumkan Mac v5.24.0 dan Windows v0.9.0.
- **`SECURITY.md` baru**: cara melaporkan masalah keamanan secara pribadi, dan daftar jujur apa yang dijaga Amnesia dan apa yang tidak bisa.
- **`llms.txt` baru**: panduan singkat untuk asisten AI yang membantu orang memasang Amnesia, supaya mereka mengecek Yang Akan Dihapus dan folder Keep dulu.
- **Tempat mendapatkan Amnesia**: README sekarang menyebut Amnesia hanya tersedia dari github.com/navi-crwn/amnesia, websitenya di GitHub Pages dan Homebrew tap `navi-crwn/tap`.

## Windows v0.9.0 · Halaman Perawatan, dan pembersihan yang berhenti kalau ragu (26 Okt 2026)

Belum dirilis. Ikut rilis Windows berikutnya.

Amnesia sudah menghapus sebagian besar folder user di setiap sign out, jadi Perawatan terutama berguna untuk folder Keep, app yang kamu simpan dan file besar yang dibuat di sesi ini.

### Baru
- **Perawatan: halaman baru untuk mengosongkan ruang kapan saja, selalu dengan daftar untuk dicek dulu.** Tidak ada yang berisiko dicentang untukmu, dan kamu mengonfirmasi jumlah, ukuran dan tujuannya sebelum ada yang dipindah.
- **Ringkasan disk** menunjukkan apa yang memakan ruang: folder Keep, vault, Recycle Bin, Temp, folder dan file terbesar, unduhan lama. Hanya dibaca.
- **Bersihkan sekarang** mengosongkan Temp, crash dump, cache app dan tempat sampah Amnesia. Recycle Bin juga ada di daftar, tapi tidak pernah dicentang untukmu, karena mengosongkannya permanen. File yang masih dibuka Windows dilewati dan dihitung, bukan ditampilkan sebagai error.
- **Hapus app**: program yang dipasang khusus untukmu menjalankan uninstaller-nya sendiri, program yang dipasang untuk semua pengguna membuka Pengaturan Windows. Sisa cache dipindah ke Recycle Bin; data pribadi tetap ada kecuali kamu centang.
- **Folder build project** (node_modules, target, build, dist, juga bin dan obj dari project .NET, dan lainnya) bisa dipindah ke Recycle Bin; folder yang dipakai 7 hari terakhir atau dilacak git tidak disentuh.
- **Installer lama** (.msi, .msix) dipindah ke Recycle Bin; file setup .exe ditampilkan tapi tidak pernah dipilihkan, dan image disk serta mesin virtual tidak pernah dipilihkan.
- **Perawatan ringan** tanpa admin: mulai ulang Explorer, buka Startup apps dan pengaturan Storage.
- **Cek kesehatan** menampilkan sisa ruang disk, memori dan isi baterai.
- **Setiap Perawatan tercatat di Riwayat** beserta ruang yang dikosongkan.

### Lebih aman
- **Pembersihan berhenti dan tidak menghapus apa pun kalau Keep List tidak bisa dibaca atau hilang**, dan dicatat di Riwayat.
- **Salinan Keep List terakhir yang baik disimpan** dan dipakai untuk memulihkannya.
- **Setiap penghapusan lewat satu pengecekan** yang menolak folder user, folder Keep, `.amnesia` dan apa pun di luar folder user.
- **Kalau pengecekan tidak yakin** (folder cloud, link, pemilik), item disimpan.

## v5.23.1 · Popup panjang bisa di-scroll, website dan README menyusul (18 Okt 2026)

**Matikan** Amnesia dulu sebelum memasang, lalu nyalakan lagi.

### Diperbaiki
- **Popup panjang sekarang bisa di-scroll.** Restore banyak app membuat popup hasilnya lebih tinggi dari layar, jadi tombolnya tidak terjangkau. Sekarang popup berhenti di sekitar setengah tinggi layar dan isinya di-scroll; tombol OK dan Batal selalu terlihat.

### Website dan README
- **Tujuh bahasa (ditambahkan 20 Okt).** Kedua halaman sekarang tersedia dalam English, 简体中文, Deutsch, Bahasa Indonesia, 日本語, Português (Brasil) dan Español, masing-masing di alamatnya sendiri (misalnya `/de/` dan `/de/win/`). Menu bola dunia di atas untuk ganti bahasa; saat pertama berkunjung, halaman Inggris mengarahkan ke bahasa browser kamu kalau halamannya ada. Halaman dibuat dari satu sumber oleh `site/i18n/build.py`. README punya baris bahasa yang menuju ke tiap halaman.
- **Halaman Mac** menampilkan v5.23: enam kartu fitur baru (Kunci Keep, Cek kesehatan, Brankas, update bertanda tangan, aman untuk iCloud, Claude dan Claude Code), Kembalikan data sebelum restore, cara cek file unduhan, dan lima jawaban FAQ baru. Tidak lagi bergeser ke samping di HP.
- **Halaman Windows** dibangun ulang untuk v0.8: bagian open source dengan grafik commit 3D, papan folder 3D untuk yang aman saat sign out, brankas 3D, Cek kesehatan, peringatan Windows yang asli, tutorial 8 langkah dan 36 foto layar app yang baru. Jawaban FAQ yang salah dibetulkan: membatalkan sign out tidak lagi membatalkan pembersihan.
- **README** (Inggris dan Indonesia) memuat versi dan fitur terbaru, plus bagian Amnesia untuk Windows. Cek update mingguan sampai bulanan, bukan harian. `windows/README.md` tidak lagi bilang "preview, tes di VM".

## Windows v0.8.2 · Pertanyaan panjang bisa di-scroll (18 Okt 2026)

Belum dirilis. Ikut rilis Windows berikutnya.

### Diperbaiki
- **Pertanyaan panjang di-scroll di dalam popup**, jadi tombolnya selalu terlihat. Tur selamat datang juga bisa di-scroll di jendela kecil.

## v5.23.0 · Claude di Keep List benar-benar tersimpan, restore lebih aman, Brankas tertutup dengan benar (17 Okt 2026)

**Matikan** Amnesia dulu sebelum memasang, lalu nyalakan lagi.

Semua di sini hasil tes di Mac sungguhan tanggal 17 Okt. Bug dari tes sebelumnya (folder symlink, nama beraksen, hapus gagal dihitung bersih) semuanya lulus kali ini.

### Diperbaiki (penting)
- **Claude ada di Keep List, tapi chat Claude Code tetap hilang.** Keep List cuma menyimpan app Claude Desktop. Chat dari tab Code ada di `~/.claude` dan `~/.claude.json`, jadi terhapus setiap logout dan baru kembali lewat restore vault. Sekarang menyimpan Claude ikut menyimpan keduanya. Pilih App menambahkannya saat kamu menyimpan Claude, dan pembersihan juga menjaganya sendiri selama Claude ada di daftar kamu.
- **Restore bisa memundurkan data kamu.** Restore selalu memasang snapshot, walaupun data di Mac lebih baru. Sekarang:
  - yang ada di Keep List tidak pernah ditimpa restore
  - kalau data sebuah app lebih baru dari snapshot-nya, kamu ditanya dulu ("Tetap Restore" atau Batal)
  - setelah restore ada tombol **Kembalikan data sebelum restore** di halaman Vault, sampai logout berikutnya
- **Brankas tidak tertutup saat logout** ("box close failed"), baru tertutup saat login. Sekarang Amnesia mencoba beberapa kali, mencari app yang masih memakainya (hanya dihitung, tanpa nama), lalu menutupnya paksa. Kalau tetap gagal, kamu diberi tahu setelah login dan ada peringatan di Cek kesehatan.

### Diperbaiki
- **Snapshot otomatis saat logout tidak dilewati lagi** kalau kamu baru snapshot kurang dari 10 menit sebelumnya. Dulu, pekerjaan sesudah snapshot manual bisa hilang. App yang tidak berubah tetap dilewati, dan snapshot yang macet tidak bisa menahan pembersihan.
- **App dibuka lagi setelah Snapshot Sekarang.** App yang tadinya terbuka dan ditutup untuk snapshot dibuka lagi sesudahnya, sama seperti setelah restore.
- **Cek kesehatan** sekarang juga menampilkan Akses Disk Penuh, folder symlink dan mesin virtual saat semuanya aman, dan peringatan kalau Brankas gagal ditutup. "1 things" sekarang "1 thing".
- **Salinan "sebelum restore"** (bisa beberapa GB) tidak lagi muncul sebagai file besar yang menakutkan. Cek kesehatan menjelaskan isinya dan kapan hilang, dan salinan yang lebih dari 3 hari dihapus.
- **Kunci Keep:** teks Pengaturan dan halaman Batasan sekarang bilang terus terang: nama file dan folder langsung di dalam Keep tetap terlihat saat terkunci.

## Windows v0.8.1 · Sign out langsung bersih, "Simpan" di app baru benar-benar menyimpan (17 Okt 2026)

Semua di sini hasil tes di laptop Windows 11 sungguhan tanggal 17 Okt.

### Diperbaiki (penting)
- **Sign out biasa masih baru bersih saat sign in berikutnya.** Menutup brankas dan membuat daftar menghabiskan beberapa detik yang diberi Windows, jadi pembersihan hampir tidak sempat jalan. Sekarang Amnesia membersihkan duluan, tepat saat Windows bertanya "boleh sign out?", menampilkan "Amnesia is cleaning up..." selama bekerja, lalu menutup brankas sesudahnya (brankas ada di Keep, jadi tidak pernah dihapus). Satu konsekuensi: kalau kamu membatalkan sign out setelah itu, pembersihan sudah terjadi, sama seperti "Bersihkan sekarang".
- **"Simpan" di daftar app baru tidak menyimpan app-nya.** Kamu tekan Simpan, tapi folder program app di AppData tetap terhapus saat sign out, app jadi rusak. Simpan sekarang juga memasukkan folder program dan folder data app itu ke Keep List.
- **App baru terhapus permanen, bukan menunggu 3 hari.** Pembersihan biasa sampai ke foldernya duluan. Sekarang folder app baru selalu masuk tempat sampah Amnesia dan menunggu 3 hari.
- **Kartu brankas bertuliskan "Windows sekali pakai".** Teksnya tertukar dengan Windows Sandbox. Kedua kartu punya teks dan tombolnya sendiri lagi.

### Diperbaiki
- **Tombol panik lebih cepat** kalau brankas besar: Amnesia minta sign out langsung setelah membersihkan, dan menutup brankas selagi Windows sign out.
- **Uninstall memberi peringatan** kalau brankas masih berisi file. Juga tidak lagi menyimpan salinan kedua brankas yang sama besar.
- **Daftar app baru lebih jelas:** satu app satu baris (tidak ada lagi angka registry seperti "121a0be4-…"), dan app yang cuma di-update (nomor versi baru) tidak dianggap app baru lagi. "Simpan semua" dicatat di log dan Riwayat.
- **Peringatan startup** sekarang muncul di jendela yang sedang terbuka, dan dicatat di trace.log. Password Keep yang salah saat uninstall juga dicatat (tidak pernah password-nya).
- **Saran Keep List:** satu app dengan folder di Local dan Roaming jadi satu pilihan yang menyimpan keduanya. Folder teknis seperti Sentry atau folder crash tidak disarankan lagi.
- **Keep masih terkunci dari versi lama:** Amnesia melihatnya dan menawarkan untuk membukanya dari halaman utama dan Cek kesehatan.
- Tes otomatis: 294 (dulu 273).

### Masih perlu dites di PC sungguhan
- Sign out biasa dengan banyak file bersih sebelum layar sign in.

## v5.22.0 · Update bertanda tangan, aman untuk iCloud, Kunci Keep, Cek kesehatan (17 Okt 2026)

**Matikan** Amnesia dulu sebelum memasang, lalu nyalakan lagi.

### Baru
- **Kunci Keep (baru).** Finder dan app lain tidak bisa membuka atau mengubah isi folder Keep sampai kamu mengetik password Keep di Amnesia. Terkunci lagi setelah 5–60 menit, saat layar terkunci, saat Amnesia ditutup, dan setiap logout dan login. Biar jelas: ini memakai izin macOS, bukan enkripsi. Siapa pun yang login sebagai kamu bisa melepasnya dengan `chmod -RN ~/Keep`. Mati secara default (Pengaturan → Kunci Keep).
- **Brankas (eksperimen).** Disk terenkripsi (APFS, AES-256) di dalam folder Keep, untuk file yang benar-benar harus rahasia. Amnesia menutupnya sebelum setiap pembersihan. Kalau lupa password-nya, file di dalamnya hilang.
- **Cek kesehatan.** 1 halaman yang menampilkan:
  - apakah Amnesia aktif dan agent login menunjuk ke app yang benar-benar ada
  - Akses Disk Penuh
  - iCloud Desktop & Documents, dan folder yang berupa symlink
  - mesin virtual yang tidak disimpan, dan file 1 GB ke atas yang akan dihapus
  - umur backup terakhir
  - cek update, Kunci Keep dan FileVault

  Sebagian besar baris punya tombol untuk memperbaikinya.
- **Halaman Batasan.** Daftar jujur yang tidak bisa dihapus Amnesia: Time Machine dan snapshot APFS, Spotlight, iCloud dan cloud lain, swap dan sleepimage, log sistem, akun lain, dan folder Keep (tidak dienkripsi).
- **App baru di Profile Vault:** Signal, Session, Element, Telegram, Obsidian, Notion, Zoom dan Bitwarden. Semuanya belum dicentang di awal, jadi kamu yang memilih.
- **Saran app untuk vault.** Amnesia menampilkan app lain yang kelihatannya menyimpan login (punya item "Safe Storage" di Keychain). Tidak ada yang ditambahkan sebelum kamu centang, dan bisa dikeluarkan lagi.
- **Meter kekuatan password** untuk password vault, Kunci Keep dan Brankas. Cuma perkiraan kasar, bukan jaminan.

### Diperbaiki
- **Folder yang berupa symlink tidak pernah dikosongkan lewat link-nya.** Dulu, kalau `~/Documents` menunjuk ke dalam folder Keep, membersihkan Documents ikut mengosongkan Keep.
- **Nama di Keep List yang pakai aksen ("Café") cocok dalam bentuk mana pun yang dipakai macOS (NFC atau NFD).** Dulu nama yang diketik di Amnesia bisa tidak cocok dengan nama yang sama dari Finder atau backup lama.
- **iCloud Desktop & Documents: Desktop dan Documents dilewati.** Membersihkannya berarti ikut menghapus file di iCloud dan di perangkat Apple kamu yang lain. Amnesia mencatatnya dan memberi tahu di halaman Yang Akan Dihapus dan di Cek kesehatan. Kalau ragu, dilewati: lebih baik ada file yang tertinggal daripada terhapus dari iCloud.
- **File yang gagal dihapus tidak dihitung "dibersihkan" lagi.** Baris pembersihan terakhir dan Riwayat sekarang menulis "N gagal dihapus". Amnesia mencobanya lagi lain kali. trace.log hanya mencatat jumlah dan bagiannya (misalnya "Downloads"), tidak pernah nama file.
- **Pengosongan tempat sampah Amnesia sekarang dicatat.** Dulu jalan diam-diam di background. Sisanya dihitung dan ditampilkan di app.
- **Pekerjaan vault tidak bisa tumpang tindih.** Snapshot atau restore kedua sekarang menunggu, lalu berhenti dengan pesan yang jelas. Sisa pekerjaan yang terputus dibersihkan dulu.
- **Restore tidak lagi menulis kunci privat vault ke disk.** Kuncinya tetap di memori.
- **Menyimpan password backup di Keychain** tidak lagi menaruhnya di baris perintah, yang bisa dilihat program lain di Mac.
- **Memindah atau mengganti nama Amnesia.app tidak lagi mematikan perlindungan diam-diam.** Muncul notifikasi selagi kamu masih login, dan alasannya dicatat di trace.log.

### Diubah
- **Update dari dalam app harus bertanda tangan.** Amnesia hanya memasang update kalau `SHA256SUMS.txt` punya tanda tangan developer yang benar (ECDSA P-256). Kalau tanda tangannya tidak ada atau salah, kamu diarahkan ke halaman rilis.
- **Backup yang sebagian filenya tidak bisa dibaca 7-Zip** (sedang dibuka app lain, tidak ada izin) sekarang "selesai dengan peringatan", bukan "berhasil" biasa. Kamu melihat apa saja yang dilewati. Daftar itu hanya ditampilkan, tidak disimpan.
- Halaman Backup sekarang menyebut apa yang sengaja tidak ikut: folder bernama `node_modules` atau `.tmp`, dan file `.DS_Store`.
- Teks Doomsday, kata panik dan Hapus Vault sekarang menjelaskan apa adanya cara menghapusnya:
  - file dihapus dengan cara biasa, tidak ditimpa
  - vault-nya sendiri terenkripsi
  - file yang dikosongkan dari Keep tidak terenkripsi
  - backup, Time Machine dan cloud tidak disentuh
- Menghapus Amnesia (dari app atau `uninstall.sh`) meminta password Keep dan membuka Keep dulu. Tanpa password, Keep tetap terkunci dan kamu diberi perintah untuk membukanya: `chmod -RN ~/Keep`.

## Windows v0.8.0 · Keep aman dari "Hapus app baru", folder cloud dan VM tidak disentuh, ada Cek kesehatan (17 Okt 2026)

Matikan Amnesia dulu sebelum memasang di atas versi lama, lalu nyalakan lagi.

Versi ini hasil audit lengkap dan tes di laptop Windows 11 sungguhan. Dua perbaikan pertama yang paling penting: tolong update.

### Diperbaiki (penting)
- **"Hapus app baru" bisa menghapus folder di dalam Keep.** Saat dites, folder yang ada di Keep List ikut terhapus permanen. Sekarang yang diambil hanya folder milik app itu sendiri di AppData, tidak pernah yang ada di Keep List, tidak pernah folder yang berisi sesuatu yang disimpan, dan tidak pernah folder bersama seperti Programs atau Packages. Dan tidak langsung dihapus lagi: foldernya masuk ke tempat sampah Amnesia dan menunggu **3 hari** dulu.
- **Folder cloud tidak pernah dihapus lagi.** Dropbox, Google Drive, iCloud Drive, Nextcloud, MEGA, Box, pCloud, Proton Drive dan lainnya tetap di tempatnya, juga semua folder yang dikenal Windows sebagai folder sync. Dulu, memindahkannya terlihat seperti "dihapus" bagi app sync-nya, sehingga file kamu di cloud bisa ikut terhapus. File yang hanya ada di cloud ("Files On-Demand") juga dibiarkan.
- **Virtual machine dan image disk besar tetap aman.** Disk VirtualBox, Hyper-V, VMware, WSL, Docker dan emulator Android, juga file .iso 1 GB ke atas. Bisa dimatikan di Pengaturan > Perlindungan.

### Diperbaiki
- **Sign out lebih cepat dan lebih bisa diandalkan.** Amnesia membuat daftar yang akan dihapus begitu Windows meminta sign out, tidak menghitung ukuran, dan menghentikan snapshot vault yang sedang berjalan supaya pembersihan dapat waktunya. trace.log sekarang mencatat lama tiap langkah. (Sign out biasa kadang menunda penghapusan ke login berikutnya; ini masih perlu dites sekali lagi di laptop kamu.)
- **Tombol panik saat Jeda sekarang jalan.** Sign out cepat membatalkan jeda, menutup Explorer, menghapus cache thumbnail dan ikonnya, membersihkan, lalu sign out. Kalau Windows lambat sign out, dicoba lagi setelah 8 detik.
- **Startup dimatikan = Amnesia diam-diam berhenti.** Kalau Startup apps di Task Manager mematikan Amnesia, halaman utama sekarang menampilkan peringatan dengan tombol **Nyalakan lagi**. Saat Amnesia mati, dia tidak ikut menyala bersama Windows lagi (switch baru: Pengaturan > Perlindungan > Buka saat login).
- **Keep tetap terkunci setelah uninstall.** Uninstall dari app sekarang meminta password Keep dan membuka Keep dulu. Uninstall dari Pengaturan Windows juga menanyakannya. Tanpa password, Keep tetap terkunci dan kamu dapat satu perintah untuk membukanya.
- **Uninstaller tidak lagi menghapus data Amnesia sendiri.** Ditanya dulu (pilihan awal: Tidak), dan tidak pernah saat Keep masih terkunci.
- **Baris Keep List yang gagal tersimpan** sekarang muncul sebagai error, bukan "Tersimpan" palsu.
- **Backup:** backup lama di dalam Keep tidak ikut dikemas ke setiap backup baru, folder backup di dalam Keep ditolak, file yang sedang dipakai dihitung dan disebut di hasilnya, dan restore yang terputus (listrik mati) membersihkan sisanya sendiri dan mengembalikan vault lama kamu.
- **Jendela terlalu sempit di skala 150%.** Sekarang ukurannya ikut skala Windows.
- Crash saat jendela ditutup sementara pekerjaan panjang masih menjawab.
- Jeda tercatat di riwayat sebagai "Dijeda untuk satu sesi" (di log dulu tertulis "turned off").
- Helper admin hanya membaca daftar folder miliknya sendiri.

### Baru
- **Ikon dan nama app di Keep List.** Barisnya menampilkan "Discord" dengan ikonnya, bukan cuma path. **Simpan sebuah app** menampilkan app yang terpasang (termasuk app Microsoft Store) dan menyimpan semua folder app itu dengan sekali klik.
- **Cek kesehatan** di halaman utama: Amnesia nyala atau tidak, ikut startup atau tidak, pembersihan terakhir, file yang tertinggal, folder cloud, vault, backup, kunci Keep. Di bawahnya: **Yang tidak bisa dilakukan Amnesia**, batasan yang jujur.
- **Update bertanda tangan (gratis).** Updater di app sekarang juga mengecek tanda tangan developer pada SHA256SUMS.txt. Tanpa tanda tangan, tidak dipasang dari app: halaman rilis yang dibuka.
- **Brankas (eksperimen):** folder terkunci di dalam Keep. Saat tertutup isinya satu file terenkripsi, saat dibuka ada di Keep\Safe. Amnesia menutupnya lagi setiap sign out.
- **Opsional:** hapus juga data app Microsoft Store, dan hapus juga password app di Credential Manager (tidak pernah akun Microsoft, OneDrive atau Office). Keduanya mati secara default.
- **Vault:** Session, WhatsApp, Element, Obsidian, Thunderbird, Bitwarden, Antigravity, Windsurf, Gemini CLI dan OpenCode. Vault juga menyarankan app terpasang yang belum dikenalnya. Ada pengukur kekuatan password, dan teks Doomsday sekarang jujur soal apa yang tidak bisa dicegahnya.
- **Setup:** halaman selamat datang, syarat, peringatan singkat sebelum pasang dan tur singkat sesudahnya, dalam bahasa Inggris dan Indonesia.
- Tes otomatis: 273 (dulu 207).

### Masih perlu dites di PC sungguhan
- Sign out biasa langsung membersihkan (bukan di login berikutnya).
- Cache thumbnail setelah sign out biasa.
- Keep List dengan folder app Microsoft Store.

## Windows v0.7.2 · Lencana "Tes di VM" hilang, website Windows lengkap (14 Okt 2026)

Matikan (Turn Off) Amnesia dulu sebelum install di atas versi lama, lalu nyalakan (Turn On) lagi.

- Lencana "Tes di VM" di samping nama sudah tidak ada, begitu juga "tes di VM sebelum di PC asli" di tur sambutan. Cara kerja app sama dengan v0.7.1.
- **Website Windows baru:** halaman Windows sekarang seperti halaman Mac, dengan animasi yang sama, screenshot asli app (Inggris dan Indonesia, gelap dan terang), cara pasang plus penjelasan peringatan SmartScreen, kunci Keep dan kunci lab, dan FAQ khusus Windows.
- **Website Mac:** menampilkan fitur v5.20 dan v5.21 (cari di Pengaturan dan di What Gets Deleted, alat developer, jadwal cek update, virtual machine disimpan, grup Trash) dan memperbaiki jawaban lama "cek update sekali sehari".

## v5.21.0 · App baru terlihat di pratinjau, cari di "Yang Akan Dihapus", virtual machine aman (13 Okt 2026)

Matikan (**Turn Off**) Amnesia dulu sebelum install, lalu nyalakan lagi.

### Fitur baru
- **Cari di "What Gets Deleted".** Ada kotak pencarian (nama atau lokasi file, di semua grup), pilihan grup, dan **Terbesar dulu**. Ukuran tiap baris sekarang langsung tampil, tanpa harus membuka grupnya.
- **Peringatan file besar.** Di atas daftar muncul peringatan kalau ada file 1 GB atau lebih, atau data virtual machine, yang akan dihapus. Empat yang terbesar ditampilkan beserta ukurannya, dengan saran memindahkannya ke Keep.
- **Virtual machine aman secara bawaan.** UTM, Parallels, VirtualBox dan VMware Fusion sekarang ada di "Pilih App". Kalau Amnesia menemukan data VM, data itu otomatis dimasukkan ke Keep List (sekali saja; kalau kamu matikan, tetap mati). Kalau dimatikan, barisnya jelas menulis "Dihapus saat logout, virtual machine juga!".
- **Trash punya grup sendiri:** "Trash (dikosongkan saat logout)", dengan ukurannya, supaya tidak ada yang kaget isi Trash ikut hilang.

### Diperbaiki
- **App yang dipasang setelah Amnesia nyala tidak tampil di pratinjau**, padahal benar-benar dihapus saat logout. Sekarang tampil di grup "App yang dipasang belakangan", lengkap dengan ikonnya.
- App yang sempat terbuka sendiri saat login (sebelum vault dipulihkan) sekarang ditutup, lalu dibuka lagi setelah datanya kembali.
- Memulihkan folder pilihan dari vault tidak lagi bisa error.

## Windows v0.7.1 · Sign out membersihkan lagi, Explorer tidak kedip, tampilan lebih rapi (13 Okt 2026)

Matikan (Turn Off) Amnesia dulu sebelum install di atas versi lama, lalu nyalakan (Turn On) lagi.

### Diperbaiki
- **Sign out tidak membersihkan** (file baru terhapus saat login berikutnya). Snapshot vault otomatis jalan duluan dan memakan waktu yang diberikan Windows. Sekarang saat sign out Amnesia **langsung membersihkan**, dan Windows menampilkan "Amnesia is cleaning up..." sampai selesai. Kalau sign out dibatalkan, tidak ada yang terhapus.
- **Snapshot otomatis pindah:** app di vault disimpan di belakang layar **setelah kamu menutupnya** (dicek tiap menit, hanya kalau berubah). Alat tanpa jendela (Claude Code, Git, folder pilihan) disimpan setelah 3 menit tidak berubah. Catatan: kalau Edge tetap jalan di belakang ("startup boost"), Edge baru tersimpan setelah benar-benar tertutup.
- Sisa snapshot yang terputus (`*.amv.new`) dibersihkan saat Amnesia mulai.
- **Kunci Keep membuat ikon Desktop kedip.** Kunci sekarang menutup isi Keep, bukan foldernya, jadi Explorer tetap bisa membaca ikon Keep. Keep keluar dari sidebar selama terkunci dan kembali saat dibuka. Nama file di dalam Keep tetap terlihat, tapi tidak bisa dibuka, dan tidak ada program yang bisa menulis ke Keep.
- **Explorer kedip setelah pembersihan saat login.** Explorer sekarang diberi tahu supaya memuat ulang ikonnya.
- Cache ikon dan thumbnail tidak pernah dihapus lagi saat Explorer sedang jalan (penyebab lama ikon berkedip).
- Peringatan palsu "setup Edge belum selesai" di vault.
- Dialog "hapus ruang kosong" tidak terpotong lagi di jendela kecil.
- Claude dari Microsoft Store ikut disarankan di Keep List.
- Ikon Keep di sidebar sekarang ikut ungu.
- Daftar "Hapus app baru" dimuat ulang setelah uninstaller selesai.

### Berubah
- **Tampilan lebih rapat:** halaman utama model kotak-kotak (bento), footer selalu di paling bawah, Pengaturan dikelompokkan (Umum, Update & bantuan, lalu Lanjutan: Saat meninggalkan PC, Privasi & Windows, Program, Kunci).
- **Cari di "Yang akan dihapus"**: kotak pencarian, filter per folder (dengan jumlah dan ukuran), dan Terbesar dulu.
- **Kumpulkan log** menampilkan status dan lokasi file, dan tombolnya tidak bisa diklik dua kali.
- Kartu pintasan Keep menulis "muncul setelah Turn On" selama Amnesia mati.
- Tes otomatis: 207 (sebelumnya 190).
- **Bukan versi tes lagi.** Website, README dan pertanyaan saat menyalakan tidak lagi menulis "virtual machine saja". Ketemu bug atau mau ada perubahan? Buka issue di GitHub.

## v5.20.0 · Cari di Pengaturan, jendela bisa diubah ukurannya, pilih app lebih pintar (12 Okt 2026)

Matikan (**Turn Off**) Amnesia dulu sebelum install, lalu nyalakan lagi.

### Fitur baru
- **Cari di Pengaturan.** Ada kotak pencarian di atas Pengaturan. Ketik dalam bahasa Inggris atau Indonesia, apa pun bahasa app-nya, dan hanya pengaturan yang cocok yang tetap tampil. Kata lain juga bisa, misalnya "filevault", "password", "startup", "idle", "pindah" atau "versi". Kalau tidak ada yang cocok, app memberi tahu.
- **Lanjutan sekarang ada di dalam Pengaturan**, sebagai grup di bagian bawah, di bawah pengaturan biasa, dan ikut dicari. Halaman Lanjutan yang terpisah sudah tidak ada (sama seperti app Windows).
- **Ukuran jendela bisa diubah.** Jendela utama bisa dibesarkan atau dikecilkan, minimal 440×560. Tetap terbuka di 480×690, dan di layar kecil otomatis lebih kecil supaya muat.
- **Deteksi app lebih akurat di "Pilih App".** Amnesia sekarang menemukan lebih banyak data app lewat bundle id: login web (HTTPStorages), data WebKit, folder bersama yang memakai nama tim, dan folder dengan nama asli app. Cache dan posisi jendela sengaja tidak diambil.
- **Alat developer & terminal.** "Pilih App" punya bagian baru berisi pengaturan SSH, GitHub CLI, zsh/bash, Vim/Neovim, tmux, npm, Docker, AWS, gcloud, kubectl, OpenCode, Claude Code, Codex dan Gemini CLI. Hanya yang ada di Mac kamu yang muncul.
- **Atur seberapa sering cek update:** Mati, tiap minggu, tiap 2 minggu atau tiap bulan. Bawaannya tiap minggu. Cek harian yang lama otomatis jadi mingguan, dan yang sudah Mati tetap Mati.

### Perbaikan & lebih aman
- App yang dulu sudah kamu simpan tetap tampil NYALA di "Pilih App" walaupun Amnesia sekarang tahu folder tambahannya, jadi tombol Simpan hanya **menambah** baris di Keep List dan tidak pernah menghapus baris lama.
- Mematikan satu app tidak lagi menghapus folder yang masih dibutuhkan app lain yang kamu simpan.

## Windows v0.7.0 · Kunci lab, kunci Keep, cadangan snapshot vault, cek update tidak spam (12 Okt 2026)

Versi percobaan Windows, tetap **tes di virtual machine saja**. Matikan (Turn Off) Amnesia dulu sebelum install di atas versi lama, lalu nyalakan (Turn On) lagi.

### Fitur baru
- **Kunci lab** (Pengaturan → Lanjutan, untuk admin). Untuk PC yang dipakai banyak orang, seperti lab komputer atau perpustakaan. Pasang PIN minimal 6 angka, lalu Windows minta izin admin sekali. Setelah itu user Windows ini tidak bisa mematikan, menjeda, menutup, meng-uninstall Amnesia, atau mengubah pengaturan dan Keep List tanpa PIN. Amnesia selalu jalan saat sign in (dijalankan Windows, bukan oleh user), dan halamannya menampilkan "Dikunci admin". PIN membuka pengaturan selama 10 menit. Salinan yang dikunci ada di `C:\ProgramData\Amnesia\lab`, yang hanya bisa dibaca user biasa. Catatan jujur: orang masih bisa mematikan Amnesia lewat Task Manager, tapi cek saat sign in berikutnya tetap membersihkan.
- **Kunci Keep** (Pengaturan → Lanjutan). Folder Keep hanya bisa dibuka lewat Amnesia (Buka Keep, menu tray, atau shortcut di Desktop) dengan password sendiri. Terkunci lagi setelah menit yang kamu pilih, saat layar dikunci (Win+L), saat sign out dan saat Amnesia mulai. Backup, pulihkan, Kumpulkan log dan Doomsday membuka kuncinya sebentar secara otomatis. Catatan jujur: file-nya tidak dienkripsi (pakai BitLocker untuk itu), dan orang yang login sebagai kamu dan paham Windows bisa melepas kuncinya lewat Properties folder. Lupa password? Caranya sama: Properties → Security, hapus baris "Deny".
- **Cadangan snapshot vault.** Setiap app menyimpan snapshot sebelum yang terbaru sebagai "sebelumnya". Kalau snapshot baru jauh lebih kecil dari yang lama (misalnya diambil dari profil baru yang masih kosong), vault memberi tahu, dan mencentang **Pakai snapshot sebelum yang terbaru** saat memulihkan mengembalikan yang lama.
- Vault memberi catatan kalau snapshot browser (Edge, Chrome...) diambil sebelum setup awalnya selesai, karena saat dipulihkan halaman sambutannya akan muncul lagi.
- **Atur seberapa sering cek update:** Mati, tiap minggu, tiap 2 minggu atau tiap bulan. Bawaannya tiap minggu, tidak lagi tiap hari.

### Perbaikan & lebih aman
- Uninstall di PC dengan kunci lab meminta PIN lab, lalu kunci lab dihapus sepenuhnya.
- "Kumpulkan log" menunggu sampai log benar-benar tersimpan sebelum bilang selesai.
- Tes otomatis baru (total 190): PIN, pengaturan kunci lab, snapshot sebelumnya, peringatan snapshot mengecil dan catatan setup Edge.

## Windows v0.6.1 · App sama, build GitHub diperbaiki (11 Okt 2026)

Tidak ada perubahan di app-nya, sama dengan v0.6.0. File catatan lisensi (`THIRD-PARTY-NOTICES.md`) tidak ikut ke GitHub karena aturan "lewati file .md", jadi build Windows otomatis di sana gagal dan v0.6.0 tidak pernah punya file download. Aturannya sekarang mengizinkan file itu, dan versi ini membuat release dengan Setup x64 dan arm64.

## Windows v0.6.0 · Tampilan mirip app Mac, sign out dari Start membersihkan lagi (11 Okt 2026)

Versi percobaan Windows, tetap **tes di virtual machine saja**. Matikan (Turn Off) Amnesia dulu sebelum install di atas versi lama, lalu nyalakan (Turn On) lagi.

### Diperbaiki
- **Sign out atau shutdown dari menu Start kadang melewati pembersihan.** Windows cuma menunggu program yang punya jendela, sedangkan penjaga sign out Amnesia tersembunyi, jadi Windows menutup Amnesia setelah beberapa detik padahal masih kerja. Sekarang penjaganya jendela beneran (tidak terlihat dan tidak bisa diklik), jadi Windows menampilkan "Amnesia is cleaning up..." dan menunggu. Snapshot otomatis langsung mulai saat Windows minta sign out, maksimal 20 detik, lalu pembersihan tetap jalan setelahnya.
- **"Amnesia (Not Responding)"** waktu tekan Apply di Advanced (data Windows, clipboard dll), simpan pengaturan, atau buka vault. Semua pekerjaan itu sekarang jalan di belakang, jadi jendela tetap lancar.
- **Ikon Amnesia mati tertinggal di Start setelah uninstall.** Uninstaller sekarang me-restart menu Start supaya ikonnya hilang.
- **Claude dari Microsoft Store** sekarang juga ditemukan vault (datanya ada di folder yang beda dari app Claude biasa).
- Reset Doomsday sekarang juga menghapus pilihan app dan folder vault, jadi vault baru mulai bersih.

### Berubah
- **Tampilan baru, mirip app Mac.** Tidak ada tab lagi. Halaman utama berisi kartu status besar dan tombol (Vault, Review & sign out, Jeda, Keep, Backup, Riwayat), tiap halaman punya tombol Kembali, dan jendelanya lebih ramping (maks 560 px, tetap bisa diubah ukurannya).
- **Advanced sekarang bagian dari Pengaturan**, di grup sendiri di bawah pengaturan biasa, dengan **kotak cari** di atas (bisa bahasa Inggris dan Indonesia).
- **Folder Keep punya ikon sendiri** (folder ungu dengan logo Amnesia), shortcut di Desktop juga. Saat uninstall ikonnya dikembalikan ke folder biasa.
- "Collect log" sekarang menyimpan log ke folder Keep (dulu ke Public Documents).
- "Hapus app baru" memberi peringatan bahwa app dari Microsoft Store juga ikut terhapus.
- trace.log sekarang mencatat area mana yang sedang dipakai kalau ada yang tidak bisa dihapus.
- Teks lebih jelas di beberapa tempat (enkripsi, masalah restore vault, Keep).
- Tes otomatis baru (total 172).
- **Website dan README:** halaman Windows sekarang bertuliskan **Sedang dibuat · v0.6.0**, berisi apa yang benar-benar sudah jalan, dan cara download Setup dari Releases (tidak lewat Artifacts lagi). Daftar "Berikutnya" juga diperbarui.

## Windows v0.5.2 · Desktop tidak berkedip lagi (11 Okt 2026)

Versi percobaan Windows, tetap **tes di virtual machine saja**. Sudah termasuk perbaikan Edge dari v0.5.1 di bawah.

### Diperbaiki
- **Ikon Desktop berkedip, Explorer makan CPU, dan file baru/hasil copy tidak muncul sebelum di-refresh.** Cek saat login menghapus cache ikon dan thumbnail milik Explorer serta "shellbags" (tampilan tiap folder, termasuk Desktop) padahal Explorer sudah jalan, lalu memberi tahu Explorer bahwa *semua* ikon berubah. Explorer jadi membangun ulang terus dan kehilangan jejak Desktop. Sekarang:
  - Cache Explorer (cache ikon, thumbnail, cache Start menu dan shell) dan shellbags hanya dihapus **saat sign out**, waktu Explorer sudah mati. Cek saat login dan "Bersihkan sekarang" tidak menyentuhnya, dan jumlah yang dilewati dicatat di trace.log.
  - Explorer hanya diberi tahu "folder ini berubah" untuk Desktop, Documents dan folder user, tidak lagi "semua ikon berubah".
  - Sisanya (file terakhir, tab Notepad, clipboard, riwayat Paint...) tetap dihapus juga saat login.
  - Catatan jujur: selama bug sign out belum diperbaiki (sign out/shutdown dari Start kadang melewati pembersihan), thumbnail bisa tertinggal sampai ada sign out yang benar-benar membersihkan. Panic key dan sign out saat idle selalu membersihkan.
- 4 tes otomatis baru (total 168).

## Windows v0.5.1 · Edge bisa kembali dari vault (11 Okt 2026)

Versi percobaan Windows, tetap **tes di virtual machine saja**. Perbaikan dari hasil tes v0.5.0 di VM.

### Diperbaiki
- **Pulihkan Microsoft Edge dari vault selalu gagal "Access denied"**, walau Edge sudah ditutup. Ternyata Edge diam-diam jalan sendiri di latar belakang tiap login (`--no-startup-window`), jadi folder `User Data`-nya selalu dipegang. Sekarang:
  - Amnesia tanya Windows program apa yang memegang folder itu (cek "file sedang dipakai" yang sama dengan punya Windows), menutup program bawaan Edge (tidak pernah WebView2, yang dipakai Amnesia dan app lain), lalu coba lagi beberapa kali.
  - Kalau Windows tetap tidak melepas foldernya, snapshot dikembalikan **file per file**. Beberapa file yang masih dipakai dibiarkan seperti semula, dan pesannya bilang berapa.
  - Satu app yang gagal tidak lagi menghentikan app lain.
  - Pulihkan tidak pernah menyentuh snapshot di vault, jadi pulihkan yang gagal tidak bisa menghilangkan snapshot.
  - trace.log sekarang mencatat hasil tiap pulihkan dan program apa yang memegang foldernya (hanya nama program, tidak pernah nama file).
- 8 tes otomatis baru (total 164).

## Windows v0.5.0 · Belajar dari 8 program sejenis: lebih banyak jejak, pengaturan privasi, sisa app, sandbox (11 Okt 2026)

Pratinjau Windows, tetap **tes di virtual machine saja**. Versi ini berisi hal yang Amnesia pelajari dari BleachBit, Winapp2, Bulk Crap Uninstaller, privacy.sexy, Win11Debloat, Pearcleaner, Sandboxie dan Tails. Kode hanya disalin kalau lisensinya boleh (Win11Debloat, MIT); sisanya cuma ide yang ditulis ulang. Detailnya ada di `windows/THIRD-PARTY-NOTICES.md`. App Mac tidak berubah (tetap v5.19.1).

### Yang baru
- **Lebih banyak jejak dihapus** (dari BleachBit, privacy.sexy, Winapp2, Bulk Crap Uninstaller): laporan crash (isinya nama program yang kamu jalankan), riwayat pencarian Windows, file terakhir Office (Word, Excel, PowerPoint... versi apa pun), file terakhir Paint / WordPad / Media Player / Media Player Classic / Photoshop, tempat terakhir yang dibuka di Registry Editor (favoritnya tetap), "baru dibuka" di Start, game terakhir yang dijalankan, **Compatibility Assistant** (daftar tersembunyi Windows berisi semua program yang pernah jalan), riwayat dialog buka/simpan, cache layar Remote Desktop, **tab Notepad yang belum disimpan**, tangkapan terakhir Snipping Tool dan **cache DNS** (website apa saja yang dibuka). Setelah bersih-bersih Explorer diminta refresh, jadi tidak menampilkan yang lama.
- **Supaya Windows tidak mengingat** (Advanced, dari Win11Debloat dan privacy.sexy). Enam kelompok pengaturan privasi bawaan Windows, khusus akun kamu, tanpa admin: tanpa daftar app/file terakhir, tanpa riwayat atau sinkron clipboard, tanpa hasil web dan riwayat pencarian di Start, Windows berhenti belajar dari ketikan dan suara kamu, tanpa ID iklan atau saran app, Recall / Click to Do / Copilot mati. Amnesia mencatat nilai lamanya dulu, jadi **Batalkan semua** mengembalikan persis seperti sebelumnya. Ada tips dari Tails ke pengaturan Wi-Fi "Random hardware addresses".
- **Daftar pembersihan tambahan** (Advanced, mati secara default, dari Winapp2 + BleachBit). Mengunduh daftar komunitas Winapp2.ini (~4.000 app) dari GitHub saat kamu tekan tombolnya; Amnesia tidak menyertakannya, jadi daftarnya tetap pakai lisensinya sendiri. Yang dipakai hanya baris untuk folder yang sengaja disimpan (AppData\Microsoft, app Store) dan registry kamu, dan hanya untuk app yang ada di PC kamu. Password tersimpan, data login, folder Keep dan Keep List tidak pernah disentuh, apa pun isi daftarnya. Entri yang punya peringatan dilewati.
- **Hapus app baru** sekarang juga menghapus **pengaturan yang ditulis program baru di registry kamu** (`HKCU\Software\<nama>`, ide dari Pearcleaner dan Bulk Crap Uninstaller). Nama milik Windows tidak pernah disentuh. Dari v0.4: kunci yang ada hari ini dicatat dulu, jadi yang lama tidak dianggap "baru".
- **Cari sisa app** (Advanced, dari "orphans" Bulk Crap Uninstaller + Pearcleaner). Mendaftar folder di Program Files / ProgramData dan pengaturan di registry kamu yang sudah tidak dipakai program mana pun. Yang "kemungkinan aman" sudah dicentang; folder yang berisi program diberi tanda "hanya kalau kamu yakin". Tidak ada yang dihapus sampai kamu tekan Hapus; folder butuh admin (sekali pertanyaan Windows) dan dicek ulang tepat sebelum dihapus.
- **Tombol Uninstall** menghapus program MSI dengan benar (`/X`, bukan `/I` yang cuma "memperbaiki").
- **Windows sekali pakai** (Advanced, ide dari Sandboxie): membuka Windows Sandbox, Windows baru di dalam jendela yang hilang saat ditutup. Pilihan: folder Keep kamu di dalamnya (hanya baca), internet nyala atau mati. Butuh Windows Pro/Enterprise; di dalam VM sering tidak bisa, dan kartunya bilang begitu.
- **Hapus ruang kosong** (Advanced, ide dari BleachBit): menjalankan `cipher /w` bawaan Windows supaya file yang sudah dihapus tidak bisa dikembalikan dengan aplikasi recovery. Lambat, minta konfirmasi dulu.
- **USB key bisa mematikan PC** (ide dari Tails): pilih "Bersihkan lalu sign out" atau "Bersihkan lalu matikan PC" saat USB key dicabut.
- **Perlindungan Windows (admin):** Recall sekarang juga tidak bisa dinyalakan lagi dan tidak menyimpan snapshot; pengaturan baru **Copilot mati untuk semua user** dan **telemetry paling sedikit**; tombol sekali jalan **Bersihkan jejak Windows sekarang** (Prefetch, Temp Windows, laporan crash, memory dump).

### Lebih aman
- Sekarang 156 cek otomatis (30 baru): daftar tambahan di daftar contoh dan di Winapp2.ini asli (4.068 entri dihitung dalam sekitar 0,3 detik, semua baris lolos aturan keamanan), password tersimpan tidak pernah, Keep List menang, sisa app, keamanan registry, Batalkan.
- Dites juga di Wine: pengecekan saat sign in benar-benar menghapus laporan crash, file terakhir Office dan riwayat registry yang baru, hanya menghapus satu nilai yang seharusnya di kunci Registry Editor, menghapus pengaturan registry app yang benar-benar baru tapi menyimpan yang lama, dan pengaturan admin menulis nilai yang benar.

## Windows v0.4.0 · Paket besar: vault, backup, halaman Keep List, keluar cepat, dan installer beneran (11 Okt 2026)

Pratinjau Windows, tetap **tes di virtual machine saja**. Semua permintaanmu dalam satu paket, jadi cukup unduh dan pasang sekali di VM. App Mac tidak berubah (tetap v5.19.1).

### Yang baru
- **Setup.exe.** `Amnesia-Setup-0.4.0-arm64.exe` (Windows ARM, seperti VM kamu) dan `-x64.exe` (PC biasa). Dipasang khusus untuk kamu, tanpa admin, ke `%LOCALAPPDATA%\Programs\Amnesia` (folder yang tidak pernah disentuh pembersihan), masuk menu Start dan Apps & features (bisa di-uninstall seperti app lain). Setelah dipasang Amnesia tetap **Mati**. Zip portable juga masih ada.
- **Halaman Keep List.** Lihat isi Keep List, hapus baris, tambah folder lewat jendela pilih folder atau ketik path. "App di PC ini" menampilkan data app yang ditemukan: klik untuk menyimpannya.
- **Vault** (ide yang sama dengan Mac). Pilih app (Chrome, Edge, Brave, Vivaldi, Opera, Firefox, Discord, Telegram, Signal, Slack, Spotify, VS Code, Cursor, Claude, Claude Code, GitHub CLI, Git) atau folder apa saja. **Snapshot sekarang** menyimpannya terkunci (AES-256-GCM, kunci acak baru per snapshot, dikunci dengan kunci RSA vault), tanpa password. **Pulihkan** butuh password. Snapshot otomatis saat sign out (hanya app yang berubah, maksimal 60 detik), pengingat setelah login (klik untuk memulihkan), **kata panik** dan **Doomsday** (3 password salah = vault dihapus; bisa dimatikan). Ganti password dan kata panik di halaman yang sama. Catatan jujur: Windows mengunci login tersimpan ke user Windows, jadi snapshot hanya kembali di PC dan user yang sama.
- **Backup.** Folder Keep + Keep List + vault dalam satu file terkunci (`amnesia_backup_YYYY-MM-DD_HHMMSS.amb`) ke folder (flashdisk, drive lain, folder OneDrive / Google Drive) atau ke server kamu lewat SSH (`scp`, bawaan Windows; `.ssh` otomatis masuk Keep List). Backup otomatis harian atau mingguan, bar progres dan tombol Batal. Backup lama tidak pernah dihapus. **Pindah ke PC baru**: pilih backup, ketik password vault, semuanya kembali (Amnesia tetap mati).
- **Halaman Lanjutan:**
  - **Sign out saat tidak dipakai** (5 sampai 60 menit): hitung mundur 60 detik, gerakkan mouse untuk batal.
  - **Tombol panik** (Ctrl+Alt+Shift+X, Q atau F12) dan **flashdisk kunci** (cabut flashdisk yang dipilih): layar langsung terkunci, Amnesia membersihkan lalu sign out tanpa menunggu app lain. Ada juga tombol **Sign out darurat sekarang** dan menu di tray.
  - **Hapus app baru** (mati secara bawaan): program yang dipasang khusus untuk kamu setelah dinyalakan kehilangan entri Apps & features, shortcut menu Start dan entri autostart saat sign out (file-nya sudah ikut terhapus); app Microsoft Store yang kamu pasang dihapus saat login berikutnya. Program untuk semua user didaftar dengan tombol **Uninstall**. **Simpan** untuk menyimpannya.
  - Saklar **Dynamic Lock** (Windows terkunci saat HP yang dipasangkan menjauh).
  - **Perlindungan Windows (admin, sekali pop-up Windows):** kosongkan page file saat shut down, matikan hibernasi, hentikan screenshot Windows Recall, matikan riwayat aktivitas.
  - **Kartu Antivirus:** menunjukkan apakah Controlled folder access di Windows Security menyala dan cara mengizinkan Amnesia.
- **Cek dulu, lalu sign out** (tombol di Beranda dan menu tray): lihat apa yang hilang, simpan sesuatu dulu, lalu sign out.
- **Jejak Windows yang ikut dihapus bertambah:** program yang pernah dijalankan (UserAssist, MuiCache, data jump list), folder yang pernah dibuka ("shellbags"), hitungan pemakaian taskbar, riwayat Remote Desktop, riwayat drive jaringan, ukuran dialog open/save, riwayat notifikasi, riwayat pencarian menu Start, cache/cookie/riwayat Internet Explorer lama, file riwayat clipboard. Snapshot Recall dan riwayat aktivitas (di `AppData\Local`) memang sudah ikut terhapus.
- **Pengaturan:** bahasa (ikut Windows, English, Indonesia), **Update** (cek GitHub sehari sekali untuk rilis Windows; memasang Setup.exe setelah SHA-256 dicek; salinan portable dapat link), **Uninstall** (dimatikan dulu; "hapus semuanya" juga menghapus pengaturan dan vault setelah kamu ketik HAPUS), tur sambutan lagi.
- **Tur sambutan** saat pertama dibuka (4 langkah singkat).

### Lebih aman
- **Tidak ada PowerShell lagi saat sign out.** Pembersihan jalan di dalam Amnesia.exe (C#). Antivirus tidak suka PowerShell tersembunyi, dan sign out jadi lebih sederhana dan cepat: helper `standby.ps1` dari v0.2.2 sudah tidak ada. Hanya "Kumpulkan log" yang masih pakai PowerShell, dan hanya saat kamu menekannya.
- **Installer yang menutup Amnesia tidak pernah dianggap sign out.** Restart Manager Windows memakai pesan "akhiri sesi" yang sama; Amnesia sekarang mengecek tandanya dan hanya keluar (Mac pernah kena bug persis ini di v5.13).
- Kalau Windows Security atau antivirus memblok pembersihan ("access denied"), Beranda dan notifikasi memberi tahu serta menjelaskan cara mengizinkan Amnesia. Tidak pernah menyuruh "matikan antivirus".
- Jendela menyesuaikan layar kecil (maksimal 90% layar, minimal 520 × 460).
- Tes sekarang juga C#: 126 cek di folder user palsu (pembersihan, Keep List, vault, backup, file rusak, Doomsday), jalan di server Windows GitHub setiap push. Build GitHub Actions juga membuat Setup.exe, zip portable dan SHA256SUMS; tag `win-v*` membuat rilis (tidak pernah ditandai "latest", jadi updater Mac tidak bingung).

## v5.19.1 · Pengaturan Lanjutan, update dari app, jalan pintas ke Keep, dan Windows yang benar-benar membersihkan (10–11 Okt 2026)

### Yang baru
- **Jalan pintas ke folder Keep** (v5.19.1). Panel menu bar punya tombol **Buka Keep** di sebelah Buka Amnesia. Pengaturan punya dua saklar baru, keduanya nyala secara bawaan. **Alias Keep di Desktop**: alias Keep yang dipasang lagi oleh Amnesia setiap selesai membersihkan (dimatikan = hilang; alias buatanmu sendiri tetap ikut terhapus seperti file lain). **Keep di sidebar Finder**: Keep muncul di Favorit. Daftar sidebar ikut dibersihkan saat logout karena isinya menunjukkan folder yang kamu pakai, jadi Amnesia menambahkan Keep lagi setiap login. Kalau folder Keep diganti, keduanya ikut pindah.
- **Halaman Lanjutan.** Pengaturan → **Lanjutan** mengumpulkan pengaturan yang bisa menghapus lebih banyak atau berjalan sendiri, masing-masing dengan penjelasan jelas dan langkah konfirmasi. Tombol Hapus Amnesia tetap di halaman Pengaturan biasa.
- **Logout otomatis kalau Mac ditinggal** (Lanjutan). Pilih Mati, 5, 10, 15, 30, atau 60 menit. Kalau keyboard, mouse, atau trackpad tidak disentuh selama itu, muncul hitung mundur 60 detik di atas semua jendela. Sentuh apa saja (atau tekan **Saya Masih di Sini**) dan logout batal. Kalau tidak, kamu di-logout dan sesi dibersihkan, dengan snapshot otomatis seperti biasa. Hanya jalan saat Amnesia Aktif (tidak dijeda, tidak sedang snapshot atau backup). App dengan dokumen yang belum disimpan masih bisa menahan logout. Tercatat di Riwayat sebagai "Logout otomatis".
- **Hapus app yang dipasang belakangan** (Lanjutan, mati secara bawaan). Saat dinyalakan, Amnesia mencatat semua app yang sudah ada di Applications. App yang kamu pasang sesudahnya dipindahkan saat logout dan dihapus saat login berikutnya, kecuali kamu tekan **Simpan** di sampingnya di halaman Lanjutan (itu menambah baris `app:` di Keep List). Amnesia sendiri tidak pernah disentuh. App yang dipasang dengan password admin (milik user lain, seperti kebanyakan installer `.pkg`) dibiarkan dan hanya dihitung di Riwayat. Jujur saja: vault menyimpan *data* app, bukan app-nya, jadi app yang terhapus harus dipasang ulang.
- **Update dari app.** Pengaturan → **Update**. Amnesia bertanya ke GitHub sehari sekali versi mana yang terbaru (cuma itu, tidak ada data tentang kamu), mengunduhnya sendiri, lalu mencocokkan file-nya dengan `SHA256SUMS.txt` dari rilis itu. Pemasangan selalu menunggu kamu: tekan **Pasang & Buka Lagi**. Kalau Amnesia sedang Aktif, Amnesia dimatikan sebentar (tidak ada yang dibersihkan), versi baru menggantikan yang lama di Applications, terbuka sendiri, lalu Amnesia diaktifkan lagi. Kalau penyalinan gagal, versi lama dikembalikan. Kedua saklar (cek harian, unduh otomatis) bisa dimatikan. Pakai Homebrew? App memberi tahu untuk memakai `brew upgrade --cask amnesia` saja.
- **Menu bar memberi tahu versi baru.** Kalau ada update, muncul satu baris di panel menu bar: buka Pengaturan, atau **Pasang** kalau sudah terunduh.
- **Cek FileVault.** Pengaturan menunjukkan apakah enkripsi disk sudah nyala. Kalau mati, dijelaskan kenapa itu penting (Amnesia hanya membersihkan saat logout dan folder Keep tidak dienkripsi), dan ada tombol ke pengaturan FileVault.
- **Jalan di background** (Pengaturan, nyala secara bawaan). Nyala: saat login, Amnesia hanya berupa ikon menu bar. Mati: jendela Amnesia ikut terbuka setiap login.
- **Riwayat menunjukkan berapa banyak yang dibersihkan,** misalnya "1284 item, 2,3 GB". Catatan lama tanpa ukuran tetap tampil seperti dulu.

### Tampilan
- **Panel menu bar sekarang mirip jendela utama:** latar yang sama, kartu status yang sama lengkap dengan tombol Aktifkan / Matikan, kotak tombol seperti di halaman utama, serta tombol Batal dan Tutup App yang lebih rapi. Grid 4 tombol yang lama sudah tidak ada.

### Perbaikan & lebih aman
- `build.sh` sekarang menolak memasang saat Amnesia masih Aktif, dengan pesan apa yang harus dilakukan (Matikan, jalankan lagi, Aktifkan). Tidak ada yang diubah dalam kasus itu.
- Catatan privasi di app, README, dan FAQ website sekarang menyebut cek update harian, supaya janji "tidak ada yang keluar dari Mac kamu" tetap jujur.

### Windows (preview v0.3.0, tes di virtual machine saja)
- **v0.3.0 (permintaanmu dari tes VM):** tab **Pengaturan** di sebelah Beranda. Isinya folder Keep kamu dengan tombol **Buka Keep**, dua saklar yang nyala secara bawaan: **Shortcut Keep di Desktop** (`Keep.lnk` yang dibiarkan Amnesia saat sign out; shortcut buatanmu sendiri tetap ikut terhapus) dan **Keep di sidebar Explorer** (disematkan ke Quick access; Windows melupakan sematan setiap sign out, jadi Amnesia menyematkannya lagi setelah setiap login), plus tombol **Kumpulkan log**. Menu ikon tray (klik kanan) sekarang punya **Buka folder Keep** dan **Nyalakan / Matikan Amnesia** (mematikan ditanya dulu; Nyalakan yang pertama kali tetap lewat jendela). Scroll diperbaiki: halaman tidak selalu menerima scroll mouse setelah dibuka dari tray, sekarang halaman mendapat fokus saat selesai dimuat dan setiap jendela muncul ke depan.
- **v0.2.3 (setelah tes restart v0.2.2):** pembersihan saat sign out sekarang jalan (2 detik di tes). Bug baru yang ketahuan: setelah cek saat sign in, membuka Amnesia memunculkan "Dll was not found" dan jendela hitam. Amnesia.exe membongkar bagian jendelanya (`WebView2Loader.dll`) ke `AppData\Local\Temp\.net\Amnesia`, dan cek saat sign in menghapus Temp saat Amnesia sedang jalan. Sekarang folder itu saja yang dijaga; isi Temp lainnya tetap dihapus.
- **v0.2.2 (setelah tes restart):** pembersihan saat sign out ternyata tidak jalan sama sekali: begitu Windows mulai sign out, Windows menolak membuka program baru, jadi PowerShell gagal dengan error 0xc0000142 (itu popup saat restart). Sekarang ada helper kecil (`scripts\standby.ps1`) yang mulai saat sign in dan menunggu diam-diam; saat sign out Amnesia tinggal memberi aba-aba. Windows juga baru menutup helper itu setelah Amnesia selesai. Pertanyaan "Unknown Publisher, Run / Cancel" di setiap sign in juga hilang: salinan yang terpasang tidak lagi membawa tanda "diunduh dari internet" dari Windows (instalasi lama otomatis dibetulkan saat Amnesia dibuka berikutnya).
- **v0.2.1 (setelah tes VM pertama):** history, cookie, dan login Microsoft Edge sekarang ikut dibersihkan (Edge menyimpannya di dalam `AppData\Local\Microsoft`, yang dijaga untuk login Windows, jadi sebelumnya terlewat). Kalau Edge sedang jalan, Edge ditutup dulu. Ada di Keep List (`AppData\Local\Microsoft\Edge`)? Edge tetap aman. Cek saat sign in sekarang langsung jalan setelah login, bukan beberapa menit kemudian (jeda startup Windows dimatikan untuk user ini selama Amnesia aktif, dan dikembalikan saat Matikan). App sekarang mencatat langkah sign out / sign in ke `trace.log`, jadi log bisa menunjukkan kenapa pembersihan saat sign out tidak jalan.
- **Sekarang benar-benar membersihkan,** setelah kamu menekan **Aktifkan** dan mencentang bahwa kamu paham. Amnesia menyalin dirinya ke `%LOCALAPPDATA%\Programs\Amnesia` dan ikut jalan saat Windows menyala.
- **Saat sign out, restart, dan shutdown** Windows menunggu selagi folder user kamu dibersihkan (semua di luar folder Keep dan Keep List dipindah ke folder sampah tersembunyi). **Saat sign in berikutnya** sampah itu dihapus dan Amnesia mengecek sekali lagi. Jeda 1 sesi melewati satu sign out dan sign in.
- **Jejak Windows ikut dihapus:** file terakhir dibuka, riwayat PowerShell, cache thumbnail dan ikon, kotak Run, address bar Explorer, riwayat pencarian, dokumen terakhir, riwayat dialog buka/simpan, Recycle Bin, dan riwayat clipboard.
- **Selalu aman:** OneDrive, folder bawaan Links, Searches dan Favorites, folder yang dibuat Windows sendiri (Screenshots, Camera Roll, Captures), dan semua yang dibutuhkan Windows untuk login.
- **Halaman Riwayat** (hanya waktu dan jumlah) dan **cek BitLocker**.
- Perbaikan dari tes VM pertama: title bar ikut gelap di mode gelap, membuka `Amnesia.exe` untuk kedua kalinya memunculkan jendela yang sudah terbuka (bukan diam saja), dan link website menuju alamat baru.
- **Kumpulkan log:** klik dua kali `scripts\Collect log.cmd` untuk menyimpan log (langkah Amnesia, pengaturan, error Windows 3 hari terakhir, tanpa nama file) ke `C:\Users\Public\Documents\amnesia-log.txt`. Tidak ada yang dikirim; kamu yang memilih apa yang dibagikan.
- Pengaman: tidak ada yang dihapus kecuali Amnesia sudah diaktifkan, app yang terpasang masih ada, dan tidak sedang dijeda. Tes baru memeriksa semua itu di folder user palsu.

## v5.18.2 · Sekarang tampilannya kayak website (7–8 Okt 2026)

Isinya v5.16 sampai v5.18.2, ditambah website baru, video-videonya, dan intip awal versi Windows.

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
- Tombol GitHub dan Ketentuan di app sekarang menuju alamat repo yang baru.

### Website & README
- **Website baru** di [navi-crwn.github.io/amnesia](https://navi-crwn.github.io/amnesia/): animasi saat scroll, logo 3D, mode terang dan gelap, app dibongkar tombol per tombol, tutorial yang bisa diikuti, kartu instalasi, dan FAQ yang lengkap. Tetap enak dibaca walau animasi dimatikan. Tanpa pelacakan.
- **Dibuat secara terbuka:** bagian berisi info repo langsung dari GitHub dan grafik 3D setiap commit.
- **"Yang paham, paham" 😉** buat kamu yang malas ditanya-tanya: Mac dipinjam, Mac hilang, "coba buka sebentar", dan keluarga kepo. Dengan catatan jujur: perlindungannya berlaku setelah logout, dan kata panik tidak bisa dibatalkan.
- **Video paper craft.** Film stop motion 54 detik tepat di bawah bagian atas halaman, plus tiga klip vertikal 30 detik di kartu "Yang paham, paham". Main tanpa suara saat terlihat; ketuk untuk menonton dengan suara.
- **README** sekarang punya pratinjau bergerak 15 detik yang mengarah ke video lengkapnya.
- **README sekarang senada dengan website.** Gambarnya diambil langsung dari website (terang atau gelap, ikut tema GitHub kamu), menggantikan screenshot lama. Gambar WebP yang lebih ringan, pratinjau link baru saat repo dibagikan, dan deskripsi repo yang lebih segar.
- **Halaman Windows** di website ([/win](https://navi-crwn.github.io/amnesia/win/)): apa yang sudah jalan, apa berikutnya, dan cara mencoba preview-nya. Ada tombol Mac / Windows di menu atas kedua halaman.
- **Cek file download kamu.** Setiap rilis sekarang punya file `SHA256SUMS.txt` dan, begitu API key VirusTotal (gratis) dipasang, link hasil scan dari 70+ antivirus. Build Windows juga dapat attestation dari GitHub: bukti bahwa file-nya dibuat dari kode repo ini.
- **Install lewat Homebrew pakai format cask yang baru,** jadi dua peringatan "deprecated" saat `brew install` harusnya hilang.
- **Perintah Homebrew lebih pendek:** `brew install navi-crwn/tap/amnesia` (tanpa `--cask`).
- **Alamat baru.** Repo-nya sekarang [github.com/navi-crwn/amnesia](https://github.com/navi-crwn/amnesia) dan websitenya [navi-crwn.github.io/amnesia](https://navi-crwn.github.io/amnesia/), karena Amnesia juga sedang menuju Windows. Link repo lama tetap jalan, tapi link website lama tidak, jadi bookmark-nya perlu diganti.

### Di balik layar
- Tes baru untuk Pulihkan File, Cek file backup, dan snapshot ringan per browser.
- **Versi Windows: langkah pertama.** Versi awal banget ada di `windows/` (app di tray + halaman yang mirip website). Cuma menunjukkan apa yang *akan* dihapus, belum menghapus apa pun. GitHub otomatis build dan mengetesnya di Windows setiap ada perubahan.

Perubahan yang lebih lama: [changelog lengkap](https://github.com/navi-crwn/amnesia/blob/main/CHANGELOG.id.md).

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
