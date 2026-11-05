// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

import { StrictMode } from "react";
import { createRoot } from "react-dom/client";

// Installs window.hwInit before App mounts - the C++ host's
// onDomReadyCallback (PrismaPanel.cpp) can fire its Invoke("window.hwInit(...)")
// call any time after this script has run, so the listener must exist
// before React itself does (D079).
import { hostPalette } from "./prisma-bridge";
import App from "./App";
// D170: both fonts are SIL OFL 1.1, bundled (latin subset, woff2 + woff).
import "@fontsource/cinzel/latin-600.css";
import "@fontsource/source-sans-3/latin-400.css";
import "@fontsource/source-sans-3/latin-600.css";
import "./style.css";
import { demoMode, runDemo } from "./demo";
import { applyTheme } from "./theme";

// D188: ?tema=... picks a palette before the first paint; in game the address
// has no query and the default stays.
// C1: unless the host already sent one (it may have, before this line ran).
if (hostPalette() === null) applyTheme();

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);

// D169: ?demo=... in a plain browser only; in game the address has no query.
const demo = demoMode();
if (demo) runDemo(demo);
