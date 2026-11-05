#!/usr/bin/env bash
# Sourceable PR-report builder for the upstream-check workflow.
#   . ./scripts/upstream-report.sh
#
# Reads env (set by the check step, CURRENT_*/LATEST_* per component,
# BUILDER_VERSION, optional RUN_TIMESTAMP) and provides:
#   build_pr_title     -> echo: chore: bump upstream (<changed components>)
#   build_branch_name    -> echo: upstream-<oc>-<code>-gh<gh>-docker<cli>-compose<compose>-node<12hex>
#   build_pr_body      -> stdout: markdown report
#
# Node values are full digests (sha256:<64hex>); shortening happens here only.
# The branch is a fingerprint of ALL six pins (changed or not), so a
# compose-only bump can never collide with a still-open PR branch.

short_digest() {
  printf '%s' "$1" | sed 's/^sha256://' | cut -c1-12
}

# _report_row <component> <current> <latest> <url> <link-label> <changed:0|1>
_report_row() {
  local name=$1 cur=$2 lat=$3 url=$4 label=$5 changed=$6
  local lat_cell=$lat lnk="—"
  if [ "$changed" = 1 ]; then
    lat_cell="**${lat}**"
    lnk="[$label]($url)"
  fi
  printf '| %s | %s | %s | %s |\n' "$name" "$cur" "$lat_cell" "$lnk"
}

build_pr_title() {
  local parts=() joined="" p
  [ "$LATEST_OC" != "$CURRENT_OC" ] && parts+=("openchamber ${LATEST_OC}")
  [ "$LATEST_CODE" != "$CURRENT_CODE" ] && parts+=("opencode ${LATEST_CODE}")
  [ "$LATEST_GH" != "$CURRENT_GH" ] && parts+=("gh ${LATEST_GH}")
  [ "$LATEST_DOCKER_CLI" != "$CURRENT_DOCKER_CLI" ] && parts+=("docker-cli ${LATEST_DOCKER_CLI}")
  [ "$LATEST_DOCKER_COMPOSE" != "$CURRENT_DOCKER_COMPOSE" ] && parts+=("compose ${LATEST_DOCKER_COMPOSE}")
  [ "$LATEST_NODE" != "$CURRENT_NODE" ] && parts+=("node $(short_digest "$LATEST_NODE")")
  for p in "${parts[@]}"; do
    if [ -z "$joined" ]; then joined=$p; else joined="$joined, $p"; fi
  done
  printf 'chore: bump upstream (%s)\n' "$joined"
}

build_branch_name() {
  printf 'upstream-%s-%s-gh%s-docker%s-compose%s-node%s\n' \
    "$LATEST_OC" "$LATEST_CODE" "$LATEST_GH" "$LATEST_DOCKER_CLI" \
    "$LATEST_DOCKER_COMPOSE" "$(short_digest "$LATEST_NODE")"
}

build_pr_body() {
  local ts="${RUN_TIMESTAMP:-$(date -u '+%Y-%m-%d %H:%M UTC')}"
  local ch_oc=0 ch_code=0 ch_gh=0 ch_cli=0 ch_compose=0 ch_node=0
  [ "$LATEST_OC" != "$CURRENT_OC" ] && ch_oc=1
  [ "$LATEST_CODE" != "$CURRENT_CODE" ] && ch_code=1
  [ "$LATEST_GH" != "$CURRENT_GH" ] && ch_gh=1
  [ "$LATEST_DOCKER_CLI" != "$CURRENT_DOCKER_CLI" ] && ch_cli=1
  [ "$LATEST_DOCKER_COMPOSE" != "$CURRENT_DOCKER_COMPOSE" ] && ch_compose=1
  [ "$LATEST_NODE" != "$CURRENT_NODE" ] && ch_node=1
  local n=$((ch_oc + ch_code + ch_gh + ch_cli + ch_compose + ch_node))

  printf '## Upstream check report\n'
  printf 'Ran %s — %s of 6 pins changed\n' "$ts" "$n"
  printf '| Component | Current | Latest | Release notes |\n'
  printf '|---|---|---|---|\n'
  _report_row "@openchamber/web" "$CURRENT_OC" "$LATEST_OC" \
    "https://www.npmjs.com/package/@openchamber/web" "npm" "$ch_oc"
  _report_row "@opencode/cli" "$CURRENT_CODE" "$LATEST_CODE" \
    "https://www.npmjs.com/package/@opencode/cli" "npm" "$ch_code"
  _report_row "gh" "$CURRENT_GH" "$LATEST_GH" \
    "https://github.com/cli/cli/releases" "GitHub" "$ch_gh"
  _report_row "node (24-bookworm-slim)" "\`$(short_digest "$CURRENT_NODE")\`" "\`$(short_digest "$LATEST_NODE")\`" \
    "https://hub.docker.com/r/library/node/tags/24-bookworm-slim" "Docker Hub" "$ch_node"
  _report_row "docker-ce-cli" "$CURRENT_DOCKER_CLI" "$LATEST_DOCKER_CLI" \
    "https://github.com/moby/moby/releases" "GitHub" "$ch_cli"
  _report_row "docker-compose-plugin" "$CURRENT_DOCKER_COMPOSE" "$LATEST_DOCKER_COMPOSE" \
    "https://github.com/docker/compose/releases" "GitHub" "$ch_compose"
  printf 'Node base digest: `%s`\n' "$LATEST_NODE"
  printf '**On merge:** docker-publish pushes `ghcr.io/amirghaghighi/openchamber` tags `latest`, `%s`, `%s-%s`, `%s-%s-%s` (cosign-signed). Close to skip.\n' \
    "$LATEST_OC" "$LATEST_OC" "$LATEST_CODE" "$LATEST_OC" "$LATEST_CODE" "$BUILDER_VERSION"
}
