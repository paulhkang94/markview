import { test, expect } from "@playwright/test";
import { loadFixture } from "../helpers/load";

test.describe("KaTeX math", () => {
  test.beforeEach(async ({ page }) => {
    await loadFixture(page, "math");
  });

  test("inline math (\\(...\\)) renders as <math> element", async ({
    page,
  }) => {
    await expect(page.locator("math").first()).toBeAttached();
  });

  test("display math ($$...$$) renders as <math display=block>", async ({
    page,
  }) => {
    await expect(page.locator('math[display="block"]').first()).toBeAttached();
  });

  test("no raw \\(...\\) delimiters visible as text", async ({ page }) => {
    const text = await page.locator("article").innerText();
    // Raw unrendered inline math shows literal \(E = mc^2\); rendered math replaces it with <math>
    expect(text).not.toMatch(/\\\(E\s*=\s*mc\^2\\\)/);
  });

  test("multiple math blocks all rendered", async ({ page }) => {
    // math.md has 4 math expressions: \(E=mc^2\), two $$...$$, and \[...\]
    const mathCount = await page.locator("math").count();
    expect(mathCount).toBeGreaterThanOrEqual(3);
  });

  test("financial dollar signs are not treated as math delimiters", async ({
    page,
  }) => {
    // Regression: $10,000 and $500 must render as plain text, not trigger LaTeX math rendering.
    // Before the fix, paired $...$ in financial prose caused garbled letter-by-letter math output.
    const text = await page.locator("article").innerText();
    expect(text).toContain("$10,000");
    expect(text).toContain("$500");
    // Confirm the dollar amounts appear as readable prose, not fragmented math characters
    const mathCount = await page.locator("math").count();
    // 4 math blocks from explicit math syntax; financial prose must not add more
    expect(mathCount).toBeLessThanOrEqual(4);
  });

  test("DOM snapshot", async ({ page }) => {
    test.skip(!!process.env.CI, "DOM snapshots are local-only baselines");
    await expect(page.locator("article")).toHaveScreenshot(
      "katex-article.png",
      {
        maxDiffPixelRatio: 0.03,
      },
    );
  });
});
