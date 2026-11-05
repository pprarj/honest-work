// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

import type { HwHistoryPayload, HwRecruitPayload, HwWorkerRow } from "../prisma-bridge";
import { capitalize, gold, stateLine, stateTone, statsFor, tierName } from "../model";
import { LiveText } from "./LiveText";

interface Props {
  workers: HwWorkerRow[] | null;
  history: HwHistoryPayload | null;
  selected: number | null;
  poolSize: number;
  recruit: HwRecruitPayload | null;
  onSelect: (slot: number) => void;
  onRecruit: () => void;
}

// Fase 17 (D167): the fixed left column - every hired worker, profession and
// tier small on top. Fase 33 etapa 9 (E2, replaces D285): line 1 is the name with what he
// has cost on the right, line 2 is the state at the full width of the card, wrapping to two
// lines at most and never cut with an ellipsis, so it cannot cover the gold. The card grows
// to fit. Candidates at the foot when the recruiter opened it.
export function Sidebar({ workers, history, selected, poolSize, recruit, onSelect, onRecruit }: Props) {
  const count = workers?.length ?? 0;
  const cap = recruit?.cap ?? poolSize;
  return (
    <aside className="hw-side">
      <div className="hw-side-head">
        <span className="hw-eyebrow">Workers</span>
        {cap > 0 && (
          <span className="hw-side-count">
            {count} / {cap}
          </span>
        )}
      </div>

      {workers === null && <p className="hw-muted hw-side-empty">Waiting for the worker list...</p>}
      {workers !== null && workers.length === 0 && (
        <p className="hw-muted hw-side-empty">Nobody is hired yet. The Hiring Agent at the inn takes on workers.</p>
      )}

      <ul className="hw-roster">
        {(workers ?? []).map((w) => {
          const stats = statsFor(history, w.slot);
          return (
            <li key={w.slot}>
              <button
                className={w.slot === selected ? "hw-roster-row is-selected" : "hw-roster-row"}
                onClick={() => onSelect(w.slot)}
              >
                <span className="hw-eyebrow">
                  {capitalize(w.profession)} - {w.tier}
                </span>
                <span className="hw-roster-line">
                  <span className="hw-roster-name">{w.name}</span>
                  <span className="hw-roster-figure">
                    <span className="hw-roster-number">{gold(stats?.goldSpent ?? 0)}</span>
                    <span className="hw-roster-unit">gold spent on contracts</span>
                  </span>
                </span>
                <span className={`hw-state hw-state-card hw-tone-${stateTone(w.state)}`} title={stateLine(w)}>
                  <span className="hw-dot" />
                  <LiveText text={stateLine(w)} />
                </span>
              </button>
            </li>
          );
        })}
      </ul>

      {recruit && (
        <div className="hw-side-foot">
          <div className="hw-side-head">
            <span className="hw-eyebrow">Candidates</span>
            <span className="hw-side-count">{recruit.candidates.length}</span>
          </div>
          {recruit.candidates.length === 0 && <p className="hw-muted hw-side-empty">No candidates right now.</p>}
          <ul className="hw-mini-list">
            {recruit.candidates.map((c) => (
              <li key={c.spot}>
                <button className="hw-mini-row" onClick={onRecruit}>
                  <span>
                    <span className="hw-mini-name">{c.name}</span>
                    <span className="hw-muted">
                      {" "}
                      {capitalize(c.profession)}, {tierName(c.tier)}
                    </span>
                  </span>
                  <span className="hw-mini-price">{gold(c.price)}</span>
                </button>
              </li>
            ))}
          </ul>
        </div>
      )}
    </aside>
  );
}
