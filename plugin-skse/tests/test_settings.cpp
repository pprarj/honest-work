// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

// test_settings.cpp
// Honest Work - Workers of Skyrim
//
// Fase 19: the DLL's pure rules, outside the game. No test framework (no new
// vcpkg dependency): each CHECK prints the failing expression and the run
// ends with exit code 1 if any failed.
//
// Covers: the TOML with and without the Fase 19 keys, the round trip through
// ConfigFile::Write (what AppConfig::SaveToFile calls), the modifier rule
// (D196), the "Ctrl+Shift+H" text and the refused keys (D197).

#include "Core/ConfigFile.h"
#include "Core/Settings.h"

#include <cmath>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>

namespace
{
	int g_failed = 0;
	int g_passed = 0;

	void Check(bool a_ok, const char* a_expr, const char* a_file, int a_line)
	{
		if (a_ok) {
			++g_passed;
			return;
		}
		++g_failed;
		std::printf("FAIL %s:%d  %s\n", a_file, a_line, a_expr);
	}

#define CHECK(expr) Check(static_cast<bool>(expr), #expr, __FILE__, __LINE__)

	namespace S = HonestWork::Core::Settings;
	namespace CF = HonestWork::Core::ConfigFile;
	using Config = HonestWork::Core::AppConfig::Config;

	std::filesystem::path TempDir()
	{
		auto dir = std::filesystem::temp_directory_path() / "honestwork-tests";
		std::filesystem::create_directories(dir);
		return dir;
	}

	std::string WriteText(const char* a_name, const std::string& a_text)
	{
		const auto path = (TempDir() / a_name).string();
		std::ofstream(path, std::ios::trunc | std::ios::binary) << a_text;
		return path;
	}

	std::string ReadText(const std::string& a_path)
	{
		std::ifstream in(a_path, std::ios::binary);
		return std::string((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
	}

	// The HonestWork.toml that shipped up to Fase 18, verbatim keys.
	const char* kOldToml =
		"[hotkeys]\n"
		"open_panel = 0x23\n"
		"[ui]\n"
		"default_tab = 0\n"
		"[logging]\n"
		"level = \"info\"\n"
		"[debug]\n"
		"worker_tracker_seconds = 0\n"
		"[gameplay]\n"
		"occupied_incident_chance = 0.50\n";

	void TestModifierRule()
	{
		using namespace S::Modifier;
		struct Case
		{
			std::uint32_t required;
			std::uint32_t held;
			bool opens;
		};
		const Case cases[] = {
			{ kNone, kNone, true },                    // none configured, none held
			{ kNone, kShift, true },                   // none configured: anything held opens (sprint)
			{ kNone, kCtrl | kAlt, true },
			{ kCtrl, kNone, false },                   // Ctrl configured, H alone
			{ kCtrl, kCtrl, true },                    // Ctrl+H
			{ kCtrl, kCtrl | kShift, true },           // extra Shift does not matter
			{ kCtrl, kShift, false },                  // the wrong one
			{ kCtrl | kShift, kCtrl, false },          // one of two
			{ kCtrl | kShift, kCtrl | kShift, true },
			{ kCtrl | kShift, kAll, true },
			{ kAlt, kAlt, true },
			{ kAlt, kCtrl | kShift, false },
			{ kAll, kAll, true },
			{ kAll, kCtrl | kShift, false },
		};
		for (const auto& c : cases) {
			CHECK(S::ModifiersSatisfied(c.required, c.held) == c.opens);
		}
	}

	void TestTextEntry()
	{
		using Sig = HonestWork::Core::Settings::TextEntrySignals;
		const auto src = [](const Sig& s) { return std::string(S::TextEntrySource(s)); };
		CHECK(src(Sig{}) == "");  // no signal: the key passes
		Sig s;
		s.consoleOpen = true;
		CHECK(src(s) == "console");
		s = Sig{};
		s.scaleformTextEntry = 1;
		CHECK(src(s) == "scaleform text field");
		s = Sig{};
		s.prismaAnyFocus = true;
		CHECK(src(s) == "another Prisma view");
		s.prismaOwnFocus = true;  // our own panel in focus: H closes it
		CHECK(src(s) == "");
		s = Sig{};
		s.prismaOwnFocus = true;  // own focus alone (no any-focus) passes
		CHECK(src(s) == "");
		s = Sig{};
		s.smfBlockingWindow = true;
		CHECK(src(s) == "SKSE Menu Framework window");
		s = Sig{};
		s.scaleformTextEntry = 2;
		s.prismaAnyFocus = true;
		s.smfBlockingWindow = true;
		CHECK(src(s) == "scaleform text field");  // first signal in order wins
	}

	// Fase 18 conserto 3 (D208): the touch is the release -> pressed transition.
	void TestKeyTouch()
	{
		using E = S::KeyEdge;
		S::KeyTouchState st;
		const auto frame = [&st](float value, float held, bool down) { return S::ClassifyKeyFrame(st, value, held, down); };

		// 1. Normal press: key-down, held frames, release, then a new press.
		auto r = frame(1.0f, 0.0f, true);
		CHECK(r.edge == E::kTouchKeyDown && !r.releaseLost);
		r = frame(1.0f, 0.016f, false);
		CHECK(r.edge == E::kRepeat);                // the one repeat line of this press
		CHECK(frame(1.0f, 0.032f, false).edge == E::kNone);  // quiet from here
		CHECK(frame(1.0f, 0.400f, false).edge == E::kNone);
		CHECK(frame(0.0f, 0.403f, false).edge == E::kNone);  // up
		r = frame(1.0f, 0.0f, true);
		CHECK(r.edge == E::kTouchKeyDown && !r.releaseLost);  // release rearmed
		CHECK(frame(1.0f, 0.016f, false).edge == E::kRepeat);  // a new press gets its own repeat line

		// 2. The first frame is lost (V050 with the SMF): the first held frame is the touch.
		st = S::KeyTouchState{};
		r = frame(1.0f, 0.001f, false);
		CHECK(r.edge == E::kTouchHeld && !r.releaseLost);
		CHECK(frame(1.0f, 0.017f, false).edge == E::kRepeat);
		CHECK(frame(1.0f, 0.033f, false).edge == E::kNone);
		CHECK(frame(0.0f, 0.403f, false).edge == E::kNone);
		// ... and the next press, again with no key-down, counts again.
		CHECK(frame(1.0f, 0.001f, false).edge == E::kTouchHeld);

		// 3. Repeats never count twice, key-down or not: 60 held frames, one touch.
		st = S::KeyTouchState{};
		int touches = 0;
		int repeats = 0;
		for (int i = 0; i < 60; ++i) {
			const auto t = frame(1.0f, 0.001f + 0.016f * static_cast<float>(i), false);
			touches += (t.edge == E::kTouchKeyDown || t.edge == E::kTouchHeld) ? 1 : 0;
			repeats += t.edge == E::kRepeat ? 1 : 0;
		}
		CHECK(touches == 1 && repeats == 1);

		// 4. Release, then press again: a second touch.
		frame(0.0f, 0.9f, false);
		CHECK(frame(1.0f, 0.001f, false).edge == E::kTouchHeld);

		// 5. Lost release, press comes with a key-down: the key-down is a new press.
		st = S::KeyTouchState{};
		frame(1.0f, 0.0f, true);
		frame(1.0f, 0.2f, false);
		r = frame(1.0f, 0.0f, true);                // no release in between
		CHECK(r.edge == E::kTouchKeyDown && r.releaseLost);

		// 6. Lost release, press comes with no key-down: held seconds went back.
		st = S::KeyTouchState{};
		frame(1.0f, 0.001f, false);
		frame(1.0f, 0.6f, false);
		r = frame(1.0f, 0.001f, false);
		CHECK(r.edge == E::kTouchHeld && r.releaseLost);
		// Same held seconds, or a little jitter below the slack: still the same press.
		st = S::KeyTouchState{};
		frame(1.0f, 0.001f, false);
		frame(1.0f, 0.100f, false);
		CHECK(frame(1.0f, 0.100f, false).edge == E::kNone);
		CHECK(frame(1.0f, 0.097f, false).edge == E::kNone);

		// 7. Lost release with a lost key-down and held seconds NOT going back
		// (the new press already older than the last frame of the old one): not
		// seen - documented in D208 as the one case the rule cannot catch.
		st = S::KeyTouchState{};
		frame(1.0f, 0.001f, false);
		frame(1.0f, 0.100f, false);
		CHECK(frame(1.0f, 0.250f, false).edge == E::kNone);

		// 8. A frame that is only a release never counts; zero or negative value is a release.
		st = S::KeyTouchState{};
		CHECK(frame(0.0f, 0.0f, false).edge == E::kNone);
		CHECK(frame(-1.0f, 0.0f, false).edge == E::kNone);
		CHECK(!st.pressed);
	}

	void TestScanCodes()
	{
		using namespace S::Scan;
		CHECK(S::ModifierBitForScanCode(kLeftControl) == S::Modifier::kCtrl);
		CHECK(S::ModifierBitForScanCode(kRightControl) == S::Modifier::kCtrl);
		CHECK(S::ModifierBitForScanCode(kLeftShift) == S::Modifier::kShift);
		CHECK(S::ModifierBitForScanCode(kRightShift) == S::Modifier::kShift);
		CHECK(S::ModifierBitForScanCode(kLeftAlt) == S::Modifier::kAlt);
		CHECK(S::ModifierBitForScanCode(kRightAlt) == S::Modifier::kAlt);
		CHECK(S::ModifierBitForScanCode(0x23) == S::Modifier::kNone);

		CHECK(S::ScanCodeName(0x23) == "H");
		CHECK(S::ScanCodeName(0x10) == "Q");
		CHECK(S::ScanCodeName(0x32) == "M");
		CHECK(S::ScanCodeName(0x02) == "1");
		CHECK(S::ScanCodeName(0x0B) == "0");
		CHECK(S::ScanCodeName(0x3B) == "F1");
		CHECK(S::ScanCodeName(0x44) == "F10");
		CHECK(S::ScanCodeName(0x58) == "F12");
		CHECK(S::ScanCodeName(0x47) == "Num 7");
		CHECK(S::ScanCodeName(0xEE) == "Key 0xEE");
	}

	void TestHotkeyText()
	{
		using namespace S::Modifier;
		CHECK(S::FormatHotkey(0x23, kCtrl | kShift) == "Ctrl+Shift+H");
		CHECK(S::FormatHotkey(0x23, kShift | kCtrl) == "Ctrl+Shift+H");  // order fixed
		CHECK(S::FormatHotkey(0x23, kNone) == "H");
		CHECK(S::FormatHotkey(0x23, kAll) == "Ctrl+Shift+Alt+H");
		CHECK(S::FormatHotkey(0x3F, kAlt) == "Alt+F5");
	}

	void TestRefusedKeys()
	{
		using namespace S::Scan;
		CHECK(!S::RejectReason(kEscape, kTilde).empty());
		CHECK(!S::RejectReason(kTilde, kTilde).empty());
		CHECK(!S::RejectReason(0x3B, 0x3B).empty());  // console remapped to F1
		CHECK(!S::RejectReason(kTilde, 0x3B).empty());  // ~ stays refused anyway
		CHECK(!S::RejectReason(kLeftShift, kTilde).empty());
		CHECK(!S::RejectReason(kRightControl, kTilde).empty());
		CHECK(!S::RejectReason(kLeftAlt, kTilde).empty());
		CHECK(!S::RejectReason(0, kTilde).empty());
		CHECK(S::RejectReason(0x23, kTilde).empty());  // H
		CHECK(S::RejectReason(0x3F, kTilde).empty());  // F5
	}

	void TestModifierToml()
	{
		using namespace S::Modifier;
		CHECK(S::ModifiersToToml(kNone) == "none");
		CHECK(S::ModifiersToToml(kCtrl) == "ctrl");
		CHECK(S::ModifiersToToml(kShift | kCtrl) == "ctrl+shift");
		CHECK(S::ModifiersToToml(kAll) == "ctrl+shift+alt");
		CHECK(S::ModifiersFromToml("none") == kNone);
		CHECK(S::ModifiersFromToml("") == kNone);
		CHECK(S::ModifiersFromToml("Ctrl") == kCtrl);
		CHECK(S::ModifiersFromToml("shift + CTRL") == (kCtrl | kShift));
		CHECK(S::ModifiersFromToml("alt,shift") == (kAlt | kShift));
		std::vector<std::string> unknown;
		CHECK(S::ModifiersFromToml("ctrl+win", &unknown) == kCtrl);
		CHECK(unknown.size() == 1 && unknown[0] == "win");
		for (std::uint32_t mask = 0; mask <= kAll; ++mask) {
			CHECK(S::ModifiersFromToml(S::ModifiersToToml(mask)) == mask);
		}
	}

	void TestValueRules()
	{
		CHECK(S::NormalizePalette("moss") == "moss");
		CHECK(S::NormalizePalette("parchment") == "parchment");
		CHECK(S::NormalizePalette("neon") == "frost");
		CHECK(S::NormalizePalette("") == "frost");
		CHECK(S::NormalizeLogLevel("trace") == "trace");
		CHECK(S::NormalizeLogLevel("verbose") == "info");
		CHECK(S::ClampIncidentChance(0.0f) == S::kIncidentMin);
		CHECK(S::ClampIncidentChance(0.9f) == S::kIncidentMax);
		CHECK(S::ClampIncidentChance(0.3f) == 0.3f);
		CHECK(S::ClampIncidentChance(std::nanf("")) == S::kIncidentMin);
		CHECK(S::ClampTrackerSeconds(-4) == 0);
		CHECK(S::ClampTrackerSeconds(30) == 30);
		CHECK(S::ClampTrackerSeconds(99999) == S::kTrackerMax);
	}

	void TestDiffLines()
	{
		Config a;
		Config b = a;
		CHECK(S::DiffLines(a, b).empty());
		b.hotkeyModifiers = S::Modifier::kCtrl | S::Modifier::kShift;
		b.palette = "moss";
		b.occupiedIncidentChance = 0.25f;
		b.logLevel = "debug";
		b.workerTrackerSeconds = 30;
		const auto lines = S::DiffLines(a, b);
		CHECK(lines.size() == 5);
		if (lines.size() == 5) {
			CHECK(lines[0] == "panel hotkey: H -> Ctrl+Shift+H");
			CHECK(lines[1] == "palette: frost -> moss");
			CHECK(lines[2] == "occupied incident chance: 0.50 -> 0.25");
			CHECK(lines[3] == "log level: info -> debug");
			CHECK(lines[4] == "worker tracker seconds: 0 -> 30");
		}
	}

	void TestOldToml()
	{
		const auto path = WriteText("old.toml", kOldToml);
		Config config;
		std::string error;
		std::vector<std::string> warnings;
		CHECK(CF::Read(path, config, error, warnings));
		CHECK(error.empty());
		CHECK(warnings.empty());
		CHECK(config.hotkeyOpenPanel == 0x23);
		CHECK(config.hotkeyModifiers == S::Modifier::kNone);  // no key: none
		CHECK(config.palette == "frost");                      // no key: frost
		CHECK(config.logLevel == "info");
		CHECK(config.workerTrackerSeconds == 0);
		CHECK(std::fabs(config.occupiedIncidentChance - 0.50f) < 1e-6f);
	}

	void TestNewToml()
	{
		const auto path = WriteText("new.toml",
			"[hotkeys]\nopen_panel = 0x3F\nopen_panel_modifiers = \"ctrl+alt\"\n"
			"[ui]\npalette = \"parchment\"\n"
			"[logging]\nlevel = \"trace\"\n"
			"[debug]\nworker_tracker_seconds = 20\n"
			"[gameplay]\noccupied_incident_chance = 0.15\n");
		Config config;
		std::string error;
		std::vector<std::string> warnings;
		CHECK(CF::Read(path, config, error, warnings));
		CHECK(warnings.empty());
		CHECK(config.hotkeyOpenPanel == 0x3F);
		CHECK(config.hotkeyModifiers == (S::Modifier::kCtrl | S::Modifier::kAlt));
		CHECK(config.palette == "parchment");
		CHECK(config.logLevel == "trace");
		CHECK(config.workerTrackerSeconds == 20);
		CHECK(std::fabs(config.occupiedIncidentChance - 0.15f) < 1e-6f);
	}

	void TestBadValues()
	{
		const auto path = WriteText("bad.toml",
			"[hotkeys]\nopen_panel_modifiers = \"ctrl+win\"\n"
			"[ui]\npalette = \"neon\"\n"
			"[logging]\nlevel = \"loud\"\n"
			"[gameplay]\noccupied_incident_chance = 0.95\n");
		Config config;
		std::string error;
		std::vector<std::string> warnings;
		CHECK(CF::Read(path, config, error, warnings));
		CHECK(warnings.size() == 4);
		CHECK(config.hotkeyModifiers == S::Modifier::kCtrl);
		CHECK(config.palette == "frost");
		CHECK(config.logLevel == "info");
		CHECK(config.occupiedIncidentChance == S::kIncidentMax);
	}

	void TestMissingFile()
	{
		Config config;
		std::string error;
		std::vector<std::string> warnings;
		CHECK(!CF::Read((TempDir() / "does-not-exist.toml").string(), config, error, warnings));
		CHECK(!error.empty());
		CHECK(config.hotkeyOpenPanel == 0x23);  // untouched defaults
	}

	void TestRoundTrip()
	{
		// Start from the old file: the write must add the new keys and keep
		// the reading of the old ones.
		const auto path = WriteText("roundtrip.toml", kOldToml);
		Config config;
		std::string error;
		std::vector<std::string> warnings;
		CHECK(CF::Read(path, config, error, warnings));

		config.hotkeyOpenPanel = 0x30;  // B
		config.hotkeyModifiers = S::Modifier::kCtrl | S::Modifier::kShift;
		config.palette = "moss";
		config.logLevel = "debug";
		config.workerTrackerSeconds = 45;
		config.occupiedIncidentChance = 0.33f;
		CHECK(CF::Write(path, config, error));

		const auto text = ReadText(path);
		CHECK(text.find("open_panel_modifiers") != std::string::npos);
		CHECK(text.find("ctrl+shift") != std::string::npos);
		CHECK(text.find("palette") != std::string::npos);

		Config back;
		warnings.clear();
		CHECK(CF::Read(path, back, error, warnings));
		CHECK(warnings.empty());
		CHECK(back.hotkeyOpenPanel == 0x30);
		CHECK(back.hotkeyModifiers == (S::Modifier::kCtrl | S::Modifier::kShift));
		CHECK(back.palette == "moss");
		CHECK(back.logLevel == "debug");
		CHECK(back.workerTrackerSeconds == 45);
		CHECK(std::fabs(back.occupiedIncidentChance - 0.33f) < 1e-6f);
		CHECK(S::DiffLines(config, back).empty());

		// Writing to a fresh path (no file yet) works too.
		const auto fresh = (TempDir() / "fresh.toml").string();
		std::filesystem::remove(fresh);
		CHECK(CF::Write(fresh, Config{}, error));
		Config freshBack;
		CHECK(CF::Read(fresh, freshBack, error, warnings));
		CHECK(S::DiffLines(Config{}, freshBack).empty());
	}
}

int main()
{
	TestModifierRule();
	TestTextEntry();
	TestKeyTouch();
	TestScanCodes();
	TestHotkeyText();
	TestRefusedKeys();
	TestModifierToml();
	TestValueRules();
	TestDiffLines();
	TestOldToml();
	TestNewToml();
	TestBadValues();
	TestMissingFile();
	TestRoundTrip();
	std::printf("HonestWorkTests: %d passed, %d failed\n", g_passed, g_failed);
	return g_failed == 0 ? 0 : 1;
}
