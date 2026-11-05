// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

// Fase 33 etapa 8 (D1, V071): the cook's kitchen is a kitchen of his own house, per type of dish,
// and the panel and the refusal say which one ran out and when it recovers.
// Run: node --test tests/*.test.ts   (Node 22.18+ strips the types itself)
import test from "node:test";
import assert from "node:assert/strict";
import { sourceText, sourceTag, wordOutcome } from "../src/model.ts";

const zone = (over: Record<string, unknown>) =>
  ({ taskId: "cook_fine", veins: -2, units: 0, reason: "DEPLETED", place: "breezehome", backInHours: 0, ...over }) as never;
const outcome = (arg: string, number: number) =>
  ({ action: "issue", code: "SOURCE", arg, number, slot: 0 }) as never;

test("KIT01 a row with units speaks of the cook's own kitchen, by name", () => {
  const said = sourceText(zone({ units: 14, reason: "" }), "Whiterun");
  console.log("MEDIDA KIT01", said);
  assert.equal(said, "~14 dish(es) left in the Breezehome kitchen");
});

test("KIT02 a worked-out kitchen says which one and when it recovers", () => {
  const said = sourceText(zone({ backInHours: 17 }), "Whiterun");
  console.log("MEDIDA KIT02", said);
  assert.match(said, /Breezehome kitchen has no more of this kind of dish/);
  assert.match(said, /back in about 17 h/);
});

test("KIT03 a worked-out kitchen without a known return does not invent one", () => {
  assert.doesNotMatch(sourceText(zone({ backInHours: 0 }), "Whiterun"), /back in/);
});

test("KIT04 a row without a house (other professions) keeps the old wording", () => {
  assert.equal(sourceText(zone({ place: "", units: 6, reason: "" }), "Whiterun"), "~6 unit(s) to gather in Whiterun");
  assert.match(sourceText(zone({ place: "", backInHours: 5 }), "Whiterun"), /worked out in Whiterun until it recovers - back in about 5 h/);
});

test("KIT05 the tag of a worked-out kitchen is Worked out, a stocked one Available", () => {
  assert.equal(sourceTag(zone({}))?.label, "Worked out");
  assert.equal(sourceTag(zone({ units: 3, reason: "" }))?.label, "Available");
});

test("KIT06 the refusal names the kitchen and the hours", () => {
  const said = wordOutcome(outcome("KITCHEN|breezehome", 9), "Eirik");
  console.log("MEDIDA KIT06", said.text);
  assert.equal(said.ok, false);
  assert.match(said.text, /The Breezehome kitchen has no more of this kind of dish/);
  assert.match(said.text, /recovers in about 9 h/);
});

test("KIT07 the refusal without hours does not say when", () => {
  assert.doesNotMatch(wordOutcome(outcome("KITCHEN|breezehome", 0), "Eirik").text, /recovers in/);
});

test("KIT08 a generic worked-out source says the wait when it is known", () => {
  assert.match(wordOutcome(outcome("DEPLETED", 6), "Eirik").text, /worked out until it recovers \(about 6 h\)/);
  assert.doesNotMatch(wordOutcome(outcome("DEPLETED", 0), "Eirik").text, /about/);
});
