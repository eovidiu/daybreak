import { defineConfig } from '@playwright/test'

export default defineConfig({
  testDir: 'e2e',
  timeout: 60000,
  workers: 1,
  use: {
    baseURL: 'http://localhost:8787',
  },
  webServer: {
    command: 'npx wrangler dev --port 8787',
    url: 'http://localhost:8787',
    reuseExistingServer: true,
    timeout: 60000,
  },
})
