; Copyright (C) 2026 Awrawra
; SPDX-License-Identifier: GPL-3.0-only
; This file is part of Honest Work - Workers of Skyrim, free software under the
; GNU General Public License, version 3. See the LICENSE file at the repository root.

ScriptName WOSK_WorkerState Hidden

; Fase 26 conserto 1 (D233): the worker's dialogue cannot read
; StorageUtil, so the contract state is mirrored as a rank in the hidden faction
; WOSK_WorkerStateFaction (HonestWork.esp 0x84D). The INFO conditions of the
; "new job" and "collect" lines read it (GetFactionRank, build_plugin.py
; WORKER_STATE_RANK_*). StorageUtil "WOSK_Contract" stays the truth; this is the
; copy the engine can see, written wherever the truth is written and rebuilt on
; every load.
;
;   rank 1  idle (no contract)             -> "I have a new job for you"
;   rank 2  traveling, working, coming back -> neither line
;   rank 3  batch awaiting pickup           -> "I want to collect the resources"
;   not in the faction (rank -1): state not known yet -> neither line
;
; "You're fired" depends on none of this: it shows for any hired worker.
; ('state' is a Papyrus keyword: the variables below are named stateFaction.)

Faction Function StateFaction() global
    return Game.GetFormFromFile(0x0000084D, "HonestWork.esp") as Faction
EndFunction

; The rank for a StorageUtil contract state string; 0 for one this build does
; not know (the worker then leaves the faction).
Int Function RankFor(string asContract) global
    if asContract == "IDLE"
        return 1
    elseIf asContract == "TRAVELING_TO" || asContract == "WORKING" || asContract == "TRAVELING_BACK"
        return 2
    elseIf asContract == "AWAITING_PICKUP"
        return 3
    endIf
    return 0
EndFunction

Function Mirror(Actor akWorker, string asContract) global
    if !akWorker
        return
    endIf
    Faction stateFaction = StateFaction()
    if !stateFaction
        Debug.Trace("WOSK_WorkerState: faction 0x84D missing, state of " + akWorker + " not mirrored")
        return
    endIf
    Int rank = RankFor(asContract)
    ; Fase 31 conserto 1 (D257): a worker retired by an accident stays on the list but
    ; takes no job and has nothing to collect: neither line shows ("You're fired" does,
    ; and it pays the pension).
    if StorageUtil.GetStringValue(akWorker, "WOSK_Lifecycle", "") == "RETIRED"
        rank = 0
    endIf
    if rank > 0
        akWorker.SetFactionRank(stateFaction, rank)
    else
        akWorker.RemoveFromFaction(stateFaction)
    endIf
    Debug.Trace("WOSK_WorkerState: " + akWorker + " contract " + asContract + " -> faction rank " + rank)
EndFunction

; Rebuilds the copy from the truth: the hire (a re-hired worker keeps his key),
; and every load (a worker hired before this existed has no rank at all).
Function Reconcile(Actor akWorker) global
    if !akWorker
        return
    endIf
    Mirror(akWorker, StorageUtil.GetStringValue(akWorker, "WOSK_Contract", "IDLE"))
    MirrorHunter(akWorker)
EndFunction

; Fase 31 (D247): the dialogue cannot read StorageUtil, so "this worker is a hunter" is
; mirrored as membership (rank 1) of a hidden faction, which the equipment line's INFO
; reads. Reconcile runs at the hire and on every load: hunters hired before this
; existed get the rank at the next load.
Faction Function HunterFaction() global
    return Game.GetFormFromFile(0x00000852, "HonestWork.esp") as Faction
EndFunction

Function MirrorHunter(Actor akWorker) global
    Faction hunterFaction = HunterFaction()
    if !akWorker || !hunterFaction
        return
    endIf
    if StorageUtil.GetStringValue(akWorker, "WOSK_Profession", "") == "hunter"
        akWorker.SetFactionRank(hunterFaction, 1)
    else
        akWorker.RemoveFromFaction(hunterFaction)
    endIf
EndFunction

; Dismissal and death: the worker is no longer anybody's worker.
Function Clear(Actor akWorker) global
    if !akWorker
        return
    endIf
    Faction stateFaction = StateFaction()
    if stateFaction
        akWorker.RemoveFromFaction(stateFaction)
    endIf
    Faction hunterFaction = HunterFaction()
    if hunterFaction
        akWorker.RemoveFromFaction(hunterFaction)
    endIf
EndFunction

; What the dialogue reads for this worker right now: the rank the actor holds,
; -1 when he is not in the faction. For the harness.
Int Function CurrentRank(Actor akWorker) global
    Faction stateFaction = StateFaction()
    if !akWorker || !stateFaction
        return -2
    endIf
    return akWorker.GetFactionRank(stateFaction)
EndFunction
