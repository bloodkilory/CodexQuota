# Windows Beta Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox syntax for tracking.

**Goal:** Deliver an independent Windows 11 x64 beta and verified GitHub Actions test/build artifacts while preserving the existing Mac app.
**Architecture:** `windows/` owns Tauri shell, Rust adapters and a credential-free frontend. Share protocol semantics and synthetic fixtures with the Mac implementation; do not port AppKit or macOS installation code.
**Tech Stack:** Tauri 2, Rust, TypeScript, Vite, Node test runner, Windows NSIS, GitHub Actions.
**Spec:** `docs/superpowers/specs/2026-10-23-windows-beta-design.md` (approved chat scope).

## Global Constraints
- Windows 11 x64 beta; existing Mac Sources/Tests/build scripts/release behavior unchanged.
- CC Switch schema 18–20 read-only; only user-selected DeepSeek official connections; no key entry or token IPC.
- Refresh startup/manual/every 60 seconds; retain transient stale readings; invalidate changed-source readings.
- Update checks startup/manual only, formal GitHub releases only; no beta publication or main merge.

## Review Focus
- Native Windows executable paths with spaces and npm shims must not trigger shell injection or orphan app-server processes.
- Config deletion, schema mismatch, busy DB and changes during in-flight transfers must not show another account's balance.
- Malformed/unknown balances and non-main Codex quota buckets must not produce fabricated zero/unlimited values.
- UI language/source switching while queries run must keep visible reading/source/labels aligned.
- Installation/update errors must leave the installed app and startup preference usable.

### Task 1: Backend adapters and polling state
**Files:** `windows/src-tauri/{Cargo.toml,src/{lib.rs,models.rs,cc_switch.rs,deepseek.rs,codex.rs,updates.rs}}`, integration fixtures/tests.
**Interfaces:** `discover(directory) -> Vec<Connection>`, `resolve(directory,id) -> Credential` (backend only); `fetch` -> serializable `Reading` or typed safe error; `AppState` owns selection and generation.
- [ ] Write failing tests for strict endpoints/schema, decimal wallets, Codex primary selection and malformed/large frames, source generation changes, retry classification, release asset selection.
- [ ] Run Rust tests; confirm RED. Implement minimum adapters and run `cargo test --no-default-features`, `cargo fmt --check`, `cargo clippy --no-default-features -- -D warnings`; expected GREEN.
- [ ] Commit backend and tests.

### Task 2: Tauri shell and bilingual UI
**Files:** `windows/src-tauri/{tauri.conf.json,build.rs,capabilities/default.json,src/desktop.rs}`, `windows/{package.json,index.html,src/*,tests/*}`.
**Interfaces:** frontend invokes only `snapshot`, `discover`, `select_source`, `save_preferences`, `refresh`, `check_update`, `install_update`, `quit`; snapshots contain metadata/readings, never secrets.
- [ ] Write failing source-switch/language/stale display tests; run `npm test` to confirm RED.
- [ ] Implement tray show/hide/quit, backend timer/single-flight polling, persistent preferences, optional autostart and user-triggered verified installer update. Build credential-free glass UI with one source selector.
- [ ] Run frontend tests/typecheck/build and native `cargo check`; expected GREEN. Browser-check synthetic preview only; no private balance screenshots.
- [ ] Commit shell, UI and tests.

### Task 3: Windows automation and beta delivery
**Files:** `.github/workflows/windows-beta.yml`, `windows/scripts/*`, `windows/tests/e2e*`, `docs/windows/README.md`, `README{,.en}.md`.
**Interfaces:** workflow runs locked Rust/npm tests, Windows native build/GUI smoke, installer package/hash; uploads beta artifacts only.
- [ ] Add workflow and Windows smoke tests (launch demo/snapshot, UI source/language operations, installer silent install/uninstall in runner only).
- [ ] Run unchanged Mac suite, local backend/frontend checks; inspect fixture-only output and final diff.
- [ ] Commit, push isolated feature branch to trigger authorized Windows CI; inspect real Actions jobs/artifacts and fix failures until green. Do not merge main or publish a Release.
- [ ] Independent final branch review, fix critical/important findings with regression tests, update evidence and beta limitations. Deliver Windows artifacts and verification status.
