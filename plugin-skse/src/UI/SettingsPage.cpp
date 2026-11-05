// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

// SettingsPage.cpp
// Honest Work - Workers of Skyrim

#include "SettingsPage.h"

#include "Core/AppConfig.h"
#include "Core/Log.h"
#include "Core/Settings.h"
#include "UI/PrismaPanel.h"

#include "RE/B/BSKeyboardDevice.h"
#include "RE/C/ControlMap.h"
#include "RE/I/InputEvent.h"
#include "RE/U/UserEvents.h"

// After the CommonLib headers: SKSEMenuFramework.h names RE::InputEvent and
// std::filesystem without including them (commonlib-scout, SMF:1-7).
#include <filesystem>
#include "SKSEMenuFramework.h"

#include <atomic>
#include <chrono>
#include <mutex>
#include <string>

namespace HonestWork::UI::SettingsPage
{
	namespace
	{
		namespace S = Core::Settings;

		std::atomic<std::uint32_t> g_heldModifiers{ S::Modifier::kNone };

		// D197: the capture of the next key (D038).
		std::atomic<bool> g_capturing{ false };
		std::atomic<std::uint32_t> g_lastCapturedCode{ 0 };
		std::atomic<std::int64_t> g_lastCapturedAtMs{ 0 };
		constexpr std::int64_t kCaptureEchoMs = 500;

		// Text under the hotkey row: why a key was refused, or what was taken.
		std::mutex g_messageMutex;
		std::string g_captureMessage;

		// What the TOML holds now. Every commit diffs the live config against
		// it, logs one line per field and writes the file.
		std::mutex g_commitMutex;
		Core::AppConfig::Config g_saved;
		std::string g_saveStatus;

		// The SMF unregisters the callback when this object is destroyed, so
		// it lives for the whole process.
		SKSEMenuFramework::Model::InputEvent* g_inputEvent = nullptr;

		std::int64_t NowMs()
		{
			using namespace std::chrono;
			return duration_cast<milliseconds>(steady_clock::now().time_since_epoch()).count();
		}

		void SetMessage(std::string a_text)
		{
			std::lock_guard lock(g_messageMutex);
			g_captureMessage = std::move(a_text);
		}

		std::string Message()
		{
			std::lock_guard lock(g_messageMutex);
			return g_captureMessage;
		}

		// The key the game maps to the console (ControlMap.h:89,
		// UserEvents.h:116); the default ~ when the map does not say.
		std::uint32_t ConsoleKey()
		{
			const auto* map = RE::ControlMap::GetSingleton();
			const auto* events = RE::UserEvents::GetSingleton();
			if (map && events) {
				const auto key = map->GetMappedKey(events->console.c_str(), RE::INPUT_DEVICE::kKeyboard,
					RE::ControlMap::InputContextID::kGameplay);
				if (key != RE::ControlMap::kInvalid && key != 0) {
					return key;
				}
			}
			return S::Scan::kTilde;
		}

		// Diff, log, apply what is not read live, write the TOML (D194).
		void Commit()
		{
			std::lock_guard lock(g_commitMutex);
			auto& config = Core::AppConfig::GetMutable();
			const auto lines = S::DiffLines(g_saved, config);
			if (lines.empty()) {
				return;
			}
			for (const auto& line : lines) {
				spdlog::info("SettingsPage: setting changed - {}", line);
			}
			if (config.logLevel != g_saved.logLevel) {
				Core::Log::ApplyConfiguredLevel(config.logLevel);
			}
			if (config.palette != g_saved.palette) {
				PrismaPanel::SetPalette(config.palette);
			}
			if (Core::AppConfig::SaveToFile()) {
				spdlog::info("SettingsPage: saved to HonestWork.toml");
				g_saveStatus = "Saved to HonestWork.toml.";
			} else {
				g_saveStatus = "Could not write HonestWork.toml - the change holds until the game closes.";
			}
			g_saved = config;
		}

		// SMF input callback (SMF:60, export RegisterInpoutEvent). The page
		// only uses it to take the new key; the panel hotkey itself stays on
		// PrismaPanel's own sink, which works with or without the SMF.
		bool __stdcall OnInput(RE::InputEvent* a_event)
		{
			if (!a_event || a_event->device != RE::INPUT_DEVICE::kKeyboard) {
				return false;
			}
			const auto* button = a_event->AsButtonEvent();
			if (!button) {
				return false;
			}
			TrackModifiers(*button);
			if (!g_capturing.load() || !button->IsDown()) {
				return false;
			}

			const auto code = button->GetIDCode();
			if (code == S::Scan::kEscape) {
				g_capturing = false;
				SetMessage("Kept the old key.");
				spdlog::info("SettingsPage: hotkey capture cancelled (Esc)");
				return true;
			}
			if (S::ModifierBitForScanCode(code) != S::Modifier::kNone) {
				return true;  // still waiting for the real key
			}
			if (const auto reason = S::RejectReason(code, ConsoleKey()); !reason.empty()) {
				SetMessage(reason);
				spdlog::info("SettingsPage: hotkey capture refused {} - {}", S::ScanCodeName(code), reason);
				return true;  // keep waiting
			}

			const auto modifiers = g_heldModifiers.load();
			auto& config = Core::AppConfig::GetMutable();
			config.hotkeyOpenPanel = code;
			config.hotkeyModifiers = modifiers;
			g_lastCapturedCode = code;
			g_lastCapturedAtMs = NowMs();
			g_capturing = false;
			SetMessage("");
			Commit();
			return true;
		}

		void ModifierBox(const char* a_label, std::uint32_t a_bit, std::uint32_t& a_mask)
		{
			bool on = (a_mask & a_bit) != 0;
			if (ImGuiMCP::Checkbox(a_label, &on)) {
				a_mask = on ? (a_mask | a_bit) : (a_mask & ~a_bit);
			}
		}

		void __stdcall Render()
		{
			auto& config = Core::AppConfig::GetMutable();

			ImGuiMCP::TextWrapped("%s", "Changes apply at once and are saved to HonestWork.toml.");
			ImGuiMCP::Separator();

			// Hotkey (D196, D197).
			ImGuiMCP::Text("Panel key: %s", S::FormatHotkey(config.hotkeyOpenPanel, config.hotkeyModifiers).c_str());
			ImGuiMCP::SameLine();
			if (g_capturing.load()) {
				if (ImGuiMCP::Button("Cancel##hwkey")) {
					g_capturing = false;
					SetMessage("Kept the old key.");
				}
				ImGuiMCP::TextWrapped("%s",
					"Hold Shift, Ctrl or Alt if you want them, then press the new key. Esc cancels.");
			} else if (ImGuiMCP::Button("Change key##hwkey")) {
				SetMessage("");
				g_capturing = true;
			}
			if (const auto message = Message(); !message.empty()) {
				ImGuiMCP::TextWrapped("%s", message.c_str());
			}
			ImGuiMCP::Text("%s", "Also hold:");
			ImGuiMCP::SameLine();
			ModifierBox("Shift##hwmod", S::Modifier::kShift, config.hotkeyModifiers);
			ImGuiMCP::SameLine();
			ModifierBox("Ctrl##hwmod", S::Modifier::kCtrl, config.hotkeyModifiers);
			ImGuiMCP::SameLine();
			ModifierBox("Alt##hwmod", S::Modifier::kAlt, config.hotkeyModifiers);
			ImGuiMCP::TextDisabled("%s", "With none ticked the key opens the panel whatever else is held.");
			ImGuiMCP::Separator();

			// Palette (D198).
			ImGuiMCP::Text("%s", "Panel palette:");
			for (const char* name : S::kPalettes) {
				ImGuiMCP::SameLine();
				if (ImGuiMCP::RadioButton((std::string(name) + "##hwpal").c_str(), config.palette == name)) {
					config.palette = name;
				}
			}
			ImGuiMCP::Separator();

			// Occupied mine incident chance (D137/D142 limit).
			float chance = config.occupiedIncidentChance;
			if (ImGuiMCP::SliderFloat("Occupied mine incident chance##hwinc", &chance, S::kIncidentMin, S::kIncidentMax,
					"%.2f")) {
				config.occupiedIncidentChance = S::ClampIncidentChance(chance);
			}
			ImGuiMCP::TextDisabled("%s", "Chance of an incident when you send a worker to a mine someone else is working.");
			ImGuiMCP::Separator();

			// Log level.
			ImGuiMCP::Text("%s", "Log level:");
			for (const char* level : S::kLogLevels) {
				ImGuiMCP::SameLine();
				if (ImGuiMCP::RadioButton((std::string(level) + "##hwlog").c_str(), config.logLevel == level)) {
					config.logLevel = level;
				}
			}
			ImGuiMCP::Separator();

			// Worker tracker (D200).
			int seconds = static_cast<int>(config.workerTrackerSeconds);
			if (ImGuiMCP::InputInt("Worker tracker, seconds##hwtrk", &seconds, 5, 60)) {
				config.workerTrackerSeconds = S::ClampTrackerSeconds(seconds);
			}
			ImGuiMCP::TextWrapped("%s",
				"0 = off. Under 5 the script uses 5. Turning it on from 0 starts at the next save load; "
				"a new interval applies after the current report.");

			// Commit once nothing is being dragged or typed: one log line and one
			// file write per change, not one per frame of a slider drag.
			if (!ImGuiMCP::IsAnyItemActive()) {
				Commit();
			}
			std::string status;
			{
				std::lock_guard lock(g_commitMutex);
				status = g_saveStatus;
			}
			if (!status.empty()) {
				ImGuiMCP::Separator();
				ImGuiMCP::TextDisabled("%s", status.c_str());
			}
		}
	}

	void TrackModifiers(const RE::ButtonEvent& a_button)
	{
		const auto bit = S::ModifierBitForScanCode(a_button.GetIDCode());
		if (bit == S::Modifier::kNone) {
			return;
		}
		if (a_button.IsUp()) {
			g_heldModifiers &= ~bit;
		} else if (a_button.IsPressed()) {
			g_heldModifiers |= bit;
		}
	}

	std::uint32_t HeldModifiers() { return g_heldModifiers.load(); }

	// Fase 20: SMF.h IsAnyBlockingWindowOpened (l. 206) is a plain exported
	// bool; false when the SMF is missing. Guarded by the registration so the
	// call is never made without the SMF. ImGuiIO::WantTextInput is NOT read:
	// GetIO needs an ImGui context current on this thread (D206).
	bool SmfBlockingWindowOpen()
	{
		return g_inputEvent && SKSEMenuFramework::IsAnyBlockingWindowOpened();
	}

	bool OwnsKey(std::uint32_t a_code)
	{
		if (g_capturing.load()) {
			return true;
		}
		return a_code == g_lastCapturedCode.load() && NowMs() - g_lastCapturedAtMs.load() < kCaptureEchoMs;
	}

	void Register()
	{
		{
			std::lock_guard lock(g_commitMutex);
			g_saved = Core::AppConfig::Get();
		}
		if (!SKSEMenuFramework::IsInstalled()) {
			spdlog::info("SettingsPage: SKSE Menu Framework not installed - settings stay in HonestWork.toml (D195).");
			return;
		}
		SKSEMenuFramework::SetSection("Honest Work");
		SKSEMenuFramework::AddSectionItem("Settings", &Render);
		g_inputEvent = SKSEMenuFramework::AddInputEvent(&OnInput);
		spdlog::info("SettingsPage: page registered in SKSE Menu Framework {} (Honest Work/Settings).",
			SKSEMenuFramework::GetMenuFrameworkVersion());
	}
}
