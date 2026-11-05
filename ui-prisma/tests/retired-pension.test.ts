// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

// Fase 31 conserto 1 (RET01-RET03): the retired worker's row, the pension hint and the statement line (D257).
// Run: node --test tests/retired-pension.test.ts   (Node 22.18+ strips the types itself)
import test from "node:test";
import assert from "node:assert/strict";
import { isRetired, outcomeText, pensionHint, stateTone, wordJournal } from "../src/model.ts";

const row = (state: string) => ({ state }) as never;

test("RET01 the label Papyrus words marks the worker as retired, in the colour of someone gone", () => {
  console.log("MEDIDA RET01", isRetired(row("Retired - hurt at work")), isRetired(row("Injured")), stateTone("Retired - hurt at work"));
  assert.equal(isRetired(row("Retired - hurt at work")), true);
  assert.equal(isRetired(row("Injured")), false);
  assert.equal(isRetired(undefined), false);
  assert.equal(stateTone("Retired - hurt at work"), "gone");
});

test("RET02 the pension hint carries the amount; the history says the cause", () => {
  console.log("MEDIDA RET02", pensionHint(1500), "|", pensionHint(0), "|", outcomeText("MAJOR"));
  assert.match(pensionHint(1500), /1,?500/);
  assert.match(pensionHint(undefined), /Releases the place/);
  assert.equal(outcomeText("MAJOR"), "Retired, badly hurt");
});

test("RET03 the statement words the pension as gold spent", () => {
  const w = wordJournal({ day: 3, kind: "PENSIONED", name: "Asa", taskId: "", qty: 0, gold: 4500 }, []);
  console.log("MEDIDA RET03", w.text, w.amount, w.tone);
  assert.equal(w.text, "Asa was pensioned off");
  assert.equal(w.amount, -4500);
  assert.equal(w.tone, "spent");
});
