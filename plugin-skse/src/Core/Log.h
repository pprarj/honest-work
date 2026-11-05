// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

// Log.h
// Honest Work - Workers of Skyrim
//
// Owns the plugin's spdlog setup. Log file:
// Documents/My Games/Skyrim Special Edition/SKSE/HonestWork.log
// (the log is the only way to learn afterwards whether a worker died, where
// and why - but that generous per-transition logging lives entirely in Papyrus/WOSK_WorkerAliasScript, not here; this
// DLL only logs its own panel/init lifecycle).

#pragma once

#include <string>

namespace HonestWork::Core::Log
{
	// Initializes the plugin log file and installs it as the default logger.
	// Must be called once, first thing in SKSEPluginLoad, before any spdlog::
	// call. Returns false if the SKSE log directory could not be resolved.
	bool Init();

	// Applies the "logging.level" TOML setting ("trace"/"debug"/"info") to
	// the default logger. No-op in debug builds, which always stay at trace.
	void ApplyConfiguredLevel(const std::string& a_level);
}
