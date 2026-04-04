import { test, expect } from "@playwright/test";
import { loadFixture } from "../helpers/load";

test.describe("Prism syntax highlighting", () => {
  test.beforeEach(async ({ page }) => {
    await loadFixture(page, "code-blocks");
  });

  test("code blocks have .token spans", async ({ page }) => {
    const tokenCount = await page.locator(".token").count();
    expect(tokenCount).toBeGreaterThan(0);
  });

  test("language class preserved on code element", async ({ page }) => {
    // Prism requires language-* class to apply highlighting
    const langCode = await page.locator("code[class*='language-']").count();
    expect(langCode).toBeGreaterThan(0);
  });

  test("DOM snapshot", async ({ page }) => {
    test.skip(!!process.env.CI, "DOM snapshots are local-only baselines");
    await expect(page.locator("article")).toHaveScreenshot(
      "prism-article.png",
      {
        maxDiffPixelRatio: 0.03,
      },
    );
  });
});
