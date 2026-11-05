// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

// SettingsPage.h
// Honest Work - Workers of Skyrim
//
// Fase 19 (D194-D200): the "Honest Work / Settings" page in the SKSE Menu
// Framework Mod Control Panel. The SMF is an OPTIONAL dependency (D195):
// without it the plugin loads, the panel opens on the TOML hotkey and every
// setting stays in Data/SKSE/Plugins/HonestWork.toml.
//
// It also owns the held-modifier state and the "press the new key" capture,
// which the Prisma panel's input sink consults.

#pragma once

#include <cstdint>

namespace RE
{
	class ButtonEvent;
}

namespace HonestWork::UI::SettingsPage
{
	// Called at kDataLoaded, after PrismaPanel::OnDataLoaded. Registers the
	// page and the SMF input callback when the SMF is installed; logs and
	// does nothing otherwise.
	void Register();

	// Shift/Ctrl/Alt held state, tracked from every keyboard button event
	// (D196 - same self-tracking as D107). Call it before any
	// filter so a release is never missed.
	void TrackModifiers(const RE::ButtonEvent& a_button);
	std::uint32_t HeldModifiers();

	// True while the page waits for the new key, and for a short moment after
	// it took one, so the same key-down does not also toggle the panel.
	bool OwnsKey(std::uint32_t a_code);

	// Fase 20: true while an SKSE Menu Framework window that blocks the game
	// input is open (SMF.h IsAnyBlockingWindowOpened). False without the SMF.
	bool SmfBlockingWindowOpen();
}
