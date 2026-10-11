# syntax=docker/dockerfile:1
# Clean-room build. Never FROM a third-party openchamber image.
# Sources: Node base image + npm registry (@openchamber/web, @opencode/cli) only.
# Update NODE_IMAGE_DIGEST explicitly when upgrading the base.
ARG NODE_IMAGE_DIGEST=sha256:d6aa754f16b3197301076f047b5def2f02ea1dbbc2ca920407d46d7ec7f87b20
FROM node:24-bookworm-slim@${NODE_IMAGE_DIGEST}

ARG OPENCHAMBER_VERSION=2.2.0
ARG OPENCODE_VERSION=2.0.25

ENV NODE_ENV=production \
    LANG=C.UTF-8 \
    HOME=/home/openchamber \
    NPM_CONFIG_PREFIX=/home/openchamber/.npm-global
ENV PATH=/home/openchamber/.npm-global/bin:${PATH}

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
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

USER openchamber
WORKDIR /home/openchamber

RUN npm install -g "@openchamber/web@${OPENCHAMBER_VERSION}" "@opencode/cli@${OPENCODE_VERSION}" \
    && npm cache clean --force \
    && openchamber --version \
    && opencode --version

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -fsS http://127.0.0.1:3000/health || exit 1

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["serve", "--foreground", "--host", "0.0.0.0", "--port", "3000"]
