import { describe, it, expect } from 'vitest'
import { hashPassword, verifyPassword, newSessionToken } from '../src/lib/auth.js'

describe('password hashing', () => {
  it('verifies a correct password', async () => {
    const hash = await hashPassword('s3cret-pass')
    expect(await verifyPassword('s3cret-pass', hash)).toBe(true)
  })

  it('rejects a wrong password', async () => {
    const hash = await hashPassword('s3cret-pass')
    expect(await verifyPassword('not-the-pass', hash)).toBe(false)
  })

  it('salts each hash differently', async () => {
    const a = await hashPassword('same')
    const b = await hashPassword('same')
    expect(a).not.toBe(b)
  })

  it('rejects malformed stored hashes without throwing', async () => {
    expect(await verifyPassword('x', 'garbage')).toBe(false)
    expect(await verifyPassword('x', '')).toBe(false)
  })
})

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
