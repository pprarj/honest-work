// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

// WorkerNatives.cpp
// Honest Work - Workers of Skyrim

#include "WorkerNatives.h"

#include <mutex>
#include <unordered_set>

namespace HonestWork::Core::WorkerNatives
{
	namespace
	{
		constexpr auto kScriptClass = "WOSK_Native";

		// Mod event the worker alias registers for (WOSK_WorkerAliasScript):
		// sender = the bandit that died, strArg = killer FormID in decimal
		// ("0" when the kill has no killer), numArg unused.
		constexpr auto kKilledEvent = "WOSK_EncounterThreatKilled";

		std::mutex                         g_lock;
		std::unordered_set<std::uint32_t>  g_watched;  // FormIDs of the road-encounter bandits

		// Same job as PO3_SKSEFunctions.SetLinkedRef(akRef, akTarget, akKeyword).
		// ExtraDataList::SetLinkedRef is the engine's own routine (ExtraDataList.h:219,
		// ExtraDataList.cpp:370-375, RELOCATION_ID(11633, 11779)) - it creates or
		// updates the ExtraLinkedRef entry for the keyword. A None target is passed
		// through as the engine's "clear" case. A None keyword is the engine's
		// default link and is allowed.
		void SetLinkedRef(RE::StaticFunctionTag*, RE::TESObjectREFR* a_ref,
			RE::TESObjectREFR* a_target, RE::BGSKeyword* a_keyword)
		{
			if (!a_ref) {
				spdlog::warn("WOSK_Native.SetLinkedRef: ref is None - nothing done.");
				return;
			}
			a_ref->extraList.SetLinkedRef(a_target, a_keyword);
		}

		void WatchEncounterThreat(RE::StaticFunctionTag*, RE::Actor* a_threat)
		{
			if (!a_threat) {
				return;
			}
			std::size_t size = 0;
			{
				std::scoped_lock lock(g_lock);
				g_watched.insert(a_threat->GetFormID());
				size = g_watched.size();
			}
			spdlog::info("WorkerNatives: watching encounter bandit {:08X} (watched now: {}).",
				a_threat->GetFormID(), size);
		}

		void UnwatchEncounterThreat(RE::StaticFunctionTag*, RE::Actor* a_threat)
		{
			if (!a_threat) {
				return;
			}
			std::size_t erased = 0;
			std::size_t size = 0;
			{
				std::scoped_lock lock(g_lock);
				erased = g_watched.erase(a_threat->GetFormID());
				size = g_watched.size();
			}
			spdlog::info("WorkerNatives: unwatched encounter bandit {:08X} (was watched: {}, watched now: {}).",
				a_threat->GetFormID(), erased != 0 ? "yes" : "no", size);
		}

		bool RegisterFuncs(RE::BSScript::IVirtualMachine* a_vm)
		{
			if (!a_vm) {
				return false;
			}
			a_vm->RegisterFunction("SetLinkedRef", kScriptClass, SetLinkedRef);
			a_vm->RegisterFunction("WatchEncounterThreat", kScriptClass, WatchEncounterThreat);
			a_vm->RegisterFunction("UnwatchEncounterThreat", kScriptClass, UnwatchEncounterThreat);
			spdlog::info("WorkerNatives: {} bound (SetLinkedRef, WatchEncounterThreat, UnwatchEncounterThreat).",
				kScriptClass);
			return true;
		}


		// One death, one event. Whoever hears the death first (either source
		// below) takes the id out of the watched set under the lock; the second
		// hearing finds nothing and returns. Only a watched bandit produces
		// anything - no log, no event for any other death in the game.
		//
		// Why two sources (D219): the TESDeathEvent sink used to act only on
		// dead == true, and the hw-22 probe (bandit AI off by EnableAI(false),
		// Kill() ~7 s after it was created) heard nothing. Whether that event
		// never came or came with dead == false is not known; the header does not
		// say. ActorKill is the source other mods' OnActorKilled hear the same
		// kill from, so it is the second way in.
		void Deliver(RE::TESObjectREFR* a_victim, std::uint32_t a_killerId, bool a_dead, const char* a_source)
		{
			const auto victimId = a_victim->GetFormID();
			bool       watched = false;
			{
				std::scoped_lock lock(g_lock);
				watched = g_watched.erase(victimId) != 0;
			}
			if (!watched) {
				return;
			}
			spdlog::info("WorkerNatives: encounter bandit {:08X} died (killer {:08X}, source {}, dead={}) - sending {}.",
				victimId, a_killerId, a_source, a_dead, kKilledEvent);
			auto* source = SKSE::GetModCallbackEventSource();
			if (!source) {
				spdlog::error("WorkerNatives: no mod event source - the worker will not hear of the death.");
				return;
			}
			SKSE::ModCallbackEvent modEvent{
				RE::BSFixedString(kKilledEvent),
				RE::BSFixedString(std::to_string(a_killerId).c_str()),
				0.0f,
				a_victim
			};
			source->SendEvent(&modEvent);
		}

		bool IsWatched(std::uint32_t a_id)
		{
			std::scoped_lock lock(g_lock);
			return g_watched.contains(a_id);
		}

		class DeathSink final : public RE::BSTEventSink<RE::TESDeathEvent>
		{
		public:
			RE::BSEventNotifyControl ProcessEvent(const RE::TESDeathEvent* a_event,
				RE::BSTEventSource<RE::TESDeathEvent>*) override
			{
				if (!a_event || !a_event->actorDying) {
					return RE::BSEventNotifyControl::kContinue;
				}
				RE::TESObjectREFR* victim = a_event->actorDying.get();
				const auto         killerId = a_event->actorKiller ? a_event->actorKiller->GetFormID() : 0u;
				if (IsWatched(victim->GetFormID())) {
					// Logged before any filter: the value of dead is what the hw-22
					// probe could not tell.
					spdlog::info("WorkerNatives: death event for watched bandit {:08X}: dead={} killer {:08X}.",
						victim->GetFormID(), a_event->dead, killerId);
					Deliver(victim, killerId, a_event->dead, "TESDeathEvent");
				}
				return RE::BSEventNotifyControl::kContinue;
			}
		};

		class KillSink final : public RE::BSTEventSink<RE::ActorKill::Event>
		{
		public:
			RE::BSEventNotifyControl ProcessEvent(const RE::ActorKill::Event* a_event,
				RE::BSTEventSource<RE::ActorKill::Event>*) override
			{
				if (!a_event || !a_event->victim) {
					return RE::BSEventNotifyControl::kContinue;
				}
				RE::Actor* victim = a_event->victim;
				const auto killerId = a_event->killer ? a_event->killer->GetFormID() : 0u;
				if (IsWatched(victim->GetFormID())) {
					spdlog::info("WorkerNatives: kill event for watched bandit {:08X}: killer {:08X}.",
						victim->GetFormID(), killerId);
					Deliver(victim, killerId, true, "ActorKill");
				}
				return RE::BSEventNotifyControl::kContinue;
			}
		};

		DeathSink g_sink;
		KillSink  g_killSink;
	}

	bool Register()
	{
		const auto* papyrus = SKSE::GetPapyrusInterface();
		return papyrus && papyrus->Register(RegisterFuncs);
	}

	void OnDataLoaded()
	{
		auto* holder = RE::ScriptEventSourceHolder::GetSingleton();
		if (!holder) {
			spdlog::error("WorkerNatives: no script event source - the encounter bandit's death will not be heard.");
		} else {
			holder->AddEventSink<RE::TESDeathEvent>(&g_sink);
			spdlog::info("WorkerNatives: death sink added.");
		}
		auto* killSource = RE::ActorKill::GetEventSource();
		if (!killSource) {
			spdlog::error("WorkerNatives: no actor kill event source - only the death event will be heard.");
		} else {
			killSource->AddEventSink(&g_killSink);
			spdlog::info("WorkerNatives: kill sink added.");
		}
	}

	void ClearWatched()
	{
		std::scoped_lock lock(g_lock);
		g_watched.clear();
	}
}