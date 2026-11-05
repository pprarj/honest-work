# PrismaUI_API.h - origin

One third-party header. **Not authored by this project, and not edited by it.**
The licence ships with it: `LICENSE.md`, next to this file.

| | |
|---|---|
| File | `PrismaUI_API.h`, the C++ API header of Prisma UI |
| Copied from | `src/PrismaUI_API.h` of `github.com/PrismaUI-SKSE/framework`, tag `1.5.1` |
| Hash | sha256, first 16 hex: `c359a4b0b20da6de` (the file as it is in the tag) |
| Licence | "Prisma UI License", the `LICENSE.md` of the same tag, saved next to the header. Section 2.4 allows distributing the original version when the licence is included without modification; this is why the header is kept byte-identical. |

Prisma UI itself is **not redistributed**: this project ships only its own DLL and its own panel page.

## Why the build defines UNICODE

The header calls `GetModuleHandle` with a wide string literal. The build defines `UNICODE` and `_UNICODE` (see `plugin-skse/CMakeLists.txt`) instead of editing the header.
