import {
  APPLE_CONTEXT_WINDOW_TOKENS,
  buildApplePromptEnvelope,
  clampPromptTextToTokenBudget,
  estimateTokenCount,
  getAppleInputTokenBudget,
  getAppleResponseTokenBudget,
} from "./harness.js";

const BRIDGE_NAME = "foundationModel";
const pendingRequests = new Map();
let installed = false;

const normalizeHistory = (history) =>
  (Array.isArray(history) ? history : [])
    .slice(-12)
    .map((entry) => ({
      role: entry?.role === "model" || entry?.role === "assistant" ? "model" : "user",
      text: clampPromptTextToTokenBudget(entry?.parts?.[0]?.text ?? entry?.content ?? entry?.text ?? "", 180),
    }))
    .filter((entry) => entry.text);

const getBridgeHandler = () => {
  if (typeof window === "undefined") return null;
  return window.webkit?.messageHandlers?.[BRIDGE_NAME] ?? null;
};

export const isAppleFoundationBridgeAvailable = () => {
  if (typeof window === "undefined") return false;
  return Boolean(getBridgeHandler() || window.__paxAppleAI?.mockRespond);
};

const installReceiver = () => {
  if (installed || typeof window === "undefined") {
    return;
  }

  installed = true;
  window.__paxAppleAI = window.__paxAppleAI || {};
  window.__paxAppleAI.receiveResponse = (response) => {
    const requestId = response?.requestId;
    const pending = pendingRequests.get(requestId);
    if (!pending) return;

    window.clearTimeout(pending.timeoutId);
    pendingRequests.delete(requestId);

    if (response?.ok) {
      pending.resolve(response.text ?? "");
    } else {
      pending.reject(new Error(response?.error || "Apple Foundation Models did not return a response."));
    }
  };
};

export const callAppleFoundation = (systemPrompt, history, opts = {}) => {
  installReceiver();

  if (typeof window === "undefined") {
    return Promise.reject(new Error("Apple Foundation Models require a native Apple host."));
  }

  const userMessage = opts.userMessage || history?.at?.(-1)?.parts?.[0]?.text || "";
  const responseFormat = opts.responseFormat || "text";
  const taskKey = opts.taskKey || "";
  const responseTokenBudget = opts.maxTokens ?? getAppleResponseTokenBudget(taskKey, responseFormat);
  const inputTokenBudget = getAppleInputTokenBudget(taskKey, responseFormat);
  const normalizedHistory = normalizeHistory(history);
  const payload = {
    contextWindowTokens: APPLE_CONTEXT_WINDOW_TOKENS,
    history: normalizedHistory,
    inputTokenBudget,
    maxTokens: responseTokenBudget,
    requestId: `apple-ai-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 9)}`,
    responseFormat,
    responseTokenBudget,
    systemPrompt: clampPromptTextToTokenBudget(systemPrompt, Math.floor(inputTokenBudget * 0.6)),
    taskKey,
    temperature: opts.temperature ?? 0.2,
    userMessage: clampPromptTextToTokenBudget(userMessage, Math.floor(inputTokenBudget * 0.18)),
  };

  if (typeof window.__paxAppleAI?.mockRespond === "function") {
    return Promise.resolve(window.__paxAppleAI.mockRespond(payload));
  }

  const handler = getBridgeHandler();
  if (!handler) {
    throw new Error("Apple Foundation Models are available only in the native iOS/macOS app.");
  }

  const promptEnvelope = buildApplePromptEnvelope(payload);
  const message = {
    ...payload,
    inputTokenEstimate: estimateTokenCount(promptEnvelope) + estimateTokenCount(payload.systemPrompt),
    promptEnvelope,
  };

  return new Promise((resolve, reject) => {
    const timeoutId = window.setTimeout(() => {
      pendingRequests.delete(payload.requestId);
      reject(new Error("Apple Foundation Models timed out. The deterministic game fallback kept the turn safe."));
    }, opts.timeoutMs ?? 25_000);

    pendingRequests.set(payload.requestId, { reject, resolve, timeoutId });
    handler.postMessage(message);
  });
};
