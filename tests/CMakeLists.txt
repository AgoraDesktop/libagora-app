# libagora-app's tests.
#
# `keyboard` needs nothing but a keymap, so it always runs. `window` needs a COMPOSITOR, which is a property
# of the machine and not of the code, so its wrapper SKIPS with a message rather than failing when no
# compositor can be started -- a test that fails for want of a display teaches nothing and gets muted.

# The tests link the whole AppKit, whose dependencies live in the install prefix; DT_RUNPATH is NOT inherited
# by a dependency, so the prefix's lib directory has to be on LD_LIBRARY_PATH for the transitive hops to
# resolve. The directory comes from an imported target rather than being written down.
set(_agora_app_test_env "LD_LIBRARY_PATH=$<TARGET_FILE_DIR:Foundation::Foundation>:$<TARGET_FILE_DIR:App>")

# **THE SIBLING'S WINDOW SERVER IS AN OPTION RATHER THAN A REQUIREMENT, AND IT HAS TO BE NAMED BEFORE IT IS USED.**
# A component's tests must not need another component's build to be present, so the tests that want a compositor of
# our own SKIP (77) when there is nothing to run against. A `set(... CACHE ...)` defined BELOW its first use expands
# to NOTHING on a fresh configure — the cache entry does not exist yet — and the skip becomes a failure, because the
# script is handed an empty server path. Declared here, once, above every test that names it.
set(AGORA_WINDOW_SERVER_BINARY "${CMAKE_CURRENT_SOURCE_DIR}/../../window-server/build/window-server"
    CACHE FILEPATH "window-server's built binary, for the tests that need a compositor of our own")

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
# **THE DEMONSTRATION DEFAULTS TO THE TREE'S OWN THEME.** It is the thing to iterate on, so it points
# `AGORA_CHROME_THEME` at `../themes` when a caller has not — the library's own default stays "no theme", because a
# library must not go looking for other people's art. The directory is git-ignored and may be absent.
target_compile_definitions(appkit_controls_draw PRIVATE
  AGORA_CHROME_DEFAULT_THEME="${CMAKE_CURRENT_SOURCE_DIR}/../themes")

add_executable(menu_view_ink menu_view_ink.m)
target_link_libraries(menu_view_ink PRIVATE App)
add_test(NAME appkit-menu-view-ink COMMAND menu_view_ink)

# **VALIDATION AND STATE, WHICH THE VIEW TESTS DO NOT REACH.** A target's `-validateMenuItem:` decides
# enablement (and may change the item while it answers), the fallback rule enables an item whose target answers
# its action, and an item that is ON draws a default checkmark when it named no image. Offscreen, so it runs
# anywhere.
add_executable(menu_validation menu_validation.m)
target_link_libraries(menu_validation PRIVATE App)
add_test(NAME appkit-menu-validation COMMAND menu_validation)
set_tests_properties(appkit-menu-validation PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

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

# **AND THE INSIDE OF A SCROLL VIEW.** `NSClipView`'s arithmetic is "the whole of it" (its own header), and it is
# checked in EXACT POINTS rather than by drawing: where a short document sits, where a long one stops, and the
# notification wire that re-constrains the scroll when the document's own frame or bounds changes. Offscreen, so it
# runs anywhere — which is the property `NSClipView.h` claims for a clip view without an `NSScrollView`.
add_executable(clip_view clip_view.m)
target_link_libraries(clip_view PRIVATE App m)
add_test(NAME appkit-clip-view COMMAND clip_view)
set_tests_properties(appkit-clip-view PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE BAR THAT GOES WITH IT.** A scroller is two inverse arithmetics — the value pair into a knob, and a point
# into a part — plus the drag that turns a point back into a value. Offscreen, and it needs neither a scroll view nor
# a document: it is a control that reports where it was pressed, and the scroll view that owns it does the scrolling.
add_executable(scroller scroller.m)
target_link_libraries(scroller PRIVATE App m)
add_test(NAME appkit-scroller COMMAND scroller)
set_tests_properties(appkit-scroller PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

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

# **THE APPkit AGAINST AGORA'S OWN WINDOW SERVER**, which is the only one that can answer `-visibleFrame`.
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

# **AND WHAT A CHROME BUTTON DOES, WHICH IS THE HALF NO PIXEL TEST CAN SEE.** `appkit-chrome-theme` proves a press
# lights the theme's pressed art; this proves the RELEASE performs the action — and only when the pointer is still
# on the button that was pressed. Same harness as the events test, for the same reason: the seam's struct is
# public and the pump is the application's own, so the only synthetic link is the compositor calling that door.
add_executable(chrome_buttons chrome_buttons.m)
target_link_libraries(chrome_buttons PRIVATE App)

add_test(NAME appkit-chrome-buttons
  COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/run-appkit-headless.sh" "$<TARGET_FILE:chrome_buttons>" 2
	  "all checks passed" )
set_tests_properties(appkit-chrome-buttons PROPERTIES SKIP_RETURN_CODE 77
  ENVIRONMENT "${_agora_app_test_env}")

# **AND HOW MANY FRAMES A DRAG COSTS.** A control's tracking is a MODAL LOOP: `NSControl -mouseDown:` runs its own
# event pump while the application's run loop is NOT turning, so everything the run loop does once per pass has to
# be done there by hand — and it was done once per EVENT. This counts the window's own draws for a forty-motion
# drag, so "laggy to drag and snappy to click" becomes a number. `timeout` is there because this is the one test
# that starts a real run loop: a drag that never reaches the control must FAIL rather than hang the suite.
add_executable(control_drag control_drag.m)
target_link_libraries(control_drag PRIVATE App)

add_test(NAME appkit-control-drag
  COMMAND timeout 60 "${CMAKE_CURRENT_SOURCE_DIR}/run-appkit-headless.sh" "$<TARGET_FILE:control_drag>" 2
	  "all checks passed" )
set_tests_properties(appkit-control-drag PROPERTIES SKIP_RETURN_CODE 77
  ENVIRONMENT "${_agora_app_test_env}")

# **AND THE FRAME'S OWN EDGES, WHICH ARE THE WINDOW'S OTHER HANDLE.** A press on one drags that edge and leaves the
# opposite one exactly where it was; the middle of the bar still moves the window; and a window that may not be
# resized does not. Driven through the seam like the events test, with the pass made by hand for the reason that
# test's does it — a resize is applied once per pass, and the pass belongs to a run loop this test is not inside.
add_executable(window_resize window_resize.m)
target_link_libraries(window_resize PRIVATE App)

add_test(NAME appkit-window-resize
  COMMAND timeout 60 "${CMAKE_CURRENT_SOURCE_DIR}/run-appkit-headless.sh" "$<TARGET_FILE:window_resize>" 2
	  "all checks passed" )
set_tests_properties(appkit-window-resize PROPERTIES SKIP_RETURN_CODE 77
  ENVIRONMENT "${_agora_app_test_env}")

# AND THE CHROME: Agora's title bar is an X, a minus and a plus drawn in one ink, a centred bold title, and a pill
# at the far end — so what is checked is the SHAPES, which is a question about pixels and not about intent. The
# client draws its own chrome, so this needs no compositor: `-cg_drawChromeInContext:` takes a bitmap rep's context.
add_executable(window_chrome window_chrome.m)
target_link_libraries(window_chrome PRIVATE App m)
add_test(NAME appkit-window-chrome COMMAND window_chrome)
set_tests_properties(appkit-window-chrome PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE THEME'S OWN READER AND GEOMETRY.** The chrome's buttons can come from an XFWM theme's `.xpm` files
# instead of the drawn marks, and this runs against `tests/fixtures/chrome` — Agora's OWN MIT fixture, sixteen
# hand-written XPMs — so the test never depends on the GPL theme that prompted the work. `AGORA_CHROME_THEME` is
# the door, and it is set here rather than in the test so the search path is exercised the way a program uses it.
add_executable(chrome_theme chrome_theme.m)
target_link_libraries(chrome_theme PRIVATE App m)
add_test(NAME appkit-chrome-theme COMMAND chrome_theme)
set_tests_properties(appkit-chrome-theme PROPERTIES
  ENVIRONMENT "${_agora_app_test_env};AGORA_CHROME_THEME=${CMAKE_CURRENT_SOURCE_DIR}/fixtures/chrome")
