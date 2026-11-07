// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

// Fase 35 etapa 13 (D322): the quote with and without a bodyguard shown before the order. The fee is
// the one WOSK_Guards.ContractFee charges: a share of the contract cost rounded up, never under the floor.
// Run: node --test tests/*.test.ts   (Node 22.18+ strips the types itself)
import test from "node:test";
import assert from "node:assert/strict";
import { contractRange, durationText, guardFeeFor, guardedContractText } from "../src/model.ts";

const terms = { rate: 0.25, min: 40 };
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
    ingredientCostPerUnit: 0,
    priceMultiplier: 1.0,
    ...over,
  }) as never;

test("GQ01 the fee is a quarter rounded up, with the floor of 40", () => {
  assert.equal(guardFeeFor(46, terms), 40); // 11.5 -> 12 -> floor
  assert.equal(guardFeeFor(160, terms), 40);
  assert.equal(guardFeeFor(161, terms), 41); // 40.25 -> 41
  assert.equal(guardFeeFor(400, terms), 100);
  console.log("MEDIDA GQ01 fee(46)=40 fee(161)=41 fee(400)=100");
});

test("GQ02 the guarded range is the contract range plus the fee at each end", () => {
  const t = task();
  const [lo, hi] = contractRange(t);
  const text = guardedContractText(t, terms);
  assert.equal(text, `With bodyguard: ~${lo + guardFeeFor(lo, terms)}-${hi + guardFeeFor(hi, terms)} gold`);
  console.log("MEDIDA GQ02", text);
});

test("GQ03 no terms, no price, or the firewood: no guarded line", () => {
  assert.equal(guardedContractText(task(), undefined), "");
  assert.equal(guardedContractText(task({ basePricePerUnit: 0 }), terms), "");
  assert.equal(guardedContractText(task({ id: "labor_firewood" }), terms), "");
});

test("GQ04 the firewood says 1 h, with no walk", () => {
  assert.equal(durationText(task({ id: "labor_firewood", hours: 1 }), undefined), "1 h");
});
