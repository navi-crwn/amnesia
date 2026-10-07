#!/usr/bin/env python3
"""Tes vault di home PALSU:  python3 test_vault.py   (butuh 7zz/7z + openssl)"""
import os, shutil, subprocess, sys, tempfile
T = tempfile.mkdtemp()
os.environ["AMNESIA_HOME"] = T
if not os.path.exists(os.environ.get("AMNESIA_7Z", "/opt/homebrew/bin/7zz")):
    os.environ["AMNESIA_7Z"] = shutil.which("7zz") or shutil.which("7z")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vault as v

def mk(rel, text):
    p = os.path.join(T, rel); os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, "w").write(text)

def expect_error(fn, text):
    try: fn()
    except v.VaultError as e: assert text in str(e), str(e); return
    raise AssertionError("expected an error: " + text)

try:
    PW = "password-panjang-123"
    mk("Library/Application Support/Google/Chrome/Default/Cookies", "login-gmail")
    mk("Library/Application Support/Google/Chrome/Default/Cache/big", "cache")
    mk("Library/Application Support/Google/Chrome/Default/Extensions/abc/1.0/main.js", "extension-code")
    mk("Library/Application Support/Google/Chrome/Default/Local Extension Settings/abc/000003.log", "ext-login")
    # abc dari Web Store (bisa diunduh ulang), xyz dipasang manual (harus tetap ikut snapshot)
    mk("Library/Application Support/Google/Chrome/Default/Secure Preferences",
       '{"extensions": {"settings": {"abc": {"from_webstore": true}, "xyz": {"from_webstore": false}}}}')
    mk("Library/Application Support/Google/Chrome/Default/Extensions/xyz/2.0/manual.js", "manual-ext")
    mk("Library/Application Support/Google/Chrome/Default/Extensions/xyz/2.0/manifest.json", '{"name": "manual"}')
    mk("Library/Application Support/Claude/config.json", "login-claude")
    mk(".local/share/opencode/auth.json", "token-opencode")
    mk(".claude.json", "token-claude-code")
    mk("Library/Group Containers/group.net.whatsapp.WhatsApp.shared/ChatStorage.sqlite", "chat-wa")
    expect_error(lambda: v.create("pendek"), "at least")
    v.create(PW, panic_word="deletesemua")
    assert v.snapshot() == ["Chrome", "Claude", "OpenCode", "Claude Code", "WhatsApp"]
    # vault tidak boleh berisi teks asli (1 arsip per app)
    raw = open(v._app_files("Chrome")[0], "rb").read()
    assert b"login-gmail" not in raw and b"Cookies" not in raw
    sz = v.sizes()
    # ukuran yang ditampilkan mengikuti mode ringan: extension Web Store (abc) tidak dihitung
    big = os.path.join(T, "Library/Application Support/Google/Chrome/Default/Extensions/abc/1.0/big.bin")
    open(big, "wb").write(b"x" * 3 * 1048576)
    assert v.sizes()["Chrome"] < 1, v.sizes()
    os.remove(big)
    assert set(sz) == {"Chrome", "Claude", "OpenCode", "Claude Code", "WhatsApp"} and all(x >= 0 for x in sz.values())
    # simulasi amnesia: data hilang
    shutil.rmtree(os.path.join(T, "Library")); shutil.rmtree(os.path.join(T, ".local")); os.remove(os.path.join(T, ".claude.json"))
    # salah 1x, lalu benar -> counter reset
    expect_error(lambda: v.restore("salah-salah-salah"), "Tries left: 2")
    names, checks = v.restore(PW)
    assert names == ["Chrome", "Claude", "OpenCode", "Claude Code", "WhatsApp"] and v.attempts() == 0
    assert all(c["ok"] for c in checks), checks
    assert not os.path.exists(v.F_STAGE)
    assert open(os.path.join(T, "Library/Application Support/Google/Chrome/Default/Cookies")).read() == "login-gmail"
    assert open(os.path.join(T, ".local/share/opencode/auth.json")).read() == "token-opencode"
    assert open(os.path.join(T, ".claude.json")).read() == "token-claude-code"
    assert open(os.path.join(T, "Library/Group Containers/group.net.whatsapp.WhatsApp.shared/ChatStorage.sqlite")).read() == "chat-wa"
    assert not os.path.exists(os.path.join(T, "Library/Application Support/Google/Chrome/Default/Cache"))
    # mode ringan (default): program extension tidak ikut, data/login extension ikut
    assert not os.path.exists(os.path.join(T, "Library/Application Support/Google/Chrome/Default/Extensions/abc"))
    assert open(os.path.join(T, "Library/Application Support/Google/Chrome/Default/Extensions/xyz/2.0/manual.js")).read() == "manual-ext"
    assert v._load_manifest()["Chrome"]["light"] and not v._load_manifest()["Claude"]["light"]
    # snapshot otomatis (--changed): app yang tidak berubah dilewati, yang berubah disimpan lagi
    import time as _t
    assert v.snapshot(changed=True) == []
    _t.sleep(1.1); mk("Library/Application Support/Claude/new.txt", "baru")
    assert v.snapshot(changed=True) == ["Claude"]
    assert open(os.path.join(T, "Library/Application Support/Google/Chrome/Default/Local Extension Settings/abc/000003.log")).read() == "ext-login"
    # restore TIDAK menghapus data yang ada sekarang: dipindah ke Library/Caches/Amnesia/before-restore
    mk("Library/Application Support/Claude/config.json", "login-baru-belum-disimpan")
    v.restore(PW)
    assert open(os.path.join(T, "Library/Application Support/Claude/config.json")).read() == "login-claude"
    assert open(os.path.join(v.BEFORE_RESTORE, "Library/Application Support/Claude/config.json")).read() == "login-baru-belum-disimpan"
    # percobaan terakhir diberi peringatan keras
    expect_error(lambda: v.restore("salah-salah-salah"), "Tries left: 2")
    expect_error(lambda: v.restore("salah-salah-salah"), "LAST TRY")
    v.restore(PW)
    assert v.attempts() == 0
    # Pindah Mac: kunci Keychain palsu
    store = {("Chrome Safe Storage", "Chrome"): "kunci-chrome", ("Claude Safe Storage", "Claude Key"): "kunci-claude"}
    v._keychain_secrets = lambda: [{"svc": s, "acct": a, "secret": k} for (s, a), k in store.items()]
    v._keychain_set = lambda s, a, k: store.__setitem__((s, a), k)
    expect_error(lambda: v.import_keys(PW), "has no keys yet")
    assert v.export_keys() == ["Chrome", "Claude"] and v.keys_info()["apps"] == ["Chrome", "Claude"]
    assert b"kunci-chrome" not in open(v.F_KEYS, "rb").read()
    store.clear()                                   # Mac baru: Keychain kosong
    expect_error(lambda: v.import_keys("salah-salah-salah"), "Tries left: 2")
    assert v.import_keys(PW) == ["Chrome", "Claude"] and v.attempts() == 0
    assert store[("Chrome Safe Storage", "Chrome")] == "kunci-chrome"
    # 3x salah -> doomsday
    for left in (2, 1):
        expect_error(lambda: v.check_password("salah-salah-salah"), f"Tries left: {left}")
    expect_error(lambda: v.check_password("salah-salah-salah"), "DOOMSDAY")
    assert not os.path.exists(v.VAULT)
    # kata panik -> doomsday langsung (+ Keep jika full)
    mk("Keep/rahasia.txt", "x")
    v.create(PW, panic_word="deletesemua", panic_full=True); v.snapshot()
    expect_error(lambda: v.restore("deletesemua"), "DOOMSDAY")
    assert not os.path.exists(v.VAULT) and os.listdir(os.path.join(T, "Keep")) == []
    # folder Keep custom (KEEP_DIR): panik mengosongkan folder itu, bukan ~/Keep
    mk("Keep/aman.txt", "x"); mk("Documents/Barang Saya/rahasia.txt", "x")
    with open(os.path.join(v.AMNESIA, "settings.conf"), "a") as f:
        f.write("KEEP_DIR=~/Documents/Barang Saya\n")
    v.create(PW, panic_word="deletesemua", panic_full=True); v.snapshot()
    expect_error(lambda: v.restore("deletesemua"), "DOOMSDAY")
    assert os.listdir(os.path.join(T, "Documents/Barang Saya")) == []
    assert os.path.exists(os.path.join(T, "Keep/aman.txt"))
    # KEEP_DIR berbahaya (home / ~/.amnesia) diabaikan
    for bad in ("~/", "~/.amnesia", "/", "relatif"):
        with open(os.path.join(v.AMNESIA, "settings.conf"), "a") as f:
            f.write(f"KEEP_DIR={bad}\n")
        assert v.keep_dir() == os.path.join(T, "Keep"), bad
    # ganti password: password lama tidak berlaku lagi, snapshot tetap bisa dibuka
    shutil.rmtree(v.VAULT, ignore_errors=True)
    with open(os.path.join(v.AMNESIA, "settings.conf"), "w") as f:
        f.write("VAULT_SKIP=Claude\n")
    mk("Library/Application Support/Claude/x.json", "c")
    v.create(PW); v.snapshot()
    assert "Claude" not in v.manifest()["apps"], "VAULT_SKIP must leave Claude out"
    expect_error(lambda: v.change_password(PW, "pendek"), "12")
    v.change_password(PW, "password-baru-123")
    expect_error(lambda: v.check_password(PW), "Tries left")
    expect_error(lambda: v.change_password("password-baru-123", "password-baru-123"), "same")
    v.restore("password-baru-123")

    # --- v5.10: snapshot per app tidak saling menimpa ---
    shutil.rmtree(v.VAULT, ignore_errors=True)
    open(os.path.join(v.AMNESIA, "settings.conf"), "w").close()
    mk("Library/Application Support/Claude/x.json", "claude-1")
    mk(".config/gh/hosts.yml", "gh-1")
    v.create(PW); v.snapshot()
    t1 = v.manifest()["per_app"]["GitHub CLI"]
    mk("Library/Application Support/Claude/x.json", "claude-2")
    mk(".config/gh/hosts.yml", "gh-2")
    assert v.snapshot(["Claude"]) == ["Claude"]
    m = v.manifest()
    assert "GitHub CLI" in m["apps"] and m["per_app"]["GitHub CLI"] == t1, "other apps must stay"
    mk(".config/gh/hosts.yml", "gh-3")
    v.restore(PW)
    assert open(os.path.join(T, "Library/Application Support/Claude/x.json")).read() == "claude-2"
    assert open(os.path.join(T, ".config/gh/hosts.yml")).read() == "gh-1"

    # restore yang gagal di tengah: data sekarang tetap utuh
    mk("Library/Application Support/Claude/x.json", "sekarang")
    arc = v._app_files("GitHub CLI")[0]
    good = open(arc, "rb").read()
    open(arc, "wb").write(b"rusak")
    try:
        v.restore(PW)
        raise AssertionError("broken archive must fail")
    except v.VaultError:
        pass
    assert open(os.path.join(T, "Library/Application Support/Claude/x.json")).read() == "sekarang"
    assert not os.path.exists(v.F_STAGE)
    open(arc, "wb").write(good)

    # folder pilihan ikut vault
    mk("Documents/PDF/buku.pdf", "isi-pdf")
    with open(os.path.join(v.AMNESIA, "settings.conf"), "a") as f:
        f.write("VAULT_FOLDERS=Documents/PDF,../luar,.amnesia\n")
    assert v.vault_folders() == ["Documents/PDF"]
    assert "~/Documents/PDF" in v.snapshot(["~/Documents/PDF"])
    shutil.rmtree(os.path.join(T, "Documents/PDF"))
    v.restore(PW)
    assert open(os.path.join(T, "Documents/PDF/buku.pdf")).read() == "isi-pdf"

    # hapus snapshot 1 app saja: app lain tetap
    v.delete_snapshot(["~/Documents/PDF"])
    m = v.manifest()
    assert "~/Documents/PDF" not in m["per_app"] and "Claude" in m["per_app"], "only the chosen snapshot goes"
    assert not os.path.exists(v._app_files("~/Documents/PDF")[0])

    # hapus snapshot saja: vault & password tetap
    v.delete_snapshot()
    assert v.exists() and v.manifest() == {} and not os.path.exists(v.F_APPDIR)
    v.check_password(PW)
    expect_error(lambda: v.restore(PW), "No snapshot")

    # snapshot lama (v5.9, 1 arsip) tetap bisa di-restore, lalu dibuang setelah semua app punya arsip sendiri
    key = "a" * 64
    tmpd = tempfile.mkdtemp()
    os.makedirs(os.path.join(tmpd, ".config/gh")); open(os.path.join(tmpd, ".config/gh/hosts.yml"), "w").write("gh-lama")
    v._7z(["a", "-t7z", "-mhe=on", "-p", v.F_SNAP, ".config/gh"], key, cwd=tmpd)
    shutil.rmtree(tmpd)
    subprocess.run([v.OPENSSL, "pkeyutl", "-encrypt", "-pubin", "-inkey", v.F_PUB, "-pkeyopt", "rsa_padding_mode:oaep",
                    "-out", v.F_SNAPKEY], input=key.encode(), check=True, capture_output=True)
    v._write_json(v.F_MANIFEST, {"apps": ["GitHub CLI"], "time": "2026-10-01 10:00", "size_mb": 0.1})
    assert v.manifest()["apps"] == ["GitHub CLI"]
    v.restore(PW)
    assert open(os.path.join(T, ".config/gh/hosts.yml")).read() == "gh-lama"
    v.snapshot(["GitHub CLI"])
    assert not os.path.exists(v.F_SNAP), "old archive is dropped once every app has its own"
    # tombol Batal (SIGTERM) saat snapshot: berhenti rapi, snapshot lama utuh, tidak ada file setengah jadi
    import signal, time as _t, json as _j
    mk("Library/Application Support/Claude/x.json", "claude-ok")
    v.snapshot(["Claude"])
    before = open(v._app_files("Claude")[0], "rb").read()
    big = os.path.join(T, "Library/Application Support/Claude/big.bin")
    with open(big, "wb") as f:
        f.write(os.urandom(60 * 1048576))
    env = dict(os.environ)
    p = subprocess.Popen([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), "vault.py"),
                          "snapshot", "Claude"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    while True:                                  # tunggu sampai 7zz benar-benar jalan
        line = p.stderr.readline().decode()
        if line.startswith("PROGRESS") and "save" in line:
            break
    _t.sleep(0.3)
    p.send_signal(signal.SIGTERM)
    out, _ = p.communicate(timeout=30)
    res = _j.loads(out.decode().strip().splitlines()[-1])
    assert res == {"ok": False, "error": "CANCELLED"}, res
    assert open(v._app_files("Claude")[0], "rb").read() == before, "old snapshot must stay"
    assert not [f for f in os.listdir(v.F_APPDIR) if f.endswith(".new")], "no half-written files"
    os.remove(big)

    # --- v5.16: snapshot ringan per app, browser Chromium lain, riwayat ---
    open(os.path.join(v.AMNESIA, "settings.conf"), "w").close()
    assert v._light_skip("Chrome")[0], "Chrome is light by default"
    with open(os.path.join(v.AMNESIA, "settings.conf"), "w") as f:
        f.write("VAULT_FULL=Chrome\n")
    assert v._light_skip("Chrome") == ([], []), "VAULT_FULL=Chrome must save Chrome in full"
    with open(os.path.join(v.AMNESIA, "settings.conf"), "w") as f:
        f.write("VAULT_LIGHT=0\n")
    assert "Chrome" in v.full_apps(), "old VAULT_LIGHT=0 means full"
    open(os.path.join(v.AMNESIA, "settings.conf"), "w").close()
    mk("Library/Application Support/BraveSoftware/Brave-Browser/Default/Cookies", "brave-login")
    assert "Brave Browser" in v.installed_apps() and "Brave Browser" in v.light_apps()
    assert "Brave Browser" in v.skipped_apps(), "a new browser must not join the vault by itself"
    with open(os.path.join(v.AMNESIA, "settings.conf"), "w") as f:
        f.write("VAULT_PICK=Brave Browser\n")
    assert "Brave Browser" in v.chosen_apps(), "picked browser joins the vault"
    hist = open(os.path.join(v.AMNESIA, "history.log")).read()
    assert "\tsnapshot\t" in hist and "\trestore\t" in hist and "\tdoomsday\t" in hist, hist
    assert "login-gmail" not in hist and "Cookies" not in hist, "history has no file names"
    print("OK: all vault tests passed")
finally:
    shutil.rmtree(T)
