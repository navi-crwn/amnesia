#!/usr/bin/env python3
"""Buat voiceover video Amnesia di Mac dengan suara bawaan macOS (perintah `say`), tanpa install apa pun.

Jalankan:  python3 ~/.amnesia/video/make_vo.py
Hasil:     ~/.amnesia/video/vo/vo-<60|30|15>-<en|id>.wav (6 file), satu kalimat per adegan,
           tiap kalimat mulai tepat di awal adegannya (waktu dari vo.json / script.js).

Suara: default "Samantha" (EN) dan "Damayanti" (ID). Suara yang lebih bagus bisa diunduh gratis di
System Settings > Accessibility > Spoken Content > System Voice > Manage Voices (misalnya "Ava (Premium)"),
lalu pakai:  VOICE_EN="Ava (Premium)" VOICE_ID="Damayanti (Enhanced)" python3 make_vo.py
Daftar suara yang terpasang:  say -v '?'
"""
import json, os, subprocess, sys, tempfile, wave

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "vo")
RATE = 44100
VOICES = {"en": os.environ.get("VOICE_EN", "Samantha"), "id": os.environ.get("VOICE_ID", "Damayanti")}
WPM = {"en": 175, "id": 165}          # kecepatan bicara normal (kata per menit)
LEAD = 0.25                            # kalimat mulai 0,25 detik setelah adegan dimulai
GAP = 0.35                             # sisa jeda minimal sebelum adegan berikutnya


def say(text, voice, wpm, path):
    subprocess.run(["say", "-v", voice, "-r", str(wpm), "--file-format=WAVE",
                    f"--data-format=LEI16@{RATE}", "-o", path, text], check=True)
    with wave.open(path) as w:
        pcm, ch = w.readframes(w.getnframes()), w.getnchannels()
        if ch == 2:   # ambil kanal kiri saja
            pcm = b"".join(pcm[i:i + 2] for i in range(0, len(pcm), 4))
        return pcm, w.getnframes() / w.getframerate()


def main():
    if sys.platform != "darwin":
        sys.exit("Jalankan di Mac (butuh perintah 'say').")
    data = json.load(open(os.path.join(HERE, "vo.json")))
    os.makedirs(OUT, exist_ok=True)
    tmp = tempfile.mkdtemp()
    for cut, scenes in data.items():
        for lang in ("en", "id"):
            total = scenes[-1]["start"] + scenes[-1]["dur"]
            buf = bytearray(int(total * RATE) * 2)          # sunyi, 16-bit mono
            for n, s in enumerate(scenes):
                room = s["dur"] - LEAD - GAP
                wpm = WPM[lang]
                pcm, secs = say(s[lang], VOICES[lang], wpm, os.path.join(tmp, "l.wav"))
                # terlalu panjang untuk adegannya? bicara sedikit lebih cepat (maks. +30%)
                while secs > room and wpm < WPM[lang] * 1.3:
                    wpm = int(wpm * 1.08)
                    pcm, secs = say(s[lang], VOICES[lang], wpm, os.path.join(tmp, "l.wav"))
                flag = "  <- masih terlalu panjang, kalimatnya perlu dipersingkat" if secs > s["dur"] - LEAD else ""
                print(f"{cut}s {lang} adegan {n + 1:2} {s['scene']:8} {secs:4.1f}/{s['dur']}s  {wpm} wpm{flag}")
                at = int((s["start"] + LEAD) * RATE) * 2
                pcm = pcm[: len(buf) - at]
                buf[at:at + len(pcm)] = pcm
            path = os.path.join(OUT, f"vo-{cut}-{lang}.wav")
            with wave.open(path, "wb") as w:
                w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE); w.writeframes(bytes(buf))
            print("  ->", path)
    print("\nSelesai. Dengarkan:  afplay ~/.amnesia/video/vo/vo-60-id.wav")


if __name__ == "__main__":
    main()
