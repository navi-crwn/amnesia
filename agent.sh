#!/bin/bash
# ============================================
# AMNESIA AGENT — dijalankan launchd (com.amnesia.agent) saat login.
# - Saat login  : cek ulang, bersihkan sisa sesi sebelumnya, lalu (opsional) kirim notifikasi.
# - Tetap hidup : saat logout/restart/shutdown macOS mengirim SIGTERM,
#                 agent (opsional) menyimpan login ke vault, lalu membersihkan sesi ini SEBELUM keluar.
# Pengaturan dibaca dari settings.conf (diatur dari app). Default semua AKTIF.
# ============================================
A="$HOME/.amnesia"
PLIST="$HOME/Library/LaunchAgents/com.amnesia.agent.plist"
PY=/opt/homebrew/bin/python3; [ -x "$PY" ] || PY=/usr/bin/python3

setting() { ! grep -qx "$1=0" "$A/settings.conf" 2>/dev/null; }

on_exit() {
    # plist sudah dihapus = Amnesia dimatikan dari app, bukan logout -> jangan bersihkan
    [ -f "$PLIST" ] || exit 0
    # Snapshot otomatis: hanya kalau vault ada, tidak sedang dijeda, dan belum ada snapshot 10 menit terakhir
    # (misalnya baru saja lewat tombol Simpan & Logout).
    if setting AUTO_SNAPSHOT && [ ! -f "$A/pause_once" ] && [ -f "$A/vault/public.pem" ] \
       && [ -z "$(find "$A/vault/manifest.json" -mmin -10 2>/dev/null)" ]; then
        "$PY" "$A/vault.py" snapshot >/dev/null 2>&1
    fi
    /bin/bash "$A/clean.sh" logout
    exit 0
}
trap on_exit TERM INT HUP

if [ -f "$A/.just_activated" ]; then
    rm -f "$A/.just_activated"        # baru diaktifkan dari app: jangan hapus sesi yang sedang dipakai
else
    /bin/bash "$A/clean.sh" login
    # buka app Amnesia di menu bar (tanpa jendela)
    open -g -b com.amnesia.controlpanel --args --background 2>/dev/null
    if setting NOTIFY; then
        osascript -e 'display notification "Mac sudah bersih. Klik ikon Amnesia di menu bar untuk restore profil." with title "Amnesia" sound name "Glass"' 2>/dev/null
    fi
fi

while :; do sleep 3600 & wait $!; done
