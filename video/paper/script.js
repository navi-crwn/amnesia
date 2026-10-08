// Naskah video Amnesia (Mata-mata, Orang tua, Pinjam Mac, gabungan; gaya paper craft di paper/): satu sumber untuk waktu adegan, teks di layar dan voiceover (EN + ID).
// Dipakai oleh video/index.html (gambar, animasi, subtitle), video/render.js (posisi suara)
// dan video/make_vo_eleven.py (lewat vo-lines.json, dibuat ulang dari file ini).
window.SCRIPT = {
  // kalimat voiceover. role: gelap = narator cerita, santai = suara kedua setelah twist
  lines: {
    L1:  { role: 'gelap',  en: "2 a.m. Someone wants what's on your Mac.", id: 'Jam dua pagi. Ada yang mengincar isi Mac kamu.' },
    L3:  { role: 'gelap',  en: 'He even knows your password.', id: 'Password kamu pun dia tahu.' },
    L4:  { role: 'gelap',  en: "But there's nothing here. No history. No logins. No chats.", id: 'Tapi isinya kosong. Tanpa riwayat. Tanpa login. Tanpa chat.' },
    L6:  { role: 'gelap',  en: 'Because hours earlier, you logged out. And your Mac forgot everything.', id: 'Karena beberapa jam sebelumnya, kamu logout. Dan Mac kamu lupa semuanya.' },
    L8:  { role: 'gelap', en: 'Amnesia. Free on GitHub. Forget everything.', id: 'Amnesia. Gratis di GitHub. Lupakan semuanya.' },
    L9:  { role: 'gelap',  en: 'Nothing.', id: 'Kosong.' },
    // skenario 2 "Orang tua" (hanya EN)
    O1:  { role: 'gelap', en: 'Uh-oh. Your parents want your Mac password.' },
    O2:  { role: 'gelap', en: 'No sweat. Save and log out.' },
    O3:  { role: 'gelap', en: 'Apps and private stuff go into the vault.' },
    O4:  { role: 'gelap', en: 'They log in. A clean Mac. Just your homework.' },
    O5:  { role: 'gelap', en: 'Privacy, no headache. Amnesia.' },
    // skenario 3 "Pinjam Mac" (hanya EN)
    B1:  { role: 'gelap', en: 'A friend wants to borrow your Mac.' },
    B2:  { role: 'gelap', en: 'Your whole life is on it. Chats. Tabs. Photos.' },
    B3:  { role: 'gelap', en: 'Save and log out. Your stuff goes into the vault.' },
    B4:  { role: 'gelap', en: 'Log back in. A clean Mac. Hand it over.' },
    B5:  { role: 'gelap', en: "Got it back? One click, and it's all yours again." },
    B6:  { role: 'gelap', en: 'Amnesia. Lend your Mac, not your life.' },
  },
  roles: {
    gelap: 'Narator (satu suara untuk semua kalimat)',
  },
  // judul besar di layar. Adegan cerita sengaja tanpa judul (gambar yang bercerita).
  headline: {
    duh:     ['...duh.', '...duh.'],
    flash:   ['3 hours earlier', '3 jam sebelumnya'],
    keep:    ['Except what you keep.', 'Kecuali yang kamu simpan.'],
    vault:   ['Profile Vault', 'Profile Vault'],
    restore: ['Back in one click.', 'Kembali dengan satu klik.'],
    panic:   ['"Open it." Sure.', '"Buka dong." Boleh.'],
    cta:     ['Amnesia. Pun intended.', 'Amnesia. Pun intended.'],
    cta2:    ['Privacy. No headache.', 'Privasi aman. Gak pakai pusing.'],
    back:    ['Back in one click.', 'Kembali dengan satu klik.'],
    cta3:    ['Lend your Mac. Not your life.', 'Pinjamkan Mac-nya. Bukan hidupmu.'],
  },
  // tiap versi = daftar [id adegan, durasi detik, kalimat voiceover (atau null)]
  cuts: {
    // skenario 1 "Mata-mata"
    30: [
      ['agent', 4, 'L1'], ['login', 5, 'L3'], ['empty', 7, 'L4'], ['duh', 3, null], ['flash', 6, 'L6'], ['cta', 5, 'L8'],
    ],
    // iklan pitching 15 detik (dari Mata-mata)
    15: [
      ['login', 4, 'L3'], ['empty', 4, 'L9'], ['duh', 3, null], ['cta', 4, 'L8'],
    ],
    // skenario 2 "Orang tua"
    p30: [
      ['parents', 4, 'O1'], ['savelo', 5, 'O2'], ['tovault', 5, 'O3'], ['parentlogin', 7, 'O4'], ['goodkid', 3, null], ['cta2', 6, 'O5'],
    ],
    // skenario 3 "Pinjam Mac"
    b30: [
      ['borrow', 4, 'B1'], ['busy', 5, 'B2'], ['savevault', 5, 'B3'], ['lend2', 6, 'B4'], ['back', 5, 'B5'], ['cta3', 5, 'B6'],
    ],
    // satu video berisi ketiga skenario, satu penutup
    all: [
      ['agent', 4, 'L1'], ['login', 4, 'L3'], ['empty', 5.5, 'L4'], ['duh', 3, null],
      ['parents', 4, 'O1'], ['savelo', 4, 'O2'], ['parentlogin', 6, 'O4'], ['goodkid', 2.5, null],
      ['borrow', 4, 'B1'], ['savevault', 5.5, 'B3'], ['lend2', 5.5, 'B4'], ['cta', 6, 'L8'],
    ],
  },
  // musik dimatikan sebentar di adegan ini (jeda lucu)
  silence: ['duh', 'goodkid'],
};
