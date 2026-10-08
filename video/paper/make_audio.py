#!/usr/bin/env python3
# Bikin SEMUA suara untuk video paper craft lewat ElevenLabs, di Mac kamu:
#   1) voiceover Bill   -> video/vo2/<kalimat>-en.mp3   (lewat make_vo_eleven.py)
#   2) efek suara       -> video/paper/sfx/<efek>.mp3   (ElevenLabs Sound Effects)
#   3) musik latar      -> video/paper/music/<skenario>.mp3 (ElevenLabs Music)
#
#   python3 ~/.amnesia/video/paper/make_audio.py            semuanya (yang belum ada saja)
#   python3 ~/.amnesia/video/paper/make_audio.py --sfx      hanya efek suara
#   python3 ~/.amnesia/video/paper/make_audio.py --music    hanya musik
#   python3 ~/.amnesia/video/paper/make_audio.py --redo crickets spy   buat ulang efek/musik tertentu
#
# API key yang sama dengan make_vo_eleven.py (disimpan di Keychain, tidak pernah ditulis ke file).
# File yang sudah ada dilewati, kecuali resepnya berubah (dicatat di made.json masing-masing folder).
import json, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import make_vo_eleven as vo   # get_key(), call()

SFX_DIR, MUS_DIR = os.path.join(HERE, 'sfx'), os.path.join(HERE, 'music')


def made(folder):
    f = os.path.join(folder, 'made.json')
    return (json.load(open(f)) if os.path.exists(f) else {}), f


def make_sfx(key, sfx, redo):
    os.makedirs(SFX_DIR, exist_ok=True)
    rec, rf = made(SFX_DIR)
    n = 0
    for name, (prompt, secs) in sfx.items():
        f = os.path.join(SFX_DIR, name + '.mp3')
        want = {'prompt': prompt, 'secs': secs}
        if os.path.exists(f) and rec.get(name) == want and name not in redo:
            continue
        print(f'  efek {name}: {prompt}')
        audio = vo.call('/sound-generation?output_format=mp3_44100_128', key,
                        {'text': prompt, 'duration_seconds': max(0.5, min(22, secs)), 'prompt_influence': 0.55})
        open(f, 'wb').write(audio)
        rec[name] = want
        json.dump(rec, open(rf, 'w'), indent=1)
        n += 1
    return n


def make_music(key, music, lens, redo):
    os.makedirs(MUS_DIR, exist_ok=True)
    rec, rf = made(MUS_DIR)
    n = 0
    for name, prompt in music.items():
        f = os.path.join(MUS_DIR, name + '.mp3')
        want = {'prompt': prompt, 'secs': lens.get(name, 32)}
        if os.path.exists(f) and rec.get(name) == want and name not in redo:
            continue
        print(f'  musik {name} ({want["secs"]} detik) ... bisa makan waktu 1-2 menit')
        audio = vo.call('/music?output_format=mp3_44100_192', key,
                        {'prompt': prompt, 'music_length_ms': int(want['secs'] * 1000), 'model_id': 'music_v1'})
        open(f, 'wb').write(audio)
        rec[name] = want
        json.dump(rec, open(rf, 'w'), indent=1)
        n += 1
    return n


def main():
    args = sys.argv[1:]
    only_sfx, only_music = '--sfx' in args, '--music' in args
    redo = args[args.index('--redo') + 1:] if '--redo' in args else []
    data = json.load(open(os.path.join(HERE, 'sound.json')))
    if not only_sfx and not only_music:
        print('1/3 Voiceover (Bill)')
        r = subprocess.run([sys.executable, os.path.join(os.path.dirname(HERE), 'make_vo_eleven.py'), '--no-open'])
        if r.returncode:
            sys.exit('Voiceover gagal, berhenti.')
    key = vo.get_key()
    total = 0
    if not only_music:
        print('2/3 Efek suara')
        total += make_sfx(key, data['sfx'], redo)
    if not only_sfx:
        print('3/3 Musik')
        try:
            total += make_music(key, data['music'], data.get('musicLen', {}), redo)
        except SystemExit as e:
            print(f'\n! Musik tidak bisa dibuat lewat API: {e}')
            print('  Kemungkinan paket ElevenLabs kamu belum termasuk Music API. Cara lain: buka elevenlabs.io > Music,')
            print('  tempel resep musik dari video/paper/sound.json, unduh MP3-nya, lalu simpan sebagai')
            print(f'  {MUS_DIR}/<spy|parents|borrow|all>.mp3')
    print(f'\nSelesai: {total} file efek/musik baru.')
    # satu zip berisi semua suara, untuk dikirim ke Claude
    import zipfile
    out = os.path.expanduser('~/Downloads/amnesia-audio.zip')
    vo2 = os.path.join(os.path.dirname(HERE), 'vo2')
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
        for folder, arc in ((vo2, 'vo2'), (SFX_DIR, 'sfx'), (MUS_DIR, 'music')):
            if not os.path.isdir(folder):
                continue
            for f in sorted(os.listdir(folder)):
                if f.endswith('-en.mp3') or (arc != 'vo2' and f.endswith('.mp3')) or f == 'made.json':
                    z.write(os.path.join(folder, f), f'{arc}/{f}')
    print(f'Kirim file ini ke Claude: {out}')
    subprocess.run(['open', '-R', out])


if __name__ == '__main__':
    main()
