; Copyright (C) 2026 Awrawra
; SPDX-License-Identifier: GPL-3.0-only
; This file is part of Honest Work - Workers of Skyrim, free software under the
; GNU General Public License, version 3. See the LICENSE file at the repository root.

ScriptName WOSK_Names Hidden

; Display names for the ids the player reads, and nothing else. The ids
; themselves - "apprentice", "worker", "veteran", "master" - are load bearing:
; they are keys in professions\*.json (minTier, hiringFee, candidateWeight),
; they name the WOSK_Tier_* keywords, and they are part of the published
; extension API (GetWorkerLevel). Renaming one would break a
; third-party mod that already reads them, so the rename lives here, at the
; edge, where only text crosses.

; "Worker" named the second tier AND any hired worker at the same time, which
; is the collision the maintainer asked to remove. "Journeyman" is the rank that
; historically sits between apprentice and master, so the ladder now reads
; Apprentice -> Journeyman -> Veteran -> Master with no word doing two jobs.
;
; An id this function does not know comes back UNCHANGED, on purpose. A
; profession shipped by another mod may declare a tier of its own; printing its
; raw id is honest, while printing "Unknown" would hide it from the player and
; from whoever reads the log afterwards.
;
; Papyrus compares strings ignoring case, so a re-cased id resolves here too.
string Function TierLabel(string asTier) global
    if asTier == "apprentice"
        return "Apprentice"
    elseIf asTier == "worker"
        return "Journeyman"
    elseIf asTier == "veteran"
        return "Veteran"
    elseIf asTier == "master"
        return "Master"
    endIf
    return asTier
EndFunction

; Queue item 11: the situation the Workers tab prints. Two stored strings decide
; it, and the LIFECYCLE wins - a worker who is injured, retired or dead has no
; business showing "Working" because his contract state was never reset.
;
; The ids being translated here are the same load-bearing kind as the tiers
; above: "TRAVELING_TO" and the rest are written to StorageUtil, matched by
; WOSK_WorkerAliasScript._AdvanceTo, and read back by the harness. The rename
; lives at the edge for the same reason.
;
; Unknown input comes back unchanged, same rule and same reason as TierLabel.
;
; TWO OF THESE LABELS ARE WORDED THE WAY THEY ARE TO DODGE THE VM, and it is
; not a style choice. The Papyrus VM keeps ONE string per case-insensitive
; spelling - whichever was interned first, by any script in the load order - so
; a label that differs from an id only in case comes out wearing the id's case.
; Measured here on 2026-09-22: "Dead" printed as 'dead' and "Retired" as
; 'RETIRED' in round HW-20260922-021339-9b2d, while "Injured" survived (the id
; is INJURED_MINOR, so there is no collision to lose). Same mechanism as
; B003 and D099.
;
; The test NAM02 could not catch it: Papyrus == ignores case, so the comparison
; passed while the printed text was wrong. Only the raw MEASURE line showed it,
; which is why that line is printed.
;
; RETIRED is not hypothetical - a MAJOR incident retires a worker and leaves the
; alias filled (WOSK_WorkerAliasScript:481), so that row really does reach the
; player's screen.
string Function StateLabel(string asLifecycle, string asContract) global
    if asLifecycle == "DEAD"
        ; Not "Dead": see above. "Lost" is also what the ledger's obituary
        ; heading already calls them (WOSK_LedgerScript.ObituaryText).
        return "Lost"
    elseIf asLifecycle == "RETIRED"
        ; Not "Retired": see above.
        ; Fase 31 conserto 1 (D257): the maintainer asked for the cause on the label.
        return "Retired - hurt at work"
    elseIf asLifecycle == "INJURED_MINOR"
        return "Injured"
    endIf
    if asContract == "IDLE"
        return "Awaiting work"
    elseIf asContract == "TRAVELING_TO"
        return "Traveling out"
    elseIf asContract == "WORKING"
        ; "At work" and not "Working": measured on 2026-09-22, in the round
        ; HW-20260922-024756-6e2a, this label came out of here as "working"
        ; in the tracker line while the very same call printed "Working" to
        ; the harness eleven seconds earlier - the VM's case cache, and the
        ; contract id IS spelled WORKING. Same reasoning as Lost and
        ; Retired - hurt at work above (D127): a screen label is never the same
        ; word as the id it translates.
        return "At work"
    elseIf asContract == "TRAVELING_BACK"
        return "Returning"
    elseIf asContract == "AWAITING_PICKUP"
        return "Awaiting pickup"
    endIf
    return asContract
EndFunction

; Fase 28 (D234): the label of a worker, who may be a cook. A cook on a contract
; stays in his house, at the pot, through the three legs, so none of "Traveling
; out" / "At work" / "Returning" is true of him: he reads "Cooking at <house>".
; Every other profession, and the cook outside a contract or hurt/lost/retired,
; read what StateLabel says.
string Function StateLabelFor(string asLifecycle, string asContract, string asProfession, string asHouse) global
    if asProfession == "cook" && asLifecycle != "DEAD" && asLifecycle != "RETIRED" && asLifecycle != "INJURED_MINOR"
        if asContract == "TRAVELING_TO" || asContract == "WORKING" || asContract == "TRAVELING_BACK"
            return CookingLabel(asHouse)
        endIf
    endIf
    return StateLabel(asLifecycle, asContract)
EndFunction

; Fase 32 (D253): "Traveling out" was printed from the moment the contract was
; issued, while the worker still stood in the cell where he was hired (round 6:
; 82 s of wall clock, the tracker saying 'out' with her at the inn). aiDeparted is
; the stored WOSK_Departed: 0 until the worker has left the cell of the order (or
; the leg ended), 1 after. Only the TRAVELING_TO leg of a non-cook reads it; a
; missing key is read by the callers as 1, the old behaviour, so a save from
; before this build keeps its label.
string Function StateLabelDeparted(string asLifecycle, string asContract, string asProfession, string asHouse, Int aiDeparted) global
    if aiDeparted == 0 && asContract == "TRAVELING_TO" && asProfession != "cook" && asLifecycle != "DEAD" && asLifecycle != "RETIRED" && asLifecycle != "INJURED_MINOR"
        ; Not spelled like an id: no id of this mod collides with this text.
        return "Setting out"
    endIf
    return StateLabelFor(asLifecycle, asContract, asProfession, asHouse)
EndFunction

; One literal per house, not the house name concatenated: the VM keeps one string
; per spelling regardless of case (D127, D233), and "breezehome" is also the id.
string Function CookingLabel(string asHouse) global
    if asHouse == "breezehome"
        return "Cooking at Breezehome"
    elseIf asHouse == "tundra_homestead"
        return "Cooking at Tundra Homestead"
    endIf
    return "Cooking at home"
EndFunction

; Queue item 12: which way the player has to walk to reach a point, in words.
; The caller passes the vector FROM the player TO the worker, in world units -
; +X is east and +Y is north in Skyrim's worldspaces.
;
; No trigonometry on purpose. The eight sectors are 45 degrees wide, so the
; boundaries sit at tan(22.5) = 0.4142 and tan(67.5) = 2.4142, and comparing
; the two legs against 2.4142 decides the sector exactly - the same answer
; atan2 would give, with nothing to get wrong about quadrants or radians.
;
; The words are lowercase because the VM keeps one string per case-insensitive
; spelling (D127): if something in the load order interned "North" first, this
; prints "North". That is cosmetic here - unlike a status label, no id of this
; mod is spelled "north", so the word cannot come back meaning something else.
string Function BearingLabel(Float afDx, Float afDy) global
    Float ax = afDx
    if ax < 0.0
        ax = -ax
    endIf
    Float ay = afDy
    if ay < 0.0
        ay = -ay
    endIf
    ; Standing on the spot. Any direction would be a lie, and "north" is the
    ; one a reader would act on.
    if ax == 0.0 && ay == 0.0
        return "here"
    endIf
    if ay > ax * 2.4142
        if afDy > 0.0
            return "north"
        endIf
        return "south"
    endIf
    if ax > ay * 2.4142
        if afDx > 0.0
            return "east"
        endIf
        return "west"
    endIf
    if afDy > 0.0
        if afDx > 0.0
            return "north-east"
        endIf
        return "north-west"
    endIf
    if afDx > 0.0
        return "south-east"
    endIf
    return "south-west"
EndFunction

; Fase 27 conserto 1 (D235): the given names the mod hands a candidate that
; Real Names - Extended has not named (it names only an actor that has been
; loaded near the player). Plain ASCII, none of them a named NPC of the game.
; aiSex is ActorBase.GetSex(): 0 male, 1 female. The index wraps.
Int Function CandidateNameCount() global
    return 32
EndFunction

; Fase 33 etapa 1 (D261): the VM keeps ONE string per spelling regardless of case (D127),
; so a literal that another mod's script spelled first comes back in THAT spelling: round 8
; showed a candidate named "asA" (the name "Asa" against a parameter of the same letters).
; A given name starts with a capital; one that comes back starting with a lowercase letter
; is not shown. AsOrd takes the WHOLE name (the code of its first character): GetNthChar
; would intern the single letter and answer for both cases.
Bool Function NameReads(string asName) global
    if asName == ""
        return false
    endIf
    Int first = StringUtil.AsOrd(asName)
    return first >= 65 && first <= 90
EndFunction

string Function CandidateGivenName(Int aiSex, Int aiIndex) global
    string[] male = new string[32]
    male[0] = "Alrik"
    male[1] = "Bjorn"
    male[2] = "Brand"
    male[3] = "Dagur"
    male[4] = "Eirik"
    male[5] = "Finnar"
    male[6] = "Geirmund"
    male[7] = "Halvar"
    male[8] = "Ingvar"
    male[9] = "Jorund"
    male[10] = "Knut"
    male[11] = "Leif"
    male[12] = "Magnus"
    male[13] = "Njall"
    male[14] = "Orm"
    male[15] = "Ragnar"
    male[16] = "Sigurd"
    male[17] = "Thorvald"
    male[18] = "Ulfar"
    male[19] = "Valdr"
    male[20] = "Hrolf"
    male[21] = "Torstein"
    male[22] = "Asmund"
    male[23] = "Bard"
    male[24] = "Egil"
    male[25] = "Fridleif"
    male[26] = "Gisli"
    male[27] = "Hakon"
    male[28] = "Kolbein"
    male[29] = "Solvar"
    male[30] = "Steinar"
    male[31] = "Vermund"
    string[] female = new string[32]
    female[0] = "Asdis"
    female[1] = "Bergljot"
    female[2] = "Dagny"
    female[3] = "Eira"
    female[4] = "Freydis"
    female[5] = "Gudrun"
    female[6] = "Hilde"
    female[7] = "Ingrid"
    female[8] = "Jorunn"
    female[9] = "Kolbrun"
    female[10] = "Liv"
    female[11] = "Maren"
    female[12] = "Njorun"
    female[13] = "Ragna"
    female[14] = "Sigrun"
    female[15] = "Thora"
    female[16] = "Una"
    female[17] = "Vigdis"
    female[18] = "Yrsa"
    female[19] = "Aslaug"
    female[20] = "Borghild"
    female[21] = "Helga"
    female[22] = "Runa"
    female[23] = "Solveig"
    female[24] = "Svana"
    female[25] = "Tora"
    female[26] = "Ylva"
    female[27] = "Orla"
    female[28] = "Hervor"
    female[29] = "Gerda"
    female[30] = "Alvild"
    female[31] = "Embla"
    Int idx = aiIndex
    if idx < 0
        idx = -idx
    endIf
    idx = idx % 32
    if aiSex == 1
        return female[idx]
    endIf
    return male[idx]
EndFunction
