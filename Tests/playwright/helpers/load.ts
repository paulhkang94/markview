import { Page } from "@playwright/test";
import * as fs from "fs";
import * as path from "path";

const FIXTURES_DIR = path.resolve(__dirname, "../fixtures");

export function loadHTML(name: string): string {
  const filePath = path.join(FIXTURES_DIR, `${name}.html`);
  if (!fs.existsSync(filePath)) {
    throw new Error(
      `Fixture not found: ${filePath}\nRun: bash scripts/gen-playwright-fixtures.sh`,
    );
  }
  return fs.readFileSync(filePath, "utf-8");
}

export async function loadFixture(page: Page, name: string): Promise<void> {
  const html = loadHTML(name);
  await page.setContent(html, { waitUntil: "domcontentloaded" });
  // Guard: check if already rendered before polling (avoids race on fast loads)
  const alreadyDone = await page.evaluate(
    () => (window as unknown as { rendered?: boolean }).rendered === true,
  );
  if (!alreadyDone) {
    await page.waitForFunction(
      () => (window as unknown as { rendered?: boolean }).rendered === true,
      { timeout: 10_000 },
    );
  }
}
