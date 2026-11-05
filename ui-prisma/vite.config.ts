// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Honest Work - Workers of Skyrim - Prisma UI panel frontend.
//
// Prisma UI's Ultralight-based view loads a plain local index.html plus its
// referenced local assets (D079) - there is no dev
// server involved at runtime, only this build's `dist/` output, deployed
// by the `prisma-builder` skill to Data/PrismaUI/views/HonestWork-Panel/.
// `base: "./"` keeps every asset reference relative, since dist/index.html
// is opened from a local path, not served from a web root.
export default defineConfig({
  plugins: [react()],
  base: "./",
  build: {
    outDir: "dist",
  },
});
