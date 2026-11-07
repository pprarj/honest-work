// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

import { useState } from "react";
import { HostBridge, type HwFollowerRow, type HwFollowersPayload, type HwRecruitPayload } from "../prisma-bridge";
import type { SendOrder } from "../App";
import { TIER_NUMERALS, blockedText, capitalize, followerRefusalText, gold, houseLabel, parseFollowerTiers, recruitShowsHouse, sameId, tierName, tierRank, type HouseInfo } from "../model";

// Fase 34 etapa 2 (D299): one follower of the player. The trade is the player's choice;
// the tier is what his skill gives in that trade (shown before the click, worked out in Papyrus).
function FollowerCard({ f, full, sendOrder }: { f: HwFollowerRow; full: boolean; sendOrder: SendOrder }) {
  const tiers = parseFollowerTiers(f.tiers);
  const trades = Object.keys(tiers);
  const [trade, setTrade] = useState<string>(trades[0] ?? "");
  // Fase 35 etapa 10 (V104): one lock for the two buttons of the card; either click turns both off.
  const [busy, setBusy] = useState(false);
  const refusal = followerRefusalText(f.refused);
  const tier = tiers[trade] ?? "apprentice";
  return (
    <article className={refusal ? "hw-card hw-candidate is-blocked" : "hw-card hw-candidate"}>
      <div className="hw-candidate-head">
        <span className="hw-band-node">{TIER_NUMERALS[tierRank(tier)] ?? "?"}</span>
        <span className="hw-eyebrow">{refusal ? "Follower" : `${capitalize(trade)} - ${tierName(tier)}`}</span>
      </div>
      <h2 className="hw-candidate-name">{f.name}</h2>
      <span className="hw-muted">{f.place ? `At ${f.place}` : "With you"}</span>
      {refusal && <p className="hw-candidate-block">{refusal}</p>}
      {!refusal && (
        <div className="hw-button-row">
          {trades.map((t) => (
            <button key={t} className={`hw-button${t === trade ? " is-primary" : ""}`} onClick={() => setTrade(t)}>
              {capitalize(t)}
            </button>
          ))}
        </div>
      )}
      <div className="hw-candidate-foot">
        <span className="hw-price">
          Free
        </span>
        <button
          className="hw-button is-primary"
          disabled={!!refusal || full || trade === "" || busy}
          title={refusal || (full ? "No place free in this hold" : undefined)}
          onClick={() => {
            // Fase 35 etapa 9 (V102): one click; the button stays off until the list answers (the
            // hire waits 2 s for the framework, and four clicks in 1.8 s had hired him twice).
            setBusy(true);
            sendOrder(`Hire ${f.name} as ${trade}.`, () => HostBridge.hireFollower(f.index, trade));
            window.setTimeout(() => setBusy(false), 6000);
          }}
        >
          Hire
        </button>
        <button
          className="hw-button"
          disabled={!!refusal || busy}
          title={refusal || "Costs gold once. He then walks with a worker on a contract and cuts the risk of death."}
          onClick={() => {
            // Fase 35 etapa 6 (V096): one click; the button stays off until the list answers.
            setBusy(true);
            sendOrder(`Assign ${f.name} as a bodyguard.`, () => HostBridge.assignGuard(f.index));
            window.setTimeout(() => setBusy(false), 6000);
          }}
        >
          Bodyguard
        </button>
      </div>
    </article>
  );
}

// Fase 35 etapa 6: a bodyguard of the hold (refused "GUARD" marks the row). Release is free (the gold
// is not returned); the order carries -(1 + row). It stays off while he escorts a worker.
function GuardCard({ f, sendOrder }: { f: HwFollowerRow; sendOrder: SendOrder }) {
  const [busy, setBusy] = useState(false);
  const escorting = f.place.startsWith("Escorting");
  return (
    <article className="hw-card hw-candidate">
      <div className="hw-candidate-head">
        <span className="hw-eyebrow">Bodyguard</span>
      </div>
      <h2 className="hw-candidate-name">{f.name}</h2>
      <span className="hw-muted">{f.place}</span>
      <div className="hw-candidate-foot">
        <span className="hw-price">Release is free</span>
        <button
          className="hw-button"
          disabled={escorting || busy}
          title={escorting ? "He is escorting a worker; release him when the contract ends." : "He goes back to being your follower. The gold paid is not returned."}
          onClick={() => {
            setBusy(true);
            sendOrder(`Release ${f.name} as a bodyguard.`, () => HostBridge.releaseGuard(f.index));
          }}
        >
          Release
        </button>
      </div>
    </article>
  );
}

function FollowersSection({ followers, full, sendOrder }: { followers: HwFollowersPayload; full: boolean; sendOrder: SendOrder }) {
  if (followers.needsPo3) {
    return (
      <section>
        <h2 className="hw-eyebrow">Your followers</h2>
        <p className="hw-muted">This list needs powerofthree's Papyrus Extender, which is not installed.</p>
      </section>
    );
  }
  if (followers.followers.length === 0) return null;
  return (
    <section>
      <h2 className="hw-eyebrow">Your followers</h2>
      <div className="hw-cards">
        {followers.followers.map((f) =>
          sameId(f.refused, "GUARD") ? (
            <GuardCard key={`g${f.index}-${f.name}`} f={f} sendOrder={sendOrder} />
          ) : (
            <FollowerCard key={f.index} f={f} full={full} sendOrder={sendOrder} />
          )
        )}
      </div>
    </section>
  );
}

// Fase 17 B (D172): the Recruit tab (D104, D161) - candidates as cards, tier
// as a node, where each one waits, the price and the button. Papyrus answers a
// hire with a refreshed list and a message (D104), shown in the answer line.
export function RecruitView({ recruit, followers, employed, house, sendOrder, onHire }: { recruit: HwRecruitPayload; followers?: HwFollowersPayload | null; employed: number; house?: HouseInfo; sendOrder: SendOrder; onHire: (spot: number) => void }) {
  // Fase 26: the count follows the live worker list (pushed on every state
  // change); recruit.hired is only what the list said when it was pushed.
  const hired = employed;
  const full = hired >= recruit.cap;
  // D184: only the panel the Hiring Agent opened can hire.
  const canHire = recruit.canHire === true;
  return (
    <div className="hw-view">
      <section className="hw-hero hw-hero-compact">
        <div className="hw-hero-id">
          <span className="hw-eyebrow">Hiring Agent</span>
          <h1 className="hw-hero-name">Recruit</h1>
        </div>
        <div className="hw-hero-figures">
          <div className="hw-small-figure">
            <span className="hw-small-value">{recruit.candidates.length}</span>
            <span className="hw-small-label">Candidates</span>
          </div>
          <div className="hw-small-figure">
            <span className="hw-small-value">
              {hired} / {recruit.cap}
            </span>
            <span className="hw-small-label">Workers employed</span>
          </div>
        </div>
      </section>

      {!canHire && recruit.candidates.length > 0 && (
        <div className="hw-why hw-why-recruiter">
          <p>Talk to the Hiring Agent to hire. From here you can see who is looking for work, but only the agent signs new workers.</p>
        </div>
      )}

      {canHire && full && recruit.candidates.length > 0 && (
        <div className="hw-why">
          <p>
            You employ {hired} of {recruit.cap} workers allowed in this hold. Dismiss one, or come back when a
            place is free.
          </p>
        </div>
      )}

      {/* Fase 33 etapa 2 (D267): where a new cook moves in; shown only with more than one house. */}
      {house && recruitShowsHouse(canHire, house, recruit.candidates) && (
        <div className="hw-why">
          <p>A cook you hire moves into {houseLabel(house.current)}.</p>
          <div className="hw-button-row">
            {house.owned.map((id) => (
              <button
                key={id}
                className={`hw-button${id === house.current ? " is-primary" : ""}`}
                disabled={id === house.current}
                onClick={() => sendOrder(`New cooks move into ${houseLabel(id)}.`, () => HostBridge.setHouse(-1, id))}
              >
                {houseLabel(id)}
              </button>
            ))}
          </div>
        </div>
      )}

      {recruit.candidates.length === 0 && (
        <div className="hw-empty">
          <h2 className="hw-empty-title">No candidates right now</h2>
          <p className="hw-muted">New people looking for work turn up at the inns every few days.</p>
        </div>
      )}

      <div className="hw-cards">
        {recruit.candidates.map((c) => (
          <article key={c.spot} className={blockedText(c) ? "hw-card hw-candidate is-blocked" : "hw-card hw-candidate"}>
            <div className="hw-candidate-head">
              <span className="hw-band-node">{TIER_NUMERALS[tierRank(c.tier)] ?? "?"}</span>
              <span className="hw-eyebrow">
                {capitalize(c.profession)} - {tierName(c.tier)}
              </span>
            </div>
            <h2 className="hw-candidate-name">{c.name}</h2>
            <span className="hw-muted">{c.place ? `Waiting at ${c.place}` : "Waiting nearby"}</span>
            {blockedText(c) && <p className="hw-candidate-block">{blockedText(c)}</p>}
            <div className="hw-candidate-foot">
              <span className="hw-price">
                {gold(c.price)} <span className="hw-muted">gold</span>
              </span>
              {/* Fase 26: the card of a panel the recruiter did not open has no Hire at all. */}
              {canHire && (
                <button
                  className="hw-button is-primary"
                  disabled={full || !!blockedText(c)}
                  title={blockedText(c) || (full ? "No place free in this hold" : undefined)}
                  onClick={() => {
                    // D254: the card leaves the list now; Papyrus's list brings it back on a refusal.
                    onHire(c.spot);
                    sendOrder(`Hire ${c.name} for ${gold(c.price)} gold.`, () => HostBridge.hireCandidate(c.spot));
                  }}
                >
                  Hire
                </button>
              )}
            </div>
          </article>
        ))}
      </div>

      {followers && <FollowersSection followers={followers} full={full} sendOrder={sendOrder} />}
    </div>
  );
}
