import { test, expect } from "@playwright/test";
import { loadFixture } from "../helpers/load";

/**
 * TOC sidebar: presence, click-to-navigate, and scroll-spy.
 *
 * Regression for: TOC click navigation broken in WKWebView.
 * Root cause: scrollIntoView() unreliable when WKWebView navigation delegate
 * is present. Fix: window.scrollTo({top: h.offsetTop - 16}) in template.html.
 *
 * These tests run in Chromium (Playwright). WKWebView parity confirmed manually.
 * The fix uses window.scrollTo() which behaves identically in both engines.
 */

test.describe("TOC sidebar", () => {
  test.beforeEach(async ({ page }) => {
    // golden-corpus has 10+ headings — TOC threshold is 3
    await loadFixture(page, "golden-corpus");
  });

  // ── Presence ────────────────────────────────────────────────────────────

  test("TOC sidebar renders for document with 3+ headings", async ({
    page,
  }) => {
    await expect(page.locator("#toc-sidebar")).toBeVisible();
  });

  test("TOC contains multiple links", async ({ page }) => {
    const count = await page.locator("#toc-sidebar a").count();
    expect(count).toBeGreaterThanOrEqual(3);
  });

  test("TOC links have #fragment hrefs matching heading IDs", async ({
    page,
  }) => {
    // Every TOC link must point to an element that exists in the DOM.
    // Use [id="..."] attribute selector instead of #CSS.escape(id) — CSS.escape is
    // a browser global not available in the Node.js Playwright test runner process.
    const hrefs: string[] = await page
      .locator("#toc-sidebar a")
      .evaluateAll((anchors) =>
        anchors.map((a) => (a as HTMLAnchorElement).getAttribute("href") ?? ""),
      );

    for (const href of hrefs) {
      expect(href).toMatch(/^#\S+/);
      const id = href.slice(1);
      const exists = await page.locator(`[id="${id}"]`).count();
      // Each TOC link must resolve to an existing heading
      expect(exists).toBeGreaterThan(0);
    }
  });

  // ── Click-to-navigate (core regression test) ────────────────────────────

  test("clicking a TOC link scrolls the page to the target heading", async ({
    page,
  }) => {
    // Start at the top
    await page.evaluate(() => window.scrollTo(0, 0));

    // Pick the 4th TOC link (index 3) — reliably below the initial viewport
    const link = page.locator("#toc-sidebar a").nth(3);
    const href = await link.getAttribute("href");
    expect(href).toBeTruthy();
    const targetId = href!.slice(1);

    // Get the target heading's offsetTop before clicking
    const targetOffsetTop = await page.evaluate((id: string) => {
      const el = document.getElementById(id);
      return el ? (el as HTMLElement).offsetTop : -1;
    }, targetId);
    expect(targetOffsetTop).toBeGreaterThan(50); // must be non-trivially below top

    // Click the link
    await link.click();

    // Wait for scroll to settle (smooth scroll may be instant in headless Chromium)
    const expectedY = Math.max(0, targetOffsetTop - 16);
    await page.waitForFunction(
      ([expected]: [number]) => Math.abs(window.scrollY - expected) < 60,
      [expectedY] as [number],
      { timeout: 2000 },
    );

    const actualY = await page.evaluate(() => window.scrollY);
    // Allow ±60px tolerance for subpixel rounding and smooth-scroll overshoot
    expect(actualY).toBeGreaterThanOrEqual(expectedY - 60);
    expect(actualY).toBeLessThanOrEqual(expectedY + 60);
  });

  test("clicking first TOC link scrolls to near top of document", async ({
    page,
  }) => {
    // Scroll away from top first
    await page.evaluate(() => window.scrollTo(0, 500));
    await page.waitForTimeout(50);

    const firstLink = page.locator("#toc-sidebar a").first();
    const href = await firstLink.getAttribute("href");
    const targetId = href!.slice(1);
    const targetOffsetTop = await page.evaluate((id: string) => {
      const el = document.getElementById(id);
      return el ? (el as HTMLElement).offsetTop : 0;
    }, targetId);

    await firstLink.click();

    const expectedY = Math.max(0, targetOffsetTop - 16);
    await page.waitForFunction(
      ([expected]: [number]) => Math.abs(window.scrollY - expected) < 60,
      [expectedY] as [number],
      { timeout: 2000 },
    );

    const actualY = await page.evaluate(() => window.scrollY);
    expect(actualY).toBeLessThanOrEqual(expectedY + 60);
  });

  test("TOC click does not navigate away (e.preventDefault works)", async ({
    page,
  }) => {
    await page.locator("#toc-sidebar a").first().click();
    // If navigation occurred the sidebar would be gone — verify it persists
    await expect(page.locator("#toc-sidebar")).toBeVisible();
  });

  // ── Re-render regression ────────────────────────────────────────────────

  /**
   * Regression: TOC click navigation broken after content update via innerHTML swap.
   * Root cause: ToC click handlers captured stale heading DOM references in closures;
   * after innerHTML swap those elements are detached so offsetTop returns 0, scrolling
   * to the top instead of the target. Fix: _markviewRebuildTOC() re-queries headings
   * and wires fresh closure references after each innerHTML swap.
   */
  test("TOC links still scroll correctly after content is re-rendered via innerHTML swap", async ({
    page,
  }) => {
    // Simulate what updateContentViaJS() does: re-inject article HTML then call rebuild
    await page.evaluate(() => {
      const contentEl = document.getElementById("md-content");
      if (contentEl) {
        const html = contentEl.innerHTML;
        contentEl.innerHTML = html; // detaches old heading refs held by TOC closures
      }
      // Call the rebuild function that updateContentViaJS now invokes post-swap
      const w = window as unknown as Record<string, unknown>;
      if (typeof w._markviewRebuildTOC === "function") {
        (w._markviewRebuildTOC as () => void)();
      }
    });

    // TOC sidebar must still be present after rebuild
    await expect(page.locator("#toc-sidebar")).toBeVisible();

    // Core assertion: click-to-scroll must still reach the correct position
    await page.evaluate(() => window.scrollTo(0, 0));
    const link = page.locator("#toc-sidebar a").nth(3);
    const href = await link.getAttribute("href");
    expect(href).toBeTruthy();
    const targetId = href!.slice(1);

    const targetOffsetTop = await page.evaluate((id: string) => {
      const el = document.getElementById(id);
      return el ? (el as HTMLElement).offsetTop : -1;
    }, targetId);
    expect(targetOffsetTop).toBeGreaterThan(50); // must be non-trivially below top

    await link.click();

    const expectedY = Math.max(0, targetOffsetTop - 16);
    await page.waitForFunction(
      ([expected]: [number]) => Math.abs(window.scrollY - expected) < 60,
      [expectedY] as [number],
      { timeout: 2000 },
    );

    const actualY = await page.evaluate(() => window.scrollY);
    expect(actualY).toBeGreaterThanOrEqual(expectedY - 60);
    expect(actualY).toBeLessThanOrEqual(expectedY + 60);
  });

  // ── Scroll-spy ──────────────────────────────────────────────────────────

  test("first TOC link is active on initial load", async ({ page }) => {
    const firstLink = page.locator("#toc-sidebar a").first();
    await expect(firstLink).toHaveClass(/active/);
  });

  test("scroll-spy updates active link when page scrolls", async ({ page }) => {
    // Get the 4th heading's position
    const link = page.locator("#toc-sidebar a").nth(3);
    const href = await link.getAttribute("href");
    const targetId = href!.slice(1);
    const offsetTop = await page.evaluate((id: string) => {
      const el = document.getElementById(id);
      return el ? (el as HTMLElement).offsetTop : 0;
    }, targetId);

    // Scroll past the 80px threshold used by scroll-spy (window.scrollY + 80 >= offsetTop)
    await page.evaluate(
      (y: number) => window.scrollTo(0, y),
      Math.max(0, offsetTop - 40),
    );
    await page.waitForTimeout(100); // let requestAnimationFrame fire

    await expect(link).toHaveClass(/active/);
  });
});
