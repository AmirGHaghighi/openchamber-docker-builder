#!/bin/sh
# Minimal entrypoint: fail fast without UI password, ensure SSH key, run server.
set -eu

HOME_DIR="${HOME:-/home/openchamber}"

# Non-server commands (e.g. --version, status) skip the password requirement.
case "${1:-serve}" in
  serve | "")
    # shortcut: legacy UI_PASSWORD alias, drop when upstream removes it.
    if [ -z "${OPENCHAMBER_UI_PASSWORD:-}" ] && [ -n "${UI_PASSWORD:-}" ]; then
      OPENCHAMBER_UI_PASSWORD="$UI_PASSWORD"
      export OPENCHAMBER_UI_PASSWORD
    fi
    if [ -z "${OPENCHAMBER_UI_PASSWORD:-}" ]; then
      echo "[entrypoint] error: OPENCHAMBER_UI_PASSWORD is not set." >&2
      echo "[entrypoint] Example: OPENCHAMBER_UI_PASSWORD=\"\$(openssl rand -base64 24)\" docker compose up -d" >&2
      exit 1
    fi
    ;;
esac

SSH_DIR="${HOME_DIR}/.ssh"
SSH_KEY="${SSH_DIR}/id_ed25519"
mkdir -p "${SSH_DIR}" "${HOME_DIR}/workspaces"
if [ ! -f "${SSH_KEY}" ]; then
  echo "[entrypoint] generating SSH key..."
  ssh-keygen -t ed25519 -N "" -f "${SSH_KEY}" >/dev/null 2>&1 \
    || echo "[entrypoint] warning: SSH key generation failed, continuing" >&2
fi

exec openchamber "$@"
