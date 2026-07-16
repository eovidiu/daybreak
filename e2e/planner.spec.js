import { test, expect } from '@playwright/test'
import { readFileSync, writeFileSync } from 'node:fs'
import v8toIstanbul from 'v8-to-istanbul'

test.describe.configure({ mode: 'serial' })

const stamp = Date.now()
const EMAIL = `e2e-web-${stamp}@daybreak.test`
const PASSWORD = 'e2e-pass-123'
const PX_PER_MIN = 1.5

let page
let coverageEntries = []

test.beforeAll(async ({ browser }) => {
  page = await browser.newPage()
  await page.coverage.startJSCoverage({ resetOnNavigation: false })
})

test.afterAll(async () => {
  coverageEntries = await page.coverage.stopJSCoverage()
  // Each reload registers app.js as a fresh script; merge every entry so hit
  // counts accumulate across the whole run.
  const appEntries = coverageEntries.filter((e) => e.url.endsWith('/app/app.js'))
  let pct = 0
  if (appEntries.length) {
    const source = readFileSync('public/app/app.js', 'utf8')
    const merged = {}
    for (const entry of appEntries) {
      const converter = v8toIstanbul('public/app/app.js', 0, { source })
      await converter.load()
      converter.applyCoverage(entry.functions)
      const cov = Object.values(converter.toIstanbul())[0]
      for (const [k, n] of Object.entries(cov.s)) {
        merged[k] = (merged[k] ?? 0) + n
      }
    }
    const counts = Object.values(merged)
    const covered = counts.filter((n) => n > 0).length
    pct = (covered / counts.length) * 100
  }
  const report = `app.js e2e line coverage: ${pct.toFixed(1)}%\n`
  writeFileSync('e2e/coverage-report.txt', report)
  console.log(report)
  expect(pct, 'e2e coverage of app.js must be >= 95%').toBeGreaterThanOrEqual(95)
  await page.close()
})

async function signOutIfIn() {
  if (await page.locator('#signOut').isVisible()) {
    await page.click('#signOut')
    await expect(page.locator('#authForm')).toBeVisible()
  }
}

function today(offsetDays = 0) {
  const d = new Date()
  d.setDate(d.getDate() + offsetDays)
  const p = (n) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`
}

const scrollTop = () => page.locator('#timeline').evaluate((el) => el.scrollTop)

test('landing page serves', async () => {
  await page.goto('/')
  await expect(page.locator('h1')).toContainText('fresh page')
})

test('oauth error query shows a message when signed out', async () => {
  await page.goto('/app/?auth_error=cancelled')
  await expect(page.locator('#authError')).toContainText('cancelled')
})

test('signup flow creates an account and lands on today', async () => {
  await page.goto('/app/')
  await signOutIfIn()
  await page.click('#authToggle')            // to signup
  await page.click('#authToggle')            // back to signin (toggle branch)
  await page.click('#authToggle')            // to signup again
  await page.fill('#authName', 'E2E Web')
  await page.fill('#authEmail', EMAIL)
  await page.fill('#authPassword', PASSWORD)
  await page.click('#authSubmit')
  await expect(page.locator('#dateTitle')).toContainText('Today')
})

async function ensureAuthMode(signup) {
  await expect(page.locator('#authForm')).toBeVisible()
  const nameVisible = await page.locator('#authName').isVisible()
  if (nameVisible !== signup) await page.click('#authToggle')
}

test('duplicate signup shows an error', async () => {
  await page.click('#signOut')
  await ensureAuthMode(true)
  await page.fill('#authName', 'E2E Web')
  await page.fill('#authEmail', EMAIL)
  await page.fill('#authPassword', PASSWORD)
  await page.click('#authSubmit')
  await expect(page.locator('#authError')).toContainText('already exists')
})

test('wrong password shows an error, correct one signs in', async () => {
  await ensureAuthMode(false)
  await page.fill('#authEmail', EMAIL)
  await page.fill('#authPassword', 'wrong-password')
  await page.click('#authSubmit')
  await expect(page.locator('#authError')).toContainText('wrong email or password')
  await page.fill('#authPassword', PASSWORD)
  await page.click('#authSubmit')
  await expect(page.locator('#dateTitle')).toContainText('Today')
})

test('timeline opens on the 08:00 window when the day is empty', async () => {
  await expect.poll(scrollTop).toBe(8 * 60 * PX_PER_MIN)
})

test('tasks can be added to all three buckets', async () => {
  for (const [bucket, title] of [
    ['urgent', 'Pay supplier'], ['progress', 'Design sprint'], ['extra', 'Water plants'],
  ]) {
    await page.fill(`.bucketCard[data-bucket=${bucket}] .addTask input`, title)
    await page.click(`.bucketCard[data-bucket=${bucket}] .addTask button`)
    await expect(page.locator('.task .title', { hasText: title })).toBeVisible()
  }
  // Enter key submit + empty input ignored
  await page.fill('.bucketCard[data-bucket=extra] .addTask input', 'Via enter')
  await page.press('.bucketCard[data-bucket=extra] .addTask input', 'Enter')
  await expect(page.locator('.task .title', { hasText: 'Via enter' })).toBeVisible()
  await page.press('.bucketCard[data-bucket=extra] .addTask input', 'Enter')
})

test('task can be completed and uncompleted', async () => {
  const row = page.locator('.task', { hasText: 'Water plants' })
  await row.locator('input[type=checkbox]').check()
  await expect(row).toHaveClass(/done/)
  await row.locator('input[type=checkbox]').uncheck()
  await expect(row).not.toHaveClass(/done/)
})

test('task editor schedules a time block with a note', async () => {
  await page.click('.task .title >> text=Design sprint')
  await page.fill('#editorName', 'Design sprint v2')
  await page.fill('#editorStart', '09:00')
  await page.fill('#editorDuration', '90')
  await page.fill('#editorNote', 'deep work')
  await page.click('#editorSave')
  const slot = page.locator('.slotItem.taskSlot', { hasText: 'Design sprint v2' })
  await expect(slot).toBeVisible()
  await expect(slot).toContainText('09:00 · 90m')
  await expect(page.locator('.task', { hasText: 'Design sprint v2' })
    .locator('.noteDot')).toBeVisible()
})

test('editor cancel discards changes', async () => {
  await page.click('.task .title >> text=Design sprint v2')
  await page.fill('#editorName', 'Should not persist')
  await page.click('#editor button[value=cancel]')
  await expect(page.locator('.task', { hasText: 'Design sprint v2' })).toBeVisible()
})

test('scheduled task checkbox on the timeline toggles done', async () => {
  const slot = page.locator('.slotItem.taskSlot', { hasText: 'Design sprint v2' })
  await slot.locator('input[type=checkbox]').check()
  await expect(page.locator('.task', { hasText: 'Design sprint v2' })).toHaveClass(/done/)
  await slot.locator('input[type=checkbox]').uncheck()
})

test('event is created via the prompt and lands on the timeline', async () => {
  page.once('dialog', (d) => d.accept('Team sync'))
  await page.click('#addEvent')
  await page.fill('#editorStart', '10:00')
  await page.fill('#editorDuration', '60')
  await page.selectOption('#editorBucket', 'progress')
  await page.click('#editorSave')
  const slot = page.locator('.slotItem.progress', { hasText: 'Team sync' })
  await expect(slot).toBeVisible()
  await expect(slot).toContainText('10:00 · 60m')
})

test('cancelled event prompt creates nothing', async () => {
  page.once('dialog', (d) => d.dismiss())
  await page.click('#addEvent')
  await expect(page.locator('.slotItem', { hasText: 'Team sync' })).toHaveCount(1)
})

// Drives the real pointer handlers with deterministic coordinates — real-mouse
// drags are flaky against the timeline's scroll container.
async function dragBy(title, selector, dy) {
  await page.evaluate(({ title, selector, dy }) => {
    const slot = [...document.querySelectorAll('.slotItem')]
      .find((s) => s.textContent.includes(title))
    const target = selector ? slot.querySelector(selector) : slot
    const r = target.getBoundingClientRect()
    const x = r.x + r.width / 2
    const y0 = r.y + Math.min(6, r.height / 2)
    const opts = (y) => ({ pointerId: 1, button: 0, clientX: x, clientY: y, bubbles: true })
    target.dispatchEvent(new PointerEvent('pointerdown', opts(y0)))
    target.dispatchEvent(new PointerEvent('pointermove', opts(y0 + dy / 2)))
    target.dispatchEvent(new PointerEvent('pointermove', opts(y0 + dy)))
    target.dispatchEvent(new PointerEvent('pointerup', opts(y0 + dy)))
  }, { title, selector, dy })
}

test('slot drag moves the event in 15-minute steps', async () => {
  await dragBy('Team sync', null, 90)   // +90px / 1.5 = +60min → 11:00
  await expect(page.locator('.slotItem', { hasText: 'Team sync' }))
    .toContainText('11:00 · 60m')
})

test('resize handle grows the event duration', async () => {
  await dragBy('Team sync', '.slotResize', 45)   // +45px / 1.5 = +30min → 90m
  await expect(page.locator('.slotItem', { hasText: 'Team sync' }))
    .toContainText('11:00 · 90m')
})

test('drag-and-drop schedules a task onto the timeline', async () => {
  await page.evaluate(() => {
    const row = [...document.querySelectorAll('.task')]
      .find((r) => r.textContent.includes('Pay supplier'))
    const dt = new DataTransfer()
    row.dispatchEvent(new DragEvent('dragstart', { dataTransfer: dt, bubbles: true }))
    const tl = document.querySelector('#timeline')
    const canvas = document.querySelector('#timelineCanvas')
    const y = canvas.getBoundingClientRect().top + 13 * 60 * 1.5
    tl.dispatchEvent(new DragEvent('dragover', {
      dataTransfer: dt, bubbles: true, clientY: y,
    }))
    tl.dispatchEvent(new DragEvent('dragleave', { bubbles: true }))
    tl.dispatchEvent(new DragEvent('dragover', {
      dataTransfer: dt, bubbles: true, clientY: y,
    }))
    tl.dispatchEvent(new DragEvent('drop', {
      dataTransfer: dt, bubbles: true, clientY: y,
    }))
  })
  await expect(page.locator('.slotItem.taskSlot', { hasText: 'Pay supplier' }))
    .toContainText('13:00')
})

test('event editor can delete the event', async () => {
  await page.click('.slotItem >> text=Team sync')
  await page.click('#editor button[value=delete]')
  await expect(page.locator('.slotItem', { hasText: 'Team sync' })).toHaveCount(0)
})

test('earlier tray offers unfinished tasks from past days', async () => {
  const yesterday = today(-1)
  await page.click(`.dayChip:has-text("${Number(yesterday.slice(8))}")`)
  await page.fill('.bucketCard[data-bucket=urgent] .addTask input', 'Left behind')
  await page.click('.bucketCard[data-bucket=urgent] .addTask button')
  await page.fill('.bucketCard[data-bucket=extra] .addTask input', 'Abandon me')
  await page.click('.bucketCard[data-bucket=extra] .addTask button')
  await page.click('#todayBtn')
  await page.click('#earlierBox summary')
  const item = page.locator('.earlierItem', { hasText: 'Left behind' })
  await item.locator('button', { hasText: 'Today' }).click()
  await expect(page.locator('.task .title', { hasText: 'Left behind' })).toBeVisible()
  const drop = page.locator('.earlierItem', { hasText: 'Abandon me' })
  await drop.locator('button[title="Delete forever"]').click()
  await expect(page.locator('.earlierItem', { hasText: 'Abandon me' })).toHaveCount(0)
})

test('task can be deleted from the editor', async () => {
  await page.click('.task .title >> text=Via enter')
  await page.click('#editor button[value=delete]')
  await expect(page.locator('.task', { hasText: 'Via enter' })).toHaveCount(0)
})

test('a pre-8am event pulls the opening scroll down to it', async () => {
  page.once('dialog', (d) => d.accept('Early flight'))
  await page.click('#addEvent')
  await page.fill('#editorStart', '05:00')
  await page.fill('#editorDuration', '60')
  await page.click('#editorSave')
  // Wait for the move to persist before reloading, else the scroll races the PATCH.
  await expect(page.locator('.slotItem', { hasText: 'Early flight' }))
    .toContainText('05:00')
  await page.reload()
  await expect(page.locator('.slotItem', { hasText: 'Early flight' })).toBeVisible()
  await expect.poll(scrollTop).toBe(5 * 60 * PX_PER_MIN)
})

test('removing the early event restores the 08:00 window', async () => {
  await page.click('.slotItem >> text=Early flight')
  await page.click('#editor button[value=delete]')
  await expect(page.locator('.slotItem', { hasText: 'Early flight' })).toHaveCount(0)
  await page.reload()
  await expect(page.locator('#dateTitle')).toContainText('Today')
  await expect.poll(scrollTop).toBe(8 * 60 * PX_PER_MIN)
})

test('day navigation and today button work', async () => {
  const tomorrowNum = Number(today(1).slice(8))
  await page.click(`.dayChip:has-text("${tomorrowNum}")`)
  await expect(page.locator('#dateTitle')).not.toContainText('Today')
  await page.click('#todayBtn')
  await expect(page.locator('#dateTitle')).toContainText('Today')
})

test('sign out returns to the auth screen and protects the api', async () => {
  await page.click('#signOut')
  await expect(page.locator('#authForm')).toBeVisible()
  const status = await page.evaluate(() =>
    fetch('/api/me').then((r) => r.status))
  expect(status).toBe(401)
})
