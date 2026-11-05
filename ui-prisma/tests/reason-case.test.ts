// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

// Fase 33 etapa 9 (E3, V072): a reason id from Papyrus is compared without case, at one
// place (model.reasonId), and a worked-out row says when it comes back.
// Run: node --test tests/*.test.ts   (Node 22.18+ strips the types itself)
import test from "node:test";
import assert from "node:assert/strict";
import { backText, reasonId, sourceTag, sourceText, wordOutcome } from "../src/model.ts";

const row = (over: Record<string, unknown>) =>
  ({ taskId: "hunt_wolf", veins: -2, units: 0, reason: "DEPLETED", place: "", backInHours: 0, ...over }) as never;
const outcome = (arg: string, number: number) =>
  ({ action: "issue", code: "SOURCE", arg, number, slot: 0 }) as never;

const CASES = ["DEPLETED", "Depleted", "depleted", " dePleTed "];

test("RSN01 every case of a reason id is the same id", () => {
  for (const c of CASES) assert.equal(reasonId(row({ reason: c })), "DEPLETED", c);
  assert.equal(reasonId(undefined), "");
});

test("RSN02 a zone row worded the same in every case, never the raw id", () => {
  const want = sourceText(row({ reason: "DEPLETED" }), "Whiterun");
  for (const c of CASES) {
    const said = sourceText(row({ reason: c }), "Whiterun");
    console.log("MEDIDA RSN02", JSON.stringify(c), "->", said);
    assert.equal(said, want);
    assert.doesNotMatch(said, /depleted/i);
  }
});

test("RSN03 a vein row (the miner) worded the same in every case", () => {
  for (const reason of ["OCCUPIED", "Occupied", "UNCONFIRMED", "Unconfirmed", "NONE", "none", "Depleted"]) {
    const said = sourceText(row({ veins: 0, units: -1, reason }), "Whiterun");
    assert.doesNotMatch(said, /^(occupied|unconfirmed|none|depleted)$/i, `${reason} came out raw`);
  }
});

test("RSN04 the tag follows the same normalised id", () => {
  for (const c of CASES) assert.equal(sourceTag(row({ reason: c }))?.label, "Worked out", c);
  assert.equal(sourceTag(row({ reason: "Occupied" }))?.label, "Held");
});

test("RSN05 Worked out carries the forecast as the hint, only when there is one", () => {
  assert.equal(backText(row({ backInHours: 17 })), "back in about 17 h");
  assert.equal(sourceTag(row({ reason: "Depleted", backInHours: 17 }))?.hint, "back in about 17 h");
  assert.equal(sourceTag(row({ backInHours: 0 }))?.hint, undefined);
  assert.equal(backText(undefined), "");
});

test("RSN06 the miner's mined-out row says the return too", () => {
  const said = sourceText(row({ veins: 0, units: -1, backInHours: 30 }), "Whiterun");
  console.log("MEDIDA RSN06", said);
  assert.match(said, /mined out in Whiterun until it grows back - back in about 30 h/);
});

test("RSN07 the refusal is worded in any case of the id", () => {
  for (const arg of ["DEPLETED", "Depleted", "depleted"]) {
    assert.match(wordOutcome(outcome(arg, 6), "Eirik").text, /worked out until it recovers \(about 6 h\)/, arg);
  }
  assert.match(wordOutcome(outcome("kitchen|Breezehome", 9), "Eirik").text, /recovers in about 9 h/);
});
