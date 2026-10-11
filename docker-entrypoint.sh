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

# Named volumes mount root-owned on first use. Take ownership so the
# non-root server can write config, state, keys, and workspaces.
if [ "$(id -u)" = "0" ]; then
  chown -R openchamber:openchamber \
    "${HOME_DIR}/.config" \
    "${HOME_DIR}/.local" \
    "${HOME_DIR}/.npm-global" \
    "${HOME_DIR}/.ssh" \
    "${HOME_DIR}/workspaces" 2>/dev/null || true
  mkdir -p "${HOME_DIR}/.config" "${HOME_DIR}/.local" "${SSH_DIR}" "${HOME_DIR}/workspaces"
  chown -R openchamber:openchamber \
    "${HOME_DIR}/.config" \
    "${HOME_DIR}/.local" \
    "${HOME_DIR}/.npm-global" \
    "${SSH_DIR}" \
    "${HOME_DIR}/workspaces" 2>/dev/null || true
fi

mkdir -p "${SSH_DIR}" "${HOME_DIR}/workspaces"
if [ ! -f "${SSH_KEY}" ]; then
  echo "[entrypoint] generating SSH key..."
  ssh-keygen -t ed25519 -N "" -f "${SSH_KEY}" >/dev/null 2>&1 \
    || echo "[entrypoint] warning: SSH key generation failed, continuing" >&2
fi

# Drop privileges: the server itself never runs as root.
# The init steps above briefly run as root (standard gosu pattern) only to
# fix volume ownership; execution below is always as openchamber.
if [ "$(id -u)" = "0" ]; then
  if ! command -v gosu >/dev/null 2>&1; then
    echo "[entrypoint] error: gosu missing, refusing to run as root" >&2
    exit 1
  fi
  exec gosu openchamber openchamber "$@"
fi

# Final guard: if we are still root here, refuse instead of running the server.
if [ "$(id -u)" = "0" ]; then
  echo "[entrypoint] error: refusing to run server as root" >&2
  exit 1
fi

exec openchamber "$@"
