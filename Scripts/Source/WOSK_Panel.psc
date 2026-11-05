; Copyright (C) 2026 Awrawra
; SPDX-License-Identifier: GPL-3.0-only
; This file is part of Honest Work - Workers of Skyrim, free software under the
; GNU General Public License, version 3. See the LICENSE file at the repository root.

ScriptName WOSK_Panel Hidden

; D104 etapa 3: the operator panel's Recruit tab (HonestWork.dll,
; UI::PrismaPanel). Papyrus builds the candidate list - tier, profession and
; price live in StorageUtil, which the DLL cannot read - and the DLL draws it.
; Both calls only queue work for the main thread; neither waits for the view.

Function SetRecruitList(string[] asNames, string[] asProfessions, string[] asTiers, Int[] aiPrices, Int[] aiSpots, string[] asPlaces, Int aiCount, Int aiHired, Int aiCap, Int aiCanHire, string asMessage, string[] asBlocked) global native
; The first aiCount entries of each array are one candidate each. asPlaces
; (D161, Fase 16) is where each candidate stands, for the row. aiCanHire
; (D184, Fase 18) is 1 when the panel open now came from the recruiter's
; dialogue, else 0: the page shows the pool either way and hires only with 1.
; Fase 33 etapa 10: asBlocked is, per candidate, the id of the rule that stops the hire
; ("COOK_HOLD": the hold already has a cook) or ""; the page words it and greys the card.

Function OpenRecruit() global native
; Shows the panel and gives it focus. The Recruit tab appears after a
; SetRecruitList; opening the panel by its hotkey hides the tab again.

; Queue item 11: the Workers tab. Same shape as SetRecruitList, and pushed from
; WOSK_PanelBridgeScript.PushPanelState() on every contract state change, so the
; situation on screen changes while the panel stays open. aiCanIssue is 0/1 - a Bool array
; over this boundary is not something this project has proved, and an Int array
; is, so the flag crosses as an Int and the DLL narrows it.
Function SetWorkerList(string[] asNames, string[] asProfessions, string[] asTiers, string[] asHolds, string[] asStates, Float[] afHoursLeft, Int[] aiSlots, Int[] aiCanIssue, Int aiCount) global native
; The first aiCount entries of each array are one hired worker each.
; afHoursLeft is -1.0 where no contract is running.

; Queue item 13: what the hold still has, in front of each contract on the
; Issue tab. Pushed on the same beats as SetWorkerList, because a contract
; being issued or settled is exactly what changes these numbers.
;
; asReasons carries an ID, never a sentence: "" when the ore can be worked,
; otherwise "UNCONFIRMED", "OCCUPIED", "DEPLETED" or "NONE" (the hold lists no
; source of the type at all). The page words it. That keeps player-facing text
; off the Papyrus side of the boundary, where a label that collides with an id
; comes out wearing the id's case (D127 and D129).
; Fase 33 etapa 8 (D1): asPlaces is the house whose kitchen a row speaks of ("" for
; the others) and aiBackHours the whole hours until a worked-out row recovers
; (0 = not worked out or unknown). Ids and numbers, worded on the page.
Function SetSourceList(string[] asTaskIds, Int[] aiVeins, Int[] aiUnits, string[] asReasons, string asHold, Int aiCount, string[] asPlaces, Int[] aiBackHours) global native
; The first aiCount entries of each array are one task each, matched to the
; Issue tab's task list by id. aiUnits is veins x what the GAME says a vein of
; that type holds, rounded down - the ore in the ground, not the contract's
; batch arithmetic - and -1 where that yield is not known on this save yet.

; Fase 17 (D168): the history the Overview and Worker tabs draw. Pushed with
; SetWorkerList, from WOSK_PanelBridgeScript.PushPanelState().
; asJournal: the statement lines (WOSK_LedgerScript, day|KIND|name|taskId|qty|gold),
; oldest first. Per hired worker, matched by slot: contracts completed, gold
; spent on him, value he delivered, and his own contracts joined by ";".
; afNow is the game time in days, so the page can say "today" and "2 days ago".
Function SetHistory(string[] asJournal, Int aiJournalCount, Int[] aiSlots, Int[] aiCompleted, Int[] aiGoldSpent, Int[] aiValue, string[] asHistories, Int aiWorkerCount, Int aiTotalGold, Int aiTotalValue, Int aiTotalDone, Int aiActive, Float afNow) global native

; Fase 17 B (D171): the answer to an order given on the panel (issue, collect,
; cure, dismiss), so the page can say it on screen and not only in the corner
; message. asCode and asArg are ids, never sentences - the page words them
; (D127/D129). aiNumber is the gold charged or the units collected, else 0.
Function SetOutcome(string asAction, Int aiSlot, string asCode, string asArg, Int aiNumber) global native
