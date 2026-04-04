import { test, expect } from "@playwright/test";
import { loadFixture } from "../helpers/load";

test.describe("GFM alerts", () => {
  test.beforeEach(async ({ page }) => {
    await loadFixture(page, "alerts");
  });

  test("NOTE renders as .alert-note div", async ({ page }) => {
    await expect(page.locator(".alert-note")).toBeAttached();
  });

  test("TIP renders as .alert-tip div", async ({ page }) => {
    await expect(page.locator(".alert-tip")).toBeAttached();
  });

  test("IMPORTANT renders as .alert-important div", async ({ page }) => {
    await expect(page.locator(".alert-important")).toBeAttached();
  });

  test("WARNING renders as .alert-warning div", async ({ page }) => {
    await expect(page.locator(".alert-warning")).toBeAttached();
  });

  test("CAUTION renders as .alert-caution div", async ({ page }) => {
    await expect(page.locator(".alert-caution")).toBeAttached();
  });

  test("no raw [!TYPE] markers visible in article", async ({ page }) => {
    const text = await page.locator("article").innerText();
    expect(text).not.toMatch(/\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]/i);
  });

  test("alert title has strong element with icon", async ({ page }) => {
    const titleEl = page.locator(".alert-note .alert-title strong").first();
    await expect(titleEl).toBeAttached();
    const titleText = await titleEl.innerText();
    expect(titleText).toMatch(/Note/i);
  });

  test("regular blockquote is not transformed", async ({ page }) => {
    // The fixture has a plain blockquote at the end — it must remain as <blockquote>
    const plainBq = await page
      .locator("article blockquote:not([class])")
      .count();
    expect(plainBq).toBeGreaterThan(0);
  });

  // DOM snapshot — skip pixel diff in CI (cross-platform unreliable), capture locally
  test("alert DOM snapshot", async ({ page }, testInfo) => {
    test.skip(!!process.env.CI, "DOM snapshots are local-only baselines");
    const alertSection = page.locator("article");
    await expect(alertSection).toHaveScreenshot("alerts-article.png", {
      maxDiffPixelRatio: 0.03,
    });
  });
});
