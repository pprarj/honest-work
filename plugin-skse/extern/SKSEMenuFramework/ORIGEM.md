# SKSEMenuFramework.h - origin

One third-party header. **Not authored by this project, and not edited by it.**
The licence ships with it: `LICENSE`, next to this file.

| | |
|---|---|
| File | `SKSEMenuFramework.h`, the C++ API header of SKSE Menu Framework 3 |
| Copied from | `resources/SKSEMenuFramework.h` of `github.com/QTR-Modding/SKSE-Menu-Framework-3` (formerly under the author's account), commit `f93a7290f08f7f2666ee3c604afa2dc25dcd03b1` (2026-07-04) |
| Hash | sha256, first 16 hex: `4dca8c4ec8be278b`, with line endings normalised to LF and no byte-order mark |
| Licence | GNU Lesser General Public License, version 2.1 - the `LICENSE` of the same commit, saved next to the header. LGPL-2.1 section 3 lets the terms be replaced by the ordinary GNU GPL (version 2 or any later one), which is how this header sits inside a GPL-3.0 project. The framework's repository itself moved to GPL-3.0 afterwards. |

SKSE Menu Framework itself is **not redistributed**. The header is an optional dependency, resolved at run time with `GetProcAddress`: no import library, and the settings page simply does not appear when the framework is absent.
