; Copyright (C) 2026 Awrawra
; SPDX-License-Identifier: GPL-3.0-only
; This file is part of Honest Work - Workers of Skyrim, free software under the
; GNU General Public License, version 3. See the LICENSE file at the repository root.

;BEGIN FRAGMENT CODE - Do not edit anything between this and the end comment
;NEXT FRAGMENT INDEX 1
Scriptname TIF__0100081E Extends TopicInfo Hidden

;BEGIN FRAGMENT Fragment_0
Function Fragment_0(ObjectReference akSpeakerRef)
	Actor akSpeaker = akSpeakerRef as Actor
	;BEGIN CODE
	; Fase 10 A: the worker's own answer opens the contract panel for that worker.
	; Fase 26: the topic's quest is WOSK_WorkerPool, which has no script - the
	; controller is found by its FormID (GetOwningQuest() was None here).
	WOSK_PanelBridgeScript.GetController().OpenWorkerPanel(akSpeaker)
	;END CODE
EndFunction
;END FRAGMENT

;END FRAGMENT CODE - Do not edit anything between this and the begin comment
