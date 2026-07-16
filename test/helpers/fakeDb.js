// Minimal in-memory Postgres stand-in that recognizes the exact queries the
// Worker issues (matched by SQL fragment) and mutates arrays accordingly.
let seq = 1
const uid = (p) => `${p}-${seq++}`

export function makeFakeDb() {
  const db = { users: [], sessions: [], tasks: [], events: [], identities: [] }

  async function query(sql, params = []) {
    const s = sql.replace(/\s+/g, ' ').trim()

    if (s.startsWith('insert into sessions')) {
      db.sessions.push({ token: params[0], user_id: params[1], expires_at: params[2] })
      return []
    }
    if (s.includes('from sessions s') && s.includes('join users u')) {
      const sess = db.sessions.find((x) => x.token === params[0])
      if (!sess) return []
      const u = db.users.find((x) => x.id === sess.user_id)
      return u ? [{ id: u.id, email: u.email, name: u.name }] : []
    }
    if (s.startsWith('delete from sessions')) {
      db.sessions = db.sessions.filter((x) => x.token !== params[0])
      return []
    }
    if (s.startsWith('insert into users') && s.includes('password_hash')) {
      if (db.users.some((u) => u.email === params[0])) {
        const e = new Error('duplicate'); e.code = '23505'; throw e
      }
      const u = { id: uid('user'), email: params[0], name: params[1], password_hash: params[2] }
      db.users.push(u)
      return [{ id: u.id }]
    }
    if (s.startsWith('insert into users') && s.includes('values ($1, $2) returning id')) {
      const u = { id: uid('user'), email: params[0], name: params[1], password_hash: null }
      db.users.push(u)
      return [{ id: u.id }]
    }
    if (s.startsWith('select id, password_hash from users')) {
      const u = db.users.find((x) => x.email === params[0])
      return u ? [{ id: u.id, password_hash: u.password_hash }] : []
    }
    if (s.startsWith('select id from users where email')) {
      const u = db.users.find((x) => x.email === params[0])
      return u ? [{ id: u.id }] : []
    }
    if (s.startsWith('update users set password_hash')) {
      const u = db.users.find((x) => x.id === params[1])
      if (u) u.password_hash = params[0]
      return []
    }
    if (s.startsWith('select user_id from identities')) {
      const i = db.identities.find((x) => x.provider === params[0] && x.provider_id === params[1])
      return i ? [{ user_id: i.user_id }] : []
    }
    if (s.startsWith('insert into identities')) {
      db.identities.push({ provider: params[0], provider_id: params[1], user_id: params[2] })
      return []
    }
    if (s.startsWith('insert into tasks')) {
      const t = {
        id: uid('task'), user_id: params[0], day: params[1], bucket: params[2],
        title: params[3], note: params[4], done: false,
        scheduled_start: null, scheduled_minutes: null, position: db.tasks.length,
      }
      db.tasks.push(t)
      return [t]
    }
    if (s.startsWith('select') && s.includes('from tasks') && s.includes('day = $2')) {
      return db.tasks.filter((t) => t.user_id === params[0] && t.day === params[1])
    }
    if (s.startsWith('select') && s.includes('from tasks') && s.includes('day < $2')) {
      return db.tasks.filter((t) => t.user_id === params[0] && t.day < params[1] && !t.done)
    }
    if (s.startsWith('update tasks set')) {
      return updateRow(db.tasks, s, params)
    }
    if (s.startsWith('delete from tasks')) {
      return deleteRow(db, 'tasks', params)
    }
    if (s.startsWith('insert into events')) {
      const e = {
        id: uid('event'), user_id: params[0], day: params[1], bucket: params[2],
        title: params[3], note: params[4], start_min: params[5], duration_min: params[6],
      }
      db.events.push(e)
      return [e]
    }
    if (s.startsWith('select') && s.includes('from events') && s.includes('day = $2')) {
      return db.events.filter((e) => e.user_id === params[0] && e.day === params[1])
    }
    if (s.startsWith('update events set')) {
      return updateRow(db.events, s, params)
    }
    if (s.startsWith('delete from events')) {
      return deleteRow(db, 'events', params)
    }
    throw new Error(`fakeDb: unhandled query: ${s}`)
  }

  // The neon() driver returns a tagged-template function that also has .query().
  const sql = () => { throw new Error('tagged template not used') }
  sql.query = query
  return { sql, db }
}

// `update <t> set a=$1, b=$2 where id=$N and user_id=$N+1 returning id`
function updateRow(rows, s, params) {
  const cols = [...s.matchAll(/(\w+) = \$(\d+)/g)]
    .map((m) => m[1]).filter((c) => c !== 'id' && c !== 'user_id')
  const id = params[params.length - 2]
  const userId = params[params.length - 1]
  const row = rows.find((r) => r.id === id && r.user_id === userId)
  if (!row) return []
  cols.forEach((c, i) => { row[c] = params[i] })
  return [{ id: row.id }]
}

function deleteRow(db, table, params) {
  const [id, userId] = params
  const before = db[table].length
  db[table] = db[table].filter((r) => !(r.id === id && r.user_id === userId))
  return db[table].length < before ? [{ id }] : []
}
