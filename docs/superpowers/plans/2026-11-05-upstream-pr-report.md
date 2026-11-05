# Upstream-check PR report — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the static one-line PR body opened by the daily `upstream-check` workflow with a self-contained report (diff table, release links, full node digest, exact publish tags), and fix the branch-name/title to be a full fingerprint of all six pins (compose was missing, causing a branch collision on compose-only bumps).

**Architecture:** New sourceable bash file `scripts/upstream-report.sh` with three functions (title, branch, body) that read `CURRENT_*`/`LATEST_*` env vars the check step already computes. The workflow's existing check step sources it, writes the body to `/tmp/pr-body.md`, and `peter-evans/create-pull-request@v8` switches from `body:` to `body-path:`. No new actions, secrets, or Node.js in the check job.

**Tech Stack:** bash (set -eu, sourceable functions), jq/sed already present in ubuntu-latest, GitHub Actions YAML.

**Spec:** No spec file — small change, design approved in conversation on 2026-11-05 (option 3 "full report" from the rendered mockup; table + links + timestamp + full digest + on-merge tags; title/branch list only changed pins; branch includes compose).

## Global Constraints

- Bash only in the check step; no new GitHub Actions, no new Node.js, no secrets.
- Pinned actions stay pinned: `actions/checkout@v7`, `peter-evans/create-pull-request@v8` — its file-based body input is named `body-path` (verified against the pinned v8 README; `body-file` is silently ignored and the default body is used).
- Body file path: `/tmp/pr-body.md`.
- Branch name: no `:` allowed (digest must be 12-char short form).
- Row order in the table (fixed): `@openchamber/web`, `@opencode/cli`, `gh`, `node (24-bookworm-slim)`, `docker-ce-cli`, `docker-compose-plugin`.
- Title/branch component order (fixed): openchamber, opencode, gh, docker-cli, compose, node.
- Links (release-notes pages, static URLs):
  - `@openchamber/web` → `https://www.npmjs.com/package/@openchamber/web`
  - `@opencode/cli` → `https://www.npmjs.com/package/@opencode/cli`
  - `gh` → `https://github.com/cli/cli/releases`
  - node → `https://hub.docker.com/r/library/node/tags/24-bookworm-slim`
  - `docker-ce-cli` → `https://github.com/moby/moby/releases`
  - `docker-compose-plugin` → `https://github.com/docker/compose/releases`
- `docker-publish.yml` and the merge-to-publish flow are untouched.

## Review Focus

1. **Compose-only bump (the historical collision):** branch must still be unique when only `DOCKER_COMPOSE_VERSION` changes — pinned by fixture B (exact branch assert).
2. **Node digest in title/branch:** `sha256:` prefix must be stripped and truncated to 12 hex chars — pinned by exact branch/title asserts in fixtures A and B.
3. **Version strings with dots/hyphens flowing into title, branch, and a YAML `${{ }}` expression:** exact-match title assert in fixture A covers the joined format.
4. **`RUN_TIMESTAMP` unset (local invocation):** body must still render with a defaulted timestamp — pinned by fixture D.
5. **`CHANGED=false` path:** `PR_TITLE`/`PR_BRANCH` never set; the open-PR step must not run — enforced by the existing `if: env.UPSTREAM_CHANGED == 'true'`; verified on the next manual `workflow_dispatch` run (Task 3), not locally.

---

### Task 1: Report builder script + self-check

**Files:**
- Create: `scripts/upstream-report.sh`
- Create: `scripts/test-upstream-report.sh`

**Interfaces:**
- Produces (sourced functions, all read env, all pure):
  - `build_pr_title` → echoes `chore: bump upstream (<changed components only, fixed order>)`
  - `build_branch_name` → echoes `upstream-<oc>-<code>-gh<gh>-docker<dockercli>-compose<compose>-node<12hex>`
  - `build_pr_body` → emits markdown report to stdout
- Env consumed: `CURRENT_OC LATEST_OC CURRENT_CODE LATEST_CODE CURRENT_GH LATEST_GH CURRENT_NODE LATEST_NODE CURRENT_DOCKER_CLI LATEST_DOCKER_CLI CURRENT_DOCKER_COMPOSE LATEST_DOCKER_COMPOSE BUILDER_VERSION` (all required), `RUN_TIMESTAMP` (optional, defaults to `date -u '+%Y-%m-%d %H:%M UTC'`).
- Node values are full digests (`sha256:<64hex>`) everywhere in env; shortening happens only inside the script.

- [ ] **Step 1: Write the failing test**

Create `scripts/test-upstream-report.sh` (executable, `#!/usr/bin/env bash`, `set -eu`, `cd "$(dirname "$0")"`, sources `./upstream-report.sh`). Assert helpers: `assert_eq label expected actual` and `assert_contains label haystack needle`, each printing `ok:`/`FAIL:` and tracking a fail flag; exit 1 if any failed.

Fixtures and assertions:

- **Fixture A — 4 of 6 changed** (changed: oc 2.5.3→2.5.4, code 2.2.1→2.3.0, node `sha256:c86ecead9e55a5210ac1727de38a4ca840bf03dcaf34dc9749addbf383b1920c`→`sha256:b1a9f3d2e7c40568aa31b9e0247f6d5c8e9a1b2c3d4e5f60718293a4b5c6d7e8f`, compose 5.6.1→5.6.2; stable: gh 2.103.3, docker-cli 29.9.2; `BUILDER_VERSION=0.0.8`, `RUN_TIMESTAMP="2026-11-05 03:00 UTC"`):
  - title == `chore: bump upstream (openchamber 2.5.4, opencode 2.3.0, compose 5.6.2, node b1a9f3d2e7c4)`
  - branch == `upstream-2.5.4-2.3.0-gh2.103.3-docker29.9.2-compose5.6.2-nodeb1a9f3d2e7c4`
  - body contains each of:
    - `Ran 2026-11-05 03:00 UTC — 4 of 6 pins changed`
    - `| @openchamber/web | 2.5.3 | **2.5.4** | [npm](https://www.npmjs.com/package/@openchamber/web) |`
    - `| @opencode/cli | 2.2.1 | **2.3.0** | [npm](https://www.npmjs.com/package/@opencode/cli) |`
    - `| gh | 2.103.3 | 2.103.3 | — |`
    - ``| node (24-bookworm-slim) | `c86ecead9e55` | **`b1a9f3d2e7c4`** | [Docker Hub](https://hub.docker.com/r/library/node/tags/24-bookworm-slim) |``
    - `| docker-ce-cli | 29.9.2 | 29.9.2 | — |`
    - `| docker-compose-plugin | 5.6.1 | **5.6.2** | [GitHub](https://github.com/docker/compose/releases) |`
    - ``Node base digest: `sha256:b1a9f3d2e7c40568aa31b9e0247f6d5c8e9a1b2c3d4e5f60718293a4b5c6d7e8f` ``
    - ``**On merge:** docker-publish pushes `ghcr.io/amirghaghighi/openchamber` tags `latest`, `2.5.4`, `2.5.4-2.3.0`, `2.5.4-2.3.0-0.0.8` (cosign-signed). Close to skip.``

- **Fixture B — compose-only change** (only compose 5.6.1→5.6.2; everything else at fixture A's CURRENT values, LATEST == CURRENT):
  - title == `chore: bump upstream (compose 5.6.2)`
  - branch == `upstream-2.5.3-2.2.1-gh2.103.3-docker29.9.2-compose5.6.2-nodec86ecead9e55` (differs from a prior run's branch — the collision fix)
  - body contains `— 1 of 6 pins changed`

- **Fixture C — gh-only change** (only gh 2.103.3→2.104.0):
  - title == `chore: bump upstream (gh 2.104.0)`
  - body contains `— 1 of 6 pins changed` and `[GitHub](https://github.com/cli/cli/releases)`

- **Fixture D — no RUN_TIMESTAMP** (fixture A values, `unset RUN_TIMESTAMP`):
  - body matches regex `^Ran [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} UTC`

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/test-upstream-report.sh`
Expected: FAIL (sourcing `./upstream-report.sh` fails — file does not exist yet).

- [ ] **Step 3: Implement `scripts/upstream-report.sh`**

Sourceable, functions only, `set -u` safe. Structure:

- `short_digest() { printf '%s' "$1" | sed 's/^sha256://' | cut -c1-12'; }` — 12-char digest for title/branch/table cells.
- `build_pr_title`: build a parts array; append one entry per changed component in fixed order (openchamber, opencode, gh, docker-cli, compose, node); join with `", "` (loop join — do not rely on `IFS=`, which joins on the first character only); echo `chore: bump upstream (<joined>)`.
- `build_branch_name`: echo `upstream-${LATEST_OC}-${LATEST_CODE}-gh${LATEST_GH}-docker${LATEST_DOCKER_CLI}-compose${LATEST_DOCKER_COMPOSE}-node$(short_digest "$LATEST_NODE")`.
- `build_pr_body`: `RUN_TIMESTAMP="${RUN_TIMESTAMP:-$(date -u '+%Y-%m-%d %H:%M UTC')}"`; count changed pins (0–6); emit:
  1. `## Upstream check report`
  2. `Ran ${RUN_TIMESTAMP} — ${N} of 6 pins changed`
  3. The 6-row table in the fixed row order. Latest cell: value (short digest for node, backticked), wrapped in `**…**` when changed. Release-notes cell: link (from Global Constraints) when changed, `—` when stable.
  4. `Node base digest: \`${LATEST_NODE}\`` (full digest)
  5. `**On merge:** docker-publish pushes \`ghcr.io/amirghaghighi/openchamber\` tags \`latest\`, \`${LATEST_OC}\`, \`${LATEST_OC}-${LATEST_CODE}\`, \`${LATEST_OC}-${LATEST_CODE}-${BUILDER_VERSION}\` (cosign-signed). Close to skip.`

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/test-upstream-report.sh`
Expected: all `ok:` lines, exit 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/upstream-report.sh scripts/test-upstream-report.sh
git commit -m "feat: upstream bump PR report builder with self-check"
```

---

### Task 2: Wire the report into upstream-check.yml

**Files:**
- Modify: `.github/workflows/upstream-check.yml:105-126`

**Interfaces:**
- Consumes: `build_pr_title`, `build_branch_name`, `build_pr_body` from Task 1 (sourced in-shell; all `CURRENT_*`/`LATEST_*` vars already exist in the check step's shell).
- Produces: GITHUB_ENV `PR_TITLE`, `PR_BRANCH`; body file `/tmp/pr-body.md`; open-PR step inputs.

- [ ] **Step 1: Extend the check step**

In `.github/workflows/upstream-check.yml`, in the "Check upstream releases" step:

- After the existing `CURRENT_DOCKER_COMPOSE="$(current DOCKER_COMPOSE_VERSION)"` line, add:

```bash
          CURRENT_BUILDER="$(current BUILDER_VERSION)"
```

- Replace the block that writes `LATEST_OC`/`LATEST_CODE`/`LATEST_GH`/`LATEST_NODE_SHORT`/`LATEST_DOCKER_CLI` to `GITHUB_ENV` (lines 105–111, keeping the `UPSTREAM_CHANGED` write) with:

```bash
          # PR report: title/branch list changed pins only; branch is a full
          # fingerprint of all six pins (compose included) so compose-only
          # bumps never collide with a still-open PR branch.
          . ./scripts/upstream-report.sh
          RUN_TIMESTAMP="$(date -u '+%Y-%m-%d %H:%M UTC')"
          PR_TITLE=""
          PR_BRANCH=""
          if [ "$CHANGED" = true ]; then
            PR_TITLE="$(build_pr_title)"
            PR_BRANCH="$(build_branch_name)"
            build_pr_body > /tmp/pr-body.md
          fi
          echo "PR_TITLE=${PR_TITLE}" >> "$GITHUB_ENV"
          echo "PR_BRANCH=${PR_BRANCH}" >> "$GITHUB_ENV"
          echo "UPSTREAM_CHANGED=${CHANGED}" >> "$GITHUB_ENV"
```

The `NODE_SHORT` line and the `# Branch names cannot contain ':'` comment move into the script's `short_digest` (already there in Task 1) — delete from the workflow.

- [ ] **Step 2: Point the open-PR step at the report**

Replace the `with:` block of "Open upstream bump PR":

```yaml
        with:
          branch: ${{ env.PR_BRANCH }}
          title: ${{ env.PR_TITLE }}
          body-path: /tmp/pr-body.md
          commit-message: ${{ env.PR_TITLE }}
```

- [ ] **Step 3: Verify locally as far as possible**

Run:
```bash
npx -y yaml@2 .github/workflows/upstream-check.yml && echo "yaml ok"   # exits non-zero on parse error; npx exists locally
grep -n 'LATEST_NODE_SHORT\|LATEST_OC=\|LATEST_CODE=\|LATEST_GH=\|LATEST_DOCKER_CLI=' .github/workflows/upstream-check.yml   # expect no matches
bash scripts/test-upstream-report.sh
```
Expected: `yaml ok`, no grep matches, all `ok:` from the test script. (If `npx` cannot fetch, read the file manually — the change is two localized blocks.)

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/upstream-check.yml
git commit -m "feat: upstream-check PR gets report body, changed-only title, compose in branch"
```

---

### Task 3: End-to-end verification on GitHub (manual dispatch)

**Files:** none.

**Interfaces:** consumes the merged branch from Tasks 1–2.

- [ ] **Step 1: Push and trigger**

Push the branch/PR, get it merged to `main` (or push the workflow change directly if the user's flow allows), then trigger the check manually:

```bash
gh workflow run upstream-check.yml
```

- [ ] **Step 2: Inspect the opened PR**

```bash
gh run watch "$(gh run list --workflow=upstream-check.yml --limit 1 --json databaseId -q '.[0].databaseId')"
gh pr list --head "$(gh run view <id> --json headBranch -q .headBranch)" --json title,body,headRefName
```

Expected: PR title lists only changed pins; branch matches `upstream-…-compose…-node…`; body renders the report (table, links, digest, on-merge tags). If no upstream changed, expect: job succeeds, no PR, `UPSTREAM_CHANGED=false` in logs — that is the correct no-op path.

- [ ] **Step 3: Close the loop**

Report the observed PR (title + body) back to the user. If the user merges it, watch `docker-publish` once via `gh run list --workflow=docker-publish.yml` to confirm the publish flow is unaffected.
