cmake_minimum_required(VERSION 3.21)

# ---------------------------------------------------------------------------
# Honest Work - Workers of Skyrim - operator panel SKSE plugin
# (CommonLibSSE-NG)
#
# Build layout: CommonLibSSE-NG as a git submodule, the vcpkg toolchain, Visual
# Studio 2022 and the x64-windows-static-md triplet.
#
# This DLL is UI-ONLY: there is no engine/logic split and no hooking (no
# safetyhook dependency). Every game rule lives in Papyrus (Scripts/Source).
# The C++ test targets cover the DLL's own pure rules: the TOML round trip, the
# hotkey modifiers and the dish price. This plugin's only job is to draw the
# Prisma UI screens (D079) and send a Mod Event (Core::ModEventBridge).
# ---------------------------------------------------------------------------

project(
    HonestWork
    VERSION 0.1.0
    LANGUAGES CXX
)

# CommonLibSSE-NG requires C++23.
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ---------------------------------------------------------------------------
# Version.h generated from src/Version.h.in. @ONLY: only expands @VAR@.
# ---------------------------------------------------------------------------
configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/src/Version.h.in"
    "${CMAKE_CURRENT_BINARY_DIR}/generated/Version.h"
    @ONLY
)

# ---------------------------------------------------------------------------
# CommonLibSSE-NG comes from the git submodule at extern/commonlibsse-ng
# (alandtse/CommonLibVR, branch ng), pinned to v6.7.1.
# ---------------------------------------------------------------------------
set(BUILD_TESTS OFF CACHE BOOL "Disable CommonLibSSE-NG tests in consumer" FORCE)

# The mod targets SE 1.5.97 + AE 1.6.x only, no VR (this avoids vendoring
# openvr.h for a platform it never targets).
set(ENABLE_SKYRIM_VR OFF CACHE BOOL "Honest Work does not target VR" FORCE)

add_subdirectory(extern/commonlibsse-ng EXCLUDE_FROM_ALL)

include(extern/commonlibsse-ng/cmake/CommonLibSSE.cmake)

# toml11 - Data/SKSE/Plugins/HonestWork.toml reader (Core/AppConfig.cpp).
# Direct dependency of this project's vcpkg.json.
find_package(toml11 CONFIG REQUIRED)

# nlohmann-json - Data/SKSE/Plugins/HonestWork/{professions,contract_types}/*.json
# directory-scan merge (Core/ProfessionsRegistry.cpp,
# D078). General-purpose library, not a CommonLibSSE-NG API,
# so it is not looked up in the CommonLibSSE-NG headers.
find_package(nlohmann_json CONFIG REQUIRED)

# add_commonlibsse_plugin creates the DLL target, wires up CommonLibSSE
# linkage, and auto-generates the SKSE version boilerplate. Output file will
# be HonestWork.dll. AUTHOR is the public author name.
add_commonlibsse_plugin(
    ${PROJECT_NAME}
    AUTHOR "Awrawra"
    SOURCES
        src/plugin.cpp
        src/PluginDeclaration.cpp
        src/Core/Log.cpp
        src/Core/AppConfig.cpp
        src/Core/ConfigFile.cpp
        src/Core/Settings.cpp
        src/Core/ModEventBridge.cpp
        src/Core/ProfessionsRegistry.cpp
        src/Core/TestChannel.cpp
        src/Core/WorkerNatives.cpp
        src/UI/PrismaPanel.cpp
        src/UI/SettingsPage.cpp
)

# Prisma UI (D079 - replaces SKSE Menu Framework, extern/SKSEMenuFramework/
# retired to _trash/plugin-skse-smf/). extern/PrismaUI/PrismaUI_API.h is a
# vendored, self-contained header (copied verbatim from PrismaUI-SKSE/
# framework tag 1.5.1), same GetProcAddress-at-runtime pattern
# SKSEMenuFramework.h uses - no import .lib, no new build dependency.
target_include_directories(${PROJECT_NAME} PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/extern/PrismaUI"
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
)

# SKSE Menu Framework (Fase 19, D195) - back as an OPTIONAL dependency for the
# settings page only; the panel itself stays on Prisma UI. The vendored header
# is the one Fase 6 used; every export it asks for is in the installed 3.16 DLL except
# AddWindowWithView, which this plugin does not call. Same GetProcAddress-at-
# runtime pattern as PrismaUI_API.h: no import .lib.
target_include_directories(${PROJECT_NAME} PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/extern/SKSEMenuFramework"
)

# Drop the generated SKSE declaration: it cannot express the Address Library
# format 5 flag that SKSE 2.3.1 requires (see src/PluginDeclaration.cpp, D214).
# Leaving both in would fail to link on SKSEPlugin_Version. The build output is
# the check: __HonestWorkPlugin.cpp must NOT appear among the compiled files.
get_target_property(honestwork_sources ${PROJECT_NAME} SOURCES)
list(REMOVE_ITEM honestwork_sources "${CMAKE_CURRENT_BINARY_DIR}/__${PROJECT_NAME}Plugin.cpp")
set_target_properties(${PROJECT_NAME} PROPERTIES SOURCES "${honestwork_sources}")

target_compile_features(${PROJECT_NAME} PRIVATE cxx_std_23)

# PrismaUI_API.h calls GetModuleHandle(L"PrismaUI.dll") (a wide string
# literal), which only resolves to GetModuleHandleW under the standard
# Win32 UNICODE convention - this target did not define it before (the
# SMF header it replaces never hit this code path). Fixing this via a
# compile definition, not by editing the vendored header (D079 - it must
# stay byte-identical to the PrismaUI-SKSE/framework tag 1.5.1 copy).
target_compile_definitions(${PROJECT_NAME} PRIVATE UNICODE _UNICODE)

target_link_libraries(${PROJECT_NAME} PRIVATE
    toml11::toml11
    nlohmann_json::nlohmann_json
)

# Where the generated Version.h is found by #include "Version.h".
target_include_directories(${PROJECT_NAME} PRIVATE
    "${CMAKE_CURRENT_BINARY_DIR}/generated"
)

# PCH.h is mandatory for CommonLibSSE-NG.
target_precompile_headers(${PROJECT_NAME} PRIVATE src/PCH.h)

# ---------------------------------------------------------------------------
# Copies the DLL to this project's own SKSE/Plugins folder after each build
# when HONESTWORK_OUTPUT_FOLDER is set (a cache variable or an environment
# variable; the folder is SKSE\Plugins, plural). Without it nothing is copied.
# ---------------------------------------------------------------------------
if(NOT DEFINED HONESTWORK_OUTPUT_FOLDER AND DEFINED ENV{HONESTWORK_OUTPUT_FOLDER})
    set(HONESTWORK_OUTPUT_FOLDER "$ENV{HONESTWORK_OUTPUT_FOLDER}")
endif()

# ---------------------------------------------------------------------------
# Reproducible build of the shipped DLL.
#
# Without /Brepro the linker stamps the wall clock into the PE TimeDateStamp -
# once in the COFF header and once more in the IMAGE_DEBUG_DIRECTORY entry that
# mirrors it. Two clean builds of identical source then differ, which breaks
# any comparison by hash: a different hash stops proving a different source.
#
# It also defeats the copy_if_different below. Those bytes differ on every
# link, so the deploy never skips - every build rewrites the installed DLL,
# including a build that changed nothing. With the game running that copy hits
# a locked file, and with a measurement in progress it swaps the binary under
# the session that is measuring it.
#
# /Brepro replaces the timestamp with a value derived from the link inputs, so
# rebuilding a given commit reproduces the same bytes.
#
# Applied only to the plugin DLL: it is the distributed artifact. A test
# executable never ships and nobody compares its hash.
#
# Measured (2026-08): two clean builds of identical source differed by 4 bytes
# out of 724992, and every one of them was a timestamp.
# ---------------------------------------------------------------------------
if(MSVC)
    target_link_options(${PROJECT_NAME} PRIVATE "/Brepro")
endif()

if(HONESTWORK_OUTPUT_FOLDER)
    message(STATUS "DLL deploy folder: ${HONESTWORK_OUTPUT_FOLDER}")
    add_custom_command(
        TARGET ${PROJECT_NAME}
        POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E make_directory "${HONESTWORK_OUTPUT_FOLDER}"
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "$<TARGET_FILE:${PROJECT_NAME}>" "${HONESTWORK_OUTPUT_FOLDER}"
        VERBATIM
    )
endif()

# ---------------------------------------------------------------------------
# Fase 19: tests of the DLL's pure rules (plugin-skse/tests/). Core/Settings and
# Core/ConfigFile use no CommonLib, no SKSE and no logger, so they build here
# alone. Run: build/Release/HonestWorkTests.exe (exit code 0 = all passed).
# ---------------------------------------------------------------------------
enable_testing()
add_executable(HonestWorkTests
    tests/test_settings.cpp
    src/Core/Settings.cpp
    src/Core/ConfigFile.cpp
)
target_include_directories(HonestWorkTests PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
target_compile_features(HonestWorkTests PRIVATE cxx_std_23)
target_link_libraries(HonestWorkTests PRIVATE toml11::toml11)
add_test(NAME HonestWorkTests COMMAND HonestWorkTests)

# Fase 33 etapa 8 (D2): Core/DishPrice.h is header-only and pure; its own main
# reads the vectors the Python model is held to.
add_executable(HonestWorkDishTests tests/test_dish_price.cpp)
target_include_directories(HonestWorkDishTests PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
target_compile_features(HonestWorkDishTests PRIVATE cxx_std_23)
target_compile_definitions(HonestWorkDishTests PRIVATE
    DISH_PRICE_VECTORS="${CMAKE_CURRENT_SOURCE_DIR}/tests/fixtures/dish_price_vectors.txt"
    GOLD_ROUNDING_VECTORS="${CMAKE_CURRENT_SOURCE_DIR}/tests/fixtures/gold_rounding_vectors.txt")
add_test(NAME HonestWorkDishTests COMMAND HonestWorkDishTests)
