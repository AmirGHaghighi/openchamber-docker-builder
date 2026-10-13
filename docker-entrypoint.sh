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
    # Entrypoint envs: upstream has no port env, so OPENCHAMBER_PORT is
    # translated to --port here (drop when upstream documents it).
    # OPENCHAMBER_HOST is read by upstream itself; the entrypoint only
    # supplies the Docker default (0.0.0.0) when neither flag nor env set it.
    has_port_flag=false
    has_host_flag=false
    for arg in "$@"; do
      case "$arg" in
        --port|--port=*|-p) has_port_flag=true ;;
        --host|--host=*) has_host_flag=true ;;
      esac
    done
    if [ "$has_host_flag" = true ]; then
      if [ -n "${OPENCHAMBER_HOST:-}" ]; then
        echo "[entrypoint] warning: --host flag wins, ignoring OPENCHAMBER_HOST" >&2
      fi
    elif [ -z "${OPENCHAMBER_HOST:-}" ]; then
      # Upstream defaults to 127.0.0.1, which would make mapped ports
      # unreachable from outside the container.
      OPENCHAMBER_HOST=0.0.0.0
      export OPENCHAMBER_HOST
    fi
    if [ "$has_port_flag" = true ]; then
      if [ -n "${OPENCHAMBER_PORT:-}" ]; then
        echo "[entrypoint] warning: --port flag wins, ignoring OPENCHAMBER_PORT" >&2
      fi
    elif [ -n "${OPENCHAMBER_PORT:-}" ]; then
      case "$OPENCHAMBER_PORT" in
        ''|*[!0-9]*)
          echo "[entrypoint] error: OPENCHAMBER_PORT must be 1-65535, got '${OPENCHAMBER_PORT}'." >&2
          exit 1
          ;;
      esac
      if [ "$OPENCHAMBER_PORT" -lt 1 ] || [ "$OPENCHAMBER_PORT" -gt 65535 ]; then
        echo "[entrypoint] error: OPENCHAMBER_PORT must be 1-65535, got '${OPENCHAMBER_PORT}'." >&2
        exit 1
      fi
      set -- "$@" --port "$OPENCHAMBER_PORT"
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

# Run as root: agents install packages (uv, gitleaks) at runtime.
exec openchamber "$@"
