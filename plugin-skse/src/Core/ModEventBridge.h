// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

// ModEventBridge.h
// Honest Work - Workers of Skyrim
//
// The only channel this DLL has into Papyrus (Fase 6 gate:
// "o fluxo emitir-contrato -> mod event -> Papyrus"). One-way, C++ -> Papyrus
// only - there is no return channel, which is why UIModule cannot show live
// worker status/cost (that state lives in StorageUtil/professions.json,
// read only by Papyrus: every business rule is resolved in Papyrus before the
// panel renders).
//
// Receiver side: WOSK_PlayerAliasScript.psc (Scripts/Source/), registered via
// RegisterForModEvent in OnInit/OnPlayerLoadGame, forwards to
// WOSK_PanelBridgeScript's global functions (Fase 6).

#pragma once

#include <string>

namespace HonestWork::Core::ModEventBridge
{
	// Event names - must match the RegisterForModEvent() string literals in
	// WOSK_PlayerAliasScript.psc exactly (plain string equality at runtime,
	// no compile-time link between the two sides - see module docstring).
	inline constexpr auto kEventIssueContract = "WOSK_RequestIssueContract";
	inline constexpr auto kEventCure = "WOSK_RequestCure";
	inline constexpr auto kEventFire = "WOSK_RequestFire";
	inline constexpr auto kEventPickUp = "WOSK_RequestPickUp";
	inline constexpr auto kEventHire = "WOSK_RequestHire";  // D104 etapa 3, numArg = candidate spot
	// Fase 9, D137: same as kEventIssueContract but the player already confirmed
	// the occupied warning in the panel. The Papyrus side draws from the
	// occupied pool and charges the incident config (0.50, clamped 0.01-0.60).
	inline constexpr auto kEventIssueOccupied = "WOSK_RequestOccupiedContract";
	// Queue item 11: the panel just opened, so the Workers tab needs a list to
	// draw. The channel is one-way by design (see above), and that is exactly
	// why the DLL cannot read the workers itself: it asks, and Papyrus answers
	// with a SetWorkerList push.
	inline constexpr auto kEventPanelOpened = "WOSK_PanelOpened";
	// D184: the panel closed (Esc, the Close button, or the hotkey). Papyrus
	// clears the recruiter sign, so only the recruiter's own opening hires.
	inline constexpr auto kEventPanelClosed = "WOSK_PanelClosed";

	// Builds and sends an SKSE::ModCallbackEvent (SKSE::GetModCallbackEventSource()
	// ->SendEvent(&event) - confirmed API, commonlib-scout,
	// Fase 6). a_aliasIndex is packed into the event's float numArg field
	// (Papyrus receives it as afNumArg and casts back to Int) - ModCallbackEvent
	// has no integer field, only string/float/Form (SKSE/Events.h).
	void Send(const char* a_eventName, const std::string& a_strArg, float a_numArg);
}
