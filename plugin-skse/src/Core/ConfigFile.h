// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

// ConfigFile.h
// Honest Work - Workers of Skyrim
//
// Fase 19: the TOML side of AppConfig, with no logger and no game API, so
// plugin-skse/tests/ checks the round trip (old file without the new keys,
// new file with them, write and read back) outside the game.

#pragma once

#include "Core/AppConfig.h"

#include <string>
#include <vector>

namespace HonestWork::Core::ConfigFile
{
	// Fills a_out from the file at a_path. Keys that are missing keep the
	// value a_out already had (the caller passes Config{} for the defaults).
	// Returns false when the file cannot be read or parsed; a_error says why.
	// a_warnings receives one line per value that was present but unusable
	// (unknown palette, unknown modifier word, incident chance out of range).
	bool Read(const std::string& a_path, AppConfig::Config& a_out, std::string& a_error,
		std::vector<std::string>& a_warnings);

	// Writes a_config to a_path. Keys of the existing file that this plugin
	// does not own are kept; the ones it owns are replaced. Returns false
	// when the file cannot be written; a_error says why.
	bool Write(const std::string& a_path, const AppConfig::Config& a_config, std::string& a_error);
}
