// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

// Fase 35 etapa 7 (GRD04-GRD05): the guard mark compared without case, and the reason
// "With bodyguard" is off.
// Run: node --test tests/guard-selector.test.ts   (Node 22.18+ strips the types itself)
import test from "node:test";
import assert from "node:assert/strict";
import { guardBlockText, sameId } from "../src/model.ts";

test("GRD04 the mark GUARD is found in the case the game sends back", () => {
  assert.ok(sameId("Guard", "GUARD"));
  assert.ok(sameId("GUARD", "GUARD"));
  assert.ok(sameId(" guard ", "GUARD"));
  assert.ok(!sameId("", "GUARD"));
  assert.ok(!sameId(undefined, "GUARD"));
  assert.ok(!sameId("NOT_UNIQUE", "GUARD"));
});

test("GRD05 With bodyguard is off, with the reason, for a cook and when no guard is free", () => {
  const row = (refused: string, place: string) => ({ refused, place });
  const free = { followers: [row("Guard", "Waits at Whiterun")] };
  const busy = { followers: [row("Guard", "Escorting Belrand")] };
  const none = { followers: [row("", "With you")] };
  assert.equal(guardBlockText(free, "miner"), "");
  assert.ok(guardBlockText(busy, "miner").includes("No bodyguard is free"));
  assert.ok(guardBlockText(none, "miner").includes("No bodyguard is free"));
  assert.ok(guardBlockText(free, "Cook").includes("cook"));
  assert.equal(guardBlockText(null, "miner"), "");
  assert.equal(guardBlockText({ followers: [], needsPo3: true }, "miner"), "");
});

test("GRD06 firewood takes no escort, by task and not by profession (Fase 35 etapa 10)", () => {
  const free = { followers: [{ refused: "Guard", place: "Waits at Whiterun" }] };
  assert.ok(guardBlockText(free, "laborer", "labor_firewood").includes("no bodyguard needed"));
  assert.ok(guardBlockText(free, "laborer", "LABOR_FIREWOOD").includes("chopping block"));
  assert.equal(guardBlockText(free, "laborer", "labor_stone"), "");
  assert.equal(guardBlockText(free, "miner", "mine_iron"), "");
});
