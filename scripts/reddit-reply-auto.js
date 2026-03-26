#!/usr/bin/env node
/**
 * reddit-reply-auto.js — Posts Reddit replies using the existing Chrome session.
 * Copies Chrome's cookie profile to a temp dir so Playwright can use it
 * without conflicting with the running Chrome instance.
 *
 * Usage:
 *   node scripts/reddit-reply-auto.js
 *   node scripts/reddit-reply-auto.js --id barrettj
 */

const { chromium } = require("playwright");
const fs = require("fs");
const path = require("path");
const os = require("os");
const { execSync } = require("child_process");

// ---------------------------------------------------------------------------
// Replies
// ---------------------------------------------------------------------------
const REPLIES = [
  {
    id: "barrettj",
    subreddit: "r/ClaudeCode",
    permalink:
      "https://www.reddit.com/r/ClaudeCode/comments/1rjshs2/comment/o8g13zx/",
    text: `Fixed. Updated \`docs/mcp-setup.md\` to use the correct paths and added an explicit callout that \`~/.claude/settings.json\` silently ignores mcpServers. The right location is \`~/.claude.json\`.

The one-liner handles config placement automatically if you want to skip editing files:

    claude mcp add markview --transport stdio -- npx -y mcp-server-markview

Thanks for tracking it down and posting the fix.`,
  },
  {
    id: "I_suck_at_uke",
    subreddit: "r/ClaudeCode",
    permalink:
      "https://www.reddit.com/r/ClaudeCode/comments/1rjshs2/comment/o8jurkb/",
    text: `Ha, \`preview_markdown\` actually takes any markdown string, so Claude Code could technically render your comment draft before you post. Less seamless than a browser extension though.`,
  },
  {
    id: "Acrobatic-Race6915",
    subreddit: "r/MacOSApps",
    permalink:
      "https://www.reddit.com/r/MacOSApps/comments/1rjs9eg/comment/o8fk7kz/",
    text: `Glad it's useful. That exact friction (opening an IDE just to read a .md file) is what prompted the whole thing. Hope it saves you some context switches.`,
  },
];

// ---------------------------------------------------------------------------
// Copy Chrome profile to temp dir (avoids profile lock, preserves cookies)
// ---------------------------------------------------------------------------
function buildTempProfile() {
  const chromeProfile = path.join(
    os.homedir(),
    "Library/Application Support/Google/Chrome",
  );
  const tempDir = fs.mkdtempSync("/tmp/chrome-reddit-");

  // Copy only the files Chrome needs for auth — skip heavy caches
  const filesToCopy = [
    "Default/Cookies",
    "Default/Local State",
    "Default/Preferences",
    "Default/Secure Preferences",
  ];

  for (const rel of filesToCopy) {
    const src = path.join(chromeProfile, rel);
    const dst = path.join(tempDir, rel);
    if (fs.existsSync(src)) {
      fs.mkdirSync(path.dirname(dst), { recursive: true });
      fs.copyFileSync(src, dst);
    }
  }

  console.log(`Temp profile at ${tempDir}`);
  return tempDir;
}

// ---------------------------------------------------------------------------
// Post a single reply
// ---------------------------------------------------------------------------
async function postReply(page, reply) {
  console.log(`\n[${reply.id}] Navigating to ${reply.permalink}`);
  await page.goto(reply.permalink, {
    waitUntil: "domcontentloaded",
    timeout: 30_000,
  });

  // Wait for the comment thread to render
  await page.waitForTimeout(3000);

  // On a comment permalink page the focused comment is at the top.
  // Strategy: find the Reply button on the first comment action bar.
  const replyBtn = page.locator("button", { hasText: /^Reply$/ }).first();
  try {
    await replyBtn.waitFor({ timeout: 10_000 });
  } catch {
    // Try old reddit fallback selector
    const altBtn = page
      .locator("a.comments-page-gilded-link, .usertext-buttons button")
      .first();
    if (await altBtn.count()) await altBtn.click();
    else throw new Error("Reply button not found");
  }
  await replyBtn.click();
  console.log(`[${reply.id}] Clicked Reply`);
  await page.waitForTimeout(1500);

  // Fill the editor — try contenteditable first, then textarea
  let filled = false;

  // New Reddit rich text editor
  const contentEditable = page.locator('div[contenteditable="true"]').first();
  if (await contentEditable.count()) {
    await contentEditable.click();
    // Use clipboard paste for React-based editors (more reliable than fill/type)
    await page.evaluate((text) => {
      const el = document.querySelector('div[contenteditable="true"]');
      if (!el) return;
      el.focus();
      const dt = new DataTransfer();
      dt.setData("text/plain", text);
      el.dispatchEvent(
        new ClipboardEvent("paste", { clipboardData: dt, bubbles: true }),
      );
    }, reply.text);
    await page.waitForTimeout(800);
    // Verify text appeared; if not, fall back to keyboard input
    const content = await contentEditable.textContent();
    if (!content || content.trim().length < 5) {
      await contentEditable.fill("");
      await contentEditable.type(reply.text, { delay: 5 });
    }
    filled = true;
  }

  if (!filled) {
    // Old Reddit / textarea fallback
    const textarea = page
      .locator('textarea[name="text"], textarea.usertext-edit')
      .first();
    if (await textarea.count()) {
      await textarea.fill(reply.text);
      filled = true;
    }
  }

  if (!filled) throw new Error("Could not find text editor");

  await page.waitForTimeout(500);

  // Submit — new Reddit labels the button "Comment", old Reddit "save"
  const submitBtn = page
    .locator(
      [
        'button[type="submit"]',
        'button:text-is("Comment")',
        'button:text-is("Save")',
        ".save-button button",
      ].join(", "),
    )
    .first();

  await submitBtn.waitFor({ timeout: 8_000 });
  await submitBtn.click();
  await page.waitForTimeout(2500);

  // Verify reply appeared (URL stays on same page, no error banner)
  const errorBanner = await page
    .locator('[id*="error"], .error-message, .ErrorBoundary')
    .count();
  if (errorBanner) throw new Error("Error banner detected after submit");

  console.log(`[${reply.id}] Posted successfully`);
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
(async () => {
  const args = process.argv.slice(2);
  const targetId = args.includes("--id")
    ? args[args.indexOf("--id") + 1]
    : null;
  const targets = targetId ? REPLIES.filter((r) => r.id === targetId) : REPLIES;

  if (!targets.length) {
    console.error(`No reply found for id: ${targetId}`);
    process.exit(1);
  }

  let tempProfile;
  try {
    tempProfile = buildTempProfile();
  } catch (err) {
    console.error("Could not copy Chrome profile:", err.message);
    process.exit(1);
  }

  const browser = await chromium.launchPersistentContext(tempProfile, {
    channel: "chrome", // use real Chrome so Keychain cookie decryption works
    headless: false,
    slowMo: 60,
    args: ["--no-first-run", "--no-default-browser-check"],
  });

  // Verify we're logged into Reddit
  const verifyPage = await browser.newPage();
  await verifyPage.goto("https://www.reddit.com", {
    waitUntil: "domcontentloaded",
    timeout: 20_000,
  });
  await verifyPage.waitForTimeout(2000);

  const loggedIn = await verifyPage.evaluate(() => {
    // New Reddit shows username in header; old Reddit has a login link
    const loginLinks = document.querySelectorAll('a[href*="/login"]');
    const userMenu = document.querySelector(
      '[data-testid*="user"], #USER_DROPDOWN_ID, .header-user-dropdown',
    );
    return !loginLinks.length || !!userMenu;
  });

  if (!loggedIn) {
    console.log(
      "Not logged in via profile cookies. Opening login page — log in and press Enter here when done.",
    );
    await verifyPage.goto("https://www.reddit.com/login", {
      waitUntil: "domcontentloaded",
    });
    await new Promise((r) => process.stdin.once("data", r));
  }
  await verifyPage.close();

  // Post replies
  const page = await browser.newPage();
  const failed = [];

  for (const reply of targets) {
    try {
      await postReply(page, reply);
    } catch (err) {
      console.error(`[${reply.id}] FAILED: ${err.message}`);
      failed.push(reply.id);
    }
  }

  await browser.close();

  // Cleanup temp profile
  try {
    fs.rmSync(tempProfile, { recursive: true });
  } catch {}

  if (failed.length) {
    console.log(
      `\nFailed: ${failed.join(", ")}. Re-run with --id to retry individually.`,
    );
    process.exit(1);
  } else {
    console.log("\nAll replies posted.");
  }
})();
