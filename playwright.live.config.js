import { defineConfig } from '@playwright/test'

// Runs the E2E suite against the deployed production site instead of wrangler dev.
export default defineConfig({
  testDir: 'e2e',
  timeout: 60000,
  workers: 1,
  use: {
    baseURL: 'https://daybreak.eovidiu.workers.dev',
  },
})
