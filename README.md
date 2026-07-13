# Daybreak 🌅

A guilt-free daily planner. Every day starts on a fresh page: no overdue pile,
no streaks, no red badges. Sort today into three buckets, block time for what
matters, close the app.

## How it works

- **Three buckets per day** — *Urgent* (things with teeth), *Progress* (the long
  game), *Extras* (if there's room).
- **A fresh page every morning** — unfinished tasks from past days wait quietly
  in an *Earlier* tray. Pull one into today, or let it rest.
- **Time blocking** — drag a task onto the day's timeline to give it a real
  slot. Hold and slide slots to move them; drag the bottom edge to resize.
  Everything snaps to 15 minutes.
- **Private notes** on tasks and events.

## Stack

| Layer    | Choice                                                        |
|----------|---------------------------------------------------------------|
| Hosting  | Cloudflare Workers (static assets + API in one Worker)        |
| API      | [Hono](https://hono.dev)                                      |
| Database | PostgreSQL over [`@neondatabase/serverless`](https://github.com/neondatabase/serverless) |
| Frontend | Vanilla ES modules, no build step                             |
| Auth     | argon2id (WASM) password hashing, HttpOnly session cookies    |
| Tests    | Vitest                                                        |

## Quick start

Prerequisites: Node 20+, a PostgreSQL database reachable over HTTP via the Neon
serverless driver (a free [Neon](https://neon.tech) project works out of the box),
and a [Cloudflare](https://dash.cloudflare.com) account for deployment.

```sh
git clone git@github.com:eovidiu/daybreak.git
cd daybreak
npm install

# 1. Apply the schema to your database
psql "$YOUR_DATABASE_URL" -f schema.sql

# 2. Point the app at your database (gitignored file)
echo 'DATABASE_URL="<your postgres connection string>"' > .dev.vars

# 3. Run locally
npm run dev          # http://localhost:8787

# 4. Run the tests
npm test
```

Open http://localhost:8787, create an account, and plan your day.

## Deploy

```sh
npx wrangler login                          # once
npx wrangler secret put DATABASE_URL       # paste your connection string
npm run deploy                              # → https://daybreak.<your-subdomain>.workers.dev
```

The Worker serves the static frontend from `public/` and handles `/api/*`
routes itself (`run_worker_first` in `wrangler.jsonc`).

## Project layout

```
src/index.js          API routes (Hono)
src/lib/password.js   argon2id hashing + legacy verification
src/lib/auth.js       session tokens
src/lib/validate.js   input validation for tasks/events
public/               landing page + planner SPA
schema.sql            database schema
test/                 vitest suites
```

## Notes

- Passwords are hashed with argon2id (OWASP parameters) compiled to WASM —
  Cloudflare Workers disallow runtime WASM compilation, so the module is
  bundled at deploy time by wrangler.
- All task/event queries are scoped by the session's user id; input validation
  whitelists fields before any SQL is built.
