import { test, expect } from "@playwright/test";
import { loadFixture } from "../helpers/load";

test.describe("diff2html rendering", () => {
  test.beforeEach(async ({ page }) => {
    await loadFixture(page, "diff");
    // diff2html runs on DOMContentLoaded — bridge should complete synchronously,
    // but wait for at least one .d2h-wrapper to be present before asserting.
    await page.waitForSelector(".d2h-wrapper", { timeout: 5_000 });
  });

  test("diff blocks render as d2h-wrapper elements", async ({ page }) => {
    // diff.md contains 2 diff fences — both must be converted
    const wrappers = await page.locator(".d2h-wrapper").count();
    expect(wrappers).toBe(2);
  });

  test("original pre.language-diff elements are replaced (not left in DOM)", async ({
    page,
  }) => {
    // After diff2html renders, the raw code block must be gone
    const rawBlocks = await page.locator("pre code.language-diff").count();
    expect(rawBlocks).toBe(0);
  });

  test("side-by-side table structure is present", async ({ page }) => {
    // Side-by-side format produces .d2h-diff-table inside each wrapper
    const diffTable = page.locator(".d2h-diff-table").first();
    await expect(diffTable).toBeVisible();
  });

  test("non-diff code block is not affected", async ({ page }) => {
    // diff.md contains one Swift block — Prism highlights it, diff2html must not touch it
    const swiftBlock = page.locator("pre code.language-swift");
    await expect(swiftBlock).toHaveCount(1);
    await expect(swiftBlock).toBeVisible();
  });

  test("diff2html CSS is applied (.d2h-file-header visible)", async ({
    page,
  }) => {
    // .d2h-file-header is a reliable CSS target — visible only if diff2html CSS was injected
    const fileHeader = page.locator(".d2h-file-header").first();
    await expect(fileHeader).toBeVisible();
  });

  test("_markviewRenderDiff fast-path is defined on window", async ({
    page,
  }) => {
    const isDefined = await page.evaluate(
      () =>
        typeof (window as unknown as Record<string, unknown>)
          ._markviewRenderDiff === "function",
    );
    expect(isDefined).toBe(true);
  });

  test("idempotency: calling _markviewRenderDiff() twice does not double-render", async ({
    page,
  }) => {
    const countBefore = await page.locator(".d2h-wrapper").count();
    await page.evaluate(() => {
      const w = window as unknown as Record<string, unknown>;
      if (typeof w._markviewRenderDiff === "function") {
        (w._markviewRenderDiff as () => void)();
      }
    });
    // Allow any synchronous DOM mutations to settle
    await page.waitForTimeout(100);
    const countAfter = await page.locator(".d2h-wrapper").count();
    expect(countAfter).toBe(countBefore);
  });

  test("data-diff2html-rendered guard is present on rendered wrappers", async ({
    page,
  }) => {
    // The bridge sets data-diff2html-rendered on processed elements to prevent
    // double-processing. Verify at least one element carries the attribute.
    const guarded = await page.locator("[data-diff2html-rendered]").count();
    expect(guarded).toBeGreaterThan(0);
  });

  test("DOM snapshot", async ({ page }, testInfo) => {
    test.skip(!!process.env.CI, "DOM snapshots are local-only baselines");
    await expect(page.locator("article")).toHaveScreenshot("diff-article.png", {
      maxDiffPixelRatio: 0.05,
    });
  });
});
