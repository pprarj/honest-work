// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

// Settings.h
// Honest Work - Workers of Skyrim
//
// Fase 19 (D195-D199): the pure rules behind the SKSE Menu Framework settings
// page and the hotkey modifiers. Nothing here touches the game, the SKSE API
// or the logger, so plugin-skse/tests/ builds it alone and checks every rule
// without the game running.

#pragma once

#include "Core/AppConfig.h"

#include <cstdint>
#include <string>
#include <vector>

namespace HonestWork::Core::Settings
{
	// Modifier bits of AppConfig::Config::hotkeyModifiers. Left and right keys
	// count as the same modifier (D196, same rule as D107).
	namespace Modifier
	{
		inline constexpr std::uint32_t kNone = 0;
		inline constexpr std::uint32_t kCtrl = 1u << 0;
		inline constexpr std::uint32_t kShift = 1u << 1;
		inline constexpr std::uint32_t kAlt = 1u << 2;
		inline constexpr std::uint32_t kAll = kCtrl | kShift | kAlt;
	}

	// DirectInput scan codes (DIK_*) this module names. Same values as
	// RE::BSKeyboardDevice::Keys; repeated here so the tests need no CommonLib.
	namespace Scan
	{
		inline constexpr std::uint32_t kEscape = 0x01;
		inline constexpr std::uint32_t kTilde = 0x29;  // the default console key
		inline constexpr std::uint32_t kLeftControl = 0x1D;
		inline constexpr std::uint32_t kRightControl = 0x9D;
		inline constexpr std::uint32_t kLeftShift = 0x2A;
		inline constexpr std::uint32_t kRightShift = 0x36;
		inline constexpr std::uint32_t kLeftAlt = 0x38;
		inline constexpr std::uint32_t kRightAlt = 0xB8;
	}

	// The modifier bit a scan code is, or kNone for any other key.
	std::uint32_t ModifierBitForScanCode(std::uint32_t a_code);

	// D196 (D107): with no modifier configured the key opens
	// whatever is held; with modifiers configured, every configured one must be
	// held and the others do not matter.
	bool ModifiersSatisfied(std::uint32_t a_required, std::uint32_t a_held);

	// "Ctrl+Shift+" style prefix, always in the order Ctrl, Shift, Alt.
	std::string ModifierPrefix(std::uint32_t a_mask);

	// Key name for the screen ("H", "F5", "Num 7"); unknown codes come back as
	// "Key 0x.." - never the bare scan code alone.
	std::string ScanCodeName(std::uint32_t a_code);

	// "Ctrl+Shift+H".
	std::string FormatHotkey(std::uint32_t a_code, std::uint32_t a_mask);

	// Why a key cannot be the panel key, or "" when it can. a_consoleKey is the
	// key the game maps to the console (0x29 unless the player remapped it).
	std::string RejectReason(std::uint32_t a_code, std::uint32_t a_consoleKey);

	// TOML text of the modifier mask: "none", or "ctrl", "ctrl+shift", ...
	std::string ModifiersToToml(std::uint32_t a_mask);

	// Reads the TOML text back. Case and spaces do not matter, "+" "," and
	// spaces all separate; "none" and "" are no modifier. A word that is not a
	// modifier is skipped and returned in a_unknown, so the loader can warn.
	std::uint32_t ModifiersFromToml(const std::string& a_text, std::vector<std::string>* a_unknown = nullptr);

	// Fase 20 (D205): the places that can be receiving typed text. Read once per
	// input frame by the sink; the decision below is pure.
	struct TextEntrySignals
	{
		bool consoleOpen = false;       // UI::IsMenuOpen(Console)
		int scaleformTextEntry = 0;     // ControlMap runtime data textEntryCount
		bool prismaAnyFocus = false;    // IVPrismaUI1::HasAnyActiveFocus
		bool prismaOwnFocus = false;    // IVPrismaUI1::HasFocus(our view)
		bool smfBlockingWindow = false; // SMF IsAnyBlockingWindowOpened
	};

	// "" when the key may toggle the panel, else the source that caught it:
	// "console", "scaleform text field", "another Prisma view", "SKSE Menu
	// Framework window". Prisma focus on our own view alone does not count (H
	// closes the panel); when both ours and another view hold focus the signals
	// cannot tell them apart and the key passes (D205).
	const char* TextEntrySource(const TextEntrySignals& a_signals);

	// Fase 18 conserto 3 (D208): a touch is the release -> pressed transition the
	// sink sees, not the key-down flag. With the SKSE Menu Framework loaded the
	// first frame of a press never reaches the sink (V050), so a press arrives as
	// "held" frames only; IsDown() is never true.
	struct KeyTouchState
	{
		bool pressed = false;       // the last frame the sink saw had value > 0
		bool repeatNoted = false;   // this press already got its one repeat line
		float lastHeld = 0.0f;      // seconds held on the last frame of this press
	};

	enum class KeyEdge
	{
		kNone,           // released, or a repeat of a press already counted (quiet)
		kTouchKeyDown,   // first frame of a press, and it is a key-down
		kTouchHeld,      // first frame the sink saw of a press, and it is not a key-down
		kRepeat,         // a later frame of a counted press: the one line this press gets
	};

	struct KeyTouch
	{
		KeyEdge edge = KeyEdge::kNone;
		bool releaseLost = false;   // the touch came while the state said "still pressed"
	};

	// One button frame of one key: a_value is ButtonEvent::Value(), a_held is
	// HeldDuration() in seconds, a_isDown is IsDown(). Updates a_state.
	KeyTouch ClassifyKeyFrame(KeyTouchState& a_state, float a_value, float a_held, bool a_isDown);

	// A frame whose held seconds went back by more than this is a new press whose
	// release the sink never saw.
	inline constexpr float kHeldRegressionSlack = 0.005f;

	// Palettes the page knows (ui-prisma/src/theme.ts). Unknown -> "frost".
	inline constexpr const char* kPalettes[] = { "frost", "amber", "moss", "parchment" };
	bool IsKnownPalette(const std::string& a_name);
	std::string NormalizePalette(const std::string& a_name);

	// Log levels the DLL applies (Core/Log.cpp). Unknown -> "info".
	inline constexpr const char* kLogLevels[] = { "info", "debug", "trace" };
	std::string NormalizeLogLevel(const std::string& a_level);

	// The occupied-mine incident chance limit of today (D142): [0.01, 0.60].
	inline constexpr float kIncidentMin = 0.01f;
	inline constexpr float kIncidentMax = 0.60f;
	float ClampIncidentChance(float a_value);

	// The floor WOSK_ControllerScript.TrackerInterval puts on the tracker.
	inline constexpr std::uint32_t kTrackerScriptFloor = 5;
	// Highest value the page accepts (one game hour of real seconds is plenty
	// for a test aid, and keeps a typo from becoming "never").
	inline constexpr std::uint32_t kTrackerMax = 3600;
	std::uint32_t ClampTrackerSeconds(std::int64_t a_value);

	// One line per field that differs: "<field>: <old> -> <new>". Empty when
	// nothing changed. The settings page logs each one at info (Fase 19 item 1).
	std::vector<std::string> DiffLines(const AppConfig::Config& a_old, const AppConfig::Config& a_new);
}
