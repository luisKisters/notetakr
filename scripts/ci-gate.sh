#!/usr/bin/env bash
# Commit any dirty files, push the current branch, wait for the matching
# GitHub Actions run, print failed logs, and exit non-zero when CI fails.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

log() { echo "[ci-gate] $*"; }

BRANCH=$(git branch --show-current)
if [[ -z "$BRANCH" ]]; then
    log "ERROR: Cannot determine current branch (detached HEAD?)."
    exit 1
fi
log "Branch: $BRANCH"

# --- Commit dirty files if any ---
if ! git diff --quiet || ! git diff --staged --quiet || [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
    log "Uncommitted changes detected — staging and committing..."
    git add -A
    git commit -m "chore: ci-gate auto-commit [$(date -u +%Y-%m-%dT%H:%M:%SZ)]" \
        --no-verify 2>&1 || true
fi

# --- Push ---
log "Pushing $BRANCH to origin..."
git push --set-upstream origin "$BRANCH" --no-verify

# --- Find the most recent run for this branch (allow a few seconds for GH to register it) ---
log "Waiting for GitHub Actions run to appear..."
RUN_ID=""
for attempt in $(seq 1 20); do
    RUN_ID=$(gh run list \
        --branch "$BRANCH" \
        --workflow macos-ci.yml \
        --limit 1 \
        --json databaseId \
        --jq '.[0].databaseId // empty' 2>/dev/null || true)
    if [[ -n "$RUN_ID" ]]; then
        break
    fi
    log "  attempt $attempt/20: run not yet visible, waiting 10s..."
    sleep 10
done

if [[ -z "$RUN_ID" ]]; then
    log "ERROR: No GitHub Actions run found for branch '$BRANCH' after waiting."
    exit 1
fi
log "Found run ID: $RUN_ID"

# --- Wait for it to complete ---
log "Watching run $RUN_ID (this may take several minutes)..."
gh run watch "$RUN_ID" --interval 15 --exit-status || {
    log "CI run $RUN_ID FAILED. Fetching failed logs..."
    gh run view "$RUN_ID" --log-failed || true
    exit 1
}

log "CI run $RUN_ID passed."
