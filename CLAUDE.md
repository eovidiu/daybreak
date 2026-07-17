# Daybreak

A guilt-free daily planner: a fresh page every morning, no overdue pile, no streaks.
Sort today into three buckets (Urgent / Progress / Extras), block time on a timeline,
close the app.

## Tech Stack

- **Web** — Cloudflare Workers (Hono) serving a vanilla ES-module SPA from `public/`,
  with Neon Postgres via `@neondatabase/serverless`. Tests: vitest (unit + routes) and
  Playwright E2E. Deployed at https://daybreak.eovidiu.workers.dev.
- **iOS** — SwiftUI app in `ios/` (xcodegen project). Tests: XCUITest + unit via
  xcodebuild on simulator/device.
- Password hashing: argon2id (WASM) with legacy pbkdf2 migration.
- OAuth sign-in scaffolding for Google / Facebook / Apple (activates per configured secret).

## Harness

This project uses the Long-Running Agent Harness (vv-harness plugin).

- Feature tracking: `.harness/features.json`
- Context and decisions: `.harness/context_summary.md` (READ THIS at session start)
- Progress handoff: `.harness/claude-progress.txt`
- Build/test gate: `.harness/init.sh` (runs the web vitest suite; iOS tests run
  separately via Xcode and are not part of the automated gate)
- Quality gates: `.claude/hooks/` (TaskCompleted, TeammateIdle, scope, git identity)

## Git Identity

This project uses: Ovidiu Eftimie <eovidiu@gmail.com>.
Remote is HTTPS (github.com/eovidiu/daybreak) authenticated via the gh token; the
`~/.ssh/id_ed25519` key is present but its agent identity was evicted in a prior session.
Always verify identity before push/pull/clone.

## Conventions

- Web restyles must preserve every DOM class/ID the Playwright E2E suite selects on —
  change only palette, type, and finish, never structure.
- Coverage bar is 95% on touched code (web ~98%, iOS ~98%).
- Never install a coverage-instrumented iOS build as the shippable app — it won't launch
  standalone. Build the app with coverage off; measure coverage only during `test`.
