
// Inline code light-mode visibility: background must be distinguishable from #ffffff
test('inline code has visible background in light mode', async ({ page }) => {
  const html = fixtures['inline-code'] || '<p>Use <code>npm install</code> to install.</p>';
  await page.setContent(html);
  const bg = await page.$eval('code', el =>
    getComputedStyle(el).backgroundColor
  );
  // Must not be pure white or fully transparent
  expect(bg).not.toBe('rgba(0, 0, 0, 0)');
  expect(bg).not.toBe('rgb(255, 255, 255)');
});
