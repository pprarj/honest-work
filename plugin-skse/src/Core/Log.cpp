// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

// Log.cpp
// Honest Work - Workers of Skyrim

#include "Log.h"

#include "Version.h"

#include <spdlog/sinks/basic_file_sink.h>

#include <filesystem>
#include <format>
#include <string>

namespace HonestWork::Core::Log
{
	namespace
	{
		// Previous sessions kept on disk - three, same depth as the game's own
		// Papyrus.0-3.log, so one habit covers both logs.
		constexpr int kKeptLogs = 3;

		// Rotates by SESSION, not by size. Mechanism taken from the Lodestone
		// logger (same author).
		//
		// The file used to be truncated on every launch, so only the session
		// just played could ever be read: a second launch before anyone looked
		// erased the first one's evidence. spdlog's rotating_file_sink is the
		// wrong tool for this - it rotates by size, so a short session never
		// rotates at all.
		//
		// HonestWork.log is always the current run; HonestWork.1.log is the
		// previous one, up to HonestWork.3.log. The current file keeps its name
		// so the contract's `log` field and every doc pointing at it still work.
		//
		// A failed rotation must never cost the log: every filesystem call uses
		// the error_code overload, and on failure the sink still opens and
		// truncates exactly as before. Returns a description of the problem, or
		// empty - it runs before the logger exists, so the caller reports it.
		std::string RotateLogs(const std::filesystem::path& a_current)
		{
			std::error_code ec;

			const auto dir = a_current.parent_path();
			const auto stem = a_current.stem().string();
			const auto ext = a_current.extension().string();

			const auto nth = [&](int a_n) {
				return dir / std::format("{}.{}{}", stem, a_n, ext);
			};

			// Oldest falls off; missing is not an error.
			std::filesystem::remove(nth(kKeptLogs), ec);

			// Shift oldest first so nothing is overwritten before it moved. A gap
			// in the sequence only sets ec and changes nothing.
			for (int i = kKeptLogs - 1; i >= 1; --i) {
				std::filesystem::rename(nth(i), nth(i + 1), ec);
			}

			if (!std::filesystem::exists(a_current, ec)) {
				return {};
			}

			std::filesystem::rename(a_current, nth(1), ec);
			if (ec) {
				return std::format("the previous log could not be renamed ({}) - it was overwritten instead",
					ec.message());
			}

			return {};
		}
	}

	bool Init()
	{
		auto path = SKSE::log::log_directory();
		if (!path) {
			// No log directory - nothing to write to, and no way to report it.
			return false;
		}

		*path /= std::format("{}.log", Version::kProjectName);

		// Before the sink opens, and therefore before anything is written.
		const auto rotationProblem = RotateLogs(*path);

		auto sink = std::make_shared<spdlog::sinks::basic_file_sink_mt>(path->string(), true);
		auto log = std::make_shared<spdlog::logger>("global log", std::move(sink));

		// Release builds stay at info; debug builds get everything - the
		// usual convention.
#ifndef NDEBUG
		log->set_level(spdlog::level::trace);
		log->flush_on(spdlog::level::trace);
#else
		log->set_level(spdlog::level::info);
		log->flush_on(spdlog::level::info);
#endif

		spdlog::set_default_logger(std::move(log));
		spdlog::set_pattern("[%H:%M:%S.%e] [%l] %v");

		if (!rotationProblem.empty()) {
			spdlog::warn("Log: {}. The previous session's log is gone.", rotationProblem);
		}

		return true;
	}

	void ApplyConfiguredLevel(const std::string& a_level)
	{
#ifndef NDEBUG
		return;
#else
		auto level = spdlog::level::info;
		if (a_level == "trace") {
			level = spdlog::level::trace;
		} else if (a_level == "debug") {
			level = spdlog::level::debug;
		}

		if (auto logger = spdlog::default_logger()) {
			logger->set_level(level);
			logger->flush_on(level);
		}
#endif
	}
}
