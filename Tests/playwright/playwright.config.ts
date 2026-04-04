import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "./specs",
  timeout: 15_000,
  expect: { timeout: 10_000 },
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: 0,
  reporter: process.env.CI ? [["github"], ["html", { open: "never" }]] : "html",

  // Snapshot baselines — first run creates them, subsequent runs diff
  snapshotDir: "./__snapshots__",
  snapshotPathTemplate: "{snapshotDir}/{projectName}/{testFilePath}/{arg}{ext}",
  updateSnapshots: "missing",

  use: {
    headless: true,
    // Screenshots only on failure (matches flow convention)
    screenshot: "only-on-failure",
    // Trace on failure for debugging CI flakes
    trace: "retain-on-failure",
  },

  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
    {
      name: "chromium-dark",
      use: {
        ...devices["Desktop Chrome"],
        colorScheme: "dark",
      },
    },
  ],
});
