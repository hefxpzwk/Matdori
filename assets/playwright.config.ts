import { defineConfig } from "@playwright/test"

export default defineConfig({
  testDir: "./tests/e2e",
  timeout: 60_000,
  retries: 1,
  use: {
    baseURL: "http://127.0.0.1:4000",
    trace: "on-first-retry",
    screenshot: "only-on-failure",
    video: "retain-on-failure",
    headless: true,
  },
  webServer: {
    command: "mix run priv/repo/e2e_seed.exs && mix phx.server",
    cwd: "..",
    url: "http://127.0.0.1:4000",
    reuseExistingServer: false,
    timeout: 120_000,
  },
})
