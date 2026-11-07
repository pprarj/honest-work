// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

// Fase 35 etapa 4 (GRD01-GRD03): the words of the bodyguard (answers and statement lines).
// Run: node --test tests/guard-words.test.ts   (Node 22.18+ strips the types itself)
import test from "node:test";
import assert from "node:assert/strict";
import { parseJournalLine, wordJournal, wordOutcome } from "../src/model.ts";

test("GRD01 a contract with a bodyguard says so; a refusal for lack of one says why", () => {
  const ok = wordOutcome({ action: "issue", slot: 0, code: "ISSUED", arg: "GUARD", number: 450 }, "Mira");
  const none = wordOutcome({ action: "issue", slot: 0, code: "NO_GUARD", arg: "FREE", number: 0 }, "Mira");
  const cook = wordOutcome({ action: "issue", slot: 0, code: "NO_GUARD", arg: "COOK", number: 0 }, "Mira");
  console.log("MEDIDA GRD01", ok.text, "|", none.text, "|", cook.text);
  assert.ok(ok.ok && ok.text.includes("bodyguard") && ok.text.includes("450"));
  assert.ok(!none.ok && none.text.includes("Recruit"));
  assert.ok(!cook.ok && cook.text.includes("cook"));
});

test("GRD02 the two fee lines of the statement are worded as money spent", () => {
  const fee = wordJournal(parseJournalLine("12|GUARD_FEE|Mira|mine_iron|0|113")!, []);
  const assign = wordJournal(parseJournalLine("12|GUARD_ASSIGN|Vorstag||0|600")!, []);
  console.log("MEDIDA GRD02", JSON.stringify(fee), JSON.stringify(assign));
  assert.equal(fee.amount, -113);
  assert.equal(assign.amount, -600);
  assert.equal(fee.tone, "spent");
  assert.ok(assign.text.includes("Vorstag"));
});

test("GRD04 the fee line says who guarded whom; an older line still reads", () => {
  const tasks = [{ id: "mine_iron", label: "Mine iron" }] as never;
  const novo = wordJournal(parseJournalLine("12|GUARD_FEE|Belrand|mine_iron@Jenassa|0|46")!, tasks);
  const velho = wordJournal(parseJournalLine("12|GUARD_FEE|Belrand|mine_iron|0|46")!, tasks);
  console.log("MEDIDA GRD04", novo.text, "|", velho.text);
  assert.ok(novo.text.startsWith("Jenassa guarded Belrand:"));
  assert.ok(velho.text.startsWith("A bodyguard guarded Belrand:"));
  assert.equal(novo.amount, -46);
});

test("GRD03 a plain contract is worded as before", () => {
  const o = wordOutcome({ action: "issue", slot: 0, code: "ISSUED", arg: "", number: 450 }, "Mira");
  assert.ok(o.ok && !o.text.includes("bodyguard"));
});
