import { describe, it, expect } from 'vitest'
import { newSessionToken } from '../src/lib/auth.js'

describe('session tokens', () => {
  it('generates url-safe tokens of sufficient entropy', () => {
    const t = newSessionToken()
    expect(t).toMatch(/^[A-Za-z0-9_-]{40,}$/)
  })

  it('never repeats', () => {
    const seen = new Set(Array.from({ length: 50 }, newSessionToken))
    expect(seen.size).toBe(50)
  })
})
