import { describe, it, expect } from 'vitest'
import { isDay, isBucket, taskPatch, eventInput, eventPatch } from '../src/lib/validate.js'

describe('isDay', () => {
  it('accepts ISO dates', () => {
    expect(isDay('2026-07-12')).toBe(true)
  })
  it('rejects non-dates and injection attempts', () => {
    expect(isDay('2026-7-12')).toBe(false)
    expect(isDay('tomorrow')).toBe(false)
    expect(isDay("2026-07-12'; drop table tasks;--")).toBe(false)
    expect(isDay(20260712)).toBe(false)
  })
  it('rejects impossible calendar dates', () => {
    expect(isDay('2026-02-30')).toBe(false)
    expect(isDay('2026-13-01')).toBe(false)
  })
})

describe('isBucket', () => {
  it('accepts the three buckets', () => {
    for (const b of ['urgent', 'progress', 'extra']) expect(isBucket(b)).toBe(true)
  })
  it('rejects anything else', () => {
    expect(isBucket('fires')).toBe(false)
    expect(isBucket('')).toBe(false)
  })
})

describe('taskPatch', () => {
  it('keeps only known, valid fields', () => {
    const p = taskPatch({
      title: '  Write report  ',
      bucket: 'urgent',
      done: true,
      evil: 'x',
      day: '2026-07-13',
    })
    expect(p).toEqual({ title: 'Write report', bucket: 'urgent', done: true, day: '2026-07-13' })
  })

  it('accepts clearing the schedule with nulls', () => {
    const p = taskPatch({ scheduled_start: null, scheduled_minutes: null })
    expect(p).toEqual({ scheduled_start: null, scheduled_minutes: null })
  })

  it('validates schedule ranges (minutes from midnight)', () => {
    expect(taskPatch({ scheduled_start: 540, scheduled_minutes: 60 }))
      .toEqual({ scheduled_start: 540, scheduled_minutes: 60 })
    expect(taskPatch({ scheduled_start: -10 })).toEqual({})
    expect(taskPatch({ scheduled_start: 1500 })).toEqual({})
    expect(taskPatch({ scheduled_minutes: 0 })).toEqual({})
  })

  it('rejects empty titles and oversized notes', () => {
    expect(taskPatch({ title: '   ' })).toEqual({})
    expect(taskPatch({ note: 'x'.repeat(5001) })).toEqual({})
  })
})

describe('eventInput', () => {
  it('normalizes a valid event', () => {
    expect(eventInput({
      day: '2026-07-12', bucket: 'extra', title: ' Standup ',
      start_min: 600, duration_min: 30,
    })).toEqual({
      day: '2026-07-12', bucket: 'extra', title: 'Standup',
      note: '', start_min: 600, duration_min: 30,
    })
  })
  it('returns null for invalid input', () => {
    expect(eventInput({ day: 'bad', bucket: 'extra', title: 'x', start_min: 0, duration_min: 30 })).toBeNull()
    expect(eventInput({ day: '2026-07-12', bucket: 'extra', title: '', start_min: 0, duration_min: 30 })).toBeNull()
    expect(eventInput({ day: '2026-07-12', bucket: 'extra', title: 'x', start_min: 900, duration_min: 900 })).toBeNull()
  })
})

describe('eventPatch', () => {
  it('keeps only known, valid fields', () => {
    expect(eventPatch({ title: ' Sync ', bucket: 'urgent', start_min: 60, duration_min: 30, evil: 1 }))
      .toEqual({ title: 'Sync', bucket: 'urgent', start_min: 60, duration_min: 30 })
  })
  it('drops invalid values instead of failing', () => {
    expect(eventPatch({ start_min: -5, duration_min: 0, bucket: 'nope' })).toEqual({})
  })
})
