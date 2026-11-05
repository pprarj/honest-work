// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

// demo.ts
// Honest Work - Workers of Skyrim
//
// Fase 17 (D169): sample data so the page opens in a plain browser, with no
// game, for layout work and the maintainer's review. Only runs when the address
// carries ?demo=... - inside Prisma UI the page is opened as a bare local
// index.html and this does nothing. The numbers below are made up for the
// layout; the task ids and labels are the registry's (professions/00_core.json).
//
//   ?demo=1        four workers, a week of statement, no recruiter
//   ?demo=recruit  the same, opened by the recruiter (Recruit tab + candidates)
//   ?demo=browse   the same candidates, panel opened by its hotkey: the tab
//                  shows them and Hire stays off (D184, no recruiter sign)
//   ?demo=empty    nobody hired, nothing in the statement
//   ?demo=full     opened by the recruiter with every place taken
//   ?demo=nobody   opened by the recruiter, nobody hired and no candidate
//   &tab=N         opens tab N;  &worker=N  selects the N-th worker (0 = first)
//   &say=1         shows a sample refusal in the answer line (for screenshots)
//   &tema=NAME     colour palette (D188, D189): frost (the default), amber, moss,
//                  parchment - read by theme.ts, works with or without demo
//
// Fase 17 B (D171): in demo mode the order buttons get sample answers, so the
// answer line can be seen working in a browser. The answers below are made
// up from the sample data; in game every answer is Papyrus's.

import type {
  HwHistoryPayload,
  HwInitPayload,
  HwOutcome,
  HwRecruitPayload,
  HwSourcesPayload,
  HwTaskInfo,
  HwTierInfo,
  HwWorkersPayload,
} from "./prisma-bridge";

const T = (
  profession: string,
  id: string,
  label: string,
  minTier: string,
  hours: number,
  batchMin: number,
  batchMax: number,
  incidentChance: number,
  basePricePerUnit: number,
  ingredientCostPerUnit = 0,
): HwTaskInfo => ({
  profession,
  id,
  label,
  minTier,
  minTierLabel: TIER_LABEL[minTier] ?? minTier,
  hours,
  batchMin,
  batchMax,
  incidentChance,
  basePricePerUnit,
  ingredientCostPerUnit,
});

const TIER_LABEL: Record<string, string> = {
  apprentice: "Apprentice",
  worker: "Journeyman",
  veteran: "Veteran",
  master: "Master",
};

const PROFESSIONS = ["cook", "fisher", "herbalist", "hunter", "laborer", "miner"];
const MIN_CONTRACTS: [string, number][] = [
  ["apprentice", 0],
  ["worker", 5],
  ["veteran", 15],
  ["master", 30],
];

// Fase 26: the registry's multipliers per tier, so the demo shows what a worker of the tier gets.
const MULTIPLIERS: Record<string, [number, number]> = {
  apprentice: [1.0, 1.0],
  worker: [0.9, 1.15],
  veteran: [0.85, 1.3],
  master: [0.8, 1.5],
};
const tiers: HwTierInfo[] = PROFESSIONS.flatMap((profession) =>
  MIN_CONTRACTS.map(([id, minContracts]) => ({
    profession,
    id,
    label: TIER_LABEL[id],
    minContracts,
    durationMultiplier: MULTIPLIERS[id][0],
    yieldMultiplier: MULTIPLIERS[id][1],
  })),
);

const init: HwInitPayload = {
  workerPoolSize: 4,
  tiers,
  tasks: [
    T("cook", "cook_simple", "Simple meals", "apprentice", 1, 4, 6, 0.01, 6, 5.666299819946289),
    T("cook", "cook_stew", "Soups and stews", "worker", 2, 3, 5, 0.01, 8, 3.1),
    T("cook", "cook_fine", "Fine dishes", "veteran", 6, 2, 3, 0.02, 14, 6.2),
    T("cook", "cook_feast", "Feasts", "master", 8, 1, 2, 0.02, 40, 18.4),
    T("hunter", "hunt_small", "Small game", "apprentice", 24, 6, 10, 0.1, 4),
    T("hunter", "hunt_wolf", "Wolf pelts", "worker", 36, 3, 6, 0.18, 25),
    T("hunter", "hunt_big", "Bear and sabre cat", "veteran", 72, 2, 4, 0.34, 40),
    T("herbalist", "herb_common", "Common flowers", "apprentice", 24, 10, 16, 0.03, 2),
    T("herbalist", "herb_tundra", "Tundra ingredients", "worker", 36, 8, 12, 0.05, 4),
    T("herbalist", "herb_rare", "Rare herbs", "veteran", 72, 3, 6, 0.08, 12),
    T("miner", "iron", "Iron ore", "apprentice", 24, 20, 32, 0.05, 7),
    T("miner", "corundum", "Corundum ore", "apprentice", 24, 20, 32, 0.05, 10),
    T("miner", "silver", "Silver ore", "apprentice", 36, 16, 24, 0.08, 25),
    T("miner", "quicksilver", "Quicksilver ore", "apprentice", 36, 16, 24, 0.08, 25),
    T("miner", "orichalcum", "Orichalcum ore", "worker", 72, 10, 16, 0.15, 45),
    T("miner", "malachite", "Malachite ore", "worker", 72, 10, 16, 0.15, 61),
    T("miner", "gold", "Gold ore", "veteran", 96, 6, 10, 0.22, 100),
    T("miner", "ebony", "Ebony ore", "veteran", 168, 4, 8, 0.3, 150),
  ],
};

const workers: HwWorkersPayload = {
  workers: [
    { slot: 0, name: "Brenna Stone-Hand", profession: "miner", tier: "Journeyman", hold: "Whiterun", state: "At work", canIssue: false, hoursLeft: 14 },
    { slot: 1, name: "Torvar Ash-Eye", profession: "hunter", tier: "Apprentice", hold: "Whiterun", state: "Injured", canIssue: false, hoursLeft: -1 },
    { slot: 2, name: "Idrys Velothi", profession: "cook", tier: "Veteran", hold: "Whiterun", state: "Awaiting pickup", canIssue: false, hoursLeft: -1 },
    { slot: 3, name: "Hulda the Quiet", profession: "herbalist", tier: "Apprentice", hold: "Whiterun", state: "Awaiting work", canIssue: true, hoursLeft: -1 },
  ],
};

const sources: HwSourcesPayload = {
  hold: "Whiterun",
  sources: [
    { taskId: "iron", veins: 6, units: 72, reason: "" },
    { taskId: "corundum", veins: 0, units: -1, reason: "UNCONFIRMED" },
    { taskId: "silver", veins: 0, units: -1, reason: "OCCUPIED" },
    { taskId: "quicksilver", veins: 2, units: -1, reason: "" },
    { taskId: "orichalcum", veins: 0, units: -1, reason: "NONE" },
    { taskId: "hunt_small", veins: -2, units: 30, reason: "" },
    { taskId: "hunt_wolf", veins: -2, units: 0, reason: "DEPLETED" },
    { taskId: "herb_common", veins: -2, units: 48, reason: "" },
    { taskId: "herb_tundra", veins: -2, units: 0, reason: "OCCUPIED" },
    { taskId: "cook_simple", veins: -2, units: 20, reason: "" },
    { taskId: "cook_stew", veins: -2, units: 20, reason: "" },
    { taskId: "cook_fine", veins: -2, units: 20, reason: "" },
  ],
};

const NOW = 214.62;

const history: HwHistoryPayload = {
  now: NOW,
  goldSpent: 6840,
  valueDelivered: 9315,
  contractsDone: 31,
  active: 1,
  journal: [
    "208.30|ISSUED|Idrys Velothi|cook_fine|0|412",
    "209.30|RETURNED|Idrys Velothi|cook_fine|5|540",
    "209.80|ISSUED|Brenna Stone-Hand|iron|0|190",
    "210.20|ISSUED|Torvar Ash-Eye|hunt_small|0|64",
    "210.80|RETURNED|Brenna Stone-Hand|iron|27|189",
    "211.25|RETURNED|Torvar Ash-Eye|hunt_small|8|32",
    "211.40|ISSUED|Hulda the Quiet|herb_common|0|50",
    "212.40|RETURNED|Hulda the Quiet|herb_common|14|28",
    "212.50|ISSUED|Torvar Ash-Eye|hunt_small|0|64",
    "213.10|ISSUED|Idrys Velothi|cook_stew|0|286",
    "213.60|INJURED|Torvar Ash-Eye|hunt_small|0|0",
    "213.75|RETURNED|Idrys Velothi|cook_stew|9|72",
    "214.05|ISSUED|Brenna Stone-Hand|silver|0|540",
  ],
  workers: [
    {
      slot: 0,
      completed: 9,
      goldSpent: 2430,
      valueDelivered: 3120,
      history:
        "196.2|SUCCESS|iron|26|190|182;199.8|SUCCESS|corundum|24|240|240;203.1|MINOR|silver|0|540|0;206.4|SUCCESS|quicksilver|19|520|475;210.8|SUCCESS|iron|27|190|189",
    },
    { slot: 1, completed: 3, goldSpent: 384, valueDelivered: 120, history: "205.0|SUCCESS|hunt_small|9|64|36;211.25|SUCCESS|hunt_small|8|64|32;213.6|MINOR|hunt_small|0|64|0" },
    {
      slot: 2,
      completed: 17,
      goldSpent: 3846,
      valueDelivered: 5920,
      history: "201.0|SUCCESS|cook_stew|10|286|80;204.9|SUCCESS|cook_fine|6|412|648;209.3|SUCCESS|cook_fine|5|412|540;213.75|SUCCESS|cook_stew|9|286|72",
    },
    { slot: 3, completed: 2, goldSpent: 180, valueDelivered: 155, history: "207.5|SUCCESS|herb_common|13|50|26;212.4|SUCCESS|herb_common|14|50|28" },
  ],
};

const recruit: HwRecruitPayload = {
  hired: 4,
  cap: 6,
  canHire: true,
  message: "",
  candidates: [
    { spot: 0, name: "Saffir", profession: "cook", tier: "apprentice", price: 500, place: "The Bannered Mare" },
    { spot: 1, name: "Olfrid the Wet", profession: "fisher", tier: "worker", price: 1500, place: "The Bannered Mare" },
    { spot: 3, name: "Kjeld Longstride", profession: "hunter", tier: "veteran", price: 4000, place: "The Drunken Huntsman" },
    { spot: 5, name: "Gunnhild Iron-Lung", profession: "miner", tier: "master", price: 10000, place: "The Bannered Mare" },
  ],
};

function param(name: string): string | null {
  try {
    return new URLSearchParams(window.location.search).get(name);
  } catch {
    return null;
  }
}

const NOT_READY: Record<string, string> = {
  "Setting out": "TRAVELING_TO",
  "Traveling out": "TRAVELING_TO",
  "At work": "WORKING",
  Returning: "TRAVELING_BACK",
};

function answer(o: HwOutcome): void {
  window.setTimeout(() => window.hwOutcome?.(o), 350);
}

function readArg(argument: string): { aliasIndex?: number; taskId?: string; spot?: number } {
  try {
    return JSON.parse(argument);
  } catch {
    return {};
  }
}

// The list the demo last sent, so a sample hire answers in the same mode.
let current: HwRecruitPayload = recruit;

function sendRecruit(payload: HwRecruitPayload): void {
  current = payload;
  window.hwRecruit?.(payload);
}

// Sample answers only; the same ids Papyrus sends (WOSK_WorkerAliasScript).
function installFakeHost(): void {
  const worker = (slot: number | undefined) => workers.workers.find((w) => w.slot === slot);
  window.hwIssueContract = (argument) => {
    const a = readArg(argument);
    const task = init.tasks.find((x) => x.id === a.taskId);
    const row = sources.sources.find((s) => s.taskId === a.taskId);
    const slot = a.aliasIndex ?? -1;
    if (row && row.reason) {
      answer({ action: "issue", slot, code: "SOURCE", arg: row.reason, number: 0 });
    } else if (task && task.basePricePerUnit * task.batchMax > 2000) {
      answer({ action: "issue", slot, code: "GOLD", arg: "1250", number: Math.ceil(((task.batchMin + task.batchMax) / 2) * task.basePricePerUnit) });
    } else {
      answer({ action: "issue", slot, code: "ISSUED", arg: "", number: task ? Math.ceil(((task.batchMin + task.batchMax) / 2) * task.basePricePerUnit) : 0 });
    }
  };
  window.hwIssueOccupied = (argument) => {
    const a = readArg(argument);
    answer({ action: "issue", slot: a.aliasIndex ?? -1, code: "ISSUED", arg: "OCCUPIED", number: 540 });
  };
  window.hwPickUp = (argument) => {
    const w = worker(readArg(argument).aliasIndex);
    if (!w) return answer({ action: "collect", slot: -1, code: "EMPTY", arg: "", number: 0 });
    if (w.state === "Awaiting pickup") return answer({ action: "collect", slot: w.slot, code: "COLLECTED", arg: "", number: 9 });
    answer({ action: "collect", slot: w.slot, code: "NOT_READY", arg: NOT_READY[w.state] ?? "IDLE", number: 0 });
  };
  window.hwCure = (argument) => {
    const w = worker(readArg(argument).aliasIndex);
    if (!w) return;
    answer({ action: "cure", slot: w.slot, code: w.state === "Injured" ? "CURED" : "NOT_INJURED", arg: "AVAILABLE", number: 0 });
  };
  window.hwFire = (argument) => {
    const w = worker(readArg(argument).aliasIndex);
    if (!w) return;
    if (NOT_READY[w.state]) return answer({ action: "dismiss", slot: w.slot, code: "IN_PERSON", arg: NOT_READY[w.state], number: 0 });
    answer({ action: "dismiss", slot: w.slot, code: "DISMISSED", arg: w.name, number: 0 });
  };
  window.hwHireCandidate = (argument) => {
    const spot = readArg(argument).spot;
    const c = recruit.candidates.find((x) => x.spot === spot);
    if (!c) return;
    if (!current.canHire) {
      answer({ action: "hire", slot: spot ?? -1, code: "NOT_RECRUITER", arg: "", number: 0 });
      window.setTimeout(() => window.hwRecruit?.({ ...current, message: "Talk to the Hiring Agent to hire." }), 450);
      return;
    }
    window.setTimeout(
      () => window.hwRecruit?.({ ...current, message: `Not enough gold: hiring ${c.name} costs ${c.price}.` }),
      350,
    );
  };
  window.hwClosePanel = () => undefined;
}

export function demoMode(): string | null {
  try {
    return new URLSearchParams(window.location.search).get("demo");
  } catch {
    return null;
  }
}

// Also read by the development reference model as the worst-case backdrop.
export const DEMO_BACKDROP = "linear-gradient(160deg, #56606a 0%, #2f3a35 45%, #6b5a45 100%)";

// Called once from main.tsx, after the bridge is installed and React mounted.
// &tab=N presses the tab's number key once the data is in (for screenshots).
export function runDemo(mode: string): void {
  // A stand-in for the game behind the translucent panel.
  document.body.style.background = DEMO_BACKDROP;
  let tab: string | null = null;
  try {
    tab = new URLSearchParams(window.location.search).get("tab");
  } catch {
    tab = null;
  }
  installFakeHost();
  const press = (key: string) => window.dispatchEvent(new KeyboardEvent("keydown", { key }));
  const pick = Number(param("worker") ?? "0");
  // One key per tick: the page re-reads the selection between two presses.
  for (let i = 0; i < pick; i += 1) window.setTimeout(() => press("ArrowDown"), 30 + i * 30);
  if (tab) {
    window.setTimeout(() => press(tab as string), 60 + pick * 30);
  }
  if (param("say")) {
    window.setTimeout(
      () => window.hwOutcome?.({ action: "issue", slot: workers.workers[pick]?.slot ?? 0, code: "SOURCE", arg: "OCCUPIED", number: 0 }),
      120 + pick * 30,
    );
  }
  // Same order the game uses: init on DOM ready, then the pushes.
  window.setTimeout(() => {
    window.hwInit?.(init);
    if (mode === "empty" || mode === "nobody") {
      window.hwWorkers?.({ workers: [] });
      window.hwHistory?.({ now: NOW, goldSpent: 0, valueDelivered: 0, contractsDone: 0, active: 0, journal: [], workers: [] });
      window.hwSources?.(sources);
      if (mode === "nobody") sendRecruit({ hired: 0, cap: 4, canHire: true, message: "", candidates: [] });
      return;
    }
    window.hwWorkers?.(workers);
    window.hwSources?.(sources);
    window.hwHistory?.(history);
    if (mode === "recruit") sendRecruit(recruit);
    if (mode === "browse") sendRecruit({ ...recruit, canHire: false });
    if (mode === "full") sendRecruit({ ...recruit, hired: 4, cap: 4 });
  }, 0);
}
