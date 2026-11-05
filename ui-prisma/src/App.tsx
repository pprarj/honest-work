// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

import { useCallback, useEffect, useRef, useState } from "react";

import {
  HW_HISTORY_EVENT,
  HW_INIT_EVENT,
  HW_OUTCOME_EVENT,
  HW_RECRUIT_EVENT,
  HW_SOURCES_EVENT,
  HW_WORKERS_EVENT,
  HostBridge,
  type HwHistoryPayload,
  type HwInitPayload,
  type HwOutcome,
  type HwRecruitPayload,
  type HwSourcesPayload,
  type HwWorkerRow,
  type HwWorkersPayload,
  replayHostEvent,
} from "./prisma-bridge";
import { Sidebar } from "./views/Sidebar";
import { Overview } from "./views/Overview";
import { WorkerView } from "./views/WorkerView";
import { ContractsView } from "./views/ContractsView";
import { RecruitView } from "./views/RecruitView";
import { initialTabFor, parseGear, parseHouse, wordOutcome, withoutHiding, type GearInfo, type HouseInfo } from "./model";

// Fase 17 (D167): full-screen panel - workers in a fixed left column, tabs on
// top. The page draws and captures clicks; every rule stays in Papyrus (SPEC 8).
export type Tab = "overview" | "worker" | "contracts" | "recruit";

const TAB_LABELS: Record<Tab, string> = {
  overview: "Overview",
  worker: "Worker",
  contracts: "Contracts",
  recruit: "Recruit",
};

// Fase 17 B (D171): the line under the tabs that says what happened to the
// last order - sent, then Papyrus's answer (hwOutcome), or a note when no
// answer reaches the page (an older DLL, or an order Papyrus does not answer).
export interface Answer {
  id: number;
  kind: "pending" | "ok" | "refused" | "info";
  text: string;
  // The line a recruit list with nobody in it carries (D235).
  emptyList?: boolean;
}

// Gives the views one way to send an order: the request and the line together.
export type SendOrder = (text: string, request: () => void) => void;

const ANSWER_WAIT_MS = 4000;

function useHostEvent<T>(name: string, onDetail: (detail: T) => void): void {
  useEffect(() => {
    const handler = (e: Event) => onDetail((e as CustomEvent<T>).detail);
    window.addEventListener(name, handler);
    // C1: what the host sent before this listener existed (the bridge keeps the
    // last payload of every state event); the live events go on as before.
    const early = replayHostEvent<T>(name);
    if (early.found) onDetail(early.detail as T);
    return () => window.removeEventListener(name, handler);
    // onDetail is a state setter wrapper defined inline; the listener is
    // installed once, like the panel's other channels.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [name]);
}

export default function App() {
  const [config, setConfig] = useState<HwInitPayload | null>(null);
  const [tab, setTab] = useState<Tab>("overview");
  const [selected, setSelected] = useState<number | null>(null);
  const [recruit, setRecruit] = useState<HwRecruitPayload | null>(null);
  // Fase 32 (D254): the spots whose Hire is in flight, off the list until Papyrus answers.
  const [hiding, setHiding] = useState<ReadonlySet<number>>(new Set());
  const [workers, setWorkers] = useState<HwWorkerRow[] | null>(null);
  const [sources, setSources] = useState<HwSourcesPayload | null>(null);
  const [history, setHistory] = useState<HwHistoryPayload | null>(null);
  const [answer, setAnswer] = useState<Answer | null>(null);
  const [gear, setGear] = useState<Record<number, GearInfo>>({});
  const [fee, setFee] = useState<Record<number, number>>({});
  const [houses, setHouses] = useState<Record<number, HouseInfo>>({});
  const answerId = useRef(0);
  // The outcome listener is installed once; it reads names from here.
  const workersRef = useRef<HwWorkerRow[] | null>(null);
  workersRef.current = workers;
  // Fase 30: set by the hotkey opening (the host clears the Recruit list with a
  // null), consumed by the next worker list. The recruiter's opening and the
  // worker's own dialogue name their tab themselves and cancel it.
  const openPending = useRef(false);

  useHostEvent<HwInitPayload>(HW_INIT_EVENT, setConfig);
  // Queue item 11: pushed on every contract state change - arrives repeatedly
  // while the panel stays open, and never switches tabs by itself.
  useHostEvent<HwWorkersPayload | null>(HW_WORKERS_EVENT, (d) => {
    const rows = d ? d.workers : null;
    setWorkers(rows);
    // Fase 30: the first list after a hotkey opening picks the tab by what the
    // player has going on (initialTabFor); a list that arrives later never moves it.
    if (openPending.current) {
      openPending.current = false;
      const start = initialTabFor(rows);
      setTab(start.tab);
      if (start.slot !== null) setSelected(start.slot);
      // The answer of the last visit belongs to the last visit.
      setAnswer(null);
    }
  });
  useHostEvent<HwSourcesPayload | null>(HW_SOURCES_EVENT, setSources);
  useHostEvent<HwHistoryPayload | null>(HW_HISTORY_EVENT, setHistory);
  useHostEvent<HwOutcome>(HW_OUTCOME_EVENT, (o) => {
    if (!o) return;
    // Fase 26 (D228): the worker's own dialogue ("I have a new job for you")
    // opens the panel on THAT worker and on the Contracts tab. It is a word to
    // the page, not an answer to an order: nothing is worded or shown.
    if ((o.action || "").toLowerCase() === "focus") {
      openPending.current = false;
      setSelected(o.slot);
      setTab(((o.code || "").toUpperCase() === "CONTRACTS" ? "contracts" : "worker") as Tab);
      return;
    }
    // Fase 30: what a hunter carries, per slot; also a word to the page.
    if ((o.action || "").toLowerCase() === "gear") {
      setGear((cur) => ({ ...cur, [o.slot]: parseGear(o.arg || "") }));
      return;
    }
    // Fase 33 etapa 2 (D267): the cook's house and the houses to choose from; slot -1 is
    // the house a new cook moves into.
    if ((o.action || "").toLowerCase() === "house") {
      setHouses((cur) => ({ ...cur, [o.slot]: parseHouse(o.code || "", o.arg || "", o.number) }));
      return;
    }
    // Fase 31 (D248): what dismissing the worker in a slot costs, in the number.
    if ((o.action || "").toLowerCase() === "fee") {
      setFee((cur) => ({ ...cur, [o.slot]: o.number }));
      return;
    }
    const name = workersRef.current?.find((w) => w.slot === o.slot)?.name ?? "";
    const worded = wordOutcome(o, name);
    answerId.current += 1;
    setAnswer({ id: answerId.current, kind: worded.ok ? "ok" : "refused", text: worded.text });
  });
  // D184/D187: the Recruit tab shows whenever a list is in; null hides it.
  // Only the recruiter's list (canHire) jumps to the tab - a hotkey opening
  // stays where the player is.
  useHostEvent<HwRecruitPayload | null>(HW_RECRUIT_EVENT, (d) => {
    if (d === null) openPending.current = true;
    else if (d.canHire) openPending.current = false;
    // Any list from Papyrus is the truth: what was hidden for a Hire comes back if the list has it.
    setHiding(new Set());
    setRecruit(d);
    // The hire answer arrives as the refreshed list's message (D104).
    if (d && d.message) {
      answerId.current += 1;
      // A message under an EMPTY list is the "nobody found yet" line (D235): it
      // is flagged so a later list with candidates can take it away.
      setAnswer({ id: answerId.current, kind: "info", text: d.message, emptyList: d.candidates.length === 0 });
    } else if (d && d.candidates.length > 0) {
      // D235: a list that arrives with candidates and no message retires the
      // empty-list line; it leaves alone the answer to an order the player
      // just gave (Hire, refusal), which is not flagged.
      setAnswer((cur) => (cur && cur.emptyList ? null : cur));
    }
    setTab((current) => (d ? (d.canHire ? "recruit" : current) : current === "recruit" ? "overview" : current));
  });

  // The selection follows the list: the first worker when nothing is picked,
  // and the next one when the picked worker leaves (dismissed, died).
  useEffect(() => {
    if (!workers || workers.length === 0) {
      setSelected(null);
      return;
    }
    setSelected((cur) => (cur !== null && workers.some((w) => w.slot === cur) ? cur : workers[0].slot));
  }, [workers]);

  const sendOrder = useCallback<SendOrder>((text, request) => {
    answerId.current += 1;
    const id = answerId.current;
    setAnswer({ id, kind: "pending", text });
    request();
    window.setTimeout(() => {
      setAnswer((cur) =>
        cur && cur.id === id && cur.kind === "pending"
          ? { id, kind: "info", text: `${text} No answer reached the panel - see the game's corner message.` }
          : cur,
      );
    }, ANSWER_WAIT_MS);
  }, []);

  // The card leaves at the click. If no list arrives in time it comes back, with the
  // same "no answer" line sendOrder prints.
  const hideCandidate = useCallback((spot: number) => {
    setHiding((cur) => new Set(cur).add(spot));
    window.setTimeout(() => {
      setHiding((cur) => {
        if (!cur.has(spot)) return cur;
        const next = new Set(cur);
        next.delete(spot);
        return next;
      });
    }, ANSWER_WAIT_MS);
  }, []);

  const tabs: Tab[] = recruit ? ["overview", "worker", "contracts", "recruit"] : ["overview", "worker", "contracts"];

  useEffect(() => {
    const onKeyDown = (e: KeyboardEvent) => {
      // Lancamento 2: in game the native sink closes on Esc (the page never
      // saw the key, test 2026-09-14); this stays for the browser.
      if (e.key === "Escape") {
        HostBridge.closePanel();
        return;
      }
      if (e.altKey || e.ctrlKey || e.metaKey) return;
      const n = Number(e.key);
      if (n >= 1 && n <= tabs.length) {
        setTab(tabs[n - 1]);
        return;
      }
      if ((e.key === "ArrowDown" || e.key === "ArrowUp") && workers && workers.length > 0) {
        e.preventDefault();
        const i = workers.findIndex((w) => w.slot === selected);
        const step = e.key === "ArrowDown" ? 1 : -1;
        const next = workers[(Math.max(i, 0) + step + workers.length) % workers.length];
        setSelected(next.slot);
      }
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [tabs, workers, selected]);

  const worker = workers?.find((w) => w.slot === selected);

  // Fase 30 (V061): a line about an order belongs to the worker it was given to and
  // to the state it was given in. Picking another worker, or the worker's state
  // changing after the line has had a moment to be read, takes it away; an order
  // still waiting for its answer stays.
  const answerAt = useRef(0);
  useEffect(() => {
    answerAt.current = Date.now();
  }, [answer?.id, answer?.kind]);
  useEffect(() => {
    setAnswer((cur) => (cur && cur.kind !== "pending" ? null : cur));
  }, [selected]);
  const workerState = worker?.state;
  useEffect(() => {
    setAnswer((cur) => (cur && cur.kind !== "pending" && Date.now() - answerAt.current > 1500 ? null : cur));
  }, [workerState]);

  return (
    <div className="hw-screen">
      <div className="hw-frame">
        <header className="hw-header">
          <div className="hw-brand">
            <span className="hw-brand-title">Honest Work</span>
            <span className="hw-brand-sub">Workers of Skyrim{sources?.hold ? ` - ${sources.hold} Hold` : ""}</span>
          </div>
          <nav className="hw-tabs" role="tablist">
            {tabs.map((t, i) => (
              <button
                key={t}
                role="tab"
                aria-selected={tab === t}
                className={tab === t ? "hw-tab is-active" : "hw-tab"}
                onClick={() => setTab(t)}
              >
                <span className="hw-tab-key">{i + 1}</span>
                {TAB_LABELS[t]}
              </button>
            ))}
          </nav>
          <button className="hw-close" onClick={() => HostBridge.closePanel()} aria-label="Close">
            <span className="hw-tab-key">Esc</span>
            Close
          </button>
        </header>

        <div className="hw-body">
          <Sidebar
            workers={workers}
            history={history}
            selected={selected}
            poolSize={config?.workerPoolSize ?? 0}
            recruit={recruit}
            onSelect={(slot) => {
              setSelected(slot);
              if (tab === "overview" || tab === "recruit") setTab("worker");
            }}
            onRecruit={() => setTab("recruit")}
          />

          <main className="hw-main">
            {answer && (
              <div className={`hw-answer is-${answer.kind}`} role="status" aria-live="polite">
                <span className="hw-answer-mark" aria-hidden="true" />
                <span className="hw-answer-text">{answer.kind === "pending" ? `${answer.text} Waiting for the answer...` : answer.text}</span>
                <button className="hw-answer-close" onClick={() => setAnswer(null)} aria-label="Dismiss the message">
                  x
                </button>
              </div>
            )}
            {!config && <p className="hw-muted hw-wait">Waiting for Honest Work data...</p>}
            {config && tab === "overview" && (
              <Overview config={config} workers={workers} history={history} onOpenWorker={(slot) => {
                setSelected(slot);
                setTab("worker");
              }} />
            )}
            {config && tab === "worker" && (
              <WorkerView
                config={config}
                worker={worker}
                history={history}
                gear={worker ? gear[worker.slot] : undefined}
                dismissFee={worker ? fee[worker.slot] : undefined}
                house={worker ? houses[worker.slot] : undefined}
                sendOrder={sendOrder}
                onNewContract={() => setTab("contracts")}
              />
            )}
            {config && tab === "contracts" && (
              <ContractsView config={config} worker={worker} sources={sources} sendOrder={sendOrder} />
            )}
            {config && tab === "recruit" && recruit && <RecruitView recruit={withoutHiding(recruit, hiding)} house={houses[-1]} onHire={hideCandidate} employed={workers ? workers.length : recruit.hired} sendOrder={sendOrder} />}
          </main>
        </div>
      </div>
    </div>
  );
}
