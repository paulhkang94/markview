import { test, expect } from "@playwright/test";
import { loadFixture } from "../helpers/load";

test.describe("KaTeX math", () => {
  test.beforeEach(async ({ page }) => {
    await loadFixture(page, "math");
  });

  test("inline math ($...$) renders as <math> element", async ({ page }) => {
    await expect(page.locator("math").first()).toBeAttached();
  });

  test("display math ($$...$$) renders as <math display=block>", async ({
    page,
  }) => {
    await expect(page.locator('math[display="block"]').first()).toBeAttached();
  });

  test("no raw $ delimiters visible as text", async ({ page }) => {
    const text = await page.locator("article").innerText();
    // Raw unrendered math shows literal $E = mc^2$; rendered math replaces it with <math>
    expect(text).not.toMatch(/\$E\s*=\s*mc\^2\$/);
  });

  test("multiple math blocks all rendered", async ({ page }) => {
    const mathCount = await page.locator("math").count();
    expect(mathCount).toBeGreaterThan(1);
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
