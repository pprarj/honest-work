; Copyright (C) 2026 Awrawra
; SPDX-License-Identifier: GPL-3.0-only
; This file is part of Honest Work - Workers of Skyrim, free software under the
; GNU General Public License, version 3. See the LICENSE file at the repository root.

ScriptName WOSK_PlayerAliasScript extends ReferenceAlias

; Attached to the one Force-Ref-to-PlayerRef alias on WOSK_Controller.
; Enxuto de proposito: toda a logica vive em WOSK_ControllerScript, este
; script so encaminha os eventos que so existem em
; ReferenceAlias/ObjectReference/Actor, nunca em Quest (confirmado lendo os
; .psc reais da instalacao - Quest.psc nao declara
; OnCellLoad/OnLocationChange/OnPlayerLoadGame, ReferenceAlias.psc declara
; os tres).

WOSK_ControllerScript Property MainQuest Auto
; Wired via VMAD Object property at plugin generation time - target is
; WOSK_Controller itself (self-reference), not CK.

Event OnPlayerLoadGame()
    MainQuest.OnPlayerLoadGameHandler()
    RegisterEvents()
    StartTracker()
EndEvent

Event OnInit()
    RegisterEvents()
    StartTracker()
EndEvent

Event OnCellLoad()
    MainQuest.OnCellLoadHandler()
EndEvent

Event OnLocationChange(Location akOldLoc, Location akNewLoc)
    MainQuest.OnLocationChangeHandler(akOldLoc, akNewLoc)
EndEvent

; ---------------------------------------------------------------------------
; Mod event bridge - "o fluxo emitir-contrato -> mod event -> Papyrus". The
; plugin-skse operator panel has no other channel into Papyrus
; (Core::ModEventBridge.h there): it builds an SKSE::ModCallbackEvent and
; sends it via SKSE::GetModCallbackEventSource()->SendEvent() (confirmed
; this session). RegisterForModEvent/OnModEvent are real ReferenceAlias/
; Alias functions - already confirmed reading Alias.psc real source.
; Registered here (not on WOSK_ControllerScript, which is a Quest and
; cannot receive OnModEvent either - same reason it cannot receive
; OnCellLoad/OnLocationChange/OnPlayerLoadGame) and re-registered on every
; OnPlayerLoadGame in case a save/reload ever drops the registration (same
; defensive pattern OnCellLoad/OnLocationChange rely on the engine for, but
; mod event registration is explicitly documented upstream as needing a
; fresh RegisterForModEvent call per load in some cases - cheap to just
; always redo it).
Function RegisterEvents()
    RegisterForModEvent("WOSK_RequestIssueContract", "OnModEvent")
    RegisterForModEvent("WOSK_RequestOccupiedContract", "OnModEvent")
    RegisterForModEvent("WOSK_RequestCure", "OnModEvent")
    RegisterForModEvent("WOSK_RequestFire", "OnModEvent")
    RegisterForModEvent("WOSK_RequestPickUp", "OnModEvent")
    RegisterForModEvent("WOSK_RequestHire", "OnModEvent")
    ; Queue item 11: the panel opened and wants the Workers tab drawn. The
    ; bridge is one-way (C++ -> Papyrus), so "the DLL asks, Papyrus answers"
    ; is the only shape available - the worker state lives in StorageUtil.
    RegisterForModEvent("WOSK_PanelOpened", "OnModEvent")
    ; D184: the panel closed - the recruiter sign goes with it.
    RegisterForModEvent("WOSK_PanelClosed", "OnModEvent")
EndFunction

Event OnModEvent(string asEventName, string asStrArg, float afNumArg, Form akSender)
    Int aliasIndex = afNumArg as Int
    if asEventName == "WOSK_RequestIssueContract"
        WOSK_PanelBridgeScript.RequestIssueContract(aliasIndex, asStrArg)
    elseIf asEventName == "WOSK_RequestOccupiedContract"
        WOSK_PanelBridgeScript.RequestOccupiedContract(aliasIndex, asStrArg)
    elseIf asEventName == "WOSK_RequestCure"
        WOSK_PanelBridgeScript.RequestCure(aliasIndex)
    elseIf asEventName == "WOSK_RequestFire"
        WOSK_PanelBridgeScript.RequestFire(aliasIndex)
    elseIf asEventName == "WOSK_RequestPickUp"
        WOSK_PanelBridgeScript.RequestPickUp(aliasIndex)
    elseIf asEventName == "WOSK_RequestHire"
        WOSK_PanelBridgeScript.RequestHireFromPool(aliasIndex)
    elseIf asEventName == "WOSK_PanelOpened"
        ; D184: opened by the hotkey - no recruiter sign, and the Recruit
        ; list goes too (shown, not hireable).
        WOSK_ControllerScript c = WOSK_PanelBridgeScript.GetController()
        if c
            c.OnPanelOpenedByKey()
        endIf
        WOSK_PanelBridgeScript.PushPanelState()
    elseIf asEventName == "WOSK_PanelClosed"
        WOSK_ControllerScript closed = WOSK_PanelBridgeScript.GetController()
        if closed
            closed.OnPanelClosed()
        endIf
    endIf
EndEvent

; ---------------------------------------------------------------------------
; Worker tracker (queue item 12, scope 1) - TEST AID, off by default
; ---------------------------------------------------------------------------
;
; The problem behind V024 (2026-09-16): it could not be confirmed anywhere that
; the worker was on the road, and the only way to find out was to walk beside
; her. The Papyrus log already carries the position on every
; state change (_TracePosition, D105), but reading a log is not the same as
; letting time pass in game and checking.
;
; Turned on by [debug] worker_tracker_seconds in HonestWork.toml, read once at
; kDataLoaded, so it cannot change inside a session - the interval is read on
; every tick anyway because that costs one native call and keeps the two ends
; from drifting.
;
; The loop is HERE and not on WOSK_Controller's OnUpdate because that one
; already carries KeepHiringAgentName/RefillCandidatePool: re-arming it would
; run those every tick as a side effect of a debug toggle, and then the toggle
; would be changing what it is supposed to be observing.
Function StartTracker()
    UnregisterForUpdate()
    ; OnInit can reach this before the VMAD property is filled. A None
    ; here would only write a Papyrus error about a debug toggle nobody
    ; turned on; the next OnPlayerLoadGame arms it for real.
    if !MainQuest
        return
    endIf
    Int seconds = MainQuest.TrackerInterval()
    if seconds > 0
        RegisterForSingleUpdate(seconds as Float)
    endIf
EndFunction

Event OnUpdate()
    if !MainQuest
        return
    endIf
    Int seconds = MainQuest.TrackerInterval()
    if seconds <= 0
        return
    endIf
    MainQuest.ReportWorkerPositions()
    RegisterForSingleUpdate(seconds as Float)
EndEvent
