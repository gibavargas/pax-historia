import assert from "node:assert/strict";
import test from "node:test";
import {
  APPLE_CONTEXT_WINDOW_TOKENS,
  buildApplePromptEnvelope,
  clampPromptText,
  clampPromptTextToTokenBudget,
  estimateTokenCount,
  extractJsonPayload,
  getAppleInputTokenBudget,
  getAppleResponseTokenBudget,
  resolveJsonPayloadOrFallback,
  splitTextByTokenBudget,
  validateTaskPayload,
} from "../src/Game/AI/harness.js";

test("extractJsonPayload accepts direct, fenced, and prose-wrapped JSON", () => {
  assert.deepEqual(extractJsonPayload('{"summary":"ok"}'), { summary: "ok" });
  assert.deepEqual(extractJsonPayload("```json\n{\"summary\":\"ok\"}\n```"), { summary: "ok" });
  assert.deepEqual(extractJsonPayload("Here is the result: {\"summary\":\"ok\"}"), { summary: "ok" });
  assert.deepEqual(extractJsonPayload("World notes: [{\"summary\":\"ok\"}]"), [{ summary: "ok" }]);
  assert.equal(extractJsonPayload(""), null);
});

test("task validation rejects malformed strategic payloads", () => {
  assert.equal(validateTaskPayload("actions", { topics: [] }), false);
  assert.equal(validateTaskPayload("actions", {
    topics: [{ title: "Diplomacy", actions: [{ title: "Open talks", text: "Start a channel." }] }],
  }), true);
  assert.equal(validateTaskPayload("nextSpeaker", { nextSpeaker: "" }), false);
});

test("invalid AI JSON falls back deterministically across a 99.9% safety budget", () => {
  let fallbackCalls = 0;
  const fallback = () => {
    fallbackCalls += 1;
    return {
      topics: [{
        actions: [{ kind: "action", text: "Preserve continuity.", title: "Stabilize" }],
        title: "Stability",
      }],
    };
  };

  for (let index = 0; index < 1000; index += 1) {
    const result = resolveJsonPayloadOrFallback({
      fallback,
      rawText: index % 2 === 0 ? "not-json" : "{\"topics\":[]}",
      taskKey: "actions",
    });
    assert.equal(result.fallbackUsed, true);
    assert.equal(result.payload.topics[0].title, "Stability");
  }

  assert.equal(fallbackCalls, 1000);
});

test("Apple prompt envelopes force strict JSON for structured tasks", () => {
  const envelope = buildApplePromptEnvelope({
    history: Array.from({ length: 12 }, (_, index) => ({
      role: "assistant",
      text: `Earlier turn ${index}: ${"context ".repeat(60)}`,
    })),
    responseFormat: "json",
    systemPrompt: `You are a strategy director. ${"system ".repeat(2_000)}`,
    taskKey: "jumpForward",
    userMessage: `Advance one month. ${"request ".repeat(900)}`,
  });

  assert.match(envelope, /strict JSON object only/);
  assert.match(envelope, /Task: jumpForward/);
  assert.ok(estimateTokenCount(envelope) <= getAppleInputTokenBudget("jumpForward", "json"));
});

test("clampPromptText trims oversized prompts before native dispatch", () => {
  const text = clampPromptText("a".repeat(30_000), 1_000);
  assert.ok(text.length <= 1_000);
  assert.match(text, /Context trimmed/);
});

test("Apple token budgets reserve response space inside the 4096 token context", () => {
  assert.equal(APPLE_CONTEXT_WINDOW_TOKENS, 4096);
  assert.equal(getAppleResponseTokenBudget("nextSpeaker", "json"), 80);
  assert.equal(getAppleResponseTokenBudget("unknownTask", "json"), 420);
  assert.equal(getAppleResponseTokenBudget("unknownTask", "text"), 360);

  const inputBudget = getAppleInputTokenBudget("jumpForward", "json");
  assert.ok(inputBudget > 2_000);
  assert.ok(inputBudget + getAppleResponseTokenBudget("jumpForward", "json") < APPLE_CONTEXT_WINDOW_TOKENS);
});

test("token-aware clamp keeps short prompts and trims long prompts", () => {
  assert.equal(clampPromptTextToTokenBudget("short note", 10), "short note");
  const trimmed = clampPromptTextToTokenBudget("abc ".repeat(2_000), 120, "[Trimmed for test.]");
  assert.match(trimmed, /\[Trimmed for test.\]/);
  assert.ok(estimateTokenCount(trimmed) <= 160);
  assert.ok(estimateTokenCount("汉字history") >= 4);
});

test("splitTextByTokenBudget chunks long Apple context deterministically", () => {
  assert.deepEqual(splitTextByTokenBudget("", 80), []);
  assert.deepEqual(splitTextByTokenBudget("compact", 80), ["compact"]);

  const paragraphA = "diplomacy ".repeat(220);
  const paragraphB = "economy ".repeat(220);
  const chunks = splitTextByTokenBudget(`${paragraphA}\n\n${paragraphB}`, 90, 4);

  assert.ok(chunks.length > 1);
  assert.ok(chunks.length <= 4);
  assert.ok(chunks.every((chunk) => chunk.trim().length > 0));
  assert.ok(chunks.every((chunk) => estimateTokenCount(chunk) <= 130));

  const hardSplit = splitTextByTokenBudget("x".repeat(5_000), 80, 3);
  assert.equal(hardSplit.length, 3);
});
