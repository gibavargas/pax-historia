import { expect, test } from "@playwright/test";

const settingsButton = (page) => page.locator("button").filter({ hasText: "⚙️" });

async function bootToPlayableMap(page) {
  await page.goto("/");
  await expect(page.locator(".fatal-shell")).toHaveCount(0);
  await expect(page.locator("canvas").first()).toBeVisible({ timeout: 35_000 });
  await expect(settingsButton(page)).toBeVisible({ timeout: 45_000 });
  await expect(page.locator(".fatal-shell")).toHaveCount(0);
}

async function putRuntimeJson(page, key, value) {
  await page.evaluate(async ({ key: assetKey, value: payload }) => {
    const response = await fetch(`/api/runtime/json/${assetKey}`, {
      body: JSON.stringify(payload),
      headers: { "Content-Type": "application/json" },
      method: "PUT",
    });

    if (!response.ok) {
      throw new Error(`Failed to write ${assetKey}: HTTP ${response.status}`);
    }
  }, { key, value });
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
  await page.locator("button").filter({ hasText: "Apple Foundation Models" }).first().click();
  await expect(page.getByText("Apple Foundation Models Settings")).toBeVisible();
  await expect(page.getByText("Device compatibility is only one gate")).toBeVisible();
  await expect(page.getByRole("button", { name: "Check Apple status" })).toBeVisible();
  await page.screenshot({ path: testInfo.outputPath("settings-ai.png"), fullPage: true });
});

test("player can choose country from the HUD selector", async ({ page }, testInfo) => {
  await bootToPlayableMap(page);

  const toggleId = testInfo.project.name === "mobile-safari-size"
    ? "country-chooser-toggle-mobile"
    : "country-chooser-toggle";
  await page.getByTestId(toggleId).click();
  await expect(page.getByTestId("country-chooser")).toBeVisible();
  await page.getByTestId("country-chooser-search").fill("Brazil");
  await page.getByTestId("country-chooser-option").filter({ hasText: "Brazil" }).first().click();

  await expect(page.getByTestId("country-chooser")).toHaveCount(0);
  const game = await page.evaluate(async () => {
    const response = await fetch("/api/runtime/json/game");
    return response.json();
  });
  expect(game.country).toBe("Brazil");
  await expect(page.getByTestId(toggleId)).toContainText("Brazil");
  await page.screenshot({ path: testInfo.outputPath("country-selected.png"), fullPage: true });
});

test("planned action time jump records durable strategic impact", async ({ page }, testInfo) => {
  await page.goto("/");
  await page.evaluate(() => {
    localStorage.setItem("api_provider", "gemini");
    localStorage.removeItem("gemini_api_key");
    localStorage.removeItem("pax_ai_health_v1");
  });
  await putRuntimeJson(page, "game", {
    country: "Brazil",
    countryCode: "BRA",
    difficulty: "standard",
    gameDate: "2030-01-01",
    language: "English",
    round: 1,
    startDate: "2030-01-01",
  });
  await putRuntimeJson(page, "actions", [
    {
      createdAt: "2030-01-01T00:00:00.000Z",
      id: "e2e-naval-readiness",
      kind: "action",
      rawInput: "Expand coastal naval readiness and secure Atlantic shipping lanes.",
      source: "manual",
      status: "planned",
      text: "Expand coastal naval readiness and secure Atlantic shipping lanes.",
      title: "Expand coastal naval readiness",
    },
  ]);
  await putRuntimeJson(page, "events", []);
  await putRuntimeJson(page, "world", {
    language: "English",
    simulationHistory: [],
    strategicEffects: [],
  });

  await page.reload();
  await expect(page.locator(".fatal-shell")).toHaveCount(0);
  await expect(page.locator("canvas").first()).toBeVisible({ timeout: 35_000 });
  await expect(settingsButton(page)).toBeVisible({ timeout: 45_000 });

  await page.locator("button").filter({ hasText: "»" }).first().click();
  await expect(page.getByText("Timeline")).toBeVisible();
  await page.getByRole("button", { name: /1 month/i }).click();
  await expect(page.getByText("Events")).toBeVisible({ timeout: 25_000 });
  await expect(page.getByText("Strategic impact", { exact: true })).toBeVisible({ timeout: 20_000 });

  const state = await page.evaluate(async () => {
    const read = async (key) => {
      const response = await fetch(`/api/runtime/json/${key}`);
      return response.json();
    };
    return {
      actions: await read("actions"),
      events: await read("events"),
      world: await read("world"),
    };
  });
  const effects = state.events.flatMap((event) => event.impacts?.strategicEffects ?? []);

  expect(state.actions.every((action) => action.status === "resolved")).toBe(true);
  expect(effects.length).toBeGreaterThan(0);
  expect(state.world.strategicEffects.length).toBeGreaterThan(0);
  expect(effects.some((effect) => effect.track === "military-readiness")).toBe(true);
  await page.screenshot({ path: testInfo.outputPath("action-impact.png"), fullPage: true });
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

test("fresh native Apple mode does not silently choose Germany", async ({ page }, testInfo) => {
  await page.addInitScript(() => {
    window.__PAX_APPLE_HOST__ = true;
    window.__PAX_NATIVE_RUNTIME__ = { mode: "apple", platform: "test" };
    localStorage.removeItem("pax-native-json:game");
    localStorage.removeItem("pax-native-player-country");
  });

  await bootToPlayableMap(page);

  const game = await page.evaluate(() => JSON.parse(localStorage.getItem("pax-native-json:game") || "{}"));

  expect(game.country).toBe("");
  expect(game.countryCode).toBe("");

  const toggleId = testInfo.project.name === "mobile-safari-size"
    ? "country-chooser-toggle-mobile"
    : "country-chooser-toggle";
  await expect(page.getByTestId(toggleId)).toContainText("Choose nation");
});
