cmake_minimum_required(VERSION 3.16)
project(ryoku-settings-apply VERSION 0.1.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_C_STANDARD 11)

# Fixed at package time — never from GUI.
set(RYOKU_REPO_PATH "" CACHE STRING "Absolute path to Ryoku OS repository")
set(RYOKU_FLAKE_HOST "" CACHE STRING "Home Manager flake host attribute / desktop user")
set(RYOKU_FLAKE_DIR "" CACHE STRING "Absolute path to distro/flake")
set(RYOKU_HOME_MANAGER "" CACHE STRING "Absolute path to home-manager")
set(RYOKU_NIX_ENV "" CACHE STRING "Absolute path to nix-env")
set(RYOKU_NIX "" CACHE STRING "Absolute path to nix CLI for semantic hash verification")
set(RYOKU_RUNUSER "/usr/sbin/runuser" CACHE STRING "Absolute path to runuser")
set(RYOKU_DBUS_RUN_SESSION "/usr/bin/dbus-run-session" CACHE STRING "Absolute path to dbus-run-session")

if(RYOKU_REPO_PATH STREQUAL "")
  message(FATAL_ERROR "RYOKU_REPO_PATH is required")
endif()
if(NOT RYOKU_FLAKE_HOST MATCHES "^[A-Za-z0-9_-]+$")
  message(FATAL_ERROR "RYOKU_FLAKE_HOST must be a flake host attribute ([A-Za-z0-9_-]+)")
endif()
if(RYOKU_FLAKE_DIR STREQUAL "")
  message(FATAL_ERROR "RYOKU_FLAKE_DIR is required")
endif()
if(RYOKU_HOME_MANAGER STREQUAL "")
  message(FATAL_ERROR "RYOKU_HOME_MANAGER is required")
endif()
if(RYOKU_NIX_ENV STREQUAL "")
  message(FATAL_ERROR "RYOKU_NIX_ENV is required")
endif()
if(RYOKU_NIX STREQUAL "")
  message(FATAL_ERROR "RYOKU_NIX is required")
endif()

add_executable(ryoku-settings-apply
  src/main.cpp
  src/ops.c
  src/ops.h
)

target_compile_definitions(ryoku-settings-apply PRIVATE
  "RYOKU_REPO_PATH=\"${RYOKU_REPO_PATH}\""
  "RYOKU_FLAKE_HOST=\"${RYOKU_FLAKE_HOST}\""
  "RYOKU_FLAKE_DIR=\"${RYOKU_FLAKE_DIR}\""
  "RYOKU_HOME_MANAGER=\"${RYOKU_HOME_MANAGER}\""
  "RYOKU_NIX_ENV=\"${RYOKU_NIX_ENV}\""
  "RYOKU_NIX=\"${RYOKU_NIX}\""
  "RYOKU_RUNUSER=\"${RYOKU_RUNUSER}\""
  "RYOKU_DBUS_RUN_SESSION=\"${RYOKU_DBUS_RUN_SESSION}\""
)

install(TARGETS ryoku-settings-apply RUNTIME DESTINATION bin)
