// OWASP minimum for argon2id; kept modest to fit Cloudflare Workers CPU budgets.
const ARGON2_OPTIONS = { timeCost: 2, memoryCost: 19456, parallelism: 1 }

const unb64 = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0))

async function derivePbkdf2(password, salt, iterations) {
  const key = await crypto.subtle.importKey(
    'raw', new TextEncoder().encode(password), 'PBKDF2', false, ['deriveBits'],
  )
  return crypto.subtle.deriveBits(
    { name: 'PBKDF2', hash: 'SHA-256', salt, iterations }, key, 256,
  )
}

async function verifyPbkdf2(password, stored) {
  try {
    const [, iterations, salt, expected] = stored.split('$')
    const bits = await derivePbkdf2(password, unb64(salt), Number(iterations))
    const actual = new Uint8Array(bits)
    const wanted = unb64(expected)
    if (actual.length !== wanted.length) return false
    let diff = 0
    for (let i = 0; i < actual.length; i++) diff |= actual[i] ^ wanted[i]
    return diff === 0
  } catch {
    return false
  }
}

export function createPasswords(argon2) {
  return {
    async hashPassword(password) {
      return argon2.hash(password, ARGON2_OPTIONS).encoded
    },

    async verifyPassword(password, stored) {
      if (typeof stored !== 'string' || !stored) return false
      if (stored.startsWith('pbkdf2$')) return verifyPbkdf2(password, stored)
      if (!stored.startsWith('$argon2')) return false
      return argon2.tryVerify(stored, password).success
    },

    needsRehash(stored) {
      return !String(stored).startsWith('$argon2')
    },
  }
}
