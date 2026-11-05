; Copyright (C) 2026 Awrawra
; SPDX-License-Identifier: GPL-3.0-only
; This file is part of Honest Work - Workers of Skyrim, free software under the
; GNU General Public License, version 3. See the LICENSE file at the repository root.

ScriptName WOSK_Native Hidden

; Natives bound by HonestWork.dll (plugin-skse/src/Core/WorkerNatives.cpp).
; They replace the two things the worker script took from the PO3 Papyrus
; Extender (D214-D216), so the mod runs where PO3 does not.

; Points akRef's linked reference for akKeyword at akTarget (what the
; LinkCustom02 travel packages read).
Function SetLinkedRef(ObjectReference akRef, ObjectReference akTarget, Keyword akKeyword) global native

; The road-encounter bandit: while watched, its death sends the mod event
; "WOSK_EncounterThreatKilled" (sender = the bandit, strArg = killer FormID as
; a decimal string). A death of anything else produces nothing.
Function WatchEncounterThreat(Actor akThreat) global native
Function UnwatchEncounterThreat(Actor akThreat) global native
