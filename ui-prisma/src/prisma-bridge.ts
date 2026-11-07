// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

// prisma-bridge.ts
// Honest Work - Workers of Skyrim
//
// Thin wrapper around the two directions of the real, confirmed Prisma UI
// bridge (D079, header read directly from
// PrismaUI-SKSE/framework tag 1.4.1, src/PrismaUI_API.h - not from memory
// or the Nexus page):
//
// - C++ -> JS: the host calls `PrismaUI->Invoke(view, "window.hwInit(...)")`
//   once the DOM is ready (plugin.cpp's CreateView onDomReadyCallback,
//   mirrors PrismaUI-SKSE/example-skse-plugin's confirmed real
//   `updateFocusLabel(...)` call shape). This module exposes that as
//   `window.hwInit`, dispatching a DOM CustomEvent so React code can react
//   to it without polling.
// - JS -> C++: `RegisterJSListener(view, "hwIssueContract"/"hwCure"/
//   "hwFire"/"hwPickUp", callback)` on the C++ side injects those four
//   names onto `window` - calling them (with a single JSON string
//   argument) is how this UI requests an action, exactly mirroring the
//   confirmed real example's `window.sendDataToSKSE(inputValue)` call
//   shape (src/PrismaPanel.cpp on the C++ side parses the JSON and
//   forwards to Core::ModEventBridge::Send, D060 - unchanged mechanism).
//
// Outside the game (plain `npm run dev` in a browser, for local UI
// iteration) none of the `window.hw*` functions exist - every call here is
// wrapped so a missing host never throws into the render tree.

import { setTheme } from "./theme.ts";

export interface HwTaskInfo {
  id: string;
  // Fase 15: the list comes from the registry, every profession at once. The
  // page filters by the worker's profession and locks a task above the
  // worker's tier; minTierLabel is the on-screen name (D126: "Journeyman").
  profession: string;
  label: string;
  minTier: string;
  minTierLabel: string;
  hours: number;
  batchMin: number;
  batchMax: number;
  incidentChance: number;
  basePricePerUnit: number;
  // Fase 15 (D159): the cook's ingredients per unit, at cost. 0 for every
  // other task; -1 when an ingredient does not resolve in game.
  ingredientCostPerUnit?: number;
  // Fase 33 etapa 10 (F1): the multiplier the charge applies to the reference price, so the
  // panel can show the cost of a contract before it is issued. Absent from an older DLL: 1.
  priceMultiplier?: number;
  // Fase 33 etapa 10 (F3): how many sources of this task the hold lists. 0 = "None here".
  // Absent from an older DLL (which dropped such a task from the list).
  holdSources?: number;
}

// Fase 17 (D168): one rung of a profession's tier ladder - what the tier asks
// in contracts completed (the registry's minContracts, the same number
// WOSK_WorkerAliasScript._MaybeAdvanceTier reads).
export interface HwTierInfo {
  profession: string;
  id: string;
  label: string;
  minContracts: number;
  // Fase 26: what the tier does to a contract (the registry's multipliers,
  // sent by the DLL). Absent from an older DLL: the page then shows the base figure.
  durationMultiplier?: number;
  yieldMultiplier?: number;
}

export interface HwInitPayload {
  workerPoolSize: number;
  tasks: HwTaskInfo[];
  // Absent from a DLL older than Fase 17: the ladder then draws no requirement.
  tiers?: HwTierInfo[];
  // Fase 35 etapa 13: the bodyguard fee terms (share of the contract price, floor), read by the DLL
  // from the row Papyrus charges by. Absent from an older DLL: the page then quotes no guarded price.
  guardFee?: { rate: number; min: number };
}

export const HW_INIT_EVENT = "hw:init";

// D104 etapa 3: the Recruit tab. Pushed by Papyrus through WOSK_Panel
// (PrismaPanel.cpp SetRecruitList); null hides the tab.
export interface HwRecruitCandidate {
  spot: number;
  name: string;
  profession: string;
  tier: string;
  price: number;
  // D161 (Fase 16): where the candidate stands; empty when the data has none.
  place?: string;
  // Fase 33 etapa 10: the id of the rule that stops this hire ("COOK_HOLD": the hold already
  // has a cook), "" or absent when none does. Papyrus decides; the page words it.
  blocked?: string;
}

export interface HwRecruitPayload {
  hired: number;
  cap: number;
  // D184: true only when the recruiter opened the panel; otherwise the tab
  // shows the pool and Hire stays off.
  canHire: boolean;
  message: string;
  candidates: HwRecruitCandidate[];
}

export const HW_RECRUIT_EVENT = "hw:recruit";

// Fase 34 etapa 2 (D299): the "Your followers" section of the Recruit tab, pushed by
// Papyrus (WOSK_Panel.SetFollowerList -> PrismaPanel.cpp SetFollowerList).
export interface HwFollowerRow {
  // The row Papyrus keeps; the hire order carries it back.
  index: number;
  name: string;
  place: string;
  // The id of the rule that refuses him ("NOT_UNIQUE", "ANIMAL", "NFF_IMPORT",
  // "OWN_FRAMEWORK") or "". The page words it (model.ts).
  refused: string;
  // "trade:tier,trade:tier": what each trade would give him by his skill.
  tiers: string;
}

export interface HwFollowersPayload {
  needsPo3: boolean;
  message: string;
  followers: HwFollowerRow[];
}

export const HW_FOLLOWERS_EVENT = "hw:followers";

// Queue item 11: the Workers tab. Same channel shape as the Recruit tab above,
// but pushed on every contract state change (WOSK_PanelBridgeScript
// .PushPanelState, called from WOSK_WorkerAliasScript._AdvanceTo), so the tab
// stays current while the panel is open instead of freezing at open time.
export interface HwWorkerRow {
  slot: number;
  name: string;
  profession: string;
  tier: string;
  hold: string;
  state: string;
  canIssue: boolean;
  // -1 where no contract is running, or where the remaining time cannot be
  // computed - the row prints nothing rather than a made-up zero.
  hoursLeft: number;
}

export interface HwWorkersPayload {
  workers: HwWorkerRow[];
}

export const HW_WORKERS_EVENT = "hw:workers";

// Queue item 13: what the hold still has, one row per task, pushed on the same
// beats as the Workers tab (WOSK_PanelBridgeScript.PushPanelState). The row is
// matched to a task by id.
//
// `reason` is an ID and never a sentence - "" when the ore can be worked,
// otherwise "UNCONFIRMED", "OCCUPIED", "DEPLETED" or "NONE". The wording is
// done here, on purpose: a player-facing label built in Papyrus can come out
// wearing the case of an id it collides with (D127, D129).
export interface HwSourceRow {
  taskId: string;
  // Veins a contract issued right now could draw from - the CONFIRMED and SAFE
  // sources only, not the hold's theoretical total.
  veins: number;
  // veins x the game's own per-vein yield: the ore in the ground, not the
  // contract's batch arithmetic (V043). -1 when the yield has
  // not been seen on this save yet - print the veins alone, never a guess.
  units: number;
  reason: string;
  // Fase 33 etapa 8 (D1): the house whose kitchen this row speaks of (the cook's
  // tasks; "" for every other task) and the whole hours until a worked-out row
  // recovers (0 = unknown or not worked out). Absent from an older DLL.
  place?: string;
  backInHours?: number;
}

export interface HwSourcesPayload {
  hold: string;
  sources: HwSourceRow[];
}

export const HW_SOURCES_EVENT = "hw:sources";

// Fase 17 (D168): the Overview and Worker tabs' history, pushed with the
// worker list (WOSK_ControllerScript.RefreshHistory -> PrismaPanel SetHistory).
// Lines arrive as Papyrus keeps them - ids and numbers joined by "|" - and are
// split and worded in model.ts, never in Papyrus (D127/D129):
//   journal line: day|KIND|name|taskId|qty|gold
//   history line: day|OUTCOME|taskId|qty|cost|value   (joined by ";")
export interface HwWorkerStats {
  slot: number;
  completed: number;
  goldSpent: number;
  valueDelivered: number;
  history: string;
}

export interface HwHistoryPayload {
  // Game time in days, the clock the "day" fields are on.
  now: number;
  goldSpent: number;
  valueDelivered: number;
  contractsDone: number;
  active: number;
  journal: string[];
  workers: HwWorkerStats[];
}

export const HW_HISTORY_EVENT = "hw:history";

// Fase 17 B (D171): what Papyrus answered to an order given on the panel
// (WOSK_PanelBridgeScript.ReportOutcome -> PrismaPanel SetOutcome). `code` and
// `arg` are ids, worded in model.ts; compare them without case (D127/D129).
//   action: issue | collect | cure | dismiss
//   number: gold charged (issue), units collected (collect), else 0
export interface HwOutcome {
  action: string;
  slot: number;
  code: string;
  arg: string;
  number: number;
}

export const HW_OUTCOME_EVENT = "hw:outcome";

declare global {
  interface Window {
    hwInit?: (payload: HwInitPayload) => void;
    hwHistory?: (payload: HwHistoryPayload | null) => void;
    hwOutcome?: (payload: HwOutcome) => void;
    hwRecruit?: (payload: HwRecruitPayload | null) => void;
    hwFollowers?: (payload: HwFollowersPayload | null) => void;
    hwHireFollower?: (argument: string) => void;
    hwAssignGuard?: (argument: string) => void;
    hwWorkers?: (payload: HwWorkersPayload | null) => void;
    hwSources?: (payload: HwSourcesPayload | null) => void;
    hwHireCandidate?: (argument: string) => void;
    hwNote?: (argument: string) => void;
    hwIssueContract?: (argument: string) => void;
    hwIssueOccupied?: (argument: string) => void;
    hwCure?: (argument: string) => void;
    hwFire?: (argument: string) => void;
    hwPickUp?: (argument: string) => void;
    hwClosePanel?: (argument: string) => void;
    hwTheme?: (name: string) => void;
    hwThemeApplied?: (argument: string) => void;
  }
}

// Fase 33 etapa 8 (C1): the host's Invoke can land before React has mounted its
// listeners (the DOM-ready callback ran 8 ms after DOM ready on 1.7.104 and the
// hw:init event left with nobody listening - the page stayed on "Waiting for
// Honest Work data..."). Every state event is therefore remembered here, last
// payload per event, and the app reads it when it mounts (replayHostEvent); the
// live event goes on being dispatched. hw:outcome is NOT remembered: it is the
// answer to one order, and replaying it would say it a second time.
const REMEMBERED_EVENTS: ReadonlySet<string> = new Set([
  HW_INIT_EVENT,
  HW_RECRUIT_EVENT,
  HW_FOLLOWERS_EVENT,
  HW_WORKERS_EVENT,
  HW_SOURCES_EVENT,
  HW_HISTORY_EVENT,
]);
const remembered = new Map<string, unknown>();
let hostTheme: string | null = null;

function deliver<T>(name: string, detail: T): void {
  if (REMEMBERED_EVENTS.has(name)) remembered.set(name, detail);
  window.dispatchEvent(new CustomEvent<T>(name, { detail }));
}

// What the host sent under this event before the caller started listening;
// `found` is false when nothing has arrived yet (a null payload is a payload).
export function replayHostEvent<T>(name: string): { found: boolean; detail: T | undefined } {
  if (!remembered.has(name)) return { found: false, detail: undefined };
  return { found: true, detail: remembered.get(name) as T };
}

// The palette the host asked for, or null when none arrived: main.tsx applies the
// address default only in that case, so a palette sent early is not undone.
export function hostPalette(): string | null {
  return hostTheme;
}

// Installed once, at module load (src/main.tsx imports this before
// rendering) - must exist before the host's onDomReadyCallback fires
// Invoke("window.hwInit(...)"), same ordering PrismaUI-SKSE's own example
// relies on (the vanilla example defines window.updateFocusLabel at
// <script> parse time, before the C++ side's Invoke call can possibly run).
window.hwInit = (payload: HwInitPayload) => {
  deliver<HwInitPayload>(HW_INIT_EVENT, payload);
};

window.hwRecruit = (payload: HwRecruitPayload | null) => {
  deliver<HwRecruitPayload | null>(HW_RECRUIT_EVENT, payload);
};

window.hwFollowers = (payload: HwFollowersPayload | null) => {
  deliver<HwFollowersPayload | null>(HW_FOLLOWERS_EVENT, payload);
};

window.hwWorkers = (payload: HwWorkersPayload | null) => {
  deliver<HwWorkersPayload | null>(HW_WORKERS_EVENT, payload);
};

window.hwSources = (payload: HwSourcesPayload | null) => {
  deliver<HwSourcesPayload | null>(HW_SOURCES_EVENT, payload);
};

window.hwHistory = (payload: HwHistoryPayload | null) => {
  deliver<HwHistoryPayload | null>(HW_HISTORY_EVENT, payload);
};

window.hwOutcome = (payload: HwOutcome) => {
  deliver<HwOutcome>(HW_OUTCOME_EVENT, payload);
};

// D198 (Fase 19): the DLL sends the palette on every page load and when the
// settings page changes it. The page answers which palette it wears, so the
// DLL log shows it arrived (PrismaPanel.cpp, OnThemeApplied).
window.hwTheme = (name: string) => {
  const asked = String(name);
  const applied = setTheme(asked);
  hostTheme = applied;
  const fn = window.hwThemeApplied;
  if (typeof fn === "function") fn(JSON.stringify({ applied, asked }));
};

function callHost(
  fnName: "hwIssueContract" | "hwIssueOccupied" | "hwCure" | "hwFire" | "hwPickUp" | "hwClosePanel" | "hwHireCandidate" | "hwHireFollower" | "hwAssignGuard" | "hwNote",
  argument: unknown,
): void {
  const fn = window[fnName];
  if (typeof fn !== "function") {
    // Not running inside Prisma UI (e.g. `npm run dev` in a plain
    // browser) - log instead of throwing, matches PrismaUI-SKSE's own
    // confirmed real example (main.cpp's RegisterJSListener callback
    // pattern) tolerating a missing host the same way.
    // eslint-disable-next-line no-console
    console.warn(`[honestwork] ${fnName} called outside Prisma UI host`, argument);
    return;
  }
  fn(JSON.stringify(argument));
}

export const HostBridge = {
  // Fase 35 etapa 4: guard = true asks for the bodyguard; the DLL adds the "|g" bit to the task id.
  issueContract(aliasIndex: number, taskId: string, guard = false): void {
    callHost("hwIssueContract", guard ? { aliasIndex, taskId, guard: true } : { aliasIndex, taskId });
  },
  // Fase 33 etapa 2 (D267): the cook's house rides the contract order's channel as the
  // task id "house:<id>" (Papyrus intercepts it); slot -1 sets the house the next cook
  // moves into. No new DLL listener, so no DLL build.
  setHouse(aliasIndex: number, houseId: string): void {
    callHost("hwIssueContract", { aliasIndex, taskId: `house:${houseId}` });
  },
  issueOccupiedContract(aliasIndex: number, taskId: string, guard = false): void {
    callHost("hwIssueOccupied", guard ? { aliasIndex, taskId, guard: true } : { aliasIndex, taskId });
  },
  // Fase 35 etapa 4: assign the follower of this row of the list as a bodyguard.
  assignGuard(index: number): void {
    callHost("hwAssignGuard", { index });
  },
  // Fase 35 etapa 6: release the bodyguard of this row; same channel, the order is -(1 + row).
  releaseGuard(index: number): void {
    callHost("hwAssignGuard", { index: -(1 + index) });
  },
  cure(aliasIndex: number): void {
    callHost("hwCure", { aliasIndex });
  },
  fire(aliasIndex: number): void {
    callHost("hwFire", { aliasIndex });
  },
  pickUp(aliasIndex: number): void {
    callHost("hwPickUp", { aliasIndex });
  },
  hireCandidate(spot: number): void {
    callHost("hwHireCandidate", { spot });
  },
  // Fase 34 etapa 2 (D299): hire the follower of this row of the list as this trade.
  hireFollower(index: number, profession: string): void {
    callHost("hwHireFollower", { index, profession });
  },
  // Fase 33 etapa 10 (F3): a line the page wants in HonestWork.log (a task with no word on its
  // source). The DLL listener is OnPanelNote; an older DLL has none and the call only warns.
  note(text: string): void {
    callHost("hwNote", { text });
  },
  closePanel(): void {
    // C++ (OnClosePanel, PrismaPanel.cpp) ignores the argument - sent as
    // an empty object only to keep the same "single JSON string argument"
    // shape every other listener uses.
    callHost("hwClosePanel", {});
  },
};
