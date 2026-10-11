#!/usr/bin/env python3
"""Amnesia Control Panel v4 — Tkinter (butuh Tk 8.6+ dari Homebrew: brew install python-tk)."""
import hashlib, os, plistlib, subprocess, sys, threading, time
import tkinter as tk
from tkinter import messagebox, simpledialog, ttk

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vault

HOME = os.path.expanduser("~")
A = os.path.join(HOME, ".amnesia")
LABEL = "com.amnesia.agent"
PLIST = os.path.join(HOME, "Library/LaunchAgents", LABEL + ".plist")
OLD_LABEL = "com.amnesia.loginreset"
OLD_PLIST = os.path.join(HOME, "Library/LaunchAgents", OLD_LABEL + ".plist")
KEEP_FILE = os.path.join(A, "keep.conf")
PAUSE = os.path.join(A, "pause_once")
CLEAN_LOG = os.path.join(A, "clean.log")
CHECKSUM_LOG = os.path.join(A, "backup_checksums.txt")
DOMAIN = f"gui/{os.getuid()}"

FONT = "Helvetica Neue"
GREEN, ORANGE, BLUE, PURPLE, RED, GOLD, GRAY = "#34C759", "#FF9500", "#007AFF", "#AF52DE", "#FF3B30", "#FFD60A", "#8E8E93"
TEXT, MUTED, BG = "#1C1C1E", "#6E6E73", "white"


# ==================== sistem ====================
def launchctl(*args):
    try:
        return subprocess.run(["launchctl", *args], capture_output=True).returncode
    except FileNotFoundError:          # bukan macOS (tes)
        return 1


def is_active():
    return os.path.exists(PLIST) and launchctl("print", f"{DOMAIN}/{LABEL}") == 0


def activate():
    # buang agent versi lama (reset saat login) kalau masih terpasang
    launchctl("bootout", f"{DOMAIN}/{OLD_LABEL}")
    if os.path.exists(OLD_PLIST):
        os.remove(OLD_PLIST)
    os.makedirs(os.path.dirname(PLIST), exist_ok=True)
    with open(PLIST, "wb") as f:
        plistlib.dump({"Label": LABEL, "ProgramArguments": ["/bin/bash", os.path.join(A, "agent.sh")],
                       "RunAtLoad": True, "ExitTimeOut": 120}, f)
    open(os.path.join(A, ".just_activated"), "w").close()   # jangan hapus sesi yang sedang dipakai
    launchctl("bootout", f"{DOMAIN}/{LABEL}")
    if launchctl("bootstrap", DOMAIN, PLIST) != 0:
        launchctl("load", PLIST)


def deactivate():
    if os.path.exists(PLIST):
        os.remove(PLIST)        # dihapus DULU: agent melihatnya dan tidak membersihkan saat berhenti
    launchctl("bootout", f"{DOMAIN}/{LABEL}")
    if os.path.exists(PAUSE):
        os.remove(PAUSE)


def last_clean():
    try:
        with open(CLEAN_LOG) as f:
            return f.read().strip()
    except OSError:
        return "Belum pernah berjalan"


# ==================== widget ====================
class FlatButton(tk.Frame):
    """Tombol berwarna (tk.Button di macOS mengabaikan warna latar)."""
    def __init__(self, master, text, command, bg, fg="white", width=26):
        super().__init__(master, bg=bg, cursor="hand2")
        self.command, self.bg, self.fg = command, bg, fg
        self.label = tk.Label(self, text=text, bg=bg, fg=fg, font=(FONT, 13, "bold"), width=width, pady=8)
        self.label.pack(fill="both", expand=True, padx=4)
        for w in (self, self.label):
            w.bind("<Button-1>", self.click)

    def set_text(self, text, bg=None):
        if bg:
            self.bg = bg
            self.config(bg=bg)
        self.label.config(text=text, bg=self.bg)

    def click(self, _=None):
        if App.busy:                           # cegah klik ganda / klik saat proses berjalan
            return
        self.label.config(bg="#D1D1D6", fg=TEXT)
        self.after(120, self.fire)

    def fire(self):
        self.label.config(bg=self.bg, fg=self.fg)
        self.command()


def title(parent, text, sub=None):
    tk.Label(parent, text=text, font=(FONT, 22, "bold"), bg=BG, fg=TEXT).pack(pady=(4, 2))
    if sub:
        tk.Label(parent, text=sub, font=(FONT, 12), bg=BG, fg=MUTED, wraplength=360).pack(pady=(0, 8))


def entry(parent, label, secret=True):
    tk.Label(parent, text=label, font=(FONT, 12), bg=BG, fg=TEXT, anchor="w").pack(fill="x", padx=30)
    e = tk.Entry(parent, show="•" if secret else "", font=(FONT, 14), relief="solid", bd=1)
    e.pack(fill="x", padx=30, pady=(2, 8))
    return e


def sep(parent):
    ttk.Separator(parent).pack(fill="x", pady=10)


# ==================== app ====================
class App:
    busy = False

    def __init__(self):
        self.root = tk.Tk()
        self.root.title("Amnesia")
        self.root.geometry("440x640")
        self.root.resizable(False, False)
        self.root.configure(bg=BG)

        self.pages = {}
        holder = self.holder = tk.Frame(self.root, bg=BG)
        holder.pack(fill="both", expand=True)
        holder.grid_rowconfigure(0, weight=1)
        holder.grid_columnconfigure(0, weight=1)
        for name in ("main", "keep", "backup", "vault"):
            f = tk.Frame(holder, bg=BG, padx=20, pady=16)
            f.grid(row=0, column=0, sticky="nsew")
            self.pages[name] = f

        # bar proses di bawah (muncul saat ada pekerjaan berjalan)
        self.busy_bar = tk.Frame(self.root, bg=BG)
        self.busy_label = tk.Label(self.busy_bar, text="", font=(FONT, 12), bg=BG, fg=MUTED)
        self.busy_label.pack()
        self.progress = ttk.Progressbar(self.busy_bar, mode="indeterminate", length=360)
        self.progress.pack(pady=(4, 12))

        self.build_main()
        self.build_keep()
        self.build_backup()
        self.build_vault()
        self.show("main")

    def show(self, name):
        getattr(self, "refresh_" + name)()
        self.pages[name].tkraise()

    # ---------- kerja di latar belakang (GUI tidak beku) ----------
    def run_bg(self, text, work, done):
        App.busy = True
        self.busy_label.config(text=text)
        self.busy_bar.pack(side="bottom", fill="x", before=self.holder)
        self.progress.start(12)
        result = {}

        def target():
            try:
                result["ok"] = work()
            except Exception as e:               # noqa: BLE001 — ditampilkan ke user
                result["err"] = e

        t = threading.Thread(target=target, daemon=True)
        t.start()

        def poll():
            if t.is_alive():
                self.root.after(150, poll)
                return
            self.progress.stop()
            self.busy_bar.pack_forget()
            App.busy = False
            done(result.get("ok"), result.get("err"))
        poll()

    # ==================== MENU UTAMA ====================
    def build_main(self):
        p = self.pages["main"]
        title(p, "Amnesia")
        self.status_lbl = tk.Label(p, font=(FONT, 14, "bold"), bg=BG)
        self.status_lbl.pack()
        self.status_sub = tk.Label(p, font=(FONT, 11), bg=BG, fg=MUTED, wraplength=360)
        self.status_sub.pack(pady=(2, 0))
        sep(p)
        self.btn_save_logout = FlatButton(p, "Simpan Profil & Logout", self.do_save_logout, GREEN)
        self.btn_vault = FlatButton(p, "Profile Vault", lambda: self.show("vault"), GOLD, fg=TEXT)
        self.btn_pause = FlatButton(p, "", self.do_pause, ORANGE)
        self.btn_backup = FlatButton(p, "Backup ke Drive", lambda: self.show("backup"), BLUE)
        self.btn_keep = FlatButton(p, "Keep List", lambda: self.show("keep"), PURPLE)
        self.btn_power = FlatButton(p, "", self.do_power, RED)
        self.main_buttons = [self.btn_save_logout, self.btn_vault, self.btn_pause,
                             self.btn_backup, self.btn_keep, self.btn_power]
        self.btn_close = FlatButton(p, "Tutup", self.root.destroy, "#E5E5EA", fg=TEXT)

    def refresh_main(self):
        active, paused = is_active(), os.path.exists(PAUSE)
        if not active:
            self.status_lbl.config(text="Status: MATI", fg=RED)
            self.status_sub.config(text="Tidak ada yang dibersihkan saat logout.")
        elif paused:
            self.status_lbl.config(text="Status: DIJEDA 1 SESI", fg=ORANGE)
            self.status_sub.config(text="Logout & login berikutnya tidak dibersihkan,\nsesudah itu otomatis aktif lagi.")
        else:
            self.status_lbl.config(text="Status: AKTIF", fg=GREEN)
            self.status_sub.config(text="Dibersihkan saat logout, dicek ulang saat login.\nTerakhir: " + last_clean())
        self.btn_pause.set_text("Batalkan Jeda" if paused else "Jeda 1 Sesi")
        self.btn_power.set_text("Matikan Amnesia" if active else "Aktifkan Amnesia", RED if active else GREEN)

        for b in self.main_buttons + [self.btn_close]:
            b.pack_forget()
        for b in self.main_buttons:
            if b is self.btn_save_logout and not vault.exists():
                continue
            if b is self.btn_pause and not active:
                continue
            b.pack(pady=5)
        self.btn_close.pack(pady=(14, 0))

    def do_pause(self):
        if os.path.exists(PAUSE):
            os.remove(PAUSE)
        else:
            open(PAUSE, "w").close()
            messagebox.showinfo("Amnesia", "Dijeda untuk 1 sesi.\n\nLogout dan login berikutnya TIDAK dibersihkan. "
                                           "Logout sesudahnya otomatis dibersihkan lagi.")
        self.refresh_main()

    def do_power(self):
        if is_active():
            if not messagebox.askyesno("Matikan Amnesia", "Matikan Amnesia?\n\nData tidak akan dibersihkan lagi "
                                       "saat logout sampai kamu aktifkan kembali.", icon="warning"):
                return
            deactivate()
        else:
            activate()
            messagebox.showinfo("Amnesia", "Amnesia AKTIF.\n\nSesi ini dibersihkan saat logout/restart/shutdown, "
                                           "lalu dicek ulang saat login.\nFolder ~/Keep tetap aman.")
        self.refresh_main()

    def do_save_logout(self):
        apps = vault.installed_apps()
        if not messagebox.askyesno("Simpan & Logout", f"Simpan profil {', '.join(apps)} ke vault, lalu logout?\n\n"
                                   "App tersebut akan ditutup dulu."):
            return

        def done(_, err):
            if err:
                messagebox.showerror("Snapshot gagal", f"{err}\n\nLogout dibatalkan supaya profil tidak hilang.")
                return
            vault.logout()
        self.run_bg("Menyimpan profil ke vault...", lambda: vault.snapshot(apps), done)

    # ==================== KEEP LIST ====================
    def build_keep(self):
        p = self.pages["keep"]
        title(p, "Keep List", "Yang TIDAK dihapus saat logout. ~/Keep dan ~/.amnesia selalu aman.")
        box = tk.Frame(p, bg=BG)
        box.pack(fill="both", expand=True)
        sb = tk.Scrollbar(box)
        sb.pack(side="right", fill="y")
        self.keep_box = tk.Listbox(box, font=(FONT, 12), selectbackground=BLUE, selectforeground="white",
                                   relief="flat", highlightthickness=1, highlightbackground="#D1D1D6",
                                   yscrollcommand=sb.set)
        self.keep_box.pack(fill="both", expand=True)
        sb.config(command=self.keep_box.yview)
        row = tk.Frame(p, bg=BG)
        row.pack(fill="x", pady=(12, 6))
        FlatButton(row, "Tambah", self.keep_add, GREEN, width=11).pack(side="left", expand=True)
        FlatButton(row, "Hapus", self.keep_remove, RED, width=11).pack(side="left", expand=True)
        FlatButton(p, "Kembali", lambda: self.show("main"), GRAY).pack(pady=(6, 0))

    @staticmethod
    def keep_lines():
        try:
            with open(KEEP_FILE) as f:
                return f.read().splitlines()
        except OSError:
            return []

    def keep_entries(self):
        return [l.strip() for l in self.keep_lines() if l.strip() and not l.strip().startswith("#")]

    def refresh_keep(self):
        self.keep_box.delete(0, tk.END)
        for e in self.keep_entries():
            self.keep_box.insert(tk.END, "  " + e)

    def keep_add(self):
        kept = set(self.keep_entries())
        cands = []
        for base in ("Library/Application Support", "Library/Containers", "Library/Group Containers"):
            try:
                names = sorted(os.listdir(os.path.join(HOME, base)))
            except OSError:
                continue
            cands += [f"{base}/{n}" for n in names if not n.startswith((".", "com.apple")) and n != "Apple"]
        cands += sorted(n for n in os.listdir(HOME) if n.startswith(".") and n not in (".Trash", ".amnesia")
                        and os.path.isdir(os.path.join(HOME, n)))
        cands = [c for c in cands if c not in kept]
        if not cands:
            messagebox.showinfo("Keep List", "Tidak ada folder lain yang bisa ditambahkan.")
            return

        dlg = tk.Toplevel(self.root)
        dlg.title("Tambah ke Keep List")
        dlg.geometry("420x420")
        dlg.configure(bg=BG)
        dlg.transient(self.root)
        dlg.grab_set()
        tk.Label(dlg, text="Pilih folder yang mau di-keep:", font=(FONT, 13, "bold"), bg=BG).pack(pady=10)
        lb = tk.Listbox(dlg, font=(FONT, 12), selectmode="extended", selectbackground=BLUE,
                        highlightthickness=1, highlightbackground="#D1D1D6")
        lb.pack(fill="both", expand=True, padx=16)
        for c in cands:
            lb.insert(tk.END, c)

        def add():
            picked = [lb.get(i) for i in lb.curselection()]
            if picked:
                with open(KEEP_FILE, "a") as f:
                    f.write("".join(p + "\n" for p in picked))
            dlg.destroy()
            self.refresh_keep()
        FlatButton(dlg, "Tambah", add, GREEN, width=14).pack(pady=12)

    def keep_remove(self):
        sel = self.keep_box.curselection()
        if not sel:
            messagebox.showinfo("Keep List", "Pilih dulu yang mau dihapus dari keep list.")
            return
        item = self.keep_box.get(sel[0]).strip()
        if not messagebox.askyesno("Keep List", f"Hapus dari keep list?\n\n{item}\n\nDatanya akan ikut "
                                   "dibersihkan saat logout berikutnya."):
            return
        lines = self.keep_lines()
        with open(KEEP_FILE, "w") as f:                 # komentar & baris lain tetap utuh
            f.write("".join(l + "\n" for l in lines if l.strip() != item))
        self.refresh_keep()

    # ==================== BACKUP ====================
    def build_backup(self):
        p = self.pages["backup"]
        title(p, "Backup ke Drive", "File .7z terenkripsi AES-256 (nama file juga terenkripsi).")
        tk.Label(p, text="Drive tujuan:", font=(FONT, 12, "bold"), bg=BG, anchor="w").pack(fill="x", padx=30)
        self.drive_var = tk.StringVar()
        self.drive_box = tk.Frame(p, bg=BG)
        self.drive_box.pack(fill="x", padx=30, pady=(2, 8))
        tk.Label(p, text="Folder:", font=(FONT, 12, "bold"), bg=BG, anchor="w").pack(fill="x", padx=30)
        fbox = tk.Frame(p, bg=BG)
        fbox.pack(fill="x", padx=30, pady=(2, 8))
        self.folder_vars = {}
        for i, name in enumerate(["Keep", "Documents", "Desktop", "Downloads", "Pictures", "Music", "Movies"]):
            v = tk.BooleanVar(value=(name == "Keep"))
            self.folder_vars[name] = v
            tk.Checkbutton(fbox, text=name, variable=v, font=(FONT, 12), bg=BG, anchor="w").grid(
                row=i // 2, column=i % 2, sticky="w", padx=(0, 30))
        self.bk_pw1 = entry(p, "Password enkripsi:")
        self.bk_pw2 = entry(p, "Ulangi password:")
        tk.Label(p, text="Simpan password ini. Tanpa password backup tidak bisa dibuka.",
                 font=(FONT, 11), bg=BG, fg=ORANGE, wraplength=360).pack()
        FlatButton(p, "Mulai Backup", self.do_backup, GREEN).pack(pady=(12, 6))
        FlatButton(p, "Kembali", lambda: self.show("main"), GRAY).pack()

    @staticmethod
    def drives():
        out = []
        for name in sorted(os.listdir("/Volumes")) if os.path.isdir("/Volumes") else []:
            path = os.path.join("/Volumes", name)
            if name.startswith(".") or os.path.realpath(path) == "/" or not os.access(path, os.W_OK):
                continue
            try:
                st = os.statvfs(path)
                out.append((name, f"{st.f_bavail * st.f_frsize / 1024 ** 3:.1f} GB kosong"))
            except OSError:
                pass
        return out

    def refresh_backup(self):
        for w in self.drive_box.winfo_children():
            w.destroy()
        ds = self.drives()
        if not ds:
            tk.Label(self.drive_box, text="Tidak ada drive eksternal. Colok SSD/flashdisk lalu buka lagi.",
                     font=(FONT, 12), bg=BG, fg=RED, wraplength=340, justify="left").pack(anchor="w")
            self.drive_var.set("")
            return
        if self.drive_var.get() not in [d for d, _ in ds]:
            self.drive_var.set(ds[0][0])
        for name, free in ds:
            tk.Radiobutton(self.drive_box, text=f"{name}  ({free})", variable=self.drive_var, value=name,
                           font=(FONT, 12), bg=BG, anchor="w").pack(fill="x")

    def do_backup(self):
        drive = self.drive_var.get()
        folders = [f for f, v in self.folder_vars.items() if v.get() and os.path.isdir(os.path.join(HOME, f))]
        pw = self.bk_pw1.get()
        if not drive:
            return messagebox.showwarning("Backup", "Pilih drive tujuan dulu.")
        if not folders:
            return messagebox.showwarning("Backup", "Pilih minimal 1 folder.")
        if not pw:
            return messagebox.showwarning("Backup", "Password tidak boleh kosong.")
        if pw != self.bk_pw2.get():
            return messagebox.showerror("Backup", "Password tidak cocok.")
        target = f"/Volumes/{drive}/amnesia_backup_{time.strftime('%Y%m%d_%H%M')}.7z"

        def work():
            r = subprocess.run([vault.SEVENZ, "a", "-t7z", "-m0=lzma2", "-mx=5", "-mhe=on", "-p", target, *folders,
                                "-xr!node_modules", "-xr!.DS_Store"],
                               input=(pw + "\n") * 2, capture_output=True, text=True, cwd=HOME)
            if r.returncode not in (0, 1) or not os.path.exists(target):
                raise RuntimeError(f"7zz gagal (kode {r.returncode}):\n{r.stderr[-300:]}")
            sha = hashlib.sha256()
            with open(target, "rb") as f:
                for chunk in iter(lambda: f.read(1 << 20), b""):
                    sha.update(chunk)
            with open(CHECKSUM_LOG, "a") as f:
                f.write(f"{sha.hexdigest()}  {target}\n")
            return os.path.getsize(target) / 1048576

        def done(size, err):
            if err:
                return messagebox.showerror("Backup gagal", str(err))
            self.bk_pw1.delete(0, tk.END)
            self.bk_pw2.delete(0, tk.END)
            messagebox.showinfo("Backup berhasil", f"{os.path.basename(target)}\n{size:.1f} MB di {drive}\n\n"
                                                   "Checksum SHA256 dicatat di backup_checksums.txt.")
            self.show("main")
        self.run_bg(f"Backup ke {drive}... (jangan cabut drive)", work, done)

    # ==================== PROFILE VAULT ====================
    def build_vault(self):
        p = self.pages["vault"]
        title(p, "Profile Vault")
        self.v_status = tk.Label(p, font=(FONT, 12), bg=BG, fg=MUTED, wraplength=380, justify="center")
        self.v_status.pack(pady=(0, 4))
        self.v_warn = tk.Label(p, font=(FONT, 13, "bold"), bg=BG, fg=RED, wraplength=380)
        sep(p)

        # belum ada vault
        self.v_setup = tk.Frame(p, bg=BG)
        tk.Label(self.v_setup, text="Password vault TIDAK bisa dipulihkan kalau lupa.",
                 font=(FONT, 11, "bold"), bg=BG, fg=ORANGE).pack(pady=(0, 6))
        self.v_new1 = entry(self.v_setup, f"Password vault (min. {vault.MIN_PASSWORD} karakter):")
        self.v_new2 = entry(self.v_setup, "Ulangi password:")
        self.v_panic = entry(self.v_setup, "Kata panik (opsional):")
        self.v_panic_full = tk.BooleanVar(value=False)
        tk.Checkbutton(self.v_setup, text="Kata panik juga mengosongkan ~/Keep", variable=self.v_panic_full,
                       font=(FONT, 12), bg=BG).pack()
        FlatButton(self.v_setup, "Buat Vault", self.do_vault_create, GOLD, fg=TEXT).pack(pady=(12, 0))

        # vault sudah ada
        self.v_open = tk.Frame(p, bg=BG)
        self.v_pw = entry(self.v_open, "Password vault:")
        self.v_pw.bind("<Return>", lambda _: self.do_restore())
        FlatButton(self.v_open, "Restore Profil", self.do_restore, GREEN).pack(pady=5)
        FlatButton(self.v_open, "Snapshot Sekarang", self.do_snapshot, BLUE).pack(pady=5)
        FlatButton(self.v_open, "Atur Kata Panik", self.do_panic, PURPLE).pack(pady=5)
        FlatButton(self.v_open, "Hapus Vault", self.do_vault_delete, RED).pack(pady=5)

        self.v_back = FlatButton(p, "Kembali", lambda: self.show("main"), GRAY)

    def refresh_vault(self):
        for w in (self.v_setup, self.v_open, self.v_warn, self.v_back):
            w.pack_forget()
        if not vault.exists():
            self.v_status.config(text="Vault belum dibuat. Buat sekali, lalu profil Chrome, Claude dan "
                                      "OpenCode bisa dipulihkan dengan 1 password.")
            self.v_setup.pack(fill="x")
        else:
            m = vault.manifest()
            if m:
                self.v_status.config(text=f"Snapshot terakhir: {m['time']}\n{', '.join(m['apps'])}  ({m['size_mb']} MB)")
            else:
                self.v_status.config(text="Vault siap, belum ada snapshot.\nLogin ke app dulu, lalu tekan Snapshot.")
            left = vault.MAX_ATTEMPTS - vault.attempts()
            if left < vault.MAX_ATTEMPTS:
                self.v_warn.config(text=f"PERINGATAN: sisa {left}x percobaan. Salah lagi sampai habis = "
                                        "vault DIHAPUS PERMANEN.")
                self.v_warn.pack(pady=(0, 6))
            self.v_open.pack(fill="x")
        self.v_back.pack(pady=(10, 0))

    def vault_error(self, err):
        if str(err) == "DOOMSDAY":
            messagebox.showerror("Vault dimusnahkan", "Vault telah dimusnahkan untuk melindungi data.")
        else:
            messagebox.showerror("Profile Vault", str(err))
        self.v_pw.delete(0, tk.END)
        self.refresh_vault()

    def do_vault_create(self):
        pw = self.v_new1.get()
        if pw != self.v_new2.get():
            return messagebox.showerror("Profile Vault", "Password tidak cocok.")

        def done(_, err):
            if err:
                return self.vault_error(err)
            for e in (self.v_new1, self.v_new2, self.v_panic):
                e.delete(0, tk.END)
            messagebox.showinfo("Profile Vault", "Vault dibuat.\n\nLogin ke Chrome, Claude, OpenCode seperti biasa, "
                                                 "lalu tekan Snapshot Sekarang (atau Simpan Profil & Logout).")
            self.refresh_vault()
        self.run_bg("Membuat kunci vault...",
                    lambda: vault.create(pw, self.v_panic.get(), self.v_panic_full.get()), done)

    def do_restore(self):
        pw = self.v_pw.get()
        if not pw:
            return messagebox.showwarning("Profile Vault", "Masukkan password vault.")

        def done(names, err):
            if err:
                return self.vault_error(err)
            self.v_pw.delete(0, tk.END)
            messagebox.showinfo("Profile Vault", f"Profil dipulihkan: {', '.join(names)}.\nSiap dipakai.")
            self.refresh_vault()
        self.run_bg("Memulihkan profil...", lambda: vault.restore(pw), done)

    def do_snapshot(self):
        apps = vault.installed_apps()
        if not apps:
            return messagebox.showinfo("Profile Vault", "Belum ada data Chrome/Claude/OpenCode di Mac ini.")
        if not messagebox.askyesno("Snapshot", f"Simpan profil {', '.join(apps)}?\n\nApp tersebut akan ditutup dulu."):
            return

        def done(_, err):
            if err:
                return self.vault_error(err)
            self.refresh_vault()
        self.run_bg("Menyimpan profil ke vault...", lambda: vault.snapshot(apps), done)

    def do_panic(self):
        pw = self.v_pw.get()
        if not pw:
            return messagebox.showwarning("Kata Panik", "Isi password vault dulu di kolom password.")
        word = simpledialog.askstring("Kata Panik", "Kata panik baru (kosongkan untuk mematikan):",
                                      show="•", parent=self.root)
        if word is None:
            return
        full = bool(word) and messagebox.askyesno("Kata Panik", "Kata panik juga mengosongkan ~/Keep?")

        def done(_, err):
            if err:
                return self.vault_error(err)
            self.v_pw.delete(0, tk.END)
            messagebox.showinfo("Kata Panik", "Kata panik disimpan." if word else "Kata panik dimatikan.")
            self.refresh_vault()
        self.run_bg("Memeriksa password...", lambda: vault.change_panic(pw, word, full), done)

    def do_vault_delete(self):
        if messagebox.askyesno("Hapus Vault", "Hapus vault dan semua snapshot profil?\n\nTidak bisa dibatalkan.",
                               icon="warning"):
            vault.doomsday(False, "dihapus manual")
            self.refresh_vault()

    def run(self):
        self.root.mainloop()


if __name__ == "__main__":
    App().run()
