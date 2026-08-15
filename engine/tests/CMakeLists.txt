# Test taxonomy (OB-1-13 §3), exposed as CTest labels so CI can matrix them
# across sanitizers:
#   unit   — pure logic and DSP, fast
#   engine — offline renders through the real Engine::process
#   abi    — boundary layout and lifecycle
#   stress — long/concurrent runs, the TSan and RTSan targets
add_library(onebeat_doctest INTERFACE)
target_include_directories(onebeat_doctest SYSTEM INTERFACE
  ${CMAKE_CURRENT_SOURCE_DIR}/../../third_party/doctest)

# ---------------------------------------------------------------------------
# Plugin fixtures for OB-2-03: real bundles the real helper really dlopens
# ---------------------------------------------------------------------------
# Deliberately *not* linked against onebeat_flags: these are stand-ins for
# third-party code, and third-party code is not built with our warnings, our
# sanitizers or our visibility rules. Building them like our own code would make
# them a friendlier target than the thing they represent.
set(OB_TEST_PLUGIN_DIR ${CMAKE_CURRENT_BINARY_DIR}/test-plugins)

function(onebeat_add_test_plugin name behaviour)
  add_library(${name} MODULE fixtures/test_plugins.cpp)
  target_include_directories(${name} SYSTEM PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../../third_party/clap/include)
  if(NOT behaviour STREQUAL "")
    target_compile_definitions(${name} PRIVATE ${behaviour})
  endif()
  set_target_properties(${name} PROPERTIES
    PREFIX "" SUFFIX ".dylib"
    LIBRARY_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/test-plugin-binaries)

  # A bundle, not a bare dylib, because that is what a scan walks: Contents/
  # MacOS/<binary> plus an Info.plist, which is also what fingerprintBundle
  # reads to decide whether a plugin has changed.
  file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/${name}-Info.plist
"<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<plist version=\"1.0\">
<dict>
  <key>CFBundleExecutable</key><string>${name}</string>
  <key>CFBundleIdentifier</key><string>dev.onebeat.test.${name}</string>
  <key>CFBundlePackageType</key><string>BNDL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
</dict>
</plist>
")
  set(bundle ${OB_TEST_PLUGIN_DIR}/${name}.clap)
  add_custom_command(TARGET ${name} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory ${bundle}/Contents/MacOS
    COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:${name}> ${bundle}/Contents/MacOS/${name}
    COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_BINARY_DIR}/${name}-Info.plist
            ${bundle}/Contents/Info.plist
    VERBATIM)
endfunction()

onebeat_add_test_plugin(ob_test_plugin_ok "")
onebeat_add_test_plugin(ob_test_plugin_gui OB_TEST_PLUGIN_GUI)
onebeat_add_test_plugin(ob_test_plugin_crash OB_TEST_PLUGIN_CRASH)
onebeat_add_test_plugin(ob_test_plugin_hang OB_TEST_PLUGIN_HANG)
onebeat_add_test_plugin(ob_test_plugin_process_crash OB_TEST_PLUGIN_PROCESS_CRASH)
onebeat_add_test_plugin(ob_test_plugin_process_hang OB_TEST_PLUGIN_PROCESS_HANG)

add_executable(onebeat_tests
  test_main.cpp
  test_time_map.cpp
  test_schedule.cpp
  test_rt_primitives.cpp
  test_sampler.cpp
  test_transport.cpp
  test_engine_render.cpp
  test_abi.cpp
  test_model.cpp
  test_model_commands.cpp
  test_note_edit.cpp
  test_flattener.cpp
  test_project_io.cpp
  test_plugin_events.cpp
  test_plugin_model.cpp
  test_clap_hosting.cpp
  test_plugin_scan.cpp
  test_plugin_quarantine.cpp
  test_stress_publish.cpp
)
target_link_libraries(onebeat_tests PRIVATE onebeat_abi onebeat_core onebeat_testing onebeat_doctest)
target_include_directories(onebeat_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/..)

# Paths rather than a search: the tests must exercise *this* build's helper and
# *this* build's fixtures, not whatever happens to be installed.
target_compile_definitions(onebeat_tests PRIVATE
  OB_TEST_PLUGIN_DIR="${OB_TEST_PLUGIN_DIR}"
  OB_STOCK_PIANO="${ONEBEAT_PIANO_BUNDLE}"
  OB_STOCK_GUITAR="${ONEBEAT_GUITAR_BUNDLE}"
  OB_TEST_HELPER="$<TARGET_FILE:onebeat_plugin_host>"
  OB_DEMO_BUNDLE="${CMAKE_CURRENT_SOURCE_DIR}/../../docs/examples/demo.obt")
add_dependencies(onebeat_tests
  onebeat_stock_piano
  onebeat_stock_guitar
  onebeat_plugin_host ob_test_plugin_ok ob_test_plugin_crash ob_test_plugin_hang
  ob_test_plugin_process_crash ob_test_plugin_process_hang ob_test_plugin_gui)

# doctest test-suite names map 1:1 to labels.
foreach(suite unit engine abi stress)
  add_test(NAME ${suite} COMMAND onebeat_tests --test-suite=${suite} --no-intern-signal-handler=1)
  set_tests_properties(${suite} PROPERTIES LABELS ${suite})
endforeach()

# The ABI header must compile as plain C: Dart's ffigen parses it as C, so a
# C++-only construct sneaking in would break binding generation (OB-1-04 AC).
add_test(NAME abi_header_is_c
  COMMAND ${CMAKE_C_COMPILER} -x c -std=c11 -fsyntax-only -Wall -Werror
          ${CMAKE_CURRENT_SOURCE_DIR}/../src/abi/onebeat_abi.h)
set_tests_properties(abi_header_is_c PROPERTIES LABELS abi)
