#!/usr/bin/env bash
#
# ci-gate.sh — push the current branch and block on the macOS GitHub Actions run.
#
# Behaviour:
#   1. Commit any dirty files (so CI sees the exact local tree).
#   2. Push the current branch to origin.
#   3. Find the GitHub Actions run for the just-pushed commit.
#   4. Wait for it to finish, streaming status.
#   5. On failure, print the failed job logs and exit non-zero.
#
# Requires: gh (authenticated), git.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

WORKFLOW_FILE="macos-ci.yml"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
err() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; }

command -v gh >/dev/null 2>&1 || { err "gh CLI is required"; exit 2; }
gh auth status >/dev/null 2>&1 || { err "gh is not authenticated"; exit 2; }

BRANCH="$(git rev-parse --abbrev-ref HEAD)"

# 1. Commit dirty files.
if ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git status --porcelain)" ]; then
    log "Committing dirty working tree"
    git add -A
    git commit -m "ci: snapshot for CI gate on ${BRANCH}" --no-verify
else
    log "Working tree clean — nothing to commit"
fi

# 2. Push.
log "Pushing ${BRANCH} to origin"
git push -u origin "$BRANCH"

COMMIT_SHA="$(git rev-parse HEAD)"
log "Waiting for GitHub Actions run for commit ${COMMIT_SHA:0:8}"

# 3. Locate the run for this commit (poll briefly until it is registered).
RUN_ID=""
for _ in $(seq 1 30); do
    RUN_ID="$(gh run list \
        --workflow "$WORKFLOW_FILE" \
        --branch "$BRANCH" \
        --commit "$COMMIT_SHA" \
        --limit 1 \
        --json databaseId \
        --jq '.[0].databaseId' 2>/dev/null || true)"
    [ -n "$RUN_ID" ] && [ "$RUN_ID" != "null" ] && break
    sleep 5
done

if [ -z "$RUN_ID" ] || [ "$RUN_ID" = "null" ]; then
    err "No ${WORKFLOW_FILE} run found for commit ${COMMIT_SHA}. Is the workflow present on this branch?"
    exit 1
fi

log "Found run ${RUN_ID} — watching until completion"

# 4. Block until the run completes (gh exits non-zero if the run failed).
if gh run watch "$RUN_ID" --exit-status; then
    log "ci-gate.sh: macOS CI passed ✅"
    exit 0
fi

# 5. Failure path — dump failed logs for investigation.
err "macOS CI failed for run ${RUN_ID}. Failed job logs follow:"
gh run view "$RUN_ID" --log-failed || gh run view "$RUN_ID" --log || true
exit 1
