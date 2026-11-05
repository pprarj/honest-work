; Copyright (C) 2026 Awrawra
; SPDX-License-Identifier: GPL-3.0-only
; This file is part of Honest Work - Workers of Skyrim, free software under the
; GNU General Public License, version 3. See the LICENSE file at the repository root.

ScriptName WOSK_Registry Hidden

; Read access to the merged professions and contract-type registries that
; HonestWork.dll builds on kDataLoaded (Core::ProfessionsRegistry). Every key -
; profession id, tier id, contract type id, task id, field name - is matched
; ignoring case, in C++. Values come back with their original case.
;
; Why not JsonUtil paths (B003, D099): the
; Papyrus VM keeps one string per case-insensitive spelling, so a path built
; from "miner" can reach the native as ".professions.Miner..." - and
; JsonUtil's Path lookups are case-sensitive. There is no Papyrus-side fix:
; any re-cased string goes back through the same cache.
;
; A missing profession, tier, task, output, row or field returns the default,
; and so does a field holding the wrong JSON type. Indexes are 0-based.

Int Function FindTaskIndex(string asProfession, string asTaskId) global native
; -1 when the profession or the task id does not exist.

Float Function GetTaskFloat(string asProfession, Int aiTaskIndex, string asField, Float afDefault) global native
string Function GetTaskString(string asProfession, Int aiTaskIndex, string asField, string asDefault) global native

Float Function GetTierFloat(string asProfession, string asTier, string asField, Float afDefault) global native
Int Function GetTierInt(string asProfession, string asTier, string asField, Int aiDefault) global native

Int Function CountTaskOutputs(string asProfession, Int aiTaskIndex) global native
; 0 when the task has no "outputs" array.
Float Function GetTaskOutputFloat(string asProfession, Int aiTaskIndex, Int aiOutputIndex, string asField, Float afDefault) global native
string Function GetTaskOutputString(string asProfession, Int aiTaskIndex, Int aiOutputIndex, string asField, string asDefault) global native

; Fase 15 (D159): what the cook buys per unit of output, [{form, count}].
; 0 when the task has no "ingredients" array - every task but the cook's.
Int Function CountTaskIngredients(string asProfession, Int aiTaskIndex) global native
Float Function GetTaskIngredientFloat(string asProfession, Int aiTaskIndex, Int aiIngredientIndex, string asField, Float afDefault) global native
string Function GetTaskIngredientString(string asProfession, Int aiTaskIndex, Int aiIngredientIndex, string asField, string asDefault) global native

Int Function CountOutcomeRows(string asContractType) global native
; 0 when the contract type or its "outcomeTable" does not exist.
Float Function GetOutcomeRowFloat(string asContractType, Int aiRow, string asField, Float afDefault) global native
string Function GetOutcomeRowString(string asContractType, Int aiRow, string asField, string asDefault) global native

Int Function CountProfessions() global native
; D104 etapa 2b: how many professions the registry holds, for the candidate roll.
string Function GetProfessionId(Int aiIndex, string asDefault) global native
; The profession id at aiIndex, lowercased, in the registry's key order.

Int Function CountHoldSources(string asHold, string asResourceType) global native
; D105: how many sources of asResourceType the hold has
; (Data/SKSE/Plugins/HonestWork/hold_sources/*.json). 0 for an unknown hold or
; type. A contract is issued only where this is above 0. D105 etapa 3: an empty
; asResourceType counts every source of the hold.

string Function GetHoldSourceId(string asHold, string asResourceType, Int aiIndex) global native
; D105 etapa 2: the id of the aiIndex-th source of asResourceType in the hold
; (0 to CountHoldSources - 1), lowercased, in the registry's key order. "" out
; of range. An empty asResourceType walks every source of the hold.
string Function GetHoldSourceString(string asHold, string asSourceId, string asField, string asDefault) global native
; A text field of one source - "destination" is the "plugin|formid" of the
; persistent reference the worker travels to.

Float Function GetHoldSourceFloat(string asHold, string asSourceId, string asField, Float afDefault) global native
; Fase 15: a numeric field of one source - a zone's "capacity" (units of
; output it holds per resource type) and "recoveryDays" (game days its memory
; lasts). afDefault for an unknown hold, source or field.

Int Function CountHoldSourceVeins(string asHold, string asSourceId, string asResourceType) global native
; D105 etapa 3: how many ore veins of asResourceType the source lists (hold
; sources schemaVersion 2, veins keyed by resource type). 0 for an unknown
; hold, source or type.
string Function GetHoldSourceVein(string asHold, string asSourceId, string asResourceType, Int aiIndex, string asDefault) global native
; The "plugin|formid" of the aiIndex-th vein of asResourceType in the source (0
; to CountHoldSourceVeins - 1), in the order the JSON lists them. asDefault out
; of range.

; Queue item 12, scope 1. Not registry data - operator config - but it lives
; here because the DLL is the only side of the mod that reads a file from disk,
; and this script is where Papyrus asks it what it read.
Int Function GetWorkerTrackerSeconds() global native
Float Function GetOccupiedIncidentChance() global native

; D161/D163 (Fase 16): one hold's candidate pool. GetCandidatePoolFloat reads
; "rotationDays", "refillDaysMin", "refillDaysMax"; GetCandidateSpotString reads a
; profession's spot, "marker" ("plugin|0xHEX") or "place". The default for an
; unknown hold, profession or field. Keys match ignoring case.
Float Function GetCandidatePoolFloat(string asHold, string asField, Float afDefault) global native
string Function GetCandidateSpotString(string asHold, string asProfession, string asField, string asDefault) global native
; D218 (Fase 22): the hold's extra spots - CountCandidateExtras is the length of
; "extraSpots" (0 without it); GetCandidateExtraString reads the aiIndex-th one's
; "marker" or "place". An extra's profession is not here: it is rolled at each
; arrival and stays on the candidate.
Int Function CountCandidateExtras(string asHold) global native
string Function GetCandidateExtraString(string asHold, Int aiIndex, string asField, string asDefault) global native
; [debug] worker_tracker_seconds in Data/SKSE/Plugins/HonestWork.toml, read
; once at kDataLoaded. 0 (the shipped value) means the worker tracker is off.
; No arguments on purpose: a section/key pair would cross this boundary as two
; strings built for a lookup, and that is exactly what the VM's case cache
; broke twice in this project (B003, D099
; and D127).
