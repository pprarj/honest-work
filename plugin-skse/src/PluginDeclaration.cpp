// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

// PluginDeclaration - the SKSE version data this DLL exports (D214).
//
// WHY THIS IS HAND-WRITTEN. add_commonlibsse_plugin generates this declaration,
// but it hardcodes StructCompatibility::Independent and offers no way to change
// it. On runtime 1.7.104 SKSE 2.3.1 then refuses the plugin with "must be
// recompiled for new address library". Declaring it here is the only place the
// required value can be expressed, so the generated translation unit is dropped
// from the target in CMakeLists.txt - two definitions of SKSEPlugin_Version
// would not link.
//
// WHAT SKSE ACTUALLY READS. SKSEPluginInfo exports a PluginDeclaration object
// and SKSE reads those same bytes as a PluginVersionData. Both are 0x350 bytes
// and their fields line up by offset, so StructCompatibility sits exactly where
// PluginVersionData keeps versionIndependenceEx. That field is a BIT FIELD, not
// an enum:
//
//     bit 0  kVersionIndependentEx_NoStructUse      == StructCompatibility::Independent
//     bit 1  kVersionIndependentEx_AddressLibraryV5
//
// SKSE 2.3.1 requires bit 1 from a plugin that resolves addresses through the
// Address Library when the PE TimeDateStamp falls in its legacy window. The
// StructCompatibility enum of CommonLib v6.7.1 has no name for bit 1, so the
// value is composed from the named constants of both sides rather than written
// as a literal 3. An older SKSE ignores a bit it does not know, so one DLL
// serves both loaders.

#include "REL/Relocation.h"
#include "SKSE/SKSE.h"

#include "Version.h"

namespace
{
	inline constexpr auto kStructCompatibility = static_cast<SKSE::StructCompatibility>(
		static_cast<std::uint32_t>(SKSE::StructCompatibility::Independent) |
		static_cast<std::uint32_t>(SKSE::PluginVersionData::kVersionIndependentEx_AddressLibraryV5));
}

// The version numbers come from Version.h so that project(... VERSION ...) in
// CMakeLists.txt stays the single source of truth.
SKSEPluginInfo(
	.Version = REL::Version{
		HonestWork::Version::kMajor,
		HonestWork::Version::kMinor,
		HonestWork::Version::kPatch,
		0 },
	.Name = HonestWork::Version::kProjectName,
	.Author = "Awrawra"sv,
	.SupportEmail = ""sv,
	.StructCompatibility = kStructCompatibility,
	.RuntimeCompatibility = SKSE::VersionIndependence::AddressLibrary,
	.MinimumSKSEVersion = REL::Version{ 0, 0, 0, 0 })
