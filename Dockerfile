# syntax=docker/dockerfile:1
# Clean-room build. Never FROM a third-party openchamber image.
# Sources: Node base image + npm registry (@openchamber/web, @opencode/cli) only.
# Update NODE_IMAGE_DIGEST explicitly when upgrading the base.
ARG NODE_IMAGE_DIGEST
FROM node:24-bookworm-slim@${NODE_IMAGE_DIGEST}

ARG OPENCHAMBER_VERSION
ARG OPENCODE_VERSION
ARG GH_VERSION
ARG DOCKER_CLI_VERSION
ARG DOCKER_COMPOSE_VERSION
ARG BUILDER_VERSION

# Fail fast: versions.env is the single source of truth, passed as build args.
RUN test -n "${OPENCHAMBER_VERSION:-}" || (echo "error: OPENCHAMBER_VERSION build arg is empty (source versions.env)" >&2; exit 1); \
    test -n "${OPENCODE_VERSION:-}" || (echo "error: OPENCODE_VERSION build arg is empty (source versions.env)" >&2; exit 1); \
    test -n "${GH_VERSION:-}" || (echo "error: GH_VERSION build arg is empty (source versions.env)" >&2; exit 1); \
    test -n "${DOCKER_CLI_VERSION:-}" || (echo "error: DOCKER_CLI_VERSION build arg is empty (source versions.env)" >&2; exit 1); \
    test -n "${DOCKER_COMPOSE_VERSION:-}" || (echo "error: DOCKER_COMPOSE_VERSION build arg is empty (source versions.env)" >&2; exit 1); \
    test -n "${BUILDER_VERSION:-}" || (echo "error: BUILDER_VERSION build arg is empty (source versions.env)" >&2; exit 1)

LABEL org.opencontainers.image.version=${OPENCHAMBER_VERSION} \
      builder.version=${BUILDER_VERSION}

ENV NODE_ENV=production \
    LANG=C.UTF-8 \
    HOME=/home/openchamber \
    NPM_CONFIG_PREFIX=/home/openchamber/.npm-global
ENV PATH=/home/openchamber/.npm-global/bin:${PATH}

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      openssh-client \
      python3 \
    && rm -rf /var/cache/apt/archives/* \
    # GitHub CLI apt repo (amd64-only ceiling; GitHub publishes arm64 too).
    # ponytail: TOFU keyring download; pin keyring hash when supply-chain requires it.
    && curl -fsSL -o /usr/share/keyrings/githubcli-archive-keyring.gpg https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    && chmod 644 /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends "gh=${GH_VERSION}*" \
    && rm -rf /var/cache/apt/archives/* \
    # Docker CLI apt repo (amd64-only ceiling, same as gh above).
    # Docker serves an ASCII-armored key: save as .asc per upstream docs
    # (a .gpg path makes apt reject the repo with NO_PUBKEY).
    # ponytail: TOFU keyring download; pin keyring hash when supply-chain requires it.
    && curl -fsSL -o /usr/share/keyrings/docker-archive-keyring.asc https://download.docker.com/linux/debian/gpg \
    && chmod 644 /usr/share/keyrings/docker-archive-keyring.asc \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.asc] https://download.docker.com/linux/debian bookworm stable" \
      > /etc/apt/sources.list.d/docker.list \
    && apt-get update && apt-get install -y --no-install-recommends \
      "docker-ce-cli=5:${DOCKER_CLI_VERSION}*" \
      "docker-compose-plugin=${DOCKER_COMPOSE_VERSION}*" \
    && rm -rf /var/cache/apt/archives/* \
    && mkdir -p /home/openchamber/.npm-global /home/openchamber/workspaces

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod 755 /usr/local/bin/docker-entrypoint.sh

# Run as root: agents install packages (uv, gitleaks) at runtime.
WORKDIR /home/openchamber

RUN --mount=type=cache,target=/home/openchamber/.npm \
    npm install -g "@openchamber/web@${OPENCHAMBER_VERSION}" "@opencode/cli@${OPENCODE_VERSION}" \
    && openchamber --version \
    && opencode --version \
    && gh --version \
    && docker --version \
    && docker compose version

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -fsS http://127.0.0.1:${OPENCHAMBER_PORT:-3000}/health || exit 1

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
# Keep flags out of CMD: entrypoint applies OPENCHAMBER_HOST (default 0.0.0.0)
# and OPENCHAMBER_PORT (translated to --port) from the environment.
# Explicit flags in a compose `command:` override still win.
CMD ["serve", "--foreground"]
