import {
  APPLE_CONTEXT_WINDOW_TOKENS,
  buildApplePromptEnvelope,
  clampPromptTextToTokenBudget,
  estimateTokenCount,
  getAppleInputTokenBudget,
  getAppleResponseTokenBudget,
} from "./harness.js";

const BRIDGE_NAME = "foundationModel";
export const APPLE_FOUNDATION_STATUS_KEY = "pax_apple_foundation_status_v1";

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

const emptyStatus = () => ({
  availability: "not-checked",
  bridgeAvailable: isAppleFoundationBridgeAvailable(),
  checkedAt: "",
  error: "",
  fallbackUsed: false,
  ok: false,
  provider: "apple-foundation",
  recoverySuggestion: "",
  requestId: "",
  taskKey: "",
  tokenBudget: "",
});

export const getAppleFoundationStatus = () => {
  if (typeof localStorage === "undefined") {
    return emptyStatus();
  }

  try {
    const parsed = JSON.parse(localStorage.getItem(APPLE_FOUNDATION_STATUS_KEY) || "null");
    return parsed && typeof parsed === "object"
      ? { ...emptyStatus(), ...parsed, bridgeAvailable: isAppleFoundationBridgeAvailable() }
      : emptyStatus();
  } catch {
    return emptyStatus();
  }
};

const normalizeAppleResponse = (response, payload = {}) => {
  if (typeof response === "string") {
    return {
      availability: "mock",
      error: "",
      fallbackUsed: false,
      ok: true,
      provider: "apple-foundation",
      recoverySuggestion: "",
      requestId: payload.requestId || "",
      taskKey: payload.taskKey || "",
      text: response,
      tokenBudget: "",
    };
  }

  if (!response || typeof response !== "object") {
    return {
      availability: "empty-response",
      error: "Apple Foundation Models returned an empty native response.",
      fallbackUsed: true,
      ok: false,
      provider: "apple-foundation",
      recoverySuggestion: "Retry from the native app; if this repeats, the WebKit bridge response contract is broken.",
      requestId: payload.requestId || "",
      taskKey: payload.taskKey || "",
      text: "",
      tokenBudget: "",
    };
  }

  return {
    availability: response?.availability || (response?.ok === false ? "unavailable" : "available"),
    error: response?.error || "",
    fallbackUsed: Boolean(response?.fallbackUsed),
    ok: response?.ok !== false,
    provider: response?.provider || "apple-foundation",
    recoverySuggestion: response?.recoverySuggestion || "",
    requestId: response?.requestId || payload.requestId || "",
    taskKey: response?.taskKey || payload.taskKey || "",
    text: response?.text ?? "",
    tokenBudget: response?.tokenBudget || "",
  };
};

const persistAppleFoundationStatus = (response) => {
  const status = {
    ...emptyStatus(),
    availability: response.availability,
    bridgeAvailable: isAppleFoundationBridgeAvailable(),
    checkedAt: new Date().toISOString(),
    error: response.error,
    fallbackUsed: response.fallbackUsed,
    ok: response.ok,
    provider: response.provider,
    recoverySuggestion: response.recoverySuggestion,
    requestId: response.requestId,
    taskKey: response.taskKey,
    tokenBudget: response.tokenBudget,
  };

  if (typeof localStorage !== "undefined") {
    localStorage.setItem(APPLE_FOUNDATION_STATUS_KEY, JSON.stringify(status));
  }

  if (
    typeof window !== "undefined" &&
    typeof window.dispatchEvent === "function" &&
    typeof CustomEvent === "function"
  ) {
    window.dispatchEvent(new CustomEvent("pax-apple-foundation-status-change", { detail: status }));
  }

  return status;
};

const installReceiver = () => {
  if (typeof window === "undefined") {
    return;
  }

  if (installed && typeof window.__paxAppleAI?.receiveResponse === "function") {
    return;
  }

  installed = true;
  window.__paxAppleAI = window.__paxAppleAI || {};
  window.__paxAppleAI.receiveResponse = (rawResponse) => {
    const response = normalizeAppleResponse(rawResponse);
    const requestId = response.requestId;
    const pending = pendingRequests.get(requestId);
    if (!pending) return;

    window.clearTimeout(pending.timeoutId);
    pendingRequests.delete(requestId);
    persistAppleFoundationStatus(response);

    if (response.ok) {
      pending.resolve(response);
    } else {
      pending.reject(new Error(response.error || "Apple Foundation Models did not return a response."));
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
    return Promise.resolve(window.__paxAppleAI.mockRespond(payload))
      .then((mockResponse) => {
        const response = normalizeAppleResponse(mockResponse, payload);
        persistAppleFoundationStatus(response);

        if (!response.ok) {
          throw new Error(response.error || "Apple Foundation Models did not return a response.");
        }

        return response;
      });
  }

  const handler = getBridgeHandler();
  if (!handler) {
    const response = normalizeAppleResponse({
      availability: "native-bridge-unavailable",
      error: "Apple Foundation Models are available only in the native iOS/macOS app.",
      fallbackUsed: true,
      ok: false,
      recoverySuggestion: "Open the bundled iOS/macOS app so WebKit can reach the native Foundation Models bridge.",
    }, payload);
    persistAppleFoundationStatus(response);
    throw new Error(response.error);
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
      const response = normalizeAppleResponse({
        availability: "timeout",
        error: "Apple Foundation Models timed out. The deterministic game fallback kept the turn safe.",
        fallbackUsed: true,
        ok: false,
        recoverySuggestion: "Retry after the current on-device generation finishes or reduce the amount of campaign context.",
        requestId: payload.requestId,
        taskKey,
      }, payload);
      persistAppleFoundationStatus(response);
      reject(new Error(response.error));
    }, opts.timeoutMs ?? 25_000);

    pendingRequests.set(payload.requestId, { reject, resolve, timeoutId });
    handler.postMessage(message);
  });
};
