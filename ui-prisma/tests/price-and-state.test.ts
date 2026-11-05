// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

// Fase 33 etapa 10 (V073): the contract price is visible and is the charged sum; every task has a
// state (a tag for every reason, "None here" for a hold with no source, never a silent gap); the
// tag fits the card; the hold in the header is the worker's; a second cook shows greyed.
// Run: node --test tests/*.test.ts   (Node 22.18+ strips the types itself)
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  blockedText,
  contractCost,
  contractRange,
  contractText,
  goldWhole,
  isKnownReason,
  noSource,
  rowFor,
  sourceIndex,
  sourceTag,
  sourceText,
  wholeGold,
} from "../src/model.ts";

const read = (p: string) => readFileSync(new URL(p, import.meta.url), "utf8");
const css = read("../src/style.css");
const contracts = read("../src/views/ContractsView.tsx");
const recruitView = read("../src/views/RecruitView.tsx");

function rule(selector: string): string {
  const at = css.indexOf(`\n${selector} {`);
  assert.ok(at >= 0, `rule ${selector} exists`);
  return css.slice(at, css.indexOf("}", at));
}

const task = (over: Record<string, unknown> = {}) =>
  ({
    id: "mine_iron",
    profession: "miner",
    label: "Mine iron",
    minTier: "apprentice",
    minTierLabel: "Apprentice",
    hours: 6,
    batchMin: 2,
    batchMax: 4,
    incidentChance: 0.1,
    basePricePerUnit: 77.6219,
    ingredientCostPerUnit: 10.5,
    priceMultiplier: 1.4,
    ...over,
  }) as never;
const row = (over: Record<string, unknown> = {}) =>
  ({ taskId: "mine_iron", veins: 0, units: -1, reason: "NONE", ...over }) as never;

// --- F1: the price ------------------------------------------------------------

test("PST01 the estimate is the charged sum: every shared vector", () => {
  let n = 0;
  for (const line of read("../../plugin-skse/tests/fixtures/contract_cost_vectors.txt").split(/\r?\n/)) {
    const t = line.trim();
    if (!t || t.startsWith("#")) continue;
    const [units, ref, mult, ing, expected] = t.split(/\s+/).map(Number);
    assert.equal(contractCost(units, ref, mult, ing), expected, t);
    n += 1;
  }
  console.log("MEDIDA PST01 vectors", n);
  assert.ok(n >= 5);
});

test("PST02 the range is the smallest and the largest lot, the same sum", () => {
  const t = task();
  const [lo, hi] = contractRange(t);
  assert.equal(lo, contractCost(2, 77.6219, 1.4, 10.5));
  assert.equal(hi, contractCost(4, 77.6219, 1.4, 10.5));
  assert.equal(contractText(t), `Contract: ~${lo}-${hi} gold`);
  console.log("MEDIDA PST02", contractText(t));
});

test("PST03 one lot size is one figure; no price is no line; a bad ingredient is no line", () => {
  assert.match(contractText(task({ batchMin: 3, batchMax: 3 })), /^Contract: ~\d[\d,]* gold$/);
  assert.equal(contractText(task({ basePricePerUnit: 0 })), "");
  assert.equal(contractText(task({ ingredientCostPerUnit: -1 })), "");
});

test("PST04 gold is whole, rounded up: every shared rounding vector", () => {
  let n = 0;
  for (const line of read("../../plugin-skse/tests/fixtures/gold_rounding_vectors.txt").split(/\r?\n/)) {
    const t = line.trim();
    if (!t || t.startsWith("#")) continue;
    const [input, expected] = t.split(/\s+/).map(Number);
    assert.equal(wholeGold(input), expected, t);
    // the float32 the DLL sends rounds to the same gold (the 0.001 is wider than the noise)
    assert.equal(wholeGold(Math.fround(input)), expected, `${t} (float32)`);
    n += 1;
  }
  console.log("MEDIDA PST04 vectors", n);
  assert.ok(n >= 15);
});

test("PST05 the page prints a price with no decimal, and says so in the contract line", () => {
  assert.equal(goldWhole(1.65), "2");
  assert.equal(goldWhole(Math.fround(2.47)), "3");
  assert.equal(goldWhole(8), "8");
  assert.equal(goldWhole(1234), "1,234");
  assert.equal(goldWhole(0), "0");
  assert.match(contracts, /goldWhole\(task\.basePricePerUnit\)/);
  assert.match(contracts, /goldWhole\(task\.ingredientCostPerUnit/);
  assert.match(contracts, /contractText\(task\)/);
  assert.doesNotMatch(contracts, /goldUnit|money\(/);
});

test("PST05b no figure of the page can carry a decimal in gold", () => {
  // every gold the views print goes through gold() (rounds) or goldWhole(); toFixed on a price is a decimal
  for (const view of ["ContractsView", "WorkerView", "Overview", "Sidebar", "RecruitView"]) {
    assert.doesNotMatch(read(`../src/views/${view}.tsx`), /toFixed|maximumFractionDigits/, view);
  }
  assert.doesNotMatch(read("../src/model.ts"), /toFixed|maximumFractionDigits/);
});

// --- F3: a state for every task -----------------------------------------------

test("PST06 a tag for every reason, a generic one for an unknown reason", () => {
  const reasons: [string, string][] = [
    ["OCCUPIED", "Held"],
    ["Unconfirmed", "Unchecked"],
    ["depleted", "Worked out"],
    ["NONE", "None here"],
    ["SOMETHING_NEW", "Unknown"],
  ];
  for (const [reason, label] of reasons) {
    assert.equal(sourceTag(row({ reason }))?.label, label, reason);
  }
  assert.equal(sourceTag(row({ veins: 2, units: 10, reason: "" }))?.label, "Available");
  assert.equal(sourceTag(row({ veins: 0, units: -1, reason: "" }), false, true)?.label, "Unknown");
  assert.equal(isKnownReason(row({ reason: "SOMETHING_NEW" })), false);
});

test("PST07 a task with no row is Unknown once the list has arrived, nothing before", () => {
  assert.equal(sourceTag(undefined), null);
  assert.equal(sourceTag(undefined, false, true)?.label, "Unknown");
  assert.equal(sourceTag(undefined, true, true)?.label, "Locked");
});

test("PST08 the id matches without case: iron and silver kept their tag", () => {
  const index = sourceIndex([row({ taskId: "Mine_Iron", reason: "", veins: 3, units: 12 })]);
  assert.equal(rowFor(index, task({ id: "mine_iron" }))?.veins, 3);
  assert.equal(rowFor(index, task({ id: "MINE_IRON" }))?.veins, 3);
});

test("PST09 holdSources 0 gives the task its own None here row, no source disables the button", () => {
  const index = sourceIndex([]);
  const synthesized = rowFor(index, task({ holdSources: 0 }));
  assert.equal(sourceTag(synthesized)?.label, "None here");
  assert.equal(noSource(synthesized), true);
  // No row and no holdSources (an older DLL): nothing is invented.
  assert.equal(rowFor(index, task()), undefined);
  assert.equal(noSource(undefined), false);
  assert.equal(noSource(row({ reason: "depleted" })), false);
  // The button is off for it, with the disabled attribute, before any enabled button is reached.
  const at = contracts.indexOf("noSource(row)");
  const enabled = contracts.indexOf("hw-button is-primary hw-button-wide");
  assert.ok(at > 0 && enabled > at, `noSource at ${at}, primary button at ${enabled}`);
  assert.match(contracts.slice(at, enabled), /disabled/);
});

test("PST10 None here is worded in the words of the work", () => {
  const want: Record<string, string> = {
    miner: "nothing to mine in Whiterun",
    hunter: "nothing to hunt in Whiterun",
    herbalist: "nothing to gather in Whiterun",
    fisher: "nothing to fish in Whiterun",
    laborer: "nothing to work in Whiterun",
    cook: "nowhere to cook in Whiterun",
  };
  for (const [profession, text] of Object.entries(want)) {
    assert.equal(sourceText(row({ veins: -2 }), "Whiterun", profession), text, profession);
  }
  // Without a profession the old wording stays (reason-case.test.ts).
  assert.equal(sourceText(row(), "Whiterun"), "nothing to mine in Whiterun");
});

test("PST11 an unknown reason is worded, never printed bare and never dropped", () => {
  const said = sourceText(row({ reason: "SOMETHING_NEW" }), "Whiterun", "miner");
  assert.ok(said.length > 0);
  assert.match(said, /SOMETHING_NEW/);
  assert.match(contracts, /HostBridge\.note\(/);
});

// --- F4: the hold in the header ----------------------------------------------

test("PST12 the header names the worker's own hold before the source list's", () => {
  assert.match(contracts, /worker\.hold \|\| sources\?\.hold \|\| ""/);
});

// --- F2: the tag fits the card ------------------------------------------------

test("PST13 the tag is the label alone; the forecast is a line of its own", () => {
  const meta = contracts.slice(contracts.indexOf('className="hw-node-meta"'), contracts.indexOf("hw-node-hint"));
  assert.doesNotMatch(meta, /tag\.hint \?/);
  assert.match(contracts, /<span className="hw-node-hint">\{tag\.hint\}<\/span>/);
  assert.match(rule(".hw-node-hint"), /overflow-wrap:\s*anywhere/);
});

test("PST14 the duration keeps its room and the pair wraps instead of overflowing", () => {
  assert.match(rule(".hw-node-hours"), /white-space:\s*nowrap/);
  assert.match(rule(".hw-node-hours"), /flex:\s*0 0 auto/);
  assert.match(rule(".hw-node-meta"), /flex-wrap:\s*wrap/);
});

// --- one cook per hold: the Recruit card --------------------------------------

test("PST15 a blocked candidate is greyed with the reason and cannot be hired", () => {
  assert.equal(blockedText({ blocked: "COOK_HOLD" }), "You already employ a cook in this hold.");
  assert.equal(blockedText({ blocked: "cook_hold" }), "You already employ a cook in this hold.");
  assert.equal(blockedText({}), "");
  assert.equal(blockedText({ blocked: "" }), "");
  assert.match(blockedText({ blocked: "NEW_RULE" }), /NEW_RULE/);
  assert.match(recruitView, /is-blocked/);
  assert.match(recruitView, /disabled=\{full \|\| !!blockedText\(c\)\}/);
  assert.match(rule(".hw-candidate.is-blocked"), /opacity/);
});
