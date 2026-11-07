; Copyright (C) 2026 Awrawra
; SPDX-License-Identifier: GPL-3.0-only
; This file is part of Honest Work - Workers of Skyrim, free software under the
; GNU General Public License, version 3. See the LICENSE file at the repository root.

ScriptName WOSK_Gear Hidden

; Fase 30 (D240-D246): the hunter's equipment handed over by the
; player. The player talks to a hired hunter ("I want to give you some equipment"),
; the gift menu opens, and what stays with the hunter is held to his tier:
;   - a bow, arrows or LIGHT armor within his tier is kept, equipped for real and
;     recorded (StorageUtil lists on the worker) so that it can be handed back;
;   - anything above his tier, any heavy armor, shield or other item goes straight
;     back to the player with a notice that says why.
; The bow multiplies the batch by the tier of the bow, the armor lowers the incident
; chance by the tier of the armor (HonestWork/professions/00_core.json, hunter tiers,
; bowGearMultiplier / armorGearReduction). Dismissed, everything the player gave goes
; back to the player; dead, it stays on the corpse.
;
; Tier tables (D241): vanilla keywords and records, read from the
; game data (Skyrim.esm, Update.esm, Dawnguard.esm, Dragonborn.esm),
; never typed from memory. An item no table names is refused, not guessed at.

Int Function RankOf(string asTier) global
    if asTier == "apprentice"
        return 0
    elseIf asTier == "worker"
        return 1
    elseIf asTier == "veteran"
        return 2
    elseIf asTier == "master"
        return 3
    endIf
    return -1
EndFunction

string Function TierId(Int aiRank) global
    if aiRank == 0
        return "apprentice"
    elseIf aiRank == 1
        return "worker"
    elseIf aiRank == 2
        return "veteran"
    elseIf aiRank == 3
        return "master"
    endIf
    return ""
EndFunction

string Function KeyForms() global
    return "WOSK_GiftForms"
EndFunction

string Function KeyCounts() global
    return "WOSK_GiftCounts"
EndFunction

Bool Function _HasKw(Form akItem, Int aiKeyword, string asPlugin) global
    Keyword k = Game.GetFormFromFile(aiKeyword, asPlugin) as Keyword
    return k != None && akItem.HasKeyword(k)
EndFunction

Bool Function _Is(Form akItem, Int aiBase, string asPlugin) global
    Form f = Game.GetFormFromFile(aiBase, asPlugin)
    return f != None && f == akItem
EndFunction

; Light armor by material keyword. -1 = not a light armor the table names, -2 = heavy,
; -3 = shield.
Int Function ArmorItemTier(Armor akArmor) global
    if !akArmor
        return -1
    endIf
    if _HasKw(akArmor, 0x000965B2, "Skyrim.esm")
        return -3
    endIf
    if _HasKw(akArmor, 0x0006BBD2, "Skyrim.esm")
        return -2
    endIf
    if !_HasKw(akArmor, 0x0006BBD3, "Skyrim.esm")
        return -1
    endIf
    ; Apprentice: leather, hide, studded, imperial light, forsworn
    if _HasKw(akArmor, 0x0006BBDB, "Skyrim.esm") || _HasKw(akArmor, 0x0006BBDD, "Skyrim.esm") \
       || _HasKw(akArmor, 0x0006BBDF, "Skyrim.esm") || _HasKw(akArmor, 0x0006BBE0, "Skyrim.esm") \
       || _HasKw(akArmor, 0x000009B9, "Update.esm")
        return 0
    endIf
    ; Journeyman: elven, gilded elven, scaled, chitin light
    if _HasKw(akArmor, 0x0006BBD9, "Skyrim.esm") || _HasKw(akArmor, 0x0006BBDA, "Skyrim.esm") \
       || _HasKw(akArmor, 0x0006BBDE, "Skyrim.esm") || _HasKw(akArmor, 0x00024102, "Dragonborn.esm")
        return 1
    endIf
    ; Veteran: glass
    if _HasKw(akArmor, 0x0006BBDC, "Skyrim.esm")
        return 2
    endIf
    ; Master: dragonscale, stalhrim light
    if _HasKw(akArmor, 0x0006BBD6, "Skyrim.esm") || _HasKw(akArmor, 0x00024107, "Dragonborn.esm")
        return 3
    endIf
    return -1
EndFunction

; Bows by material keyword (the Forsworn bow carries none in the base game: named by
; record). -1 = not a bow the table names.
Int Function BowItemTier(Weapon akWeapon) global
    if !akWeapon || !_HasKw(akWeapon, 0x0001E715, "Skyrim.esm")
        return -1
    endIf
    if _Is(akWeapon, 0x000CEE9B, "Skyrim.esm")
        return 0
    endIf
    ; Apprentice: wood (long, hunting), imperial, iron, steel
    if _HasKw(akWeapon, 0x0001E717, "Skyrim.esm") || _HasKw(akWeapon, 0x0001E718, "Skyrim.esm") \
       || _HasKw(akWeapon, 0x0001E719, "Skyrim.esm") || _HasKw(akWeapon, 0x000C5C00, "Skyrim.esm")
        return 0
    endIf
    ; Journeyman: dwarven, elven, orcish, falmer (plain and honed), nordic
    if _HasKw(akWeapon, 0x0001E71A, "Skyrim.esm") || _HasKw(akWeapon, 0x0001E71B, "Skyrim.esm") \
       || _HasKw(akWeapon, 0x0001E71C, "Skyrim.esm") || _HasKw(akWeapon, 0x000C5C03, "Skyrim.esm") \
       || _HasKw(akWeapon, 0x000C5C04, "Skyrim.esm") || _HasKw(akWeapon, 0x00026230, "Dragonborn.esm")
        return 1
    endIf
    ; Veteran: glass
    if _HasKw(akWeapon, 0x0001E71D, "Skyrim.esm")
        return 2
    endIf
    ; Master: ebony, daedric, stalhrim, dragonbone
    if _HasKw(akWeapon, 0x0001E71E, "Skyrim.esm") || _HasKw(akWeapon, 0x0001E71F, "Skyrim.esm") \
       || _HasKw(akWeapon, 0x0002622F, "Dragonborn.esm") || _HasKw(akWeapon, 0x00019822, "Dawnguard.esm")
        return 3
    endIf
    return -1
EndFunction

; Arrows have no material keyword in the base game: named by record.
Int Function AmmoItemTier(Ammo akAmmo) global
    if !akAmmo
        return -1
    endIf
    if _Is(akAmmo, 0x0001397D, "Skyrim.esm") || _Is(akAmmo, 0x0001397F, "Skyrim.esm") || _Is(akAmmo, 0x000CEE9E, "Skyrim.esm")
        return 0
    endIf
    if _Is(akAmmo, 0x000139BB, "Skyrim.esm") || _Is(akAmmo, 0x000139BC, "Skyrim.esm") || _Is(akAmmo, 0x000139BD, "Skyrim.esm") \
       || _Is(akAmmo, 0x00038341, "Skyrim.esm") || _Is(akAmmo, 0x0002623B, "Dragonborn.esm")
        return 1
    endIf
    if _Is(akAmmo, 0x000139BE, "Skyrim.esm")
        return 2
    endIf
    if _Is(akAmmo, 0x000139BF, "Skyrim.esm") || _Is(akAmmo, 0x000139C0, "Skyrim.esm") \
       || _Is(akAmmo, 0x00026239, "Dragonborn.esm") || _Is(akAmmo, 0x000176F4, "Dawnguard.esm")
        return 3
    endIf
    return -1
EndFunction

; The kind of an item for the gift: "bow", "arrow", "armor" or "" (anything else).
string Function ItemKind(Form akItem) global
    if akItem as Weapon
        if (akItem as Weapon).IsBow()
            return "bow"
        endIf
        return ""
    endIf
    if akItem as Ammo
        return "arrow"
    endIf
    if akItem as Armor
        return "armor"
    endIf
    return ""
EndFunction

; The tier rank of a gift item, or the negative code of Armor/Bow/AmmoItemTier.
Int Function ItemTier(Form akItem) global
    string kind = ItemKind(akItem)
    if kind == "bow"
        return BowItemTier(akItem as Weapon)
    elseIf kind == "arrow"
        return AmmoItemTier(akItem as Ammo)
    elseIf kind == "armor"
        return ArmorItemTier(akItem as Armor)
    endIf
    return -1
EndFunction

Int Function WorkerRank(Actor akWorker) global
    return RankOf(StorageUtil.GetStringValue(akWorker, "WOSK_Tier", "apprentice"))
EndFunction

; ---------------------------------------------------------------------------
; The record of what the player gave.

Int Function GiftedCount(Actor akWorker, Form akItem) global
    Int idx = StorageUtil.FormListFind(akWorker, KeyForms(), akItem)
    if idx < 0
        return 0
    endIf
    return StorageUtil.IntListGet(akWorker, KeyCounts(), idx)
EndFunction

Function _RecordGift(Actor akWorker, Form akItem, Int aiCount) global
    Int idx = StorageUtil.FormListFind(akWorker, KeyForms(), akItem)
    if idx < 0
        StorageUtil.FormListAdd(akWorker, KeyForms(), akItem, false)
        StorageUtil.IntListAdd(akWorker, KeyCounts(), aiCount, true)
    else
        StorageUtil.IntListSet(akWorker, KeyCounts(), idx, StorageUtil.IntListGet(akWorker, KeyCounts(), idx) + aiCount)
    endIf
EndFunction

Int Function GiftStacks(Actor akWorker) global
    return StorageUtil.FormListCount(akWorker, KeyForms())
EndFunction

; ---------------------------------------------------------------------------
; Hand-over.

; One item that reached the hunter. 1 = kept (recorded, equipped when he is loaded);
; 0 = above his tier, -1 = not a bow, arrow or light armor the tables name, -2 = heavy
; armor, -3 = shield. Anything refused goes straight back to the player with the
; reason in a corner message.
Int Function AcceptItem(Actor akWorker, Form akItem, Int aiCount) global
    Actor player = Game.GetPlayer()
    ; Fase 34 etapa 2 (P11): the mod gives no equipment to a follower; it goes back.
    if WOSK_Followers.IsFollower(akWorker)
        akWorker.RemoveItem(akItem, aiCount, true, player)
        Debug.Notification("Honest Work: " + akWorker.GetDisplayName() + " is a follower; use his own menu for equipment.")
        return -4
    endIf
    Int itemTier = ItemTier(akItem)
    Int workerRank = WorkerRank(akWorker)
    string who = akWorker.GetDisplayName()
    string what = akItem.GetName()
    Int result = 1
    if itemTier == -2
        result = -2
        Debug.Notification("Honest Work: " + who + " does not wear heavy armor (" + what + ").")
    elseIf itemTier == -3
        result = -3
        Debug.Notification("Honest Work: " + who + " has no use for a shield (" + what + ").")
    elseIf itemTier < 0
        result = -1
        Debug.Notification("Honest Work: " + who + " only takes bows, arrows and light armor (" + what + ").")
    elseIf itemTier > workerRank
        result = 0
        Debug.Notification("Honest Work: " + what + " needs a " + WOSK_Names.TierLabel(TierId(itemTier)) + " hunter; " + who + " is " + WOSK_Names.TierLabel(TierId(workerRank)) + ".")
    endIf
    if result != 1
        akWorker.RemoveItem(akItem, aiCount, true, player)
        Debug.Trace("WOSK_Gear: refused - worker=" + akWorker + " item=" + akItem + " x" + aiCount + " itemTier=" + itemTier + " workerRank=" + workerRank + " result=" + result)
        return result
    endIf
    _RecordGift(akWorker, akItem, aiCount)
    Debug.Trace("WOSK_Gear: kept - worker=" + akWorker + " item=" + akItem + " x" + aiCount + " itemTier=" + itemTier + " workerRank=" + workerRank)
    EquipGiven(akWorker, akItem)
    return 1
EndFunction

; Puts a kept item on for real. A worker without loaded 3D cannot take EquipItem (the
; F28C.8 measurement), so the call is left for the next time he is loaded
; (EnsureEquipped, run at issue and on every load).
Function EquipGiven(Actor akWorker, Form akItem) global
    if !akWorker.Is3DLoaded()
        Debug.Trace("WOSK_Gear: equip deferred, 3D not loaded - worker=" + akWorker + " item=" + akItem)
        return
    endIf
    string kind = ItemKind(akItem)
    if kind == "arrow"
        akWorker.EquipItem(akItem, false, true)
    else
        akWorker.EquipItem(akItem, true, true)
    endIf
    Debug.Trace("WOSK_Gear: equip - worker=" + akWorker + " item=" + akItem + " kind=" + kind + " equipped=" + akWorker.IsEquipped(akItem))
EndFunction

; Everything the player gave that is not on yet goes on, best bow and best armor last
; so they win the slot. Idempotent.
Function EnsureEquipped(Actor akWorker) global
    if !akWorker || !akWorker.Is3DLoaded()
        return
    endIf
    Int n = StorageUtil.FormListCount(akWorker, KeyForms())
    Int rank = 0
    while rank < 4
        Int i = 0
        while i < n
            Form f = StorageUtil.FormListGet(akWorker, KeyForms(), i)
            if f && ItemTier(f) == rank && akWorker.GetItemCount(f) > 0 && !akWorker.IsEquipped(f)
                EquipGiven(akWorker, f)
            endIf
            i += 1
        endWhile
        rank += 1
    endWhile
EndFunction

; The conversation: the gift menu (latent), then the inventory difference decides
; what stays. Only the hunters; the speaker is next to the player by definition.
Function GiveToWorker(Actor akWorker) global
    if !akWorker
        return
    endIf
    string who = akWorker.GetDisplayName()
    ; Fase 34 etapa 2 (P11): before the gift menu opens, not after.
    if WOSK_Followers.IsFollower(akWorker)
        Debug.Notification("Honest Work: " + who + " is a follower; use his own menu for equipment.")
        return
    endIf
    if StorageUtil.GetStringValue(akWorker, "WOSK_Profession", "") != "hunter"
        Debug.Notification("Honest Work: only a hunter can use a bow or armor for his work. " + who + " has no use for it.")
        return
    endIf
    Form[] beforeForms = new Form[128]
    Int[] beforeCounts = new Int[128]
    Int nBefore = akWorker.GetNumItems()
    if nBefore > 128
        nBefore = 128
    endIf
    Int i = 0
    while i < nBefore
        beforeForms[i] = akWorker.GetNthForm(i)
        beforeCounts[i] = akWorker.GetItemCount(beforeForms[i])
        i += 1
    endWhile
    akWorker.ShowGiftMenu(true, None, false, false)
    Int stacks = 0
    Int kept = 0
    Int nAfter = akWorker.GetNumItems()
    ; Collected first: AcceptItem moves items, which would shift the indices.
    Form[] gained = new Form[128]
    Int[] gainedCounts = new Int[128]
    Int g = 0
    i = 0
    while i < nAfter && g < 128
        Form f = akWorker.GetNthForm(i)
        Int had = 0
        Int j = 0
        while j < nBefore
            if beforeForms[j] == f
                had = beforeCounts[j]
                j = nBefore
            endIf
            j += 1
        endWhile
        Int delta = akWorker.GetItemCount(f) - had
        if f && delta > 0
            gained[g] = f
            gainedCounts[g] = delta
            g += 1
        endIf
        i += 1
    endWhile
    i = 0
    while i < g
        stacks += 1
        if AcceptItem(akWorker, gained[i], gainedCounts[i]) == 1
            kept += 1
        endIf
        i += 1
    endWhile
    Debug.Trace("WOSK_Gear: gift menu closed - worker=" + akWorker + " stacks=" + stacks + " kept=" + kept)
    if stacks == 0
        Debug.Notification("Honest Work: you gave " + who + " nothing.")
    elseIf kept > 0
        Debug.Notification("Honest Work: " + who + " carries " + GearLine(akWorker) + ".")
    endIf
    PushGear(akWorker)
EndFunction

; ---------------------------------------------------------------------------
; Reading what the hunter carries (always from the game, never from a counter).

; Tier rank of the bow in his hand; -1 when none. The bow the mod hands every hunter
; does not count (D238), unless the player gave one of the same record. A worker
; whose 3D is not loaded reads from the record of gifts (ASSUMPTION, D243: equipment
; state is not readable without 3D).
Int Function EquippedBowTier(Actor akWorker) global
    Weapon hand = akWorker.GetEquippedWeapon(false)
    if hand && hand.IsBow()
        if hand == WOSK_Outfits.HuntBow() && GiftedCount(akWorker, hand) <= 0
            return -1
        endIf
        return BowItemTier(hand)
    endIf
    if akWorker.Is3DLoaded()
        return -1
    endIf
    return _BestGifted(akWorker, "bow")
EndFunction

; Fase 33 etapa 1 (D260): the armor the player GAVE and he still holds, 3D or not. It used
; to read the body when the 3D was up - the trade pieces, the gift that "was not equipped"
; - and the record of gifts when it was not, so the panel's label changed with where the
; worker stood (round 8: Apprentice / veteran for the same hunter). The trade outfit is
; the mod's own, like the bow the mod hands every hunter (D238), and counts for nothing.
Int Function ArmorTierWorn(Actor akWorker) global
    return _BestGifted(akWorker, "armor")
EndFunction

; Best tier among the arrows he still holds that the player gave.
Int Function ArrowTierHeld(Actor akWorker) global
    return _BestGifted(akWorker, "arrow")
EndFunction

Int Function _BestGifted(Actor akWorker, string asKind) global
    Int best = -1
    Int n = StorageUtil.FormListCount(akWorker, KeyForms())
    Int i = 0
    while i < n
        Form f = StorageUtil.FormListGet(akWorker, KeyForms(), i)
        if f && ItemKind(f) == asKind && akWorker.GetItemCount(f) > 0
            Int t = ItemTier(f)
            if t > best
                best = t
            endIf
        endIf
        i += 1
    endWhile
    return best
EndFunction

; The multiplier the batch gets from the bow at issue: the tier value of the bow he
; carries (hunter tiers, bowGearMultiplier), 1.0 without one.
Float Function BowMultiplier(Actor akWorker, string asProfession, Float afTaskBow) global
    Int t = EquippedBowTier(akWorker)
    if t < 0
        return 1.0
    endIf
    return WOSK_Registry.GetTierFloat(asProfession, TierId(t), "bowGearMultiplier", afTaskBow)
EndFunction

; The incident chance the armor takes off at issue (hunter tiers, armorGearReduction).
Float Function ArmorReduction(Actor akWorker, string asProfession) global
    Int t = ArmorTierWorn(akWorker)
    if t < 0
        return 0.0
    endIf
    return WOSK_Registry.GetTierFloat(asProfession, TierId(t), "armorGearReduction", 0.0)
EndFunction

; "bow=Veteran;arrows=Journeyman;armor=Apprentice" - an empty value = none. The page
; reads it (model.ts parseGear).
string Function GearData(Actor akWorker) global
    string bow = ""
    string arrows = ""
    string worn = ""
    Int t = EquippedBowTier(akWorker)
    if t >= 0
        bow = WOSK_Names.TierLabel(TierId(t))
    endIf
    t = ArrowTierHeld(akWorker)
    if t >= 0
        arrows = WOSK_Names.TierLabel(TierId(t))
    endIf
    t = ArmorTierWorn(akWorker)
    if t >= 0
        worn = WOSK_Names.TierLabel(TierId(t))
    endIf
    return "bow=" + bow + ";arrows=" + arrows + ";armor=" + worn
EndFunction

; The same for a corner message.
string Function GearLine(Actor akWorker) global
    string line = ""
    Int t = EquippedBowTier(akWorker)
    if t >= 0
        line = "a " + WOSK_Names.TierLabel(TierId(t)) + " bow"
    endIf
    t = ArrowTierHeld(akWorker)
    if t >= 0
        if line != ""
            line += ", "
        endIf
        line += WOSK_Names.TierLabel(TierId(t)) + " arrows"
    endIf
    t = ArmorTierWorn(akWorker)
    if t >= 0
        if line != ""
            line += ", "
        endIf
        line += WOSK_Names.TierLabel(TierId(t)) + " armor"
    endIf
    if line == ""
        return "nothing of yours"
    endIf
    return line
EndFunction

; Tells the panel what the hunter in a slot carries. Its own channel: the worker list
; has no field for it and the DLL is out of this phase's scope (D244). Not through
; ReportOutcome: that one also keeps WOSK_LastOutcome, which is an order's answer.
Function PushGear(Actor akWorker, Int aiSlot = -1) global
    Int slot = aiSlot
    if slot < 0
        WOSK_ControllerScript c = WOSK_PanelBridgeScript.GetController()
        if c
            slot = c.WorkerSlotOf(akWorker)
        endIf
    endIf
    if slot < 0
        return
    endIf
    WOSK_Panel.SetOutcome("gear", slot, "", GearData(akWorker), 0)
EndFunction

; ---------------------------------------------------------------------------
; Dismissal.

; Hands everything the player gave back to the player (dismissal). Returns the number
; of stacks handed back. A dead worker is never passed here: it stays on the corpse.
Int Function ReturnToPlayer(Actor akWorker) global
    Actor player = Game.GetPlayer()
    Int n = StorageUtil.FormListCount(akWorker, KeyForms())
    Int given = 0
    Int i = 0
    while i < n
        Form f = StorageUtil.FormListGet(akWorker, KeyForms(), i)
        Int owed = StorageUtil.IntListGet(akWorker, KeyCounts(), i)
        Int has = 0
        if f
            has = akWorker.GetItemCount(f)
        endIf
        if has < owed
            owed = has
        endIf
        if f && owed > 0
            akWorker.UnequipItem(f, false, true)
            akWorker.RemoveItem(f, owed, true, player)
            given += 1
            Debug.Trace("WOSK_Gear: handed back - worker=" + akWorker + " item=" + f + " x" + owed)
        endIf
        i += 1
    endWhile
    StorageUtil.FormListClear(akWorker, KeyForms())
    StorageUtil.IntListClear(akWorker, KeyCounts())
    if given > 0
        Debug.Notification("Honest Work: " + akWorker.GetDisplayName() + " hands back the equipment you gave.")
    endIf
    return given
EndFunction

; Death: the record goes, the items stay where they are (on the corpse).
Function ForgetGifts(Actor akWorker) global
    StorageUtil.FormListClear(akWorker, KeyForms())
    StorageUtil.IntListClear(akWorker, KeyCounts())
EndFunction

; ---------------------------------------------------------------------------
; Bow in hand at the work site (D245): drawn while he works, put away
; for the road. DrawWeapon needs his 3D; the alias calls this on state change and when
; he loads (D245).

Function DrawAtWork(Actor akWorker) global
    if akWorker && akWorker.Is3DLoaded() && akWorker.GetEquippedWeapon(false) && !akWorker.IsWeaponDrawn()
        akWorker.DrawWeapon()
    endIf
EndFunction

Function PutAway(Actor akWorker) global
    if akWorker && akWorker.Is3DLoaded() && akWorker.IsWeaponDrawn()
        akWorker.SheatheWeapon()
    endIf
EndFunction
