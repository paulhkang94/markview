import { test, expect } from "@playwright/test";
import { loadFixture } from "../helpers/load";

test.describe("Mermaid diagrams", () => {
  test.beforeEach(async ({ page }) => {
    await loadFixture(page, "mermaid");
    // Mermaid is async — wait for SVGs beyond the sentinel
    await page
      .waitForSelector(".mermaid svg", { timeout: 12_000 })
      .catch(() => {});
  });

  test("renders at least one SVG diagram", async ({ page }) => {
    const svgCount = await page.locator(".mermaid svg").count();
    expect(svgCount).toBeGreaterThan(0);
  });

  test("all mermaid fences replaced (no pre.language-mermaid remaining)", async ({
    page,
  }) => {
    const remaining = await page.locator("pre code.language-mermaid").count();
    expect(remaining).toBe(0);
  });

  test("SVG has no fixed width/height (responsive sizing applied)", async ({
    page,
  }) => {
    // Target diagram SVGs inside .mermaid-inner — not the control icon SVGs in .mermaid-controls
    // (control icons have width="1em" by design for em-based scaling)
    const svgs = page.locator(".mermaid-inner svg");
    const count = await svgs.count();
    expect(count).toBeGreaterThan(0);
    for (let i = 0; i < count; i++) {
      const width = await svgs.nth(i).getAttribute("width");
      expect(width).toBeNull();
    }
  });

  // Regression: mermaid.min.js bundles DOMPurify which contains </body> as JS string.
  // If insertBeforeBodyClose uses forward search, that string gets replaced and
  // 120KB of JS source leaks into the rendered article text. (Apr 4 2026 bug)
  test("no JS source visible in article text (mermaid.min.js leak regression)", async ({
    page,
  }) => {
    const text = await page.locator("article").innerText();
    expect(text).not.toMatch(/DOMPurify/);
    expect(text).not.toMatch(/createHTMLDocument/);
    expect(text).not.toMatch(/\.prototype\./);
  });

  test("DOM snapshot", async ({ page }, testInfo) => {
    test.skip(!!process.env.CI, "DOM snapshots are local-only baselines");
    await expect(page.locator("article")).toHaveScreenshot(
      "mermaid-article.png",
      {
        maxDiffPixelRatio: 0.05,
      },
    );
  });
});
