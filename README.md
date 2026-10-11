# openchamber-docker-builder

Production-ready Docker image bundling [OpenChamber](https://github.com/openchamber/openchamber)
(web UI) and [OpenCode](https://github.com/sst/opencode) (coding agent), published to GHCR.

Clean-room build: sources are the Node base image plus the npm registry only.
This image never uses `FROM` on third-party openchamber images.

## Quickstart

```bash
docker run -d --name openchamber -p 3000:3000 \
  -e OPENCHAMBER_UI_PASSWORD="$(openssl rand -base64 24)" \
  -v openchamber-home:/home/openchamber \
  -v ./workspaces:/home/openchamber/workspaces \
  ghcr.io/amirghaghighi/openchamber:2.2.0-2.0.25-0.0.1
```

Open http://localhost:3000 and sign in with the password. Health: `/health`.

With compose (explicit 6-mount layout, named volumes):

```bash
OPENCHAMBER_UI_PASSWORD="$(openssl rand -base64 24)" docker compose up -d
```

The container fails fast with a clear error when `OPENCHAMBER_UI_PASSWORD` is
missing, since Docker binds `0.0.0.0` and unauthenticated LAN exposure is
blocked upstream.

## Deploy with compose

On the server:

```bash
git clone https://github.com/AmirGHaghighi/openchamber-docker-builder.git
cd openchamber-docker-builder
cp .env.example .env   # set OPENCHAMBER_UI_PASSWORD (and IMAGE_TAG if pinned)
mkdir -p workspaces
docker compose up -d
```

Check health, then follow logs:

```bash
curl -fsS http://localhost:3000/health
docker compose logs -f
```

Update to a newer image:

```bash
docker compose pull && docker compose up -d
```

Back up everything except `opencode-state` (see Volumes table below). Named
volumes live under Docker's volume dir; the bind-mounted `./workspaces` backs
up with plain file copy.

## Environment

| Variable | Required | Purpose |
|---|---|---|
| `OPENCHAMBER_UI_PASSWORD` | yes (server) | Browser UI password |
| `OPENCHAMBER_LAN_URL` | LAN pairing | Address pairing links offer, e.g. `http://192.168.1.20:3000` |
| `OPENCHAMBER_DATA_DIR` | no | Override data dir (default `~/.config/openchamber`) |
| `OPENCODE_HOST` + `OPENCODE_SKIP_START=true` | no | Use an external OpenCode server instead of the managed one |
| `OPENCODE_PORT` | no | Port of external OpenCode server |
| `UI_PASSWORD` | no | Legacy alias of `OPENCHAMBER_UI_PASSWORD` |

Port/host can be overridden per run: `docker run ... <image> serve --foreground --host 0.0.0.0 --port 8080`.

## Volumes

| Volume | Mount | Stored | Safe to delete? | Why back up? |
|---|---|---|---|---|
| `openchamber-config` | `/home/openchamber/.config/openchamber` | Projects, sessions index, device tokens, UI settings | No — lose projects, sessions, pairings | Yes — only copy of session/project state |
| `opencode-share` | `/home/openchamber/.local/share/opencode` | Provider auth, session history, message cache | No — lose auth + agent history | Yes — avoids re-login, keeps history |
| `opencode-state` | `/home/openchamber/.local/state/opencode` | Logs, temp files, crash recovery | Yes — debug logs only | No — ephemeral |
| `opencode-config` | `/home/openchamber/.config/opencode` | `opencode.json`, rules, permissions | No — resets agent config | Yes — your tuned agent setup |
| `ssh-keys` | `/home/openchamber/.ssh` | ed25519 keypair, known_hosts | Key rotates — re-authorize in git hosts | Yes — avoids re-authorizing key |
| `./workspaces` | `/home/openchamber/workspaces` | User code — the only volume holding user value | Must keep | Yes — irreplaceable user work |

## Versions

Pinned in `versions.env` (single source of truth): `OPENCHAMBER_VERSION`,
`OPENCODE_VERSION`, `NODE_IMAGE_DIGEST`, `BUILDER_VERSION`.

- Upstream bump: edit the upstream pin(s) only.
- Builder/infra change: bump `BUILDER_VERSION` only.
- Any `versions.env` value change on `main` = release. Comment/whitespace-only
  edits are skipped by the value-diff gate.

```bash
set -a; . ./versions.env; set +a
docker build \
  --build-arg NODE_IMAGE_DIGEST="$NODE_IMAGE_DIGEST" \
  --build-arg OPENCHAMBER_VERSION="$OPENCHAMBER_VERSION" \
  --build-arg OPENCODE_VERSION="$OPENCODE_VERSION" \
  --build-arg BUILDER_VERSION="$BUILDER_VERSION" \
  -t openchamber:dev .
```

Published tags: `latest`, `<openchamber>`, `<openchamber>-<opencode>`,
`<openchamber>-<opencode>-<builder>` (e.g. `2.2.0-2.0.25-0.0.1`). Only the
4-part tag is immutable — the rest float and get overwritten on later
releases, so pin the 4-part tag. All tags cosign-signed with SBOM +
provenance attestation.

Infra-only fixes (Dockerfile, entrypoint, workflows) get a no-push
validation build via `docker-validate`. A weekly `upstream-check` workflow
queries npm for new `@openchamber/web` / `@opencode/cli` releases and opens
a bump PR only when a pin actually changed; merging it publishes. Quiet
weeks produce no PR.
