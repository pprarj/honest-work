// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

// Fase 33 etapa 6 (D276, D277; V069 A1/A3): an empty batch keeps Collect on, and the contract
// length is whole hours - the same sum as WOSK_WorkerAliasScript.WholeHours.
// Run: node --test tests/*.test.ts   (Node 22.18+ strips the types itself)
import test from "node:test";
import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import { PICKUP_EMPTY, PICKUP_FAR, PICKUP_READY, backLine, emptyBatchHint, hoursFor, hoursText, pickupBlock, wordOutcome } from "../src/model.ts";

const row = (hoursLeft: number) => ({ name: "Eirik", state: "Awaiting pickup", hoursLeft }) as never;
const task = (hours: number) => ({ hours }) as never;
const tier = (durationMultiplier: number) => ({ durationMultiplier }) as never;

test("EMP01 a worker awaiting pickup with an empty batch does not block Collect", () => {
  assert.equal(pickupBlock(row(PICKUP_EMPTY)), "");
  console.log("MEDIDA EMP01", emptyBatchHint(row(PICKUP_EMPTY)));
  assert.match(emptyBatchHint(row(PICKUP_EMPTY)), /Eirik came back empty-handed/);
  assert.match(emptyBatchHint(row(PICKUP_EMPTY)), /closes the contract/);
});

test("EMP02 a worker too far away still blocks Collect, a ready one does not", () => {
  assert.match(pickupBlock(row(PICKUP_FAR)), /too far away/);
  assert.equal(pickupBlock(row(PICKUP_READY)), "");
  assert.equal(pickupBlock({ name: "Eirik", state: "At work", hoursLeft: PICKUP_EMPTY } as never), "");
});

test("EMP03 the back line and the answer to the order say the contract closes", () => {
  assert.match(backLine(row(PICKUP_EMPTY)), /nothing to hand over/);
  assert.match(backLine(row(PICKUP_EMPTY)), /close the contract/);
  const said = wordOutcome({ action: "collect", code: "NO_BATCH", arg: "", number: 0, slot: 0 } as never, "Eirik");
  console.log("MEDIDA EMP03", said.text);
  assert.match(said.text, /nothing to hand over/);
  assert.match(said.text, /contract is closed/);
});

test("HRS01 hours are whole: 6 h x 0.85 is 5, 10 h x 0.85 is 9 (the half goes up), 168 h x 0.8 is 134", () => {
  assert.equal(hoursFor(task(6), tier(0.85)), 5);
  assert.equal(hoursFor(task(10), tier(0.85)), 9);
  assert.equal(hoursFor(task(168), tier(0.8)), 134);
  assert.equal(hoursFor(task(12), tier(0.9)), 11);
  assert.equal(hoursFor(task(10), undefined), 10);
});

test("HRS02 never below one hour, and no decimal on screen", () => {
  assert.equal(hoursFor(task(1), tier(0.8)), 1);
  assert.equal(hoursFor(task(2), tier(0.8)), 2);
  assert.equal(hoursText(hoursFor(task(6), tier(0.85))), "5 h");
  assert.equal(hoursText(hoursFor(task(1), tier(0.8))), "1 h");
  assert.doesNotMatch(hoursText(hoursFor(task(36), tier(0.85))), /\./);
});

// The data file is part of the release archive, not of this repository: the check runs when the
// file sits at SKSE/Plugins/HonestWork/professions/00_core.json beside the checkout (an installed
// mod folder), and is skipped otherwise.
const coreUrl = new URL("../../SKSE/Plugins/HonestWork/professions/00_core.json", import.meta.url);

test("HRS03 every task and tier of the shipped data comes out whole and at least 1", { skip: !existsSync(coreUrl) }, async () => {
  const { readFileSync } = await import("node:fs");
  const core = JSON.parse(readFileSync(coreUrl, "utf-8"));
  let checked = 0;
  for (const prof of Object.values(core.professions) as any[]) {
    const tiers = Array.isArray(prof.tiers) ? prof.tiers : Object.values(prof.tiers);
    const tasks = Array.isArray(prof.tasks) ? prof.tasks : Object.values(prof.tasks);
    for (const t of tasks) {
      for (const tr of tiers) {
        const h = hoursFor(t, tr);
        assert.ok(Number.isInteger(h) && h >= 1, `${t.id} ${h}`);
        checked++;
      }
    }
  }
  console.log("MEDIDA HRS03", checked, "combinations");
  assert.ok(checked > 80);
});
