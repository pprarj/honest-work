// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

// AppConfig.cpp
// Honest Work - Workers of Skyrim

#include "AppConfig.h"

#include "Core/ConfigFile.h"

namespace HonestWork::Core::AppConfig
{
	namespace
	{
		Config g_config;

		// Deploy path: Data/SKSE/Plugins/HonestWork.toml
		// ("SKSE\Plugins\" plural, mirrors Data\).
		// Relative to the process working directory, same convention
		// as other SKSE plugins (skse64_loader.exe launches with the Skyrim installation folder as cwd). Under MO2 the
		// write lands in the overwrite folder, which is normal.
		constexpr auto kConfigPath = "Data/SKSE/Plugins/HonestWork.toml";
	}

	void Load()
	{
		Config config;
		std::string error;
		std::vector<std::string> warnings;
		if (!ConfigFile::Read(kConfigPath, config, error, warnings)) {
			spdlog::warn("AppConfig: {} - using built-in defaults.", error);
			g_config = Config{};
			return;
		}
		for (const auto& line : warnings) {
			spdlog::warn("AppConfig: {}", line);
		}
		g_config = config;
	}

	const Config& Get() { return g_config; }

	Config& GetMutable() { return g_config; }

	bool SaveToFile()
	{
		std::string error;
		if (!ConfigFile::Write(kConfigPath, g_config, error)) {
			spdlog::error("AppConfig::SaveToFile: {}.", error);
			return false;
		}
		return true;
	}
}
