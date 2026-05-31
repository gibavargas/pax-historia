import { readGameData, writeGameData } from "./gameState.js";
import { updateActiveGameRuntimeSummary } from "./library.js";

const FALLBACK_GAME_DATE = "2016-01-01";

const normalizeString = (value) => String(value ?? "").trim();

export const selectPlayerCountry = async ({ code = "", name }) => {
  const country = normalizeString(name);
  if (!country) {
    throw new Error("Choose a country first.");
  }

  const currentGame = await readGameData({ force: true });
  const nextGame = {
    ...currentGame,
    country,
    countryCode: normalizeString(code) || currentGame.countryCode || "",
    gameDate: currentGame.gameDate || currentGame.startDate || FALLBACK_GAME_DATE,
    round: currentGame.round || 1,
  };

  const savedGame = await writeGameData(nextGame);
  updateActiveGameRuntimeSummary({
    country: savedGame.country,
    currentDate: savedGame.gameDate,
    round: savedGame.round,
  });

  if (typeof window !== "undefined") {
    window.dispatchEvent(new CustomEvent("pax-game-state-change", {
      detail: {
        country: savedGame.country,
        countryCode: savedGame.countryCode,
        gameDate: savedGame.gameDate,
        round: savedGame.round,
      },
    }));
  }

  return savedGame;
};
