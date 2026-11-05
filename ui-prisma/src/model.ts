// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

// model.ts
// Honest Work - Workers of Skyrim
//
// Pure helpers for the panel: wording, tier ranks, and the split of the history
// lines Papyrus keeps as ids and numbers (WOSK_LedgerScript, D168). Nothing in
// here decides a game rule - every rule stays in Papyrus (SPEC 8); this file
// only turns what arrived into words and numbers on screen.

import type { HwHistoryPayload, HwOutcome, HwSourceRow, HwTaskInfo, HwTierInfo, HwWorkerRow, HwWorkerStats } from "./prisma-bridge";

export function capitalize(text: string): string {
  return text ? text.charAt(0).toUpperCase() + text.slice(1).toLowerCase() : text;
}

// Fase 30 (V061): lowers only the first letter, so a place name inside the text
// ("Cooking at Breezehome") keeps its capitals when the line goes mid-sentence.
export function lowerFirst(text: string): string {
  return text ? text.charAt(0).toLowerCase() + text.slice(1) : text;
}

export function gold(n: number): string {
  return Math.round(n).toLocaleString("en-US");
}

// Queue item 11. -1 is "no number to print" (no contract, no start stamp,
// unresolvable task length), so it prints nothing rather than a zero.
// Fase 28 conserto 1 (D238, V060): says what is left, in game hours ("~5 h left"),
// where it used to say "back within the hour" / "back in 24 h".
export function hoursLeftText(hours: number): string {
  if (hours < 0) return "";
  // Fase 31 (V062): below an hour it counts game minutes, in steps of 5 ("~40 min left").
  if (hours < 1) return `~${Math.max(5, Math.round((hours * 60) / 5) * 5)} min left`;
  return `~${Math.round(hours)} h left`;
}

// Fase 28 conserto 1 (D238): for a worker awaiting pickup Papyrus puts a code in the
// hours field instead of a number (WOSK_WorkerAliasScript.PanelHoursLeft): -2 the
// batch can be collected now, -3 the worker is not near the player, -4 nothing to
// collect. Anything else is hours (>= 0) or "no number" (-1).
export const PICKUP_READY = -2;
export const PICKUP_FAR = -3;
export const PICKUP_EMPTY = -4;

// Why the Collect button is off for this worker, "" when it is not.
// Fase 33 etapa 6 (D277, V069 A1): a batch of nothing no longer turns Collect off. Papyrus
// accepts the order and closes the contract (NO_BATCH), which is the only way out of
// "Awaiting pickup" for him; the button stays on and says so (emptyBatchHint).
export function pickupBlock(w: HwWorkerRow): string {
  if (w.state !== "Awaiting pickup") return "";
  if (w.hoursLeft === PICKUP_FAR) return `${w.name} is too far away - go to them to collect.`;
  return "";
}

// The line beside Collect for a worker who came back with an empty batch.
export function emptyBatchHint(w: HwWorkerRow): string {
  return `${w.name} came back empty-handed. Collecting closes the contract.`;
}

// Fase 33 etapa 1 (V064): a worker who is home with the batch says so, whether the clock
// ended the contract or he walked in before it (Papyrus resolves the contract on arrival).
export function backLine(w: HwWorkerRow): string {
  if (w.hoursLeft === PICKUP_EMPTY) return `${w.name} is back home with nothing to hand over. Collect to close the contract.`;
  if (w.hoursLeft === PICKUP_FAR) return `${w.name} is back home with the batch - go to them to collect.`;
  return `${w.name} is back home - the batch is ready to collect.`;
}

// Fase 33 etapa 1 (V064): the Contracts count of a worker hired at a rank above the first
// is credit for that rank, not contracts settled with the player; the empty history says
// which it is instead of contradicting the number.
export function creditLine(completed: number, w: HwWorkerRow): string {
  if (completed > 0) {
    return `${completed} contract(s) of experience came with ${w.name}'s rank. None settled with you yet.`;
  }
  return "No contract settled yet.";
}

// The one line a card of an injured worker carries (V060).
export function injuredLine(w: HwWorkerRow): string {
  return `${w.name} was injured: the contract brought nothing, and they cannot work until cured.`;
}

// Fase 32 (D254): the Recruit list the page shows while a Hire is in flight. The
// click takes the card off the list at once; Papyrus then answers with the list
// as it stands (a hire has taken the candidate, a refusal has left it) and that
// list replaces this one - so a refusal puts the card back with the answer, and
// the page never has to guess what Papyrus decided. Pure on purpose (tests/).
export function withoutHiding<T extends { candidates: ReadonlyArray<{ spot: number }> }>(recruit: T, hiding: ReadonlySet<number>): T {
  if (hiding.size === 0) return recruit;
  return { ...recruit, candidates: recruit.candidates.filter((c) => !hiding.has(c.spot)) };
}

// The state label is worded in Papyrus already (WOSK_Names.StateLabel, kept
// different from the ids on purpose, D127). This only sorts it into a tone for
// the colour of the dot, and falls back to "idle" for anything new.
export type StateTone = "idle" | "away" | "ready" | "hurt" | "gone";
export function stateTone(state: string): StateTone {
  // Fase 28 (D234): the cook on a contract reads "Cooking at <his house>"; the
  // house name is part of the text, so it is matched by its start.
  if (state.startsWith("Cooking at")) return "away";
  switch (state) {
    case "Setting out":
    case "Traveling out":
    case "At work":
    case "Returning":
      return "away";
    case "Awaiting pickup":
      return "ready";
    case "Injured":
      return "hurt";
    case "Lost":
    case "Retired - hurt at work":
      return "gone";
    default:
      return "idle";
  }
}

// Fase 31 conserto 1 (D257): a worker retired by an accident keeps his place until the
// player pays the pension. WOSK_Names words the state; the page tells him by it.
export const RETIRED_STATE = "Retired - hurt at work";
export function isRetired(w: HwWorkerRow | undefined): boolean {
  return !!w && w.state === RETIRED_STATE;
}

export function stateLine(w: HwWorkerRow): string {
  const left = hoursLeftText(w.hoursLeft);
  return left ? `${w.state}, ${left}` : w.state;
}

// Fase 30: the tab the panel opens on when the player opens it with the hotkey.
// A worker with a contract running (a number of hours left, or a batch waiting
// at the pickup) takes the Worker tab; otherwise a worker without a contract
// takes Contracts; nobody hired is the Overview. The slot is the worker to
// select, null when the selection should stay as it is.
export type StartTab = { tab: "overview" | "worker" | "contracts"; slot: number | null };
export function initialTabFor(rows: HwWorkerRow[] | null): StartTab {
  if (!rows || rows.length === 0) return { tab: "overview", slot: null };
  // -1 is "no number" (no contract); -2..-4 are the pickup codes of a finished
  // contract, which the Worker tab is where the player collects.
  const running = rows.find((w) => w.hoursLeft !== -1 && (w.hoursLeft >= 0 || w.hoursLeft <= PICKUP_READY));
  if (running) return { tab: "worker", slot: running.slot };
  const free = rows.find((w) => w.canIssue) ?? rows[0];
  return { tab: "contracts", slot: free.slot };
}

// Fase 30: what the hunter carries, as Papyrus words it in the "gear" outcome
// (WOSK_Gear.GearLine): "armor=<tier>;bow=<tier>;arrows=<tier>", a field empty
// when the hunter has none of it. Tiers read as the card's own labels.
export interface GearInfo {
  armor: string;
  bow: string;
  arrows: string;
}
export function parseGear(text: string): GearInfo {
  const out: GearInfo = { armor: "", bow: "", arrows: "" };
  for (const part of (text || "").split(";")) {
    const eq = part.indexOf("=");
    if (eq < 0) continue;
    const key = part.slice(0, eq).trim() as keyof GearInfo;
    if (key in out) out[key] = part.slice(eq + 1).trim();
  }
  return out;
}
export function gearLine(g: GearInfo | undefined): string {
  if (!g || (!g.armor && !g.bow && !g.arrows)) return "";
  const bits: string[] = [];
  if (g.bow) bits.push(`bow: ${g.bow}`);
  if (g.arrows) bits.push(`arrows: ${g.arrows}`);
  if (g.armor) bits.push(`armor: ${g.armor}`);
  return bits.join(", ");
}

// Fase 33 etapa 2 (D267): the cook's house, as Papyrus words it in the "house" outcome:
// code = the house he lives in (or, for slot -1, the one a new cook moves into), arg = the
// houses the player owns joined by "|", number 1 when the change is open (no contract).
export interface HouseInfo {
  current: string;
  owned: string[];
  open: boolean;
}
export function parseHouse(code: string, arg: string, number: number): HouseInfo {
  return {
    current: (code || "").toLowerCase(),
    owned: (arg || "").split("|").map((s) => s.trim().toLowerCase()).filter(Boolean),
    open: number > 0,
  };
}
// Fase 33 etapa 3: the game sends the profession as "Cook" / "Miner" (the VM keeps one
// spelling per string, D127/D129), so a profession is compared without case.
export function isProfession(profession: string | undefined, id: string): boolean {
  return (profession || "").toLowerCase() === id.toLowerCase();
}
// The house picker needs two owned houses; a new cook's house (Recruit tab) only matters
// when a cook is on the list, the cook's own button row only on a cook.
export function hasHouseChoice(house: HouseInfo | undefined): house is HouseInfo {
  return !!house && house.owned.length > 1;
}
export function recruitShowsHouse(canHire: boolean, house: HouseInfo | undefined, candidates: { profession: string }[]): boolean {
  return canHire && hasHouseChoice(house) && candidates.some((c) => isProfession(c.profession, "cook"));
}
export function workerShowsHouse(profession: string | undefined, house: HouseInfo | undefined): boolean {
  return isProfession(profession, "cook") && hasHouseChoice(house);
}
// "tundra_homestead" -> "Tundra Homestead"
export function houseLabel(id: string): string {
  return (id || "")
    .split("_")
    .filter(Boolean)
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
    .join(" ");
}

// Fase 15: the rank of a tier from its id or its on-screen name (the worker
// rows carry the name, D126: "Journeyman" for the id "worker"). -1 for unknown.
const TIER_RANKS: Record<string, number> = { apprentice: 0, worker: 1, journeyman: 1, veteran: 2, master: 3 };
export function tierRank(tier: string): number {
  return TIER_RANKS[(tier || "").toLowerCase()] ?? -1;
}

export const TIER_NUMERALS = ["I", "II", "III", "IV"];

// A tier id or label on screen (D126: the id "worker" reads "Journeyman").
const TIER_NAMES: Record<string, string> = {
  apprentice: "Apprentice",
  worker: "Journeyman",
  journeyman: "Journeyman",
  veteran: "Veteran",
  master: "Master",
};
export function tierName(tier: string): string {
  return TIER_NAMES[(tier || "").toLowerCase()] ?? capitalize(tier);
}

export function taskLocked(task: HwTaskInfo, worker: HwWorkerRow | undefined): boolean {
  if (!worker) return false;
  const have = tierRank(worker.tier);
  const need = tierRank(task.minTier);
  return have >= 0 && need >= 0 && have < need;
}

// The ladder of one profession, in rank order. Empty when the DLL sent none.
export function ladderFor(tiers: HwTierInfo[] | undefined, profession: string): HwTierInfo[] {
  return (tiers ?? [])
    .filter((t) => t.profession.toLowerCase() === (profession || "").toLowerCase())
    .sort((a, b) => tierRank(a.id) - tierRank(b.id));
}

// Fase 26: the figures a worker of this tier really gets. The rules stay in
// Papyrus (hours = base x durationMultiplier, units = Floor(roll x yieldMultiplier),
// D136); this only shows them. No ladder row -> multiplier 1, the base figure.
export function tierOf(tiers: HwTierInfo[] | undefined, worker: HwWorkerRow): HwTierInfo | undefined {
  return ladderFor(tiers, worker.profession).find((t) => tierRank(t.id) === tierRank(worker.tier));
}

// "5 h", "134 h": whole hours, no decimal (Fase 33 etapa 6, D277).
export function hoursText(hours: number): string {
  return `${Math.round(hours)} h`;
}

// Fase 33 etapa 6 (D277, V069 A3): the length a contract is sold for, in WHOLE hours and at
// least one - the same sum as WOSK_WorkerAliasScript.WholeHours (hours x multiplier, the half
// rounded up; the 0.0001 keeps an exact x.5 on the same side in Papyrus's float32 and here).
export const WHOLE_HOURS_ROUNDING = 0.5001;
export function hoursFor(task: HwTaskInfo, tier: HwTierInfo | undefined): number {
  return Math.max(1, Math.floor(task.hours * (tier?.durationMultiplier ?? 1) + WHOLE_HOURS_ROUNDING));
}

export function batchRangeFor(task: HwTaskInfo, tier: HwTierInfo | undefined): [number, number] {
  const m = tier?.yieldMultiplier ?? 1;
  return [Math.floor(task.batchMin * m), Math.floor(task.batchMax * m)];
}

// Fase 33 etapa 11 (G1, D295, no decimal in the game's money): a price in
// WHOLE gold, rounded UP, at least 1 for a positive one; 0 and a negative pass through. The DLL
// already sends the reference and the ingredients of one unit as whole gold, so this is the
// identity on them; it stays so that no figure the page prints can carry a decimal, and it is
// the same rule as WOSK_WorkerAliasScript.WholeGold, Core/DishPrice.h and core_model.whole_gold
// (vectors in plugin-skse/tests/fixtures/gold_rounding_vectors.txt). The 0.001 keeps a figure that is
// whole in exact arithmetic (float32 noise: 6.000000476837158) on the same side.
export const GOLD_EPSILON = 0.001;
export function wholeGold(n: number): number {
  if (!(n > 0)) return n;
  return Math.max(1, Math.ceil(n - GOLD_EPSILON));
}

// The price of ONE unit, or the ingredients of one, as the page prints it: the whole gold the
// charge works with, no decimal (replaces the one-decimal goldUnit and the two-decimal money of
// the earlier etapas).
export function goldWhole(n: number): string {
  return gold(wholeGold(n));
}

// Fase 33 etapa 10 (F1): what a contract of `units` units costs, the sum the game charges
// (WOSK_WorkerAliasScript.ContractCost): ceil(units x (reference x multiplier + ingredients)),
// an unresolved ingredient (-1) counting 0. Every step is rounded to float32, as Papyrus does,
// so an exact figure does not tip over a gold. One sum for the panel and the log: the vectors
// in plugin-skse/tests/fixtures/contract_cost_vectors.txt hold TypeScript, Python and Papyrus to it.
export function contractCost(units: number, reference: number, multiplier: number, ingredients: number): number {
  const f = Math.fround;
  const perUnit = f(f(f(reference) * f(multiplier)) + f(Math.max(ingredients, 0)));
  return Math.ceil(f(f(units) * perUnit));
}

// The estimate on the task: the smallest and the largest lot of the task (the base batch, not
// the tier's yield: the charge is worked out on the middle of the base lot and does not move
// with the tier). The real charge is the middle one, and lower where the site has few veins.
export function contractRange(task: HwTaskInfo): [number, number] {
  const mult = task.priceMultiplier ?? 1;
  const ing = task.ingredientCostPerUnit ?? 0;
  return [
    contractCost(task.batchMin, task.basePricePerUnit, mult, ing),
    contractCost(task.batchMax, task.basePricePerUnit, mult, ing),
  ];
}

// "Contract: ~48-76 gold"; "" when the task has no price in this game (nothing to charge for).
export function contractText(task: HwTaskInfo): string {
  if (!(task.basePricePerUnit > 0) || (task.ingredientCostPerUnit ?? 0) < 0) return "";
  const [lo, hi] = contractRange(task);
  return lo === hi ? `Contract: ~${gold(lo)} gold` : `Contract: ~${gold(lo)}-${gold(hi)} gold`;
}

export function taskLabel(tasks: HwTaskInfo[], taskId: string): string {
  const t = tasks.find((x) => x.id.toLowerCase() === (taskId || "").toLowerCase());
  return t ? t.label : taskId || "a contract";
}

// "Today", "Yesterday", "3 days ago" - by calendar day, on the game clock.
export function dayLabel(day: number, now: number): string {
  const diff = Math.floor(now) - Math.floor(day);
  if (diff <= 0) return "Today";
  if (diff === 1) return "Yesterday";
  return `${diff} days ago`;
}

// --- statement (journal) -----------------------------------------------------

export type JournalKind = "ISSUED" | "RETURNED" | "INJURED" | "RETIRED" | "DIED" | string;

export interface JournalEntry {
  day: number;
  kind: JournalKind;
  name: string;
  taskId: string;
  qty: number;
  gold: number;
}

function num(text: string | undefined): number {
  const n = Number(text);
  return Number.isFinite(n) ? n : 0;
}

// day|KIND|name|taskId|qty|gold. A line with fewer fields still shows, with
// zeros: a line the page cannot fully read is still a line the player should see.
export function parseJournalLine(line: string): JournalEntry | null {
  if (!line) return null;
  const f = line.split("|");
  if (f.length < 2) return null;
  return { day: num(f[0]), kind: f[1], name: f[2] ?? "", taskId: f[3] ?? "", qty: num(f[4]), gold: num(f[5]) };
}

export interface WordedEntry {
  text: string;
  // Signed amount for the right-hand column, or null for no amount.
  amount: number | null;
  tone: "spent" | "earned" | "bad" | "plain";
}

export function wordJournal(e: JournalEntry, tasks: HwTaskInfo[]): WordedEntry {
  const who = e.name || "A worker";
  const task = taskLabel(tasks, e.taskId);
  switch (e.kind) {
    case "ISSUED":
      return { text: `${who} sent out: ${task}`, amount: -e.gold, tone: "spent" };
    case "RETURNED":
      return { text: `${who} brought back ${e.qty} unit(s): ${task}`, amount: e.gold, tone: "earned" };
    case "INJURED":
      return { text: `${who} came back injured`, amount: null, tone: "bad" };
    case "RETIRED":
      return { text: `${who} was badly hurt and retired`, amount: null, tone: "bad" };
    case "PENSIONED":
      return { text: `${who} was pensioned off`, amount: e.gold > 0 ? -e.gold : null, tone: "spent" };
    case "DIED":
      return { text: `${who} did not survive: ${task}`, amount: null, tone: "bad" };
    default:
      return { text: `${who}: ${e.kind}`, amount: null, tone: "plain" };
  }
}

// Newest day first, lines inside a day newest first.
export function groupJournal(payload: HwHistoryPayload | null): [string, JournalEntry[]][] {
  if (!payload) return [];
  const entries = payload.journal
    .map(parseJournalLine)
    .filter((e): e is JournalEntry => e !== null)
    .sort((a, b) => b.day - a.day);
  const groups = new Map<string, JournalEntry[]>();
  for (const e of entries) {
    const key = dayLabel(e.day, payload.now);
    const g = groups.get(key);
    if (g) g.push(e);
    else groups.set(key, [e]);
  }
  return [...groups.entries()];
}

// --- one worker's contracts --------------------------------------------------

export interface HistoryEntry {
  day: number;
  outcome: string;
  taskId: string;
  qty: number;
  cost: number;
  value: number;
}

export function parseWorkerHistory(text: string): HistoryEntry[] {
  if (!text) return [];
  return text
    .split(";")
    .map((line) => line.split("|"))
    .filter((f) => f.length >= 2)
    // Fase 31 (D251): Papyrus interns strings without case, so the outcome can arrive as
    // "success"; the colour and the wording compare the upper-case id.
    .map((f) => ({ day: num(f[0]), outcome: f[1].trim().toUpperCase(), taskId: f[2] ?? "", qty: num(f[3]), cost: num(f[4]), value: num(f[5]) }))
    .sort((a, b) => b.day - a.day);
}

// Fase 31 (D248): the Dismiss hint. The fee is worked out in Papyrus (it decays with
// the days of service); -1/undefined is "not known yet" and says nothing about gold.
export function dismissHint(fee: number | undefined): string {
  if (fee === undefined || fee < 0) return "Ends the employment.";
  if (fee === 0) return "Ends the employment, free of charge.";
  return `Ends the employment. Fee: ${gold(fee)} gold. A contract in progress is not refunded.`;
}

// Fase 31 conserto 1 (D257): the Dismiss slot of a retired worker is the pension. The
// number is the same one Papyrus sends for the fee (DismissalFee returns the pension).
export function pensionHint(fee: number | undefined): string {
  if (fee === undefined || fee < 0) return "Releases the place. The amount is on its way.";
  if (fee === 0) return "Releases the place, free of charge.";
  return `Releases the place for ${gold(fee)} gold. Any equipment you handed over is given back.`;
}

export function outcomeText(outcome: string): string {
  switch (outcome) {
    case "SUCCESS":
      return "Returned";
    case "MINOR":
      return "Injured";
    case "MAJOR":
      return "Retired, badly hurt";
    case "DEATH":
      return "Did not survive";
    default:
      return outcome;
  }
}

export function statsFor(payload: HwHistoryPayload | null, slot: number): HwWorkerStats | undefined {
  return payload?.workers.find((w) => w.slot === slot);
}

// --- what the hold still has (queue item 13) --------------------------------

// The reason ids arrive from Papyrus and are worded here (D127/D129).
// Anything unrecognised is printed as it came rather than hidden.
// Fase 33 etapa 9 (E3, V072): the ONE place a reason id is read. It arrives from Papyrus and
// can come back in the case of another string it collides with ("Depleted" reached the panel
// as a sentence on 1.6.1170); every comparison below goes through here, never `=== "X"`.
export function reasonId(row: HwSourceRow | undefined): string {
  return (row?.reason ?? "").trim().toUpperCase();
}

// "back in about 17 h" when the DLL has a forecast for a worked-out row, else "".
export function backText(row: HwSourceRow | undefined): string {
  const hours = row?.backInHours ?? 0;
  return hours > 0 ? `back in about ${hoursText(hours)}` : "";
}

// Fase 33 etapa 10 (F3): the reasons the page words. Anything else is shown as "Unknown", never
// dropped (the iron and silver tags that vanished in boot 085043 were a silent null).
const KNOWN_REASONS = ["", "OCCUPIED", "UNCONFIRMED", "DEPLETED", "NONE"];
export function isKnownReason(row: HwSourceRow | undefined): boolean {
  return KNOWN_REASONS.includes(reasonId(row));
}

// The source rows by task id, the id lowercased: a Papyrus string can come back in the case of
// another literal (D127/D129), and the task list and the source list are two different strings.
export function sourceIndex(sources: HwSourceRow[] | null | undefined): Map<string, HwSourceRow> {
  return new Map((sources ?? []).map((s) => [(s.taskId ?? "").toLowerCase(), s]));
}

// Fase 33 etapa 10 (F3): the row a task shows. A task the hold has NO source for (the DLL says
// so with holdSources 0) gets a "None here" row of its own, so it has a state like every other.
export function rowFor(index: Map<string, HwSourceRow>, task: HwTaskInfo): HwSourceRow | undefined {
  const row = index.get(task.id.toLowerCase());
  if (row) return row;
  if (task.holdSources === 0) return { taskId: task.id, veins: 0, units: -1, reason: "NONE" };
  return undefined;
}

// The "nothing to do here" sentence, in the words of the work (D292: "None here" on
// the tag, "nothing to mine in <hold>" in the line). "" profession keeps the old wording.
const NONE_WORDS: Record<string, string> = {
  miner: "nothing to mine in",
  hunter: "nothing to hunt in",
  herbalist: "nothing to gather in",
  fisher: "nothing to fish in",
  laborer: "nothing to work in",
  cook: "nowhere to cook in",
};
export function noneText(profession: string, hold: string, zone: boolean): string {
  const words = NONE_WORDS[profession.toLowerCase()];
  if (words) return `${words} ${hold}`;
  return zone ? `nowhere to do this in ${hold}` : `nothing to mine in ${hold}`;
}

// Fase 33 etapa 10: why a recruit candidate cannot be hired, worded here from the id Papyrus
// sends ("COOK_HOLD"). "" when nothing stops the hire; an id not known is shown as it came.
export function blockedText(c: { blocked?: string }): string {
  const id = (c.blocked ?? "").trim().toUpperCase();
  if (id === "") return "";
  if (id === "COOK_HOLD") return "You already employ a cook in this hold.";
  return `Cannot be hired now (${c.blocked})`;
}

// True when the task cannot be ordered because the hold has nothing for it.
export function noSource(row: HwSourceRow | undefined): boolean {
  return reasonId(row) === "NONE";
}

export function sourceText(row: HwSourceRow | undefined, hold: string, profession = ""): string {
  if (!row) return "";
  const reason = reasonId(row);
  if (reason === "NONE" && profession) return noneText(profession, hold, row.veins === -2);
  if (!isKnownReason(row)) return `no word on this site (${row.reason})`;
  const back = backText(row) ? ` - ${backText(row)}` : "";
  // Fase 15 (D153): a zone row arrives with veins -2.
  if (row.veins === -2) {
    // Fase 33 etapa 8 (D1): the cook's rows speak of the kitchen of his own house.
    const kitchen = row.place ? `the ${houseLabel(row.place)} kitchen` : "";
    if (kitchen) {
      if (row.units > 0) return `~${row.units} dish(es) left in ${kitchen}`;
      if (reason === "DEPLETED") return `${kitchen} has no more of this kind of dish${back}`;
    }
    if (row.units > 0) return `~${row.units} unit(s) to gather in ${hold}`;
    if (reason === "OCCUPIED") return `the grounds in ${hold} are held by enemies`;
    if (reason === "DEPLETED") return `worked out in ${hold} until it recovers${back}`;
    if (reason === "NONE") return `nowhere to do this in ${hold}`;
    return row.reason;
  }
  if (row.veins > 0) {
    return row.units >= 0 ? `${row.veins} vein(s), ~${row.units} ore in ${hold}` : `${row.veins} vein(s) in ${hold}`;
  }
  if (reason === "UNCONFIRMED") return `nobody has checked the ${hold} mines lately`;
  // "the whole site": IsCleared() is a property of the LCTN, so a hostile
  // OUTSIDE the cave still holds it.
  if (reason === "OCCUPIED") return `the ${hold} mines are still held - the whole site, outside the cave too`;
  if (reason === "DEPLETED") return `mined out in ${hold} until it grows back${back}`;
  if (reason === "NONE") return `nothing to mine in ${hold}`;
  return row.reason;
}

// --- what Papyrus answered to an order (Fase 17 B, D171) -------------------

export type SourceTone = "open" | "held" | "unknown" | "spent" | "none";

// A short tag for a task's source, from the same reason ids sourceText words.
// Fase 27 conserto 1 (D235): a task above the worker's tier says so; the source
// ("Available") is not what the player is told while the task is out of reach.
// Fase 33 etapa 10 (F3): `loaded` says the source list has arrived. With it, a task with no row
// (and an unknown reason) gets a generic "Unknown" tag instead of nothing; the page also tells
// the host (HostBridge.note) so the round's log carries the reason.
export function sourceTag(
  row: HwSourceRow | undefined,
  locked = false,
  loaded = false,
): { label: string; tone: SourceTone; hint?: string } | null {
  if (locked) return { label: "Locked", tone: "none" };
  if (!row) return loaded ? { label: "Unknown", tone: "unknown" } : null;
  const reason = reasonId(row);
  if (row.veins > 0|| (row.veins === -2 && row.units > 0)) return { label: "Available", tone: "open" };
  if (reason === "OCCUPIED") return { label: "Held", tone: "held" };
  if (reason === "UNCONFIRMED") return { label: "Unchecked", tone: "unknown" };
  // E3: "Worked out" carries the forecast as a hint when the DLL has one.
  if (reason === "DEPLETED") return { label: "Worked out", tone: "spent", hint: backText(row) || undefined };
  if (reason === "NONE") return { label: "None here", tone: "none" };
  return loaded || reason !== "" ? { label: "Unknown", tone: "unknown" } : null;
}

export interface WordedOutcome {
  text: string;
  ok: boolean;
}

// Ids are compared without case: a Papyrus string literal can come back in
// the case of another literal it collides with (D127/D129).
export function wordOutcome(o: HwOutcome, name: string): WordedOutcome {
  const action = (o.action || "").toLowerCase();
  const code = (o.code || "").toUpperCase();
  const arg = o.arg || "";
  const argUp = arg.toUpperCase();
  const who = name || "The worker";
  const say = (text: string, ok = false): WordedOutcome => ({ text, ok });
  if (code === "EMPTY") return say("Nobody is hired in that place any more.");
  if (action === "issue") {
    switch (code) {
      case "ISSUED":
        return say(
          argUp === "OCCUPIED"
            ? `Contract issued for ${gold(o.number)} gold. ${who} goes to a held site - the risk is high.`
            : argUp === "COOK"
              ? `Contract issued for ${gold(o.number)} gold. ${who} is preparing the meal.`
              : `Contract issued for ${gold(o.number)} gold. ${who} is on the way.`,
          true,
        );
      case "NOT_AVAILABLE":
        if (argUp === "WORKING") return say(`${who} is already out on a contract.`);
        if (argUp === "INJURED_MINOR") return say(`${who} is injured - cure them first.`);
        return say(`${who} cannot take work right now.`);
      case "UNKNOWN_TASK":
        return say(`${who} does not know this work.`);
      case "TIER":
        return say(`This work needs a ${tierName(arg)} worker.`);
      case "SOURCE":
        if (argUp === "OCCUPIED") return say("The site is still held. Confirm the occupied gamble to send them anyway.");
        if (argUp === "UNCONFIRMED") return say("Nobody has checked the mines lately - clear or visit one first.");
        // Fase 33 etapa 8 (D1): "KITCHEN|<house>" - which kitchen ran out; the number is the
        // hours until it recovers (0 = not known).
        if (argUp.startsWith("KITCHEN|")) {
          const kitchen = houseLabel(arg.split("|")[1] ?? "");
          return say(
            `The ${kitchen || "cook's"} kitchen has no more of this kind of dish for now.` +
              (o.number > 0 ? ` It recovers in about ${hoursText(o.number)}.` : ""),
          );
        }
        if (argUp === "DEPLETED") {
          return say(`The source is worked out until it recovers${o.number > 0 ? ` (about ${hoursText(o.number)})` : ""}.`);
        }
        if (argUp === "FORCED") return say("That source is not part of this hold.");
        return say("There is nowhere in this hold to do this work.");
      case "NO_DESTINATION":
        return say("The way to the source could not be found.");
      case "NO_VALUE":
        return say("Nothing this work produces has a value in this game.");
      case "INGREDIENTS":
        return say("The ingredients for this work are not available in this game.");
      case "GOLD":
        return say(`Not enough gold: the contract costs ${gold(o.number)}, you carry ${gold(Number(arg) || 0)}.`);
    }
  }
  if (action === "collect") {
    switch (code) {
      case "COLLECTED":
        return say(
          argUp === "HOUSECARL"
            ? `${o.number} unit(s) delivered to your housecarl.`
            : `${o.number} unit(s) collected from ${who}.`,
          true,
        );
      case "RESOLVED":
        return say("The contract ended on the road - there is nothing to collect.");
      case "NOT_READY":
        if (argUp === "TRAVELING_TO") return say(`${who} is still on the way to the source.`);
        if (argUp === "WORKING") return say(`${who} is still working at the source.`);
        if (argUp === "TRAVELING_BACK") return say(`${who} is still on the way back.`);
        return say(`${who} has no batch to collect.`);
      case "TOO_FAR":
        return say(`${who} is too far away - go to them to collect.`);
      case "NO_BATCH":
        return say(`${who} had nothing to hand over - the contract is closed.`);
      case "NO_HOUSECARL":
        return say("No housecarl is assigned for this hold.");
    }
  }
  if (action === "cure") {
    if (code === "CURED") return say(`${who} is back on their feet.`, true);
    if (code === "NOT_INJURED") return say(`${who} is not injured.`);
  }
  if (action === "home") {
    const where = houseLabel(arg);
    if (code === "OK") return say(`${who} now cooks at ${where}.`, true);
    if (code === "SAME") return say(`${who} already cooks at ${where}.`);
    if (code === "BUSY") return say(`${who} is out on a contract - change the house when the meal is done.`);
    if (code === "NOT_OWNED") return say(`You do not own ${where || "that house"}.`);
    if (code === "NOT_COOK") return say(`Only a cook needs a house.`);
  }
  if (action === "hire") {
    // D184: the panel was not opened by the Hiring Agent.
    if (code === "NOT_RECRUITER") return say("Talk to the Hiring Agent to hire.");
  }
  if (action === "dismiss") {
    if (code === "DISMISSED") return say(`${arg || who} has been dismissed.`, true);
    if (code === "PENSIONED") return say(`${arg || who} has been pensioned off.`, true);
    if (code === "PENSION_GOLD") return say(`The pension for ${who} is ${gold(o.number)} gold, you carry ${gold(Number(arg) || 0)}.`);
    if (code === "IN_PERSON") return say(`${who} is out on a contract - dismiss them in person.`);
    // Fase 31 (D248): the fee is the number, what the player carries is the arg.
    if (code === "GOLD") return say(`Dismissing ${who} costs ${gold(o.number)} gold, you carry ${gold(Number(arg) || 0)}.`);
  }
  // Unknown pair: shown as it came rather than hidden.
  return say(`${action}: ${code}${arg ? ` (${arg})` : ""}`);
}
