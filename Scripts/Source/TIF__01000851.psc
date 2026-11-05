; Copyright (C) 2026 Awrawra
; SPDX-License-Identifier: GPL-3.0-only
; This file is part of Honest Work - Workers of Skyrim, free software under the
; GNU General Public License, version 3. See the LICENSE file at the repository root.

;BEGIN FRAGMENT CODE - Do not edit anything between this and the end comment
;NEXT FRAGMENT INDEX 1
Scriptname TIF__01000851 Extends TopicInfo Hidden

;BEGIN FRAGMENT Fragment_0
Function Fragment_0(ObjectReference akSpeakerRef)
	Actor akSpeaker = akSpeakerRef as Actor
	;BEGIN CODE
	; Fase 30: "I want to give you some equipment" - the hunter's gift menu (the
	; topic's quest has no script, so the controller is found by its FormID).
	WOSK_PanelBridgeScript.GetController().GiveGearByActor(akSpeaker)
	;END CODE
EndFunction
;END FRAGMENT

;END FRAGMENT CODE - Do not edit anything between this and the begin comment
