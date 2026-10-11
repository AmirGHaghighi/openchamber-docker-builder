# syntax=docker/dockerfile:1
# Clean-room build. Never FROM a third-party openchamber image.
# Sources: Node base image + npm registry (@openchamber/web, @opencode/cli) only.
# Update NODE_IMAGE_DIGEST explicitly when upgrading the base.
ARG NODE_IMAGE_DIGEST
FROM node:24-bookworm-slim@${NODE_IMAGE_DIGEST}

ARG OPENCHAMBER_VERSION
ARG OPENCODE_VERSION
ARG BUILDER_VERSION

# Fail fast: versions.env is the single source of truth, passed as build args.
RUN test -n "${OPENCHAMBER_VERSION:-}" || (echo "error: OPENCHAMBER_VERSION build arg is empty (source versions.env)" >&2; exit 1); \
    test -n "${OPENCODE_VERSION:-}" || (echo "error: OPENCODE_VERSION build arg is empty (source versions.env)" >&2; exit 1); \
    test -n "${BUILDER_VERSION:-}" || (echo "error: BUILDER_VERSION build arg is empty (source versions.env)" >&2; exit 1)

LABEL org.opencontainers.image.version=${OPENCHAMBER_VERSION} \
      builder.version=${BUILDER_VERSION}

ENV NODE_ENV=production \
    LANG=C.UTF-8 \
    HOME=/home/openchamber \
    NPM_CONFIG_PREFIX=/home/openchamber/.npm-global
ENV PATH=/home/openchamber/.npm-global/bin:${PATH}

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      gosu \
      openssh-client \
      python3 \
    && rm -rf /var/lib/apt/lists/* \
    # Replace the base image's 'node' user (UID/GID 1000) with 'openchamber'
    # so mounted volumes with 1000:1000 ownership work correctly.
    && (userdel -r node || true) \
    && (getent group node && groupdel node || true) \
    && groupadd -g 1000 openchamber \
    && useradd -u 1000 -g 1000 -m -s /bin/bash openchamber \
    && mkdir -p /home/openchamber/.npm-global /home/openchamber/workspaces \
    && chown -R openchamber:openchamber /home/openchamber

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod 755 /usr/local/bin/docker-entrypoint.sh

# Stay root: entrypoint fixes volume ownership, then drops to openchamber.
WORKDIR /home/openchamber

RUN gosu openchamber npm install -g "@openchamber/web@${OPENCHAMBER_VERSION}" "@opencode/cli@${OPENCODE_VERSION}" \
    && gosu openchamber npm cache clean --force \
    && gosu openchamber openchamber --version \
    && gosu openchamber opencode --version

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -fsS http://127.0.0.1:3000/health || exit 1

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["serve", "--foreground", "--host", "0.0.0.0", "--port", "3000"]
