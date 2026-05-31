const normalizeString = (value) => String(value ?? "").trim();

export const APPLE_CONTEXT_WINDOW_TOKENS = 4096;
export const APPLE_CONTEXT_SAFETY_TOKENS = 384;

export const APPLE_RESPONSE_TOKEN_BUDGETS = {
  actions: 520,
  autoJumpForward: 760,
  catalystCreation: 420,
  catalystExecutor: 360,
  catalystSummary: 220,
  descriptionToAction: 260,
  eventConsolidator: 220,
  gameMaster: 360,
  jumpForward: 760,
  nextSpeaker: 80,
  text: 360,
};

const maybeJsonParse = (value) => {
  try {
    return JSON.parse(value);
  } catch {
    return null;
  }
};

const countCjkCharacters = (text) =>
  (text.match(/[\u3040-\u30ff\u3400-\u9fff\uf900-\ufaff\uac00-\ud7af]/g) ?? []).length;

export const estimateTokenCount = (value) => {
  const text = normalizeString(value);
  if (!text) return 0;

  const cjkCount = countCjkCharacters(text);
  const latinLikeCount = Math.max(0, text.length - cjkCount);
  return Math.ceil(cjkCount + latinLikeCount / 3.3);
};

export const getAppleResponseTokenBudget = (taskKey = "", responseFormat = "text") => {
  if (taskKey && APPLE_RESPONSE_TOKEN_BUDGETS[taskKey]) {
    return APPLE_RESPONSE_TOKEN_BUDGETS[taskKey];
  }

  return responseFormat === "json" ? 420 : APPLE_RESPONSE_TOKEN_BUDGETS.text;
};

export const getAppleInputTokenBudget = (taskKey = "", responseFormat = "text") =>
  Math.max(
    900,
    APPLE_CONTEXT_WINDOW_TOKENS -
      APPLE_CONTEXT_SAFETY_TOKENS -
      getAppleResponseTokenBudget(taskKey, responseFormat),
  );

export const clampPromptText = (value, maxLength = 8_000) => {
  const text = normalizeString(value);
  if (text.length <= maxLength) {
    return text;
  }

  return `${text.slice(0, maxLength - 120)}\n\n[Context trimmed to stay inside the on-device model window.]`;
};

export const clampPromptTextToTokenBudget = (value, tokenBudget, suffix = "[Context trimmed.]") => {
  const text = normalizeString(value);
  if (estimateTokenCount(text) <= tokenBudget) {
    return text;
  }

  const charBudget = Math.max(240, Math.floor(tokenBudget * 3));
  return `${text.slice(0, Math.max(0, charBudget - suffix.length - 3)).trim()}\n\n${suffix}`;
};

export const splitTextByTokenBudget = (value, tokenBudget = 1_100, maxChunks = 6) => {
  const text = normalizeString(value);
  if (!text) return [];
  if (estimateTokenCount(text) <= tokenBudget) return [text];

  const chunks = [];
  const paragraphs = text
    .split(/\n{2,}/)
    .map((entry) => entry.trim())
    .filter(Boolean);
  let current = "";

  const pushCurrent = () => {
    if (!current.trim()) return;
    chunks.push(current.trim());
    current = "";
  };

  for (const paragraph of paragraphs.length ? paragraphs : [text]) {
    const candidate = current ? `${current}\n\n${paragraph}` : paragraph;
    if (estimateTokenCount(candidate) <= tokenBudget) {
      current = candidate;
      continue;
    }

    pushCurrent();

    if (estimateTokenCount(paragraph) <= tokenBudget) {
      current = paragraph;
      continue;
    }

    const charBudget = Math.max(240, Math.floor(tokenBudget * 3));
    for (let start = 0; start < paragraph.length; start += charBudget) {
      chunks.push(paragraph.slice(start, start + charBudget).trim());
      if (chunks.length >= maxChunks) {
        return chunks;
      }
    }
  }

  pushCurrent();
  return chunks.slice(0, maxChunks);
};

export const extractJsonPayload = (rawText) => {
  const text = normalizeString(rawText).replace(/^\uFEFF/, "");
  if (!text) return null;

  const direct = maybeJsonParse(text);
  if (direct) return direct;

  const fencedMatch = text.match(/```(?:json)?\s*([\s\S]*?)```/i);
  if (fencedMatch?.[1]) {
    const parsed = maybeJsonParse(fencedMatch[1].trim());
    if (parsed) return parsed;
  }

  const objectStart = text.indexOf("{");
  const arrayStart = text.indexOf("[");
  if (arrayStart !== -1 && (objectStart === -1 || arrayStart < objectStart)) {
    const parsed = maybeJsonParse(text.slice(arrayStart, text.lastIndexOf("]") + 1));
    if (parsed) return parsed;
  }

  const objectMatch = text.match(/\{[\s\S]*\}/);
  if (objectMatch?.[0]) {
    const parsed = maybeJsonParse(objectMatch[0]);
    if (parsed) return parsed;
  }

  const arrayMatch = text.match(/\[[\s\S]*\]/);
  if (arrayMatch?.[0]) {
    const parsed = maybeJsonParse(arrayMatch[0]);
    if (parsed) return parsed;
  }

  return null;
};

const isObject = (value) => Boolean(value && typeof value === "object" && !Array.isArray(value));
const hasText = (value) => normalizeString(value).length > 0;

const taskValidators = {
  actions: (payload) =>
    Array.isArray(payload?.topics) &&
    payload.topics.some((topic) => hasText(topic?.title) && Array.isArray(topic?.actions)),
  autoJumpForward: (payload) =>
    hasText(payload?.summary) || Array.isArray(payload?.events) || isObject(payload?.catalyst),
  catalystCreation: (payload) =>
    hasText(payload?.title) || hasText(payload?.premise) || hasText(payload?.opening),
  catalystExecutor: (payload) => hasText(payload?.summary),
  catalystSummary: (payload) => hasText(payload?.title) || hasText(payload?.description),
  descriptionToAction: (payload) => hasText(payload?.title) || hasText(payload?.text),
  eventConsolidator: (payload) => hasText(payload?.summary),
  gameMaster: (payload) => hasText(payload?.summary) || isObject(payload?.impacts),
  jumpForward: (payload) =>
    hasText(payload?.summary) || Array.isArray(payload?.events) || isObject(payload?.catalyst),
  nextSpeaker: (payload) => hasText(payload?.nextSpeaker),
};

export const validateTaskPayload = (taskKey, payload) => {
  if (!payload) return false;
  const validator = taskValidators[taskKey];
  return validator ? validator(payload) : isObject(payload) || Array.isArray(payload);
};

export const resolveJsonPayloadOrFallback = ({
  fallback,
  rawText,
  taskKey = "",
  validator,
} = {}) => {
  const parsed = extractJsonPayload(rawText);
  const isValid = typeof validator === "function"
    ? validator(parsed)
    : validateTaskPayload(taskKey, parsed);

  if (isValid) {
    return {
      fallbackUsed: false,
      payload: parsed,
    };
  }

  return {
    fallbackUsed: true,
    payload: fallback(),
  };
};

export const buildApplePromptEnvelope = ({
  history = [],
  responseFormat = "text",
  systemPrompt = "",
  taskKey = "",
  userMessage = "",
} = {}) => {
  const formatInstruction =
    responseFormat === "json"
      ? "Return one strict JSON object only. Do not include Markdown, prose, code fences, or comments."
      : "Return concise in-game prose only.";

  const responseBudget = getAppleResponseTokenBudget(taskKey, responseFormat);
  const inputBudget = getAppleInputTokenBudget(taskKey, responseFormat);
  const systemBudget = Math.floor(inputBudget * 0.58);
  const userBudget = Math.floor(inputBudget * 0.18);
  const historyBudget = Math.max(120, inputBudget - systemBudget - userBudget - 160);
  const compactHistory = (Array.isArray(history) ? history : [])
    .slice(-6)
    .map((entry) => `${entry.role || "message"}: ${entry.text || entry.content || ""}`)
    .join("\n");

  const envelope = [
    "Pax Historia on-device generation request.",
    taskKey ? `Task: ${taskKey}` : "",
    `Context window: ${APPLE_CONTEXT_WINDOW_TOKENS} tokens. Reserve ${responseBudget} tokens for the response.`,
    formatInstruction,
    "",
    "System context:",
    clampPromptTextToTokenBudget(systemPrompt, systemBudget, "[System context trimmed for Apple Foundation Models.]"),
    compactHistory ? "\nRecent turns:" : "",
    compactHistory
      ? clampPromptTextToTokenBudget(compactHistory, historyBudget, "[History trimmed for Apple Foundation Models.]")
      : "",
    "",
    "Player/game request:",
    clampPromptTextToTokenBudget(userMessage, userBudget, "[Request trimmed for Apple Foundation Models.]"),
  ]
    .filter(Boolean)
    .join("\n");

  return clampPromptTextToTokenBudget(envelope, inputBudget, "[Envelope trimmed for Apple Foundation Models.]");
};
