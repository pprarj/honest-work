// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

// TestChannel.cpp
// Honest Work - Workers of Skyrim

#include "TestChannel.h"

namespace HonestWork::Core::TestChannel
{
	namespace
	{
		// Script class the harness declares the native on. Plain string
		// equality at bind time, same as a mod event name: a typo on either
		// side leaves the Papyrus call bound to nothing.
		constexpr auto kScriptClass = "HWTest_Native";

		// Global native: RE::StaticFunctionTag* first (TypeTraits.h:9,
		// IVirtualMachine.h:146-147), string as RE::BSFixedString - same shape
		// as Lodestone's SetBookText (BookFramework.cpp:151, :217), v6.7.1.
		void Log(RE::StaticFunctionTag*, RE::BSFixedString a_line)
		{
			spdlog::info("{}", a_line.c_str() ? a_line.c_str() : "");
		}

		bool RegisterFuncs(RE::BSScript::IVirtualMachine* a_vm)
		{
			if (!a_vm) {
				return false;
			}
			a_vm->RegisterFunction("Log", kScriptClass, Log);
			// Logged here, when SKSE actually hands over the VM - not in
			// Register(), where it would only prove the request was queued.
			spdlog::info("TestChannel: {}.Log bound (test harness channel; no release script calls it).",
				kScriptClass);
			return true;
		}
	}

	bool Register()
	{
		const auto* papyrus = SKSE::GetPapyrusInterface();
		return papyrus && papyrus->Register(RegisterFuncs);
	}
}
