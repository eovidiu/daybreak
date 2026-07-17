# Context Summary

Persistent record of architectural decisions, patterns, gotchas, and active context.
Referenced in CLAUDE.md; load at session start.

## Active Context
- Currently working on: harness adoption on an existing, shipped app
- Next up: F001 — fix iOS field text color (white-on-white in Dark Mode)

## Cross-Cutting Concerns
- Dual-stack:
  - **Web** — Cloudflare Workers (Hono) + Neon Postgres (`@neondatabase/serverless`)
    + vanilla ES-module SPA in `public/`. Tests: vitest (unit + routes, 52) and
    Playwright E2E (23). Coverage gated at 95% (currently ~98%).
  - **iOS** — SwiftUI app in `ios/` (xcodegen project). Tests: 20 (15 unit + 5 UI)
    via xcodebuild on simulator/device, ~98% coverage.
- Deployed: web at https://daybreak.eovidiu.workers.dev ; iOS installed on iPhone XR.
- Design: "Warm Editorial" — cream ink-on-paper, Playfair Display (web, self-hosted)
  / New York (iOS), muted terracotta/sage/slate accents.

## Domain: Daily Planner

### Decisions
- Node stack chosen for the harness gate: the web vitest suite is the reliable
  headless test; iOS tests need Xcode+device so they run outside the gate (2026-07-17)
- Passwords: argon2id (WASM on web, verified) with legacy pbkdf2 migration
- Timeline: 24h canvas, opens on an 08:00–20:00 window, auto-scrolls to earliest item

### Patterns
- Web restyles must preserve every DOM class/ID the E2E suite selects on — change
  only palette/type/finish, never structure
- iOS Store's API is injectable behind `PlannerApi` so unit tests drive a mock

### Gotchas
- **iOS coverage-instrumented builds do not launch standalone** — never install a
  build made with coverage on as the shippable app (see [[swiftui-xcuitest-gotchas]])
- Cloudflare Workers cap PBKDF2 at 100k iterations; wrangler dev doesn't enforce it
- `URL.appending(path:)` percent-encodes `?` — breaks query strings on iOS
- On-device XCUITest needs the phone screen awake

## Meta-Patterns
<!-- Cross-feature coordination insights. Populated by the retrospective step. -->
- (none yet — first retrospective will populate this)
