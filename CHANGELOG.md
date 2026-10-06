# Changelog

Semua perubahan Amnesia dicatat di sini. Versi terbaru ada di paling atas.
Nomor versi juga terlihat di app (di samping judul dan di bawah menu bar).

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
