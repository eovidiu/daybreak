import { describe, it, expect } from 'vitest'
import {
  enabledProviders, authorizeUrl, decodeJwtPayload, appleClientSecret,
} from '../src/lib/oauth.js'

const FULL_ENV = {
  GOOGLE_CLIENT_ID: 'g-id', GOOGLE_CLIENT_SECRET: 'g-secret',
  FACEBOOK_APP_ID: 'f-id', FACEBOOK_APP_SECRET: 'f-secret',
  APPLE_SERVICE_ID: 'a-id', APPLE_TEAM_ID: 'T123', APPLE_KEY_ID: 'K123',
  APPLE_PRIVATE_KEY: 'pem',
}

describe('enabledProviders', () => {
  it('lists only fully configured providers', () => {
    expect(enabledProviders(FULL_ENV)).toEqual(['google', 'facebook', 'apple'])
    expect(enabledProviders({ GOOGLE_CLIENT_ID: 'x', GOOGLE_CLIENT_SECRET: 'y' }))
      .toEqual(['google'])
    expect(enabledProviders({ APPLE_SERVICE_ID: 'x' })).toEqual([])
    expect(enabledProviders({})).toEqual([])
  })
})

describe('authorizeUrl', () => {
  const redirect = 'https://app.example/api/auth/oauth/google/callback'

  it('builds a Google OIDC URL with state and scopes', () => {
    const u = new URL(authorizeUrl('google', FULL_ENV, redirect, 'st4te'))
    expect(u.origin + u.pathname).toBe('https://accounts.google.com/o/oauth2/v2/auth')
    expect(u.searchParams.get('client_id')).toBe('g-id')
    expect(u.searchParams.get('state')).toBe('st4te')
    expect(u.searchParams.get('response_type')).toBe('code')
    expect(u.searchParams.get('redirect_uri')).toBe(redirect)
    expect(u.searchParams.get('scope')).toContain('email')
  })

  it('builds a Facebook URL', () => {
    const u = new URL(authorizeUrl('facebook', FULL_ENV, redirect, 's'))
    expect(u.hostname).toBe('www.facebook.com')
    expect(u.searchParams.get('client_id')).toBe('f-id')
    expect(u.searchParams.get('scope')).toContain('email')
  })

  it('builds an Apple URL with form_post response mode', () => {
    const u = new URL(authorizeUrl('apple', FULL_ENV, redirect, 's'))
    expect(u.hostname).toBe('appleid.apple.com')
    expect(u.searchParams.get('client_id')).toBe('a-id')
    expect(u.searchParams.get('response_mode')).toBe('form_post')
    expect(u.searchParams.get('scope')).toBe('name email')
  })

  it('throws on unknown provider', () => {
    expect(() => authorizeUrl('github', FULL_ENV, redirect, 's')).toThrow()
  })
})

describe('decodeJwtPayload', () => {
  it('decodes the payload of a JWT without verifying', () => {
    const payload = { sub: '123', email: 'a@b.c' }
    const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url')
    const jwt = `${b64({ alg: 'none' })}.${b64(payload)}.sig`
    expect(decodeJwtPayload(jwt)).toEqual(payload)
  })

  it('returns null on garbage', () => {
    expect(decodeJwtPayload('not-a-jwt')).toBeNull()
    expect(decodeJwtPayload('')).toBeNull()
  })
})

describe('appleClientSecret', () => {
  it('produces an ES256 JWT verifiable with the matching public key', async () => {
    const { publicKey, privateKey } = await crypto.subtle.generateKey(
      { name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify'],
    )
    const pkcs8 = await crypto.subtle.exportKey('pkcs8', privateKey)
    const pem = `-----BEGIN PRIVATE KEY-----\n${
      Buffer.from(pkcs8).toString('base64')}\n-----END PRIVATE KEY-----`

    const env = { ...FULL_ENV, APPLE_PRIVATE_KEY: pem }
    const jwt = await appleClientSecret(env, 1750000000)

    const [h, p, s] = jwt.split('.')
    const header = decodeJwtPayload(`x.${h}.x`)
    expect(header).toEqual({ alg: 'ES256', kid: 'K123' })
    const claims = JSON.parse(Buffer.from(p, 'base64url').toString())
    expect(claims).toMatchObject({
      iss: 'T123', sub: 'a-id', aud: 'https://appleid.apple.com', iat: 1750000000,
    })
    expect(claims.exp).toBeGreaterThan(claims.iat)

    const ok = await crypto.subtle.verify(
      { name: 'ECDSA', hash: 'SHA-256' }, publicKey,
      Buffer.from(s, 'base64url'), new TextEncoder().encode(`${h}.${p}`),
    )
    expect(ok).toBe(true)
  })
})
