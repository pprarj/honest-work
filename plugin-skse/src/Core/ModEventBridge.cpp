// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

// ModEventBridge.cpp
// Honest Work - Workers of Skyrim

#include "ModEventBridge.h"

namespace HonestWork::Core::ModEventBridge
{
	void Send(const char* a_eventName, const std::string& a_strArg, float a_numArg)
	{
		// SKSE::ModCallbackEvent / SKSE::GetModCallbackEventSource() confirmed
		// against the real vendored headers (commonlib-scout, this session):
		// SKSE/Events.h (struct ModCallbackEvent { BSFixedString eventName;
		// BSFixedString strArg; float numArg; TESForm* sender; }) and
		// SKSE/API.h (GetModCallbackEventSource() -> BSTEventSource<ModCallbackEvent>*).
		// sender is always null here - none of this panel's 4 actions (issue
		// contract / cure / fire / pick up) need a Form sender, only an alias
		// index (packed into numArg) and, for issue contract, a task id
		// string (strArg).
		SKSE::ModCallbackEvent modEvent{
			RE::BSFixedString(a_eventName),
			RE::BSFixedString(a_strArg.c_str()),
			a_numArg,
			nullptr
		};
		SKSE::GetModCallbackEventSource()->SendEvent(&modEvent);

		spdlog::info("ModEventBridge: sent '{}' strArg='{}' numArg={:.0f}", a_eventName, a_strArg, a_numArg);
	}
}
