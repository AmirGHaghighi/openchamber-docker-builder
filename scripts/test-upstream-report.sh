#!/usr/bin/env bash
# Self-check for scripts/upstream-report.sh.
# Run: bash scripts/test-upstream-report.sh
set -eu
cd "$(dirname "$0")"

FAILURES=0

assert_eq() {
  if [ "$2" = "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1"
    printf '  expected: %s\n  actual:   %s\n' "$2" "$3"
    FAILURES=1
  fi
}

assert_contains() {
  case "$2" in
    *"$3"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1"
      printf '  needle: %s\n' "$3"
      FAILURES=1
      ;;
  esac
}

assert_regex() {
  if printf '%s\n' "$2" | grep -Eq "$3"; then
    echo "ok: $1"
  else
    echo "FAIL: $1"
    printf '  regex: %s\n' "$3"
    FAILURES=1
  fi
}

. ./upstream-report.sh

# ---------------------------------------------------------------- fixture A
# 4 of 6 changed: openchamber, opencode, node digest, compose
export CURRENT_OC=2.5.3      LATEST_OC=2.5.4
export CURRENT_CODE=2.2.1    LATEST_CODE=2.3.0
export CURRENT_GH=2.103.3    LATEST_GH=2.103.3
export CURRENT_NODE=sha256:c86ecead9e55a5210ac1727de38a4ca840bf03dcaf34dc9749addbf383b1920c
export LATEST_NODE=sha256:b1a9f3d2e7c40568aa31b9e0247f6d5c8e9a1b2c3d4e5f60718293a4b5c6d7e8f
export CURRENT_DOCKER_CLI=29.9.2    LATEST_DOCKER_CLI=29.9.2
export CURRENT_DOCKER_COMPOSE=5.6.1 LATEST_DOCKER_COMPOSE=5.6.2
export BUILDER_VERSION=0.0.8
export RUN_TIMESTAMP="2026-11-05 03:00 UTC"

title="$(build_pr_title)"
assert_eq "A: title lists only changed pins" \
  "chore: bump upstream (openchamber 2.5.4, opencode 2.3.0, compose 5.6.2, node b1a9f3d2e7c4)" "$title"

branch="$(build_branch_name)"
assert_eq "A: branch is full six-pin fingerprint" \
  "upstream-2.5.4-2.3.0-gh2.103.3-docker29.9.2-compose5.6.2-nodeb1a9f3d2e7c4" "$branch"

body="$(build_pr_body)"
assert_contains "A: run line" "$body" "Ran 2026-11-05 03:00 UTC — 4 of 6 pins changed"
assert_contains "A: row openchamber" "$body" '| @openchamber/web | 2.5.3 | **2.5.4** | [npm](https://www.npmjs.com/package/@openchamber/web) |'
assert_contains "A: row opencode" "$body" '| @opencode/cli | 2.2.1 | **2.3.0** | [npm](https://www.npmjs.com/package/@opencode/cli) |'
assert_contains "A: row gh stable" "$body" '| gh | 2.103.3 | 2.103.3 | — |'
assert_contains "A: row node" "$body" '| node (24-bookworm-slim) | `c86ecead9e55` | **`b1a9f3d2e7c4`** | [Docker Hub](https://hub.docker.com/r/library/node/tags/24-bookworm-slim) |'
assert_contains "A: row docker-cli stable" "$body" '| docker-ce-cli | 29.9.2 | 29.9.2 | — |'
assert_contains "A: row compose" "$body" '| docker-compose-plugin | 5.6.1 | **5.6.2** | [GitHub](https://github.com/docker/compose/releases) |'
assert_contains "A: full node digest" "$body" 'Node base digest: `sha256:b1a9f3d2e7c40568aa31b9e0247f6d5c8e9a1b2c3d4e5f60718293a4b5c6d7e8f`'
assert_contains "A: on-merge tags" "$body" '**On merge:** docker-publish pushes `ghcr.io/amirghaghighi/openchamber` tags `latest`, `2.5.4`, `2.5.4-2.3.0`, `2.5.4-2.3.0-0.0.8` (cosign-signed). Close to skip.'

# ---------------------------------------------------------------- fixture B
# compose-only change (the historical branch-collision case)
export CURRENT_OC=2.5.3      LATEST_OC=2.5.3
export CURRENT_CODE=2.2.1    LATEST_CODE=2.2.1
export CURRENT_GH=2.103.3    LATEST_GH=2.103.3
export CURRENT_NODE=sha256:c86ecead9e55a5210ac1727de38a4ca840bf03dcaf34dc9749addbf383b1920c
export LATEST_NODE=sha256:c86ecead9e55a5210ac1727de38a4ca840bf03dcaf34dc9749addbf383b1920c
export CURRENT_DOCKER_CLI=29.9.2    LATEST_DOCKER_CLI=29.9.2
export CURRENT_DOCKER_COMPOSE=5.6.1 LATEST_DOCKER_COMPOSE=5.6.2

title="$(build_pr_title)"
assert_eq "B: compose-only title" "chore: bump upstream (compose 5.6.2)" "$title"

branch="$(build_branch_name)"
assert_eq "B: compose-only branch is unique" \
  "upstream-2.5.3-2.2.1-gh2.103.3-docker29.9.2-compose5.6.2-nodec86ecead9e55" "$branch"

body="$(build_pr_body)"
assert_contains "B: 1 of 6 pins changed" "$body" "— 1 of 6 pins changed"

# ---------------------------------------------------------------- fixture C
# gh-only change (reset compose to unchanged from fixture B)
export CURRENT_GH=2.103.3    LATEST_GH=2.104.0
export CURRENT_DOCKER_COMPOSE=5.6.1 LATEST_DOCKER_COMPOSE=5.6.1

title="$(build_pr_title)"
assert_eq "C: gh-only title" "chore: bump upstream (gh 2.104.0)" "$title"

body="$(build_pr_body)"
assert_contains "C: 1 of 6 pins changed" "$body" "— 1 of 6 pins changed"
assert_contains "C: gh release link" "$body" '[GitHub](https://github.com/cli/cli/releases)'

# ---------------------------------------------------------------- fixture D
# RUN_TIMESTAMP unset -> body still renders with a generated timestamp
unset RUN_TIMESTAMP
body="$(build_pr_body)"
assert_regex "D: generated run line" "$body" '^Ran [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} UTC'

# ---------------------------------------------------------------- fixture E
# Workflow contract: the check step must provide every env var the script requires.
# (The BUILDER_VERSION export was missing once — see ledger ruling.)
WF="../.github/workflows/upstream-check.yml"
assert_contains "E: workflow sets BUILDER_VERSION for the report" \
  "$(grep -o 'BUILDER_VERSION="\$(current BUILDER_VERSION)"' "$WF" | head -1)" \
  'BUILDER_VERSION="$(current BUILDER_VERSION)"'
assert_contains "E: open-PR step uses the action's body-path input" \
  "$(grep -o 'body-path: /tmp/pr-body.md' "$WF" | head -1)" \
  'body-path: /tmp/pr-body.md'

if [ "$FAILURES" -ne 0 ]; then
  echo "FAILURES" >&2
  exit 1
fi
echo "all ok"
