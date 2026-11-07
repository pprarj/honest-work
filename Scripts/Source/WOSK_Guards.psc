; Copyright (C) 2026 Awrawra
; SPDX-License-Identifier: GPL-3.0-only
; This file is part of Honest Work - Workers of Skyrim, free software under the
; GNU General Public License, version 3. See the LICENSE file at the repository root.

ScriptName WOSK_Guards Hidden

; Fase 35 etapa 4 (D313): a follower of the player as a bodyguard. Global helpers; the
; decisions of the assignment (cap, gold, refusal) stay on WOSK_ControllerScript.AssignGuard
; and the ones of the contract (fee, table, who is attached) on WOSK_WorkerAliasScript.
; A guard is a unique NPC the mod did not create: he is NOT a worker (no alias, no
; WOSK_Followers mark), he carries the marks below, and he walks beside ONE worker for the
; length of ONE contract, then waits at his post.

string Function KeyGuard() global
    return "WOSK_Guard"
EndFunction

; On the guard: the worker he escorts now (a Form), absent while he waits.
string Function KeyEscorting() global
    return "WOSK_GuardOf"
EndFunction

; On the worker: the guard of the contract that runs (a Form), absent without one.
string Function KeyContractGuard() global
    return "WOSK_ContractGuard"
EndFunction

string Function ListKey() global
    return "WOSK_Guards"
EndFunction

; LinkCustom02 link the guard had before the escort, and whether it was read: "none" is also an
; answer. Only the travel mechanism (below) touches that link.
string Function KeyPrevLink() global
    return "WOSK_GuardPrevLink02"
EndFunction

string Function KeyPrevLinkSaved() global
    return "WOSK_GuardPrevLinkSaved02"
EndFunction

; On the guard: which way he follows now. 0 = concrete Follow package, 1 = the travel package.
string Function KeyMech() global
    return "WOSK_GuardMech"
EndFunction

string Function KeyStall() global
    return "WOSK_GuardStall"
EndFunction

string Function KeyLastDist() global
    return "WOSK_GuardLastDist"
EndFunction

; Mechanism 0 (Fase 35 etapa 5, D314). The Follow 0x00019B2C of the earlier rounds is a package
; TEMPLATE (Type=PackageTemplate); the game runs concrete packages built from it. This one is
; concrete (Type=Package, template Follow), has no condition, runs, keeps 128-256 from the
; target and accompanies; its target is the linked reference WITH keyword 0x000B2847.
Package Function FollowPackage() global
    return Game.GetFormFromFile(0x000B2848, "Skyrim.esm") as Package ; TODO-VERIFY: read in Skyrim.esm (TestPackagesFollowwLeaderChicken)
EndFunction

Keyword Function FollowKeyword() global
    return Game.GetFormFromFile(0x000B2847, "Skyrim.esm") as Keyword ; TODO-VERIFY: keyword of that package's target
EndFunction

; Mechanism 1: the package that already walks the workers (Travel to the LinkCustom02 reference),
; aimed at the worker. Taken only when mechanism 0 does not close the distance.
Package Function TravelPackage() global
    return Game.GetFormFromFile(0x000235E2, "Skyrim.esm") as Package
EndFunction

Keyword Function TravelKeyword() global
    return Game.GetFormFromFile(0x0005D5E7, "Skyrim.esm") as Keyword
EndFunction

; The template the rounds before used: only taken off a guard that still carries it.
Package Function OldTemplatePackage() global
    return Game.GetFormFromFile(0x00019B2C, "Skyrim.esm") as Package
EndFunction

Bool Function IsGuard(Actor akActor) global
    return akActor && StorageUtil.GetIntValue(akActor, KeyGuard(), 0) == 1
EndFunction

Int Function GuardCount() global
    return StorageUtil.FormListCount(None, ListKey())
EndFunction

Actor Function GuardAt(Int aiIndex) global
    return StorageUtil.FormListGet(None, ListKey(), aiIndex) as Actor
EndFunction

; The numbers are data (contract_types/00_collection.json, type "bodyguard", row 0).
Float Function Param(string asField, Float afDefault) global
    return WOSK_Registry.GetOutcomeRowFloat("bodyguard", 0, asField, afDefault)
EndFunction

; Paid once, to assign a follower (B2). The gold leaves the player and is gone.
Int Function AssignFee() global
    return Param("assignFee", 600.0) as Int
EndFunction

; Paid at every contract he escorts (B2, B5): a share of the contract's price, never
; less than the floor. Whole gold, rounded up (D295). Mirrored by an offline model of the same formula.
Int Function ContractFee(Int aiContractCost) global
    Float rate = Param("contractFeeRate", 0.25)
    Int fee = Math.Ceiling(aiContractCost * rate)
    Int floorFee = Param("contractFeeMin", 40.0) as Int
    if fee < floorFee
        fee = floorFee
    endIf
    return fee
EndFunction

; Fase 35 etapa 10 (D319): a contract that is never escorted, by its task (not by the profession of
; the worker): the firewood cut in town at the chopping block. Mirrored in the panel (model.ts
; NO_ESCORT_TASKS). Papyrus compares strings without case.
Bool Function TaskHasNoEscort(string asTaskId) global
    return asTaskId == "labor_firewood"
EndFunction

; The outcome table of a contract: with a guard the death slice is a fifth (B4, Q1), data.
string Function OutcomeTableFor(string asContractType, Bool abGuarded) global
    if abGuarded
        return asContractType + "_guarded"
    endIf
    return asContractType
EndFunction

; The guard of the contract that runs, None without one.
Actor Function GuardOf(Actor akWorker) global
    if !akWorker
        return None
    endIf
    return StorageUtil.GetFormValue(akWorker, KeyContractGuard(), None) as Actor
EndFunction

; The first assigned guard that is alive and not escorting anyone (B1: one per worker).
Actor Function FreeGuard() global
    Int n = GuardCount()
    Int i = 0
    while i < n
        Actor g = GuardAt(i)
        if g && !g.IsDead() && !StorageUtil.GetFormValue(g, KeyEscorting(), None)
            return g
        endIf
        i += 1
    endWhile
    return None
EndFunction

; Seen = loaded AND (in the line of sight of the player OR near him). The distance leg is the
; V094 fix: a loaded guard a few steps from the player is on his screen even when the line test
; says no. What the player sees is never moved; what he does not see may be.
Bool Function Seen(Actor akActor) global
    if !akActor || !akActor.Is3DLoaded()
        return false
    endIf
    Actor pl = Game.GetPlayer()
    if pl.HasLOS(akActor)
        return true
    endIf
    Float dp = pl.GetDistance(akActor)
    return dp >= 0.0 && dp < 2500.0
EndFunction

; The legs of the sight test apart, for the log lines: never only the sum.
string Function SeenText(Actor akActor) global
    Bool l3 = akActor.Is3DLoaded()
    Bool los = l3 && Game.GetPlayer().HasLOS(akActor)
    return "3d=" + l3 as Int + " los=" + los as Int + " distPlayer=" + (Game.GetPlayer().GetDistance(akActor) as Int)
EndFunction

; Binds the guard to the worker by the mechanism he is on: the link (with the keyword that
; mechanism reads) and the package at the priority of the travel package.
Function BindFollow(Actor akGuard, Actor akWorker) global
    if StorageUtil.GetIntValue(akGuard, KeyMech(), 0) == 0
        WOSK_Native.SetLinkedRef(akGuard, akWorker, FollowKeyword())
        ActorUtil.AddPackageOverride(akGuard, FollowPackage(), 30, 0)
    else
        WOSK_Native.SetLinkedRef(akGuard, akWorker, TravelKeyword())
        ActorUtil.AddPackageOverride(akGuard, TravelPackage(), 30, 0)
    endIf
EndFunction

; Puts the guard beside the worker for the contract.
Function Attach(Actor akWorker, Actor akGuard) global
    if !akWorker || !akGuard
        return
    endIf
    if !StorageUtil.HasIntValue(akGuard, KeyPrevLinkSaved())
        StorageUtil.SetFormValue(akGuard, KeyPrevLink(), akGuard.GetLinkedRef(TravelKeyword()))
        StorageUtil.SetIntValue(akGuard, KeyPrevLinkSaved(), 1)
    endIf
    StorageUtil.SetFormValue(akWorker, KeyContractGuard(), akGuard)
    StorageUtil.SetFormValue(akGuard, KeyEscorting(), akWorker)
    StorageUtil.SetIntValue(akGuard, KeyMech(), 0)
    StorageUtil.SetIntValue(akGuard, KeyStall(), 0)
    StorageUtil.UnsetFloatValue(akGuard, KeyLastDist())
    ; Off the post sandbox and off the old template, so only the escort package decides.
    ActorUtil.RemovePackageOverride(akGuard, WOSK_PlayerHouse.HomeSandbox())
    ActorUtil.RemovePackageOverride(akGuard, OldTemplatePackage())
    ; Fase 35 etapa 7 (V098): a guard whose cell is unloaded gets NO package yet. With the Follow
    ; package on, the engine carried him to the player's cell by itself and he arrived without an
    ; animation graph (T-pose). He is held pending; Tick puts him beside the worker, by the mod,
    ; once the player sees neither of them, and only then binds the escort.
    if !akGuard.Is3DLoaded()
        StorageUtil.SetIntValue(akGuard, KeyPending(), 1)
        Debug.Trace("WOSK_Guards: GUARDA-ANEXADO-PENDENTE guard=" + akGuard + " worker=" + akWorker + " " + ProbeText(akGuard) + " dist=" + (akGuard.GetDistance(akWorker) as Int) + " - not loaded, no package until he is moved")
        WOSK_PanelBridgeScript.PushGuardState()
        return
    endIf
    StorageUtil.UnsetIntValue(akGuard, KeyPending())
    BindFollow(akGuard, akWorker)
    akGuard.EvaluatePackage()
    Debug.Trace("WOSK_Guards: GUARDA-ANEXADO guard=" + akGuard + " worker=" + akWorker + " mech=0 pkg=" + FollowPackage() + " kw=" + FollowKeyword() + " " + ProbeText(akGuard) + " dist=" + (akGuard.GetDistance(akWorker) as Int) + " prevLink02=" + StorageUtil.GetFormValue(akGuard, KeyPrevLink(), None))
    ; V100: the page learns he is escorting now, not at the next refresh.
    WOSK_PanelBridgeScript.PushGuardState()
EndFunction

; On the guard: 1 while he is attached but not yet carried to the worker (his cell was unloaded).
string Function KeyPending() global
    return "WOSK_GuardPending"
EndFunction

; The legs of the probe (V098): where he is, whether he has a 3D, what he runs. Never only one.
string Function ProbeText(Actor akGuard) global
    return "cell=" + akGuard.GetParentCell() + " 3d=" + akGuard.Is3DLoaded() as Int + " curPkg=" + akGuard.GetCurrentPackage() + " disabled=" + akGuard.IsDisabled() as Int
EndFunction

; Mechanism 0 did not close the distance in three ticks with both loaded: the travel package
; takes over, once. Both mechanisms are measured in the same contract this way.
Function SwitchToTravel(Actor akGuard, Actor akWorker, Float afDist) global
    ActorUtil.RemovePackageOverride(akGuard, FollowPackage())
    WOSK_Native.SetLinkedRef(akGuard, None, FollowKeyword())
    StorageUtil.SetIntValue(akGuard, KeyMech(), 1)
    StorageUtil.SetIntValue(akGuard, KeyStall(), 0)
    BindFollow(akGuard, akWorker)
    akGuard.EvaluatePackage()
    Debug.Trace("WOSK_Guards: GUARDA-MECANISMO guard=" + akGuard + " worker=" + akWorker + " de=Follow para=Travel dist=" + (afDist as Int) + " pkgAgora=" + akGuard.GetCurrentPackage())
EndFunction

; Every ~6 s while the contract runs (WOSK_WorkerAliasScript.OnUpdate). The guard walks by the
; package when both are loaded. When he is far or in another cell he is joined to the worker by
; MoveTo ONLY when neither of them is seen by the player (V090). One line per tick (GUARDA-PASSO)
; with the package he runs and each leg of the sight test; a line for each re-join.
Function Tick(Actor akWorker) global
    Actor g = GuardOf(akWorker)
    if !g
        return
    endIf
    if g.IsDead()
        Debug.Trace("WOSK_Guards: GUARDA-MORTO guard=" + g + " worker=" + akWorker + " - the contract goes on without him")
        Detach(akWorker, "guard dead")
        return
    endIf
    if StorageUtil.GetIntValue(g, KeyPending(), 0) == 1
        ; V098: held until he can be carried out of the player's sight (or loads by himself).
        Bool loadedNow = g.Is3DLoaded()
        Bool workerSeen = Seen(akWorker)
        Debug.Trace("WOSK_Guards: GUARDA-PENDENTE guard=" + g + " " + ProbeText(g) + " dist=" + (g.GetDistance(akWorker) as Int) + " trabalhadorVisto[" + SeenText(akWorker) + "]")
        if !loadedNow && workerSeen
            return
        endIf
        if !StillHis(akWorker, g)
            return
        endIf
        if !loadedNow
            g.MoveTo(akWorker, 100.0, 0.0, 0.0)
        endIf
        StorageUtil.UnsetIntValue(g, KeyPending())
        BindFollow(g, akWorker)
        g.EvaluatePackage()
        Debug.Trace("WOSK_Guards: GUARDA-CHEGOU guard=" + g + " worker=" + akWorker + " moved=" + (!loadedNow) as Int + " " + ProbeText(g) + " dist=" + (g.GetDistance(akWorker) as Int))
        return
    endIf
    Int mech = StorageUtil.GetIntValue(g, KeyMech(), 0)
    Keyword kw = FollowKeyword()
    if mech == 1
        kw = TravelKeyword()
    endIf
    ; The link is lost on a load (V024); the override stays in the cosave. Put back what is missing.
    if !StillHis(akWorker, g)
        return
    endIf
    if g.GetLinkedRef(kw) != akWorker as ObjectReference
        WOSK_Native.SetLinkedRef(g, akWorker, kw)
    endIf
    if ActorUtil.CountPackageOverride(g) < 1
        BindFollow(g, akWorker)
        g.EvaluatePackage()
    endIf
    Float d = g.GetDistance(akWorker)
    Bool otherCell = g.GetParentCell() != akWorker.GetParentCell()
    Debug.Trace("WOSK_Guards: GUARDA-PASSO guard=" + g + " mech=" + mech + " " + ProbeText(g) + " dist=" + (d as Int) + " otherCell=" + otherCell as Int + " guardaVisto[" + SeenText(g) + "] trabalhadorVisto[" + SeenText(akWorker) + "]")
    if !otherCell && d >= 0.0 && d < 500.0
        StorageUtil.SetIntValue(g, KeyStall(), 0)
        StorageUtil.UnsetFloatValue(g, KeyLastDist())
        return
    endIf
    ; Stalled = both loaded, far, and not closing in since the last tick.
    Float lastD = StorageUtil.GetFloatValue(g, KeyLastDist(), -1.0)
    Int stall = StorageUtil.GetIntValue(g, KeyStall(), 0)
    if !otherCell && g.Is3DLoaded() && akWorker.Is3DLoaded() && d > 900.0 && lastD >= 0.0 && d >= lastD - 100.0
        stall += 1
    else
        stall = 0
    endIf
    StorageUtil.SetIntValue(g, KeyStall(), stall)
    StorageUtil.SetFloatValue(g, KeyLastDist(), d)
    if stall >= 3 && mech == 0
        SwitchToTravel(g, akWorker, d)
        return
    endIf
    ; Fase 35 etapa 9 (V102): the worker is already out of the scene (no 3D). The guard's follow
    ; package does not walk toward an unloaded actor, so waiting near the player for the distance leg
    ; left him standing ~66 s. Here only the line of sight keeps him from being moved: what the player
    ; does not look at may be carried to the worker.
    Bool workerGone = !akWorker.Is3DLoaded()
    Bool seenG = false
    Bool seenW = false
    if workerGone
        seenG = g.Is3DLoaded() && Game.GetPlayer().HasLOS(g)
    else
        seenG = Seen(g)
        seenW = Seen(akWorker)
    endIf
    if seenG || seenW
        ; Nothing is moved. He walks; a log line only when this starts, not at every tick.
        if StorageUtil.GetIntValue(g, "WOSK_GuardSeenLogged", 0) == 0
            StorageUtil.SetIntValue(g, "WOSK_GuardSeenLogged", 1)
            Debug.Trace("WOSK_Guards: GUARDA-ANDA guard=" + g + " worker=" + akWorker + " dist=" + (d as Int) + " otherCell=" + otherCell as Int + " seenGuard=" + seenG as Int + " seenWorker=" + seenW as Int + " workerGone=" + workerGone as Int + " - in sight, no MoveTo")
        endIf
        return
    endIf
    StorageUtil.UnsetIntValue(g, "WOSK_GuardSeenLogged")
    ; V100: the sight tests above are slow; the escort may have ended on another stack meanwhile.
    if !StillHis(akWorker, g)
        Debug.Trace("WOSK_Guards: GUARDA-TICK-TARDIO guard=" + g + " worker=" + akWorker + " - the escort ended before the re-join; nothing moved")
        return
    endIf
    Debug.Trace("WOSK_Guards: GUARDA-REENCONTRO-VISTA guard=" + g + " workerGone=" + workerGone as Int + " guardaVisto[" + SeenText(g) + "] trabalhadorVisto[" + SeenText(akWorker) + "]")
    g.MoveTo(akWorker, 100.0, 0.0, 0.0)
    if !StillHis(akWorker, g)
        UndoLateTick(g, akWorker)
        return
    endIf
    WOSK_Native.SetLinkedRef(g, akWorker, kw)
    if !StillHis(akWorker, g)
        UndoLateTick(g, akWorker)
        return
    endIf
    StorageUtil.SetIntValue(g, KeyStall(), 0)
    StorageUtil.UnsetFloatValue(g, KeyLastDist())
    g.EvaluatePackage()
    Debug.Trace("WOSK_Guards: GUARDA-REENCONTROguard=" + g + " worker=" + akWorker + " mech=" + mech + " antes dist=" + (d as Int) + " otherCell=" + otherCell as Int + " depois dist=" + (g.GetDistance(akWorker) as Int))
EndFunction

; The end of the escort: the contract resolved, the worker died, or the guard did. The
; packages and the links go back as they were; the guard goes to his post (P6). Never Disable.
Function Detach(Actor akWorker, string asWhy) global
    Actor g = GuardOf(akWorker)
    if !g
        return
    endIf
    Int mech = StorageUtil.GetIntValue(g, KeyMech(), 0)
    StorageUtil.UnsetFormValue(akWorker, KeyContractGuard())
    StorageUtil.UnsetFormValue(g, KeyEscorting())
    StorageUtil.UnsetIntValue(g, "WOSK_GuardSeenLogged")
    StorageUtil.UnsetIntValue(g, KeyPending())
    StorageUtil.UnsetIntValue(g, KeyStall())
    StorageUtil.UnsetFloatValue(g, KeyLastDist())
    Bool removed = ActorUtil.RemovePackageOverride(g, FollowPackage())
    Bool removedTravel = ActorUtil.RemovePackageOverride(g, TravelPackage())
    ActorUtil.RemovePackageOverride(g, OldTemplatePackage())
    WOSK_Native.SetLinkedRef(g, None, FollowKeyword())
    if StorageUtil.HasIntValue(g, KeyPrevLinkSaved())
        WOSK_Native.SetLinkedRef(g, StorageUtil.GetFormValue(g, KeyPrevLink(), None) as ObjectReference, TravelKeyword())
    endIf
    StorageUtil.UnsetFormValue(g, KeyPrevLink())
    StorageUtil.UnsetIntValue(g, KeyPrevLinkSaved())
    StorageUtil.UnsetIntValue(g, KeyMech())
    g.EvaluatePackage()
    Debug.Trace("WOSK_Guards: GUARDA-LIBERADO guard=" + g + " worker=" + akWorker + " why=" + asWhy + " mech=" + mech + " removed=" + removed as Int + " removedTravel=" + removedTravel as Int + " overrides=" + ActorUtil.CountPackageOverride(g) + " dist=" + (g.GetDistance(akWorker) as Int))
    if !g.IsDead()
        SendToPost(g)
    endIf
    ; V100: he is free again; the page turns "With bodyguard" back on.
    WOSK_PanelBridgeScript.PushGuardState()
EndFunction

; V100: still the escort of this worker. A Tick in flight read the guard before a Detach on
; another stack ended the contract; it must not move or bind him after the post was given.
Bool Function StillHis(Actor akWorker, Actor akGuard) global
    return GuardOf(akWorker) == akGuard
EndFunction

; V100: a Tick that moved him after the Detach: the link and the packages the Tick put back
; come off and he goes to his post again.
Function UndoLateTick(Actor akGuard, Actor akWorker) global
    ActorUtil.RemovePackageOverride(akGuard, FollowPackage())
    ActorUtil.RemovePackageOverride(akGuard, TravelPackage())
    ; Only the Follow link is cleared: the Travel link is the one he had of his own, which the
    ; Detach gave back (a late Tick on the travel mechanism is rare and is measured by this line).
    WOSK_Native.SetLinkedRef(akGuard, None, FollowKeyword())
    Debug.Trace("WOSK_Guards: GUARDA-TICK-TARDIO guard=" + akGuard + " worker=" + akWorker + " - the escort ended while a tick ran; post given again")
    SendToPost(akGuard)
EndFunction

; P6: where a guard waits between contracts. Whiterun's own: his editor location (moved
; there only out of sight, else he walks by his own package). Anyone else: the player's house
; marker, else the Bannered Mare marker, one step apart per guard (offset kept on him), and
; HOLDS there by the home sandbox (Fase 35 etapa 5): without a package of his own he went back
; to his native home (V094). The sandbox is taken off again at the next Attach.
; Fase 35 etapa 10 (V104, D319): abOnAssign is true only for the assignment from the panel. With a
; house of the player the guard goes to its marker even in sight, as a hired worker does; every other
; call (the end of a contract) keeps the rule of never moving what the player sees.
Function SendToPost(Actor akGuard, Bool abOnAssign = false) global
    string ownedHouse = WOSK_PlayerHouse.OwnedHouse()
    if ownedHouse == "" && StorageUtil.GetIntValue(akGuard, WOSK_Followers.KeyNativeHome(), 0) == 1
        WOSK_Followers.SendHomeIfUnseen(akGuard)
        return
    endIf
    ; He waits where he is at least, on the sandbox of his current location.
    ActorUtil.AddPackageOverride(akGuard, WOSK_PlayerHouse.HomeSandbox(), 30, 0)
    ; Fase 35 etapa 7 (V098, author): with a house of his own the player's guard waits there, the
    ; same marker the workers use (WOSK_PlayerHouse); without one, the post of the inn as before.
    ObjectReference post = None
    if ownedHouse != ""
        post = WOSK_PlayerHouse.HomeMarker(ownedHouse)
    endIf
    if !post
        post = StorageUtil.GetFormValue(Game.GetPlayer(), "WOSK_HoldHome_0", None) as ObjectReference
    endIf
    if !post
        post = Game.GetFormFromFile(0x00000810, "HonestWork.esp") as ObjectReference
    endIf
    if !post
        akGuard.EvaluatePackage()
        Debug.Trace("WOSK_Guards: GUARDA-POSTO guard=" + akGuard + " has no post marker - holds where he is")
        return
    endIf
    Bool moveSeen = abOnAssign && ownedHouse != ""
    if Seen(akGuard)
        if !moveSeen
            akGuard.EvaluatePackage()
            Debug.Trace("WOSK_Guards: GUARDA-POSTO guard=" + akGuard + " in the player's sight - not moved, holds where he is " + SeenText(akGuard))
            return
        endIf
        Debug.Trace("WOSK_Guards: GUARDA-POSTO-ATRIBUICAO guard=" + akGuard + " is in sight and goes to the house of the player on the assignment " + SeenText(akGuard))
    endIf
    Float zBefore = akGuard.GetPositionZ()
    akGuard.MoveTo(post, StorageUtil.GetFloatValue(akGuard, WOSK_Followers.KeyHomeOffset(), 0.0), 0.0, 0.0)
    akGuard.EvaluatePackage()
    Debug.Trace("WOSK_Guards: GUARDA-POSTO guard=" + akGuard + " placed at " + post + " cell=" + akGuard.GetParentCell() + " zAntes=" + (zBefore as Int) + " zDepois=" + (akGuard.GetPositionZ() as Int) + " distPosto=" + (akGuard.GetDistance(post) as Int) + " pkg=" + akGuard.GetCurrentPackage())
EndFunction

; Takes the guard back to a plain follower of the player (the gold is not returned, Q5):
; used by the release (etapa 5) and by the probe that gives him back.
Function Forget(Actor akGuard) global
    if !akGuard
        return
    endIf
    StorageUtil.FormListRemove(None, ListKey(), akGuard, true)
    ActorUtil.RemovePackageOverride(akGuard, WOSK_PlayerHouse.HomeSandbox())
    StorageUtil.UnsetIntValue(akGuard, KeyGuard())
    StorageUtil.UnsetFormValue(akGuard, KeyEscorting())
    StorageUtil.UnsetIntValue(akGuard, WOSK_Followers.KeyNativeHome())
    StorageUtil.UnsetFloatValue(akGuard, WOSK_Followers.KeyHomeOffset())
EndFunction
