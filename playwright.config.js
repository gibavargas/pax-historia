import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "tests/e2e",
  timeout: 45_000,
  workers: 1,
  expect: {
    timeout: 20_000,
  },
  reporter: [["list"], ["html", { open: "never" }]],
  use: {
    baseURL: "http://127.0.0.1:3000",
    trace: "retain-on-failure",
  },
  webServer: {
    command: "npm run build && node server/server.js",
    reuseExistingServer: !process.env.CI,
    timeout: 90_000,
    url: "http://127.0.0.1:3000",
  },
  projects: [
    {
      name: "desktop-chromium",
      use: { ...devices["Desktop Chrome"], viewport: { width: 1440, height: 960 } },
    },
    {
      name: "mobile-safari-size",
      use: { ...devices["iPhone 15"], browserName: "chromium" },
    },
  ],
});
