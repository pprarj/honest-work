; Copyright (C) 2026 Awrawra
; SPDX-License-Identifier: GPL-3.0-only
; This file is part of Honest Work - Workers of Skyrim, free software under the
; GNU General Public License, version 3. See the LICENSE file at the repository root.

ScriptName WOSK_Backpack Hidden

; Fase 25 (D227): the miner and the hunter wear a backpack of
; the optional Creation Club "Backpacks" (ccfsvsse001-backpacks.esl) while a
; contract is running. Without the plugin nothing here does anything.
;
;   miner   ccFSVSSE001_Backpack_HunterFull         0x00080D  (fur pack)
;   hunter  ccFSVSSE001_Backpack_AdventurerBedroll  0x00080A  (leather, bedroll)
;
; The record names do not match the trade on purpose: the pick follows the
; chosen look, not the editor id.
;
; The plugin is ESL flagged: same three asks as WOSK_PlayerHouse.TundraLoaded()
; (IsPluginInstalled, light index, full index), checked before any
; GetFormFromFile so a game without the plugin gets no error line.

string Function PluginName() global
    return "ccfsvsse001-backpacks.esl"
EndFunction

Bool Function PluginLoaded() global
    string plugin = PluginName()
    if Game.IsPluginInstalled(plugin)
        return true
    endIf
    Int lightIndex = Game.GetLightModByName(plugin)
    if lightIndex >= 0 && lightIndex < Game.GetLightModCount()
        return true
    endIf
    Int fullIndex = Game.GetModByName(plugin)
    return fullIndex >= 0 && fullIndex < Game.GetModCount()
EndFunction

; The backpack of a profession, or None: other trades, plugin not loaded, or a
; record that does not resolve.
Armor Function BackpackFor(string asProfession) global
    Int formId = 0
    if asProfession == "miner"
        formId = 0x0000080D
    elseIf asProfession == "hunter"
        formId = 0x0000080A
    else
        return None
    endIf
    if !PluginLoaded()
        return None
    endIf
    return Game.GetFormFromFile(formId, PluginName()) as Armor
EndFunction

; Contract starts. Does nothing for the other trades. Trade with a backpack but
; no plugin: one info line per game session (flag cleared on every load by
; OnGameLoaded), never an error.
Function Wear(Actor akWorker, string asProfession) global
    ; Fase 34 etapa 2 (P12): no backpack on a follower; his inventory is his framework's.
    if !akWorker || WOSK_Followers.IsFollower(akWorker) || (asProfession != "miner" && asProfession != "hunter")
        return
    endIf
    Armor pack = BackpackFor(asProfession)
    if !pack
        if !StorageUtil.GetIntValue(None, "WOSK_BackpackAbsentLogged", 0)
            StorageUtil.SetIntValue(None, "WOSK_BackpackAbsentLogged", 1)
            Debug.Trace("WOSK_Backpack: " + PluginName() + " not loaded (or record missing), workers go without a backpack (info)")
        endIf
        return
    endIf
    if akWorker.GetItemCount(pack) < 1
        akWorker.AddItem(pack, 1, true)
    endIf
    Debug.Trace("WOSK_Backpack: wear - worker=" + akWorker + " profession=" + asProfession + " form=" + pack)
    akWorker.EquipItem(pack, false, true)
EndFunction

; Contract is over (IDLE, dismissal, death, retirement). Takes whichever of the
; two backpacks the worker carries, so a worker whose trade changed is clean
; too. Silent when there is nothing to take.
Function Strip(Actor akWorker) global
    if !akWorker || !PluginLoaded()
        return
    endIf
    StripOne(akWorker, 0x0000080D, "miner")
    StripOne(akWorker, 0x0000080A, "hunter")
EndFunction

Function StripOne(Actor akWorker, Int aiFormId, string asProfession) global
    Armor pack = Game.GetFormFromFile(aiFormId, PluginName()) as Armor
    if !pack || akWorker.GetItemCount(pack) < 1
        return
    endIf
    Debug.Trace("WOSK_Backpack: strip - worker=" + akWorker + " profession=" + asProfession + " form=" + pack)
    akWorker.UnequipItem(pack, false, true)
    akWorker.RemoveItem(pack, akWorker.GetItemCount(pack), true, None)
EndFunction

; Every load: the session flag of the absent-plugin line goes back to zero, and
; a worker in a running contract is put back in the pack (the item and its
; equipped state live in the save; this only covers what an outfit refresh or
; an older save lost). A worker out of contract is stripped.
Function Reconcile(Actor akWorker, string asProfession, Bool abContractRunning) global
    if !akWorker || WOSK_Followers.IsFollower(akWorker)
        return
    endIf
    if abContractRunning
        Armor pack = BackpackFor(asProfession)
        if pack && !akWorker.IsEquipped(pack)
            Wear(akWorker, asProfession)
        endIf
    else
        Strip(akWorker)
    endIf
EndFunction

Function OnGameLoaded() global
    StorageUtil.UnsetIntValue(None, "WOSK_BackpackAbsentLogged")
EndFunction
