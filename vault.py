#!/usr/bin/env python3
"""Amnesia Profile Vault — snapshot & restore profil app terenkripsi.

Cara kerja kunci (supaya "Simpan & Logout" tidak perlu ketik password):
- Saat vault dibuat: dibuat pasangan kunci RSA. Kunci publik disimpan biasa,
  kunci privat dikunci 7zz (AES-256) dengan password vault.
- Snapshot: profil dikunci 7zz dengan kunci acak, kunci acak itu dikunci kunci publik.
  -> tidak butuh password.
- Restore: password membuka kunci privat -> kunci acak -> profil.
Password tidak pernah disimpan, dan dikirim ke 7zz lewat stdin (tidak terlihat di `ps`).
v5.22: kunci privat tidak pernah ditulis ke disk saat restore (tetap di memori, ke openssl lewat pipe), hanya 1
perintah vault yang boleh jalan sekaligus (flock), dan sisa folder sementara dari proses yang terputus disapu.
"""
import fcntl, fnmatch, glob, hashlib, json, os, re, secrets, shutil, signal, subprocess, sys, time, unicodedata

HOME = os.environ.get("AMNESIA_HOME", os.path.expanduser("~"))
AMNESIA = os.path.join(HOME, ".amnesia")
VAULT = os.path.join(AMNESIA, "vault")
TMP = os.path.join(VAULT, ".tmp")
# 7-Zip: bawaan app (~/.amnesia/bin/7zz), kalau tidak ada pakai Homebrew
SEVENZ = os.environ.get("AMNESIA_7Z") or next(
    (p for p in (os.path.join(AMNESIA, "bin", "7zz"), "/opt/homebrew/bin/7zz", "/usr/local/bin/7zz")
     if os.path.exists(p)), "/opt/homebrew/bin/7zz")
OPENSSL = os.environ.get("AMNESIA_OPENSSL", "/usr/bin/openssl")
MAX_ATTEMPTS = 3
MIN_PASSWORD = 12

# App yang di-snapshot. Path relatif dari home, boleh pakai * ; yang tidak ada di Mac dilewati.
# quit=None: program Terminal (CLI), tidak perlu ditutup.
APPS = {
    "Chrome": {"quit": "Google Chrome",
               "paths": ["Library/Application Support/Google/Chrome"],
               # mode ringan (VAULT_LIGHT, default nyala): cache & model Chrome tidak disimpan, juga program
               # extension yang dari Web Store (Chrome mengunduh ulang lewat tombol Repair). Extension lain tetap
               # disimpan (tidak bisa diunduh ulang). Login (Cookies, Login Data, Local Storage, IndexedDB,
               # Local Extension Settings) selalu disimpan.
               "light": "chromium"},
    "Claude": {"quit": "Claude",
               "paths": ["Library/Application Support/Claude"]},
    "OpenCode": {"quit": "OpenCode",
                 "paths": [".local/share/opencode", ".config/opencode",
                           "Library/Application Support/ai.opencode.desktop"]},
    "Claude Code": {"quit": None, "paths": [".claude", ".claude.json"]},
    "CodeBuddy": {"quit": None, "paths": [".codebuddy"]},
    "Gemini CLI": {"quit": None, "paths": [".gemini"]},
    "Kimi": {"quit": None, "paths": [".kimi-work", ".kimi-webbridge"]},
    "GitHub CLI": {"quit": None, "paths": [".config/gh"]},
    "Antigravity": {"quit": "Antigravity",
                    "paths": ["Library/Application Support/Antigravity", ".antigravity-ide"]},
    "WhatsApp": {"quit": "WhatsApp",
                 "paths": ["Library/Containers/net.whatsapp.WhatsApp",
                           "Library/Group Containers/group.net.whatsapp*"]},
    "Windows App": {"quit": "Windows App",
                    "paths": ["Library/Containers/com.microsoft.rdc.macos",
                              "Library/Group Containers/*com.microsoft.rdc*"]},
    # v5.16: browser lain berbasis Chromium (profil seperti Chrome, bisa disimpan ringan). Hanya muncul kalau
    # datanya ada di Mac ini, dan saat pertama muncul TIDAK langsung ikut vault (kamu yang memilih).
    "Brave Browser": {"quit": "Brave Browser", "light": "chromium", "new": True,
                      "paths": ["Library/Application Support/BraveSoftware/Brave-Browser"]},
    "Microsoft Edge": {"quit": "Microsoft Edge", "light": "chromium", "new": True,
                       "paths": ["Library/Application Support/Microsoft Edge"]},
    "Vivaldi": {"quit": "Vivaldi", "light": "chromium", "new": True,
                "paths": ["Library/Application Support/Vivaldi"]},
    "Arc": {"quit": "Arc", "light": "chromium", "new": True,
            "paths": ["Library/Application Support/Arc/User Data"]},
    "Opera": {"quit": "Opera", "light": "chromium", "new": True,
              "paths": ["Library/Application Support/com.operasoftware.Opera"]},
    # v5.22: chat & app lain (Electron). Login-nya dikunci kunci Keychain "<Nama> Safe Storage", yang sudah dijaga
    # baris "keychain:* Safe Storage" di Keep List. Seperti browser di atas: TIDAK langsung ikut vault, kamu yang memilih.
    "Signal": {"quit": "Signal", "new": True,                  # Keychain: "Signal Safe Storage"
               "paths": ["Library/Application Support/Signal"]},
    "Session": {"quit": "Session", "new": True,                # Keychain: "Session Safe Storage"
                "paths": ["Library/Application Support/Session"]},
    "Element": {"quit": "Element", "new": True,
                "paths": ["Library/Application Support/Element"]},
    "Telegram": {"quit": "Telegram", "new": True,              # versi App Store + Telegram Desktop
                 "paths": ["Library/Group Containers/*.ru.keepcoder.Telegram",
                           "Library/Application Support/Telegram Desktop"]},
    "Obsidian": {"quit": "Obsidian", "new": True,              # pengaturan app; catatan (vault Obsidian) ada di folder kamu sendiri
                 "paths": ["Library/Application Support/obsidian"]},
    "Notion": {"quit": "Notion", "new": True,
               "paths": ["Library/Application Support/Notion"]},
    "Zoom": {"quit": "zoom.us", "new": True,
             "paths": ["Library/Application Support/zoom.us"]},
    "Bitwarden": {"quit": "Bitwarden", "new": True,
                  "paths": ["Library/Application Support/Bitwarden", "Library/Containers/com.bitwarden.desktop"]},
}
# Snapshot ringan untuk browser berbasis Chromium: cache & model tidak disimpan, juga program extension yang
# dari Web Store (browser mengunduh ulang lewat tombol Repair). Extension lain tetap disimpan (tidak bisa diunduh
# ulang). Login (Cookies, Login Data, Local Storage, IndexedDB, Local Extension Settings) selalu disimpan.
CHROMIUM_LIGHT = ["Extensions", "ScriptCache", "optimization_guide_model_store", "OptGuideOnDeviceModel",
                  "OnDeviceHeadSuggestModel", "WasmTtsEngine", "Safe Browsing", "screen_ai",
                  "GraphiteDawnCache", "BrowserMetrics", "BrowserMetrics-spare.pma"]
# Cache tidak perlu disimpan (besar, dibuat ulang otomatis oleh app)
EXCLUDE = ["Cache", "Code Cache", "GPUCache", "CacheStorage", "ShaderCache", "GrShaderCache",
           "DawnCache", "DawnGraphiteCache", "DawnWebGPUCache", "component_crx_cache",
           "Crashpad", "vm_bundles", "CachedData", "CachedExtensionVSIXs", ".DS_Store"]

# Restore tidak menghapus data app yang ada sekarang: dipindah ke sini dulu (hanya restore terakhir).
# Ada di Library/Caches, jadi ikut dibersihkan di logout berikutnya (tidak jadi jejak permanen).
# v5.23: + catatan .undo.json (untuk "Kembalikan data sebelum restore"), dan clean.sh membuangnya setelah 3 hari
# kalau ternyata lolos dari logout (mis. Library/Caches di Keep List).
BEFORE_RESTORE = os.path.join(HOME, "Library", "Caches", "Amnesia", "before-restore")
F_UNDO = os.path.join(BEFORE_RESTORE, ".undo.json")
# v5.23: data hasil restore yang disingkirkan oleh "Kembalikan data sebelum restore" (tidak langsung dihapus)
AFTER_RESTORE = os.path.join(HOME, "Library", "Caches", "Amnesia", "after-restore")
CLAUDE_CODE = [".claude", ".claude.json", ".claude.json.backup"]

F_PUB = os.path.join(VAULT, "public.pem")
F_APPDIR = os.path.join(VAULT, "apps")          # v5.10: 1 arsip per app (apps/<id>.7z + .key), tidak saling menimpa
F_STAGE = os.path.join(VAULT, ".restore")       # restore dibongkar di sini dulu, baru dipindah (aman kalau dibatalkan)
F_PRIV = os.path.join(VAULT, "private.7z")
F_SNAP = os.path.join(VAULT, "profiles.7z")      # format lama (v5.9): semua app dalam 1 arsip
F_SNAPKEY = os.path.join(VAULT, "profiles.key")
F_MANIFEST = os.path.join(VAULT, "manifest.json")
F_KEYS = os.path.join(VAULT, "keys.7z")          # kunci Keychain "... Safe Storage" (untuk Pindah Mac)
F_KEYSKEY = os.path.join(VAULT, "keys.key")
SECURITY = "/usr/bin/security"
F_ATTEMPTS = os.path.join(VAULT, "attempts.json")
F_PANIC = os.path.join(VAULT, "panic.json")
F_LOG = os.path.join(AMNESIA, "doomsday.log")
F_LOCK = os.path.join(VAULT, ".lock")
# v5.22: app tambahan yang kamu pilih sendiri dari "Ditemukan di Mac ini" (deteksi otomatis di app)
F_CUSTOM = os.path.join(AMNESIA, "vault_apps.json")
KEEPLOCK = os.path.join(AMNESIA, "keeplock.sh")
MIN_KEEP_PASSWORD = 8


def _lang():
    try:
        with open(os.path.join(AMNESIA, "settings.conf")) as f:
            return [l.strip()[5:] for l in f if l.startswith("LANG=")][-1]
    except (OSError, IndexError):
        return "en"


def history(kind, data=""):
    """v5.16: 1 baris di ~/.amnesia/history.log (halaman Riwayat). Hanya waktu, jenis dan nama app, tanpa nama file."""
    try:
        with open(os.path.join(AMNESIA, "history.log"), "a") as f:
            f.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')}\t{kind}\t{data}\n")
    except OSError:
        pass


def _setting(key, default=""):
    try:
        with open(os.path.join(AMNESIA, "settings.conf")) as f:
            vals = [l.rstrip("\n")[len(key) + 1:] for l in f if l.startswith(key + "=")]
        return vals[-1] if vals else default
    except OSError:
        return default


def keep_dir():
    """Folder Keep pilihan user (KEEP_DIR, default ~/Keep). '~/' = folder home."""
    d = _setting("KEEP_DIR", "~/Keep")
    if d.startswith("~/"):
        d = os.path.join(HOME, d[2:])
    if not os.path.isabs(d):
        d = os.path.join(HOME, "Keep")
    d = os.path.normpath(d)
    # jangan pernah mengosongkan home, ~/.amnesia, atau folder sistem
    bad = {os.path.normpath(HOME), os.path.normpath(AMNESIA), "/", "/Users", "/Volumes", "/Applications"}
    if d in bad or d.startswith(os.path.normpath(AMNESIA) + os.sep) or d.count(os.sep) < 2:
        d = os.path.join(HOME, "Keep")
    return d


def T(en, id_):
    """Pesan sesuai bahasa di Pengaturan (LANG=en|id)."""
    return id_ if _lang() == "id" else en


# ---------------- v5.23: Keep List (sama seperti clean.sh), supaya restore tidak menimpa yang disimpan ----------------
class KeepRules:
    """Pola Keep List (keep.conf, lalu keep.conf.last, lalu keep.example.conf) + folder Keep. Cocok seperti [[ == ]] di clean.sh:
    * juga melewati '/'. Claude di Keep List = Claude Code ikut disimpan (sama dengan clean.sh)."""

    def __init__(self):
        # v5.24: keep.conf hilang atau tidak bisa dibaca -> salinan terakhir yang baik (keep.conf.last), baru
        # keep.example.conf. Dulu langsung contoh (atau kosong kalau gagal dibaca), jadi restore bisa menimpa
        # yang sebenarnya disimpan.
        # Ada Keep List (atau salinannya) tapi tidak ada yang bisa dibaca: berhenti, jangan pakai contoh (yang tidak
        # menyimpan barang kamu). Ragu = tidak menimpa apa pun.
        lines = None
        seen = False
        for name in ("keep.conf", "keep.conf.last", "keep.example.conf"):
            conf = os.path.join(AMNESIA, name)
            if not os.path.lexists(conf):
                continue
            if name == "keep.example.conf" and seen:
                break
            seen = True
            try:
                with open(conf, encoding="utf-8", errors="replace") as f:
                    lines = f.read().splitlines()
                break
            except OSError:
                continue
        if lines is None and seen:
            raise VaultError(T("The Keep List could not be read, so nothing was changed. Open Keep List to check it.",
                               "Keep List tidak bisa dibaca, jadi tidak ada yang diubah. Buka Keep List untuk mengeceknya."))
        pats = []
        for line in lines or []:
            line = line.strip()
            if not line or line.startswith("#") or line.startswith("keychain:") or line.startswith("app:"):
                continue
            line = line[2:] if line.startswith("~/") else line
            for form in ("NFC", "NFD"):          # nama dari Finder/backup lama bisa beda bentuk Unicode
                x = unicodedata.normalize(form, line)
                if x not in pats:
                    pats.append(x)
        self.pats = pats
        kd = keep_dir()
        self.keep_rel = os.path.relpath(kd, HOME) if kd.startswith(os.path.normpath(HOME) + os.sep) else ""
        if self.kept("Library/Application Support/Claude"):
            self.pats += [c for c in CLAUDE_CODE if not self.kept(c)]

    def kept(self, rel):
        if self.keep_rel and (rel == self.keep_rel or rel.startswith(self.keep_rel + "/")):
            return True
        return any(fnmatch.fnmatchcase(rel, p) for p in self.pats)

    def kept_inside(self, rel):
        """Ada pola Keep yang lebih dalam dari path ini? (seperti has_kept_inside di clean.sh)"""
        n = rel.count("/")
        if self.keep_rel.startswith(rel + "/"):
            return True
        for p in self.pats:
            if p.count("/") > n and fnmatch.fnmatchcase(rel, "/".join(p.split("/")[:n + 1])):
                return True
        return False

    def held(self, rel):
        """Item di dalam path (folder) ini yang ada di Keep List, yang memang ada di disk sekarang."""
        out = []
        full = os.path.join(HOME, rel)
        if not os.path.isdir(full) or os.path.islink(full) or not self.kept_inside(rel):
            return out
        for x in sorted(os.listdir(full)):
            r = rel + "/" + x
            if self.kept(r):
                out.append(r)
            else:
                out += self.held(r)
        return out


class VaultError(Exception):
    pass


# ---------------- util ----------------
def _read_json(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def _write_json(path, data):
    tmp = path + ".new"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2)
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)


def _7z(args, password, cwd=None):
    """Jalankan 7zz; password lewat stdin (2x untuk 'a' karena 7zz minta konfirmasi)."""
    stdin = (password + "\n") * 2
    return subprocess.run([SEVENZ] + args, input=stdin, capture_output=True, text=True, cwd=cwd)


def _progress(pct, step=""):
    """Kemajuan untuk app (dibaca dari stderr): 'PROGRESS 42 save 2/3 Chrome'
    (persen total, tahap, urutan, nama app)."""
    sys.stderr.write(f"PROGRESS {int(pct)} {step}".rstrip() + "\n")
    sys.stderr.flush()


_CHILD = [None]      # 7zz yang sedang jalan (dihentikan kalau kamu menekan Batal)


def _on_cancel(sig, frame):
    """Tombol Batal di app mengirim SIGTERM: hentikan 7zz, lalu berhenti dengan rapi."""
    p = _CHILD[0]
    if p is not None and p.poll() is None:
        p.kill()
    raise VaultError("CANCELLED")


class _no_cancel:
    """Bagian yang tidak boleh terpotong di tengah (memindahkan file): Batal ditunda sampai selesai."""
    def __enter__(self):
        if hasattr(signal, "pthread_sigmask"):
            signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGTERM})

    def __exit__(self, *a):
        if hasattr(signal, "pthread_sigmask"):
            signal.pthread_sigmask(signal.SIG_UNBLOCK, {signal.SIGTERM})


def _7z_progress(args, password, cwd=None, start=0, end=100, step=""):
    """Seperti _7z, tapi persen dari 7zz diteruskan ke app (start..end)."""
    p = subprocess.Popen([SEVENZ] + args + ["-bso0", "-bsp2", "-bse2"], stdin=subprocess.PIPE,
                         stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, cwd=cwd)
    _CHILD[0] = p
    p.stdin.write(((password + "\n") * 2).encode())
    p.stdin.close()
    err, last = b"", -1
    while True:
        chunk = os.read(p.stderr.fileno(), 4096)
        if not chunk:
            break
        err = (err + chunk)[-20000:]
        found = re.findall(rb"(\d{1,3})%", chunk)
        if found:
            pct = start + (end - start) * min(int(found[-1]), 100) / 100
            if int(pct) != last:
                last = int(pct)
                _progress(pct, step)
    p.wait()
    _CHILD[0] = None
    text = re.sub(r"\s*\d{1,3}%[^\n\x08]*", "", err.decode(errors="replace").replace("\x08", ""))
    return subprocess.CompletedProcess(p.args, p.returncode, "", text)


def _clean_tmp():
    shutil.rmtree(TMP, ignore_errors=True)


_LOCK_FD = [None]


def _lock_and_sweep(wait=20):
    """v5.22: hanya 1 perintah vault yang mengubah sesuatu boleh jalan sekaligus (mis. snapshot otomatis saat logout
    dan restore dari app). Setelah kunci didapat, sisa proses yang terputus (crash, mati listrik) disapu: folder
    sementara (.tmp, .restore) dan file setengah jadi (*.new)."""
    if not os.path.isdir(VAULT) or _LOCK_FD[0] is not None:
        return
    fd = os.open(F_LOCK, os.O_CREAT | os.O_RDWR, 0o600)
    end = time.time() + wait
    while True:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            break
        except OSError:
            if time.time() >= end:
                os.close(fd)
                raise VaultError(T("Another vault job is still running (for example a snapshot). Wait until it's done, then try again.",
                                   "Masih ada proses vault lain yang berjalan (misalnya snapshot). Tunggu sampai selesai, lalu coba lagi."))
            time.sleep(0.5)
    _LOCK_FD[0] = fd
    for d in (TMP, F_STAGE):
        shutil.rmtree(d, ignore_errors=True)
    for f in glob.glob(os.path.join(glob.escape(F_APPDIR), "*.new")) + [F_PRIV + ".new", F_KEYS + ".new", F_KEYSKEY + ".new"]:
        try:
            os.remove(f)
        except OSError:
            pass


def _private_pem(password):
    """v5.22: kunci privat langsung dari 7zz ke memori (-so = ke stdout), tidak pernah ke disk. None = gagal."""
    r = subprocess.run([SEVENZ, "e", "-so", "-y", F_PRIV, "private.pem"], input=((password + "\n") * 2).encode(),
                       capture_output=True)
    if r.returncode != 0 or b"PRIVATE KEY" not in r.stdout:
        return None, r.stderr.decode(errors="replace")
    return r.stdout, ""


def _rsa_decrypt(pem, keyfile):
    """Buka 1 kunci acak dengan kunci privat yang ada di memori. Kunci privat ke openssl lewat pipe (/dev/fd)."""
    rfd, wfd = os.pipe()
    try:
        os.write(wfd, pem)                    # kunci RSA-4096 ±3 KB, jauh di bawah batas buffer pipe
        os.close(wfd)
        wfd = None
        return subprocess.run([OPENSSL, "pkeyutl", "-decrypt", "-inkey", f"/dev/fd/{rfd}",
                               "-pkeyopt", "rsa_padding_mode:oaep", "-in", keyfile],
                              check=True, capture_output=True, pass_fds=(rfd,)).stdout
    finally:
        os.close(rfd)
        if wfd is not None:
            os.close(wfd)


def _new_tmp():
    _clean_tmp()
    os.makedirs(TMP, mode=0o700)
    return TMP


def _hash(word, salt):
    return hashlib.pbkdf2_hmac("sha512", word.encode(), bytes.fromhex(salt), 200_000).hex()


# ---------------- status ----------------
def exists():
    return os.path.exists(F_PRIV) and os.path.exists(F_PUB)


def vault_folders():
    """Folder pilihan kamu yang ikut disimpan di vault (VAULT_FOLDERS, relatif dari home)."""
    out = []
    for x in _setting("VAULT_FOLDERS", "").split(","):
        x = x.strip().strip("/")
        parts = x.split("/")
        if x and not os.path.isabs(x) and ".." not in parts and parts[0] not in (".amnesia", ".Trash"):
            out.append(x)
    return out


def _safe_rel(x):
    """Path relatif dari home yang boleh dipakai app tambahan (bukan ~/.amnesia, Trash, Keep, atau '..')."""
    parts = x.split("/")
    return bool(x) and not os.path.isabs(x) and ".." not in parts and parts[0] not in (".amnesia", ".amnesia-trash", ".Trash") \
        and not os.path.join(HOME, x).startswith(keep_dir() + os.sep) and "," not in x


def custom_apps():
    """v5.22: app tambahan yang kamu centang sendiri: {nama: {"quit": ..., "paths": [...], "custom": True}}."""
    out = {}
    raw = _read_json(F_CUSTOM, [])
    for a in raw if isinstance(raw, list) else []:
        if not isinstance(a, dict):
            continue
        name, paths = str(a.get("name", "")).strip(), [str(p).strip("/") for p in a.get("paths", []) if isinstance(p, str)]
        paths = [p for p in paths if _safe_rel(p)]
        if not name or name in APPS or name.startswith("~/") or not paths:
            continue
        quit_name = a.get("quit")
        out[name] = {"quit": quit_name if isinstance(quit_name, str) and quit_name else None, "paths": paths, "custom": True}
    return out


def add_custom(entry):
    """Tambah/ganti 1 app tambahan. entry = {"name", "quit", "paths"}."""
    name = str(entry.get("name", "")).strip()
    paths = [str(p).strip("/") for p in entry.get("paths", []) if isinstance(p, str)]
    if not name or name in APPS or name.startswith("~/") or "\n" in name or "," in name:   # "," = pemisah VAULT_SKIP
        raise VaultError(T("This name can't be used.", "Nama ini tidak bisa dipakai."))
    bad = [p for p in paths if not _safe_rel(p)]
    if not paths or bad:
        raise VaultError(T("These folders can't go in the vault: ", "Folder ini tidak bisa masuk vault: ") + ", ".join(bad or ["-"]))
    raw = [a for a in _read_json(F_CUSTOM, []) if isinstance(a, dict) and a.get("name") != name]
    raw.append({"name": name, "quit": entry.get("quit") or None, "paths": paths})
    os.makedirs(AMNESIA, exist_ok=True)
    _write_json(F_CUSTOM, raw)


def remove_custom(name):
    """Keluarkan app tambahan dari vault. Snapshot-nya ikut dihapus (supaya tidak ada sisa yang tidak terlihat)."""
    raw = [a for a in _read_json(F_CUSTOM, []) if isinstance(a, dict) and a.get("name") != name]
    _write_json(F_CUSTOM, raw)
    if exists():
        delete_snapshot([name])


def items():
    """Semua yang bisa disimpan: app di APPS + app tambahan (v5.22) + folder pilihan (nama '~/<folder>')."""
    d = dict(APPS)
    d.update(custom_apps())
    for f in vault_folders():
        d["~/" + f] = {"quit": None, "paths": [f], "folder": True}
    return d


def _slug(name):
    return hashlib.sha1(name.encode()).hexdigest()[:16]


def _app_files(name):
    base = os.path.join(F_APPDIR, _slug(name))
    return base + ".7z", base + ".key"


def _summary(per):
    """Ringkasan untuk app: daftar app, waktu snapshot terbaru, total ukuran."""
    names = [n for n in items() if n in per] + sorted(n for n in per if n not in items())
    times = [v.get("time") or "" for v in per.values()]
    # v5.25 (item 192): ukuran dari arsip yang ada (byte persis). Dulu dibulatkan ke 0,1 MB, jadi snapshot kecil
    # seperti GitHub CLI (beberapa KB) tampil "0 KB".
    for n, v in per.items():
        if not v.get("legacy"):
            arc = _app_files(n)[0]
            if os.path.exists(arc):
                v["size_mb"] = round(os.path.getsize(arc) / 1048576, 6)
    size = sum(v.get("size_mb") or 0 for v in per.values() if not v.get("legacy"))
    if any(v.get("legacy") for v in per.values()) and os.path.exists(F_SNAP):
        size += os.path.getsize(F_SNAP) / 1048576
    return {"apps": names, "time": max(times) if times else "", "size_mb": round(size, 6), "per_app": per}


def _load_manifest():
    """Manifest v5.10 ({per_app: {...}}). Snapshot lama (v5.9, 1 arsip) dibaca sebagai 'legacy'."""
    m = _read_json(F_MANIFEST, {})
    per = m.get("per_app")
    if per is None:
        per = {}
        if os.path.exists(F_SNAP):
            per = {a: {"time": m.get("time", ""), "size_mb": None, "legacy": True} for a in m.get("apps", [])}
    return per


def _save_manifest(per):
    if per:
        _write_json(F_MANIFEST, _summary(per))
    elif os.path.exists(F_MANIFEST):
        os.remove(F_MANIFEST)


def manifest():
    per = _load_manifest()
    return _summary(per) if per else {}


def attempts():
    return _read_json(F_ATTEMPTS, {"failed": 0})["failed"]


def app_paths(name):
    """Path (relatif dari home) milik app/folder yang benar-benar ada di Mac ini."""
    pats = items().get(name, {}).get("paths", [])
    return [os.path.relpath(f, HOME) for p in pats
            for f in sorted(glob.glob(os.path.join(glob.escape(HOME), p)))]


def installed_apps():
    """App (dan folder pilihan) yang punya data di Mac ini."""
    return [n for n in items() if app_paths(n)]


def skipped_apps():
    """App yang kamu matikan di halaman Profile Vault (VAULT_SKIP di settings.conf).
    v5.16: app baru (browser Chromium lain) ikut dimatikan sampai kamu memilihnya (VAULT_PICK)."""
    skip = [x for x in _setting("VAULT_SKIP", "").split(",") if x]
    pick = [x for x in _setting("VAULT_PICK", "").split(",") if x]
    return skip + [n for n, v in APPS.items() if v.get("new") and n not in pick and n not in skip]


def chosen_apps():
    skip = skipped_apps()
    return [n for n in installed_apps() if n not in skip]


def _size(paths, light=(), exact=()):
    """Ukuran (byte) tanpa cache, sama seperti yang masuk snapshot (mode ringan ikut dihitung)."""
    skip = set(EXCLUDE) | set(light)
    skip_full = {os.path.join(HOME, x) for x in exact}
    total = 0
    for p in paths:
        full = os.path.join(HOME, p)
        if os.path.islink(full) or os.path.isfile(full):
            total += os.lstat(full).st_size
            continue
        for root, dirs, files in os.walk(full):
            dirs[:] = [d for d in dirs if d not in skip and os.path.join(root, d) not in skip_full]
            for f in files:
                if f not in skip:
                    try:
                        total += os.lstat(os.path.join(root, f)).st_size
                    except OSError:
                        pass
    return total


def sizes():
    """Ukuran tiap app (MB), untuk ditampilkan sebelum snapshot."""
    return {n: round(_size(app_paths(n), *_light_skip(n)) / 1048576, 6) for n in installed_apps()}   # v5.25 (192)


# ---------------- buat vault ----------------
def create(password, panic_word="", panic_full=False):
    if len(password) < MIN_PASSWORD:
        raise VaultError(T(f"The password needs at least {MIN_PASSWORD} characters.", f"Password minimal {MIN_PASSWORD} karakter."))
    if panic_word and panic_word == password:
        raise VaultError(T("The panic word can't be the same as the password.", "Kata panik tidak boleh sama dengan password."))
    if not os.path.exists(SEVENZ):
        raise VaultError(T(f"7zz not found at {SEVENZ}. Run: brew install sevenzip", f"7zz tidak ditemukan di {SEVENZ}. Jalankan: brew install sevenzip"))
    os.makedirs(VAULT, mode=0o700, exist_ok=True)
    tmp = _new_tmp()
    try:
        priv = os.path.join(tmp, "private.pem")
        # ponytail: kunci privat sesaat ada di disk (folder 700) sebelum dikunci 7zz
        subprocess.run([OPENSSL, "genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:4096",
                        "-out", priv], check=True, capture_output=True)
        subprocess.run([OPENSSL, "pkey", "-in", priv, "-pubout", "-out", F_PUB],
                       check=True, capture_output=True)
        if os.path.exists(F_PRIV):
            os.remove(F_PRIV)
        r = _7z(["a", "-t7z", "-mhe=on", "-p", F_PRIV, "private.pem"], password, cwd=tmp)
        if r.returncode != 0:
            raise VaultError(T("Couldn't lock the private key:\n", "Gagal mengunci kunci privat:\n") + r.stderr[-300:])
    finally:
        _clean_tmp()
    _write_json(F_ATTEMPTS, {"failed": 0})
    set_panic(panic_word, panic_full)


def set_panic(word, full=False):
    if not word:
        if os.path.exists(F_PANIC):
            os.remove(F_PANIC)
        return
    salt = secrets.token_hex(16)
    _write_json(F_PANIC, {"salt": salt, "hash": _hash(word, salt), "full": bool(full)})


# ---------------- snapshot (tanpa password) ----------------
def _is_running(app):
    """App GUI sedang jalan? (tanpa membukanya)"""
    try:
        r = subprocess.run(["osascript", "-e", f'application "{app}" is running'],
                           capture_output=True, text=True, timeout=10)
        return r.stdout.strip() == "true"
    except (OSError, subprocess.TimeoutExpired):
        return False


def quit_apps(names):
    """Tutup app dengan sopan dulu (data tersimpan), baru paksa. Mencegah profil corrupt.
    Hasil (v5.21): app yang tadi sedang jalan, supaya bisa dibuka lagi setelah restore."""
    if not shutil.which("osascript") or os.environ.get("AMNESIA_HOME"):   # bukan macOS / home palsu (tes, screenshot)
        return []
    # v5.21: lewat items(), karena folder pilihan ("~/<folder>") tidak ada di APPS
    gui = [q for q in (items().get(n, {}).get("quit") for n in names) if q]
    if not gui:
        return []
    running = [q for q in gui if _is_running(q)]
    for q in gui:
        subprocess.run(["osascript", "-e", f'quit app "{q}"'], capture_output=True)
    time.sleep(3)
    for q in gui:
        subprocess.run(["killall", q], capture_output=True)
    time.sleep(1)
    return running


def reopen_apps(apps):
    """v5.21: buka lagi app yang ditutup untuk restore (sekarang dengan profil yang sudah kembali)."""
    if not apps or not shutil.which("open") or os.environ.get("AMNESIA_HOME"):
        return
    for q in apps:
        try:
            subprocess.run(["open", "-a", q], capture_output=True, timeout=15)
        except (OSError, subprocess.TimeoutExpired):
            pass


WEBSTORE = "clients2.google.com/service/update2/crx"


def _webstore_ext(ext_dir, settings):
    """Extension ini dari Chrome Web Store (bisa diunduh ulang)?"""
    s = settings.get(os.path.basename(ext_dir)) or {}
    if s.get("from_webstore") is True or WEBSTORE in str((s.get("manifest") or {}).get("update_url", "")):
        return True
    for m in glob.glob(os.path.join(glob.escape(ext_dir), "*", "manifest.json")):
        try:
            with open(m, encoding="utf-8") as f:
                if WEBSTORE in str(json.load(f).get("update_url", "")):
                    return True
        except (OSError, ValueError, AttributeError):
            pass
    return False


def light_apps():
    """App yang bisa disimpan ringan (browser berbasis Chromium)."""
    return [n for n, v in items().items() if v.get("light")]


def full_apps():
    """v5.16: app yang disimpan LENGKAP (saklar "Ringan" dimatikan di Profile Vault, VAULT_FULL).
    VAULT_LIGHT=0 dari versi lama = semua disimpan lengkap."""
    if _setting("VAULT_LIGHT", "1") == "0":
        return light_apps()
    return [x for x in _setting("VAULT_FULL", "").split(",") if x]


def _light_skip(n):
    """Mode ringan: (nama folder yang dilewati di mana saja, path persis yang dilewati).
    Program extension dari Web Store dilewati; extension lain tetap ikut snapshot."""
    light = CHROMIUM_LIGHT if items().get(n, {}).get("light") else []
    if not light or n in full_apps():
        return [], []
    exact = []
    if "Extensions" in light:
        for base in app_paths(n):
            for ext in glob.glob(os.path.join(glob.escape(os.path.join(HOME, base)), "*", "Extensions")):
                settings = {}
                for f in ("Preferences", "Secure Preferences"):
                    try:
                        with open(os.path.join(os.path.dirname(ext), f), encoding="utf-8") as fh:
                            for k, v in ((json.load(fh).get("extensions") or {}).get("settings") or {}).items():
                                if isinstance(v, dict):
                                    settings.setdefault(k, {}).update(v)
                    except (OSError, ValueError, AttributeError):
                        pass
                for eid in sorted(os.listdir(ext)):
                    if _webstore_ext(os.path.join(ext, eid), settings):
                        exact.append(os.path.relpath(os.path.join(ext, eid), HOME))
    return [x for x in light if x != "Extensions"], exact


def _newest(n):
    """Waktu perubahan terbaru di data app ini (untuk snapshot otomatis: lewati app yang tidak berubah)."""
    t = 0
    for rel in app_paths(n):
        full = os.path.join(HOME, rel)
        try:
            t = max(t, os.lstat(full).st_mtime)
        except OSError:
            continue
        for root, dirs, files in os.walk(full):
            for x in dirs + files:
                try:
                    t = max(t, os.lstat(os.path.join(root, x)).st_mtime)
                except OSError:
                    pass
    return t


def snapshot(names=None, changed=False, reopen=False):
    """Simpan app ke vault, 1 arsip per app. Tidak butuh password.
    Hanya app yang dipilih yang diperbarui; snapshot app lain tetap ada.
    changed=True (snapshot otomatis saat logout): app yang tidak berubah sejak snapshot terakhirnya dilewati.
    reopen=True (v5.23, tombol Snapshot Sekarang): app yang tadi sedang jalan dibuka lagi setelah selesai, juga kalau
    gagal atau dibatalkan. Tidak untuk Simpan & Logout dan snapshot otomatis saat logout."""
    if not exists():
        raise VaultError(T("No vault yet.", "Vault belum dibuat."))
    names = [n for n in (names or chosen_apps()) if app_paths(n)]
    if changed:
        per0 = _load_manifest()
        names = [n for n in names if not per0.get(n, {}).get("ts") or _newest(n) > per0[n]["ts"]
                 or not os.path.exists(_app_files(n)[0])]
        if not names:
            return []
    if not names:
        raise VaultError(T("There is no app data to snapshot.", "Tidak ada data app yang bisa di-snapshot."))
    weight = {n: max(_size(app_paths(n), *_light_skip(n)), 1) for n in names}
    total = sum(weight.values())
    _progress(0, f"quit 1/{len(names)} {names[0]}")
    was_running = quit_apps(names)
    try:
        return _snapshot_all(names, weight, total, changed)
    finally:
        if reopen:
            reopen_apps(was_running)


def _snapshot_all(names, weight, total, changed):
    os.makedirs(F_APPDIR, mode=0o700, exist_ok=True)
    per = _load_manifest()
    done, saved = 0, []
    for i, n in enumerate(names):
        arc, keyf = _app_files(n)
        new_arc, new_key = arc + ".new", keyf + ".new"
        try:
            for f in (new_arc, new_key):
                if os.path.exists(f):
                    os.remove(f)
            key = secrets.token_hex(32)
            start, end = 2 + 96 * done / total, 2 + 96 * (done + weight[n]) / total
            step = f"save {i + 1}/{len(names)} {n}"
            _progress(start, step)
            light, exact = _light_skip(n)
            ts = time.time()
            args = (["a", "-t7z", "-mx=3", "-mhe=on", "-p", new_arc] + app_paths(n)
                    + [f"-xr!{x}" for x in EXCLUDE + light] + [f"-x!{x}" for x in exact])
            r = _7z_progress(args, key, cwd=HOME, start=start, end=end, step=step)
            if r.returncode not in (0, 1):          # 1 = warning (mis. file terkunci), arsip tetap jadi
                raise VaultError(T(f"Snapshot of {n} failed:\n", f"Snapshot {n} gagal:\n") + r.stderr[-300:])
            subprocess.run([OPENSSL, "pkeyutl", "-encrypt", "-pubin", "-inkey", F_PUB,
                            "-pkeyopt", "rsa_padding_mode:oaep", "-out", new_key],
                           input=key.encode(), check=True, capture_output=True)
            with _no_cancel():                       # arsip & kuncinya selalu diganti berpasangan
                os.replace(new_arc, arc)
                os.replace(new_key, keyf)
                per[n] = {"time": time.strftime("%Y-%m-%d %H:%M"), "ts": ts, "light": bool(exact),
                          "size_mb": round(os.path.getsize(arc) / 1048576, 6)}      # v5.25 (192): tidak dibulatkan ke 0,1 MB
                _save_manifest(per)
        finally:
            for f in (new_arc, new_key):
                if os.path.exists(f):
                    os.remove(f)
        done += weight[n]
        saved.append(n)
    _drop_legacy(per)
    if saved:
        history("snapshot", ("auto:" if changed else "") + ", ".join(saved))
    return saved


def _drop_legacy(per):
    """Arsip lama (v5.9) dihapus begitu semua app di dalamnya sudah punya snapshot sendiri."""
    if os.path.exists(F_SNAP) and not any(v.get("legacy") for v in per.values()):
        for f in (F_SNAP, F_SNAPKEY):
            if os.path.exists(f):
                os.remove(f)


def delete_snapshot(names=None):
    """Hapus snapshot. names = hanya app/folder itu; kosong = semua.
    Vault, password, kata panik dan kunci Pindah Mac tetap ada."""
    if names:
        per = _load_manifest()
        for n in names:
            for f in _app_files(n):
                if os.path.exists(f):
                    os.remove(f)
            per.pop(n, None)
        _drop_legacy(per)
        _save_manifest(per)
        return
    shutil.rmtree(F_APPDIR, ignore_errors=True)
    shutil.rmtree(F_STAGE, ignore_errors=True)
    for f in (F_SNAP, F_SNAPKEY, F_MANIFEST):
        if os.path.exists(f):
            os.remove(f)


# ---------------- buka & restore (butuh password) ----------------
def doomsday(full=False, reason=""):
    """Hapus seluruh vault. full=True juga mengosongkan folder Keep."""
    shutil.rmtree(VAULT, ignore_errors=True)
    # ponytail: tanpa overwrite 3x — di SSD/APFS itu tidak menjamin apa pun;
    # isi vault terenkripsi, jadi tanpa password datanya tetap tidak terbaca.
    if full:
        keep = keep_dir()
        # v5.22: Brankas ditutup dan Kunci Keep dibuka dulu, kalau tidak isinya tidak bisa dihapus
        if os.path.exists(KEEPLOCK):
            for c in ("box-detach", "unlock"):
                try:
                    subprocess.run(["/bin/bash", KEEPLOCK, c], capture_output=True, timeout=60)
                except (OSError, subprocess.TimeoutExpired):
                    pass
        for x in os.listdir(keep) if os.path.isdir(keep) else []:
            p = os.path.join(keep, x)
            try:
                if os.path.isdir(p) and not os.path.islink(p):
                    shutil.rmtree(p, ignore_errors=True)
                else:
                    os.remove(p)
            except OSError:
                pass
    with open(F_LOG, "a") as f:
        f.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} doomsday ({reason}){' + Keep' if full else ''}\n")
    history("doomsday", "keep" if full else "")


def _unlock_many(password, keyfiles):
    """Buka kunci acak dari tiap keyfile (None kalau file-nya tidak ada). Menangani kata panik & hitungan salah."""
    if not exists():
        raise VaultError(T("No vault yet.", "Vault belum dibuat."))
    panic = _read_json(F_PANIC, None)
    if panic and secrets.compare_digest(_hash(password, panic["salt"]), panic["hash"]):
        doomsday(panic.get("full", False), "kata panik")
        raise VaultError("DOOMSDAY")
    pem = None
    try:
        pem, err = _private_pem(password)
        if pem is None:
            if "password" not in err.lower():
                raise VaultError(T("The vault can't be opened (not a password problem):\n", "Vault tidak bisa dibuka (bukan karena password):\n") + err[-300:])
            failed = attempts() + 1
            if failed >= MAX_ATTEMPTS:
                doomsday(False, f"{failed}x password salah")
                raise VaultError("DOOMSDAY")
            _write_json(F_ATTEMPTS, {"failed": failed})
            left = MAX_ATTEMPTS - failed
            if left == 1:
                raise VaultError(T("Wrong password. Tries left: 1. LAST TRY: one more wrong password DELETES the vault "
                                   "for good. Stop and check your password notes first.",
                                   "Password salah. Sisa percobaan: 1. PERCOBAAN TERAKHIR: salah sekali lagi = vault "
                                   "DIHAPUS PERMANEN. Berhenti dulu dan cek catatan password kamu."))
            raise VaultError(T(f"Wrong password. Tries left: {left}", f"Password salah. Sisa percobaan: {left}"))
        _write_json(F_ATTEMPTS, {"failed": 0})
        keys = []
        for kf in keyfiles:
            if not os.path.exists(kf):
                keys.append(None)
                continue
            keys.append(_rsa_decrypt(pem, kf).decode())
        return keys
    finally:
        pem = None


def _unlock(password, keyfile=None):
    return _unlock_many(password, [keyfile or F_SNAPKEY])[0]


def check_password(password):
    _unlock_many(password, [])


def restore(password, only=None):
    """Kembalikan semua app dari snapshot. Arsip dibongkar ke folder sementara dulu;
    data app saat ini baru diganti setelah semuanya berhasil dibongkar (aman kalau dibatalkan).
    v5.25: only = daftar nama app (profil vault): hanya app itu yang dikembalikan. None = semua, seperti dulu."""
    per = _load_manifest()
    names = [n for n in per if n in items() and (per[n].get("legacy") or os.path.exists(_app_files(n)[0]))]
    if not names:
        raise VaultError(T("No snapshot yet. Make one first.", "Belum ada snapshot. Buat snapshot dulu."))
    if only is not None:
        names = [n for n in names if n in only]
        if not names:
            raise VaultError(T("None of these apps has a snapshot yet.", "Belum ada snapshot untuk app-app ini."))
    legacy = [n for n in names if per[n].get("legacy")]
    fresh = [n for n in names if n not in legacy]
    keys = _unlock_many(password, [_app_files(n)[1] for n in fresh] + ([F_SNAPKEY] if legacy else []))
    shutil.rmtree(F_STAGE, ignore_errors=True)
    os.makedirs(F_STAGE, mode=0o700)
    try:
        jobs = [(n, _app_files(n)[0], keys[i], os.path.join(F_STAGE, _slug(n))) for i, n in enumerate(fresh)]
        if legacy:
            jobs.append((", ".join(legacy), F_SNAP, keys[-1], os.path.join(F_STAGE, "legacy")))
        weight = [max(os.path.getsize(a), 1) if os.path.exists(a) else 1 for _, a, _, _ in jobs]
        total, done = sum(weight), 0
        for i, (label, arc, key, dest) in enumerate(jobs):
            if not key or not os.path.exists(arc):
                raise VaultError(T(f"The snapshot of {label} is missing.", f"Snapshot {label} tidak ada."))
            start, end = 90 * done / total, 90 * (done + weight[i]) / total
            step = f"restore {i + 1}/{len(jobs)} {label}"
            _progress(start, step)
            r = _7z_progress(["x", "-y", f"-o{dest}", arc], key, start=start, end=end, step=step)
            if r.returncode != 0:
                raise VaultError(T(f"Restore of {label} failed:\n", f"Restore {label} gagal:\n") + r.stderr[-300:])
            done += weight[i]
        _progress(92, f"swap 1/1 {names[0]}")
        # v5.21: app yang sempat terbuka (mis. dibuka otomatis saat login, dengan profil kosong) ditutup dulu,
        # lalu dibuka lagi setelah datanya kembali
        keep = KeepRules()           # v5.24: dibaca sebelum app ditutup (Keep List tidak terbaca = berhenti di sini)
        was_running = quit_apps(names)
        skipped = set()
        rec = {"time": time.strftime("%Y-%m-%d %H:%M"), "ts": time.time(), "apps": names,
               "moved": [], "placed": [], "held": []}
        with _no_cancel():                           # mulai di sini: data lama diganti, tidak boleh terpotong
            # data app yang sekarang DIPINDAH (bukan dihapus) ke BEFORE_RESTORE; isi restore sebelumnya dibuang
            shutil.rmtree(BEFORE_RESTORE, ignore_errors=True)
            shutil.rmtree(AFTER_RESTORE, ignore_errors=True)
            try:
                for n in names:
                    src = os.path.join(F_STAGE, "legacy" if n in legacy else _slug(n))
                    hold = []
                    for p in app_paths(n):
                        full = os.path.join(HOME, p)
                        # v5.23: yang ada di Keep List tidak ditimpa (Keep menang)
                        if keep.kept(p):
                            skipped.add(p)
                            continue
                        hold += keep.held(p)
                        if os.path.lexists(full):
                            old = os.path.join(BEFORE_RESTORE, p)
                            os.makedirs(os.path.dirname(old), exist_ok=True)
                            shutil.move(full, old)
                            rec["moved"].append(p)
                    for pat in items().get(n, {}).get("paths", []):
                        for f in sorted(glob.glob(os.path.join(glob.escape(src), pat))):
                            rel = os.path.relpath(f, src)
                            target = os.path.join(HOME, rel)
                            if keep.kept(rel) and os.path.lexists(target):
                                skipped.add(rel)
                                continue
                            os.makedirs(os.path.dirname(target), exist_ok=True)
                            os.replace(f, target)
                            rec["placed"].append(rel)
                    # isi folder app yang ada di Keep List: versi di Mac ini kembali ke tempatnya, bukan versi snapshot
                    for h in hold:
                        target, old = os.path.join(HOME, h), os.path.join(BEFORE_RESTORE, h)
                        if not os.path.lexists(old):
                            continue
                        _remove(target)
                        os.makedirs(os.path.dirname(target), exist_ok=True)
                        shutil.move(old, target)
                        rec["held"].append(h)
                        skipped.add(h)
            finally:
                os.makedirs(BEFORE_RESTORE, exist_ok=True)
                _write_json(F_UNDO, rec)
    finally:
        shutil.rmtree(F_STAGE, ignore_errors=True)
    _progress(96, f"check 1/1 {names[0]}")
    history("restore", ", ".join(names))
    reopen_apps(was_running)
    return names, check_restore(names), len(skipped)


def _remove(full):
    if os.path.isdir(full) and not os.path.islink(full):
        shutil.rmtree(full, ignore_errors=True)
    elif os.path.lexists(full):
        os.remove(full)


def undo_info():
    """v5.23: restore terakhir yang masih bisa dibatalkan (sampai logout berikutnya), atau None."""
    rec = _read_json(F_UNDO, None)
    if not isinstance(rec, dict) or not os.path.isdir(BEFORE_RESTORE):
        return None
    return {"time": rec.get("time", ""), "apps": rec.get("apps", [])}


def undo_restore():
    """v5.23: "Kembalikan data sebelum restore": data dari BEFORE_RESTORE kembali ke tempatnya. Data hasil restore
    tidak dihapus, tapi dipindah ke AFTER_RESTORE (ikut terhapus saat logout, seperti BEFORE_RESTORE)."""
    rec = _read_json(F_UNDO, None)
    if not isinstance(rec, dict):
        raise VaultError(T("There is no restore to undo (it's gone after a logout).",
                           "Tidak ada restore yang bisa dibatalkan (hilang setelah logout)."))
    names = [n for n in rec.get("apps", []) if isinstance(n, str)]
    rels = lambda k: [r for r in rec.get(k, []) if isinstance(r, str) and _safe_undo(r)]
    was_running = quit_apps(names)
    with _no_cancel():
        shutil.rmtree(AFTER_RESTORE, ignore_errors=True)
        # item Keep List di dalam folder app: itu data Mac ini sendiri, ikut kembali bersama foldernya
        for h in rels("held"):
            full, old = os.path.join(HOME, h), os.path.join(BEFORE_RESTORE, h)
            if os.path.lexists(full) and not os.path.lexists(old):
                os.makedirs(os.path.dirname(old), exist_ok=True)
                shutil.move(full, old)
        for r in sorted(set(rels("placed")) | set(rels("moved"))):
            full = os.path.join(HOME, r)
            if os.path.lexists(full):
                away = os.path.join(AFTER_RESTORE, r)
                os.makedirs(os.path.dirname(away), exist_ok=True)
                shutil.move(full, away)
        for r in rels("moved"):
            old = os.path.join(BEFORE_RESTORE, r)
            if os.path.lexists(old):
                os.makedirs(os.path.dirname(os.path.join(HOME, r)), exist_ok=True)
                shutil.move(old, os.path.join(HOME, r))
        shutil.rmtree(BEFORE_RESTORE, ignore_errors=True)
    history("undo", ", ".join(names))
    reopen_apps(was_running)
    return names


def _safe_undo(rel):
    parts = rel.split("/")
    return bool(rel) and not os.path.isabs(rel) and ".." not in parts and parts[0] not in (".amnesia", ".amnesia-trash")


def _newest_data(n, keep, ts):
    """v5.23: waktu perubahan terbaru di data app ini yang akan ditimpa restore. Hanya file (folder berubah waktu juga
    saat isinya dipindah); cache, dan yang ada di Keep List, tidak dihitung. Berhenti begitu ada yang lebih baru dari ts."""
    t = 0
    for rel in app_paths(n):
        full = os.path.join(HOME, rel)
        if keep.kept(rel) or not os.path.lexists(full):
            continue
        if os.path.islink(full) or not os.path.isdir(full):
            t = max(t, os.lstat(full).st_mtime)
            continue
        for root, dirs, files in os.walk(full):
            dirs[:] = [d for d in dirs if d not in EXCLUDE and not keep.kept(os.path.relpath(os.path.join(root, d), HOME))]
            for x in files:
                f = os.path.join(root, x)
                if x in EXCLUDE or keep.kept(os.path.relpath(f, HOME)):
                    continue
                try:
                    t = max(t, os.lstat(f).st_mtime)
                except OSError:
                    pass
            if t > ts:
                return t
    return t


def newer_apps():
    """v5.23: app yang datanya di Mac ini lebih baru dari snapshot-nya (restore akan memundurkannya).
    Dipanggil app sebelum restore, supaya kamu ditanya dulu."""
    per = _load_manifest()
    keep = KeepRules()
    out = []
    for n in per:
        ts = per[n].get("ts")
        if not ts or n not in items() or not os.path.exists(_app_files(n)[0]):
            continue
        t = _newest_data(n, keep, ts + 60)          # 1 menit toleransi (file yang disentuh tepat saat snapshot)
        if t > ts + 60:
            out.append({"app": n, "snap": per[n].get("time", ""), "now": time.strftime("%Y-%m-%d %H:%M", time.localtime(t))})
    return out


def _app_installed(name):
    q = items().get(name, {}).get("quit")
    if not q or os.environ.get("AMNESIA_HOME"):      # CLI/folder, atau home palsu (tes)
        return True
    return any(os.path.isdir(os.path.join(d, q + ".app")) for d in ("/Applications", os.path.join(HOME, "Applications")))


def check_restore(names):
    """Cek otomatis setelah restore: file ada, app terpasang, login gh jalan."""
    out = []
    for n in names:
        paths = app_paths(n)
        ok, note = bool(paths), ""
        if not ok:
            note = T("no files came back", "tidak ada file yang kembali")
        elif not _app_installed(n):
            ok, note = False, T("files are back, but the app isn't installed", "file kembali, tapi app-nya belum terpasang")
        elif n == "GitHub CLI":
            gh = next((g for g in ("/opt/homebrew/bin/gh", "/usr/local/bin/gh") if os.path.exists(g)), None)
            if gh and not os.environ.get("AMNESIA_HOME"):
                try:
                    r = subprocess.run([gh, "auth", "status"], capture_output=True, text=True, timeout=20)
                    ok = r.returncode == 0
                    note = T("gh is logged in", "gh sudah login") if ok else T("gh is not logged in (needs internet)", "gh belum login (butuh internet)")
                except (OSError, subprocess.TimeoutExpired):
                    ok, note = False, T("gh didn't answer (needs internet)", "gh tidak menjawab (butuh internet)")
        out.append({"app": n, "ok": ok, "note": note})
    return out


# ---------------- Pindah Mac: kunci Keychain ----------------
# Chrome, Claude, WhatsApp, dll. mengenkripsi login dengan kunci "<App> Safe Storage" di Keychain.
# Di Mac yang sama kunci itu tetap ada (keychain: di keep list). Di Mac BARU kunci itu tidak ada,
# jadi profil hasil restore tidak bisa membaca login. exportkeys menyimpan kunci itu di vault.
def _keychain_secrets():
    """[{svc, acct, secret}] untuk semua item 'Safe Storage'. macOS bisa minta 'Always Allow' per item."""
    dump = subprocess.run([SECURITY, "dump-keychain"], capture_output=True, text=True).stdout
    items, seen = [], set()
    for block in dump.split("keychain: ")[1:]:
        if 'class: "genp"' not in block:
            continue
        svc = re.search(r'"svce"<blob>="([^"]*)"', block)
        acct = re.search(r'"acct"<blob>="([^"]*)"', block)
        if not svc or not svc.group(1).endswith(" Safe Storage"):
            continue
        key = (svc.group(1), acct.group(1) if acct else "")
        if key in seen:
            continue
        seen.add(key)
        r = subprocess.run([SECURITY, "find-generic-password", "-s", key[0], "-a", key[1], "-w"],
                           capture_output=True, text=True)
        if r.returncode == 0:
            items.append({"svc": key[0], "acct": key[1], "secret": r.stdout.rstrip("\n")})
    return items


def _keychain_set(svc, acct, secret):
    # v5.22: dulu secret lewat argumen -w (terlihat sesaat di `ps`). Sekarang perintahnya dikirim lewat stdin ke
    # `security -i`, dan secret ditulis sebagai hex (-X), jadi tidak ada tanda kutip yang bisa merusak perintah.
    if any(c in x for x in (svc, acct) for c in '"\\\n'):
        raise VaultError(T(f"Couldn't save the {svc} key: unusual name.", f"Gagal menyimpan kunci {svc}: namanya tidak biasa."))
    cmd = f'add-generic-password -U -s "{svc}" -a "{acct}" -X {secret.encode().hex()}\n'
    r = subprocess.run([SECURITY, "-i"], input=cmd, capture_output=True, text=True)
    chk = subprocess.run([SECURITY, "find-generic-password", "-s", svc, "-a", acct], capture_output=True, text=True)
    if r.returncode != 0 or chk.returncode != 0:
        raise VaultError(T(f"Couldn't save the {svc} key: ", f"Gagal menyimpan kunci {svc}: ") + (r.stderr or chk.stderr).strip()[-200:])


def keys_info():
    return _read_json(os.path.join(VAULT, "keys_info.json"), None) if os.path.exists(F_KEYS) else None


def export_keys():
    """Simpan kunci Safe Storage ke vault. Tidak butuh password (pakai public key)."""
    if not exists():
        raise VaultError(T("No vault yet.", "Vault belum dibuat."))
    items = _keychain_secrets()
    if not items:
        raise VaultError(T("No 'Safe Storage' keys could be read from the Keychain.", "Tidak ada kunci 'Safe Storage' yang bisa dibaca dari Keychain."))
    tmp = _new_tmp()
    try:
        src = os.path.join(tmp, "keys.json")
        _write_json(src, items)
        key = secrets.token_hex(32)
        new = F_KEYS + ".new"
        if os.path.exists(new):
            os.remove(new)
        r = _7z(["a", "-t7z", "-mhe=on", "-p", new, "keys.json"], key, cwd=tmp)
        if r.returncode != 0:
            raise VaultError(T("Couldn't save the keys:\n", "Gagal menyimpan kunci:\n") + r.stderr[-300:])
        subprocess.run([OPENSSL, "pkeyutl", "-encrypt", "-pubin", "-inkey", F_PUB,
                        "-pkeyopt", "rsa_padding_mode:oaep", "-out", F_KEYSKEY + ".new"],
                       input=key.encode(), check=True, capture_output=True)
        os.replace(new, F_KEYS)
        os.replace(F_KEYSKEY + ".new", F_KEYSKEY)
    finally:
        _clean_tmp()
    names = sorted({i["svc"].removesuffix(" Safe Storage") for i in items})
    _write_json(os.path.join(VAULT, "keys_info.json"), {"apps": names, "time": time.strftime("%Y-%m-%d %H:%M")})
    return names


def import_keys(password):
    """Pasang kembali kunci Safe Storage dari vault ke Keychain Mac ini."""
    key = _unlock(password, F_KEYSKEY)
    if not key or not os.path.exists(F_KEYS):
        raise VaultError(T("This vault has no keys yet. Run 'Prepare Move' on the old Mac first.", "Vault ini belum berisi kunci. Jalankan 'Siapkan Pindah Mac' di Mac lama dulu."))
    tmp = _new_tmp()
    try:
        r = _7z(["x", "-y", f"-o{tmp}", F_KEYS], key)
        if r.returncode != 0:
            raise VaultError(T("Couldn't open the keys:\n", "Gagal membuka kunci:\n") + r.stderr[-300:])
        items = _read_json(os.path.join(tmp, "keys.json"), [])
    finally:
        _clean_tmp()
    quit_apps([n for n in APPS if APPS[n]["quit"]])
    for i in items:
        _keychain_set(i["svc"], i["acct"], i["secret"])
    return sorted({i["svc"].removesuffix(" Safe Storage") for i in items})


def change_password(old, new):
    """Ganti password vault: kunci privat dibuka dengan password lama, lalu dikunci ulang dengan yang baru.
    Snapshot tidak perlu dibuat ulang (dikunci dengan kunci publik yang sama)."""
    if new == old:
        raise VaultError(T("The new password is the same as the current one. Pick a different password.",
                           "Password baru sama dengan password sekarang. Pilih password yang berbeda."))
    if len(new) < MIN_PASSWORD:
        raise VaultError(T(f"The new password needs at least {MIN_PASSWORD} characters.", f"Password baru minimal {MIN_PASSWORD} karakter."))
    panic = _read_json(F_PANIC, None)
    if panic and secrets.compare_digest(_hash(new, panic["salt"]), panic["hash"]):
        raise VaultError(T("The new password can't be the same as the panic word.", "Password baru tidak boleh sama dengan kata panik."))
    check_password(old)                  # cek password lama (ikut hitungan salah & kata panik)
    tmp = _new_tmp()
    try:
        r = _7z(["x", "-y", f"-o{tmp}", F_PRIV], old)
        if r.returncode != 0:
            raise VaultError(T("Couldn't open the vault key:\n", "Gagal membuka kunci vault:\n") + r.stderr[-300:])
        new_priv = F_PRIV + ".new"
        if os.path.exists(new_priv):
            os.remove(new_priv)
        r = _7z(["a", "-t7z", "-mhe=on", "-p", new_priv, "private.pem"], new, cwd=tmp)
        if r.returncode != 0:
            raise VaultError(T("Couldn't lock the vault key:\n", "Gagal mengunci kunci vault:\n") + r.stderr[-300:])
        os.replace(new_priv, F_PRIV)
    finally:
        _clean_tmp()


def change_panic(password, word, full=False):
    check_password(password)
    if word == password:
        raise VaultError(T("The panic word can't be the same as the password.", "Kata panik tidak boleh sama dengan password."))
    set_panic(word, full)


# ---------------- v5.22: password Kunci Keep (hash PBKDF2, sama seperti kata panik) ----------------
def keep_hash(word):
    if len(word) < MIN_KEEP_PASSWORD:
        raise VaultError(T(f"The Keep password needs at least {MIN_KEEP_PASSWORD} characters.",
                           f"Password Keep minimal {MIN_KEEP_PASSWORD} karakter."))
    salt = secrets.token_hex(16)
    return salt + ":" + _hash(word, salt)


def keep_check(word):
    stored = _setting("KEEP_LOCK_PW", "")
    salt, _, h = stored.partition(":")
    if not salt or not h:
        raise VaultError(T("The Keep lock has no password set.", "Kunci Keep belum punya password."))
    try:
        ok = secrets.compare_digest(_hash(word, salt), h)
    except ValueError:
        ok = False
    if not ok:
        raise VaultError(T("Wrong Keep password.", "Password Keep salah."))


# ---------------- v5.25: profil vault (kelompok app, supaya restore hanya yang kamu perlukan) ----------------
# ~/.amnesia/profiles.json: {"version":1,"last":"all","profiles":[{"id","name","apps"}]}. Hanya nama, tanpa rahasia.
# "Semua" (id all) tidak pernah disimpan. Selama file belum ada, profil bawaan dipakai (hanya app yang ada di sini).
F_PROFILES = os.path.join(AMNESIA, "profiles.json")
MAX_PROFILES = 20
BUILTIN_PROFILES = [
    ("work", ("Work", "Kerja"),
     ["Claude", "Claude Code", "OpenCode", "Gemini CLI", "GitHub CLI", "CodeBuddy", "Kimi", "Antigravity",
      "Notion", "Zoom", "Windows App", "Chrome"]),
    # browser kedua (untuk streaming dll.) ikut di sini kalau ada di Mac ini
    ("personal", ("Personal", "Santai"),
     ["WhatsApp", "Telegram", "Signal", "Session", "Element",
      "Brave Browser", "Arc", "Vivaldi", "Opera", "Microsoft Edge"]),
]
_PROFILE_ID = re.compile(r"^[a-z0-9-]{1,32}$")


def snapshot_apps():
    """v5.25: app yang punya snapshot (arsip ada, atau snapshot lama 1 arsip)."""
    per = _load_manifest()
    return [n for n in per if n in items() and (per[n].get("legacy") or os.path.exists(_app_files(n)[0]))]


def profile_apps_here():
    """v5.25: app yang bisa masuk profil di Mac ini: datanya ada ATAU sudah ada snapshot-nya
    (setelah logout data app hilang, tapi snapshot-nya tetap bisa di-restore)."""
    have = set(installed_apps()) | set(snapshot_apps())
    return [n for n in items() if n in have]


def _profile_name_ok(name):
    return isinstance(name, str) and 1 <= len(name) <= 40 and not any(ord(c) < 32 or ord(c) == 127 for c in name) \
        and name.strip().lower() not in ("all", "everything", "semua")


def _profile_slug(name, taken):
    s = unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode().lower()
    s = re.sub(r"[^a-z0-9]+", "-", s).strip("-")[:32].strip("-") or "profile"
    base, i = s, 2
    while s in taken or s == "all":
        tail = f"-{i}"
        s = base[:32 - len(tail)] + tail
        i += 1
    return s


def _builtin_profiles():
    here = profile_apps_here()
    out = []
    for pid, (en, id_), apps in BUILTIN_PROFILES:
        apps = [a for a in apps if a in here]
        if apps:
            out.append({"id": pid, "name": T(en, id_), "apps": apps, "builtin": True})
    return out


def _stored_profiles():
    """Isi profiles.json, sudah dicek. None = belum pernah disimpan (profil bawaan dipakai)."""
    if not os.path.exists(F_PROFILES):
        return None
    raw = _read_json(F_PROFILES, {})
    if isinstance(raw, dict) and "profiles" not in raw:      # baru "last" yang tersimpan
        return None
    out, seen = [], set()
    for p in raw.get("profiles", []) if isinstance(raw, dict) and isinstance(raw.get("profiles"), list) else []:
        if not isinstance(p, dict):
            continue
        pid, name = p.get("id"), p.get("name")
        if not isinstance(pid, str) or not _PROFILE_ID.match(pid) or pid == "all" or pid in seen \
                or not _profile_name_ok(name):
            continue
        apps = []
        for a in p.get("apps", []) if isinstance(p.get("apps"), list) else []:
            if isinstance(a, str) and a not in apps:
                apps.append(a)
        seen.add(pid)
        out.append({"id": pid, "name": name, "apps": apps})
    return out[:MAX_PROFILES]


def profiles_list():
    """Profil yang ditampilkan: app yang tidak dikenal lagi (mis. app tambahan yang sudah dikeluarkan) tidak ikut."""
    stored = _stored_profiles()
    if stored is None:
        return _builtin_profiles()
    known = items()
    return [{"id": p["id"], "name": p["name"], "apps": [a for a in p["apps"] if a in known], "builtin": False}
            for p in stored]


def profiles_shared(profs):
    """App yang ada di 2 profil atau lebih: {app: [id, ...]}. 1 browser = 1 kumpulan login, tidak bisa dibagi."""
    out = {}
    for p in profs:
        for a in p["apps"]:
            out.setdefault(a, []).append(p["id"])
    return {a: ids for a, ids in out.items() if len(ids) > 1}


def profile_last():
    raw = _read_json(F_PROFILES, {})
    last = raw.get("last") if isinstance(raw, dict) else None
    ids = [p["id"] for p in profiles_list()]
    return last if isinstance(last, str) and last in ids else "all"


def _save_profiles(profs, last=None):
    """Mulai simpan pertama, file ini berisi SELURUH daftar (profil bawaan yang dihapus tetap hilang)."""
    data = {"version": 1, "last": last if last is not None else profile_last(),
            "profiles": [{"id": p["id"], "name": p["name"], "apps": list(p["apps"])} for p in profs]}
    os.makedirs(AMNESIA, exist_ok=True)
    _write_json(F_PROFILES, data)


def profile_info():
    profs = profiles_list()
    have = set(snapshot_apps())
    shown = [dict(p, missing=[a for a in p["apps"] if a not in have]) for p in profs]
    return {"profiles": shown, "last": profile_last(), "shared": profiles_shared(profs), "apps": profile_apps_here()}


def profile_set(entry):
    """Buat atau ubah 1 profil. entry = {"id"?, "name", "apps"}. App yang tidak dikenal dibuang (dilaporkan di "ignored").
    Tanpa id: profil dengan nama yang sama (huruf besar/kecil tidak dibedakan) diubah, kalau tidak ada dibuat baru."""
    if not isinstance(entry, dict):
        raise VaultError(T("Bad profile data.", "Data profil tidak valid."))
    name = entry.get("name")
    name = name.strip() if isinstance(name, str) else ""
    if not _profile_name_ok(name):
        raise VaultError(T("Give the profile a name of 1 to 40 characters (not \"Everything\").",
                           "Beri profil nama 1 sampai 40 karakter (bukan \"Semua\")."))
    raw_apps = entry.get("apps", [])
    if not isinstance(raw_apps, list):
        raise VaultError(T("Bad profile data.", "Data profil tidak valid."))
    known = items()
    apps, ignored = [], []
    for a in raw_apps:
        if isinstance(a, str) and a in known:
            if a not in apps:
                apps.append(a)
        elif isinstance(a, str) and a not in ignored:
            ignored.append(a)
    profs = profiles_list()
    pid = entry.get("id")
    cur = next((p for p in profs if isinstance(pid, str) and p["id"] == pid), None)
    if cur is None and not pid:
        cur = next((p for p in profs if p["name"].lower() == name.lower()), None)
    same = next((p for p in profs if p["name"].lower() == name.lower() and p is not cur), None)
    if same:
        raise VaultError(T(f"There is already a profile called {same['name']}.", f"Sudah ada profil bernama {same['name']}."))
    if cur is None:
        if len(profs) >= MAX_PROFILES:
            raise VaultError(T(f"You can have up to {MAX_PROFILES} profiles.", f"Maksimal {MAX_PROFILES} profil."))
        cur = {"id": _profile_slug(name, {p["id"] for p in profs}), "name": name, "apps": apps}
        profs.append(cur)
    else:
        cur["name"], cur["apps"] = name, apps
    _save_profiles(profs)
    out = {"id": cur["id"], "name": cur["name"], "apps": cur["apps"], "builtin": False}
    return out, profiles_shared(profs), ignored


def profile_delete(pid):
    if pid == "all":
        raise VaultError(T("\"Everything\" can't be deleted.", "\"Semua\" tidak bisa dihapus."))
    profs = profiles_list()
    last = profile_last()
    _save_profiles([p for p in profs if p["id"] != pid], last="all" if last == pid else last)


def profile_set_last(pid):
    if pid != "all" and pid not in [p["id"] for p in profiles_list()]:
        raise VaultError(T("This profile no longer exists.", "Profil ini sudah tidak ada."))
    if pid == profile_last():
        return
    if _stored_profiles() is None:          # profil bawaan belum disimpan: simpan pilihan terakhir saja
        # v5.25 (item 189): "Semua" = bawaan, jadi file tidak dibuat untuk itu. Item 201: file yang sudah ada
        # tidak dihapus, tapi ditulis "last": "all" (uji Mac 27 Okt: menghapusnya mengejutkan).
        if pid == "all" and not os.path.exists(F_PROFILES):
            return
        os.makedirs(AMNESIA, exist_ok=True)
        _write_json(F_PROFILES, {"version": 1, "last": pid})
    else:
        _save_profiles(profiles_list(), last=pid)


def profile_apps(pid):
    """App di profil (None = Semua)."""
    if pid == "all":
        return None
    p = next((p for p in profiles_list() if p["id"] == pid), None)
    if p is None:
        raise VaultError(T("This profile no longer exists.", "Profil ini sudah tidak ada."))
    return p["apps"]


def logout():
    """Logout macOS tanpa dialog konfirmasi."""
    subprocess.run(["osascript", "-e", 'tell application "loginwindow" to «event aevtrlgo»'])


# ---------------- CLI (dipanggil app SwiftUI; password lewat stdin, bukan argumen) ----------------
def _cli(argv, stdin):
    cmd = argv[1] if len(argv) > 1 else "status"
    full = "full" in argv[2:]
    line = lambda: stdin.readline().rstrip("\n")
    out = {}
    if cmd not in ("status", "sizes", "logout", "keephash", "keepcheck", "newer", "profiles"):   # v5.25: + profiles
        _lock_and_sweep()                 # v5.22: 1 perintah sekaligus + sapu sisa yang terputus
    if cmd == "status":
        out = {"exists": exists(), "manifest": manifest() or None, "attempts": attempts(),
               "max": MAX_ATTEMPTS, "min": MIN_PASSWORD, "apps": installed_apps(), "skip": skipped_apps(),
               "folders": vault_folders(), "keys": keys_info(),
               "light": [n for n in light_apps() if n in installed_apps()], "full": full_apps(),
               "custom": sorted(custom_apps()),          # v5.22: app tambahan pilihan kamu
               # path tiap app yang ikut snapshot: dipakai halaman "Yang akan dihapus" (kelompok "dipulihkan dari vault")
               "patterns": {n: items()[n]["paths"] for n in chosen_apps()} if exists() else {},
               "undo": undo_info()}                       # v5.23: restore terakhir yang masih bisa dibatalkan
    elif cmd == "sizes":
        out = {"sizes": sizes()}
    elif cmd == "check":
        check_password(line())
    elif cmd == "create":
        pw, panic = line(), line()
        create(pw, panic, full)
    elif cmd == "snapshot":
        args = [a for a in argv[2:] if not a.startswith("--")]
        out = {"apps": snapshot(args or None, changed="--changed" in argv[2:], reopen="--reopen" in argv[2:])}
    elif cmd == "restore":
        # v5.25: restore [--profile <id>] [App ...]: hanya app itu (+ app di profil). Tanpa keduanya: semua, seperti dulu.
        args, prof, i = [], None, 2
        while i < len(argv):
            if argv[i] == "--profile" and i + 1 < len(argv):
                prof, i = argv[i + 1], i + 2
                continue
            if not argv[i].startswith("--"):
                args.append(argv[i])
            i += 1
        only, ignored = None, []
        if prof is not None:
            only = profile_apps(prof)
            profile_set_last(prof)
        if args:
            known = items()
            ignored = [a for a in args if a not in known]
            only = (only if only is not None else []) + [a for a in args if a in known]
        if only is not None:
            have = set(snapshot_apps())
            ignored += [a for a in only if a not in have and a not in ignored]   # belum ada snapshot-nya
        names, checks, skipped = restore(line(), only)
        per = _load_manifest()
        out = {"apps": names, "checks": checks, "light": [n for n in names if per.get(n, {}).get("light")],
               "skipped": skipped,               # v5.23: berapa path dilewati karena ada di Keep List
               "ignored": ignored}               # v5.25: nama yang tidak dikenal / belum ada snapshot-nya
    elif cmd == "newer":                         # v5.23: dicek app sebelum restore
        out = {"newer": newer_apps()}
    elif cmd == "undo":                          # v5.23: Kembalikan data sebelum restore
        out = {"apps": undo_restore()}
    elif cmd == "delsnap":
        delete_snapshot(argv[2:] or None)
    elif cmd == "passwd":
        old, new = line(), line()
        change_password(old, new)
    elif cmd == "panic":
        pw, word = line(), line()
        change_panic(pw, word, full)
    elif cmd == "exportkeys":
        out = {"apps": export_keys()}
    elif cmd == "importkeys":
        out = {"apps": import_keys(line())}
    elif cmd == "delete":
        doomsday(False, "dihapus manual")
    elif cmd == "logout":
        logout()
    elif cmd == "addapp":                  # v5.22: 1 baris JSON {"name", "quit", "paths"}
        try:
            add_custom(json.loads(line() or "{}"))
        except ValueError:
            raise VaultError(T("Bad app data.", "Data app tidak valid."))
    elif cmd == "delapp":
        for n in argv[2:]:
            remove_custom(n)
    elif cmd == "keephash":                # password lewat stdin; hasilnya disimpan app di KEEP_LOCK_PW
        out = {"hash": keep_hash(line())}
    elif cmd == "keepcheck":
        keep_check(line())
    elif cmd == "profiles":                # v5.25: profil vault (hanya membaca)
        out = profile_info()
    elif cmd == "profile-set":             # v5.25: 1 baris JSON {"id"?, "name", "apps"}
        try:
            entry = json.loads(line() or "{}")
        except ValueError:
            raise VaultError(T("Bad profile data.", "Data profil tidak valid."))
        prof, shared, ignored = profile_set(entry)
        out = {"profile": prof, "shared": shared, "ignored": ignored}
    elif cmd == "profile-delete":
        for pid in argv[2:]:
            profile_delete(pid)
    elif cmd == "profile-last":
        profile_set_last(argv[2] if len(argv) > 2 else "all")
    else:
        raise VaultError(T(f"Unknown command: {cmd}", f"Perintah tidak dikenal: {cmd}"))
    return out


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, _on_cancel)       # tombol Batal di app
    try:
        res = {"ok": True}
        res.update(_cli(sys.argv, sys.stdin))
    except VaultError as e:
        res = {"ok": False, "error": str(e)}
    except Exception as e:                       # noqa: BLE001 — dikirim ke GUI
        res = {"ok": False, "error": f"{type(e).__name__}: {e}"}
    print(json.dumps(res))
