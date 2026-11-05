// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

// DishPrice.h
// Honest Work - Workers of Skyrim
//
// Fase 33 etapa 8 (D284) and etapa 9 (E1, rule "ladder by the contract"): the
// reference price of one unit of a task, in every profession; whole gold since
// etapa 11 (G1, D295). The file keeps its etapa 8 name (the cook was the first).
// Pure: no CommonLib, no JSON, so the test target builds it alone
// (tests/test_dish_price.cpp) against the same vectors the Python model and the
// Papyrus harness are held to (plugin-skse/tests/fixtures/dish_price_vectors.txt).
//
//   ing       = WholeGold(ingredient cost of one unit)
//   average contract = batch x (reference x multiplier + ing)
//   reference = WholeGold(max(game value, ing x margin,
//                             (below x step / batch - ing) / multiplier))
//   reference = max(reference, dearest reference of the tier below + 1)   (step > 0)
//   below     = the dearest average contract among the tasks at the nearest lower
//               rank (the tier's minContracts) the profession has tasks at
//
// There is no decimal in the game's money: the reference and the ingredients are whole
// gold, rounded UP, and the tier above is at least one gold over the tier below
// whatever the rounding did. A term whose factor is 0 (or whose base is 0) is off, the
// +1 with the step. A game value of 0 stays 0; an ingredient cost below 0 (not
// resolved) leaves the whole game value. The reference never goes below the game
// value. The item's value in the game does not change; only the contract reads this.
// The same sum lives in the development reference model (price_reference) and in
// WOSK_WorkerAliasScript.psc (PriceReference); change one, change the three, with the
// operations in the same order (float32 in Papyrus).

#pragma once

#include <cmath>
#include <cstddef>
#include <vector>

namespace HonestWork::Core::DishPrice
{
	struct Rung
	{
		int minContracts = -1;     // contracts the task's minTier asks (-1: tier unknown)
		float game = 0.0f;         // mean gold value of the outputs, by weight
		float ingredients = 0.0f;  // gold the ingredients of one unit cost (< 0: not resolved; 0: none)
		float margin = 0.0f;       // ingredientMargin
		float step = 0.0f;         // tierStep
		float batch = 0.0f;        // (batchMin + batchMax) / 2
		float multiplier = 1.0f;   // priceMultiplier
	};

	// A figure that is whole in exact arithmetic (2.0000002 in float32) stays on its side of
	// the rounding: no real price sits within this of a whole number without being one.
	inline constexpr float kGoldEpsilon = 0.001f;

	// Round a price up to whole gold, at least 1 for a positive one. 0 (no price) and a
	// negative (the -1 of an ingredient that does not resolve) pass through unchanged.
	inline float WholeGold(float a_gold)
	{
		if (a_gold <= 0.0f) {
			return a_gold;
		}
		const float whole = std::ceil(a_gold - kGoldEpsilon);
		return whole < 1.0f ? 1.0f : whole;
	}

	// a_ingredients is already whole gold (WholeGold).
	inline float Reference(float a_game, float a_ingredients, float a_margin, float a_belowContract,
		float a_belowReference, float a_step, float a_batch, float a_multiplier)
	{
		if (a_game <= 0.0f) {
			return a_game;
		}
		if (a_ingredients < 0.0f) {
			return WholeGold(a_game);
		}
		float reference = a_game;
		if (a_margin > 0.0f && a_ingredients > 0.0f && a_ingredients * a_margin > reference) {
			reference = a_ingredients * a_margin;
		}
		if (a_step > 0.0f && a_belowContract > 0.0f && a_batch > 0.0f && a_multiplier > 0.0f) {
			const float needed = (a_belowContract * a_step / a_batch - a_ingredients) / a_multiplier;
			if (needed > reference) {
				reference = needed;
			}
		}
		reference = WholeGold(reference);
		if (a_step > 0.0f && a_belowReference > 0.0f && a_belowReference + 1.0f > reference) {
			reference = a_belowReference + 1.0f;
		}
		return reference;
	}

	inline float ContractOf(const Rung& a_rung, float a_reference)
	{
		return a_rung.batch * (a_reference * a_rung.multiplier + (a_rung.ingredients > 0.0f ? WholeGold(a_rung.ingredients) : 0.0f));
	}

	// The reference of task a_index. a_depth guards a malformed table (the tier below
	// always asks fewer contracts, so the walk ends in a few steps).
	inline float ReferenceOf(const std::vector<Rung>& a_rungs, std::size_t a_index, int a_depth = 0)
	{
		const Rung& rung = a_rungs[a_index];
		if (a_depth > 16 || rung.game <= 0.0f || rung.ingredients < 0.0f) {
			return rung.game <= 0.0f || rung.ingredients >= 0.0f ? rung.game : WholeGold(rung.game);
		}
		float below = 0.0f;
		float belowReference = 0.0f;
		if (rung.step > 0.0f && rung.minContracts >= 0) {
			int belowRank = -1;
			for (std::size_t i = 0; i < a_rungs.size(); ++i) {
				if (i != a_index && a_rungs[i].minContracts >= 0 && a_rungs[i].minContracts < rung.minContracts &&
					a_rungs[i].minContracts > belowRank) {
					belowRank = a_rungs[i].minContracts;
				}
			}
			if (belowRank >= 0) {
				for (std::size_t i = 0; i < a_rungs.size(); ++i) {
					if (i != a_index && a_rungs[i].minContracts == belowRank) {
						const float reference = ReferenceOf(a_rungs, i, a_depth + 1);
						const float contract = ContractOf(a_rungs[i], reference);
						if (contract > below) {
							below = contract;
						}
						if (reference > belowReference) {
							belowReference = reference;
						}
					}
				}
			}
		}
		return Reference(rung.game, WholeGold(rung.ingredients), rung.margin, below, belowReference, rung.step, rung.batch,
			rung.multiplier);
	}
}
