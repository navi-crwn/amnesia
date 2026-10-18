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

# v5.15: letak app (diberikan oleh app saat menjalankan agent ini). App dibuang ke Trash atau dihapus
# tanpa uninstall = jangan bersihkan apa pun, dan matikan agent untuk seterusnya.
APP="${AMNESIA_APP:-}"
app_gone() {
    [ -n "$APP" ] || return 1
    case "$APP" in */.Trash/*) return 0 ;; esac
    [ -d "$APP" ] && return 1
    sleep 2; [ ! -d "$APP" ]            # cek sekali lagi: jangan salah baca saat app sedang dipasang ulang
}

# v5.22: dulu agent mati diam-diam kalau Amnesia.app dipindah/di-rename. Sekarang kamu diberi tahu.
notify_gone() {
    local msg
    if grep -qx "LANG=id" "$A/settings.conf" 2>/dev/null; then
        msg="Amnesia.app tidak ditemukan di tempatnya ($APP). Saat logout tidak ada yang dibersihkan dan Amnesia mati. Kembalikan app ke Applications, buka, lalu tekan Aktifkan."
    else
        msg="Amnesia.app is not where it was ($APP). Nothing is wiped at logout and Amnesia turns itself off. Move the app back to Applications, open it and press Turn On."
    fi
    msg="${msg//\"/}"
    osascript -e "display notification \"$msg\" with title \"Amnesia\" sound name \"Basso\"" 2>/dev/null
}

on_exit() {
    # plist sudah dihapus = Amnesia dimatikan dari app, bukan logout -> jangan bersihkan
    trap ':' TERM INT HUP               # sinyal kedua tidak boleh memulai pembersihan dua kali
    [ -f "$PLIST" ] || { trace "stopped (Amnesia turned off)"; exit 0; }
    if app_gone; then
        trace "stopped (app removed or moved, nothing wiped)"
        notify_gone
        rm -f "$PLIST" "$HOME/Library/LaunchAgents/com.amnesia.menubar.plist"
        exit 0
    fi
    trace "logout signal"
    # Snapshot otomatis: hanya kalau vault ada dan tidak sedang dijeda. Selalu SEBELUM pembersihan, jadi restore
    # setelah login memakai versi terbaru (mis. chat Claude Code yang tidak ada di Keep List).
    # v5.14: hanya app yang berubah sejak snapshot terakhirnya, paling lama 150 detik (lewat dari itu
    # dibatalkan dengan rapi, snapshot lama tetap utuh) supaya pembersihan selalu sempat jalan.
    # v5.23: dulu dilewati kalau ada snapshot 10 menit terakhir; perubahan sesudah snapshot manual itu ikut hilang.
    # Sekarang tidak lagi: app yang tidak berubah (mis. sesudah Simpan & Logout) tetap dilewati oleh --changed.
    # Gagal atau macet = pembersihan tetap jalan (TERM setelah 150 detik, KILL 10 detik kemudian).
    if setting AUTO_SNAPSHOT && [ ! -f "$A/pause_once" ] && [ -f "$A/vault/public.pem" ]; then
        trace "snapshot start"
        "$PY" "$A/vault.py" snapshot --changed >/dev/null 2>&1 &
        SP=$!
        ( sleep 150; kill -TERM "$SP" 2>/dev/null; sleep 10; kill -KILL "$SP" 2>/dev/null ) >/dev/null 2>&1 &
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
    # buka app Amnesia: hanya di menu bar (tanpa jendela), kecuali "Jalan di background" dimatikan (v5.19)
    if grep -qx "BG_START=0" "$A/settings.conf" 2>/dev/null; then
        open -b com.amnesia.controlpanel 2>/dev/null
    else
        open -g -b com.amnesia.controlpanel --args --background 2>/dev/null
    fi
    if setting NOTIFY; then
        if grep -qx "LANG=id" "$A/settings.conf" 2>/dev/null; then
            MSG="Mac sudah bersih. Klik ikon Amnesia di menu bar untuk restore profil."
        else
            MSG="Your Mac is clean. Click the Amnesia icon in the menu bar to restore your profiles."
        fi
        osascript -e "display notification \"$MSG\" with title \"Amnesia\" sound name \"Glass\"" 2>/dev/null
    fi
    # v5.23: Brankas gagal ditutup saat logout (keeplock.sh menulis box.close_failed): beri tahu sekali
    if [ -f "$A/box.close_failed" ] && [ ! -f "$A/box.close_failed.told" ]; then
        if grep -qx "LANG=id" "$A/settings.conf" 2>/dev/null; then
            MSG="Brankas tidak bisa ditutup saat logout. Lain kali tutup dulu app yang membuka file dari Brankas."
        else
            MSG="Brankas could not be closed at logout. Next time, close the apps using it first."
        fi
        osascript -e "display notification \"$MSG\" with title \"Amnesia\" sound name \"Basso\"" 2>/dev/null
        touch "$A/box.close_failed.told"
        trace "brankas close failure shown"
    fi
fi

# v5.22: tiap 10 menit cek apakah app masih ada. Kalau dipindah/di-rename, kamu diberi tahu SEKALI selagi masih
# login (notifikasi saat logout sering tidak terlihat), dan dicatat di trace.log.
WARNED=0
while :; do
    sleep 600 & wait $!
    if [ "$WARNED" = 0 ] && [ -n "$APP" ] && [ ! -d "$APP" ]; then
        trace "app not found where it was (moved or renamed?)"
        notify_gone
        WARNED=1
    fi
done
