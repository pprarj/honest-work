; Copyright (C) 2026 Awrawra
; SPDX-License-Identifier: GPL-3.0-only
; This file is part of Honest Work - Workers of Skyrim, free software under the
; GNU General Public License, version 3. See the LICENSE file at the repository root.

ScriptName WOSK_LedgerScript

; Global utility - no script state, no VMAD attachment (callable as
; WOSK_LedgerScript.Function(...) from any script, same "library script with
; global functions" pattern as vanilla StringUtil.psc/JsonUtil.psc). Called by
; WOSK_ControllerScript.RefreshLedger(); the actual Lodestone.SetBookText() call
; lives there too, since this script has no Book property to hold.
;
; It formats, and it also owns the OBITUARY: the one piece of ledger content
; that cannot be read off a live alias, because a dead worker's alias is
; Clear()ed in OnDeath and its slot goes back to reading "empty". The list is
; kept by StorageUtil on the worker-pool quest - the same Form BuildLedgerText
; already receives - so recording a death needs no new wiring and no new
; property, and the text and the storage that feeds it stay in one file.

; The three fields the maintainer asked for are WHERE, WHEN and WHO KILLED. A
; worker died to a bandit and another to a trap at Halted Stream Camp, and
; nothing was written down either time: the mechanic was right, the record was
; missing.
string Function ObituaryKey() global
    return "WOSK_Obituary"
EndFunction

; The book is read in one sitting, and an unbounded list would push the living
; workers off the top of it. Oldest entries drop first.
Int Function ObituaryMax() global
    return 12
EndFunction

string Function BuildLedgerText(Quest akWorkerPool, Int aiPoolSize) global
    string text = "Honest Work - Ledger\n\n"
    Int i = 0
    while i < aiPoolSize
        ReferenceAlias a = akWorkerPool.GetAlias(i) as ReferenceAlias
        Actor worker = None
        if a
            worker = a.GetActorRef()
        endIf
        if worker
            text += _WorkerLine(worker)
        else
            text += "  Slot " + i + ": empty\n"
        endIf
        i += 1
    endwhile
    return text + ObituaryText(akWorkerPool)
EndFunction

Function RecordDeath(Quest akWorkerPool, string asName, string asWhere, Float afGameDay, string asKiller) global
    if !akWorkerPool
        return
    endIf
    string line = "  " + asName + " - " + DayStamp(afGameDay) + ", " + asWhere + ", " + asKiller + "\n"
    ; allowDuplicate is passed on purpose, and true is what this wants: two
    ; workers can die the same day, in the same place, to the same bandit, and
    ; the second death is not a repeat of the first. The default happens to be
    ; true as well - saying it here keeps a future reader from "fixing" it.
    StorageUtil.StringListAdd(akWorkerPool, ObituaryKey(), line, true)
    while StorageUtil.StringListCount(akWorkerPool, ObituaryKey()) > ObituaryMax()
        StorageUtil.StringListRemoveAt(akWorkerPool, ObituaryKey(), 0)
    endwhile
EndFunction

string Function ObituaryText(Quest akWorkerPool) global
    Int n = StorageUtil.StringListCount(akWorkerPool, ObituaryKey())
    if n <= 0
        return ""
    endIf
    string text = "\nLost\n"
    Int i = 0
    while i < n
        text += StorageUtil.StringListGet(akWorkerPool, ObituaryKey(), i)
        i += 1
    endwhile
    return text
EndFunction

; GetCurrentGameTime() counts days since the game began, fraction and all. The
; hour is that fraction, and it is worth printing: "died on day 42" and "died on
; day 42 at 23h" read very differently when the player is trying to remember
; where he was.
string Function DayStamp(Float afGameDay) global
    Int day = afGameDay as Int
    Int hour = ((afGameDay - (day as Float)) * 24.0) as Int
    return "day " + day + " at " + hour + "h"
EndFunction

string Function _WorkerLine(Actor akWorker) global
    string name = akWorker.GetDisplayName()
    string lifecycle = StorageUtil.GetStringValue(akWorker, "WOSK_Lifecycle", "AVAILABLE")
    string contract = StorageUtil.GetStringValue(akWorker, "WOSK_Contract", "IDLE")
    string tier = StorageUtil.GetStringValue(akWorker, "WOSK_Tier", "apprentice")
    string taskId = StorageUtil.GetStringValue(akWorker, "WOSK_TaskId", "")

    string line = "  " + name + " (" + WOSK_Names.TierLabel(tier) + ") - " + lifecycle
    if contract != "IDLE"
        line += ", " + contract
        if taskId != ""
            line += " [" + taskId + "]"
        endIf
    endIf
    return line + "\n"
EndFunction

; ---------------------------------------------------------------------------
; Fase 17 (D168): the panel's history - totals, the daily statement and each
; worker's own contracts. The panel draws what is kept here; nothing here
; decides anything.
;
; Kept in StorageUtil, global (none) for the totals and the statement, on the
; worker actor for his own counters and contracts. Ids and numbers only, never
; a sentence: the page words every line (same rule as the source reasons,
; D127/D129). Fields are joined by "|":
;   statement line: day|KIND|name|taskId|qty|gold
;     KIND in ISSUED (gold = charge), RETURNED (gold = value of the batch),
;     INJURED, RETIRED, DIED (qty and gold 0)
;   worker line:    day|OUTCOME|taskId|qty|cost|value
;     OUTCOME in SUCCESS, MINOR, MAJOR, DEATH
; day is the game time in days (Utility.GetCurrentGameTime).
; ---------------------------------------------------------------------------

string Function JournalKey() global
    return "WOSK_Journal"
EndFunction

; The panel shows the last days, not the whole campaign. Oldest lines drop.
Int Function JournalMax() global
    return 30
EndFunction

string Function WorkerHistoryKey() global
    return "WOSK_History"
EndFunction

Int Function WorkerHistoryMax() global
    return 12
EndFunction

Function _AppendCapped(Form akKey, string asKey, string asLine, Int aiMax) global
    StorageUtil.StringListAdd(akKey, asKey, asLine, true)
    while StorageUtil.StringListCount(akKey, asKey) > aiMax
        StorageUtil.StringListRemoveAt(akKey, asKey, 0)
    endwhile
EndFunction

; One statement line. akWorker may be None only from a test.
Function RecordEvent(string asKind, Actor akWorker, string asTaskId, Int aiQty, Int aiGold) global
    string who = ""
    if akWorker
        who = akWorker.GetDisplayName()
    endIf
    string line = Utility.GetCurrentGameTime() + "|" + asKind + "|" + who + "|" + asTaskId + "|" + aiQty + "|" + aiGold
    _AppendCapped(None, JournalKey(), line, JournalMax())
    Debug.Trace("WOSK_Ledger: statement " + line)
EndFunction

; Called right after the charge is taken (WOSK_WorkerAliasScript.IssueContract).
Function RecordIssued(Actor akWorker, string asTaskId, Int aiCostGold) global
    StorageUtil.AdjustIntValue(None, "WOSK_StatGoldSpent", aiCostGold)
    StorageUtil.AdjustIntValue(akWorker, "WOSK_GoldSpent", aiCostGold)
    StorageUtil.SetIntValue(akWorker, "WOSK_ContractCost", aiCostGold)
    RecordEvent("ISSUED", akWorker, asTaskId, 0, aiCostGold)
EndFunction

; Fase 35 etapa 4 (B6, D313): the bodyguard's fee has its own line and its own total, apart from
; the cost of the contract (WOSK_StatGoldSpent and the worker's WOSK_GoldSpent do not hold it).
; GUARD_FEE: the name is the worker's, taskId the contract, qty 0, gold the fee of that contract.
; GUARD_ASSIGN: the name is the guard's, the fee paid once to assign him.
Function RecordGuardFee(Actor akWorker, Actor akGuard, string asTaskId, Int aiFee) global
    StorageUtil.AdjustIntValue(None, "WOSK_StatGuardFees", aiFee)
    ; Fase 35 etapa 6: the guard's name rides after an "@" in the task field, so the statement can
    ; say who guarded whom (an older line without it still reads).
    string taskField = asTaskId
    if akGuard
        taskField = asTaskId + "@" + akGuard.GetDisplayName()
    endIf
    RecordEvent("GUARD_FEE", akWorker, taskField, 0, aiFee)
EndFunction

Function RecordGuardAssigned(Actor akGuard, Int aiFee) global
    StorageUtil.AdjustIntValue(None, "WOSK_StatGuardFees", aiFee)
    RecordEvent("GUARD_ASSIGN", akGuard, "", 0, aiFee)
EndFunction

; Called once per contract, when the outcome is settled
; (WOSK_WorkerAliasScript._ResolveContractCompletion). aiQty and aiValue are 0
; for an outcome with no batch. aiValue is the batch at the game's own value of
; the output (the reference price), not what the player paid.
Function RecordOutcome(Actor akWorker, string asOutcome, string asTaskId, Int aiQty, Int aiValue) global
    Int cost = StorageUtil.GetIntValue(akWorker, "WOSK_ContractCost", 0)
    StorageUtil.UnsetIntValue(akWorker, "WOSK_ContractCost")
    if aiQty > 0
        StorageUtil.AdjustIntValue(None, "WOSK_StatValueDelivered", aiValue)
        StorageUtil.AdjustIntValue(None, "WOSK_StatContractsDone", 1)
        StorageUtil.AdjustIntValue(akWorker, "WOSK_ValueDelivered", aiValue)
        RecordEvent("RETURNED", akWorker, asTaskId, aiQty, aiValue)
    endIf
    if asOutcome == "MINOR"
        RecordEvent("INJURED", akWorker, asTaskId, 0, 0)
    elseIf asOutcome == "MAJOR"
        RecordEvent("RETIRED", akWorker, asTaskId, 0, 0)
    elseIf asOutcome == "DEATH"
        RecordEvent("DIED", akWorker, asTaskId, 0, 0)
    endIf
    string line = Utility.GetCurrentGameTime() + "|" + asOutcome + "|" + asTaskId + "|" + aiQty + "|" + cost + "|" + aiValue
    _AppendCapped(akWorker, WorkerHistoryKey(), line, WorkerHistoryMax())
EndFunction

; The worker's own contracts, oldest first, joined by ";" for the panel.
string Function WorkerHistoryText(Actor akWorker) global
    string text = ""
    Int n = StorageUtil.StringListCount(akWorker, WorkerHistoryKey())
    Int i = 0
    while i < n
        if i > 0
            text += ";"
        endIf
        text += StorageUtil.StringListGet(akWorker, WorkerHistoryKey(), i)
        i += 1
    endwhile
    return text
EndFunction
