// Copyright (C) 2026 Awrawra
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of Honest Work - Workers of Skyrim, free software under the
// GNU General Public License, version 3. See the LICENSE file at the repository root.

// Fase 33 etapa 7 (D281, V070 B1): text whose width changes while the panel is open
// ("~10 min left" -> "~5 min left"). React updates a bare text node in place; inside the
// shrink-to-fit .hw-state the box gets narrower and the embedded browser did not repaint
// the strip the old text covered, leaving "~5 min lefteft". Keying the span on the text
// removes the old node and inserts a new one, which invalidates the old area.
export function LiveText({ text }: { text: string }) {
  return (
    <span key={text} className="hw-live-text">
      {text}
    </span>
  );
}
