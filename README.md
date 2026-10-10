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
  ghcr.io/amirghaghighi/openchamber:2.2.0
```

Open http://localhost:3000 and sign in with the password. Health: `/health`.

With compose (explicit 6-mount layout, named volumes):

```bash
OPENCHAMBER_UI_PASSWORD="$(openssl rand -base64 24)" docker compose up -d
```

The container fails fast with a clear error when `OPENCHAMBER_UI_PASSWORD` is
missing, since Docker binds `0.0.0.0` and unauthenticated LAN exposure is
blocked upstream.

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

## Versions

Pinned via build args (defaults: `OPENCHAMBER_VERSION=2.2.0`, `OPENCODE_VERSION=2.0.25`):

```bash
docker build --build-arg OPENCHAMBER_VERSION=2.3.0 --build-arg OPENCODE_VERSION=2.0.26 -t openchamber:dev .
```

To release a new upstream version: bump the defaults in `Dockerfile` and the
`workflow_dispatch` defaults, push to `main`. CI tags `latest`,
`<openchamber-version>`, `<openchamber-version>-<short-sha>`, all cosign-signed
with SBOM + provenance attestation. Weekly cron rebuilds the same versions on
a fresh base image.
