# Changelog

[English](CHANGELOG.md) · **Bahasa Indonesia**

Semua perubahan Amnesia dicatat di sini. Versi terbaru ada di paling atas.
Nomor versi juga terlihat di app (di samping judul dan di bawah menu bar).

## v5.18.1 — 2026-10-07

### Diperbaiki
- **Tombol utama popup tidak terlihat** (misalnya Matikan atau Aktifkan Amnesia, hanya Batal yang muncul). Di v5.18 tombol itu diberi warna indigo website, dan di macOS 26 justru membuatnya hilang. Sekarang tombol utamanya muncul lagi dengan warna aksen Mac kamu, seperti sebelum v5.18. Kotak berwarna di dalam popup tetap memakai warna website.

## v5.18 — 2026-10-07

### Diubah
- **Tampilan app sekarang sama dengan website.** Warna dan permukaannya sama, di mode gelap maupun terang (otomatis mengikuti pengaturan Appearance di Mac kamu).
  - **Latar:** hampir hitam (atau putih lembut di mode terang) dengan cahaya indigo tipis di kanan atas dan cyan di kiri bawah, seperti bagian atas website.
  - **Kartu dan panel** sekarang datar dengan garis tipis, bukan kaca buram. Tombol bulat (Kembali, Pengaturan) dan kolom isian juga memakai garis tipis yang sama.
  - **Warna per fitur kembali, tapi tetap kalem:** Profile Vault indigo, Simpan & Logout cyan, Jeda oranye, Keep List hijau, Backup pink, Riwayat abu-abu, Yang Akan Dihapus ungu. Ikon diletakkan di atas warna tipis, bukan kotak warna penuh.
  - **Kotak di beranda** memunculkan garis berwarna dan cahaya lembut saat disorot kursor.
  - **Kartu status** (beranda dan panel menu bar): hijau tipis saat Amnesia Aktif, oranye saat Dijeda, netral saat Mati. Teksnya tidak lagi putih di atas blok warna penuh. Tombol Aktifkan berwarna indigo penuh; tombol Matikan berwarna tipis.
  - **Tombol:** tombol utama (indigo) dan tombol hapus (merah) berwarna penuh dengan teks putih, tombol fitur berwarna tipis dengan garis warna, tombol abu-abu netral.
  - **Popup:** kotak berwarnanya memakai warna website (Yang akan terjadi cyan, Yang akan dihapus merah, Tetap tersimpan hijau, Yang perlu kamu lakukan indigo, Perhatikan oranye, Perlu diketahui abu-abu), dan tombol utama popup berwarna indigo (merah kalau menghapus sesuatu), bukan warna aksen Mac kamu.
  - **Ikon kecil dan catatan** di semua halaman (Riwayat, Profile Vault, Keep List, Backup, Pengaturan) memakai palet yang sama, bukan warna bawaan sistem.
  - Label versi di samping judul memakai gradasi merek (cyan, indigo, pink). Judul memakai huruf sistem biasa, bukan huruf bulat, seperti website.
- Selain tampilan tidak ada yang berubah: halaman, tombol dan cara kerjanya tetap sama.

## Website — 2026-10-07

### Diubah
- **Landing page baru** (navi-crwn.github.io/amnesia-mac). Desain gelap dengan animasi saat di-scroll: kata "everything" di judul pecah jadi partikel, meja Mac penuh file dibersihkan saat **Log Out** ditekan sementara Keep, Vault, Keep List dan Apps tetap ada dan menyala hijau, Profile Vault terkunci sambil inisial app terbang masuk, timeline harian tergambar sendiri, dan `.7z` backup tersambung ke semua tujuan. Semua isi lama tetap ada dalam bahasa Inggris dan Indonesia: fitur, yang dihapus vs. yang tetap, tur fitur dengan screenshot, cara pasang, tutorial 10 langkah, glosarium, dan 27 jawaban FAQ. Peringatan penghapusan dan link Ketentuan ada di bagian atas dan di bagian Pasang.
- Tetap bisa dipakai tanpa animasi: kalau "Reduce motion" nyala, JavaScript mati, atau library animasi gagal dimuat, halaman menampilkan semuanya dalam keadaan akhir. Tanpa pelacakan atau analytics.
- **Update (v2): app dijelaskan per bagian.** Tur screenshot diganti jendela utama Amnesia yang digambar ulang dengan gaya website. Saat di-scroll, jendelanya terpecah: satu tombol diangkat sementara yang lain menjauh, penjelasannya muncul di sampingnya, dan titik-titik di kiri menunjukkan posisi kamu (11 bagian: Beranda, menu bar, Profile Vault, Simpan & Logout, Jeda, Keep List, Yang Akan Dihapus, Backup, Riwayat, Pengaturan, Pindah Mac). Di akhir semuanya menyatu lagi. Di HP, tiap penjelasan menampilkan bagiannya sendiri.
- Adegan meja tidak terasa macet lagi: file muncul sambil di-scroll, Logout langsung jalan, bagian yang ditahan lebih pendek, dan ada garis progres. Teksnya lebih panjang dan menjelaskan apa saja yang dikumpulkan Mac setiap hari.
- Glosarium dipindah tepat setelah tur app, dan tiap istilah (Selective Amnesia, Global Amnesia, Memory Recall) punya grid kecil beranimasi.
- File baru: `docs/assets/css/site.css`, `docs/assets/js/site.js` dan `docs/assets/js/scenes/` (hero, desk, puzzle, story). Animasi memakai GSAP dan Lenis dari jsDelivr (versi dikunci). App-nya sendiri tidak berubah.
- **Update (v3): rapi dari atas sampai bawah.**
  - **Light mode.** Seluruh website punya versi terang, kebalikan dari versi gelap. Otomatis mengikuti pengaturan Mac atau HP, dan tombol matahari/bulan di navbar untuk menggantinya (diingat).
  - **Logo 3D.** Shield Amnesia di bagian atas sekarang 3D sungguhan (three.js): kotak gradasi, shield dengan lubang kunci, dan tiga titik yang melayang pergi. Logonya menghadap ke arah kursor, dikelilingi pecahan kaca yang melayang. Bagian penutup punya satu lagi. Di HP versinya lebih ringan, dengan Reduce motion hanya 1 gambar diam, dan tanpa WebGL logo biasa tetap tampil.
  - **Tombol panah, titik, dan ← →** di adegan meja, tur app, dan tutorial, jadi tidak harus scroll untuk pindah slide.
  - **Meja (01/02):** teksnya sudah ada saat ikon muncul dan baru hilang setelah ikon dihapus. **Yang tetap ada (03):** coretan merah menunggu sampai daftarnya tampil di layar, baris demi baris.
  - **Tur app (08):** 10 bagian, bukan 11 (Pindah Mac sekarang di Pengaturan), teks lebih pendek supaya muat di laptop 1280×720, jendelanya sudah utuh saat mulai ditahan, kursor bergerak ke tiap bagian lalu mengkliknya, dan ikon roda gigi sekarang jelas bentuknya dengan label "Pengaturan".
  - **Popup** digambar ulang dengan gaya website (bukan screenshot putih lagi) dalam susunan bento: Aktifkan, Simpan & Logout, Restore selesai, Percobaan terakhir, dan Hapus Amnesia, plus keterangan arti warna.
  - **Bagian Glosarium dihapus.** Selective Amnesia, Global Amnesia, dan Memory Recall sekarang muncul langsung di penjelasan yang cocok (logout, vault, backup, pengaturan, tutorial).
  - **Pasang:** kartu Homebrew dengan perintah yang mengetik sendiri dan output brew, kartu .dmg yang menyeret app ke Applications, kartu GitHub dengan jumlah bintang, fork, dan versi terbaru, kebutuhan sistem, dan urutan update. Badge bintang, rilis, lisensi, dan macOS. Angkanya diambil langsung dari API publik GitHub oleh browser kamu, disimpan 1 jam, tanpa cookie atau pelacakan.
  - **Tutorial** seperti rekaman layar: 10 langkahnya diputar di jendela Amnesia yang digambar (kursor bergerak, klik, mengetik, popup terbuka), dengan penjelasan detail dan tips di sampingnya. Di desktop, scroll memindah langkah; titik bernomor untuk lompat ke langkah mana saja.
  - **Susunan bento dengan cahaya yang mengikuti kursor** untuk fitur, popup, pasang, dan FAQ. FAQ dikelompokkan dalam kartu (Keamanan, Profile Vault, Backup, Sehari-hari, Menghapus Amnesia).
  - **Running text** di antara fitur dan tur app.
  - **Footer baru:** logo dan tagline, kartu repo (MIT, versi, bintang), kolom Produk / Sumber / Legal, dan catatan merek dagang.
  - File baru: `docs/assets/js/scenes/tutorial.js` dan `docs/assets/js/scenes/shield3d.js` (three.js 0.186.1 dari jsDelivr). Website tidak memakai screenshot lagi.
- **Update (v4): open source jadi sorotan.**
  - **Hero:** latar belakang sendiri (grid titik dengan cahaya lembut warna brand), **menu bar pil yang melayang**, tombol **Kasih star repo ini** di sebelah Download, dan kartu repo kecil (nama, Public, MIT, versi, bahasa utama).
  - **Jumlah bintang tidak ditampilkan lagi di mana pun** (badge hero, badge Install, kartu GitHub, footer). Yang tersisa hanya tombol "Kasih star repo ini".
  - **Bagian baru 01 "Dibuat secara terbuka":** tombol Star / Fork / Buka issue dan kartu repo besar berisi bar bahasa serta Lisensi, Rilis terbaru, Commit, Rilis, Kontributor, dan Update terakhir, dibaca langsung dari GitHub API (tanpa cookie, tanpa referrer, disimpan 1 jam). Bagian lain sekarang bernomor 02 sampai 12.
  - **Grafik 3D "Semua commit":** satu kolom per hari di atas grid ubin, tingginya sesuai jumlah commit hari itu. Arahkan kursor atau ketuk kolom untuk melihat tanggalnya. Kalau GitHub tidak bisa dihubungi, yang muncul link ke daftar commit.
  - **Brankas 3D di Profile Vault:** dial berputar memasukkan kombinasi, gagang berputar, dan cincinnya menyala hijau, di tengah lingkaran app.
  - **FAQ:** "Masih bingung?" sekarang satu baris penuh di bawah kedua kolom.
  - **Teks bahasa Indonesia ditulis ulang** di seluruh website (sekitar 140 kalimat) supaya terasa natural, bukan seperti terjemahan. Nama tombol dari app tetap sama.
  - **Perbaikan:** di tur app, titik-titik di bawah teks tidak lagi tertinggal di langkah terakhir setelah loncat kembali ke atas.
  - File baru: `docs/assets/js/scenes/objects3d.js`.
- **Update (v5): "Yang paham, paham" 😉.**
  - **Blok baru di "Data kamu tetap milikmu"** untuk kamu yang malas ditanya-tanya: Mac mau dipinjam?, Hilang atau dicuri?, "Coba buka sebentar." (kata panik) dan Keluarga kepo?, masing-masing kartu singkat dengan kedipan mata.
  - Baris terminal kecil `$ amnesia --forget-everything # pun intended` dan catatan jujur: perlindungan baru berlaku setelah kamu logout, kunci layar kamu, dan kata panik tidak bisa dibatalkan. FileVault tetap disarankan karena ~/Keep tidak dienkripsi.
  - **Bagian penutup:** baris baru di bawah judul, "Download, lalu lupakan semuanya. Pun intended."
  - Video (item 76) draft 3: kalimat voiceover penutup sekarang diakhiri "Lalu lupakan semuanya. Pun intended." dan adegan panik berbunyi "Dipaksa membukanya? Ketik kata panik saja."

## v5.17.1 — 2026-10-07

### Diperbaiki
- **Tombol dan kotak tidak terpotong lagi di pinggir.** Di semua halaman (beranda, Profile Vault, Backup, Pengaturan, Riwayat, Pindah Mac, Keep List dan daftar Yang Akan Dihapus), apa pun yang menempel ke pinggir kiri atau kanan terpotong garis, bayangan atau cincin fokusnya, paling kelihatan saat kotak di kolom kanan di-hover. Sekarang area scroll memberi sedikit ruang di dalamnya, dan tata letaknya tetap sama.
- **Jendela Pulihkan File** memakai warna indigo Amnesia untuk tombol utamanya, bukan warna aksen Mac kamu, supaya serasi dengan bagian app lainnya.

## v5.17 — 2026-10-07

### Baru
- **Pulihkan File** (halaman Backup → **Pulihkan File…**). Pilih file backup `.7z`, ketik password-nya, lalu centang file atau folder yang mau dikembalikan (folder bisa dibuka untuk memilih isinya satu per satu). **Pulihkan ke Lokasi Asal** mengembalikan semuanya persis ke tempat asalnya. Tidak ada yang pernah ditimpa: file atau folder yang sudah ada di sana dipindah dulu ke `~/.amnesia/before-restore/<tanggal-jam>/`, dan popup hasilnya punya tombol **Lihat File Lama**. Kalau tempat asalnya ada di drive eksternal yang tidak tercolok, Amnesia memberi tahu dan meminta kamu memilih folder lain. **Ke Folder Lain…** memulihkan semuanya ke folder pilihanmu. Halaman Riwayat mencatat "File dipulihkan dari backup".
- **Backup ingat asal file-nya.** Setiap backup baru membawa `backup-index.json` kecil berisi lokasi asal setiap folder. Backup lama tetap bisa dipakai: folder-nya dianggap berasal dari folder home.
- **Glosarium** di website dan README: *Selective Amnesia* (pembersihan normal saat logout), *Global Amnesia* (semua hilang tanpa jalan kembali) dan *Memory Recall* (semua cara mengembalikan data). Istilah ini hanya dipakai di teks; tombol di app tetap memakai nama biasanya. Syarat & Ketentuan juga menyebutnya.
- **"Baca selengkapnya…"** di bawah teks panjang (keterangan di Pengaturan, kartu snapshot ringan, folder di vault, panduan Pindah Mac, catatan SSH): hanya dua baris yang tampil sampai kamu menekannya.
- **FAQ baru:** mengambil beberapa file dari backup, kenapa backup tidak terbuka saat di-klik dua kali (pakai Keka atau `7zz` dan ketik password saat diminta), arti "tidak berisi Profile Vault", dan kenapa backup terjadwal minta password Mac.

### Diubah
- **Desain lebih tenang.** Satu warna aksen indigo dan abu-abu netral, bukan warna berbeda untuk setiap ikon; hijau, oranye dan merah hanya untuk status (nyala, jeda, mati, bahaya). Ikon duduk di latar berwarna lembut, latar belakang hanya satu cahaya samar, tema terang dan gelap tetap ada.
- **Semua sedikit lebih kecil dan rapi:** kartu status di beranda, tile, judul halaman dan tombol Kembali. Tombol besar **Cara kerja backup** jadi tautan kecil **Panduan** di samping judul Backup.
- **Tujuan backup bisa dilipat.** Kalau tujuan sudah diatur, kartu "Tujuan" hanya menampilkan satu baris ringkasan (misalnya "SSH: user@host"); tekan untuk membuka dan mengubahnya.
- **Teks status pakai bahasa sehari-hari, sesuai bahasamu.** "logout: 1284 items wiped" jadi "Terakhir dibersihkan: hari ini 13:03, saat logout, 1284 item"; status backup berbunyi "Backup terakhir: hari ini 10:17, 4,9 GB ke …" atau bilang jelas kalau gagal dan kenapa.
- **"0 KB"** menggantikan "Zero KB" untuk ukuran kosong.
- **Keterangan tile Jeda** lebih pendek supaya tidak terpotong.
- **Tombol nonaktif tetap terbaca:** latar abu-abu dengan teks gelap (atau terang), bukan teks putih pudar.
- **Cek file backup bilang apa masalahnya.** Sekarang menyebut nama file-nya dan membedakan password salah, backup tanpa Profile Vault (dibuat saat *Sertakan Profile Vault* mati, atau sebelum v5.13) dan file rusak, lengkap dengan saran untuk masing-masing.

### Diperbaiki
- **Backup terjadwal minta password Mac** (popup Keychain). Password backup yang tersimpan dibuat oleh versi app yang lama. Setelah kamu mengizinkannya sekali, Amnesia menyimpannya ulang atas nama versi sekarang, jadi popup-nya tidak muncul lagi.
- **Screenshot:** tidak ada lagi screenshot halaman penuh yang terlalu tinggi (dihapus dari website); jendela diaktifkan dulu sebelum dipotret supaya sakelar tampil berwarna, bukan abu-abu. Tips Screen Recording sekarang bilang izinkan **Terminal**, karena skrip screenshot dijalankan dari Terminal.

### Tes
- `test_backup.sh`: backup berisi `backup-index.json`; `--list` menampilkan Keep, file di dalamnya dan folder dari luar home, serta menyembunyikan `.amnesia`; password salah memberi `[wrongpw]`; backup tanpa vault memberi `[novault]`; file kembali ke tempat asalnya dan salinan lama dipindah ke `before-restore`; `--to` berfungsi; `.amnesia` dan `..` ditolak; Riwayat tercatat dan tidak ada folder sementara yang tertinggal.

## v5.16 — 2026-10-07

### Baru
- **Snapshot ringan per browser, langsung di Profile Vault.** Tombol "Snapshot Chrome ringan" dipindah dari Pengaturan. Sekarang Profile Vault punya kartu **Snapshot ringan** dengan 1 tombol untuk tiap browser. Nyala (bawaan): cache browser dan file program extension dari Web Store tidak ikut disimpan, jadi Chrome dari sekitar 1 GB jadi 150 MB. Login, bookmark, pengaturan extension, dan extension yang bukan dari Web Store selalu disimpan. Mati: browser disimpan lengkap. Simpan & Logout dan snapshot otomatis saat logout mengikuti tombol yang sama. Kalau di v5.15 mode ringan kamu matikan, Chrome otomatis jadi "lengkap", jadi tidak ada yang berubah.
- **Browser Chromium lain bisa masuk vault:** Brave, Microsoft Edge, Vivaldi, Arc dan Opera. Hanya muncul kalau terpasang, dan awalnya tidak dipilih: klik untuk menambahkan.
- **Halaman Riwayat.** Kotak baru di halaman utama yang menampilkan apa saja yang dilakukan Amnesia, dikelompokkan per hari (Hari ini, Kemarin, lalu tanggal): pembersihan saat logout dan login (dengan jumlah item), sesi yang dijeda, snapshot (manual atau otomatis), restore, backup (otomatis atau manual, dengan ukuran, dan yang gagal) serta tombol darurat. Yang dicatat hanya waktu, jumlah dan nama app, tidak pernah nama file kamu. Catatannya ada di `~/.amnesia/history.log` dan merapikan dirinya sendiri supaya tidak membesar.
- **Cek file backup** (halaman Backup). Pilih file backup `.7z`: Amnesia membuka Profile Vault-nya saja di folder sementara, menampilkan ukuran, tanggal dan app di dalamnya, lalu menghapus salinan sementara itu. Vault kamu yang sekarang tidak pernah disentuh. Cara aman untuk mengetes apakah backup benar-benar bisa mengembalikan login kamu.
- **Jalankan backup terjadwal sekarang** (halaman Backup, muncul kalau jadwal sudah diatur). Berjalan persis seperti jadwal, pakai password tersimpan, jadi bisa dites tanpa menunggu sehari.
- **Footer di halaman utama:** versi, Lisensi MIT (link), © 2026 navi-crwn dan link ke GitHub.

### Diubah
- **Tombol Aktifkan / Matikan dipindah** dari kotak kanan bawah ke tombol besar di kartu status paling atas halaman utama. Kotak yang kosong sekarang jadi Riwayat.
- **Popup lebih jelas.** Semua peringatan dan konfirmasi sekarang dibagi jadi kotak berwarna, bukan teks biasa: *Yang akan terjadi* (biru), *Yang akan dihapus* (merah), *Berikut ini tetap tersimpan (tidak dihapus)* (hijau), *Yang perlu kamu lakukan* (ungu), *Perhatikan* (oranye) dan *Perlu diketahui* (abu-abu). Dipakai di Aktifkan/Matikan, Simpan & Logout, hasil Restore, hapus snapshot atau vault, kesempatan terakhir password vault, Pindah Mac, Keep List dan Hapus Amnesia.
- **Semua kata-kata dicek ulang.** Nama tombol di teks sekarang sama dengan tombol aslinya (Restore Profil, Snapshot Sekarang, Yang Akan Dihapus, Pindah Mac). Singkatan seperti "=" dan "1x" dihapus, "setting" diganti "pengaturan" di semua tempat, "Tidak bisa dibatalkan" jadi "Tidak bisa dikembalikan lagi", dan teks Inggris serta Indonesia sekarang artinya sama.
- **Penjelasan snapshot otomatis lebih detail** di Pengaturan: kapan berjalan, hanya menyimpan app yang datanya berubah, batas 150 detik, app yang dimatikan dilewati, dan snapshot lama tetap aman kalau waktunya habis.
- **Hapus Amnesia sekarang bertahap.** Popup pertama menjelaskan apa yang akan terjadi dan apa saja yang masih tersimpan (vault, snapshot di dalamnya, Keep List, pengaturan). Ada kotak centang *Hapus juga vault, snapshot, Keep List, dan pengaturan* yang bawaannya tidak dicentang. Kalau dicentang, ada konfirmasi kedua; file-file itu dipindah ke Trash (tidak langsung hilang) dan password backup yang tersimpan dihapus dari Keychain. Kalau tidak dicentang, semuanya tetap di `~/.amnesia` seperti sebelumnya.
- **README dan website ditulis ulang:** setiap fitur dijelaskan dengan screenshot, tutorial langkah demi langkah dengan screenshot, galeri popup baru, dan FAQ yang jauh lebih lengkap per topik.
- **Screenshot HD.** `app/screenshots.sh` sekarang membuat salinan khusus screenshot, **Amnesia Shots** (`app/shots/`, tidak di-upload). Salinan ini tidak bisa menghapus, memindah atau menyimpan apa pun: semua perintah diblokir kecuali yang hanya membaca (preview dry-run, status dan ukuran vault), dan langsung keluar kalau dibuka tanpa `--shots`. Jendela asli difoto lewat ScreenCaptureKit macOS, jadi hasilnya persis seperti app (saat pertama kali, macOS minta izin **Perekaman Layar** untuk *Amnesia Shots*; tanpa izin itu, dipakai cara gambar 2x yang lama). Screenshot baru: Riwayat, Vault/Backup/Pengaturan versi panjang, dan 5 popup.

### Tes
- `test_vault.py`: Chrome ringan secara bawaan, `VAULT_FULL` dan `VAULT_LIGHT=0` lama menyimpan lengkap, Brave dilewati sampai dipilih, `VAULT_PICK` menambahkannya, baris riwayat tidak pernah berisi nama file.
- `test_backup.sh`: `--check-vault` menemukan vault di dalam backup dan tidak menyentuh vault asli.

## v5.15 — 2026-10-07

### Diperbaiki
- **Saat login hanya ikon menu bar, tanpa jendela.** Kalau kamu mencentang "Reopen windows when logging back in" waktu logout, macOS membuka ulang Amnesia saat login lengkap dengan jendela utamanya. Sekarang Amnesia minta macOS tidak membukanya ulang dengan cara itu, dan jendelanya tidak dikembalikan otomatis. Saat login Amnesia dibuka oleh "Buka saat login", hanya di menu bar.

### Ditambahkan
- **Tombol uninstall** di Pengaturan: *Hapus Amnesia*. Amnesia dimatikan untuk seterusnya (agent login dan item "Buka saat login" dihapus lebih dulu, jadi tidak ada yang dibersihkan), `~/.amnesia-trash` dikosongkan, lalu app dipindah ke Trash. Vault, Keep List dan pengaturan di `~/.amnesia` tetap ada, begitu juga folder Keep. Tidak perlu Terminal. Kalau dipasang lewat Homebrew, popup-nya menyarankan `brew uninstall --cask amnesia`.
- **Aman kalau app diseret ke Trash.** Selama Amnesia terbuka, ia mengecek tiap beberapa detik apakah app-nya masih ada di Applications. Kalau dipindah ke Trash, Amnesia langsung mematikan dirinya sendiri dan menjelaskan cara menyelesaikan (kosongkan Trash) atau membatalkan (Put Back, buka, Turn On).
- **Agent login ikut mengecek.** Saat logout, agent mengecek dulu apakah app Amnesia masih ada. Kalau app sudah dihapus atau ada di Trash, tidak ada yang dibersihkan dan agent menghapus dirinya sendiri, jadi tidak jalan lagi. Ini berlaku walau app sedang tidak terbuka.

### Diubah
- README dan website menjelaskan tombol uninstall yang baru.
- Tes baru di `test_clean.sh`: agent membersihkan saat logout kalau app masih ada, dan tidak melakukan apa pun kalau app sudah hilang atau ada di Trash.

## v5.14 — 2026-10-07

### Logout dan login lebih cepat
- **Logout memindah, tidak menghapus satu per satu.** Semua yang dibersihkan sekarang dipindah ke tempat sampah milik Amnesia (`~/.amnesia-trash`) di disk yang sama. Memindah itu instan, mau 1 GB atau 100 GB, jadi logout tidak makin lama walau data kerja makin besar. Penghapusan sebenarnya jalan setelah login berikutnya, pelan-pelan di background (prioritas rendah), jadi Mac tidak terasa lambat. Isi folder itu tidak muncul di mana pun (Spotlight melewatinya). Kalau pemindahan gagal, item langsung dihapus seperti dulu.
- **Cek saat login lebih ringan.** Logout meninggalkan penanda kecil kalau selesai dengan rapi. Kalau penanda ada, cek saat login melewati langkah Keychain. Kalau logout terputus (crash, dimatikan paksa), cek saat login membersihkan penuh seperti dulu.
- **Snapshot otomatis hanya menyimpan app yang berubah.** Saat logout, app yang datanya tidak berubah sejak snapshot terakhirnya dilewati. Snapshot otomatis juga dibatasi 150 detik: kalau lebih lama, dibatalkan dengan rapi (snapshot lama tetap ada) supaya pembersihan selalu sempat jalan.

### Ditambahkan
- **Peringatan kalau vault belum punya snapshot** saat kamu tekan Turn On. Kalau snapshot otomatis mati, ada peringatan bahwa login app akan terhapus saat logout berikutnya, lalu kamu diarahkan ke Profile Vault.
- **Cara Repair extension Chrome** di hasil Restore, muncul kalau snapshot Chrome-nya versi ringan: buka `chrome://extensions`, tekan Repair di tiap extension, tutup dan buka lagi Chrome kalau tombolnya belum ada, dan jangan pakai Remove.
- **Catatan langkah untuk melacak masalah** di `~/.amnesia/trace.log`: hanya jam dan nama langkah (sinyal logout, mulai/selesai snapshot, tiap tahap pembersihan, permintaan logout yang ditahan atau dilepas app, tombol Lanjut/Batal). Tanpa nama file. Hanya menyimpan beberapa ratus baris terakhir.
- **Laporan crash Amnesia disimpan** di `~/.amnesia/crash` (5 terbaru) sebelum folder log dibersihkan.
- **Batas waktu untuk langkah pembersihan** yang bisa macet (perintah Keychain, reset cache sistem), supaya satu perintah yang macet tidak menahan logout.

### Diubah
- **Snapshot Chrome ringan tetap menyimpan extension yang bukan dari Web Store.** Hanya extension dari Web Store yang dilewati (Chrome bisa mengunduhnya lagi lewat Repair). Extension yang kamu pasang dengan cara lain tetap ikut snapshot, jadi tidak hilang.
- **Save & Log Out hanya menyebut app yang nyala** di Profile Vault (sejak dulu yang disimpan memang hanya itu, tapi pertanyaannya menyebut semua app).
- `uninstall.sh` juga mengosongkan `~/.amnesia-trash`.
- **Ukuran tiap app di Profile Vault mengikuti snapshot ringan.** Dulu Chrome tetap menunjukkan ukuran penuhnya (sekitar 1 GB), padahal snapshot ringan menyimpan jauh lebih sedikit. Sekarang angkanya tidak menghitung yang dilewati mode ringan, jadi cocok dengan yang benar-benar masuk vault.

## v5.13.1 — 2026-10-07

### Diperbaiki
- **Memasang update saat Amnesia AKTIF membersihkan sesi yang sedang dipakai.** Saat memasang, `build.sh` menghentikan semua proses Amnesia, termasuk agent di background yang menjalankan pembersihan saat logout. Agent yang dihentikan tidak bisa membedakannya dari logout sungguhan, jadi ia menyimpan snapshot vault lalu membersihkan sesi (login Chrome dan data lain di luar Keep List dan folder Keep) padahal kamu masih login. Sekarang `build.sh` membiarkan agent tetap jalan dan hanya menutup app di menu bar.

## v5.13 — 2026-10-07

### Diperbaiki
- **Shutdown tetap jalan walaupun Amnesia sudah mencoba menahannya.** Saat ada popup Amnesia yang terbuka (misalnya "password salah"), macOS harus menunggu popup ditutup dulu sebelum Amnesia bisa menjawab permintaan shutdown. Saat itu macOS sudah berhenti menunggu, jadi "Batal" dari Amnesia datang terlambat. Sekarang popup tidak lagi menahan Amnesia: logout, restart atau shutdown langsung dijawab walau ada popup terbuka. Kalau jendela utama tertutup, Amnesia membukanya dulu supaya popup bisa menempel di sana.
- **Restore Profil menghapus data app yang ada di Mac tepat sebelum restore.** Sekarang data itu dipindah (tidak dihapus) ke `~/Library/Caches/Amnesia/before-restore`, dan hasil Restore memberi tahu letaknya. Folder itu ada sampai logout berikutnya.

### Ditambahkan
- **Peringatan "PERCOBAAN TERAKHIR".** Kalau tinggal 1 kali percobaan password, Amnesia bertanya dulu: salah sekali lagi = vault terhapus selamanya. Muncul sebelum Restore Profil, cek password di Ganti Password, simpan Kata Panik dan Pulihkan Kunci. Pesan password salah juga menulis "PERCOBAAN TERAKHIR" saat tinggal 1 kali.
- **Turn On mengecek apakah vault sudah ada di backup.** Kalau kamu punya vault yang belum pernah ikut backup, Turn On memberi peringatan dulu dan menawarkan pindah ke halaman Backup. "Tetap Aktifkan" tetap bisa dipilih.
- **Buka saat login** (Pengaturan, nyala dari awal). Amnesia jalan sendiri di menu bar setiap kamu login, juga saat sedang dimatikan. Memakai item login kecil terpisah (`com.amnesia.menubar`) yang hanya membuka app dan tidak pernah menghapus apa pun. Berlaku mulai login berikutnya. `uninstall.sh` ikut menghapusnya.
- **Snapshot Chrome ringan** (Pengaturan, nyala dari awal). Vault melewati file program extension dan cache besar Chrome (Extensions, ScriptCache, file model AI, daftar Safe Browsing dan sejenisnya). Di Mac biasa ukurannya turun dari sekitar 1 GB ke 150 MB, jadi snapshot dan restore jauh lebih cepat. Login, bookmark, riwayat, password dan pengaturan di dalam extension tetap disimpan. Setelah Restore, Chrome mengunduh ulang extension dari Web Store (butuh internet, beberapa menit). Extension yang bukan dari Web Store tidak kembali. Matikan pilihan ini kalau mau menyimpan profil Chrome lengkap.

### Diubah
- **Backup otomatis menyertakan Profile Vault.** Pilihannya sekarang bernama "Sertakan Profile Vault (login app yang tersimpan, terenkripsi)". Label lama "(untuk Pindah Mac)" membuatnya terkesan hanya untuk pindah ke Mac baru, sehingga vault bisa hilang tanpa salinan. Kalau dicentang mati, ada peringatan bahwa vault yang hilang tidak bisa dikembalikan. Kalau sebelumnya kamu mematikannya, pilihan itu tetap mati.
- Backup yang menyertakan vault meninggalkan penanda kecil (`~/.amnesia/backup.vault.ok`), yang dipakai Turn On untuk pengecekan di atas.

## v5.12 — 2026-10-07

### Diperbaiki
- **Backup ke Dropbox langsung 100%** lalu diam di 100% sampai selesai, dengan kecepatan yang awalnya sangat tinggi lalu turun pelan-pelan. rclone mengisi potongan file 48 MB dulu sebelum dikirim ke Dropbox, dan potongan itu langsung dihitung "terkirim" begitu terisi. Sekarang Amnesia memakai potongan 8 MB untuk Dropbox, jadi progress bar mengikuti upload yang sebenarnya. OneDrive dan cloud lain tidak diubah.
- **Tes kecepatan server menunjukkan angka yang jauh terlalu tinggi** (misalnya "10000 KB/s" di koneksi yang aslinya sekitar 750 KB/s). Waktu membuka koneksi dikurangkan dari waktu kirim, dan kalau keduanya hampir sama, sisanya hampir nol. Sekarang tes mengirim 1 MB lalu 5 MB dan hanya melihat waktu tambahan yang dibutuhkan yang lebih besar, jadi waktu koneksi hilang dengan sendirinya. Kalau selisihnya terlalu kecil untuk dipercaya, dipakai waktu totalnya, yang hasilnya lebih rendah, tidak pernah terlalu tinggi.

### Diubah
- **Catatan privasi di tur awal dan di Pengaturan lebih besar** ("Semua tetap di Mac ini…"), jadi lebih mudah dibaca.

## v5.11 — 2026-10-07

### Diperbaiki
- **Login ke Dropbox, OneDrive, Box dan pCloud selalu gagal** ("isn't connected"). Amnesia menjalankan rclone dengan pilihan (`--auth-no-open-browser`) yang tidak dikenal perintah hubungkan, jadi rclone langsung berhenti dan halaman login tidak pernah terbuka. Pilihan itu sudah dibuang.
- **Google Drive dibilang "belum login" padahal sedang sinkron.** Sekarang Amnesia mencari Google Drive di belakang layar, bilang "sudah login, tapi belum siap (masih sinkron)" kalau memang begitu, dan menampilkan 3 langkah: buka Google Drive dan login, tunggu sampai sinkron selesai, tekan Cek Lagi.

### Diubah
- **Login cloud terbuka di browser biasa kamu** (browser default, atau Safari di Mac baru), bukan jendela kecil di dalam Amnesia. Layar tunggu punya tombol "Browser tidak terbuka? Buka halaman login" dan tombol Batal.
- **Kolom ulangi langsung memberi tahu sudah sama atau belum**: password vault, kata panik (saat buat vault dan di jendela Kata Panik), password baru, dan password backup.
- **"Yang disimpan di vault" sekarang berupa kotak-kotak kecil** berisi ikon app, nama dan ukuran. Klik kotak untuk memilih. Cukup 1 catatan singkat di bawah kalau snapshot bisa makan beberapa menit (dan app mana yang besar), bukan peringatan di setiap app.
- **Vault baru dimulai tanpa app yang dicentang.** Kamu yang memilih app mana yang masuk.
- **Hapus snapshot 1 app** lewat ikon tempat sampah di sampingnya. "Hapus Semua Snapshot" tetap menghapus semuanya (vault dan password tetap).
- **Panduan terbuka sebagai popup** dengan tombol yang jelas: "Cara kerja backup" (sekarang di atas halaman Backup) dan "Lihat caranya (7 langkah)" untuk akses Google sendiri.
- **Teks lebih besar dan mudah dibaca** di halaman utama dan tur awal. Kotak di halaman utama sekarang ikon di kiri dan teks di sampingnya, jadi seluruh halaman (termasuk "Yang Akan Dihapus") muat tanpa scroll.
- **"Yang Akan Dihapus" menjelaskan baris dari app yang ada di Keep List**, misalnya "hanya cache: app ini ada di Keep List, login-nya tetap aman".
- **Tes kecepatan server** mengirim 2 MB dan tidak menghitung waktu membuka koneksi, jadi angkanya lebih mendekati kecepatan backup sungguhan. Ditandai sebagai perkiraan kasar.
- **Layar tunggu backup** hanya bilang "Jangan cabut drive-nya" untuk flashdisk, "Jangan matikan internet" untuk server dan cloud, dan bahwa app Google Drive yang mengunggah untuk Google Drive.
- Google Drive sekarang muncul di daftar app Keep List (datanya ada di `Application Support/Google/DriveFS`).

## v5.10.1 — 2026-10-07

### Diperbaiki
- **Izin Akses Disk Penuh tidak hilang lagi setelah update.** Amnesia tidak ditandatangani Apple, jadi setiap build baru dianggap app lain oleh macOS: tombolnya di System Settings tetap menyala, tapi izinnya tidak berlaku. Sekarang `app/build.sh` membuat sertifikat tanda tangan lokal sekali saja ("Amnesia Local Signing", di Keychain login kamu) dan memakainya di setiap build, jadi macOS tahu ini app yang sama.
- Build pertama mungkin memunculkan 1 popup Keychain yang menanyakan apakah `codesign` boleh memakai kuncinya. Masukkan password Mac, lalu tekan **Always Allow**.
- Sekali lagi setelah update ini: hapus Amnesia dari Full Disk Access (−), tambahkan lagi (+), lalu Tutup & Buka Lagi. Setelah itu izinnya tetap.
- Kalau sertifikat gagal dibuat, build memakai cara lama dan memberi tahu. Pembersihan saat logout hanya menghapus password di Keychain, tidak pernah sertifikat, jadi sertifikat ini tetap ada.

## v5.10 — 2026-10-07

### Ditambahkan
- **"Akun & data Apple" di Keep List.** Kartu baru di paling atas Keep List (dan di halaman "Apa yang disimpan?" setelah tur) menyimpan login iCloud / Apple ID, Foto, Notes, Mail, Calendar & Reminders, Kontak, Messages, Shortcuts dan pengaturan git. Semua menyala secara default. Tiap item bisa dimatikan (Amnesia tanya dulu). Disimpan di Keep List, bukan vault, karena akun Apple terikat ke Mac ini dan Foto bisa sangat besar (`APPLE_KEEP` di settings.conf).
- **Tambah file atau folder apa saja ke Keep List.** "Tambah Folder atau File" sekarang punya tombol "Pilih di Finder…" (file tersembunyi ikut tampil) dan kolom untuk mengetik path, jadi file seperti `Library/Preferences/MobileMeAccounts.plist` juga bisa ditambahkan.
- **Snapshot per app.** Setiap app punya snapshot sendiri, jadi menyimpan satu app tidak pernah menimpa app lain. Halaman vault menampilkan waktu dan ukuran snapshot terakhir per app. Snapshot lama (1 file) tetap dibaca, dan dibersihkan setelah semua app punya snapshot sendiri.
- **Folder di vault.** Tambahkan folder (dokumen, PDF, musik, video) ke vault di halaman Profile Vault. Ada peringatan kalau folder lebih dari 1 GB (`VAULT_FOLDERS` di settings.conf).
- **Ukuran sebelum menyimpan.** Halaman vault menampilkan ukuran tiap app dan totalnya, dan hanya app besar (500 MB atau lebih) yang diberi peringatan "bisa lama".
- **"Hapus Snapshot"** hanya menghapus snapshot yang tersimpan. Vault dan password tetap. "Hapus Vault" tetap menghapus semuanya.
- **Tombol Batal** untuk Snapshot, Restore dan Backup (di jendela dan di panel menu bar). Snapshot atau backup sebelumnya tetap utuh, dan file setengah jadi dihapus.
- **Cek setelah Restore.** Setelah restore muncul daftar ✅ atau ❌ per app (misalnya apakah `gh` masih login), plus baris "cek sendiri" untuk login web di Chrome.
- **Progress backup untuk semua tujuan** (flashdisk, folder, server, cloud): tahap ("1/2 Mengunci file…", "2/2 Mengunggah…"), persen, kecepatan, sisa waktu, dan tombol Batal. Kalau tidak ada kemajuan selama 10 menit, backup berhenti sendiri dan memberi tahu.
- **Backup ke folder mana saja** (misalnya drive jaringan yang sudah terpasang), selain flashdisk, server dan cloud.
- **Server: kolom Port** (default 22). Format `user@alamat:port` juga bisa.
- **Server: Hubungkan mengecek folder.** Folder backup dibuat, dites bisa ditulis, dan path lengkapnya di server ditampilkan. Kalau folder butuh izin admin (sudo), pesannya jelas dan menyarankan folder di home. Amnesia tidak pernah memakai sudo.
- **Server: tes kecepatan saat Hubungkan**, lalu perkiraan lama backup. Backup yang lambat biasanya karena upload internet yang pelan, bukan macet.
- **Google Drive lewat app Google Drive.** Kalau Google Drive for Desktop terpasang, Amnesia menyalin backup ke foldernya dan app itu yang mengunggah. Kalau belum terpasang, ada tombol download. Client ID Google milikmu sendiri ada di "Lanjutan", dengan panduan langkah demi langkah.
- **Panduan Backup di dalam app**: langkah per tujuan, folder yang aman, perkiraan lama, dan cara mengecek file backup.
- **Tombol pintas "Yang akan dihapus"** di halaman utama.
- Catatan login cloud ditulis ke `~/.amnesia/cloud.log` (tanpa password atau token), untuk membantu mencari tahu kenapa login gagal.

### Diubah
- **"Yang akan dihapus" lebih mudah dibaca.** Baris memakai ikon app asli, ikon macOS untuk item sistem, dan ikon jenis file untuk file. Thumbnail asli hanya dibuat saat kelompok dibuka, dan hanya untuk Desktop, Downloads, Documents dan Pictures. Tiap baris punya nama jelas (misalnya "Chrome · cache"); path lengkap muncul saat diklik atau disorot.
- Kelompok berdasarkan arti: "Dipulihkan dari vault", "File kamu", "Akun & sinkronisasi Apple", "Data & setting app", "Keychain", "Riwayat, cache & log" dan "Data sistem macOS (dibuat ulang otomatis)". Kelompok sistem disembunyikan kecuali kamu nyalakan.
- Pintasan buatan Amnesia (`~/Desktop/Keep`, `~/Desktop/Amnesia.app`) tidak ditampilkan lagi, karena dibuat ulang otomatis.
- **Kotak Cloud 3 langkah:** 1. pilih layanan, 2. hubungkan ("✓ Terhubung sebagai …"), 3. tulis nama folder saja. Istilah "remote" dan "rclone" pindah ke "Lanjutan".
- **Progress snapshot per app**: "Menyimpan OpenCode… 2 dari 3". Teksnya selalu sesuai app yang sedang disimpan.
- **Akses Disk Penuh dicek sekali, sebelum Snapshot**, supaya macOS tidak bertanya di tengah proses. Tutup & Buka Lagi diblokir selama ada proses jalan, dan app menjelaskan cara membetulkan kalau terlanjur menekan "Limit Access".
- **Buat vault:** kolom "Ulangi password" baru muncul setelah mulai mengetik, dan memberi tahu kalau keduanya tidak sama.
- **Ganti password:** password sekarang dulu, lalu password baru, lalu ulangi. Password baru yang sama dengan yang lama ditolak.
- **Pesan backup** menyebut jam dan tujuan, dengan pesan jelas untuk dibatalkan ("Backup dibatalkan. Backup sebelumnya tetap aman."), dihentikan, macet dan gagal, bukan "exited with code 15".
- **Popup menempel di jendela Amnesia**, bukan di tengah layar, dan jendela mengingat posisinya.
- Kotak di halaman utama sedikit lebih kecil dan halamannya bisa di-scroll, supaya semua muat.

### Diperbaiki
- Dropbox dan OneDrive kadang gagal dengan pesan "isn't connected". Kalau jendela login tidak selesai, Amnesia sekarang menawarkan login lewat browser biasa. (Belum pasti tuntas; kabari kalau masih gagal.)
- `app/screenshots.sh` tidak memotret "Yang akan dihapus" karena macOS menutup app saat daftarnya disiapkan. Penutupan otomatis sekarang dimatikan selama screenshot. Halaman Pindah ke Mac baru juga ikut dipotret (total 28 screenshot).
- Membatalkan backup bisa meninggalkan 7-Zip tetap jalan di belakang.

## v5.9.1 — 2026-10-06

### Ditambahkan
- **Hapus app dengan aman: `uninstall.sh`.** Jalankan `bash ~/.amnesia/uninstall.sh` di Terminal. Script ini menghapus file agent login lebih dulu, jadi menghentikan agent tidak akan memicu pembersihan. Lalu menghentikan yang masih jalan, menghapus app (termasuk versi Homebrew), dan mengecek tidak ada yang tersisa. Kalau masih ada sisa, kamu diberi tahu supaya jangan logout dulu.
- Secara default vault, Keep List dan pengaturan di `~/.amnesia` tetap disimpan, kalau nanti mau pasang lagi. `--all` ikut menghapusnya, tapi hanya setelah kamu mengetik `HAPUS` (atau `DELETE`). Folder Keep kamu tidak pernah disentuh.
- App menyalin `uninstall.sh` ke `~/.amnesia`, jadi tetap ada walaupun kamu pasang dari .dmg.
- `brew uninstall --cask amnesia` sekarang menjalankan langkah aman yang sama.
- **Cara hapus** dijelaskan di README (bagian "Cara hapus"), FAQ website, READ ME FIRST di .dmg, dan pesan Homebrew: jangan cuma buang app ke Trash.

### Diperbaiki
- App gagal di-compile karena bentrok nama di kode screenshot (`log`).

## v5.9 — 2026-10-06

### Ditambahkan
- **Progress bar** untuk Snapshot, Restore dan Simpan & Logout. Ada persentasenya, jadi kamu tahu sudah sampai mana. Panel menu bar juga menampilkan persentasenya.
- **Ganti password vault** (Profile Vault, tombol Password). Snapshot kamu tetap utuh; tidak perlu hapus vault lalu buat baru lagi.
- **Pilih apa yang disimpan di vault.** Di halaman Profile Vault, centang app yang mau disimpan (misalnya WhatsApp tidak ikut). Snapshot dan Simpan & Logout hanya menyimpan app yang dicentang (`VAULT_SKIP` di settings.conf).
- **Ketik ulang kata panik** saat mengaturnya (waktu buat vault dan di jendela Kata Panik), supaya salah ketik tidak bikin repot. Tombol Simpan baru aktif kalau keduanya sama.
- **Pindah ke Mac baru** sekarang punya halaman sendiri (dari halaman Profile Vault atau Pengaturan), dengan panduan 4 langkah: Siapkan Pindah, Backup, Ambil Vault dari Backup, Restore Profil dan Kunci.
- Tombol **Tutup & Buka Lagi** di samping Akses Disk Penuh (di tur dan di Pengaturan). **Tur ingat posisi terakhir**, jadi setelah dibuka lagi tur lanjut di halaman yang sama, tidak mulai dari awal.
- **Pesan SSH yang jelas.** Kalau backup gagal ke server, pesannya bilang kenapa: server menolak kunci (tekan Hubungkan lagi), server terlihat berbeda (diinstal ulang?), atau server sedang tidak bisa dihubungi (nanti dicoba lagi). Ganti password server tidak merusak backup, karena Amnesia login pakai kunci, bukan password.
- Kalau server diinstal ulang, tombol Hubungkan menjelaskannya dan bertanya dulu sebelum melupakan identitas server lama.

### Diubah
- App di snapshot sekarang tampil sebagai kotak-kotak rapi, bukan teks yang turun ke bawah. Halaman ini juga menjelaskan bahwa hanya snapshot terbaru yang disimpan, dan snapshot tidak perlu password (hanya Restore yang perlu).
- **"Yang akan dihapus"**: klik di mana saja pada baris kelompok untuk membuka daftarnya (bukan cuma panah kecilnya). Waktunya sekarang menunjukkan kapan benar-benar diperbarui (misalnya "Hari ini 15.20"), bukan "0 detik lalu", dan daftar hanya dibuat ulang kalau sudah lebih dari 1 menit.
- Kotak backup cloud menampilkan langkahnya: 1. pilih layanan (Google Drive, Dropbox, OneDrive, Box, pCloud), 2. tekan tombol untuk login.

## v5.8.1 — 2026-10-06

### Diperbaiki
- `app/screenshots.sh` berhenti setelah 10 screenshot (cuma English). Sekarang jalan per bahasa, jadi masalah di satu bahasa tidak menghentikan yang lain, dan layar "yang akan dihapus" diambil paling akhir dengan daftarnya disiapkan di background.
- Catatan proses screenshot disimpan di `~/.amnesia/shots.log`, dan script memberi tahu berapa dari 22 screenshot yang berhasil.
- Pesan "No such file or directory" yang tidak berbahaya di script screenshot sudah hilang.

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
