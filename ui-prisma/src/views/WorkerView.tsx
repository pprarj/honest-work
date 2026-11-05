// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

import { useEffect, useState } from "react";

import { HostBridge, type HwHistoryPayload, type HwInitPayload, type HwWorkerRow } from "../prisma-bridge";
import type { SendOrder } from "../App";
import { LiveText } from "./LiveText";
import {
  TIER_NUMERALS,
  type GearInfo,
  type HouseInfo,
  houseLabel,
  isProfession,
  workerShowsHouse,
  capitalize,
  dayLabel,
  dismissHint,
  gearLine,
  gold,
  ladderFor,
  outcomeText,
  parseWorkerHistory,
  stateLine,
  PICKUP_EMPTY,
  emptyBatchHint,
  pickupBlock,
  backLine,
  creditLine,
  injuredLine,
  isRetired,
  pensionHint,
  stateTone,
  statsFor,
  taskLabel,
  tierName,
  tierRank,
} from "../model";

interface Props {
  config: HwInitPayload;
  worker: HwWorkerRow | undefined;
  history: HwHistoryPayload | null;
  gear: GearInfo | undefined;
  dismissFee: number | undefined;
  house: HouseInfo | undefined;
  sendOrder: SendOrder;
  onNewContract: () => void;
}

// Fase 17 (D167): the selected worker - figures, the tier ladder, his own
// contracts and the orders. The orders send the same requests as before
// (Cure, Dismiss, Collect); Papyrus still refuses what it refuses, and the
// answer comes back on screen (Fase 17 B, D171).
export function WorkerView({ config, worker, history, gear, dismissFee, house, sendOrder, onNewContract }: Props) {
  const [confirmFire, setConfirmFire] = useState(false);
  useEffect(() => setConfirmFire(false), [worker?.slot]);

  if (!worker) {
    return (
      <div className="hw-view">
        <div className="hw-empty">
          <h2 className="hw-empty-title">No worker selected</h2>
          <p className="hw-muted">Hire a worker through the Hiring Agent at the inn, then pick them in the list on the left.</p>
        </div>
      </div>
    );
  }

  const stats = statsFor(history, worker.slot);
  const completed = stats?.completed ?? 0;
  const retired = isRetired(worker);
  const ladder = ladderFor(config.tiers, worker.profession);
  const rank = tierRank(worker.tier);
  const next = ladder.find((t) => tierRank(t.id) > rank);
  const current = ladder.find((t) => tierRank(t.id) === rank);
  // Fase 26: the bar runs from the CURRENT tier's own threshold (a Veteran at 15
  // of 30 is half way, not at 0/30).
  const base = current?.minContracts ?? 0;
  const span = next ? Math.max(next.minContracts - base, 1) : 1;
  const progress = next ? Math.max(0, Math.min(1, (completed - base) / span)) : 1;
  const toGo = next ? Math.max(next.minContracts - completed, 0) : 0;
  const contracts = parseWorkerHistory(stats?.history ?? "");
  const tone = stateTone(worker.state);
  const collectBlock = pickupBlock(worker);

  return (
    <div className="hw-view">
      <section className="hw-hero">
        <div className="hw-hero-id">
          <span className="hw-eyebrow">
            {capitalize(worker.profession)} - {worker.hold}
          </span>
          <h1 className="hw-hero-name">{worker.name}</h1>
          <span className={`hw-state hw-tone-${tone}`} title={stateLine(worker)}>
            <span className="hw-dot" />
            <LiveText text={stateLine(worker)} />
          </span>
          {tone === "hurt" && <span className="hw-muted hw-bad">{injuredLine(worker)}</span>}
          {tone === "ready" && <span className="hw-muted hw-good">{backLine(worker)}</span>}
          {retired && (
            <span className="hw-muted hw-bad">
              Badly hurt at work. {worker.name} keeps the place and takes no contract until the pension is paid.
            </span>
          )}
        </div>
        <div className="hw-hero-figures">
          <SmallFigure value={tierName(worker.tier)} label="Tier" />
          <SmallFigure value={String(completed)} label="Contracts completed" />
          <SmallFigure value={gold(stats?.goldSpent ?? 0)} label="Gold spent on contracts" />
          <SmallFigure value={gold(stats?.valueDelivered ?? 0)} label="Goods collected (value)" />
        </div>
      </section>

      <section className="hw-card">
        <div className="hw-card-head">
          <h2 className="hw-card-title">Tier</h2>
          <span className="hw-muted">
            {next
              ? toGo > 0
                ? `${toGo} more contract(s) completed alive to reach ${next.label}`
                : `Reaches ${next.label} on the next contract completed`
              : ladder.length > 0
                ? "The top of the trade"
                : ""}
          </span>
        </div>
        {ladder.length === 0 && <p className="hw-muted">The tier ladder arrives with the game data.</p>}
        {ladder.length > 0 && (
          <>
            <ol className="hw-ladder">
              {ladder.map((t) => {
                const r = tierRank(t.id);
                const state = r < rank ? "is-done" : r === rank ? "is-current" : t === next ? "is-next" : "is-locked";
                return (
                  <li key={t.id} className={`hw-rung ${state}`}>
                    <span className="hw-rung-node">{TIER_NUMERALS[r] ?? "?"}</span>
                    <span className="hw-rung-name">{t.label}</span>
                    <span className="hw-rung-req">
                      {t.minContracts === 0 ? "On hire" : `${t.minContracts} contracts`}
                    </span>
                  </li>
                );
              })}
            </ol>
            {next && (
              <div className="hw-progress" aria-label="Progress to the next tier">
                <span className="hw-progress-fill" style={{ width: `${Math.round(progress * 100)}%` }} />
                <span className="hw-progress-text">
                  {completed} / {next.minContracts}
                </span>
              </div>
            )}
          </>
        )}
      </section>

      {isProfession(worker.profession, "hunter") && (
        <section className="hw-card">
          <div className="hw-card-head">
            <h2 className="hw-card-title">Equipment</h2>
            <span className="hw-muted">{gearLine(gear) || "Nothing handed over yet."}</span>
          </div>
          <p className="hw-muted">
            A bow and arrows raise the batch, light armor lowers the risk. What you hand over is held to the hunter's
            tier. Stand next to {worker.name}, talk, and pick "I want to give you some equipment." Heavy armor is
            never accepted. Dismissed, the hunter hands it all back.
          </p>
        </section>
      )}

      <div className="hw-columns hw-columns-wide">
        <section className="hw-card">
          <h2 className="hw-card-title">Contracts</h2>
          {contracts.length === 0 && (
            <p className="hw-muted">
              {stats ? creditLine(completed, worker) : "Waiting for the history..."}
            </p>
          )}
          {contracts.length > 0 && (
            <table className="hw-table">
              <thead>
                <tr>
                  <th>When</th>
                  <th>Work</th>
                  <th>Outcome</th>
                  <th className="hw-num">Batch</th>
                  <th className="hw-num">Paid</th>
                  <th className="hw-num">Goods (value)</th>
                </tr>
              </thead>
              <tbody>
                {contracts.map((c, i) => (
                  <tr key={i}>
                    <td className="hw-muted">{history ? dayLabel(c.day, history.now) : ""}</td>
                    <td>{taskLabel(config.tasks, c.taskId)}</td>
                    <td className={c.outcome === "SUCCESS" ? "hw-good" : "hw-bad"}>{outcomeText(c.outcome)}</td>
                    <td className="hw-num">{c.qty > 0 ? c.qty : "-"}</td>
                    <td className="hw-num">{c.cost > 0 ? gold(c.cost) : "-"}</td>
                    <td className="hw-num">{c.value > 0 ? gold(c.value) : "-"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </section>

        <section className="hw-card hw-orders">
          <h2 className="hw-card-title">Orders</h2>
          <Order
            label="New contract"
            hint={worker.canIssue ? "Pick the work on the Contracts tab." : "Only while the worker is awaiting work."}
            primary={worker.canIssue}
            disabled={!worker.canIssue}
            onClick={onNewContract}
          />
          <Order
            label="Collect"
            hint={
              collectBlock ||
              (tone === "ready"
                ? worker.hoursLeft === PICKUP_EMPTY
                  ? emptyBatchHint(worker)
                  : "The batch is waiting."
                : `${worker.name} has no batch waiting.`)
            }
            primary={tone === "ready" && !collectBlock}
            disabled={collectBlock !== "" || tone !== "ready"}
            onClick={() => sendOrder(`Collect from ${worker.name}.`, () => HostBridge.pickUp(worker.slot))}
          />
          <Order
            label="Cure"
            hint={
              tone === "hurt"
                ? injuredLine(worker)
                : retired
                  ? `${worker.name} is retired for good - no treatment helps.`
                  : `${worker.name} is not injured.`
            }
            primary={tone === "hurt"}
            disabled={tone !== "hurt"}
            onClick={() => sendOrder(`Cure ${worker.name}.`, () => HostBridge.cure(worker.slot))}
          />
          {/* Fase 33 etapa 2 (D267): a cook chooses which of the player's houses he cooks in. With one house nothing shows. */}
          {house && workerShowsHouse(worker.profession, house) && (
            <div className="hw-order">
              <div className="hw-button-row">
                {house.owned.map((id) => (
                  <button
                    key={id}
                    className={`hw-button hw-order-button${id === house.current ? " is-primary" : ""}`}
                    disabled={!house.open || id === house.current}
                    onClick={() =>
                      sendOrder(`Move ${worker.name} to ${houseLabel(id)}.`, () => HostBridge.setHouse(worker.slot, id))
                    }
                  >
                    {houseLabel(id)}
                  </button>
                ))}
              </div>
              <span className="hw-order-hint">
                {house.open
                  ? `${worker.name} cooks at ${houseLabel(house.current)}. Pick another house to move.`
                  : `${worker.name} is out on a contract - change the house afterwards.`}
              </span>
            </div>
          )}
          {!confirmFire && (
            <Order
              label={retired ? "Pay pension" : "Dismiss"}
              hint={retired ? pensionHint(dismissFee) : dismissHint(dismissFee)}
              danger
              onClick={() => setConfirmFire(true)}
            />
          )}
          {confirmFire && (
            <div className="hw-confirm">
              <p>
                {retired ? "Pension off" : "Dismiss"} {worker.name}?
                {dismissFee !== undefined && dismissFee > 0 ? ` It costs ${gold(dismissFee)} gold.` : ""}
              </p>
              <div className="hw-button-row">
                <button
                  className="hw-button is-danger"
                  onClick={() => {
                    sendOrder(retired ? `Pension off ${worker.name}.` : `Dismiss ${worker.name}.`, () =>
                      HostBridge.fire(worker.slot),
                    );
                    setConfirmFire(false);
                  }}
                >
                  {retired ? "Pay pension" : "Dismiss"}
                </button>
                <button className="hw-button" onClick={() => setConfirmFire(false)}>
                  Keep
                </button>
              </div>
            </div>
          )}
        </section>
      </div>
    </div>
  );
}

function SmallFigure({ value, label }: { value: string; label: string }) {
  return (
    <div className="hw-small-figure">
      <span className="hw-small-value">{value}</span>
      <span className="hw-small-label">{label}</span>
    </div>
  );
}

function Order(props: {
  label: string;
  hint: string;
  primary?: boolean;
  danger?: boolean;
  disabled?: boolean;
  onClick: () => void;
}) {
  const cls = ["hw-button", "hw-order-button", props.primary ? "is-primary" : "", props.danger ? "is-danger" : ""]
    .filter(Boolean)
    .join(" ");
  return (
    <div className="hw-order">
      <button className={cls} disabled={props.disabled} onClick={props.onClick}>
        {props.label}
      </button>
      <span className="hw-order-hint">{props.hint}</span>
    </div>
  );
}
