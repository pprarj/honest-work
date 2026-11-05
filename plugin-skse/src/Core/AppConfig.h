// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

// AppConfig.h
// Honest Work - Workers of Skyrim
//
// Process-lifetime holder for the config read from
// Data/SKSE/Plugins/HonestWork.toml ([hotkeys] open panel, [ui] initial tab,
// [logging] level). No separate Engine::Config
// layer - this plugin is UI-only
// (only the panel, no game logic), so there is no
// pure-logic module for a config struct to be shared with.
//
// Fase 19: the SKSE Menu Framework settings page (UI/SettingsPage) edits this
// config in game and writes it back with SaveToFile (D194). The file side
// (parse and write, no logger) lives in Core/ConfigFile so the tests in
// plugin-skse/tests/ can run it without the game.

#pragma once

#include <cstdint>
#include <string>

namespace HonestWork::Core::AppConfig
{
	struct Config
	{
		// [hotkeys] - DirectInput scan code (DIK_*) that opens the panel.
		// Default 0x23 = 'H', an unused vanilla bind, chosen so it is not a
		// vanilla movement/menu key.
		std::uint32_t hotkeyOpenPanel = 0x23;

		// [hotkeys] open_panel_modifiers - Core::Settings::Modifier bits
		// (D196). 0 = none: the key opens whatever else is held, the behavior
		// before Fase 19, so an old TOML without the key keeps working.
		std::uint32_t hotkeyModifiers = 0;

		// [ui] palette - the Prisma panel palette (D198), one of
		// Core::Settings::kPalettes. Unknown values fall back to "frost".
		// The old [ui] default_tab is gone (D199): the Prisma panel never read it.
		std::string palette = "frost";

		// [logging] - "trace"/"debug"/"info".
		std::string logLevel = "info";

		// [debug] - seconds between the worker-tracker notification (queue
		// item 12, scope 1). 0 is off, and off is what a player build ships
		// with: this exists so the maintainer can let time pass in game and still
		// know where a worker under contract is, which the Papyrus log alone
		// does not give it (V024). The compass/map version is
		// a different scope and an open decision - V041.
		std::uint32_t workerTrackerSeconds = 0;

		// [gameplay] - incident chance for an OCCUPIED mine gamble (Fase 9, D137).
		// Clamped to [0.01, 0.60] on read, same as _ComputeIncidentChance.
		float occupiedIncidentChance = 0.50f;
	};

	// Reads Data/SKSE/Plugins/HonestWork.toml. Never fails: falls back to
	// Config{} defaults and logs a warning if the file is missing or
	// malformed (a missing config must never stop the
	// rest of the plugin from working).
	void Load();

	const Config& Get();

	// Non-const access for the settings page (UI/SettingsPage, Fase 19).
	Config& GetMutable();

	// Writes the current config back to the same path Load() reads from.
	// Returns false (and logs) on failure - never throws.
	bool SaveToFile();
}
