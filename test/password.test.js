import { describe, it, expect, beforeAll } from 'vitest'
import initialize from '@phi-ag/argon2/node'
import { createPasswords } from '../src/lib/password.js'

// Real hash produced by the previous PBKDF2 implementation for 'testpass123'.
const LEGACY_HASH =
  'pbkdf2$100000$JpYp9qC8G53HTUWv+UGyLA==$+tXNGbHWajpewBnkUctPlJ3B+fewnvrKV6lVkDKuq3g='

let passwords

beforeAll(async () => {
  passwords = createPasswords(await initialize())
})

describe('argon2 hashing', () => {
  it('produces argon2id encoded hashes', async () => {
    const hash = await passwords.hashPassword('my secret password')
    expect(hash.startsWith('$argon2id$')).toBe(true)
  })

  it('verifies a correct password and rejects a wrong one', async () => {
    const hash = await passwords.hashPassword('my secret password')
    expect(await passwords.verifyPassword('my secret password', hash)).toBe(true)
    expect(await passwords.verifyPassword('not it', hash)).toBe(false)
  })

  it('salts each hash differently', async () => {
    expect(await passwords.hashPassword('same')).not.toBe(await passwords.hashPassword('same'))
  })
})

describe('legacy pbkdf2 support', () => {
  it('still verifies pbkdf2 hashes', async () => {
    expect(await passwords.verifyPassword('testpass123', LEGACY_HASH)).toBe(true)
    expect(await passwords.verifyPassword('wrong', LEGACY_HASH)).toBe(false)
  })

  it('flags pbkdf2 hashes for rehash, argon2 not', async () => {
    expect(passwords.needsRehash(LEGACY_HASH)).toBe(true)
    expect(passwords.needsRehash(await passwords.hashPassword('x'))).toBe(false)
  })

  it('rejects malformed stored hashes without throwing', async () => {
    expect(await passwords.verifyPassword('x', 'garbage')).toBe(false)
    expect(await passwords.verifyPassword('x', '')).toBe(false)
  })
})
