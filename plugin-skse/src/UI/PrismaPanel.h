// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

// PrismaPanel.h
// Honest Work - Workers of Skyrim
//
// Prisma UI panel (D079 - replaces SKSE Menu Framework's
// PanelModule, retired to _trash/plugin-skse-smf/). Pure UI: draws (via the
// ui-prisma/ React frontend, not this DLL), captures the JS side's action
// requests, and forwards them to Papyrus via the SAME Core::ModEventBridge
// mechanism the SMF panel already used (D060, unchanged) - every real
// decision (cost, state machine, StorageUtil/JsonUtil access) still lives
// entirely in Papyrus, as this layer is meant to do.
// The only genuinely new capability the Prisma bridge adds over SMF
// is bidirectional communication (D079 resolves D061's
// "no return channel" limitation) - not yet used to push live worker
// status back to the UI in this pass; the static reference data pushed on
// DOM ready (hwInit) is the same kind of display-only data the SMF panel
// already showed.

#pragma once

#include <string>

namespace HonestWork::UI::PrismaPanel
{
	// Call once, from the kDataLoaded SKSE message handler. No-op (logs a
	// warning) if the PrismaUI.dll module cannot be found or does not
	// support interface V1 - a missing/incompatible framework install must
	// never stop the rest of the plugin, same
	// tolerance the old SKSEMenuFramework::IsInstalled() check had.
	void OnDataLoaded();

	// D104 etapa 3: binds the WOSK_Panel natives (Scripts/Source/WOSK_Panel.psc)
	// that feed and open the Recruit tab. Call from SKSEPluginLoad. Returns
	// false if SKSE refused the request.
	bool RegisterNatives();

	// Fase 19 (D198): the palette the settings page or the TOML chose. Sent to
	// the page now (window.hwTheme) and again on every DOM ready. Unknown names
	// become "frost". Safe from any thread: the view is touched from an SKSE task.
	void SetPalette(const std::string& a_palette);
}
