import assert from "node:assert/strict";
import test from "node:test";
import {
  getNativeLibraryCatalog,
  isAppleNativeHost,
  makeNativeJsonUrl,
  readNativeJson,
  requestNativeJson,
  resolveBundledAssetUrl,
  writeNativeJson,
} from "../src/runtime/nativeHost.js";

const makeLocalStorage = () => {
  const storage = new Map();
  return {
    getItem: (key) => (storage.has(key) ? storage.get(key) : null),
    removeItem: (key) => storage.delete(key),
    setItem: (key, value) => storage.set(key, String(value)),
  };
};

const withNativeWindow = async (callback) => {
  const previousWindow = globalThis.window;
  const previousLocalStorage = Object.getOwnPropertyDescriptor(globalThis, "localStorage");

  Object.defineProperty(globalThis, "localStorage", {
    configurable: true,
    value: makeLocalStorage(),
  });
  globalThis.window = {
    __PAX_APPLE_HOST__: true,
    location: { href: "file:///app/dist/index.html" },
  };

  try {
    await callback();
  } finally {
    if (previousWindow === undefined) {
      delete globalThis.window;
    } else {
      globalThis.window = previousWindow;
    }

    if (previousLocalStorage) {
      Object.defineProperty(globalThis, "localStorage", previousLocalStorage);
    } else {
      delete globalThis.localStorage;
    }
  }
};

test("Apple native game fallback seeds a playable campaign when bundled JSON fetch fails", async () => {
  const game = await readNativeJson(makeNativeJsonUrl("game"), {
    defaultValue: {
      country: "",
      gameDate: "",
      startDate: "",
    },
  });

  assert.equal(game.country, "Germany");
  assert.equal(game.gameDate, "2030-09-15");
  assert.equal(game.startDate, "2025-03-25");
});

test("Apple native host stores JSON locally and reports a seeded catalog", async () => {
  await withNativeWindow(async () => {
    assert.equal(isAppleNativeHost(), true);
    assert.equal(resolveBundledAssetUrl("./logo.png"), "file:///app/dist/logo.png");

    const url = makeNativeJsonUrl("events");
    await writeNativeJson(url, [{ title: "World event" }]);
    assert.deepEqual(await readNativeJson(url, { defaultValue: [] }), [{ title: "World event" }]);

    const catalog = getNativeLibraryCatalog();
    assert.equal(catalog.activeGameId, "native-game");
    assert.equal(catalog.games[0].country, "Germany");
    assert.equal(catalog.games[0].currentDate, "2030-09-15");
  });
});

test("Apple native API shim serves library records and rejects unsupported reads", async () => {
  const catalog = await requestNativeJson("/api/library");
  assert.equal(catalog.runtimeScenario.id, "default");

  const game = await requestNativeJson("/api/games/native-game", {
    body: { name: "Edited Native Campaign" },
  });
  assert.equal(game.name, "Edited Native Campaign");
  assert.equal(game.country, "Germany");

  const postResult = await requestNativeJson("/api/scenarios", { method: "POST" });
  assert.equal(postResult.selectedScenarioId, "default");

  await assert.rejects(
    () => requestNativeJson("/api/unsupported"),
    /not available in the bundled Apple build/,
  );
});
