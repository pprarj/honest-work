# Building Honest Work

This repository holds source only. Building it produces the files a release archive carries; it does not produce an installed mod on its own.

Clone with the submodule:

```
git clone --recurse-submodules https://github.com/pprarj/honest-work.git
```

## The SKSE plugin (`plugin-skse/`)

Toolchain: Visual Studio 2022 (MSVC, C++23), CMake 3.21+, and [vcpkg](https://github.com/microsoft/vcpkg) with `VCPKG_ROOT` set to your checkout. The dependencies come from `plugin-skse/vcpkg.json` (manifest mode, pinned baseline). The triplet is `x64-windows-static-md`.

```
cmake -S plugin-skse -B plugin-skse/build --preset vs2022-windows
cmake --build plugin-skse/build --config Release
```

The DLL lands in `plugin-skse/build/Release/HonestWork.dll`. To also copy it somewhere after every build (for example into a mod folder), set `HONESTWORK_OUTPUT_FOLDER` as a CMake cache variable or an environment variable; without it nothing is copied.

Tests of the plugin's pure rules are built with it. Both exit with code 0 when everything passes; the second one reads the vectors in `plugin-skse/tests/fixtures/`.

```
plugin-skse/build/Release/HonestWorkTests.exe
plugin-skse/build/Release/HonestWorkDishTests.exe
```

**Visual Studio's developer prompt sets its own `VCPKG_ROOT`** (the vcpkg bundled with Visual Studio). The preset reads `$env{VCPKG_ROOT}`, so set `VCPKG_ROOT` to your own vcpkg after opening the prompt, not before.

## The panel (`ui-prisma/`)

Needs Node.js 22.18 or newer (the tests run TypeScript directly).

```
cd ui-prisma
npm ci
node --test tests/*.test.ts
npm run build
```

`npm run build` writes `ui-prisma/dist/`. Prisma UI loads a plain local `index.html`, so a release carries that folder as `Data/PrismaUI/views/HonestWork-Panel/`.

## Papyrus

`Scripts/Source/*.psc` compiles with the Papyrus compiler that ships with the Creation Kit. Besides this repository's source folder, the compiler needs the script sources of everything these scripts extend or call, and none of them are redistributable here:

| Import | Why |
|---|---|
| `<this repo>\Scripts\Source` | this project's scripts |
| `<Skyrim>\Data\Scripts\Source` or `<Skyrim>\Data\Source\Scripts` | vanilla and SKSE script sources |
| SkyUI, PapyrusUtil SE, powerofthree's Papyrus Extender, ConsoleUtilSSE NG, Lodestone | their `Scripts\Source` folders |

```
PapyrusCompiler.exe <script or folder> ^
  -f="TESV_Papyrus_Flags.flg" ^
  -i="<import 1>;<import 2>;..." ^
  -o="<where you want the .pex>"
```

The game paths differ between installs, so they are placeholders. The list is order-independent and the separator is `;`.

## What the author's own tree does differently

The author develops inside a Mod Organizer 2 instance, where this repository sits inside the mod folder and the build writes up into it, so the game loads a build immediately. That is one way of pointing the outputs; nothing in the source depends on it.
