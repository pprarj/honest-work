; Copyright (C) 2026 Awrawra
; SPDX-License-Identifier: GPL-3.0-only
; This file is part of Honest Work - Workers of Skyrim, free software under the
; GNU General Public License, version 3. See the LICENSE file at the repository root.

ScriptName WOSK_WorkerAliasScript extends ReferenceAlias

; Attached to each of the 4 WOSK_WorkerPool aliases. Owns the full contract
; cycle for whichever Actor currently fills this alias. State is kept in
; StorageUtil, keyed by the filled Actor (GetActorRef()) - not by alias
; index, so state survives ForceRefTo/Clear cycles cleanly (a re-hired
; worker with the same Actor keeps its history; a different Actor filling
; this same alias slot later gets a clean state).
;
; Every function here is a direct Papyrus port of the reference model
; (already unit-tested there, 56 cases) - no new business rule is
; introduced, only translation.
;
; Fase 8 (D078): profession and contract-type lookups
; below read the id stored per worker (WOSK_Profession/defaults to "miner",
; the only profession the MVP hires) instead of a literal ".miner." path
; segment, and resourceType delivery reads the task's "outputs" array
; instead of a hardcoded if/elseIf switch of vanilla FormIDs - mechanism
; generalized, MVP behavior identical (same numbers, same items).
;
; B003 (D099): every registry read goes through the
; WOSK_Registry natives in HonestWork.dll, which match keys ignoring case.
; Until 2026-09-13 these reads were JsonUtil paths built by concatenation, and
; the Papyrus string cache handed JsonUtil ".professions.Miner..." - its Path
; lookups are case-sensitive, so batch, price and minContracts read 0 and
; ebony was refused. Do not go back to JsonUtil paths here.

; --- Lifecycle/contract state string constants (mirror the reference model's
; enums verbatim, for direct log/StorageUtil traceability against the tested
; harness) ---
string Property LIFECYCLE_AVAILABLE = "AVAILABLE" Auto Hidden
string Property LIFECYCLE_WORKING = "WORKING" Auto Hidden
string Property LIFECYCLE_INJURED_MINOR = "INJURED_MINOR" Auto Hidden
string Property LIFECYCLE_RETIRED = "RETIRED" Auto Hidden
string Property LIFECYCLE_DEAD = "DEAD" Auto Hidden

string Property CONTRACT_IDLE = "IDLE" Auto Hidden
string Property CONTRACT_TRAVELING_TO = "TRAVELING_TO" Auto Hidden
string Property CONTRACT_WORKING = "WORKING" Auto Hidden
string Property CONTRACT_TRAVELING_BACK = "TRAVELING_BACK" Auto Hidden
; D105: the MVP's only hold, as named in hold_sources/*.json.
string Property MVP_HOLD = "Whiterun" Auto Hidden
string Property CONTRACT_AWAITING_PICKUP = "AWAITING_PICKUP" Auto Hidden

string Property OUTCOME_SUCCESS = "SUCCESS" Auto Hidden
string Property OUTCOME_MINOR = "MINOR" Auto Hidden
string Property OUTCOME_MAJOR = "MAJOR" Auto Hidden
string Property OUTCOME_DEATH = "DEATH" Auto Hidden

Float Property ENCOUNTER_WINDOW_HOURS = 4.0 Auto Hidden
; // ASSUMPTION: no spec gives a window size for "o jogador esta na janela
; de tempo" - 4 hours chosen as a round, playable value.
Float Property ENCOUNTER_RADIUS_UNITS = 2000.0 Auto Hidden
; Reuses the same 2000-unit threshold already used for the position
; watchdog, for internal consistency rather than a second invented number.
Float Property HOME_ARRIVAL_RADIUS_UNITS = 1024.0 Auto Hidden
; D105 etapa 2 (2026-09-15): a worker this close to home while still
; TRAVELING_BACK counts as back, and the batch can be picked up before the
; clock. The radius of the candidates' own sandbox at the inn
; (DefaultSandboxCurrentLocation1024), so a worker idling there is inside it.

; ---------------------------------------------------------------------------
; Contract entry point
; ---------------------------------------------------------------------------

; AVAILABLE -(contrato emitido)-> WORKING, applying the hiring cost, and
; rolagem de incidente (executada aqui, oculta, no inicio de TRAVELING_TO).
; Returns false and changes nothing if the worker cannot accept a contract,
; the task/tier data cannot be read, or the player cannot afford it.
; asSourceId (D105 etapa 3, measurement round): when not empty, the contract
; goes to that source instead of a drawn one - it must be one of the hold's
; sources of the task's type. Only the test harness passes it; the panel path
; (WOSK_ControllerScript.RequestContract) never does.
; Fase 9, D137: when abConfirmOccupied is false (panel), an OCCUPIED-only hold is
; refused and no gold changes hands; with true (harness or confirmed panel) the
; contract is drawn from the occupied pool and incident chance comes from config
; (occupiedIncidentChance, default 0.50, clamped 0.01-0.60).
; Fase 17 B (D171): the answer, sent back to the panel by slot.
Function _Outcome(string asAction, string asCode, string asArg = "", Int aiNumber = 0)
    WOSK_PanelBridgeScript.ReportOutcome(asAction, GetID(), asCode, asArg, aiNumber)
EndFunction

Bool Function IssueContract(string asTaskId, string asSourceId = "", Bool abConfirmOccupied = false)
    Actor worker = GetActorRef()
    if !worker
        Debug.Trace("WOSK_WorkerAlias: IssueContract(" + asTaskId + ") failed - alias is empty")
        _Outcome("issue", "EMPTY")
        return false
    endIf

    string lifecycle = StorageUtil.GetStringValue(worker, "WOSK_Lifecycle", LIFECYCLE_AVAILABLE)
    if lifecycle != LIFECYCLE_AVAILABLE
        Debug.Trace("WOSK_WorkerAlias: IssueContract refused, " + worker + " lifecycle=" + lifecycle)
        _Outcome("issue", "NOT_AVAILABLE", lifecycle)
        return false
    endIf

    string profession = _WorkerProfession(worker)
    string tier = StorageUtil.GetStringValue(worker, "WOSK_Tier", "apprentice")
    Int taskIndex = _FindTaskIndex(profession, asTaskId)
    if taskIndex < 0
        Debug.Trace("WOSK_WorkerAlias: IssueContract refused, unknown taskId=" + asTaskId + \
                     " for profession=" + profession)
        _Outcome("issue", "UNKNOWN_TASK", asTaskId)
        return false
    endIf
    string minTier = WOSK_Registry.GetTaskString(profession, taskIndex, "minTier", "apprentice")
    if !_MeetsMinTier(tier, minTier)
        Debug.Trace("WOSK_WorkerAlias: IssueContract refused, tier " + tier + " below minTier " + minTier)
        ; Fase 15: the refusal is said, not only logged - the panel locks the task,
        ; and a call from anywhere else (dialogue, harness) still gets the answer.
        Debug.Notification("Honest Work: this work needs a " + WOSK_Names.TierLabel(minTier) + " worker.")
        _Outcome("issue", "TIER", minTier)
        return false
    endIf
    ; D105: only in a hold with a source of the task's resource type - a worker
    ; never works in another hold.
    string resourceType = WOSK_Registry.GetTaskString(profession, taskIndex, "resourceType", "")
    ; Fase 24 (D223): the cook works only in the kitchen of the player's house he
    ; lives in - the source is that house's zone, never one picked at random. No
    ; house any more: refused, and said, before any gold changes hands.
    if WOSK_PlayerHouse.RequiresHouse(profession)
        string house = WOSK_PlayerHouse.WorkerHouse(worker)
        if house == ""
            Debug.Trace("WOSK_WorkerAlias: IssueContract refused, " + profession + " " + worker + " has no house of the player to work in (task=" + asTaskId + ")")
            Debug.Notification("Honest Work: " + WOSK_PlayerHouse.NeedsHouseText(worker.GetDisplayName()))
            _Outcome("issue", "SOURCE", "HOUSE")
            return false
        endIf
        string kitchen = WOSK_PlayerHouse.KitchenZone(house)
        if asSourceId != "" && asSourceId != kitchen
            Debug.Trace("WOSK_WorkerAlias: IssueContract refused, forced source '" + asSourceId + "' is not the kitchen of " + house + " (task=" + asTaskId + ")")
            _Outcome("issue", "SOURCE", "FORCED")
            return false
        endIf
        Debug.Trace("WOSK_WorkerAlias: IssueContract " + profession + " works at home: " + house + " -> source " + kitchen)
        asSourceId = kitchen
    endIf
    Int sourceCount = WOSK_Registry.CountHoldSources(MVP_HOLD, resourceType)
    if sourceCount <= 0
        Debug.Trace("WOSK_WorkerAlias: IssueContract refused, " + MVP_HOLD + " has no source of " + resourceType + \
                     " (task=" + asTaskId + ")")
        _Outcome("issue", "SOURCE", "NONE")
        return false
    endIf
    ; D105 etapa 2: the source is chosen among the hold's sources of the type, and
    ; its destination resolved, before any gold changes hands.
    ; D105 etapa 3 (decision B): only among the usable ones - a confirmed dungeon
    ; mine first, else a safe source - weighted by the veins each has left. None
    ; usable refuses the contract and tells the player why.
    string sourceId = ""
    Bool occupiedGamble = false
    if asSourceId == ""
        sourceId = WOSK_DepletionScript.PickSource(MVP_HOLD, resourceType, Utility.RandomFloat(0.0, 1.0))
        if sourceId == ""
            string reason = WOSK_DepletionScript.RefusalReason(MVP_HOLD, resourceType)
            if reason == "OCCUPIED" && abConfirmOccupied
                sourceId = WOSK_DepletionScript.PickOccupiedSource(MVP_HOLD, resourceType, Utility.RandomFloat(0.0, 1.0))
                if sourceId != ""
                    occupiedGamble = true
                    Debug.Trace("WOSK_WorkerAlias: IssueContract OCCUPIED gamble confirmed - source " + sourceId)
                endIf
            endIf
            if sourceId == ""
                Debug.Trace("WOSK_WorkerAlias: IssueContract refused, no usable " + MVP_HOLD + " source of " + resourceType + \
                             " (reason=" + reason + ", task=" + asTaskId + ")")
                Debug.Notification(WOSK_DepletionScript.RefusalMessage(reason, MVP_HOLD, resourceType))
                Int waitHours = 0
                if reason == "DEPLETED"
                    waitHours = WOSK_DepletionScript.HoursUntilBack(MVP_HOLD, resourceType)
                endIf
                _Outcome("issue", "SOURCE", reason, waitHours)
                return false
            endIf
        endIf
    else
        Int si = 0
        while si < sourceCount && sourceId == ""
            string candidate = WOSK_Registry.GetHoldSourceId(MVP_HOLD, resourceType, si)
            if candidate == asSourceId
                sourceId = candidate
            endIf
            si += 1
        endwhile
        if sourceId == ""
            Debug.Trace("WOSK_WorkerAlias: IssueContract refused, forced source '" + asSourceId + "' is not a " + \
                         MVP_HOLD + " source of " + resourceType + " (task=" + asTaskId + ")")
            _Outcome("issue", "SOURCE", "FORCED")
            return false
        endIf
        Debug.Trace("WOSK_WorkerAlias: IssueContract source forced by caller: " + sourceId + " (task=" + asTaskId + \
                    ", state=" + WOSK_DepletionScript.SourceStateOf(MVP_HOLD, sourceId, resourceType) + ")")
        ; A forced source skips the dungeon check (the harness and the probe
        ; measure there on purpose), not the veins it has left.
        if WOSK_DepletionScript.RemainingVeins(MVP_HOLD, sourceId, resourceType) <= 0
            ; Fase 33 etapa 8 (D1, V071): the refusal says which kitchen ran out and
            ; when it is back; the number of the outcome is that wait in hours.
            Int backHours = WOSK_DepletionScript.HoursToRecover(MVP_HOLD, sourceId, resourceType)
            Debug.Trace("WOSK_WorkerAlias: IssueContract refused, forced source '" + sourceId + "' has no vein of " + \
                         resourceType + " left, back in " + backHours + " h (task=" + asTaskId + ")")
            string kitchenHouse = WOSK_PlayerHouse.HouseOfKitchen(sourceId)
            if kitchenHouse != ""
                Debug.Notification(WOSK_PlayerHouse.KitchenWornOutText(kitchenHouse, backHours))
                _Outcome("issue", "SOURCE", "KITCHEN|" + kitchenHouse, backHours)
            else
                Debug.Notification(WOSK_DepletionScript.RefusalMessage("DEPLETED", MVP_HOLD, resourceType))
                _Outcome("issue", "SOURCE", "DEPLETED", backHours)
            endIf
            return false
        endIf
    endIf
    ObjectReference destination = _ResolveFormRef(WOSK_Registry.GetHoldSourceString(MVP_HOLD, sourceId, "destination", "")) as ObjectReference
    if !destination
        Debug.Trace("WOSK_WorkerAlias: IssueContract refused, source '" + sourceId + "' of " + resourceType + \
                     " has no destination that resolves (task=" + asTaskId + ")")
        _Outcome("issue", "NO_DESTINATION")
        return false
    endIf

    Float batchMin = WOSK_Registry.GetTaskFloat(profession, taskIndex, "batchMin", 0.0)
    Float batchMax = WOSK_Registry.GetTaskFloat(profession, taskIndex, "batchMax", 0.0)
    Float basePricePerUnit = _TaskUnitPrice(profession, taskIndex)
    Float priceMultiplier = WOSK_Registry.GetTaskFloat(profession, taskIndex, "priceMultiplier", 1.0)
    if basePricePerUnit <= 0.0
        Debug.Trace("WOSK_WorkerAlias: IssueContract refused, no output of task=" + asTaskId + " has a value in game")
        _Outcome("issue", "NO_VALUE")
        return false
    endIf
    ; Fase 15 (D159): the cook buys the ingredients; their value enters the
    ; price at cost, per expected unit. 0.0 for every other task.
    Float ingredientCost = TaskIngredientCost(profession, taskIndex)
    if ingredientCost < 0.0
        Debug.Trace("WOSK_WorkerAlias: IssueContract refused, an ingredient of task=" + asTaskId + " does not resolve in game")
        Debug.Notification("Honest Work: the ingredients for this work are not available.")
        _Outcome("issue", "INGREDIENTS")
        return false
    endIf

    ; D105 etapa 3: the contract reserves the veins for the largest batch the tier
    ; can roll, never more than the source has left, and the player pays only for
    ; what the reserved veins hold. Fase 15: at a zone a slot is one unit of
    ; output (SourceUnitsPerSlot 1.0) and the same arithmetic reserves units.
    Float unitsPerVein = WOSK_DepletionScript.SourceUnitsPerSlot(MVP_HOLD, sourceId, profession, taskIndex)
    Float yieldMultiplier = WOSK_Registry.GetTierFloat(profession, tier, "yieldMultiplier", 1.0)
    ; Fase 15, SPEC 5.7: the hunter's bow multiplies the batch. Read once, here,
    ; and stored with the contract (WOSK_ContractGear); the settlement reads the
    ; stored value, never the inventory. The cost below does not move.
    ; Fase 30 (D242): what the hunter owns goes on before it is read (a bow he could not
    ; take while unloaded); the read is of what is equipped.
    if profession == "hunter"
        WOSK_Outfits.Reconcile(worker, profession)
    endIf
    Float gearMultiplier = _GearMultiplier(worker, profession, taskIndex)
    yieldMultiplier = yieldMultiplier * gearMultiplier
    Int remainingVeins = WOSK_DepletionScript.RemainingVeins(MVP_HOLD, sourceId, resourceType)
    Int reservedVeins = WOSK_DepletionScript.VeinsToReserve(batchMax, yieldMultiplier, unitsPerVein, remainingVeins)
    Float expectedUnits = WOSK_DepletionScript.CappedExpectedUnits(batchMin, batchMax, unitsPerVein, reservedVeins)
    ; D104: no hiringFee here - it is paid once, on hiring.
    ; Fase 33 etapa 10 (F1, V073): the charge is ContractCost, the same sum the panel shows as
    ; "Contract: ~X-Y gold" (ui-prisma model.contractCost; vectors in
    ; plugin-skse/tests/fixtures/contract_cost_vectors.txt), and it is logged for every task.
    Int costGold = ContractCost(expectedUnits, basePricePerUnit, priceMultiplier, ingredientCost)
    Debug.Trace("WOSK_WorkerAlias: IssueContract cost " + costGold + " gold = ceil(" + expectedUnits + " unit(s) x (reference " + basePricePerUnit + \
                " x multiplier " + priceMultiplier + " + ingredients " + ingredientCost + ")) task=" + asTaskId + " tier=" + tier)

    Actor player = Game.GetPlayer()
    Form goldForm = Game.GetFormFromFile(0x0000000F, "Skyrim.esm")
    if player.GetItemCount(goldForm) < costGold
        Debug.Trace("WOSK_WorkerAlias: IssueContract refused, player has " + player.GetItemCount(goldForm) + \
                     " gold, needs " + costGold)
        _Outcome("issue", "GOLD", "" + player.GetItemCount(goldForm), costGold)
        return false
    endIf
    player.RemoveItem(goldForm, costGold)
    ; Fase 28 conserto 1 (D238, V060): the cook does not set out, he cooks at home;
    ; "on the way" is never said of him.
    if profession == "cook"
        Debug.Notification("Honest Work: contract issued for " + costGold + " gold. " + worker.GetDisplayName() + " is preparing the meal.")
    else
        Debug.Notification("Honest Work: contract issued for " + costGold + " gold.")
    endIf
    ; Fase 17 (D168): the panel's gold-spent counter and statement line.
    WOSK_LedgerScript.RecordIssued(worker, asTaskId, costGold)
    if occupiedGamble
        _Outcome("issue", "ISSUED", "OCCUPIED", costGold)
    elseIf profession == "cook"
        _Outcome("issue", "ISSUED", "COOK", costGold)
    else
        _Outcome("issue", "ISSUED", "", costGold)
    endIf

    StorageUtil.SetStringValue(worker, "WOSK_TaskId", asTaskId)
    StorageUtil.SetStringValue(worker, "WOSK_ContractSource", sourceId)
    StorageUtil.SetFormValue(worker, "WOSK_ContractDestination", destination)
    StorageUtil.SetStringValue(worker, "WOSK_ContractResourceType", resourceType)
    StorageUtil.SetIntValue(worker, "WOSK_ContractVeins", reservedVeins)
    StorageUtil.SetFloatValue(worker, "WOSK_ContractGear", gearMultiplier)
    WOSK_DepletionScript.Reserve(MVP_HOLD, sourceId, resourceType, reservedVeins)
    StorageUtil.SetStringValue(worker, "WOSK_Lifecycle", LIFECYCLE_WORKING)
    StorageUtil.SetStringValue(worker, "WOSK_Contract", CONTRACT_TRAVELING_TO)
    WOSK_WorkerState.Mirror(worker, CONTRACT_TRAVELING_TO)
    StorageUtil.SetIntValue(worker, "WOSK_EncounterResolved", 0)
    ; Fase 25 (D227): miner and hunter put the CC backpack on for the contract;
    ; _AdvanceTo takes it off when the contract goes back to IDLE.
    WOSK_Backpack.Wear(worker, profession)

    ; Incident roll, hidden, once, right now.
    ; Fase 9, D137: occupied gamble replaces the table chance with config (0.50, clamped).
    Float chanceFinal = 0.0
    if occupiedGamble
        chanceFinal = WOSK_Registry.GetOccupiedIncidentChance()
        if chanceFinal < 0.01
            chanceFinal = 0.01
        elseIf chanceFinal > 0.60
            chanceFinal = 0.60
        endIf
        Debug.Trace("WOSK_WorkerAlias: occupied gamble chance=" + chanceFinal + " source=" + sourceId)
    else
        Float taskIncidentChance = WOSK_Registry.GetTaskFloat(profession, taskIndex, "incidentChance", 0.05)
        Float tierIncidentModifier = WOSK_Registry.GetTierFloat(profession, tier, "incidentModifier", 0.0)
        Int previousMinorInjuries = StorageUtil.GetIntValue(worker, "WOSK_MinorInjuries", 0)
        Float armorValueTotal = worker.GetActorValue("DamageResist")
        ; Fase 30 (D243): the hunter's armor is worth what its TIER says (00_core.json,
        ; armorGearReduction), read from what he wears; DamageResist is not counted for
        ; him, or the same armor would pay twice.
        Float armorReduction = 0.0
        if profession == "hunter"
            armorValueTotal = 0.0
            armorReduction = WOSK_Gear.ArmorReduction(worker, profession)
        endIf
        ; // ASSUMPTION: no spec defines what "valor_armadura_total" measures.
        ; DamageResist (confirmed real AV, commented usage in the real Bethesda
        ; script DLC2AshShellScript.psc) is a single native call that already
        ; scales roughly to the /2000 divisor's 0-0.15 cap for a fully armored
        ; actor, without needing to enumerate biped armor slots.
        chanceFinal = _ComputeIncidentChance(taskIncidentChance, tierIncidentModifier, previousMinorInjuries, armorValueTotal)
        if armorReduction > 0.0
            chanceFinal = chanceFinal - armorReduction
            if chanceFinal < 0.01
                chanceFinal = 0.01
            endIf
            Debug.Trace("WOSK_WorkerAlias: hunter armor lowers the incident chance by " + armorReduction + " -> " + chanceFinal)
        endIf
    endIf

    Float roll = Utility.RandomFloat(0.0, 1.0)
    string outcome = OUTCOME_SUCCESS
    if roll <= chanceFinal
        string contractType = WOSK_Registry.GetTaskString(profession, taskIndex, "contractType", "collection")
        Float roll2 = Utility.RandomFloat(0.0, 1.0)
        outcome = _ResolveOutcome(contractType, roll2)
    endIf
    StorageUtil.SetStringValue(worker, "WOSK_IncidentOutcome", outcome)

    Float taskHours = WOSK_Registry.GetTaskFloat(profession, taskIndex, "hours", 24.0)
    ; Fase 9 (D136): tier speed bonus applied once at issue, before storing.
    Float durationMultiplier = WOSK_Registry.GetTierFloat(profession, tier, "durationMultiplier", 1.0)
    if durationMultiplier <= 0.0 || durationMultiplier > 1.0
        durationMultiplier = 1.0
    endIf
    ; Fase 33 etapa 6 (D277, V069 A3): whole hours, the same sum the panel shows.
    Float finalHours = WholeHours(taskHours, durationMultiplier)
    if outcome != OUTCOME_SUCCESS
        Float timingRoll = Utility.RandomFloat(0.0, 1.0)
        Float momentoIncidente = (0.2 + timingRoll * 0.6) * finalHours
        StorageUtil.SetFloatValue(worker, "WOSK_IncidentEventGameTime", Utility.GetCurrentGameTime() * 24.0 + momentoIncidente)
    else
        StorageUtil.UnsetFloatValue(worker, "WOSK_IncidentEventGameTime")
    endIf

    Debug.Trace("WOSK_WorkerAlias: contract issued - worker=" + worker + " profession=" + profession + \
                " task=" + asTaskId + " tier=" + tier + " unitPrice=" + basePricePerUnit + " cost=" + costGold + " chanceFinal=" + chanceFinal + \
                " rolledOutcome=" + outcome + " hours=" + taskHours + " durationMultiplier=" + durationMultiplier + " finalHours=" + finalHours + " source=" + sourceId + " destination=" + destination + \
                " veinsLeft=" + remainingVeins + " veinsReserved=" + reservedVeins + " unitsPerVein=" + unitsPerVein + " expectedUnits=" + expectedUnits, 0)

    if profession == "cook"
        ; Fase 28 (D234): the cook does not travel. He cooks at the pot of his
        ; house until the contract ends; without a pot he stays on the home
        ; sandbox. The legs below still run, as the clock only.
        WOSK_PlayerHouse.StartCooking(worker)
        WOSK_PlayerHouse.ProbeCooking(worker, "start")
        StorageUtil.SetIntValue(worker, "WOSK_CookProbeN", 0)
        RegisterForSingleUpdate(15.0)
    else
        _SetTravelTarget(worker, destination)
        ; D223: the home sandbox off first - same priority as the travel package.
        WOSK_PlayerHouse.LeaveHome(worker)
        ActorUtil.AddPackageOverride(worker, _TravelPackage(), 30, 0)
        ; Fase 32 (D253): "Traveling out" waits for the worker to leave the cell of
        ; the order. The cell is stored and compared in real time (see OnUpdate).
        StorageUtil.SetIntValue(worker, "WOSK_Departed", 0)
        StorageUtil.SetFormValue(worker, "WOSK_IssueCell", worker.GetParentCell())
        StorageUtil.SetFloatValue(worker, "WOSK_IssueRealTime", Utility.GetCurrentRealTime())
        StorageUtil.SetIntValue(worker, "WOSK_DepartProbeN", 0)
        RegisterForSingleUpdate(2.0)
    endIf
    _TracePosition(worker, "contract issued")
    ; The contract clock: when it started and how long it was sold for. The
    ; legs are read off these two, not counted one per timer firing.
    StorageUtil.SetFloatValue(worker, "WOSK_ContractStartHours", Utility.GetCurrentGameTime() * 24.0)
    StorageUtil.SetFloatValue(worker, "WOSK_ContractTaskHours", finalHours)
    _ArmContractTimer(worker, CONTRACT_TRAVELING_TO)
    ; Fase 26: the contract state above is written without _AdvanceTo, so nothing
    ; pushed the panel and the row kept saying 'Awaiting work' after the order.
    WOSK_PanelBridgeScript.PushPanelState()
    return true
EndFunction

; Fase 33 etapa 6 (D277, V069 A3): the length a contract is sold for, in WHOLE hours and
; at least one. hours x multiplier, rounded half up (the 0.0001 over the half keeps an
; exact x.5 on the same side here and in the panel, model.ts hoursFor). A contract
; already running keeps the hours stored at its issue (WOSK_ContractTaskHours).
Float Function WholeHours(Float afHours, Float afMultiplier) global
    Float whole = Math.Floor(afHours * afMultiplier + 0.5001) as Float
    if whole < 1.0
        whole = 1.0
    endIf
    return whole
EndFunction

; ---------------------------------------------------------------------------
; Contract state machine ("Contrato": IDLE -> TRAVELING_TO -> WORKING ->
; TRAVELING_BACK -> AWAITING_PICKUP -> IDLE)
; ---------------------------------------------------------------------------

; Fase 28 conserto 1 (D238): the cook's probe in real time (15, 45, 90 and 180 s after
; the contract starts) - the legs below are game time and a long wait skips them.
Event OnUpdate()
    Actor worker = GetActorRef()
    if !worker
        return
    endIf
    ; Fase 33 etapa 2 (D263): the move home that did not land is looked at again.
    if StorageUtil.GetIntValue(worker, "WOSK_HomeRecheck", 0) == 1
        StorageUtil.UnsetIntValue(worker, "WOSK_HomeRecheck")
        EnsureAtHome("recheck")
    endIf
    if _WorkerProfession(worker) != "cook"
        WOSK_Outfits.Guard(worker, "OnUpdate")
        _DepartureProbe(worker)
        _ArrivalProbe(worker)
        return
    endIf
    ; Fase 33 etapa 2 (D264): the cook's guard pass (his _GuardLater runs only while no
    ; contract runs, below) - the second look at his clothes 1.5 s after the 3D.
    WOSK_Outfits.Guard(worker, "OnUpdate")
    string contract = StorageUtil.GetStringValue(worker, "WOSK_Contract", CONTRACT_IDLE)
    if contract == CONTRACT_IDLE || contract == CONTRACT_AWAITING_PICKUP
        return
    endIf
    Int n = StorageUtil.GetIntValue(worker, "WOSK_CookProbeN", 0)
    WOSK_PlayerHouse.ProbeCooking(worker, "t+" + n)
    StorageUtil.SetIntValue(worker, "WOSK_CookProbeN", n + 1)
    if n == 0
        RegisterForSingleUpdate(30.0)
    elseIf n == 1
        RegisterForSingleUpdate(45.0)
    elseIf n == 2
        RegisterForSingleUpdate(90.0)
    endIf
EndEvent

; Fase 32 (D253): has the worker left the cell where the contract was issued? Real
; time, every 2 s while the leg is TRAVELING_TO and WOSK_Departed is 0. A cell that
; differs is the answer; so is the end of the leg (_EnterWorking sets it), and a cap
; of 5 minutes of polling so a worker who never leaves does not poll forever (it is
; traced, so that case is read off the log). Every 5th poll logs where the worker is
; and which package the engine runs - the evidence the round-6 log did not carry
; (gate item 5, STATUS).
Function _DepartureProbe(Actor akWorker)
    if StorageUtil.GetStringValue(akWorker, "WOSK_Contract", CONTRACT_IDLE) != CONTRACT_TRAVELING_TO
        return
    endIf
    if StorageUtil.GetIntValue(akWorker, "WOSK_Departed", 1) == 1
        return
    endIf
    Int n = StorageUtil.GetIntValue(akWorker, "WOSK_DepartProbeN", 0) + 1
    StorageUtil.SetIntValue(akWorker, "WOSK_DepartProbeN", n)
    Cell issueCell = StorageUtil.GetFormValue(akWorker, "WOSK_IssueCell", None) as Cell
    Cell nowCell = akWorker.GetParentCell()
    Float secs = Utility.GetCurrentRealTime() - StorageUtil.GetFloatValue(akWorker, "WOSK_IssueRealTime", 0.0)
    if nowCell != issueCell
        _MarkDeparted(akWorker, "left the cell after " + secs + " s, probe " + n)
        return
    endIf
    if n % 5 == 0
        Debug.Trace("WOSK_WorkerAlias: " + akWorker + " still in the issue cell after " + secs + " s, probe " + n + \
                    " package=" + akWorker.GetCurrentPackage() + " " + _WhereString(akWorker))
    endIf
    if n >= 150
        _MarkDeparted(akWorker, "gave up polling after " + secs + " s in the issue cell")
        return
    endIf
    RegisterForSingleUpdate(2.0)
EndFunction

; Fase 33 etapa 1 (V064): a worker who gets home while the leg is still
; TRAVELING_BACK is collectable at once, by the topic and by the panel. Both ask for the
; state AWAITING_PICKUP (faction rank 3), which used to arrive only with the clock, so the
; contract is RESOLVED when he arrives: the same _ResolveContractCompletion the clock
; calls (outcome rolled at issue, batch rolled here with the tier's yield, no extra bonus
; for coming early), and AWAITING_PICKUP's own 7 days timer. Real time, every 5 s while
; the leg runs (the departure probe above is TRAVELING_TO's; the two never overlap), and
; a cap of one hour of polling so a worker who never arrives does not poll forever (the
; game clock still ends the leg). Not the cook: he works at the house (D234), the leg is
; only a name for him. The clock keeps its own timer; this only comes first.
Function _ArrivalProbe(Actor akWorker)
    if StorageUtil.GetStringValue(akWorker, "WOSK_Contract", CONTRACT_IDLE) != CONTRACT_TRAVELING_BACK
        return
    endIf
    Int n = StorageUtil.GetIntValue(akWorker, "WOSK_ArriveProbeN", 0) + 1
    StorageUtil.SetIntValue(akWorker, "WOSK_ArriveProbeN", n)
    if _IsAtHome(akWorker)
        _ArrivedHome(akWorker, n)
        return
    endIf
    if n % 12 == 0
        Debug.Trace("WOSK_WorkerAlias: " + akWorker + " still on the way back, probe " + n + " " + _WhereString(akWorker))
    endIf
    if n >= 720
        Debug.Trace("WOSK_WorkerAlias: " + akWorker + " arrival probe gave up after " + n + " polls, the clock ends the leg")
        return
    endIf
    RegisterForSingleUpdate(5.0)
EndFunction

Function _ArrivedHome(Actor akWorker, Int aiProbe)
    Debug.Trace("WOSK_WorkerAlias: " + akWorker + " arrived home before the clock (probe " + aiProbe + "), contract resolved now " + _WhereString(akWorker))
    StorageUtil.UnsetIntValue(akWorker, "WOSK_ArriveProbeN")
    UnregisterForUpdateGameTime()
    ActorUtil.RemovePackageOverride(akWorker, _TravelPackage())
    WOSK_PlayerHouse.StopCooking(akWorker)
    _ResolveContractCompletion(akWorker)
EndFunction

Function _MarkDeparted(Actor akWorker, string asWhy)
    if StorageUtil.GetIntValue(akWorker, "WOSK_Departed", 1) == 1
        return
    endIf
    StorageUtil.SetIntValue(akWorker, "WOSK_Departed", 1)
    Debug.Trace("WOSK_WorkerAlias: " + akWorker + " departed: " + asWhy)
    WOSK_PanelBridgeScript.PushPanelState()
EndFunction

; Fase 30 (D245): the hunter who loads while he is working (the player walked up to
; the site) has the bow drawn; equipment the player gave while he was unloaded goes on.
Event OnLoad()
    Actor worker = GetActorRef()
    if !worker
        return
    endIf
    WOSK_Outfits.Probe(worker, "OnLoad")
    WOSK_Outfits.Guard(worker, "OnLoad")
    _GuardLater(worker)
    if _WorkerProfession(worker) != "hunter"
        return
    endIf
    WOSK_Outfits.Reconcile(worker, "hunter")
    if StorageUtil.GetStringValue(worker, "WOSK_Contract", CONTRACT_IDLE) == CONTRACT_WORKING
        WOSK_Gear.DrawAtWork(worker)
    endIf
EndEvent

; Fase 33 etapa 1 (probe, gate item 4): the cell attach and the unequip of a piece the
; mod put on are the two moments the default outfit would come back. Reading only.
Event OnCellAttach()
    Actor worker = GetActorRef()
    if worker
        WOSK_Outfits.Probe(worker, "OnCellAttach")
        WOSK_Outfits.Guard(worker, "OnCellAttach")
        _GuardLater(worker)
    endIf
EndEvent

; Fase 33 etapa 1 (D259): the engine's own dressing arrives a moment after the 3D, so the
; guard runs once more 1.5 s later. The cook is left out: his OnUpdate is the cooking probe
; and he is dressed by the house, not walked out of town. The single update this registers
; is shared with the two polls (departure, arrival); they re-arm themselves.
Function _GuardLater(Actor akWorker)
    if StorageUtil.GetStringValue(akWorker, WOSK_Outfits.KeyPieces(), "") == ""
        return
    endIf
    ; Fase 33 etapa 2 (D264, V065 "allOn=False" twice on the new cook): EquipItem lands a
    ; moment after the call, so the pass that ran right at the 3D read the pieces as not
    ; on, and nothing looked again because the cook was left out here. He is in now while
    ; no contract runs; during one his OnUpdate is the cooking probe (it re-arms with its
    ; own intervals, a 1.5 s update in between would eat a probe number).
    if _WorkerProfession(akWorker) == "cook" && StorageUtil.GetStringValue(akWorker, "WOSK_Contract", CONTRACT_IDLE) != CONTRACT_IDLE \
        && StorageUtil.GetStringValue(akWorker, "WOSK_Contract", CONTRACT_IDLE) != CONTRACT_AWAITING_PICKUP
        return
    endIf
    RegisterForSingleUpdate(1.5)
EndFunction

Event OnObjectEquipped(Form akBaseObject, ObjectReference akReference)
    Actor worker = GetActorRef()
    if worker && akBaseObject && WOSK_Outfits.IsDefaultPiece(worker, akBaseObject)
        WOSK_Outfits.Probe(worker, "OnObjectEquipped", akBaseObject)
        WOSK_Outfits.Guard(worker, "OnObjectEquipped", akBaseObject)
    endIf
EndEvent

Event OnObjectUnequipped(Form akBaseObject, ObjectReference akReference)
    Actor worker = GetActorRef()
    if worker && akBaseObject && WOSK_Outfits.IsOutfitPiece(worker, akBaseObject)
        WOSK_Outfits.Probe(worker, "OnObjectUnequipped", akBaseObject)
        if !WOSK_Outfits.IsDefaultPiece(worker, akBaseObject)
            WOSK_Outfits.Guard(worker, "OnObjectUnequipped", akBaseObject)
        endIf
    endIf
EndEvent

Event OnUpdateGameTime()
    Actor worker = GetActorRef()
    if !worker
        return
    endIf
    string contract = StorageUtil.GetStringValue(worker, "WOSK_Contract", CONTRACT_IDLE)

    if contract == CONTRACT_AWAITING_PICKUP
        ; 7 days without pickup deposits the batch and frees the worker.
        ; RegisterForSingleUpdateGameTime(7 days) was armed when
        ; AWAITING_PICKUP started (_ResolveContractCompletion below); reaching
        ; here means the timeout elapsed with no PickUp() call.
        _DepositToShipmentChestAndFree(worker)
        return
    endIf

    _RunContractLegs(worker, contract)
EndEvent

; 2026-09-21 (Parte 2): the contract used to advance ONE leg per firing, each
; leg armed relative to the moment the previous one fired. A single 24 h wait
; therefore closed one leg and threw the surplus away - the maintainer needed three
; separate waits (24 h + 12 h + 4 h) to get a 24 h contract back. The legs are
; now read off the time elapsed since the contract was issued, so one long wait
; closes every leg it covers.
;
; Boundaries, in hours since issue: TRAVELING_TO ends at taskHours/3, WORKING at
; 2*taskHours/3, TRAVELING_BACK at taskHours.
;
; A contract issued before this build has no start stamp. It keeps the old
; one-leg-per-firing behaviour instead of resolving at once, which is what an
; unknown elapsed time honestly supports.
Function _RunContractLegs(Actor akWorker, string asContract)
    Float taskHours = _ContractTaskHours(akWorker)
    Float legHours = taskHours / 3.0
    Float elapsed = _ContractElapsedHours(akWorker)
    Bool timed = (elapsed >= 0.0)

    string contract = asContract
    Bool advancing = true
    while advancing
        advancing = false

        if contract == CONTRACT_TRAVELING_TO
            if !timed || elapsed >= legHours
                _EnterWorking(akWorker)
                contract = CONTRACT_WORKING
                advancing = timed
            endIf

        elseIf contract == CONTRACT_WORKING
            if !timed || elapsed >= legHours * 2.0
                _EnterTravelingBack(akWorker)
                contract = CONTRACT_TRAVELING_BACK
                advancing = timed
            endIf

        elseIf contract == CONTRACT_TRAVELING_BACK
            if !timed || elapsed >= taskHours
                if _WorkerProfession(akWorker) == "cook"
                    WOSK_PlayerHouse.ProbeCooking(akWorker, "leg end")
                endIf
                ActorUtil.RemovePackageOverride(akWorker, _TravelPackage())
                WOSK_PlayerHouse.StopCooking(akWorker)
                _ResolveContractCompletion(akWorker)
                return
            endIf

        else
            ; IDLE or anything else: no leg to run, no timer to arm.
            return
        endIf
    endWhile

    _ArmContractTimer(akWorker, contract)
EndFunction

Function _EnterWorking(Actor akWorker)
    ; D253: a leg that ends counts as departed, whatever the probe saw.
    StorageUtil.SetIntValue(akWorker, "WOSK_Departed", 1)
    _AdvanceTo(akWorker, CONTRACT_WORKING)
    if _WorkerProfession(akWorker) == "cook"
        ; D234: the cook is already at his pot - nothing to swap.
        WOSK_PlayerHouse.ProbeCooking(akWorker, "leg working")
        return
    endIf
    ActorUtil.RemovePackageOverride(akWorker, _TravelPackage())
    ActorUtil.AddPackageOverride(akWorker, _SandboxPackage(), 30, 0)
EndFunction

Function _EnterTravelingBack(Actor akWorker)
    if _WorkerProfession(akWorker) == "cook"
        ; D234: no way back for a cook; the package stays until the contract ends.
        _AdvanceTo(akWorker, CONTRACT_TRAVELING_BACK)
        WOSK_PlayerHouse.ProbeCooking(akWorker, "leg returning")
        return
    endIf
    ; Home becomes the target before the state changes, so the position line
    ; _AdvanceTo writes names where the worker is going now.
    ActorUtil.RemovePackageOverride(akWorker, _SandboxPackage())
    _SetTravelTarget(akWorker, _HomeTarget(akWorker))
    _AdvanceTo(akWorker, CONTRACT_TRAVELING_BACK)
    ActorUtil.AddPackageOverride(akWorker, _TravelPackage(), 30, 0)
    StorageUtil.SetIntValue(akWorker, "WOSK_ArriveProbeN", 0)
    RegisterForSingleUpdate(5.0)
EndFunction

; Arms the timer for what is LEFT of the leg the worker is in, measured from
; the contract's start - never a fresh full leg from "now".
Function _ArmContractTimer(Actor akWorker, string asContract)
    Float taskHours = _ContractTaskHours(akWorker)
    Float legHours = taskHours / 3.0
    Float dueAt = legHours
    if asContract == CONTRACT_WORKING
        dueAt = legHours * 2.0
    elseIf asContract == CONTRACT_TRAVELING_BACK
        dueAt = taskHours
    endIf

    Float remaining = legHours
    Float elapsed = _ContractElapsedHours(akWorker)
    if elapsed >= 0.0
        remaining = dueAt - elapsed
    endIf
    if remaining < 0.01
        remaining = 0.01
    endIf
    RegisterForSingleUpdateGameTime(remaining)
EndFunction

; Hours since the contract was issued, or -1.0 when there is no start stamp
; (a contract issued before the clock existed).
Float Function _ContractElapsedHours(Actor akWorker)
    if !StorageUtil.HasFloatValue(akWorker, "WOSK_ContractStartHours")
        return -1.0
    endIf
    Float start = StorageUtil.GetFloatValue(akWorker, "WOSK_ContractStartHours", 0.0)
    return Utility.GetCurrentGameTime() * 24.0 - start
EndFunction

; Queue item 11: what the Workers tab prints next to a running contract. It is
; the only piece of the row the controller cannot read straight out of
; StorageUtil, because the remaining time is a subtraction against the clock and
; the task length has a fallback path (_ContractTaskHours).
;
; -1.0 means "no number to print", and it covers three different cases on
; purpose: no contract running, a contract issued before the start stamp
; existed, and a task whose length could not be resolved. The tab prints nothing
; for all three, and inventing a 0.0 there would read as "arriving now".
Float Function ContractHoursLeft()
    Actor worker = GetActorRef()
    if !worker
        return -1.0
    endIf
    string contract = StorageUtil.GetStringValue(worker, "WOSK_Contract", CONTRACT_IDLE)
    if contract == CONTRACT_IDLE || contract == CONTRACT_AWAITING_PICKUP
        return -1.0
    endIf
    Float elapsed = _ContractElapsedHours(worker)
    if elapsed < 0.0
        return -1.0
    endIf
    Float left = _ContractTaskHours(worker) - elapsed
    if left < 0.0
        ; The timer has fired late, or the player slept past the return. The
        ; contract is still standing, so the row says "0" rather than a negative
        ; number that reads as a bug.
        return 0.0
    endIf
    return left
EndFunction

; Queue item 12, scope 1: one line about where this worker is, for the tracker
; [debug] worker_tracker_seconds turns on. "" when the slot is empty or no
; contract is running - the tracker exists for the wait, and a worker standing
; at home is not the one the maintainer loses sight of (V024: it could not be
; confirmed anywhere that the worker was on the road, and the only way to find out
; was to follow her).
;
; This is a TEST AID and reads like one: raw units, not a distance in steps the
; player would recognise. The engine's unit is the only length this mod has
; measured, and inventing a conversion to metres would be a number nobody
; checked.
string Function TrackerLine()
    Actor worker = GetActorRef()
    if !worker
        return ""
    endIf
    string contract = StorageUtil.GetStringValue(worker, "WOSK_Contract", CONTRACT_IDLE)
    if contract == CONTRACT_IDLE
        return ""
    endIf
    string lifecycle = StorageUtil.GetStringValue(worker, "WOSK_Lifecycle", LIFECYCLE_AVAILABLE)
    string line = worker.GetDisplayName() + ": " + WOSK_Names.StateLabelDeparted(lifecycle, contract, _WorkerProfession(worker), StorageUtil.GetStringValue(worker, "WOSK_House", ""), StorageUtil.GetIntValue(worker, "WOSK_Departed", 1))
    Float hoursLeft = ContractHoursLeft()
    if hoursLeft >= 0.0
        line += ", " + _TimeLeftText(hoursLeft)
    endIf
    return line + ", " + _WhereFromPlayer(worker)
EndFunction

; Whole hours and whole minutes, because a Papyrus Float prints six decimals
; and "2.100000h" in a notification reads as a machine talking to itself.
string Function _TimeLeftText(Float afHours)
    Int wholeHours = afHours as Int
    Int minutes = ((afHours - (wholeHours as Float)) * 60.0) as Int
    if wholeHours <= 0
        return minutes + " min left"
    endIf
    return wholeHours + "h " + minutes + "m left"
EndFunction

; How far and which way, from where the player is standing. Across worldspaces
; a distance is meaningless (_SameSpace), and there the place name is the only
; true thing left to say.
string Function _WhereFromPlayer(Actor akWorker)
    Actor player = Game.GetPlayer()
    if !player
        return _PlaceWords(akWorker)
    endIf
    if !_SameSpace(akWorker, player)
        return _PlaceWords(akWorker) + ", too far to point at"
    endIf
    Float dx = akWorker.GetPositionX() - player.GetPositionX()
    Float dy = akWorker.GetPositionY() - player.GetPositionY()
    return (akWorker.GetDistance(player) as Int) + " units " + WOSK_Names.BearingLabel(dx, dy)
EndFunction

Function _ClearContractClock(Actor akWorker)
    StorageUtil.UnsetFloatValue(akWorker, "WOSK_ContractStartHours")
    StorageUtil.UnsetFloatValue(akWorker, "WOSK_ContractTaskHours")
EndFunction

; abPush=false: the caller pushes the panel itself, later (OnDeath, which must
; free the alias before the slow push - V046 ENC06, D175).
Function _AdvanceTo(Actor akWorker, string asNewContractState, Bool abPush = true)
    string old = StorageUtil.GetStringValue(akWorker, "WOSK_Contract", CONTRACT_IDLE)
    StorageUtil.SetStringValue(akWorker, "WOSK_Contract", asNewContractState)
    ; Fase 26 conserto 1 (D233): the dialogue reads the state as a faction rank.
    WOSK_WorkerState.Mirror(akWorker, asNewContractState)
    Debug.Trace("WOSK_WorkerAlias: " + akWorker + " contract " + old + " -> " + asNewContractState)
    _TracePosition(akWorker, "contract now " + asNewContractState)
    ; Fase 25 (D227): every way out of a contract (delivery, timeout, retirement,
    ; death) lands on IDLE through here.
    if asNewContractState == CONTRACT_IDLE
        WOSK_Backpack.Strip(akWorker)
    endIf
    ; Fase 30 (D245): the hunter has the bow in hand at the work
    ; site and puts it away for the road and the town.
    if _WorkerProfession(akWorker) == "hunter"
        if asNewContractState == CONTRACT_WORKING
            WOSK_Gear.DrawAtWork(akWorker)
        else
            WOSK_Gear.PutAway(akWorker)
        endIf
    endIf
    ; Queue item 11: this is the single funnel every contract transition goes
    ; through, which is what makes the Workers tab live instead of a snapshot.
    if abPush
        WOSK_PanelBridgeScript.PushPanelState()
    endIf
EndFunction

; WORKING --(sucesso)--> AVAILABLE, --(leve)--> INJURED_MINOR, --(grave)-->
; RETIRED, --(morte)--> DEAD. Delivered batch/gold only apply on a lifecycle
; result that leaves the worker alive to hand it over - matches the
; reference model's apply_incident_to_lifecycle().
Function _ResolveContractCompletion(Actor akWorker)
    ; V014 (D102): an encounter bandit still alive no longer decides anything.
    _UnwatchThreat(akWorker)
    StorageUtil.UnsetFormValue(akWorker, "WOSK_EncounterThreat")
    ; The legs are over; the AWAITING_PICKUP timeout below is armed on its own.
    _ClearContractClock(akWorker)
    ; Fase 15: the gear multiplier stored at issue (1.0 for a contract issued
    ; before it existed, or without a bow).
    Float gearMultiplier = StorageUtil.GetFloatValue(akWorker, "WOSK_ContractGear", 1.0)
    StorageUtil.UnsetFloatValue(akWorker, "WOSK_ContractGear")
    string outcome = StorageUtil.GetStringValue(akWorker, "WOSK_IncidentOutcome", OUTCOME_SUCCESS)
    string profession = _WorkerProfession(akWorker)
    string taskId = StorageUtil.GetStringValue(akWorker, "WOSK_TaskId", "")
    string tier = StorageUtil.GetStringValue(akWorker, "WOSK_Tier", "apprentice")
    Int taskIndex = _FindTaskIndex(profession, taskId)

    if outcome == OUTCOME_SUCCESS
        Float batchMin = WOSK_Registry.GetTaskFloat(profession, taskIndex, "batchMin", 0.0)
        Float batchMax = WOSK_Registry.GetTaskFloat(profession, taskIndex, "batchMax", 0.0)
        Float yieldMultiplier = WOSK_Registry.GetTierFloat(profession, tier, "yieldMultiplier", 1.0) * gearMultiplier
        Float roll = Utility.RandomFloat(0.0, 1.0)
        Int qty = Math.Floor((batchMin + roll * (batchMax - batchMin)) * yieldMultiplier) as Int
        if qty < 1
            qty = 1
        endIf
        Int rolledQty = qty
        ; D105 etapa 3: never more than the reserved veins hold; the veins not
        ; emptied go back to the source. A contract issued before etapa 3 has no
        ; reservation and keeps its rolled batch.
        Int reserved = StorageUtil.GetIntValue(akWorker, "WOSK_ContractVeins", -1)
        Int veinsUsed = -1
        if reserved >= 0
            string slotSource = StorageUtil.GetStringValue(akWorker, "WOSK_ContractSource", "")
            Float unitsPerVein = WOSK_DepletionScript.SourceUnitsPerSlot(MVP_HOLD, slotSource, profession, taskIndex)
            qty = WOSK_DepletionScript.CapDeliveredQty(qty, unitsPerVein, reserved)
            veinsUsed = WOSK_DepletionScript.VeinsUsed(qty, unitsPerVein, reserved)
        endIf
        Debug.Trace("WOSK_WorkerAlias: batch rolled - worker=" + akWorker + " task=" + taskId + " tier=" + tier + \
                    " batchMin=" + batchMin + " batchMax=" + batchMax + " roll=" + roll + \
                    " yieldMultiplier=" + yieldMultiplier + " gear=" + gearMultiplier + " rolled=" + rolledQty + " veinsReserved=" + reserved + \
                    " veinsUsed=" + veinsUsed + " qty=" + qty)
        StorageUtil.SetIntValue(akWorker, "WOSK_PendingDeliveryQty", qty)
        if reserved >= 0
            string sourceId = StorageUtil.GetStringValue(akWorker, "WOSK_ContractSource", "")
            string resourceType = StorageUtil.GetStringValue(akWorker, "WOSK_ContractResourceType", "")
            StorageUtil.UnsetIntValue(akWorker, "WOSK_ContractVeins")
            WOSK_DepletionScript.Settle(MVP_HOLD, sourceId, resourceType, reserved, veinsUsed)
        endIf

        Int completedSoFar = StorageUtil.GetIntValue(akWorker, "WOSK_ContractsCompleted", 0)
        StorageUtil.SetIntValue(akWorker, "WOSK_ContractsCompleted", completedSoFar + 1)
        StorageUtil.SetStringValue(akWorker, "WOSK_Lifecycle", LIFECYCLE_AVAILABLE)
        _MaybeAdvanceTier(akWorker)
        Debug.Notification("Honest Work: your worker has returned with " + qty + " units.")

    else
        _ReleaseContractVeins(akWorker, "outcome " + outcome)
    endIf

    if outcome == OUTCOME_MINOR
        Int priorMinorInjuries = StorageUtil.GetIntValue(akWorker, "WOSK_MinorInjuries", 0)
        StorageUtil.SetIntValue(akWorker, "WOSK_MinorInjuries", priorMinorInjuries + 1)
        StorageUtil.SetStringValue(akWorker, "WOSK_Lifecycle", LIFECYCLE_INJURED_MINOR)
        ; Fase 28 conserto 1 (D238, V060): says what the injury cost - the contract
        ; brought nothing - and that he takes no work until cured.
        Debug.Notification("Honest Work: " + akWorker.GetDisplayName() + " was injured. The contract brought nothing, and they cannot work until cured.")

    elseIf outcome == OUTCOME_MAJOR
        StorageUtil.SetStringValue(akWorker, "WOSK_Lifecycle", LIFECYCLE_RETIRED)
        ; Fase 31 conserto 1 (D257, V063): the worker is named, and the notice says what
        ; it takes to free the place. He stays on the list until the player pays.
        Debug.Notification("Honest Work: " + akWorker.GetDisplayName() + " was badly hurt at work and has retired. Pay " + PensionFee() + " gold to release the place.")

    elseIf outcome == OUTCOME_DEATH
        StorageUtil.SetStringValue(akWorker, "WOSK_Lifecycle", LIFECYCLE_DEAD)
        Debug.Notification("Honest Work: your worker did not survive the contract.")
    endIf

    Debug.Trace("WOSK_WorkerAlias: contract resolved - worker=" + akWorker + " outcome=" + outcome)
    ; Fase 17 (D168): the panel's history. The batch is valued at the game's
    ; own price of the output (the reference price), read before the slot
    ; is cleared below.
    Int deliveredQty = 0
    Int deliveredValue = 0
    if outcome == OUTCOME_SUCCESS
        deliveredQty = StorageUtil.GetIntValue(akWorker, "WOSK_PendingDeliveryQty", 0)
        deliveredValue = Math.Floor(deliveredQty * _TaskUnitPrice(profession, taskIndex) + 0.5) as Int
        if deliveredValue < 0
            deliveredValue = 0
        endIf
    endIf
    WOSK_LedgerScript.RecordOutcome(akWorker, outcome, taskId, deliveredQty, deliveredValue)

    if outcome == OUTCOME_SUCCESS
        _AdvanceTo(akWorker, CONTRACT_AWAITING_PICKUP)
        _ReturnHomeIfConfigured(akWorker)
        RegisterForSingleUpdateGameTime(7.0 * 24.0)
    elseIf outcome == OUTCOME_MINOR
        ; Fase 28 conserto 1 (D238, V060): an injured contract has no batch, so there is
        ; nothing to wait for - straight to IDLE (Cure is a lifecycle order), never an
        ; AWAITING_PICKUP whose Collect hands over zero.
        _AdvanceTo(akWorker, CONTRACT_IDLE)
        _ReturnHomeIfConfigured(akWorker)
    elseIf outcome == OUTCOME_MAJOR
        ; Fase 31 conserto 1 (D257, V063): RETIRED no longer frees the slot nor sends the
        ; worker away. He keeps the place, takes no contract, goes home like an injured
        ; one, and leaves only when the player pays the pension (FireForFee), which ends
        ; in Fire(): SendAway BEFORE Clear, as D104 requires.
        _AdvanceTo(akWorker, CONTRACT_IDLE)
        _ReturnHomeIfConfigured(akWorker)
        WOSK_PanelBridgeScript.PushPanelState()
    else
        ; DEAD -> [slot liberado], no batch to pick up. A dead one leaves its body.
        _AdvanceTo(akWorker, CONTRACT_IDLE)
        Clear()
        ; After Clear(), not before: the list is built from the aliases that still hold an actor.
        WOSK_PanelBridgeScript.PushPanelState()
    endIf
EndFunction

; D149 (Fase 12, V029 p.4): housecarl path. Same as PickUp but delivers to
; akHousecarl's inventory instead of the player's. Caller must have verified
; Thane + housecarl alive; this function only validates the batch is ready
; and logs the housecarl FormID before AddItem (contract 6 before 7).
Bool Function CollectViaHousecarl(Actor akHousecarl)
    if !akHousecarl
        Debug.Trace("WOSK_WorkerAlias: CollectViaHousecarl refused - no housecarl")
        Debug.Notification("Honest Work: no housecarl assigned for this hold.")
        _Outcome("collect", "NO_HOUSECARL")
        return false
    endIf
    return _PickUpTo(akHousecarl)
EndFunction

; Player collects the batch (called externally, e.g. by
; WOSK_PanelBridgeScript). Returns false if there is nothing pending.
; D105 etapa 2 (2026-09-15): a refusal tells the player why - it used
; to be silent, and the panel always says "requested" - and a worker already
; home while TRAVELING_BACK has the contract resolved now instead of waiting
; for the clock. The rolled outcome stands; a road encounter not yet due is
; skipped, as it would be by the worker arriving.
;
; Fase 28 conserto 1 (D238, V060): abRequireNear is the panel's Collect - it
; works only with the worker and the player in the same cell (open ground: within
; NearPickupUnits). The dialogue's "I want to collect" passes false: speaking to the
; worker is already being near. The housecarl path never asks for it.
Bool Function PickUp(Bool abRequireNear = false)
    return _PickUpTo(Game.GetPlayer(), abRequireNear)
EndFunction

Float Function NearPickupUnits() global
    return 1500.0
EndFunction

; Same cell as the player; on open ground (a cell there is a 4096-unit square) the
; same worldspace within NearPickupUnits, the worker loaded. ASSUMPTION (D238): the
; outdoor radius is a guess at "close enough to walk up to"; the maintainer judges it.
Bool Function _IsNearPlayer(Actor akWorker)
    Actor player = Game.GetPlayer()
    if !akWorker || !player
        return false
    endIf
    Cell workerCell = akWorker.GetParentCell()
    if workerCell && workerCell == player.GetParentCell()
        return true
    endIf
    if akWorker.GetWorldSpace() && akWorker.Is3DLoaded() && _SameSpace(akWorker, player)
        return akWorker.GetDistance(player) <= NearPickupUnits()
    endIf
    return false
EndFunction

; What the Workers tab gets in the hours field (the DLL passes the float as it is):
; the running contract's hours left, or for a worker AWAITING_PICKUP a code below
; -1 that the page words (model.ts PICKUP_*): -2 collectable now, -3 too far from
; the player, -4 nothing to collect.
Float Function PanelHoursLeft()
    Actor worker = GetActorRef()
    if worker && StorageUtil.GetStringValue(worker, "WOSK_Contract", CONTRACT_IDLE) == CONTRACT_AWAITING_PICKUP
        if StorageUtil.GetIntValue(worker, "WOSK_PendingDeliveryQty", 0) <= 0
            return -4.0
        endIf
        if !_IsNearPlayer(worker)
            return -3.0
        endIf
        return -2.0
    endIf
    return ContractHoursLeft()
EndFunction

Bool Function _PickUpTo(ObjectReference akTarget, Bool abRequireNear = false)
    Actor worker = GetActorRef()
    if !worker
        Debug.Trace("WOSK_WorkerAlias: PickUp refused - slot " + GetID() + " is empty")
        Debug.Notification("Honest Work: nobody is hired in slot " + GetID() + ".")
        _Outcome("collect", "EMPTY")
        return false
    endIf
    string contract = StorageUtil.GetStringValue(worker, "WOSK_Contract", CONTRACT_IDLE)
    if contract == CONTRACT_TRAVELING_BACK && _IsAtHome(worker)
        Debug.Trace("WOSK_WorkerAlias: " + worker + " already home while TRAVELING_BACK, contract resolved on pickup " + _WhereString(worker))
        UnregisterForUpdateGameTime()
        ActorUtil.RemovePackageOverride(worker, _TravelPackage())
        WOSK_PlayerHouse.StopCooking(worker)
        _ResolveContractCompletion(worker)
        if GetActorRef() != worker
            ; RETIRED/DEAD: resolved, alias cleared, nothing to hand over.
            _Outcome("collect", "RESOLVED")
            return false
        endIf
        contract = StorageUtil.GetStringValue(worker, "WOSK_Contract", CONTRACT_IDLE)
        if contract == CONTRACT_IDLE
            ; An injury ended it: no batch, and the injury was already said.
            _Outcome("collect", "RESOLVED")
            return false
        endIf
    endIf
    if contract != CONTRACT_AWAITING_PICKUP
        string reason = " has no batch to pick up."
        if contract == CONTRACT_TRAVELING_TO
            reason = " is still on the way to the source."
        elseIf contract == CONTRACT_WORKING
            reason = " is still working at the source."
        elseIf contract == CONTRACT_TRAVELING_BACK
            reason = " is still on the way back."
        endIf
        Debug.Trace("WOSK_WorkerAlias: PickUp refused - " + worker + " contract=" + contract + " " + _WhereString(worker))
        Debug.Notification("Honest Work: " + worker.GetDisplayName() + reason)
        _Outcome("collect", "NOT_READY", contract)
        return false
    endIf
    Int qty = StorageUtil.GetIntValue(worker, "WOSK_PendingDeliveryQty", 0)
    string taskId = StorageUtil.GetStringValue(worker, "WOSK_TaskId", "")
    if qty <= 0
        ; Fase 28 conserto 1 (D238): a Collect that hands over zero is never silent. A
        ; contract that left no batch (a save from before the injured contract went to
        ; IDLE) is closed here, and the player is told.
        Debug.Trace("WOSK_WorkerAlias: PickUp with no batch - " + worker + " task=" + taskId + " qty=" + qty + ", contract closed")
        Debug.Notification("Honest Work: " + worker.GetDisplayName() + " has nothing to hand over.")
        StorageUtil.UnsetIntValue(worker, "WOSK_PendingDeliveryQty")
        _AdvanceTo(worker, CONTRACT_IDLE)
        _ReturnHomeIfConfigured(worker)
        _Outcome("collect", "NO_BATCH")
        return false
    endIf
    if abRequireNear && !_IsNearPlayer(worker)
        Debug.Trace("WOSK_WorkerAlias: PickUp refused - " + worker + " is not near the player " + _WhereString(worker) + " playerCell=" + Game.GetPlayer().GetParentCell())
        Debug.Notification("Honest Work: " + worker.GetDisplayName() + " is too far away. Go to them to collect.")
        _Outcome("collect", "TOO_FAR")
        return false
    endIf
    Int taskIndex = _FindTaskIndex(_WorkerProfession(worker), taskId)
    ObjectReference dest = akTarget
    ; Housecarl path logs FormID explicitly (D149).
    if akTarget != Game.GetPlayer()
        Debug.Trace("WOSK_WorkerAlias: PickUp delivering to housecarl - " + worker + " task=" + taskId + " qty=" + qty + " housecarl=" + akTarget + " housecarlFormID=" + (akTarget as Actor).GetFormID())
        dest = akTarget
    else
        dest = _DeliveryTargetOr(worker, Game.GetPlayer())
        Debug.Trace("WOSK_WorkerAlias: PickUp delivering - " + worker + " task=" + taskId + " qty=" + qty + " to=" + dest)
    endIf
    if qty > 0 && taskIndex >= 0
        _DeliverTaskOutputs(dest, _WorkerProfession(worker), taskIndex, qty)
    endIf
    StorageUtil.UnsetIntValue(worker, "WOSK_PendingDeliveryQty")
    _AdvanceTo(worker, CONTRACT_IDLE)
    _ReturnHomeIfConfigured(worker)
    if akTarget != Game.GetPlayer()
        Debug.Notification("Honest Work: " + qty + " units delivered to your housecarl.")
        _Outcome("collect", "COLLECTED", "HOUSECARL", qty)
    else
        _Outcome("collect", "COLLECTED", "", qty)
    endIf
    return true
EndFunction

Function _DepositToShipmentChestAndFree(Actor akWorker)
    ; "Deposita o lote num bau de remessa" - no shipment chest reference
    ; exists yet in this project; the batch is handed to the delivery
    ; target configured for this hold (D078), or, if
    ; none was set, straight to the worker's own inventory (default,
    ; unchanged since Fase 5) - either way the player can still recover it.
    Int qty = StorageUtil.GetIntValue(akWorker, "WOSK_PendingDeliveryQty", 0)
    string taskId = StorageUtil.GetStringValue(akWorker, "WOSK_TaskId", "")
    string profession = _WorkerProfession(akWorker)
    Int taskIndex = _FindTaskIndex(profession, taskId)
    if qty > 0 && taskIndex >= 0
        _DeliverTaskOutputs(_DeliveryTargetOr(akWorker, akWorker), profession, taskIndex, qty)
    endIf
    StorageUtil.UnsetIntValue(akWorker, "WOSK_PendingDeliveryQty")
    _AdvanceTo(akWorker, CONTRACT_IDLE)
    _ReturnHomeIfConfigured(akWorker)
EndFunction

; Hands a waiting batch over on dismissal and returns the sentence to append
; to the dismissal notification - "" when there is nothing waiting. The target
; is the hold's configured delivery target (D078) or the player,
; never the worker: see the comment on Fire() for why this does not reuse
; _DepositToShipmentChestAndFree.
string Function _HandOverPendingBatch(Actor akWorker)
    Int qty = StorageUtil.GetIntValue(akWorker, "WOSK_PendingDeliveryQty", 0)
    if qty <= 0
        return ""
    endIf
    string taskId = StorageUtil.GetStringValue(akWorker, "WOSK_TaskId", "")
    string profession = _WorkerProfession(akWorker)
    Int taskIndex = _FindTaskIndex(profession, taskId)
    StorageUtil.UnsetIntValue(akWorker, "WOSK_PendingDeliveryQty")
    if taskIndex < 0
        Debug.Trace("WOSK_WorkerAlias: dismissal with qty=" + qty + " but task '" + taskId + \
                    "' is unknown to profession '" + profession + "' - nothing to hand over")
        return ""
    endIf
    ObjectReference target = _DeliveryTargetOr(akWorker, Game.GetPlayer())
    Debug.Trace("WOSK_WorkerAlias: dismissal handing over - " + akWorker + " task=" + taskId + \
                " qty=" + qty + " to=" + target)
    _DeliverTaskOutputs(target, profession, taskIndex, qty)
    return " " + qty + " units handed over."
EndFunction

Function Cure()
    Actor worker = GetActorRef()
    if worker && StorageUtil.GetStringValue(worker, "WOSK_Lifecycle", "") == LIFECYCLE_INJURED_MINOR
        StorageUtil.SetStringValue(worker, "WOSK_Lifecycle", LIFECYCLE_AVAILABLE)
        Debug.Trace("WOSK_WorkerAlias: " + worker + " cured, back to AVAILABLE")
        ; Lifecycle changes do not pass through _AdvanceTo, so the Workers tab
        ; is pushed here too - it prints the lifecycle over the contract state.
        WOSK_PanelBridgeScript.PushPanelState()
        _Outcome("cure", "CURED")
    elseIf worker
        _Outcome("cure", "NOT_INJURED", StorageUtil.GetStringValue(worker, "WOSK_Lifecycle", ""))
    else
        _Outcome("cure", "EMPTY")
    endIf
EndFunction

; 2026-09-21 (Parte 2 em jogo): dismissing a worker used to be completely
; silent - no notification at all - and it dropped WOSK_PendingDeliveryQty on
; the floor. The batch never exists as an item (only PickUp's
; _DeliverTaskOutputs creates one), so firing a worker sitting in
; AWAITING_PICKUP made the units AND the gold that paid for them vanish with
; nothing written anywhere. The 7-day timeout already answers the same
; situation - batch ready, nobody collected - by handing it over
; (_DepositToShipmentChestAndFree), so dismissal answers it the same way.
; _DepositToShipmentChestAndFree itself is NOT reusable here: its fallback
; target is the worker's own inventory, and a dismissed worker is disabled
; and (when run-time created) deleted, which would destroy the batch instead
; of delivering it. The fallback here is the player, as in PickUp().
Function Fire()
    Actor worker = GetActorRef()
    Int workerFormId = 0
    string handedOver = ""
    if worker
        workerFormId = worker.GetFormID()
        Debug.Trace("WOSK_WorkerAlias: " + worker + " dismissed")
        ActorUtil.ClearPackageOverride(worker)
        ; D223: a dismissed worker no longer lives in the player's house.
        WOSK_PlayerHouse.ClearHouse(worker)
        ; Fase 25 (D227): a dismissed worker does not keep the backpack.
        WOSK_Backpack.Strip(worker)
        UnregisterForUpdateGameTime()
        _UnwatchThreat(worker)
        StorageUtil.UnsetFormValue(worker, "WOSK_EncounterThreat")
        _ReleaseContractVeins(worker, "dismissed")
        _ClearContractClock(worker)
        handedOver = _HandOverPendingBatch(worker)
        if StorageUtil.GetStringValue(worker, "WOSK_Lifecycle", "") == LIFECYCLE_RETIRED
            Debug.Notification("Honest Work: " + worker.GetDisplayName() + " has been pensioned off." + handedOver)
        else
            Debug.Notification("Honest Work: " + worker.GetDisplayName() + " has been dismissed." + handedOver)
        endIf
        if StorageUtil.GetStringValue(worker, "WOSK_Lifecycle", "") == LIFECYCLE_RETIRED
            _Outcome("dismiss", "PENSIONED", worker.GetDisplayName())
        else
            _Outcome("dismiss", "DISMISSED", worker.GetDisplayName())
        endIf
    endIf
    ; D104: a dismissed worker leaves the game. SendAway runs BEFORE Clear():
    ; the filled alias is the only persistence anchor of a run-time actor, so
    ; clearing it first frees the form and every call after that finds no
    ; native object bound - the CTD measured in 2026-09-21, Parte 2.
    WOSK_PanelBridgeScript.GetController().SendAway(worker, workerFormId)
    Clear()
    ; After Clear(), not before: the row has to disappear from the tab, and the
    ; list is built by reading which aliases still hold an actor.
    WOSK_PanelBridgeScript.PushPanelState()
EndFunction

; Fase 31 (D248): what dismissing this worker costs, in gold. A fraction of the tier's
; hiringFee, high on the day of the hire and falling linearly to a floor after
; dismissFeeDays days of service (all three in professions\*.json). A worker with no
; hire day on record (hired before this version) is read as long in service: the floor.
; A contract in progress is neither refunded nor charged extra: the fee is only this.
Int Function DismissalFee()
    Actor worker = GetActorRef()
    if !worker
        return 0
    endIf
    ; Fase 31 conserto 1 (D257): a worker retired by an accident is released for the
    ; pension, not for the dismissal fee; the panel reads this one number for both.
    if StorageUtil.GetStringValue(worker, "WOSK_Lifecycle", "") == LIFECYCLE_RETIRED
        return PensionFee()
    endIf
    string profession = StorageUtil.GetStringValue(worker, "WOSK_Profession", "miner")
    string tier = StorageUtil.GetStringValue(worker, "WOSK_Tier", "apprentice")
    Float hiring = WOSK_Registry.GetTierInt(profession, tier, "hiringFee", 0) as Float
    Float startFrac = WOSK_Registry.GetTierFloat(profession, tier, "dismissFeeStart", 0.0)
    Float floorFrac = WOSK_Registry.GetTierFloat(profession, tier, "dismissFeeFloor", 0.0)
    Float span = WOSK_Registry.GetTierInt(profession, tier, "dismissFeeDays", 1) as Float
    if span < 1.0
        span = 1.0
    endIf
    Float served = span
    if StorageUtil.HasFloatValue(worker, "WOSK_HiredDay")
        served = Utility.GetCurrentGameTime() - StorageUtil.GetFloatValue(worker, "WOSK_HiredDay", 0.0)
    endIf
    if served < 0.0
        served = 0.0
    endIf
    Float t = served / span
    if t > 1.0
        t = 1.0
    endIf
    Float frac = startFrac - (startFrac - floorFrac) * t
    return Math.Floor(hiring * frac + 0.5)
EndFunction

; Fase 31 conserto 1 (D257, V063): what releasing a worker retired by a MAJOR accident
; costs - the tier's hiringFee times pensionMultiplier (3.0 by default, per tier in
; professions\*.json, the maintainer tunes it there). A contract in progress does not exist
; for him: a retired worker has none.
Int Function PensionFee()
    Actor worker = GetActorRef()
    if !worker
        return 0
    endIf
    string profession = StorageUtil.GetStringValue(worker, "WOSK_Profession", "miner")
    string tier = StorageUtil.GetStringValue(worker, "WOSK_Tier", "apprentice")
    Float hiring = WOSK_Registry.GetTierInt(profession, tier, "hiringFee", 0) as Float
    Float mult = WOSK_Registry.GetTierFloat(profession, tier, "pensionMultiplier", 3.0)
    Int fee = Math.Floor(hiring * mult + 0.5)
    if fee < 0
        fee = 0
    endIf
    return fee
EndFunction

; The dismissal the player asks for - the panel and the dialogue both come here. Without
; the fee in the pocket it is refused and the worker stays (D248, alternative dropped:
; charging "what there is"). Fire() itself stays free: it is the clean-up every other
; path and the tests use. Returns true when the worker was dismissed.
Bool Function FireForFee()
    Actor worker = GetActorRef()
    if !worker
        return false
    endIf
    Int fee = DismissalFee()
    Bool pension = StorageUtil.GetStringValue(worker, "WOSK_Lifecycle", "") == LIFECYCLE_RETIRED
    string what = "dismissing "
    if pension
        what = "pensioning off "
    endIf
    if fee > 0
        Actor player = Game.GetPlayer()
        Form goldForm = Game.GetFormFromFile(0x0000000F, "Skyrim.esm")
        Int have = player.GetItemCount(goldForm)
        if have < fee
            Debug.Trace("WOSK_WorkerAlias: " + what + "refused, fee " + fee + " gold, player has " + have)
            Debug.Notification("Honest Work: " + what + worker.GetDisplayName() + " costs " + fee + " gold; you carry " + have + ".")
            if pension
                _Outcome("dismiss", "PENSION_GOLD", "" + have, fee)
            else
                _Outcome("dismiss", "GOLD", "" + have, fee)
            endIf
            return false
        endIf
        player.RemoveItem(goldForm, fee, true)
        Debug.Trace("WOSK_WorkerAlias: " + what + "fee " + fee + " gold paid for " + worker)
        if pension
            ; The totals count it as gold spent, and the statement says it by name.
            StorageUtil.AdjustIntValue(None, "WOSK_StatGoldSpent", fee)
            WOSK_LedgerScript.RecordEvent("PENSIONED", worker, "", 0, fee)
        endIf
    elseIf pension
        WOSK_LedgerScript.RecordEvent("PENSIONED", worker, "", 0, 0)
    endIf
    Fire()
    return true
EndFunction

; ---------------------------------------------------------------------------
; Encounter on the road
; ---------------------------------------------------------------------------

Function CheckEncounter()
    Actor worker = GetActorRef()
    if !worker
        return
    endIf
    if StorageUtil.GetIntValue(worker, "WOSK_EncounterResolved", 0) != 0
        return
    endIf
    string outcome = StorageUtil.GetStringValue(worker, "WOSK_IncidentOutcome", OUTCOME_SUCCESS)
    if outcome == OUTCOME_SUCCESS
        return
    endIf
    if !StorageUtil.HasFloatValue(worker, "WOSK_IncidentEventGameTime")
        return
    endIf
    Float eventTime = StorageUtil.GetFloatValue(worker, "WOSK_IncidentEventGameTime", 0.0)
    Float nowHours = Utility.GetCurrentGameTime() * 24.0
    if nowHours < eventTime || nowHours > eventTime + ENCOUNTER_WINDOW_HOURS
        return
    endIf

    Actor player = Game.GetPlayer()
    if player.GetDistance(worker) > ENCOUNTER_RADIUS_UNITS
        return
    endIf

    StorageUtil.SetIntValue(worker, "WOSK_EncounterResolved", 1)
    Debug.Trace("WOSK_WorkerAlias: encounter triggered for " + worker)
    worker.EnableAI(true)
    ActorBase threatBase = Game.GetFormFromFile(0x000F62D7, "Skyrim.esm") as ActorBase
    ; // ASSUMPTION: no spec pins down a threat "conforme tier da tarefa" -
    ; one generic confirmed-real leveled bandit (LvlBanditMeleeAnyAggro1536)
    ; is used for every tier for now, not a per-tier roster.
    if threatBase
        ; V014 (D102): kept so OnActorKilled can tell this bandit's death apart
        ; from any other kill in the game.
        Actor threat = worker.PlaceActorAtMe(threatBase)
        StorageUtil.SetFormValue(worker, "WOSK_EncounterThreat", threat)
        _WatchThreat(threat)
    endIf
EndFunction

; Fase 21 (D216): the DLL (WOSK_Native) tells this alias when the stored
; encounter bandit dies; the mod event registration lives in the save, the
; DLL's watch list does not (RestoreTravelTarget watches again on load).
Function _WatchThreat(Actor akThreat)
    RegisterForModEvent("WOSK_EncounterThreatKilled", "OnEncounterThreatKilled")
    WOSK_Native.WatchEncounterThreat(akThreat)
EndFunction

; Call BEFORE the stored threat is unset: it is what tells the DLL which
; bandit to stop watching.
Function _UnwatchThreat(Actor akWorker)
    UnregisterForModEvent("WOSK_EncounterThreatKilled")
    Actor threat = StorageUtil.GetFormValue(akWorker, "WOSK_EncounterThreat", None) as Actor
    if threat
        WOSK_Native.UnwatchEncounterThreat(threat)
    endIf
EndFunction

; V014 (D102): the road-encounter bandit dying while the worker
; is alive saves the contract - whoever killed it, the rolled outcome is
; annulled into SUCCESS. The DLL only sends this for the bandit it was told to
; watch; the check against the stored bandit stays as a guard. asKillerId is
; the killer's FormID in decimal ("0": no killer).
Event OnEncounterThreatKilled(string asEventName, string asKillerId, float afNum, Form akSender)
    Actor worker = GetActorRef()
    if !worker
        return
    endIf
    Actor threat = StorageUtil.GetFormValue(worker, "WOSK_EncounterThreat", None) as Actor
    if !threat || akSender != threat
        return
    endIf
    _UnwatchThreat(worker)
    StorageUtil.UnsetFormValue(worker, "WOSK_EncounterThreat")
    if worker.IsDead()
        return
    endIf
    StorageUtil.SetStringValue(worker, "WOSK_IncidentOutcome", OUTCOME_SUCCESS)
    Debug.Trace("WOSK_WorkerAlias: encounter bandit " + akSender + " killed (killer id " + asKillerId + ") with " + worker + " alive, outcome overridden to SUCCESS")
EndEvent

; V014 (D102): the worker dying is DEATH whoever the killer is - the old rule
; turned "the player killed the worker" into SUCCESS - and it is applied at
; once, with or without a contract running, so the slot is freed.
; D105 etapa 2 (test 2026-09-15): the player is told right away - until then a
; worker killed in the field only reached the log.
Event OnDeath(Actor akKiller)
    Actor worker = GetActorRef()
    if !worker
        return
    endIf
    Debug.Trace("WOSK_WorkerAlias: " + worker + " died (killer=" + akKiller + "), outcome DEATH, slot freed")
    _TracePosition(worker, "died")
    Debug.Notification("Honest Work: your worker " + worker.GetDisplayName() + " has died.")
    ; The ledger line goes in HERE, before the teardown below, and the order is
    ; the whole reason this is not two lines lower: _ReleaseContractVeins()
    ; unsets the contract keys, Clear() releases the alias, and after either one
    ; the where and the owning quest are gone. The notification above tells the
    ; player it happened; this is what he can still read tomorrow.
    WOSK_LedgerScript.RecordDeath(GetOwningQuest(), worker.GetDisplayName(), _PlaceWords(worker), \
                                  Utility.GetCurrentGameTime(), _KillerName(akKiller))
    ; Fase 17 (D168): the statement and the worker's own history. A death
    ; settled by _ResolveContractCompletion never reaches here alive, so this
    ; does not record the same death twice.
    WOSK_LedgerScript.RecordOutcome(worker, OUTCOME_DEATH, StorageUtil.GetStringValue(worker, "WOSK_TaskId", ""), 0, 0)
    UnregisterForUpdateGameTime()
    _UnwatchThreat(worker)
    ActorUtil.ClearPackageOverride(worker)
    ; Fase 27 (D232): the trade's outfit goes back to the original one.
    ; Fase 30 (D244): a dead hunter keeps what the player gave him (on the corpse).
    WOSK_Outfits.Restore(worker, false)
    StorageUtil.UnsetFormValue(worker, "WOSK_EncounterThreat")
    _ReleaseContractVeins(worker, "death")
    _ClearContractClock(worker)
    StorageUtil.SetStringValue(worker, "WOSK_IncidentOutcome", OUTCOME_DEATH)
    StorageUtil.SetStringValue(worker, "WOSK_Lifecycle", LIFECYCLE_DEAD)
    ; D175 (V046, ENC06): the panel push inside _AdvanceTo takes about 3 s of real
    ; time (the source list is rebuilt), and Clear() came after it, so for those
    ; seconds a dead worker still held the slot: the harness read slot 0 full
    ; 5 s after the kill, and a hire in that window would have been refused.
    ; The slot is freed first now; the one push below shows the empty row.
    _AdvanceTo(worker, CONTRACT_IDLE, false)
    WOSK_WorkerState.Clear(worker)
    Clear()
    Debug.Trace("WOSK_WorkerAlias: death - alias cleared, now holds " + GetActorRef())
    WOSK_PanelBridgeScript.PushPanelState()
EndEvent

; V023 (probe, measures only): a worker caught near a fight crouched and walked
; the rest of the route sneaking. The packages have no sneak flag (read in
; Skyrim.esm), so this logs what the actor itself reports when combat starts
; and ends, and again 10 and 60 seconds after it ends, to show whether the
; sneak or the alert state sticks. aeCombatState: 0 none, 1 combat, 2 searching.
Event OnCombatStateChanged(Actor akTarget, int aeCombatState)
    Actor worker = GetActorRef()
    if !worker
        return
    endIf
    _TraceCombat(worker, "combat state " + aeCombatState + " (target=" + akTarget + ")")
    if aeCombatState != 0
        return
    endIf
    Utility.Wait(10.0)
    if GetActorRef() == worker && !worker.IsDead()
        _TraceCombat(worker, "10s after leaving combat")
    endIf
    Utility.Wait(50.0)
    if GetActorRef() == worker && !worker.IsDead()
        _TraceCombat(worker, "60s after leaving combat")
    endIf
EndEvent

; ---------------------------------------------------------------------------
; Helpers - professions.json lookups, tier math, package selection, resource
; item delivery.
; ---------------------------------------------------------------------------

; (D078): the id a worker was hired
; under. Not settable from here on purpose - hiring flow assignment is out
; of MVP scope ("outras profissoes ... fora do escopo
; do MVP"); the default keeps every MVP worker exactly "miner", unchanged
; behavior. WOSK_ControllerScript.GetWorkerProfession() reads the same key.
string Function _WorkerProfession(Actor akWorker)
    return StorageUtil.GetStringValue(akWorker, "WOSK_Profession", "miner")
EndFunction

; -1 when the profession or the task id does not exist. Both are matched
; ignoring case, in C++ (B003, D099).
Int Function _FindTaskIndex(string asProfession, string asTaskId)
    return WOSK_Registry.FindTaskIndex(asProfession, asTaskId)
EndFunction

Int Property TIER_APPRENTICE_RANK = 0 Auto Hidden
Int Property TIER_WORKER_RANK = 1 Auto Hidden
Int Property TIER_VETERAN_RANK = 2 Auto Hidden
Int Property TIER_MASTER_RANK = 3 Auto Hidden

Int Function _TierRank(string asTierId)
    if asTierId == "worker"
        return TIER_WORKER_RANK
    elseIf asTierId == "veteran"
        return TIER_VETERAN_RANK
    elseIf asTierId == "master"
        return TIER_MASTER_RANK
    endIf
    return TIER_APPRENTICE_RANK
EndFunction

Bool Function _MeetsMinTier(string asWorkerTier, string asTaskMinTier)
    return _TierRank(asWorkerTier) >= _TierRank(asTaskMinTier)
EndFunction

; chance_final formula, verbatim from the reference model's
; compute_incident_chance().
Float Function _ComputeIncidentChance(Float afBaseChance, Float afTierModifier, Int aiPreviousMinorInjuries, Float afArmorValueTotal)
    Float modificadorFerimentos = 0.01 * (aiPreviousMinorInjuries as Float)
    Float armorReduction = afArmorValueTotal / 2000.0
    if armorReduction > 0.15
        armorReduction = 0.15
    endIf
    Float chance = afBaseChance + afTierModifier + modificadorFerimentos - armorReduction
    if chance < 0.01
        chance = 0.01
    elseIf chance > 0.60
        chance = 0.60
    endIf
    return chance
EndFunction

; (D078): outcome table lookup,
; replacing the fixed 0.55/0.85 thresholds with data read from
; contract_types/*.json (merged). "upTo" rows are cumulative upper bounds in
; ascending order (mirrors the old strict "<" chain exactly - the MVP's only
; contract type, "collection", ships the same 0.55/0.85/1.01 breakpoints, so
; behavior is unchanged, only the mechanism is now data-driven).
string Function _ResolveOutcome(string asContractType, Float afRoll2)
    Int count = WOSK_Registry.CountOutcomeRows(asContractType)
    Int i = 0
    while i < count
        Float upTo = WOSK_Registry.GetOutcomeRowFloat(asContractType, i, "upTo", 1.01)
        if afRoll2 < upTo
            return WOSK_Registry.GetOutcomeRowString(asContractType, i, "outcome", OUTCOME_DEATH)
        endIf
        i += 1
    endwhile
    ; No contract_types/*.json shipped or the type is unknown - fall back to
    ; the MVP's own fixed table rather than silently returning SUCCESS,
    ; which would hide a real incident (never fail silently into
    ; "nothing happened").
    if afRoll2 < 0.55
        return OUTCOME_MINOR
    elseIf afRoll2 < 0.85
        return OUTCOME_MAJOR
    endIf
    return OUTCOME_DEATH
EndFunction

; The hours the contract was SOLD for - never what is left of it. The old name
; (_RemainingTaskHours) said the opposite of what the body does, and the caller
; that divided it by 3 every firing is exactly how the legs stopped adding up
; (2026-09-21). The stamp written at issue time wins; the registry lookup is the
; fallback for a contract issued before the stamp existed.
Float Function _ContractTaskHours(Actor akWorker)
    Float stored = StorageUtil.GetFloatValue(akWorker, "WOSK_ContractTaskHours", -1.0)
    if stored > 0.0
        return stored
    endIf
    string profession = _WorkerProfession(akWorker)
    string taskId = StorageUtil.GetStringValue(akWorker, "WOSK_TaskId", "")
    Int taskIndex = _FindTaskIndex(profession, taskId)
    if taskIndex < 0
        return 24.0
    endIf
    return WOSK_Registry.GetTaskFloat(profession, taskIndex, "hours", 24.0)
EndFunction

; Tier advances by contracts completed alive, never regresses.
Function _MaybeAdvanceTier(Actor akWorker)
    string profession = _WorkerProfession(akWorker)
    string current = StorageUtil.GetStringValue(akWorker, "WOSK_Tier", "apprentice")
    Int completed = StorageUtil.GetIntValue(akWorker, "WOSK_ContractsCompleted", 0)
    string best = current
    string[] tiers = new string[4]
    tiers[0] = "apprentice"
    tiers[1] = "worker"
    tiers[2] = "veteran"
    tiers[3] = "master"
    Int i = 0
    while i < 4
        Int minContracts = WOSK_Registry.GetTierInt(profession, tiers[i], "minContracts", 0)
        if completed >= minContracts && _TierRank(tiers[i]) >= _TierRank(best)
            best = tiers[i]
        endIf
        i += 1
    endwhile
    if best != current
        StorageUtil.SetStringValue(akWorker, "WOSK_Tier", best)
        Debug.Trace("WOSK_WorkerAlias: " + akWorker + " tier " + current + " -> " + best)
    endIf
EndFunction

; D105 etapa 3: gives back to the source every vein a contract reserved and did
; not empty. Called when the contract ends without a batch (incident, death,
; dismissal); a no-op once the reservation was settled.
Function _ReleaseContractVeins(Actor akWorker, string asWhy)
    Int reserved = StorageUtil.GetIntValue(akWorker, "WOSK_ContractVeins", -1)
    if reserved < 0
        return
    endIf
    string sourceId = StorageUtil.GetStringValue(akWorker, "WOSK_ContractSource", "")
    string resourceType = StorageUtil.GetStringValue(akWorker, "WOSK_ContractResourceType", "")
    StorageUtil.UnsetIntValue(akWorker, "WOSK_ContractVeins")
    StorageUtil.UnsetFloatValue(akWorker, "WOSK_ContractGear")
    if sourceId == "" || resourceType == ""
        return
    endIf
    Debug.Trace("WOSK_WorkerAlias: " + akWorker + " releases " + reserved + " vein(s) of " + resourceType + " at " + sourceId + " (" + asWhy + ")")
    WOSK_DepletionScript.Settle(MVP_HOLD, sourceId, resourceType, reserved, 0)
EndFunction

; (D078, D149): moves akWorker to the
; hold's configured home - the inn of the hold. Rule, not coincidence:
; outside an active contract (IDLE/AWAITING_PICKUP after pickup or deposit,
; or after Fire/Clear), the worker is at the inn. Resolution order:
; WOSK_WorkerHome (Fase 24, the player's house he lives in) -> HoldHome_0
; (SetWorkerHome) -> WOSK_HomeMarker (candidate spot saved at
; hire, each marker is in WhiterunBanneredMare 0x0001605E, D074 anchor
; ACHR 0x0001A671 etc + offset 80) -> marker 0x01000810 (fallback).
; So even without an explicit SetWorkerHome call the worker returns to
; the inn via HomeMarker/_HomeTarget.
Function _ReturnHomeIfConfigured(Actor akWorker)
    ObjectReference home = _HomeTarget(akWorker)
    if home && _WorkerProfession(akWorker) == "cook" && _SameSpace(akWorker, home)
        ; D234: the cook is already in his house, at the pot; no jump back to the marker.
        Debug.Trace("WOSK_WorkerAlias: " + akWorker + " is already in his house - not moved")
        WOSK_PlayerHouse.StayHome(akWorker)
    elseIf home
        akWorker.MoveTo(home)
        Debug.Trace("WOSK_WorkerAlias: " + akWorker + " sent home to " + home + " (inn rule D149)")
        ; D223: a worker who lives in the player's house stays inside it.
        WOSK_PlayerHouse.StayHome(akWorker)
        ; Fase 33 etapa 2 (D263, V065): the line after the move, and a recheck when it did not land.
        _AfterMove(akWorker, home, "sent home")
    endIf
EndFunction

; Fase 33 etapa 2 (D263, V065): the line after EVERY MoveTo that sends a worker home - the
; cell he is in now, the cell of the marker, whether his 3D is up and the distance. The
; round-9 hunter was "sent home" from the open road after a load and was never seen in the
; Drunken Huntsman; nothing recorded where the move left her. Returns true when he is in
; the marker's cell. A marker whose cell does not read counts as landed (it cannot be
; checked; the line says so) so an unreadable cell cannot make a loop.
Bool Function _AfterMove(Actor akWorker, ObjectReference akHome, string asWhy)
    Cell homeCell = akHome.GetParentCell()
    Cell nowCell = akWorker.GetParentCell()
    Bool landed = true
    string verdict = "landed"
    if !homeCell
        verdict = "unchecked (marker cell does not read)"
    elseIf nowCell != homeCell
        landed = false
        verdict = "NOT LANDED"
    endIf
    string dist = "n/a (other space)"
    if _SameSpace(akWorker, akHome)
        dist = "" + (akWorker.GetDistance(akHome) as Int)
    endIf
    Debug.Trace("WOSK_WorkerAlias: AFTER-MOVE " + asWhy + " - worker=" + akWorker + " " + verdict + " cell=" + nowCell + " homeCell=" + homeCell + \
                " loaded=" + akWorker.Is3DLoaded() + " dist=" + dist + " contract=" + StorageUtil.GetStringValue(akWorker, "WOSK_Contract", CONTRACT_IDLE))
    if !landed
        StorageUtil.SetIntValue(akWorker, "WOSK_HomeRecheck", 1)
        RegisterForSingleUpdate(3.0)
    endIf
    return landed
EndFunction

; Fase 33 etapa 2 (D263, V065): "who comes back, arrives". A worker with no running contract
; (IDLE, or AWAITING_PICKUP) is in the cell of his home marker; if he is not, he is sent
; home again. Called at every game load (RestoreTravelTarget), at every cell load of the
; player (the home cell loaded is the one move that cannot fail), when a panel opens, and
; 3 s after a move that did not land (asWhy "recheck", at most 4 in a row). Returns true when
; he is, or ends up, in the cell. The harness turns it off with the player key WOSK_NoHomeFix.
Bool Function EnsureAtHome(string asWhy)
    Actor worker = GetActorRef()
    if !worker || worker.IsDead()
        return false
    endIf
    string contract = StorageUtil.GetStringValue(worker, "WOSK_Contract", CONTRACT_IDLE)
    if contract != CONTRACT_IDLE && contract != CONTRACT_AWAITING_PICKUP
        return false
    endIf
    if StorageUtil.GetIntValue(Game.GetPlayer(), "WOSK_NoHomeFix", 0) == 1
        return false
    endIf
    ObjectReference home = _HomeTarget(worker)
    if !home
        return false
    endIf
    Cell homeCell = home.GetParentCell()
    if !homeCell
        return false
    endIf
    if worker.GetParentCell() == homeCell
        StorageUtil.UnsetIntValue(worker, "WOSK_HomeFixN")
        return true
    endIf
    Int n = StorageUtil.GetIntValue(worker, "WOSK_HomeFixN", 0)
    if asWhy == "recheck"
        if n >= 4
            Debug.Trace("WOSK_WorkerAlias: " + worker + " still not home after " + n + " rechecks - waits for the next load or cell load of the player " + _WhereString(worker))
            return false
        endIf
        StorageUtil.SetIntValue(worker, "WOSK_HomeFixN", n + 1)
    else
        StorageUtil.UnsetIntValue(worker, "WOSK_HomeFixN")
    endIf
    Debug.Trace("WOSK_WorkerAlias: " + worker + " is not in his home cell (" + asWhy + ", contract=" + contract + ") - sending him home " + _WhereString(worker))
    _ReturnHomeIfConfigured(worker)
    return worker.GetParentCell() == homeCell
EndFunction

; Returns the hold's configured delivery target (D078) if SetDeliveryTarget() was ever called for it, or
; akDefault otherwise (Game.GetPlayer() from PickUp(), the worker itself
; from the AWAITING_PICKUP timeout path - both unchanged pre-D078 defaults).
; aiHoldID is hardcoded 0 (Whiterun, the MVP's only hold); the parameter exists ahead of a second hold.
ObjectReference Function _DeliveryTargetOr(Actor akWorker, ObjectReference akDefault)
    Form target = StorageUtil.GetFormValue(Game.GetPlayer(), "WOSK_HoldDeliveryTarget_0", None)
    if target
        return target as ObjectReference
    endIf
    return akDefault
EndFunction

; Resolves a task's "outputs" array (replaces the
; old hardcoded resourceType if/elseIf switch of literal vanilla FormIDs) and
; adds aiQty units, each one drawn by the output weights (Fase 33 etapa 6, D276; it was
; a fixed floor() split with the rest to the last output until then). A single output
; keeps the whole quantity (weight 100 in HonestWork/professions/00_core.json).
Function _DeliverTaskOutputs(ObjectReference akTarget, string asProfession, Int aiTaskIndex, Int aiQty)
    Int count = WOSK_Registry.CountTaskOutputs(asProfession, aiTaskIndex)
    if count <= 0
        return
    endIf

    Float totalWeight = 0.0
    Int i = 0
    while i < count
        totalWeight += WOSK_Registry.GetTaskOutputFloat(asProfession, aiTaskIndex, i, "weight", 0.0)
        i += 1
    endwhile
    if totalWeight <= 0.0
        return
    endIf

    ; Fase 33 etapa 6 (D276, V069 A2): each unit of the batch is drawn on its own by the
    ; weights, so every configured item comes out over a few batches (the fixed split
    ; gave a lot of 3 the same 1 + 0 + 2 every time). The quantity does not change.
    Int[] counts = new Int[16]
    Int used = count
    if used > 16
        used = 16
    endIf
    Int u = 0
    while u < aiQty
        Int pick = PickOutputIndex(asProfession, aiTaskIndex, used, Utility.RandomFloat(0.0, 1.0))
        if pick >= 0
            counts[pick] = counts[pick] + 1
        endIf
        u += 1
    endwhile
    string drawn = ""
    i = 0
    while i < used
        Int thisQty = counts[i]
        if thisQty > 0
            string formRef = WOSK_Registry.GetTaskOutputString(asProfession, aiTaskIndex, i, "form", "")
            Form item = _ResolveFormRef(formRef)
            if item
                akTarget.AddItem(item, thisQty)
                drawn += " " + i + "x" + thisQty
            else
                Debug.Trace("WOSK_WorkerAlias: _DeliverTaskOutputs could not resolve form '" + formRef + "'")
            endIf
        endIf
        i += 1
    endwhile
    Debug.Trace("WOSK_WorkerAlias: batch drawn per unit - task=" + asProfession + "/" + aiTaskIndex + " qty=" + aiQty + " outputs(index x units)=" + drawn)
EndFunction

; Fase 33 etapa 6 (D276): the output one unit is, by weight. afRoll in [0, 1) times the
; total weight of the first aiCount outputs lands on one of them; weight 0 is never
; picked. -1 when no output has weight. Mirrors the development reference model pick_output_index.
Int Function PickOutputIndex(string asProfession, Int aiTaskIndex, Int aiCount, Float afRoll) global
    Float total = 0.0
    Int i = 0
    while i < aiCount
        total += WOSK_Registry.GetTaskOutputFloat(asProfession, aiTaskIndex, i, "weight", 0.0)
        i += 1
    endwhile
    if total <= 0.0
        return -1
    endIf
    Float point = afRoll * total
    Float run = 0.0
    Int last = -1
    i = 0
    while i < aiCount
        Float weight = WOSK_Registry.GetTaskOutputFloat(asProfession, aiTaskIndex, i, "weight", 0.0)
        if weight > 0.0
            last = i
            run += weight
            if point < run
                return i
            endIf
        endIf
        i += 1
    endwhile
    return last
EndFunction

; V006 (D103): the price per unit follows the game, not the JSON - the mean
; of each output's GetGoldValue(), weighted by the output weight, so a mod
; that changes ore value (WACCF) changes the contract price too. An output
; whose form does not resolve is left out; 0.0 when none resolves.
;
; Fase 33 etapa 9 (E1, V072, rule "ladder by the contract"): in EVERY profession the
; reference is not the game's value alone, which put the dearer tier's contract below the
; cheaper one's (fish, labour, hunt, herbs) and the master's dishes below the veteran's:
;   reference = max(game value, ingredients x ingredientMargin,
;                   (dearest average contract of the tier below x tierStep / batch
;                    - ingredients) / priceMultiplier)
; the average contract being batch x (reference x priceMultiplier + ingredients). It never
; goes below the game value. Same sum in C++ (ProfessionsRegistry.cpp TaskUnitPrice,
; Core/DishPrice.h) and in the development reference model price_reference; the vectors in
; plugin-skse/tests/fixtures/dish_price_vectors.txt hold all three to the same numbers. The
; item's value in the game does not change; the value delivered in the ledger
; (quantity x reference) follows the reference.
;
; Fase 33 etapa 11 (G1, D295, gold is always whole): there is no decimal
; in the game's money. The reference of one unit and the ingredients of one unit are WHOLE
; gold, rounded UP (WholeGold) where they are worked out, and the tier above is at least one
; gold over the dearest whole reference of the tier below (the +1, with the step):
;   reference = max(WholeGold(max(game value, ingredients x ingredientMargin,
;                                 (dearest contract below x tierStep / batch - ingredients)
;                                  / priceMultiplier)),
;                   dearest reference below + 1)
; the contract below being batch x (reference x priceMultiplier + ingredients) of whole
; figures. The value delivered (quantity x reference) is therefore whole by construction.
Float Function _TaskUnitPrice(string asProfession, Int aiTaskIndex)
    return TaskUnitPrice(asProfession, aiTaskIndex)
EndFunction

; Fase 33 etapa 11 (G1): a price rounded UP to whole gold, at least 1 for a positive one; 0
; (no price) and a negative (the -1 of an ingredient that does not resolve) pass through. The
; 0.001 keeps a figure that is whole in exact arithmetic (2.0000002 in float32) on the same
; side as the C++ (Core/DishPrice.h WholeGold), Python (core_model.whole_gold) and the
; panel (model.wholeGold); no real price sits within it of a whole number without being one.
Float Function WholeGold(Float afGold) global
    if afGold <= 0.0
        return afGold
    endIf
    Float whole = Math.Ceiling(afGold - 0.001)
    if whole < 1.0
        whole = 1.0
    endIf
    return whole
EndFunction

; Fase 33 etapa 10 (F1): what a contract of afUnits units costs the player, in gold:
;   ceil(units x (reference x multiplier + ingredients)).
; The one place the charge is worked out; the panel's estimate is this sum at the smallest and
; the largest lot. An ingredient cost below 0 (not resolved) counts as 0 here (the contract is
; refused before it gets this far).
Int Function ContractCost(Float afUnits, Float afReference, Float afMultiplier, Float afIngredients) global
    Float ingredients = afIngredients
    if ingredients < 0.0
        ingredients = 0.0
    endIf
    Float cost = afUnits * (afReference * afMultiplier + ingredients)
    return Math.Ceiling(cost) as Int
EndFunction

; The old V006 sum, alone: mean of GetGoldValue() of the outputs, by weight.
Float Function TaskGameValue(string asProfession, Int aiTaskIndex) global
    Int count = WOSK_Registry.CountTaskOutputs(asProfession, aiTaskIndex)
    Float totalWeight = 0.0
    Float weightedValue = 0.0
    Int i = 0
    while i < count
        string formRef = WOSK_Registry.GetTaskOutputString(asProfession, aiTaskIndex, i, "form", "")
        Float weight = WOSK_Registry.GetTaskOutputFloat(asProfession, aiTaskIndex, i, "weight", 0.0)
        Form item = WOSK_DepletionScript.ResolveFormRef(formRef)
        if item && weight > 0.0
            totalWeight += weight
            weightedValue += weight * item.GetGoldValue()
        else
            Debug.Trace("WOSK_WorkerAlias: TaskGameValue left out output '" + formRef + "' (weight=" + weight + ")")
        endIf
        i += 1
    endwhile
    if totalWeight <= 0.0
        return 0.0
    endIf
    return weightedValue / totalWeight
EndFunction

; The pure rule. margin and step 0 (or below 0) switch their term off, the +1 with the step;
; a game value of 0 stays 0, and an ingredient cost below 0 (not resolved) leaves the whole
; game value, as the contract is refused then. afIngredients is already whole gold
; (TaskIngredientCost); afBelowReference is the dearest whole reference of the tier below.
Float Function PriceReference(Float afGameValue, Float afIngredients, Float afMargin, Float afBelowContract, Float afBelowReference, Float afStep, Float afBatch, Float afMult) global
    if afGameValue <= 0.0
        return afGameValue
    endIf
    if afIngredients < 0.0
        return WholeGold(afGameValue)
    endIf
    Float reference = afGameValue
    if afMargin > 0.0 && afIngredients > 0.0 && afIngredients * afMargin > reference
        reference = afIngredients * afMargin
    endIf
    if afStep > 0.0 && afBelowContract > 0.0 && afBatch > 0.0 && afMult > 0.0
        Float needed = (afBelowContract * afStep / afBatch - afIngredients) / afMult
        if needed > reference
            reference = needed
        endIf
    endIf
    reference = WholeGold(reference)
    if afStep > 0.0 && afBelowReference > 0.0 && afBelowReference + 1.0 > reference
        reference = afBelowReference + 1.0
    endIf
    return reference
EndFunction

; The rank of the task's tier (the tier's minContracts); -1 when the tier is unknown.
Float Function TaskRank(string asProfession, Int aiTaskIndex) global
    return WOSK_Registry.GetTierFloat(asProfession, WOSK_Registry.GetTaskString(asProfession, aiTaskIndex, "minTier", ""), "minContracts", -1.0)
EndFunction

; N expected: the middle of batchMin / batchMax (SPEC 5.5).
Float Function TaskBatch(string asProfession, Int aiTaskIndex) global
    return (WOSK_Registry.GetTaskFloat(asProfession, aiTaskIndex, "batchMin", 0.0) + WOSK_Registry.GetTaskFloat(asProfession, aiTaskIndex, "batchMax", 0.0)) / 2.0
EndFunction

; The contract at the middle of the batch: batch x (reference x multiplier + ingredients).
; An ingredient that does not resolve counts as 0; a task without a value is 0.
Float Function TaskAverageContract(string asProfession, Int aiTaskIndex) global
    Float reference = TaskUnitPrice(asProfession, aiTaskIndex)
    if reference <= 0.0
        return 0.0
    endIf
    Float ingredients = TaskIngredientCost(asProfession, aiTaskIndex)
    if ingredients < 0.0
        ingredients = 0.0
    endIf
    return TaskBatch(asProfession, aiTaskIndex) * (reference * WOSK_Registry.GetTaskFloat(asProfession, aiTaskIndex, "priceMultiplier", 1.0) + ingredients)
EndFunction

; What to climb over: the dearest average contract (index 0) and the dearest whole reference
; (index 1) among the profession's tasks at the nearest lower rank (minContracts) it has tasks
; at. Both 0 when there is no tier below, or the tier of this task is unknown. One pass, so the
; walk down the tiers is not done twice.
Float[] Function LadderBelow(string asProfession, Int aiTaskIndex) global
    Float[] below = new Float[2]
    below[0] = 0.0
    below[1] = 0.0
    Float mine = TaskRank(asProfession, aiTaskIndex)
    if mine < 0.0
        return below
    endIf
    Float belowRank = -1.0
    Int t = 0
    while t < 64 && WOSK_Registry.GetTaskString(asProfession, t, "id", "") != ""
        if t != aiTaskIndex
            Float rank = TaskRank(asProfession, t)
            if rank >= 0.0 && rank < mine && rank > belowRank
                belowRank = rank
            endIf
        endIf
        t += 1
    endwhile
    if belowRank < 0.0
        return below
    endIf
    t = 0
    while t < 64 && WOSK_Registry.GetTaskString(asProfession, t, "id", "") != ""
        if t != aiTaskIndex && TaskRank(asProfession, t) == belowRank
            Float reference = TaskUnitPrice(asProfession, t)
            if reference > 0.0
                Float ingredients = TaskIngredientCost(asProfession, t)
                if ingredients < 0.0
                    ingredients = 0.0
                endIf
                Float contract = TaskBatch(asProfession, t) * (reference * WOSK_Registry.GetTaskFloat(asProfession, t, "priceMultiplier", 1.0) + ingredients)
                if contract > below[0]
                    below[0] = contract
                endIf
                if reference > below[1]
                    below[1] = reference
                endIf
            endIf
        endIf
        t += 1
    endwhile
    return below
EndFunction

; The contract to climb over (LadderBelow, index 0).
Float Function ContractBelow(string asProfession, Int aiTaskIndex) global
    Float[] below = LadderBelow(asProfession, aiTaskIndex)
    return below[0]
EndFunction

; The reference price per unit of a task (see the header above). Global so the
; harness and the contract read the same number.
Float Function TaskUnitPrice(string asProfession, Int aiTaskIndex) global
    Float gameValue = TaskGameValue(asProfession, aiTaskIndex)
    if gameValue <= 0.0
        return 0.0
    endIf
    Float ingredients = TaskIngredientCost(asProfession, aiTaskIndex)
    if ingredients < 0.0
        return WholeGold(gameValue)
    endIf
    Float step = WOSK_Registry.GetTaskFloat(asProfession, aiTaskIndex, "tierStep", 0.0)
    Float below = 0.0
    Float belowReference = 0.0
    if step > 0.0
        Float[] ladder = LadderBelow(asProfession, aiTaskIndex)
        below = ladder[0]
        belowReference = ladder[1]
    endIf
    Float margin = WOSK_Registry.GetTaskFloat(asProfession, aiTaskIndex, "ingredientMargin", 0.0)
    Float reference = PriceReference(gameValue, ingredients, margin, below, belowReference, step, TaskBatch(asProfession, aiTaskIndex), WOSK_Registry.GetTaskFloat(asProfession, aiTaskIndex, "priceMultiplier", 1.0))
    if reference != gameValue
        Debug.Trace("WOSK_WorkerAlias: TaskUnitPrice " + asProfession + "#" + aiTaskIndex + " game " + gameValue + " ingredients " + ingredients + " contract below " + below + " reference below " + belowReference + " -> reference " + reference)
    endIf
    return reference
EndFunction

; Fase 15 (D159): what the ingredients of one unit of output cost the cook,
; sum of count x GetGoldValue() in game, rounded UP to whole gold (Fase 33 etapa 11, G1).
; 0.0 for a task without ingredients.
; -1.0 when an ingredient does not resolve: leaving it out would undercharge,
; so the contract is refused. Global so the harness reads the same number.
Float Function TaskIngredientCost(string asProfession, Int aiTaskIndex) global
    Int count = WOSK_Registry.CountTaskIngredients(asProfession, aiTaskIndex)
    Float total = 0.0
    Int i = 0
    while i < count
        string formRef = WOSK_Registry.GetTaskIngredientString(asProfession, aiTaskIndex, i, "form", "")
        Float perUnit = WOSK_Registry.GetTaskIngredientFloat(asProfession, aiTaskIndex, i, "count", 0.0)
        Form item = WOSK_DepletionScript.ResolveFormRef(formRef)
        if !item || perUnit <= 0.0
            Debug.Trace("WOSK_WorkerAlias: TaskIngredientCost - ingredient '" + formRef + "' not resolved (count=" + perUnit + ")")
            return -1.0
        endIf
        total += perUnit * item.GetGoldValue()
        i += 1
    endwhile
    return WholeGold(total)
EndFunction

; "plugin|formid" -> Form. D105 etapa 3: the parser moved to
; WOSK_DepletionScript.ResolveFormRef (global), so the source code can use it too.
Form Function _ResolveFormRef(string asFormRef)
    return WOSK_DepletionScript.ResolveFormRef(asFormRef)
EndFunction

; No PACK is ever generated by this project; behavior is
; ActorUtil.AddPackageOverride() (PapyrusUtil SE, confirmed real) against
; real vanilla packages only.
; D105 etapa 2: both packages go to the actor's LinkCustom02 linked reference -
; defaultTravelToLinkCustom02 (Travel template, PLDT near linked ref with that
; keyword) and DefaultSandboxLinkCustom02512 (Sandbox template, radius 512),
; read in Skyrim.esm. Until D105 this was Travel itself (0x00016FAA), a
; template whose location is the editor location - the worker never left.
Package Function _TravelPackage()
    return Game.GetFormFromFile(0x000235E2, "Skyrim.esm") as Package
EndFunction

Package Function _SandboxPackage()
    return Game.GetFormFromFile(0x000DD837, "Skyrim.esm") as Package
EndFunction

Keyword Function _TravelKeyword()
    return Game.GetFormFromFile(0x0005D5E7, "Skyrim.esm") as Keyword
EndFunction

; Points the packages above at akTarget (WOSK_Native.SetLinkedRef, D215).
Function _SetTravelTarget(Actor akWorker, ObjectReference akTarget)
    WOSK_Native.SetLinkedRef(akWorker, akTarget, _TravelKeyword())
    Debug.Trace("WOSK_WorkerAlias: " + akWorker + " travel target -> " + akTarget)
EndFunction

; V024 (log of 2026-09-15): right after loading a save with the worker WORKING,
; the LinkCustom02 reference set above was None. The package overrides
; (PapyrusUtil) kept working after that load; the target did not. Called by
; WOSK_ControllerScript on every load: puts the target back from what StorageUtil
; keeps - the source destination while going or working, home on the way back.
; The trace before any change is also the V024 measurement.
Function RestoreTravelTarget()
    Actor worker = GetActorRef()
    if !worker
        return
    endIf
    ; D216: the DLL forgets its watched bandit on every load.
    Actor encounterThreat = StorageUtil.GetFormValue(worker, "WOSK_EncounterThreat", None) as Actor
    if encounterThreat && !encounterThreat.IsDead()
        _WatchThreat(encounterThreat)
    endIf
    string contract = StorageUtil.GetStringValue(worker, "WOSK_Contract", CONTRACT_IDLE)
    ; Fase 33 etapa 2 (D263, V065): the round-9 hunter loaded in TRAVELING_BACK, the contract
    ; resolved and sent her "home" from the road, and she never reached the inn. Every load
    ; checks that a worker without a running contract is in his home cell (the contract
    ; running at load is checked by the clock, and again by the cell load of the player).
    StorageUtil.UnsetIntValue(worker, "WOSK_HomeFixN")
    EnsureAtHome("load")
    ; Fase 26 conserto 1 (D233): a worker hired before the state faction existed,
    ; or whose rank was lost, gets it back from the key on every load.
    WOSK_WorkerState.Reconcile(worker)
    ; Fase 25 (D227): the backpack follows the contract across a load.
    ; Fase 27 (D232): the outfit first - a refresh of it can take the pack off.
    WOSK_Outfits.Reconcile(worker, _WorkerProfession(worker))
    WOSK_Backpack.Reconcile(worker, _WorkerProfession(worker), contract != CONTRACT_IDLE)
    ; Fase 28 (D234): a cook on a contract goes back to his pot (the link is lost
    ; on load, V024); also takes a contract of the previous build off the travel
    ; package. No pot: the home sandbox he was left on stands.
    if (contract == CONTRACT_TRAVELING_TO || contract == CONTRACT_WORKING || contract == CONTRACT_TRAVELING_BACK) && _WorkerProfession(worker) == "cook"
        Bool resumed = WOSK_PlayerHouse.StartCooking(worker)
        Debug.Trace("WOSK_WorkerAlias: " + worker + " cook on load - contract=" + contract + " resumedAtPot=" + resumed)
        return
    endIf
    ObjectReference expected = None
    if contract == CONTRACT_TRAVELING_TO || contract == CONTRACT_WORKING
        expected = StorageUtil.GetFormValue(worker, "WOSK_ContractDestination", None) as ObjectReference
    elseIf contract == CONTRACT_TRAVELING_BACK
        expected = _HomeTarget(worker)
    endIf
    if !expected
        return
    endIf
    ObjectReference current = worker.GetLinkedRef(_TravelKeyword())
    Debug.Trace("WOSK_WorkerAlias: " + worker + " travel target on load - contract=" + contract + \
                " current=" + current + " expected=" + expected)
    if current == expected
        return
    endIf
    _SetTravelTarget(worker, expected)
    ; The package may already have been picked with no target during the load.
    worker.EvaluatePackage()
    _TracePosition(worker, "travel target restored")
EndFunction

; Where the worker goes back to: his own home (Fase 24, D223 - the player's house
; for a worker who lives there, WOSK_PlayerHouse), else the hold's configured
; home (SetWorkerHome), else the candidate marker of the spot the worker was
; hired from, else the inn's first candidate marker (a worker hired before D105
; etapa 2 has no spot saved).
ObjectReference Function _HomeTarget(Actor akWorker)
    Form home = StorageUtil.GetFormValue(akWorker, "WOSK_WorkerHome", None)
    if !home
        home = StorageUtil.GetFormValue(Game.GetPlayer(), "WOSK_HoldHome_0", None)
    endIf
    if !home
        home = StorageUtil.GetFormValue(akWorker, "WOSK_HomeMarker", None)
    endIf
    if !home
        home = Game.GetFormFromFile(0x00000810, "HonestWork.esp")
    endIf
    return home as ObjectReference
EndFunction

; D105 etapa 2 (test 2026-09-15): where the worker is, for the log - so a tester
; can let time pass and still know where the worker went. Distance to the travel
; target only when both are in the same worldspace, or the same interior cell;
; across spaces GetDistance means nothing.
; Where the worker IS, in words the player recognises - not the coordinates
; _WhereString() logs. The three fallbacks are ordered by how much they tell
; him: a named Location, then the cell, then the place he sent the worker to.
;
; Named _DeathPlace until queue item 12, when the tracker started calling it
; for a worker who is very much alive. The function never had anything to do
; with dying; the ledger's death line was just its only caller.
string Function _PlaceWords(Actor akWorker)
    Location loc = akWorker.GetCurrentLocation()
    if loc && loc.GetName() != ""
        return "at " + loc.GetName()
    endIf
    Cell parentCell = akWorker.GetParentCell()
    if parentCell && parentCell.GetName() != ""
        return "at " + parentCell.GetName()
    endIf
    ; Open ground away from anything named - and that is most of the route. The
    ; contract's own source is the only place name left, and it is the one he
    ; picked himself.
    string sourceId = StorageUtil.GetStringValue(akWorker, "WOSK_ContractSource", "")
    if sourceId != ""
        return "on the road to " + sourceId
    endIf
    return "in an unnamed place"
EndFunction

; OnDeath hands over None for a trap, a fall, drowning or a scripted kill.
; Saying that outright is the answer; "unknown killer" would read as a hole in
; the record, and the maintainer already lost a worker to a trap at Halted Stream
; Camp with nothing written down.
string Function _KillerName(Actor akKiller)
    if !akKiller
        return "no killer - a trap, a fall or the cold"
    endIf
    string name = akKiller.GetDisplayName()
    if name == ""
        return "killed by something with no name"
    endIf
    return "killed by " + name
EndFunction

Function _TracePosition(Actor akWorker, string asWhy)
    Debug.Trace("WOSK_WorkerAlias: " + akWorker + " position (" + asWhy + ") " + _WhereString(akWorker))
EndFunction

Function _TraceCombat(Actor akWorker, string asWhy)
    Debug.Trace("WOSK_WorkerAlias: " + akWorker + " " + asWhy + " - combatState=" + akWorker.GetCombatState() + \
                " sneaking=" + akWorker.IsSneaking() + " alerted=" + akWorker.IsAlerted() + \
                " package=" + akWorker.GetCurrentPackage() + \
                " contract=" + StorageUtil.GetStringValue(akWorker, "WOSK_Contract", CONTRACT_IDLE) + " " + _WhereString(akWorker))
EndFunction

string Function _WhereString(Actor akWorker)
    WorldSpace space = akWorker.GetWorldSpace()
    Cell parentCell = akWorker.GetParentCell()
    string where = "gameDay=" + Utility.GetCurrentGameTime() + " world=" + space + " cell=" + parentCell + \
                   " pos=(" + (akWorker.GetPositionX() as Int) + "," + (akWorker.GetPositionY() as Int) + "," + \
                   (akWorker.GetPositionZ() as Int) + ") loaded=" + akWorker.Is3DLoaded()
    ObjectReference target = akWorker.GetLinkedRef(_TravelKeyword())
    if !target
        return where + " target=None"
    endIf
    where += " target=" + target
    if _SameSpace(akWorker, target)
        return where + " dist=" + (akWorker.GetDistance(target) as Int)
    endIf
    return where + " dist=n/a (other space)"
EndFunction

; Same worldspace, or the same interior cell - the only cases where
; GetDistance between the two means anything.
Bool Function _SameSpace(ObjectReference akA, ObjectReference akB)
    WorldSpace space = akA.GetWorldSpace()
    if space
        return akB.GetWorldSpace() == space
    endIf
    Cell parentCell = akA.GetParentCell()
    if !parentCell
        return false
    endIf
    return akB.GetParentCell() == parentCell
EndFunction

Bool Function _IsAtHome(Actor akWorker)
    ObjectReference home = _HomeTarget(akWorker)
    if !home || !_SameSpace(akWorker, home)
        return false
    endIf
    return akWorker.GetDistance(home) <= HOME_ARRIVAL_RADIUS_UNITS
EndFunction

; Fase 15, SPEC 5.7: a task with bowMultiplier > 1.0 (the hunter's) multiplies
; the batch when the worker has a bow equipped at issue. One read of the
; equipped weapon, at issue; 1.0 for every other task, or without a bow.
; ASSUMPTION: a hired NPC may never have a bow equipped (Fase 15 A).
Float Function _GearMultiplier(Actor akWorker, string asProfession, Int aiTaskIndex)
    Float bow = WOSK_Registry.GetTaskFloat(asProfession, aiTaskIndex, "bowMultiplier", 1.0)
    if bow <= 1.0
        return 1.0
    endIf
    ; Fase 30 (D243): the multiplier is the tier value of the bow he carries
    ; (WOSK_Gear.BowMultiplier -> hunter tiers, bowGearMultiplier), no longer the
    ; task's fixed one (bow here is only the fallback and the "this task uses a bow"
    ; marker). The mod's own hunting bow still pays nothing (D238).
    Weapon equipped = akWorker.GetEquippedWeapon(false)
    Float gear = WOSK_Gear.BowMultiplier(akWorker, asProfession, bow)
    Debug.Trace("WOSK_WorkerAlias: bow read at issue - worker=" + akWorker + " weapon=" + equipped + " bowTier=" + WOSK_Gear.EquippedBowTier(akWorker) + " gear=" + gear)
    return gear
EndFunction
