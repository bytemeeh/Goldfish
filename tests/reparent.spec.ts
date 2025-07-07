
import { test, expect } from '@playwright/test';

test('reparent drag-and-drop', async ({ page }) => {
  await page.goto('/');
  await page.getByText('Christoph').dragTo(page.getByText('Raissa'));
  await expect(page.getByText('Raissa')).toHaveScreenshot();
});
