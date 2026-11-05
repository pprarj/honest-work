; Copyright (C) 2026 Awrawra
; SPDX-License-Identifier: GPL-3.0-only
; This file is part of Honest Work - Workers of Skyrim, free software under the
; GNU General Public License, version 3. See the LICENSE file at the repository root.

ScriptName WOSK_PlayerHouse Hidden

; Fase 24 (D223): the player's house in the hold, and the
; worker who lives in it. The cook is hired only when the player owns a house
; in Whiterun, moves into it on hire and cooks in its kitchen.
;
; Two houses for now, in this order (the first one owned wins):
;   "breezehome"        Breezehome, Skyrim.esm cell WhiterunBreezehome 0x000165A8
;   "tundra_homestead"  Tundra Homestead, Creation Club cceejsse001-hstead.esm
;
; How each one is read (measured, D223):
; - Breezehome: the cell's faction owner is PlayerFaction (0x00000DB1). The
;   vanilla purchase (HousePurchaseScript.PurchaseHouse) and the Alternate
;   Start - Live Another Life start that gives the house (its own
;   PurchaseHouse) both call HouseInterior.SetFactionOwner(PlayerFaction); the
;   cell record itself has no owner.
; - Tundra Homestead: its quest ccEEJSSE001_Quest (0x008C8) has stage 10 done.
;   That stage is the one fragment that marks the house owned
;   (CCHouse.SetHouseOwned(101)); the flag it sets is a plain script variable,
;   not a property, so it cannot be read from here.
;
; The houses are listed here, in code, and not in the JSON: the hold-sources
; schema the DLL reads is closed (ProfessionsRegistry.cpp SourceSchemaError),
; and a house needs a cell, a signal and a home marker it has no key for.

string Function TundraPlugin() global
    return "cceejsse001-hstead.esm"
EndFunction

; The professions that need a house. Only the cook (D223).
Bool Function RequiresHouse(string asProfession) global
    return asProfession == "cook"
EndFunction

; Which house of the hold the player owns: "breezehome", "tundra_homestead" or
; "" for none. Breezehome first. Tundra only with its plugin loaded - checked
; before any lookup, so a game without the Creation Club file reads "" and the
; Papyrus log gets nothing.
string Function OwnedHouse() global
    if OwnsHouse("breezehome")
        return "breezehome"
    endIf
    if OwnsHouse("tundra_homestead")
        return "tundra_homestead"
    endIf
    return ""
EndFunction

; Fase 33 etapa 2 (D267, V065, request: "choose the house the cook lives in"). Which house
; the player owns, as ids joined by "|", in the fixed order of the list above - what the
; panel offers. Ids and not names: the VM keeps one string per spelling without case
; (D127/D129), so the page words them itself.
string Function OwnedHouses() global
    string out = ""
    if OwnsHouse("breezehome")
        out = "breezehome"
    endIf
    if OwnsHouse("tundra_homestead")
        if out != ""
            out = out + "|"
        endIf
        out = out + "tundra_homestead"
    endIf
    return out
EndFunction

; The house a NEW cook moves into: the one the player chose in the panel (kept on the
; game, not on a worker) while he still owns it, else the first one owned (OwnedHouse).
string Function ChosenHouse() global
    string pref = StorageUtil.GetStringValue(None, "WOSK_PreferredHouse", "")
    if pref != "" && OwnsHouse(pref)
        return pref
    endIf
    return OwnedHouse()
EndFunction

; The panel's change of the cook's house. Answers a code the page words: OK, SAME,
; NOT_COOK, NOT_OWNED, BUSY. Only a cook with no running contract moves: he works at the
; pot of his house during a contract (D234), and taking him out of it in the middle would
; leave the contract on a pot he is no longer at - the change waits for the end of the
; contract (alternative discarded: move at once and restart the cooking in the new house).
; He is moved with MoveTo, not walked: the road between the two houses is doors and
; streets the travel package does not cross reliably (D105), and the move is logged after
; (AFTER-MOVE) so a cell that does not take him shows up.
string Function ChangeHouse(Actor akWorker, string asHouse) global
    if !akWorker || StorageUtil.GetStringValue(akWorker, "WOSK_Profession", "") != "cook"
        return "NOT_COOK"
    endIf
    if asHouse == "" || !OwnsHouse(asHouse)
        return "NOT_OWNED"
    endIf
    if StorageUtil.GetStringValue(akWorker, "WOSK_House", "") == asHouse
        return "SAME"
    endIf
    if StorageUtil.GetStringValue(akWorker, "WOSK_Contract", "IDLE") != "IDLE"
        Debug.Trace("WOSK_PlayerHouse: " + akWorker + " change to '" + asHouse + "' refused, contract " + StorageUtil.GetStringValue(akWorker, "WOSK_Contract", "IDLE"))
        return "BUSY"
    endIf
    Debug.Trace("WOSK_PlayerHouse: " + akWorker + " changes house '" + StorageUtil.GetStringValue(akWorker, "WOSK_House", "") + "' -> '" + asHouse + "' (panel)")
    if MoveIn(akWorker, asHouse)
        return "OK"
    endIf
    return "NOT_OWNED"
EndFunction

Bool Function OwnsHouse(string asHouse) global
    if asHouse == "breezehome"
        Cell house = Game.GetFormFromFile(0x000165A8, "Skyrim.esm") as Cell
        Faction playerFaction = Game.GetFormFromFile(0x00000DB1, "Skyrim.esm") as Faction
        return house && playerFaction && house.GetFactionOwner() == playerFaction
    elseIf asHouse == "tundra_homestead"
        if !TundraLoaded()
            return false
        endIf
        Quest houseQuest = Game.GetFormFromFile(0x000008C8, TundraPlugin()) as Quest
        return houseQuest && houseQuest.GetStageDone(10)
    endIf
    return false
EndFunction

; The plugin is ESM+ESL flagged, so it loads as a light plugin. Three asks, any
; one counts: IsPluginInstalled, the light index, the full index. The indexes
; are checked against the counts and not against a "not found" value, which
; Game.psc does not document (ASSUMPTION, F24.3 measures it).
Bool Function TundraLoaded() global
    string plugin = TundraPlugin()
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

; Where a worker who lives in the house stands between contracts: a persistent
; marker inside the house, so it resolves with the cell unloaded.
; Breezehome: XMarker 0x0001F88E (ground floor, ~270 units from the cooking pot
; 0x0010C061, which is not persistent). Tundra Homestead: its center marker
; ccEEJSSE001_CenterMarkerRef 0x00F99.
ObjectReference Function HomeMarker(string asHouse) global
    if asHouse == "breezehome"
        return Game.GetFormFromFile(0x0001F88E, "Skyrim.esm") as ObjectReference
    elseIf asHouse == "tundra_homestead" && TundraLoaded()
        return Game.GetFormFromFile(0x00000F99, TundraPlugin()) as ObjectReference
    endIf
    return None
EndFunction

; The hold source (hold_sources/10_whiterun_zones.json) a worker of this house
; works at: "<house>_kitchen".
string Function KitchenZone(string asHouse) global
    if asHouse == ""
        return ""
    endIf
    return asHouse + "_kitchen"
EndFunction

; A zone that belongs to a house - never picked at random.
Bool Function IsHouseZone(string asSourceId) global
    return asSourceId == "breezehome_kitchen" || asSourceId == "tundra_homestead_kitchen"
EndFunction

; The house a kitchen zone belongs to ("breezehome_kitchen" -> "breezehome"); "" for any
; other source. The inverse of KitchenZone.
string Function HouseOfKitchen(string asSourceId) global
    if asSourceId == "breezehome_kitchen"
        return "breezehome"
    elseIf asSourceId == "tundra_homestead_kitchen"
        return "tundra_homestead"
    endIf
    return ""
EndFunction

; Fase 33 etapa 8 (D1): what the player reads when the cook's kitchen has no more of this
; kind of dish. Which kitchen and when it is back; one literal per house, as in
; MovedIntoText (the VM keeps one string per spelling without case, D127/D129).
string Function KitchenWornOutText(string asHouse, Int aiHours) global
    if asHouse == "breezehome"
        return "Honest Work: the Breezehome kitchen has no more of this kind of dish for now. It recovers in about " + aiHours + " h."
    elseIf asHouse == "tundra_homestead"
        return "Honest Work: the Tundra Homestead kitchen has no more of this kind of dish for now. It recovers in about " + aiHours + " h."
    endIf
    return "Honest Work: this kitchen has no more of this kind of dish for now. It recovers in about " + aiHours + " h."
EndFunction

string Function HouseName(string asHouse) global
    if asHouse == "breezehome"
        return "Breezehome"
    elseIf asHouse == "tundra_homestead"
        return "Tundra Homestead"
    endIf
    return ""
EndFunction

; The sentence the player reads at the hire (Fase 26 conserto 1, D233). The house
; name sits inside a literal of its own, not in the return of HouseName: the VM
; keeps one string per spelling-regardless-of-case ("breezehome" is also the id of
; the house), and the first spelling it met came back for "Breezehome" in the
; notice of the rodada 2 (V057, print 211050). A longer literal is its own string.
string Function MovedIntoText(string asName, string asHouse) global
    if asHouse == "breezehome"
        return asName + " moved into Breezehome."
    elseIf asHouse == "tundra_homestead"
        return asName + " moved into Tundra Homestead."
    endIf
    return asName + " moved into your house."
EndFunction

; The sentence the player reads when the cook cannot be hired or sent to work.
string Function NeedsHouseText(string asName) global
    return asName + " needs a house of yours in Whiterun to live and cook in (Breezehome or Tundra Homestead)."
EndFunction

; DefaultSandboxCurrentLocation1024 (Skyrim.esm 0x000BFB6B), the package the
; candidates already stand on: keeps the worker inside the house while idle.
Package Function HomeSandbox() global
    return Game.GetFormFromFile(0x000BFB6B, "Skyrim.esm") as Package
EndFunction

; The house this worker lives in now, kept up to date: the stored one while the
; player still owns it; else the house the player owns now (his home moves
; there); else "" and the worker has no house any more.
string Function WorkerHouse(Actor akWorker) global
    if !akWorker
        return ""
    endIf
    string stored = StorageUtil.GetStringValue(akWorker, "WOSK_House", "")
    if stored != "" && OwnsHouse(stored)
        return stored
    endIf
    string owned = OwnedHouse()
    if owned != stored
        Debug.Trace("WOSK_PlayerHouse: " + akWorker + " house '" + stored + "' -> '" + owned + "'")
        if owned != ""
            _SetHouse(akWorker, owned)
        else
            ClearHouse(akWorker)
        endIf
    endIf
    return owned
EndFunction

; Hire (D223): the worker's home becomes the house marker and he is moved
; there at once, on the sandbox that keeps him inside.
Bool Function MoveIn(Actor akWorker, string asHouse) global
    ObjectReference marker = HomeMarker(asHouse)
    if !akWorker || !marker
        Debug.Trace("WOSK_PlayerHouse: MoveIn refused - worker=" + akWorker + " house='" + asHouse + "' marker=" + marker)
        return false
    endIf
    _SetHouse(akWorker, asHouse)
    Debug.Trace("WOSK_PlayerHouse: " + akWorker + " moves into " + HouseName(asHouse) + " at " + marker)
    akWorker.MoveTo(marker)
    StayHome(akWorker)
    ; Fase 33 etapa 2 (D263): where the move left him, for the hire and for the change.
    string dist = "n/a (other cell)"
    if akWorker.GetParentCell() == marker.GetParentCell()
        dist = "" + (akWorker.GetDistance(marker) as Int)
    endIf
    Debug.Trace("WOSK_PlayerHouse: AFTER-MOVE move in - worker=" + akWorker + " cell=" + akWorker.GetParentCell() + " houseCell=" + marker.GetParentCell() + \
                " loaded=" + akWorker.Is3DLoaded() + " dist=" + dist)
    return true
EndFunction

; The idle package at home, for a worker who lives in a house. Nothing for the
; others: their idle behaviour does not change.
Function StayHome(Actor akWorker) global
    if akWorker && StorageUtil.GetStringValue(akWorker, "WOSK_House", "") != ""
        ActorUtil.AddPackageOverride(akWorker, HomeSandbox(), 30, 0)
        akWorker.EvaluatePackage()
    endIf
EndFunction

Function LeaveHome(Actor akWorker) global
    if akWorker
        ActorUtil.RemovePackageOverride(akWorker, HomeSandbox())
    endIf
EndFunction

; Fase 28 (D234): the cooking pot of the house - the Furniture reference the cook
; works at during a contract. Breezehome: 0x0010C061 (CraftingCookingPotSmNoHandle,
; not persistent, enabled by WhiterunPlayerHouseDecorateKitchen). Tundra Homestead:
; 0x0000090F (persistent). None when the house has none or the plugin is not loaded.
ObjectReference Function CookingPot(string asHouse) global
    if asHouse == "breezehome"
        return Game.GetFormFromFile(0x0010C061, "Skyrim.esm") as ObjectReference
    elseIf asHouse == "tundra_homestead" && TundraLoaded()
        return Game.GetFormFromFile(0x0000090F, TundraPlugin()) as ObjectReference
    endIf
    return None
EndFunction

; WOSK_Package_CookAtPot (HonestWork.esp 0x84E): Sandbox template, radius 200
; around the LinkCustom02 linked reference of the actor.
Package Function CookPackage() global
    return Game.GetFormFromFile(0x0000084E, "HonestWork.esp") as Package
EndFunction

; The cook starts cooking: the pot becomes his LinkCustom02 target and the package
; replaces the home sandbox until StopCooking. Idempotent - it is also what puts
; the cook back on the pot after a load (the link is lost on load, V024) and what
; takes a contract issued by the build before this one off the travel and sandbox
; packages it was left with. Returns false, and changes nothing, when the house has
; no pot to work at (none resolved, or the kitchen not set up): the cook then stays
; on the home sandbox and the contract runs on its clock as it always did (D234).
Bool Function StartCooking(Actor akWorker) global
    if !akWorker
        return false
    endIf
    string house = WorkerHouse(akWorker)
    ObjectReference pot = CookingPot(house)
    Package cookPackage = CookPackage()
    if !pot || !cookPackage
        Debug.Trace("WOSK_PlayerHouse: " + akWorker + " has no pot to cook at - house='" + house + "' pot=" + pot + " package=" + cookPackage)
        return false
    endIf
    if pot.IsDisabled()
        Debug.Trace("WOSK_PlayerHouse: " + akWorker + " pot " + pot + " is disabled (kitchen not set up) - stays on the home sandbox")
        return false
    endIf
    Keyword linkKeyword = Game.GetFormFromFile(0x0005D5E7, "Skyrim.esm") as Keyword
    WOSK_Native.SetLinkedRef(akWorker, pot, linkKeyword)
    ActorUtil.RemovePackageOverride(akWorker, Game.GetFormFromFile(0x000235E2, "Skyrim.esm") as Package)
    ActorUtil.RemovePackageOverride(akWorker, Game.GetFormFromFile(0x000DD837, "Skyrim.esm") as Package)
    ActorUtil.RemovePackageOverride(akWorker, cookPackage)
    LeaveHome(akWorker)
    ActorUtil.AddPackageOverride(akWorker, cookPackage, 30, 0)
    akWorker.EvaluatePackage()
    Debug.Trace("WOSK_PlayerHouse: " + akWorker + " cooks at " + pot + " in " + HouseName(house))
    return true
EndFunction

; Fase 28 conserto 1 (D238, V060): probe for the cook who stayed upstairs for a whole
; contract with the cook line in the log. One MEDIDA-style line with what the first
; contract did not record: the package running, the LinkCustom02 target, the pot's
; state, the cells and the distance (and the floor difference). Read only.
Function ProbeCooking(Actor akWorker, string asWhy) global
    if !akWorker
        return
    endIf
    string house = StorageUtil.GetStringValue(akWorker, "WOSK_House", "")
    ObjectReference pot = CookingPot(house)
    Keyword linkKeyword = Game.GetFormFromFile(0x0005D5E7, "Skyrim.esm") as Keyword
    ObjectReference linked = akWorker.GetLinkedRef(linkKeyword)
    string potState = "pot=None"
    string where = ""
    if pot
        potState = "pot=" + pot + " potDisabled=" + pot.IsDisabled() + " pot3D=" + pot.Is3DLoaded() + " potCell=" + pot.GetParentCell()
        if pot.GetParentCell() == akWorker.GetParentCell()
            where = " dist=" + (akWorker.GetDistance(pot) as Int) + " dz=" + ((akWorker.GetPositionZ() - pot.GetPositionZ()) as Int)
        else
            where = " dist=n/a (other cell)"
        endIf
    endIf
    Debug.Trace("WOSK_PlayerHouse: COOK-PROBE " + asWhy + " - worker=" + akWorker + " package=" + akWorker.GetCurrentPackage() + " cookPackage=" + CookPackage() + \
                " overrides=" + ActorUtil.CountPackageOverride(akWorker) + " linkCustom02=" + linked + " " + potState + " workerCell=" + akWorker.GetParentCell() + \
                " pos=(" + (akWorker.GetPositionX() as Int) + "," + (akWorker.GetPositionY() as Int) + "," + (akWorker.GetPositionZ() as Int) + ") loaded=" + akWorker.Is3DLoaded() + \
                " sitting=" + akWorker.GetSitState() + " contract=" + StorageUtil.GetStringValue(akWorker, "WOSK_Contract", "IDLE") + where)
EndFunction

; The end of the cooking; the caller puts the home sandbox back (StayHome).
Function StopCooking(Actor akWorker) global
    if akWorker
        Package cookPackage = CookPackage()
        if cookPackage
            ActorUtil.RemovePackageOverride(akWorker, cookPackage)
        endIf
    endIf
EndFunction

Function ClearHouse(Actor akWorker) global
    if !akWorker
        return
    endIf
    StorageUtil.UnsetStringValue(akWorker, "WOSK_House")
    StorageUtil.UnsetFormValue(akWorker, "WOSK_WorkerHome")
    LeaveHome(akWorker)
EndFunction

Function _SetHouse(Actor akWorker, string asHouse) global
    StorageUtil.SetStringValue(akWorker, "WOSK_House", asHouse)
    ; SPEC 13.2, per worker: read first by WOSK_WorkerAliasScript._HomeTarget.
    StorageUtil.SetFormValue(akWorker, "WOSK_WorkerHome", HomeMarker(asHouse))
EndFunction
