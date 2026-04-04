import { test, expect } from "@playwright/test";
import { loadFixture } from "../helpers/load";

/**
 * Golden corpus: all rendering features in one document.
 * These tests would have caught BOTH Apr 4 2026 bugs immediately:
 *   1. mermaid.min.js DOMPurify </body> leak → "no JS source" assertion
 *   2. GFM alerts regex failing → "no raw [!NOTE]" assertion
 */
test.describe("Golden corpus — all features", () => {
  test.beforeEach(async ({ page }) => {
    await loadFixture(page, "golden-corpus");
    // Mermaid is async — wait for SVGs if present
    const hasMermaid =
      (await page.locator("pre code.language-mermaid, .mermaid").count()) > 0;
    if (hasMermaid) {
      await page
        .waitForSelector(".mermaid svg", { timeout: 12_000 })
        .catch(() => {});
    }
  });

  // --- Rendering completeness ---

  test("article has substantial content", async ({ page }) => {
    const text = await page.locator("article").innerText();
    expect(text.length).toBeGreaterThan(200);
  });

  // --- Alert regression (Apr 4 2026 bug #2) ---

  test("GFM alerts transformed — no raw [!TYPE] markers", async ({ page }) => {
    // Don't use article.innerText() — it matches [!NOTE] inside code blocks/table cells.
    // Instead check that no <blockquote> elements still contain the raw marker
    // (transformed alerts become .alert-* divs, not blockquotes).
    const hasRawAlertBq = await page.evaluate(() => {
      return Array.from(document.querySelectorAll("article blockquote")).some(
        (bq) =>
          /\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]/i.test(
            bq.textContent || "",
          ),
      );
    });
    expect(hasRawAlertBq).toBe(false);
  });

  test("alert divs present", async ({ page }) => {
    const alertCount = await page.locator("[class^='alert alert-']").count();
    expect(alertCount).toBeGreaterThan(0);
  });

  // --- Mermaid regression (Apr 4 2026 bug #1) ---

  test("no mermaid.min.js source visible in article", async ({ page }) => {
    const text = await page.locator("article").innerText();
    expect(text).not.toMatch(/DOMPurify/);
    expect(text).not.toMatch(/createHTMLDocument/);
  });

  // --- KaTeX ---

  test("math renders as <math> elements", async ({ page }) => {
    const mathCount = await page.locator("math").count();
    expect(mathCount).toBeGreaterThan(0);
  });

  // --- Prism ---

  test("Prism ran on code blocks (pre elements have tabindex)", async ({
    page,
  }) => {
    // Prism adds tabindex="0" to all <pre> elements it processes, even for
    // languages not in the core bundle (swift, python, json). This verifies
    // Prism executed without requiring core-language tokens.
    // Token assertions live in prism.spec.ts which uses code-blocks.md (has JS blocks).
    const preTabs = await page.locator("pre[tabindex]").count();
    expect(preTabs).toBeGreaterThan(0);
  });

  // --- TOC ---

  test("TOC sidebar present (corpus has ≥3 headings)", async ({ page }) => {
    await expect(page.locator("#toc-sidebar")).toBeAttached();
  });

  // --- Tables ---

  test("tables wrapped in .table-wrapper", async ({ page }) => {
    const wrapperCount = await page.locator(".table-wrapper").count();
    expect(wrapperCount).toBeGreaterThan(0);
  });

  // --- DOM snapshot (local only) ---

  test("full corpus DOM snapshot — light mode", async ({ page }) => {
    test.skip(!!process.env.CI, "DOM snapshots are local-only baselines");
    await expect(page.locator("article")).toHaveScreenshot(
      "golden-corpus-light.png",
      { fullPage: false, maxDiffPixelRatio: 0.04 },
    );
  });

  test("full corpus DOM snapshot — dark mode", async ({ page }) => {
    test.skip(!!process.env.CI, "DOM snapshots are local-only baselines");
    // Only meaningful when run with chromium-dark project
    test.skip(
      !process.env.PLAYWRIGHT_PROJECT?.includes("dark"),
      "dark mode snapshot requires chromium-dark project",
    );
    await expect(page.locator("article")).toHaveScreenshot(
      "golden-corpus-dark.png",
      { fullPage: false, maxDiffPixelRatio: 0.04 },
    );
  });
});
