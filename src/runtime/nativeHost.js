export const NATIVE_JSON_PREFIX = "native-json:";

const DEFAULT_SCENARIO = {
  accentColor: "#c49a35",
  assetStatus: {
    cities: true,
    colors: true,
    countries: true,
    regions: true,
  },
  baseSaveId: "save0",
  cacheToken: "native-save0",
  canDelete: false,
  countryNameOverrides: {},
  description: "Bundled modern-day scenario for the native Apple build.",
  eyebrow: "Apple Native",
  heroSubtitle: "Runs from the app bundle with on-device AI when Apple Intelligence is available.",
  heroTitle: "Modern Day",
  id: "default",
  name: "Modern Day",
  subtitle: "Bundled save0 configuration",
};

const DEFAULT_RUNTIME_GAME = {
  country: "Germany",
  difficulty: "standard",
  gameDate: "2030-09-15",
  language: "English",
  round: 1,
  startDate: "2025-03-25",
};

const DEFAULT_GAME = {
  cacheToken: "native-game",
  canDelete: false,
  coverImageUrl: "./loading_screen.jpg",
  country: DEFAULT_RUNTIME_GAME.country,
  currentDate: DEFAULT_RUNTIME_GAME.gameDate,
  createdAt: new Date(0).toISOString(),
  description: "Local native campaign state stored in this WebView.",
  id: "native-game",
  name: "Native Campaign",
  scenarioId: "default",
  subtitle: "Apple Foundation Models host",
  updatedAt: new Date(0).toISOString(),
};

const NATIVE_JSON_PATHS = {
  actions: "saves/save0/storage/actions.json",
  advisor: "saves/save0/storage/advisor.json",
  chat: "saves/save0/storage/chat.json",
  colors: "assets/colors.json",
  events: "saves/save0/storage/events.json",
  game: "saves/save0/game.json",
  prompts: "saves/save0/prompts.json",
  world: "saves/save0/world.json",
};

const NATIVE_JSON_DEFAULTS = {
  actions: [],
  advisor: [],
  chat: [],
  colors: {},
  events: [],
  game: DEFAULT_RUNTIME_GAME,
  prompts: {},
  world: {},
};

const nativeStorageKey = (key) => `pax-native-json:${key}`;

const readStoredNativeJson = (key) => {
  if (typeof localStorage === "undefined") return null;

  try {
    const stored = localStorage.getItem(nativeStorageKey(key));
    return stored ? JSON.parse(stored) : null;
  } catch {
    return null;
  }
};

const resolveNativeFallback = (key, defaultValue) => {
  const nativeDefault = NATIVE_JSON_DEFAULTS[key];
  if (defaultValue === undefined) {
    return nativeDefault;
  }

  if (key === "game") {
    return {
      ...defaultValue,
      ...DEFAULT_RUNTIME_GAME,
    };
  }

  return defaultValue;
};

const getNativeRuntimeGame = () => ({
  ...DEFAULT_RUNTIME_GAME,
  ...(readStoredNativeJson("game") ?? {}),
});

const getNativeGameSummary = () => {
  const runtimeGame = getNativeRuntimeGame();
  return {
    ...DEFAULT_GAME,
    country: runtimeGame.country || DEFAULT_RUNTIME_GAME.country,
    currentDate: runtimeGame.gameDate || DEFAULT_RUNTIME_GAME.gameDate,
    round:
      Number.isFinite(Number(runtimeGame.round)) && Number(runtimeGame.round) > 0
        ? Math.trunc(Number(runtimeGame.round))
        : 1,
  };
};

export const isAppleNativeHost = () => {
  if (typeof window === "undefined") return false;
  return Boolean(
    window.__PAX_APPLE_HOST__ ||
      window.__PAX_NATIVE_RUNTIME__?.mode === "apple" ||
      window.webkit?.messageHandlers?.foundationModel,
  );
};

export const makeNativeJsonUrl = (key) => `${NATIVE_JSON_PREFIX}${key}`;
export const isNativeJsonUrl = (url) => String(url ?? "").startsWith(NATIVE_JSON_PREFIX);
export const getNativeJsonKey = (url) => String(url ?? "").slice(NATIVE_JSON_PREFIX.length);

export const resolveBundledAssetUrl = (relativePath) => {
  if (typeof window === "undefined") return relativePath;
  return new URL(relativePath.replace(/^\.\//, ""), window.location.href).toString();
};

const cloneJson = (value) => {
  if (value == null) return value;
  if (typeof structuredClone === "function") {
    return structuredClone(value);
  }

  return JSON.parse(JSON.stringify(value));
};

export const readNativeJson = async (url, { defaultValue } = {}) => {
  const key = getNativeJsonKey(url);
  const fallback = resolveNativeFallback(key, defaultValue);

  if (typeof localStorage !== "undefined") {
    const stored = localStorage.getItem(nativeStorageKey(key));
    if (stored !== null) {
      try {
        return JSON.parse(stored);
      } catch {
        localStorage.removeItem(nativeStorageKey(key));
      }
    }
  }

  const sourcePath = NATIVE_JSON_PATHS[key];
  if (!sourcePath) {
    return cloneJson(fallback);
  }

  try {
    const response = await fetch(resolveBundledAssetUrl(sourcePath), { cache: "force-cache" });
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }

    const data = await response.json();
    if (typeof localStorage !== "undefined") {
      localStorage.setItem(nativeStorageKey(key), JSON.stringify(data));
    }
    return data;
  } catch {
    return cloneJson(fallback);
  }
};

export const writeNativeJson = async (url, data) => {
  const key = getNativeJsonKey(url);
  if (typeof localStorage !== "undefined") {
    localStorage.setItem(nativeStorageKey(key), JSON.stringify(data));
    localStorage.setItem("pax-native-cache-token", Date.now().toString(36));
  }

  return cloneJson(data);
};

export const getNativeLibraryCatalog = () => {
  const token =
    typeof localStorage !== "undefined"
      ? localStorage.getItem("pax-native-cache-token") || "native-save0"
      : "native-save0";
  const game = getNativeGameSummary();

  return {
    activeGameId: game.id,
    baseSaves: ["save0"],
    games: [{ ...game, cacheToken: token }],
    runtimeScenario: { ...DEFAULT_SCENARIO, cacheToken: token },
    scenarios: [{ ...DEFAULT_SCENARIO, cacheToken: token }],
    selectedScenarioId: DEFAULT_SCENARIO.id,
    token,
  };
};

export const requestNativeJson = async (pathname, { body, method = "GET" } = {}) => {
  if (pathname === "/api/library" || pathname === "/api/scenarios" || pathname === "/api/games") {
    return getNativeLibraryCatalog();
  }

  if (pathname === "/api/scenarios/active" || pathname === "/api/scenarios/selected" || pathname === "/api/games/active") {
    return getNativeLibraryCatalog();
  }

  if (pathname.startsWith("/api/scenarios/default") || pathname.startsWith("/api/games/native-game")) {
    return pathname.startsWith("/api/games/")
      ? { ...getNativeGameSummary(), ...(body ?? {}) }
      : { ...DEFAULT_SCENARIO, ...(body ?? {}) };
  }

  if (method === "POST" || method === "PUT" || method === "DELETE") {
    return getNativeLibraryCatalog();
  }

  throw new Error("This library operation is not available in the bundled Apple build.");
};
