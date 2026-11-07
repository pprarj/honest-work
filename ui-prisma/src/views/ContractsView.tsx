// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

import { useEffect, useState } from "react";

import {
  HostBridge,
  type HwFollowersPayload,
  type HwInitPayload,
  type HwSourceRow,
  type HwSourcesPayload,
  type HwTaskInfo,
  type HwWorkerRow,
} from "../prisma-bridge";
import type { SendOrder } from "../App";
import {
  TIER_NUMERALS,
  capitalize,
  batchRangeFor,
  contractText,
  goldWhole,
  durationText,
  guardBlockText,
  guardedContractText,
  isKnownReason,
  lowerFirst,
  noSource,
  reasonId,
  rowFor,
  sourceIndex,
  sourceTag,
  sourceText,
  stateLine,
  taskLocked,
  tierName,
  tierOf,
  tierRank,
} from "../model";

interface Props {
  config: HwInitPayload;
  worker: HwWorkerRow | undefined;
  sources: HwSourcesPayload | null;
  sendOrder: SendOrder;
  followers?: HwFollowersPayload | null;
}

// The unknown-source notes already sent to the host (once per task and reason, per page load).
const notedUnknown = new Set<string>();

// Fase 17 B (D172): the work of the selected worker's profession, as nodes in
// tier bands (I to IV), a band above the worker's tier locked with the tier it
// needs; a detail card with the facts and the button. Same requests as before
// (Fase 15 filter and lock, D137 occupied gamble); every refusal is Papyrus's
// and comes back on screen (D171).
export function ContractsView({ config, worker, sources, sendOrder, followers }: Props) {
  const [taskId, setTaskId] = useState("");
  const [occupiedConfirm, setOccupiedConfirm] = useState<string | null>(null);
  useEffect(() => setOccupiedConfirm(null), [worker?.slot, taskId]);

  // Fase 33 etapa 10 (F3): a task the page can only tag "Unknown" (no row, or a reason it does
  // not word) is told to the host once, so the round's log carries which task and why.
  useEffect(() => {
    if (!worker || !sources) return;
    const index = sourceIndex(sources.sources);
    for (const t of config.tasks) {
      if (t.profession.toLowerCase() !== worker.profession.toLowerCase()) continue;
      const row = rowFor(index, t);
      if (row && isKnownReason(row)) continue;
      const key = `${t.id}|${row ? row.reason : "no-row"}`;
      if (notedUnknown.has(key)) continue;
      notedUnknown.add(key);
      HostBridge.note(`task ${t.id} (${t.profession}) shows Unknown: ${row ? `reason '${row.reason}'` : "no source row"}, hold '${sources.hold}', holdSources ${t.holdSources ?? "absent"}`);
    }
  }, [config.tasks, sources, worker?.profession]);

  if (!worker) {
    return (
      <div className="hw-view">
        <div className="hw-empty">
          <h2 className="hw-empty-title">No worker selected</h2>
          <p className="hw-muted">Contracts are issued to a hired worker. Pick one in the list on the left.</p>
        </div>
      </div>
    );
  }

  const visible: HwTaskInfo[] = config.tasks.filter(
    (t) => t.profession.toLowerCase() === worker.profession.toLowerCase(),
  );
  const task: HwTaskInfo | undefined =
    visible.find((t) => t.id === taskId) ?? visible.find((t) => !taskLocked(t, worker)) ?? visible[0];
  // F3/F4 (etapa 10): ids matched without case; the hold is the worker's own, the source list's
  // only where the worker list has none (it said "THE HOLD" for Una and Aslaug before).
  const index = sourceIndex(sources?.sources);
  const rowOf = (t: HwTaskInfo): HwSourceRow | undefined => rowFor(index, t);
  const loaded = sources != null;
  const hold = worker.hold || sources?.hold || "";

  // Bands in tier order; a task with an unknown tier goes last, as it came.
  const bands = new Map<number, HwTaskInfo[]>();
  for (const t of visible) {
    const r = tierRank(t.minTier);
    const band = bands.get(r);
    if (band) band.push(t);
    else bands.set(r, [t]);
  }
  const ranks = [...bands.keys()].sort((a, b) => (a < 0 ? 99 : a) - (b < 0 ? 99 : b));
  const workerRank = tierRank(worker.tier);
  // Fase 26: hours and units of THIS worker's tier, not the base task.
  const tier = tierOf(config.tiers, worker);
  const [unitsMin, unitsMax] = batchRangeFor(task, tier);

  return (
    <div className="hw-view">
      <section className="hw-hero hw-hero-compact">
        <div className="hw-hero-id">
          <span className="hw-eyebrow">
            {capitalize(worker.profession)} - {tierName(worker.tier)} - {hold || "the hold"}
          </span>
          <h1 className="hw-hero-name">Work for {worker.name}</h1>
        </div>
        <div className="hw-hero-figures">
          <div className="hw-small-figure">
            <span className="hw-small-value">{visible.filter((t) => !taskLocked(t, worker)).length} / {visible.length}</span>
            <span className="hw-small-label">Open to this tier</span>
          </div>
        </div>
      </section>

      {visible.length === 0 && (
        <div className="hw-empty">
          <h2 className="hw-empty-title">No work here</h2>
          <p className="hw-muted">No {capitalize(worker.profession)} work is offered in {hold || "this hold"}.</p>
        </div>
      )}

      {task && (
        <div className="hw-columns hw-columns-contracts">
          <section className="hw-card">
            <h2 className="hw-card-title">Work by tier</h2>
            <ol className="hw-bands">
              {ranks.map((r) => {
                const open = workerRank < 0 || r < 0 || r <= workerRank;
                const tasks = bands.get(r) ?? [];
                return (
                  <li key={r} className={open ? "hw-band" : "hw-band is-locked"}>
                    <div className="hw-band-head">
                      <span className="hw-band-node">{TIER_NUMERALS[r] ?? "?"}</span>
                      <span className="hw-band-name">{tasks[0].minTierLabel || tierName(tasks[0].minTier)}</span>
                      <span className="hw-band-state">{open ? "Open" : `Locked - needs a ${tasks[0].minTierLabel}`}</span>
                    </div>
                    <div className="hw-band-tasks">
                      {tasks.map((t) => {
                        const locked = taskLocked(t, worker);
                        const tag = sourceTag(rowOf(t), locked, loaded);
                        return (
                          <button
                            key={t.id}
                            className={["hw-node", task.id === t.id ? "is-selected" : "", locked ? "is-locked" : ""].join(" ")}
                            onClick={() => setTaskId(t.id)}
                            aria-pressed={task.id === t.id}
                          >
                            <span className="hw-node-name">{t.label}</span>
                            <span className="hw-node-meta">
                              <span className="hw-node-hours">{durationText(t, tier)}</span>
                              {tag && (
                                <span className={`hw-tag hw-tag-${tag.tone}`} title={tag.hint}>
                                  {tag.label}
                                </span>
                              )}
                            </span>
                            {tag?.hint && <span className="hw-node-hint">{tag.hint}</span>}
                          </button>
                        );
                      })}
                    </div>
                  </li>
                );
              })}
            </ol>
          </section>

          <section className="hw-card hw-detail">
            <span className="hw-eyebrow">
              Tier {TIER_NUMERALS[tierRank(task.minTier)] ?? "?"} - {task.minTierLabel} work
            </span>
            <h2 className="hw-detail-title">{task.label}</h2>
            <SourceLine row={rowOf(task)} hold={hold} locked={taskLocked(task, worker)} loaded={loaded} profession={worker.profession} />
            <div className="hw-detail-figures">
              <Figure value={durationText(task, tier)} label="Duration" />
              <Figure value={`${unitsMin}-${unitsMax}`} label="Units" />
              <Figure value={`${Math.round(task.incidentChance * 100)}%`} label="Incident" />
              <Figure value={goldWhole(task.basePricePerUnit)} label="Gold a unit" />
            </div>
            {contractText(task) && <p className="hw-detail-line hw-contract-cost">{contractText(task)}</p>}
            {guardedContractText(task, config.guardFee) && (
              <p className="hw-detail-line hw-contract-cost">{guardedContractText(task, config.guardFee)}</p>
            )}
            {(task.ingredientCostPerUnit ?? 0) > 0 && (
              <p className="hw-detail-line">Ingredients: {goldWhole(task.ingredientCostPerUnit ?? 0)} gold a unit, at cost, in the price.</p>
            )}
            {(task.ingredientCostPerUnit ?? 0) < 0 && (
              <p className="hw-detail-line hw-bad">The ingredients for this work are not available in this game.</p>
            )}
            <p className="hw-muted hw-detail-note">
              The price per unit is the reference value of the output, in whole gold: the game's own value, raised where
              needed so a higher tier's contract pays more than the tier below it, and always at least a gold over the
              tier below. The contract cost is worked out from the middle of the lot when it is issued, and may come
              out lower where the site has few veins left.
            </p>
            <IssueButton
              task={task}
              worker={worker}
              row={rowOf(task)}
              occupiedConfirm={occupiedConfirm}
              setOccupiedConfirm={setOccupiedConfirm}
              sendOrder={sendOrder}
              guardBlock={guardBlockText(followers, worker.profession, task.id)}
            />
          </section>
        </div>
      )}
    </div>
  );
}

function Figure({ value, label }: { value: string; label: string }) {
  return (
    <div className="hw-figure-cell">
      <span className="hw-figure-value">{value}</span>
      <span className="hw-figure-label">{label}</span>
    </div>
  );
}

function SourceLine(props: {
  row: HwSourceRow | undefined;
  hold: string;
  locked: boolean;
  loaded: boolean;
  profession: string;
}) {
  const { row, hold, locked, loaded, profession } = props;
  const tag = sourceTag(row, locked, loaded);
  const text = sourceText(row, hold, profession);
  if (!tag && !text) return null;
  return (
    <p className="hw-source-line">
      {tag && <span className={`hw-tag hw-tag-${tag.tone}`}>{tag.label}</span>}
      <span>{text}</span>
    </p>
  );
}

function IssueButton(props: {
  task: HwTaskInfo;
  worker: HwWorkerRow;
  row: HwSourceRow | undefined;
  occupiedConfirm: string | null;
  setOccupiedConfirm: (id: string | null) => void;
  sendOrder: SendOrder;
  guardBlock: string;
}) {
  const { task, worker, row, occupiedConfirm, setOccupiedConfirm, sendOrder, guardBlock } = props;
  if (taskLocked(task, worker)) {
    // Not hidden and not silent: the task stays with the tier it needs.
    return (
      <div className="hw-why">
        <p>
          This work needs a {task.minTierLabel} worker. {worker.name} is {/^[aeiou]/i.test(tierName(worker.tier)) ? "an" : "a"}{" "}
          {tierName(worker.tier)} - the Worker tab shows how far the next tier is.
        </p>
      </div>
    );
  }
  if (!worker.canIssue) {
    return (
      <div className="hw-why">
        <p>
          {worker.name} is not awaiting work: {lowerFirst(stateLine(worker))}.
        </p>
        <button className="hw-button hw-button-wide" disabled>
          Issue contract
        </button>
      </div>
    );
  }
  if (noSource(row)) {
    // Fase 33 etapa 10 (F3, D292): a task the hold has no source for cannot be
    // ordered; the button stays, off, and the line above says why.
    return (
      <div className="hw-why">
        <p>The hold has nothing for this work, so there is no contract to issue.</p>
        <button className="hw-button hw-button-wide" disabled>
          Issue contract
        </button>
      </div>
    );
  }
  const occupied = reasonId(row) === "OCCUPIED";
  const site = row?.veins === -2 ? "The grounds are" : "The mines are";
  if (occupied && occupiedConfirm !== task.id) {
    return (
      <div className="hw-confirm">
        <p>{site} still held by enemies. A worker sent anyway faces a high incident risk (0.50).</p>
        <button className="hw-button is-danger hw-button-wide" onClick={() => setOccupiedConfirm(task.id)}>
          Send anyway...
        </button>
      </div>
    );
  }
  if (occupied) {
    return (
      <div className="hw-confirm">
        <p>Send {worker.name} to the held site? The contract is paid now and the risk is high.</p>
        <div className="hw-button-row">
          <button
            className="hw-button is-danger"
            onClick={() => {
              sendOrder(`Occupied contract: ${task.label} for ${worker.name}.`, () =>
                HostBridge.issueOccupiedContract(worker.slot, task.id),
              );
              setOccupiedConfirm(null);
            }}
          >
            Confirm (risk 0.50)
          </button>
          <button className="hw-button" onClick={() => setOccupiedConfirm(null)}>
            Cancel
          </button>
        </div>
      </div>
    );
  }
  return (
    <div className="hw-button-row">
      <button
        className="hw-button is-primary hw-button-wide"
        onClick={() => sendOrder(`Contract: ${task.label} for ${worker.name}.`, () => HostBridge.issueContract(worker.slot, task.id))}
      >
        Issue contract
      </button>
      <button
        className="hw-button hw-button-wide"
        disabled={guardBlock !== ""}
        title={guardBlock || "A bodyguard walks with the worker: a fee on top of the price, and a fifth of the risk of death."}
        onClick={() =>
          sendOrder(`Contract with a bodyguard: ${task.label} for ${worker.name}.`, () => HostBridge.issueContract(worker.slot, task.id, true))
        }
      >
        With bodyguard
      </button>
    </div>
  );
}
