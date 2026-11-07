; Copyright (C) 2026 Awrawra
; SPDX-License-Identifier: GPL-3.0-only
; This file is part of Honest Work - Workers of Skyrim, free software under the
; GNU General Public License, version 3. See the LICENSE file at the repository root.

ScriptName WOSK_PanelBridgeScript

; Global utility, no Extends, no VMAD attachment (SKSE Menu Framework panel
; does not exist yet). Every function here is callable with no live object
; reference needed (Game.GetFormFromFile(FormID, "HonestWork.esp") -
; confirmed real, used by the vanilla BYOHHouseBuildingScript.psc - resolves
; WOSK_Controller by its fixed FormID), which is exactly what a C++ panel
; button handler needs: a function it can call without first having to
; obtain a Quest reference of its own.
;
; All real decisions (cost, state machine, JSON/StorageUtil access) stay on
; WOSK_ControllerScript/WOSK_WorkerAliasScript - this script only looks the
; controller up and forwards.

WOSK_ControllerScript Function GetController() global
    Quest controllerQuest = Game.GetFormFromFile(0x00000800, "HonestWork.esp") as Quest
    return controllerQuest as WOSK_ControllerScript
EndFunction

; Queue item 11: the one door the live Workers tab goes through.
;
; The wiring problem it solves: every contract state change happens on a worker
; ALIAS (WOSK_WorkerAliasScript._AdvanceTo is the single funnel), while the
; panel list is built by the CONTROLLER, a different quest the alias holds no
; property for. Giving it one would mean a new VMAD property on four aliases -
; editable only by regenerating the plugin, and silently None if a binding is
; ever missed, which is the failure that writes nothing to any log. This script
; already owns the lookup for exactly that reason, so the push belongs here too.
;
; Silent about failure on purpose. It is called from the middle of contract
; work, and a panel that cannot be reached must never be the reason a contract
; does not advance.
Function PushPanelState() global
    WOSK_ControllerScript c = GetController()
    if c
        c.RefreshWorkerList()
        ; Queue item 13: the two lists go together on purpose. They are pushed
        ; at the same moments - a contract issued or settled changes both - and
        ; a separate entry point would be a second list of call sites to keep in
        ; step, which is the shape that leaves one of them stale.
        c.RefreshSourceList()
        ; Fase 17 (D168): the Overview and Worker tabs' history.
        c.RefreshHistory()
    endIf
EndFunction

; Fase 17 B (D171): what Papyrus answered to an order from the panel. Called
; at each place that already refuses or accepts it - no new rule, only the
; answer sent back. The last answer is also kept in StorageUtil (global
; WOSK_LastOutcome, "action|slot|code|arg|number") so the harness can read what
; the page was told. Like PushPanelState, it must never stop the order itself.
Function ReportOutcome(string asAction, Int aiSlot, string asCode, string asArg, Int aiNumber) global
    StorageUtil.SetStringValue(None, "WOSK_LastOutcome", asAction + "|" + aiSlot + "|" + asCode + "|" + asArg + "|" + aiNumber)
    WOSK_Panel.SetOutcome(asAction, aiSlot, asCode, asArg, aiNumber)
EndFunction

Int Function RequestHire(Actor akCandidate) global
    return GetController().HireCandidate(akCandidate)
EndFunction

; D104 etapa 3: the Recruit tab's hire button.
Int Function RequestHireFromPool(Int aiSpot) global
    return GetController().HireFromPool(aiSpot)
EndFunction

; Fase 34 etapa 2 (D299): the Recruit tab's follower section.
Function RequestHireFollower(Int aiIndex, string asProfession) global
    GetController().HireFollowerFromPanel(aiIndex, asProfession)
EndFunction

; Fase 35 etapa 8 (V100): the follower list again when a guard goes on or off an escort. Silent
; about failure, like PushPanelState.
Function PushGuardState() global
    WOSK_ControllerScript c = GetController()
    if c
        c.RefreshGuardState()
    endIf
EndFunction

; Fase 35 etapa 4 (D313, B9): the Recruit tab's Bodyguards section, button Assign.
Function RequestAssignGuard(Int aiIndex) global
    GetController().AssignGuardFromPanel(aiIndex)
EndFunction

Bool Function RequestIssueContract(Int aiAliasIndex, string asTaskId) global
    return GetController().RequestContract(aiAliasIndex, asTaskId, false)
EndFunction

; D137: panel confirm path for an occupied mine - only called after the panel's
; own warning dialog. The DLL calls this instead of RequestIssueContract.
Bool Function RequestOccupiedContract(Int aiAliasIndex, string asTaskId) global
    return GetController().RequestContract(aiAliasIndex, asTaskId, true)
EndFunction

Function RequestCure(Int aiAliasIndex) global
    GetController().RequestCure(aiAliasIndex)
EndFunction

Function RequestFire(Int aiAliasIndex) global
    GetController().RequestFire(aiAliasIndex)
EndFunction

Bool Function RequestPickUp(Int aiAliasIndex) global
    Quest workerPool = GetController().WorkerPool
    ReferenceAlias a = workerPool.GetAlias(aiAliasIndex) as ReferenceAlias
    if !a
        return false
    endIf
    ; Fase 28 conserto 1 (D238): the panel's Collect needs the worker near.
    return (a as WOSK_WorkerAliasScript).PickUp(true)
EndFunction

; D149 (Fase 12, V029 p.4): housecarl path - panel/dial calls this instead of
; RequestPickUp when the player asks the housecarl to collect.
Bool Function RequestCollectViaHousecarl(Int aiAliasIndex) global
    WOSK_ControllerScript c = GetController()
    if !c
        return false
    endIf
    return c.RequestCollectViaHousecarl(aiAliasIndex)
EndFunction
