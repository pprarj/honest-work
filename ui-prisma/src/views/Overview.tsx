// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

import type { HwHistoryPayload, HwInitPayload, HwWorkerRow } from "../prisma-bridge";
import { capitalize, gold, groupJournal, stateLine, stateTone, statsFor, wordJournal } from "../model";
import { LiveText } from "./LiveText";

interface Props {
  config: HwInitPayload;
  workers: HwWorkerRow[] | null;
  history: HwHistoryPayload | null;
  onOpenWorker: (slot: number) => void;
}

// Fase 17 (D167): three large figures, the statement of the last days, and the
// workers as a table.
export function Overview({ config, workers, history, onOpenWorker }: Props) {
  const days = groupJournal(history);
  return (
    <div className="hw-view">
      <section className="hw-figures">
        <Figure value={history ? gold(history.goldSpent) : "-"} label="Gold spent on contracts" unit="" />
        <Figure value={history ? gold(history.valueDelivered) : "-"} label="Goods collected (value)" unit="counted when collected, at each task's reference price" accent />
        <Figure
          value={history ? String(history.active) : "-"}
          label="Contracts under way"
          unit={history ? `${history.contractsDone} completed` : ""}
        />
      </section>

      <div className="hw-columns">
        <section className="hw-card">
          <h2 className="hw-card-title">Statement</h2>
          {!history && <p className="hw-muted">Waiting for the statement...</p>}
          {history && days.length === 0 && (
            <p className="hw-muted">Nothing yet. Issue a contract and its cost, the batch and any injury land here.</p>
          )}
          {days.map(([day, entries]) => (
            <div key={day} className="hw-day">
              <h3 className="hw-day-title">{day}</h3>
              <ul className="hw-ledger">
                {entries.map((e, i) => {
                  const w = wordJournal(e, config.tasks);
                  return (
                    <li key={i} className={`hw-ledger-row hw-ledger-${w.tone}`}>
                      <span className="hw-ledger-text">{w.text}</span>
                      <span className="hw-ledger-amount">
                        {w.amount === null ? "" : `${w.amount > 0 ? "+" : "-"}${gold(Math.abs(w.amount))}`}
                      </span>
                    </li>
                  );
                })}
              </ul>
            </div>
          ))}
        </section>

        <section className="hw-card">
          <h2 className="hw-card-title">Workers</h2>
          {workers && workers.length === 0 && <p className="hw-muted">Nobody is hired yet.</p>}
          {workers && workers.length > 0 && (
            <table className="hw-table">
              <thead>
                <tr>
                  <th>Name</th>
                  <th>Profession</th>
                  <th>Tier</th>
                  <th>State</th>
                  <th className="hw-num">Delivered</th>
                </tr>
              </thead>
              <tbody>
                {workers.map((w) => {
                  const s = statsFor(history, w.slot);
                  return (
                    <tr key={w.slot} className="hw-table-link" onClick={() => onOpenWorker(w.slot)}>
                      <td className="hw-strong">{w.name}</td>
                      <td>{capitalize(w.profession)}</td>
                      <td>{w.tier}</td>
                      <td>
                        <span className={`hw-state hw-tone-${stateTone(w.state)}`}>
                          <span className="hw-dot" />
                          <LiveText text={stateLine(w)} />
                        </span>
                      </td>
                      <td className="hw-num">{s ? gold(s.valueDelivered) : "-"}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          )}
        </section>
      </div>
    </div>
  );
}

function Figure({ value, label, unit, accent }: { value: string; label: string; unit: string; accent?: boolean }) {
  return (
    <div className={accent ? "hw-figure is-accent" : "hw-figure"}>
      <span className="hw-figure-value">{value}</span>
      <span className="hw-figure-label">{label}</span>
      {unit && <span className="hw-figure-unit">{unit}</span>}
    </div>
  );
}
