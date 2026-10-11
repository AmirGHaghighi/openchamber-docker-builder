# OpenChamber UI password research

Date: 2026-10-11. Upstream: `openchamber/openchamber` `main` (cloned 2026-10-11).
Question: can the browser UI password be set/changed from the browser UI, or only via CLI flag / env var?

## Short answers

- **Set (first time), `openchamber serve`:** `--ui-password <value>` flag, `OPENCHAMBER_UI_PASSWORD` env var, or bare `--ui-password` (server generates a 16-char password and prints it once). No browser-UI setter exists for `serve`.
- **Change from browser UI while running:** **No.** No settings page or API route sets a new UI password at runtime. The only auth-mutating browser action is `POST /api/auth/reset` ("Sign out everywhere"), which rotates the JWT secret and wipes passkeys — it does not install a new password. Changing the password requires restarting the server with a new flag/env value.
- **Env var live or startup-only:** **Startup-only.** `server/index.js` reads `options.uiPassword ?? process.env.OPENCHAMBER_UI_PASSWORD` once at boot and `createUiAuth()` hashes it into memory; later env edits have no effect until restart.
- **Mismatch / rotation:** wrong password → `401 { error: 'Invalid credentials' }` + rate-limit counting + cookie cleared. Restarting with a new password **does not** invalidate existing browser session cookies by itself (sessions are JWTs verified only against the persisted JWT secret); it **does** wipe stored passkeys (password-bound). Only `POST /api/auth/reset` (JWT-secret rotation) signs out everywhere.

## All ways to SET the password (first time)

1. **CLI flag with value** — `openchamber --ui-password be-creative-here` / `openchamber serve --ui-password <pw>`.
   Docs (`security.mdx` / published Security page) show exactly this as the primary method; `--help` lists `--ui-password [password] Protect browser UI with a password (generates one when omitted)`.
   Sources:
   - https://docs.openchamber.dev/security/
   - https://raw.githubusercontent.com/openchamber/openchamber/main/packages/docs/content/docs/security.mdx
   - https://raw.githubusercontent.com/openchamber/openchamber/main/packages/web/bin/lib/cli-args.js (`--ui-password` case, help text)
2. **Env var** — `OPENCHAMBER_UI_PASSWORD=<pw> openchamber` (documented as the alternative to the flag; required before LAN/tunnel/reverse-proxy exposure).
   Sources:
   - https://docs.openchamber.dev/security/
   - https://docs.openchamber.dev/environment/ (`OPENCHAMBER_UI_PASSWORD`, plus `OPENCHAMBER_UI_SESSION_TTL_HOURS` default 12, `OPENCHAMBER_UI_TRUSTED_SESSION_TTL_DAYS` default 7)
   - https://raw.githubusercontent.com/openchamber/openchamber/main/packages/docs/content/docs/environment.mdx
   - https://raw.githubusercontent.com/openchamber/openchamber/main/packages/web/server/index.js (`startWebUiServer`: `options.uiPassword ?? process.env.OPENCHAMBER_UI_PASSWORD`, then refuses network-exposed bind without a password)
3. **Bare `--ui-password` (generated)** — flag without a value generates a 16-char password from an unambiguous charset (`ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789`); daemon/foreground serve prints it once ("Save this password — it is not shown again") and persists it in the instance state file that restart/status flows read.
   Sources:
   - https://raw.githubusercontent.com/openchamber/openchamber/main/packages/web/bin/lib/cli-network.js (`hasUiPasswordConfigured`, `generateUiPassword`, `resolveServeUiPassword`)
   - https://raw.githubusercontent.com/openchamber/openchamber/main/packages/web/bin/lib/commands-serve.js (resolve → env propagation → generated-password output → `writeInstanceOptions({ uiPassword })`)
   - https://raw.githubusercontent.com/openchamber/openchamber/main/packages/web/bin/lib/cli-args.js (`explicitUiPassword` tracking)
4. **Startup-service / auto-start callers** — `openchamber startup enable [--ui-password …]` snapshots the password into the service env (re-run after changing it); `connect-url --ui-password` and `tunnel start --ui-password` apply it when they auto-start an instance. CLI restarts and in-app updates reuse the saved instance `uiPassword` by re-exporting `OPENCHAMBER_UI_PASSWORD` to the child.
   Sources:
   - https://raw.githubusercontent.com/openchamber/openchamber/main/packages/web/bin/lib/cli-startup.js (`env.OPENCHAMBER_UI_PASSWORD = uiPassword`)
   - https://raw.githubusercontent.com/openchamber/openchamber/main/packages/web/bin/lib/cli-args.js (`startup enable` / `connect-url` / `tunnel start` help text)
   - https://raw.githubusercontent.com/openchamber/openchamber/main/packages/web/server/lib/opencode/openchamber-routes.js (update/restart spawn with `OPENCHAMBER_UI_PASSWORD: storedOptions.uiPassword`)
   - https://docs.openchamber.dev/environment/ ("`openchamber startup enable` snapshots the current environment by default, so rerun it after changing variables")
5. **Desktop app only** — the Electron shell reads the persisted `desktopUiPassword` setting and launches its managed server with `OPENCHAMBER_UI_PASSWORD` / `uiPassword`. This never applies to a standalone `openchamber serve` process.
   Sources:
   - https://raw.githubusercontent.com/openchamber/openchamber/main/packages/electron/main.mjs (reads `settings.desktopUiPassword`, spawns with `OPENCHAMBER_UI_PASSWORD` + `uiPassword`)
   - https://raw.githubusercontent.com/openchamber/openchamber/main/packages/ui/src/components/sections/openchamber/DesktopNetworkSettings.tsx (write-only field, `hasDesktopUiPassword` flag, desktop-surfaces-only)
   - https://raw.githubusercontent.com/openchamber/openchamber/main/packages/ui/src/lib/settings/registry.ts (`desktopUiPassword: … surfaces: ['desktop']`)
6. **Legacy/compat aliases (marginal):** `parseServeCliOptions` in `server/lib/opencode/cli-options.js` also accepts `OPENCODE_UI_PASSWORD` as an env fallback; this repo's Docker layer additionally maps `UI_PASSWORD` → `OPENCHAMBER_UI_PASSWORD` in `docker-entrypoint.sh` (repo-local, upstream does not document `UI_PASSWORD`).
   Sources:
   - https://raw.githubusercontent.com/openchamber/openchamber/main/packages/web/server/lib/opencode/cli-options.js (`env.OPENCHAMBER_UI_PASSWORD || env.OPENCODE_UI_PASSWORD`)
   - `docker-entrypoint.sh`, `docker-compose.yml`, `.env.example`, `README.md` (this repo)

Password normalization: `normalizePassword()` = Unicode `.normalize().trim()`; `hasUiPasswordConfigured()` treats empty/whitespace-only as unset.
Sources:
- https://raw.githubusercontent.com/openchamber/openchamber/main/packages/web/server/lib/ui-auth/ui-auth.js (`normalizePassword`, `verifyPassword` via scrypt + `timingSafeEqual`)
- https://raw.githubusercontent.com/openchamber/openchamber/main/packages/web/bin/lib/cli-network.js (`hasUiPasswordConfigured`)

## Can it be CHANGED from the browser UI while running?

**No (for `serve`).** Evidence:

- No server route sets a password at runtime. The auth surface in `server/lib/opencode/core-routes.js` is: `GET/POST /auth/session` (status/login), `POST /auth/url-token`, `GET /auth/passkey/status`, `POST /auth/passkey/{authenticate,register}/…`, `GET /api/passkeys`, `DELETE /api/passkeys/:id`, `POST /api/auth/reset`. There is no `PUT/POST …/password`, no `setUiPassword`/`updateUiPassword` handler anywhere under `packages/web/server`.
  Source: https://raw.githubusercontent.com/openchamber/openchamber/main/packages/web/server/lib/opencode/core-routes.js
- The browser `POST /auth/session` body only takes `{ password, trustDevice, issueClientToken, … }` for *verification* (`verifyPassword` → issue session JWT on success). There is no "new password" field.
  Source: https://raw.githubusercontent.com/openchamber/openchamber/main/packages/web/server/lib/ui-auth/ui-auth.js (`handleSessionCreate`)
- `POST /api/auth/reset` ("Sign out everywhere" in `PasskeySettings.tsx`) requires a valid session (`requireSessionAuth`), then: clears all passkeys, rotates the JWT secret, clears URL tokens, clears the caller's cookie, returns `{ cleared: true, clearedPasskeys, signedOutEverywhere: true }`. It is **not** a password change — the configured password stays what the process booted with. It is also disabled for tunnel scope (`403`, `tunnelLocked: true`) and throws `400 Global sign-out is unavailable while OPENCODE_JWT_SECRET is set`.
  Sources:
  - https://raw.githubusercontent.com/openchamber/openchamber/main/packages/web/server/lib/ui-auth/ui-auth.js (`handleResetAuth`, `rotateJwtSecret`, `persistJwtSecret`)
  - https://raw.githubusercontent.com/openchamber/openchamber/main/packages/web/server/lib/opencode/core-routes.js (`app.post('/api/auth/reset', …)`)
  - https://raw.githubusercontent.com/openchamber/openchamber/main/packages/ui/src/components/sections/openchamber/PasskeySettings.tsx (`handleResetAllAuth` → `window.location.reload()`)
  - https://raw.githubusercontent.com/openchamber/openchamber/main/packages/ui/src/lib/passkeys.ts (`resetAllAuth` → `/api/auth/reset`)
- Settings UI: `Settings → OpenChamber` contains `PasskeySettings` (add/revoke passkeys, sign-out-everywhere) plus, **desktop shell only**, `DesktopNetworkSettings` (write-only `desktopUiPassword` field). The General-section comment mentioning "access password" refers to that desktop-only field; the web `serve` runtime never reads `desktopUiPassword` from the settings file (registry marks it `surfaces: ['desktop']`; `bootstrap-runtime.js` passes only the boot-time `uiPassword` into `createUiAuth`).
  Sources:
  - https://raw.githubusercontent.com/openchamber/openchamber/main/packages/ui/src/components/sections/openchamber/OpenChamberPage.tsx
  - https://raw.githubusercontent.com/openchamber/openchamber/main/packages/ui/src/components/sections/openchamber/DesktopNetworkSettings.tsx
  - https://raw.githubusercontent.com/openchamber/openchamber/main/packages/web/server/lib/opencode/settings-registry.json (`desktopUiPassword` / `hasDesktopUiPassword`)
  - https://raw.githubusercontent.com/openchamber/openchamber/main/packages/web/server/lib/opencode/bootstrap-runtime.js (`createUiAuth({ password: uiPassword, … })`, "UI password protection enabled for browser sessions")
- Docs describe password changes only as out-of-band ("If you change or remove the password, saved passkeys are cleared and you'll add them again" at `Settings → OpenChamber → Passkeys`), i.e. restart with a new value, then re-enroll passkeys.
  Source: https://docs.openchamber.dev/security/

**Persistence note:** since the browser cannot change the password, there is nothing browser-side to persist. The durable password for services is the snapshotted service env / instance state file (`startup enable`, `writeInstanceOptions`); a browser "change" would not survive restart because no such write path exists.

## Env var: read once at startup or re-read live?

**Read once at startup.** `startWebUiServer` resolves `uiPassword` a single time, hands it to `setupBaseRoutes → createUiAuth({ password })`, which normalizes it, derives the scrypt hash + random salt once, and closes over them. `verifyPassword` compares each login against the in-memory hash; nothing re-reads `process.env` per request and there is no settings/env watcher for the password. Daemon spawns bake the resolved value into the child's env (`assignInjectedEnv({ … OPENCHAMBER_UI_PASSWORD: effectiveUiPassword })`); update/restart re-exports the stored value.
Sources:
- https://raw.githubusercontent.com/openchamber/openchamber/main/packages/web/server/index.js (`const uiPassword = … options.uiPassword … process.env.OPENCHAMBER_UI_PASSWORD …`)
- https://raw.githubusercontent.com/openchamber/openchamber/main/packages/web/server/lib/opencode/bootstrap-runtime.js
- https://raw.githubusercontent.com/openchamber/openchamber/main/packages/web/server/lib/ui-auth/ui-auth.js (`createUiAuth`, `normalizePassword`, `expectedHash`/`salt`, `verifyPassword`, `readSessionTtlMs` TTL handling)
- https://raw.githubusercontent.com/openchamber/openchamber/main/packages/web/bin/lib/commands-serve.js
- https://raw.githubusercontent.com/openchamber/openchamber/main/packages/web/server/lib/ui-auth/DOCUMENTATION.md

## Mismatch / rotation behavior (existing sessions?)

- **Wrong password:** `POST /auth/session` → `401 { error: 'Invalid credentials' }`, failed attempt recorded for rate limiting, session cookie cleared. Rate limits: 10 attempts / 5 min per IP (3 for no-IP key), 15-min lockout → `429` + `Retry-After` (+ `X-RateLimit-*` headers).
  Source: https://raw.githubusercontent.com/openchamber/openchamber/main/packages/web/server/lib/ui-auth/ui-auth.js (`handleSessionCreate`, `checkRateLimit`, `RATE_LIMIT_*` constants)
- **Password rotated across restart (new flag/env, same data dir):** existing browser session cookies **stay valid** until their own expiry (default 12 h, 7 d trusted-device), because `isSessionValid` only `jwtVerify`s against the persisted JWT secret (`$OPENCHAMBER_DATA_DIR/jwt-secret`, `0600`, auto-created; or `OPENCODE_JWT_SECRET` env when set). Session JWT payload is `{ type: 'ui-session', iat, exp }` — no password binding. So rotation alone does **not** revoke sessions.
  Sources:
  - https://raw.githubusercontent.com/openchamber/openchamber/main/packages/web/server/lib/ui-auth/ui-auth.js (`isSessionValid`, `issueSession`, `getOrCreateJwtSecret`, `JWT_SECRET_FILE`)
  - https://docs.openchamber.dev/environment/ (`OPENCODE_JWT_SECRET`: "Secret used to sign UI authentication tokens. Use a long random value for persistent service deployments")
- **Passkeys on password change:** passkey store (`$OPENCHAMBER_DATA_DIR/ui-passkeys.json`) records `passwordBinding = HMAC(jwtSecret, normalizedPassword)`. On boot with a different password (or with password removed), `loadStore` discards all passkeys and persists the empty store — matching the docs sentence quoted above. Passkeys also require a password to be configured at all.
  Sources:
  - https://raw.githubusercontent.com/openchamber/openchamber/main/packages/web/server/lib/ui-auth/ui-passkeys.js (`passwordBinding`, `loadStore`, `assertEnabled`)
  - https://docs.openchamber.dev/security/ ("Passkeys are tied to the current password…")
- **True global revocation:** `POST /api/auth/reset` (authenticated) rotates and persists a fresh JWT secret, drops in-memory URL tokens, rebuilds the passkey controller, clears all passkeys, clears the caller's cookie → every existing session JWT fails verification. Caveats: needs a valid session, blocked for tunnel scope, blocked when `OPENCODE_JWT_SECRET` is set.
  Sources: `ui-auth.js` (`rotateJwtSecret`, `handleResetAuth`) + `core-routes.js` (`/api/auth/reset`) — same raw URLs as above.
- **Missing password on exposed bind:** hard start failure (`AUTH_CONFIG_ERROR`-class CLI error / `getUnauthenticatedLanErrorMessage`), and public tunnels refuse to start without one ("Restart OpenChamber with --ui-password", `ui_password_required`).
  Sources:
  - https://raw.githubusercontent.com/openchamber/openchamber/main/packages/web/bin/lib/cli-network.js (`assertAuthenticatedNetworkExposure`)
  - https://raw.githubusercontent.com/openchamber/openchamber/main/packages/web/server/lib/security/bind-host.js
  - https://raw.githubusercontent.com/openchamber/openchamber/main/packages/web/server/lib/tunnels/routes.js

## Implications for this Docker builder repo

- `OPENCHAMBER_UI_PASSWORD` (or repo-local `UI_PASSWORD` alias mapped in `docker-entrypoint.sh`) is the only password input for the containerized `serve`; compose marks it required (`${OPENCHAMBER_UI_PASSWORD:?…}`).
- Rotation = set the new value in the env file / host env and recreate the container. Old browser cookies survive rotation unless someone also hits "Sign out everywhere" (`POST /api/auth/reset`) before/after — consider documenting a reset step for rotations. Passkeys will be wiped server-side on the change; users re-enroll at `Settings → OpenChamber → Passkeys`.
- `OPENCODE_JWT_SECRET` deserves a stable value in long-lived Docker deployments (else each fresh data dir mints a new secret and pre-existing cookies die on volume loss); note it disables global sign-out while set.

## Full OpenChamber env reference (upstream `main`, 2026-10-11)

Documented at https://docs.openchamber.dev/environment/ unless marked `(undocumented)`.
Raw `OPENCHAMBER_*` scan also surfaced internals, `__`-suffixed test markers,
and dev-only helpers — those are excluded below. Code refs are
`packages/web/server/…` / `packages/web/bin/…` unless noted.

### Server bind + auth

- `OPENCHAMBER_HOST` — bind address. `--host` wins when both given.
  (`server/index.js`, `bin/lib/cli-network.js` `resolveConfiguredBindHost`)
- `OPENCHAMBER_PORT` — dev/vite/test scaffolding only (`vite.config.ts`,
  `scripts/dev-server-watch.mjs`). Production server never reads it for
  listening; port comes from `--port`/`-p` or daemon instance state.
- `OPENCHAMBER_LAN_URL` — address pairing links/QR offer. Display only.
- `OPENCHAMBER_UI_PASSWORD` — browser UI password. Startup-only.
- `OPENCODE_UI_PASSWORD` (undocumented) — env fallback for the above
  (`server/lib/opencode/cli-options.js`).
- `OPENCHAMBER_UI_SESSION_TTL_HOURS` — default 12.
- `OPENCHAMBER_UI_TRUSTED_SESSION_TTL_DAYS` — default 7.
- `OPENCHAMBER_API_ONLY` — headless mode (`true`/`1`).
- `OPENCHAMBER_FRAME_ANCESTORS` — allowed framing origins.
- `OPENCHAMBER_RATE_LIMIT_MAX_ATTEMPTS` (undocumented) — default 10 per 5 min.
- `OPENCHAMBER_RATE_LIMIT_NO_IP_MAX_ATTEMPTS` (undocumented) — default 3.
- `OPENCHAMBER_API_PREFIX` / `OPENCODE_API_PREFIX` (undocumented) — API prefix.

### Data dirs

- `OPENCHAMBER_DATA_DIR` — default `~/.config/openchamber`.
- `OPENCHAMBER_CHATS_DIR` — default `<data-dir>/chats`.

### OpenCode managed server

- `OPENCODE_HOST` — external OpenCode origin (explicit port, no path).
- `OPENCODE_PORT` — managed port request, or external port with skip-start.
- `OPENCODE_SKIP_START` / `OPENCHAMBER_SKIP_OPENCODE_START` — skip managed start.
- `OPENCHAMBER_OPENCODE_HOSTNAME` — managed bind hostname, default `127.0.0.1`.
- `OPENCODE_JWT_SECRET` — UI token signing secret. Stable value recommended
  for persistent deployments; while set, global sign-out is unavailable.
- `OPENCODE_BINARY` — opencode executable path.
- `OPENCODE_CONFIG` / `OPENCODE_CONFIG_DIR` / `OPENCODE_DATA_DIR` — config paths.
- `OPENCODE_WSL_DISTRO` / `OPENCHAMBER_OPENCODE_WSL_DISTRO` — WSL distro.
- `OPENCHAMBER_OPENCODE_PORT` (undocumented) — managed OpenCode port override.
- `OPENCHAMBER_OPENCODE_HEALTH_*` (undocumented) — healthcheck tuning
  (`INTERVAL_MS`, `TIMEOUT_MS`, `CACHE_MS`, `CONSECUTIVE_FAILURES`).

### Terminal / Git

- `OPENCHAMBER_TERMINAL_SHELL`, `OPENCHAMBER_GIT_BINARY`, `GIT_BINARY`,
  `OPENCHAMBER_GIT_READ_CACHE_TTL_MS`.

### Voice / tunnels / relay

- `OPENAI_API_KEY`, `OPENCHAMBER_ALLOW_REMOTE_OPENAI_COMPAT_URLS`, `NGROK_AUTHTOKEN`.
- `OPENCHAMBER_RELAY_URL` (undocumented in env page; enterprise docs cover it).
- `OPENCHAMBER_RELAY_HOST` (undocumented) — `on`/`off` passive relay hosting.
- `OPENCHAMBER_TRY_CF_TUNNEL` (legacy), `OPENCHAMBER_TUNNEL_PROVIDER`,
  `OPENCHAMBER_TUNNEL_MODE`, `OPENCHAMBER_TUNNEL_CONFIG`,
  `OPENCHAMBER_TUNNEL_TOKEN`, `OPENCHAMBER_TUNNEL_HOSTNAME` (undocumented).

### Enterprise mode

- `OPENCHAMBER_ENTERPRISE_MODE=1`, `OPENCHAMBER_ALLOW_NETWORK_ACCESS=1`,
  `OPENCHAMBER_ALLOWED_EXTENSIONS` (comma-separated),
  `OPENCHAMBER_ALLOW_LOCAL_EXTENSIONS=1`, `OPENCHAMBER_JEV_URL`,
  `OPENCHAMBER_JEV_MODEL`, `OPENCHAMBER_JEV_API_KEY`, `OPENCHAMBER_RELAY_URL`.
  (`server/lib/enterprise-mode.js`; https://docs.openchamber.dev/security/)

### App behavior / runtime

- `OPENCHAMBER_COMPRESS_API` / `OPENCHAMBER_SKIP_API_COMPRESSION`.
- `OPENCHAMBER_VERBOSE_REQUEST_LOGS`.
- `OPENCHAMBER_UPDATE_API_URL`, `OPENCHAMBER_PACKAGE_MANAGER`.
- `OPENCHAMBER_ALLOW_UNAUTHENTICATED_LAN` (undocumented) — bypasses
  unauthenticated-LAN refusal (`server/lib/security/bind-host.js`).
- `OPENCHAMBER_PUBLIC_ORIGIN`, `OPENCHAMBER_SERVER_URL` (undocumented).
- `OPENCHAMBER_VAPID_SUBJECT` (undocumented) — push notifications.
- `OPENCHAMBER_FS_EXEC_TIMEOUT_MS`, `OPENCHAMBER_FS_UPLOAD_MAX_BYTES`,
  `OPENCHAMBER_GUEST_UPLOAD_MAX_BYTES` (undocumented).
- `OPENCHAMBER_EVENT_DELTA_COALESCE_MS` (undocumented).
- `OPENCHAMBER_MEMORY_ENABLE` (undocumented).
- `OPENCHAMBER_RUNTIME`, `OPENCHAMBER_DESKTOP_NOTIFY`,
  `OPENCHAMBER_ELECTRON_DEV`, `OPENCHAMBER_BUNDLED_OPENCODE_CLI_DIR`,
  `OPENCHAMBER_NODE_BINARY`, `OPENCHAMBER_BUN_BINARY` (runtime/plumbing).
- `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY` (lowercase work too).
