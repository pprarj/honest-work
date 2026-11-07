; Copyright (C) 2026 Awrawra
; SPDX-License-Identifier: GPL-3.0-only
; This file is part of Honest Work - Workers of Skyrim, free software under the
; GNU General Public License, version 3. See the LICENSE file at the repository root.

ScriptName WOSK_Followers Hidden

; Fase 34 etapa 2 (D299): a follower of the player as a worker. Global helpers; the
; decisions (cap, one cook per hold, house) stay on WOSK_ControllerScript.HireFollower.
; The follower is a unique NPC the mod did not create: it carries the mark below, and
; the code that dresses, names, packs or gifts a worker skips a marked actor.

string Function KeyMark() global
    return "WOSK_IsFollower"
EndFunction

; 1 when the home is the follower's own (Whiterun): there is no ref to go to, so the
; vanilla package he gets back when the overrides are cleared takes him there (V077 F34E1.5).
string Function KeyNativeHome() global
    return "WOSK_FollowerNativeHome"
EndFunction

; The LinkCustom02 target another mod had set on him before the first SetLinkedRef of
; the mod (P9); KeySavedLink says it was read, because "none" is also an answer.
string Function KeyPrevLink() global
    return "WOSK_PrevLinkCustom02"
EndFunction

string Function KeySavedLink() global
    return "WOSK_PrevLinkCustom02Saved"
EndFunction

; X offset of his spot at the Bannered Mare fallback, so two followers do not stand on one point.
string Function KeyHomeOffset() global
    return "WOSK_HomeOffsetX"
EndFunction

string Function NffPlugin() global
    return "nwsFollowerFramework.esp"
EndFunction

Bool Function IsFollower(Actor akActor) global
    return akActor && StorageUtil.GetIntValue(akActor, KeyMark(), 0) == 1
EndFunction

; PO3's GetPlayerFollowers is the only list of followers; without PO3 the section is empty.
Bool Function Po3Present() global
    return SKSE.GetPluginVersion("powerofthree's Papyrus Extender") > 0
EndFunction

; P8: the vanilla skill nearest the gesture of the trade (D299). Mirrored in
; the development reference model and checked against this text by its test.
string Function SkillFor(string asProfession) global
    if asProfession == "miner"
        return "Smithing"
    elseIf asProfession == "hunter"
        return "Marksman"
    elseIf asProfession == "cook"
        return "Alchemy"
    elseIf asProfession == "herbalist"
        return "Alchemy"
    elseIf asProfession == "fisher"
        return "Sneak"
    elseIf asProfession == "laborer"
        return "TwoHanded"
    endIf
    return ""
EndFunction

; A3: up to 24 apprentice, 25-49 worker, 50-74 veteran, 75+ master.
string Function TierForSkill(Int aiSkill) global
    if aiSkill >= 75
        return "master"
    elseIf aiSkill >= 50
        return "veteran"
    elseIf aiSkill >= 25
        return "worker"
    endIf
    return "apprentice"
EndFunction

Int Function SkillLevel(Actor akFollower, string asProfession) global
    string skill = SkillFor(asProfession)
    if !akFollower || skill == ""
        return 0
    endIf
    return akFollower.GetBaseActorValue(skill) as Int
EndFunction

string Function TierFor(Actor akFollower, string asProfession) global
    return TierForSkill(SkillLevel(akFollower, asProfession))
EndFunction

; DialogueFollower quest (Skyrim.esm 0x000750BA, the slot quest vanilla and the NFF both
; use; slotDF was measured on it in F34E1, V077).
Quest Function DialogueQuest() global
    return Game.GetFormFromFile(0x000750BA, "Skyrim.esm") as Quest
EndFunction

; The slot of the DialogueFollower quest the actor occupies, -1 when none, -2 without the quest.
Int Function FrameworkSlot(Actor akFollower) global
    Quest df = DialogueQuest()
    if !df
        return -2
    endIf
    Int n = df.GetNumAliases()
    Int i = 0
    while i < n && i < 16
        ReferenceAlias a = df.GetNthAlias(i) as ReferenceAlias
        if a && a.GetReference() == akFollower as ObjectReference
            return i
        endIf
        i += 1
    endWhile
    return -1
EndFunction

; The id of the rule that refuses this follower (A1, D298 item 5 and P13), "" when he can be
; hired. Ids, worded on the page: NOT_UNIQUE, ANIMAL, NFF_IMPORT, OWN_FRAMEWORK.
string Function Refusal(Actor akFollower) global
    if !akFollower.GetActorBase().IsUnique()
        return "NOT_UNIQUE"
    endIf
    Race r = akFollower.GetRace()
    if r && r.HasKeywordString("ActorTypeAnimal")
        return "ANIMAL"
    endIf
    ; P13: a custom follower imported into the NFF (Serana included) runs on a script of its own.
    Faction imported = PO3_SKSEFunctions.GetFormFromEditorID("nwsFF_ImportFac") as Faction
    if imported && akFollower.IsInFaction(imported)
        return "NFF_IMPORT"
    endIf
    ; A follower on a framework of its own holds no slot of the DialogueFollower quest.
    if FrameworkSlot(akFollower) < 0
        return "OWN_FRAMEWORK"
    endIf
    return ""
EndFunction

; Lets go of him through the framework that holds him, before any package of the mod
; (a follower still held is pulled back by the NFF warp, D298). NFF: the actor goes into the
; controller's speaker alias (2) and DismissFollower(-1, 0) is silent. Without NFF: the
; vanilla alias, DismissFollower(0, 0) - the D298 path, not measured (V077: etapa 4).
; True when he is no longer a teammate.
Bool Function DismissFromFramework(Actor akFollower) global
    DialogueFollowerScript d = DialogueQuest() as DialogueFollowerScript
    if !d || !akFollower
        Debug.Trace("WOSK_Followers: dismiss refused, no DialogueFollower script")
        return false
    endIf
    string path = "none"
    if Game.IsPluginInstalled(NffPlugin())
        Quest nff = Game.GetFormFromFile(0x0000434F, NffPlugin()) as Quest
        ReferenceAlias speaker = None
        if nff
            speaker = nff.GetAlias(2) as ReferenceAlias
        endIf
        if speaker
            speaker.ForceRefTo(akFollower)
            d.DismissFollower(-1, 0)
            path = "nff"
        endIf
    elseIf d.pFollowerAlias && d.pFollowerAlias.GetActorRef() == akFollower
        d.DismissFollower(0, 0)
        path = "vanilla"
    endIf
    Utility.Wait(2.0)
    Bool released = !akFollower.IsPlayerTeammate()
    Debug.Trace("WOSK_Followers: dismiss " + akFollower + " path=" + path + " released=" + released + " slotDF=" + FrameworkSlot(akFollower))
    return released
EndFunction

; Fase 35 etapa 8 (V100): the way back of DismissFromFramework. DialogueFollowerScript.SetFollower
; is the door both frameworks answer: vanilla runs its own, and the NFF replaces the script so it
; lands in nwsFollowerControllerScript.RecruitFollower (read in the NFF source, SetFollower l.39 /
; RecruitFollower l.341; it acts on a timer of 0.2 s, so the result is polled). True when he is a
; teammate again. The caller has already taken his guard marks off.
Bool Function RecruitToFramework(Actor akFollower) global
    DialogueFollowerScript d = DialogueQuest() as DialogueFollowerScript
    if !d || !akFollower
        Debug.Trace("WOSK_Followers: RECRUTAR-DE-VOLTA refused, no DialogueFollower script")
        return false
    endIf
    if akFollower.IsPlayerTeammate()
        Debug.Trace("WOSK_Followers: RECRUTAR-DE-VOLTA " + akFollower + " is a teammate already")
        return true
    endIf
    d.SetFollower(akFollower)
    Int waited = 0
    while !akFollower.IsPlayerTeammate() && waited < 10
        Utility.Wait(0.5)
        waited += 1
    endWhile
    Bool back = akFollower.IsPlayerTeammate()
    Debug.Trace("WOSK_Followers: RECRUTAR-DE-VOLTA " + akFollower + " teammate=" + back as Int + " slotDF=" + FrameworkSlot(akFollower) + " waited=" + (waited as Float * 0.5) + " s")
    if back
        ; Fase 35 etapa 9 (V102): the dialogue of a released guard came out mixed. What the framework's
        ; lines test is read here (factions with rank, slot) on him and on one follower the framework
        ; recruited by its own dialogue, so the next round compares the two; then the one repair the
        ; source of RecruitAction/RemoveAction supports (the dismissed mark off, the ranks to 0).
        LogFrameworkState("RECRUTADO-DE-VOLTA", akFollower)
        RepairFrameworkMarks(akFollower)
        Actor ref = ReferenceFollower(akFollower)
        if ref
            LogFrameworkState("REFERENCIA-DIALOGO", ref)
        else
            Debug.Trace("WOSK_Followers: NFF-ESTADO REFERENCIA-DIALOGO none - no other follower of the framework to compare")
        endIf
    endIf
    return back
EndFunction

; The factions the framework's dialogue and slots turn on. EditorIDs resolved at run time (never a
; FormID from memory); a name that does not resolve is logged as such.
string Function FactionState(Actor akActor, string asEditorId) global
    Faction f = PO3_SKSEFunctions.GetFormFromEditorID(asEditorId) as Faction
    if !f
        return asEditorId + "=sem-form"
    endIf
    if !akActor.IsInFaction(f)
        return asEditorId + "=0"
    endIf
    return asEditorId + "=1/rank" + akActor.GetFactionRank(f)
EndFunction

Function LogFrameworkState(string asTag, Actor akActor) global
    Debug.Trace("WOSK_Followers: NFF-ESTADO " + asTag + " " + akActor + " teammate=" + akActor.IsPlayerTeammate() as Int + " slotDF=" + FrameworkSlot(akActor) + " " \
        + FactionState(akActor, "CurrentFollowerFaction") + " " + FactionState(akActor, "PotentialFollowerFaction") + " " + FactionState(akActor, "DismissedFollower") + " " \
        + FactionState(akActor, "CurrentHireling") + " " + FactionState(akActor, "PlayerFollowerFaction") + " " + FactionState(akActor, "FollowerCommentFaction") + " WaitingForPlayer=" + akActor.GetActorValue("WaitingForPlayer"))
EndFunction

; One teammate of the player that is neither a guard nor a worker nor the one given: the framework
; recruited him by its own dialogue (or vanilla did). None when there is none or PO3 is absent.
Actor Function ReferenceFollower(Actor akExcept) global
    if !Po3Present()
        return None
    endIf
    Actor[] found = PO3_SKSEFunctions.GetPlayerFollowers()
    Int i = 0
    while found && i < found.Length
        Actor f = found[i]
        if f && f != akExcept && !IsFollower(f) && StorageUtil.GetIntValue(f, "WOSK_Guard", 0) == 0
            return f
        endIf
        i += 1
    endWhile
    return None
EndFunction

; The dismissal of the framework puts the dismissed mark on and the ranks at -1; the recruitment
; takes both back. If the mark stayed (the recruitment ran on a timer and lost), it comes off here.
Function RepairFrameworkMarks(Actor akFollower) global
    Faction dismissed = PO3_SKSEFunctions.GetFormFromEditorID("DismissedFollower") as Faction
    Faction cur = PO3_SKSEFunctions.GetFormFromEditorID("CurrentFollowerFaction") as Faction
    Bool fixedAny = false
    if dismissed && akFollower.IsInFaction(dismissed)
        akFollower.RemoveFromFaction(dismissed)
        fixedAny = true
    endIf
    if cur && akFollower.IsInFaction(cur) && akFollower.GetFactionRank(cur) < 0
        akFollower.SetFactionRank(cur, 0)
        fixedAny = true
    endIf
    Debug.Trace("WOSK_Followers: NFF-REPARO " + akFollower + " acted=" + fixedAny as Int)
EndFunction

; Fase 34 etapa 4 (A4, D306): the one way out for a follower, free. Order matters (V077: a
; re-recruit does not take the override away): the packages go FIRST so the package of his
; own comes back, then the link the other mod had, then the marks. Never Disable.
Function ReleaseFollower(Actor akFollower) global
    if !akFollower
        return
    endIf
    ActorUtil.ClearPackageOverride(akFollower)
    Keyword link = Game.GetFormFromFile(0x0005D5E7, "Skyrim.esm") as Keyword
    ObjectReference prev = None
    if link && StorageUtil.HasIntValue(akFollower, KeySavedLink())
        prev = StorageUtil.GetFormValue(akFollower, KeyPrevLink(), None) as ObjectReference
        WOSK_Native.SetLinkedRef(akFollower, prev, link)
    endIf
    StorageUtil.UnsetFormValue(akFollower, KeyPrevLink())
    StorageUtil.UnsetIntValue(akFollower, KeySavedLink())
    StorageUtil.UnsetIntValue(akFollower, KeyNativeHome())
    StorageUtil.UnsetFloatValue(akFollower, KeyHomeOffset())
    StorageUtil.UnsetIntValue(akFollower, KeyMark())
    akFollower.EvaluatePackage()
    Debug.Trace("WOSK_Followers: released " + akFollower + " (overrides left " + ActorUtil.CountPackageOverride(akFollower) + ", linkCustom02 back to " + prev + ")")
    ; Fase 34 etapa 7 (D310, V090): free re-hire from the moment of the release, and findable.
    ReopenRehire(akFollower)
    SendHomeIfUnseen(akFollower)
EndFunction

; Fase 34 etapa 7 (D310, V090): the vanilla re-hire window is "the player dismissed him just now":
; DialogueFollowerScript.DismissFollower ends in HirelingRehireScript.DismissHireling, which sets
; CanRehire<Name> = GameDaysPassed + 1 for the six vanilla hirelings (SetHirelingRehire.psc); the
; "team up again" line is free while that global >= GameDaysPassed (INFO 104F1F/104F23, read with
; houseCARL). The mod dismissed him at the HIRE (DismissFromFramework), so the window had closed
; by the time it released him (V090: both paid 500 again). Opened here again, the same call vanilla
; makes. A follower that is not one of the six: nothing to open, and the trace says so.
Function ReopenRehire(Actor akFollower) global
    DialogueFollowerScript d = DialogueQuest() as DialogueFollowerScript
    if !d || !d.HirelingRehireScript || !akFollower
        Debug.Trace("WOSK_Followers: re-hire window not opened for " + akFollower + " (no DialogueFollower script)")
        return
    endIf
    ActorBase base = akFollower.GetActorBase()
    d.HirelingRehireScript.DismissHireling(base)
    GlobalVariable window = PO3_SKSEFunctions.GetFormFromEditorID("CanRehire" + base.GetName()) as GlobalVariable
    if window
        Debug.Trace("WOSK_Followers: REHIRE-WINDOW " + akFollower + " " + window.GetName() + "=" + window.GetValue() + " gameDaysPassed=" + Utility.GetCurrentGameTime())
    else
        Debug.Trace("WOSK_Followers: REHIRE-WINDOW " + akFollower + " is not one of the six vanilla hirelings: no free re-hire window exists for him")
    endIf
EndFunction

; Where his own home is, in words ("" when the game gives him none).
string Function OwnHomeName(Actor akFollower) global
    Location own = akFollower.GetEditorLocation()
    if own && own.GetName() != ""
        return own.GetName()
    endIf
    return ""
EndFunction

; Fase 34 etapa 7 (D310, V090): released away from home he used to walk the road to his own
; package and the player never found him (Belrand, cell=None loaded=False). Out of the
; player's sight (not loaded, or no line of sight) he is put at his own home location; in
; sight he walks there by his own package. Trace line HOME-STATE-RELEASE.
Function SendHomeIfUnseen(Actor akFollower) global
    Location own = akFollower.GetEditorLocation()
    if !own
        Debug.Trace("WOSK_Followers: HOME-STATE-RELEASE " + akFollower + " has no editor location - left where he is")
        return
    endIf
    if akFollower.IsInLocation(own)
        Debug.Trace("WOSK_Followers: HOME-STATE-RELEASE " + akFollower + " already in " + own.GetName())
        return
    endIf
    Bool seen = akFollower.Is3DLoaded() && Game.GetPlayer().HasLOS(akFollower)
    if seen
        Debug.Trace("WOSK_Followers: HOME-STATE-RELEASE " + akFollower + " in the player's sight - walks to " + own.GetName() + " by his own package")
        return
    endIf
    akFollower.MoveToMyEditorLocation()
    akFollower.EvaluatePackage()
    Debug.Trace("WOSK_Followers: HOME-STATE-RELEASE " + akFollower + " placed at " + own.GetName() + " cell=" + akFollower.GetParentCell() + " pos=(" + (akFollower.GetPositionX() as Int) + "," + (akFollower.GetPositionY() as Int) + "," + (akFollower.GetPositionZ() as Int) + ") loaded=" + akFollower.Is3DLoaded())
EndFunction

; A follower that died keeps no mark; his body stays (P10). Nothing touches the packages.
Function ForgetFollower(Actor akFollower) global
    if akFollower
        StorageUtil.UnsetIntValue(akFollower, KeyMark())
        StorageUtil.UnsetIntValue(akFollower, KeyNativeHome())
        StorageUtil.UnsetFloatValue(akFollower, KeyHomeOffset())
    endIf
EndFunction

; P6: is his own home (editor location) inside Whiterun? WhiterunLocation 0x00018A56 is the
; city, read with houseCARL (LCTN, parent WhiterunHoldLocation); the Drunken Huntsman and the
; other houses of the city are its children.
Bool Function InWhiterun(Actor akFollower) global
    Location city = Game.GetFormFromFile(0x00018A56, "Skyrim.esm") as Location
    Location home = akFollower.GetEditorLocation()
    if !city || !home
        return false
    endIf
    ; Location.IsChild(other) is true when OTHER is a child of the caller (vanilla Location.psc),
    ; so the city is the caller. The first version had it the other way round (V078 F34E2.3).
    Bool same = home == city
    Bool inside = city.IsChild(home)
    Bool reversed = home.IsChild(city)
    Debug.Trace("WOSK_Followers: InWhiterun " + akFollower + " editorLocation=" + home + " same=" + same + " city.IsChild(home)=" + inside + " home.IsChild(city)=" + reversed)
    return same || inside
EndFunction
