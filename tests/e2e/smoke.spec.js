import { expect, test } from "@playwright/test";

const settingsButton = (page) => page.locator("button").filter({ hasText: "⚙️" });

async function bootToPlayableMap(page) {
  await page.goto("/");
  await expect(page.locator(".fatal-shell")).toHaveCount(0);
  await expect(page.locator("canvas").first()).toBeVisible({ timeout: 35_000 });
  await expect(settingsButton(page)).toBeVisible({ timeout: 45_000 });
  await expect(page.locator(".fatal-shell")).toHaveCount(0);
}

test("boots to an actionable map screen without fatal UI", async ({ page }, testInfo) => {
  await bootToPlayableMap(page);
  await page.screenshot({ path: testInfo.outputPath("boot-map.png"), fullPage: true });
});

test("settings expose Apple provider and AI reliability guardrails", async ({ page }, testInfo) => {
  await bootToPlayableMap(page);

  await settingsButton(page).click();
  await expect(page.getByText("Game Settings")).toBeVisible();
  await expect(page.getByText("AI Reliability")).toBeVisible();

  await page.getByText("Change").click();
  await page.getByPlaceholder("Search provider, protocol or gateway...").fill("apple");
  await expect(page.getByText("Apple Foundation Models")).toBeVisible();
  await page.screenshot({ path: testInfo.outputPath("settings-ai.png"), fullPage: true });
});

test("native Apple mode selects on-device provider and avoids fatal startup", async ({ page }) => {
  await page.addInitScript(() => {
    window.__PAX_APPLE_HOST__ = true;
    window.__PAX_NATIVE_RUNTIME__ = { mode: "apple", platform: "test" };
    localStorage.setItem("api_provider", "apple-foundation");
    window.__paxAppleAI = {
      mockRespond: () => "{\"topics\":[]}",
    };
  });

  await bootToPlayableMap(page);

  const provider = await page.evaluate(() => localStorage.getItem("api_provider"));
  expect(provider).toBe("apple-foundation");
});
