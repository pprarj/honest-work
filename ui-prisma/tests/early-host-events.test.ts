// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

// Fase 33 etapa 8 (C1): the host's Invoke can arrive before React listens.
// Run: node --test tests/early-host-events.test.ts   (Node 22.18+ strips the types itself)
import test from "node:test";
import assert from "node:assert/strict";

// The bridge touches window and document at load; stand-ins are enough here.
const win: any = new EventTarget();
(globalThis as any).window = win;
(globalThis as any).document = { documentElement: { dataset: {} as Record<string, string> } };

const bridge = await import("../src/prisma-bridge.ts");

test("EHE01 hwInit before any listener: the payload is replayed, and the live event still fires", () => {
  const payload = { workerPoolSize: 2, tasks: [{ id: "cook_simple" }] };
  assert.equal(bridge.replayHostEvent(bridge.HW_INIT_EVENT).found, false);
  win.hwInit(payload);
  const early = bridge.replayHostEvent<typeof payload>(bridge.HW_INIT_EVENT);
  console.log("MEDIDA EHE01", JSON.stringify(early));
  assert.equal(early.found, true);
  assert.deepEqual(early.detail, payload);

  const seen: unknown[] = [];
  win.addEventListener(bridge.HW_INIT_EVENT, (e: any) => seen.push(e.detail));
  const next = { workerPoolSize: 3, tasks: [] };
  win.hwInit(next);
  assert.deepEqual(seen, [next]);
  assert.deepEqual(bridge.replayHostEvent(bridge.HW_INIT_EVENT).detail, next);
});

test("EHE02 a null payload is remembered as a payload (the host clearing a list)", () => {
  win.hwRecruit(null);
  const r = bridge.replayHostEvent(bridge.HW_RECRUIT_EVENT);
  assert.equal(r.found, true);
  assert.equal(r.detail, null);
});

test("EHE03 the outcome of an order is never replayed", () => {
  win.hwOutcome({ action: "issue", slot: 0, code: "ISSUED", arg: "", number: 10 });
  assert.equal(bridge.replayHostEvent(bridge.HW_OUTCOME_EVENT).found, false);
});

test("EHE04 the palette sent early is remembered, so main.tsx does not undo it", () => {
  assert.equal(bridge.hostPalette(), null);
  win.hwTheme("moss");
  console.log("MEDIDA EHE04", bridge.hostPalette(), JSON.stringify((globalThis as any).document.documentElement.dataset));
  assert.equal(bridge.hostPalette(), "moss");
});
