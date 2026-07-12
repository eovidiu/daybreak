const DAY_RE = /^\d{4}-\d{2}-\d{2}$/
const BUCKETS = new Set(['urgent', 'progress', 'extra'])
const MAX_TITLE = 300
const MAX_NOTE = 5000
const DAY_MINUTES = 24 * 60

export function isDay(v) {
  if (typeof v !== 'string' || !DAY_RE.test(v)) return false
  const d = new Date(`${v}T00:00:00Z`)
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === v
}

export function isBucket(v) {
  return BUCKETS.has(v)
}

const isStart = (v) => Number.isInteger(v) && v >= 0 && v < DAY_MINUTES
const isDuration = (v) => Number.isInteger(v) && v > 0 && v <= 12 * 60

function cleanTitle(v) {
  if (typeof v !== 'string') return null
  const t = v.trim()
  return t && t.length <= MAX_TITLE ? t : null
}

function cleanNote(v) {
  return typeof v === 'string' && v.length <= MAX_NOTE ? v : null
}

export function taskPatch(body) {
  const p = {}
  const title = cleanTitle(body.title)
  if (title) p.title = title
  const note = cleanNote(body.note)
  if (note !== null && 'note' in body) p.note = note
  if (isBucket(body.bucket)) p.bucket = body.bucket
  if (typeof body.done === 'boolean') p.done = body.done
  if (isDay(body.day)) p.day = body.day
  if (body.scheduled_start === null || isStart(body.scheduled_start)) {
    if ('scheduled_start' in body) p.scheduled_start = body.scheduled_start
  }
  if (body.scheduled_minutes === null || isDuration(body.scheduled_minutes)) {
    if ('scheduled_minutes' in body) p.scheduled_minutes = body.scheduled_minutes
  }
  if (Number.isInteger(body.position)) p.position = body.position
  return p
}

export function eventPatch(body) {
  const p = {}
  const title = cleanTitle(body.title)
  if (title) p.title = title
  const note = cleanNote(body.note)
  if (note !== null && 'note' in body) p.note = note
  if (isBucket(body.bucket)) p.bucket = body.bucket
  if (isDay(body.day)) p.day = body.day
  if (isStart(body.start_min)) p.start_min = body.start_min
  if (isDuration(body.duration_min)) p.duration_min = body.duration_min
  return p
}

export function eventInput(body) {
  const title = cleanTitle(body.title)
  if (!title || !isDay(body.day) || !isBucket(body.bucket)) return null
  if (!isStart(body.start_min) || !isDuration(body.duration_min)) return null
  if (body.start_min + body.duration_min > DAY_MINUTES) return null
  const note = cleanNote(body.note ?? '')
  if (note === null) return null
  return {
    day: body.day, bucket: body.bucket, title,
    note, start_min: body.start_min, duration_min: body.duration_min,
  }
}
