#!/usr/bin/env python3
"""Amnesia Profile Vault — snapshot & restore profil app terenkripsi.

Cara kerja kunci (supaya "Simpan & Logout" tidak perlu ketik password):
- Saat vault dibuat: dibuat pasangan kunci RSA. Kunci publik disimpan biasa,
  kunci privat dikunci 7zz (AES-256) dengan password vault.
- Snapshot: profil dikunci 7zz dengan kunci acak, kunci acak itu dikunci kunci publik.
  -> tidak butuh password.
- Restore: password membuka kunci privat -> kunci acak -> profil.
Password tidak pernah disimpan, dan dikirim ke 7zz lewat stdin (tidak terlihat di `ps`).
"""
import glob, hashlib, json, os, re, secrets, shutil, signal, subprocess, sys, time

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
               "paths": ["Library/Application Support/Google/Chrome"]},
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
}
# Cache tidak perlu disimpan (besar, dibuat ulang otomatis oleh app)
EXCLUDE = ["Cache", "Code Cache", "GPUCache", "CacheStorage", "ShaderCache", "GrShaderCache",
           "DawnCache", "DawnGraphiteCache", "DawnWebGPUCache", "component_crx_cache",
           "Crashpad", "vm_bundles", "CachedData", "CachedExtensionVSIXs", ".DS_Store"]

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


def _lang():
    try:
        with open(os.path.join(AMNESIA, "settings.conf")) as f:
            return [l.strip()[5:] for l in f if l.startswith("LANG=")][-1]
    except (OSError, IndexError):
        return "en"


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


def items():
    """Semua yang bisa disimpan: app di APPS + folder pilihan (nama '~/<folder>')."""
    d = dict(APPS)
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
    size = sum(v.get("size_mb") or 0 for v in per.values() if not v.get("legacy"))
    if any(v.get("legacy") for v in per.values()) and os.path.exists(F_SNAP):
        size += os.path.getsize(F_SNAP) / 1048576
    return {"apps": names, "time": max(times) if times else "", "size_mb": round(size, 1), "per_app": per}


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
    """App yang kamu matikan di halaman Profile Vault (VAULT_SKIP di settings.conf)."""
    return [x for x in _setting("VAULT_SKIP", "").split(",") if x]


def chosen_apps():
    skip = skipped_apps()
    return [n for n in installed_apps() if n not in skip]


def _size(paths):
    """Ukuran (byte) tanpa cache, sama seperti yang masuk snapshot."""
    total = 0
    for p in paths:
        full = os.path.join(HOME, p)
        if os.path.islink(full) or os.path.isfile(full):
            total += os.lstat(full).st_size
            continue
        for root, dirs, files in os.walk(full):
            dirs[:] = [d for d in dirs if d not in EXCLUDE]
            for f in files:
                if f not in EXCLUDE:
                    try:
                        total += os.lstat(os.path.join(root, f)).st_size
                    except OSError:
                        pass
    return total


def sizes():
    """Ukuran tiap app (MB), untuk ditampilkan sebelum snapshot."""
    return {n: round(_size(app_paths(n)) / 1048576, 1) for n in installed_apps()}


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
def quit_apps(names):
    """Tutup app dengan sopan dulu (data tersimpan), baru paksa. Mencegah profil corrupt."""
    if not shutil.which("osascript") or os.environ.get("AMNESIA_HOME"):   # bukan macOS / home palsu (tes, screenshot)
        return
    gui = [APPS[n]["quit"] for n in names if APPS[n]["quit"]]
    if not gui:
        return
    for q in gui:
        subprocess.run(["osascript", "-e", f'quit app "{q}"'], capture_output=True)
    time.sleep(3)
    for q in gui:
        subprocess.run(["killall", q], capture_output=True)
    time.sleep(1)


def snapshot(names=None):
    """Simpan app ke vault, 1 arsip per app. Tidak butuh password.
    Hanya app yang dipilih yang diperbarui; snapshot app lain tetap ada."""
    if not exists():
        raise VaultError(T("No vault yet.", "Vault belum dibuat."))
    names = [n for n in (names or chosen_apps()) if app_paths(n)]
    if not names:
        raise VaultError(T("There is no app data to snapshot.", "Tidak ada data app yang bisa di-snapshot."))
    weight = {n: max(_size(app_paths(n)), 1) for n in names}
    total = sum(weight.values())
    _progress(0, f"quit 1/{len(names)} {names[0]}")
    quit_apps(names)
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
            args = ["a", "-t7z", "-mx=3", "-mhe=on", "-p", new_arc] + app_paths(n) + [f"-xr!{x}" for x in EXCLUDE]
            r = _7z_progress(args, key, cwd=HOME, start=start, end=end, step=step)
            if r.returncode not in (0, 1):          # 1 = warning (mis. file terkunci), arsip tetap jadi
                raise VaultError(T(f"Snapshot of {n} failed:\n", f"Snapshot {n} gagal:\n") + r.stderr[-300:])
            subprocess.run([OPENSSL, "pkeyutl", "-encrypt", "-pubin", "-inkey", F_PUB,
                            "-pkeyopt", "rsa_padding_mode:oaep", "-out", new_key],
                           input=key.encode(), check=True, capture_output=True)
            with _no_cancel():                       # arsip & kuncinya selalu diganti berpasangan
                os.replace(new_arc, arc)
                os.replace(new_key, keyf)
                per[n] = {"time": time.strftime("%Y-%m-%d %H:%M"),
                          "size_mb": round(os.path.getsize(arc) / 1048576, 1)}
                _save_manifest(per)
        finally:
            for f in (new_arc, new_key):
                if os.path.exists(f):
                    os.remove(f)
        done += weight[n]
        saved.append(n)
    _drop_legacy(per)
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
        for x in os.listdir(keep) if os.path.isdir(keep) else []:
            p = os.path.join(keep, x)
            if os.path.isdir(p) and not os.path.islink(p):
                shutil.rmtree(p, ignore_errors=True)
            else:
                os.remove(p)
    with open(F_LOG, "a") as f:
        f.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} doomsday ({reason}){' + Keep' if full else ''}\n")


def _unlock_many(password, keyfiles):
    """Buka kunci acak dari tiap keyfile (None kalau file-nya tidak ada). Menangani kata panik & hitungan salah."""
    if not exists():
        raise VaultError(T("No vault yet.", "Vault belum dibuat."))
    panic = _read_json(F_PANIC, None)
    if panic and secrets.compare_digest(_hash(password, panic["salt"]), panic["hash"]):
        doomsday(panic.get("full", False), "kata panik")
        raise VaultError("DOOMSDAY")
    tmp = _new_tmp()
    try:
        r = _7z(["x", "-y", f"-o{tmp}", F_PRIV], password)
        if r.returncode != 0:
            if "password" not in (r.stdout + r.stderr).lower():
                raise VaultError(T("The vault can't be opened (not a password problem):\n", "Vault tidak bisa dibuka (bukan karena password):\n") + r.stderr[-300:])
            failed = attempts() + 1
            if failed >= MAX_ATTEMPTS:
                doomsday(False, f"{failed}x password salah")
                raise VaultError("DOOMSDAY")
            _write_json(F_ATTEMPTS, {"failed": failed})
            raise VaultError(T(f"Wrong password. Tries left: {MAX_ATTEMPTS - failed}", f"Password salah. Sisa percobaan: {MAX_ATTEMPTS - failed}"))
        _write_json(F_ATTEMPTS, {"failed": 0})
        keys = []
        for kf in keyfiles:
            if not os.path.exists(kf):
                keys.append(None)
                continue
            out = subprocess.run([OPENSSL, "pkeyutl", "-decrypt", "-inkey", os.path.join(tmp, "private.pem"),
                                  "-pkeyopt", "rsa_padding_mode:oaep", "-in", kf],
                                 check=True, capture_output=True)
            keys.append(out.stdout.decode())
        return keys
    finally:
        _clean_tmp()


def _unlock(password, keyfile=None):
    return _unlock_many(password, [keyfile or F_SNAPKEY])[0]


def check_password(password):
    _unlock_many(password, [])


def restore(password):
    """Kembalikan semua app dari snapshot. Arsip dibongkar ke folder sementara dulu;
    data app saat ini baru diganti setelah semuanya berhasil dibongkar (aman kalau dibatalkan)."""
    per = _load_manifest()
    names = [n for n in per if n in items() and (per[n].get("legacy") or os.path.exists(_app_files(n)[0]))]
    if not names:
        raise VaultError(T("No snapshot yet. Make one first.", "Belum ada snapshot. Buat snapshot dulu."))
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
        quit_apps(names)
        with _no_cancel():                           # mulai di sini: data lama diganti, tidak boleh terpotong
            for n in names:
                src = os.path.join(F_STAGE, "legacy" if n in legacy else _slug(n))
                for p in app_paths(n):
                    full = os.path.join(HOME, p)
                    if os.path.isdir(full) and not os.path.islink(full):
                        shutil.rmtree(full, ignore_errors=True)
                    elif os.path.lexists(full):
                        os.remove(full)
                for pat in items().get(n, {}).get("paths", []):
                    for f in sorted(glob.glob(os.path.join(glob.escape(src), pat))):
                        target = os.path.join(HOME, os.path.relpath(f, src))
                        os.makedirs(os.path.dirname(target), exist_ok=True)
                        os.replace(f, target)
    finally:
        shutil.rmtree(F_STAGE, ignore_errors=True)
    _progress(96, f"check 1/1 {names[0]}")
    return names, check_restore(names)


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
    # ponytail: secret lewat argumen -w terlihat sesaat di daftar proses; 'security' tidak punya input
    # stdin untuk ini. Risiko kecil karena hanya jalan saat user menekan "Pulihkan Kunci".
    r = subprocess.run([SECURITY, "add-generic-password", "-U", "-s", svc, "-a", acct, "-w", secret],
                       capture_output=True, text=True)
    if r.returncode != 0:
        raise VaultError(T(f"Couldn't save the {svc} key: ", f"Gagal menyimpan kunci {svc}: ") + r.stderr.strip()[-200:])


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


def logout():
    """Logout macOS tanpa dialog konfirmasi."""
    subprocess.run(["osascript", "-e", 'tell application "loginwindow" to «event aevtrlgo»'])


# ---------------- CLI (dipanggil app SwiftUI; password lewat stdin, bukan argumen) ----------------
def _cli(argv, stdin):
    cmd = argv[1] if len(argv) > 1 else "status"
    full = "full" in argv[2:]
    line = lambda: stdin.readline().rstrip("\n")
    out = {}
    if cmd == "status":
        out = {"exists": exists(), "manifest": manifest() or None, "attempts": attempts(),
               "max": MAX_ATTEMPTS, "min": MIN_PASSWORD, "apps": installed_apps(), "skip": skipped_apps(),
               "folders": vault_folders(), "keys": keys_info(),
               # path tiap app yang ikut snapshot: dipakai halaman "Yang akan dihapus" (kelompok "dipulihkan dari vault")
               "patterns": {n: items()[n]["paths"] for n in chosen_apps()} if exists() else {}}
    elif cmd == "sizes":
        out = {"sizes": sizes()}
    elif cmd == "check":
        check_password(line())
    elif cmd == "create":
        pw, panic = line(), line()
        create(pw, panic, full)
    elif cmd == "snapshot":
        out = {"apps": snapshot(argv[2:] or None)}
    elif cmd == "restore":
        names, checks = restore(line())
        out = {"apps": names, "checks": checks}
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
