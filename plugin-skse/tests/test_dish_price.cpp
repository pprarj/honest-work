// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

// test_dish_price.cpp
// Honest Work - Workers of Skyrim
//
// Fase 33 etapa 8 (D2), etapa 9 (E1) and etapa 11 (G1, whole gold): Core/DishPrice.h against the vectors the Python model
// is held to (plugin-skse/tests/fixtures/dish_price_vectors.txt; DISH_PRICE_VECTORS is
// the path CMake passes). No framework: each CHECK prints the failing
// expression and the run ends with exit code 1 if any failed.

#include "Core/DishPrice.h"

#include <cmath>
#include <cstdio>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

namespace
{
	int g_failed = 0;
	int g_passed = 0;

	void Check(bool a_ok, const std::string& a_what, int a_line)
	{
		if (a_ok) {
			++g_passed;
			return;
		}
		++g_failed;
		std::printf("FAIL line %d  %s\n", a_line, a_what.c_str());
	}

	namespace D = HonestWork::Core::DishPrice;

	void RunCase(const std::string& a_name, const std::vector<D::Rung>& a_rungs, const std::vector<float>& a_expected)
	{
		Check(a_rungs.size() == a_expected.size(), a_name + ": task count and expect count differ", 0);
		if (a_rungs.size() != a_expected.size()) {
			return;
		}
		for (std::size_t i = 0; i < a_rungs.size(); ++i) {
			const float got = D::ReferenceOf(a_rungs, i);
			Check(std::fabs(got - a_expected[i]) < 0.001f,
				a_name + ": task " + std::to_string(i) + " got " + std::to_string(got) + " want " +
					std::to_string(a_expected[i]),
				0);
		}
	}

	void TestVectors()
	{
		std::ifstream in(DISH_PRICE_VECTORS);
		Check(in.good(), std::string("open ") + DISH_PRICE_VECTORS, 0);
		std::string line;
		std::string name;
		std::vector<D::Rung> rungs;
		int cases = 0;
		while (std::getline(in, line)) {
			if (!line.empty() && line.back() == '\r') {
				line.pop_back();
			}
			if (line.empty() || line[0] == '#') {
				continue;
			}
			std::istringstream words(line);
			std::string key;
			words >> key;
			if (key == "case") {
				words >> name;
				rungs.clear();
			} else if (key == "task") {
				D::Rung rung;
				float batchMin = 0.0f;
				float batchMax = 0.0f;
				words >> rung.minContracts >> rung.game >> rung.ingredients >> rung.margin >> rung.step >> batchMin >>
					batchMax >> rung.multiplier;
				rung.batch = (batchMin + batchMax) / 2.0f;
				rungs.push_back(rung);
			} else if (key == "expect") {
				std::vector<float> expected;
				float value = 0.0f;
				while (words >> value) {
					expected.push_back(value);
				}
				RunCase(name, rungs, expected);
				++cases;
			}
		}
		Check(cases >= 18, "all the cases of the vectors file ran (" + std::to_string(cases) + ")", 0);
	}

	void TestRoundingVectors()
	{
		std::ifstream in(GOLD_ROUNDING_VECTORS);
		Check(in.good(), std::string("open ") + GOLD_ROUNDING_VECTORS, 0);
		std::string line;
		int vectors = 0;
		while (std::getline(in, line)) {
			if (!line.empty() && line.back() == '\r') {
				line.pop_back();
			}
			if (line.empty() || line[0] == '#') {
				continue;
			}
			std::istringstream words(line);
			float input = 0.0f;
			float expected = 0.0f;
			words >> input >> expected;
			const float got = D::WholeGold(input);
			Check(got == expected, "WholeGold(" + std::to_string(input) + ") got " + std::to_string(got) + " want " + std::to_string(expected), 0);
			++vectors;
		}
		Check(vectors >= 15, "all the rounding vectors ran (" + std::to_string(vectors) + ")", 0);
	}

	void TestTerms()
	{
		// The floor lifts a dish above its own ingredients: 5.44 is 6 gold, 6 x 1.2 = 7.2, up to 8.
		Check(D::Reference(4.56f, D::WholeGold(5.44f), 1.2f, 0.0f, 0.0f, 1.15f, 5.0f, 1.4f) == 8.0f, "floor", 0);
		// A factor of 0 switches its term off (the game value, rounded up).
		Check(D::Reference(4.56f, 6.0f, 0.0f, 99.0f, 99.0f, 0.0f, 5.0f, 1.4f) == 5.0f, "both off", 0);
		// The game value wins when it is already the highest.
		Check(D::Reference(50.0f, 6.0f, 1.2f, 10.0f, 3.0f, 1.15f, 5.0f, 1.4f) == 50.0f, "game value wins", 0);
		// The ladder solves the unit net of the ingredients: (70 x 1 / 5 - 3) / 2 = 5.5, up to 6.
		Check(D::Reference(1.0f, 3.0f, 0.0f, 70.0f, 0.0f, 1.0f, 5.0f, 2.0f) == 6.0f, "net of ingredients", 0);
		// An ingredient that does not resolve leaves the whole game value.
		Check(D::Reference(4.56f, -1.0f, 1.2f, 99.0f, 99.0f, 1.15f, 5.0f, 1.4f) == 5.0f, "ingredient not resolved", 0);
		// No price stays no price.
		Check(D::Reference(0.0f, 3.0f, 1.2f, 99.0f, 99.0f, 1.15f, 5.0f, 1.4f) == 0.0f, "no game value", 0);
		// The contract at the reference meets the ladder.
		const float ref = D::Reference(1.0f, 3.0f, 0.0f, 70.0f, 0.0f, 1.15f, 5.0f, 2.0f);
		D::Rung rung;
		rung.ingredients = 3.0f;
		rung.batch = 5.0f;
		rung.multiplier = 2.0f;
		Check(D::ContractOf(rung, ref) >= 70.0f * 1.15f - 0.01f, "contract meets the ladder", 0);
		// The tier above is one over the tier below when the ladder alone would tie: 10 and 10 -> 11.
		Check(D::Reference(1.0f, 0.0f, 0.0f, 100.0f, 10.0f, 1.0f, 10.0f, 1.0f) == 11.0f, "plus one", 0);
		// The ladder above the +1 stays: 100 x 1.5 / 10 = 15.
		Check(D::Reference(1.0f, 0.0f, 0.0f, 100.0f, 10.0f, 1.5f, 10.0f, 1.0f) == 15.0f, "ladder above plus one", 0);
		// Step 0 switches both off.
		Check(D::Reference(1.0f, 0.0f, 0.0f, 100.0f, 10.0f, 0.0f, 10.0f, 1.0f) == 1.0f, "step off", 0);
		// WholeGold: up, with the tolerance, at least 1, 0 and -1 pass.
		Check(D::WholeGold(1.01f) == 2.0f, "whole 1.01", 0);
		Check(D::WholeGold(2.0004f) == 2.0f, "whole 2.0004", 0);
		Check(D::WholeGold(2.002f) == 3.0f, "whole 2.002", 0);
		Check(D::WholeGold(0.2f) == 1.0f, "whole 0.2", 0);
		Check(D::WholeGold(7.0f) == 7.0f, "whole 7", 0);
		Check(D::WholeGold(6.0000005f) == 6.0f, "whole float noise", 0);
		Check(D::WholeGold(0.0f) == 0.0f && D::WholeGold(-1.0f) == -1.0f, "whole passes 0 and -1", 0);
		Check(D::WholeGold(D::WholeGold(80.58f)) == D::WholeGold(80.58f), "whole is idempotent", 0);
		// The lowest tier has nothing below it: the game value stays.
		std::vector<D::Rung> rungs(2);
		rungs[0].minContracts = 0;
		rungs[0].game = 10.0f;
		rungs[0].step = 1.15f;
		rungs[0].batch = 10.0f;
		rungs[1] = rungs[0];
		rungs[1].minContracts = 5;
		rungs[1].game = 1.0f;
		Check(D::ReferenceOf(rungs, 0) == 10.0f, "no tier below the first", 0);
		// 10 x (10 x 1) = 100 below; x 1.15 / 10 / 1 = 11.5, up to 12.
		Check(D::ReferenceOf(rungs, 1) == 12.0f, "the second climbs over the first", 0);
	}
}

int main()
{
	TestVectors();
	TestRoundingVectors();
	TestTerms();
	std::printf("HonestWorkDishTests: %d passed, %d failed\n", g_passed, g_failed);
	return g_failed == 0 ? 0 : 1;
}
