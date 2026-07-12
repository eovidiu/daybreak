const DAY_START_MIN = 6 * 60
const DAY_END_MIN = 22 * 60
const PX_PER_MIN = 1

const $ = (sel) => document.querySelector(sel)
const state = { user: null, day: localToday(), tasks: [], events: [], earlier: [] }

function localToday() {
  const d = new Date()
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
}
function pad(n) { return String(n).padStart(2, '0') }
function addDays(day, n) {
  const d = new Date(`${day}T12:00:00`)
  d.setDate(d.getDate() + n)
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
}
function fmtTime(min) {
  return `${pad(Math.floor(min / 60))}:${pad(min % 60)}`
}
function parseTime(hhmm) {
  const [h, m] = hhmm.split(':').map(Number)
  return h * 60 + m
}

async function api(path, options = {}) {
  const res = await fetch(path, {
    headers: options.body ? { 'content-type': 'application/json' } : {},
    ...options,
  })
  if (res.status === 401) {
    showAuth()
    throw new Error('unauthorized')
  }
  const data = await res.json().catch(() => ({}))
  if (!res.ok) throw new Error(data.error || 'request failed')
  return data
}

/* ---------- auth ---------- */
let signupMode = false

function showAuth() {
  $('#planner').classList.add('hidden')
  $('#auth').classList.remove('hidden')
}

function setAuthMode(signup) {
  signupMode = signup
  $('#authTitle').textContent = signup ? 'Create your account' : 'Welcome back'
  $('#authSubmit').textContent = signup ? 'Create account' : 'Sign in'
  $('#authToggle').textContent = signup
    ? 'Have an account? Sign in' : 'New here? Create an account'
  $('#authName').classList.toggle('hidden', !signup)
}

async function handleAuthSubmit(e) {
  e.preventDefault()
  $('#authError').classList.add('hidden')
  const body = {
    email: $('#authEmail').value,
    password: $('#authPassword').value,
    name: $('#authName').value,
  }
  const path = signupMode ? '/api/auth/signup' : '/api/auth/signin'
  try {
    await api(path, { method: 'POST', body: JSON.stringify(body) })
    await boot()
  } catch (err) {
    const el = $('#authError')
    el.textContent = err.message
    el.classList.remove('hidden')
  }
}

/* ---------- data ---------- */
async function loadDay() {
  const [dayData, earlier] = await Promise.all([
    api(`/api/day/${state.day}`),
    api(`/api/earlier?before=${localToday()}`),
  ])
  state.tasks = dayData.tasks
  state.events = dayData.events
  state.earlier = earlier.tasks
  render()
}

/* ---------- rendering ---------- */
function render() {
  renderTitle()
  renderWeekStrip()
  renderBuckets()
  renderEarlier()
  renderTimeline()
}

function renderTitle() {
  const d = new Date(`${state.day}T12:00:00`)
  const opts = { weekday: 'long', month: 'long', day: 'numeric' }
  const label = d.toLocaleDateString(undefined, opts)
  $('#dateTitle').textContent = state.day === localToday() ? `Today — ${label}` : label
}

function renderWeekStrip() {
  const strip = $('#weekStrip')
  strip.innerHTML = ''
  for (let i = -3; i <= 3; i++) {
    const day = addDays(state.day, i)
    const d = new Date(`${day}T12:00:00`)
    const chip = document.createElement('button')
    chip.className = 'dayChip'
    if (day === state.day) chip.classList.add('selected')
    if (day === localToday()) chip.classList.add('isToday')
    chip.innerHTML = `<small>${d.toLocaleDateString(undefined, { weekday: 'short' })}</small>
      <strong>${d.getDate()}</strong>`
    chip.onclick = () => { state.day = day; loadDay() }
    strip.appendChild(chip)
  }
}

function renderBuckets() {
  for (const bucket of ['urgent', 'progress', 'extra']) {
    const list = $(`#list-${bucket}`)
    list.innerHTML = ''
    state.tasks.filter((t) => t.bucket === bucket)
      .forEach((t) => list.appendChild(taskRow(t)))
  }
}

function taskRow(t) {
  const row = document.createElement('div')
  row.className = 'task' + (t.done ? ' done' : '')
  row.draggable = !t.done

  const box = document.createElement('input')
  box.type = 'checkbox'
  box.checked = t.done
  box.onchange = () => patchTask(t.id, { done: box.checked })

  const title = document.createElement('span')
  title.className = 'title'
  title.textContent = t.title
  title.onclick = () => openTaskEditor(t)

  row.append(box, title)
  if (t.note) {
    const dot = document.createElement('span')
    dot.className = 'noteDot'
    dot.textContent = '✎'
    row.appendChild(dot)
  }
  if (t.scheduled_start != null) {
    const chip = document.createElement('span')
    chip.className = 'chip'
    chip.textContent = fmtTime(t.scheduled_start)
    row.appendChild(chip)
  }
  row.ondragstart = (e) => e.dataTransfer.setData('text/task-id', t.id)
  return row
}

function renderEarlier() {
  const list = $('#earlierList')
  const count = $('#earlierCount')
  list.innerHTML = ''
  count.textContent = state.earlier.length ? `(${state.earlier.length})` : ''
  $('#earlierBox').classList.toggle('hidden', !state.earlier.length)
  for (const t of state.earlier) {
    const row = document.createElement('div')
    row.className = 'earlierItem'
    const when = document.createElement('span')
    when.className = 'when'
    when.textContent = t.day.slice(5)
    const title = document.createElement('span')
    title.className = 'title'
    title.textContent = t.title
    const pull = document.createElement('button')
    pull.textContent = 'Today'
    pull.onclick = () => patchTask(t.id, { day: localToday(), scheduled_start: null,
      scheduled_minutes: null })
    const drop = document.createElement('button')
    drop.textContent = '✕'
    drop.title = 'Delete forever'
    drop.onclick = () => api(`/api/tasks/${t.id}`, { method: 'DELETE' }).then(loadDay)
    row.append(when, title, pull, drop)
    list.appendChild(row)
  }
}

function renderTimeline() {
  const tl = $('#timeline')
  tl.innerHTML = ''
  tl.style.height = `${(DAY_END_MIN - DAY_START_MIN) * PX_PER_MIN}px`
  for (let min = DAY_START_MIN; min <= DAY_END_MIN; min += 60) {
    const row = document.createElement('div')
    row.className = 'hourRow'
    row.style.top = `${(min - DAY_START_MIN) * PX_PER_MIN}px`
    row.innerHTML = `<span>${fmtTime(min)}</span>`
    tl.appendChild(row)
  }
  for (const ev of state.events) tl.appendChild(slotItem(ev, false))
  for (const t of state.tasks.filter((t) => t.scheduled_start != null)) {
    tl.appendChild(slotItem(t, true))
  }
}

function slotItem(item, isTask) {
  const start = isTask ? item.scheduled_start : item.start_min
  const dur = isTask ? (item.scheduled_minutes ?? 60) : item.duration_min
  const el = document.createElement('div')
  el.className = `slotItem ${item.bucket}` + (isTask ? ' taskSlot' : '')
  el.style.top = `${Math.max(0, (start - DAY_START_MIN)) * PX_PER_MIN}px`
  el.style.height = `${Math.max(24, dur * PX_PER_MIN - 2)}px`
  if (isTask) {
    const box = document.createElement('input')
    box.type = 'checkbox'
    box.checked = item.done
    box.onclick = (e) => e.stopPropagation()
    box.onpointerdown = (e) => e.stopPropagation()
    box.onchange = () => patchTask(item.id, { done: box.checked })
    el.appendChild(box)
  }
  const label = document.createElement('div')
  label.innerHTML = `<div>${escapeHtml(item.title)}</div>
    <div class="slotTime">${fmtTime(start)} · ${dur}m</div>`
  el.appendChild(label)
  const resize = document.createElement('div')
  resize.className = 'slotResize'
  el.appendChild(resize)
  el.onclick = () => {
    if (el.dataset.dragged) return delete el.dataset.dragged
    isTask ? openTaskEditor(item) : openEventEditor(item)
  }
  wireSlotDrag(el, item, isTask, dur)
  wireSlotResize(resize, el, item, isTask)
  return el
}

async function patchSlot(item, isTask, patch) {
  const base = isTask ? '/api/tasks' : '/api/events'
  await api(`${base}/${item.id}`, { method: 'PATCH', body: JSON.stringify(patch) })
  await loadDay()
}

function wireSlotResize(handle, el, item, isTask) {
  handle.onpointerdown = (e) => {
    if (e.button !== 0) return
    e.stopPropagation()
    const startY = e.clientY
    const origH = el.offsetHeight
    const maxH = (DAY_END_MIN - DAY_START_MIN) * PX_PER_MIN - parseFloat(el.style.top)
    let moved = false
    handle.setPointerCapture(e.pointerId)

    handle.onpointermove = (ev) => {
      const dy = ev.clientY - startY
      if (!moved && Math.abs(dy) < 4) return
      moved = true
      el.classList.add('dragging')
      el.style.height = `${Math.min(Math.max(15 * PX_PER_MIN, origH + dy), maxH)}px`
    }

    handle.onpointerup = async () => {
      handle.onpointermove = null
      handle.onpointerup = null
      el.classList.remove('dragging')
      if (!moved) return
      el.dataset.dragged = '1'
      const raw = parseFloat(el.style.height) / PX_PER_MIN
      const minutes = Math.max(15, Math.round(raw / 15) * 15)
      const patch = isTask ? { scheduled_minutes: minutes } : { duration_min: minutes }
      await patchSlot(item, isTask, patch)
    }
  }
}

function wireSlotDrag(el, item, isTask, dur) {
  el.onpointerdown = (e) => {
    if (e.button !== 0) return
    const startY = e.clientY
    const origTop = parseFloat(el.style.top)
    const maxTop = (DAY_END_MIN - DAY_START_MIN - dur) * PX_PER_MIN
    let moved = false
    el.setPointerCapture(e.pointerId)

    el.onpointermove = (ev) => {
      const dy = ev.clientY - startY
      if (!moved && Math.abs(dy) < 6) return
      moved = true
      el.classList.add('dragging')
      el.style.top = `${Math.min(Math.max(0, origTop + dy), maxTop)}px`
    }

    el.onpointerup = async () => {
      el.onpointermove = null
      el.onpointerup = null
      el.classList.remove('dragging')
      if (!moved) return
      el.dataset.dragged = '1'
      const raw = DAY_START_MIN + parseFloat(el.style.top) / PX_PER_MIN
      const snapped = Math.round(raw / 15) * 15
      await patchSlot(item, isTask, isTask
        ? { scheduled_start: snapped } : { start_min: snapped })
    }
  }
}

function escapeHtml(s) {
  const div = document.createElement('div')
  div.textContent = s
  return div.innerHTML
}

/* ---------- mutations ---------- */
async function patchTask(id, patch) {
  await api(`/api/tasks/${id}`, { method: 'PATCH', body: JSON.stringify(patch) })
  await loadDay()
}

async function addTask(bucket, title) {
  await api('/api/tasks', {
    method: 'POST',
    body: JSON.stringify({ day: state.day, bucket, title }),
  })
  await loadDay()
}

/* ---------- editor dialog ---------- */
const editor = $('#editor')
let editorContext = null

function openEditor({ title, item, isTask, showTime }) {
  editorContext = { item, isTask }
  $('#editorTitle').textContent = title
  $('#editorName').value = item.title
  $('#editorNote').value = item.note || ''
  $('#editorBucket').value = item.bucket
  $('#editorTimeRow').classList.toggle('hidden', !showTime)
  if (showTime) {
    const start = isTask ? item.scheduled_start : item.start_min
    const dur = isTask ? item.scheduled_minutes : item.duration_min
    $('#editorStart').value = start != null ? fmtTime(start) : ''
    $('#editorDuration').value = dur ?? 60
  }
  editor.showModal()
}

const openTaskEditor = (t) => openEditor({
  title: 'Edit task', item: t, isTask: true, showTime: true,
})
const openEventEditor = (ev) => openEditor({
  title: 'Edit event', item: ev, isTask: false, showTime: true,
})

function editorPatch() {
  const { isTask } = editorContext
  const patch = {
    title: $('#editorName').value,
    note: $('#editorNote').value,
    bucket: $('#editorBucket').value,
  }
  const startStr = $('#editorStart').value
  const dur = Number($('#editorDuration').value) || 60
  if (isTask) {
    patch.scheduled_start = startStr ? parseTime(startStr) : null
    patch.scheduled_minutes = startStr ? dur : null
  } else if (startStr) {
    patch.start_min = parseTime(startStr)
    patch.duration_min = dur
  }
  return patch
}

async function handleEditorClose() {
  const { item, isTask } = editorContext || {}
  const action = editor.returnValue
  editorContext = null
  if (!item || action === 'cancel' || !action) return
  const base = isTask ? '/api/tasks' : '/api/events'
  if (action === 'delete') {
    await api(`${base}/${item.id}`, { method: 'DELETE' })
  } else {
    await api(`${base}/${item.id}`, { method: 'PATCH', body: JSON.stringify(editorPatch()) })
  }
  await loadDay()
}

/* ---------- new event ---------- */
async function createEvent() {
  const title = prompt('Event title?')
  if (!title || !title.trim()) return
  await api('/api/events', {
    method: 'POST',
    body: JSON.stringify({
      day: state.day, bucket: 'extra', title: title.trim(),
      start_min: 9 * 60, duration_min: 60,
    }),
  })
  await loadDay()
  const created = state.events.find((e) => e.title === title.trim())
  if (created) openEventEditor(created)
}

/* ---------- drag to schedule ---------- */
function wireTimelineDrop() {
  const tl = $('#timeline')
  tl.ondragover = (e) => {
    if (e.dataTransfer.types.includes('text/task-id')) {
      e.preventDefault()
      tl.classList.add('dropTarget')
    }
  }
  tl.ondragleave = () => tl.classList.remove('dropTarget')
  tl.ondrop = async (e) => {
    e.preventDefault()
    tl.classList.remove('dropTarget')
    const id = e.dataTransfer.getData('text/task-id')
    if (!id) return
    const y = e.clientY - tl.getBoundingClientRect().top
    const raw = DAY_START_MIN + y / PX_PER_MIN
    const snapped = Math.round(raw / 30) * 30
    await patchTask(id, { scheduled_start: snapped, scheduled_minutes: 60 })
  }
}

/* ---------- boot ---------- */
async function boot() {
  try {
    state.user = await api('/api/me')
  } catch {
    return
  }
  $('#auth').classList.add('hidden')
  $('#planner').classList.remove('hidden')
  await loadDay()
}

$('#authForm').onsubmit = handleAuthSubmit
$('#authToggle').onclick = () => setAuthMode(!signupMode)
$('#signOut').onclick = async () => {
  await api('/api/auth/signout', { method: 'POST' })
  showAuth()
}
$('#todayBtn').onclick = () => { state.day = localToday(); loadDay() }
$('#addEvent').onclick = createEvent
editor.addEventListener('close', handleEditorClose)
document.querySelectorAll('.addTask').forEach((form) => {
  form.onsubmit = (e) => {
    e.preventDefault()
    const input = form.querySelector('input')
    const title = input.value.trim()
    if (!title) return
    input.value = ''
    addTask(form.closest('.bucketCard').dataset.bucket, title)
  }
})
wireTimelineDrop()
setAuthMode(false)
boot()
