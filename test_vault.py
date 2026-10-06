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
    mk("Library/Application Support/Claude/config.json", "login-claude")
    mk(".local/share/opencode/auth.json", "token-opencode")
    mk(".claude.json", "token-claude-code")
    mk("Library/Group Containers/group.net.whatsapp.WhatsApp.shared/ChatStorage.sqlite", "chat-wa")
    expect_error(lambda: v.create("pendek"), "at least")
    v.create(PW, panic_word="deletesemua")
    assert v.snapshot() == ["Chrome", "Claude", "OpenCode", "Claude Code", "WhatsApp"]
    # vault tidak boleh berisi teks asli
    raw = open(v.F_SNAP, "rb").read()
    assert b"login-gmail" not in raw and b"Cookies" not in raw
    # simulasi amnesia: data hilang
    shutil.rmtree(os.path.join(T, "Library")); shutil.rmtree(os.path.join(T, ".local")); os.remove(os.path.join(T, ".claude.json"))
    # salah 1x, lalu benar -> counter reset
    expect_error(lambda: v.restore("salah-salah-salah"), "Tries left: 2")
    assert v.restore(PW) == ["Chrome", "Claude", "OpenCode", "Claude Code", "WhatsApp"] and v.attempts() == 0
    assert open(os.path.join(T, "Library/Application Support/Google/Chrome/Default/Cookies")).read() == "login-gmail"
    assert open(os.path.join(T, ".local/share/opencode/auth.json")).read() == "token-opencode"
    assert open(os.path.join(T, ".claude.json")).read() == "token-claude-code"
    assert open(os.path.join(T, "Library/Group Containers/group.net.whatsapp.WhatsApp.shared/ChatStorage.sqlite")).read() == "chat-wa"
    assert not os.path.exists(os.path.join(T, "Library/Application Support/Google/Chrome/Default/Cache"))
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
    print("OK: all vault tests passed")
finally:
    shutil.rmtree(T)
