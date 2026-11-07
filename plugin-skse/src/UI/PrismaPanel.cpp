// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

// PrismaPanel.cpp
// Honest Work - Workers of Skyrim

#include "PrismaPanel.h"

#include "Core/AppConfig.h"
#include "Core/ModEventBridge.h"
#include "Core/ProfessionsRegistry.h"
#include "Core/Settings.h"
#include "UI/SettingsPage.h"

#include "PrismaUI_API.h"

#include "RE/B/BSInputDeviceManager.h"
#include "RE/B/BSKeyboardDevice.h"
#include "RE/C/Console.h"
#include "RE/C/ControlMap.h"
#include "RE/I/InputEvent.h"
#include "RE/U/UI.h"

#include <nlohmann/json.hpp>

#include <algorithm>
#include <array>
#include <cstdint>
#include <mutex>
#include <string>
#include <vector>

namespace HonestWork::UI::PrismaPanel
{
	namespace
	{
		using json = nlohmann::json;

		PRISMA_UI_API::IVPrismaUI1* g_prismaUI = nullptr;
		PrismaView g_view = 0;

		// Fase 19 (D198): the palette the page should wear. Read on DOM ready
		// (the main thread) and written by SetPalette (any thread).
		std::mutex g_paletteMutex;
		std::string g_palette = "frost";

		std::string CurrentPalette()
		{
			std::lock_guard lock(g_paletteMutex);
			return g_palette;
		}

		// Main thread only (DOM-ready callback or an SKSE task).
		void SendPalette(PrismaView a_view, const std::string& a_palette, const char* a_why)
		{
			// The name is one of Core::Settings::kPalettes, so it needs no escaping.
			const std::string script = "window.hwTheme && window.hwTheme(\"" + a_palette + "\")";
			g_prismaUI->Invoke(a_view, script.c_str());
			spdlog::info("PrismaPanel: palette '{}' sent to the page ({})", a_palette, a_why);
		}

		// hwThemeApplied: the page says which palette it wears now, so the log
		// shows the palette arrived and not only that it was sent.
		void OnThemeApplied(const char* a_argument)
		{
			try {
				const json arg = json::parse(a_argument);
				const auto applied = arg.value("applied", std::string());
				const auto asked = arg.value("asked", std::string());
				spdlog::info("PrismaPanel: page applied palette '{}' (asked '{}')", applied, asked);
			} catch (const json::exception& e) {
				spdlog::error("PrismaPanel: hwThemeApplied could not parse '{}' ({})", a_argument, e.what());
			}
		}

		// The MVP worker pool is a fixed 4-slot ReferenceAlias array
		// (WOSK_WorkerPool, WOSK_ControllerScript.WorkerPoolSize). Duplicated
		// here as a UI-only constant (same reasoning the SMF panel already
		// had - PanelModule.cpp, D079 does not remove this duplication, only
		// the rendering technology changes).
		constexpr std::uint32_t kWorkerPoolSize = 4;

		// D105: the MVP's only hold. A task is offered only where the hold has a
		// source of its resource type (Core::ProfessionsRegistry, hold_sources/).
		constexpr auto kHold = "Whiterun";

		// D126: the second tier is "Journeyman" on screen and "worker" in the
		// data. Same rule as WOSK_Names.TierLabel (Papyrus): unknown ids come
		// back unchanged.
		std::string TierLabel(const std::string& a_tier)
		{
			if (a_tier == "apprentice") {
				return "Apprentice";
			}
			if (a_tier == "worker") {
				return "Journeyman";
			}
			if (a_tier == "veteran") {
				return "Veteran";
			}
			if (a_tier == "master") {
				return "Master";
			}
			return a_tier;
		}

		// Built in OnDataLoaded, on the main thread, because the price calls
		// into the game; the view callback only sends it.
		std::string g_initPayload;

		// Fase 15: every task of every profession, read from the registry - the
		// fixed miner list is gone. The page shows a worker only the tasks of
		// that worker's profession, and a task above the worker's tier locked,
		// with the tier it needs (minTier/minTierLabel below).
		// The bodyguard fee terms, read from the same outcome row Papyrus charges by
		// (WOSK_Guards.ContractFee), so the quote on the page and the gold taken share one source.
		json GuardFeeTerms()
		{
			const float rate = Core::ProfessionsRegistry::OutcomeRowFloat("bodyguard", 0, "contractFeeRate", 0.25f);
			const float minFee = Core::ProfessionsRegistry::OutcomeRowFloat("bodyguard", 0, "contractFeeMin", 40.0f);
			spdlog::info("PrismaPanel: bodyguard fee terms rate={} min={} (the quote on the page)", rate, minFee);
			return json{ { "rate", rate }, { "min", minFee } };
		}

		std::string BuildInitPayload()
		{
			json tasks = json::array();
			for (const auto& t : Core::ProfessionsRegistry::ListTasks()) {
				const std::int32_t sources = Core::ProfessionsRegistry::CountHoldSources(kHold, t.resourceType);
				// Fase 33 etapa 10 (D292, V073): a task with no source in the hold is no longer
				// dropped here. It stays on the list and the page shows it as "None here" with the
				// contract button off, so the player sees why the work is missing. holdSources lets the
				// page say so before Papyrus's own list arrives.
				spdlog::info("PrismaPanel: task '{}/{}' ({}) listed - {} source(s) in {}{}", t.profession, t.id,
					t.resourceType, sources, kHold, sources > 0 ? "" : " (shown as None here)");
				const float price = Core::ProfessionsRegistry::TaskUnitPrice(t.profession, t.id);
				spdlog::info("PrismaPanel: task '{}/{}' reference price {} gold/unit (output value in game)",
					t.profession, t.id, price);
				const float ingredients = Core::ProfessionsRegistry::TaskIngredientCost(t.profession, t.id);
				if (ingredients != 0.0f) {
					spdlog::info("PrismaPanel: task '{}/{}' ingredients {} gold/unit (D159, -1 = not resolved)",
						t.profession, t.id, ingredients);
				}
				tasks.push_back(json{
					{ "id", t.id },
					{ "profession", t.profession },
					{ "label", t.label },
					{ "minTier", t.minTier },
					{ "minTierLabel", TierLabel(t.minTier) },
					{ "hours", t.hours },
					{ "batchMin", t.batchMin },
					{ "batchMax", t.batchMax },
					{ "incidentChance", t.incidentChance },
					{ "basePricePerUnit", price },
					{ "ingredientCostPerUnit", ingredients },
					{ "priceMultiplier", t.priceMultiplier },
					{ "holdSources", sources },
				});
			}
			// Fase 17 (D168): the tier ladder on the Worker tab - what each tier
			// asks in contracts completed, per profession, read from the registry
			// (the same minContracts WOSK_WorkerAliasScript._MaybeAdvanceTier reads).
			json tiers = json::array();
			for (const auto& r : Core::ProfessionsRegistry::ListTiers()) {
				tiers.push_back(json{
					{ "profession", r.profession },
					{ "id", r.id },
					{ "label", TierLabel(r.id) },
					{ "minContracts", r.minContracts },
					{ "durationMultiplier", r.durationMultiplier },
					{ "yieldMultiplier", r.yieldMultiplier },
				});
			}
			json payload{
				{ "workerPoolSize", kWorkerPoolSize },
				{ "tasks", tasks },
				{ "tiers", tiers },
				{ "guardFee", GuardFeeTerms() },
			};
			return payload.dump();
		}

		// Every JS -> C++ listener callback below takes a single JSON string
		// argument (JSListenerCallback = void(*)(const char*), PrismaUI_API.h)
		// and never trusts it blindly - a malformed/unexpected payload is
		// logged and dropped, never crashes, same
		// tolerance the rest of this project already applies to third-party
		// JSON (D078).
		bool TryGetInt(const json& a_obj, const char* a_key, int& a_out)
		{
			auto it = a_obj.find(a_key);
			if (it == a_obj.end() || !it->is_number_integer()) {
				return false;
			}
			a_out = it->get<int>();
			return true;
		}

		// The bodyguard choice rides the task id as "<taskId>|g" (the bridge carries one string and
		// one float; the Papyrus side strips the suffix). Only a literal JSON true adds it.
		std::string WithGuardBit(std::string a_taskId, const json& a_obj)
		{
			auto it = a_obj.find("guard");
			if (it != a_obj.end() && it->is_boolean() && it->get<bool>()) {
				a_taskId += "|g";
			}
			return a_taskId;
		}

		void OnIssueContract(const char* a_argument)
		{
			try {
				json arg = json::parse(a_argument);
				int aliasIndex = 0;
				if (!TryGetInt(arg, "aliasIndex", aliasIndex)) {
					spdlog::error("PrismaPanel: hwIssueContract missing/invalid aliasIndex: {}", a_argument);
					return;
				}
				auto taskIdIt = arg.find("taskId");
				if (taskIdIt == arg.end() || !taskIdIt->is_string()) {
					spdlog::error("PrismaPanel: hwIssueContract missing/invalid taskId: {}", a_argument);
					return;
				}
				Core::ModEventBridge::Send(
					Core::ModEventBridge::kEventIssueContract, WithGuardBit(taskIdIt->get<std::string>(), arg), static_cast<float>(aliasIndex));
			} catch (const json::exception& e) {
				spdlog::error("PrismaPanel: hwIssueContract could not parse '{}' ({})", a_argument, e.what());
			}
		}

		void OnIssueOccupied(const char* a_argument)
		{
			try {
				json arg = json::parse(a_argument);
				int aliasIndex = 0;
				if (!TryGetInt(arg, "aliasIndex", aliasIndex)) {
					spdlog::error("PrismaPanel: hwIssueOccupied missing/invalid aliasIndex: {}", a_argument);
					return;
				}
				auto taskIdIt = arg.find("taskId");
				if (taskIdIt == arg.end() || !taskIdIt->is_string()) {
					spdlog::error("PrismaPanel: hwIssueOccupied missing/invalid taskId: {}", a_argument);
					return;
				}
				Core::ModEventBridge::Send(
					Core::ModEventBridge::kEventIssueOccupied, WithGuardBit(taskIdIt->get<std::string>(), arg), static_cast<float>(aliasIndex));
			} catch (const json::exception& e) {
				spdlog::error("PrismaPanel: hwIssueOccupied could not parse '{}' ({})", a_argument, e.what());
			}
		}

		void OnCure(const char* a_argument)
		{
			try {
				json arg = json::parse(a_argument);
				int aliasIndex = 0;
				if (!TryGetInt(arg, "aliasIndex", aliasIndex)) {
					spdlog::error("PrismaPanel: hwCure missing/invalid aliasIndex: {}", a_argument);
					return;
				}
				Core::ModEventBridge::Send(Core::ModEventBridge::kEventCure, "", static_cast<float>(aliasIndex));
			} catch (const json::exception& e) {
				spdlog::error("PrismaPanel: hwCure could not parse '{}' ({})", a_argument, e.what());
			}
		}

		void OnFire(const char* a_argument)
		{
			try {
				json arg = json::parse(a_argument);
				int aliasIndex = 0;
				if (!TryGetInt(arg, "aliasIndex", aliasIndex)) {
					spdlog::error("PrismaPanel: hwFire missing/invalid aliasIndex: {}", a_argument);
					return;
				}
				Core::ModEventBridge::Send(Core::ModEventBridge::kEventFire, "", static_cast<float>(aliasIndex));
			} catch (const json::exception& e) {
				spdlog::error("PrismaPanel: hwFire could not parse '{}' ({})", a_argument, e.what());
			}
		}

		void OnPickUp(const char* a_argument)
		{
			try {
				json arg = json::parse(a_argument);
				int aliasIndex = 0;
				if (!TryGetInt(arg, "aliasIndex", aliasIndex)) {
					spdlog::error("PrismaPanel: hwPickUp missing/invalid aliasIndex: {}", a_argument);
					return;
				}
				Core::ModEventBridge::Send(Core::ModEventBridge::kEventPickUp, "", static_cast<float>(aliasIndex));
			} catch (const json::exception& e) {
				spdlog::error("PrismaPanel: hwPickUp could not parse '{}' ({})", a_argument, e.what());
			}
		}

		// Fase 33 etapa 10: the page tells the log what it could not word (a state it does not
		// know, a task with no row), so the next round can read it. Text only, never trusted:
		// clipped and logged.
		void OnPanelNote(const char* a_argument)
		{
			try {
				json arg = json::parse(a_argument);
				std::string text = arg.value("text", std::string());
				if (text.size() > 300) {
					text.resize(300);
				}
				spdlog::info("PrismaPanel: panel note: {}", text);
			} catch (const json::exception& e) {
				spdlog::error("PrismaPanel: hwNote could not parse '{}' ({})", a_argument, e.what());
			}
		}

		// D104 etapa 3: the Recruit tab's hire button.
		void OnHireCandidate(const char* a_argument)
		{
			try {
				json arg = json::parse(a_argument);
				int spot = 0;
				if (!TryGetInt(arg, "spot", spot)) {
					spdlog::error("PrismaPanel: hwHireCandidate missing/invalid spot: {}", a_argument);
					return;
				}
				Core::ModEventBridge::Send(Core::ModEventBridge::kEventHire, "", static_cast<float>(spot));
			} catch (const json::exception& e) {
				spdlog::error("PrismaPanel: hwHireCandidate could not parse '{}' ({})", a_argument, e.what());
			}
		}

		// Fase 34 etapa 2 (D299): hire a follower from the Recruit tab. The trade id is text from
		// the page, so it is clipped and limited to [a-z_] before it travels to Papyrus.
		void OnHireFollower(const char* a_argument)
		{
			try {
				json arg = json::parse(a_argument);
				int index = 0;
				if (!TryGetInt(arg, "index", index)) {
					spdlog::error("PrismaPanel: hwHireFollower missing/invalid index: {}", a_argument);
					return;
				}
				std::string profession = arg.value("profession", std::string());
				if (profession.empty() || profession.size() > 32 ||
					profession.find_first_not_of("abcdefghijklmnopqrstuvwxyz_") != std::string::npos) {
					spdlog::error("PrismaPanel: hwHireFollower invalid profession: {}", a_argument);
					return;
				}
				Core::ModEventBridge::Send(Core::ModEventBridge::kEventHireFollower, profession,
					static_cast<float>(index));
			} catch (const json::exception& e) {
				spdlog::error("PrismaPanel: hwHireFollower could not parse '{}' ({})", a_argument, e.what());
			}
		}

		// Assign a follower of the player as a bodyguard (the Recruit tab, same list as the hire).
		void OnAssignGuard(const char* a_argument)
		{
			try {
				json arg = json::parse(a_argument);
				int index = 0;
				if (!TryGetInt(arg, "index", index)) {
					spdlog::error("PrismaPanel: hwAssignGuard missing/invalid index: {}", a_argument);
					return;
				}
				Core::ModEventBridge::Send(Core::ModEventBridge::kEventAssignGuard, "", static_cast<float>(index));
			} catch (const json::exception& e) {
				spdlog::error("PrismaPanel: hwAssignGuard could not parse '{}' ({})", a_argument, e.what());
			}
		}

		// --- Recruit tab natives (D104 etapa 3, Scripts/Source/WOSK_Panel.psc) ---
		//
		// Papyrus builds the candidate list - tier, profession and price live in
		// StorageUtil, which this DLL cannot read - and hands it over here. The
		// view is only touched from an SKSE task (SKSE/Interfaces.h:180-223,
		// AddTask(std::function<void()>)), never from the VM thread that runs the
		// native.
		constexpr auto kPanelScriptClass = "WOSK_Panel";

		std::string Text(const RE::BSFixedString& a_text)
		{
			return a_text.c_str() ? std::string(a_text.c_str()) : std::string();
		}

		// Arrays arrive as std::vector (PackUnpackImpl.h:73-92, one-shot copy).
		void SetRecruitList(RE::StaticFunctionTag*, std::vector<RE::BSFixedString> a_names,
			std::vector<RE::BSFixedString> a_professions, std::vector<RE::BSFixedString> a_tiers,
			std::vector<std::int32_t> a_prices, std::vector<std::int32_t> a_spots,
			std::vector<RE::BSFixedString> a_places, std::int32_t a_count, std::int32_t a_hired, std::int32_t a_cap,
			std::int32_t a_canHire, RE::BSFixedString a_message,
			std::vector<RE::BSFixedString> a_blocked)
		{
			// Parenthesized: windows.h defines min/max as macros.
			const std::size_t count = (std::min)({ static_cast<std::size_t>((std::max)(a_count, 0)), a_names.size(),
				a_professions.size(), a_tiers.size(), a_prices.size(), a_spots.size(), a_places.size() });
			json candidates = json::array();
			for (std::size_t i = 0; i < count; ++i) {
				candidates.push_back(json{
					{ "spot", a_spots[i] },
					{ "name", Text(a_names[i]) },
					{ "profession", Text(a_professions[i]) },
					{ "tier", Text(a_tiers[i]) },
					{ "price", a_prices[i] },
					{ "place", Text(a_places[i]) },  // D161: where the candidate stands
					// Fase 33 etapa 10: the id of the rule that stops the hire (COOK_HOLD) or "";
					// a shorter array (an older script) reads as none.
					{ "blocked", i < a_blocked.size() ? Text(a_blocked[i]) : std::string() },
				});
				spdlog::info("PrismaPanel: recruit candidate spot {} '{}' {} {} {} gold at '{}'", a_spots[i],
					Text(a_names[i]), Text(a_professions[i]), Text(a_tiers[i]), a_prices[i], Text(a_places[i]));
			}
			// D184: canHire is the recruiter sign (Papyrus sends 0/1). Without it
			// the page shows the pool and keeps the Hire button off.
			const bool canHire = a_canHire != 0;
			json payload{
				{ "hired", a_hired },
				{ "cap", a_cap },
				{ "canHire", canHire },
				{ "message", Text(a_message) },
				{ "candidates", candidates },
			};
			spdlog::info("PrismaPanel: recruit list sent ({} candidate(s), {} of {} hired, canHire {}, message '{}')",
				count, a_hired, a_cap, canHire, Text(a_message));
			// ASCII-escaped, bad bytes replaced: a name is game text, and the result
			// is pasted into a JS call.
			std::string script = "window.hwRecruit(" +
			                     payload.dump(-1, ' ', true, json::error_handler_t::replace) + ")";
			SKSE::GetTaskInterface()->AddTask([script = std::move(script)]() {
				if (g_prismaUI && g_view) {
					g_prismaUI->Invoke(g_view, script.c_str());
				}
			});
		}

		// Fase 34 etapa 2 (D299): the "Your followers" section. Same shape as SetRecruitList.
		void SetFollowerList(RE::StaticFunctionTag*, std::vector<RE::BSFixedString> a_names,
			std::vector<RE::BSFixedString> a_places, std::vector<RE::BSFixedString> a_refused,
			std::vector<RE::BSFixedString> a_tiers, std::int32_t a_count, std::int32_t a_needsPo3,
			RE::BSFixedString a_message)
		{
			const std::size_t count = (std::min)({ static_cast<std::size_t>((std::max)(a_count, 0)), a_names.size(),
				a_places.size(), a_refused.size(), a_tiers.size() });
			json followers = json::array();
			for (std::size_t i = 0; i < count; ++i) {
				followers.push_back(json{
					{ "index", static_cast<int>(i) },
					{ "name", Text(a_names[i]) },
					{ "place", Text(a_places[i]) },
					{ "refused", Text(a_refused[i]) },
					{ "tiers", Text(a_tiers[i]) },  // "trade:tier,trade:tier"
				});
				spdlog::info("PrismaPanel: follower {} '{}' at '{}' refused='{}'", i, Text(a_names[i]),
					Text(a_places[i]), Text(a_refused[i]));
			}
			json payload{
				{ "needsPo3", a_needsPo3 != 0 },
				{ "message", Text(a_message) },
				{ "followers", followers },
			};
			spdlog::info("PrismaPanel: follower list sent ({} follower(s), needsPo3 {}, message '{}')", count,
				a_needsPo3 != 0, Text(a_message));
			std::string script = "window.hwFollowers(" +
			                     payload.dump(-1, ' ', true, json::error_handler_t::replace) + ")";
			SKSE::GetTaskInterface()->AddTask([script = std::move(script)]() {
				if (g_prismaUI && g_view) {
					g_prismaUI->Invoke(g_view, script.c_str());
				}
			});
		}

		// --- Workers tab native (queue item 11, Scripts/Source/WOSK_Panel.psc) ---
		//
		// Same shape as SetRecruitList above, and deliberately so: the tab needs a
		// LIVE channel, and the recruit list is the only channel this panel has
		// that Papyrus can push at any moment. The difference is who calls it -
		// the recruit list is built when the player opens the tab, this one is
		// pushed by WOSK_PanelBridgeScript.PushPanelState() from every contract
		// state change, so the situation on screen changes without reopening it.
		void SetWorkerList(RE::StaticFunctionTag*, std::vector<RE::BSFixedString> a_names,
			std::vector<RE::BSFixedString> a_professions, std::vector<RE::BSFixedString> a_tiers,
			std::vector<RE::BSFixedString> a_holds, std::vector<RE::BSFixedString> a_states,
			std::vector<float> a_hoursLeft, std::vector<std::int32_t> a_slots,
			std::vector<std::int32_t> a_canIssue, std::int32_t a_count)
		{
			// Parenthesized: windows.h defines min/max as macros.
			const std::size_t count = (std::min)({ static_cast<std::size_t>((std::max)(a_count, 0)), a_names.size(),
				a_professions.size(), a_tiers.size(), a_holds.size(), a_states.size(), a_hoursLeft.size(),
				a_slots.size(), a_canIssue.size() });
			json workers = json::array();
			for (std::size_t i = 0; i < count; ++i) {
				workers.push_back(json{
					{ "slot", a_slots[i] },
					{ "name", Text(a_names[i]) },
					{ "profession", Text(a_professions[i]) },
					{ "tier", Text(a_tiers[i]) },
					{ "hold", Text(a_holds[i]) },
					{ "state", Text(a_states[i]) },
					// Papyrus has no Bool array over the native boundary that this
					// codebase already proved, so the flag crosses as 0/1 and is
					// narrowed here instead of on the page.
					{ "canIssue", a_canIssue[i] != 0 },
					{ "hoursLeft", a_hoursLeft[i] },
				});
			}
			json payload{
				{ "workers", workers },
			};
			spdlog::info("PrismaPanel: worker list sent ({} worker(s))", count);
			// ASCII-escaped, bad bytes replaced: a name is game text, and the result
			// is pasted into a JS call.
			std::string script = "window.hwWorkers(" +
			                     payload.dump(-1, ' ', true, json::error_handler_t::replace) + ")";
			SKSE::GetTaskInterface()->AddTask([script = std::move(script)]() {
				if (g_prismaUI && g_view) {
					g_prismaUI->Invoke(g_view, script.c_str());
				}
			});
		}

		// --- Issue tab source native (queue item 13, Scripts/Source/WOSK_Panel.psc) ---
		//
		// What the hold still has, per task. Pushed on the same beats as
		// SetWorkerList - a contract issued or settled is what changes these
		// numbers - and matched to the Issue tab's task list by id on the page.
		//
		// a_units is veins x the game's own per-vein yield, and -1 where that
		// yield has not been seen on this save yet; the page prints the veins
		// alone in that case.
		//
		// The reason crosses as an ID ("UNCONFIRMED", "OCCUPIED", "DEPLETED",
		// "NONE", or "" when the ore can be worked) and is worded on the page,
		// so no player-facing sentence is built in Papyrus, where a literal
		// that collides with an id comes out wearing the id's case (D127/D129).
		void SetSourceList(RE::StaticFunctionTag*, std::vector<RE::BSFixedString> a_taskIds,
			std::vector<std::int32_t> a_veins, std::vector<std::int32_t> a_units,
			std::vector<RE::BSFixedString> a_reasons, RE::BSFixedString a_hold, std::int32_t a_count,
			std::vector<RE::BSFixedString> a_places, std::vector<std::int32_t> a_backHours)
		{
			// Parenthesized: windows.h defines min/max as macros.
			const std::size_t count = (std::min)({ static_cast<std::size_t>((std::max)(a_count, 0)),
				a_taskIds.size(), a_veins.size(), a_units.size(), a_reasons.size() });
			json sources = json::array();
			for (std::size_t i = 0; i < count; ++i) {
				sources.push_back(json{
					{ "taskId", Text(a_taskIds[i]) },
					{ "veins", a_veins[i] },
					{ "units", a_units[i] },
					{ "reason", Text(a_reasons[i]) },
					// Fase 33 etapa 8 (D1): the kitchen a row speaks of and the hours until a
					// worked-out row recovers; shorter arrays (an older script) read as none.
					{ "place", i < a_places.size() ? Text(a_places[i]) : std::string() },
					{ "backInHours", i < a_backHours.size() ? a_backHours[i] : 0 },
				});
			}
			// Fase 33 etapa 10 (F3, V073): the rows themselves, once per change. The log of round 17
			// had only the count, so "iron and silver without a tag" could not be told from a row that
			// never arrived. taskId/veins/units/reason per row; an id that is not all lowercase came
			// back from Papyrus in the case of another string it collides with, and the page matches
			// ids ignoring case for that reason.
			{
				static std::string s_lastRows;
				std::string rows;
				std::size_t oddCase = 0;
				for (std::size_t i = 0; i < count; ++i) {
					const std::string id = Text(a_taskIds[i]);
					const std::string reason = Text(a_reasons[i]);
					for (const char ch : id) {
						if (ch >= 'A' && ch <= 'Z') {
							++oddCase;
							break;
						}
					}
					rows += id + ":" + std::to_string(a_veins[i]) + "/" + std::to_string(a_units[i]) + "/" +
					        (reason.empty() ? std::string("-") : reason) + " ";
				}
				if (rows != s_lastRows) {
					s_lastRows = rows;
					spdlog::info("PrismaPanel: source rows (task:veins/units/reason) {}- {} id(s) not in lowercase", rows, oddCase);
				}
			}
			json payload{
				{ "hold", Text(a_hold) },
				{ "sources", sources },
			};
			spdlog::info("PrismaPanel: source list sent ({} task row(s) for {})", count, Text(a_hold));
			// ASCII-escaped, bad bytes replaced: a hold name is game text, and the
			// result is pasted into a JS call.
			std::string script = "window.hwSources(" +
			                     payload.dump(-1, ' ', true, json::error_handler_t::replace) + ")";
			SKSE::GetTaskInterface()->AddTask([script = std::move(script)]() {
				if (g_prismaUI && g_view) {
					g_prismaUI->Invoke(g_view, script.c_str());
				}
			});
		}

		// --- History native (Fase 17, D168, Scripts/Source/WOSK_Panel.psc) ---
		//
		// The Overview and Worker tabs: totals, the statement and each hired
		// worker's counters. Pushed with SetWorkerList on every contract state
		// change. Lines cross as Papyrus wrote them (ids and numbers joined by
		// "|", WOSK_LedgerScript) and are split and worded on the page, so no
		// player-facing sentence is built on the Papyrus side (D127/D129).
		void SetHistory(RE::StaticFunctionTag*, std::vector<RE::BSFixedString> a_journal, std::int32_t a_journalCount,
			std::vector<std::int32_t> a_slots, std::vector<std::int32_t> a_completed,
			std::vector<std::int32_t> a_goldSpent, std::vector<std::int32_t> a_value,
			std::vector<RE::BSFixedString> a_histories, std::int32_t a_workerCount, std::int32_t a_totalGold,
			std::int32_t a_totalValue, std::int32_t a_totalDone, std::int32_t a_active, float a_now)
		{
			// Parenthesized: windows.h defines min/max as macros.
			const std::size_t journalCount =
				(std::min)(static_cast<std::size_t>((std::max)(a_journalCount, 0)), a_journal.size());
			json journal = json::array();
			for (std::size_t i = 0; i < journalCount; ++i) {
				journal.push_back(Text(a_journal[i]));
			}
			const std::size_t workerCount = (std::min)({ static_cast<std::size_t>((std::max)(a_workerCount, 0)),
				a_slots.size(), a_completed.size(), a_goldSpent.size(), a_value.size(), a_histories.size() });
			json workers = json::array();
			for (std::size_t i = 0; i < workerCount; ++i) {
				workers.push_back(json{
					{ "slot", a_slots[i] },
					{ "completed", a_completed[i] },
					{ "goldSpent", a_goldSpent[i] },
					{ "valueDelivered", a_value[i] },
					{ "history", Text(a_histories[i]) },
				});
			}
			json payload{
				{ "now", a_now },
				{ "goldSpent", a_totalGold },
				{ "valueDelivered", a_totalValue },
				{ "contractsDone", a_totalDone },
				{ "active", a_active },
				{ "journal", journal },
				{ "workers", workers },
			};
			spdlog::info("PrismaPanel: history sent ({} statement line(s), {} worker(s), spent {}, delivered {}, "
						 "done {}, active {})",
				journalCount, workerCount, a_totalGold, a_totalValue, a_totalDone, a_active);
			// ASCII-escaped, bad bytes replaced: a name is game text, and the result
			// is pasted into a JS call.
			std::string script = "window.hwHistory(" +
			                     payload.dump(-1, ' ', true, json::error_handler_t::replace) + ")";
			SKSE::GetTaskInterface()->AddTask([script = std::move(script)]() {
				if (g_prismaUI && g_view) {
					g_prismaUI->Invoke(g_view, script.c_str());
				}
			});
		}

		// Fase 17 B (D171): the answer to an order given on the panel - issue,
		// collect, cure, dismiss - so the page says it on screen. Ids only; the
		// page words them (D127/D129). Same queue-to-the-view path as above.
		void SetOutcome(RE::StaticFunctionTag*, RE::BSFixedString a_action, std::int32_t a_slot,
			RE::BSFixedString a_code, RE::BSFixedString a_arg, std::int32_t a_number)
		{
			json payload{
				{ "action", Text(a_action) },
				{ "slot", a_slot },
				{ "code", Text(a_code) },
				{ "arg", Text(a_arg) },
				{ "number", a_number },
			};
			spdlog::info("PrismaPanel: outcome sent ({} slot {}: {} '{}' {})", Text(a_action), a_slot, Text(a_code),
				Text(a_arg), a_number);
			std::string script = "window.hwOutcome(" +
			                     payload.dump(-1, ' ', true, json::error_handler_t::replace) + ")";
			SKSE::GetTaskInterface()->AddTask([script = std::move(script)]() {
				if (g_prismaUI && g_view) {
					g_prismaUI->Invoke(g_view, script.c_str());
				}
			});
		}

		void OpenRecruit(RE::StaticFunctionTag*)
		{
			SKSE::GetTaskInterface()->AddTask([]() {
				if (!g_prismaUI || !g_view) {
					spdlog::warn("PrismaPanel: OpenRecruit with no panel (Prisma UI missing)");
					return;
				}
				g_prismaUI->Show(g_view);
				g_prismaUI->Focus(g_view, false, false);
				spdlog::info("PrismaPanel: panel opened by the recruiter");
			});
		}

		bool RegisterFuncs(RE::BSScript::IVirtualMachine* a_vm)
		{
			if (!a_vm) {
				return false;
			}
			a_vm->RegisterFunction("SetRecruitList", kPanelScriptClass, SetRecruitList);
			a_vm->RegisterFunction("SetFollowerList", kPanelScriptClass, SetFollowerList);
			a_vm->RegisterFunction("SetWorkerList", kPanelScriptClass, SetWorkerList);
			a_vm->RegisterFunction("SetSourceList", kPanelScriptClass, SetSourceList);
			a_vm->RegisterFunction("SetHistory", kPanelScriptClass, SetHistory);
			a_vm->RegisterFunction("SetOutcome", kPanelScriptClass, SetOutcome);
			a_vm->RegisterFunction("OpenRecruit", kPanelScriptClass, OpenRecruit);
			spdlog::info("PrismaPanel: {} natives bound (SetRecruitList, SetWorkerList, SetSourceList, SetHistory, "
						 "SetOutcome, OpenRecruit).",
				kPanelScriptClass);
			return true;
		}

		// Show/hide/unfocus is pure UI. The one thing Papyrus hears is that the
		// panel closed (D184): the recruiter sign must not outlive the panel
		// it was given to, so the next opening starts without it.
		void SendPanelClosed(const char* a_how)
		{
			spdlog::info("PrismaPanel: panel closed ({}), {} sent", a_how, Core::ModEventBridge::kEventPanelClosed);
			Core::ModEventBridge::Send(Core::ModEventBridge::kEventPanelClosed, "", 0.0f);
		}

		void HidePanel(const char* a_how)
		{
			if (g_prismaUI && g_view) {
				g_prismaUI->Hide(g_view);
				g_prismaUI->Unfocus(g_view);
				SendPanelClosed(a_how);
			}
		}

		// hwClosePanel: the page's Close button (and Esc in a browser).
		void OnClosePanel(const char*)
		{
			HidePanel("close button");
		}

		void TogglePanel()
		{
			if (!g_prismaUI || !g_view) {
				spdlog::info("PrismaPanel: TogglePanel dropped - Prisma UI {} / view {}",
					g_prismaUI ? "ready" : "missing", g_view ? "ready" : "missing");
				return;
			}
			const bool wasHidden = g_prismaUI->IsHidden(g_view);
			spdlog::info("PrismaPanel: TogglePanel - panel was {}", wasHidden ? "hidden, opening" : "shown, closing");
			if (wasHidden) {
				g_prismaUI->Show(g_view);
				// pauseGame=false: this panel was never modal under SKSE Menu
				// Framework either (PanelModule.cpp had no pause call) - the
				// ledger/worker cycle keeps advancing in game time while the
				// panel is open, matching the design's timers.
				g_prismaUI->Focus(g_view, false, false);
				// D187: the old Recruit list is cleared first, so a list left by
				// the recruiter (canHire on) is never shown on a hotkey opening.
				// Papyrus answers WOSK_PanelOpened with a fresh list without the
				// sign (D184), which replaces this null.
				g_prismaUI->Invoke(g_view, "window.hwRecruit(null)");
				// Queue item 11: ask Papyrus for the worker list. Without this
				// the tab would be empty until the next contract state change,
				// which can be hours of game time away.
				Core::ModEventBridge::Send(Core::ModEventBridge::kEventPanelOpened, "", 0.0f);
			} else {
				HidePanel("hotkey");
			}
		}

		// Fase 18 conserto 3 (D208): per-key state of the touch rule, read and
		// written only by the input sink (one thread).
		Core::Settings::KeyTouchState g_hotkeyTouch;
		std::uint32_t g_hotkeyTouchCode = 0;
		Core::Settings::KeyTouchState g_escapeTouch;

		// Which frame the accepted touch came in on, for the log (D208).
		const char* TouchPath(const Core::Settings::KeyTouch& a_touch)
		{
			return a_touch.edge == Core::Settings::KeyEdge::kTouchKeyDown ?
			           "via key-down" :
			           "via first held frame, key-down not seen";
		}

		// RE::BSTEventSink<RE::InputEvent*>::ProcessEvent receives the head of
		// a frame's linked list of input events (InputEvent::next), not a
		// single event - confirmed against
		// the real instantiation shape already used by RE::MenuControls in
		// the vendored headers (extern/commonlibsse-ng/include/RE/M/
		// MenuControls.h). A raw BSTEventSink<InputEvent*> registered directly
		// replaces what SKSEMenuFramework's wrapper did before.
		class InputSink : public RE::BSTEventSink<RE::InputEvent*>
		{
		public:
			RE::BSEventNotifyControl ProcessEvent(
				RE::InputEvent* const* a_events, RE::BSTEventSource<RE::InputEvent*>*) override
			{
				if (!a_events) {
					return RE::BSEventNotifyControl::kContinue;
				}

				auto* ui = RE::UI::GetSingleton();
				const bool consoleOpen = ui && ui->IsMenuOpen(RE::Console::MENU_NAME);

					// Fase 20 (D205): every place that can be receiving typed
					// text, read once per frame.
					Core::Settings::TextEntrySignals signals;
					signals.consoleOpen = consoleOpen;
					if (auto* controlMap = RE::ControlMap::GetSingleton()) {
						signals.scaleformTextEntry = controlMap->GetRuntimeData().textEntryCount;
					}
					if (g_prismaUI) {
						signals.prismaAnyFocus = g_prismaUI->HasAnyActiveFocus();
						signals.prismaOwnFocus = g_view && g_prismaUI->HasFocus(g_view);
					}
					signals.smfBlockingWindow = SettingsPage::SmfBlockingWindowOpen();
					const char* textEntry = Core::Settings::TextEntrySource(signals);

				for (auto* event = *a_events; event; event = event->next) {
					// Fase 18 conserto: V048 saw the hotkey injected and no log line.
					// The configured key is logged before any filter, and the
					// filter that drops it says why.
					const auto* keyEvent = event->AsButtonEvent();
					// Fase 19 (D196): Shift/Ctrl/Alt held state, before every
					// filter - a release seen only by a filtered branch would
					// leave the modifier stuck "held" (D107).
					if (event->device == RE::INPUT_DEVICE::kKeyboard && keyEvent) {
						SettingsPage::TrackModifiers(*keyEvent);
					}
					const bool isHotkey = event->device == RE::INPUT_DEVICE::kKeyboard && keyEvent &&
					                      keyEvent->GetIDCode() == Core::AppConfig::Get().hotkeyOpenPanel;
					if (isHotkey) {
						// Fase 18 conserto 2 (D203): the event value and the seconds
						// the key has been held, so a frame that is not a key-down
						// says what it is (ButtonEvent::Value / HeldDuration).
						// D209: the keyboard device's own state for this key, to
						// tell an event lost above the sink from a key never down.
						// curState is read through GetRuntimeData() (inline): the
						// out-of-line IsPressed() pulls BSWin32KeyboardDevice.obj
						// into the link, whose virtuals this build does not define.
						auto* manager = RE::BSInputDeviceManager::GetSingleton();
						auto* keyboard = manager ? manager->GetKeyboard() : nullptr;
						const auto code = keyEvent->GetIDCode();
						const char* deviceState = !keyboard ? "no device" :
						                          code >= 0x100 ? "out of range" :
						                          (keyboard->GetRuntimeData().curState[code] & 0x80) ? "yes" : "no";
						spdlog::info("PrismaPanel: hotkey 0x{:X} arrived (down: {}, up: {}, value: {}, held: {:.3f} s, console open: {}, device state pressed: {})",
							keyEvent->GetIDCode(), keyEvent->IsDown(), keyEvent->IsUp(), keyEvent->Value(),
							keyEvent->HeldDuration(), consoleOpen, deviceState);
							spdlog::info("PrismaPanel: hotkey signals - console: {}, scaleform text entry count: {}, "
								"prisma any focus: {}, prisma own focus: {}, smf blocking window: {}, verdict: {}",
								signals.consoleOpen, signals.scaleformTextEntry, signals.prismaAnyFocus,
								signals.prismaOwnFocus, signals.smfBlockingWindow, *textEntry ? textEntry : "pass");
					}
					// Fase 18 conserto 3 (D208): a touch is the release -> pressed
					// transition this sink sees, read before every filter (a
					// release seen only by a filtered branch would leave the key
					// "pressed" and the next touch uncounted). With the SMF
					// loaded the key-down frame never arrives (V050), so the
					// first frame with value > 0 is the touch, key-down or not.
					Core::Settings::KeyTouch touch;
					bool isEscape = false;
					if (event->device == RE::INPUT_DEVICE::kKeyboard && keyEvent) {
						const auto hotkeyCode = Core::AppConfig::Get().hotkeyOpenPanel;
						if (hotkeyCode != g_hotkeyTouchCode) {
							g_hotkeyTouch = {};  // the key was changed: its old state is not the new key's
							g_hotkeyTouchCode = hotkeyCode;
						}
						isEscape = keyEvent->GetIDCode() == RE::BSKeyboardDevice::Keys::kEscape;
						if (isEscape) {
							touch = Core::Settings::ClassifyKeyFrame(g_escapeTouch, keyEvent->Value(),
								keyEvent->HeldDuration(), keyEvent->IsDown());
						} else if (isHotkey) {
							touch = Core::Settings::ClassifyKeyFrame(g_hotkeyTouch, keyEvent->Value(),
								keyEvent->HeldDuration(), keyEvent->IsDown());
						}
					}
					const bool isTouch = touch.edge == Core::Settings::KeyEdge::kTouchKeyDown ||
					                     touch.edge == Core::Settings::KeyEdge::kTouchHeld;
					if (consoleOpen) {
						// Same guard the SMF panel already had (D035): typing in the console
						// must never toggle this panel.
						if (isHotkey && isTouch) {
							spdlog::info("PrismaPanel: hotkey dropped - text entry ({})", textEntry);
						}
						continue;
					}
					if (event->device != RE::INPUT_DEVICE::kKeyboard || !keyEvent) {
						continue;
					}
					// Lancamento 2: Esc closes the panel. The page's own keydown
					// handler never saw the key in game (test 2026-09-14), so the
					// native sink closes it.
					if (isEscape) {
						if (isTouch && g_prismaUI && g_view && !g_prismaUI->IsHidden(g_view)) {
							spdlog::info("PrismaPanel: Esc touch accepted ({}, held {:.3f} s)",
								TouchPath(touch), keyEvent->HeldDuration());
							HidePanel("Esc");
						}
						continue;
					}
					if (!isHotkey) {
						continue;
					}
					if (!isTouch) {
						// One line per press, not one per frame (D208).
						if (touch.edge == Core::Settings::KeyEdge::kRepeat) {
							spdlog::info("PrismaPanel: hotkey dropped - repeat of a press already counted "
										 "(held {:.3f} s)", keyEvent->HeldDuration());
						}
						continue;
					}
					auto* button = keyEvent;
					// Fase 20 (D205): typing somewhere else (a Scaleform field, a
						// Prisma view of another mod, an SMF window) is not a press.
						if (*textEntry) {
							spdlog::info("PrismaPanel: hotkey dropped - text entry ({})", textEntry);
							continue;
						}
						// Fase 19 (D197): the settings page is taking this key as the
					// new hotkey; it is not a press of the old one.
					if (SettingsPage::OwnsKey(button->GetIDCode())) {
						spdlog::info("PrismaPanel: hotkey dropped - the settings page is capturing a key");
						continue;
					}
					// Fase 19 (D196): the configured modifiers must be held; the
					// others do not matter. None configured opens always.
					const auto required = Core::AppConfig::Get().hotkeyModifiers;
					const auto held = SettingsPage::HeldModifiers();
					if (!Core::Settings::ModifiersSatisfied(required, held)) {
						spdlog::info("PrismaPanel: hotkey dropped - needs {} held, held: {}",
							Core::Settings::ModifiersToToml(required), Core::Settings::ModifiersToToml(held));
						continue;
					}
					spdlog::info("PrismaPanel: hotkey 0x{:X} touch accepted ({}, held {:.3f} s{})",
						button->GetIDCode(), TouchPath(touch), button->HeldDuration(),
						touch.releaseLost ? ", the release of the last press was not seen" : "");
					TogglePanel();
				}

				return RE::BSEventNotifyControl::kContinue;
			}
		};

		InputSink g_inputSink;
	}

	void OnDataLoaded()
	{
		g_prismaUI = PRISMA_UI_API::RequestPluginAPI<PRISMA_UI_API::IVPrismaUI1>();
		if (!g_prismaUI) {
			spdlog::warn("PrismaPanel: Prisma UI not installed or interface V1 unavailable - the operator "
						 "panel will not be available this session.");
			return;
		}

		g_initPayload = BuildInitPayload();
		{
			std::lock_guard lock(g_paletteMutex);
			g_palette = Core::Settings::NormalizePalette(Core::AppConfig::Get().palette);
		}

		// "HonestWork-Panel/index.html" resolves against PrismaUI's own view
		// root (confirmed against the real PrismaUI-SKSE/example-skse-plugin
		// main.cpp, which passes just "PrismaUI-Example-UI/index.html" - no
		// "Data/" or plugin-name prefix) - deployed by the prisma-builder
		// skill to Data/PrismaUI/views/HonestWork-Panel/index.html.
		g_view = g_prismaUI->CreateView("HonestWork-Panel/index.html", [](PrismaView a_view) {
			if (g_prismaUI) {
				// Fase 33 etapa 8 (C1): the page keeps what arrives before it listens, but
				// nothing said the Invoke happened; this line is the evidence.
				g_prismaUI->Invoke(a_view, ("window.hwInit(" + g_initPayload + ")").c_str());
				spdlog::info("PrismaPanel: window.hwInit invoked on DOM ready ({} bytes of payload)", g_initPayload.size());
				// D198: every page load starts on the palette the config says.
				SendPalette(a_view, CurrentPalette(), "page loaded");
			}
		});

		g_prismaUI->RegisterJSListener(g_view, "hwIssueContract", &OnIssueContract);
		g_prismaUI->RegisterJSListener(g_view, "hwIssueOccupied", &OnIssueOccupied);
		g_prismaUI->RegisterJSListener(g_view, "hwCure", &OnCure);
		g_prismaUI->RegisterJSListener(g_view, "hwFire", &OnFire);
		g_prismaUI->RegisterJSListener(g_view, "hwPickUp", &OnPickUp);
		g_prismaUI->RegisterJSListener(g_view, "hwClosePanel", &OnClosePanel);
		g_prismaUI->RegisterJSListener(g_view, "hwHireCandidate", &OnHireCandidate);
		g_prismaUI->RegisterJSListener(g_view, "hwHireFollower", &OnHireFollower);
		g_prismaUI->RegisterJSListener(g_view, "hwAssignGuard", &OnAssignGuard);
		g_prismaUI->RegisterJSListener(g_view, "hwThemeApplied", &OnThemeApplied);
		g_prismaUI->RegisterJSListener(g_view, "hwNote", &OnPanelNote);

		// Starts hidden - same "closed until the hotkey opens it" UX the SMF
		// panel had, just implemented via Prisma's Show/Hide instead of a
		// framework-owned IsOpen flag.
		g_prismaUI->Hide(g_view);

		// // ASSUMPTION (): registering against
		// RE::BSInputDeviceManager from the kDataLoaded handler, not
		// kInputLoaded - BSInputDeviceManager is a device-level singleton
		// with no dependency on save/world data, and this project already
		// has a working, tested kDataLoaded entry point (this same
		// function) - no header comment confirms kInputLoaded is required instead.
		RE::BSInputDeviceManager::GetSingleton()->AddEventSink(&g_inputSink);

		spdlog::info("PrismaPanel: panel registered (hotkey {} = scan code {:#04x}, modifiers {}, from config).",
			Core::Settings::FormatHotkey(Core::AppConfig::Get().hotkeyOpenPanel, Core::AppConfig::Get().hotkeyModifiers),
			Core::AppConfig::Get().hotkeyOpenPanel, Core::Settings::ModifiersToToml(Core::AppConfig::Get().hotkeyModifiers));
	}

	void SetPalette(const std::string& a_palette)
	{
		const auto palette = Core::Settings::NormalizePalette(a_palette);
		{
			std::lock_guard lock(g_paletteMutex);
			g_palette = palette;
		}
		SKSE::GetTaskInterface()->AddTask([palette]() {
			if (!g_prismaUI || !g_view) {
				spdlog::info("PrismaPanel: palette '{}' kept for the next page load (no view)", palette);
				return;
			}
			SendPalette(g_view, palette, "settings page");
		});
	}

	bool RegisterNatives()
	{
		const auto* papyrus = SKSE::GetPapyrusInterface();
		return papyrus && papyrus->Register(RegisterFuncs);
	}
}
