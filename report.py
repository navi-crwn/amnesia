#!/usr/bin/env python3
"""
AMNESIA REPORT (v5.25): laporan aman-privasi untuk minta saran ke AI, dan pemeriksa jawaban AI.

  report.py [--json] [--hide-names] [--no-dryrun]      laporan (Markdown, atau JSON)
  report.py --prompt [--lang en|id] [--hide-names]     prompt siap pakai + laporan
  report.py --save [--lang en|id] [--hide-names]       simpan prompt + laporan ke folder Keep (.md), cetak path-nya
  report.py --parse-suggestion < jawaban               baca blok ```amnesia-suggestion dari jawaban AI, cek semuanya
  report.py --mode                                     cetak mode sekarang (full|balanced|light|custom)

Isi laporan: TIDAK ada isi file dan TIDAK ada nama file/folder di bawah tingkat teratas folder home.
Pengecualian: nama folder langsung di Library/Application Support, nama app (.app) yang terpasang, dan baris Keep List.
Tidak pernah memakai internet, tidak pernah menghapus atau mengubah apa pun (kecuali --save: 1 file baru di folder Keep).
"""
import fnmatch, importlib.util, json, os, platform, re, shutil, subprocess, sys, time

HOME = os.path.normpath(os.environ.get("AMNESIA_HOME") or os.path.expanduser("~"))
A = os.path.join(HOME, ".amnesia")
# mesin (clean.sh, vault.py, presets/): di sebelah file ini (~/.amnesia), atau AMNESIA_ENGINE (tes)
ENGINE = os.environ.get("AMNESIA_ENGINE") or os.path.dirname(os.path.abspath(__file__))
KEEP_CONF = os.path.join(A, "keep.conf")
MODES = ["full", "balanced", "light", "custom"]
# v5.25: baris milik Amnesia yang tidak boleh dihapus lewat saran AI (sama dengan presets/full.conf)
REQUIRED = ["keychain:Amnesia Backup", "keychain:Amnesia VirusTotal", ".config/rclone", "keychain:* Safe Storage"]
STANDARD = {"Desktop", "Documents", "Downloads", "Library", "Movies", "Music", "Pictures", "Public", "Applications"}
MAX_INPUT = 64 * 1024
DU_ITEM, DU_BUDGET = 20, 90
BEGIN_RE = re.compile(r"^#\s*amnesia-mode:\s*([a-z]+)\s+begin\s*$")
END_RE = re.compile(r"^#\s*amnesia-mode\s+end\s*$")


# ---------------- pengaturan ----------------
def setting(key, default=""):
    try:
        with open(os.path.join(A, "settings.conf"), encoding="utf-8", errors="replace") as f:
            vals = [l.rstrip("\n")[len(key) + 1:] for l in f if l.startswith(key + "=")]
        return vals[-1] if vals else default
    except OSError:
        return default


def lang():
    return "id" if setting("LANG") == "id" else "en"


def T(en, id_):
    return id_ if lang() == "id" else en


def keep_dir():
    """Folder Keep (KEEP_DIR, default ~/Keep). Aturan sama dengan vault.py."""
    d = setting("KEEP_DIR", "~/Keep")
    if d.startswith("~/"):
        d = os.path.join(HOME, d[2:])
    if not os.path.isabs(d):
        d = os.path.join(HOME, "Keep")
    d = os.path.normpath(d)
    bad = {HOME, os.path.normpath(A), "/", "/Users", "/Volumes", "/Applications"}
    if d in bad or d.startswith(os.path.normpath(A) + os.sep) or d.count(os.sep) < 2:
        d = os.path.join(HOME, "Keep")
    return d


def keep_rel():
    """Folder Keep relatif dari home ('' kalau di luar home)."""
    d = keep_dir()
    return d[len(HOME) + 1:] if d.startswith(HOME + os.sep) else ""


def clean_text(s):
    """Tanpa karakter kontrol (nama aneh tidak merusak tabel/JSON)."""
    # v5.25: tanda format tak terlihat (mis. U+200E di nama app WhatsApp) dibuang, karakter kontrol lain jadi "?"
    import unicodedata
    return "".join(c if c.isprintable() else "?" for c in str(s) if unicodedata.category(c) != "Cf")


# ---------------- Keep List ----------------
def keep_status():
    """ok | keeplist-missing | keeplist-unreadable (sama dengan clean.sh)."""
    if os.path.lexists(KEEP_CONF):
        try:
            with open(KEEP_CONF, encoding="utf-8") as f:
                f.read()
            return "ok"
        except (OSError, UnicodeDecodeError):
            return "keeplist-unreadable"
    if os.path.lexists(os.path.join(A, "keep.conf.last")):
        return "keeplist-missing"
    return "ok"


def keep_text():
    for p in (KEEP_CONF, os.path.join(A, "keep.conf.last") if not os.path.lexists(KEEP_CONF) else None):
        if p:
            try:
                with open(p, encoding="utf-8") as f:
                    return f.read()
            except (OSError, UnicodeDecodeError):
                pass
    return ""


def split_keep(text):
    """(mode_id atau None, baris mode, baris sendiri, rusak?). Blok OK = tepat 1 begin lalu 1 end."""
    lines = [l.strip() for l in text.replace("\r", "").split("\n")]
    begins = [i for i, l in enumerate(lines) if BEGIN_RE.match(l)]
    ends = [i for i, l in enumerate(lines) if END_RE.match(l)]
    marks = [i for i, l in enumerate(lines) if l.startswith("# amnesia-mode") or l.startswith("#amnesia-mode")]
    real = lambda ls: [l for l in ls if l and not l.startswith("#")]
    if not begins and not ends and not marks:
        return None, [], real(lines), False
    if len(begins) == 1 and len(ends) == 1 and begins[0] < ends[0] and len(marks) == 2:
        b, e = begins[0], ends[0]
        return BEGIN_RE.match(lines[b]).group(1), real(lines[b + 1:e]), real(lines[:b] + lines[e + 1:]), False
    return None, [], real(lines), True


def keep_entries():
    return [l.strip() for l in keep_text().replace("\r", "").split("\n") if l.strip() and not l.strip().startswith("#")]


def preset_lines(mid):
    """Baris preset (tanpa komentar). None = tidak ada / tidak bisa dibaca / kosong."""
    try:
        with open(os.path.join(ENGINE, "presets", mid + ".conf"), encoding="utf-8") as f:
            ls = [l.strip() for l in f]
    except (OSError, UnicodeDecodeError):
        return None
    ls = [l for l in ls if l and not l.startswith("#")]
    return ls or None


def current_mode():
    """Sama dengan Keep.currentMode() di app. Tanpa file preset: pakai AMNESIA_MODE (default balanced)."""
    mid, block, _own, broken = split_keep(keep_text())
    saved = setting("AMNESIA_MODE")
    if broken:
        return "custom"
    if mid:
        pl = preset_lines(mid)
        if mid in MODES and mid != "custom" and pl is not None:
            return mid if block == pl else "custom"
        return saved if saved in MODES else "custom"
    if saved == "custom":
        return "custom"
    bal = preset_lines("balanced")
    if bal is None:
        return saved if saved in MODES else "balanced"
    have = set(keep_entries())
    return "balanced" if all(l in have for l in bal) else "custom"


MODE_TITLE = {"full": ("Retrograde Amnesia", "Retrograde Amnesia"), "balanced": ("Selective Amnesia (recommended)", "Selective Amnesia (disarankan)"),
              "light": ("Partial Amnesia", "Partial Amnesia"), "custom": ("Custom Amnesia", "Custom Amnesia")}


# ---------------- ukuran (du -sk, 20 detik per item, 90 detik total) ----------------
class Sizer:
    def __init__(self):
        self.left = DU_BUDGET
        self.cache = {}

    def __call__(self, path):
        if path in self.cache:
            return self.cache[path]
        if not os.path.lexists(path):
            self.cache[path] = 0
            return 0
        r = -1
        if self.left > 1:
            t0 = time.time()
            try:
                p = subprocess.run(["du", "-sk", path], capture_output=True, text=True,
                                   timeout=min(DU_ITEM, self.left), errors="replace")
                first = (p.stdout.split("\n") or [""])[0].split("\t")[0].strip()
                if first.isdigit():
                    r = int(first) * 1024
            except (OSError, subprocess.SubprocessError):
                r = -1
            self.left -= time.time() - t0
        self.cache[path] = r
        return r


def size_text(b):
    """v5.25 (item 194): satuan desimal (1 MB = 1000 KB), sama dengan app dan Finder."""
    if b is None or b < 0:
        return "?"
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if b < 1000 or unit == "TB":
            return (f"{b:.0f} {unit}" if unit in ("B", "KB") else f"{b:.1f} {unit}")
        b /= 1000.0
    return "?"


# ---------------- vault (lewat vault.py) ----------------
def vault_call(args, timeout=90):
    try:
        p = subprocess.run([sys.executable, os.path.join(ENGINE, "vault.py")] + args, capture_output=True, text=True,
                           timeout=timeout, stdin=subprocess.DEVNULL, errors="replace")
        last = [l for l in p.stdout.split("\n") if l.strip()]
        r = json.loads(last[-1]) if last else {}
        return r if isinstance(r, dict) and r.get("ok") else {}
    except (OSError, subprocess.SubprocessError, ValueError):
        return {}


_VAULT_MOD = None


def vault_items():
    """{nama app: [path]} dari vault.py (diimpor, hanya membaca). Kosong kalau gagal."""
    global _VAULT_MOD
    try:
        if _VAULT_MOD is None:
            spec = importlib.util.spec_from_file_location("amnesia_vault", os.path.join(ENGINE, "vault.py"))
            _VAULT_MOD = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(_VAULT_MOD)
        return {n: list(v.get("paths", [])) for n, v in _VAULT_MOD.items().items()}
    except Exception:            # noqa: BLE001 (laporan tetap jadi tanpa ini)
        return {}


def vault_names(status):
    """Nama app vault yang dikenal di Mac ini (terpasang + punya snapshot)."""
    per = ((status.get("manifest") or {}).get("per_app") or {})
    out = list(status.get("apps") or [])
    out += [n for n in per if n not in out]
    return out


def profiles_list():
    r = vault_call(["profiles"], timeout=30)
    if r.get("profiles") is not None:
        return [{"id": p.get("id", ""), "name": p.get("name", ""), "apps": list(p.get("apps") or [])}
                for p in r["profiles"] if isinstance(p, dict)]
    raw = {}
    try:
        with open(os.path.join(A, "profiles.json"), encoding="utf-8") as f:
            raw = json.load(f)
    except (OSError, ValueError):
        pass
    ps = raw.get("profiles") if isinstance(raw, dict) else None
    return [{"id": str(p.get("id", "")), "name": str(p.get("name", "")), "apps": [str(a) for a in p.get("apps") or []]}
            for p in ps or [] if isinstance(p, dict)]


# ---------------- dry-run ----------------
def dry_run():
    """Ringkasan clean.sh logout --dry-run: hanya jumlah per area, tidak ada nama file."""
    res = {"total": 0, "areas": {"Desktop": 0, "Documents": 0, "Downloads": 0, "Library": 0, "dot folders": 0, "other": 0},
           "keychain": 0, "apps": 0, "stopped": None}
    try:
        p = subprocess.run(["/bin/bash", os.path.join(ENGINE, "clean.sh"), "logout", "--dry-run"], capture_output=True,
                           text=True, timeout=300, stdin=subprocess.DEVNULL, errors="replace")
        out = p.stdout
    except (OSError, subprocess.SubprocessError):
        res["total"] = -1
        return res
    summary = None
    for line in out.split("\n"):
        parts = line.split(None, 1)
        if len(parts) < 2:
            continue
        kind, item = parts[0], parts[1].strip()
        if kind == "HAPUS":
            rel = item[2:] if item.startswith("~/") else item
            top = rel.split("/")[0]
            area = top if top in ("Desktop", "Documents", "Downloads", "Library") else \
                ("dot folders" if top.startswith(".") else "other")
            res["areas"][area] += 1
        elif kind.startswith("KEYCHAIN"):
            res["keychain"] += 1
        elif kind == "APP":
            res["apps"] += 1
        elif kind == "STOP":
            res["stopped"] = item
        elif kind == "---" and "dry-run" in item:
            m = re.search(r"\)\s*:?\s*(\d+)", item)
            summary = int(m.group(1)) if m else None
    computed = sum(res["areas"].values()) + res["keychain"] + res["apps"]
    res["total"] = summary if summary is not None else computed
    return res


# ---------------- laporan ----------------
def last_cleanup():
    try:
        with open(os.path.join(A, "history.log"), encoding="utf-8", errors="replace") as f:
            lines = [l.rstrip("\n").split("\t") for l in f]
    except OSError:
        return None
    for f in reversed(lines):
        if len(f) >= 3 and f[1] == "clean":
            w = f[2].split()
            num = lambda i: int(w[i]) if len(w) > i and w[i].lstrip("-").isdigit() else 0
            return {"time": f[0][:16], "kind": w[0] if w else "", "items": num(1), "kb": num(2), "failed": num(3)}
    return None


def state():
    if not os.path.exists(os.path.join(HOME, "Library", "LaunchAgents", "com.amnesia.agent.plist")):
        return "off"
    return "paused" if os.path.exists(os.path.join(A, "pause_once")) else "on"


def os_name():
    v = platform.mac_ver()[0]
    return f"macOS {v}" if v else f"{platform.system()} {platform.release()}"


def amnesia_version():
    for p in (os.path.join(A, ".engine_version"), os.path.join(ENGINE, ".engine_version")):
        try:
            with open(p, encoding="utf-8") as f:
                v = f.read().strip()
            if v:
                return clean_text(v)[:20]
        except OSError:
            pass
    return "?"


def installed_apps():
    dirs = [os.path.join(HOME, "Applications")]
    if not os.environ.get("AMNESIA_HOME"):       # tes: /Applications asli tidak dibaca
        dirs = ["/Applications", "/Applications/Utilities"] + dirs
    names = set()
    for d in dirs:
        try:
            for n in os.listdir(d):
                if n.endswith(".app") and not n.startswith("."):
                    names.add(clean_text(n[:-4]))
        except OSError:
            pass
    return sorted(names, key=str.lower)


def build(hide=False, dry=True):
    size = Sizer()
    status = vault_call(["status"], timeout=60)
    kst = keep_status()
    mid, block, own, broken = split_keep(keep_text())
    mode = current_mode()
    items = vault_items()

    # vault: app terpasang + snapshot + ukuran
    names = vault_names(status)
    per = ((status.get("manifest") or {}).get("per_app") or {})
    skip = set(status.get("skip") or [])
    sizes = (vault_call(["sizes"], timeout=60).get("sizes") or {}) if names else {}
    folder_n = [0]

    def app_label(n):
        """Item folder vault ('~/<folder>'): nama folder bertingkat tidak pernah ditampilkan."""
        if not n.startswith("~/"):
            return clean_text(n)
        rel = n[2:]
        if "/" not in rel and not hide:
            return "~/" + clean_text(rel)
        folder_n[0] += 1
        return f"vault folder {folder_n[0]}"

    labels = {n: app_label(n) for n in names}
    vault_apps = []
    for n in names:
        mb = sizes.get(n)
        snap = per.get(n, {}).get("time") if n in per else None
        if n in per and mb is None and per[n].get("size_mb") is not None:
            mb = per[n]["size_mb"]
        vault_apps.append({"name": labels[n], "bytes": int(mb * 1048576) if isinstance(mb, (int, float)) else -1,
                           "snapshot": snap or None, "chosen": n not in skip})

    profs = []
    for p in profiles_list():
        apps = [labels.get(a) or app_label(a) for a in p["apps"]]
        profs.append({"id": clean_text(p["id"]), "name": clean_text(p["name"]), "apps": apps})

    # folder home: hanya tingkat teratas
    home, loose_n, loose_b, k = [], 0, 0, 0
    try:
        top = sorted(os.listdir(HOME), key=str.lower)
    except OSError:
        top = []
    for n in top:
        full = os.path.join(HOME, n)
        if os.path.isdir(full) and not os.path.islink(full):
            shown = clean_text(n)
            if hide and n not in STANDARD:
                k += 1
                shown = f"folder {k}"
            home.append({"name": shown, "bytes": size(full)})
        else:
            loose_n += 1
            try:
                loose_b += os.lstat(full).st_size
            except OSError:
                pass

    # folder data app (langsung di Library/Application Support)
    owners = {}
    for app, paths in items.items():
        for p in paths:
            parts = p.split("/")
            if len(parts) >= 3 and parts[0] == "Library" and parts[1] == "Application Support":
                owners.setdefault(parts[2], app)
    asup = os.path.join(HOME, "Library", "Application Support")
    app_data, k = [], 0
    try:
        ads = sorted(os.listdir(asup), key=str.lower)
    except OSError:
        ads = []
    for n in ads:
        full = os.path.join(asup, n)
        if not os.path.isdir(full) or os.path.islink(full) or n.startswith("."):
            continue
        owner = next((a for pat, a in owners.items() if fnmatch.fnmatchcase(n, pat)), None)
        shown = clean_text(n)
        if hide and not owner:
            k += 1
            shown = f"app data {k}"
        app_data.append({"name": shown, "where": "Library/Application Support", "bytes": size(full)})

    # Keep List: baris mode tetap, baris sendiri disembunyikan kalau diminta
    def kind(line):
        return "keychain" if line.startswith("keychain:") else ("app" if line.startswith("app:") else "path")
    own_shown = [f"line {i + 1} ({kind(l)})" if hide else clean_text(l)
                 for i, l in enumerate(own)]
    # v5.25: baris yang kamu tulis sendiri DI DALAM bagian mode (bukan dari preset) juga disembunyikan
    preset_set = set(preset_lines(mid) or []) if mid else set()
    block_shown = [clean_text(l) if not hide or l in preset_set else f"mode line {i + 1} ({kind(l)})"
                   for i, l in enumerate(block)]
    kd = keep_dir()
    try:
        disk = shutil.disk_usage(HOME)
        free, total = disk.free, disk.total
    except OSError:
        free = total = -1
    nxt = dry_run() if dry else {"total": -1, "areas": {}, "keychain": -1, "apps": -1, "stopped": None}
    return {
        "schema": "amnesia-report/1",
        "made": time.strftime("%Y-%m-%d %H:%M"),
        "platform": "mac", "os": os_name(), "arch": platform.machine(), "hide_names": hide,
        "amnesia": {"version": amnesia_version(), "state": state(), "mode": mode, "last_cleanup": last_cleanup(),
                    "keep_list": kst},
        "keep_dir": {"path": "(hidden)" if hide else clean_text(kd.replace(HOME, "~", 1) if kd.startswith(HOME + "/") else kd),
                     "bytes": size(kd)},
        "keep_list": {"mode_block": {"mode": mid, "lines": block_shown} if mid else None,
                      "own": own_shown, **({"mode_section_damaged": True} if broken else {})},
        "vault": {"exists": bool(status.get("exists")), "apps": vault_apps},
        "profiles": profs,
        "home": home,
        "home_loose_files": {"count": loose_n, "bytes": loose_b},
        "app_data": app_data,
        "installed_apps": installed_apps(),
        "next_cleanup": nxt,
        "care": {"disk_free": free, "disk_total": total, "caches": size(os.path.join(HOME, "Library", "Caches")),
                 "trash": size(os.path.join(HOME, ".Trash")), "vault": size(os.path.join(A, "vault"))},
    }


def cell(s):
    return str(s).replace("|", "\\|")


def markdown(r):
    a = r["amnesia"]
    L = []
    L.append("# Amnesia report")
    L.append("")
    L.append(f"Made by Amnesia {a['version']} on {r['made']}. No file contents and no names of your files. "
             f"Folder names: {'hidden' if r['hide_names'] else 'shown'}.")
    L.append("")
    L.append("## System")
    L.append("")
    L.append(f"- OS: {r['os']} ({r['arch']})")
    L.append(f"- Amnesia: {a['version']}")
    L.append(f"- State: {a['state']}")
    L.append(f"- Mode: {a['mode']} ({MODE_TITLE.get(a['mode'], (a['mode'],))[0]})")
    lc = a["last_cleanup"]
    L.append(f"- Last cleanup: {lc['time']}, {lc['kind']}, {lc['items']} items, {size_text(lc['kb'] * 1024)}"
             + (f", {lc['failed']} failed" if lc["failed"] else "") if lc else "- Last cleanup: none yet")
    L.append(f"- Keep List: {'ok' if a['keep_list'] == 'ok' else 'stopped (' + a['keep_list'] + ')'}")
    L.append(f"- Keep folder: {r['keep_dir']['path']}, {size_text(r['keep_dir']['bytes'])}")
    L.append("")
    L.append("## Keep List")
    L.append("")
    kl = r["keep_list"]
    L.append("```text")
    if kl["mode_block"]:
        for l in kl["mode_block"]["lines"]:
            L.append(f"{l}    (from mode {kl['mode_block']['mode']})")
    for l in kl["own"]:
        L.append(l)
    if not kl["own"] and not kl["mode_block"]:
        L.append("(empty)")
    L.append("```")
    if kl.get("mode_section_damaged"):
        L.append("")
        L.append("The mode section of the Keep List is damaged, so all lines are shown as own lines.")
    L.append("")
    L.append("## Profile Vault")
    L.append("")
    v = r["vault"]
    L.append(f"Set up: {'yes' if v['exists'] else 'no'}")
    if v["apps"]:
        L.append("")
        L.append("| App | Snapshot | Size | In vault |")
        L.append("| --- | --- | --- | --- |")
        for x in v["apps"]:
            L.append(f"| {cell(x['name'])} | {x['snapshot'] or 'none'} | {size_text(x['bytes'])} | "
                     f"{'yes' if x['chosen'] else 'no'} |")
    L.append("")
    L.append("## Vault profiles")
    L.append("")
    if r["profiles"]:
        for p in r["profiles"]:
            L.append(f"- {p['name']}: {', '.join(p['apps']) or '(no apps)'}")
    else:
        L.append("None yet (restore brings back every app).")
    L.append("")
    L.append("## Home folder")
    L.append("")
    L.append("| Folder | Size |")
    L.append("| --- | --- |")
    for x in r["home"]:
        L.append(f"| {cell(x['name'])} | {size_text(x['bytes'])} |")
    lf = r["home_loose_files"]
    L.append("")
    L.append(f"{lf['count']} loose files, {size_text(lf['bytes'])}")
    L.append("")
    L.append("## App data folders")
    L.append("")
    if r["app_data"]:
        L.append("| Folder | Where | Size |")
        L.append("| --- | --- | --- |")
        for x in r["app_data"]:
            L.append(f"| {cell(x['name'])} | {x['where']} | {size_text(x['bytes'])} |")
    else:
        L.append("None.")
    L.append("")
    L.append("## Installed apps")
    L.append("")
    L.append(", ".join(r["installed_apps"]) or "None found.")
    L.append("")
    L.append("## What gets deleted at the next logout")
    L.append("")
    n = r["next_cleanup"]
    if n.get("stopped"):
        L.append(f"Nothing: the cleanup is stopped ({n['stopped']}) until the Keep List is fixed.")
    elif n["total"] < 0:
        L.append("Not checked.")
    else:
        L.append(f"- Total: {n['total']} items")
        for k, c in n["areas"].items():
            L.append(f"- {k}: {c}")
        L.append(f"- Keychain items: {n['keychain']}")
        L.append(f"- Apps installed this session: {n['apps']}")
    L.append("")
    L.append("## Care overview")
    L.append("")
    c = r["care"]
    L.append(f"- Disk: {size_text(c['disk_free'])} free of {size_text(c['disk_total'])}")
    L.append(f"- Caches: {size_text(c['caches'])}")
    L.append(f"- Trash: {size_text(c['trash'])}")
    L.append(f"- Keep folder: {size_text(r['keep_dir']['bytes'])}")
    L.append(f"- Vault: {size_text(c['vault'])}")
    L.append("")
    return "\n".join(L)


# ---------------- prompt ----------------
EXAMPLE = ('```amnesia-suggestion\n'
           '{"mode": "balanced", "keep_add": [], "keep_remove": [], "profiles": {"Work": []}, "notes": ""}\n'
           '```')

PROMPT_EN = (
    "I use Amnesia, a privacy app that wipes my home folder at every logout, except my Keep folder, the lines on my "
    "Keep List and the apps saved in its Profile Vault. Below is a report Amnesia made about my computer. It has no "
    "file contents and no names of my files. Please help me choose the best settings. Explain in simple words what is "
    "wiped today and what I might lose, and what I could safely keep or stop keeping. Modes I can pick: full (only the "
    "Keep folder and Amnesia itself survive), balanced (Keep folder, app logins through the vault, terminal tools), "
    "light (apps keep settings and logins; my files, Downloads, Desktop, caches, logs, Trash and shell history are "
    "wiped), custom (my own list). Vault profiles group vault apps so I restore only what I need, for example Work and "
    "Personal. Use only app names from the report's Profile Vault section. Keep List lines are paths relative to my "
    "home folder, or keychain:<name> on a Mac. Never suggest removing Amnesia's own lines. At the end, give your "
    "suggestion in exactly one block like this:\n" + EXAMPLE + "\n"
    "Use null for mode if you would not change it. Amnesia shows me every change with a checkbox, and nothing is "
    "applied until I confirm.")

PROMPT_ID = (
    "Saya memakai Amnesia, app privasi yang menghapus folder home saya setiap logout, kecuali folder Keep saya, "
    "baris-baris di Keep List saya dan app yang disimpan di Profile Vault-nya. Di bawah ini ada laporan yang dibuat "
    "Amnesia tentang komputer saya. Laporan ini tidak berisi isi file dan tidak berisi nama file saya. Tolong bantu "
    "saya memilih pengaturan terbaik. Jelaskan dengan kata-kata sederhana apa yang dihapus sekarang dan apa yang "
    "mungkin hilang, serta apa yang aman untuk disimpan atau berhenti disimpan. Mode yang bisa saya pilih: full (hanya "
    "folder Keep dan Amnesia sendiri yang tetap ada), balanced (folder Keep, login app lewat vault, alat terminal), "
    "light (app tetap menyimpan pengaturan dan login; file saya, Downloads, Desktop, cache, log, Trash dan riwayat "
    "terminal dihapus), custom (daftar saya sendiri). Profil vault mengelompokkan app di vault supaya saya hanya "
    "me-restore yang saya perlukan, misalnya Kerja dan Santai. Pakai hanya nama app dari bagian Profile Vault di "
    "laporan. Baris Keep List adalah path relatif dari folder home saya, atau keychain:<nama> di Mac. Jangan pernah "
    "menyarankan menghapus baris milik Amnesia sendiri. Jawab dalam bahasa Indonesia. Di akhir, berikan saranmu "
    "dalam tepat satu blok seperti ini:\n" + EXAMPLE + "\n"
    "Pakai null untuk mode kalau kamu tidak akan menggantinya. Amnesia menampilkan setiap perubahan dengan kotak "
    "centang, dan tidak ada yang diterapkan sebelum saya konfirmasi.")


def prompt_text(lng, report_md):
    # pagar 4 backtick: laporan sendiri berisi blok ``` (Keep List)
    return (PROMPT_ID if lng == "id" else PROMPT_EN) + "\n\n````markdown\n" + report_md.rstrip("\n") + "\n````\n"


def save(lng, hide):
    d = keep_dir()
    os.makedirs(d, exist_ok=True)
    base = time.strftime("Amnesia report %Y-%m-%d %H%M")
    path, i = os.path.join(d, base + ".md"), 2
    while os.path.lexists(path):
        path, i = os.path.join(d, f"{base} {i}.md"), i + 1
    text = prompt_text(lng, markdown(build(hide)))
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(text)
    return path


# ---------------- jawaban AI: blok ```amnesia-suggestion ----------------
FENCE_OPEN = re.compile(r"^\s*(`{3,}|~{3,})\s*amnesia-suggestion\s*$", re.IGNORECASE)
TAG_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_-]*:")


def extract_block(text):
    lines = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    for i, l in enumerate(lines):
        if FENCE_OPEN.match(l):
            body = []
            for l2 in lines[i + 1:]:
                if l2.strip().startswith("```") or l2.strip().startswith("~~~"):
                    break
                body.append(l2)
            return "\n".join(body)
    return None


def check_line(raw):
    """(baris yang sudah dirapikan, None) atau (None, alasan)."""
    if not isinstance(raw, str):
        return None, "not-text"
    s = raw.strip()
    if any(ord(c) < 32 or ord(c) == 127 for c in s):
        return None, "control-character"
    if len(s) > 300:
        return None, "too-long"
    if s.startswith("~/"):
        s = s[2:]
    if not s:
        return None, "empty"
    if s.startswith("keychain:"):
        return (s, None) if s[9:].strip() else (None, "empty")
    if TAG_RE.match(s):
        return None, "unknown-tag"
    if s.startswith("/") or s.startswith("\\") or s.startswith("~") or re.match(r"^[A-Za-z]:", s):
        return None, "absolute"
    while "//" in s:
        s = s.replace("//", "/")
    s = s.rstrip("/")
    parts = s.split("/")
    if any(p in ("..", ".") for p in parts):
        return None, "dots"
    if not s:
        return None, "empty"
    if s.startswith(".amnesia") or s.startswith(".Trash"):
        return None, "protected"
    kr = keep_rel()
    if kr and (s == kr or s.startswith(kr + "/")):
        return None, "in-keep-folder"
    if set(parts[0]) <= set("*?"):
        return None, "wildcard-top"
    return s, None


def parse_suggestion(text, vault_known=None):
    if len(text.encode("utf-8", "replace")) > MAX_INPUT:
        return {"ok": False, "error": "too-big"}
    body = extract_block(text)
    if body is None:
        return {"ok": False, "error": "no-block"}
    try:
        data = json.loads(body)
    except ValueError:
        return {"ok": False, "error": "bad-json"}
    if not isinstance(data, dict):
        return {"ok": False, "error": "not-object"}
    out = {"ok": True, "mode": None, "keep_add": [], "keep_remove": [], "profiles": {}, "notes": "",
           "rejected": [], "skipped": [], "ignored_apps": []}
    rej = lambda item, why: out["rejected"].append({"item": clean_text(item)[:300], "why": why})
    skp = lambda item, why: out["skipped"].append({"item": clean_text(item)[:300], "why": why})

    m = data.get("mode")
    if m is not None:
        if isinstance(m, str) and m.strip().lower() in MODES:
            out["mode"] = m.strip().lower()
        else:
            rej(m if isinstance(m, str) else json.dumps(m), "unknown-mode")

    have = set(l[2:] if l.startswith("~/") else l for l in keep_entries())

    def lst(key):
        v = data.get(key)
        if v is None:
            return []
        if not isinstance(v, list):
            rej(key, "not-a-list")
            return []
        for x in v[200:]:
            rej(x if isinstance(x, str) else json.dumps(x), "too-many")
        return v[:200]

    for x in lst("keep_add"):
        s, why = check_line(x)
        if why:
            rej(x if isinstance(x, str) else json.dumps(x), why)
        elif s in have:
            skp(s, "already-kept")
        elif s in out["keep_add"]:
            skp(s, "duplicate")
        else:
            out["keep_add"].append(s)
    for x in lst("keep_remove"):
        s, why = check_line(x)
        if why:
            rej(x if isinstance(x, str) else json.dumps(x), why)
        elif s in REQUIRED:
            rej(s, "required")
        elif s not in have:
            skp(s, "not-on-list")
        elif s in out["keep_remove"]:
            skp(s, "duplicate")
        elif s in out["keep_add"]:
            rej(s, "conflict")
        else:
            out["keep_remove"].append(s)

    profs = data.get("profiles")
    if profs is not None and not isinstance(profs, dict):
        rej("profiles", "not-an-object")
        profs = {}
    if profs:
        known = vault_known if vault_known is not None else vault_names(vault_call(["status"], timeout=60))
        canon = {n.lower(): n for n in known}
        seen = set()
        for i, (name, apps) in enumerate(profs.items()):
            nm = name.strip() if isinstance(name, str) else ""
            if i >= 10:
                rej(nm, "too-many")
                continue
            if not nm or len(nm) > 40 or any(ord(c) < 32 or ord(c) == 127 for c in nm):
                rej(nm, "bad-name")
                continue
            if nm.lower() in ("everything", "semua", "all"):
                rej(nm, "reserved")
                continue
            if nm.lower() in seen:
                skp(nm, "duplicate")
                continue
            if not isinstance(apps, list):
                rej(nm, "not-a-list")
                continue
            good = []
            for a in apps[:200]:
                c = canon.get(a.strip().lower()) if isinstance(a, str) else None
                if c is None:
                    bad = clean_text(a if isinstance(a, str) else json.dumps(a))[:80]
                    if bad not in out["ignored_apps"]:
                        out["ignored_apps"].append(bad)
                elif c not in good:
                    good.append(c)
            if not good:
                rej(nm, "no-known-apps")
                continue
            seen.add(nm.lower())
            out["profiles"][nm] = good

    notes = data.get("notes")
    if isinstance(notes, str):
        out["notes"] = notes[:2000]
    return out


# ---------------- CLI ----------------
def main(argv):
    args = argv[1:]
    known = {"--json", "--hide-names", "--no-dryrun", "--prompt", "--save", "--parse-suggestion", "--mode", "--lang"}
    lng = lang()
    if "--lang" in args:
        i = args.index("--lang")
        lng = args[i + 1] if i + 1 < len(args) and args[i + 1] in ("en", "id") else None
        if lng is None:
            print("report.py: --lang needs en or id", file=sys.stderr)
            return 2
        args = args[:i] + args[i + 2:]
    bad = [a for a in args if a not in known]
    if bad:
        print("report.py: unknown option " + " ".join(bad), file=sys.stderr)
        return 2
    hide = "--hide-names" in args
    if "--parse-suggestion" in args:
        data = sys.stdin.buffer.read(MAX_INPUT + 1).decode("utf-8", "replace")
        print(json.dumps(parse_suggestion(data)))
        return 0
    if "--mode" in args:
        print(current_mode())
        return 0
    if "--save" in args:
        try:
            print(save(lng, hide))
        except OSError as e:
            print(f"report.py: could not save: {e.strerror}", file=sys.stderr)
            return 1
        return 0
    r = build(hide, dry="--no-dryrun" not in args)
    if "--json" in args:
        print(json.dumps(r, indent=2))
    elif "--prompt" in args:
        sys.stdout.write(prompt_text(lng, markdown(r)))
    else:
        sys.stdout.write(markdown(r))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
