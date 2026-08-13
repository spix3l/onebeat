cmake_minimum_required(VERSION 3.28)
project(onebeat_engine VERSION 0.2.0 LANGUAGES C CXX)
if(APPLE)
  enable_language(OBJCXX)
endif()

# The engine builds standalone: no Flutter, no app, no network. `cmake -S engine
# -B build && cmake --build build` is the whole story (OB-1-01).

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_C_STANDARD 11)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE RelWithDebInfo CACHE STRING "" FORCE)
endif()

option(ONEBEAT_ASAN "Build with AddressSanitizer + UndefinedBehaviorSanitizer" OFF)
option(ONEBEAT_TSAN "Build with ThreadSanitizer" OFF)
option(ONEBEAT_RTSAN "Build with RealtimeSanitizer (needs LLVM >= 20; Xcode clang has no RTSan)" OFF)
option(ONEBEAT_WERROR "Promote warnings to errors" ON)

set(ONEBEAT_THIRD_PARTY ${CMAKE_CURRENT_SOURCE_DIR}/../third_party)

# ---------------------------------------------------------------------------
# Vendored dependencies (header-only, permissive licences — see OB-1-02 audit)
# ---------------------------------------------------------------------------
add_library(onebeat_third_party INTERFACE)
target_include_directories(onebeat_third_party SYSTEM INTERFACE
  ${ONEBEAT_THIRD_PARTY}/dr_libs
  ${ONEBEAT_THIRD_PARTY}/clap/include
)

# ---------------------------------------------------------------------------
# Warning / sanitizer discipline (NFR-08)
# ---------------------------------------------------------------------------
add_library(onebeat_flags INTERFACE)
target_compile_options(onebeat_flags INTERFACE
  -Wall -Wextra -Wpedantic
  -Wshadow -Wnon-virtual-dtor -Wold-style-cast -Wcast-align -Wunused
  -Woverloaded-virtual -Wconversion -Wsign-conversion -Wdouble-promotion
  # The compile-time half of the RT contract: every [[clang::nonblocking]]
  # function is proved allocation-, lock- and exception-free at build time.
  -Wfunction-effects
)
if(ONEBEAT_WERROR)
  target_compile_options(onebeat_flags INTERFACE -Werror)
endif()

if(ONEBEAT_ASAN)
  target_compile_definitions(onebeat_flags INTERFACE ONEBEAT_SANITIZER_BUILD=1)
  target_compile_options(onebeat_flags INTERFACE -fsanitize=address,undefined -fno-omit-frame-pointer)
  target_link_options(onebeat_flags INTERFACE -fsanitize=address,undefined)
endif()
if(ONEBEAT_TSAN)
  target_compile_definitions(onebeat_flags INTERFACE ONEBEAT_SANITIZER_BUILD=1)
  target_compile_options(onebeat_flags INTERFACE -fsanitize=thread -fno-omit-frame-pointer)
  target_link_options(onebeat_flags INTERFACE -fsanitize=thread)
endif()
if(ONEBEAT_RTSAN)
  target_compile_definitions(onebeat_flags INTERFACE ONEBEAT_SANITIZER_BUILD=1)
  # The probe must compile *and link*, with the flag on both command lines:
  # -fsanitize=realtime pulls in a runtime library, so a compile-only check
  # fails with undefined symbols even on a toolchain that fully supports RTSan.
  include(CheckCXXSourceCompiles)
  set(CMAKE_REQUIRED_FLAGS "-fsanitize=realtime")
  set(CMAKE_REQUIRED_LINK_OPTIONS "-fsanitize=realtime")
  check_cxx_source_compiles("int main() { return 0; }" ONEBEAT_HAVE_RTSAN)
  unset(CMAKE_REQUIRED_FLAGS)
  unset(CMAKE_REQUIRED_LINK_OPTIONS)
  if(NOT ONEBEAT_HAVE_RTSAN)
    message(FATAL_ERROR
      "This toolchain has no RealtimeSanitizer. Xcode's clang does not ship it; "
      "use Homebrew LLVM >= 20:\n"
      "  brew install llvm\n"
      "  cmake -S engine -B build-rtsan -DONEBEAT_RTSAN=ON \\\n"
      "        -DCMAKE_CXX_COMPILER=$(brew --prefix llvm)/bin/clang++ \\\n"
      "        -DCMAKE_C_COMPILER=$(brew --prefix llvm)/bin/clang")
  endif()
  target_compile_options(onebeat_flags INTERFACE -fsanitize=realtime)
  target_link_options(onebeat_flags INTERFACE -fsanitize=realtime)
endif()

# ---------------------------------------------------------------------------
# Platform sources — the only place platform code is named (NFR-11)
# ---------------------------------------------------------------------------
if(APPLE)
  set(ONEBEAT_PLATFORM_SOURCES src/audio_io/coreaudio/coreaudio_device.cpp)
  if(ONEBEAT_ASAN OR ONEBEAT_TSAN OR ONEBEAT_RTSAN)
    set(ONEBEAT_EDITOR_SOURCE src/plugin/clap/clap_editor_stub.cpp)
  else()
    set(ONEBEAT_EDITOR_SOURCE src/plugin/clap/clap_editor_mac.mm)
  endif()
  set(ONEBEAT_PLATFORM_LIBS
    "-framework CoreAudio" "-framework AudioToolbox" "-framework CoreFoundation"
    "-framework AppKit" "-framework QuartzCore")
else()
  message(FATAL_ERROR "OneBeat v0.1 targets macOS. Windows/Linux backends are a v2 port: "
                      "add engine/src/audio_io/<platform>/ and implement createPlatformAudioDevice().")
endif()

# ---------------------------------------------------------------------------
# The engine core (static, so both the dylib and the tests link one copy)
# ---------------------------------------------------------------------------
add_library(onebeat_core STATIC
  src/core/engine.cpp
  src/core/schedule.cpp
  src/core/sampler.cpp
  src/core/wav_loader.cpp
  src/core/diagnostics.cpp
  src/core/rt/rt.cpp
  src/core/rt/rt_log.cpp
  src/model/ids.cpp
  src/model/json.cpp
  src/model/project.cpp
  src/model/command.cpp
  src/model/commands.cpp
  src/model/note_edit.cpp
  src/model/flattener.cpp
  src/model/invariants.cpp
  src/model/project_io.cpp
  src/plugin/plugin_types.cpp
  src/plugin/clap/clap_plugin_instance.cpp
  ${ONEBEAT_EDITOR_SOURCE}
  src/plugin/sandbox/sandboxed_plugin_proxy.cpp
  src/plugin/sandbox/runtime_host.cpp
  src/plugin/builtin/sampler_plugin.cpp
  src/plugin/scan/descriptor.cpp
  src/plugin/scan/plugin_cache.cpp
  src/plugin/scan/plugin_library.cpp
  src/plugin/scan/scanner.cpp
  src/plugin/scan/subprocess_probe.cpp
  src/audio_io/null/null_device.cpp
  ${ONEBEAT_PLATFORM_SOURCES}
)
target_include_directories(onebeat_core PUBLIC src)
target_link_libraries(onebeat_core PUBLIC onebeat_third_party onebeat_flags ${ONEBEAT_PLATFORM_LIBS})
set_target_properties(onebeat_core PROPERTIES CXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN ON)

# ---------------------------------------------------------------------------
# The shipped dylib: only the extern "C" ABI is visible (OB-1-01)
# ---------------------------------------------------------------------------
# An OBJECT library so both the dylib and the test binary get the same ABI
# implementation, and so the linker cannot drop objects nothing references.
add_library(onebeat_abi OBJECT src/abi/onebeat_abi.cpp)
target_link_libraries(onebeat_abi PUBLIC onebeat_core)

add_library(onebeat_engine SHARED $<TARGET_OBJECTS:onebeat_abi>)
target_link_libraries(onebeat_engine PRIVATE onebeat_core)
target_include_directories(onebeat_engine PUBLIC src)
set_target_properties(onebeat_engine PROPERTIES
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN ON
  MACOSX_RPATH ON
  OUTPUT_NAME onebeat_engine
)

# ---------------------------------------------------------------------------
# Stock plug-ins
# ---------------------------------------------------------------------------
# These are real CLAP bundles, not privileged engine classes. Keeping the stock
# piano on the public hosting path prevents first-party-only assumptions from
# creeping into the plug-in model and gives a clean install one playable
# instrument without writing into the user's global CLAP directory.
set(ONEBEAT_STOCK_PLUGIN_DIR ${CMAKE_BINARY_DIR}/stock-plugins)
add_library(onebeat_stock_piano MODULE
  stock_plugins/piano/piano_clap.cpp
  stock_plugins/piano/piano_engine.cpp)
target_include_directories(onebeat_stock_piano SYSTEM PRIVATE
  ${ONEBEAT_THIRD_PARTY}/clap/include)
target_link_libraries(onebeat_stock_piano PRIVATE onebeat_flags)
set_target_properties(onebeat_stock_piano PROPERTIES
  PREFIX ""
  SUFFIX ".dylib"
  OUTPUT_NAME "OneBeat Piano"
  LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/stock-plugin-binaries
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN ON)

set(ONEBEAT_PIANO_BUNDLE "${ONEBEAT_STOCK_PLUGIN_DIR}/OneBeat Piano.clap")
file(WRITE "${CMAKE_BINARY_DIR}/OneBeatPiano-Info.plist"
"<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<plist version=\"1.0\">
<dict>
  <key>CFBundleExecutable</key><string>OneBeat Piano</string>
  <key>CFBundleIdentifier</key><string>dev.onebeat.stock.piano</string>
  <key>CFBundleName</key><string>OneBeat Piano</string>
  <key>CFBundlePackageType</key><string>BNDL</string>
  <key>CFBundleShortVersionString</key><string>${PROJECT_VERSION}</string>
  <key>CFBundleVersion</key><string>${PROJECT_VERSION}</string>
</dict>
</plist>
")
add_custom_command(TARGET onebeat_stock_piano POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E make_directory "${ONEBEAT_PIANO_BUNDLE}/Contents/MacOS"
  COMMAND ${CMAKE_COMMAND} -E copy "$<TARGET_FILE:onebeat_stock_piano>"
          "${ONEBEAT_PIANO_BUNDLE}/Contents/MacOS/OneBeat Piano"
  COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_BINARY_DIR}/OneBeatPiano-Info.plist"
          "${ONEBEAT_PIANO_BUNDLE}/Contents/Info.plist"
  VERBATIM)

# ---------------------------------------------------------------------------
# Test harness + tests
# ---------------------------------------------------------------------------
add_library(onebeat_testing STATIC testing/offline_driver.cpp)
target_include_directories(onebeat_testing PUBLIC . src)
target_link_libraries(onebeat_testing PUBLIC onebeat_core)

# A terminal driver for the engine: hear sound, list devices, sweep formats and
# render offline without the app (used by the stage exit checklist).
add_executable(onebeat_devtool tools/devtool.cpp)
target_link_libraries(onebeat_devtool PRIVATE onebeat_core onebeat_testing)

# ---------------------------------------------------------------------------
# The helper process (OB-2-03; OB-2-05 §1 and §6)
# ---------------------------------------------------------------------------
# The only executable in the project allowed to load third-party code. It ships
# beside the dylib, which is how `SubprocessProbe::discoverHelperPath()` finds
# it — keep them together in every bundle layout (`tools/build.sh`, OB-2-06).
add_executable(onebeat_plugin_host src/host/host_main.cpp)
target_link_libraries(onebeat_plugin_host PRIVATE onebeat_core)
set_target_properties(onebeat_plugin_host PROPERTIES
  OUTPUT_NAME onebeat-plugin-host
  RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR})

enable_testing()
add_subdirectory(tests)
