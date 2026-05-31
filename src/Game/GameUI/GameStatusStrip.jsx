import React from "react";
import { getAIHealthSummary } from "../AI/aiHealth.js";
import {
  normalizeActions,
  normalizeEvents,
  readActionsState,
  readEventsState,
  readGameData,
} from "../../runtime/gameState.js";

const formatDate = (value) => {
  if (!value) return "No date";
  try {
    return new Intl.DateTimeFormat(undefined, { dateStyle: "medium" }).format(new Date(value));
  } catch {
    return value;
  }
};

const pillStyle = {
  alignItems: "center",
  background: "rgba(255,255,255,0.06)",
  border: "1px solid rgba(255,255,255,0.08)",
  borderRadius: "999px",
  display: "inline-flex",
  gap: "0.32rem",
  minWidth: 0,
  padding: "0.35rem 0.62rem",
};

const statusColors = {
  guarded: "#fca5a5",
  healthy: "#86efac",
  watching: "#fde68a",
};

export const GameStatusStrip = ({
  onOpenActions,
  onOpenAdvisor,
  onOpenCountryChooser,
  topOffset = "4.75rem",
}) => {
  const [snapshot, setSnapshot] = React.useState({
    actions: [],
    ai: getAIHealthSummary(),
    events: [],
    game: {},
  });

  React.useEffect(() => {
    let cancelled = false;

    const refresh = async () => {
      const [game, actions, events] = await Promise.all([
        readGameData({ force: true }),
        readActionsState({ force: true }),
        readEventsState({ force: true }),
      ]);

      if (!cancelled) {
        setSnapshot({
          actions: normalizeActions(actions),
          ai: getAIHealthSummary(),
          events: normalizeEvents(events),
          game,
        });
      }
    };

    refresh().catch(() => {});
    const interval = window.setInterval(() => refresh().catch(() => {}), 5000);
    const refreshAI = () => setSnapshot((current) => ({ ...current, ai: getAIHealthSummary() }));
    window.addEventListener("pax-ai-health-change", refreshAI);
    window.addEventListener("pax-game-state-change", refresh);

    return () => {
      cancelled = true;
      window.clearInterval(interval);
      window.removeEventListener("pax-ai-health-change", refreshAI);
      window.removeEventListener("pax-game-state-change", refresh);
    };
  }, []);

  const plannedActions = snapshot.actions.filter((action) => action.status === "planned");
  const lastEvent = snapshot.events.at(-1);
  const aiColor = statusColors[snapshot.ai.status] ?? statusColors.healthy;

  return (
    <div
      data-compact-hide="mobile"
      style={{
        alignItems: "center",
        backdropFilter: "blur(10px)",
        background: "rgba(8, 10, 17, 0.82)",
        border: "1px solid rgba(255,255,255,0.08)",
        borderRadius: "999px",
        boxShadow: "0 14px 36px rgba(0,0,0,0.3)",
        color: "rgba(255,255,255,0.88)",
        display: "flex",
        fontFamily: "sans-serif",
        fontSize: "0.75rem",
        gap: "0.45rem",
        left: "50%",
        maxWidth: "min(42rem, calc(100vw - 27rem))",
        minHeight: "2.4rem",
        overflow: "hidden",
        padding: "0.32rem",
        pointerEvents: "auto",
        position: "fixed",
        top: `calc(${topOffset} + 0.55rem)`,
        transform: "translateX(-50%)",
        whiteSpace: "nowrap",
        zIndex: 9997,
      }}
    >
      <button
        data-testid="country-chooser-toggle"
        onClick={onOpenCountryChooser}
        style={{
          ...pillStyle,
          color: "rgba(255,255,255,0.9)",
          cursor: "pointer",
          font: "inherit",
          maxWidth: "13rem",
        }}
        title="Choose player country"
        type="button"
      >
        <strong style={{ color: "white" }}>{snapshot.game.country || "Choose nation"}</strong>
        <span style={{ color: "rgba(255,255,255,0.52)", overflow: "hidden", textOverflow: "ellipsis" }}>
          R{snapshot.game.round || 1} · {formatDate(snapshot.game.gameDate)}
        </span>
      </button>

      <button
        onClick={onOpenActions}
        style={{
          ...pillStyle,
          color: "rgba(255,255,255,0.9)",
          cursor: "pointer",
          font: "inherit",
        }}
        type="button"
      >
        {plannedActions.length} planned
      </button>

      <button
        onClick={onOpenAdvisor}
        style={{
          ...pillStyle,
          color: aiColor,
          cursor: "pointer",
          font: "inherit",
          textTransform: "capitalize",
        }}
        type="button"
      >
        AI {snapshot.ai.status}
      </button>

      {lastEvent && (
        <div style={{ ...pillStyle, minWidth: 0 }}>
          <span style={{ color: "rgba(255,255,255,0.52)" }}>Latest</span>
          <span style={{ overflow: "hidden", textOverflow: "ellipsis" }}>{lastEvent.title}</span>
        </div>
      )}
    </div>
  );
};
