#!/usr/bin/env node
/**
 * reddit-reply.js — Playwright automation for posting MarkView Reddit comment replies
 *
 * Usage:
 *   node scripts/reddit-reply.js --login     # one-time: opens browser for Reddit login, saves cookies
 *   node scripts/reddit-reply.js --dry-run   # prints replies that would be posted, no browser
 *   node scripts/reddit-reply.js --post      # posts all pending replies using saved cookies
 *   node scripts/reddit-reply.js --post --id barrettj  # post single reply by key
 *
 * Cookies saved to ~/.markview/reddit-cookies.json after --login.
 */

const { chromium } = require("playwright");
const fs = require("fs");
const path = require("path");
const os = require("os");

const COOKIES_PATH = path.join(
  os.homedir(),
  ".markview",
  "reddit-cookies.json",
);

// ---------------------------------------------------------------------------
// Reply definitions — edit text here, never touch the automation logic below
// ---------------------------------------------------------------------------
const REPLIES = [
  {
    id: "barrettj",
    subreddit: "r/ClaudeCode",
    commentPermalink:
      "https://www.reddit.com/r/ClaudeCode/comments/1rjshs2/comment/o8g13zx/",
    text: `Fixed. Updated \`docs/mcp-setup.md\` to use the correct paths and added an explicit callout that \`~/.claude/settings.json\` silently ignores mcpServers. The right location is \`~/.claude.json\`.

The one-liner handles config placement automatically if you want to skip editing files:

    claude mcp add markview --transport stdio -- npx -y mcp-server-markview

Thanks for tracking it down and posting the fix.`,
  },
  {
    id: "I_suck_at_uke",
    subreddit: "r/ClaudeCode",
    commentPermalink:
      "https://www.reddit.com/r/ClaudeCode/comments/1rjshs2/comment/o8jurkb/",
    text: `Ha, \`preview_markdown\` actually takes any markdown string, so Claude Code could technically render your comment draft before you post. Less seamless than a browser extension though.`,
  },
  {
    id: "Acrobatic-Race6915",
    subreddit: "r/MacOSApps",
    commentPermalink:
      "https://www.reddit.com/r/MacOSApps/comments/1rjs9eg/comment/o8fk7kz/",
    text: `Glad it's useful. That exact friction (opening an IDE just to read a .md file) is what prompted the whole thing. Hope it saves you some context switches.`,
  },
];

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function ensureDir(p) {
  const dir = path.dirname(p);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
}

function loadCookies() {
  if (!fs.existsSync(COOKIES_PATH)) return null;
  return JSON.parse(fs.readFileSync(COOKIES_PATH, "utf8"));
}

function saveCookies(cookies) {
  ensureDir(COOKIES_PATH);
  fs.writeFileSync(COOKIES_PATH, JSON.stringify(cookies, null, 2));
  console.log(`Cookies saved to ${COOKIES_PATH}`);
}

async function loginFlow() {
  console.log(
    "Opening browser for Reddit login. Log in, then close the browser to save your session.",
  );
  const browser = await chromium.launch({ headless: false, slowMo: 50 });
  const context = await browser.newContext();
  const page = await context.newPage();
  await page.goto("https://www.reddit.com/login", {
    waitUntil: "domcontentloaded",
  });

  // Wait for user to manually log in and reach the home feed
  await page.waitForURL("**/reddit.com/**", { timeout: 120_000 });
  await page.waitForTimeout(2000);

  const cookies = await context.cookies();
  saveCookies(cookies);
  await browser.close();
  console.log("Login complete.");
}

async function postReply(page, reply) {
  console.log(`\nNavigating to ${reply.commentPermalink}`);
  await page.goto(reply.commentPermalink, {
    waitUntil: "domcontentloaded",
    timeout: 30_000,
  });
  await page.waitForTimeout(2000);

  // The target comment is the first top-level comment when navigating to its permalink.
  // Find the Reply button closest to the top of the page (the focused comment).
  const replyBtn = page.locator("button", { hasText: /^Reply$/ }).first();
  await replyBtn.waitFor({ timeout: 10_000 });
  await replyBtn.click();
  await page.waitForTimeout(1000);

  // Reddit's new UI uses a contenteditable rich text editor.
  // Try contenteditable first, fall back to textarea.
  let editor = page.locator('div[contenteditable="true"]').first();
  const editorCount = await editor.count();
  if (editorCount === 0) {
    editor = page.locator("textarea").first();
  }
  await editor.waitFor({ timeout: 8_000 });
  await editor.click();
  await editor.fill(reply.text);
  await page.waitForTimeout(500);

  // Submit button — Reddit new UI uses "Comment" as the label
  const submitBtn = page
    .locator('button[type="submit"]', { hasText: /comment/i })
    .or(page.locator("button", { hasText: /^Comment$/ }))
    .first();
  await submitBtn.waitFor({ timeout: 8_000 });

  console.log(`  Posting reply to ${reply.id} in ${reply.subreddit}...`);
  await submitBtn.click();
  await page.waitForTimeout(2500);
  console.log(`  Done: ${reply.id}`);
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
(async () => {
  const args = process.argv.slice(2);
  const mode =
    args.find((a) => ["--login", "--dry-run", "--post"].includes(a)) ||
    "--dry-run";
  const targetId = args.includes("--id")
    ? args[args.indexOf("--id") + 1]
    : null;

  const targets = targetId ? REPLIES.filter((r) => r.id === targetId) : REPLIES;

  if (mode === "--dry-run") {
    console.log("DRY RUN — replies that would be posted:\n");
    for (const r of targets) {
      console.log(`=== ${r.id} (${r.subreddit}) ===`);
      console.log(`URL: ${r.commentPermalink}`);
      console.log("TEXT:");
      console.log(r.text);
      console.log("");
    }
    return;
  }

  if (mode === "--login") {
    await loginFlow();
    return;
  }

  if (mode === "--post") {
    const cookies = loadCookies();
    if (!cookies) {
      console.error("No saved cookies. Run with --login first.");
      process.exit(1);
    }

    const browser = await chromium.launch({ headless: false, slowMo: 80 });
    const context = await browser.newContext();
    await context.addCookies(cookies);

    // Verify login by checking username visible on reddit
    const checkPage = await context.newPage();
    await checkPage.goto("https://www.reddit.com", {
      waitUntil: "domcontentloaded",
      timeout: 20_000,
    });
    const loggedIn = await checkPage
      .locator(
        '[data-testid="user-drawer-header"], #USER_DROPDOWN_ID, button[aria-label*="profile"]',
      )
      .count();
    if (loggedIn === 0) {
      console.error("Session expired or not logged in. Run --login again.");
      await browser.close();
      process.exit(1);
    }
    await checkPage.close();

    const page = await context.newPage();
    for (const reply of targets) {
      try {
        await postReply(page, reply);
      } catch (err) {
        console.error(`Failed to post reply to ${reply.id}:`, err.message);
        console.error("Continuing with next reply...");
      }
    }

    await browser.close();
    console.log("\nAll replies posted.");
  }
})();
