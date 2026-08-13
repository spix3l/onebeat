# Test taxonomy (OB-1-13 §3), exposed as CTest labels so CI can matrix them
# across sanitizers:
#   unit   — pure logic and DSP, fast
#   engine — offline renders through the real Engine::process
#   abi    — boundary layout and lifecycle
#   stress — long/concurrent runs, the TSan and RTSan targets
add_library(onebeat_doctest INTERFACE)
target_include_directories(onebeat_doctest SYSTEM INTERFACE
  ${CMAKE_CURRENT_SOURCE_DIR}/../../third_party/doctest)

add_executable(onebeat_tests
  test_main.cpp
  test_time_map.cpp
  test_schedule.cpp
  test_rt_primitives.cpp
  test_sampler.cpp
  test_transport.cpp
  test_engine_render.cpp
  test_abi.cpp
  test_plugin_events.cpp
  test_plugin_model.cpp
  test_stress_publish.cpp
)
target_link_libraries(onebeat_tests PRIVATE onebeat_abi onebeat_core onebeat_testing onebeat_doctest)
target_include_directories(onebeat_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/..)

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
