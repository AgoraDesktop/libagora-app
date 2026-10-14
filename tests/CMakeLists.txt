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
# **THE OTHER NUMBER THE SERVER OWNS.** The work area is one question and the bar's usable region is another;
# this asserts they get two different answers, against a compositor that speaks `agora_shell`.
add_executable(menubar_area menubar_area.c)
target_link_libraries(menubar_area PRIVATE App)
add_test(NAME seam-menubar-area
  COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/run-menubar-area.sh"
	  "$<TARGET_FILE:menubar_area>" "${AGORA_WINDOW_SERVER_BINARY}")
set_tests_properties(seam-menubar-area PROPERTIES SKIP_RETURN_CODE 77
  ENVIRONMENT "${_agora_app_test_env}")

add_executable(menu_cell_ink menu_cell_ink.m)
target_link_libraries(menu_cell_ink PRIVATE App)
add_test(NAME appkit-menu-cell-ink COMMAND menu_cell_ink)
# The seam's libraries live in the install prefix and RUNPATH does NOT apply to a transitive dependency, so a
# test that links only the AppKit still has to be told where the prefix's lib directory is — the same reason
# every other test here sets it. Without this the loader cannot find libagora-dispatch.so and the test fails
# before main runs, which reads as a broken cell rather than a missing path.
set_tests_properties(appkit-menu-cell-ink PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE CLASS THAT CALLS THE CELLS.** One row per item, in order, with the highlighted one distinguished — the
# arrangement `NSMenuItemCell` had no caller to provide.
# **A MENU ON A DISPLAY, FOR A PERSON TO LOOK AT.** Not a ctest: it needs a desktop and it is a demonstration
# rather than an assertion. Run it nested against Agora's own window server, which grabs nothing.
add_executable(appkit_menu_draw appkit_menu_draw.m)
target_link_libraries(appkit_menu_draw PRIVATE App)

# **A WINDOW FULL OF CONTROLS, FOR A PERSON TO LOOK AT.** Not a ctest: it needs a display and it is a demonstration
# rather than an assertion. It is what found the subview-placement defect in `NSView -displayRect:`.
add_executable(appkit_controls_draw appkit_controls_draw.m)
target_link_libraries(appkit_controls_draw PRIVATE App)

add_executable(menu_view_ink menu_view_ink.m)
target_link_libraries(menu_view_ink PRIVATE App)
add_test(NAME appkit-menu-view-ink COMMAND menu_view_ink)

# **THE CONTROL LAYER: A VIEW THAT DELEGATES ITS FACE TO A CELL.** Offscreen, and the claim is the INK — a button's
# bezel and title, a switch's indicator, the value doors forwarding, and `-performClick:` reaching the target.
add_executable(control_ink control_ink.m)
target_link_libraries(control_ink PRIVATE App)
add_test(NAME appkit-control-ink COMMAND control_ink)
set_tests_properties(appkit-control-ink PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# THE NEXT CONTROL: a slider is the first whose VALUE is a position rather than a state, so its probe is the one that
# has to measure the geometry's two directions and not just the ink.
add_executable(slider_ink slider_ink.m)
target_link_libraries(slider_ink PRIVATE App m)
add_test(NAME appkit-slider-ink COMMAND slider_ink)
set_tests_properties(appkit-slider-ink PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# AND THE TRACKING AREA: the class that replaced the window's blanket enter/exit synthesis, and whose SCOPE word is
# what keeps a background window's controls from lighting up.
add_executable(tracking_area tracking_area.m)
target_link_libraries(tracking_area PRIVATE App m)
add_test(NAME appkit-tracking-area COMMAND tracking_area)
set_tests_properties(appkit-tracking-area PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# AND THE METRICS: a push button's height is a control METRIC and a line of text is a plausible height. Both halves
# are one defect chain, so they are one probe — see the file's own header for why the order matters.
add_executable(control_metrics control_metrics.m)
target_link_libraries(control_metrics PRIVATE App m)
add_test(NAME appkit-control-metrics COMMAND control_metrics)
set_tests_properties(appkit-control-metrics PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# AND TEXT INPUT: the first slice of the text system, driven the way a window drives it — an NSEvent turned into a
# command by -interpretKeyEvents:, and the command editing the string.
add_executable(text_input text_input.m)
target_link_libraries(text_input PRIVATE App m)
add_test(NAME appkit-text-input COMMAND text_input)
set_tests_properties(appkit-text-input PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE DISPLAY PATH.** The ink tests are all offscreen; this one puts a menu's window on a headless
# compositor and reads the COMPOSITOR'S OWN FRAMEBUFFER back, which is the only place the present can be seen.
# It skips when there is no window server, so a component's tests still do not need a sibling's build.
add_test(NAME appkit-menu-headless
  COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/run-menu-headless.sh"
	  "$<TARGET_FILE:appkit_menu_draw>" "${AGORA_WINDOW_SERVER_BINARY}" 3 60)
set_tests_properties(appkit-menu-headless PROPERTIES SKIP_RETURN_CODE 77
  ENVIRONMENT "${_agora_app_test_env}")
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

# **ONLY THE ACTIVE APPLICATION'S MENUS SHOW.** The compositor already says which CLIENT has the keyboard, so an
# application knows when it is in front without a protocol of its own; this asserts that the menu bar window is
# shown while active and HIDDEN when deactivated. It needs Agora's own server, since the menu bar is its strip.
add_executable(appkit_activation appkit_activation.m)
target_link_libraries(appkit_activation PRIVATE App)
add_test(NAME appkit-menu-activation
  COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/run-activation-headless.sh"
	  "$<TARGET_FILE:appkit_activation>" "${AGORA_WINDOW_SERVER_BINARY}" 3)
set_tests_properties(appkit-menu-activation PROPERTIES SKIP_RETURN_CODE 77
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

# AND THE CHROME: Agora's title bar is an X, a minus and a plus drawn in one ink, a centred bold title, and a pill
# at the far end — so what is checked is the SHAPES, which is a question about pixels and not about intent. The
# client draws its own chrome, so this needs no compositor: `-cg_drawChromeInContext:` takes a bitmap rep's context.
add_executable(window_chrome window_chrome.m)
target_link_libraries(window_chrome PRIVATE App m)
add_test(NAME appkit-window-chrome COMMAND window_chrome)
set_tests_properties(appkit-window-chrome PROPERTIES ENVIRONMENT "${_agora_app_test_env}")
