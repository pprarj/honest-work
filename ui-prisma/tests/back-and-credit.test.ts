// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

// Fase 33 etapa 1 (V064): the "back home" line and the rank-credit text (D262).
// Run: node --test tests/back-and-credit.test.ts   (Node 22.18+ strips the types itself)
import test from "node:test";
import assert from "node:assert/strict";
import { backLine, creditLine } from "../src/model.ts";

const row = (hoursLeft: number) => ({ name: "Dagny", hoursLeft }) as never;

test("BAC01 the back line names the worker and says the batch is ready", () => {
  const line = backLine(row(0));
  console.log("MEDIDA BAC01", line);
  assert.match(line, /Dagny is back home/);
  assert.match(line, /ready to collect/);
});

test("BAC02 the credit text says where the count came from, never contradicts it", () => {
  const withCredit = creditLine(15, row(0));
  const none = creditLine(0, row(0));
  console.log("MEDIDA BAC02", withCredit, "|", none);
  assert.match(withCredit, /15 contract\(s\) of experience/);
  assert.match(withCredit, /None settled with you yet/);
  assert.equal(none, "No contract settled yet.");
});

test("BAC03 the back line names the place Papyrus put in the state (D309)", () => {
  const at = { name: "Jenassa", hoursLeft: -2, state: "Awaiting pickup at The Drunken Huntsman" } as never;
  const line = backLine(at);
  console.log("MEDIDA BAC03", line);
  assert.equal(line, "Jenassa is back at The Drunken Huntsman - the batch is ready to collect.");
  assert.doesNotMatch(line, /back home/);
});
