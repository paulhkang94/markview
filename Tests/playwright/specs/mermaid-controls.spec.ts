import { test, expect, BrowserContext, Page } from "@playwright/test";
import { loadFixture } from "../helpers/load";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Parse a CSS transform string like "translate(40px,0px) scale(1.3)" */
function parseTransform(t: string): { tx: number; ty: number; s: number } {
  const translateMatch = t.match(/translate\(([^,]+)px,([^)]+)px\)/);
  const scaleMatch = t.match(/scale\(([^)]+)\)/);
  return {
    tx: translateMatch ? parseFloat(translateMatch[1]) : 0,
    ty: translateMatch ? parseFloat(translateMatch[2]) : 0,
    s: scaleMatch ? parseFloat(scaleMatch[1]) : 1,
  };
}

/** Read the current .mermaid-inner transform for the nth container (0-based). */
async function getTransform(
  page: Page,
  index = 0,
): Promise<{ tx: number; ty: number; s: number }> {
  const raw = await page.evaluate((idx: number) => {
    const inners = document.querySelectorAll(".mermaid-inner");
    const el = inners[idx] as HTMLElement | undefined;
    return el ? el.style.transform : "";
  }, index);
  return parseTransform(raw);
}

/** Hover over the nth .mermaid container so controls become pointer-events:auto. */
async function hoverMermaid(page: Page, index = 0): Promise<void> {
  const containers = page.locator(".mermaid");
  await containers.nth(index).hover();
}

/** Click a control button by its data-a attribute inside the nth container. */
async function clickControl(
  page: Page,
  action: string,
  containerIndex = 0,
): Promise<void> {
  const containers = page.locator(".mermaid");
  const btn = containers.nth(containerIndex).locator(`[data-a="${action}"]`);
  await btn.click();
}

// ---------------------------------------------------------------------------
// Test suite
// ---------------------------------------------------------------------------

test.describe("Mermaid pan/zoom/copy controls", () => {
  // Each test gets a fresh page load so transform state is clean.
  test.beforeEach(async ({ page }) => {
    await loadFixture(page, "mermaid");
    // loadFixture already waits for window.rendered === true (set inside mermaid.run().then())
    // Belt-and-suspenders: also wait for at least one .mermaid-controls to exist so the
    // DOM injection step has definitely fired before any test body runs.
    await page.waitForSelector(".mermaid-controls", { timeout: 12_000 });
  });

  // -------------------------------------------------------------------------
  // 1. Structural tests
  // -------------------------------------------------------------------------

  test.describe("structural", () => {
    test("each .mermaid container has a .mermaid-controls overlay", async ({
      page,
    }) => {
      const containers = await page.locator(".mermaid").count();
      expect(containers).toBeGreaterThan(0);

      // Every container must have exactly one .mermaid-controls child
      for (let i = 0; i < containers; i++) {
        const controlCount = await page
          .locator(".mermaid")
          .nth(i)
          .locator(".mermaid-controls")
          .count();
        expect(controlCount, `container ${i} missing .mermaid-controls`).toBe(
          1,
        );
      }
    });

    test("each .mermaid container has a .mermaid-inner wrapper", async ({
      page,
    }) => {
      const containers = await page.locator(".mermaid").count();
      for (let i = 0; i < containers; i++) {
        const innerCount = await page
          .locator(".mermaid")
          .nth(i)
          .locator(".mermaid-inner")
          .count();
        expect(innerCount, `container ${i} missing .mermaid-inner`).toBe(1);
      }
    });

    test("SVG is nested inside .mermaid-inner (not a direct .mermaid child)", async ({
      page,
    }) => {
      const svgDirectChildren = await page.locator(".mermaid > svg").count();
      expect(
        svgDirectChildren,
        "SVGs should be inside .mermaid-inner, not direct .mermaid children",
      ).toBe(0);

      const svgInInner = await page.locator(".mermaid-inner > svg").count();
      expect(svgInInner).toBeGreaterThan(0);
    });

    test("all 8 control buttons present with correct data-a values", async ({
      page,
    }) => {
      // Check on first container — representative
      const expected = ["u", "l", "r0", "ri", "d", "zi", "zo", "cp"];
      const controls = page
        .locator(".mermaid")
        .first()
        .locator(".mermaid-controls");

      for (const action of expected) {
        const count = await controls.locator(`[data-a="${action}"]`).count();
        expect(count, `button data-a="${action}" not found`).toBe(1);
      }
    });

    test("nav group has correct button layout (3×3 grid with spacers)", async ({
      page,
    }) => {
      const nav = page.locator(".mermaid").first().locator(".mermaid-ctrl-nav");
      await expect(nav).toBeAttached();

      // The 5 action buttons: up, left, reset, right, down
      for (const action of ["u", "l", "r0", "ri", "d"]) {
        await expect(
          nav.locator(`[data-a="${action}"]`),
          `nav missing data-a="${action}"`,
        ).toBeAttached();
      }
    });

    test("zoom group has zoom-in, zoom-out, copy buttons", async ({ page }) => {
      const zoom = page
        .locator(".mermaid")
        .first()
        .locator(".mermaid-ctrl-zoom");
      await expect(zoom).toBeAttached();

      for (const action of ["zi", "zo", "cp"]) {
        await expect(zoom.locator(`[data-a="${action}"]`)).toBeAttached();
      }
    });

    test("controls are initially invisible (opacity 0, pointer-events none)", async ({
      page,
    }) => {
      const { opacity, pointerEvents } = await page.evaluate(() => {
        const el = document.querySelector(".mermaid-controls") as HTMLElement;
        if (!el) return { opacity: "-1", pointerEvents: "unknown" };
        const computed = window.getComputedStyle(el);
        return {
          opacity: computed.opacity,
          pointerEvents: computed.pointerEvents,
        };
      });

      expect(parseFloat(opacity)).toBe(0);
      expect(pointerEvents).toBe("none");
    });
  });

  // -------------------------------------------------------------------------
  // 2. Pan tests
  // -------------------------------------------------------------------------

  test.describe("pan", () => {
    test("pan up (↑) increases ty", async ({ page }) => {
      await hoverMermaid(page);
      await clickControl(page, "u");
      const { ty } = await getTransform(page);
      expect(ty).toBe(40);
    });

    test("pan down (↓) decreases ty", async ({ page }) => {
      await hoverMermaid(page);
      await clickControl(page, "d");
      const { ty } = await getTransform(page);
      expect(ty).toBe(-40);
    });

    test("pan left (←) increases tx", async ({ page }) => {
      await hoverMermaid(page);
      await clickControl(page, "l");
      const { tx } = await getTransform(page);
      expect(tx).toBe(40);
    });

    test("pan right (→) decreases tx", async ({ page }) => {
      await hoverMermaid(page);
      await clickControl(page, "ri");
      const { tx } = await getTransform(page);
      expect(tx).toBe(-40);
    });

    test("reset (↺) returns transform to identity after pan", async ({
      page,
    }) => {
      await hoverMermaid(page);
      await clickControl(page, "u");
      await clickControl(page, "l");

      // Verify non-identity state before reset
      const before = await getTransform(page);
      expect(before.tx !== 0 || before.ty !== 0).toBe(true);

      await clickControl(page, "r0");
      const { tx, ty, s } = await getTransform(page);
      expect(tx).toBe(0);
      expect(ty).toBe(0);
      expect(s).toBe(1);
    });

    test("multiple pan up clicks accumulate ty", async ({ page }) => {
      await hoverMermaid(page);
      await clickControl(page, "u");
      await clickControl(page, "u");
      await clickControl(page, "u");
      const { ty } = await getTransform(page);
      expect(ty).toBe(120); // 3 × 40px
    });

    test("pan up then pan down cancel out", async ({ page }) => {
      await hoverMermaid(page);
      await clickControl(page, "u");
      await clickControl(page, "d");
      const { ty } = await getTransform(page);
      expect(ty).toBe(0);
    });

    test("pan left then pan right cancel out", async ({ page }) => {
      await hoverMermaid(page);
      await clickControl(page, "l");
      await clickControl(page, "ri");
      const { tx } = await getTransform(page);
      expect(tx).toBe(0);
    });
  });

  // -------------------------------------------------------------------------
  // 3. Zoom tests
  // -------------------------------------------------------------------------

  test.describe("zoom", () => {
    const Z = 1.3;

    test("zoom in (＋) sets scale > 1", async ({ page }) => {
      await hoverMermaid(page);
      await clickControl(page, "zi");
      const { s } = await getTransform(page);
      expect(s).toBeCloseTo(Z, 5);
    });

    test("zoom in multiple times multiplies scale", async ({ page }) => {
      await hoverMermaid(page);
      await clickControl(page, "zi");
      await clickControl(page, "zi");
      const { s } = await getTransform(page);
      expect(s).toBeCloseTo(Z * Z, 4);
    });

    test("zoom out (－) sets scale < 1", async ({ page }) => {
      await hoverMermaid(page);
      await clickControl(page, "zo");
      const { s } = await getTransform(page);
      expect(s).toBeCloseTo(1 / Z, 5);
    });

    test("zoom is clamped to max 8", async ({ page }) => {
      await hoverMermaid(page);
      // 1.3^10 > 8; clicking many times should not exceed 8
      for (let i = 0; i < 12; i++) {
        await clickControl(page, "zi");
      }
      const { s } = await getTransform(page);
      expect(s).toBeLessThanOrEqual(8);
    });

    test("zoom is clamped to min 0.1", async ({ page }) => {
      await hoverMermaid(page);
      for (let i = 0; i < 14; i++) {
        await clickControl(page, "zo");
      }
      const { s } = await getTransform(page);
      expect(s).toBeGreaterThanOrEqual(0.1);
    });

    test("zoom in then reset (↺) returns scale to 1", async ({ page }) => {
      await hoverMermaid(page);
      await clickControl(page, "zi");
      await clickControl(page, "zi");

      const before = await getTransform(page);
      expect(before.s).toBeGreaterThan(1);

      await clickControl(page, "r0");
      const { s } = await getTransform(page);
      expect(s).toBe(1);
    });

    test("zoom out then reset (↺) returns scale to 1", async ({ page }) => {
      await hoverMermaid(page);
      await clickControl(page, "zo");
      await clickControl(page, "r0");
      const { s } = await getTransform(page);
      expect(s).toBe(1);
    });
  });

  // -------------------------------------------------------------------------
  // 4. Copy test
  // -------------------------------------------------------------------------

  test.describe("copy SVG", () => {
    // Clipboard API requires document focus + user activation in headless Chromium.
    // We inject a reliable in-page mock so tests don't depend on the host clipboard.
    // The mock captures writeText() calls and exposes them via readText(),
    // making clipboard state fully inspectable from page.evaluate().
    async function injectClipboardMock(page: Page): Promise<void> {
      await page.evaluate(() => {
        let _written = "";
        const mock = {
          writeText: (text: string) => {
            _written = text;
            return Promise.resolve();
          },
          readText: () => Promise.resolve(_written),
        };
        Object.defineProperty(navigator, "clipboard", {
          value: mock,
          configurable: true,
          writable: true,
        });
      });
    }

    test("copy button (⎘) writes SVG XML to clipboard", async ({ page }) => {
      await injectClipboardMock(page);
      await hoverMermaid(page);
      await clickControl(page, "cp");

      // Poll until the mock clipboard has content (writeText is async Promise)
      const text = await page.waitForFunction(
        async () => {
          const t = await navigator.clipboard.readText();
          return t.length > 0 ? t : null;
        },
        { timeout: 5_000 },
      );

      const value = await text.jsonValue();
      expect(value as string).toMatch(/(<\?xml|<svg)/);
      expect(value as string).toContain("</svg>");
    });

    test("copy button shows checkmark SVG immediately after click", async ({
      page,
    }) => {
      await injectClipboardMock(page);
      await hoverMermaid(page);

      const btn = page.locator(".mermaid").first().locator('[data-a="cp"]');
      await btn.click();

      // After SVG icon switch: btn.innerHTML = IC.ck (checkmark SVG, no rect element)
      // The checkmark SVG has a <path> with stroke but no <rect>, unlike the copy icon.
      // Wait for the copy icon's <rect> to disappear (replaced by checkmark SVG).
      await page.waitForFunction(
        () => {
          const b = document.querySelector(
            '[data-a="cp"]',
          ) as HTMLElement | null;
          // Checkmark SVG: has <path> but no <rect>
          return (
            b !== null &&
            b.querySelector("rect") === null &&
            b.querySelector("path") !== null
          );
        },
        { timeout: 3_000 },
      );
      // Verify the checkmark SVG is present (no rect = checkmark, not copy icon)
      await expect(btn.locator("rect")).not.toBeAttached();
      await expect(btn.locator("path")).toBeAttached();
    });

    test("copy button reverts to ⎘ after 1200ms feedback window", async ({
      page,
    }) => {
      await injectClipboardMock(page);
      await hoverMermaid(page);
      await clickControl(page, "cp");

      // Wait for ✓ SVG to appear (button shows checkmark SVG on success)
      await page.waitForFunction(
        () =>
          (
            document.querySelector('[data-a="cp"]') as HTMLElement | null
          )?.querySelector("path[d*='4 4']") !== null, // checkmark path distinctive segment
        { timeout: 3_000 },
      );
      // Wait for button to revert — textContent becomes empty again (SVG, no text nodes)
      await page.waitForFunction(
        () => {
          const b = document.querySelector(
            '[data-a="cp"]',
          ) as HTMLElement | null;
          // Reverted: button holds the copy SVG again (2 children: rect + path)
          return b !== null && b.querySelector("rect") !== null;
        },
        { timeout: 2_500 }, // 1200ms + buffer
      );
      // Verify button contains the copy icon SVG (rect element is unique to the copy icon)
      await expect(
        page.locator(".mermaid").first().locator('[data-a="cp"] rect'),
      ).toBeAttached();
    });

    test("clipboard contains the SVG from the hovered diagram", async ({
      page,
    }) => {
      await injectClipboardMock(page);

      const domSvg = await page.evaluate(() => {
        const svg = document.querySelector(".mermaid-inner svg");
        return svg ? new XMLSerializer().serializeToString(svg) : "";
      });
      expect(domSvg.length).toBeGreaterThan(0);

      await hoverMermaid(page);
      await clickControl(page, "cp");

      const copied = await page.waitForFunction(
        async () => {
          const t = await navigator.clipboard.readText();
          return t.length > 0 ? t : null;
        },
        { timeout: 5_000 },
      );
      const value = (await copied.jsonValue()) as string;
      expect(value).toMatch(/(<\?xml|<svg)/);
      expect(value).toContain("</svg>");
    });
  });

  // -------------------------------------------------------------------------
  // 5. Visibility / hover tests
  // -------------------------------------------------------------------------

  test.describe("visibility", () => {
    test("controls have opacity 0 when mouse is not over diagram", async ({
      page,
    }) => {
      // Move mouse well away from diagram
      await page.mouse.move(0, 0);

      const opacity = await page.evaluate(() => {
        const el = document.querySelector(".mermaid-controls") as HTMLElement;
        return el ? parseFloat(window.getComputedStyle(el).opacity) : -1;
      });

      expect(opacity).toBe(0);
    });

    test("controls become opacity 1 on hover", async ({ page }) => {
      await hoverMermaid(page);

      // Wait for CSS transition to complete (0.15s) — use waitForFunction
      await page.waitForFunction(
        () => {
          const el = document.querySelector(
            ".mermaid:hover .mermaid-controls",
          ) as HTMLElement | null;
          if (!el) return false;
          return parseFloat(window.getComputedStyle(el).opacity) === 1;
        },
        { timeout: 2_000 },
      );

      const opacity = await page.evaluate(() => {
        const el = document.querySelector(
          ".mermaid:hover .mermaid-controls",
        ) as HTMLElement | null;
        return el ? parseFloat(window.getComputedStyle(el).opacity) : -1;
      });

      expect(opacity).toBe(1);
    });

    test("controls pointer-events become auto on hover", async ({ page }) => {
      await hoverMermaid(page);

      await page.waitForFunction(
        () => {
          const el = document.querySelector(
            ".mermaid:hover .mermaid-controls",
          ) as HTMLElement | null;
          if (!el) return false;
          return window.getComputedStyle(el).pointerEvents === "auto";
        },
        { timeout: 2_000 },
      );

      const pointerEvents = await page.evaluate(() => {
        const el = document.querySelector(
          ".mermaid:hover .mermaid-controls",
        ) as HTMLElement | null;
        return el ? window.getComputedStyle(el).pointerEvents : "none";
      });

      expect(pointerEvents).toBe("auto");
    });

    test("controls revert to opacity 0 after mouse leaves diagram", async ({
      page,
    }) => {
      // Hover to make visible
      await hoverMermaid(page);
      await page.waitForFunction(
        () => {
          const el = document.querySelector(
            ".mermaid:hover .mermaid-controls",
          ) as HTMLElement | null;
          return el
            ? parseFloat(window.getComputedStyle(el).opacity) === 1
            : false;
        },
        { timeout: 2_000 },
      );

      // Move mouse far away to trigger mouseleave
      await page.mouse.move(0, 0);

      // Wait for CSS transition back to opacity 0 (transition: 0.15s)
      await page.waitForFunction(
        () => {
          const controls = document.querySelectorAll(".mermaid-controls");
          for (const el of Array.from(controls)) {
            if (parseFloat(window.getComputedStyle(el).opacity) > 0) {
              return false;
            }
          }
          return controls.length > 0;
        },
        { timeout: 2_000 },
      );

      const opacity = await page.evaluate(() => {
        const el = document.querySelector(".mermaid-controls") as HTMLElement;
        return el ? parseFloat(window.getComputedStyle(el).opacity) : -1;
      });

      expect(opacity).toBe(0);
    });
  });

  // -------------------------------------------------------------------------
  // 6. Multi-diagram isolation
  // -------------------------------------------------------------------------

  // -------------------------------------------------------------------------
  // 6. Wheel scroll behavior
  // Regression: plain scroll was intercepted by e.preventDefault(), blocking
  // page scroll when the pointer was over a diagram.
  // -------------------------------------------------------------------------

  test.describe("wheel scroll behavior", () => {
    test("plain wheel scroll does NOT zoom diagram (passes through to page)", async ({
      page,
    }) => {
      const before = await getTransform(page, 0);
      // Dispatch a plain wheel event (no ctrlKey/metaKey) — should NOT zoom
      await page.locator(".mermaid").first().dispatchEvent("wheel", {
        deltaY: -120,
        deltaMode: 0,
        ctrlKey: false,
        metaKey: false,
      });
      const after = await getTransform(page, 0);
      // Scale must be unchanged — plain scroll must not zoom
      expect(after.s).toBeCloseTo(before.s, 3);
    });

    test("Ctrl+wheel zooms diagram in (does not scroll page)", async ({
      page,
    }) => {
      const before = await getTransform(page, 0);
      // Dispatch a Ctrl+wheel event — should zoom in
      await page.locator(".mermaid").first().dispatchEvent("wheel", {
        deltaY: -120,
        deltaMode: 0,
        ctrlKey: true,
        metaKey: false,
      });
      const after = await getTransform(page, 0);
      expect(after.s).toBeGreaterThan(before.s);
    });

    test("Ctrl+wheel zoom out reduces scale below 1", async ({ page }) => {
      const before = await getTransform(page, 0);
      await page.locator(".mermaid").first().dispatchEvent("wheel", {
        deltaY: 120,
        deltaMode: 0,
        ctrlKey: true,
        metaKey: false,
      });
      const after = await getTransform(page, 0);
      expect(after.s).toBeLessThan(before.s);
    });
  });

  test.describe("multi-diagram isolation", () => {
    test("panning one diagram does not affect another", async ({ page }) => {
      const count = await page.locator(".mermaid").count();
      test.skip(count < 2, "needs at least 2 diagrams in fixture");

      // Pan the first diagram
      await hoverMermaid(page, 0);
      await clickControl(page, "u", 0);

      const first = await getTransform(page, 0);
      const second = await getTransform(page, 1);

      expect(first.ty).toBe(40);
      expect(second.ty).toBe(0); // second diagram is unaffected
    });

    test("each diagram has its own independent controls", async ({ page }) => {
      const count = await page.locator(".mermaid").count();
      test.skip(count < 2, "needs at least 2 diagrams in fixture");

      const controlSets = await page.locator(".mermaid-controls").count();
      expect(controlSets).toBe(count);
    });
  });
});
