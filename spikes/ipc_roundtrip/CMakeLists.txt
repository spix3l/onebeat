cmake_minimum_required(VERSION 3.28)
project(ob204_ipc_roundtrip LANGUAGES CXX)

# Standalone on purpose: this measures the IPC mechanism, so it links nothing
# from the engine. Build it with
#   cmake -S spikes/ipc_roundtrip -B spikes/ipc_roundtrip/build -DCMAKE_BUILD_TYPE=Release
#   cmake --build spikes/ipc_roundtrip/build

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

add_executable(ob204_host host.cpp)
add_executable(ob204_helper helper.cpp)
foreach(t ob204_host ob204_helper)
  target_include_directories(${t} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
  target_compile_options(${t} PRIVATE -Wall -Wextra -Wpedantic)
endforeach()
