import { defineConfig } from 'vitest/config'

export default defineConfig({
  test: {
    include: ['test/**/*.test.js'],
    coverage: {
      provider: 'v8',
      include: ['src/**'],
      reporter: ['text', 'json-summary'],
      thresholds: { lines: 95, functions: 95, statements: 95 },
    },
  },
})
