// عمارتي — Playwright end-to-end config.
//
// These tests drive the REAL Flutter web build in a real browser and exercise
// the live Laravel backend through the page's own `fetch()` (same network path
// the app uses). They intentionally do NOT click through the CanvasKit canvas
// (whose semantics tree is brittle to automate); instead they assert backend
// behaviour end-to-end from inside the browser — which is what actually proves
// the fixes.
//
// Prereqs (see e2e/README.md):
//   1. An ISOLATED backend on :8001 pointing at a throwaway, seeded DB
//      (never your real data — these tests mutate).
//   2. The Flutter web build served on :8099.
const { defineConfig } = require('@playwright/test');

module.exports = defineConfig({
  testDir: '.',
  timeout: 30000,
  retries: 0,
  // Serial: these tests share one stateful backend — parallel workers would race
  // on data and share the auth rate-limit bucket.
  workers: 1,
  fullyParallel: false,
  use: {
    baseURL: process.env.WEB_BASE || 'http://127.0.0.1:8099',
    headless: true,
    trace: 'off',
  },
  reporter: [['list']],
});
