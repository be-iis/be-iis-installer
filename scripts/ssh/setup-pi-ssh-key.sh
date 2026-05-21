#!/usr/bin/env bash
set -euo pipefail

KEY_NAME="${1:-id_ed25519_be_iis_pi}"
KEY_PATH="$HOME/.ssh/$KEY_NAME"

log() {
    printf '[INFO] %s\n' "$*"
}

warn() {
    printf '[WARN] %s\n' "$*" >&2
}

die() {
    printf '[ERROR] %s\n' "$*" >&2
    exit 1
}

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

if [[ -f "$KEY_PATH" ]]; then
    log "SSH key already exists: $KEY_PATH"
else
    log "Generating SSH key: $KEY_PATH"
    ssh-keygen -t ed25519 -f "$KEY_PATH" -N "" -C "$(whoami)@$(hostname)-be-iis"
fi

chmod 600 "$KEY_PATH"
chmod 644 "$KEY_PATH.pub"

log "Public key:"
echo
cat "$KEY_PATH.pub"
echo

if [[ -z "${SSH_CONNECTION:-}" ]]; then
    warn "No active SSH connection detected."
    warn "Automatic host detection is not possible."
    exit 0
fi

CLIENT_IP="$(echo "$SSH_CONNECTION" | awk '{print $1}')"

log "Detected SSH client IP: $CLIENT_IP"
echo

cat <<EOF
To allow this Raspberry Pi to log in to your host machine,
add the public key above to this file on your host:

  ~/.ssh/authorized_keys

If your host machine accepts SSH connections, you can try:

  ssh-copy-id -i "$KEY_PATH.pub" USER@$CLIENT_IP

Example:

  ssh-copy-id -i "$KEY_PATH.pub" philipp@$CLIENT_IP

Test from the Pi:

  ssh -i "$KEY_PATH" USER@$CLIENT_IP
EOF
