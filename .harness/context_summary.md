# Context Summary

Persistent record of architectural decisions, patterns, gotchas, and active context.
Referenced in CLAUDE.md; load at session start.

## Active Context
- Last completed: F001 — pinned iOS app to light (`.preferredColorScheme(.light)`) so
  fields are legible in Dark Mode. Passing, 98.03% coverage, 21 tests.
- Next up: no open features. Optionally build+install the fixed clean app on the XR.

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
- **SwiftData: three crash traps hit building F003's LocalStore** — (1) `#Predicate` with a
  captured variable (e.g. `#Predicate { $0.day == day }`) crashes at fetch on iOS 26.5;
  fetch-all-and-filter in Swift instead (local data is small). (2) Creating MANY
  `ModelContainer`s in one process crashes after the first 1-2; use ONE shared in-memory
  container across a test class and wipe it per test (`context.delete(model:)`). (3) A
  `ModelContext` traps (Core Data thread-confinement, EXC_BREAKPOINT) if captured at
  construction on one execution context and used later on another — the classic symptom
  was a bare `context.fetch()` crashing only in the app (via the protocol) but not in
  direct-call unit tests. Fix: make the store protocol `@MainActor` AND access
  `container.mainContext` LAZILY inside the `@MainActor` methods (don't stash it in init).
- **Local-first pivot (F003)**: iOS no longer uses the cloud API — the `PlannerApi` seam
  now has a SwiftData `LocalStore`; the cloud `ApiClient` and `AuthView` were DELETED
  (replaced, not deprecated). The app opens straight to the planner. `load()` must fetch
  the day and earlier tray SEQUENTIALLY (not `async let`) — one shared context.
- **iOS coverage-instrumented builds do not launch standalone** — never install a
  build made with coverage on as the shippable app (see [[swiftui-xcuitest-gotchas]])
- Cloudflare Workers cap PBKDF2 at 100k iterations; wrangler dev doesn't enforce it
- `URL.appending(path:)` percent-encodes `?` — breaks query strings on iOS
- On-device XCUITest needs the phone screen awake
- **Forcing Dark Mode in XCUITest**: the `-AppleInterfaceStyle Dark` launch argument
  does NOT force the app dark on the iOS 26.5 simulator (silent false-green). Force it
  at the simulator level: `xcrun simctl ui <sim> appearance dark`, then run the test on
  that booted sim by id. The dark-mode test requires this precondition.
- **The app hardcodes a light palette** (Theme sRGB colors don't adapt) and is now
  pinned via `.preferredColorScheme(.light)`. It intentionally has NO Dark Mode.
- **Xcode/OS updates wipe simulator runtimes** — `simctl list runtimes` can go empty
  overnight; re-run `xcodebuild -downloadPlatform iOS` (~8.5GB) before iOS tests. The
  available simulator after the 2026-07-17 update is iPhone 17 Pro / iOS 26.5.

## Meta-Session 2026-07-17
- Scope vs planned: F001 stayed within its 5-file scope; no expansions. Theme.swift was
  in scope but needed no edit (Theme.ink already existed) — a harmless scope superset.
- Discovered mid-work: the first test design was a false-green (launch-arg didn't force
  dark). The RED check — deliberately running with the pin disabled — is what caught it.
  Lesson: always execute the RED step; a test that passes before the fix is worthless.
- Environment: an overnight Xcode/OS update wiped the iOS simulator runtime, forcing an
  8.5GB re-download mid-feature. Not code-related; budget for it after system updates.
- Pattern that worked: pin appearance at the scene root (not per-view) so sheets inherit.

## Meta-Patterns
<!-- Cross-feature coordination insights. Populated by the retrospective step. -->
- The spec gate earns its cost on "simple" visual bugs: F001 looked trivial ("fix the
  color") but the gate's ASK surfaced the Form-background inverse trap and the
  recolor-vs-pin ambiguity before any code was written. Run it even for one-line fixes.
- For any test that depends on an environment mode (dark mode, locale, network state),
  prove it RED by disabling the fix before trusting a GREEN — env-dependent tests are
  the most common false-greens.
