import assert from "node:assert/strict";
import test from "node:test";
import {
  applyEventImpactsToWorld,
  normalizeEvents,
  normalizeWorldState,
} from "../src/runtime/gameState.js";

test("event strategic effects are normalized and persisted into world state", () => {
  const [event] = normalizeEvents([
    {
      date: "2030-02-01",
      description: "The naval readiness order changes regional calculations.",
      impacts: {
        strategicEffects: [
          {
            direction: "positive",
            magnitude: 3,
            summary: "Ports and admiralties can sustain more patrols.",
            target: "Brazil",
            track: "military-readiness",
          },
        ],
      },
      title: "Brazil expands naval readiness",
    },
  ]);

  assert.equal(event.impacts.strategicEffects.length, 1);
  assert.equal(event.impacts.strategicEffects[0].target, "Brazil");
  assert.equal(event.impacts.strategicEffects[0].magnitude, 3);

  const { world } = applyEventImpactsToWorld({
    events: [event],
    world: normalizeWorldState({ strategicEffects: [] }),
  });

  assert.equal(world.strategicEffects.length, 1);
  assert.equal(world.strategicEffects[0].eventId, event.id);
  assert.equal(world.strategicEffects[0].date, "2030-02-01");
  assert.equal(world.strategicEffects[0].track, "military-readiness");
});
