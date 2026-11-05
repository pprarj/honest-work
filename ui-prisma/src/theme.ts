// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

// theme.ts
// Honest Work - Workers of Skyrim
//
// D188 (Fase 18): three candidate palettes next to the current one, for the
// comparison in a browser. Each palette is a block of the same
// tokens in style.css (:root[data-theme="..."]). ?tema=NAME sets it; with no
// ?tema= (always the case in game) the default stays. D189: frost,
// which is now :root itself; amber (the old default) is a block.

export const THEMES = ["frost", "amber", "moss", "parchment"] as const;
export type Theme = (typeof THEMES)[number];

export function themeFromAddress(): Theme {
  try {
    const t = new URLSearchParams(window.location.search).get("tema");
    return (THEMES as readonly string[]).includes(t ?? "") ? (t as Theme) : "frost";
  } catch {
    return "frost";
  }
}

// D198 (Fase 19): the palette the DLL sends (window.hwTheme, from the TOML or
// the SKSE Menu Framework settings page). Applied in place, no reload; an
// unknown name falls back to frost. Returns the palette now worn.
export function setTheme(name: string): Theme {
  const theme = (THEMES as readonly string[]).includes(name) ? (name as Theme) : "frost";
  if (theme === "frost") delete document.documentElement.dataset.theme;
  else document.documentElement.dataset.theme = theme;
  return theme;
}

export function applyTheme(): Theme {
  return setTheme(themeFromAddress());
}
