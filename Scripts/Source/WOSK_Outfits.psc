; Copyright (C) 2026 Awrawra
; SPDX-License-Identifier: GPL-3.0-only
; This file is part of Honest Work - Workers of Skyrim, free software under the
; GNU General Public License, version 3. See the LICENSE file at the repository root.

ScriptName WOSK_Outfits Hidden

; Fase 27 (D232): each trade has its own outfit (WOSK_Outfit_*,
; HonestWork.esp 0x845-0x84A, vanilla Skyrim.esm clothing). It goes on when the
; candidate is hired and the original one comes back when the worker leaves
; (dismissal, death, discard).
;
; Fase 31 conserto 1 (D256): the outfit is NOT set with Actor.SetOutfit any more.
; The candidates are generic actors whose base is shared by every NPC of that base,
; and in the maintainer's round 7 three workers of one base wore each other's clothes
; (the hunter in the miner's, the miner in the fisher's). Whether SetOutfit reached
; the shared base is inferred, never measured (the harness line ATR-OUTFIT does it);
; the way it is done now is right in both cases: the worker is DRESSED, piece by
; piece, in his own inventory. The pieces of the trade's outfit are added to the
; actor and equipped (abPreventRemoval), the default outfit pieces he wears are taken
; off and kept on a list on the actor (KeyStash), and the base is never written.
;
; The original outfit of a candidate is whatever he wears when hired, read off the
; body. OriginalOutfit() below is only the farmers' base outfit (FarmClothesOutfit02,
; Skyrim.esm 0x0002D75E), used to recognise the leftovers of an earlier build that
; did call SetOutfit.

string Function KeyWorn() global
    return "WOSK_OutfitWorn"
EndFunction

; The outfit record's object id for a trade, 0 for a trade with none. Same order
; as build_plugin.py WORKER_OUTFITS.
Int Function OutfitObjectId(string asProfession) global
    if asProfession == "cook"
        return 0x00000845
    elseIf asProfession == "fisher"
        return 0x00000846
    elseIf asProfession == "herbalist"
        return 0x00000847
    elseIf asProfession == "hunter"
        return 0x00000848
    elseIf asProfession == "laborer"
        return 0x00000849
    elseIf asProfession == "miner"
        return 0x0000084A
    endIf
    return 0
EndFunction

; Fase 31 (D249): a fisher reads as a fisher. Creation Club "Fishing" (Anniversary
; Edition content) carries a fishing outfit of its own - hat, clothes, boots - and a
; rod. They are used when that plugin is in the load order and never required: it is
; looked up at run time by file name and EditorID-checked ids read from the game data
; (ccBGSSSE001_FishingOutfit 0x000B76, ccBGSSSE001_FishingRodImperialWeap 0x00084F). Without
; it the fisher keeps the plugin's own farm clothes (WOSK_Outfit_Fisher) and no rod.
Outfit Function FishingCCOutfit() global
    return Game.GetFormFromFile(0x00000B76, "ccBGSSSE001-Fish.esm") as Outfit
EndFunction

Weapon Function FishingCCRod() global
    return Game.GetFormFromFile(0x0000084F, "ccBGSSSE001-Fish.esm") as Weapon
EndFunction

Outfit Function OutfitFor(string asProfession) global
    if asProfession == "fisher"
        Outfit cc = FishingCCOutfit()
        if cc
            return cc
        endIf
    endIf
    Int id = OutfitObjectId(asProfession)
    if id == 0
        return None
    endIf
    return Game.GetFormFromFile(id, "HonestWork.esp") as Outfit
EndFunction

Outfit Function OriginalOutfit() global
    return Game.GetFormFromFile(0x0002D75E, "Skyrim.esm") as Outfit
EndFunction

; Fase 27 conserto 1 (D235): the base and the sex of the actor for the log lines
; and the harness (ATR-BASE): two workers of one base and one sex are the pair
; where a SetOutfit that reached the base would show.
string Function BaseAndSex(Actor akWorker) global
    if !akWorker
        return "base=None sex=?"
    endIf
    ActorBase b = akWorker.GetActorBase()
    return "base=" + b + " sex=" + b.GetSex()
EndFunction

; Puts the trade's outfit on. Idempotent: a worker already wearing it is left
; alone, so the load-time reconcile does not redress anyone.
Function Wear(Actor akWorker, string asProfession) global
    _WearOutfit(akWorker, asProfession)
    ; Fase 28 conserto 1 (D238): the hunter carries a hunting bow with the outfit.
    WearGear(akWorker, asProfession)
    WearRod(akWorker, asProfession)
    WearPick(akWorker, asProfession)
EndFunction

; Fase 33 etapa 1 (V064): the miner holds a pickaxe, the way the fisher holds the
; rod. The vanilla record is weapPickaxe, Skyrim.esm 0x0E3C16 (EditorID
; weapPickaxe, "Pickaxe"). Added once (its own key), put in the hand when the 3D is loaded,
; taken back on dismissal and death with the rest of the kit. A weapon the player put in
; the hands is not replaced. Does not count in any batch.
string Function KeyPick() global
    return "WOSK_PickAdded"
EndFunction

Weapon Function MinerPick() global
    return Game.GetFormFromFile(0x000E3C16, "Skyrim.esm") as Weapon
EndFunction

Function WearPick(Actor akWorker, string asProfession) global
    if !akWorker || asProfession != "miner"
        return
    endIf
    Weapon pick = MinerPick()
    if !pick
        Debug.Trace("WOSK_Outfits: no pickaxe for the miner (record missing) - " + akWorker + " goes without")
        return
    endIf
    if StorageUtil.GetStringValue(akWorker, KeyPick(), "") == ""
        akWorker.AddItem(pick, 1, true)
        StorageUtil.SetStringValue(akWorker, KeyPick(), asProfession)
    endIf
    if akWorker.Is3DLoaded() && !akWorker.GetEquippedWeapon(false)
        akWorker.EquipItem(pick, false, true)
        Debug.Trace("WOSK_Outfits: pickaxe on - worker=" + akWorker + " pick=" + pick + " equipped=" + akWorker.IsEquipped(pick))
    endIf
EndFunction

Function RemovePick(Actor akWorker) global
    if !akWorker || StorageUtil.GetStringValue(akWorker, KeyPick(), "") == ""
        return
    endIf
    Weapon pick = MinerPick()
    if pick && akWorker.GetItemCount(pick) > 0
        akWorker.UnequipItem(pick, false, true)
        akWorker.RemoveItem(pick, 1, true, None)
    endIf
    StorageUtil.UnsetStringValue(akWorker, KeyPick())
    Debug.Trace("WOSK_Outfits: pickaxe off - worker=" + akWorker)
EndFunction

; Fase 31 (D249): the fisher holds a fishing rod when the CC plugin is present. Added once
; (its own key) and put in the hand when the 3D is loaded; taken back on dismissal and
; death with the rest of the kit. A rod the player put in the hands is not replaced.
string Function KeyRod() global
    return "WOSK_RodAdded"
EndFunction

Function WearRod(Actor akWorker, string asProfession) global
    if !akWorker || asProfession != "fisher"
        return
    endIf
    Weapon rod = FishingCCRod()
    if !rod
        return
    endIf
    if StorageUtil.GetStringValue(akWorker, KeyRod(), "") == ""
        akWorker.AddItem(rod, 1, true)
        StorageUtil.SetStringValue(akWorker, KeyRod(), asProfession)
    endIf
    if akWorker.Is3DLoaded() && !akWorker.GetEquippedWeapon(false)
        akWorker.EquipItem(rod, false, true)
    endIf
EndFunction

Function RemoveRod(Actor akWorker) global
    if !akWorker || StorageUtil.GetStringValue(akWorker, KeyRod(), "") == ""
        return
    endIf
    Weapon rod = FishingCCRod()
    if rod && akWorker.GetItemCount(rod) > 0
        akWorker.UnequipItem(rod, false, true)
        akWorker.RemoveItem(rod, 1, true, None)
    endIf
    StorageUtil.UnsetStringValue(akWorker, KeyRod())
EndFunction

; Fase 28 conserto 1 (D238, V060): the hired hunter carries a hunting bow and
; arrows, on from the hire and gone on dismissal like the outfit. Vanilla records,
; read from Skyrim.esm: HuntingBow 0x013985, IronArrow 0x01397D.
; Idempotent by its own key, so a hunter hired before this build gets the kit on the
; next load (Reconcile -> Wear) and a bow the player swapped in by trade is not
; replaced. The bow does NOT count in the batch (WOSK_WorkerAliasScript._GearMultiplier).
string Function KeyGear() global
    return "WOSK_GearWorn"
EndFunction

Weapon Function HuntBow() global
    return Game.GetFormFromFile(0x00013985, "Skyrim.esm") as Weapon
EndFunction

Ammo Function HuntArrow() global
    return Game.GetFormFromFile(0x0001397D, "Skyrim.esm") as Ammo
EndFunction

Int Function HuntArrowCount() global
    return 40
EndFunction

; Fase 30 (D242, F28C.8): two keys. KeyGearAdded says the kit is in the inventory
; (added once). KeyGear says it is ON: set only after IsEquipped confirms it, never on
; the call alone. EquipItem on a worker whose 3D is not loaded (hired from the panel in
; another cell) does nothing, and the old code sealed the key regardless, so the bow
; never went on. Now the equip waits for the 3D and every load / issue retries it.
string Function KeyGearAdded() global
    return "WOSK_GearAdded"
EndFunction

Function WearGear(Actor akWorker, string asProfession) global
    if !akWorker || asProfession != "hunter"
        return
    endIf
    if StorageUtil.GetStringValue(akWorker, KeyGear(), "") != ""
        return
    endIf
    Weapon bow = HuntBow()
    Ammo arrow = HuntArrow()
    if !bow || !arrow
        Debug.Trace("WOSK_Outfits: no bow kit for the hunter (record missing) - " + akWorker + " goes without")
        return
    endIf
    ; A worker hired before this build already holds the kit (key from Fase 28): nothing
    ; to add, only to put on.
    if StorageUtil.GetStringValue(akWorker, KeyGearAdded(), "") == ""
        akWorker.AddItem(bow, 1, true)
        akWorker.AddItem(arrow, HuntArrowCount(), true)
        StorageUtil.SetStringValue(akWorker, KeyGearAdded(), asProfession)
    endIf
    if !akWorker.Is3DLoaded()
        Debug.Trace("WOSK_Outfits: gear added, equip deferred (3D not loaded) - worker=" + akWorker)
        return
    endIf
    ; A better bow the player already put in his hands stays in them.
    if !akWorker.GetEquippedWeapon(false)
        akWorker.EquipItem(bow, false, true)
    endIf
    akWorker.EquipItem(arrow, false, true)
    Bool onNow = akWorker.IsEquipped(bow) || akWorker.GetEquippedWeapon(false) != None
    if onNow
        StorageUtil.SetStringValue(akWorker, KeyGear(), asProfession)
    endIf
    Debug.Trace("WOSK_Outfits: gear on - worker=" + akWorker + " bow=" + bow + " arrows=" + arrow + " x" + HuntArrowCount() + " equippedBow=" + akWorker.IsEquipped(bow) + " sealed=" + onNow)
EndFunction

; Takes back the kit the mod gave: ITS bow and ITS arrows, nothing the player gave (the
; record of gifts is returned or left on a corpse by the caller, never eaten here).
Function RemoveGear(Actor akWorker) global
    ; A hunter of the Fase 28 build carries only KeyGear.
    if !akWorker || (StorageUtil.GetStringValue(akWorker, KeyGearAdded(), "") == "" && StorageUtil.GetStringValue(akWorker, KeyGear(), "") == "")
        return
    endIf
    Weapon bow = HuntBow()
    Ammo arrow = HuntArrow()
    if bow && akWorker.GetItemCount(bow) > 0
        akWorker.UnequipItem(bow, false, true)
        akWorker.RemoveItem(bow, 1, true, None)
    endIf
    if arrow
        Int have = akWorker.GetItemCount(arrow)
        Int own = HuntArrowCount()
        if have < own
            own = have
        endIf
        if own > 0
            akWorker.UnequipItem(arrow, false, true)
            akWorker.RemoveItem(arrow, own, true, None)
        endIf
    endIf
    StorageUtil.UnsetStringValue(akWorker, KeyGear())
    StorageUtil.UnsetStringValue(akWorker, KeyGearAdded())
    Debug.Trace("WOSK_Outfits: gear off - worker=" + akWorker)
EndFunction

; Fase 31 conserto 1 (D256): the three keys. KeyWorn (kept: the harness and the older
; saves read it) says the worker was dressed for that trade. KeyPieces says the
; per-actor way did it (a worker of the earlier SetOutfit build has KeyWorn and no
; KeyPieces, and is dressed again on the next load). KeyOn says every piece is
; equipped now: set only after IsEquipped confirms it, like the bow (D242).
string Function KeyPieces() global
    return "WOSK_OutfitPieces"
EndFunction

string Function KeyOn() global
    return "WOSK_OutfitOn"
EndFunction

string Function KeyStash() global
    return "WOSK_OutfitStash"
EndFunction

Bool Function _InOutfit(Outfit akOutfit, Form akItem) global
    if !akOutfit || !akItem
        return false
    endIf
    Int n = akOutfit.GetNumParts()
    Int i = 0
    while i < n
        if akOutfit.GetNthPart(i) == akItem
            return true
        endIf
        i += 1
    endwhile
    return false
EndFunction

; An item the worker could have been given as an outfit: the outfit of his base, the
; farmers' original one, the six trade outfits and the CC fishing one. A gift of the
; player, the bow, the rod are none of these and are never taken off.
Bool Function _IsKnownOutfitPart(Actor akWorker, Form akItem) global
    if _InOutfit(akWorker.GetActorBase().GetOutfit(false), akItem) || _InOutfit(OriginalOutfit(), akItem)
        return true
    endIf
    Int id = 0x00000845
    while id <= 0x0000084A
        if _InOutfit(Game.GetFormFromFile(id, "HonestWork.esp") as Outfit, akItem)
            return true
        endIf
        id += 1
    endwhile
    return _InOutfit(FishingCCOutfit(), akItem)
EndFunction

; Public name of _IsKnownOutfitPart for the alias events (Fase 33 etapa 1 probe).
Bool Function IsOutfitPiece(Actor akWorker, Form akItem) global
    return _IsKnownOutfitPart(akWorker, akItem)
EndFunction

; What is on the body, slot by slot (slot 30 + bit), for the log and the harness.
string Function WornSummary(Actor akWorker) global
    if !akWorker
        return "worn=None"
    endIf
    string text = ""
    Int bit = 0
    while bit < 31
        Form f = akWorker.GetWornForm(Math.LeftShift(1, bit))
        if f
            text += (30 + bit) + ":" + f + " "
        endIf
        bit += 1
    endwhile
    return "worn=[" + text + "]"
EndFunction

; Fase 33 etapa 1 (probe, gate item 4): answers the INFERRED "the engine dresses the base's
; default outfit again when the 3D reloads". One line per event on EVERY worker, with what
; is on the body slot by slot, whether the pieces are marked on, the base outfit and how
; many of each kind of piece sit in the inventory. Never changes anything. Capped per
; worker so a dressing loop cannot flood the log.
string Function KeyProbeN() global
    return "WOSK_ProbeN"
EndFunction

Function Probe(Actor akWorker, string asWhy, Form akItem = None) global
    if !akWorker
        return
    endIf
    Int n = StorageUtil.GetIntValue(akWorker, KeyProbeN(), 0)
    if n >= 400
        return
    endIf
    StorageUtil.SetIntValue(akWorker, KeyProbeN(), n + 1)
    string trade = StorageUtil.GetStringValue(akWorker, KeyPieces(), "")
    Int stashed = StorageUtil.FormListCount(akWorker, KeyStash())
    string stashHave = ""
    Int i = 0
    while i < stashed
        Form kept = StorageUtil.FormListGet(akWorker, KeyStash(), i)
        if kept
            stashHave += kept + "x" + akWorker.GetItemCount(kept) + " "
        endIf
        i += 1
    endWhile
    string tradeHave = ""
    Outfit t = None
    if trade != ""
        t = OutfitFor(trade)
    endIf
    Int parts = 0
    if t
        parts = t.GetNumParts()
    endIf
    i = 0
    while i < parts
        Form p = t.GetNthPart(i)
        if p
            tradeHave += p + "x" + akWorker.GetItemCount(p) + (akWorker.IsEquipped(p) as Int) + " "
        endIf
        i += 1
    endWhile
    Debug.Trace("WOSK_Outfits: PROBE " + asWhy + " #" + (n + 1) + " - worker=" + akWorker + " " + BaseAndSex(akWorker) + " 3D=" + akWorker.Is3DLoaded() + " trade=" + trade + " on=" + (StorageUtil.GetStringValue(akWorker, KeyOn(), "") != "") + " item=" + akItem + " baseOutfit=" + akWorker.GetActorBase().GetOutfit(false) + " " + WornSummary(akWorker) + " tradeItems=[" + tradeHave + "] stashItems=[" + stashHave + "]")
EndFunction

; Takes off (and keeps, on the actor) the default outfit pieces the worker wears that
; the trade's outfit does not use.
Function _StashDefault(Actor akWorker, Outfit akTrade) global
    Int bit = 0
    while bit < 31
        Form f = akWorker.GetWornForm(Math.LeftShift(1, bit))
        if f && (f as Armor) && !_InOutfit(akTrade, f) && _IsKnownOutfitPart(akWorker, f)
            if StorageUtil.FormListFind(akWorker, KeyStash(), f) < 0
                StorageUtil.FormListAdd(akWorker, KeyStash(), f, false)
            endIf
        endIf
        bit += 1
    endwhile
    Int n = StorageUtil.FormListCount(akWorker, KeyStash())
    Int i = 0
    while i < n
        Form kept = StorageUtil.FormListGet(akWorker, KeyStash(), i)
        if kept && akWorker.GetItemCount(kept) > 0
            akWorker.UnequipItem(kept, false, true)
        endIf
        i += 1
    endwhile
EndFunction

; Fase 33 etapa 1 (D259): the default pieces are TAKEN OFF, no longer removed from the
; inventory. Round 8 showed what removing them does: out of town the body held both
; outfits and wore the default one, so the engine puts its outfit back when the actor
; has none of its pieces (INFERRED; the probe lines answer it). They stay on the body as
; unworn items; Guard keeps them off.

; A piece of an outfit that is not the worker's trade outfit - the base's own, the
; farmers' original, another trade's - is what the engine puts on when it dresses the
; actor by himself.
Bool Function IsDefaultPiece(Actor akWorker, Form akItem) global
    if !akWorker || !akItem || !(akItem as Armor)
        return false
    endIf
    string trade = StorageUtil.GetStringValue(akWorker, KeyPieces(), "")
    if trade == ""
        return false
    endIf
    if _InOutfit(OutfitFor(trade), akItem)
        return false
    endIf
    return _IsKnownOutfitPart(akWorker, akItem)
EndFunction

; True when an armor the PLAYER gave (and the worker still holds) takes a slot the piece
; takes. By what is held, not by IsEquipped: right after EquipItem the answer is still
; "no" (round 8 logged on=False straight after the call), and the guard would put the
; trade piece back over the gift.
Bool Function _CoveredByGift(Actor akWorker, Armor akPiece) global
    Int mask = akPiece.GetSlotMask()
    Int n = StorageUtil.FormListCount(akWorker, WOSK_Gear.KeyForms())
    Int i = 0
    while i < n
        Armor g = StorageUtil.FormListGet(akWorker, WOSK_Gear.KeyForms(), i) as Armor
        if g && akWorker.GetItemCount(g) > 0 && Math.LogicalAnd(g.GetSlotMask(), mask) != 0
            return true
        endIf
        i += 1
    endwhile
    return false
EndFunction

; How many CORRECTIONS the guard makes in 20 s of real time before it stops (D270). Measured
; in round 12 (boot 20261102-001420): one entry into the house costs 4-6 corrections (cell
; attach, load and the engine's equip of each default piece), so 20 lets three entries in
; 20 s through and still cuts two scripts fighting, which correct several times a second.
Int Function GuardMax() global
    return 20
EndFunction

; The guard (D259, D270). Whatever put a default piece on the body - the 3D reloading in
; another cell, a fast travel, a load - this takes it off again and puts the trade pieces
; back, except the slots an armor the player gave covers. Idempotent, reads the body first.
; The limit counts the corrections it makes, not the times it is called (round 12: the
; cook's calls that found nothing wrong used the 12 passes up, and the stop came with the
; body in the default clothes); calls are counted apart, for the stop line only.
Function Guard(Actor akWorker, string asWhy, Form akItem = None) global
    if !akWorker || !akWorker.Is3DLoaded()
        return
    endIf
    string trade = StorageUtil.GetStringValue(akWorker, KeyPieces(), "")
    if trade == ""
        return
    endIf
    Outfit tradeOutfit = OutfitFor(trade)
    if !tradeOutfit
        return
    endIf
    Float now = Utility.GetCurrentRealTime()
    if now - StorageUtil.GetFloatValue(akWorker, "WOSK_GuardT0", 0.0) > 20.0
        StorageUtil.SetFloatValue(akWorker, "WOSK_GuardT0", now)
        StorageUtil.SetIntValue(akWorker, "WOSK_GuardN", 0)
        StorageUtil.SetIntValue(akWorker, "WOSK_GuardCalls", 0)
    endIf
    Int calls = StorageUtil.GetIntValue(akWorker, "WOSK_GuardCalls", 0) + 1
    StorageUtil.SetIntValue(akWorker, "WOSK_GuardCalls", calls)
    Int corrections = StorageUtil.GetIntValue(akWorker, "WOSK_GuardN", 0)
    ; Is anything wrong? A default piece worn, or a trade piece missing from a free slot.
    Bool wrong = false
    Int bit = 0
    while bit < 31 && !wrong
        Form f = akWorker.GetWornForm(Math.LeftShift(1, bit))
        if f && IsDefaultPiece(akWorker, f)
            wrong = true
        endIf
        bit += 1
    endwhile
    Int n = tradeOutfit.GetNumParts()
    Int i = 0
    while i < n && !wrong
        Armor piece = tradeOutfit.GetNthPart(i) as Armor
        if piece && !_CoveredByGift(akWorker, piece) && !_IsOn(akWorker, piece)
            wrong = true
        endIf
        i += 1
    endwhile
    if !wrong
        if StorageUtil.GetStringValue(akWorker, KeyOn(), "") == ""
            StorageUtil.SetStringValue(akWorker, KeyOn(), trade)
        endIf
        return
    endIf
    corrections += 1
    if corrections > GuardMax()
        if corrections == GuardMax() + 1
            StorageUtil.SetIntValue(akWorker, "WOSK_GuardN", corrections)
            Debug.Trace("WOSK_Outfits: guard stopped - worker=" + akWorker + " " + GuardMax() + " corrections in 20 s, " + calls + " calls (" + asWhy + ") worn " + WornSummary(akWorker))
        endIf
        return
    endIf
    StorageUtil.SetIntValue(akWorker, "WOSK_GuardN", corrections)
    string before = WornSummary(akWorker)
    bit = 0
    while bit < 31
        Form f2 = akWorker.GetWornForm(Math.LeftShift(1, bit))
        if f2 && IsDefaultPiece(akWorker, f2)
            if StorageUtil.FormListFind(akWorker, KeyStash(), f2) < 0
                StorageUtil.FormListAdd(akWorker, KeyStash(), f2, false)
            endIf
            akWorker.UnequipItem(f2, false, true)
        endIf
        bit += 1
    endwhile
    Bool allOn = _EquipPieces(akWorker, tradeOutfit)
    WOSK_Gear.EnsureEquipped(akWorker)
    if allOn
        StorageUtil.SetStringValue(akWorker, KeyOn(), trade)
    endIf
    Debug.Trace("WOSK_Outfits: guard " + asWhy + " #" + corrections + " (of " + calls + " calls) - worker=" + akWorker + " " + BaseAndSex(akWorker) + " trade=" + trade + " item=" + akItem + " allOn=" + allOn + " before " + before + " after " + WornSummary(akWorker))
EndFunction

; True when the piece is on the body. IsEquipped lags the EquipItem call by a moment (rounds
; 9 and 12: allOn=False on three guard lines whose own "after worn" already showed every
; piece), GetWornForm does not, so either one counts (D270).
Bool Function _IsOn(Actor akWorker, Armor akPiece) global
    if akWorker.IsEquipped(akPiece)
        return true
    endIf
    Int mask = akPiece.GetSlotMask()
    Int bit = 0
    while bit < 31
        if Math.LogicalAnd(mask, Math.LeftShift(1, bit)) != 0
            if akWorker.GetWornForm(Math.LeftShift(1, bit)) == (akPiece as Form)
                return true
            endIf
        endIf
        bit += 1
    endwhile
    return false
EndFunction

; Adds what is missing and equips every piece. True when all of them are on.
Bool Function _EquipPieces(Actor akWorker, Outfit akTrade) global
    Bool allOn = true
    Int n = akTrade.GetNumParts()
    Int i = 0
    while i < n
        Armor piece = akTrade.GetNthPart(i) as Armor
        ; Fase 33 etapa 1 (D259): a slot the player's armor covers is that armor's.
        if piece && !_CoveredByGift(akWorker, piece)
            if akWorker.GetItemCount(piece) < 1
                akWorker.AddItem(piece, 1, true)
            endIf
            if akWorker.Is3DLoaded()
                if !_IsOn(akWorker, piece)
                    ; Not locked (D259): abPreventRemoval kept neither the engine's outfit
                    ; off (round 8) nor the player's armor on (glass cuirass, equipped=False).
                    akWorker.EquipItem(piece, false, true)
                endIf
                if !_IsOn(akWorker, piece)
                    allOn = false
                endIf
            else
                allOn = false
            endIf
        endIf
        i += 1
    endwhile
    return allOn
EndFunction

Function _WearOutfit(Actor akWorker, string asProfession) global
    if !akWorker
        return
    endIf
    Outfit trade = OutfitFor(asProfession)
    if !trade
        Debug.Trace("WOSK_Outfits: no outfit for '" + asProfession + "' (record missing or trade unknown), " + akWorker + " keeps his own")
        return
    endIf
    if StorageUtil.GetStringValue(akWorker, KeyPieces(), "") == asProfession
        ; Dressed already: only make sure every piece is on (a load, a 3D that was not up).
        if StorageUtil.GetStringValue(akWorker, KeyOn(), "") == "" && _EquipPieces(akWorker, trade)
            StorageUtil.SetStringValue(akWorker, KeyOn(), asProfession)
            Debug.Trace("WOSK_Outfits: pieces on - worker=" + akWorker + " " + BaseAndSex(akWorker) + " profession=" + asProfession)
        endIf
        return
    endIf
    string before = WornSummary(akWorker)
    _StashDefault(akWorker, trade)
    StorageUtil.SetStringValue(akWorker, KeyPieces(), asProfession)
    StorageUtil.SetStringValue(akWorker, KeyWorn(), asProfession)
    StorageUtil.UnsetStringValue(akWorker, KeyOn())
    if _EquipPieces(akWorker, trade)
        StorageUtil.SetStringValue(akWorker, KeyOn(), asProfession)
    endIf
    ; The line the maintainer's round answers the SetOutfit question with: the base, the
    ; outfit the BASE carries (it must not follow the trade), and what is on the body.
    Debug.Trace("WOSK_Outfits: wear - worker=" + akWorker + " " + BaseAndSex(akWorker) + " profession=" + asProfession + " outfit=" + trade + " baseOutfit=" + akWorker.GetActorBase().GetOutfit(false) + " on=" + (StorageUtil.GetStringValue(akWorker, KeyOn(), "") != "") + " before " + before + " after " + WornSummary(akWorker))
EndFunction

; Gives the original clothes back. Silent when the worker never wore the trade's.
;
; Fase 30 (D244): what the PLAYER gave the hunter goes back to the player first
; (abReturnGifts true: dismissal); a dead worker passes false and the gifts stay on
; the corpse. Only then is the mod's own kit taken back.
;
; Fase 31 conserto 1 (D256): the trade pieces come off and the default pieces kept in
; KeyStash go back on, for a worker who stays alive. A dead one keeps what he wears.
Function Restore(Actor akWorker, Bool abReturnGifts = true) global
    if !akWorker
        return
    endIf
    if abReturnGifts
        WOSK_Gear.ReturnToPlayer(akWorker)
    else
        WOSK_Gear.ForgetGifts(akWorker)
    endIf
    RemoveGear(akWorker)
    RemoveRod(akWorker)
    RemovePick(akWorker)
    string worn = StorageUtil.GetStringValue(akWorker, KeyWorn(), "")
    if worn == ""
        return
    endIf
    ; Fase 33 etapa 1 (D259): first, so the guard no longer reads the default pieces put
    ; back below as a thing to take off.
    StorageUtil.UnsetStringValue(akWorker, KeyPieces())
    StorageUtil.UnsetStringValue(akWorker, KeyOn())
    if abReturnGifts
        Outfit trade = OutfitFor(worn)
        Int n = 0
        if trade
            n = trade.GetNumParts()
        endIf
        Int i = 0
        while i < n
            Armor piece = trade.GetNthPart(i) as Armor
            if piece && StorageUtil.FormListFind(akWorker, KeyStash(), piece) < 0 && akWorker.GetItemCount(piece) > 0
                akWorker.UnequipItem(piece, false, true)
                akWorker.RemoveItem(piece, akWorker.GetItemCount(piece), true, None)
            endIf
            i += 1
        endwhile
        Int kept = StorageUtil.FormListCount(akWorker, KeyStash())
        i = 0
        while i < kept
            Form f = StorageUtil.FormListGet(akWorker, KeyStash(), i)
            if f
                if akWorker.GetItemCount(f) < 1
                    akWorker.AddItem(f, 1, true)
                endIf
                if akWorker.Is3DLoaded()
                    akWorker.EquipItem(f, false, true)
                endIf
            endIf
            i += 1
        endwhile
    endIf
    StorageUtil.FormListClear(akWorker, KeyStash())
    StorageUtil.UnsetStringValue(akWorker, KeyPieces())
    StorageUtil.UnsetStringValue(akWorker, KeyOn())
    StorageUtil.UnsetStringValue(akWorker, KeyWorn())
    Debug.Trace("WOSK_Outfits: restore - worker=" + akWorker + " " + BaseAndSex(akWorker) + " was " + worn + " baseOutfit=" + akWorker.GetActorBase().GetOutfit(false) + " " + WornSummary(akWorker))
EndFunction

; Every load: a hired worker who has no outfit key (hired before Fase 27, or the
; key lost) is dressed for his trade. Idempotent.
Function Reconcile(Actor akWorker, string asProfession) global
    if !akWorker
        return
    endIf
    Wear(akWorker, asProfession)
    ; Fase 30: what the player gave and could not be put on while he was unloaded.
    WOSK_Gear.EnsureEquipped(akWorker)
EndFunction
