; Copyright (C) 2026 Awrawra
; SPDX-License-Identifier: GPL-3.0-only
; This file is part of Honest Work - Workers of Skyrim, free software under the
; GNU General Public License, version 3. See the LICENSE file at the repository root.

ScriptName WOSK_ControllerScript extends Quest

; Attached to WOSK_Controller (0x01000800). Central state/logic holder for
; the mod - a Quest script cannot receive OnCellLoad/OnLocationChange/
; OnPlayerLoadGame directly (confirmed against the real vanilla
; ReferenceAlias.psc/ObjectReference.psc/Actor.psc source - those events are
; declared there, not on Quest.psc), so a thin forwarder
; (WOSK_PlayerAliasScript, on a Force-Ref-to-PlayerRef alias also on this
; quest) receives them and calls the *Handler functions below. This alias
; exists purely as plumbing to reach those events, not as a gameplay slot.

Quest Property WorkerPool Auto
; WOSK_WorkerPool (0x01000801) - wired via VMAD Object property at plugin
; generation time, not CK.

Book Property LedgerBook Auto
; Wired via VMAD Object property at plugin generation time - target is
; WOSK_LedgerBook (0x01000812). RefreshLedger() below still no-ops safely
; if this is ever None.

Int Property WorkerPoolSize = 4 Auto Hidden
; MVP pool size. Aliases are indexed 0..WorkerPoolSize-1.

Quest Property CandidatePool Auto
; D104 etapa 2: WOSK_CandidatePool (0x01000813) - 5 aliases holding the
; candidates standing in the tavern. Wired via VMAD.

Int Property CandidatePoolSize = 5 Auto Hidden
; Obsolete since Fase 16 (D161): an Auto property keeps the value the save
; stored, so the pool size is read from the quest - CandidatePoolCount().

; Queue of run-time-created actors waiting to be deleted, kept by StorageUtil
; on this quest so it survives a save. See SweepPendingDeletes.
String Property PENDING_DELETE_KEY = "WOSK_PendingDelete" Auto Hidden

; ---------------------------------------------------------------------------
; Forwarded events (called by WOSK_PlayerAliasScript)
; ---------------------------------------------------------------------------

Function OnPlayerLoadGameHandler()
    Debug.Trace("WOSK_Controller: OnPlayerLoadGame -> RefreshLedger")
    SweepPendingDeletes()
    WOSK_Backpack.OnGameLoaded()
    RestoreTravelTargets()
    WOSK_DepletionScript.ClearLegacyPending()
    UpdateSources()
    KeepHiringAgentName()
    RefillCandidatePool()
    ArmPoolClock()
    RefreshLedger()
EndFunction

; Fase 33 etapa 2 (D263, V065): a hired worker without a running contract is in his home
; cell. Asks every worker; each one moves only if he is not.
Function EnsureWorkersHome(string asWhy)
    if !WorkerPool
        return
    endIf
    Int i = 0
    while i < WorkerPoolSize
        WOSK_WorkerAliasScript w = WorkerPool.GetAlias(i) as WOSK_WorkerAliasScript
        if w
            w.EnsureAtHome(asWhy)
        endIf
        i += 1
    endwhile
EndFunction

; Fase 34 etapa 5 (D308, V086): the player entered a cell - every follower worker who is in it
; (his home cell, usually) writes where he stands.
Function LogFollowersInPlayerCell()
    if !WorkerPool
        return
    endIf
    Cell here = Game.GetPlayer().GetParentCell()
    Int i = 0
    while i < WorkerPoolSize
        WOSK_WorkerAliasScript w = WorkerPool.GetAlias(i) as WOSK_WorkerAliasScript
        if w
            Actor a = w.GetActorRef()
            if a && WOSK_Followers.IsFollower(a) && a.GetParentCell() == here
                w.LogHomeState("player entered his cell")
            endIf
        endIf
        i += 1
    endwhile
EndFunction

; Fase 33 etapa 2 (D266, V065): the pool renews with TIME. Until now it was looked at only on
; a cell load and a game load, so a player who waited in the inn (Wait, sleep) never saw the
; rotation (days 17 to 26 without a change, round 9). One game-time update every few hours
; of game time: it fires once when a Wait ends, not once per hour waited. Re-armed on every
; load and from itself.
Function ArmPoolClock()
    RegisterForSingleUpdateGameTime(3.0)
EndFunction

Event OnUpdateGameTime()
    RefillCandidatePool()
    ArmPoolClock()
EndEvent

; V024: the workers' travel targets (PO3 SetLinkedRef) do not seem to survive a
; save; each worker alias puts its own back (WOSK_WorkerAliasScript).
Function RestoreTravelTargets()
    Int i = 0
    while i < WorkerPoolSize
        WOSK_WorkerAliasScript w = WorkerPool.GetAlias(i) as WOSK_WorkerAliasScript
        if w
            w.RestoreTravelTarget()
        endIf
        i += 1
    endwhile
EndFunction

Function OnCellLoadHandler()
    SweepPendingDeletes()
    UpdateSources()
    CheckAllEncounters()
    KeepHiringAgentName()
    RefillCandidatePool()
    EnsureWorkersHome("cell load")
    LogFollowersInPlayerCell()
EndFunction

; D104 etapa 2: the candidate pool fills itself shortly after the quest
; starts - not inside OnInit, where WOSK_CandidatePool's aliases may not be
; filled yet.
Event OnInit()
    RegisterForSingleUpdate(10.0)
    ArmPoolClock()
EndEvent

Event OnUpdate()
    KeepHiringAgentName()
    RefillCandidatePool()
EndEvent

Function OnLocationChangeHandler(Location akOldLoc, Location akNewLoc)
    WOSK_DepletionScript.RecordPlayerVisit(MvpHold())
    CheckAllEncounters()
EndFunction

; D105 etapa 3: the player inside a dungeon mine confirms it, and the veins the
; mod remembers as used are depleted where they now resolve. Replaces the lazy
; depletion (RunDepletionForLoadedCell) that thinned the veins of any cell.
Function UpdateSources()
    string hold = MvpHold()
    WOSK_DepletionScript.RecordPlayerVisit(hold)
    WOSK_DepletionScript.SyncHold(hold)
EndFunction

; The MVP's only hold, as the worker aliases name it (WOSK_WorkerAliasScript.MVP_HOLD).
string Function MvpHold()
    WOSK_WorkerAliasScript w = WorkerPool.GetAlias(0) as WOSK_WorkerAliasScript
    if w
        return w.MVP_HOLD
    endIf
    return "Whiterun"
EndFunction

; ---------------------------------------------------------------------------
; Ledger - "re-render do ledger", wires Lodestone.SetBookText for real once
; LedgerBook exists
; ---------------------------------------------------------------------------

Function RefreshLedger()
    string text = WOSK_LedgerScript.BuildLedgerText(WorkerPool, WorkerPoolSize)
    if LedgerBook
        Lodestone.SetBookText(LedgerBook, text)
    endIf
EndFunction

; ---------------------------------------------------------------------------
; Workers tab (queue item 11) - every hired worker, with the situation he is in
; right now and a button to put him to work when he is standing idle.
; ---------------------------------------------------------------------------

; Sends the hired workers to the panel. Returns how many were sent.
;
; This is the LIVE channel, and that is the whole point of the tab: it is called
; from WOSK_PanelBridgeScript.PushPanelState(), which every contract state change
; goes through, so the situation on screen changes while the panel stays open.
; RefreshLedger() above is the opposite - it only runs on load - and the tab
; would have been a snapshot if it had been wired the same way.
Int Function RefreshWorkerList()
    ; Fase 31 conserto 1 (D258): how many times the list went to the panel, for the harness
    ; (PSH01-PSH04): "pushed after every change" is read off this number, not assumed.
    StorageUtil.AdjustIntValue(None, "WOSK_PanelPushes", 1)
    ; 4 mirrors the WorkerPoolSize property default, same compile-time-constant
    ; limitation as GetWorkers() below: change one and this needs changing too.
    string[] names = new string[4]
    string[] professions = new string[4]
    string[] tiers = new string[4]
    string[] holds = new string[4]
    string[] states = new string[4]
    Float[] hoursLeft = new Float[4]
    Int[] slots = new Int[4]
    Int[] canIssue = new Int[4]
    string hold = MvpHold()
    Int count = 0
    Int i = 0
    while i < WorkerPoolSize && i < 4
        WOSK_WorkerAliasScript a = WorkerPool.GetAlias(i) as WOSK_WorkerAliasScript
        Actor worker = None
        if a
            worker = a.GetActorRef()
        endIf
        if worker
            string lifecycle = StorageUtil.GetStringValue(worker, "WOSK_Lifecycle", "AVAILABLE")
            string contract = StorageUtil.GetStringValue(worker, "WOSK_Contract", "IDLE")
            names[count] = worker.GetDisplayName()
            professions[count] = StorageUtil.GetStringValue(worker, "WOSK_Profession", "miner")
            tiers[count] = WOSK_Names.TierLabel(StorageUtil.GetStringValue(worker, "WOSK_Tier", "apprentice"))
            ; The MVP has one hold, so the grouping the maintainer asked for is one
            ; group today. The field is sent anyway: the page groups by it, and
            ; the day a second hold exists nothing on the page has to change.
            holds[count] = hold
            states[count] = WOSK_Names.StateLabelDeparted(lifecycle, contract, professions[count], StorageUtil.GetStringValue(worker, "WOSK_House", ""), StorageUtil.GetIntValue(worker, "WOSK_Departed", 1))
            ; Fase 28 conserto 1 (D238): AWAITING_PICKUP rows carry -2/-3/-4 here.
            ; Fase 34 etapa 6 (D309): a worker waiting for pickup is named with the place he is at
            ; ("Awaiting pickup at The Drunken Huntsman"); the page words the line from it.
            if contract == "AWAITING_PICKUP"
                states[count] = states[count] + " at " + a.HomePlaceName(worker)
            endIf
            hoursLeft[count] = a.PanelHoursLeft()
            slots[count] = i
            ; The same two conditions IssueContract itself refuses on first
            ; (WOSK_WorkerAliasScript:74). Offering the button where the call
            ; would be refused is worse than not offering it.
            if lifecycle == "AVAILABLE" && contract == "IDLE"
                canIssue[count] = 1
            else
                canIssue[count] = 0
            endIf
            count += 1
        endIf
        i += 1
    endwhile
    ; Fase 33 etapa 10 (F4): the hold the page is told, once per push; before, no log said it.
    Debug.Trace("WOSK_Controller: worker list sent, " + count + " worker(s), hold '" + hold + "'")
    WOSK_Panel.SetWorkerList(names, professions, tiers, holds, states, hoursLeft, slots, canIssue, count)
    ; Fase 30 (D244): what each hunter carries rides on its own channel, after the list.
    Int g = 0
    while g < count
        WOSK_WorkerAliasScript ga = WorkerPool.GetAlias(slots[g]) as WOSK_WorkerAliasScript
        if ga && ga.GetActorRef()
            if professions[g] == "hunter"
                WOSK_Gear.PushGear(ga.GetActorRef(), slots[g])
            endIf
            ; Fase 31 (D248): the dismissal fee, shown before the Dismiss button. Same
            ; pseudo-outcome channel as the gear; the amount rides in the number.
            WOSK_Panel.SetOutcome("fee", slots[g], "", "", ga.DismissalFee())
            ; Fase 33 etapa 2 (D267): the cook's house and the houses to choose from; the
            ; number says whether the change is open now (no contract running).
            if professions[g] == "cook"
                PushHouse(ga.GetActorRef(), slots[g])
            endIf
        endIf
        g += 1
    endWhile
    return count
EndFunction

; Fase 33 etapa 2 (D267): the "house" word to the page, same channel as "fee" and "gear".
; slot >= 0: that cook - code = his house id, arg = the owned house ids ("a|b"), number 1
; when no contract runs; slot -1: the house a new cook moves into (code), same arg.
Function PushHouse(Actor akCook, Int aiSlot)
    Int open = 0
    string current = WOSK_PlayerHouse.ChosenHouse()
    if akCook
        current = StorageUtil.GetStringValue(akCook, "WOSK_House", "")
        if StorageUtil.GetStringValue(akCook, "WOSK_Contract", "IDLE") == "IDLE"
            open = 1
        endIf
    endIf
    WOSK_Panel.SetOutcome("house", aiSlot, current, WOSK_PlayerHouse.OwnedHouses(), open)
EndFunction

; The panel's house order, riding the contract order's channel (the DLL passes the task id
; string through and a new listener is a DLL build, out of this stage): task id
; "house:<id>". Slot >= 0 changes that cook's house; slot -1 sets the house the next cook
; moves into. The answer is the "home" outcome, worded by the page.
Bool Function _HouseOrder(Int aiSlot, string asHouse)
    if aiSlot < 0
        if asHouse != "" && !WOSK_PlayerHouse.OwnsHouse(asHouse)
            WOSK_PanelBridgeScript.ReportOutcome("home", aiSlot, "NOT_OWNED", asHouse, 0)
            return false
        endIf
        StorageUtil.SetStringValue(None, "WOSK_PreferredHouse", asHouse)
        Debug.Trace("WOSK_Controller: the next cook moves into '" + asHouse + "' (panel)")
        PushHouse(None, -1)
        return true
    endIf
    WOSK_WorkerAliasScript w = WorkerPool.GetAlias(aiSlot) as WOSK_WorkerAliasScript
    Actor cook = None
    if w
        cook = w.GetActorRef()
    endIf
    string code = WOSK_PlayerHouse.ChangeHouse(cook, asHouse)
    WOSK_PanelBridgeScript.ReportOutcome("home", aiSlot, code, asHouse, 0)
    if code == "OK"
        RefreshWorkerList()
    else
        PushHouse(cook, aiSlot)
    endIf
    return code == "OK"
EndFunction

; Fase 17 (D168): the totals, the statement and each worker's counters, for the
; Overview and Worker tabs. Same beats as RefreshWorkerList. Returns the number
; of statement lines sent.
Int Function RefreshHistory()
    ; 30 mirrors WOSK_LedgerScript.JournalMax(), 4 the worker pool (array sizes
    ; must be compile-time constants).
    string[] journal = new string[30]
    string journalKey = WOSK_LedgerScript.JournalKey()
    Int total = StorageUtil.StringListCount(None, journalKey)
    Int first = 0
    if total > 30
        first = total - 30
    endIf
    Int jc = 0
    Int j = first
    while j < total
        journal[jc] = StorageUtil.StringListGet(None, journalKey, j)
        jc += 1
        j += 1
    endwhile

    Int[] slots = new Int[4]
    Int[] completed = new Int[4]
    Int[] goldSpent = new Int[4]
    Int[] value = new Int[4]
    string[] histories = new string[4]
    Int count = 0
    Int active = 0
    Int i = 0
    while i < WorkerPoolSize && i < 4
        WOSK_WorkerAliasScript a = WorkerPool.GetAlias(i) as WOSK_WorkerAliasScript
        Actor worker = None
        if a
            worker = a.GetActorRef()
        endIf
        if worker
            slots[count] = i
            completed[count] = StorageUtil.GetIntValue(worker, "WOSK_ContractsCompleted", 0)
            goldSpent[count] = StorageUtil.GetIntValue(worker, "WOSK_GoldSpent", 0)
            value[count] = StorageUtil.GetIntValue(worker, "WOSK_ValueDelivered", 0)
            histories[count] = WOSK_LedgerScript.WorkerHistoryText(worker)
            string contract = StorageUtil.GetStringValue(worker, "WOSK_Contract", "IDLE")
            if contract != "IDLE" && contract != "AWAITING_PICKUP"
                active += 1
            endIf
            count += 1
        endIf
        i += 1
    endwhile
    WOSK_Panel.SetHistory(journal, jc, slots, completed, goldSpent, value, histories, count, \
                          StorageUtil.GetIntValue(None, "WOSK_StatGoldSpent", 0), \
                          StorageUtil.GetIntValue(None, "WOSK_StatValueDelivered", 0), \
                          StorageUtil.GetIntValue(None, "WOSK_StatContractsDone", 0), active, \
                          Utility.GetCurrentGameTime())
    return jc
EndFunction

; ---------------------------------------------------------------------------
; What the hold still has (queue item 13) - in front of each contract, so the
; player picks an ore knowing whether anyone can still dig it.
; ---------------------------------------------------------------------------

; Sends one row per task to the panel. Returns how many rows went.
;
; The numbers are the ones a contract issued right now would meet, not the
; hold's theoretical total: AvailableVeins counts only the sources PickSource
; would draw from, and the units are the task's own unitsPerVein - what the
; WORKER brings back, which is what the player is buying. The vanilla vein
; holds 3 and that is a different quantity; the comparison is traced below and
; is an open question for the maintainer, V043.
;
; Every profession is walked, not the one the panel happens to show: the page
; matches rows to tasks by id, so a second profession needs nothing here.
Int Function RefreshSourceList()
    ; Fase 15: 64 rows - six professions do not fit in the miner's 16.
    string[] taskIds = new string[64]
    Int[] veins = new Int[64]
    Int[] units = new Int[64]
    string[] reasons = new string[64]
    ; Fase 33 etapa 8 (D1): the house whose kitchen a row speaks of ("" for the others)
    ; and the hours until a worked-out row recovers (0 when unknown or not worked out).
    string[] places = new string[64]
    Int[] backHours = new Int[64]
    string hold = MvpHold()
    Int count = 0
    Bool sampled = false
    Int p = 0
    Int professionCount = WOSK_Registry.CountProfessions()
    while p < professionCount && count < 64
        string profession = WOSK_Registry.GetProfessionId(p, "")
        Int t = 0
        string taskId = WOSK_Registry.GetTaskString(profession, 0, "id", "")
        while taskId != "" && count < 64
            string resourceType = WOSK_Registry.GetTaskString(profession, t, "resourceType", "")
            Int available = 0
            string reason = "NONE"
            if WOSK_Registry.CountHoldSources(hold, resourceType) > 0
                available = WOSK_DepletionScript.AvailableVeins(hold, resourceType)
                if available > 0
                    reason = ""
                else
                    reason = WOSK_DepletionScript.RefusalReason(hold, resourceType)
                    if reason == ""
                        ; No source usable and no reason to give: the refusal walk
                        ; found nothing to report, so the honest answer is the same
                        ; as having no source at all.
                        reason = "NONE"
                    endIf
                endIf
            endIf
            ; Fase 33 etapa 8 (D1, V071): the cook works in the kitchen of his own house
            ; only (D267), so his rows speak of that kitchen - not of the sum of every
            ; kitchen of the hold, which counted the Tundra one he never uses. The house
            ; is the one a cook moves into (ChosenHouse), the one the panel shows.
            string place = ""
            string kitchen = ""
            string cookHouse = ""
            if WOSK_PlayerHouse.RequiresHouse(profession) && WOSK_Registry.CountHoldSources(hold, resourceType) > 0
                cookHouse = WOSK_PlayerHouse.ChosenHouse()
                kitchen = WOSK_PlayerHouse.KitchenZone(cookHouse)
                if kitchen == ""
                    available = 0
                    reason = "NONE"
                else
                    place = cookHouse
                    available = WOSK_DepletionScript.AvailableAt(hold, kitchen, resourceType)
                    reason = WOSK_DepletionScript.ReasonAt(hold, kitchen, resourceType)
                    if available <= 0 && reason == ""
                        reason = "NONE"
                    endIf
                endIf
            endIf
            Int backIn = 0
            if reason == "DEPLETED"
                if kitchen != ""
                    backIn = WOSK_DepletionScript.HoursToRecover(hold, kitchen, resourceType)
                else
                    backIn = WOSK_DepletionScript.HoursUntilBack(hold, resourceType)
                endIf
            endIf
            places[count] = place
            backHours[count] = backIn
            ; The ore count the row prints is veins x what the GAME says a vein
            ; of this type holds - the quantity the player would dig out of the
            ; ground there, which is what the line is about. It is NOT the
            ; task's unitsPerVein: that number is the contract's batch
            ; arithmetic, the two are different quantities, and the difference
            ; is an open question for the maintainer (V043).
            ;
            ; -1 means the yield is not known on this save yet, and the page
            ; prints the veins alone rather than a made-up estimate.
            ; Fase 15: a zone counts units, not veins - one slot is one unit, so
            ; the units are the count itself and the page prints no vein.
            Bool zoneType = WOSK_DepletionScript.TypeIsZone(hold, resourceType)
            Float yieldPerVein = 1.0
            if !zoneType
                yieldPerVein = WOSK_DepletionScript.VeinYield(hold, resourceType, 3)
            endIf
            taskIds[count] = taskId
            veins[count] = available
            if zoneType
                ; -2 tells the page this row is a zone (units, no vein).
                veins[count] = -2
                units[count] = available
            elseIf yieldPerVein > 0.0
                units[count] = Math.Floor((available as Float) * yieldPerVein)
            else
                units[count] = -1
            endIf
            reasons[count] = reason
            ; ONE drift trace per push: the push runs at every contract state
            ; change, and the same two numbers repeated forty times a round is
            ; noise, not evidence.
            if !sampled && !zoneType && yieldPerVein > 0.0
                Float unitsPerVein = WOSK_DepletionScript.UnitsPerVein(profession, t)
                if unitsPerVein != yieldPerVein
                    sampled = true
                    Debug.Trace("WOSK_Controller: yield check " + resourceType + " - contract batch counts " + unitsPerVein + \
                                " unit(s)/vein, the ground gives " + yieldPerVein + " (V043)")
                endIf
            endIf
            count += 1
            t += 1
            taskId = WOSK_Registry.GetTaskString(profession, t, "id", "")
        endwhile
        p += 1
    endwhile
    WOSK_Panel.SetSourceList(taskIds, veins, units, reasons, hold, count, places, backHours)
    Debug.Trace("WOSK_Controller: source list sent, " + count + " task row(s) for " + hold)
    return count
EndFunction

; ---------------------------------------------------------------------------
; Worker tracker (queue item 12, scope 1) - TEST AID, off unless the TOML says
; a number of seconds. The loop that calls this lives on WOSK_PlayerAliasScript.
; ---------------------------------------------------------------------------

; One notification per worker with a live contract. Returns how many it showed,
; so the harness can measure it without watching the screen.
;
; Nothing here is a player-facing feature: scope 2 of the same request - a quest
; objective on the compass and the map - needs a QOBJ/QSTA record in
; WOSK_WorkerPool and a decision the maintainer has not taken (V041).
; How many seconds between reports, already clamped. 0 means off, and that is
; what the shipped TOML says. Anything the config puts below the floor is
; raised to it: at one second this would be a wall of notifications, and a
; tester cannot read what he cannot keep on screen.
;
; On the quest and not on the alias that runs the loop so the harness can call
; it without hunting for an alias index - and because this project keeps its
; logic here (the alias is plumbing, see the header of WOSK_PlayerAliasScript).
Int Function TrackerInterval()
    Int seconds = WOSK_Registry.GetWorkerTrackerSeconds()
    if seconds <= 0
        return 0
    endIf
    if seconds < 5
        return 5
    endIf
    return seconds
EndFunction

Int Function ReportWorkerPositions()
    Int shown = 0
    Int i = 0
    while i < WorkerPoolSize
        WOSK_WorkerAliasScript a = WorkerPool.GetAlias(i) as WOSK_WorkerAliasScript
        if a
            string line = a.TrackerLine()
            if line != ""
                Debug.Notification("Honest Work: " + line)
                Debug.Trace("WOSK_Controller: tracker slot " + i + " - " + line)
                shown += 1
            endIf
        endIf
        i += 1
    endwhile
    ; Traced even at zero, and that is the point: with every worker idle the
    ; sweep says nothing on screen, so without this line there is no way to
    ; tell a tracker that is running quietly from one that never armed.
    Debug.Trace("WOSK_Controller: tracker tick, " + shown + " worker(s) reported")
    return shown
EndFunction

; ---------------------------------------------------------------------------
; Encounter check - iterate the fixed pool of worker aliases, let each one
; decide independently whether the player just crossed its local_incidente.
; ---------------------------------------------------------------------------

Function CheckAllEncounters()
    Int i = 0
    while i < WorkerPoolSize
        ReferenceAlias a = WorkerPool.GetAlias(i) as ReferenceAlias
        if a
            (a as WOSK_WorkerAliasScript).CheckEncounter()
        endIf
        i += 1
    endwhile
EndFunction

; ---------------------------------------------------------------------------
; Public API - called by WOSK_PanelBridgeScript and by whatever hires a
; candidate (dialogue or Activate). Kept here (not in the bridge) so the
; bridge stays a thin global lookup - all real decisions and
; StorageUtil/JsonUtil access live on this one script.
; ---------------------------------------------------------------------------

; Hires akCandidate into the first empty alias. Returns the alias index used,
; or -1 if the pool is full. Does not remove akCandidate from
; WOSK_FL_Candidates_Whiterun - that FormList is the *source* of who can be
; hired, not the record of who currently holds a slot (StorageUtil per-worker
; state, keyed by Actor, already recognizes an alias as "taken" if its
; reference is filled).
Int Function HireCandidate(Actor akCandidate)
    if !akCandidate
        return -1
    endIf
    ; D183: 2 workers per hold, 3 once the player is Thane.
    Int cap = GetHireCap(0)
    if GetWorkerCount(0) >= cap
        Debug.Notification("Honest Work: you can employ only " + cap + " worker(s) in this hold.")
        Debug.Trace("WOSK_Controller: HireCandidate refused, " + GetWorkerCount(0) + " hired, cap " + cap + " (thane=" + IsThane(0) + ")")
        return -1
    endIf
    ; Fase 24 (D223): the cook lives in the player's house in the hold. None
    ; owned: refused before any gold moves; the candidate stays where he is.
    string profession = EnsureCandidateProfession(akCandidate)
    ; Fase 33 etapa 10 (D294): ONE cook per hold. The second is refused here, before
    ; any gold moves; a save that already has two keeps both (nobody is dismissed).
    string blocked = HireBlockReason(profession)
    if blocked != ""
        Debug.Notification("Honest Work: " + HireBlockText(blocked))
        Debug.Trace("WOSK_Controller: HireCandidate refused, " + akCandidate + " (" + profession + ") - " + blocked + ", the hold '" + MvpHold() + "' already has " + CountWorkersOfProfession(profession))
        return -1
    endIf
    string house = ""
    if WOSK_PlayerHouse.RequiresHouse(profession)
        ; Fase 33 etapa 2 (D267): the house the player chose for his cook, else the first.
        house = WOSK_PlayerHouse.ChosenHouse()
        if house == ""
            Debug.Notification("Honest Work: " + WOSK_PlayerHouse.NeedsHouseText(CandidateShownName(akCandidate)))
            Debug.Trace("WOSK_Controller: HireCandidate refused, " + akCandidate + " (" + profession + ") needs a house of the player in the hold, none owned")
            return -1
        endIf
    endIf
    Int i = 0
    while i < WorkerPoolSize
        ReferenceAlias a = WorkerPool.GetAlias(i) as ReferenceAlias
        if a && !a.GetReference()
            ; D104: hiring is paid once, by the candidate's tier.
            Int price = GetHirePrice(akCandidate)
            string tier = StorageUtil.GetStringValue(akCandidate, "WOSK_Tier", "apprentice")
            Actor player = Game.GetPlayer()
            Form goldForm = Game.GetFormFromFile(0x0000000F, "Skyrim.esm")
            if player.GetItemCount(goldForm) < price
                Debug.Trace("WOSK_Controller: HireCandidate refused, player has " + player.GetItemCount(goldForm) + \
                             " gold, " + akCandidate + " (" + tier + ") costs " + price)
                return -1
            endIf
            player.RemoveItem(goldForm, price)
            ; D104 etapa 2: the hired candidate leaves the pool, and its spot
            ; gets a new candidate in 3 to 7 days.
            Int candidateSpot = _CandidateAliasIndex(akCandidate)
            if candidateSpot >= 0
                ; D105 etapa 2: the worker returns to this spot after each contract.
                ; D161: the spot it stood at, the one stored when it was placed.
                StorageUtil.SetFormValue(akCandidate, "WOSK_HomeMarker", CandidateMarker(akCandidate, candidateSpot))
                ; D165: a hired worker is no longer a candidate the dialogue talks for.
                _ClearCandidateFactions(akCandidate)
                (CandidatePool.GetAlias(candidateSpot) as ReferenceAlias).Clear()
                ActorUtil.ClearPackageOverride(akCandidate)
                OpenCandidateVacancy(candidateSpot)
            endIf
            a.ForceRefTo(akCandidate)
            ; Fase 31 (D248): the day of the hire, which the dismissal fee decays from.
            StorageUtil.SetFloatValue(akCandidate, "WOSK_HiredDay", Utility.GetCurrentGameTime())
            ; Fase 27 (D232): the trade's outfit goes on at the hire (Fase 31 conserto 1,
            ; D256: piece by piece on HIM, never on the shared base); SendAway gives the
            ; original one back, and the worker's death leaves what he wears.
            WOSK_Outfits.Wear(akCandidate, profession)
            ; Fase 26 conserto 1 (D233): the dialogue reads the contract state as a
            ; faction rank; a hired worker starts idle (or with his old contract key).
            WOSK_WorkerState.Reconcile(akCandidate)
            ; Fase 26 (D228): a worker hired above the first tier starts with the
            ; contracts that tier stands for, so the tier bar counts from there.
            Int tierFloor = WOSK_Registry.GetTierInt(profession, tier, "minContracts", 0)
            if tierFloor > StorageUtil.GetIntValue(akCandidate, "WOSK_ContractsCompleted", 0)
                StorageUtil.SetIntValue(akCandidate, "WOSK_ContractsCompleted", tierFloor)
            endIf
            if house != ""
                ; D223: the house becomes his home and he moves in now.
                WOSK_PlayerHouse.MoveIn(akCandidate, house)
            endIf
            Debug.Notification("Honest Work: worker hired for " + price + " gold.")
            if house != ""
                ; Fase 26 (D229): said once, at the hire, so the player knows where he went.
                Debug.Notification("Honest Work: " + WOSK_PlayerHouse.MovedIntoText(CandidateShownName(akCandidate), house))
            endIf
            Debug.Trace("WOSK_Controller: hired " + akCandidate + " (" + tier + ") into slot " + i + " for " + price + " gold, house='" + house + "', hold='" + MvpHold() + "'")
            ; Queue item 11: a hire is the one change that ADDS a row, and it
            ; passes through no alias, so _AdvanceTo never sees it.
            RefreshWorkerList()
            ; Fase 31 conserto 1 (D258): the new row's counters ride with it; without them
            ; the Worker tab said "Waiting for the history..." and "-" until the next push.
            RefreshHistory()
            ; Fase 26: the recruit card and the 'employed' count change at a hire
            ; too, however the hire was reached (the dialogue calls this directly).
            RefreshRecruitList("")
            return i
        endIf
        i += 1
    endwhile
    Debug.Trace("WOSK_Controller: HireCandidate failed, pool full (size=" + WorkerPoolSize + ")")
    return -1
EndFunction

; ---------------------------------------------------------------------------
; Fase 34 etapa 2 (D299) - a follower of the player hired as a worker, from the
; "Your followers" section of the Recruit tab. Free; the profession is the
; player's choice and the tier comes from the skill nearest the trade (A3, P8).
; ---------------------------------------------------------------------------

Actor[] _followerList
string _followerMsg = ""

; The answer for the page, written by the last HireFollower.
string Function FollowerProblem()
    return _followerMsg
EndFunction

; Returns the alias index used, or -1 (the reason is in FollowerProblem and goes
; to the page). The framework lets him go BEFORE the alias takes him (D298).
Int Function HireFollower(Actor akFollower, string asProfession)
    _followerMsg = ""
    if !akFollower || WOSK_Followers.SkillFor(asProfession) == ""
        _followerMsg = "That follower cannot be hired for that trade."
        return -1
    endIf
    if WOSK_Followers.IsFollower(akFollower)
        _followerMsg = akFollower.GetDisplayName() + " already works for you."
        return -1
    endIf
    string refusal = WOSK_Followers.Refusal(akFollower)
    if refusal != ""
        _followerMsg = akFollower.GetDisplayName() + " cannot be hired (" + refusal + ")."
        Debug.Trace("WOSK_Controller: HireFollower refused, " + akFollower + " - " + refusal)
        return -1
    endIf
    ; P4: the hold's housecarl keeps his post.
    if akFollower == GetHousecarlForHold(0)
        _followerMsg = akFollower.GetDisplayName() + " is the housecarl of the hold and keeps his post."
        return -1
    endIf
    Int cap = GetHireCap(0)
    Int count = GetWorkerCount(0)
    if count >= cap
        _followerMsg = "You can employ only " + cap + " worker(s) in this hold."
        return -1
    endIf
    string blocked = HireBlockReason(asProfession)
    if blocked != ""
        _followerMsg = HireBlockText(blocked)
        return -1
    endIf
    string house = ""
    if WOSK_PlayerHouse.RequiresHouse(asProfession)
        house = WOSK_PlayerHouse.ChosenHouse()
        if house == ""
            _followerMsg = WOSK_PlayerHouse.NeedsHouseText(akFollower.GetDisplayName())
            return -1
        endIf
    endIf
    ReferenceAlias slot = None
    Int slotIndex = -1
    Int i = 0
    while i < WorkerPoolSize && !slot
        ReferenceAlias a = WorkerPool.GetAlias(i) as ReferenceAlias
        if a && !a.GetReference()
            slot = a
            slotIndex = i
        endIf
        i += 1
    endWhile
    if !slot
        _followerMsg = "Every worker slot is taken."
        return -1
    endIf
    ; P9: whatever another mod linked him to is saved once, before the first link of ours.
    Keyword link = Game.GetFormFromFile(0x0005D5E7, "Skyrim.esm") as Keyword
    if link && !StorageUtil.HasIntValue(akFollower, WOSK_Followers.KeySavedLink())
        StorageUtil.SetFormValue(akFollower, WOSK_Followers.KeyPrevLink(), akFollower.GetLinkedRef(link))
        StorageUtil.SetIntValue(akFollower, WOSK_Followers.KeySavedLink(), 1)
    endIf
    if !WOSK_Followers.DismissFromFramework(akFollower)
        _followerMsg = akFollower.GetDisplayName() + " is still bound to his follower framework."
        Debug.Trace("WOSK_Controller: HireFollower stopped, " + akFollower + " still a teammate after the dismissal")
        return -1
    endIf
    string tier = WOSK_Followers.TierFor(akFollower, asProfession)
    StorageUtil.SetIntValue(akFollower, WOSK_Followers.KeyMark(), 1)
    StorageUtil.SetStringValue(akFollower, "WOSK_Profession", asProfession)
    StorageUtil.SetStringValue(akFollower, "WOSK_Tier", tier)
    StorageUtil.SetFloatValue(akFollower, "WOSK_HiredDay", Utility.GetCurrentGameTime())
    ; P6: home is his own in Whiterun; elsewhere the inn marker, one step apart per worker.
    if house != ""
        ; D223: the cook lives in the house, as any cook.
        StorageUtil.UnsetIntValue(akFollower, WOSK_Followers.KeyNativeHome())
    elseIf WOSK_Followers.InWhiterun(akFollower)
        StorageUtil.SetIntValue(akFollower, WOSK_Followers.KeyNativeHome(), 1)
    else
        StorageUtil.UnsetIntValue(akFollower, WOSK_Followers.KeyNativeHome())
        StorageUtil.SetFloatValue(akFollower, WOSK_Followers.KeyHomeOffset(), 90.0 * count)
    endIf
    slot.ForceRefTo(akFollower)
    WOSK_WorkerState.Reconcile(akFollower)
    Int tierFloor = WOSK_Registry.GetTierInt(asProfession, tier, "minContracts", 0)
    if tierFloor > StorageUtil.GetIntValue(akFollower, "WOSK_ContractsCompleted", 0)
        StorageUtil.SetIntValue(akFollower, "WOSK_ContractsCompleted", tierFloor)
    endIf
    if house != ""
        WOSK_PlayerHouse.MoveIn(akFollower, house)
    else
        ; Fase 34 etapa 5 (D308, V086): hiring sends him home at once, as every other send.
        (slot as WOSK_WorkerAliasScript).SendHomeOnHire()
    endIf
    Debug.Notification("Honest Work: " + akFollower.GetDisplayName() + " now works for you.")
    Debug.Trace("WOSK_Controller: follower hired " + akFollower + " as " + asProfession + " (" + tier + ", skill " + WOSK_Followers.SkillLevel(akFollower, asProfession) + \
                ") into slot " + slotIndex + ", nativeHome=" + StorageUtil.GetIntValue(akFollower, WOSK_Followers.KeyNativeHome(), 0) + ", house='" + house + "'")
    RefreshWorkerList()
    RefreshHistory()
    _followerMsg = akFollower.GetDisplayName() + " now works for you as " + asProfession + " (" + WOSK_Names.TierLabel(tier) + ")."
    RefreshRecruitList("")
    return slotIndex
EndFunction

Float _hireSince = 0.0

; The page sends the row of the list it was last given.
Function HireFollowerFromPanel(Int aiIndex, string asProfession)
    if _followerList && aiIndex >= 0 && aiIndex < _followerList.Length && _followerList[aiIndex]
        ; Fase 35 etapa 9 (V102): one hire at a time. The dismissal from the framework waits 2 s, and
        ; the second click passed the IsFollower check before the first one set the mark. The stamp is
        ; real time, so a stack lost mid-way frees itself after 20 s.
        Float now = Utility.GetCurrentRealTime()
        if _hireSince > 0.0 && now >= _hireSince && now - _hireSince < 20.0
            _followerMsg = "A hire is already under way."
            Debug.Trace("WOSK_Controller: HIRE-DOBRO-RECUSADO " + _followerList[aiIndex] + " as " + asProfession + " - a hire started " + (now - _hireSince) + " s ago is still running")
        else
            _hireSince = now
            HireFollower(_followerList[aiIndex], asProfession)
            _hireSince = 0.0
        endIf
    else
        _followerMsg = "That follower is no longer in the list."
    endIf
    RefreshRecruitList("")
EndFunction

; Fase 35 etapa 4: the Bodyguards section sends the row of the same list.
Function AssignGuardFromPanel(Int aiIndex)
    if aiIndex < 0
        ; Fase 35 etapa 6: a negative order is a release (-(1 + row)).
        ReleaseGuardFromPanel(aiIndex)
        return
    endIf
    if _followerList && aiIndex >= 0 && aiIndex < _followerList.Length && _followerList[aiIndex]
        AssignGuard(_followerList[aiIndex])
    else
        _followerMsg = "That follower is no longer in the list."
    endIf
    RefreshRecruitList("")
EndFunction

; Sends the followers to the page: names, where they stand, the id of the rule that
; refuses them ("" when free) and the tier each trade would give is worked out
; by the page from the skill list below. Called at the end of RefreshRecruitList.
Function RefreshFollowerList(string asMessage)
    string msg = asMessage
    if msg == "" && _followerMsg != ""
        msg = _followerMsg
    endIf
    _followerMsg = ""
    string[] names = new string[16]
    string[] places = new string[16]
    string[] refused = new string[16]
    string[] tiers = new string[16]
    Int count = 0
    Int needsPo3 = 0
    _followerList = new Actor[8]
    if !WOSK_Followers.Po3Present()
        needsPo3 = 1
    else
        Actor[] found = PO3_SKSEFunctions.GetPlayerFollowers()
        Int i = 0
        while found && i < found.Length && count < 8
            Actor f = found[i]
            if f && WOSK_Guards.IsGuard(f)
                ; Fase 35 etapa 6: a guard the framework took back (its dialogue) stops being a guard.
                if ReleaseGuard(f, "rejoined the follower framework")
                    msg = f.GetDisplayName() + " rejoined you as a follower and is no longer your bodyguard."
                endIf
            elseIf f && !WOSK_Followers.IsFollower(f)
                _followerList[count] = f
                names[count] = f.GetDisplayName()
                Location loc = f.GetCurrentLocation()
                if loc
                    places[count] = loc.GetName()
                endIf
                refused[count] = WOSK_Followers.Refusal(f)
                tiers[count] = _FollowerTiers(f)
                count += 1
            endIf
            i += 1
        endWhile
    endIf
    ; Fase 35 etapa 6: the bodyguards ride the same channel, after the followers; refused "GUARD" is
    ; the mark, the place field says where he waits or whom he escorts. The release order sends
    ; -(1 + row), which GuardRowToIndex maps back.
    _guardRowStart = count
    _guardRows = new Actor[8]
    Int g = 0
    Int gn = WOSK_Guards.GuardCount()
    while g < gn && count < 16 && g < 8
        Actor guard = WOSK_Guards.GuardAt(g)
        if guard
            _guardRows[g] = guard
            names[count] = guard.GetDisplayName()
            Actor boss = StorageUtil.GetFormValue(guard, WOSK_Guards.KeyEscorting(), None) as Actor
            if boss
                places[count] = "Escorting " + boss.GetDisplayName()
            else
                Location gloc = guard.GetCurrentLocation()
                if gloc
                    places[count] = WOSK_PlayerHouse.WaitsAtText(gloc.GetName())
                else
                    places[count] = "Waits for a contract"
                endIf
            endIf
            refused[count] = "GUARD"
            tiers[count] = ""
            count += 1
        endIf
        g += 1
    endWhile
    WOSK_Panel.SetFollowerList(names, places, refused, tiers, count, needsPo3, msg)
EndFunction

Actor[] _guardRows
Int _guardRowStart = 0

; Fase 35 etapa 8 (V100): Attach and Detach change who is free; the page decides "With
; bodyguard" from the list it was last given, so the list goes again at those moments. The
; pending message is kept for the next real refresh.
Function RefreshGuardState()
    if WOSK_Guards.GuardCount() < 1
        return
    endIf
    string keep = _followerMsg
    RefreshFollowerList("")
    _followerMsg = keep
    Debug.Trace("WOSK_Controller: GUARDA-LISTA-ENVIADA guards=" + WOSK_Guards.GuardCount())
EndFunction

; Fase 35 etapa 6 (Q5): free, the gold is not returned. A guard on a contract is not released
; (the escort ends first). Fase 35 etapa 8 (V100): abRecruit puts him back into the follower
; framework he was taken out of (the release from the panel); when the framework itself took him
; back (its dialogue) there is nothing to give back.
Bool Function ReleaseGuard(Actor akGuard, string asWhy, Bool abRecruit = false)
    if !akGuard || !WOSK_Guards.IsGuard(akGuard)
        return false
    endIf
    if StorageUtil.GetFormValue(akGuard, WOSK_Guards.KeyEscorting(), None)
        _followerMsg = akGuard.GetDisplayName() + " is escorting a worker and cannot be released now."
        Debug.Trace("WOSK_Controller: GUARDA-SOLTAR-RECUSADO " + akGuard + " - escorting, why=" + asWhy)
        return false
    endIf
    WOSK_Guards.Forget(akGuard)
    akGuard.EvaluatePackage()
    Bool back = false
    if abRecruit
        ; His own post (house sandbox) is off with Forget; the framework takes him from here.
        back = WOSK_Followers.RecruitToFramework(akGuard)
        if !back
            _followerMsg = akGuard.GetDisplayName() + " could not rejoin your followers; talk to him to recruit him."
        endIf
    endIf
    Debug.Trace("WOSK_Controller: GUARDA-SOLTO " + akGuard + " why=" + asWhy + " guards=" + WOSK_Guards.GuardCount() + " recruited=" + back as Int)
    return true
EndFunction

; The page sends the row it was given, negated: -(1 + row). Row minus the first guard row is
; the slot in _guardRows.
Function ReleaseGuardFromPanel(Int aiOrder)
    Int row = -aiOrder - 1
    Int slot = row - _guardRowStart
    if _guardRows && slot >= 0 && slot < _guardRows.Length && _guardRows[slot]
        Actor guard = _guardRows[slot]
        if ReleaseGuard(guard, "released from the panel", true)
            if _followerMsg == ""
                _followerMsg = guard.GetDisplayName() + " is no longer your bodyguard and follows you again. The gold is not returned."
            endIf
        endIf
    else
        _followerMsg = "That bodyguard is no longer in the list."
    endIf
    RefreshRecruitList("")
EndFunction

; "miner:worker,hunter:master,..." - what each trade would give him, so the page can
; show the tier before the click without holding the table itself.
string Function _FollowerTiers(Actor akFollower)
    string out = ""
    Int n = WOSK_Registry.CountProfessions()
    Int i = 0
    while i < n
        string p = WOSK_Registry.GetProfessionId(i, "")
        if p != ""
            if out != ""
                out += ","
            endIf
            out += p + ":" + WOSK_Followers.TierFor(akFollower, p)
        endIf
        i += 1
    endWhile
    return out
EndFunction

; D104: a candidate's tier is rolled once, by each tier's
; candidateWeight in the JSON, the first time anyone asks - and kept after.
; D182 (revokes D164): each candidate rolls alone, without looking at the rest
; of the pool - none, one or several masters can stand in the hold.
; Mirrors the development reference model roll_candidate_tier.
string Function EnsureCandidateTier(Actor akCandidate)
    if StorageUtil.HasStringValue(akCandidate, "WOSK_Tier")
        return StorageUtil.GetStringValue(akCandidate, "WOSK_Tier", "apprentice")
    endIf
    string profession = EnsureCandidateProfession(akCandidate)
    string[] tiers = new string[4]
    tiers[0] = "apprentice"
    tiers[1] = "worker"
    tiers[2] = "veteran"
    tiers[3] = "master"
    Int last = 4
    Int total = 0
    Int i = 0
    while i < last
        total += WOSK_Registry.GetTierInt(profession, tiers[i], "candidateWeight", 0)
        i += 1
    endwhile
    string rolled = "apprentice"
    if total > 0
        Float pick = Utility.RandomFloat(0.0, 1.0) * total
        Int cumulative = 0
        Bool found = false
        i = 0
        while i < last && !found
            Int weight = WOSK_Registry.GetTierInt(profession, tiers[i], "candidateWeight", 0)
            if weight > 0
                cumulative += weight
                rolled = tiers[i]
                found = pick < cumulative
            endIf
            i += 1
        endwhile
    endIf
    StorageUtil.SetStringValue(akCandidate, "WOSK_Tier", rolled)
    Debug.Trace("WOSK_Controller: " + akCandidate + " candidate tier rolled " + rolled + " (weights total " + total + ")")
    return rolled
EndFunction

; D104 etapa 2b: a candidate's profession is rolled once, evenly among the
; registered professions, and kept. Rolled before the tier, whose weights are
; per profession.
string Function EnsureCandidateProfession(Actor akCandidate)
    if StorageUtil.HasStringValue(akCandidate, "WOSK_Profession")
        return StorageUtil.GetStringValue(akCandidate, "WOSK_Profession", "miner")
    endIf
    string rolled = "miner"
    Int count = WOSK_Registry.CountProfessions()
    if count > 0
        rolled = WOSK_Registry.GetProfessionId(Utility.RandomInt(0, count - 1), "miner")
    endIf
    StorageUtil.SetStringValue(akCandidate, "WOSK_Profession", rolled)
    Debug.Trace("WOSK_Controller: " + akCandidate + " candidate profession rolled " + rolled + " (of " + count + ")")
    return rolled
EndFunction

; D104 etapa 2b: Thane of the hold. Vanilla keeps it on FavorJarlsMakeFriends
; (0x00087E24): GetOutofJailCard sets WhiterunImpGetOutofJail or
; WhiterunSonsGetOutofJail to 1 (2 once the card is used), and both ways to
; the title call it - Favor253 stage 25 (QF_Favor253_000A2C9E.psc:41) and
; MQ104B stage 160 (QF_MQ104B_0002610C.psc:291). Only Whiterun (hold 0) exists
; in the MVP.
Bool Function IsThane(Int aiHoldID)
    FavorJarlsMakeFriendsScript friends = Game.GetFormFromFile(0x00087E24, "Skyrim.esm") as FavorJarlsMakeFriendsScript
    if aiHoldID != 0 || !friends
        return false
    endIf
    return friends.WhiterunImpGetOutofJail > 0 || friends.WhiterunSonsGetOutofJail > 0
EndFunction

; D183 (maintainer decision 2026-10-26; was 1 and 2, D104 etapa 2b): 2 workers
; per hold, 3 once the player is Thane. The player picks the professions.
; WOSK_WorkerPool has 4 aliases (WorkerPoolSize), so 3 fit.
Int Function GetHireCap(Int aiHoldID)
    if IsThane(aiHoldID)
        return 3
    endIf
    return 2
EndFunction

; Fase 33 etapa 10: how many hired workers (an alias holds the actor) have this profession.
; The one count the cook rule reads, on the panel's list and on the hire itself.
Int Function CountWorkersOfProfession(string asProfession)
    Int count = 0
    Int i = 0
    while i < WorkerPoolSize
        ReferenceAlias a = WorkerPool.GetAlias(i) as ReferenceAlias
        Actor w = None
        if a
            w = a.GetActorRef()
        endIf
        if w && StorageUtil.GetStringValue(w, "WOSK_Profession", "") == asProfession
            count += 1
        endIf
        i += 1
    endwhile
    return count
EndFunction

; The id of the rule that stops the hire of a candidate of asProfession, "" when none does.
; Only one rule today: a hold has one cook (the kitchen is his house's, D223/D267).
string Function HireBlockReason(string asProfession)
    if asProfession == "cook" && CountWorkersOfProfession("cook") > 0
        return "COOK_HOLD"
    endIf
    return ""
EndFunction

string Function HireBlockText(string asReason)
    if asReason == "COOK_HOLD"
        return "you already employ a cook in this hold."
    endIf
    return "this candidate cannot be hired now."
EndFunction

; D104: what hiring akCandidate costs - the hiringFee of its tier.
Int Function GetHirePrice(Actor akCandidate)
    string profession = EnsureCandidateProfession(akCandidate)
    return WOSK_Registry.GetTierInt(profession, EnsureCandidateTier(akCandidate), "hiringFee", 0)
EndFunction

; ---------------------------------------------------------------------------
; Candidate pool (D104 etapa 2; Fase 16 D161-D165) - one spot per
; profession that has a place in the hold (candidate_pools/*.json). A
; candidate nobody hires leaves after rotationDays and another arrives in the
; same load; a spot opened by a hire or a death gets a new one refillDaysMin
; to refillDaysMax days later.
; ---------------------------------------------------------------------------

; D161/D218: the pool has as many spots as WOSK_CandidatePool has aliases (10:
; the six fixed ones and the four extras), never more than the hold's JSON
; names. Read from the quest, not from CandidatePoolSize: an Auto property
; keeps the value the save stored (5), whatever the script now says. A save
; from before Fase 22 has six aliases filled and four that the plugin adds
; empty; RefillCandidatePool fills them at its first run (D218).
Int Function CandidatePoolCount()
    if !CandidatePool
        return 0
    endIf
    Int n = CandidatePool.GetNumAliases()
    Int cap = FixedSlotCount() + ExtraSlotCount()
    if cap > 0 && n > cap
        n = cap
    endIf
    return n
EndFunction

; D161: how many professions have a spot in the hold - the fixed spots, slots
; 0 to FixedSlotCount() - 1.
Int Function FixedSlotCount()
    string hold = MvpHold()
    Int n = WOSK_Registry.CountProfessions()
    Int k = 0
    Int count = 0
    while k < n
        string prof = WOSK_Registry.GetProfessionId(k, "")
        if prof != "" && WOSK_Registry.GetCandidateSpotString(hold, prof, "marker", "") != ""
            count += 1
        endIf
        k += 1
    endwhile
    return count
EndFunction

; D218: the hold's extra spots (candidate_pools extraSpots) - the slots after the
; fixed ones. Their profession is rolled at each arrival, not the spot's.
Int Function ExtraSlotCount()
    return WOSK_Registry.CountCandidateExtras(MvpHold())
EndFunction

Bool Function IsExtraSlot(Int aiSlot)
    Int fixed = FixedSlotCount()
    return aiSlot >= fixed && aiSlot < fixed + ExtraSlotCount()
EndFunction

; D218: the profession of an extra's new candidate - one of the hold's fixed
; spots' professions, evenly (repeats allowed), rolled at every arrival. ""
; when the hold has no fixed spot. Mirrors the development reference model
; roll_extra_profession.
string Function RollExtraProfession()
    Int fixed = FixedSlotCount()
    if fixed <= 0
        return ""
    endIf
    return SlotProfession(Utility.RandomInt(0, fixed - 1))
EndFunction

; D161: spot aiSlot is the aiSlot-th profession of the registry (its order) that
; has a spot in the hold's candidate pool. "" when there is no such spot - and
; for an extra (D218), whose profession is the candidate's, stored on it.
; Mirrors the development reference model candidate_slots.
string Function SlotProfession(Int aiSlot)
    string hold = MvpHold()
    Int n = WOSK_Registry.CountProfessions()
    Int k = 0
    Int slot = 0
    while k < n
        string prof = WOSK_Registry.GetProfessionId(k, "")
        if prof != "" && WOSK_Registry.GetCandidateSpotString(hold, prof, "marker", "") != ""
            if slot == aiSlot
                return prof
            endIf
            slot += 1
        endIf
        k += 1
    endwhile
    return ""
EndFunction

; Where a new candidate of spot aiSlot stands: the spot's marker in the JSON,
; or the alias's TargetMarker when the JSON does not resolve.
ObjectReference Function SlotMarker(Int aiSlot)
    ObjectReference marker = None
    string prof = SlotProfession(aiSlot)
    if prof != ""
        marker = WOSK_DepletionScript.ResolveFormRef(WOSK_Registry.GetCandidateSpotString(MvpHold(), prof, "marker", "")) as ObjectReference
    elseIf IsExtraSlot(aiSlot)
        marker = WOSK_DepletionScript.ResolveFormRef(WOSK_Registry.GetCandidateExtraString(MvpHold(), aiSlot - FixedSlotCount(), "marker", "")) as ObjectReference
    endIf
    if !marker && CandidatePool
        WOSK_CandidateAliasScript a = CandidatePool.GetAlias(aiSlot) as WOSK_CandidateAliasScript
        if a
            marker = a.TargetMarker
        endIf
    endIf
    return marker
EndFunction

; The place name the Recruit tab prints for a marker: the place of the JSON
; spot with that marker. "" for a marker no spot names (a candidate of a save
; from before Fase 16 standing on the old fifth spot).
string Function PlaceOfMarker(ObjectReference akMarker)
    if !akMarker
        return ""
    endIf
    string hold = MvpHold()
    Int n = WOSK_Registry.CountProfessions()
    Int k = 0
    while k < n
        string prof = WOSK_Registry.GetProfessionId(k, "")
        string ref = WOSK_Registry.GetCandidateSpotString(hold, prof, "marker", "")
        if ref != "" && WOSK_DepletionScript.ResolveFormRef(ref) == akMarker
            return WOSK_Registry.GetCandidateSpotString(hold, prof, "place", "")
        endIf
        k += 1
    endwhile
    ; D218: the extras' spots.
    Int extras = ExtraSlotCount()
    Int e = 0
    while e < extras
        string extraRef = WOSK_Registry.GetCandidateExtraString(hold, e, "marker", "")
        if extraRef != "" && WOSK_DepletionScript.ResolveFormRef(extraRef) == akMarker
            return WOSK_Registry.GetCandidateExtraString(hold, e, "place", "")
        endIf
        e += 1
    endwhile
    return ""
EndFunction

; The marker this candidate stands at (stored when it was placed).
ObjectReference Function CandidateMarker(Actor akCandidate, Int aiSlot)
    ObjectReference marker = StorageUtil.GetFormValue(akCandidate, "WOSK_CandidateMarker", None) as ObjectReference
    if !marker
        marker = SlotMarker(aiSlot)
    endIf
    return marker
EndFunction

Float Function PoolFloat(string asField, Float afDefault)
    return WOSK_Registry.GetCandidatePoolFloat(MvpHold(), asField, afDefault)
EndFunction

; Fills every empty spot that is due, and rotates the candidate whose week is
; up. A spot with no date is filled at once - the pool starts full, the first
; spots with the candidates placed in the plugin (WOSK_FL_Candidates_Whiterun),
; once each. Cheap when nothing is due, so it runs on every cell and game load.
Function RefillCandidatePool()
    if !CandidatePool
        return
    endIf
    Actor player = Game.GetPlayer()
    Float today = Utility.GetCurrentGameTime()
    Float rotation = PoolFloat("rotationDays", 7.0)
    FormList placed = Game.GetFormFromFile(0x0000080A, "HonestWork.esp") as FormList
    Int count = CandidatePoolCount()
    Int i = 0
    while i < count
        ReferenceAlias a = CandidatePool.GetAlias(i) as ReferenceAlias
        if a
            Actor candidate = a.GetActorRef()
            string dueKey = "WOSK_CandidateDue_" + i
            string seededKey = "WOSK_CandidateSeeded_" + i
            if candidate
                if !StorageUtil.HasIntValue(candidate, "WOSK_CandidatePlaced")
                    _SetupCandidate(a, candidate, i)
                elseIf !StorageUtil.HasFloatValue(candidate, "WOSK_CandidateArrived")
                    _MigrateCandidate(a, candidate, i, today, rotation)
                else
                    _SetCandidateFactions(candidate)
                endIf
                ; Fase 27 (D232): a candidate placed by an older save has no
                ; reveal key - he was on the player's list, so he stays on it.
                ; A new arrival got its 0 in _SetupCandidate just above.
                if !StorageUtil.HasIntValue(candidate, "WOSK_CandidateRevealed")
                    StorageUtil.SetIntValue(candidate, "WOSK_CandidateRevealed", 1)
                    Debug.Trace("WOSK_Controller: candidate " + candidate + " spot " + i + " revealed (save from before Fase 27)")
                endIf
                Float arrived =StorageUtil.GetFloatValue(candidate, "WOSK_CandidateArrived", today)
                if today >= arrived + rotation
                    ; Fase 33 etapa 2 (D266, V065): he leaves unless the player can see him
                    ; (same cell, 3D up, line of sight, no menu or loading screen over it).
                    ; Until round 9 any candidate in the player's cell stayed for good.
                    if _PlayerSees(candidate)
                        Debug.Trace("WOSK_Controller: candidate spot " + i + " due since day " + (arrived + rotation) + " (today " + today + "), the player sees him - stays")
                    else
                        _RotateCandidate(a, candidate, i, arrived)
                    endIf
                endIf
            elseIf placed && i < placed.GetSize() && !StorageUtil.HasIntValue(player, seededKey)
                StorageUtil.SetIntValue(player, seededKey, 1)
                ; Fase 33 etapa 2 (D265, V065): the plugin places two seeds, a man (spot 0, the
                ; cook) and a woman (spot 1); spot 0 was always the man. One draw per game
                ; decides whether the two swap; the second spot takes the other seed.
                Int seedIndex = i
                if i < 2 && placed.GetSize() >= 2
                    Int flip = StorageUtil.GetIntValue(player, "WOSK_SeedFlip", -1)
                    if flip < 0
                        flip = Utility.RandomInt(0, 1)
                        StorageUtil.SetIntValue(player, "WOSK_SeedFlip", flip)
                        Debug.Trace("WOSK_Controller: seed draw " + flip + " (0 = spot 0 gets the man, 1 = the woman)")
                    endIf
                    if flip == 1
                        seedIndex = 1 - i
                    endIf
                endIf
                Actor seed = placed.GetAt(seedIndex) as Actor
                a.ForceRefTo(seed)
                _SetupCandidate(a, seed, i)
            elseIf !StorageUtil.HasFloatValue(player, dueKey) || StorageUtil.GetFloatValue(player, dueKey, 0.0) <= today
                ; A new arrival does not pop into view either: the spot waits while the
                ; player looks at its marker; the next look (cell load, the game clock,
                ; the recruiter) tries again.
                ObjectReference spotMarker = SlotMarker(i)
                if spotMarker && _PlayerSeesRef(spotMarker)
                    Debug.Trace("WOSK_Controller: candidate spot " + i + " is due (day " + StorageUtil.GetFloatValue(player, dueKey, today) + ", today " + today + "), the player sees its marker - waits")
                else
                    StorageUtil.UnsetFloatValue(player, dueKey)
                    _SpawnCandidate(a, i)
                endIf
            endIf
        endIf
        i += 1
    endwhile
EndFunction

; Fase 33 etapa 2 (D266): can the player see this candidate right now? Same cell as the
; player, 3D loaded, in line of sight and no menu up (Wait, sleep, a loading screen and
; the map all count as a menu: the world is not what he looks at). The test for "leaves
; in front of the player"; nobody who is seen is replaced.
Bool Function _PlayerSees(Actor akCandidate)
    return _PlayerSeesRef(akCandidate)
EndFunction

Bool Function _PlayerSeesRef(ObjectReference akRef)
    Actor player = Game.GetPlayer()
    ; The harness runs from the console, a menu, so it fixes the answer: the player key
    ; WOSK_SeesForTest 1 = sees, 0 = does not (unset in play).
    Int forced = StorageUtil.GetIntValue(player, "WOSK_SeesForTest", -1)
    if forced >= 0
        return forced == 1
    endIf
    if !akRef || Utility.IsInMenuMode()
        return false
    endIf
    if akRef.GetParentCell() != player.GetParentCell()
        return false
    endIf
    ; A marker has no 3D to ask about; an actor does.
    if (akRef as Actor) && !akRef.Is3DLoaded()
        return false
    endIf
    return player.HasLOS(akRef)
EndFunction

; D163: the candidate leaves the game as a dismissed worker does (disabled; a
; run-time actor queued for deletion) and the spot's new candidate arrives now.
Function _RotateCandidate(ReferenceAlias akAlias, Actor akCandidate, Int aiSlot, Float afArrived)
    Int formId = akCandidate.GetFormID()
    Debug.Trace("WOSK_Controller: candidate " + akCandidate + " spot " + aiSlot + " (" + \
                StorageUtil.GetStringValue(akCandidate, "WOSK_Profession", "?") + ", " + \
                StorageUtil.GetStringValue(akCandidate, "WOSK_Tier", "?") + ") leaves after arriving on day " + afArrived)
    _ClearCandidateFactions(akCandidate)
    ; SendAway reads the form id passed in: it must run BEFORE Clear().
    SendAway(akCandidate, formId)
    akAlias.Clear()
    _SpawnCandidate(akAlias, aiSlot)
EndFunction

; D163: a candidate placed before Fase 16 has no arrival date. It gets one up
; to rotationDays - 1 days back, so the candidates already there leave spread
; over the week instead of together; it keeps its profession and its marker.
; Mirrors the development reference model migration_arrival.
Function _MigrateCandidate(ReferenceAlias akAlias, Actor akCandidate, Int aiSlot, Float afToday, Float afRotation)
    Float back = 0.0
    if afRotation > 1.0
        back = Utility.RandomFloat(0.0, afRotation - 1.0)
    endIf
    StorageUtil.SetFloatValue(akCandidate, "WOSK_CandidateArrived", afToday - back)
    if !StorageUtil.HasFormValue(akCandidate, "WOSK_CandidateMarker")
        ObjectReference marker = (akAlias as WOSK_CandidateAliasScript).TargetMarker
        if !marker
            marker = SlotMarker(aiSlot)
        endIf
        StorageUtil.SetFormValue(akCandidate, "WOSK_CandidateMarker", marker)
    endIf
    StorageUtil.SetStringValue(akCandidate, "WOSK_CandidatePlace", PlaceOfMarker(StorageUtil.GetFormValue(akCandidate, "WOSK_CandidateMarker", None) as ObjectReference))
    _SetCandidateFactions(akCandidate)
    Debug.Trace("WOSK_Controller: candidate " + akCandidate + " spot " + aiSlot + " migrated (" + \
                EnsureCandidateProfession(akCandidate) + "), arrival set to day " + (afToday - back) + ", leaves on day " + (afToday - back + afRotation))
EndFunction

Function OpenCandidateVacancy(Int aiSpot)
    Float refillMin = PoolFloat("refillDaysMin", 3.0)
    Float refillMax = PoolFloat("refillDaysMax", 7.0)
    if refillMax < refillMin
        refillMax = refillMin
    endIf
    Float due = Utility.GetCurrentGameTime() + Utility.RandomFloat(refillMin, refillMax)
    StorageUtil.SetFloatValue(Game.GetPlayer(), "WOSK_CandidateDue_" + aiSpot, due)
    Debug.Trace("WOSK_Controller: candidate spot " + aiSpot + " open, new candidate on game day " + due + " (refill " + refillMin + "-" + refillMax + ")")
EndFunction

; Called by WOSK_CandidateAliasScript.OnDeath.
Function OnCandidateDied(ReferenceAlias akAlias)
    Int count = CandidatePoolCount()
    Int i = 0
    while i < count
        if CandidatePool.GetAlias(i) == akAlias
            akAlias.Clear()
            OpenCandidateVacancy(i)
            return
        endIf
        i += 1
    endwhile
EndFunction

Int Function _CandidateAliasIndex(Actor akActor)
    Int count = CandidatePoolCount()
    Int i = 0
    while i < count
        ReferenceAlias a = CandidatePool.GetAlias(i) as ReferenceAlias
        if a && a.GetReference() == akActor
            return i
        endIf
        i += 1
    endwhile
    return -1
EndFunction

; On its spot's marker, kept near it by the vanilla sandbox package the worker
; also uses (DefaultSandboxCurrentLocation1024, 0x000BFB6B), profession from
; the spot, tier rolled, arrival stamped, the ranks the dialogue reads set.
Function _SetupCandidate(ReferenceAlias akAlias, Actor akCandidate, Int aiSlot)
    ObjectReference marker = SlotMarker(aiSlot)
    if marker
        akCandidate.MoveTo(marker)
    endIf
    ActorUtil.AddPackageOverride(akCandidate, Game.GetFormFromFile(0x000BFB6B, "Skyrim.esm") as Package, 30, 0)
    if !StorageUtil.HasStringValue(akCandidate, "WOSK_Profession")
        string prof = SlotProfession(aiSlot)
        if prof == "" && IsExtraSlot(aiSlot)
            ; D218: an extra's profession is rolled at each arrival and stays on
            ; the candidate; nothing else derives it from the slot.
            prof = RollExtraProfession()
        endIf
        if prof != ""
            StorageUtil.SetStringValue(akCandidate, "WOSK_Profession", prof)
        endIf
    endIf
    string tier = EnsureCandidateTier(akCandidate)
    StorageUtil.SetFormValue(akCandidate, "WOSK_CandidateMarker", marker)
    StorageUtil.SetStringValue(akCandidate, "WOSK_CandidatePlace", PlaceOfMarker(marker))
    if !StorageUtil.HasFloatValue(akCandidate, "WOSK_CandidateArrived")
        StorageUtil.SetFloatValue(akCandidate, "WOSK_CandidateArrived", Utility.GetCurrentGameTime())
    endIf
    _SetCandidateFactions(akCandidate)
    StorageUtil.SetIntValue(akCandidate, "WOSK_CandidatePlaced", 1)
    ; Fase 27 (D232): a new arrival is hidden from the Recruit tab until the
    ; player talks to the recruiter or to him.
    if !StorageUtil.HasIntValue(akCandidate, "WOSK_CandidateRevealed")
        StorageUtil.SetIntValue(akCandidate, "WOSK_CandidateRevealed", 0)
    endIf
    ; Fase 33 etapa 2 (D265, V065): sex, base and trade of every candidate, on the one line
    ; the log has per candidate - the round-9 question "always a woman / always a man by
    ; trade" was answered by counting 21 of them by hand.
    Debug.Trace("WOSK_Controller: candidate " + akCandidate + " spot " + aiSlot + " (" + EnsureCandidateProfession(akCandidate) + ", " + tier + \
                ") placed at " + marker + " '" + StorageUtil.GetStringValue(akCandidate, "WOSK_CandidatePlace", "") + "' " + WOSK_Outfits.BaseAndSex(akCandidate))
EndFunction

; Fase 32 (D252, D255): the bases a candidate can be, in the order of
; the development reference model CANDIDATE_BASES (test_candidate_faces.py compares
; the two). All vanilla civilians of the playable races, none templated, each with
; the FaceGen it was baked with: spawned directly, never cloned (D036). No Khajiit
; (D255). The index is a draw, 0 .. CandidateBaseCount() - 1; out of range wraps.
Int Function CandidateBaseCount() global
    return 19
EndFunction

Int Function CandidateBaseId(Int aiIndex) global
    Int[] ids = new Int[19]
    ids[0] = 0x001034E4 ; WEFarmerMale, MaleNord, nord
    ids[1] = 0x001034E6 ; WEFarmerFemale, FemaleNord, nord
    ids[2] = 0x00045804 ; TreasCorpseCommonerNordMale, MaleCommonerAccented, nord
    ids[3] = 0x000457F5 ; TreasCorpseCommonerNordFemale, FemaleCommoner, nord
    ids[4] = 0x000457F8 ; TreasCorpseCommonerImperialMale, MaleCondescending, imperial
    ids[5] = 0x00045802 ; TreasCorpseCommonerImperialFemale, FemaleCommoner, imperial
    ids[6] = 0x000457F6 ; TreasCorpseCommonerBretonMale, MaleCondescending, breton
    ids[7] = 0x000457FF ; TreasCorpseCommonerBretonFemale, FemaleCommoner, breton
    ids[8] = 0x00048117 ; TreasCorpseCommonerRedguardFemale, FemaleCommoner, redguard
    ids[9] = 0x00045800 ; TreasCorpseCommonerDarkElfM, MaleDarkElf, darkelf
    ids[10] = 0x000457F7 ; TreasCorpseCommonerDarkElfFemale, FemaleCoward, darkelf
    ids[11] = 0x00045801 ; TreasCorpseCommonerHighElfMale, MaleElfHaughty, highelf
    ids[12] = 0x000457F9 ; TreasCorpseCommonerHighElfFemale, FemaleEvenToned, highelf
    ids[13] = 0x000457FC ; TreasCorpseCommonerWoodElfMale, MaleEvenToned, woodelf
    ids[14] = 0x00045805 ; TreasCorpseCommonerWoodElfFemale, FemaleElfHaughty, woodelf
    ids[15] = 0x000457FD ; TreasCorpseCommonerOrcMale, MaleOrc, orc
    ids[16] = 0x00045806 ; TreasCorpseCommonerOrcFemale, FemaleOrc, orc
    ids[17] = 0x000457FE ; TreasCorpseCommonerArgonianMale, MaleArgonian, argonian
    ids[18] = 0x000457FB ; TreasCorpseCommonerArgonianFemale, FemaleArgonian, argonian
    Int idx = aiIndex
    if idx < 0
        idx = -idx
    endIf
    return ids[idx % 19]
EndFunction

; The race key of a base (the same table, the same order), the key the pool JSON uses:
; raceWeight_<key>. Nine races, 0 .. 8.
string Function CandidateBaseRace(Int aiIndex) global
    string[] keys = new string[19]
    keys[0] = "nord"
    keys[1] = "nord"
    keys[2] = "nord"
    keys[3] = "nord"
    keys[4] = "imperial"
    keys[5] = "imperial"
    keys[6] = "breton"
    keys[7] = "breton"
    keys[8] = "redguard"
    keys[9] = "darkelf"
    keys[10] = "darkelf"
    keys[11] = "highelf"
    keys[12] = "highelf"
    keys[13] = "woodelf"
    keys[14] = "woodelf"
    keys[15] = "orc"
    keys[16] = "orc"
    keys[17] = "argonian"
    keys[18] = "argonian"
    Int idx = aiIndex
    if idx < 0
        idx = -idx
    endIf
    return keys[idx % 19]
EndFunction

string Function RaceKey(Int aiRace) global
    if aiRace == 0
        return "nord"
    elseIf aiRace == 1
        return "imperial"
    elseIf aiRace == 2
        return "breton"
    elseIf aiRace == 3
        return "redguard"
    elseIf aiRace == 4
        return "darkelf"
    elseIf aiRace == 5
        return "highelf"
    elseIf aiRace == 6
        return "woodelf"
    elseIf aiRace == 7
        return "orc"
    endIf
    return "argonian"
EndFunction

; Where the bases of a race sit in the table above (the table keeps a race together,
; test_candidate_faces.py checks it): the first index and how many, by RaceKey order.
Int Function RaceBaseStart(Int aiRace) global
    Int[] s = new Int[9]
    s[0] = 0
    s[1] = 4
    s[2] = 6
    s[3] = 8
    s[4] = 9
    s[5] = 11
    s[6] = 13
    s[7] = 15
    s[8] = 17
    return s[aiRace]
EndFunction

Int Function RaceBaseSpan(Int aiRace) global
    Int[] n = new Int[9]
    n[0] = 4
    n[1] = 2
    n[2] = 2
    n[3] = 1
    n[4] = 2
    n[5] = 2
    n[6] = 2
    n[7] = 2
    n[8] = 2
    return n[aiRace]
EndFunction

; D255: how likely a race is among the candidates of a hold - data the maintainer tunes,
; flat fields of the hold's pool (candidate_pools/*.json): "raceWeight_<race>", and
; "raceWeightMiner_<race>" for a miner. The hold's own field, else the "Default"
; hold's, else 0; a miner's field wins over the plain one. Mirrors
; professions_loader.race_weight (test_race_weights.py).
Float Function RaceWeight(string asHold, string asRace, Bool abMiner) global
    Float w = WOSK_Registry.GetCandidatePoolFloat(asHold, "raceWeight_" + asRace, -1.0)
    if w < 0.0
        w = WOSK_Registry.GetCandidatePoolFloat("Default", "raceWeight_" + asRace, 0.0)
    endIf
    if abMiner
        Float m = WOSK_Registry.GetCandidatePoolFloat(asHold, "raceWeightMiner_" + asRace, -1.0)
        if m < 0.0
            m = WOSK_Registry.GetCandidatePoolFloat("Default", "raceWeightMiner_" + asRace, -1.0)
        endIf
        if m >= 0.0
            w = m
        endIf
    endIf
    return w
EndFunction

; The draw, apart from the spawn so the harness can count it (FCE02, RAC01-RAC05):
; the race first, by the hold's weights (a miner's weights for a miner), then one of
; that race's bases, even. No weight at all (the JSON missing) is the old farmer.
Int Function DrawCandidateBaseFor(string asHold, string asProfession)
    Bool miner = asProfession == "miner"
    Float[] w = new Float[9]
    Float total = 0.0
    Int lastPositive = -1
    Int r = 0
    while r < 9
        w[r] = RaceWeight(asHold, RaceKey(r), miner)
        if w[r] > 0.0
            total += w[r]
            lastPositive = r
        endIf
        r += 1
    endwhile
    if lastPositive < 0
        Debug.Trace("WOSK_Controller: no race weight for hold '" + asHold + "' (candidate_pools JSON), drawing the old farmer")
        return 0
    endIf
    Float roll = Utility.RandomFloat(0.0, total)
    Float acc = 0.0
    Int pickedRace = -1
    r = 0
    while r < 9 && pickedRace < 0
        if w[r] > 0.0
            acc += w[r]
            if roll < acc
                pickedRace = r
            endIf
        endIf
        r += 1
    endwhile
    if pickedRace < 0
        pickedRace = lastPositive
    endIf
    Int nth = Utility.RandomInt(0, RaceBaseSpan(pickedRace) - 1)
    return RaceBaseStart(pickedRace) + nth
EndFunction

; D100 / D252 / D255: a vanilla civilian drawn from the table above by the hold's race
; weights, named by Real Names - Extended - which names actors created at run time too
; (measured, D104). The alias is what keeps the new actor persistent.
Function _SpawnCandidate(ReferenceAlias akAlias, Int aiSlot)
    ObjectReference marker = SlotMarker(aiSlot)
    if !marker
        Debug.Trace("WOSK_Controller: candidate spot " + aiSlot + " has no marker (JSON nor TargetMarker), not filled")
        return
    endIf
    ; The profession is settled BEFORE the draw (a miner draws from the miner weights);
    ; _SetupCandidate finds it on the actor and keeps it.
    string prof = SlotProfession(aiSlot)
    if prof == "" && IsExtraSlot(aiSlot)
        prof = RollExtraProfession()
    endIf
    string hold = MvpHold()
    Int pick = DrawCandidateBaseFor(hold, prof)
    Int baseId = CandidateBaseId(pick)
    ActorBase candidateBase = Game.GetFormFromFile(baseId, "Skyrim.esm") as ActorBase
    if !candidateBase
        ; The table is Skyrim.esm; this is a damaged install. The old farmer keeps the spot filled.
        Debug.Trace("WOSK_Controller: candidate base " + baseId + " does not resolve, falling back to WEFarmerMale")
        candidateBase = Game.GetFormFromFile(0x001034E4, "Skyrim.esm") as ActorBase
    endIf
    Actor spawned = marker.PlaceActorAtMe(candidateBase)
    if prof != "" && !StorageUtil.HasStringValue(spawned, "WOSK_Profession")
        StorageUtil.SetStringValue(spawned, "WOSK_Profession", prof)
    endIf
    Debug.Trace("WOSK_Controller: candidate spot " + aiSlot + " (" + prof + ") in " + hold + " drawn base " + pick + " " + CandidateBaseRace(pick) + " " + candidateBase)
    akAlias.ForceRefTo(spawned)
    _SetupCandidate(akAlias, spawned, aiSlot)
EndFunction

; D165: the candidate's dialogue reads profession and tier as ranks in two
; hidden factions (WOSK_CandidateProfessionFaction 0x01000825,
; WOSK_CandidateTierFaction 0x01000826). The rank order is the generator's
; (build_plugin.py CANDIDATE_PROFESSION_RANKS / CANDIDATE_TIER_RANKS).
Int Function ProfessionRank(string asProfession)
    if asProfession == "cook"
        return 0
    elseIf asProfession == "fisher"
        return 1
    elseIf asProfession == "herbalist"
        return 2
    elseIf asProfession == "hunter"
        return 3
    elseIf asProfession == "laborer"
        return 4
    elseIf asProfession == "miner"
        return 5
    endIf
    return -1
EndFunction

Int Function TierRank(string asTier)
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

Function _SetCandidateFactions(Actor akCandidate)
    Faction profFaction = Game.GetFormFromFile(0x00000825, "HonestWork.esp") as Faction
    Faction tierFaction = Game.GetFormFromFile(0x00000826, "HonestWork.esp") as Faction
    if !profFaction || !tierFaction
        Debug.Trace("WOSK_Controller: candidate factions missing (prof=" + profFaction + ", tier=" + tierFaction + ")")
        return
    endIf
    Int profRank = ProfessionRank(EnsureCandidateProfession(akCandidate))
    if profRank >= 0
        akCandidate.SetFactionRank(profFaction, profRank)
    else
        akCandidate.RemoveFromFaction(profFaction)
    endIf
    Int tierRank = TierRank(EnsureCandidateTier(akCandidate))
    if tierRank >= 0
        akCandidate.SetFactionRank(tierFaction, tierRank)
    endIf
EndFunction

Function _ClearCandidateFactions(Actor akCandidate)
    Faction profFaction = Game.GetFormFromFile(0x00000825, "HonestWork.esp") as Faction
    Faction tierFaction = Game.GetFormFromFile(0x00000826, "HonestWork.esp") as Faction
    if profFaction
        akCandidate.RemoveFromFaction(profFaction)
    endIf
    if tierFaction
        akCandidate.RemoveFromFaction(tierFaction)
    endIf
EndFunction

; ---------------------------------------------------------------------------
; Recruit tab (D104 etapa 3) - Papyrus builds the list and
; WOSK_Panel draws it.
; ---------------------------------------------------------------------------

; D184 (maintainer decision 2026-10-26): the Recruit tab shows the pool however
; the panel was opened, but hires only when the panel open NOW came from the
; recruiter's dialogue (OpenRecruitPanel). Kept on this quest, so a save made
; with the panel open keeps it; cleared by every other way the panel opens
; (hotkey: WOSK_PanelOpened; worker dialogue: OpenWorkerPanel) and when the
; panel closes (WOSK_PanelClosed, sent by the DLL).
Bool _recruiterPanel = false

Bool Function RecruiterPanelOpen()
    return _recruiterPanel
EndFunction

; The Papyrus half of the recruiter's path: the sign, then the list carrying it.
; OpenRecruitPanel adds the panel itself; the harness calls this alone, so an
; unattended run never takes the screen's focus.
Function BeginRecruiterPanel()
    _recruiterPanel = true
    Debug.Trace("WOSK_Controller: recruiter panel sign set (Recruit tab can hire)")
    RefreshRecruitList("")
EndFunction

; The panel was opened by its hotkey (WOSK_PanelOpened). The Recruit tab is
; drawn too, without the sign: the page shows the pool and keeps Hire off.
Function OnPanelOpenedByKey()
    _ClearRecruiterPanel("opened by hotkey")
    EnsureWorkersHome("panel")
    RefreshRecruitList("")
EndFunction

; The panel closed (WOSK_PanelClosed): whatever opens it next starts without
; the sign.
Function OnPanelClosed()
    _ClearRecruiterPanel("panel closed")
EndFunction

Function _ClearRecruiterPanel(string asWhy)
    if _recruiterPanel
        Debug.Trace("WOSK_Controller: recruiter panel sign cleared (" + asWhy + ")")
    endIf
    _recruiterPanel = false
EndFunction

; Sends the candidates standing in the tavern to the panel, with asMessage
; under the list. Returns how many were sent.
Int Function RefreshRecruitList(string asMessage)
    ; Fase 24: the last line the Recruit tab was given, for the harness (HSE03).
    StorageUtil.SetStringValue(None, "WOSK_LastRecruitMessage", asMessage)
    ; D218: ten spots (six fixed, four extras) - the pool's alias count.
    string[] names = new string[10]
    string[] professions = new string[10]
    string[] tiers = new string[10]
    Int[] prices = new Int[10]
    Int[] spots = new Int[10]
    string[] places = new string[10]
    string[] blockedBy = new string[10]
    Int poolCount = CandidatePoolCount()
    Int count = 0
    Int i = 0
    while i < poolCount
        ReferenceAlias a = CandidatePool.GetAlias(i) as ReferenceAlias
        Actor candidate = None
        if a
            candidate = a.GetActorRef()
        endIf
        ; Fase 27 (D232): the tab lists only the candidates the player has found.
        if candidate && IsCandidateRevealed(candidate)
            names[count] = CandidateShownName(candidate)
            professions[count] = EnsureCandidateProfession(candidate)
            ; The panel gets the LABEL, not the id. Nothing on the page reads
            ; the tier back - it only prints it (App.tsx, the Recruit row) - and
            ; sending the label here keeps the naming in one file instead of
            ; forking it between Papyrus and the front-end.
            tiers[count] = WOSK_Names.TierLabel(EnsureCandidateTier(candidate))
            prices[count] = GetHirePrice(candidate)
            spots[count] = i
            places[count] = StorageUtil.GetStringValue(candidate, "WOSK_CandidatePlace", "")
            blockedBy[count] = HireBlockReason(professions[count])
            count += 1
        endIf
        i += 1
    endwhile
    ; D184: aiCanHire (0/1, an Int like SetWorkerList's aiCanIssue) is the
    ; recruiter sign; without it the page keeps the Hire button off.
    Int canHire = 0
    if _recruiterPanel
        canHire = 1
    endIf
    ; Fase 27 (D232): the line under the list speaks of the revealed ones. With
    ; none revealed it says how to find some, unless a caller already said
    ; something.
    string shownLine = asMessage
    if count == 0 && shownLine == ""
        shownLine = "Nobody has been found yet. Talk to the Hiring Agent, or to the people looking for work around the hold."
    endIf
    WOSK_Panel.SetRecruitList(names, professions, tiers, prices, spots, places, count, GetWorkerCount(0), GetHireCap(0), canHire, shownLine, blockedBy)
    ; Fase 34 etapa 2 (D299): the followers section of the same tab.
    RefreshFollowerList("")
    return count
EndFunction

; ---------------------------------------------------------------------------
; Fase 27 (D232) - the Recruit tab lists only the candidates the player has
; found: by talking to the recruiter (every candidate in the pool at that
; moment) or to the candidate himself. A new arrival is hidden. Key on the
; candidate: StorageUtil int "WOSK_CandidateRevealed" (1 revealed, 0 hidden).
; ---------------------------------------------------------------------------

; A candidate with no key is one an older save placed (Refill stamps it 1 at its
; next run); counted as revealed here too, so the list is right even before it.
Bool Function IsCandidateRevealed(Actor akCandidate)
    if !akCandidate
        return false
    endIf
    if StorageUtil.HasIntValue(akCandidate, "WOSK_CandidateRevealed")
        return StorageUtil.GetIntValue(akCandidate, "WOSK_CandidateRevealed", 0) == 1
    endIf
    return StorageUtil.HasIntValue(akCandidate, "WOSK_CandidatePlaced")
EndFunction

; Returns true when this call is what revealed him.
Bool Function RevealCandidate(Actor akCandidate, string asWhy)
    if !akCandidate || IsCandidateRevealed(akCandidate)
        return false
    endIf
    StorageUtil.SetIntValue(akCandidate, "WOSK_CandidateRevealed", 1)
    Debug.Trace("WOSK_Controller: candidate " + akCandidate + " revealed (" + asWhy + "), name '" + CandidateShownName(akCandidate) + "'")
    return true
EndFunction

; The recruiter's word: every candidate standing in the pool now. Returns how
; many it revealed.
Int Function RevealAllCandidates(string asWhy)
    Int revealed = 0
    Int count = CandidatePoolCount()
    Int i = 0
    while i < count
        ReferenceAlias a = CandidatePool.GetAlias(i) as ReferenceAlias
        if a
            if RevealCandidate(a.GetActorRef(), asWhy)
                revealed += 1
            endIf
        endIf
        i += 1
    endWhile
    return revealed
EndFunction

; The candidate dialogue's reveal (WOSK_CandidateAliasScript.OnActivate): the
; pool holds the actor, the actor is the speaker.
Function OnCandidateSpokenTo(Actor akCandidate)
    if RevealCandidate(akCandidate, "player spoke to him")
        RefreshRecruitList("")
    endIf
EndFunction

; Fase 27 conserto 1 (D235): every candidate the player is told about has a
; name, near or far. Real Names - Extended names only an actor that has been
; loaded near the player; until then GetDisplayName() is the base's "Farmer"
; (V016, 2026-09-13; V059, the herbalist revealed from Arcadia's Cauldron).
; This gives the name, once, and keeps it:
;   1. a name already on the actor (Real Names, or this function earlier) stays;
;   2. a name stored on him (RNE_Name, the key Real Names reads and writes, or
;      WOSK_CandidateName) is put back - a display name lost on a load;
;   3. otherwise the next given name of WOSK_Names, by his sex, is stored in
;      BOTH keys and set. Real Names, when it reaches him later, finds RNE_Name
;      and applies that same name (RealNamesChange.psc: HasStringValue ->
;      GetStringValue -> SetDisplayName), so what the player saw does not change.
; Works without Real Names: the keys are only read, never required.
string Function EnsureCandidateName(Actor akCandidate)
    if !akCandidate
        return ""
    endIf
    ActorBase base = akCandidate.GetActorBase()
    ; Fase 31 (D251, V062): only a name THIS function gave is kept. A name Real Names -
    ; Extended put on the actor first is not trusted: it came from a list of its own,
    ; and the maintainer met a repeat in one list and a woman's name on a man's body. Ours
    ; is picked by the actor's sex from a running counter, so ten candidates in a row
    ; never repeat, and it is stored in RNE_Name too, where Real Names finds and applies it.
    string stored = StorageUtil.GetStringValue(akCandidate, "WOSK_CandidateName", "")
    string how = "restored"
    ; Fase 31 conserto 1 (D258, V063): the list asks for the name of every candidate at
    ; each refresh; one that already wears his name needs no SetDisplayName and no trace.
    if stored != "" && akCandidate.GetDisplayName() == stored && WOSK_Names.NameReads(stored)
        return stored
    endIf
    ; Fase 33 etapa 1 (D261): a stored name that reads wrong (lowercase first letter, the
    ; "asA" of round 8) is dropped and the candidate gets the next one that reads right.
    if stored != "" && !WOSK_Names.NameReads(stored)
        Debug.Trace("WOSK_Controller: candidate " + akCandidate + " stored name '" + stored + "' does not read as a name, renaming")
        stored = ""
    endIf
    if stored == ""
        Int n = 0
        if StorageUtil.HasIntValue(None, "WOSK_CandidateNameCounter")
            n = StorageUtil.GetIntValue(None, "WOSK_CandidateNameCounter", 0)
        else
            n = Utility.RandomInt(0, WOSK_Names.CandidateNameCount() - 1)
        endIf
        Int tries = 0
        stored = WOSK_Names.CandidateGivenName(base.GetSex(), n)
        while !WOSK_Names.NameReads(stored) && tries < WOSK_Names.CandidateNameCount()
            Debug.Trace("WOSK_Controller: given name '" + stored + "' does not read as a name (interned in another spelling), next one")
            n += 1
            tries += 1
            stored = WOSK_Names.CandidateGivenName(base.GetSex(), n)
        endWhile
        StorageUtil.SetIntValue(None, "WOSK_CandidateNameCounter", n + 1)
        StorageUtil.SetStringValue(akCandidate, "RNE_Name", stored)
        how = "given"
    endIf
    StorageUtil.SetStringValue(akCandidate, "WOSK_CandidateName", stored)
    akCandidate.SetDisplayName(stored, true)
    Debug.Trace("WOSK_Controller: candidate " + akCandidate + " named '" + stored + "' (" + how + ", sex=" + base.GetSex() + ", base=" + base + ")")
    return stored
EndFunction

; The name the list shows.
string Function CandidateShownName(Actor akCandidate)
    string shown = EnsureCandidateName(akCandidate)
    if shown == "" || shown == akCandidate.GetActorBase().GetName()
        string prof = EnsureCandidateProfession(akCandidate)
        if prof == ""
            prof = "worker"
        endIf
        return "Unnamed " + prof
    endIf
    return shown
EndFunction

; The recruiter's dialogue (etapa 4) calls this: the list, then the panel.
; D104 etapa 4: the Hiring Agent keeps its name. The NPC is unique in the
; record, but it takes its looks from a template whose chain ends in a leveled
; list, and in game both GetActorBase().IsUnique() and
; GetLeveledActorBase().IsUnique() read False (harness 2026-09-14). Real Names
; skips a non-unique actor whose base is on its RealNamesNonUniqueNoRename
; list (RealNamesChange.psc:54-58), so the agent goes on that list.
; Fase 33 etapa 9 (E4, V072): without the plugin there is nothing to keep, and asking
; GetFormFromFile for a plugin that is not loaded writes an error line in the Papyrus log.
; The same three asks as WOSK_Backpack.PluginLoaded (IsPluginInstalled, light index, full
; index) go first; without Real Names one line goes to the trace and the function leaves.
Bool Function RealNamesLoaded() global
    string plugin = "RealNamesExtended.esp"
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

Bool Function KeepHiringAgentName()
    if !RealNamesLoaded()
        Debug.Trace("WOSK_Controller: KeepHiringAgentName - RealNamesExtended.esp is not loaded, nothing to keep")
        return false
    endIf
    FormList noRename = Game.GetFormFromFile(0x00000CD7, "RealNamesExtended.esp") as FormList
    ActorBase agentBase = Game.GetFormFromFile(0x00000817, "HonestWork.esp") as ActorBase
    if !noRename || !agentBase
        Debug.Trace("WOSK_Controller: KeepHiringAgentName - list or agent missing (list=" + noRename + ", agent=" + agentBase + ")")
        return false
    endIf
    if noRename.Find(agentBase) < 0
        noRename.AddForm(agentBase)
        Debug.Trace("WOSK_Controller: Hiring Agent " + agentBase + " added to RealNamesNonUniqueNoRename")
    endIf
    RestoreHiringAgentName(agentBase)
    return noRename.Find(agentBase) >= 0
EndFunction

; Fase 18 conserto (D190): in a game where the mod never ran, Real Names names the
; agent when it first loads, before the list above has the agent (V048: the name
; picked 2 s before "added to RealNamesNonUniqueNoRename"). Being on the list
; later does not undo a name: Real Names keeps it in StorageUtil "RNE_Name" and
; on the reference's display name. So the name is given back and the key
; cleared; with the agent on the list Real Names does not name it again.
; Without Real Names the key is never set and nothing happens here.
Function RestoreHiringAgentName(ActorBase akAgentBase)
    Actor agent = Game.GetFormFromFile(0x00000818, "HonestWork.esp") as Actor
    if !agent || !StorageUtil.HasStringValue(agent, "RNE_Name")
        return
    endIf
    string renamed = StorageUtil.GetStringValue(agent, "RNE_Name", "")
    StorageUtil.UnsetStringValue(agent, "RNE_Name")
    agent.SetDisplayName(akAgentBase.GetName(), true)
    ; What the mod undid, kept for the harness (RCT-AGENTE prints it).
    StorageUtil.SetStringValue(agent, "WOSK_AgentNameGivenBack", renamed)
    Debug.Trace("WOSK_Controller: Hiring Agent name '" + renamed + "' given back to '" + akAgentBase.GetName() + "'")
EndFunction

Function OpenRecruitPanel()
    ; Fase 31 conserto 1 (D258, V063): the panel opens FIRST and the data follows. A
    ; test measured 1-3 s from the end of the line to the panel; the lists below are
    ; what took it. The page already takes a list that arrives after it is up.
    Float t0 = Utility.GetCurrentRealTime()
    WOSK_Panel.OpenRecruit()
    Float tOpen = Utility.GetCurrentRealTime() - t0
    ; Fase 33 etapa 2 (D266): talking to the recruiter shows the pool as of now - the
    ; candidates whose week is up and whom the player does not see are replaced first.
    RefillCandidatePool()
    EnsureWorkersHome("panel")
    ; Fase 27 (D232): the recruiter's word reveals every candidate in the pool
    ; now. ASSUMPTION: "talk to the Hiring Agent" means all of them (F27).
    Int revealed = RevealAllCandidates("recruiter dialogue")
    Debug.Trace("WOSK_Controller: recruiter dialogue revealed " + revealed + " candidate(s)")
    BeginRecruiterPanel()
    ; Queue item 11: this path opens the panel from Papyrus and never reaches
    ; TogglePanel(), which is where the DLL asks for the list - so it asks here.
    RefreshWorkerList()
    ; Fase 33 etapa 10 (F4, V073): the source list also carries the hold the Contracts tab
    ; names. This path never sent it, so a worker hired from here was "THE HOLD" until the
    ; first contract change pushed it (boot 085043: Una and Aslaug). It follows the worker list.
    RefreshSourceList()
    ; Fase 33 etapa 2 (D267): the house a new cook moves into, for the Recruit tab.
    PushHouse(None, -1)
    Debug.Trace("WOSK_Controller: OpenRecruitPanel open-call " + tOpen + " s, data done " + (Utility.GetCurrentRealTime() - t0) + " s")
EndFunction

Function OpenWorkerPanel(Actor akSpeaker)
    ; Fase 10 A: the worker dialogue opens the panel filtered to that speaker.
    ; Fase 26 (D228): the page is also told WHICH worker and WHICH tab - the
    ; panel used to open on the Overview with the first worker selected. The
    ; word crosses as an outcome with action "focus" (no native added); the
    ; page selects the slot and shows the Contracts tab, and says nothing.
    ; D184: the worker is not the recruiter - the Recruit tab only shows.
    _ClearRecruiterPanel("opened by worker dialogue")
    ; Fase 31 conserto 1 (D258, V063): open first, then push in the order the page needs
    ; it: the workers, the focus, the recruit list, and last the source list - the
    ; heaviest (every task of every trade), which only the Contracts tab reads.
    Float t0 = Utility.GetCurrentRealTime()
    WOSK_Panel.OpenRecruit()
    Float tOpen = Utility.GetCurrentRealTime() - t0
    Int idx = WorkerSlotOf(akSpeaker)
    EnsureWorkersHome("panel")
    RefreshWorkerList()
    RefreshHistory()
    if idx >= 0
        WOSK_PanelBridgeScript.ReportOutcome("focus", idx, "CONTRACTS", "", 0)
    endIf
    Float tWorkers = Utility.GetCurrentRealTime() - t0
    RefreshRecruitList("")
    RefreshSourceList()
    Debug.Trace("WOSK_Controller: OpenWorkerPanel speaker=" + akSpeaker + " slot=" + idx + " open-call " + tOpen + " s, workers " + tWorkers + " s, all data " + (Utility.GetCurrentRealTime() - t0) + " s")
EndFunction

; Fase 26 (D228): the slot holding akWorker, or -1 when he is not a hired worker.
Int Function WorkerSlotOf(Actor akWorker)
    if !akWorker
        return -1
    endIf
    Int i = 0
    while i < WorkerPoolSize
        ReferenceAlias a = WorkerPool.GetAlias(i) as ReferenceAlias
        if a && a.GetActorRef() == akWorker
            return i
        endIf
        i += 1
    endwhile
    return -1
EndFunction

; Fase 26 (D228): "I want to collect the resources" - the batch goes to the
; player when the worker is waiting with it. When he is not, PickUp itself says
; why in a corner message and to the panel (still on the way, still working,
; nothing to collect), so the answer is never silent.
Function CollectWorkerByActor(Actor akSpeaker)
    Int idx = WorkerSlotOf(akSpeaker)
    if idx < 0
        Debug.Trace("WOSK_Controller: CollectWorkerByActor - speaker not a hired worker: " + akSpeaker)
        Debug.Notification("Honest Work: nobody is hired in that place.")
        return
    endIf
    Debug.Trace("WOSK_Controller: CollectWorkerByActor slot " + idx + " via dialogue")
    (WorkerPool.GetAlias(idx) as WOSK_WorkerAliasScript).PickUp()
EndFunction

; Fase 30 (D240): "I want to give you some equipment" - the gift menu of the hunter
; who is talking to the player (so he is near by definition); WOSK_Gear decides what
; stays. A worker who is not a hunter is told so, never ignored.
Function GiveGearByActor(Actor akSpeaker)
    Int idx = WorkerSlotOf(akSpeaker)
    if idx < 0
        Debug.Trace("WOSK_Controller: GiveGearByActor - speaker not a hired worker: " + akSpeaker)
        Debug.Notification("Honest Work: nobody is hired in that place.")
        return
    endIf
    Debug.Trace("WOSK_Controller: GiveGearByActor slot " + idx + " via dialogue")
    WOSK_Gear.GiveToWorker(akSpeaker)
EndFunction

; D149 (Fase 12, V029 p.3): housecarl discovery. Whiterun only (MVP): Lydia
; NPC_ 0x000A2C8E, ACHR HousecarlWhiterunRef 0x000A2C94, quest Favor253
; 0x000A2C9E (BYOHHouseBuilding only handles DLC housecarls). Cheapest:
; direct Form lookup + alive check. No faction or BYOH alias needed for
; hold 0. IsThane already covers the title requirement.
Actor Function GetHousecarlForHold(Int aiHoldID)
    if aiHoldID != 0
        return None
    endIf
    Actor housecarl = Game.GetFormFromFile(0x000A2C94, "Skyrim.esm") as Actor
    if !housecarl
        housecarl = Game.GetFormFromFile(0x000A2C8E, "Skyrim.esm") as Actor
    endIf
    if housecarl && !housecarl.IsDead() && !housecarl.IsDisabled()
        return housecarl
    endIf
    return None
EndFunction

; D149 (Fase 12, V029 p.4): collect via housecarl. Checks Thane + housecarl
; alive, then delegates to WOSK_WorkerAliasScript._PickUpTo(housecarl).
; Logs housecarl FormID before AddItem. Refuses with message if no thane
; or no housecarl. Only called from dialogue (worker or housecarl branch).
Bool Function RequestCollectViaHousecarl(Int aiAliasIndex)
    if !IsThane(0)
        Debug.Trace("WOSK_Controller: RequestCollectViaHousecarl refused - not Thane of Whiterun")
        Debug.Notification("Honest Work: You must be Thane of Whiterun to use the housecarl.")
        return false
    endIf
    Actor housecarl = GetHousecarlForHold(0)
    if !housecarl
        Debug.Trace("WOSK_Controller: RequestCollectViaHousecarl refused - housecarl not available (dead/disabled)")
        Debug.Notification("Honest Work: Your housecarl is not available.")
        return false
    endIf
    ; Fase 34 etapa 2 (P4): the housecarl himself does not go to collect when he is a worker.
    if WOSK_Followers.IsFollower(housecarl)
        Debug.Trace("WOSK_Controller: RequestCollectViaHousecarl refused - the housecarl works for the player")
        Debug.Notification("Honest Work: Your housecarl works for you; he cannot fetch the batch.")
        return false
    endIf
    ReferenceAlias a = WorkerPool.GetAlias(aiAliasIndex) as ReferenceAlias
    if !a
        Debug.Trace("WOSK_Controller: RequestCollectViaHousecarl refused - alias " + aiAliasIndex + " empty")
        return false
    endIf
    WOSK_WorkerAliasScript w = a as WOSK_WorkerAliasScript
    if !w
        return false
    endIf
    Debug.Trace("WOSK_Controller: RequestCollectViaHousecarl slot " + aiAliasIndex + " housecarl=" + housecarl + " formID=" + housecarl.GetFormID())
    return w.CollectViaHousecarl(housecarl)
EndFunction

; Fase 11 B: dismiss by dialogue - finds the alias holding akSpeaker and calls Fire()
; directly (any state). Dialogue is the personal channel that always works.
Function FireWorkerByActor(Actor akSpeaker)
    if !akSpeaker
        Debug.Trace("WOSK_Controller: FireWorkerByActor - no speaker")
        return
    endIf
    Int i = 0
    while i < WorkerPoolSize
        ReferenceAlias a = WorkerPool.GetAlias(i) as ReferenceAlias
        if a && a.GetActorRef() == akSpeaker
            Debug.Trace("WOSK_Controller: FireWorkerByActor slot " + i + " via dialogue")
            ; Fase 31 (D248): the dismissal fee is charged here too.
            (a as WOSK_WorkerAliasScript).FireForFee()
            return
        endIf
        i += 1
    endwhile
    Debug.Trace("WOSK_Controller: FireWorkerByActor - speaker not a hired worker: " + akSpeaker)
EndFunction

; The Recruit tab's hire button (mod event WOSK_RequestHire, spot in numArg).
; Answers the panel with the refreshed list and what happened.
Int Function HireFromPool(Int aiSpot)
    ; D184: only a panel opened by the recruiter hires. Refused before anything
    ; else is read, so no gold moves and no slot is taken.
    if !_recruiterPanel
        Debug.Trace("WOSK_Controller: HireFromPool(" + aiSpot + ") refused - panel not opened by the recruiter (" + GetWorkerCount(0) + " hired, cap " + GetHireCap(0) + ")")
        WOSK_PanelBridgeScript.ReportOutcome("hire", aiSpot, "NOT_RECRUITER", "", 0)
        RefreshRecruitList("Talk to the Hiring Agent to hire.")
        return -1
    endIf
    Actor candidate = None
    if aiSpot >= 0 && aiSpot < CandidatePoolCount()
        candidate = (CandidatePool.GetAlias(aiSpot) as ReferenceAlias).GetActorRef()
    endIf
    Int slot = -1
    string outcome = ""
    if !candidate
        outcome = "That candidate is no longer available."
    else
        string name = CandidateShownName(candidate)
        Int price = GetHirePrice(candidate)
        Int cap = GetHireCap(0)
        if GetWorkerCount(0) >= cap
            outcome = "You already employ " + cap + " worker(s) in this hold."
        elseIf HireBlockReason(EnsureCandidateProfession(candidate)) != ""
            ; Fase 33 etapa 10: one cook per hold.
            outcome = "You already employ a cook in this hold."
        elseIf WOSK_PlayerHouse.RequiresHouse(EnsureCandidateProfession(candidate)) && WOSK_PlayerHouse.OwnedHouse() == ""
            ; Fase 24 (D223): said on the Recruit tab, where the button was pressed.
            outcome = WOSK_PlayerHouse.NeedsHouseText(name)
        elseIf Game.GetPlayer().GetItemCount(Game.GetFormFromFile(0x0000000F, "Skyrim.esm")) < price
            outcome = "Not enough gold: hiring " + name + " costs " + price + "."
        else
            slot = HireCandidate(candidate)
            if slot >= 0
                outcome = name + " hired for " + price + " gold."
            else
                outcome = "Could not hire " + name + "."
            endIf
        endIf
    endIf
    Debug.Trace("WOSK_Controller: HireFromPool(" + aiSpot + ") -> slot " + slot + ": " + outcome)
    RefreshRecruitList(outcome)
    return slot
EndFunction

; D104: a dismissed or retired worker leaves the game. A placed reference can
; only be disabled; one created at run time (FormID 0xFF000000-0xFFFFFFFF,
; negative as a Papyrus Int) is deleted too.
; 2026-09-21 (Parte 2, CTD ao demitir): aiFormId comes in from the caller, read
; while the alias still held the reference. Reading it here failed with "no
; native object bound" once the alias had been cleared - the delete branch was
; skipped and the engine crashed on the half-torn-down actor. The caller must
; still run this BEFORE Clear(); the parameter only removes the second way to
; get it wrong.
; 2026-09-21 (Part 3): the sentence that used to sit here - "DeleteWhenAble
; waits for the reference to stop persisting" - was copied from the vanilla
; docstring and is WRONG. Its body waits for GetParentCell().IsAttached() to
; go false, which is a different condition, and with the player in the same
; cell it never does. Deletion now goes to the queue SweepPendingDeletes
; drains.
Function SendAway(Actor akWorker, Int aiFormId = 0)
    if !akWorker
        return
    endIf
    Int formId = aiFormId
    if formId == 0
        formId = akWorker.GetFormID()
    endIf
    ; Fase 27 (D232): whoever leaves the game gives the trade's outfit back first
    ; (silent for an actor that never wore one: a rotated candidate).
    WOSK_Outfits.Restore(akWorker)
    WOSK_WorkerState.Clear(akWorker)
    ActorUtil.ClearPackageOverride(akWorker)
    if WOSK_Followers.IsFollower(akWorker)
        ; Fase 34 etapa 4 (A4, D306): a follower is a unique NPC of the game; he is released
        ; (packages, link, marks - WOSK_Followers.ReleaseFollower), never disabled nor queued
        ; for deletion. This is the only way out, for the panel and the dialogue alike.
        WOSK_Followers.ReleaseFollower(akWorker)
        Debug.Trace("WOSK_Controller: follower " + akWorker + " released, not disabled")
        return
    endIf
    akWorker.Disable()
    if formId < 0 && formId >= -16777216
        ; allowDuplicate=false: the default is true, so without it a worker
        ; dismissed twice would be queued twice.
        StorageUtil.FormListAdd(Self, PENDING_DELETE_KEY, akWorker, false)
    endIf
    Debug.Trace("WOSK_Controller: worker formId " + formId + " sent away")
EndFunction

Bool Function RequestContract(Int aiAliasIndex, string asTaskId, Bool abConfirmOccupied = false)
    ; Fase 33 etapa 2 (D267): "house:<id>" is the cook's house order, not a task.
    if StringUtil.GetLength(asTaskId) > 6 && StringUtil.Substring(asTaskId, 0, 6) == "house:"
        return _HouseOrder(aiAliasIndex, StringUtil.Substring(asTaskId, 6))
    endIf
    ; Fase 35 etapa 4 (D313): "<taskId>|g" = the player said yes to a bodyguard. The mod event
    ; carries one string and one float; the bit rides on the string, after a bar no task id has.
    string taskId = asTaskId
    Bool guarded = false
    Int bar = StringUtil.Find(asTaskId, "|")
    if bar >= 0
        guarded = StringUtil.Substring(asTaskId, bar + 1) == "g"
        taskId = StringUtil.Substring(asTaskId, 0, bar)
    endIf
    ReferenceAlias a = WorkerPool.GetAlias(aiAliasIndex) as ReferenceAlias
    if !a
        return false
    endIf
    return (a as WOSK_WorkerAliasScript).IssueContract(taskId, "", abConfirmOccupied, guarded)
EndFunction

; Fase 35 etapa 4 (D313, B1, B2, B9, Q4): a follower of the Recruit tab becomes a bodyguard.
; One guard per slot of the hold, apart from the workers; the assignment is paid once, the
; gold is gone; the framework lets him go first, as for a worker (D298). Returns false with
; the reason in FollowerProblem.
;
; Fase 35 etapa 6 (V096): the IsGuard check below runs before the latent part (the framework's
; dismissal), so a second click arriving while the first still works passed it and charged twice.
; One assignment at a time: the second event is refused while the first is under way. The stamp is
; real time, so a stack lost mid-way (load, crash) frees itself after kGuardAssignWindow seconds.
Float _guardAssignSince = 0.0

Bool Function AssignGuard(Actor akFollower)
    Float now = Utility.GetCurrentRealTime()
    if _guardAssignSince > 0.0 && now >= _guardAssignSince && now - _guardAssignSince < 20.0
        _followerMsg = "An assignment is already under way."
        Debug.Trace("WOSK_Controller: GUARDA-DOBRO-RECUSADO " + akFollower + " - an assignment started " + (now - _guardAssignSince) + " s ago is still running")
        return false
    endIf
    _guardAssignSince = now
    Bool done = _AssignGuardWork(akFollower)
    _guardAssignSince = 0.0
    return done
EndFunction

Bool Function _AssignGuardWork(Actor akFollower)
    _followerMsg = ""
    if !akFollower
        _followerMsg = "That follower cannot be assigned."
        return false
    endIf
    string name = akFollower.GetDisplayName()
    if WOSK_Followers.IsFollower(akFollower)
        _followerMsg = name + " already works for you."
        return false
    endIf
    if WOSK_Guards.IsGuard(akFollower)
        _followerMsg = name + " is already your bodyguard."
        return false
    endIf
    string refusal = WOSK_Followers.Refusal(akFollower)
    if refusal != ""
        _followerMsg = name + " cannot be assigned (" + refusal + ")."
        Debug.Trace("WOSK_Controller: AssignGuard refused, " + akFollower + " - " + refusal)
        return false
    endIf
    if akFollower == GetHousecarlForHold(0)
        _followerMsg = name + " is the housecarl of the hold and keeps his post."
        return false
    endIf
    Int cap = GetHireCap(0)
    if WOSK_Guards.GuardCount() >= cap
        _followerMsg = "You can have only " + cap + " bodyguard(s) in this hold."
        return false
    endIf
    Int fee = WOSK_Guards.AssignFee()
    Actor player = Game.GetPlayer()
    Form goldForm = Game.GetFormFromFile(0x0000000F, "Skyrim.esm")
    if player.GetItemCount(goldForm) < fee
        _followerMsg = "You need " + fee + " gold to assign " + name + " as a bodyguard."
        return false
    endIf
    ; P9: what another mod linked him to is kept once, before the first link of ours.
    Keyword link = Game.GetFormFromFile(0x0005D5E7, "Skyrim.esm") as Keyword
    if link && !StorageUtil.HasIntValue(akFollower, WOSK_Followers.KeySavedLink())
        StorageUtil.SetFormValue(akFollower, WOSK_Followers.KeyPrevLink(), akFollower.GetLinkedRef(link))
        StorageUtil.SetIntValue(akFollower, WOSK_Followers.KeySavedLink(), 1)
    endIf
    if !WOSK_Followers.DismissFromFramework(akFollower)
        _followerMsg = name + " is still bound to his follower framework."
        Debug.Trace("WOSK_Controller: AssignGuard stopped, " + akFollower + " still a teammate after the dismissal")
        return false
    endIf
    player.RemoveItem(goldForm, fee)
    StorageUtil.SetIntValue(akFollower, WOSK_Guards.KeyGuard(), 1)
    StorageUtil.FormListAdd(None, WOSK_Guards.ListKey(), akFollower, false)
    ; P6: home is his own in Whiterun; elsewhere the inn marker, one step apart per guard.
    if WOSK_Followers.InWhiterun(akFollower)
        StorageUtil.SetIntValue(akFollower, WOSK_Followers.KeyNativeHome(), 1)
    else
        StorageUtil.UnsetIntValue(akFollower, WOSK_Followers.KeyNativeHome())
        StorageUtil.SetFloatValue(akFollower, WOSK_Followers.KeyHomeOffset(), 90.0 * (WOSK_Guards.GuardCount() + GetWorkerCount(0)))
    endIf
    WOSK_LedgerScript.RecordGuardAssigned(akFollower, fee)
    WOSK_Guards.SendToPost(akFollower, true)
    Debug.Notification("Honest Work: " + name + " is now your bodyguard (" + fee + " gold).")
    Debug.Trace("WOSK_Controller: GUARDA-ATRIBUIDO " + akFollower + " fee=" + fee + " nativeHome=" + StorageUtil.GetIntValue(akFollower, WOSK_Followers.KeyNativeHome(), 0) + " guards=" + WOSK_Guards.GuardCount() + "/" + cap)
    _followerMsg = name + " is now your bodyguard."
    return true
EndFunction

; D137: panel path for an occupied gamble - same as above but forwarded as a
; confirmed occupied call, so only the panel's explicit confirm reaches it.
Bool Function RequestOccupiedContract(Int aiAliasIndex, string asTaskId)
    return RequestContract(aiAliasIndex, asTaskId, true)
EndFunction

; Deletes the run-time actors that can be deleted right now, and GIVES UP on
; the rest instead of waiting. The condition is the same one vanilla's
; DeleteWhenAble tests - parent cell missing or detached - but here it is
; polled, not awaited: DeleteWhenAble is a Papyrus loop around Utility.Wait(5)
; that parks the calling stack, and dismissing a worker while the player is in
; the same cell never leaves that loop. Measured 2026-09-21.
;
; Walks backwards because it removes entries during the pass.
Function SweepPendingDeletes()
    Int i = StorageUtil.FormListCount(Self, PENDING_DELETE_KEY)
    Int deleted = 0
    while i > 0
        i -= 1
        Form f = StorageUtil.FormListGet(Self, PENDING_DELETE_KEY, i)
        ObjectReference ref = f as ObjectReference
        if !ref
            ; dead entry - the form went away by some other path
            StorageUtil.FormListRemove(Self, PENDING_DELETE_KEY, f, true)
        else
            Cell c = ref.GetParentCell()
            if !c || !c.IsAttached()
                ref.Delete()
                StorageUtil.FormListRemove(Self, PENDING_DELETE_KEY, f, true)
                deleted += 1
            endIf
        endIf
    endwhile
    if deleted > 0
        Debug.Trace("WOSK_Controller: sweep deleted " + deleted + " pending actor(s), " + StorageUtil.FormListCount(Self, PENDING_DELETE_KEY) + " left")
    endIf
EndFunction

Function RequestCure(Int aiAliasIndex)
    ReferenceAlias a = WorkerPool.GetAlias(aiAliasIndex) as ReferenceAlias
    if a
        (a as WOSK_WorkerAliasScript).Cure()
    endIf
EndFunction

; Fase 11 B: panel refuses dismiss in TRAVELING_TO/WORKING/TRAVELING_BACK.
Function RequestFire(Int aiAliasIndex)
    ReferenceAlias a = WorkerPool.GetAlias(aiAliasIndex) as ReferenceAlias
    if !a
        return
    endIf
    Actor worker = a.GetActorRef()
    if worker
        string contract = StorageUtil.GetStringValue(worker, "WOSK_Contract", CONTRACT_IDLE)
        if contract == CONTRACT_TRAVELING_TO || contract == CONTRACT_WORKING || contract == CONTRACT_TRAVELING_BACK
            Debug.Trace("WOSK_Controller: RequestFire refused - slot " + aiAliasIndex + " contract=" + contract + " (dismiss in person)")
            Debug.Notification("Honest Work: You must speak to this worker in person to dismiss them.")
            WOSK_PanelBridgeScript.ReportOutcome("dismiss", aiAliasIndex, "IN_PERSON", contract, 0)
            return
        endIf
    endIf
    ; Fase 31 (D248): the dismissal fee is charged; without it the worker stays.
    (a as WOSK_WorkerAliasScript).FireForFee()
EndFunction

string Property CONTRACT_TRAVELING_TO = "TRAVELING_TO" Auto Hidden
string Property CONTRACT_WORKING = "WORKING" Auto Hidden
string Property CONTRACT_TRAVELING_BACK = "TRAVELING_BACK" Auto Hidden
string Property CONTRACT_IDLE = "IDLE" Auto Hidden
string Property CONTRACT_AWAITING_PICKUP = "AWAITING_PICKUP" Auto Hidden

; ---------------------------------------------------------------------------
; Extension points (D078) - public
; surface for the HWT (or any other mod) to configure/read this project's
; state without needing HonestWork.esp as a master. No record is ever
; edited by these; everything lives in StorageUtil, same discipline as the
; rest of this project.
; ---------------------------------------------------------------------------

; 13.2 - residencia do trabalhador. aiHoldID hardcoded-valid only for 0
; (Whiterun) in the MVP - kept as a parameter now so a second hold (v1.1+)
; is additive, not a signature change. Consumed by
; WOSK_WorkerAliasScript._ReturnHomeIfConfigured().
Function SetWorkerHome(Int aiHoldID, ObjectReference akHome)
    StorageUtil.SetFormValue(Game.GetPlayer(), "WOSK_HoldHome_" + aiHoldID, akHome)
    Debug.Trace("WOSK_Controller: SetWorkerHome(hold=" + aiHoldID + ") -> " + akHome)
EndFunction

Function ResetWorkerHome(Int aiHoldID)
    StorageUtil.UnsetFormValue(Game.GetPlayer(), "WOSK_HoldHome_" + aiHoldID)
    Debug.Trace("WOSK_Controller: ResetWorkerHome(hold=" + aiHoldID + ")")
EndFunction

; 13.3 - destino da entrega. Consumed by
; WOSK_WorkerAliasScript._DeliveryTargetOr() (PickUp()/AWAITING_PICKUP timeout).
Function SetDeliveryTarget(Int aiHoldID, ObjectReference akContainer)
    StorageUtil.SetFormValue(Game.GetPlayer(), "WOSK_HoldDeliveryTarget_" + aiHoldID, akContainer)
    Debug.Trace("WOSK_Controller: SetDeliveryTarget(hold=" + aiHoldID + ") -> " + akContainer)
EndFunction

Function ResetDeliveryTarget(Int aiHoldID)
    StorageUtil.UnsetFormValue(Game.GetPlayer(), "WOSK_HoldDeliveryTarget_" + aiHoldID)
    Debug.Trace("WOSK_Controller: ResetDeliveryTarget(hold=" + aiHoldID + ")")
EndFunction

; 13.4 - API de leitura, read-only, sem efeito colateral.

; True only if akWorker currently fills one of WorkerPool's aliases - game
; state, not a StorageUtil flag, since neither WOSK_Profession nor
; WOSK_Lifecycle is written until a worker's first real event (hire/
; IssueContract respectively), so an unwritten key cannot tell "never
; contracted yet" apart from "not one of our workers at all".
Bool Function _IsHiredWorker(Actor akWorker)
    if !akWorker
        return false
    endIf
    Int i = 0
    while i < WorkerPoolSize
        ReferenceAlias a = WorkerPool.GetAlias(i) as ReferenceAlias
        if a && a.GetReference() == akWorker
            return true
        endIf
        i += 1
    endwhile
    return false
EndFunction

Int Function GetWorkerCount(Int aiHoldID)
    Int count = 0
    Int i = 0
    while i < WorkerPoolSize
        ReferenceAlias a = WorkerPool.GetAlias(i) as ReferenceAlias
        if a && a.GetReference()
            count += 1
        endIf
        i += 1
    endwhile
    return count
EndFunction

Form[] Function GetWorkers(Int aiHoldID)
    ; Papyrus array literals need a compile-time constant size - 4 mirrors
    ; the WorkerPoolSize property default (MVP pool).
    ; If WorkerPoolSize is ever changed, this literal needs updating too;
    ; not auto-derived, a known Papyrus language limitation.
    Form[] workers = new Form[4]
    Int i = 0
    while i < WorkerPoolSize && i < 4
        ReferenceAlias a = WorkerPool.GetAlias(i) as ReferenceAlias
        if a
            workers[i] = a.GetReference()
        endIf
        i += 1
    endwhile
    return workers
EndFunction

; Rank of the worker's tier (0=apprentice .. 3=master) -
; 0 for anything that isn't a currently-hired worker of this project.
Int Function GetWorkerLevel(Actor akWorker)
    if !_IsHiredWorker(akWorker)
        return 0
    endIf
    string tier = StorageUtil.GetStringValue(akWorker, "WOSK_Tier", "apprentice")
    if tier == "worker"
        return 1
    elseIf tier == "veteran"
        return 2
    elseIf tier == "master"
        return 3
    endIf
    return 0
EndFunction

; profession_id - "" for anything that isn't a
; currently-hired worker of this project.
string Function GetWorkerProfession(Actor akWorker)
    if !_IsHiredWorker(akWorker)
        return ""
    endIf
    return StorageUtil.GetStringValue(akWorker, "WOSK_Profession", "miner")
EndFunction

; lifecycle != AVAILABLE - false for anything that
; isn't a currently-hired worker of this project (an absent worker cannot be
; "busy").
Bool Function IsWorkerBusy(Actor akWorker)
    if !_IsHiredWorker(akWorker)
        return false
    endIf
    return StorageUtil.GetStringValue(akWorker, "WOSK_Lifecycle", "AVAILABLE") != "AVAILABLE"
EndFunction
