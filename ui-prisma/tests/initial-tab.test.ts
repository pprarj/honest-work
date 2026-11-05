// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

// Fase 30 (TAB01-TAB03): the tab the panel opens on, by what the workers are doing.
// Run: node --test tests/initial-tab.test.ts   (Node 22.18+ strips the types itself)
import test from "node:test";
import assert from "node:assert/strict";
import { initialTabFor } from "../src/model.ts";

// Only the fields initialTabFor reads; hoursLeft -1 = no contract, >= 0 = running,
// -2..-4 = pickup codes of a finished contract.
const row = (slot: number, hoursLeft: number, canIssue: boolean): any => ({ slot, hoursLeft, canIssue });

test("TAB01 nobody hired: Overview", () => {
  const a = initialTabFor([]);
  const b = initialTabFor(null);
  console.log("MEDIDA TAB01", JSON.stringify(a), JSON.stringify(b));
  assert.deepEqual(a, { tab: "overview", slot: null });
  assert.deepEqual(b, { tab: "overview", slot: null });
});

test("TAB02 a worker has a contract running: Worker, on that worker", () => {
  const rows = [row(0, -1, true), row(1, 5, false), row(2, -1, true)];
  const r = initialTabFor(rows);
  const done = initialTabFor([row(0, -1, true), row(1, -2, false)]);
  console.log("MEDIDA TAB02", JSON.stringify(r), JSON.stringify(done));
  assert.deepEqual(r, { tab: "worker", slot: 1 });
  assert.deepEqual(done, { tab: "worker", slot: 1 });
});

test("TAB03 hired but none has a contract: Contracts, on the one who can take one", () => {
  const rows = [row(0, -1, false), row(1, -1, true)];
  const r = initialTabFor(rows);
  const none = initialTabFor([row(3, -1, false)]);
  console.log("MEDIDA TAB03", JSON.stringify(r), JSON.stringify(none));
  assert.deepEqual(r, { tab: "contracts", slot: 1 });
  assert.deepEqual(none, { tab: "contracts", slot: 3 });
});
