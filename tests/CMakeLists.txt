# libagora-app's tests.
#
# `keyboard` needs nothing but a keymap, so it always runs. `window` needs a COMPOSITOR, which is a property
# of the machine and not of the code, so its wrapper SKIPS with a message rather than failing when no
# compositor can be started -- a test that fails for want of a display teaches nothing and gets muted.

# The tests link the whole AppKit, whose dependencies live in the install prefix; DT_RUNPATH is NOT inherited
# by a dependency, so the prefix's lib directory has to be on LD_LIBRARY_PATH for the transitive hops to
# resolve. The directory comes from an imported target rather than being written down.
set(_agora_app_test_env "LD_LIBRARY_PATH=$<TARGET_FILE_DIR:Foundation::Foundation>:$<TARGET_FILE_DIR:App>")

add_executable(keyboard keyboard.c)
target_link_libraries(keyboard PRIVATE App PkgConfig::XKBCOMMON)

add_test(NAME keyboard COMMAND keyboard)
set_tests_properties(keyboard PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

add_executable(window window.c)
target_link_libraries(window PRIVATE App)

# The window test drives the seam against a headless compositor and asserts the FRAME COUNT: 0 means the
# configure/present path is broken, and more than asked for means more than one frame callback is in flight.
add_test(NAME window-headless
  COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/run-window-headless.sh" "$<TARGET_FILE:window>" 60)
set_tests_properties(window-headless PROPERTIES SKIP_RETURN_CODE 77
  ENVIRONMENT "${_agora_app_test_env}")

# THE APPkit ITSELF: a real NSWindow with a real NSView, pumped through NSApplication. This is the test that
# says the port works, because it never touches the seam directly.
add_executable(appkit_window appkit_window.m)
target_link_libraries(appkit_window PRIVATE App)

# **THE DRAWING HALF, VERIFIED WITHOUT A DISPLAY.** No compositor, no window and no run loop: a bitmap rep, a
# graphics context over it, and the cell's own geometry door as the check on where the ink landed. It can therefore
# run anywhere, which is what a test of "does this door draw" should be.
add_executable(menu_cell_ink menu_cell_ink.m)
target_link_libraries(menu_cell_ink PRIVATE App)
add_test(NAME appkit-menu-cell-ink COMMAND menu_cell_ink)

# **THE CLASS THAT CALLS THE CELLS.** One row per item, in order, with the highlighted one distinguished — the
# arrangement `NSMenuItemCell` had no caller to provide.
# **A MENU ON A DISPLAY, FOR A PERSON TO LOOK AT.** Not a ctest: it needs a desktop and it is a demonstration
# rather than an assertion. Run it nested against Agora's own window server, which grabs nothing.
add_executable(appkit_menu_draw appkit_menu_draw.m)
target_link_libraries(appkit_menu_draw PRIVATE App)

add_executable(menu_view_ink menu_view_ink.m)
target_link_libraries(menu_view_ink PRIVATE App)
add_test(NAME appkit-menu-view-ink COMMAND menu_view_ink)
set_tests_properties(appkit-menu-view-ink PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE CLASS THAT CALLS THE CELLS.** One row per item, in order, with the highlighted one distinguished — the
# arrangement `NSMenuItemCell` had no caller to provide.
# It gets its own ctest, and the run takes seconds rather than frames: NSWindow's pump waits on the
# compositor's frame callbacks rather than counting them.
add_test(NAME appkit-window-headless
  COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/run-appkit-headless.sh" "$<TARGET_FILE:appkit_window>" 3)
set_tests_properties(appkit-window-headless PROPERTIES SKIP_RETURN_CODE 77
  ENVIRONMENT "${_agora_app_test_env}")

# **THE APPkit AGAINST AGORA'S OWN WINDOW SERVER**, which is the only one that can answer `-visibleFrame`. The
# sibling's binary is an OPTION rather than a requirement: a component's tests must not need another component's
# build to be present, so this SKIPS when there is nothing to run against.
set(AGORA_WINDOW_SERVER_BINARY "${CMAKE_CURRENT_SOURCE_DIR}/../../window-server/build/window-server"
    CACHE FILEPATH "window-server's built binary, for the tests that need a compositor of our own")

add_test(NAME appkit-work-area
  COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/run-appkit-agora.sh"
	  "$<TARGET_FILE:appkit_window>" "${AGORA_WINDOW_SERVER_BINARY}" 3 24)
set_tests_properties(appkit-work-area PROPERTIES SKIP_RETURN_CODE 77
  ENVIRONMENT "${_agora_app_test_env}")

# AND THE INPUT PATH: the seam's event, through NSWindow, to the view that should get it. The headless
# compositor has no seat, so this test builds the AGEvents a compositor would have sent and pushes them
# through the window's own door -- the link that is NOT synthetic is the one a configure event already proves.
add_executable(appkit_events appkit_events.m)
target_link_libraries(appkit_events PRIVATE App)

add_test(NAME appkit-events-headless
  COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/run-appkit-headless.sh" "$<TARGET_FILE:appkit_events>" 2
	  "all checks passed" )
set_tests_properties(appkit-events-headless PROPERTIES SKIP_RETURN_CODE 77
  ENVIRONMENT "${_agora_app_test_env}")
