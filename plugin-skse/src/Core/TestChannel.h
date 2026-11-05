// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

// TestChannel.h
// Honest Work - Workers of Skyrim
//
// Output channel for the in-game test harness (D089): one
// global Papyrus native, HWTest_Native.Log(string), that writes the line to
// HonestWork.log at info level. Info is the floor in Release -
// Log::ApplyConfiguredLevel never goes above it - so no TOML setting can
// silence a harness line.
//
// Why a native and not Debug.Trace: Papyrus.log only exists when the user's
// Skyrim.ini enables it, and a harness that runs with that flag off looks
// exactly like a harness that never ran. Writing here also puts the harness
// result in the same file, and on the same clock, as the ModEventBridge
// "sent" lines it has to be matched against (V010).
//
// This ships in the release DLL on purpose, as a registered native that no
// release script calls: the harness scripts and HonestWork_Test.esp that call
// it stay out of the package. A test-only build flag was rejected because the
// maintainer would then test a different binary than the one that ships.

#pragma once

namespace HonestWork::Core::TestChannel
{
	// Registers HWTest_Native.Log with the Papyrus VM. Call once from
	// SKSEPluginLoad. Returns false if SKSE refused the registration.
	bool Register();
}
