#!/usr/bin/env python3
"""v5.25: tes report.py (laporan untuk AI, pemeriksa jawaban AI) dan perintah Terminal bin/amnesia.
Semua di home palsu (AMNESIA_HOME), tidak pernah home asli. Jalankan: timeout 300 python3 test_report.py"""
import json, os, shutil, stat, subprocess, sys, tempfile

REPO = os.path.dirname(os.path.abspath(__file__))
fails = 0


def check(cond, name):
    global fails
    print(("ok   " if cond else "FAIL ") + name)
    if not cond:
        fails += 1


def write(path, text=""):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)


tmp = tempfile.mkdtemp(prefix="amnesia-report-test-")
H = os.path.join(tmp, "home")
A = os.path.join(H, ".amnesia")
ENG = os.path.join(tmp, "engine")
os.makedirs(A)
os.makedirs(ENG)
for f in ("clean.sh", "vault.py", "report.py", "keep.example.conf"):
    shutil.copy(os.path.join(REPO, f), ENG)
# preset "balanced" untuk tes: hanya 2 baris (file preset asli dibuat di cabang lain)
write(os.path.join(ENG, "presets", "balanced.conf"), "## test preset\n.ssh\nkeychain:* Safe Storage\n")
write(os.path.join(ENG, "presets", "full.conf"),
      "keychain:Amnesia Backup\nkeychain:Amnesia VirusTotal\n.config/rclone\nkeychain:* Safe Storage\n")

# home palsu dengan nama yang TIDAK boleh muncul di laporan
write(os.path.join(H, "Desktop", "private-diary-XYZ.txt"), "secret content QQQ")
write(os.path.join(H, "Documents", "secret-project-ABC", "topsecret-DEF.txt"), "more secret content QQQ")
write(os.path.join(H, "Downloads", "bank-statement-GHI.pdf"), "x")
write(os.path.join(H, "Library", "Application Support", "Claude", "config.json"), "{}")
write(os.path.join(H, "Library", "Application Support", "Google", "Chrome", "Default", "Cookies"), "x")
write(os.path.join(H, "Library", "Application Support", "HiddenVendorApp", "data-JKL.db"), "x")
write(os.path.join(H, "Library", "Caches", "cache-file-MNO"), "x" * 5000)
write(os.path.join(H, "MyPrivateTopFolder", "inner-PQR.txt"), "x")
write(os.path.join(H, ".config", "gh", "hosts.yml"), "token: STU")
write(os.path.join(H, ".zsh_history", ), "ls\n")
write(os.path.join(H, "Keep", "kept-file-VWX.txt"), "x")
os.makedirs(os.path.join(H, "Applications", "TestApp.app"))
write(os.path.join(A, "settings.conf"), "LANG=en\nAMNESIA_MODE=balanced\n")
write(os.path.join(A, ".engine_version"), "5.25.0\n")
write(os.path.join(A, "history.log"), "2026-10-25 10:00:00\tclean\tlogout 120 20480 0\n"
      "2026-10-25 10:05:00\tsnapshot\tClaude\n")
KEEP = ("# amnesia-mode: balanced begin\n"
        "# Amnesia writes the lines between these markers when you pick a mode. Put your own lines below the end marker.\n"
        ".ssh\nkeychain:* Safe Storage\n# amnesia-mode end\n"
        "Projects/client-secret-YZ\nkeychain:MyBank-Token\n.config/rclone\n")
write(os.path.join(A, "keep.conf"), KEEP)

env = dict(os.environ, AMNESIA_HOME=H, AMNESIA_ENGINE=ENG)
SECRETS = ["private-diary-XYZ", "secret-project-ABC", "topsecret-DEF", "bank-statement-GHI", "data-JKL", "cache-file-MNO",
           "inner-PQR", "hosts.yml", "STU", "QQQ", "kept-file-VWX", "Cookies", "config.json", "Default"]


def run(args, inp=None):
    return subprocess.run([sys.executable, os.path.join(ENG, "report.py")] + args, env=env, capture_output=True,
                          text=True, input=inp, timeout=280)


def files_snapshot():
    out = []
    for root, dirs, files in os.walk(H):
        for n in dirs + files:
            out.append(os.path.relpath(os.path.join(root, n), H))
    return sorted(out)


before = files_snapshot()

# ---------- laporan Markdown ----------
r = run([])
md = r.stdout
check(r.returncode == 0, "report.py runs")
check(md.startswith("# Amnesia report"), "markdown starts with the title")
for s in SECRETS:
    check(s not in md, f"markdown has no '{s}'")
for sec in ("## System", "## Keep List", "## Profile Vault", "## Vault profiles", "## Home folder", "## App data folders",
            "## Installed apps", "## What gets deleted at the next logout", "## Care overview"):
    check(sec in md, f"markdown has section {sec}")
check("| Documents |" in md and "| MyPrivateTopFolder |" in md, "top-level folder names are shown")
check("| Claude |" in md and "HiddenVendorApp" in md, "app data folder names are shown")
check("TestApp" in md, "installed app names are shown")
check(".ssh    (from mode balanced)" in md, "mode lines are labelled")
check("Projects/client-secret-YZ" in md, "own Keep List lines are shown")
check("Mode: balanced" in md, "mode is balanced (block equals the preset)")
check("Made by Amnesia 5.25.0" in md, "version from .engine_version")
check("Last cleanup: 2026-10-25 10:00, logout, 120 items" in md, "last cleanup from history")

# ---------- JSON ----------
r = run(["--json"])
j = json.loads(r.stdout)
check(j["schema"] == "amnesia-report/1" and j["platform"] == "mac", "json schema + platform")
for k in ("made", "os", "arch", "hide_names", "amnesia", "keep_dir", "keep_list", "vault", "profiles", "home",
          "home_loose_files", "app_data", "installed_apps", "next_cleanup", "care"):
    check(k in j, f"json has '{k}'")
check(j["amnesia"]["keep_list"] == "ok", "json keep_list ok")
check(j["keep_list"]["mode_block"] == {"mode": "balanced", "lines": [".ssh", "keychain:* Safe Storage"]}, "json mode block")
check(j["keep_list"]["own"] == ["Projects/client-secret-YZ", "keychain:MyBank-Token", ".config/rclone"], "json own lines")
names = [a["name"] for a in j["vault"]["apps"]]
check("Claude" in names and "Chrome" in names and "GitHub CLI" in names, "vault apps listed (installed)")
check(j["next_cleanup"]["areas"]["Desktop"] == 1 and j["next_cleanup"]["areas"]["Downloads"] == 1,
      "dry-run counts per area")
check(j["next_cleanup"]["total"] >= 5 and j["next_cleanup"]["stopped"] is None, "dry-run total")
check(j["home_loose_files"]["count"] == 1, "loose files counted (.zsh_history), not named")
raw = json.dumps(j)
for s in SECRETS:
    check(s not in raw, f"json has no '{s}'")

# ---------- --hide-names ----------
r = run(["--json", "--hide-names"])
jh = json.loads(r.stdout)
raw = json.dumps(jh)
for s in ("MyPrivateTopFolder", "HiddenVendorApp", "Projects/client-secret-YZ", "MyBank-Token"):
    check(s not in raw, f"--hide-names hides '{s}'")
hn = [x["name"] for x in jh["home"]]
check("Documents" in hn and "Library" in hn and "folder 1" in hn, "--hide-names keeps standard names, numbers the rest")
ad = [x["name"] for x in jh["app_data"]]
check("Claude" in ad and "Google" in ad and any(n.startswith("app data") for n in ad),
      "--hide-names keeps vault app data names, numbers the rest")
check(jh["keep_dir"]["path"] == "(hidden)", "--hide-names hides the Keep folder path")
check(jh["keep_list"]["own"] == ["line 1 (path)", "line 2 (keychain)", "line 3 (path)"], "--hide-names numbers own lines")
check(jh["keep_list"]["mode_block"]["lines"] == [".ssh", "keychain:* Safe Storage"], "--hide-names keeps mode lines")
check("Folder names: hidden" in run(["--hide-names", "--no-dryrun"]).stdout, "markdown says names are hidden")

# ---------- prompt ----------
p = run(["--prompt", "--lang", "en", "--no-dryrun"]).stdout
check(p.startswith("I use Amnesia") and "```amnesia-suggestion" in p and "````markdown\n# Amnesia report" in p,
      "prompt EN with report in a fence")
p = run(["--prompt", "--lang", "id", "--no-dryrun"]).stdout
check(p.startswith("Saya memakai Amnesia") and "bahasa Indonesia" in p and '"keep_add": []' in p, "prompt ID")
check(run(["--bogus"]).returncode == 2, "unknown option refused")

# laporan tidak mengubah apa pun di home
check(files_snapshot() == before, "report changes nothing in the home folder")

# ---------- --save ----------
r = run(["--save", "--no-dryrun"])
path = r.stdout.strip()
check(r.returncode == 0 and os.path.dirname(path) == os.path.join(H, "Keep") and path.endswith(".md")
      and os.path.basename(path).startswith("Amnesia report "), "--save writes into the Keep folder")
check(stat.S_IMODE(os.stat(path).st_mode) == 0o600, "--save file is mode 600")
os.remove(path)

# ---------- mode detection ----------
check(run(["--mode"]).stdout.strip() == "balanced", "--mode: block equals preset")
write(os.path.join(A, "keep.conf"), KEEP.replace(".ssh\n", ".ssh\n.extra\n", 1))
check(run(["--mode"]).stdout.strip() == "custom", "--mode: edited block = custom")
# v5.25 (audit): a line the user wrote inside the mode block is hidden too
jx = json.loads(run(["--json", "--hide-names", "--no-dryrun"]).stdout)
check(jx["keep_list"]["mode_block"]["lines"] == [".ssh", "mode line 2 (path)", "keychain:* Safe Storage"],
      "--hide-names hides own lines inside the mode block")
write(os.path.join(A, "keep.conf"), KEEP + "# amnesia-mode: full begin\n")
check(run(["--mode"]).stdout.strip() == "custom", "--mode: damaged block = custom")
jb = json.loads(run(["--json", "--no-dryrun"]).stdout)
check(jb["keep_list"]["mode_block"] is None and jb["keep_list"].get("mode_section_damaged") is True,
      "damaged block reported")
write(os.path.join(A, "keep.conf"), KEEP)

# ---------- parser: blok amnesia-suggestion ----------
def parse(obj_or_text, raw_text=False):
    text = obj_or_text if raw_text else "Here you go:\n```amnesia-suggestion\n" + json.dumps(obj_or_text) + "\n```\nbye"
    out = run(["--parse-suggestion"], inp=text)
    return json.loads(out.stdout)


def why(res, item):
    return [x["why"] for x in res["rejected"] + res["skipped"] if x["item"] == item]


check(parse("no block here", True) == {"ok": False, "error": "no-block"}, "parser: no-block")
check(parse("```amnesia-suggestion\n{bad json\n```", True)["error"] == "bad-json", "parser: bad-json")
check(parse("```amnesia-suggestion\n[1,2]\n```", True)["error"] == "not-object", "parser: not-object")
check(parse("x" * (64 * 1024 + 10), True)["error"] == "too-big", "parser: too-big")
check(parse("```Amnesia-Suggestion\n{\"mode\": \"light\"}\n```", True)["mode"] == "light", "parser: fence case-insensitive")
check(parse("```json\n{\"mode\": \"full\"}\n```\n```amnesia-suggestion\n{\"mode\": \"light\"}\n```", True)["mode"] == "light",
      "parser: first amnesia-suggestion fence, not other fences")
res = parse({"mode": "turbo"})
check(res["ok"] and res["mode"] is None and why(res, "turbo") == ["unknown-mode"], "parser: unknown mode rejected")
check(parse({"mode": None})["mode"] is None, "parser: null mode")
res = parse({"keep_add": ["../etc", "Documents/../..", "/etc/passwd", "~/Work/Notes", "~/.ssh", "./x", "a/./b",
                          "C:/Windows", "\\\\server\\share", ".amnesia/vault", ".amnesia-trash", ".Trash/x",
                          "Keep/sub", "*", "**/x", "?/y", "keychain:", "keychain:Work VPN", "app:/Applications/X.app",
                          "foo\nbar", "x" * 301, "", 42, "Work/Notes", "~/Library/Application Support/Claude"]})
check(res["keep_add"] == ["Work/Notes", "keychain:Work VPN", "Library/Application Support/Claude"], "parser: keep_add accepted items")
for item, w in (("../etc", "dots"), ("Documents/../..", "dots"), ("/etc/passwd", "absolute"), ("./x", "dots"),
                ("a/./b", "dots"), ("C:/Windows", "unknown-tag"), ("\\\\server\\share", "absolute"),
                (".amnesia/vault", "protected"), (".amnesia-trash", "protected"), (".Trash/x", "protected"),
                ("Keep/sub", "in-keep-folder"), ("*", "wildcard-top"), ("**/x", "wildcard-top"), ("?/y", "wildcard-top"),
                ("keychain:", "empty"), ("app:/Applications/X.app", "unknown-tag"), ("foo?bar", "control-character"),
                ("x" * 300, "too-long"), ("", "empty"), ("42", "not-text"), ("~/.ssh", None)):
    if w:
        check(w in why(res, item), f"parser: keep_add '{item[:30]}' -> {w}")
check(why(res, ".ssh") == ["already-kept"], "parser: already kept is skipped")
check(why(res, "Work/Notes") == ["duplicate"], "parser: duplicate is skipped")
res = parse({"keep_remove": ["keychain:* Safe Storage", ".config/rclone", "keychain:MyBank-Token", "Not/On/List",
                             "../x", "/abs"]})
check(res["keep_remove"] == ["keychain:MyBank-Token"], "parser: keep_remove accepted only a listed own line")
check(why(res, "keychain:* Safe Storage") == ["required"] and why(res, ".config/rclone") == ["required"],
      "parser: Amnesia's required lines can't be removed")
check(why(res, "Not/On/List") == ["not-on-list"], "parser: remove of a line not on the list is skipped")
check(why(res, "../x") == ["dots"] and why(res, "/abs") == ["absolute"], "parser: keep_remove path rules")
res = parse({"profiles": {"Work": ["claude", "Chrome", "NotAnApp"], "Everything": ["Claude"], "semua": ["Claude"],
                          "ALL": ["Claude"], "": ["Claude"], "x" * 41: ["Claude"], "Empty": ["Nope"],
                          "Personal": "Claude"}})
check(res["profiles"] == {"Work": ["Claude", "Chrome"]}, "parser: profiles keep known apps (case-insensitive)")
check("NotAnApp" in res["ignored_apps"] and "Nope" in res["ignored_apps"], "parser: unknown apps ignored")
for n in ("Everything", "semua", "ALL"):
    check(why(res, n) == ["reserved"], f"parser: profile name '{n}' reserved")
check(why(res, "") == ["bad-name"] and why(res, "x" * 41) == ["bad-name"], "parser: bad profile names")
check(why(res, "Empty") == ["no-known-apps"] and why(res, "Personal") == ["not-a-list"], "parser: empty/invalid profiles")
res = parse({"profiles": {f"P{i}": ["Claude"] for i in range(12)}})
check(len(res["profiles"]) == 10 and why(res, "P11") == ["too-many"], "parser: at most 10 profiles")
res = parse({"keep_add": [f"Dir{i}" for i in range(205)]})
check(len(res["keep_add"]) == 200 and why(res, "Dir204") == ["too-many"], "parser: at most 200 items")
res = parse({"notes": "<b>hi</b>" + "n" * 3000, "unknown_key": 1})
check(res["ok"] and len(res["notes"]) == 2000 and res["notes"].startswith("<b>hi</b>"), "parser: notes cut at 2000, kept as text")
check(files_snapshot() == before, "parser changes nothing in the home folder")

# ---------- perintah Terminal (bin/amnesia) ----------
CLI = os.path.join(REPO, "bin", "amnesia")
check(os.access(CLI, os.X_OK), "bin/amnesia is executable")
# clean.sh palsu: mencatat argumennya, supaya terlihat bahwa amnesia hanya memakai --dry-run
FAKE = os.path.join(tmp, "fake-engine")
os.makedirs(FAKE)
LOG = os.path.join(tmp, "args.log")
write(os.path.join(FAKE, "clean.sh"), f'#!/bin/bash\necho "$*" >> "{LOG}"\n'
      'echo "HAPUS  ~/Desktop/a"\necho "HAPUS  ~/.zsh_history"\necho "KEYCHAIN  x"\n'
      'echo "--- dry-run (logout): 3 items would be deleted. Nothing was deleted. ---"\n')
shutil.copy(os.path.join(REPO, "report.py"), FAKE)


def cli(args, engine=ENG):
    e = dict(env, AMNESIA_ENGINE=engine)
    return subprocess.run(["/bin/bash", CLI] + args, env=e, capture_output=True, text=True, timeout=280, stdin=subprocess.DEVNULL)


r = cli(["preview"], FAKE)
check(r.returncode == 0 and "Desktop:      1" in r.stdout and "3 items would be deleted" in r.stdout, "cli preview summarises")
with open(LOG) as f:
    calls = f.read().split("\n")
check([c for c in calls if c] == ["logout --dry-run"], "cli preview runs clean.sh only with 'logout --dry-run'")
r = cli(["preview"])           # clean.sh asli di home palsu
check(r.returncode == 0 and "Nothing was deleted" in r.stdout and "Desktop:      1" in r.stdout, "cli preview with the real clean.sh")
check(files_snapshot() == before, "cli preview deletes nothing")
r = cli(["status"])
check(r.returncode == 0 and "Amnesia 5.25.0" in r.stdout and "State: off" in r.stdout
      and "Mode: Selective Amnesia (recommended)" in r.stdout and "Keep List: ok (5 lines)" in r.stdout
      and "Vault: not set up" in r.stdout and "120 items" in r.stdout, "cli status")
# v5.25 (item 194): satuan desimal seperti app dan Finder: 20480 KB (du) = 20,97 MB -> "21.0 MB" (dulu 1024: "20.0 MB")
check("21.0 MB" in r.stdout, "cli status: decimal MB like the app (194)")
sz = subprocess.run([sys.executable, "-I", "-c", "import sys; sys.path.insert(0, sys.argv[1]); import report as r; "
                     "print(r.size_text(1500000), r.size_text(999), r.size_text(2_000_000_000), sep='|')", ENG],
                    capture_output=True, text=True, timeout=60, env=env)
check(sz.stdout.strip() == "1.5 MB|999 B|2.0 GB", "report size_text uses 1000 (194): " + sz.stdout.strip() + sz.stderr[-200:])
r = cli(["keep"])
check("=== Mode section (balanced)" in r.stdout and "  | .ssh" in r.stdout and "Projects/client-secret-YZ" in r.stdout,
      "cli keep marks the mode section")
r = cli(["history", "5"])
check("Wiped at logout" in r.stdout and "Snapshot" in r.stdout, "cli history")
r = cli(["report", "--json", "--hide-names", "--no-dryrun"])
check(r.returncode == 0 and json.loads(r.stdout)["hide_names"] is True, "cli report passes flags")
for bad in (["bogus"], ["report", "--save"], ["report", "--parse-suggestion"], ["preview", "--really"],
            ["history", "abc"], ["status", "x"], ["report", "--lang", "fr"]):
    check(cli(bad).returncode == 2, f"cli refuses {' '.join(bad)}")
check(cli(["help"]).returncode == 0 and "never deletes" in cli(["help"]).stdout, "cli help")
os.rename(os.path.join(A, "keep.conf"), os.path.join(A, "keep.conf.moved"))
write(os.path.join(A, "keep.conf.last"), KEEP)
r = cli(["status"])
check("Keep List: STOPPED (keeplist-missing)" in r.stdout, "cli status shows a stopped Keep List")
r = cli(["preview"])
check("STOPPED (keeplist-missing)" in r.stdout, "cli preview shows the stop")
check(json.loads(run(["--json", "--no-dryrun"]).stdout)["amnesia"]["keep_list"] == "keeplist-missing",
      "report shows keeplist-missing")
with open(CLI) as f:
    src = f.read()
import re
code = "\n".join(l for l in src.split("\n") if not l.lstrip().startswith("#"))
check(not re.search(r"\b(rm|mv|cp|ln|tee|touch|mkdir|chmod|security|defaults)\s", code) and ">>" not in code
      and not re.search(r'>\s*"?\$', code), "cli source has no rm, mv or file writes")
runs = re.findall(r'bash\s+"\$E/clean\.sh"([^\n]*)', code)
check(len(runs) == 1 and runs[0].startswith(" logout --dry-run "),
      "cli runs clean.sh in exactly one place, with --dry-run")

shutil.rmtree(tmp, ignore_errors=True)
if fails:
    print(f"FAILED: {fails} report tests")
    sys.exit(1)
print("OK: all report tests passed")
