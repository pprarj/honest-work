# Honest Work - Workers of Skyrim

Honest Work is a mod for Skyrim Special Edition / Anniversary Edition. You recruit workers by hold and issue paid gold contracts; they travel to a resource, run a real risk of injury or death, and come back with the batch.

This repository holds the **source** of the mod's native plugin, its panel and its Papyrus scripts. The mod itself is published on Nexus Mods as "Honest Work - Workers of Skyrim" (search the title on [Nexus Mods Skyrim Special Edition](https://www.nexusmods.com/skyrimspecialedition)).

**Version of this source:** the tag `v1.0.0` is the source of the 1.0.0 release. Later work lands on other branches when it has been tested.

## License

Copyright (C) 2026 Awrawra.

Honest Work is free software, released under the **GNU General Public License, version 3** (GPL-3.0-only). See [LICENSE](LICENSE) and <https://www.gnu.org/licenses/gpl-3.0.html>. The reason is that the native plugin links against CommonLibSSE-NG, which is GPL-3.0.

Third-party files that are kept in this repository under their own terms:

| File | Terms |
|---|---|
| `plugin-skse/extern/PrismaUI/PrismaUI_API.h` | Prisma UI License, shipped next to it (`LICENSE.md`). Copied unmodified. |
| `plugin-skse/extern/SKSEMenuFramework/SKSEMenuFramework.h` | LGPL-2.1, shipped next to it (`LICENSE`). Copied unmodified. |
| `plugin-skse/extern/commonlibsse-ng` | CommonLibSSE-NG, GPL-3.0 with its own modding exceptions; a git submodule, not copied. |
| `ui-prisma/public/FONTS-LICENSE.txt` | Cinzel and Source Sans 3, SIL Open Font License 1.1. |

## What is in this repository

```
plugin-skse/     SKSE plugin source (C++, CommonLibSSE-NG): the panel bridge and the registry merge
ui-prisma/       The operator panel (React, TypeScript, Vite) that Prisma UI draws
Scripts/Source/  Papyrus source (.psc)
```

The plugin file (`HonestWork.esp`), its generated records, voice lines and JSON data are not here: they are part of the release archive on Nexus Mods. This repository is the source of the code.

## Building

See [DEVELOPMENT.md](DEVELOPMENT.md).

## Contributing

Issues and patches are welcome. A pull request is judged on the code alone, so explain the why in the description.
