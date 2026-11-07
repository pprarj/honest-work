; Copyright (C) 2026 Awrawra
; SPDX-License-Identifier: GPL-3.0-only
; This file is part of Honest Work - Workers of Skyrim, free software under the
; GNU General Public License, version 3. See the LICENSE file at the repository root.

ScriptName WOSK_Stump Hidden

; Fase 35 etapa 10 (D319): the firewood contract is cut at the nearest chopping block (the vanilla
; furniture WoodChoppingBlock) instead of the far sawmill. Global helpers only; the contract keeps
; its source (the sawmill, for the veins and the price) and swaps its destination for the block.

; The base form of the block, Skyrim.esm 0x0007022E (EditorID WoodChoppingBlock, keyword
; FurnitureWoodChoppingBlock), read from the record, not from memory.
Form Function BlockBase() global
    return Game.GetFormFromFile(0x0007022E, "Skyrim.esm")
EndFunction

; A placed block of Whiterun (WhiterunWorld) the search falls back to when nothing near the home is
; loaded: 0x00016D05 (cell WhiterunPlainsDistrict04) and 0x000CDD7A (the block of the Plains
; District house); both read from the REFR records, base WoodChoppingBlock. 0 ends the list.
Int Function Candidate(Int aiIndex) global
    if aiIndex == 0
        return 0x00016D05
    elseIf aiIndex == 1
        return 0x000CDD7A
    endIf
    return 0
EndFunction

; Fase 35 etapa 11 (D320): the block is chosen by the distance from the OUTSIDE of the worker's
; house, read from data (PapyrusUtil JSON, SKSE/Plugins/StorageUtilData/HonestWork/stumps.json):
; one door anchor per house and a list of blocks with their world position. Same world only:
; positions of two worldspaces do not compare. Nothing here needs a cell to be loaded.
string Function DataFile() global
    return "HonestWork/stumps.json"
EndFunction

; Fase 35 etapa 13 (D322, V109): the whole block flow (Pick, legs by distance, wait, cut, home tick) is
; off unless "stumpenabled" is 1.0 in the data file. Off (the default, also when the key is missing):
; firewood is fixed hours by the clock and closes at the end of them wherever the worker is.
Bool Function Enabled() global
    return JsonUtil.GetFloatValue(DataFile(), "stumpenabled", 0.0) >= 0.5
EndFunction

; Fase 35 etapa 12 (D321, V107): the file is typed ("float", "stringList", ... sections, keys in lower
; case) because the JsonUtil reads by type; a key it does not find used to fall to the default in
; silence. Now the miss is logged, once per read.
Float Function Param(string asKey, Float afDefault) global
    Float miss = -987654.0
    Float v = JsonUtil.GetFloatValue(DataFile(), asKey, miss)
    if v == miss
        Debug.Trace("WOSK_Stump: STUMP-DADO-VAZIO key='" + asKey + "' not found in " + DataFile() + " - default " + afDefault)
        return afDefault
    endIf
    return v
EndFunction

; The house a home marker belongs to ("breezehome", "tundra_homestead"), "" for any other home.
string Function HouseOfHome(ObjectReference akHome) global
    if !akHome
        return ""
    endIf
    if akHome == WOSK_PlayerHouse.HomeMarker("breezehome")
        return "breezehome"
    endIf
    if akHome == WOSK_PlayerHouse.HomeMarker("tundra_homestead")
        return "tundra_homestead"
    endIf
    return ""
EndFunction

; Hours of one way: distance / walking speed (real seconds), turned into game hours by the
; TimeScale global (0x00003A, Skyrim.esm; 20 by default), between a floor and a ceiling (data).
; Mirrored by an offline model of the same formula.
Float Function LegHours(Float afDist) global
    Float speed = Param("walkunitspersecond", 150.0)
    if speed < 10.0
        speed = 10.0
    endIf
    Float ts = 20.0
    GlobalVariable tsVar = Game.GetFormFromFile(0x0000003A, "Skyrim.esm") as GlobalVariable
    if tsVar && tsVar.GetValue() >= 1.0
        ts = tsVar.GetValue()
    endIf
    Float hours = afDist / speed * ts / 3600.0
    Float lo = Param("minleghours", 0.1)
    Float hi = Param("maxleghours", 3.0)
    if hours < lo
        hours = lo
    endIf
    if hours > hi
        hours = hi
    endIf
    return hours
EndFunction

; The chosen block by distance from the house door. None when the house has no anchor in the data
; (the caller falls back to Nearest). The distance goes to StorageUtil WOSK_StumpDist on the worker.
ObjectReference Function Pick(Actor akWorker, ObjectReference akHome) global
    StorageUtil.UnsetFloatValue(akWorker, "WOSK_StumpDist")
    string file = DataFile()
    string house = HouseOfHome(akHome)
    Int a = -1
    if house != ""
        a = JsonUtil.StringListFind(file, "anchorhouse", house)
    endIf
    if JsonUtil.StringListCount(file, "anchorhouse") == 0
        Debug.Trace("WOSK_Stump: STUMP-DADO-VAZIO the list 'anchorhouse' is empty or the file " + file + " was not read")
    endIf
    if a < 0
        Debug.Trace("WOSK_Stump: STUMP-PICK no anchor for house='" + house + "' (home=" + akHome + ") - the engine search stands")
        return None
    endIf
    string space = JsonUtil.StringListGet(file, "anchorspace", a)
    Float ax = JsonUtil.FloatListGet(file, "anchorx", a)
    Float ay = JsonUtil.FloatListGet(file, "anchory", a)
    Int n = JsonUtil.IntListCount(file, "stumpformid")
    Int best = -1
    Int second = -1
    Int third = -1
    Float bestD = 0.0
    Float secondD = 0.0
    Float thirdD = 0.0
    Int i = 0
    while i < n
        if JsonUtil.StringListGet(file, "stumpspace", i) == space
            Float dx = JsonUtil.FloatListGet(file, "stumpx", i) - ax
            Float dy = JsonUtil.FloatListGet(file, "stumpy", i) - ay
            Float d = Math.sqrt(dx * dx + dy * dy)
            if best < 0 || d < bestD
                third = second
                thirdD = secondD
                second = best
                secondD = bestD
                best = i
                bestD = d
            elseIf second < 0 || d < secondD
                third = second
                thirdD = secondD
                second = i
                secondD = d
            elseIf third < 0 || d < thirdD
                third = i
                thirdD = d
            endIf
        endIf
        i += 1
    endWhile
    if best < 0
        Debug.Trace("WOSK_Stump: STUMP-PICK house=" + house + " world=" + space + " no block listed in that world")
        return None
    endIf
    string next = ""
    if second >= 0
        next = " second=" + JsonUtil.StringListGet(file, "stumplabel", second) + "@" + (secondD as Int)
    endIf
    if third >= 0
        next += " third=" + JsonUtil.StringListGet(file, "stumplabel", third) + "@" + (thirdD as Int)
    endIf
    Debug.Trace("WOSK_Stump: STUMP-PICK house=" + house + " world=" + space + " chosen=" + JsonUtil.StringListGet(file, "stumplabel", best) + "@" + (bestD as Int) + next)
    ObjectReference blockRef = Game.GetFormFromFile(JsonUtil.IntListGet(file, "stumpformid", best), "Skyrim.esm") as ObjectReference
    if !blockRef || blockRef.GetBaseObject() != BlockBase()
        Debug.Trace("WOSK_Stump: STUMP-PICK the chosen block does not resolve to a chopping block - the engine search stands")
        return None
    endIf
    StorageUtil.SetFloatValue(akWorker, "WOSK_StumpDist", bestD)
    return blockRef
EndFunction

; The block's reference: from the nearest one the engine finds around the home (loaded cells), else
; the nearest placed one of the list, else None. The worker's position decides when he stands
; outdoors; indoors the first candidate (the one nearest to the city gate) stands for the home.
ObjectReference Function Nearest(Actor akWorker, ObjectReference akHome) global
    Form base = BlockBase()
    if !base
        Debug.Trace("WOSK_Stump: STUMP-BUSCA the base form does not resolve")
        return None
    endIf
    ObjectReference found = None
    if akHome && akHome.Is3DLoaded()
        found = Game.FindClosestReferenceOfTypeFromRef(base, akHome, 6000.0)
    endIf
    if !found && akWorker && akWorker.Is3DLoaded() && !akWorker.IsInInterior()
        found = Game.FindClosestReferenceOfTypeFromRef(base, akWorker, 6000.0)
    endIf
    if found
        Debug.Trace("WOSK_Stump: STUMP-BUSCA found by the engine around the home/worker: " + found)
        return found
    endIf
    Bool outdoors = akWorker && !akWorker.IsInInterior()
    ObjectReference best = None
    Float bestDist = 0.0
    Int i = 0
    while Candidate(i) != 0
        ObjectReference c = Game.GetFormFromFile(Candidate(i), "Skyrim.esm") as ObjectReference
        if c && c.GetBaseObject() == base
            Float d = 0.0
            if outdoors && akWorker.GetWorldSpace() == c.GetWorldSpace()
                d = akWorker.GetDistance(c)
            endIf
            if !best || (outdoors && d > 0.0 && d < bestDist)
                best = c
                bestDist = d
            endIf
        endIf
        i += 1
    endwhile
    Debug.Trace("WOSK_Stump: STUMP-BUSCA from the list: " + best + " dist=" + (bestDist as Int) + " outdoors=" + outdoors as Int)
    return best
EndFunction

; Fase 35 etapa 12 (D321): the firewood legs are ALWAYS computed. The distance Pick measured from the
; door anchor when there is one; otherwise from the real position, in the same world as the block:
; the house marker, else the worker. No usable position (another world, an unloaded cell): the data's
; defaultdistance, traced. Never the old thirds of the task length.
Float Function DistanceFor(Actor akWorker, ObjectReference akHome, ObjectReference akBlock, Float afPicked) global
    if afPicked > 0.0
        return afPicked
    endIf
    Float d = 0.0
    string from = "none"
    if akBlock
        WorldSpace ws = akBlock.GetWorldSpace()
        if akHome && ws && akHome.GetWorldSpace() == ws
            d = akHome.GetDistance(akBlock)
            from = "home marker"
        endIf
        if d <= 0.0 && akWorker && ws && akWorker.GetWorldSpace() == ws
            d = akWorker.GetDistance(akBlock)
            from = "worker"
        endIf
        if d <= 0.0 && akHome && akHome.GetParentCell() && akHome.GetParentCell() == akBlock.GetParentCell()
            d = akHome.GetDistance(akBlock)
            from = "same cell"
        endIf
    endIf
    if d <= 0.0
        d = Param("defaultdistance", 3000.0)
        from = "default (no position that compares)"
    endIf
    Debug.Trace("WOSK_Stump: STUMP-DIST no door anchor - distance " + (d as Int) + " from " + from)
    return d
EndFunction

; Fase 35 etapa 12 (D321, V107 "Activate does not put him on the block"): the cut is a PACK of ours,
; WOSK_Package_ChopAtBlock (HonestWork.esp 0x853), Sandbox template, radius 200 around the actor's
; LinkCustom02 reference, special furniture allowed - the cook's package aimed at the block instead
; of the pot. Vanilla precedent: HalfmoonMillHertChoppingSandbox7x11 (0x00083D8F).
Package Function ChopPackage() global
    return Game.GetFormFromFile(0x00000853, "HonestWork.esp") as Package
EndFunction

; Takes the worker to the block by package and holds him there; the lines say whether he is on it
; (inUse of the furniture, the current package) 2 s and 8 s later. Leaves with StopUse.
Function Use(Actor akWorker, ObjectReference akBlock) global
    if !akWorker || !akBlock
        return
    endIf
    Package pack = ChopPackage()
    if !pack
        Debug.Trace("WOSK_Stump: STUMP-USO the chop package does not resolve (HonestWork.esp 0x853) - nothing to do")
        return
    endIf
    WOSK_Native.SetLinkedRef(akWorker, akBlock, Game.GetFormFromFile(0x0005D5E7, "Skyrim.esm") as Keyword)
    ActorUtil.RemovePackageOverride(akWorker, pack)
    ActorUtil.AddPackageOverride(akWorker, pack, 30, 0)
    akWorker.EvaluatePackage()
    Utility.Wait(2.0)
    Debug.Trace("WOSK_Stump: STUMP-USO worker=" + akWorker + " block=" + akBlock + " inUse=" + akBlock.IsFurnitureInUse() as Int + " dist=" + (akWorker.GetDistance(akBlock) as Int) + " package=" + akWorker.GetCurrentPackage() + " ours=" + (akWorker.GetCurrentPackage() == pack) as Int)
    Utility.Wait(6.0)
    Debug.Trace("WOSK_Stump: STUMP-USO-2 worker=" + akWorker + " inUse=" + akBlock.IsFurnitureInUse() as Int + " dist=" + (akWorker.GetDistance(akBlock) as Int) + " package=" + akWorker.GetCurrentPackage() + " ours=" + (akWorker.GetCurrentPackage() == pack) as Int)
EndFunction

; The end of the work: the package goes off (safe when it was never on).
Function StopUse(Actor akWorker) global
    Package pack = ChopPackage()
    if akWorker && pack
        ActorUtil.RemovePackageOverride(akWorker, pack)
    endIf
EndFunction
