import { Hono } from 'hono'
import { getCookie, setCookie, deleteCookie } from 'hono/cookie'
import { neon } from '@neondatabase/serverless'
import Argon2 from '@phi-ag/argon2'
import argon2Wasm from '@phi-ag/argon2/argon2.wasm'
import { newSessionToken } from './lib/auth.js'
import { createPasswords } from './lib/password.js'
import { enabledProviders, authorizeUrl, fetchIdentity } from './lib/oauth.js'
import { isDay, isBucket, taskPatch, eventInput, eventPatch } from './lib/validate.js'

const passwords = createPasswords(new Argon2(await WebAssembly.instantiate(argon2Wasm)))

const COOKIE = 'daybreak_session'
const SESSION_DAYS = 30
const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/

const app = new Hono()

const db = (c) => neon(c.env.DATABASE_URL)

async function startSession(c, sql, userId) {
  const token = newSessionToken()
  const expires = new Date(Date.now() + SESSION_DAYS * 86400000)
  await sql.query(
    'insert into sessions (token, user_id, expires_at) values ($1, $2, $3)',
    [token, userId, expires.toISOString()],
  )
  setCookie(c, COOKIE, token, {
    httpOnly: true, secure: true, sameSite: 'Lax', path: '/', expires,
  })
}

app.use('/api/*', async (c, next) => {
  c.set('sql', db(c))
  await next()
})

const PUBLIC = new Set(['/api/auth/signup', '/api/auth/signin'])

app.use('/api/*', async (c, next) => {
  if (PUBLIC.has(c.req.path) || c.req.path.startsWith('/api/auth/oauth/')) return next()
  const token = getCookie(c, COOKIE)
  if (!token) return c.json({ error: 'unauthorized' }, 401)
  const rows = await c.get('sql').query(
    `select u.id, u.email, u.name from sessions s
     join users u on u.id = s.user_id
     where s.token = $1 and s.expires_at > now()`,
    [token],
  )
  if (!rows.length) return c.json({ error: 'unauthorized' }, 401)
  c.set('user', rows[0])
  await next()
})

app.post('/api/auth/signup', async (c) => {
  const body = await c.req.json().catch(() => ({}))
  const email = String(body.email ?? '').trim().toLowerCase()
  const name = String(body.name ?? '').trim().slice(0, 100)
  const password = String(body.password ?? '')
  if (!EMAIL_RE.test(email)) return c.json({ error: 'valid email required' }, 400)
  if (password.length < 8) return c.json({ error: 'password must be 8+ characters' }, 400)
  const sql = c.get('sql')
  const hash = await passwords.hashPassword(password)
  let rows
  try {
    rows = await sql.query(
      'insert into users (email, name, password_hash) values ($1, $2, $3) returning id',
      [email, name, hash],
    )
  } catch (e) {
    if (String(e?.code) === '23505') return c.json({ error: 'account already exists' }, 409)
    throw e
  }
  await startSession(c, sql, rows[0].id)
  return c.json({ ok: true })
})

app.post('/api/auth/signin', async (c) => {
  const body = await c.req.json().catch(() => ({}))
  const email = String(body.email ?? '').trim().toLowerCase()
  const password = String(body.password ?? '')
  const sql = c.get('sql')
  const rows = await sql.query(
    'select id, password_hash from users where email = $1', [email],
  )
  const ok = rows.length && await passwords.verifyPassword(password, rows[0].password_hash)
  if (!ok) return c.json({ error: 'wrong email or password' }, 401)
  if (passwords.needsRehash(rows[0].password_hash)) {
    const fresh = await passwords.hashPassword(password)
    await sql.query('update users set password_hash = $1 where id = $2', [fresh, rows[0].id])
  }
  await startSession(c, sql, rows[0].id)
  return c.json({ ok: true })
})

app.post('/api/auth/signout', async (c) => {
  const token = getCookie(c, COOKIE)
  await c.get('sql').query('delete from sessions where token = $1', [token])
  deleteCookie(c, COOKIE, { path: '/' })
  return c.json({ ok: true })
})

app.get('/api/me', (c) => c.json(c.get('user')))

/* ---------- OAuth sign-in ---------- */
const OAUTH_COOKIE = 'daybreak_oauth'

const callbackUri = (c, provider) =>
  `${new URL(c.req.url).origin}/api/auth/oauth/${provider}/callback`

app.get('/api/auth/oauth/providers', (c) => c.json({ providers: enabledProviders(c.env) }))

app.get('/api/auth/oauth/:provider/start', (c) => {
  const provider = c.req.param('provider')
  if (!enabledProviders(c.env).includes(provider)) {
    return c.json({ error: 'provider not configured' }, 404)
  }
  const state = newSessionToken()
  setCookie(c, OAUTH_COOKIE, state, {
    httpOnly: true, secure: true, sameSite: 'None', path: '/api/auth/oauth', maxAge: 600,
  })
  return c.redirect(authorizeUrl(provider, c.env, callbackUri(c, provider), state))
})

async function oauthUserId(sql, provider, identity) {
  const linked = await sql.query(
    'select user_id from identities where provider = $1 and provider_id = $2',
    [provider, identity.providerId],
  )
  if (linked.length) return linked[0].user_id
  const email = identity.email?.trim().toLowerCase()
  if (!email) return null
  let userId
  const existing = await sql.query('select id from users where email = $1', [email])
  if (existing.length) {
    userId = existing[0].id
  } else {
    const rows = await sql.query(
      'insert into users (email, name) values ($1, $2) returning id',
      [email, (identity.name ?? '').slice(0, 100)],
    )
    userId = rows[0].id
  }
  await sql.query(
    'insert into identities (provider, provider_id, user_id) values ($1, $2, $3)',
    [provider, identity.providerId, userId],
  )
  return userId
}

async function oauthCallback(c) {
  const provider = c.req.param('provider')
  if (!enabledProviders(c.env).includes(provider)) {
    return c.json({ error: 'provider not configured' }, 404)
  }
  const params = c.req.method === 'POST'
    ? Object.fromEntries((await c.req.formData()).entries())
    : Object.fromEntries(new URL(c.req.url).searchParams.entries())
  const expected = getCookie(c, OAUTH_COOKIE)
  deleteCookie(c, OAUTH_COOKIE, { path: '/api/auth/oauth' })
  if (params.error || !params.code) return c.redirect('/app/?auth_error=cancelled')
  if (!expected || params.state !== expected) return c.redirect('/app/?auth_error=state')

  const identity = await fetchIdentity(provider, c.env, callbackUri(c, provider), params.code)
  if (provider === 'apple' && params.user) {
    const name = JSON.parse(params.user)?.name
    if (name) identity.name = [name.firstName, name.lastName].filter(Boolean).join(' ')
  }
  const sql = c.get('sql')
  const userId = await oauthUserId(sql, provider, identity)
  if (!userId) return c.redirect('/app/?auth_error=email')
  await startSession(c, sql, userId)
  return c.redirect('/app/')
}

app.get('/api/auth/oauth/:provider/callback', oauthCallback)
app.post('/api/auth/oauth/:provider/callback', oauthCallback)

app.get('/api/day/:day', async (c) => {
  const day = c.req.param('day')
  if (!isDay(day)) return c.json({ error: 'bad day' }, 400)
  const sql = c.get('sql')
  const uid = c.get('user').id
  const [tasks, events] = await Promise.all([
    sql.query(
      `select id, to_char(day, 'YYYY-MM-DD') as day, bucket, title, note, done,
              scheduled_start, scheduled_minutes, position
       from tasks where user_id = $1 and day = $2 order by position, created_at`,
      [uid, day],
    ),
    sql.query(
      `select id, to_char(day, 'YYYY-MM-DD') as day, bucket, title, note,
              start_min, duration_min
       from events where user_id = $1 and day = $2 order by start_min`,
      [uid, day],
    ),
  ])
  return c.json({ tasks, events })
})

app.get('/api/earlier', async (c) => {
  const before = c.req.query('before')
  if (!isDay(before)) return c.json({ error: 'bad date' }, 400)
  const rows = await c.get('sql').query(
    `select id, to_char(day, 'YYYY-MM-DD') as day, bucket, title, note
     from tasks where user_id = $1 and day < $2 and done = false
     order by day desc, position limit 200`,
    [c.get('user').id, before],
  )
  return c.json({ tasks: rows })
})

app.post('/api/tasks', async (c) => {
  const body = await c.req.json().catch(() => ({}))
  const title = String(body.title ?? '').trim()
  if (!title || !isDay(body.day) || !isBucket(body.bucket)) {
    return c.json({ error: 'day, bucket and title required' }, 400)
  }
  const rows = await c.get('sql').query(
    `insert into tasks (user_id, day, bucket, title, note, position)
     values ($1, $2, $3, $4, $5,
       coalesce((select max(position) + 1 from tasks where user_id = $1 and day = $2), 0))
     returning id, to_char(day, 'YYYY-MM-DD') as day, bucket, title, note, done,
               scheduled_start, scheduled_minutes, position`,
    [c.get('user').id, body.day, body.bucket, title.slice(0, 300),
     String(body.note ?? '').slice(0, 5000)],
  )
  return c.json(rows[0])
})

function buildUpdate(table, patch, id, userId) {
  const keys = Object.keys(patch)
  const sets = keys.map((k, i) => `${k} = $${i + 1}`).join(', ')
  return {
    text: `update ${table} set ${sets}
           where id = $${keys.length + 1} and user_id = $${keys.length + 2}
           returning id`,
    params: [...Object.values(patch), id, userId],
  }
}

async function applyPatch(c, table, patch) {
  if (!Object.keys(patch).length) return c.json({ error: 'nothing to update' }, 400)
  const { text, params } = buildUpdate(table, patch, c.req.param('id'), c.get('user').id)
  const rows = await c.get('sql').query(text, params)
  if (!rows.length) return c.json({ error: 'not found' }, 404)
  return c.json({ ok: true })
}

async function deleteRow(c, table) {
  const rows = await c.get('sql').query(
    `delete from ${table} where id = $1 and user_id = $2 returning id`,
    [c.req.param('id'), c.get('user').id],
  )
  if (!rows.length) return c.json({ error: 'not found' }, 404)
  return c.json({ ok: true })
}

app.patch('/api/tasks/:id', async (c) => {
  const patch = taskPatch(await c.req.json().catch(() => ({})))
  return applyPatch(c, 'tasks', patch)
})

app.delete('/api/tasks/:id', (c) => deleteRow(c, 'tasks'))

app.post('/api/events', async (c) => {
  const input = eventInput(await c.req.json().catch(() => ({})))
  if (!input) return c.json({ error: 'invalid event' }, 400)
  const rows = await c.get('sql').query(
    `insert into events (user_id, day, bucket, title, note, start_min, duration_min)
     values ($1, $2, $3, $4, $5, $6, $7)
     returning id, to_char(day, 'YYYY-MM-DD') as day, bucket, title, note,
               start_min, duration_min`,
    [c.get('user').id, input.day, input.bucket, input.title, input.note,
     input.start_min, input.duration_min],
  )
  return c.json(rows[0])
})

app.patch('/api/events/:id', async (c) => {
  const patch = eventPatch(await c.req.json().catch(() => ({})))
  return applyPatch(c, 'events', patch)
})

app.delete('/api/events/:id', (c) => deleteRow(c, 'events'))

app.onError((err, c) => {
  console.log('api error', err?.message)
  return c.json({ error: 'server error' }, 500)
})

export default app
