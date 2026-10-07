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
trace() { echo "$(date '+%F %T') agent: $*" >> "$A/trace.log" 2>/dev/null; }   # jam + langkah, tanpa nama file

on_exit() {
    # plist sudah dihapus = Amnesia dimatikan dari app, bukan logout -> jangan bersihkan
    trap ':' TERM INT HUP               # sinyal kedua tidak boleh memulai pembersihan dua kali
    [ -f "$PLIST" ] || { trace "stopped (Amnesia turned off)"; exit 0; }
    trace "logout signal"
    # Snapshot otomatis: hanya kalau vault ada, tidak sedang dijeda, dan belum ada snapshot 10 menit terakhir
    # (misalnya baru saja lewat tombol Simpan & Logout).
    # v5.14: hanya app yang berubah sejak snapshot terakhirnya, paling lama 150 detik (lewat dari itu
    # dibatalkan dengan rapi, snapshot lama tetap utuh) supaya pembersihan selalu sempat jalan.
    if setting AUTO_SNAPSHOT && [ ! -f "$A/pause_once" ] && [ -f "$A/vault/public.pem" ] \
       && [ -z "$(find "$A/vault/manifest.json" -mmin -10 2>/dev/null)" ]; then
        trace "snapshot start"
        "$PY" "$A/vault.py" snapshot --changed >/dev/null 2>&1 &
        SP=$!
        ( sleep 150; kill -TERM "$SP" 2>/dev/null ) >/dev/null 2>&1 &
        W=$!
        wait "$SP"; trace "snapshot end ($?)"
        kill "$W" 2>/dev/null
    fi
    /bin/bash "$A/clean.sh" logout
    trace "logout done"
    exit 0
}
trap on_exit TERM INT HUP

trace "login"
if [ -f "$A/.just_activated" ]; then
    rm -f "$A/.just_activated"        # baru diaktifkan dari app: jangan hapus sesi yang sedang dipakai
else
    /bin/bash "$A/clean.sh" login
    # buka app Amnesia di menu bar (tanpa jendela)
    open -g -b com.amnesia.controlpanel --args --background 2>/dev/null
    if setting NOTIFY; then
        if grep -qx "LANG=id" "$A/settings.conf" 2>/dev/null; then
            MSG="Mac sudah bersih. Klik ikon Amnesia di menu bar untuk restore profil."
        else
            MSG="Your Mac is clean. Click the Amnesia icon in the menu bar to restore your profiles."
        fi
        osascript -e "display notification \"$MSG\" with title \"Amnesia\" sound name \"Glass\"" 2>/dev/null
    fi
fi

while :; do sleep 3600 & wait $!; done
