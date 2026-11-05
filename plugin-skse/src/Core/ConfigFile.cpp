// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

// ConfigFile.cpp
// Honest Work - Workers of Skyrim

#include "Core/ConfigFile.h"

#include "Core/Settings.h"

#include <toml.hpp>

#include <cstdio>
#include <exception>
#include <fstream>
#include <limits>

namespace HonestWork::Core::ConfigFile
{
	namespace
	{
		const toml::value* FindValue(const toml::value& a_root, const char* a_section, const char* a_key)
		{
			if (!a_root.is_table()) {
				return nullptr;
			}
			const auto& tbl = a_root.as_table();
			const auto sectionIt = tbl.find(a_section);
			if (sectionIt == tbl.end() || !sectionIt->second.is_table()) {
				return nullptr;
			}
			const auto& section = sectionIt->second.as_table();
			const auto keyIt = section.find(a_key);
			return keyIt == section.end() ? nullptr : &keyIt->second;
		}

		template <class T>
		T FindOr(const toml::value& a_root, const char* a_section, const char* a_key, T a_default)
		{
			if (const auto* value = FindValue(a_root, a_section, a_key)) {
				try {
					return toml::get<T>(*value);
				} catch (const std::exception&) {
					return a_default;
				}
			}
			return a_default;
		}
	}

	bool Read(const std::string& a_path, AppConfig::Config& a_out, std::string& a_error,
		std::vector<std::string>& a_warnings)
	{
		try {
			const auto result = toml::try_parse(a_path);
			if (result.is_err()) {
				a_error = "could not parse '" + a_path + "'";
				return false;
			}
			const auto& root = result.unwrap();

			a_out.hotkeyOpenPanel = FindOr<std::uint32_t>(root, "hotkeys", "open_panel", a_out.hotkeyOpenPanel);

			// D196: a TOML from before Fase 19 has no modifiers key - none.
			if (FindValue(root, "hotkeys", "open_panel_modifiers")) {
				const auto text = FindOr<std::string>(root, "hotkeys", "open_panel_modifiers", "none");
				std::vector<std::string> unknown;
				a_out.hotkeyModifiers = Settings::ModifiersFromToml(text, &unknown);
				for (const auto& word : unknown) {
					a_warnings.push_back("open_panel_modifiers: '" + word + "' is not ctrl, shift or alt - skipped");
				}
			}

			if (FindValue(root, "ui", "palette")) {
				const auto palette = FindOr<std::string>(root, "ui", "palette", a_out.palette);
				if (!Settings::IsKnownPalette(palette)) {
					a_warnings.push_back("palette: '" + palette + "' is not a known palette - frost");
				}
				a_out.palette = Settings::NormalizePalette(palette);
			}

			if (FindValue(root, "logging", "level")) {
				const auto level = FindOr<std::string>(root, "logging", "level", a_out.logLevel);
				const auto normal = Settings::NormalizeLogLevel(level);
				if (normal != level) {
					a_warnings.push_back("logging level: '" + level + "' is not info, debug or trace - info");
				}
				a_out.logLevel = normal;
			}

			a_out.workerTrackerSeconds =
				FindOr<std::uint32_t>(root, "debug", "worker_tracker_seconds", a_out.workerTrackerSeconds);

			if (FindValue(root, "gameplay", "occupied_incident_chance")) {
				const float raw = FindOr<float>(root, "gameplay", "occupied_incident_chance",
					std::numeric_limits<float>::quiet_NaN());
				const float clamped = Settings::ClampIncidentChance(raw);
				if (clamped != raw) {
					char buffer[96];
					std::snprintf(buffer, sizeof(buffer), "occupied_incident_chance: %g outside [0.01, 0.60] - %.2f",
						static_cast<double>(raw), static_cast<double>(clamped));
					a_warnings.emplace_back(buffer);
				}
				a_out.occupiedIncidentChance = clamped;
			}
			return true;
		} catch (const std::exception& e) {
			a_error = std::string("exception while parsing '") + a_path + "' (" + e.what() + ")";
			return false;
		}
	}

	bool Write(const std::string& a_path, const AppConfig::Config& a_config, std::string& a_error)
	{
		try {
			toml::value root = toml::table{};
			if (auto parsed = toml::try_parse(a_path); parsed.is_ok()) {
				root = parsed.unwrap();
			}

			root["hotkeys"]["open_panel"] = a_config.hotkeyOpenPanel;
			root["hotkeys"]["open_panel_modifiers"] = Settings::ModifiersToToml(a_config.hotkeyModifiers);
			root["ui"]["palette"] = a_config.palette;
			root["logging"]["level"] = a_config.logLevel;
			root["debug"]["worker_tracker_seconds"] = a_config.workerTrackerSeconds;
			root["gameplay"]["occupied_incident_chance"] = a_config.occupiedIncidentChance;

			std::ofstream file(a_path, std::ios::trunc);
			if (!file) {
				a_error = "could not open '" + a_path + "' for writing";
				return false;
			}
			file << toml::format(root);
			file.flush();
			if (!file) {
				a_error = "could not finish writing '" + a_path + "'";
				return false;
			}
			return true;
		} catch (const std::exception& e) {
			a_error = std::string("exception writing '") + a_path + "' (" + e.what() + ")";
			return false;
		}
	}
}
