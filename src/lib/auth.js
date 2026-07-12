const ITERATIONS = 150000

const b64 = (buf) => btoa(String.fromCharCode(...new Uint8Array(buf)))
const unb64 = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0))

async function derive(password, salt, iterations) {
  const key = await crypto.subtle.importKey(
    'raw', new TextEncoder().encode(password), 'PBKDF2', false, ['deriveBits'],
  )
  return crypto.subtle.deriveBits(
    { name: 'PBKDF2', hash: 'SHA-256', salt, iterations }, key, 256,
  )
}

export async function hashPassword(password) {
  const salt = crypto.getRandomValues(new Uint8Array(16))
  const bits = await derive(password, salt, ITERATIONS)
  return `pbkdf2$${ITERATIONS}$${b64(salt)}$${b64(bits)}`
}

export async function verifyPassword(password, stored) {
  try {
    const [scheme, iterations, salt, expected] = stored.split('$')
    if (scheme !== 'pbkdf2') return false
    const bits = await derive(password, unb64(salt), Number(iterations))
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

export function newSessionToken() {
  const bytes = crypto.getRandomValues(new Uint8Array(32))
  return b64(bytes).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '')
}
