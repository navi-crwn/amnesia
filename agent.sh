#!/bin/bash
# ============================================
# AMNESIA AGENT — dijalankan launchd (com.amnesia.agent) saat login.
# - Saat login  : cek ulang, bersihkan sisa sesi sebelumnya.
# - Tetap hidup : saat logout/restart/shutdown macOS mengirim SIGTERM,
#                 agent membersihkan sesi ini SEBELUM keluar.
# ============================================
A="$HOME/.amnesia"
PLIST="$HOME/Library/LaunchAgents/com.amnesia.agent.plist"

on_exit() {
    # plist sudah dihapus = Amnesia dimatikan dari GUI, bukan logout -> jangan bersihkan
    [ -f "$PLIST" ] && /bin/bash "$A/clean.sh" logout
    exit 0
}
trap on_exit TERM INT HUP

if [ -f "$A/.just_activated" ]; then
    rm -f "$A/.just_activated"        # baru diaktifkan dari GUI: jangan hapus sesi yang sedang dipakai
else
    /bin/bash "$A/clean.sh" login
    # buka app Amnesia di menu bar (tanpa jendela)
    open -g -b com.amnesia.controlpanel --args --background 2>/dev/null
fi

while :; do sleep 3600 & wait $!; done
