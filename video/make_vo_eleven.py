#!/usr/bin/env python3
# Bikin semua file voiceover (L1-en.mp3, O1-en.mp3, B1-en.mp3, ...) otomatis lewat ElevenLabs API.
# Dijalankan di Mac kamu, bukan di cloud. Tidak butuh paket tambahan.
#
#   python3 ~/.amnesia/video/make_vo_eleven.py           semua kalimat bahasa Inggris
#   python3 ~/.amnesia/video/make_vo_eleven.py --test    hanya L1, untuk cek suara dulu
#   python3 ~/.amnesia/video/make_vo_eleven.py --redo L4 buat ulang satu kalimat
#   python3 ~/.amnesia/video/make_vo_eleven.py --voice   pilih suara lagi
#   python3 ~/.amnesia/video/make_vo_eleven.py --lang id juga bahasa Indonesia (en,id = keduanya)
#
# File yang sudah ada dilewati, kecuali kalimatnya atau suaranya berubah (dicatat di vo2/made.json).
# Jadi cukup jalankan lagi setiap naskah diubah: hanya kalimat yang berubah yang dibuat ulang.
#
# API key: diketik sekali (tidak terlihat di layar), lalu disimpan di Keychain Mac kamu.
# Key tidak pernah ditulis ke file, ke repo, atau ke riwayat Terminal.
import getpass, json, os, subprocess, sys, urllib.request, urllib.error

DIR = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(DIR, 'vo2')
CONF = os.path.join(DIR, 'vo2', 'voice.json')        # hanya nama + ID suara, bukan key
KC_SERVICE, KC_ACCOUNT = 'amnesia-elevenlabs', 'api-key'
MODEL = 'eleven_multilingual_v2'                     # bisa bahasa Indonesia
SETTINGS = {'stability': 0.5, 'similarity_boost': 0.75, 'style': 0.1, 'use_speaker_boost': True}
MADE = os.path.join(OUT, 'made.json')                # suara + kalimat tiap file, supaya tahu mana yang perlu dibuat ulang
API = 'https://api.elevenlabs.io/v1'


def keychain_get():
    r = subprocess.run(['security', 'find-generic-password', '-s', KC_SERVICE, '-a', KC_ACCOUNT, '-w'],
                       capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else ''


def keychain_set(key):
    # Perintah dikirim lewat stdin ke "security -i", jadi key tidak muncul di daftar proses.
    if not key.replace('_', '').replace('-', '').isalnum():
        return False
    r = subprocess.run(['security', '-i'], capture_output=True, text=True,
                       input=f'add-generic-password -U -s {KC_SERVICE} -a {KC_ACCOUNT} -w "{key}"\n')
    return r.returncode == 0 and keychain_get() == key


def get_key():
    key = keychain_get()
    if key:
        return key
    print('Tempel API key ElevenLabs kamu (elevenlabs.io → Developers → API Keys).')
    print('Tulisannya tidak akan terlihat saat ditempel. Tekan Enter setelahnya.')
    key = getpass.getpass('API key: ').strip()
    if not key:
        sys.exit('Tidak ada key. Berhenti.')
    if keychain_set(key):
        print('Key disimpan di Keychain (nama: amnesia-elevenlabs).')
    return key


def call(path, key, body=None):
    req = urllib.request.Request(API + path, headers={'xi-api-key': key, 'Content-Type': 'application/json'},
                                 data=json.dumps(body).encode() if body is not None else None)
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return r.read()
    except urllib.error.HTTPError as e:
        msg = e.read().decode(errors='replace')[:300]
        if e.code == 401:
            subprocess.run(['security', 'delete-generic-password', '-s', KC_SERVICE, '-a', KC_ACCOUNT],
                           capture_output=True)
            sys.exit('API key ditolak (401). Key lama dihapus dari Keychain; jalankan lagi dan tempel key yang benar.')
        sys.exit(f'ElevenLabs menolak permintaan ({e.code}): {msg}')
    except (urllib.error.URLError, OSError) as e:
        sys.exit(f'Tidak bisa menghubungi ElevenLabs ({e}). Cek koneksi internet, lalu jalankan lagi.')


def pick_voices(key, roles, conf):
    voices = json.loads(call('/voices', key))['voices']
    voices.sort(key=lambda v: v.get('name', ''))
    print('\nSuara yang ada di akun kamu (My Voices):')
    for i, v in enumerate(voices, 1):
        lab = v.get('labels') or {}
        info = ', '.join(x for x in [lab.get('gender'), lab.get('age'), lab.get('accent'), lab.get('description') or lab.get('descriptive')] if x)
        print(f'  {i:2}. {v["name"]}  ({info})')
    print('Mau suara lain? Tambahkan dulu dari Voice Library ke My Voices.')
    for role, desc in roles.items():
        print(f'\n[{role}] {desc}')
        while True:
            s = input(f'Nomor suara untuk "{role}": ').strip()
            if s.isdigit() and 1 <= int(s) <= len(voices):
                v = voices[int(s) - 1]
                conf[role] = {'voice_id': v['voice_id'], 'name': v['name']}
                print(f'Dipakai: {v["name"]}')
                break
    json.dump(conf, open(CONF, 'w'), indent=1)
    return conf


def load_conf():
    if not os.path.exists(CONF):
        return {}
    c = json.load(open(CONF))
    return {'gelap': c} if 'voice_id' in c else c      # file lama: satu suara saja


def main():
    args = sys.argv[1:]
    os.makedirs(OUT, exist_ok=True)
    data = json.load(open(os.path.join(DIR, 'vo-lines.json')))
    lines, roles = data['lines'], data['roles']
    key = get_key()
    conf = load_conf()
    if '--voice' in args:
        want = [a for a in args[args.index('--voice') + 1:] if a in roles] or list(roles)
        conf = pick_voices(key, {r: roles[r] for r in want}, conf)
    missing = {r: d for r, d in roles.items() if r not in conf}
    if missing:
        conf = pick_voices(key, missing, conf)
    langs = args[args.index('--lang') + 1].split(',') if '--lang' in args else ['en']
    todo = list(lines)
    if '--test' in args:
        todo = ['L1']
    redo = [a for a in args[args.index('--redo') + 1:] if a in lines] if '--redo' in args else []
    if redo:
        todo = redo
    record = json.load(open(MADE)) if os.path.exists(MADE) else {}
    made = 0
    for lid in todo:
        for lang in langs:
            text = lines[lid].get(lang)
            if not text:
                continue
            role = lines[lid].get('role', 'gelap')
            voice = conf[role]
            name = f'{lid}-{lang}.mp3'
            f = os.path.join(OUT, name)
            same = record.get(name) == {'voice_id': voice['voice_id'], 'text': text}
            if os.path.exists(f) and same and not redo and '--test' not in args:
                continue
            print(f'  {lid}-{lang} [{voice["name"]}]: {text}')
            audio = call(f'/text-to-speech/{voice["voice_id"]}?output_format=mp3_44100_128', key,
                         {'text': text, 'model_id': MODEL, 'voice_settings': SETTINGS})
            open(f, 'wb').write(audio)
            record[name] = {'voice_id': voice['voice_id'], 'text': text}
            json.dump(record, open(MADE, 'w'), indent=1, ensure_ascii=False)
            made += 1
    print(f'\nSelesai: {made} file baru di {OUT}')
    if '--no-open' not in args:
        subprocess.run(['open', OUT])


if __name__ == '__main__':
    main()
