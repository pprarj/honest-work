// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

// Fase 34 etapa 2 (FOL01-FOL03): the words of the "Your followers" section (D299).
// Run: node --test tests/follower-words.test.ts   (Node 22.18+ strips the types itself)
import test from "node:test";
import assert from "node:assert/strict";
import { followerRefusalText, isTradeId, parseFollowerTiers } from "../src/model.ts";

test("FOL01 each refusal id has its own sentence; a free follower has none", () => {
  const ids = ["NOT_UNIQUE", "ANIMAL", "NFF_IMPORT", "OWN_FRAMEWORK"];
  const words = ids.map((id) => followerRefusalText(id));
  console.log("MEDIDA FOL01", words.join(" | "));
  assert.equal(new Set(words).size, 4);
  assert.ok(words.every((w) => w.length > 0));
  assert.equal(followerRefusalText(""), "");
});

test("FOL02 the id is read without case and an unknown id is shown as it came", () => {
  assert.equal(followerRefusalText("own_framework"), followerRefusalText("OWN_FRAMEWORK"));
  assert.equal(followerRefusalText("SOMETHING_NEW"), "Cannot be hired (SOMETHING_NEW)");
});

test("FOL03 the trade:tier list from Papyrus is split into a table", () => {
  const t = parseFollowerTiers("miner:worker,hunter:master,cook:apprentice");
  console.log("MEDIDA FOL03", JSON.stringify(t));
  assert.deepEqual(t, { miner: "worker", hunter: "master", cook: "apprentice" });
  assert.deepEqual(parseFollowerTiers(""), {});
});

test("FOL04 the six trades reach the DLL filter as ids even when Papyrus sends the label (V078)", () => {
  const ids = ["miner", "hunter", "cook", "herbalist", "fisher", "laborer"];
  const labelled = ids.map((id) => `${id[0].toUpperCase()}${id.slice(1)}:worker`).join(",");
  const t = parseFollowerTiers(labelled);
  console.log("MEDIDA FOL04", JSON.stringify(Object.keys(t)));
  assert.deepEqual(Object.keys(t), ids);
  assert.ok(Object.keys(t).every((k) => isTradeId(k)));
  assert.equal(isTradeId("Miner"), false);
});
