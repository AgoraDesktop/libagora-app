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

# THE APPkit STACK'S OWN THREE, IN APPLE'S OWN ORDER: Foundation under everything, Core Graphics for what a
# window draws with, Core Text for what a font is. A PUBLIC link for each, because the AppKit HEADERS name
# their types -- NSColor.h includes CoreGraphics, NSFont.h names CTFontRef -- so a consumer of this library
# reaches all three itself.
# AND THE RUNTIME ITSELF: this is an Objective-C library, so a consumer that has ObjC code of its own needs
# `libobjc` on ITS link line -- a shared library's private dependencies are not propagated, and the failure is
# "DSO missing from command line" at the consumer, not here.
find_package(libobjc CONFIG REQUIRED)          # -> objc
find_package(Foundation CONFIG REQUIRED)
find_package(AgoraDrawing CONFIG REQUIRED)
find_package(AgoraText CONFIG REQUIRED)

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
# Include shim: these headers are included as <AppKit/...>, which is how
# Apple's own include each other and how a consumer writes them.
# ---------------------------------------------------------------------------
set(_agora_include_dir "${CMAKE_BINARY_DIR}/agora-include")
file(REMOVE_RECURSE "${_agora_include_dir}")
file(MAKE_DIRECTORY "${_agora_include_dir}")
file(CREATE_LINK "${CMAKE_CURRENT_SOURCE_DIR}" "${_agora_include_dir}/AppKit" SYMBOLIC)

# ---------------------------------------------------------------------------
# AGORA'S OWN WINDOW-MANAGEMENT PROTOCOL
#
# The contract is window-server's (`protocol/agora-shell.xml`) — one component's own file, read here from the
# sibling source tree. **THAT IS A DEVIATION AND IT IS RECORDED RATHER THAN HIDDEN**: this project's rule is that
# a component consumes another only as that component's BUILT OUTPUT, and a protocol is exactly the thing that
# should be installed as one. It is read from source for now because window-server installs nothing yet, and a
# COPY would be worse — two sources of truth for one contract, drifting. When window-server grows an install rule
# for its protocol, this becomes a `find_package`.
# ---------------------------------------------------------------------------
set(AGORA_SHELL_XML "${CMAKE_CURRENT_SOURCE_DIR}/../window-server/protocol/agora-shell.xml")
add_custom_command(
  OUTPUT "${_generated}/agora-shell-client-protocol.h"
  COMMAND ${WAYLAND_SCANNER} client-header "${AGORA_SHELL_XML}" "${_generated}/agora-shell-client-protocol.h"
  DEPENDS "${AGORA_SHELL_XML}" VERBATIM)
add_custom_command(
  OUTPUT "${_generated}/agora-shell-protocol.c"
  COMMAND ${WAYLAND_SCANNER} private-code "${AGORA_SHELL_XML}" "${_generated}/agora-shell-protocol.c"
  DEPENDS "${AGORA_SHELL_XML}" VERBATIM)
add_custom_target(agora-shell-bindings
  DEPENDS
    "${_generated}/agora-shell-client-protocol.h"
    "${_generated}/agora-shell-protocol.c")

# ---------------------------------------------------------------------------
# The library
# ---------------------------------------------------------------------------
file(GLOB APP_SOURCES CONFIGURE_DEPENDS
  "${CMAKE_CURRENT_SOURCE_DIR}/*.m"
  "${CMAKE_CURRENT_SOURCE_DIR}/*.c"
  "${CMAKE_CURRENT_SOURCE_DIR}/platform/*.c")

add_library(App SHARED
  ${APP_SOURCES}
  "${_generated}/xdg-shell-protocol.c"
  "${_generated}/agora-shell-protocol.c")

add_dependencies(App xdg-shell-bindings agora-shell-bindings)

set_target_properties(App PROPERTIES OUTPUT_NAME agora-app)

target_include_directories(App
  PUBLIC
    "$<BUILD_INTERFACE:${_agora_include_dir}>"
    "$<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/platform>"
    "$<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>"
  PRIVATE
    "${_generated}"
    "${CMAKE_CURRENT_SOURCE_DIR}/platform")

target_link_libraries(App
  PUBLIC
    objc
    Foundation::Foundation
    AgoraDrawing::Drawing
    AgoraText::Text
  PRIVATE
    PkgConfig::WAYLAND_CLIENT
    PkgConfig::XKBCOMMON)

enable_testing()
add_subdirectory(tests)

# ---------------------------------------------------------------------------
# Install rules: the library, its headers, its data, and a CMake package
#
# libagora-app INSTALLED NOTHING, so the release build had nothing to stage for
# it and no package could carry the Application Kit. This is one component with
# one target; the shape is libagora-drawing's, so a consumer learns one idiom.
# ---------------------------------------------------------------------------

file(GLOB APP_PUBLIC_HEADERS CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/*.h")

install(FILES ${APP_PUBLIC_HEADERS}
    DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/AppKit)
install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/platform/"
    DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/AppKit/platform
    FILES_MATCHING PATTERN "*.h")

install(TARGETS App
    EXPORT AgoraAppTargets
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})

include(CMakePackageConfigHelpers)

install(EXPORT AgoraAppTargets
    FILE AgoraAppTargets.cmake
    NAMESPACE AgoraApp::
    DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/AgoraApp)

configure_package_config_file(cmake/AgoraAppConfig.cmake.in
    ${CMAKE_CURRENT_BINARY_DIR}/AgoraAppConfig.cmake
    INSTALL_DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/AgoraApp)
write_basic_package_version_file(
    ${CMAKE_CURRENT_BINARY_DIR}/AgoraAppConfigVersion.cmake
    VERSION 1.0.0
    COMPATIBILITY SameMajorVersion)
install(FILES
    ${CMAKE_CURRENT_BINARY_DIR}/AgoraAppConfig.cmake
    ${CMAKE_CURRENT_BINARY_DIR}/AgoraAppConfigVersion.cmake
    DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/AgoraApp)

# THE CHROME THEME IS DELIBERATELY NOT INSTALLED. A theme is external work under
# its own licence -- the one this was built against is GPL -- and this tree
# excludes GPL, so `themes/` is gitignored and never ships. libagora-app reads a
# theme from $AGORA_CHROME_THEME or the user's XDG data directory, and falls back
# to the marks NSWindow draws when there is none.
