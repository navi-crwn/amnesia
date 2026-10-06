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
import glob, hashlib, json, os, re, secrets, shutil, subprocess, sys, time

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
F_PRIV = os.path.join(VAULT, "private.7z")
F_SNAP = os.path.join(VAULT, "profiles.7z")
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
    """Kemajuan untuk app (dibaca dari stderr): 'PROGRESS 42 Chrome'."""
    sys.stderr.write(f"PROGRESS {int(pct)} {step}\n")
    sys.stderr.flush()


def _7z_progress(args, password, cwd=None, start=0, end=100):
    """Seperti _7z, tapi persen dari 7zz diteruskan ke app (start..end)."""
    p = subprocess.Popen([SEVENZ] + args + ["-bso0", "-bsp2", "-bse2"], stdin=subprocess.PIPE,
                         stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, cwd=cwd)
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
                _progress(pct)
    p.wait()
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


def manifest():
    return _read_json(F_MANIFEST, {})


def attempts():
    return _read_json(F_ATTEMPTS, {"failed": 0})["failed"]


def app_paths(name):
    """Path (relatif dari home) milik app yang benar-benar ada di Mac ini."""
    return [os.path.relpath(f, HOME) for p in APPS[name]["paths"]
            for f in sorted(glob.glob(os.path.join(glob.escape(HOME), p)))]


def installed_apps():
    """App yang punya data di Mac ini."""
    return [n for n in APPS if app_paths(n)]


def skipped_apps():
    """App yang kamu matikan di halaman Profile Vault (VAULT_SKIP di settings.conf)."""
    return [x for x in _setting("VAULT_SKIP", "").split(",") if x]


def chosen_apps():
    skip = skipped_apps()
    return [n for n in installed_apps() if n not in skip]


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
    """Simpan profil app ke vault. Tidak butuh password."""
    if not exists():
        raise VaultError(T("No vault yet.", "Vault belum dibuat."))
    names = names or chosen_apps()
    paths = [p for n in names for p in app_paths(n)]
    if not paths:
        raise VaultError(T("There is no app data to snapshot.", "Tidak ada data app yang bisa di-snapshot."))
    _progress(0, "quit")
    quit_apps(names)
    key = secrets.token_hex(32)
    new_snap, new_key = F_SNAP + ".new", F_SNAPKEY + ".new"
    for f in (new_snap, new_key):
        if os.path.exists(f):
            os.remove(f)
    args = ["a", "-t7z", "-mx=3", "-mhe=on", "-p", new_snap] + paths + [f"-xr!{x}" for x in EXCLUDE]
    r = _7z_progress(args, key, cwd=HOME, start=2, end=98)
    if r.returncode not in (0, 1):          # 1 = warning (mis. file terkunci), arsip tetap jadi
        raise VaultError(T("Snapshot failed:\n", "Snapshot gagal:\n") + r.stderr[-300:])
    subprocess.run([OPENSSL, "pkeyutl", "-encrypt", "-pubin", "-inkey", F_PUB,
                    "-pkeyopt", "rsa_padding_mode:oaep", "-out", new_key],
                   input=key.encode(), check=True, capture_output=True)
    os.replace(new_snap, F_SNAP)
    os.replace(new_key, F_SNAPKEY)
    _write_json(F_MANIFEST, {"apps": names, "time": time.strftime("%Y-%m-%d %H:%M"),
                             "size_mb": round(os.path.getsize(F_SNAP) / 1048576, 1)})
    return names


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


def _unlock(password, keyfile=None):
    """Kembalikan kunci acak (default: kunci profil). Menangani kata panik & hitungan salah."""
    keyfile = keyfile or F_SNAPKEY
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
        if not os.path.exists(keyfile):
            return None
        out = subprocess.run([OPENSSL, "pkeyutl", "-decrypt", "-inkey", os.path.join(tmp, "private.pem"),
                              "-pkeyopt", "rsa_padding_mode:oaep", "-in", keyfile],
                             check=True, capture_output=True)
        return out.stdout.decode()
    finally:
        _clean_tmp()


def check_password(password):
    _unlock(password)


def restore(password):
    """Kembalikan semua profil dari snapshot. Data app saat ini diganti."""
    key = _unlock(password)
    if not key or not os.path.exists(F_SNAP):
        raise VaultError(T("No snapshot yet. Make one first.", "Belum ada snapshot. Buat snapshot dulu."))
    names = manifest().get("apps", list(APPS))
    _progress(0, "quit")
    quit_apps(names)
    for n in names:
        for p in app_paths(n):
            full = os.path.join(HOME, p)
            if os.path.isdir(full) and not os.path.islink(full):
                shutil.rmtree(full, ignore_errors=True)
            else:
                os.remove(full)
    r = _7z_progress(["x", "-y", f"-o{HOME}", F_SNAP], key, start=5, end=100)
    if r.returncode != 0:
        raise VaultError(T("Restore failed:\n", "Restore gagal:\n") + r.stderr[-300:])
    return names


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
    if len(new) < MIN_PASSWORD:
        raise VaultError(T(f"The new password needs at least {MIN_PASSWORD} characters.", f"Password baru minimal {MIN_PASSWORD} karakter."))
    panic = _read_json(F_PANIC, None)
    if panic and secrets.compare_digest(_hash(new, panic["salt"]), panic["hash"]):
        raise VaultError(T("The new password can't be the same as the panic word.", "Password baru tidak boleh sama dengan kata panik."))
    _unlock(old)                         # cek password lama (ikut hitungan salah & kata panik)
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
    _unlock(password)
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
               "keys": keys_info()}
    elif cmd == "create":
        pw, panic = line(), line()
        create(pw, panic, full)
    elif cmd == "snapshot":
        out = {"apps": snapshot()}
    elif cmd == "restore":
        out = {"apps": restore(line())}
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
    import sys
    try:
        res = {"ok": True}
        res.update(_cli(sys.argv, sys.stdin))
    except VaultError as e:
        res = {"ok": False, "error": str(e)}
    except Exception as e:                       # noqa: BLE001 — dikirim ke GUI
        res = {"ok": False, "error": f"{type(e).__name__}: {e}"}
    print(json.dumps(res))
