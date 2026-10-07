// Naskah video Amnesia: satu sumber untuk waktu adegan, judul di layar dan voiceover (EN + ID).
// Dipakai oleh video/index.html (gambar & animasi) dan video/make_vo.py (lewat vo.json).
// Tiap versi (cut) = daftar adegan [id adegan, durasi detik, teks voiceover EN, teks voiceover ID].
// Draft 2: sudut privasi / OPSEC (Mac dipinjam, Mac hilang atau dicuri, kata panik).
window.SCRIPT = {
  // judul besar di layar, per adegan
  headline: {
    logo:    ['Amnesia', 'Amnesia'],
    desk:    ['Your Mac remembers.', 'Mac kamu mengingat.'],
    labels:  ['More than you think.', 'Lebih banyak dari yang kamu kira.'],
    wipe:    ['Log out. Gone.', 'Logout. Hilang.'],
    lend:    ['Lending your Mac?', 'Mac mau dipinjam?'],
    lost:    ['Lost or stolen?', 'Hilang atau dicuri?'],
    keep:    ['Except what you keep.', 'Kecuali yang kamu simpan.'],
    vault:   ['Profile Vault', 'Profile Vault'],
    restore: ['Back in one click.', 'Kembali dengan satu klik.'],
    panic:   ['"Open it." Sure.', '"Buka dong." Boleh.'],
    app:     ['One switch.', 'Satu tombol.'],
    backup:  ['Back up anywhere.', 'Backup ke mana saja.'],
    oss:     ['Free & open source.', 'Gratis & open source.'],
    cta:     ['Get Amnesia', 'Unduh Amnesia'],
  },
  cuts: {
    // 60 detik: pengenalan lengkap
    60: [
      ['logo', 3, 'Meet Amnesia. Privacy for your Mac.',
                  'Kenalan dengan Amnesia. Privasi untuk Mac kamu.'],
      ['desk', 4, 'Every day, your Mac quietly remembers what you do.',
                  'Setiap hari, Mac kamu diam-diam mengingat semua yang kamu lakukan.'],
      ['labels', 4, 'History, cookies, downloads, saved logins, chats.',
                    'Riwayat, cookie, unduhan, login tersimpan, chat.'],
      ['wipe', 5, 'With Amnesia on, it is all wiped every time you log out.',
                  'Dengan Amnesia, semuanya dihapus setiap kamu logout.'],
      ['lend', 5, 'Someone needs your Mac? Log out, log back in, and hand it over clean.',
                  'Ada yang mau pinjam Mac kamu? Logout, login lagi, dan serahkan dalam keadaan bersih.'],
      ['lost', 6, 'Lost or stolen after you logged out? There is nothing left to find, and your vault stays encrypted.',
                  'Hilang atau dicuri setelah kamu logout? Tidak ada yang tersisa, dan vault kamu tetap terenkripsi.'],
      ['keep', 5, 'Only what you choose to keep stays: your Keep folder and Keep List.',
                  'Yang tetap ada hanya pilihanmu: folder Keep dan Keep List.'],
      ['vault', 6, 'App logins wait in Profile Vault, locked with your password.',
                   'Login app menunggu di Profile Vault, dikunci dengan password kamu.'],
      ['restore', 4, 'Back in? Restore them with one click.',
                     'Sudah login lagi? Kembalikan dengan satu klik.'],
      ['panic', 5, 'Forced to open it? Type your panic word instead. The vault is gone.',
                   'Dipaksa membukanya? Ketik kata panik saja. Vault langsung hilang.'],
      ['app', 4, 'Turn it on once. The rest is automatic.',
                 'Aktifkan sekali. Sisanya otomatis.'],
      ['oss', 4, 'Free and open source.',
                 'Gratis dan open source.'],
      ['cta', 5, 'Get Amnesia on GitHub. Then forget everything. Pun intended.',
                 'Unduh Amnesia di GitHub. Lalu lupakan semuanya. Pun intended.'],
    ],
    // 30 detik: untuk README / halaman GitHub
    30: [
      ['logo', 2, 'This is Amnesia.', 'Ini Amnesia.'],
      ['labels', 4, 'Your Mac keeps history, cookies, downloads and logins.',
                    'Mac kamu menyimpan riwayat, cookie, unduhan, dan login.'],
      ['wipe', 5, 'Amnesia wipes it all, every time you log out.',
                  'Amnesia menghapus semuanya, setiap kamu logout.'],
      ['lend', 5, 'Lending your Mac? Log out and back in. It is clean.',
                  'Mac mau dipinjam? Logout lalu login lagi. Sudah bersih.'],
      ['lost', 5, 'Lost or stolen? Nothing left to find.',
                  'Hilang atau dicuri? Tidak ada yang bisa ditemukan.'],
      ['keep', 4, 'Except what you choose to keep.', 'Kecuali yang kamu pilih untuk disimpan.'],
      ['cta', 5, 'Free on GitHub. Then forget everything. Pun intended.', 'Gratis di GitHub. Lalu lupakan semuanya. Pun intended.'],
    ],
    // 15 detik: seperti iklan / pitching
    15: [
      ['desk', 3, 'Your Mac remembers everything.', 'Mac kamu mengingat semuanya.'],
      ['wipe', 4, 'Amnesia makes it forget, every logout.', 'Amnesia membuatnya lupa, setiap logout.'],
      ['lost', 4, 'Lost, stolen or borrowed? Nothing to find.', 'Hilang, dicuri, atau dipinjam? Tak ada yang bisa ditemukan.'],
      ['cta', 4, 'Amnesia. Forget everything. Pun intended.', 'Amnesia. Lupakan semuanya. Pun intended.'],
    ],
  },
};
