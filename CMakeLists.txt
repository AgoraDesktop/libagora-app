#===----------------------------------------------------------------------===#
#
# Agora's build for the Application Kit (libagora-app).
#
# THE FIRST CODE HERE IS NOT APPkit -- it is the seam AppKit's windows sit on. `NSWindow` has to put pixels
# on a screen and get events back, and it must not know how; the Fiwix import it comes from knows, because
# it calls XOpenDisplay, XCreateSimpleWindow, XMapWindow, XPutImage and XNextEvent directly. Agora's target
# is Wayland with no X11-native target, so those calls go and `platform/AGWindowServer.h` replaces them --
# an interface, with an `xdg-shell` client as its FIRST implementation rather than as a hard dependency
# (see the header for why `xdg-shell` is the bootstrap protocol and not the destination).
#
# THE PROTOCOL BINDINGS ARE GENERATED, NOT VENDORED. xdg-shell's client code is generated from the system's
# `wayland-protocols` by `wayland-scanner` at build time: it is generated code, and checking in a copy would
# silently age against the protocol on the machine. `wayland-client` and `xkbcommon` are system libraries,
# on the same terms as ICU and OpenSSL elsewhere in Agora -- neither is vendored or pinned.
#
# THE APPkit SOURCES ARRIVE NEXT (NSWindow, NSView, NSApplication and the rest of the Fiwix import), and
# they are added to the SAME target: this is one component, and the seam is its platform layer, not a
# separate library.
#
#===----------------------------------------------------------------------===#

cmake_minimum_required(VERSION 3.24)

project(AgoraApp LANGUAGES C OBJC)

include(GNUInstallDirs)

set(CMAKE_POSITION_INDEPENDENT_CODE YES)
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

find_package(PkgConfig REQUIRED)
pkg_check_modules(WAYLAND_CLIENT REQUIRED IMPORTED_TARGET wayland-client)
pkg_check_modules(XKBCOMMON REQUIRED IMPORTED_TARGET xkbcommon)
find_program(WAYLAND_SCANNER wayland-scanner REQUIRED)

# ---------------------------------------------------------------------------
# xdg-shell: generated from the system's protocol XML
# ---------------------------------------------------------------------------
find_file(XDG_SHELL_XML
  NAMES xdg-shell.xml
  PATHS /usr/share/wayland-protocols/stable/xdg-shell
  NO_DEFAULT_PATH REQUIRED)

set(_generated "${CMAKE_CURRENT_BINARY_DIR}/generated")
file(MAKE_DIRECTORY "${_generated}")

add_custom_command(
  OUTPUT "${_generated}/xdg-shell-client-protocol.h"
  COMMAND ${WAYLAND_SCANNER} client-header "${XDG_SHELL_XML}" "${_generated}/xdg-shell-client-protocol.h"
  DEPENDS "${XDG_SHELL_XML}"
  VERBATIM)
add_custom_command(
  OUTPUT "${_generated}/xdg-shell-protocol.c"
  COMMAND ${WAYLAND_SCANNER} private-code "${XDG_SHELL_XML}" "${_generated}/xdg-shell-protocol.c"
  DEPENDS "${XDG_SHELL_XML}"
  VERBATIM)

# BOTH outputs have to exist before anything compiles, and only the .c is a source file: without a target
# that names the HEADER too, the header's custom command never runs and the backend cannot include it.
add_custom_target(xdg-shell-bindings
  DEPENDS
    "${_generated}/xdg-shell-client-protocol.h"
    "${_generated}/xdg-shell-protocol.c")

# ---------------------------------------------------------------------------
# The library
# ---------------------------------------------------------------------------
file(GLOB APP_SOURCES CONFIGURE_DEPENDS
  "${CMAKE_CURRENT_SOURCE_DIR}/*.m"
  "${CMAKE_CURRENT_SOURCE_DIR}/*.c"
  "${CMAKE_CURRENT_SOURCE_DIR}/platform/*.c")

add_library(App SHARED
  ${APP_SOURCES}
  "${_generated}/xdg-shell-protocol.c")

add_dependencies(App xdg-shell-bindings)

set_target_properties(App PROPERTIES OUTPUT_NAME agora-app)

target_include_directories(App
  PUBLIC
    "$<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/platform>"
    "$<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>"
  PRIVATE
    "${_generated}"
    "${CMAKE_CURRENT_SOURCE_DIR}/platform")

target_link_libraries(App
  PRIVATE
    PkgConfig::WAYLAND_CLIENT
    PkgConfig::XKBCOMMON)

enable_testing()
add_subdirectory(tests)
