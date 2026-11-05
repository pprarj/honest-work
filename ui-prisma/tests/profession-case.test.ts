// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

// Fase 33 etapa 3 (PCA01-PCA04): the game sends the profession as "Cook" / "Miner"; the
// house picker and its buttons must show anyway (V066: they compared with "cook").
// Run: node --test tests/profession-case.test.ts   (Node 22.18+ strips the types itself)
import test from "node:test";
import assert from "node:assert/strict";
import { isProfession, parseHouse, recruitShowsHouse, workerShowsHouse } from "../src/model.ts";

const two = parseHouse("breezehome", "breezehome|tundra_homestead", 1);
const one = parseHouse("breezehome", "breezehome", 1);

test("PCA01 isProfession ignores case, both sides", () => {
  const r = [isProfession("Cook", "cook"), isProfession("cook", "cook"), isProfession("COOK", "Cook"), isProfession("Miner", "cook"), isProfession(undefined, "cook")];
  console.log("MEDIDA PCA01", JSON.stringify(r));
  assert.deepEqual(r, [true, true, true, false, false]);
});

test("PCA02 Recruit tab: picker shows with a capitalized Cook and two houses", () => {
  const list = [{ profession: "Miner" }, { profession: "Cook" }];
  const r = [recruitShowsHouse(true, two, list), recruitShowsHouse(true, one, list), recruitShowsHouse(true, two, [{ profession: "Miner" }]), recruitShowsHouse(false, two, list)];
  console.log("MEDIDA PCA02", JSON.stringify(r));
  assert.deepEqual(r, [true, false, false, false]);
});

test("PCA03 cook tab: buttons show for Cook with two houses, not for Miner, not with one house", () => {
  const r = [workerShowsHouse("Cook", two), workerShowsHouse("cook", two), workerShowsHouse("Miner", two), workerShowsHouse("Cook", one), workerShowsHouse("Cook", undefined)];
  console.log("MEDIDA PCA03", JSON.stringify(r));
  assert.deepEqual(r, [true, true, false, false, false]);
});

test("PCA04 house ids from the game are lower-cased by parseHouse", () => {
  const h = parseHouse("Breezehome", "Breezehome|Tundra_Homestead", 0);
  console.log("MEDIDA PCA04", JSON.stringify(h));
  assert.deepEqual(h, { current: "breezehome", owned: ["breezehome", "tundra_homestead"], open: false });
});
