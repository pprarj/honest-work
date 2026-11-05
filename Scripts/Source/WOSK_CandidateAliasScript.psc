; Copyright (C) 2026 Awrawra
; SPDX-License-Identifier: GPL-3.0-only
; This file is part of Honest Work - Workers of Skyrim, free software under the
; GNU General Public License, version 3. See the LICENSE file at the repository root.

ScriptName WOSK_CandidateAliasScript extends ReferenceAlias

; D104 etapa 2: on each of WOSK_CandidatePool's aliases (6 since
; Fase 16, D161, one per profession) - the
; candidates standing in the tavern. Replaces WOSK_CandidateScript, which sat
; on the placed reference and so could not watch a candidate created at run
; time.

ObjectReference Property TargetMarker Auto
; This alias's spot, wired via VMAD. Since Fase 16 (D161) the spot comes from
; candidate_pools/*.json and the candidate keeps the marker it was placed at
; (StorageUtil "WOSK_CandidateMarker"); this is the fallback.

Float Property WATCHDOG_DISTANCE_UNITS = 2000.0 Auto Hidden

; V017 (D101): only candidates are watched. A hired worker leaves this quest's
; aliases, so its position belongs to the contract.
Event OnLoad()
    Actor candidate = GetActorRef()
    if !candidate
        return
    endIf
    ObjectReference marker = StorageUtil.GetFormValue(candidate, "WOSK_CandidateMarker", None) as ObjectReference
    if !marker
        marker = TargetMarker
    endIf
    if marker && candidate.GetDistance(marker) > WATCHDOG_DISTANCE_UNITS
        Debug.Trace("WOSK_Candidate: " + candidate + " drifted from marker " + marker + ", forcing MoveTo")
        candidate.MoveTo(marker)
    endIf
EndEvent

; Fase 27 (D232): the player activating a candidate (the talk prompt) is what
; reveals him on the Recruit tab. ASSUMPTION: OnActivate reaches this alias when
; the player starts the dialogue (F27).
Event OnActivate(ObjectReference akActionRef)
    Actor candidate = GetActorRef()
    if candidate && akActionRef == Game.GetPlayer()
        WOSK_PanelBridgeScript.GetController().OnCandidateSpokenTo(candidate)
    endIf
EndEvent

; A candidate killed before being hired opens its spot, like a hire does.
Event OnDeath(Actor akKiller)
    Debug.Trace("WOSK_Candidate: " + GetActorRef() + " died (killer=" + akKiller + "), candidate spot opens")
    WOSK_PanelBridgeScript.GetController().OnCandidateDied(Self)
EndEvent
