// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

// Settings.cpp
// Honest Work - Workers of Skyrim

#include "Core/Settings.h"

#include <algorithm>
#include <cctype>
#include <cstdio>

namespace HonestWork::Core::Settings
{
	std::uint32_t ModifierBitForScanCode(std::uint32_t a_code)
	{
		switch (a_code) {
		case Scan::kLeftControl:
		case Scan::kRightControl:
			return Modifier::kCtrl;
		case Scan::kLeftShift:
		case Scan::kRightShift:
			return Modifier::kShift;
		case Scan::kLeftAlt:
		case Scan::kRightAlt:
			return Modifier::kAlt;
		default:
			return Modifier::kNone;
		}
	}

	const char* TextEntrySource(const TextEntrySignals& a_signals)
	{
		if (a_signals.consoleOpen) {
			return "console";
		}
		if (a_signals.scaleformTextEntry > 0) {
			return "scaleform text field";
		}
		if (a_signals.prismaAnyFocus && !a_signals.prismaOwnFocus) {
			return "another Prisma view";
		}
		if (a_signals.smfBlockingWindow) {
			return "SKSE Menu Framework window";
		}
		return "";
	}

	KeyTouch ClassifyKeyFrame(KeyTouchState& a_state, float a_value, float a_held, bool a_isDown)
	{
		KeyTouch result;
		if (!(a_value > 0.0f)) {
			a_state = KeyTouchState{};  // a release rearms the key
			return result;
		}

		bool newPress = !a_state.pressed;
		if (a_state.pressed) {
			// A real key-down cannot follow a press that is still going: the
			// release was lost (focus change, a frame the sink never got). The
			// held seconds going back says the same for a press with no key-down.
			if (a_isDown) {
				newPress = true;
				result.releaseLost = true;
			} else if (a_held + kHeldRegressionSlack < a_state.lastHeld) {
				newPress = true;
				result.releaseLost = true;
			}
		}
		a_state.lastHeld = a_held;

		if (newPress) {
			a_state.pressed = true;
			a_state.repeatNoted = false;
			result.edge = a_isDown ? KeyEdge::kTouchKeyDown : KeyEdge::kTouchHeld;
			return result;
		}
		if (!a_state.repeatNoted) {
			a_state.repeatNoted = true;
			result.edge = KeyEdge::kRepeat;
		}
		return result;
	}

	bool ModifiersSatisfied(std::uint32_t a_required, std::uint32_t a_held)
	{
		const std::uint32_t required = a_required & Modifier::kAll;
		if (required == Modifier::kNone) {
			return true;
		}
		return (a_held & required) == required;
	}

	std::string ModifierPrefix(std::uint32_t a_mask)
	{
		std::string prefix;
		if (a_mask & Modifier::kCtrl) {
			prefix += "Ctrl+";
		}
		if (a_mask & Modifier::kShift) {
			prefix += "Shift+";
		}
		if (a_mask & Modifier::kAlt) {
			prefix += "Alt+";
		}
		return prefix;
	}

	std::string ScanCodeName(std::uint32_t a_code)
	{
		// Letters and digits by scan-code row (set 1, the DIK_* values).
		static constexpr const char* kRowQ = "QWERTYUIOP";  // 0x10-0x19
		static constexpr const char* kRowA = "ASDFGHJKL";   // 0x1E-0x26
		static constexpr const char* kRowZ = "ZXCVBNM";     // 0x2C-0x32
		if (a_code >= 0x02 && a_code <= 0x0A) {
			return std::string(1, static_cast<char>('1' + (a_code - 0x02)));
		}
		if (a_code == 0x0B) {
			return "0";
		}
		if (a_code >= 0x10 && a_code <= 0x19) {
			return std::string(1, kRowQ[a_code - 0x10]);
		}
		if (a_code >= 0x1E && a_code <= 0x26) {
			return std::string(1, kRowA[a_code - 0x1E]);
		}
		if (a_code >= 0x2C && a_code <= 0x32) {
			return std::string(1, kRowZ[a_code - 0x2C]);
		}
		if (a_code >= 0x3B && a_code <= 0x44) {
			return "F" + std::to_string(1 + (a_code - 0x3B));
		}
		switch (a_code) {
		case 0x01: return "Esc";
		case 0x0C: return "-";
		case 0x0D: return "=";
		case 0x0E: return "Backspace";
		case 0x0F: return "Tab";
		case 0x1A: return "[";
		case 0x1B: return "]";
		case 0x1C: return "Enter";
		case 0x1D: return "Left Ctrl";
		case 0x27: return ";";
		case 0x28: return "'";
		case 0x29: return "~";
		case 0x2A: return "Left Shift";
		case 0x2B: return "\\";
		case 0x33: return ",";
		case 0x34: return ".";
		case 0x35: return "/";
		case 0x36: return "Right Shift";
		case 0x37: return "Num *";
		case 0x38: return "Left Alt";
		case 0x39: return "Space";
		case 0x3A: return "Caps Lock";
		case 0x45: return "Num Lock";
		case 0x46: return "Scroll Lock";
		case 0x47: return "Num 7";
		case 0x48: return "Num 8";
		case 0x49: return "Num 9";
		case 0x4A: return "Num -";
		case 0x4B: return "Num 4";
		case 0x4C: return "Num 5";
		case 0x4D: return "Num 6";
		case 0x4E: return "Num +";
		case 0x4F: return "Num 1";
		case 0x50: return "Num 2";
		case 0x51: return "Num 3";
		case 0x52: return "Num 0";
		case 0x53: return "Num .";
		case 0x57: return "F11";
		case 0x58: return "F12";
		case 0x9C: return "Num Enter";
		case 0x9D: return "Right Ctrl";
		case 0xB5: return "Num /";
		case 0xB7: return "Print Screen";
		case 0xB8: return "Right Alt";
		case 0xC5: return "Pause";
		case 0xC7: return "Home";
		case 0xC8: return "Up";
		case 0xC9: return "Page Up";
		case 0xCB: return "Left";
		case 0xCD: return "Right";
		case 0xCF: return "End";
		case 0xD0: return "Down";
		case 0xD1: return "Page Down";
		case 0xD2: return "Insert";
		case 0xD3: return "Delete";
		default:
			break;
		}
		char buffer[16];
		std::snprintf(buffer, sizeof(buffer), "Key 0x%02X", static_cast<unsigned>(a_code));
		return buffer;
	}

	std::string FormatHotkey(std::uint32_t a_code, std::uint32_t a_mask)
	{
		return ModifierPrefix(a_mask) + ScanCodeName(a_code);
	}

	std::string RejectReason(std::uint32_t a_code, std::uint32_t a_consoleKey)
	{
		if (a_code == Scan::kEscape) {
			return "Esc closes menus and cannot open the panel.";
		}
		if (a_code == a_consoleKey || a_code == Scan::kTilde) {
			return ScanCodeName(a_code) + " opens the console and cannot open the panel.";
		}
		if (ModifierBitForScanCode(a_code) != Modifier::kNone) {
			return "Shift, Ctrl and Alt only combine with a key; tick them below instead.";
		}
		if (a_code == 0) {
			return "No key.";
		}
		return "";
	}

	std::string ModifiersToToml(std::uint32_t a_mask)
	{
		std::string text;
		auto add = [&text](const char* a_word) {
			if (!text.empty()) {
				text += "+";
			}
			text += a_word;
		};
		if (a_mask & Modifier::kCtrl) {
			add("ctrl");
		}
		if (a_mask & Modifier::kShift) {
			add("shift");
		}
		if (a_mask & Modifier::kAlt) {
			add("alt");
		}
		return text.empty() ? "none" : text;
	}

	std::uint32_t ModifiersFromToml(const std::string& a_text, std::vector<std::string>* a_unknown)
	{
		std::uint32_t mask = Modifier::kNone;
		std::string word;
		auto flush = [&]() {
			if (word.empty()) {
				return;
			}
			if (word == "ctrl" || word == "control") {
				mask |= Modifier::kCtrl;
			} else if (word == "shift") {
				mask |= Modifier::kShift;
			} else if (word == "alt") {
				mask |= Modifier::kAlt;
			} else if (word != "none") {
				if (a_unknown) {
					a_unknown->push_back(word);
				}
			}
			word.clear();
		};
		for (const char c : a_text) {
			if (c == '+' || c == ',' || std::isspace(static_cast<unsigned char>(c))) {
				flush();
			} else {
				word += static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
			}
		}
		flush();
		return mask;
	}

	bool IsKnownPalette(const std::string& a_name)
	{
		return std::any_of(std::begin(kPalettes), std::end(kPalettes),
			[&a_name](const char* a_known) { return a_name == a_known; });
	}

	std::string NormalizePalette(const std::string& a_name)
	{
		return IsKnownPalette(a_name) ? a_name : std::string(kPalettes[0]);
	}

	std::string NormalizeLogLevel(const std::string& a_level)
	{
		const bool known = std::any_of(std::begin(kLogLevels), std::end(kLogLevels),
			[&a_level](const char* a_known) { return a_level == a_known; });
		return known ? a_level : std::string(kLogLevels[0]);
	}

	float ClampIncidentChance(float a_value)
	{
		if (!(a_value >= kIncidentMin)) {  // also catches NaN
			return kIncidentMin;
		}
		if (a_value > kIncidentMax) {
			return kIncidentMax;
		}
		return a_value;
	}

	std::uint32_t ClampTrackerSeconds(std::int64_t a_value)
	{
		if (a_value < 0) {
			return 0;
		}
		if (a_value > static_cast<std::int64_t>(kTrackerMax)) {
			return kTrackerMax;
		}
		return static_cast<std::uint32_t>(a_value);
	}

	std::vector<std::string> DiffLines(const AppConfig::Config& a_old, const AppConfig::Config& a_new)
	{
		std::vector<std::string> lines;
		if (a_old.hotkeyOpenPanel != a_new.hotkeyOpenPanel || a_old.hotkeyModifiers != a_new.hotkeyModifiers) {
			lines.push_back("panel hotkey: " + FormatHotkey(a_old.hotkeyOpenPanel, a_old.hotkeyModifiers) + " -> " +
							FormatHotkey(a_new.hotkeyOpenPanel, a_new.hotkeyModifiers));
		}
		if (a_old.palette != a_new.palette) {
			lines.push_back("palette: " + a_old.palette + " -> " + a_new.palette);
		}
		if (a_old.occupiedIncidentChance != a_new.occupiedIncidentChance) {
			char buffer[64];
			std::snprintf(buffer, sizeof(buffer), "occupied incident chance: %.2f -> %.2f",
				static_cast<double>(a_old.occupiedIncidentChance), static_cast<double>(a_new.occupiedIncidentChance));
			lines.emplace_back(buffer);
		}
		if (a_old.logLevel != a_new.logLevel) {
			lines.push_back("log level: " + a_old.logLevel + " -> " + a_new.logLevel);
		}
		if (a_old.workerTrackerSeconds != a_new.workerTrackerSeconds) {
			lines.push_back("worker tracker seconds: " + std::to_string(a_old.workerTrackerSeconds) + " -> " +
							std::to_string(a_new.workerTrackerSeconds));
		}
		return lines;
	}
}
