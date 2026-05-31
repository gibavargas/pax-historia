const STORAGE_KEY = "pax_ai_health_v1";
const RECENT_LIMIT = 60;

const emptyMetrics = () => ({
  calls: 0,
  failures: 0,
  fallbacks: 0,
  lastError: "",
  recent: [],
});

const readMetrics = () => {
  if (typeof localStorage === "undefined") {
    return emptyMetrics();
  }

  try {
    const parsed = JSON.parse(localStorage.getItem(STORAGE_KEY) || "null");
    return parsed && typeof parsed === "object"
      ? { ...emptyMetrics(), ...parsed, recent: Array.isArray(parsed.recent) ? parsed.recent : [] }
      : emptyMetrics();
  } catch {
    return emptyMetrics();
  }
};

const writeMetrics = (metrics) => {
  if (typeof localStorage === "undefined") {
    return metrics;
  }

  localStorage.setItem(STORAGE_KEY, JSON.stringify(metrics));
  window.dispatchEvent?.(new CustomEvent("pax-ai-health-change", { detail: metrics }));
  return metrics;
};

export const recordAIResult = ({
  error = "",
  fallbackUsed = false,
  ok = true,
  provider = "",
  taskKey = "",
} = {}) => {
  const metrics = readMetrics();
  const entry = {
    at: new Date().toISOString(),
    error: String(error ?? "").slice(0, 220),
    fallbackUsed: Boolean(fallbackUsed),
    ok: Boolean(ok),
    provider,
    taskKey,
  };

  const next = {
    calls: metrics.calls + 1,
    failures: metrics.failures + (entry.ok ? 0 : 1),
    fallbacks: metrics.fallbacks + (entry.fallbackUsed ? 1 : 0),
    lastError: entry.ok && !entry.fallbackUsed ? metrics.lastError : entry.error,
    recent: [...metrics.recent, entry].slice(-RECENT_LIMIT),
  };

  return writeMetrics(next);
};

export const recordAIFallback = ({ provider = "", taskKey = "", reason = "" } = {}) =>
  recordAIResult({
    error: reason,
    fallbackUsed: true,
    ok: true,
    provider,
    taskKey,
  });

export const getAIHealthSummary = () => {
  const metrics = readMetrics();
  const recent = metrics.recent.slice(-20);
  const recentFailures = recent.filter((entry) => !entry.ok).length;
  const recentFallbacks = recent.filter((entry) => entry.fallbackUsed).length;
  const recentRisk = recent.length > 0 ? (recentFailures + recentFallbacks) / recent.length : 0;

  return {
    ...metrics,
    recentFallbacks,
    recentFailures,
    recentRisk,
    status: recentRisk >= 0.35 ? "guarded" : recentRisk > 0 ? "watching" : "healthy",
  };
};

export const shouldUseDeterministicFallback = (provider) => {
  const metrics = getAIHealthSummary();
  if (!provider || provider === "apple-foundation") {
    return false;
  }

  return metrics.recent.length >= 12 && metrics.recentRisk >= 0.5;
};

export const resetAIHealthMetrics = () => writeMetrics(emptyMetrics());
