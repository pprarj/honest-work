; Copyright (C) 2026 Awrawra
; SPDX-License-Identifier: GPL-3.0-only
; This file is part of Honest Work - Workers of Skyrim, free software under the
; GNU General Public License, version 3. See the LICENSE file at the repository root.

ScriptName WOSK_DepletionScript Hidden

; D105 etapa 3: availability of a contract's source. Global functions only, no
; VMAD attachment. Replaces the lazy depletion of the original design (a pending batch
; per resource type that Disable()d up to 60% of the veins of whatever cell the
; player loaded next, anywhere in the world).
;
; The mod keeps its own memory per source, on the player, because a vein
; reference in an unloaded cell resolves to None until the game has changed it
; (measured 2026-09-16) - its state cannot be read before a contract:
;   WOSK_SrcUsed_<source>|<resourceType>  Int    veins used, reservations of
;                                                contracts still running included
;   WOSK_SrcTouch_<source>|<resourceType> Float  game day the memory of that type
;                                                was last touched (issue, resolution,
;                                                visit). Per type since Fase 33 etapa 8
;                                                (D1); older saves carry one per source,
;                                                seeded into each type once (_SeedStamp)
;   WOSK_SrcVisit_<source>                Float  game day the player was last in
;                                                the cell of a dungeon mine
; The memory lapses once the game's own respawn time passes since the last
; touch. The veins the player sees follow it: SyncVisibleDepletion calls the
; vanilla MineOreScript.depleteOreDueToFailure() on as many veins as the memory
; says are used, so they come back with the game's respawn.
;
; Decision B (2026-09-17): a dungeon mine whose Location is
; not cleared is OCCUPIED; cleared but not visited by the player within the
; respawn window is UNCONFIRMED; cleared and visited is CONFIRMED and preferred.
; Without a confirmed mine the contract goes to a SAFE source (open air); with
; none, it is refused before any gold changes hands.
;
; Fase 15: a source of kind "zone" (hunting ground, herb field) has no vein.
; It holds a simulated stock - "capacity" units of output per resource type -
; and the same memory counts units instead of veins: one unit is one slot
; (SourceUnitsPerSlot 1.0), so VeinsToReserve/CapDeliveredQty/VeinsUsed serve
; both. The memory of a zone lapses "recoveryDays" game days after the last
; touch, read from the JSON. Nothing in the world is changed for a zone.
;
; Pure logic mirrors the development reference model (SourceAvailabilityTests,
; ZoneSourceTests).

; ---------------------------------------------------------------------------
; Pure logic
; ---------------------------------------------------------------------------

; ASSUMPTION: the game settings below are the respawn times that apply to these
; sources - a cleared dungeon interior and any other cell. The vanilla values
; (720 and 240) are the fallback when the read gives 0 or less.
Int Function HoursToRespawnCleared() global
    Int hours = Game.GetGameSettingInt("iHoursToRespawnCellCleared")
    if hours <= 0
        return 720
    endIf
    return hours
EndFunction

Int Function HoursToRespawnCell() global
    Int hours = Game.GetGameSettingInt("iHoursToRespawnCell")
    if hours <= 0
        return 240
    endIf
    return hours
EndFunction

Int Function MemoryWindowHours(string asKind) global
    if asKind == "dungeonMine"
        return HoursToRespawnCleared()
    endIf
    return HoursToRespawnCell()
EndFunction

; afTouchDays < 0 means never touched.
Bool Function MemoryExpired(Float afNowDays, Float afTouchDays, Int aiWindowHours) global
    if afTouchDays < 0.0
        return true
    endIf
    return (afNowDays - afTouchDays) * 24.0 >= aiWindowHours as Float
EndFunction

; Veins taken when the contract is issued: enough for the largest batch the
; tier can roll, never more than the source has left.
Int Function VeinsToReserve(Float afBatchMax, Float afYieldMultiplier, Float afUnitsPerVein, Int aiRemaining) global
    if aiRemaining <= 0 || afUnitsPerVein <= 0.0
        return 0
    endIf
    Int maxQty = Math.Floor(afBatchMax * afYieldMultiplier)
    if maxQty < 1
        maxQty = 1
    endIf
    Int needed = Math.Ceiling((maxQty as Float) / afUnitsPerVein)
    if needed > aiRemaining
        return aiRemaining
    endIf
    return needed
EndFunction

; N_esperado, never above what the reserved veins hold.
Float Function CappedExpectedUnits(Float afBatchMin, Float afBatchMax, Float afUnitsPerVein, Int aiReserved) global
    Float expected = (afBatchMin + afBatchMax) / 2.0
    Float capacity = (aiReserved as Float) * afUnitsPerVein
    if capacity < expected
        return capacity
    endIf
    return expected
EndFunction

Int Function CapDeliveredQty(Int aiQty, Float afUnitsPerVein, Int aiReserved) global
    Int capacity = Math.Floor((aiReserved as Float) * afUnitsPerVein)
    if aiQty > capacity
        aiQty = capacity
    endIf
    if aiQty < 0
        return 0
    endIf
    return aiQty
EndFunction

Int Function VeinsUsed(Int aiQty, Float afUnitsPerVein, Int aiReserved) global
    if aiQty <= 0 || afUnitsPerVein <= 0.0
        return 0
    endIf
    Int used = Math.Ceiling((aiQty as Float) / afUnitsPerVein)
    if used > aiReserved
        return aiReserved
    endIf
    return used
EndFunction

; afVisitDays < 0 means the player was never recorded inside. abCleared is
; ignored for anything but a dungeon mine or a zone. A zone has no visit step:
; held is OCCUPIED, anything else SAFE (a zone without a location passes true).
string Function SourceState(string asKind, Int aiRemaining, Bool abCleared, Float afVisitDays, Float afNowDays, Int aiWindowHours) global
    if aiRemaining <= 0
        return "DEPLETED"
    endIf
    if asKind == "zone"
        if !abCleared
            return "OCCUPIED"
        endIf
        return "SAFE"
    endIf
    if asKind != "dungeonMine"
        return "SAFE"
    endIf
    if !abCleared
        return "OCCUPIED"
    endIf
    if afVisitDays < 0.0 || (afNowDays - afVisitDays) * 24.0 > aiWindowHours as Float
        return "UNCONFIRMED"
    endIf
    return "CONFIRMED"
EndFunction

; ---------------------------------------------------------------------------
; Registry reads
; ---------------------------------------------------------------------------

; D105 etapa 3: units of ore one vein gives the worker (professions JSON,
; optional "unitsPerVein"). 3.0 is the vanilla vein and the default.
Float Function UnitsPerVein(string asProfession, Int aiTaskIndex) global
    Float upv = WOSK_Registry.GetTaskFloat(asProfession, aiTaskIndex, "unitsPerVein", 3.0)
    if upv < 1.0
        return 3.0
    endIf
    return upv
EndFunction

; Fase 15: how many units of output one reserved slot is worth at this source -
; the task's unitsPerVein at a vein source, 1.0 at a zone (its slots are units).
Float Function SourceUnitsPerSlot(string asHold, string asSourceId, string asProfession, Int aiTaskIndex) global
    if IsZone(asHold, asSourceId)
        return 1.0
    endIf
    return UnitsPerVein(asProfession, aiTaskIndex)
EndFunction

Bool Function IsZone(string asHold, string asSourceId) global
    return WOSK_Registry.GetHoldSourceString(asHold, asSourceId, "kind", "") == "zone"
EndFunction

; True when the hold's sources of the type are zones (the first one decides: a
; resource type is either an ore or zone output, never both - the loader test
; ZoneSourceTests checks that the shipped data keeps them apart).
Bool Function TypeIsZone(string asHold, string asResourceType) global
    if WOSK_Registry.CountHoldSources(asHold, asResourceType) <= 0
        return StringUtil.Find(asResourceType, "ore_") != 0
    endIf
    return IsZone(asHold, WOSK_Registry.GetHoldSourceId(asHold, asResourceType, 0))
EndFunction

; Slots the source holds of the type when nothing is used: the vein count, or a
; zone's capacity. A zone answers for any type it lists; the caller already
; walks only the sources of the type (CountHoldSources/GetHoldSourceId).
Int Function SourceCapacity(string asHold, string asSourceId, string asResourceType) global
    if IsZone(asHold, asSourceId)
        Int capacity = WOSK_Registry.GetHoldSourceFloat(asHold, asSourceId, "capacity", 0.0) as Int
        if capacity < 0
            return 0
        endIf
        return capacity
    endIf
    return WOSK_Registry.CountHoldSourceVeins(asHold, asSourceId, asResourceType)
EndFunction

; The memory window of one source: a zone's own recoveryDays, else the game's
; respawn time for the kind (MemoryWindowHours). A zone with a missing or bad
; recoveryDays falls back to the open-air window.
Int Function SourceWindowHours(string asHold, string asSourceId) global
    string kind = WOSK_Registry.GetHoldSourceString(asHold, asSourceId, "kind", "")
    if kind == "zone"
        Float days = WOSK_Registry.GetHoldSourceFloat(asHold, asSourceId, "recoveryDays", 0.0)
        if days > 0.0
            Int hours = Math.Ceiling(days * 24.0)
            if hours < 1
                return 1
            endIf
            return hours
        endIf
    endIf
    return MemoryWindowHours(kind)
EndFunction

; Splits "PluginName.esp|0x00071CF3" and resolves
; it via Game.GetFormFromFile - a plugin|formid reference is never trusted as
; a raw FormID without the plugin name (load order index changes).
; Returns None if the string has no "|" or the hex
; part is malformed - never throws (a third-party JSON entry must not crash
; the game, D078).
; Validated first in the development reference model (parse_form_ref/
; hex_string_to_int/hex_digit_value, 14 cases) - StringUtil.Split/GetLength/
; GetNthChar confirmed native, Data/Scripts/Source/StringUtil.psc lines 16-45;
; no hex-string-to-int parser exists in vanilla/SKSE64/PapyrusUtil SE, so
; _HexToInt below is this project's own algorithm. Moved here from
; WOSK_WorkerAliasScript in etapa 3 so global code can resolve sources too.
Form Function ResolveFormRef(string asFormRef) global
    string[] parts = StringUtil.Split(asFormRef, "|")
    if parts.Length != 2
        return None
    endIf
    return Game.GetFormFromFile(_HexToInt(parts[1]), parts[0])
EndFunction

Int Function _HexToInt(string asHex) global
    string hex = asHex
    if StringUtil.GetLength(hex) >= 2 && (StringUtil.Substring(hex, 0, 2) == "0x" || StringUtil.Substring(hex, 0, 2) == "0X")
        hex = StringUtil.Substring(hex, 2)
    endIf
    Int len = StringUtil.GetLength(hex)
    if len == 0
        return 0
    endIf
    Int result = 0
    Int i = 0
    while i < len
        Int digit = _HexDigitValue(StringUtil.GetNthChar(hex, i))
        if digit < 0
            return 0
        endIf
        result = result * 16 + digit
        i += 1
    endwhile
    return result
EndFunction

Int Function _HexDigitValue(string asChar) global
    if asChar == "0"
        return 0
    elseIf asChar == "1"
        return 1
    elseIf asChar == "2"
        return 2
    elseIf asChar == "3"
        return 3
    elseIf asChar == "4"
        return 4
    elseIf asChar == "5"
        return 5
    elseIf asChar == "6"
        return 6
    elseIf asChar == "7"
        return 7
    elseIf asChar == "8"
        return 8
    elseIf asChar == "9"
        return 9
    elseIf asChar == "A" || asChar == "a"
        return 10
    elseIf asChar == "B" || asChar == "b"
        return 11
    elseIf asChar == "C" || asChar == "c"
        return 12
    elseIf asChar == "D" || asChar == "d"
        return 13
    elseIf asChar == "E" || asChar == "e"
        return 14
    elseIf asChar == "F" || asChar == "f"
        return 15
    endIf
    return -1
EndFunction

; ---------------------------------------------------------------------------
; Source memory
; ---------------------------------------------------------------------------

string Function _UsedKey(string asSourceId, string asResourceType) global
    return "WOSK_SrcUsed_" + asSourceId + "|" + asResourceType
EndFunction

; Fase 33 etapa 8 (D1, V071): the stamp is per source AND type. One stamp per source
; let a contract of "Pastries and feasts" renew the whole kitchen and push back the
; recovery of "Fine dishes", which had run out.
string Function _TouchKey(string asSourceId, string asResourceType) global
    return "WOSK_SrcTouch_" + asSourceId + "|" + asResourceType
EndFunction

; A save made before this etapa carries the stamp of the whole source
; (WOSK_SrcTouch_<source>). The first time a type of that source is read, its
; own stamp is seeded from it, once (the marker says it was): the counters stay,
; and each type goes on lapsing on the day the old stamp would have lapsed it.
; Without the marker a type that had lapsed would be seeded again from the old
; stamp and its next reservation wiped by the very Touch that follows it.
Function _SeedStamp(string asSourceId, string asResourceType) global
    Actor player = Game.GetPlayer()
    string markKey = "WOSK_SrcStamped_" + asSourceId + "|" + asResourceType
    if StorageUtil.HasIntValue(player, markKey)
        return
    endIf
    StorageUtil.SetIntValue(player, markKey, 1)
    string legacyKey = "WOSK_SrcTouch_" + asSourceId
    if StorageUtil.HasFloatValue(player, legacyKey) && !StorageUtil.HasFloatValue(player, _TouchKey(asSourceId, asResourceType))
        StorageUtil.SetFloatValue(player, _TouchKey(asSourceId, asResourceType), StorageUtil.GetFloatValue(player, legacyKey, 0.0))
        Debug.Trace("WOSK_Depletion: stamp of " + asResourceType + " at " + asSourceId + " seeded from the old per-source stamp")
    endIf
EndFunction

; Forgets the used veins of ONE type at the source once its respawn window has
; passed since that type's last touch. Every read of the memory goes through here
; first.
Function _ExpireIfLapsed(string asHold, string asSourceId, string asResourceType) global
    Actor player = Game.GetPlayer()
    _SeedStamp(asSourceId, asResourceType)
    string touchKey = _TouchKey(asSourceId, asResourceType)
    ; The key's PRESENCE is what says "never touched". Reading a sentinel out of
    ; the valid range said it too, and that hid the expiry from a stored day the
    ; harness wrote before day zero (D105 etapa 3, SRC14).
    if !StorageUtil.HasFloatValue(player, touchKey)
        return
    endIf
    Float touch = StorageUtil.GetFloatValue(player, touchKey, 0.0)
    Int window = SourceWindowHours(asHold, asSourceId)
    Float now = Utility.GetCurrentGameTime()
    if MemoryExpired(now, touch, window)
        Int had = StorageUtil.GetIntValue(player, _UsedKey(asSourceId, asResourceType), 0)
        StorageUtil.UnsetIntValue(player, _UsedKey(asSourceId, asResourceType))
        StorageUtil.UnsetFloatValue(player, touchKey)
        Debug.Trace("WOSK_Depletion: memory of " + asResourceType + " at source " + asSourceId + " lapsed (touched day " + touch + ", now " + now + \
                    ", window " + window + "h) - " + had + " used-vein count forgotten")
    endIf
EndFunction

Function _Touch(string asHold, string asSourceId, string asResourceType) global
    _ExpireIfLapsed(asHold, asSourceId, asResourceType)
    StorageUtil.SetFloatValue(Game.GetPlayer(), _TouchKey(asSourceId, asResourceType), Utility.GetCurrentGameTime())
EndFunction

; Every type the source serves, each touched: the player's visit to a mine
; restarts the respawn timer of the whole site, whatever was dug there.
Function _TouchAllTypes(string asHold, string asSourceId) global
    Int professions = WOSK_Registry.CountProfessions()
    Int p = 0
    while p < professions
        string profession = WOSK_Registry.GetProfessionId(p, "")
        Int t = 0
        string resourceType = WOSK_Registry.GetTaskString(profession, 0, "resourceType", "")
        while resourceType != "" && t < 64
            Int n = WOSK_Registry.CountHoldSources(asHold, resourceType)
            Int s = 0
            while s < n
                if WOSK_Registry.GetHoldSourceId(asHold, resourceType, s) == asSourceId
                    _Touch(asHold, asSourceId, resourceType)
                endIf
                s += 1
            endwhile
            t += 1
            resourceType = WOSK_Registry.GetTaskString(profession, t, "resourceType", "")
        endwhile
        p += 1
    endwhile
EndFunction

Int Function UsedVeins(string asHold, string asSourceId, string asResourceType) global
    _ExpireIfLapsed(asHold, asSourceId, asResourceType)
    return StorageUtil.GetIntValue(Game.GetPlayer(), _UsedKey(asSourceId, asResourceType), 0)
EndFunction

; Whole hours until the memory of this type at this source lapses and the
; source is whole again; 0 when nothing is remembered. At least 1 while it is.
Int Function HoursToRecover(string asHold, string asSourceId, string asResourceType) global
    _ExpireIfLapsed(asHold, asSourceId, asResourceType)
    Actor player = Game.GetPlayer()
    string touchKey = _TouchKey(asSourceId, asResourceType)
    if !StorageUtil.HasFloatValue(player, touchKey)
        return 0
    endIf
    Float touch = StorageUtil.GetFloatValue(player, touchKey, 0.0)
    Float left = SourceWindowHours(asHold, asSourceId) as Float - (Utility.GetCurrentGameTime() - touch) * 24.0
    Int hours = Math.Ceiling(left)
    if hours < 1
        return 1
    endIf
    return hours
EndFunction

Int Function RemainingVeins(string asHold, string asSourceId, string asResourceType) global
    Int total = SourceCapacity(asHold, asSourceId, asResourceType)
    Int remaining = total - UsedVeins(asHold, asSourceId, asResourceType)
    if remaining < 0
        return 0
    endIf
    return remaining
EndFunction

; ---------------------------------------------------------------------------
; Availability, for the panel (queue item 13)
; ---------------------------------------------------------------------------

; Veins a contract issued RIGHT NOW could really draw from: the CONFIRMED and
; SAFE pools, which are the two PickSource walks and nothing else. A vein
; inside an occupied or unconfirmed mine is not availability - it is a fight or
; a walk - and counting it would print a number on the panel that the very next
; press of Emitir contrato refuses.
Int Function AvailableVeins(string asHold, string asResourceType) global
    Int n = WOSK_Registry.CountHoldSources(asHold, asResourceType)
    Int total = 0
    Int i = 0
    while i < n
        string sid = WOSK_Registry.GetHoldSourceId(asHold, asResourceType, i)
        string srcState = SourceStateOf(asHold, sid, asResourceType)
        if srcState == "CONFIRMED" || srcState == "SAFE"
            total += RemainingVeins(asHold, sid, asResourceType)
        endIf
        i += 1
    endwhile
    return total
EndFunction

; Fase 33 etapa 8 (D1): the same two answers as AvailableVeins and RefusalReason,
; for ONE named source - the cook's kitchen is a single source, not a hold-wide sum.
; Slots a contract could draw from this source right now (0 unless CONFIRMED/SAFE).
Int Function AvailableAt(string asHold, string asSourceId, string asResourceType) global
    string srcState = SourceStateOf(asHold, asSourceId, asResourceType)
    if srcState == "CONFIRMED" || srcState == "SAFE"
        return RemainingVeins(asHold, asSourceId, asResourceType)
    endIf
    return 0
EndFunction

; Whole hours until the first worked-out source of the type is whole again; 0 when
; none is worked out. The panel's "back in" for a task that picks among sources.
Int Function HoursUntilBack(string asHold, string asResourceType) global
    Int n = WOSK_Registry.CountHoldSources(asHold, asResourceType)
    Int best = 0
    Int i = 0
    while i < n
        string sid = WOSK_Registry.GetHoldSourceId(asHold, asResourceType, i)
        if RemainingVeins(asHold, sid, asResourceType) <= 0
            Int hours = HoursToRecover(asHold, sid, asResourceType)
            if hours > 0 && (best == 0 || hours < best)
                best = hours
            endIf
        endIf
        i += 1
    endwhile
    return best
EndFunction

; "" when the source is usable, else "UNCONFIRMED", "OCCUPIED" or "DEPLETED".
string Function ReasonAt(string asHold, string asSourceId, string asResourceType) global
    string srcState = SourceStateOf(asHold, asSourceId, asResourceType)
    if srcState == "CONFIRMED" || srcState == "SAFE"
        return ""
    endIf
    return srcState
EndFunction

; What the GAME says one vein of this type holds, read at runtime instead of
; assumed: MineOreScript.ResourceCount (ore per strike) x ResourceCountTotal
; (strikes before it is empty), off the first vein that resolves. -1.0 when
; none does, which is the normal answer for a hold the player is not standing
; in - a reference in an unloaded cell is None until the game has changed it
; (measured 2026-09-16, see the header of this file).
;
; THIS IS NOT THE NUMBER THE PANEL PRINTS, and the difference is the point. The
; units a WORKER brings back are the task's own "unitsPerVein" (8 for iron),
; because that is what the contract pays and what the reservation spends. The
; vanilla vein holds 3. The two are not the same quantity and were never meant
; to match; this read exists so the day a MOD moves the world number, the drift
; shows up in the log instead of being invisible. V043.
;
; Bounded on purpose: it runs on a panel push, and an unbounded walk would
; parse every vein of every source of the type for an answer that is almost
; always "nothing is loaded".
Float Function VanillaUnitsPerVein(string asHold, string asResourceType, Int aiMaxTries) global
    Int sources = WOSK_Registry.CountHoldSources(asHold, asResourceType)
    Int tries = 0
    Int s = 0
    while s < sources && tries < aiMaxTries
        string sid = WOSK_Registry.GetHoldSourceId(asHold, asResourceType, s)
        Int veins = WOSK_Registry.CountHoldSourceVeins(asHold, sid, asResourceType)
        Int v = 0
        while v < veins && tries < aiMaxTries
            tries += 1
            MineOreScript ore = ResolveFormRef(WOSK_Registry.GetHoldSourceVein(asHold, sid, asResourceType, v, "")) as MineOreScript
            if ore
                return (ore.ResourceCount * ore.ResourceCountTotal) as Float
            endIf
            v += 1
        endwhile
        s += 1
    endwhile
    return -1.0
EndFunction

; The yield the PANEL prints with, remembered once it has been seen.
;
; VanillaUnitsPerVein only answers while a vein is loaded, which is almost
; never for the hold the player is not standing in - so a panel that asked it
; directly would print the ore count only in the minutes the player is inside
; the mine, which is the one moment they do not need a panel to tell them.
;
; The cache is on the player, like the rest of the source memory, so it rides
; the save. It is per resource type and not per hold: the yield is a property
; of the ore base, and the same base answers for every mine of that type.
;
; It is written ONCE per type, the first time a vein of that type resolves -
; every later call is a StorageUtil read and costs no form resolution. That is
; what makes it affordable on a push that runs at every contract state change.
; A mod that changes the vein yield is picked up on a save that has not learned
; the type yet; on a save that has, the cached number is what the panel keeps
; saying, and the drift trace in WOSK_ControllerScript is where it shows.
;
; Returns -1.0 while the type has never been seen. The panel prints the veins
; without an ore estimate in that case, which is the honest answer - a number
; invented from the registry here would be the contract's batch arithmetic
; wearing the clothes of a measurement of the ground.
Float Function VeinYield(string asHold, string asResourceType, Int aiMaxTries) global
    ; "key" collides with the Papyrus type of the same name and does not
    ; compile - a known trap, not a style choice.
    string cacheKey = "WOSK_VeinYield_" + asResourceType
    Float cached = StorageUtil.GetFloatValue(Game.GetPlayer(), cacheKey, -1.0)
    if cached > 0.0
        return cached
    endIf
    Float live = VanillaUnitsPerVein(asHold, asResourceType, aiMaxTries)
    if live > 0.0
        StorageUtil.SetFloatValue(Game.GetPlayer(), cacheKey, live)
        Debug.Trace("WOSK_Depletion: vein yield learned - " + asResourceType + " gives " + live + " ore per vein")
        return live
    endIf
    return -1.0
EndFunction

; Takes aiVeins from the source for a contract being issued.
Function Reserve(string asHold, string asSourceId, string asResourceType, Int aiVeins) global
    Int used = UsedVeins(asHold, asSourceId, asResourceType)
    StorageUtil.SetIntValue(Game.GetPlayer(), _UsedKey(asSourceId, asResourceType), used + aiVeins)
    _Touch(asHold, asSourceId, asResourceType)
    Debug.Trace("WOSK_Depletion: reserved " + aiVeins + " vein(s) of " + asResourceType + " at " + asSourceId + \
                ", used " + used + " -> " + (used + aiVeins) + " of " + SourceCapacity(asHold, asSourceId, asResourceType))
EndFunction

; A contract ended: aiUsed of its aiReserved veins were really emptied, the rest
; go back to the source. aiUsed 0 releases the whole reservation.
Function Settle(string asHold, string asSourceId, string asResourceType, Int aiReserved, Int aiUsed) global
    Int used = UsedVeins(asHold, asSourceId, asResourceType)
    Int after = used - (aiReserved - aiUsed)
    if after < 0
        after = 0
    endIf
    if after > 0
        StorageUtil.SetIntValue(Game.GetPlayer(), _UsedKey(asSourceId, asResourceType), after)
    else
        StorageUtil.UnsetIntValue(Game.GetPlayer(), _UsedKey(asSourceId, asResourceType))
    endIf
    _Touch(asHold, asSourceId, asResourceType)
    Debug.Trace("WOSK_Depletion: settled " + asResourceType + " at " + asSourceId + " - reserved " + aiReserved + \
                ", emptied " + aiUsed + ", used " + used + " -> " + after)
    if aiUsed > 0
        SyncVisibleDepletion(asHold, asSourceId, asResourceType)
    endIf
EndFunction

; ---------------------------------------------------------------------------
; Source state and selection
; ---------------------------------------------------------------------------

string Function SourceStateOf(string asHold, string asSourceId, string asResourceType) global
    Int remaining = RemainingVeins(asHold, asSourceId, asResourceType)
    string kind = WOSK_Registry.GetHoldSourceString(asHold, asSourceId, "kind", "")
    Bool cleared = true
    ; A zone is judged by its location only when the JSON gives one.
    string zoneLocRef = ""
    if kind == "zone"
        zoneLocRef = WOSK_Registry.GetHoldSourceString(asHold, asSourceId, "location", "")
    endIf
    if kind == "zone" && remaining > 0 && zoneLocRef != ""
        Location zoneLoc = ResolveFormRef(zoneLocRef) as Location
        cleared = zoneLoc && zoneLoc.IsCleared()
    elseIf kind == "dungeonMine" && remaining > 0
        ; A mine whose Location does not resolve cannot be judged: treated as
        ; occupied, the answer that sends nobody into it.
        Location loc = ResolveFormRef(WOSK_Registry.GetHoldSourceString(asHold, asSourceId, "location", "")) as Location
        cleared = loc && loc.IsCleared()
    endIf
    ; Same rule as the touch key: absence is what means "never recorded
    ; inside", so a stored day reaches SourceState as written.
    string visitKey = "WOSK_SrcVisit_" + asSourceId
    Float visit = -1.0
    if StorageUtil.HasFloatValue(Game.GetPlayer(), visitKey)
        visit = StorageUtil.GetFloatValue(Game.GetPlayer(), visitKey, 0.0)
    endIf
    return SourceState(kind, remaining, cleared, visit, Utility.GetCurrentGameTime(), HoursToRespawnCleared())
EndFunction

; The source for a new contract, or "" when none is usable (RefusalReason says
; why). A confirmed dungeon mine is preferred; without one, a safe source. The
; pick inside the pool is weighted by remaining veins; afRoll in [0.0, 1.0].
string Function PickSource(string asHold, string asResourceType, Float afRoll) global
    Int n = WOSK_Registry.CountHoldSources(asHold, asResourceType)
    if n > 64
        n = 64
    endIf
    string[] ids = new string[64]
    string[] states = new string[64]
    Int[] remaining = new Int[64]
    Int i = 0
    while i < n
        ids[i] = WOSK_Registry.GetHoldSourceId(asHold, asResourceType, i)
        states[i] = SourceStateOf(asHold, ids[i], asResourceType)
        remaining[i] = RemainingVeins(asHold, ids[i], asResourceType)
        ; The two changed words below ("src", "reads") are the V032 discriminator:
        ; the log printed state names in a case this source never writes, and the
        ; question was whether the game runs this project's .pex at all. A format
        ; word cannot be rewritten by the VM string cache the way a state name
        ; can, so the word that comes out of the log answers it outright.
        Debug.Trace("WOSK_Depletion: src " + ids[i] + " of " + asResourceType + " reads " + states[i] + " (" + remaining[i] + " vein(s) left)")
        i += 1
    endwhile

    string[] pools = new string[2]
    pools[0] = "CONFIRMED"
    pools[1] = "SAFE"
    Int p = 0
    while p < 2
        Int total = 0
        i = 0
        while i < n
            if states[i] == pools[p]
                total += remaining[i]
            endIf
            i += 1
        endwhile
        if total > 0
            Float pick = afRoll * (total as Float)
            Int cumulative = 0
            string last = ""
            i = 0
            while i < n
                if states[i] == pools[p]
                    cumulative += remaining[i]
                    last = ids[i]
                    if pick < cumulative as Float
                        return ids[i]
                    endIf
                endIf
                i += 1
            endwhile
            return last
        endIf
        p += 1
    endwhile
    return ""
EndFunction

; Fase 9, D137: same weighted pick but only over OCCUPIED sources. Called only
; when the panel has already warned and the player confirmed - never from the
; normal PickSource path. Empty when no occupied source of the type has veins.
string Function PickOccupiedSource(string asHold, string asResourceType, Float afRoll) global
    Int n = WOSK_Registry.CountHoldSources(asHold, asResourceType)
    if n > 64
        n = 64
    endIf
    string[] ids = new string[64]
    string[] states = new string[64]
    Int[] remaining = new Int[64]
    Int i = 0
    while i < n
        ids[i] = WOSK_Registry.GetHoldSourceId(asHold, asResourceType, i)
        states[i] = SourceStateOf(asHold, ids[i], asResourceType)
        remaining[i] = RemainingVeins(asHold, ids[i], asResourceType)
        i += 1
    endwhile
    Int total = 0
    i = 0
    while i < n
        if states[i] == "OCCUPIED"
            total += remaining[i]
        endIf
        i += 1
    endwhile
    if total <= 0
        return ""
    endIf
    Float pick = afRoll * (total as Float)
    Int cumulative = 0
    string last = ""
    i = 0
    while i < n
        if states[i] == "OCCUPIED"
            cumulative += remaining[i]
            last = ids[i]
            if pick < cumulative as Float
                return ids[i]
            endIf
        endIf
        i += 1
    endwhile
    return last
EndFunction

; Why no source of the type is usable, most actionable first: "UNCONFIRMED"
; (the player can go and see), "OCCUPIED" (clearing takes a fight), "DEPLETED"
; (only waiting helps); "" when some source is usable or there is none at all.
string Function RefusalReason(string asHold, string asResourceType) global
    Int n = WOSK_Registry.CountHoldSources(asHold, asResourceType)
    Bool unconfirmed = false
    Bool occupied = false
    Bool depleted = false
    Int i = 0
    while i < n
        string srcState = SourceStateOf(asHold, WOSK_Registry.GetHoldSourceId(asHold, asResourceType, i), asResourceType)
        if srcState == "CONFIRMED" || srcState == "SAFE"
            return ""
        elseIf srcState == "UNCONFIRMED"
            unconfirmed = true
        elseIf srcState == "OCCUPIED"
            occupied = true
        elseIf srcState == "DEPLETED"
            depleted = true
        endIf
        i += 1
    endwhile
    if unconfirmed
        return "UNCONFIRMED"
    elseIf occupied
        return "OCCUPIED"
    elseIf depleted
        return "DEPLETED"
    endIf
    return ""
EndFunction

string Function RefusalMessage(string asReason, string asHold, string asResourceType) global
    ; Fase 15: a type that is not an ore comes from a zone (game, herbs). The
    ; type id is data, not prose, so the message names the grounds, not the type.
    if StringUtil.Find(asResourceType, "ore_") != 0
        if asReason == "OCCUPIED"
            return "Honest Work: the grounds of " + asHold + " for this work are held by enemies."
        elseIf asReason == "DEPLETED"
            return "Honest Work: the grounds of " + asHold + " for this work are worked out until they recover."
        elseIf asReason == "UNCONFIRMED"
            return "Honest Work: nobody has been to the grounds of " + asHold + " for this work in a long time."
        endIf
        return "Honest Work: " + asHold + " has no ground for this work."
    endIf
    string ore = asResourceType
    if StringUtil.Find(ore, "ore_") == 0
        ore = StringUtil.Substring(ore, 4)
    endIf
    if asReason == "UNCONFIRMED"
        return "Honest Work: nobody has been to the " + ore + " mines of " + asHold + " in a long time. Visit one to confirm it is clear."
    elseIf asReason == "OCCUPIED"
        ; "the whole site" is not decoration: IsCleared() belongs to the LCTN, not
        ; to the interior cell, so a hostile tied to the location but standing
        ; OUTSIDE the cave keeps the flag set. A player who just cleared the
        ; interior reads the old wording as a bug in this mod. Measured in game
        ; at the Sleeping Tree Camp: cave cleared, still refused, and it passed
        ; only after the giant outside was killed.
        return "Honest Work: the " + ore + " mines of " + asHold + " are still held. The whole site counts - enemies outside the cave hold it too."
    elseIf asReason == "DEPLETED"
        return "Honest Work: the " + ore + " sources of " + asHold + " are mined out until they grow back."
    endIf
    return "Honest Work: " + asHold + " has no source of " + ore + " to work."
EndFunction

; ---------------------------------------------------------------------------
; The world follows the memory
; ---------------------------------------------------------------------------

; Depletes veins of the type, in JSON order, until as many read depleted as the
; memory says are used. Never restores one: the game's respawn does that. A vein
; that does not resolve (unloaded and never changed) is skipped - it is caught
; up when the player loads its cell (SyncHold).
Function SyncVisibleDepletion(string asHold, string asSourceId, string asResourceType) global
    if IsZone(asHold, asSourceId)
        return
    endIf
    Int used = UsedVeins(asHold, asSourceId, asResourceType)
    if used <= 0
        return
    endIf
    Int n = WOSK_Registry.CountHoldSourceVeins(asHold, asSourceId, asResourceType)
    if n > 128
        n = 128
    endIf
    ; ObjectReference[]: the compiler refuses "new MineOreScript[n]".
    ObjectReference[] veins = new ObjectReference[128]
    Int depleted = 0
    Int unresolved = 0
    Int i = 0
    while i < n
        MineOreScript ore = ResolveFormRef(WOSK_Registry.GetHoldSourceVein(asHold, asSourceId, asResourceType, i, "")) as MineOreScript
        veins[i] = ore
        if !ore
            unresolved += 1
        elseIf ore.ResourceCountCurrent == 0
            depleted += 1
        endIf
        i += 1
    endwhile
    Int before = depleted
    i = 0
    while i < n && depleted < used
        MineOreScript ore = veins[i] as MineOreScript
        if ore && ore.ResourceCountCurrent != 0
            ore.depleteOreDueToFailure()
            depleted += 1
        endIf
        i += 1
    endwhile
    if depleted != before || unresolved > 0
        Debug.Trace("WOSK_Depletion: sync " + asResourceType + " at " + asSourceId + " - used " + used + ", read depleted " + \
                    before + ", depleted now " + (depleted - before) + ", unresolved " + unresolved + " of " + n)
    endIf
EndFunction

; Every source of every task type in the hold that has used veins. Called on
; the player's cell load, the moment an unloaded vein starts to resolve.
Function SyncHold(string asHold) global
    Int professions = WOSK_Registry.CountProfessions()
    Int p = 0
    while p < professions
        string profession = WOSK_Registry.GetProfessionId(p, "")
        Int t = 0
        string resourceType = WOSK_Registry.GetTaskString(profession, 0, "resourceType", "")
        while resourceType != "" && t < 64
            Int n = WOSK_Registry.CountHoldSources(asHold, resourceType)
            Int s = 0
            while s < n
                string sid = WOSK_Registry.GetHoldSourceId(asHold, resourceType, s)
                if UsedVeins(asHold, sid, resourceType) > 0
                    SyncVisibleDepletion(asHold, sid, resourceType)
                endIf
                s += 1
            endwhile
            t += 1
            resourceType = WOSK_Registry.GetTaskString(profession, t, "resourceType", "")
        endwhile
        p += 1
    endwhile
EndFunction

; The player standing in the cell of a dungeon mine's destination confirms the
; mine (decision B) and refreshes its memory, as the game's own respawn timer
; restarts. Entering the interior is what counts: Location.IsCleared() only
; updates when that cell loads (measured 2026-09-16). The worker arriving does
; not count - it cannot tell bandits from an empty mine.
Function RecordPlayerVisit(string asHold) global
    Actor player = Game.GetPlayer()
    Cell here = player.GetParentCell()
    if !here
        return
    endIf
    Int n = WOSK_Registry.CountHoldSources(asHold, "")
    Int i = 0
    while i < n
        string sid = WOSK_Registry.GetHoldSourceId(asHold, "", i)
        if WOSK_Registry.GetHoldSourceString(asHold, sid, "kind", "") == "dungeonMine"
            ObjectReference dest = ResolveFormRef(WOSK_Registry.GetHoldSourceString(asHold, sid, "destination", "")) as ObjectReference
            if dest && dest.GetParentCell() == here
                Float now = Utility.GetCurrentGameTime()
                StorageUtil.SetFloatValue(player, "WOSK_SrcVisit_" + sid, now)
                _TouchAllTypes(asHold, sid)
                Debug.Trace("WOSK_Depletion: player visit recorded at " + sid + " (cell " + here + ", day " + now + ")")
            endIf
        endIf
        i += 1
    endwhile
EndFunction

; Pre-etapa-3 saves carry the old lazy depletion counters on the player.
Function ClearLegacyPending() global
    Actor player = Game.GetPlayer()
    Int cleared = StorageUtil.ClearObjFloatValuePrefix(player, "WOSK_Pending_")
    cleared += StorageUtil.ClearObjIntValuePrefix(player, "WOSK_Notified_")
    if cleared > 0
        Debug.Trace("WOSK_Depletion: " + cleared + " legacy lazy-depletion value(s) cleared")
    endIf
EndFunction
