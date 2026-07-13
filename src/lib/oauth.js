const PROVIDERS = {
  google: {
    keys: ['GOOGLE_CLIENT_ID', 'GOOGLE_CLIENT_SECRET'],
    authorize: 'https://accounts.google.com/o/oauth2/v2/auth',
    token: 'https://oauth2.googleapis.com/token',
  },
  facebook: {
    keys: ['FACEBOOK_APP_ID', 'FACEBOOK_APP_SECRET'],
    authorize: 'https://www.facebook.com/v19.0/dialog/oauth',
    token: 'https://graph.facebook.com/v19.0/oauth/access_token',
  },
  apple: {
    keys: ['APPLE_SERVICE_ID', 'APPLE_TEAM_ID', 'APPLE_KEY_ID', 'APPLE_PRIVATE_KEY'],
    authorize: 'https://appleid.apple.com/auth/authorize',
    token: 'https://appleid.apple.com/auth/token',
  },
}

const b64urlToB64 = (s) => s.replaceAll('-', '+').replaceAll('_', '/')
const b64urlEncode = (bytes) => btoa(String.fromCharCode(...new Uint8Array(bytes)))
  .replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '')
const b64urlEncodeJson = (obj) => b64urlEncode(new TextEncoder().encode(JSON.stringify(obj)))

export function enabledProviders(env) {
  return Object.keys(PROVIDERS)
    .filter((p) => PROVIDERS[p].keys.every((k) => env[k]))
}

export function authorizeUrl(provider, env, redirectUri, state) {
  const cfg = PROVIDERS[provider]
  if (!cfg) throw new Error(`unknown provider ${provider}`)
  const u = new URL(cfg.authorize)
  u.searchParams.set('client_id', env[cfg.keys[0]])
  u.searchParams.set('redirect_uri', redirectUri)
  u.searchParams.set('response_type', 'code')
  u.searchParams.set('state', state)
  if (provider === 'google') u.searchParams.set('scope', 'openid email profile')
  if (provider === 'facebook') u.searchParams.set('scope', 'public_profile,email')
  if (provider === 'apple') {
    u.searchParams.set('scope', 'name email')
    u.searchParams.set('response_mode', 'form_post')
  }
  return u.toString()
}

export function decodeJwtPayload(jwt) {
  try {
    const payload = String(jwt).split('.')[1]
    return JSON.parse(atob(b64urlToB64(payload)))
  } catch {
    return null
  }
}

async function importApplePrivateKey(pem) {
  const der = atob(pem.replace(/-----[A-Z ]+-----/g, '').replace(/\s/g, ''))
  const bytes = Uint8Array.from(der, (c) => c.charCodeAt(0))
  return crypto.subtle.importKey(
    'pkcs8', bytes, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign'],
  )
}

export async function appleClientSecret(env, nowSeconds) {
  const header = b64urlEncodeJson({ alg: 'ES256', kid: env.APPLE_KEY_ID })
  const claims = b64urlEncodeJson({
    iss: env.APPLE_TEAM_ID,
    iat: nowSeconds,
    exp: nowSeconds + 30 * 86400,
    aud: 'https://appleid.apple.com',
    sub: env.APPLE_SERVICE_ID,
  })
  const key = await importApplePrivateKey(env.APPLE_PRIVATE_KEY)
  const sig = await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' }, key,
    new TextEncoder().encode(`${header}.${claims}`),
  )
  return `${header}.${claims}.${b64urlEncode(sig)}`
}

async function postForm(url, params) {
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(params).toString(),
  })
  if (!res.ok) throw new Error(`token exchange failed: ${res.status}`)
  return res.json()
}

// Exchanges the authorization code and returns { providerId, email, name }.
export async function fetchIdentity(provider, env, redirectUri, code) {
  if (provider === 'google') {
    const tok = await postForm(PROVIDERS.google.token, {
      code, client_id: env.GOOGLE_CLIENT_ID, client_secret: env.GOOGLE_CLIENT_SECRET,
      redirect_uri: redirectUri, grant_type: 'authorization_code',
    })
    const claims = decodeJwtPayload(tok.id_token)
    if (!claims?.sub) throw new Error('google: no identity in id_token')
    return { providerId: claims.sub, email: claims.email, name: claims.name ?? '' }
  }

  if (provider === 'facebook') {
    const u = new URL(PROVIDERS.facebook.token)
    u.searchParams.set('client_id', env.FACEBOOK_APP_ID)
    u.searchParams.set('client_secret', env.FACEBOOK_APP_SECRET)
    u.searchParams.set('redirect_uri', redirectUri)
    u.searchParams.set('code', code)
    const tokRes = await fetch(u)
    if (!tokRes.ok) throw new Error(`token exchange failed: ${tokRes.status}`)
    const tok = await tokRes.json()
    const me = await fetch('https://graph.facebook.com/v19.0/me?fields=id,name,email'
      + `&access_token=${encodeURIComponent(tok.access_token)}`)
    if (!me.ok) throw new Error(`facebook profile fetch failed: ${me.status}`)
    const profile = await me.json()
    return { providerId: profile.id, email: profile.email, name: profile.name ?? '' }
  }

  if (provider === 'apple') {
    const secret = await appleClientSecret(env, Math.floor(Date.now() / 1000))
    const tok = await postForm(PROVIDERS.apple.token, {
      code, client_id: env.APPLE_SERVICE_ID, client_secret: secret,
      redirect_uri: redirectUri, grant_type: 'authorization_code',
    })
    const claims = decodeJwtPayload(tok.id_token)
    if (!claims?.sub) throw new Error('apple: no identity in id_token')
    return { providerId: claims.sub, email: claims.email, name: '' }
  }

  throw new Error(`unknown provider ${provider}`)
}
