// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

// Fase 33 etapa 9 (E2, V072): the roster card puts the state on a line of its own, at the full
// width, wrapping and never cut with an ellipsis. A source-level check: the layout lives in JSX
// and CSS, and the embedded browser is not available to a node test.
// Run: node --test tests/*.test.ts   (Node 22.18+ strips the types itself)
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (p: string) => readFileSync(new URL(p, import.meta.url), "utf8");
const sidebar = read("../src/views/Sidebar.tsx");
const worker = read("../src/views/WorkerView.tsx");
const css = read("../src/style.css");

// The body of the first rule whose selector list is exactly `selector`.
function rule(selector: string): string {
  const at = css.indexOf(`\n${selector} {`);
  assert.ok(at >= 0, `rule ${selector} exists`);
  return css.slice(at, css.indexOf("}", at));
}

test("CRD01 the name and the gold share a line, the state comes after it", () => {
  const line = sidebar.indexOf('className="hw-roster-line"');
  const gold = sidebar.indexOf("hw-roster-number");
  const state = sidebar.indexOf("hw-state-card");
  assert.ok(line >= 0 && gold > line && state > gold, `line ${line} gold ${gold} state ${state}`);
  // The state is no longer inside the text column next to the gold.
  assert.equal(sidebar.includes("hw-roster-text"), false);
});

test("CRD02 the state of a card wraps: no nowrap and no ellipsis", () => {
  const live = rule(".hw-state-card .hw-live-text");
  console.log("MEDIDA CRD02", live.replace(/\s+/g, " ").trim());
  assert.match(live, /white-space:\s*normal/);
  assert.doesNotMatch(live, /text-overflow:\s*ellipsis/);
  assert.doesNotMatch(live, /nowrap/);
  assert.match(rule(".hw-state-card"), /width:\s*100%/);
});

test("CRD03 the gold figure keeps its width and the card is a column that grows", () => {
  assert.match(rule(".hw-roster-figure"), /flex:\s*none/);
  const row = rule(".hw-roster-row");
  assert.match(row, /flex-direction:\s*column/);
  assert.doesNotMatch(row, /(^|[^-])height:/);
});

test("CRD04 the WORKER header state wraps by the same rule", () => {
  assert.ok(worker.includes("hw-state hw-tone-"));
  const live = rule(".hw-hero-id .hw-live-text");
  assert.match(live, /white-space:\s*normal/);
  assert.doesNotMatch(live, /text-overflow:\s*ellipsis/);
});
