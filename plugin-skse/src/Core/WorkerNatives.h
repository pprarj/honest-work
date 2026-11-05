// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

// WorkerNatives.h
// Honest Work - Workers of Skyrim
//
// The two things the worker script used to take from the PO3 Papyrus Extender
// (D214-D216): the linked reference an actor's packages read
// by keyword, and the death of the road-encounter bandit.

#pragma once

namespace HonestWork::Core::WorkerNatives
{
	// Binds the WOSK_Native script class (Papyrus). False if the VM interface
	// was refused.
	bool Register();

	// Adds the death sink. Call once, at kDataLoaded.
	void OnDataLoaded();

	// Forgets every watched bandit (new game / before a save loads: the worker
	// script watches again from RestoreTravelTarget).
	void ClearWatched();
}
