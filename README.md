# Notetakr

Local-first macOS meeting notes. A native SwiftUI menu-bar app that records
system + microphone audio locally, prepares meeting notes, and transcribes
on-device through a replaceable adapter. No cloud services, no login, no
browser extension.

> **Status:** MVP in progress. See [`docs/plans/20260608-meeting-notes-mvp.md`](docs/plans/20260608-meeting-notes-mvp.md)
> for the build plan and [`docs/agent-progress.md`](docs/agent-progress.md) for
> what is implemented and verified.

## Architecture

- **`NotetakrCore`** — cross-platform (Linux + macOS), Foundation-only domain
  logic: models, storage, calendar matching, transcription/vocabulary logic.
  Fully covered by `swift test` on Linux.
- **`NotetakrAppKit`** — the SwiftUI views and app model (macOS-only; guarded
  behind `#if os(macOS)`).
- **`NotetakrApp`** — thin menu-bar executable entry point.

This split lets the fast inner loop run in a Linux container while the macOS
GitHub Actions runner is the source of truth for native compilation and
macOS-only tests.

## Development

```bash
# Fast inner loop — Linux-compatible build + tests (bootstraps Swift if needed)
bash scripts/local-validate.sh

# Push the branch and block on the macOS GitHub Actions run
bash scripts/ci-gate.sh
```

Requirements:

- Swift 6.1 (auto-installed by `local-validate.sh` on Ubuntu).
- For native work: macOS 14+, Xcode 15+.

## Current limitations

- Real microphone and system-audio capture can only be verified on a physical
  Mac — see [`docs/manual-smoke-test.md`](docs/manual-smoke-test.md) (added in a
  later task). CI verifies compilation only for native audio code.
