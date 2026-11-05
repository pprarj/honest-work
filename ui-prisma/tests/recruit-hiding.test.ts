// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

// Fase 32 (HID01-HID03): the Recruit list while a Hire is in flight (D254).
// Run: node --test tests/recruit-hiding.test.ts   (Node 22.18+ strips the types itself)
import test from "node:test";
import assert from "node:assert/strict";
import { stateTone, withoutHiding } from "../src/model.ts";

const list = { cap: 4, hired: 1, candidates: [{ spot: 0, name: "Asa" }, { spot: 3, name: "Leif" }, { spot: 7, name: "Orm" }] };

test("HID01 nothing in flight: the same list comes back untouched", () => {
  const r = withoutHiding(list, new Set<number>());
  console.log("MEDIDA HID01", r.candidates.map((c) => c.spot).join(","));
  assert.equal(r, list);
});

test("HID02 a Hire in flight takes only that card off; the rest of the payload is kept", () => {
  const r = withoutHiding(list, new Set([3]));
  console.log("MEDIDA HID02", r.candidates.map((c) => c.spot).join(","), "cap", r.cap, "hired", r.hired);
  assert.deepEqual(r.candidates.map((c) => c.spot), [0, 7]);
  assert.equal(r.cap, 4);
  assert.equal(r.hired, 1);
  assert.equal(list.candidates.length, 3, "the source list is not mutated");
});

test("HID03 a refusal: Papyrus's list still has the card, an empty hiding set shows it again; 'Setting out' has the colour of a worker on the road", () => {
  const back = withoutHiding(list, new Set<number>());
  console.log("MEDIDA HID03", back.candidates.length, stateTone("Setting out"), stateTone("Traveling out"));
  assert.equal(back.candidates.length, 3);
  assert.equal(stateTone("Setting out"), "away");
  assert.equal(stateTone("Traveling out"), "away");
});
