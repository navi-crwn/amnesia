#!/bin/bash
# Tambah baris ke ~/.amnesia/keep.conf kalau belum ada (isi lama tidak diubah).
K="$HOME/.amnesia/keep.conf"
add() { grep -qxF "$1" "$K" 2>/dev/null || { echo "$1" >> "$K"; echo "  + $1"; }; }
grep -q "Tambahan 2026-10-06" "$K" || printf '\n# --- Tambahan 2026-10-06: setting Terminal & app harian ---\n' >> "$K"
add ".zshrc"
add ".zprofile"
add ".mitmproxy"
add "Library/Containers/cc.ffitch.shottr"
add "Library/Preferences/cc.ffitch.shottr*"
add "Library/Containers/io.tailscale*"
add "Library/Group Containers/*tailscale*"
add "Library/Preferences/io.tailscale*"
add "keychain:*ailscale*"
# login Claude Code & GitHub CLI tersimpan di Keychain (filenya di Vault)
add "keychain:Claude Code*"
add "keychain:gh:*"
add "keychain:gemini"
add "keychain:*.XAUTH"            # password profil VPN
add ".gitconfig"
echo "Keep List diperbarui."
