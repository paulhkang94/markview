#!/usr/bin/env node
/**
 * smithery-submit.js — Playwright automation for Smithery registry submission
 *
 * Modes:
 *   --check    Check current listing status (default, headless)
 *   --login    Open headed browser for GitHub OAuth, saves session cookies
 *   --submit   Attempt web-based submission after login
 *
 * Session cookies saved to ~/.smithery/playwright-cookies.json after --login.
 * Subsequent --check and --submit runs reuse saved cookies headlessly.
 *
 * Usage:
 *   node scripts/smithery-submit.js --check
 *   node scripts/smithery-submit.js --login   # one-time, needs human for 2FA
 *   node scripts/smithery-submit.js --submit
 *
 * Dependencies:
 *   npm install playwright  (or: npx playwright install chromium)
 */

const { chromium } = require("playwright");
const fs = require("fs");
const path = require("path");
const readline = require("readline");

// ── Config ────────────────────────────────────────────────────────────────────

const COOKIES_FILE = path.join(
  process.env.HOME,
  ".smithery",
  "playwright-cookies.json",
);
const SCREENSHOTS_DIR = path.join(__dirname, "../.smithery/screenshots");
const SERVER_SLUG = "markview/markview";
const SERVER_URL = `https://smithery.ai/servers/${SERVER_SLUG}`;
const PUBLISH_URL = "https://smithery.ai/new";
const NPM_PACKAGE = "mcp-server-markview";
const GITHUB_REPO = "https://github.com/paulhkang94/markview";

// ── Cookie helpers ─────────────────────────────────────────────────────────────

function loadCookies() {
  if (!fs.existsSync(COOKIES_FILE)) return null;
  try {
    return JSON.parse(fs.readFileSync(COOKIES_FILE, "utf8"));
  } catch {
    return null;
  }
}

async function saveCookies(context) {
  const cookies = await context.cookies();
  fs.mkdirSync(path.dirname(COOKIES_FILE), { recursive: true });
  fs.writeFileSync(COOKIES_FILE, JSON.stringify(cookies, null, 2));
  console.log(`✓ Session saved → ${COOKIES_FILE}`);
}

// ── Screenshot helper ──────────────────────────────────────────────────────────

async function screenshot(page, name) {
  fs.mkdirSync(SCREENSHOTS_DIR, { recursive: true });
  const p = path.join(SCREENSHOTS_DIR, `${name}.png`);
  await page.screenshot({ path: p, fullPage: true });
  console.log(`  📸 ${p}`);
  return p;
}

// ── Status check ───────────────────────────────────────────────────────────────

async function checkStatus(page) {
  console.log(`\nChecking ${SERVER_URL} …`);
  await page
    .goto(SERVER_URL, { waitUntil: "networkidle", timeout: 30_000 })
    .catch(() => {});
  const finalUrl = page.url();
  const title = await page.title();
  await screenshot(page, "status");

  const is404 =
    title.includes("404") ||
    finalUrl.includes("404") ||
    finalUrl.includes("not-found");
  const hasTools = (await page.locator("text=preview_markdown").count()) > 0;
  const hasInstall = (await page.locator("text=npx").count()) > 0;
  const isDeployed =
    (await page.locator("text=Deployed").count()) > 0 ||
    (await page.locator('[data-status="deployed"]').count()) > 0;

  // Try to find any "Publish" / "Add Release" / "Deploy" button when logged in
  const publishBtn = await page
    .locator(
      'button:has-text("Publish"), button:has-text("Deploy"), a:has-text("Add Release"), button:has-text("Add Release")',
    )
    .count();

  return {
    is404,
    hasTools,
    hasInstall,
    isDeployed,
    publishBtn,
    finalUrl,
    title,
  };
}

// ── Login flow ─────────────────────────────────────────────────────────────────

async function loginFlow(page, context) {
  console.log("\nOpening Smithery in headed browser for GitHub OAuth …");
  await page.goto("https://smithery.ai", { waitUntil: "networkidle" });

  // Click Sign In / Login button
  const loginBtn = page
    .locator(
      'a:has-text("Sign in"), button:has-text("Sign in"), a:has-text("Login"), button:has-text("Login")',
    )
    .first();
  if ((await loginBtn.count()) > 0) {
    await loginBtn.click();
    console.log("  Clicked Sign In");
  }

  // Wait for human to complete GitHub OAuth + 2FA
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });
  await new Promise((resolve) => {
    rl.question(
      "\n  Complete GitHub OAuth in the browser, then press Enter …\n",
      () => {
        rl.close();
        resolve();
      },
    );
  });

  await page.waitForLoadState("networkidle").catch(() => {});
  await saveCookies(context);
  await screenshot(page, "post-login");
  console.log("✓ Login complete");
}

// ── Submit flow ────────────────────────────────────────────────────────────────

async function submitFlow(page) {
  console.log("\nAttempting web-based Smithery submission …");

  // First check server page — does it exist with a way to publish a release?
  const status = await checkStatus(page);

  if (!status.is404 && status.publishBtn > 0) {
    console.log("  Found publish/release button on server page — attempting …");
    const btn = page
      .locator(
        'button:has-text("Publish"), button:has-text("Deploy"), a:has-text("Add Release"), button:has-text("Add Release")',
      )
      .first();
    await btn.click();
    await page.waitForLoadState("networkidle").catch(() => {});
    await screenshot(page, "after-publish-click");
    console.log("  Clicked publish button — check screenshot for next steps");
    return;
  }

  // Navigate to /new — the Smithery submission form
  console.log(`  Navigating to ${PUBLISH_URL} …`);
  await page
    .goto(PUBLISH_URL, { waitUntil: "networkidle", timeout: 30_000 })
    .catch(() => {});
  await screenshot(page, "new-server-form");

  const pageText = await page.textContent("body").catch(() => "");
  console.log(
    `  Page content preview: ${pageText.slice(0, 200).replace(/\s+/g, " ")} …`,
  );

  // Look for npm package input
  const npmInput = page
    .locator(
      'input[placeholder*="npm"], input[name*="npm"], input[placeholder*="package"], input[type="text"]',
    )
    .first();
  if ((await npmInput.count()) > 0) {
    await npmInput.fill(NPM_PACKAGE);
    console.log(`  Filled npm package: ${NPM_PACKAGE}`);
    await screenshot(page, "npm-filled");

    // Look for submit button
    const submitBtn = page
      .locator(
        'button[type="submit"], button:has-text("Submit"), button:has-text("Add"), button:has-text("Create")',
      )
      .first();
    if ((await submitBtn.count()) > 0) {
      console.log(
        "  Submit button found — NOT auto-clicking (review screenshot first)",
      );
      console.log(`  Screenshot: ${SCREENSHOTS_DIR}/npm-filled.png`);
    }
  }

  // Look for GitHub URL input as fallback
  const githubInput = page
    .locator(
      'input[placeholder*="github"], input[placeholder*="GitHub"], input[placeholder*="repo"], input[placeholder*="URL"]',
    )
    .first();
  if ((await githubInput.count()) > 0) {
    await githubInput.fill(GITHUB_REPO);
    console.log(`  Filled GitHub URL: ${GITHUB_REPO}`);
    await screenshot(page, "github-filled");
  }
}

// ── Main ───────────────────────────────────────────────────────────────────────

async function main() {
  const args = process.argv.slice(2);
  const isLogin = args.includes("--login");
  const isSubmit = args.includes("--submit");
  const headless = !isLogin;

  const browser = await chromium.launch({
    headless,
    slowMo: headless ? 0 : 100,
  });
  const context = await browser.newContext({
    viewport: { width: 1280, height: 900 },
  });

  // Load saved session cookies
  const cookies = loadCookies();
  if (cookies) {
    await context.addCookies(cookies);
    console.log(`✓ Loaded session cookies from ${COOKIES_FILE}`);
  } else {
    console.log(`  No saved cookies found at ${COOKIES_FILE}`);
    if (!isLogin) {
      console.log("  Run with --login first to authenticate");
    }
  }

  const page = await context.newPage();

  try {
    if (isLogin) {
      await loginFlow(page, context);
      // After login, check status
      const status = await checkStatus(page);
      printStatus(status);
    } else if (isSubmit) {
      await submitFlow(page);
    } else {
      // Default: check only
      const status = await checkStatus(page);
      printStatus(status);
      process.exitCode = status.is404 ? 1 : 0;
    }
  } finally {
    await browser.close();
  }
}

function printStatus(status) {
  console.log("\n── Smithery status ──────────────────────────────");
  console.log(`  URL:           ${status.finalUrl}`);
  console.log(`  Exists:        ${!status.is404 ? "✓ YES" : "✗ NO (404)"}`);
  console.log(`  Tools listed:  ${status.hasTools ? "✓ YES" : "✗ NO"}`);
  console.log(`  Install cmd:   ${status.hasInstall ? "✓ YES" : "✗ NO"}`);
  console.log(`  Deployed:      ${status.isDeployed ? "✓ YES" : "✗ NO"}`);
  console.log(
    `  Publish btn:   ${status.publishBtn > 0 ? "✓ FOUND" : "not found"}`,
  );
  console.log(`  Screenshots:   ${SCREENSHOTS_DIR}/`);
  console.log("─────────────────────────────────────────────────");

  if (status.is404) {
    console.log(
      "\n  → Server not listed. Run: node scripts/smithery-submit.js --login",
    );
    console.log(
      "                       then: node scripts/smithery-submit.js --submit",
    );
  } else if (!status.hasTools) {
    console.log(
      "\n  → Server page exists but tools not showing. May need a release.",
    );
    if (status.publishBtn > 0) {
      console.log("  → Run: node scripts/smithery-submit.js --submit");
    }
  } else {
    console.log("\n  ✓ Server is listed with tools visible.");
  }
}

main().catch((err) => {
  console.error("Error:", err.message);
  process.exit(1);
});
