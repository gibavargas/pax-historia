import assert from "node:assert/strict";
import test from "node:test";
import {
  APPLE_FOUNDATION_STATUS_KEY,
  callAppleFoundation,
  getAppleFoundationStatus,
} from "../src/Game/AI/appleBridge.js";

const makeLocalStorage = () => {
  const storage = new Map();
  return {
    getItem: (key) => (storage.has(key) ? storage.get(key) : null),
    removeItem: (key) => storage.delete(key),
    setItem: (key, value) => storage.set(key, String(value)),
  };
};

const withBrowserWindow = async (windowOverrides, callback) => {
  const previousWindow = globalThis.window;
  const previousLocalStorage = Object.getOwnPropertyDescriptor(globalThis, "localStorage");

  Object.defineProperty(globalThis, "localStorage", {
    configurable: true,
    value: makeLocalStorage(),
  });
  globalThis.window = {
    clearTimeout: globalThis.clearTimeout.bind(globalThis),
    dispatchEvent: () => true,
    setTimeout: globalThis.setTimeout.bind(globalThis),
    ...windowOverrides,
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

test("Apple native bridge preserves fallback readiness diagnostics", async () => {
  const nativeMessages = [];

  await withBrowserWindow({
    webkit: {
      messageHandlers: {
        foundationModel: {
          postMessage: (message) => {
            nativeMessages.push(message);
            queueMicrotask(() => {
              window.__paxAppleAI.receiveResponse({
                availability: "model-not-ready",
                error: "Apple Intelligence is not ready on this device.",
                fallbackUsed: true,
                ok: true,
                provider: "apple-foundation",
                recoverySuggestion: "Keep the device on power and Wi-Fi, then retry.",
                requestId: message.requestId,
                taskKey: message.taskKey,
                text: "{\"topics\":[]}",
                tokenBudget: "fallback context=4096, estimate=80, maxResponse=520",
              });
            });
          },
        },
      },
    },
  }, async () => {
    const result = await callAppleFoundation(
      "You are a strategy game generator.",
      [{ role: "user", parts: [{ text: "Create possible actions." }] }],
      { responseFormat: "json", taskKey: "actions", timeoutMs: 500 },
    );

    assert.equal(result.availability, "model-not-ready");
    assert.equal(result.fallbackUsed, true);
    assert.equal(result.recoverySuggestion, "Keep the device on power and Wi-Fi, then retry.");
    assert.equal(result.text, "{\"topics\":[]}");
    assert.equal(nativeMessages.length, 1);
    assert.match(nativeMessages[0].promptEnvelope, /strict JSON object only/);

    const status = getAppleFoundationStatus();
    assert.equal(status.availability, "model-not-ready");
    assert.equal(status.bridgeAvailable, true);
    assert.equal(status.fallbackUsed, true);
    assert.equal(status.taskKey, "actions");
    assert.match(localStorage.getItem(APPLE_FOUNDATION_STATUS_KEY), /model-not-ready/);
  });
});

test("Apple bridge records an actionable status when the native host is missing", async () => {
  await withBrowserWindow({}, async () => {
    assert.throws(
      () => callAppleFoundation(
        "System",
        [{ role: "user", parts: [{ text: "Hello" }] }],
        { taskKey: "text", timeoutMs: 50 },
      ),
      /native iOS\/macOS app/,
    );

    const status = getAppleFoundationStatus();
    assert.equal(status.availability, "native-bridge-unavailable");
    assert.equal(status.ok, false);
    assert.equal(status.fallbackUsed, true);
    assert.match(status.recoverySuggestion, /bundled iOS\/macOS app/);
  });
});

test("Apple mock bridge remains compatible with string-only responses", async () => {
  await withBrowserWindow({
    __paxAppleAI: {
      mockRespond: () => "{\"summary\":\"ok\"}",
    },
  }, async () => {
    const result = await callAppleFoundation(
      "System",
      [{ role: "user", parts: [{ text: "Summarize" }] }],
      { responseFormat: "json", taskKey: "eventConsolidator" },
    );

    assert.equal(result.availability, "mock");
    assert.equal(result.fallbackUsed, false);
    assert.equal(result.text, "{\"summary\":\"ok\"}");
    assert.equal(getAppleFoundationStatus().availability, "mock");
  });
});
