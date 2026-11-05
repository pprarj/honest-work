// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

// ProfessionsRegistry.h
// Honest Work - Workers of Skyrim
//
// Directory-scan merge for the two extension points that are data, not
// Papyrus API (D078): profession
// definitions and contract-type outcome tables. Third-party mods (the HWT,
// or anyone else) drop a *.json file into one of the two watched
// directories instead of editing this project's own file - no master
// dependency, no Papyrus required on their side.
//
// Algorithm ported 1:1 from the validated reference,
// the development reference model (merge_directory_entries /
// merge_hold_resources). Only the source_plugin loaded-check (RE::TESDataHandler) has
// no Python equivalent, since it needs the real game data handler.
//
// Papyrus reads the merged registry through the WOSK_Registry natives
// (RegisterNatives below), which match every key ignoring case - not through
// JsonUtil paths, whose lookups are case-sensitive while the Papyrus string
// cache is not (B003, D099).

#pragma once

#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace HonestWork::Core::ProfessionsRegistry
{
	// Scans Data/SKSE/Plugins/HonestWork/professions/*.json and
	// Data/SKSE/Plugins/HonestWork/contract_types/*.json (ascending
	// filename order), merges each, writes the result for anyone who wants
	// to read it:
	//   Data/SKSE/Plugins/HonestWork/professions_merged.json
	//   Data/SKSE/Plugins/HonestWork/contract_types_merged.json
	// and keeps a key-lowercased copy in memory for the natives.
	// Call once, from the kDataLoaded SKSE message handler (RE::TESDataHandler
	// must be fully populated - confirmed safe there by commonlib-scout
	// against real-world usage, D078).
	// Never throws; a missing directory, an empty directory, or a malformed
	// individual file is logged and does not stop the rest of the plugin
	//.
	void MergeAll();

	// Binds the WOSK_Registry global natives (Scripts/Source/WOSK_Registry.psc).
	// Call from SKSEPluginLoad. Returns false if SKSE refused the request.
	bool RegisterNatives();

	// V006 (D103): a task's price per unit, the way the
	// worker script charges it - the mean of each output form's gold value in
	// game, weighted by the output weight. Outputs whose form does not resolve
	// are left out; 0 when none resolves. Call after MergeAll, on the main thread.
	float TaskUnitPrice(std::string_view a_profession, std::string_view a_taskId);

	// Fase 15 (D159): what the ingredients of one unit of output cost in game,
	// sum of count x gold value. 0 for a task without ingredients; -1 when an
	// ingredient does not resolve (the contract is refused). Main thread.
	float TaskIngredientCost(std::string_view a_profession, std::string_view a_taskId);

	// D105: how many sources of a resource type the hold has
	// (Data/SKSE/Plugins/HonestWork/hold_sources/*.json), hold and type matched
	// ignoring case; 0 for an unknown hold or type. Call after MergeAll.
	std::int32_t CountHoldSources(std::string_view a_hold, std::string_view a_resourceType);

	// The task's resourceType, or an empty string when the task is unknown.
	std::string TaskResourceType(std::string_view a_profession, std::string_view a_taskId);

	// Fase 15: every task of every profession, in the registry's order
	// (profession ids sorted, tasks in JSON order), for the panel's task list.
	// Ids come back lowercased (the in-memory copy); label falls back to the id.
	struct TaskSummary
	{
		std::string profession;
		std::string id;
		std::string label;
		std::string minTier;
		std::string resourceType;
		float hours = 0.0f;
		float batchMin = 0.0f;
		float batchMax = 0.0f;
		float incidentChance = 0.0f;
		// Fase 33 etapa 10 (F1): the multiplier the charge applies on top of the reference
		// price, so the panel can show the cost of a contract before it is issued.
		float priceMultiplier = 1.0f;
	};
	std::vector<TaskSummary> ListTasks();

	// Fase 17 (D168): every tier of every profession, for the panel's tier
	// ladder - the profession ids sorted, the tiers in rank order (apprentice,
	// worker, veteran, master; a tier the JSON does not have is skipped).
	struct TierSummary
	{
		std::string profession;
		std::string id;
		std::int32_t minContracts = 0;
		// Fase 26: what the tier does to a contract, so the panel shows the
		// hours and the batch range a worker of this tier really gets.
		float durationMultiplier = 1.0f;
		float yieldMultiplier = 1.0f;
	};
	std::vector<TierSummary> ListTiers();
}
