// Efek suara + musik untuk video paper craft (dibuat ElevenLabs lewat make_audio.py di Mac).
// Waktu tiap efek ditentukan animasi di index.html (fungsi sfx()); di sini hanya "resep" suaranya.
// Kalimat voiceover tetap di ../script.js (satu suara: Bill). sound.json dibuat ulang dari file ini oleh build.js.
window.SOUND = {
  sfx: {
    // [prompt, durasi detik]
    rustle:   ['Soft paper rustle, a sheet of craft paper sliding across a wooden table, close mic, dry, no music', 1.2],
    unfold:   ['Paper pop-up card unfolding, crisp cardstock fold opening, satisfying, close mic, no music', 1.0],
    flick:    ['Single light paper card flick, quick soft whoosh of a small paper cutout, dry, no music', 0.5],
    tap:      ['Tiny cardboard piece tapped down onto a wooden table, soft tap, stop motion foley, no music', 0.5],
    swoosh:   ['Paper cutout sliding in slowly, airy soft whoosh, sneaky, no music', 1.2],
    sting:    ['Short sneaky low pizzicato string pluck, two notes, mysterious cartoon sting', 1.2],
    type:     ['Soft laptop keyboard typing, six quick key presses, close mic, no music', 1.4],
    click:    ['Crisp single mouse click, clean, no music', 0.3],
    stamp:    ['Rubber stamp pressed firmly onto paper, solid thud, satisfying, no music', 0.6],
    suck:     ['Several paper cards whooshing quickly into a metal box, fast airy paper flurry, no music', 1.3],
    lock:     ['Heavy safe door closing with a metal clunk, then a combination dial spinning briefly', 1.6],
    crickets: ['Quiet crickets chirping at night, awkward silence, comedic, no music', 3.0],
    key:      ['Small metal key turning in a lock, two clicks, soft unlock, no music', 0.9],
    flurry:   ['Paper cards flying out joyfully and landing, bright flurry of paper, whoosh then gentle taps, no music', 1.8],
    letter:   ['Small cardboard letter tile placed on a table, soft tap with tiny paper rustle, no music', 0.5],
    ding:     ['Warm gentle glockenspiel chime, two notes, resolving, subtle', 1.6],
    tick:     ['Old mechanical clock ticking, three ticks, quiet room, no music', 1.6],
    flip:     ['Fast paper pages flipping backwards like a flip book, whoosh, no music', 1.2],
    slide:    ['Laptop sliding across a wooden table, soft friction, no music', 1.0],
    pop:      ['Cute soft paper pop, speech bubble appearing, light, no music', 0.4],
  },
  // satu musik per skenario (ElevenLabs Music). Panjang dibuat sesuai versi terpanjang skenario itu, lalu dipotong untuk versi pendek.
  music: {
    spy:    'Stop-motion paper craft film score for a playful spy caper, 96 bpm. Sneaky low pizzicato strings and upright bass, ' +
            'brushed snare, muted trumpet hints, felt piano, glockenspiel accents. Starts tense and sneaky at night, ' +
            'drops to near silence for a comedic pause, then a quick rewind, and turns warm, bright and confident, ending on a clean final chord. No vocals.',
    parents:'Stop-motion paper craft film score, playful family comedy, 100 bpm. Pizzicato strings, ukulele, felt piano, glockenspiel, ' +
            'light hand claps. Starts with a comic "uh-oh" tension, then relaxed and cheeky, a short pause, and a cheerful warm ending. No vocals.',
    borrow: 'Stop-motion paper craft film score, friendly and cozy, 98 bpm. Ukulele, pizzicato strings, felt piano, glockenspiel, soft shaker. ' +
            'Light curious start, gentle build, relaxed middle, warm uplifting resolve with a clean ending. No vocals.',
    // video gabungan 3 skenario (sekitar 54 detik)
    all:    'Stop-motion paper craft film score, anthology of three short comic stories, 96 bpm. Pizzicato strings, upright bass, felt piano, ukulele, ' +
            'glockenspiel, brushed snare. Part one sneaky spy caper at night, part two cheeky family comedy, part three friendly and cozy, ' +
            'each part separated by a short playful pause, ending warm, bright and confident with a clean final chord. No vocals.',
  },
  // panjang musik (detik) per skenario: dibuat sedikit lebih panjang dari videonya
  musicLen: { spy: 32, parents: 32, borrow: 32, all: 56 },
  scenario: c => String(c).startsWith('p') ? 'parents' : String(c).startsWith('b') ? 'borrow' : 'spy',
};
