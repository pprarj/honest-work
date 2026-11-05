// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

// ProfessionsRegistry.cpp
// Honest Work - Workers of Skyrim

#include "ProfessionsRegistry.h"

#include "AppConfig.h"
#include "DishPrice.h"

#include <nlohmann/json.hpp>

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <shared_mutex>
#include <string>
#include <string_view>
#include <vector>

namespace HonestWork::Core::ProfessionsRegistry
{
	namespace
	{
		namespace fs = std::filesystem;
		using json = nlohmann::json;

		// RE::TESDataHandler::GetSingleton (TESDataHandler.h:46),
		// LookupLoadedModByName (TESDataHandler.h:74, full/master plugins),
		// LookupLoadedLightModByName (TESDataHandler.h:78, ESL-flagged
		// plugins) - all three confirmed by commonlib-scout this session
		// against the real vendored headers. Neither Lookup* function alone
		// covers both plugin classes, and a third-party source_plugin
		// filename could be either - same composition, called from
		// the kDataLoaded handler.
		bool IsPluginLoaded(const std::string& a_pluginName)
		{
			auto* dataHandler = RE::TESDataHandler::GetSingleton();
			if (!dataHandler) {
				return false;
			}
			return dataHandler->LookupLoadedModByName(a_pluginName) != nullptr ||
			       dataHandler->LookupLoadedLightModByName(a_pluginName) != nullptr;
		}

		// Ascending filename order, non-recursive, *.json only. An absent
		// directory returns an empty list, not an error - shipping no
		// extension file at all is the common case for a fresh install.
		std::vector<fs::path> SortedJsonFiles(const fs::path& a_dir)
		{
			std::vector<fs::path> files;
			std::error_code ec;
			if (!fs::exists(a_dir, ec) || !fs::is_directory(a_dir, ec)) {
				return files;
			}
			for (const auto& entry : fs::directory_iterator(a_dir, ec)) {
				if (entry.is_regular_file() && entry.path().extension() == ".json") {
					files.push_back(entry.path());
				}
			}
			std::sort(files.begin(), files.end(), [](const fs::path& a, const fs::path& b) {
				return a.filename().string() < b.filename().string();
			});
			return files;
		}

		// Direct port of the development reference model
		// (validated there first, 16 cases, before this port). a_topLevelKey is "professions" or "contractTypes".
		json MergeEntries(const std::vector<fs::path>& a_files, const char* a_topLevelKey)
		{
			json merged = json::object();

			for (const auto& filePath : a_files) {
				const std::string fileName = filePath.filename().string();

				std::ifstream stream(filePath);
				if (!stream) {
					spdlog::error("ProfessionsRegistry: {}: could not open file, skipped", fileName);
					continue;
				}

				json parsed;
				try {
					stream >> parsed;
				} catch (const json::parse_error& e) {
					spdlog::error("ProfessionsRegistry: {}: JSON parse failed ({}), file skipped",
						fileName, e.what());
					continue;
				}

				if (!parsed.is_object()) {
					spdlog::error(
						"ProfessionsRegistry: {}: top-level value is not an object, file skipped", fileName);
					continue;
				}

				auto blockMapIt = parsed.find(a_topLevelKey);
				if (blockMapIt == parsed.end() || !blockMapIt->is_object()) {
					spdlog::error("ProfessionsRegistry: {}: missing or non-object '{}' key, file skipped",
						fileName, a_topLevelKey);
					continue;
				}

				for (auto& [entryId, block] : blockMapIt->items()) {
					if (!block.is_object()) {
						spdlog::error("ProfessionsRegistry: {}: {}.{} is not an object, entry skipped",
							fileName, a_topLevelKey, entryId);
						continue;
					}

					auto sourcePluginIt = block.find("source_plugin");
					if (sourcePluginIt != block.end() && sourcePluginIt->is_string()) {
						const std::string sourcePlugin = sourcePluginIt->get<std::string>();
						if (!sourcePlugin.empty() && !IsPluginLoaded(sourcePlugin)) {
							spdlog::info(
								"ProfessionsRegistry: {}: {} '{}' skipped, source_plugin '{}' not loaded",
								fileName, a_topLevelKey, entryId, sourcePlugin);
							continue;
						}
					}

					if (merged.contains(entryId)) {
						spdlog::info(
							"ProfessionsRegistry: {}: {} '{}' overrides an earlier definition (collision)",
							fileName, a_topLevelKey, entryId);
					}
					merged[entryId] = block;
				}
			}

			return merged;
		}

		// Fase 15: the closed schema of one source, by kind - the same rule as
		// the development reference model. A vein kind
		// (safeMine, dungeonMine, openAir) keeps its veins; a zone has no vein
		// and holds a simulated stock instead: "capacity" units of output that
		// come back "recoveryDays" game days after the last contract touched it.
		// Returns an empty string when the block is valid, else the reason.
		std::string SourceSchemaError(const json& a_block)
		{
			const auto kindIt = a_block.find("kind");
			if (kindIt == a_block.end() || !kindIt->is_string()) {
				return "missing or non-string 'kind'";
			}
			const std::string kind = kindIt->get<std::string>();
			const bool isZone = kind == "zone";
			if (!isZone && kind != "safeMine" && kind != "dungeonMine" && kind != "openAir") {
				return "unknown kind '" + kind + "'";
			}
			for (const auto& [key, value] : a_block.items()) {
				const bool common = key == "kind" || key == "destination" || key == "resourceTypes" ||
				                    key == "source_plugin" || key == "location";
				const bool own = isZone ? (key == "capacity" || key == "recoveryDays") : key == "veins";
				if (!common && !own) {
					return "key '" + key + "' is not allowed for kind '" + kind + "'";
				}
			}
			const auto destination = a_block.find("destination");
			if (destination == a_block.end() || !destination->is_string()) {
				return "missing or non-string 'destination'";
			}
			const auto types = a_block.find("resourceTypes");
			if (types == a_block.end() || !types->is_array() || types->empty()) {
				return "missing or empty 'resourceTypes'";
			}
			if (isZone) {
				const auto capacity = a_block.find("capacity");
				if (capacity == a_block.end() || !capacity->is_number_integer() || capacity->get<int>() < 1) {
					return "zone needs an integer 'capacity' of at least 1";
				}
				const auto recovery = a_block.find("recoveryDays");
				if (recovery == a_block.end() || !recovery->is_number() || recovery->get<double>() <= 0.0) {
					return "zone needs a 'recoveryDays' above 0";
				}
			} else if (!a_block.contains("veins") || !a_block["veins"].is_object()) {
				return "missing or non-object 'veins'";
			}
			return {};
		}

		// D105: direct port of the development reference model.
		// hold -> {source id -> block}; per hold, a later file's block for the
		// same id replaces the earlier one and the other ids survive; a block
		// whose source_plugin is not loaded is dropped.
		json MergeHoldSources(const std::vector<fs::path>& a_files)
		{
			json merged = json::object();

			for (const auto& filePath : a_files) {
				const std::string fileName = filePath.filename().string();

				std::ifstream stream(filePath);
				if (!stream) {
					spdlog::error("ProfessionsRegistry: {}: could not open file, skipped", fileName);
					continue;
				}
				json parsed;
				try {
					stream >> parsed;
				} catch (const json::parse_error& e) {
					spdlog::error("ProfessionsRegistry: {}: JSON parse failed ({}), file skipped", fileName, e.what());
					continue;
				}
				if (!parsed.is_object() || !parsed.contains("holdSources") || !parsed["holdSources"].is_object()) {
					spdlog::error("ProfessionsRegistry: {}: missing or non-object 'holdSources' key, file skipped",
						fileName);
					continue;
				}
				// D105 etapa 3: schemaVersion 2 keys veins by resource type. A
				// version 1 file (flat veins list) would read as a source with no
				// vein of any type, so it is refused out loud instead.
				if (!parsed.contains("schemaVersion") || !parsed["schemaVersion"].is_number_integer() ||
					parsed["schemaVersion"].get<int>() != 2) {
					spdlog::error("ProfessionsRegistry: {}: hold sources schemaVersion must be 2 (veins keyed by "
								  "resource type), file skipped",
						fileName);
					continue;
				}

				for (auto& [hold, sources] : parsed["holdSources"].items()) {
					if (!sources.is_object()) {
						spdlog::error("ProfessionsRegistry: {}: holdSources.{} is not an object, hold skipped",
							fileName, hold);
						continue;
					}
					json& mergedHold = merged[hold];
					if (!mergedHold.is_object()) {
						mergedHold = json::object();
					}
					for (auto& [sourceId, block] : sources.items()) {
						if (!block.is_object()) {
							spdlog::error("ProfessionsRegistry: {}: holdSources.{}.{} is not an object, source skipped",
								fileName, hold, sourceId);
							continue;
						}
						auto sourcePluginIt = block.find("source_plugin");
						if (sourcePluginIt != block.end() && sourcePluginIt->is_string()) {
							const std::string sourcePlugin = sourcePluginIt->get<std::string>();
							if (!sourcePlugin.empty() && !IsPluginLoaded(sourcePlugin)) {
								spdlog::info(
									"ProfessionsRegistry: {}: holdSources.{} '{}' skipped, source_plugin '{}' not loaded",
									fileName, hold, sourceId, sourcePlugin);
								continue;
							}
						}
						if (const auto schemaError = SourceSchemaError(block); !schemaError.empty()) {
							spdlog::error("ProfessionsRegistry: {}: holdSources.{}.{}: {}, source skipped", fileName,
								hold, sourceId, schemaError);
							continue;
						}
						if (mergedHold.contains(sourceId)) {
							spdlog::info(
								"ProfessionsRegistry: {}: holdSources.{} '{}' overrides an earlier definition (collision)",
								fileName, hold, sourceId);
						}
						mergedHold[sourceId] = block;
					}
				}
			}

			return merged;
		}

		void WriteMergedFile(const fs::path& a_outputPath, const json& a_content)
		{
			std::error_code ec;
			fs::create_directories(a_outputPath.parent_path(), ec);

			std::ofstream out(a_outputPath, std::ios::trunc);
			if (!out) {
				spdlog::error("ProfessionsRegistry: could not open '{}' for writing", a_outputPath.string());
				return;
			}
			out << a_content.dump(2);
		}

		// --- In-memory registry for Papyrus (B003, D099) ---
		//
		// The Papyrus VM keeps one string per case-insensitive spelling, so an
		// id or field name written "miner" in a script can reach a native as
		// "Miner". JsonUtil's Path lookups are case-sensitive (measured, harness
		// v3 CAC-SONDA), which made the worker script read 0 for batch, price and
		// minContracts. These copies have every object key lowercased at every
		// depth, and every lookup lowercases its input - the case of what
		// arrives from Papyrus stops mattering. Values keep their case.
		//
		// Written once per MergeAll (kDataLoaded), read by the natives below.
		// The shared lock makes the reads safe whatever thread the VM calls a
		// native from.

		constexpr auto kScriptClass = "WOSK_Registry";

		std::shared_mutex g_registryLock;
		json g_professions = json::object();
		json g_contractTypes = json::object();
		json g_holdSources = json::object();  // D105
		json g_candidatePools = json::object();  // D161

		std::string ToLower(std::string_view a_text)
		{
			std::string out(a_text);
			for (auto& c : out) {
				c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
			}
			return out;
		}

		json LowercaseKeys(const json& a_value, const std::string& a_where)
		{
			if (a_value.is_object()) {
				json out = json::object();
				for (const auto& [key, child] : a_value.items()) {
					std::string lower = ToLower(key);
					if (out.contains(lower)) {
						spdlog::warn(
							"ProfessionsRegistry: '{}' has keys that differ only in case ('{}') - "
							"the last one in key order wins",
							a_where, key);
					}
					out[lower] = LowercaseKeys(child, a_where + "." + key);
				}
				return out;
			}
			if (a_value.is_array()) {
				json out = json::array();
				for (std::size_t i = 0; i < a_value.size(); ++i) {
					out.push_back(LowercaseKeys(a_value[i], a_where + "[" + std::to_string(i) + "]"));
				}
				return out;
			}
			return a_value;
		}

		std::string_view View(const RE::BSFixedString& a_text)
		{
			const char* text = a_text.c_str();
			return text ? std::string_view(text) : std::string_view();
		}

		// Caller holds g_registryLock (shared). Every helper tolerates a null
		// parent, so a missing profession/task/tier just yields nullptr.
		const json* Child(const json* a_parent, std::string_view a_key)
		{
			if (!a_parent || !a_parent->is_object()) {
				return nullptr;
			}
			auto it = a_parent->find(ToLower(a_key));
			return it != a_parent->end() ? &*it : nullptr;
		}

		const json* Element(const json* a_array, std::int32_t a_index)
		{
			if (!a_array || !a_array->is_array() || a_index < 0 ||
				static_cast<std::size_t>(a_index) >= a_array->size()) {
				return nullptr;
			}
			return &(*a_array)[static_cast<std::size_t>(a_index)];
		}

		const json* Task(std::string_view a_profession, std::int32_t a_taskIndex)
		{
			return Element(Child(Child(&g_professions, a_profession), "tasks"), a_taskIndex);
		}

		const json* Tier(std::string_view a_profession, std::string_view a_tier)
		{
			return Child(Child(Child(&g_professions, a_profession), "tiers"), a_tier);
		}

		const json* OutcomeRows(std::string_view a_contractType)
		{
			return Child(Child(&g_contractTypes, a_contractType), "outcomeTable");
		}

		// Same rule as the Papyrus "==" FindTaskIndex replaced: ids compare
		// ignoring case. -1 when the profession or the task is missing.
		std::int32_t TaskIndexById(std::string_view a_profession, std::string_view a_taskId)
		{
			const json* tasks = Child(Child(&g_professions, a_profession), "tasks");
			if (!tasks || !tasks->is_array()) {
				return -1;
			}
			const std::string wanted = ToLower(a_taskId);
			for (std::size_t i = 0; i < tasks->size(); ++i) {
				const json* id = Child(&(*tasks)[i], "id");
				if (id && id->is_string() && ToLower(id->get<std::string>()) == wanted) {
					return static_cast<std::int32_t>(i);
				}
			}
			return -1;
		}

		// "Plugin.esp|0x00071CF3", the format the worker script's _ResolveFormRef
		// reads. LookupForm takes the id local to the plugin and adds the load
		// order index itself, full and light plugins alike (TESDataHandler.h:62,
		// TESDataHandler.cpp:113-141).
		RE::TESForm* ResolveFormRef(const std::string& a_ref)
		{
			auto* dataHandler = RE::TESDataHandler::GetSingleton();
			const auto bar = a_ref.find('|');
			if (!dataHandler || bar == std::string::npos) {
				return nullptr;
			}
			const char* hex = a_ref.c_str() + bar + 1;
			char* end = nullptr;
			const unsigned long localId = std::strtoul(hex, &end, 16);
			if (end == hex || *end != '\0') {
				return nullptr;
			}
			return dataHandler->LookupForm(static_cast<RE::FormID>(localId), std::string_view(a_ref).substr(0, bar));
		}

		float AsFloat(const json* a_value, float a_default)
		{
			return a_value && a_value->is_number() ? a_value->get<float>() : a_default;
		}

		std::int32_t AsInt(const json* a_value, std::int32_t a_default)
		{
			if (!a_value || !a_value->is_number()) {
				return a_default;
			}
			if (a_value->is_number_integer()) {
				return static_cast<std::int32_t>(a_value->get<std::int64_t>());
			}
			return static_cast<std::int32_t>(a_value->get<double>());  // truncates toward zero
		}

		RE::BSFixedString AsString(const json* a_value, const RE::BSFixedString& a_default)
		{
			return a_value && a_value->is_string() ? RE::BSFixedString(a_value->get<std::string>()) : a_default;
		}

		std::int32_t CountArray(const json* a_array)
		{
			return a_array && a_array->is_array() ? static_cast<std::int32_t>(a_array->size()) : 0;
		}

		// D105. Whether the source's resourceTypes contain a_wanted (already
		// lowercased), ignoring case. D105 etapa 3: an empty a_wanted matches every
		// source, so the player's visits can walk all the sources of a hold.
		bool SourceHasType(const json& a_source, const std::string& a_wanted)
		{
			if (a_wanted.empty()) {
				return true;
			}
			const json* types = Child(&a_source, "resourceTypes");
			if (!types || !types->is_array()) {
				return false;
			}
			for (const auto& type : *types) {
				if (type.is_string() && ToLower(type.get<std::string>()) == a_wanted) {
					return true;
				}
			}
			return false;
		}

		// D105. Caller holds g_registryLock (shared). Sources of the hold whose
		// resourceTypes contain a_resourceType, both matched ignoring case; every
		// source of the hold when a_resourceType is empty.
		std::int32_t CountSourcesLocked(std::string_view a_hold, std::string_view a_resourceType)
		{
			const json* sources = Child(&g_holdSources, a_hold);
			if (!sources || !sources->is_object()) {
				return 0;
			}
			const std::string wanted = ToLower(a_resourceType);
			std::int32_t count = 0;
			for (const auto& [sourceId, source] : sources->items()) {
				if (SourceHasType(source, wanted)) {
					++count;
				}
			}
			return count;
		}

		// D105 etapa 2. Caller holds g_registryLock (shared). The id of the
		// a_index-th source of the hold whose resourceTypes contain
		// a_resourceType (any source when it is empty), in the registry's key
		// order (lowercased ids, sorted), or empty when there is no such source.
		std::string SourceIdLocked(std::string_view a_hold, std::string_view a_resourceType, std::int32_t a_index)
		{
			const json* sources = Child(&g_holdSources, a_hold);
			if (!sources || !sources->is_object() || a_index < 0) {
				return {};
			}
			const std::string wanted = ToLower(a_resourceType);
			std::int32_t seen = 0;
			for (const auto& [sourceId, source] : sources->items()) {
				if (!SourceHasType(source, wanted)) {
					continue;
				}
				if (seen == a_index) {
					return sourceId;
				}
				++seen;
			}
			return {};
		}

		// Global natives: RE::StaticFunctionTag* first (TypeTraits.h:9);
		// BSFixedString/int32/float as parameter and return (PackUnpack.h
		// 95-145 and 198-251, v6.7.1, commonlib-scout 2026-09-13).

		std::int32_t FindTaskIndex(RE::StaticFunctionTag*, RE::BSFixedString a_profession, RE::BSFixedString a_taskId)
		{
			std::shared_lock lock(g_registryLock);
			return TaskIndexById(View(a_profession), View(a_taskId));
		}

		float GetTaskFloat(RE::StaticFunctionTag*, RE::BSFixedString a_profession, std::int32_t a_taskIndex,
			RE::BSFixedString a_field, float a_default)
		{
			std::shared_lock lock(g_registryLock);
			return AsFloat(Child(Task(View(a_profession), a_taskIndex), View(a_field)), a_default);
		}

		RE::BSFixedString GetTaskString(RE::StaticFunctionTag*, RE::BSFixedString a_profession,
			std::int32_t a_taskIndex, RE::BSFixedString a_field, RE::BSFixedString a_default)
		{
			std::shared_lock lock(g_registryLock);
			return AsString(Child(Task(View(a_profession), a_taskIndex), View(a_field)), a_default);
		}

		float GetTierFloat(RE::StaticFunctionTag*, RE::BSFixedString a_profession, RE::BSFixedString a_tier,
			RE::BSFixedString a_field, float a_default)
		{
			std::shared_lock lock(g_registryLock);
			return AsFloat(Child(Tier(View(a_profession), View(a_tier)), View(a_field)), a_default);
		}

		std::int32_t GetTierInt(RE::StaticFunctionTag*, RE::BSFixedString a_profession, RE::BSFixedString a_tier,
			RE::BSFixedString a_field, std::int32_t a_default)
		{
			std::shared_lock lock(g_registryLock);
			return AsInt(Child(Tier(View(a_profession), View(a_tier)), View(a_field)), a_default);
		}

		std::int32_t CountTaskOutputs(RE::StaticFunctionTag*, RE::BSFixedString a_profession, std::int32_t a_taskIndex)
		{
			std::shared_lock lock(g_registryLock);
			return CountArray(Child(Task(View(a_profession), a_taskIndex), "outputs"));
		}

		float GetTaskOutputFloat(RE::StaticFunctionTag*, RE::BSFixedString a_profession, std::int32_t a_taskIndex,
			std::int32_t a_outputIndex, RE::BSFixedString a_field, float a_default)
		{
			std::shared_lock lock(g_registryLock);
			const json* output = Element(Child(Task(View(a_profession), a_taskIndex), "outputs"), a_outputIndex);
			return AsFloat(Child(output, View(a_field)), a_default);
		}

		RE::BSFixedString GetTaskOutputString(RE::StaticFunctionTag*, RE::BSFixedString a_profession,
			std::int32_t a_taskIndex, std::int32_t a_outputIndex, RE::BSFixedString a_field,
			RE::BSFixedString a_default)
		{
			std::shared_lock lock(g_registryLock);
			const json* output = Element(Child(Task(View(a_profession), a_taskIndex), "outputs"), a_outputIndex);
			return AsString(Child(output, View(a_field)), a_default);
		}

		// Fase 15 (D159): the cook's ingredients, [{form, count}] per unit of
		// output - the same shape of access as the outputs above.
		std::int32_t CountTaskIngredients(RE::StaticFunctionTag*, RE::BSFixedString a_profession, std::int32_t a_taskIndex)
		{
			std::shared_lock lock(g_registryLock);
			return CountArray(Child(Task(View(a_profession), a_taskIndex), "ingredients"));
		}

		float GetTaskIngredientFloat(RE::StaticFunctionTag*, RE::BSFixedString a_profession, std::int32_t a_taskIndex,
			std::int32_t a_ingredientIndex, RE::BSFixedString a_field, float a_default)
		{
			std::shared_lock lock(g_registryLock);
			const json* ingredient =
				Element(Child(Task(View(a_profession), a_taskIndex), "ingredients"), a_ingredientIndex);
			return AsFloat(Child(ingredient, View(a_field)), a_default);
		}

		RE::BSFixedString GetTaskIngredientString(RE::StaticFunctionTag*, RE::BSFixedString a_profession,
			std::int32_t a_taskIndex, std::int32_t a_ingredientIndex, RE::BSFixedString a_field,
			RE::BSFixedString a_default)
		{
			std::shared_lock lock(g_registryLock);
			const json* ingredient =
				Element(Child(Task(View(a_profession), a_taskIndex), "ingredients"), a_ingredientIndex);
			return AsString(Child(ingredient, View(a_field)), a_default);
		}

		std::int32_t CountOutcomeRows(RE::StaticFunctionTag*, RE::BSFixedString a_contractType)
		{
			std::shared_lock lock(g_registryLock);
			return CountArray(OutcomeRows(View(a_contractType)));
		}

		float GetOutcomeRowFloat(RE::StaticFunctionTag*, RE::BSFixedString a_contractType, std::int32_t a_row,
			RE::BSFixedString a_field, float a_default)
		{
			std::shared_lock lock(g_registryLock);
			return AsFloat(Child(Element(OutcomeRows(View(a_contractType)), a_row), View(a_field)), a_default);
		}

		RE::BSFixedString GetOutcomeRowString(RE::StaticFunctionTag*, RE::BSFixedString a_contractType,
			std::int32_t a_row, RE::BSFixedString a_field, RE::BSFixedString a_default)
		{
			std::shared_lock lock(g_registryLock);
			return AsString(Child(Element(OutcomeRows(View(a_contractType)), a_row), View(a_field)), a_default);
		}

		// D104 etapa 2b: the candidate roll picks a profession among these. Ids
		// come back lowercased (the in-memory copy), in the registry's key order.
		std::int32_t CountProfessions(RE::StaticFunctionTag*)
		{
			std::shared_lock lock(g_registryLock);
			return g_professions.is_object() ? static_cast<std::int32_t>(g_professions.size()) : 0;
		}

		RE::BSFixedString GetProfessionId(RE::StaticFunctionTag*, std::int32_t a_index, RE::BSFixedString a_default)
		{
			std::shared_lock lock(g_registryLock);
			if (!g_professions.is_object() || a_index < 0 ||
				static_cast<std::size_t>(a_index) >= g_professions.size()) {
				return a_default;
			}
			auto it = g_professions.begin();
			std::advance(it, a_index);
			return RE::BSFixedString(it.key());
		}

		// D105: a contract is issued only where the hold has a source of the
		// task's resource type. 0 for an unknown hold or type.
		std::int32_t CountHoldSourcesNative(RE::StaticFunctionTag*, RE::BSFixedString a_hold,
			RE::BSFixedString a_resourceType)
		{
			std::shared_lock lock(g_registryLock);
			return CountSourcesLocked(View(a_hold), View(a_resourceType));
		}

		// D105 etapa 2: a contract draws one of the hold's sources of the type
		// (index 0 to CountHoldSources - 1) and reads where the worker goes.
		RE::BSFixedString GetHoldSourceIdNative(RE::StaticFunctionTag*, RE::BSFixedString a_hold,
			RE::BSFixedString a_resourceType, std::int32_t a_index)
		{
			std::shared_lock lock(g_registryLock);
			return RE::BSFixedString(SourceIdLocked(View(a_hold), View(a_resourceType), a_index));
		}

		RE::BSFixedString GetHoldSourceStringNative(RE::StaticFunctionTag*, RE::BSFixedString a_hold,
			RE::BSFixedString a_sourceId, RE::BSFixedString a_field, RE::BSFixedString a_default)
		{
			std::shared_lock lock(g_registryLock);
			return AsString(Child(Child(Child(&g_holdSources, View(a_hold)), View(a_sourceId)), View(a_field)), a_default);
		}

		// Fase 15: a numeric field of one source - a zone's "capacity" and
		// "recoveryDays". afDefault for an unknown hold, source or field.
		float GetHoldSourceFloatNative(RE::StaticFunctionTag*, RE::BSFixedString a_hold,
			RE::BSFixedString a_sourceId, RE::BSFixedString a_field, float a_default)
		{
			std::shared_lock lock(g_registryLock);
			return AsFloat(Child(Child(Child(&g_holdSources, View(a_hold)), View(a_sourceId)), View(a_field)), a_default);
		}

		// D105 etapa 3: the ore veins of one resource type in one source, for
		// the availability rule and the vein state the mod remembers. An
		// unloaded vein reference resolves to None in game, so the type comes
		// from the data (veins keyed by resource type). 0 for an unknown hold,
		// source or type.
		const json* SourceVeins(const RE::BSFixedString& a_hold, const RE::BSFixedString& a_sourceId,
			const RE::BSFixedString& a_resourceType)
		{
			return Child(Child(Child(Child(&g_holdSources, View(a_hold)), View(a_sourceId)), "veins"), View(a_resourceType));
		}

		std::int32_t CountHoldSourceVeinsNative(RE::StaticFunctionTag*, RE::BSFixedString a_hold,
			RE::BSFixedString a_sourceId, RE::BSFixedString a_resourceType)
		{
			std::shared_lock lock(g_registryLock);
			return CountArray(SourceVeins(a_hold, a_sourceId, a_resourceType));
		}

		RE::BSFixedString GetHoldSourceVeinNative(RE::StaticFunctionTag*, RE::BSFixedString a_hold,
			RE::BSFixedString a_sourceId, RE::BSFixedString a_resourceType, std::int32_t a_index,
			RE::BSFixedString a_default)
		{
			std::shared_lock lock(g_registryLock);
			return AsString(Element(SourceVeins(a_hold, a_sourceId, a_resourceType), a_index), a_default);
		}

		// Queue item 12, scope 1. Not registry data - config - but it rides on
		// this script for the same reason the registry does: the DLL is the only
		// side of the mod that reads a file from disk, and WOSK_Registry is where
		// Papyrus asks it what it read. A no-argument native on purpose: a
		// section/key pair would cross the boundary as two strings, and this
		// project has already paid twice for what the VM's case cache does to
		// strings built for a lookup (B003,
		// D099 and D127).
		std::int32_t GetWorkerTrackerSeconds(RE::StaticFunctionTag*)
		{
			return static_cast<std::int32_t>(AppConfig::Get().workerTrackerSeconds);
		}

		float GetOccupiedIncidentChance(RE::StaticFunctionTag*)
		{
			return AppConfig::Get().occupiedIncidentChance;
		}

		// D161/D163 (Fase 16): a number of one hold's candidate pool -
		// "rotationdays", "refilldaysmin", "refilldaysmax". afDefault for an
		// unknown hold or field.
		float GetCandidatePoolFloatNative(RE::StaticFunctionTag*, RE::BSFixedString a_hold,
			RE::BSFixedString a_field, float a_default)
		{
			std::shared_lock lock(g_registryLock);
			return AsFloat(Child(Child(&g_candidatePools, View(a_hold)), View(a_field)), a_default);
		}

		// D161: a field of one profession's spot in a hold's pool - "marker"
		// ("plugin|formid") and "place". asDefault when the hold has no spot
		// for that profession: the pool then has no slot for it.
		RE::BSFixedString GetCandidateSpotStringNative(RE::StaticFunctionTag*, RE::BSFixedString a_hold,
			RE::BSFixedString a_profession, RE::BSFixedString a_field, RE::BSFixedString a_default)
		{
			std::shared_lock lock(g_registryLock);
			return AsString(
				Child(Child(Child(Child(&g_candidatePools, View(a_hold)), "spots"), View(a_profession)), View(a_field)),
				a_default);
		}

		// D218 (Fase 22): the hold's extra spots - "extraspots", an array of
		// { "marker", "place" } whose profession is rolled at each arrival, not
		// the spot's. 0 for an unknown hold or a hold without the list.
		std::int32_t CountCandidateExtrasNative(RE::StaticFunctionTag*, RE::BSFixedString a_hold)
		{
			std::shared_lock lock(g_registryLock);
			return CountArray(Child(Child(&g_candidatePools, View(a_hold)), "extraSpots"));
		}

		// One extra spot's "marker" or "place". asDefault for an unknown hold,
		// index or field.
		RE::BSFixedString GetCandidateExtraStringNative(RE::StaticFunctionTag*, RE::BSFixedString a_hold,
			std::int32_t a_index, RE::BSFixedString a_field, RE::BSFixedString a_default)
		{
			std::shared_lock lock(g_registryLock);
			return AsString(
				Child(Element(Child(Child(&g_candidatePools, View(a_hold)), "extraSpots"), a_index), View(a_field)),
				a_default);
		}

		bool RegisterFuncs(RE::BSScript::IVirtualMachine* a_vm)
		{
			if (!a_vm) {
				return false;
			}
			// ASSUMPTION: true lets the VM call these without waiting for the
			// main thread. The vendored CommonLib only stores the flag
			// (NativeFunctionBase.cpp:137-145); the engine's use of it is not
			// in any header. The reads are correct either way - they only
			// touch data behind g_registryLock - so a wrong guess costs speed,
			// not correctness.
			constexpr bool kCallableFromTasklets = true;
			a_vm->RegisterFunction("FindTaskIndex", kScriptClass, FindTaskIndex, kCallableFromTasklets);
			a_vm->RegisterFunction("GetTaskFloat", kScriptClass, GetTaskFloat, kCallableFromTasklets);
			a_vm->RegisterFunction("GetTaskString", kScriptClass, GetTaskString, kCallableFromTasklets);
			a_vm->RegisterFunction("GetTierFloat", kScriptClass, GetTierFloat, kCallableFromTasklets);
			a_vm->RegisterFunction("GetTierInt", kScriptClass, GetTierInt, kCallableFromTasklets);
			a_vm->RegisterFunction("CountTaskOutputs", kScriptClass, CountTaskOutputs, kCallableFromTasklets);
			a_vm->RegisterFunction("GetTaskOutputFloat", kScriptClass, GetTaskOutputFloat, kCallableFromTasklets);
			a_vm->RegisterFunction("GetTaskOutputString", kScriptClass, GetTaskOutputString, kCallableFromTasklets);
			a_vm->RegisterFunction("CountTaskIngredients", kScriptClass, CountTaskIngredients, kCallableFromTasklets);
			a_vm->RegisterFunction("GetTaskIngredientFloat", kScriptClass, GetTaskIngredientFloat, kCallableFromTasklets);
			a_vm->RegisterFunction("GetTaskIngredientString", kScriptClass, GetTaskIngredientString, kCallableFromTasklets);
			a_vm->RegisterFunction("CountOutcomeRows", kScriptClass, CountOutcomeRows, kCallableFromTasklets);
			a_vm->RegisterFunction("GetOutcomeRowFloat", kScriptClass, GetOutcomeRowFloat, kCallableFromTasklets);
			a_vm->RegisterFunction("GetOutcomeRowString", kScriptClass, GetOutcomeRowString, kCallableFromTasklets);
			a_vm->RegisterFunction("CountProfessions", kScriptClass, CountProfessions, kCallableFromTasklets);
			a_vm->RegisterFunction("GetProfessionId", kScriptClass, GetProfessionId, kCallableFromTasklets);
			a_vm->RegisterFunction("CountHoldSources", kScriptClass, CountHoldSourcesNative, kCallableFromTasklets);
			a_vm->RegisterFunction("GetHoldSourceId", kScriptClass, GetHoldSourceIdNative, kCallableFromTasklets);
			a_vm->RegisterFunction("GetHoldSourceString", kScriptClass, GetHoldSourceStringNative, kCallableFromTasklets);
			a_vm->RegisterFunction("GetHoldSourceFloat", kScriptClass, GetHoldSourceFloatNative, kCallableFromTasklets);
			a_vm->RegisterFunction("CountHoldSourceVeins", kScriptClass, CountHoldSourceVeinsNative, kCallableFromTasklets);
			a_vm->RegisterFunction("GetHoldSourceVein", kScriptClass, GetHoldSourceVeinNative, kCallableFromTasklets);
			a_vm->RegisterFunction("GetWorkerTrackerSeconds", kScriptClass, GetWorkerTrackerSeconds, kCallableFromTasklets);
			a_vm->RegisterFunction("GetOccupiedIncidentChance", kScriptClass, GetOccupiedIncidentChance, kCallableFromTasklets);
			a_vm->RegisterFunction("GetCandidatePoolFloat", kScriptClass, GetCandidatePoolFloatNative, kCallableFromTasklets);
			a_vm->RegisterFunction("GetCandidateSpotString", kScriptClass, GetCandidateSpotStringNative, kCallableFromTasklets);
			a_vm->RegisterFunction("CountCandidateExtras", kScriptClass, CountCandidateExtrasNative, kCallableFromTasklets);
			a_vm->RegisterFunction("GetCandidateExtraString", kScriptClass, GetCandidateExtraStringNative, kCallableFromTasklets);
			spdlog::info("ProfessionsRegistry: {} natives bound (27 functions, keys matched ignoring case).",
				kScriptClass);
			return true;
		}

		void MergeProfessions()
		{
			constexpr auto kSourceDir = "Data/SKSE/Plugins/HonestWork/professions";
			constexpr auto kOutputPath = "Data/SKSE/Plugins/HonestWork/professions_merged.json";

			const auto files = SortedJsonFiles(kSourceDir);
			if (files.empty()) {
				spdlog::warn(
					"ProfessionsRegistry: no *.json files found in '{}' - professions_merged.json "
					"will have no professions.",
					kSourceDir);
			}

			json output = json::object();
			output["schemaVersion"] = 2;
			output["professions"] = MergeEntries(files, "professions");

			WriteMergedFile(kOutputPath, output);

			json lowered = LowercaseKeys(output["professions"], "professions");
			{
				std::unique_lock lock(g_registryLock);
				g_professions = std::move(lowered);
			}

			spdlog::info(
				"ProfessionsRegistry: merged {} profession file(s) from '{}' -> '{}' ({} profession(s))",
				files.size(), kSourceDir, kOutputPath, output["professions"].size());
		}

		void MergeContractTypes()
		{
			constexpr auto kSourceDir = "Data/SKSE/Plugins/HonestWork/contract_types";
			constexpr auto kOutputPath = "Data/SKSE/Plugins/HonestWork/contract_types_merged.json";

			const auto files = SortedJsonFiles(kSourceDir);
			if (files.empty()) {
				spdlog::warn(
					"ProfessionsRegistry: no *.json files found in '{}' - contract_types_merged.json "
					"will have no contract types.",
					kSourceDir);
			}

			json output = json::object();
			output["schemaVersion"] = 1;
			output["contractTypes"] = MergeEntries(files, "contractTypes");

			WriteMergedFile(kOutputPath, output);

			json lowered = LowercaseKeys(output["contractTypes"], "contractTypes");
			{
				std::unique_lock lock(g_registryLock);
				g_contractTypes = std::move(lowered);
			}

			spdlog::info(
				"ProfessionsRegistry: merged {} contract type file(s) from '{}' -> '{}' ({} type(s))",
				files.size(), kSourceDir, kOutputPath, output["contractTypes"].size());
		}

		// D105: ore sources per hold. A hold with no source of a task's
		// resource type neither offers nor issues that task.
		void MergeHoldSourceFiles()
		{
			constexpr auto kSourceDir = "Data/SKSE/Plugins/HonestWork/hold_sources";
			constexpr auto kOutputPath = "Data/SKSE/Plugins/HonestWork/hold_sources_merged.json";

			const auto files = SortedJsonFiles(kSourceDir);
			if (files.empty()) {
				spdlog::warn(
					"ProfessionsRegistry: no *.json files found in '{}' - no hold has a source, so no task "
					"can be issued.",
					kSourceDir);
			}

			json output = json::object();
			output["schemaVersion"] = 2;
			output["holdSources"] = MergeHoldSources(files);

			WriteMergedFile(kOutputPath, output);

			json lowered = LowercaseKeys(output["holdSources"], "holdSources");
			{
				std::unique_lock lock(g_registryLock);
				g_holdSources = std::move(lowered);
			}

			for (const auto& [hold, sources] : output["holdSources"].items()) {
				for (const auto& [sourceId, source] : sources.items()) {
					const auto kind = source.contains("kind") ? source["kind"].dump() : std::string("?");
					const auto types = source.contains("resourceTypes") ? source["resourceTypes"].dump() : std::string("[]");
					std::string veins;
					if (source.contains("veins") && source["veins"].is_object()) {
						for (const auto& [resourceType, refs] : source["veins"].items()) {
							veins += (veins.empty() ? "" : ", ") + resourceType + " " +
								std::to_string(refs.is_array() ? refs.size() : 0);
						}
					}
					if (source.contains("capacity")) {
						veins = "zone capacity " + source["capacity"].dump() + ", recovery " +
						        (source.contains("recoveryDays") ? source["recoveryDays"].dump() : std::string("?")) +
						        " day(s)";
					}
					spdlog::info("ProfessionsRegistry: hold '{}' source '{}' kind {} types {} (veins: {})", hold,
						sourceId, kind, types, veins.empty() ? std::string("none") : veins);
				}
			}
			spdlog::info("ProfessionsRegistry: merged {} hold source file(s) from '{}' -> '{}' ({} hold(s))",
				files.size(), kSourceDir, kOutputPath, output["holdSources"].size());
		}

		// D161 (Fase 16): the candidate pool of each hold - one spot per
		// profession (marker and place), rotation and refill days. A later
		// file's block for a hold replaces the earlier one wholesale, as a
		// profession block does (MergeEntries).
		void MergeCandidatePoolFiles()
		{
			constexpr auto kSourceDir = "Data/SKSE/Plugins/HonestWork/candidate_pools";
			constexpr auto kOutputPath = "Data/SKSE/Plugins/HonestWork/candidate_pools_merged.json";

			const auto files = SortedJsonFiles(kSourceDir);
			if (files.empty()) {
				spdlog::warn(
					"ProfessionsRegistry: no *.json files found in '{}' - no hold has a candidate pool, so no "
					"candidate stands anywhere.",
					kSourceDir);
			}

			json output = json::object();
			output["schemaVersion"] = 1;
			output["candidatePools"] = MergeEntries(files, "candidatePools");

			WriteMergedFile(kOutputPath, output);

			json lowered = LowercaseKeys(output["candidatePools"], "candidatePools");
			{
				std::unique_lock lock(g_registryLock);
				g_candidatePools = std::move(lowered);
			}

			for (const auto& [hold, pool] : output["candidatePools"].items()) {
				std::string spots;
				if (pool.contains("spots") && pool["spots"].is_object()) {
					for (const auto& [profession, spot] : pool["spots"].items()) {
						spots += (spots.empty() ? "" : ", ") + profession + " " +
							(spot.contains("marker") ? spot["marker"].dump() : std::string("?")) + " " +
							(spot.contains("place") ? spot["place"].dump() : std::string("?"));
					}
				}
				std::string extras;
				if (pool.contains("extraSpots") && pool["extraSpots"].is_array()) {
					for (const auto& extra : pool["extraSpots"]) {
						extras += (extras.empty() ? "" : ", ") +
							(extra.contains("marker") ? extra["marker"].dump() : std::string("?")) + " " +
							(extra.contains("place") ? extra["place"].dump() : std::string("?"));
					}
				}
				spdlog::info("ProfessionsRegistry: hold '{}' candidate pool rotation {} day(s), refill {}-{} day(s), spots: {}, extra spots: {}",
					hold, pool.contains("rotationDays") ? pool["rotationDays"].dump() : std::string("?"),
					pool.contains("refillDaysMin") ? pool["refillDaysMin"].dump() : std::string("?"),
					pool.contains("refillDaysMax") ? pool["refillDaysMax"].dump() : std::string("?"),
					spots.empty() ? std::string("none") : spots, extras.empty() ? std::string("none") : extras);
			}
			spdlog::info("ProfessionsRegistry: merged {} candidate pool file(s) from '{}' -> '{}' ({} hold(s))",
				files.size(), kSourceDir, kOutputPath, output["candidatePools"].size());
		}
	}

	void MergeAll()
	{
		MergeProfessions();
		MergeContractTypes();
		MergeHoldSourceFiles();
		MergeCandidatePoolFiles();
	}

	bool RegisterNatives()
	{
		const auto* papyrus = SKSE::GetPapyrusInterface();
		return papyrus && papyrus->Register(RegisterFuncs);
	}

	// Caller holds g_registryLock (shared). The V006 sum alone: the mean gold
	// value of the task's outputs, by weight.
	static float TaskGameValueLocked(std::string_view a_profession, std::int32_t a_taskIndex, std::string_view a_taskId)
	{
		const json* outputs = Child(Task(a_profession, a_taskIndex), "outputs");
		if (!outputs || !outputs->is_array()) {
			return 0.0f;
		}
		double totalWeight = 0.0;
		double weightedValue = 0.0;
		for (const auto& output : *outputs) {
			const json* form = Child(&output, "form");
			const float weight = AsFloat(Child(&output, "weight"), 0.0f);
			RE::TESForm* item = form && form->is_string() ? ResolveFormRef(form->get<std::string>()) : nullptr;
			if (item && weight > 0.0f) {
				totalWeight += weight;
				weightedValue += weight * item->GetGoldValue();  // TESForm.h:292
			} else {
				spdlog::warn("ProfessionsRegistry: {}/{}: output {} left out of the price (form not resolved, or weight {})",
					a_profession, a_taskId, form ? form->dump() : "without form", weight);
			}
		}
		return totalWeight > 0.0 ? static_cast<float>(weightedValue / totalWeight) : 0.0f;
	}

	// Caller holds g_registryLock (shared). Whole gold, rounded up (Fase 33 etapa 11, G1: there
	// is no decimal in the game's money). -1 when an ingredient does not resolve.
	static float TaskIngredientCostLocked(std::string_view a_profession, std::int32_t a_taskIndex, std::string_view a_taskId)
	{
		const json* ingredients = Child(Task(a_profession, a_taskIndex), "ingredients");
		if (!ingredients || !ingredients->is_array()) {
			return 0.0f;
		}
		double total = 0.0;
		for (const auto& ingredient : *ingredients) {
			const json* form = Child(&ingredient, "form");
			const float count = AsFloat(Child(&ingredient, "count"), 0.0f);
			RE::TESForm* item = form && form->is_string() ? ResolveFormRef(form->get<std::string>()) : nullptr;
			if (!item || count <= 0.0f) {
				// D159: an ingredient left out would undercharge; Papyrus refuses
				// the contract on the same condition.
				spdlog::warn("ProfessionsRegistry: {}/{}: ingredient {} not resolved (count {}) - no price",
					a_profession, a_taskId, form ? form->dump() : "without form", count);
				return -1.0f;
			}
			total += count * item->GetGoldValue();  // TESForm.h:292
		}
		return DishPrice::WholeGold(static_cast<float>(total));
	}

	// Fase 33 etapa 9 (E1): the reference price of every task - the game value, the
	// cook's floor and the ladder by the contract. Whole gold since etapa 11 (G1): rounded
	// up, and at least one over the tier below. See Core/DishPrice.h.
	float TaskUnitPrice(std::string_view a_profession, std::string_view a_taskId)
	{
		std::shared_lock lock(g_registryLock);
		const std::int32_t index = TaskIndexById(a_profession, a_taskId);
		const float game = TaskGameValueLocked(a_profession, index, a_taskId);
		if (game <= 0.0f) {
			return game;
		}

		const json* tasks = Child(Child(&g_professions, a_profession), "tasks");
		std::vector<DishPrice::Rung> rungs;
		std::size_t mine = 0;
		for (std::size_t i = 0; tasks && tasks->is_array() && i < tasks->size(); ++i) {
			const json* row = &(*tasks)[i];
			DishPrice::Rung rung;
			const json* tier = Child(row, "mintier");
			const json* tierRow = tier && tier->is_string() ? Tier(a_profession, tier->get<std::string>()) : nullptr;
			rung.minContracts = AsInt(Child(tierRow, "minContracts"), -1);
			if (i == static_cast<std::size_t>(index)) {
				mine = i;
			}
			const json* id = Child(row, "id");
			const std::string rowId = id && id->is_string() ? id->get<std::string>() : std::string();
			rung.game = TaskGameValueLocked(a_profession, static_cast<std::int32_t>(i), rowId);
			rung.ingredients = TaskIngredientCostLocked(a_profession, static_cast<std::int32_t>(i), rowId);
			rung.margin = AsFloat(Child(row, "ingredientMargin"), 0.0f);
			rung.step = AsFloat(Child(row, "tierStep"), 0.0f);
			rung.batch = (AsFloat(Child(row, "batchMin"), 0.0f) + AsFloat(Child(row, "batchMax"), 0.0f)) / 2.0f;
			rung.multiplier = AsFloat(Child(row, "priceMultiplier"), 1.0f);
			rungs.push_back(rung);
		}
		if (rungs.empty()) {
			return DishPrice::WholeGold(game);
		}
		const float reference = DishPrice::ReferenceOf(rungs, mine);
		if (reference != game) {
			spdlog::info("ProfessionsRegistry: {}/{}: reference price {} gold (game value {:.2f})",
				a_profession, a_taskId, reference, game);
		}
		return reference;
	}

	float TaskIngredientCost(std::string_view a_profession, std::string_view a_taskId)
	{
		std::shared_lock lock(g_registryLock);
		return TaskIngredientCostLocked(a_profession, TaskIndexById(a_profession, a_taskId), a_taskId);
	}

	std::int32_t CountHoldSources(std::string_view a_hold, std::string_view a_resourceType)
	{
		std::shared_lock lock(g_registryLock);
		return CountSourcesLocked(a_hold, a_resourceType);
	}

	std::string TaskResourceType(std::string_view a_profession, std::string_view a_taskId)
	{
		std::shared_lock lock(g_registryLock);
		const json* type = Child(Task(a_profession, TaskIndexById(a_profession, a_taskId)), "resourceType");
		return type && type->is_string() ? type->get<std::string>() : std::string();
	}

	std::vector<TaskSummary> ListTasks()
	{
		const auto text = [](const json* a_value, const std::string& a_default) {
			return a_value && a_value->is_string() && !a_value->get<std::string>().empty() ?
			           a_value->get<std::string>() :
			           a_default;
		};
		std::shared_lock lock(g_registryLock);
		std::vector<TaskSummary> out;
		if (!g_professions.is_object()) {
			return out;
		}
		for (const auto& [profession, block] : g_professions.items()) {
			const json* tasks = Child(&block, "tasks");
			if (!tasks || !tasks->is_array()) {
				continue;
			}
			for (const auto& task : *tasks) {
				TaskSummary summary;
				summary.profession = profession;
				summary.id = text(Child(&task, "id"), std::string());
				if (summary.id.empty()) {
					continue;
				}
				summary.label = text(Child(&task, "label"), summary.id);
				summary.minTier = text(Child(&task, "minTier"), "apprentice");
				summary.resourceType = text(Child(&task, "resourceType"), std::string());
				summary.hours = AsFloat(Child(&task, "hours"), 0.0f);
				summary.batchMin = AsFloat(Child(&task, "batchMin"), 0.0f);
				summary.batchMax = AsFloat(Child(&task, "batchMax"), 0.0f);
				summary.incidentChance = AsFloat(Child(&task, "incidentChance"), 0.0f);
				summary.priceMultiplier = AsFloat(Child(&task, "priceMultiplier"), 1.0f);
				out.push_back(std::move(summary));
			}
		}
		return out;
	}

	std::vector<TierSummary> ListTiers()
	{
		static constexpr const char* kTierOrder[] = { "apprentice", "worker", "veteran", "master" };
		std::shared_lock lock(g_registryLock);
		std::vector<TierSummary> out;
		if (!g_professions.is_object()) {
			return out;
		}
		for (const auto& [profession, block] : g_professions.items()) {
			for (const char* tier : kTierOrder) {
				const json* row = Child(Child(&block, "tiers"), tier);
				if (!row || !row->is_object()) {
					continue;
				}
				TierSummary summary;
				summary.profession = profession;
				summary.id = tier;
				summary.minContracts = AsInt(Child(row, "minContracts"), 0);
				summary.durationMultiplier = AsFloat(Child(row, "durationMultiplier"), 1.0f);
				summary.yieldMultiplier = AsFloat(Child(row, "yieldMultiplier"), 1.0f);
				out.push_back(std::move(summary));
			}
		}
		return out;
	}
}
