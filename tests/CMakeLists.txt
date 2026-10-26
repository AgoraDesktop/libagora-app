# Copyright © 2026 Kyle J. Cardoza.
# SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
# SPDX-License-Identifier: GPL-3.0-or-later

# libagora-app's tests.
#
# `keyboard` needs nothing but a keymap, so it always runs. `window` needs a COMPOSITOR, which is a property
# of the machine and not of the code, so its wrapper SKIPS with a message rather than failing when no
# compositor can be started -- a test that fails for want of a display teaches nothing and gets muted.

# The tests link the whole AppKit, whose dependencies live in the install prefix; DT_RUNPATH is NOT inherited
# by a dependency, so the prefix's lib directory has to be on LD_LIBRARY_PATH for the transitive hops to
# resolve. The directory comes from an imported target rather than being written down.
#
# **AND THE BUILD TREE COMES FIRST, WHICH IS NOT COSMETIC.** The prefix also carries an installed
# `libagora-app.so`, so with the prefix first every test loaded the INSTALLED AppKit while the executable it
# had just been linked with — and the source tree it is meant to test — were ignored. MEASURED: a triangle moved
# four points in `NSOutlineView.m` and rebuilt changed nothing in `appkit-outline-view`, because the test had
# loaded the prefix's copy; the same was true of a baseline change that the guard checks exist to catch.
set(_agora_app_test_env "LD_LIBRARY_PATH=$<TARGET_FILE_DIR:App>:$<TARGET_FILE_DIR:Foundation::Foundation>")

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
# **THE MENU VIEW'S ERA SURFACE.** The view had five of its forty-two selectors; this checks the rest — where a row is
# (`-rectOfItemAtIndex:`, `-indexOfItemAtPoint:`), where the columns inside a row start (the offsets and widths, measured
# from a menu whose rows differ so a "widest" that answered the first row would fail), the view's answer to the menu
# changing under it (through NSMenu's own notifications, so there is one path into the cell cache), the highlight by index,
# the action-with-a-flash, the face and the bar's height — and the ten doors that refuse by name, with the reason.
add_executable(menu_view_surface menu_view_surface.m)
target_link_libraries(menu_view_surface PRIVATE App)

add_test(NAME appkit-menu-view-surface COMMAND menu_view_surface)
set_tests_properties(appkit-menu-view-surface PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

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

# **THE OUTLINE: THE TABLE'S TREE, FLATTENED.** Roots and children, levels, the disclosure triangle's click, the
# outline column's inset, and selection in item terms — offscreen.
add_executable(outline_view outline_view.m)
target_link_libraries(outline_view PRIVATE App m)
add_test(NAME appkit-outline-view COMMAND outline_view)
set_tests_properties(appkit-outline-view PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE PATH CONTROL: A PATH AS COMPONENT CELLS.** URL decomposition, the component geometry and its middle
# truncation, the three styles, single/double action and the bar's ink -- offscreen, with a borderless window only
# as the coordinate root for the double-click event.
add_executable(path_control path_control.m)
target_link_libraries(path_control PRIVATE App m)
add_test(NAME appkit-path-control COMMAND path_control)
set_tests_properties(appkit-path-control PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE SEGMENTED CONTROL: A ROW OF BUTTONS THAT ACTS AS ONE CONTROL.** The public forwards, the segment geometry,
# the three tracking modes, the per-segment storage and the ink -- offscreen, because all of it is geometry and
# drawing once the cell is handed a control view.
add_executable(segmented_control segmented_control.m)
target_link_libraries(segmented_control PRIVATE App m)
add_test(NAME appkit-segmented-control COMMAND segmented_control)
set_tests_properties(appkit-segmented-control PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE TABLE'S OTHER HALF: VARIABLE HEIGHTS, TYPE-SELECT, REORDERING, AUTOSAVE AND EDITING.** Offscreen, with a
# scroll view and a window for the header's coordinate root and the field editor.
add_executable(table_advanced table_advanced.m)
target_link_libraries(table_advanced PRIVATE App m)
add_test(NAME appkit-table-advanced COMMAND table_advanced)
set_tests_properties(appkit-table-advanced PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE TABLE'S LAST TWENTY DOORS.** The deprecated spellings are checked through their modern counterparts, the
# autoresizing styles by the widths they leave, and the drawings by pixels: the grid mask, the focus ring, the header's
# indicator image, the three drag-destination feedback styles, and the drag image's union size. The vertical-motion gate
# is measured through a table subclass whose drag entry point is a counter, so "the drag began" is a fact.
add_executable(table_tail table_tail.m)
target_link_libraries(table_tail PRIVATE App m)
add_test(NAME appkit-table-tail COMMAND table_tail)
set_tests_properties(appkit-table-tail PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE SPLIT VIEW: PANES, DIVIDERS, THE DRAG, THE COLLAPSE AND THE DELEGATE.** Offscreen: the geometry, the
# effective rectangles and the ink need no compositor, and a synthetic press is delivered to the view directly.
add_executable(split_view split_view.m)
target_link_libraries(split_view PRIVATE App m)
add_test(NAME appkit-split-view COMMAND split_view)
set_tests_properties(appkit-split-view PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE TABLE: A DATA SOURCE'S ROWS, COLUMNS, HEADER, SELECTION AND INK.** Offscreen: a scroll view, a table and a
# header are geometry and drawing, and the one window in the probe only supplies a coordinate root for the events.
add_executable(table_view table_view.m)
target_link_libraries(table_view PRIVATE App m)
add_test(NAME appkit-table-view COMMAND table_view)
set_tests_properties(appkit-table-view PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE TOOLBAR: A DELEGATE'S ITEMS, THE BAND THEY TAKE, THE INK THEY DRAW AND THE CLICK THEY ANSWER.** Offscreen,
# like the chrome: the frame arithmetic and the view's own context need no compositor.
add_executable(toolbar toolbar.m)
target_link_libraries(toolbar PRIVATE App m)
add_test(NAME appkit-toolbar COMMAND toolbar)
set_tests_properties(appkit-toolbar PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE CONTROL LAYER: A VIEW THAT DELEGATES ITS FACE TO A CELL.** Offscreen, and the claim is the INK — a button's
# bezel and title, a switch's indicator, the value doors forwarding, and `-performClick:` reaching the target.
add_executable(control_ink control_ink.m)
target_link_libraries(control_ink PRIVATE App)
add_test(NAME appkit-control-ink COMMAND control_ink)
set_tests_properties(appkit-control-ink PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE CONTROL'S LAST TWENTY-EIGHT DOORS.** The class factory, the one-cell selection, the paint/invalidate quartet,
# the sender-value family, the formatter pair and `-validateEditing`, measured by a counting cell and by a real field
# editor session rather than by the forwards' return values.
add_executable(control_tail control_tail.m)
target_link_libraries(control_tail PRIVATE App m)
add_test(NAME appkit-control-tail COMMAND control_tail)
set_tests_properties(appkit-control-tail PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# THE NEXT CONTROL: a slider is the first whose VALUE is a position rather than a state, so its probe is the one that
# has to measure the geometry's two directions and not just the ink.
add_executable(slider_ink slider_ink.m)
target_link_libraries(slider_ink PRIVATE App m)
add_test(NAME appkit-slider-ink COMMAND slider_ink)
set_tests_properties(appkit-slider-ink PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE SLIDER'S TICK VALUES, ITS TITLE AND THE TWO NO-ARGUMENT INK DOORS.** The ticks are checked in both directions
# (the nth mark's value, the nearest mark to a value, and the snap every setter then performs), each mark's centre is
# matched to the knob's centre in both orientations AND in a flipped view — the case the old inline ink drew upside
# down — and the title's band is measured by the knob moving down and the words drawing above it.
add_executable(slider_title_ticks slider_title_ticks.m)
target_link_libraries(slider_title_ticks PRIVATE App m)
add_test(NAME appkit-slider-title-ticks COMMAND slider_title_ticks)
set_tests_properties(appkit-slider-title-ticks PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# AND THE TRACKING AREA: the class that replaced the window's blanket enter/exit synthesis, and whose SCOPE word is
# what keeps a background window's controls from lighting up.
add_executable(tracking_area tracking_area.m)
target_link_libraries(tracking_area PRIVATE App m)
add_test(NAME appkit-tracking-area COMMAND tracking_area)
set_tests_properties(appkit-tracking-area PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE VIEW'S LAST TWENTY-EIGHT DOORS.** The forced display family, the frame/rotation setters, the subview list,
# autoscroll, the focus-lock/layer/definition refusals and the ruler client defaults — measured by a counting view, a
# real clip view and an old ruler client that records its own farewell.
add_executable(view_tail view_tail.m)
target_link_libraries(view_tail PRIVATE App m)
add_test(NAME appkit-view-tail COMMAND view_tail)
set_tests_properties(appkit-view-tail PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

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

# **AND THE STORE THE RICH-TEXT SLICE IS BUILT ON.** `NSTextStorage` is an attributed string that announces its own
# edits: the two primitives record a mask, a range and a length change; `-beginEditing`/`-endEditing` coalesce a group
# into ONE announcement; and an edit made through a door the store never overrode is announced by DISPATCH.
add_executable(text_storage text_storage.m)
target_link_libraries(text_storage PRIVATE App)
add_test(NAME appkit-text-storage COMMAND text_storage)
set_tests_properties(appkit-text-storage PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE REGION THE STORE GETS LAID OUT IN.** `NSTextContainer` holds four facts (a size, a fragment padding, two
# tracking flags) and one computation: given a proposed line fragment, the part of it that falls inside — with the
# carry-back a typesetter asks for when a line misses the region entirely.
add_executable(text_container text_container.m)
target_link_libraries(text_container PRIVATE App)
add_test(NAME appkit-text-container COMMAND text_container)
set_tests_properties(appkit-text-container PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND A CONTAINER'S SHAPED REGION, WHICH THE LAYOUT NOW ASKS FOR.** A non-simple container is asked for each
# line's band; an inset first line starts at its x and breaks at its width, and a hole splits ONE logical line into
# two fragments at the same baseline, with the hit test choosing by x among them.
add_executable(text_container_region text_container_region.m)
target_link_libraries(text_container_region PRIVATE App)
add_test(NAME appkit-text-container-region COMMAND text_container_region)
set_tests_properties(appkit-text-container-region PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE WEB THAT TIES THE TRIO TOGETHER.** `NSLayoutManager` slice one: a store it is handed by the storage that
# lists it, containers it owns and they borrow, and ONE piece of behaviour — an edit in the store is folded into a stale
# range and announced to a delegate. Each pair is checked from BOTH sides.
add_executable(text_layout_web text_layout_web.m)
target_link_libraries(text_layout_web PRIVATE App)
add_test(NAME appkit-text-layout-web COMMAND text_layout_web)
set_tests_properties(appkit-text-layout-web PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE FRAGMENTS THAT WEB PRODUCES.** `NSLayoutManager` slice two: the store is laid into the container's lines by
# the typesetter — one fragment per line, the container's width — and the geometry doors answer where each is and what
# the container has used. The character-to-glyph map is checked as the IDENTITY it is, clamping included.
add_executable(text_layout_fragments text_layout_fragments.m)
target_link_libraries(text_layout_fragments PRIVATE App m)
add_test(NAME appkit-text-layout-fragments COMMAND text_layout_fragments)
set_tests_properties(appkit-text-layout-fragments PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE INK THAT LAYOUT PRODUCES.** The manager DRAWS the fragments it laid out: two lines are two bands, the
# origin moves them, a glyph range draws only its own line, the bounding rect is the union of the fragments a range
# touches, and a foreground colour in the STORE is the colour the glyphs come out.
add_executable(text_layout_draw text_layout_draw.m)
target_link_libraries(text_layout_draw PRIVATE App m)
add_test(NAME appkit-text-layout-draw COMMAND text_layout_draw)
set_tests_properties(appkit-text-layout-draw PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE TWO INK KEYS BESIDES THE GLYPHS: A BACKGROUND AND AN UNDERLINE.** A background colour fills the used rect
# of its run and an underline draws a rule below the baseline; both are read as PIXELS, and the two-run case is what
# makes the RUN WALK the subject rather than one colour per line.
add_executable(text_layout_attributes text_layout_attributes.m)
target_link_libraries(text_layout_attributes PRIVATE App m)
add_test(NAME appkit-text-layout-attributes COMMAND text_layout_attributes)
set_tests_properties(appkit-text-layout-attributes PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE SECOND CONTAINER: TEXT THAT DOES NOT FIT THE FIRST IS CARRIED TO THE NEXT.** A container's own height is
# the overflow edge, so a first container two lines tall takes two lines and the next takes the rest — checked as
# fragment counts, per-container glyph ranges and each container's own coordinates.
add_executable(text_layout_overflow text_layout_overflow.m)
target_link_libraries(text_layout_overflow PRIVATE App m)
add_test(NAME appkit-text-layout-overflow COMMAND text_layout_overflow)
set_tests_properties(appkit-text-layout-overflow PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE WORD GRANULARITY OF THE SAME KEYS.** Option+arrow moves by the word and Option+Delete deletes one, which
# is arithmetic over the string's own characters and needs no layout model — the correction `NSResponder.h` carries.
# Driven as KEYS, so the mapping is under test as well as the walk.
add_executable(text_word_movement text_word_movement.m)
target_link_libraries(text_word_movement PRIVATE App m)
add_test(NAME appkit-text-word-movement COMMAND text_word_movement)
set_tests_properties(appkit-text-word-movement PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE FIRST SLICE OF THE MULTI-LINE TEXT VIEW.** `NSTextView` holds many lines where `NSText` holds one: the line
# model is checked as arithmetic (including a trailing newline's empty last line), the layout as PIXELS (two lines, two
# ink bands), and the behaviour as KEYS and CLICKS — Return, Tab, Up and Down are the keys a one-line field refuses.
add_executable(text_view_lines text_view_lines.m)
target_link_libraries(text_view_lines PRIVATE App m)
add_test(NAME appkit-text-view-lines COMMAND text_view_lines)
set_tests_properties(appkit-text-view-lines PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE SLICE ABOVE IT: THE SAME MODEL WRAPPED TO THE VIEW'S WIDTH.** A paragraph too wide becomes several VISUAL
# lines; the model line count does not move; the ranges are contiguous; a wrapped line ends on a space; the click, the
# movements and the INK all walk the visual lines; and `-sizeToFit` keeps the width and answers the height.
add_executable(text_view_wrapping text_view_wrapping.m)
target_link_libraries(text_view_wrapping PRIVATE App m)
add_test(NAME appkit-text-view-wrapping COMMAND text_view_wrapping)
set_tests_properties(appkit-text-view-wrapping PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE SLICE THAT PUTS IT IN A SCROLL VIEW.** `NSView -scrollRectToVisible:`/`-scrollPoint:` find the enclosing
# clip view and move it; the text view settles its own height and turns a caret into a rectangle. Measured against a
# REAL scroll view and read as the clip view's own `bounds` origin.
add_executable(text_view_scrolling text_view_scrolling.m)
target_link_libraries(text_view_scrolling PRIVATE App m)
add_test(NAME appkit-text-view-scrolling COMMAND text_view_scrolling)
set_tests_properties(appkit-text-view-scrolling PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE VIEW READING THE STORE THROUGH THE MANAGER, WHICH RETIRED ITS OWN LAYOUT.** The view owns the trio,
# `-string` is the store's, an edit in either direction reaches the other, the visual line count IS the manager's
# fragment count, a run in the store is the ink the view draws, and typing inherits the run at the insertion point.
add_executable(text_view_store text_view_store.m)
target_link_libraries(text_view_store PRIVATE App m)
add_test(NAME appkit-text-view-store COMMAND text_view_store)
set_tests_properties(appkit-text-view-store PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE GLYPH STORE THE MANAGER KEEPS: THE GENERATED LINES, AND THE FOUR REVERSE LOOKUPS.** `-numberOfGlyphs`,
# the two conversion doors, a glyph's x from its fragment's own origin, the point-to-glyph inverse, and the ORDINAL
# fragment doors — including the boundary index, which belongs to the fragment that STARTS there.
add_executable(text_layout_glyphs text_layout_glyphs.m)
target_link_libraries(text_layout_glyphs PRIVATE App m)
add_test(NAME appkit-text-layout-glyphs COMMAND text_layout_glyphs)
set_tests_properties(appkit-text-layout-glyphs PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE PARAGRAPH STYLE, WHICH IS A VALUE OBJECT WITH TWO READERS.** The class's defaults and its copy/freeze
# dance are the first half; the ALIGNMENT (which moves a line inside its width) and the LINE-BREAK MODE (which the
# typesetter obeys) are the two properties the layout reads, and the view's `-setAlignment:` is the store writing the
# style the manager then reads.
# **AND THE HYPHENATION FACTOR, THE LAST PROPERTY OF `NSParagraphStyle` WITH NO READER.** It is read as a
# HYPHENATION ZONE (`lineWidth < factor * width`), a piece of the word that did not fit is pulled onto the line
# and a U+2010 that is NOT a character of the store is drawn at its end — so the case checks the ranges, that the
# fragments still tile the text, that the glyph space is unmoved, and that the ink reaches the reserved edge.
add_executable(text_hyphenation text_hyphenation.m)
target_link_libraries(text_hyphenation PRIVATE App m)
add_test(NAME appkit-text-hyphenation COMMAND text_hyphenation)
set_tests_properties(appkit-text-hyphenation PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

add_executable(text_paragraph_style text_paragraph_style.m)
target_link_libraries(text_paragraph_style PRIVATE App m)
add_test(NAME appkit-text-paragraph-style COMMAND text_paragraph_style)
set_tests_properties(appkit-text-paragraph-style PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE MARKED TEXT, WHICH IS WHAT AN INPUT METHOD COMPOSES THROUGH.** `NSTextInput`'s doors are driven by hand:
# a composition is replaced keystroke by keystroke, confirmed by `-insertText:` and taken back by `-unmarkText`; the
# candidate window's four questions are asked; and the composition draws a rule the plain text does not.
add_executable(text_marked_text text_marked_text.m)
target_link_libraries(text_marked_text PRIVATE App m)
add_test(NAME appkit-text-marked-text COMMAND text_marked_text)
set_tests_properties(appkit-text-marked-text PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE INPUT CONTEXT, WHERE A KEY GOES BEFORE THE TEXT VIEW.** `NSView -inputContext` answers one for a text input
# client; the standard key binding now lives in its `-handleEvent:`; and it owns the composition through
# `-discardMarkedText`. The probe drives the context directly, so the mapping's new home is under test rather than the
# responder that hands the event over.
add_executable(text_input_context text_input_context.m)
target_link_libraries(text_input_context PRIVATE App m)
add_test(NAME appkit-text-input-context COMMAND text_input_context)
set_tests_properties(appkit-text-input-context PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE INPUT METHOD ITSELF: A DEAD KEY COMPOSED WITH THE NEXT KEYSTROKE.** The context is handed an
# `AGInputMethod`; the accent goes into the store MARKED, and the next letter either composes over it or the accent
# stands alone. A key the method does not own — a plain letter, a movement — is DECLINED and reaches the standard
# binding, which is what makes a source safe to install.
add_executable(text_input_method text_input_method.m)
target_link_libraries(text_input_method PRIVATE App m)
add_test(NAME appkit-text-input-method COMMAND text_input_method)
set_tests_properties(appkit-text-input-method PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE CANDIDATE LIST: THE READINGS A METHOD OFFERS, AND THE WINDOW THAT SHOWS THEM.** A list view sized from its
# strings with the selected reading's accent fill; a borderless window placed under the caret and following it; and a
# method that holds a letter's variants open across keystrokes — arrows to move, Return to pick, Escape to take back.
add_executable(text_candidate_list text_candidate_list.m)
target_link_libraries(text_candidate_list PRIVATE App m)
add_test(NAME appkit-text-candidate-list COMMAND text_candidate_list)
set_tests_properties(appkit-text-candidate-list PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE BASE WRITING DIRECTION, WHICH DECIDES WHAT NATURAL ALIGNMENT MEANS.** `+defaultWritingDirectionForLanguage:`
# asks the locale, and the layout manager resolves `NSNaturalTextAlignment` through the direction — right for a
# right-to-left paragraph — while the three EXPLICIT alignments are untouched. Glyph reordering is the engine's, named.
add_executable(text_writing_direction text_writing_direction.m)
target_link_libraries(text_writing_direction PRIVATE App m)
add_test(NAME appkit-text-writing-direction COMMAND text_writing_direction)
set_tests_properties(appkit-text-writing-direction PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE EDITING COMMANDS THE RESPONDER NAMED AS OWED**: `-transpose:` (pure string arithmetic over a position) and
# the `IgnoringFieldEditor` insertions plus the paragraph separator, checked across a view that holds a break and a
# field that refuses one.
add_executable(text_editing_commands text_editing_commands.m)
target_link_libraries(text_editing_commands PRIVATE App m)
add_test(NAME appkit-text-editing-commands COMMAND text_editing_commands)
set_tests_properties(appkit-text-editing-commands PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE TABLE BLOCK, WHICH IS THE BOX A PARAGRAPH IS SET IN.** The block's ledger and bounds arithmetic, the cell's
# place in its table, the paragraph style's block array, and the manager drawing the ground and border where the
# block's lines are — the last read as pixels.
add_executable(text_table text_table.m)
target_link_libraries(text_table PRIVATE App m)
add_test(NAME appkit-text-table COMMAND text_table)
set_tests_properties(appkit-text-table PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND RTF, THE FORMAT A DOCUMENT TRAVELS IN.** The writer and reader are checked as a ROUND TRIP for the attributes
# this tier draws — the text and its break, the font, the inks, the rules and the paragraph alignment — plus the
# control words the bytes carry.
add_executable(text_rtf text_rtf.m)
target_link_libraries(text_rtf PRIVATE App m)
add_test(NAME appkit-text-rtf COMMAND text_rtf)
set_tests_properties(appkit-text-rtf PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE TABLE GRID: CELLS SIDE BY SIDE.** The layout manager lays a table's cells out as a grid — each inside its
# own columns' width — so the probe reads where a glyph in each cell lands: a row shares a y, a column shares an x, an
# overflowing row is scaled and wraps, and a fixed table divides the width equally.
add_executable(text_table_grid text_table_grid.m)
target_link_libraries(text_table_grid PRIVATE App m)
add_test(NAME appkit-text-table-grid COMMAND text_table_grid)
set_tests_properties(appkit-text-table-grid PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND A SHARED BORDER DRAWN ONCE WHEN THE TABLE COLLAPSES ITS BORDERS.** Two cells side by side meet at their
# column's edge and each drew that edge; with `-collapsesBorders` the left cell keeps it and the right cell's is
# suppressed, which the probe reads as the red pixels either side of the seam — plus a lone cell, which must be
# unchanged, and a stack of two, where the difference must be EXACTLY one strip.
add_executable(text_table_collapse text_table_collapse.m)
target_link_libraries(text_table_collapse PRIVATE App m)
add_test(NAME appkit-text-table-collapse COMMAND text_table_collapse)
set_tests_properties(appkit-text-table-collapse PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND A TABLE THAT DOES NOT FIT GOES ON IN THE NEXT CONTAINER.** A row that does not fit the container it is being
# laid into begins the next one, with the columns measured from EVERY cell so they do not move across the break. The
# probe reads each container's fragments, the glyph range each took, and column two's x either side of the break.
add_executable(text_table_flow text_table_flow.m)
target_link_libraries(text_table_flow PRIVATE App m)
add_test(NAME appkit-text-table-flow COMMAND text_table_flow)
set_tests_properties(appkit-text-table-flow PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE ATTACHMENT'S INLINE FLOW: A FIXED-SIZE BOX THE TEXT FLOWS AROUND.** The manager records the difference
# between the box's width and the placeholder glyph's advance, so the character after an attachment is one box width
# past it, a point inside the box hit-tests to the attachment, and the picture is drawn where the box is.
add_executable(text_attachment_flow text_attachment_flow.m)
target_link_libraries(text_attachment_flow PRIVATE App m)
add_test(NAME appkit-text-attachment-flow COMMAND text_attachment_flow)
set_tests_properties(appkit-text-attachment-flow PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE TRACKING FAMILY, DRIVEN BY THE TEXT VIEW'S OWN EVENT STREAM.** The view hit-tests the attachment, asks the
# cell whether it wants the mouse, and sends the down, every drag and the up through the cell's door one event at a
# time — no modal loop. The probe drives the real mouse methods, reads the cell's highlight as accent ink, and records
# one call per event with the attachment's own character index.
add_executable(text_attachment_tracking text_attachment_tracking.m)
target_link_libraries(text_attachment_tracking PRIVATE App m)
add_test(NAME appkit-text-attachment-tracking COMMAND text_attachment_tracking)
set_tests_properties(appkit-text-attachment-tracking PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE TAB STOPS.** `NSTextTab` names a place and a kind; the manager copies them into the `CTParagraphStyle` it
# builds, and `CTLine` advances a `\t` to the next stop — so the character after a tab begins AT the stop, which the
# probe reads from the manager's own offsets.
add_executable(text_tab_stops text_tab_stops.m)
target_link_libraries(text_tab_stops PRIVATE App m)
add_test(NAME appkit-text-tab-stops COMMAND text_tab_stops)
set_tests_properties(appkit-text-tab-stops PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE PARAGRAPH STYLE'S GEOMETRY, WHICH IS NOW READ.** The indents place a line and narrow it, the spacings open
# gaps between lines and across paragraph boundaries, and the line-height multiple and clamps set the band — each read as
# the manager's own geometry, with the defaults pinned unmoved by the first case.
add_executable(text_paragraph_geometry text_paragraph_geometry.m)
target_link_libraries(text_paragraph_geometry PRIVATE App m)
add_test(NAME appkit-text-paragraph-geometry COMMAND text_paragraph_geometry)
set_tests_properties(appkit-text-paragraph-geometry PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND AN ATTACHMENT, WHICH IS A CHARACTER THAT STANDS FOR A PICTURE.** The value object (a picture gives an attachment
# a cell sized to it), the cell's own drawing, and the layout manager drawing the cell at the attachment character's
# place in a store — all read as the picture's colour in a pixel.
add_executable(text_attachment text_attachment.m)
target_link_libraries(text_attachment PRIVATE App m)
add_test(NAME appkit-text-attachment COMMAND text_attachment)
set_tests_properties(appkit-text-attachment PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

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

# **AND THE FRAME THAT JOINS THEM.** A scroll view owns a clip view and two scrollers, tiles them, and carries the two
# directions of the scroll loop — a scroller's action moves the clip view, a moved clip view updates the scrollers.
# Offscreen: it is a view with three subviews and an arithmetic between them, and `NSView -enclosingScrollView` is
# finally a walk rather than a nil with a reason.
add_executable(scroll_view scroll_view.m)
target_link_libraries(scroll_view PRIVATE App m)
add_test(NAME appkit-scroll-view COMMAND scroll_view)
set_tests_properties(appkit-scroll-view PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE BUTTON PAIR FINISHED.** Twenty doors over two classes: the button's eight forwards (checked against the CELL,
# which is the object that draws), the cell's alternate mnemonic (a parse, so tested as one), its two font doors (one
# field, so the pair is checked against itself), the bezel's shading (pixels, since a gradient is a picture), and the
# three ink doors the face is now split into — counted by a subclass AND painted by one, so a door that is called and
# ignored cannot pass. Offscreen: a bitmap rep and the cells' own geometry.
add_executable(button_sweep button_sweep.m)
target_link_libraries(button_sweep PRIVATE App m)
add_test(NAME appkit-button-sweep COMMAND button_sweep)
set_tests_properties(appkit-button-sweep PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE PLATFORM'S OWN PICTURES, WHICH USED TO BE NAMES WITH NOTHING BEHIND THEM.** Every `NSImageName…` this
# tier draws answers an image; every one is a template; and a template drawn through the tint door really does take
# the ink it was given. Offscreen, into a bitmap rep.
add_executable(system_images system_images.m)
target_link_libraries(system_images PRIVATE App m)
add_test(NAME appkit-system-images COMMAND system_images)
set_tests_properties(appkit-system-images PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE HALF OF "DRAW ONLY WHAT CHANGED" NOTHING CAN SEE FROM OUTSIDE: THE CLIP.** A window hands `-displayRect:`
# the union of what was invalidated; the tree draws anyway, so unless that rectangle is a CLIP each `-drawRect:` paints
# its whole bounds and the saving is the copy alone. The probe is a view that paints everything on purpose — and its
# pixels outside the rectangle must stay untouched. Offscreen, into a bitmap rep.
add_executable(display_damage display_damage.m)
target_link_libraries(display_damage PRIVATE App m)
add_test(NAME appkit-display-damage COMMAND display_damage)
set_tests_properties(appkit-display-damage PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE ONE THING A SCROLL ACTUALLY MOVES: A NON-ZERO `bounds` ORIGIN.** It is read in the conversions, in the live
# `-displayRect:`, and in the offscreen `fn_draw_view` that used to refuse it — so a clip view scrolled correctly and
# nothing moved. Offscreen, into a bitmap rep.
add_executable(view_offset view_offset.m)
target_link_libraries(view_offset PRIVATE App m)
add_test(NAME appkit-view-offset COMMAND view_offset)
set_tests_properties(appkit-view-offset PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE CONTROL THAT JOINS TWO SUBSYSTEMS: A BUTTON THAT RAISES A MENU.** The probe is the CHAIN — the wiring
# `-setMenu:` does, a pick through the menu's own dispatch, the selection and the title that follow it — plus the
# arrow's ink and where the two `-arrowPosition` values put it. NO EVENT LOOP IS NEEDED, because every link in that
# chain is a call the probe can make itself: that is what makes a menu testable offscreen.
add_executable(popup_menu popup_menu.m)
target_link_libraries(popup_menu PRIVATE App)
add_test(NAME appkit-popup-menu COMMAND popup_menu)
set_tests_properties(appkit-popup-menu PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE OTHER FIELD WITH A CHIP IN IT**, which the sample draws on the row below the pop-up's. This probe's subject
# is a COUNT: a pop-up's chip carries two triangles knocked out of it and a combo box's carries one, so the column
# down the chip's middle is walked and its runs of white are counted. It also draws BOTH cells into the same geometry
# and compares where their chips land, which is what makes "one field, one chip" a claim rather than a comment.
add_executable(combo_box combo_box.m)
target_link_libraries(combo_box PRIVATE App)
add_test(NAME appkit-combo-box COMMAND combo_box)
set_tests_properties(appkit-combo-box PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND A PICK FROM THE LIST WHILE SOMEBODY IS TYPING ELSEWHERE.** A combo box's list is a menu session; the pick is
# sound, but the cell's value setter also pushes its string into whatever editor the cell holds. This asserts that a
# box which is NOT being edited cannot write into the window's shared editor, which belongs to the focused field.
add_executable(combo_pick_focus combo_pick_focus.m)
target_link_libraries(combo_pick_focus PRIVATE App)
add_test(NAME appkit-combo-pick-focus COMMAND combo_pick_focus)
set_tests_properties(appkit-combo-pick-focus PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE EDIT SESSION ITSELF.** A window lends an editor, a cell begins a session with it, a string is EDITED through
# the primitive a keystroke uses, and the cell takes it back — the round trip that makes a field a field, driven
# offscreen with no event loop.
# **AND THE SWITCH, WHICH IS THE FIRST CONTROL HERE THAT NEEDS NO FONT AT ALL.** Its value is where the knob is and its
# state is what the track is filled with, so every claim about it is a pixel this probe reads out of a bitmap.
add_executable(control_switch control_switch.m)
target_link_libraries(control_switch PRIVATE App)
add_test(NAME appkit-control-switch COMMAND control_switch)
set_tests_properties(appkit-control-switch PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

add_executable(text_field_cell text_field_cell.m)
target_link_libraries(text_field_cell PRIVATE App)
add_test(NAME appkit-text-field-cell COMMAND text_field_cell)
set_tests_properties(appkit-text-field-cell PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE VIEW ABOVE THAT CELL, WHICH IS THE HALF A PERSON EXERCISES.** The cell probe begins a session by hand;
# this one presses the field, commits with Return, throws away with Escape, opens with `-selectText:`, and aborts —
# and asks the WINDOW who its first responder is, because a field's keyboard belongs to its editor and not to itself.
# Offscreen, so it runs anywhere.
add_executable(text_field_control text_field_control.m)
target_link_libraries(text_field_control PRIVATE App)
add_test(NAME appkit-text-field-control COMMAND text_field_control)
set_tests_properties(appkit-text-field-control PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE FIELD'S TWO BORDER SHAPES, WHICH ARE A CLAIM ABOUT PIXELS.** The square/rounded pair is read where the ink
# falls: the four corner pixels carry the border for a square field and none for a rounded one, and every measure that
# is NOT the corner is checked to agree. Offscreen, into a bitmap rep.
add_executable(text_field_bezel text_field_bezel.m)
target_link_libraries(text_field_bezel PRIVATE App m)
add_test(NAME appkit-text-field-bezel COMMAND text_field_bezel)
set_tests_properties(appkit-text-field-bezel PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND WHAT AN EMPTY FIELD SAYS IT IS FOR, WHICH IS A CLAIM ABOUT INK AND ABOUT A SESSION.** An empty field with a
# placeholder draws a hint DIMMER than a value; one without draws nothing; an attributed placeholder is drawn with its
# own attributes; and the hint survives a click into an empty field and leaves when a character arrives. Offscreen,
# into a bitmap rep, plus one real session on a real window for the live-text half.
add_executable(text_field_placeholder text_field_placeholder.m)
target_link_libraries(text_field_placeholder PRIVATE App m)
add_test(NAME appkit-text-field-placeholder COMMAND text_field_placeholder)
set_tests_properties(appkit-text-field-placeholder PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND WHAT A FIELD MAY HOLD, AND THE DOOR THAT TELLS THE EDITOR.** The attributed-editing flags were carried by the
# cell and by the editor and were never connected; this checks the chain at all three objects, and drives
# `-setUpFieldEditorAttributes:` directly because that is the door a subclass would override.
add_executable(text_field_attributes text_field_attributes.m)
target_link_libraries(text_field_attributes PRIVATE App m)
add_test(NAME appkit-text-field-attributes COMMAND text_field_attributes)
set_tests_properties(appkit-text-field-attributes PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

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
# **AND THREE DISPATCH QUESTIONS THE PUMP ANSWERED WRONGLY**, each a wrong answer rather than a missing feature:
# a mask that named one event selected all of them (the `mask & NSAnyEventMask` pattern, in the posted queue, the
# discard door AND the per-window queue); a compositor's close bypassed `-windowShouldClose:`; and a main-menu key
# equivalent never reached the menu bar on the ordinary `-sendEvent:` route, only while a menu was tracking.
# **THE APPLICATION'S LOOP IS A RUN LOOP.** `-[NSApplication run]` gives one `NSRunLoop` pass per frame, so a timer,
# a delayed perform, a performer from another thread and `dispatch_async(dispatch_get_main_queue(), …)` are all
# delivered inside it — and a timer added for a mode it never runs is not. No window is made, so this case needs no
# compositor and runs everywhere rather than skipping with the window tests.
# **AND THE COMPOSITOR'S DESCRIPTOR IS ONE OF THE LOOP'S SOURCES.** A view paints only when the compositor asks for a
# frame, so a paint produced by a `-runUntilDate:` wait with no manual pumping can only mean the connection was
# serviced by the loop. The headless runner supplies the compositor; without one the case SKIPS (77).
add_executable(appkit_runloop_connection appkit_runloop_connection.m)
target_link_libraries(appkit_runloop_connection PRIVATE App)

add_test(NAME appkit-runloop-connection
  COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/run-appkit-headless.sh" "$<TARGET_FILE:appkit_runloop_connection>" 3
	  "all checks passed")
set_tests_properties(appkit-runloop-connection PROPERTIES SKIP_RETURN_CODE 77
  ENVIRONMENT "${_agora_app_test_env}")

# **THE COMMIT NAMES ITS DAMAGE, INSTEAD OF THE WHOLE BUFFER.** A strip repaint must reach the seam as a strip — asked
# through `AGWindowLastDamage`, so the assertion is about what the compositor was told rather than what the AppKit
# meant. The headless runner supplies the compositor; without one the case SKIPS (77).
add_executable(appkit_partial_damage appkit_partial_damage.m)
target_link_libraries(appkit_partial_damage PRIVATE App)

add_test(NAME appkit-partial-damage
  COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/run-appkit-headless.sh" "$<TARGET_FILE:appkit_partial_damage>" 3
	  "all checks passed")
set_tests_properties(appkit-partial-damage PROPERTIES SKIP_RETURN_CODE 77
  ENVIRONMENT "${_agora_app_test_env}")

add_executable(appkit_runloop_timer appkit_runloop_timer.m)
target_link_libraries(appkit_runloop_timer PRIVATE App dispatch)

add_test(NAME appkit-runloop-timer COMMAND appkit_runloop_timer)
set_tests_properties(appkit-runloop-timer PROPERTIES TIMEOUT 60
  ENVIRONMENT "${_agora_app_test_env}")

add_executable(appkit_dispatch appkit_dispatch.m)
target_link_libraries(appkit_dispatch PRIVATE App)

add_test(NAME appkit-dispatch
  COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/run-appkit-headless.sh" "$<TARGET_FILE:appkit_dispatch>" 3
	  "all checks passed" )
set_tests_properties(appkit-dispatch PROPERTIES SKIP_RETURN_CODE 77
  ENVIRONMENT "${_agora_app_test_env}")

# **AND THE COMPOSITOR'S RESIZE IS THE APPLICATION'S RESIZE.** The configure used to assign the size, mark dirty and
# DRAW inside libwayland's listener — painting stale content geometry, announcing nothing to the delegate, and putting
# a delegate that closes the window inside a live native callback. The application's own path announced
# `-windowDidResize:` before re-laying the content, so an observer read new bounds and old ones in one callback.
# This measures WHEN each half becomes visible, and that a batch of configures is one resize.
add_executable(appkit_resize appkit_resize.m)
target_link_libraries(appkit_resize PRIVATE App)

add_test(NAME appkit-resize
  COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/run-appkit-headless.sh" "$<TARGET_FILE:appkit_resize>" 3
	  "all checks passed" )
set_tests_properties(appkit-resize PROPERTIES SKIP_RETURN_CODE 77
  ENVIRONMENT "${_agora_app_test_env}")

# **AND WHICH CLASS THE ONE APPLICATION IS.** `+sharedApplication` hard-coded `[[NSApplication alloc] init]`, so a
# subclass could never be the object `NSApp` names. The receiving class is now honoured, `NSPrincipalClass` is read
# from the bundle when nobody says otherwise, and the two refusals are checked rather than hoped for.
add_executable(appkit_principal_class appkit_principal_class.m)
target_link_libraries(appkit_principal_class PRIVATE App)

add_test(NAME appkit-principal-class
  COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/run-appkit-headless.sh" "$<TARGET_FILE:appkit_principal_class>" 2
	  "all checks passed" )
set_tests_properties(appkit-principal-class PROPERTIES SKIP_RETURN_CODE 77
  ENVIRONMENT "${_agora_app_test_env}")

# **AND THE WHEEL, WHICH HAD NOWHERE TO GO.** The seam had no scroll event at all, so `wl_pointer.axis` stopped at the
# platform and `-scrollWheel:` was never called by anything. This delivers the seam's own axis events and checks the two
# things that are conventions rather than plumbing: the units (one notch is one line, a finger's fraction is a fraction)
# and the signs (the protocol's down/right is Cocoa's negative), plus routing by hit test and that a wheel is not a
# press.
add_executable(appkit_scroll appkit_scroll.m)
target_link_libraries(appkit_scroll PRIVATE App)

add_test(NAME appkit-scroll
  COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/run-appkit-headless.sh" "$<TARGET_FILE:appkit_scroll>" 3
	  "all checks passed" )
set_tests_properties(appkit-scroll PROPERTIES SKIP_RETURN_CODE 77
  ENVIRONMENT "${_agora_app_test_env}")

# **AND THE GENERAL PASTEBOARD ACROSS A PROCESS BOUNDARY**, which is the one thing it could not do: the ordinary
# `-declareTypes:owner:` / `-setData:forType:` / `-dataForType:` API, driven by two processes through the compositor's
# selection (see window-server's CLIPBOARD-PLAN.md).
add_executable(pasteboard_remote pasteboard_remote.m)
target_link_libraries(pasteboard_remote PRIVATE App)

add_test(NAME appkit-pasteboard-remote
  COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/run-pasteboard-remote.sh"
    "${AGORA_WINDOW_SERVER_BINARY}" "$<TARGET_FILE:pasteboard_remote>")
set_tests_properties(appkit-pasteboard-remote PROPERTIES SKIP_RETURN_CODE 77
  ENVIRONMENT "${_agora_app_test_env}")

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

# **THE WINDOW'S LAST EIGHTEEN DOORS.** The `is` aliases, the mutable style mask, the represented filename, the
# default button/backing/order/colour state, the screen initialiser, the animated frame set and the local event queue's
# post/discard pair — measured by the style/chrome arithmetic and by dequeuing the queue itself.
add_executable(window_tail window_tail.m)
target_link_libraries(window_tail PRIVATE App m)
add_test(NAME appkit-window-tail COMMAND window_tail)
set_tests_properties(appkit-window-tail PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE THEME'S OWN READER AND GEOMETRY.** The chrome's buttons can come from an XFWM theme's `.xpm` files
# instead of the drawn marks, and this runs against `tests/fixtures/chrome` — Agora's OWN MIT fixture, sixteen
# hand-written XPMs — so the test never depends on the GPL theme that prompted the work. `AGORA_CHROME_THEME` is
# the door, and it is set here rather than in the test so the search path is exercised the way a program uses it.
add_executable(chrome_theme chrome_theme.m)
target_link_libraries(chrome_theme PRIVATE App m)
add_test(NAME appkit-chrome-theme COMMAND chrome_theme)
set_tests_properties(appkit-chrome-theme PROPERTIES
  ENVIRONMENT "${_agora_app_test_env};AGORA_CHROME_THEME=${CMAKE_CURRENT_SOURCE_DIR}/fixtures/chrome")

# Writing an image out. The class's encoder door refused for its whole life because Core Graphics had no
# `CGImageDestination`; this probe measures the answer with the class's own decoder and every refusal that
# remains beside it.
add_executable(appkit_bitmap_encode appkit_bitmap_encode.m)
target_link_libraries(appkit_bitmap_encode PRIVATE App)

add_test(NAME appkit-bitmap-encode COMMAND appkit_bitmap_encode)
set_tests_properties(appkit-bitmap-encode PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# The one rule an image rep's draw has to keep in BOTH coordinate systems AppKit builds: up is up. The
# Desktop is y-up and `WSIconView` is flipped, and the same bytes must not arrive mirrored in the two.
add_executable(image_draw image_draw.m)
target_link_libraries(image_draw PRIVATE App)

add_test(NAME appkit-image-draw COMMAND image_draw)
set_tests_properties(appkit-image-draw PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **NSImageView: THE IMAGE CELL'S FACE AND THE TWO EDIT FLAGS.** The alignment is checked by the ink's horizontal
# position, the forwards against the cell, and paste/cut/delete on both sides of their gate — with the pasteboard
# carrying a real PNG.
add_executable(image_view image_view.m)
target_link_libraries(image_view PRIVATE App m)
add_test(NAME appkit-image-view COMMAND image_view)
set_tests_properties(appkit-image-view PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE PDF CHAIN: VIEW -> BYTES -> REP -> PIXELS.** No window and no compositor: a flipped probe view writes a
# page through -dataWithPDFInsideRect:, the same bytes go onto a pasteboard under NSPDFPboardType, NSPDFImageRep
# parses them back, and both the page and the rep's vector draw are read as pixels. The second half asks the
# multi-page doors that a view cannot exercise.
add_executable(pdf_app pdf_app.m)
target_link_libraries(pdf_app PRIVATE App)

add_test(NAME appkit-pdf COMMAND pdf_app)
set_tests_properties(appkit-pdf PROPERTIES ENVIRONMENT "${_agora_app_test_env}")
# **EPS THROUGH APPKIT.** `-dataWithEPSInsideRect:` and `-writeEPSInsideRect:toPasteboard:` drive the EPS
# writer; Ghostscript reads the result when the host has it. The structural checks do not need it.
add_executable(eps_app eps_app.m)
target_link_libraries(eps_app PRIVATE App)

add_test(NAME appkit-eps COMMAND eps_app)
set_tests_properties(appkit-eps PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# The package form of the RTF document: TXT.rtf plus one file per attachment, and the reference between them.
add_executable(text_rtfd text_rtfd.m)
target_link_libraries(text_rtfd PRIVATE App)

add_test(NAME appkit-text-rtfd COMMAND text_rtfd)
set_tests_properties(appkit-text-rtfd PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# The refusal census: every `APPKIT-REFUSE` site in this library, counted against the committed table in BOTH
# directions. `nm` cannot answer here — every door in this layer is an Objective-C method, which is dispatched
# dynamically and appears in no symbol table — so the census counts the sites the prose itself makes.
# **THE NEEDLE TAKES BOTH SPELLINGS OF A REFUSAL**, which `tests/refusal_census.txt` explains: the marker literal and
# the shared `fn_refuse_window` helper. Counting only the literal made half the refusals in the library invisible,
# including every one added since the helper landed.
add_test(NAME appkit-refusal-census
    COMMAND "${CMAKE_COMMAND}"
            "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}/.."
            "-DCENSUS=${CMAKE_CURRENT_SOURCE_DIR}/refusal_census.txt"
            "-DEXTENSION=.m"
            "-DNEEDLE=(APPKIT-REFUSE|fn_refuse_[a-z]+)"
            -P "${CMAKE_CURRENT_SOURCE_DIR}/claims_census.cmake")

# And the same instrument over the HEADERS, counting the OWED claims — as a WORD, so `ALLOWED` does not count.
add_test(NAME appkit-owed-census
    COMMAND "${CMAKE_COMMAND}"
            "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}/.."
            "-DCENSUS=${CMAKE_CURRENT_SOURCE_DIR}/owed_census.txt"
            "-DEXTENSION=.h"
            "-DNEEDLE=(^|[^A-Za-z_])OWED"
            -P "${CMAKE_CURRENT_SOURCE_DIR}/claims_census.cmake")

# **AND THE MEASUREMENT THOSE TWO CLAIMS ARE ABOUT.** The censuses above count what this tree SAYS it cannot do; this
# one counts what a caller would actually GET from it, against the committed facts of the Mac OS X 10.6 AppKit
# (`api/10.6/appkit-manifest.txt` — names and relationships only, because Apple's SDK is not redistributable). The
# parser is `tools/api-ledger`, because deciding whether a selector is answered needs a superclass chain rather than a
# regex; the gate is `api_census.cmake`, which does the same two-directional comparison as the other two.
#
# **AND THE BUILT LIBRARY IS PART OF THE INPUT, BECAUSE A DECLARATION IS NOT A DOOR.** `-DLIBRARY=$<TARGET_FILE:App>`
# lets `nm -D --defined-only` answer which functions a caller can actually link against; the gate fails outright if the
# headers and the symbols disagree in either direction, rather than moving a number.
#
# A PYTHON INTERPRETER IS A NEW REQUIREMENT, AND IT IS HERE RATHER THAN IN THE BUILD. Every other test in this suite is
# a compiled executable, so the tree needs no interpreter to BUILD; only this gate needs one to RUN. It is therefore
# registered unconditionally and fails loudly at run time if the interpreter is missing, instead of disappearing from
# the suite — a gate that quietly unregisters itself is the drift these censuses exist to stop.
find_package(Python3 COMPONENTS Interpreter QUIET)
if(Python3_Interpreter_FOUND)
  set(_agora_api_python "${Python3_EXECUTABLE}")
else()
  message(STATUS
    "appkit-api-census: no Python 3 found. The test is still registered and will FAIL at run time — install "
    "python3, or the 10.6 API census goes unmeasured.")
  set(_agora_api_python python3)
endif()

add_test(NAME appkit-api-census
    COMMAND "${CMAKE_COMMAND}"
            "-DPYTHON=${_agora_api_python}"
            "-DLEDGER=${CMAKE_CURRENT_SOURCE_DIR}/../tools/api-ledger"
            "-DMANIFEST=${CMAKE_CURRENT_SOURCE_DIR}/../api/10.6/appkit-manifest.txt"
            "-DLIBRARY=$<TARGET_FILE:App>"
            "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}/.."
            "-DCENSUS=${CMAKE_CURRENT_SOURCE_DIR}/api-10.6-census.txt"
            -P "${CMAKE_CURRENT_SOURCE_DIR}/api_census.cmake")

# NSTextList: the marker arithmetic, and the paragraph style that carries lists.
add_executable(text_list text_list.m)
target_link_libraries(text_list PRIVATE App)

add_test(NAME appkit-text-list COMMAND text_list)
set_tests_properties(appkit-text-list PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# Lists in the RTF writer: the list table, the paragraph's \ls/\ilvl, and no marker text in the string.
add_executable(text_rtf_lists text_rtf_lists.m)
target_link_libraries(text_rtf_lists PRIVATE App)

add_test(NAME appkit-text-rtf-lists COMMAND text_rtf_lists)
set_tests_properties(appkit-text-rtf-lists PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# NSCoding on the text-layout values: an archived list and an archived block, round-tripped.
add_executable(text_coding text_coding.m)
target_link_libraries(text_coding PRIVATE App)

add_test(NAME appkit-text-coding COMMAND text_coding)
set_tests_properties(appkit-text-coding PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# The table's delegation doors: a subclass of NSTextTable paints its own cells.
add_executable(text_table_delegation text_table_delegation.m)
target_link_libraries(text_table_delegation PRIVATE App)

add_test(NAME appkit-text-table-delegation COMMAND text_table_delegation)
set_tests_properties(appkit-text-table-delegation PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# And the README's citations: every `tests/<name>.m` it names must exist, because four of its "still owed" claims were
# found false in one reading and the root cause was a sentence nobody had to revisit.
add_test(NAME appkit-readme-refs
    COMMAND "${CMAKE_COMMAND}"
            "-DREADME=${CMAKE_CURRENT_SOURCE_DIR}/../README.md"
            "-DTESTS_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
            -P "${CMAKE_CURRENT_SOURCE_DIR}/readme_refs.cmake")

# The NSTextInputClient protocol: a view held as a client and asked through it.
add_executable(text_input_client text_input_client.m)
target_link_libraries(text_input_client PRIVATE App)

add_test(NAME appkit-text-input-client COMMAND text_input_client)
set_tests_properties(appkit-text-input-client PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE DRAG SESSION: THE SOURCE, THE DESTINATION AND THE IMAGE.** Two registered windows, a source view and a
# destination view, driven through the application's own dispatch (`-[NSWindow sendEvent:]`) — no compositor, because
# the search falls back to the application's window registry when there is no connection. The floating image window
# needs glass and is asked about by `drag_seam` against the sibling's headless server.
add_executable(drag_session drag_session.m)
target_link_libraries(drag_session PRIVATE App m)
add_test(NAME appkit-drag-session COMMAND drag_session)
set_tests_properties(appkit-drag-session PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE IMAGE WINDOW NEEDS GLASS.** The session is offscreen; the borderless floating window is not, so this asks the
# sibling's headless server for a real connection and SKIPS (77) when it is not built.
add_executable(drag_seam drag_seam.m)
target_link_libraries(drag_seam PRIVATE App m)
add_test(NAME appkit-drag-seam
  COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/run-drag-seam.sh"
	  "$<TARGET_FILE:drag_seam>" "${AGORA_WINDOW_SERVER_BINARY}")
set_tests_properties(appkit-drag-seam PROPERTIES SKIP_RETURN_CODE 77
  ENVIRONMENT "${_agora_app_test_env}")

# **THE BROWSER'S OWN PROBE.** Columns are private tables; the delegate's row counts, the selection that opens the
# next column, the path and the cell fill are the public contract.
add_executable(browser browser.m)
target_link_libraries(browser PRIVATE App m)
add_test(NAME appkit-browser COMMAND browser)
set_tests_properties(appkit-browser PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **WHERE THE BROWSER'S COLUMNS ARE, AND WHAT ITS TITLE STRIP HOLDS.** The browser had a `-titleHeight` its layout
# ignored and no `-isTitled` at all; this checks the slice that reserved the strip and drew the title in it — three frames
# that are one rect cut three ways, a row's place, `-getRow:column:forPoint:` as the exact inverse, the title's INK on a
# surface with an untitled column as the negative control, the click that records `-clickedRow`/`-clickedColumn`, and the
# one width conversion with the two width defaults behind it.
add_executable(browser_geometry browser_geometry.m)
target_link_libraries(browser_geometry PRIVATE App m)
add_test(NAME appkit-browser-geometry COMMAND browser_geometry)
set_tests_properties(appkit-browser-geometry PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE 10.6 ITEM-BASED MODEL, WHICH THIS CLASS NOW ADVERTISES.** A delegate of model objects — how many children an
# item has, which child is at an index, whether an item is a leaf, what its cell should show — drives a browser that makes
# its own cells, walks an item path from the nil root, and reads and writes the selection as an index path. The cell-based
# delegate is measured beside it, because the older contract is the FALLBACK rather than the removed one.
add_executable(browser_items browser_items.m)
target_link_libraries(browser_items PRIVATE App)

add_test(NAME appkit-browser-items COMMAND browser_items)
set_tests_properties(appkit-browser-items PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE PROGRESS INDICATOR: A VALUE AS A BAR.** Offscreen, with a bitmap for the fill.
add_executable(progress_indicator progress_indicator.m)
target_link_libraries(progress_indicator PRIVATE App m)
add_test(NAME appkit-progress-indicator COMMAND progress_indicator)
set_tests_properties(appkit-progress-indicator PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AUTO LAYOUT: EQUATIONS BECOME FRAMES.** No window and no compositor — a tree of views, a handful of constraints,
# and frames that a person can compute by hand. The flipped-parent case and the cousin case are the two that a
# one-level solver would pass and this one must too, so they are why the probe is not just a width check.
add_executable(auto_layout auto_layout.m)
target_link_libraries(auto_layout PRIVATE App m)
add_test(NAME appkit-auto-layout COMMAND auto_layout)
set_tests_properties(appkit-auto-layout PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE PANEL AND THE ALERT: A HELPER WINDOW, AND A QUESTION WITH BUTTONS.** The panel's defaults and its
# click-to-key rule, the alert's content and layout, the button codes through a modal session, Return and Escape
# through the panel's own key handler, and the sheet form's reply. Offscreen: the geometry, the field strings and
# the session doors need no compositor, and `-runModal` is deliberately not called because it is an unbounded loop.
add_executable(panel_alert panel_alert.m)
target_link_libraries(panel_alert PRIVATE App m)
add_test(NAME appkit-panel-alert COMMAND panel_alert)
set_tests_properties(appkit-panel-alert PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE SHEET ITSELF, WHICH IS A PAIR OF WINDOWS RATHER THAN ONE.** Where it goes (top edge at the bottom of the
# parent's title bar, centred), what it loses (its own strip, and the frame that held it), that the pair is re-pinned on
# every move and resize rather than remembering an offset, that its top rows are not a handle, and that ending the
# session gives the strip back with the content intact. Offscreen: the geometry needs no compositor, the pixels are
# `window_chrome`'s, and the compositor's half of the shape is `set_sheet_parent`'s.
add_executable(sheet sheet.m)
target_link_libraries(sheet PRIVATE App m)
add_test(NAME appkit-sheet COMMAND sheet)
set_tests_properties(appkit-sheet PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE SAME PROBE ONCE WITH GLASS, BECAUSE ONE OF ITS RULES NEEDS SOME.** `-orderFront:` creates the window and
# refuses without a compositor, so the visibility half of the pair — a parent ordered out takes its sheet with it, and
# brings it back — can only be asserted where there is something to be visible ON. The probe says which half it ran,
# and this is the run where the answer is "both". `drawer_visibility` is the same shape: a rule about the glass, held
# by a headless compositor, skipping (77) where none can be started.
add_test(NAME appkit-sheet-visibility
  COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/run-appkit-headless.sh"
    "$<TARGET_FILE:sheet>" 3 "sheet: all checks passed")
set_tests_properties(appkit-sheet-visibility PROPERTIES SKIP_RETURN_CODE 77
  ENVIRONMENT "${_agora_app_test_env}")

# **THE SEARCH FIELD: A FIELD WITH A MAGNIFIER AND A CLEAR BUTTON.** The three rectangles and the measurement that
# pays for both slots, the glyph ink and the clear button that is absent until there is text, the press that misses
# the text and starts no session, the delayed/immediate/whole-string sending rules with the timer fired by hand, and
# the recents list, its autosave and the template menu built from the four tagged placeholders. Offscreen: a bitmap,
# a real field editor and no run loop.
add_executable(search_field search_field.m)
target_link_libraries(search_field PRIVATE App m)
add_test(NAME appkit-search-field COMMAND search_field)
set_tests_properties(appkit-search-field PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE FIRST-PARTY NIB FORMAT'S ROUND TRIP.** Views, a control, a cell, an outlet and an action — archived, written
# as a file, read back, and compared. It needs no display: it builds views rather than windows, which is why it always
# runs. The three refusals it asserts (a class outside the allow-list, a class that only inherits coding, a file that is
# not a nib) are the format's security rules and are tested here rather than trusted.
add_executable(nib_roundtrip nib_roundtrip.m)
target_link_libraries(nib_roundtrip PRIVATE App)
add_test(NAME appkit-nib-roundtrip COMMAND nib_roundtrip)
set_tests_properties(appkit-nib-roundtrip PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **APPLE'S COMPILED NIB (.nib) IS A COMPATIBILITY DOOR, not a second spelling of this tree's keys.** The fixture is
# built the way Apple builds one -- binary property list, CF$UID references, NSObjectsKeys/NSObjectsValues,
# NSNib*Connector records -- and translated into live objects. The test asserts both halves: the view tree and the
# outlet/action connections. No compositor is needed because the fixture's top level is a view; the window-template
# check validates rather than instantiates.
add_executable(apple_nib apple_nib.m)
target_link_libraries(apple_nib PRIVATE App)
add_test(NAME appkit-apple-nib COMMAND apple_nib)
set_tests_properties(appkit-apple-nib PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE TEXT SOURCE, AND THE COMPILER THAT MAKES THE ARCHIVE FROM IT.** `NSNibSource` parses the OpenStep-shaped source
# (dictionaries, arrays, quoted strings, and bare words TYPED as numbers or booleans) and compiles it into a nib — the
# same split as `.xib` and `.nib`, and the one that makes a design something git can review. `nib_compile` asserts the
# good case, the typed words, and six refusals that must each NAME what was wrong.
add_executable(nib_compile nib_compile.m NSNibSource.m)
target_link_libraries(nib_compile PRIVATE App)
add_test(NAME appkit-nib-compile COMMAND nib_compile)
set_tests_properties(appkit-nib-compile PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **A NIB IN A BUNDLE, LOADED BY NAME, INTO A VIEW CONTROLLER.** Every other nib test used a PATH; an application says
# `initWithNibName:bundle:` and lets the bundle find Contents/Resources/Main.nib. This builds a real bundle-shaped
# directory, compiles two nibs into it from source, and then does what an application does — including the two branches
# nothing else touches: the name lookup and NSViewController's owner outlet.
add_executable(nib_bundle nib_bundle.m NSNibSource.m)
target_link_libraries(nib_bundle PRIVATE App)
add_test(NAME appkit-nib-bundle COMMAND nib_bundle
	"${CMAKE_CURRENT_SOURCE_DIR}/fixtures/Main.nibsource")
set_tests_properties(appkit-nib-bundle PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **A WINDOW OUT OF A NIB, ON A COMPOSITOR, DRAWING.** The one coding path in the format that had never run: a window's
# -initWithCoder: derives the frame/style/backing, calls the DESIGNATED INITIALISER, and puts the archived content view
# back through -setContentView:. It needs a real compositor (the wall every other nib test deliberately avoids), so it
# runs under the AppKit's headless wrapper and SKIPS 77 without one. The assertion that matters is the DRAW COUNT: a
# decoded window that is never asked to draw is a window that only looks like one.
add_executable(nib_window nib_window.m NSNibSource.m)
target_link_libraries(nib_window PRIVATE App)
add_test(NAME appkit-nib-window
  COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/run-appkit-headless.sh" "$<TARGET_FILE:nib_window>" 3
	  "all nib-window assertions passed")
set_tests_properties(appkit-nib-window PROPERTIES SKIP_RETURN_CODE 77
  ENVIRONMENT "${_agora_app_test_env}")

# **THE PROJECT BUILDER ROLE'S FIRST PIECE: A BUNDLE FOR MORE THAN ONE MACHINE.** Apple's universal binary is a Mach-O
# container; the ELF loaders here have none, so a universal Agora bundle is one complete binary per platform plus a
# manifest table that NAMES them (`AGBundleExecutables`, resolved by NSBundle against `uname`). The tool writes it and the
# test OPENS what it wrote — the writer and the reader are two halves of one decision, and checking only the files would
# be checking the half that cannot be wrong in an interesting way.
add_executable(agora_bundler agora_bundler.m)
target_link_libraries(agora_bundler PRIVATE App)

add_executable(bundler_test bundler_test.m)
target_link_libraries(bundler_test PRIVATE App)
add_test(NAME appkit-bundler COMMAND bundler_test "$<TARGET_FILE:agora_bundler>")
set_tests_properties(appkit-bundler PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE FORMAT'S COMMAND LINE, AND ITS TEST.** `ibtool` is the reason a design file can be checked by a shell rather than
# by a person clicking: `dump`, `validate` and `roundtrip` read the same archives the reader does, with no display and no
# owner. The test RUNS the tool — the only honest way to test an executable — and builds its own fixture, because this
# repository commits no binaries.
add_executable(ibtool ibtool.m NSNibSource.m)
target_link_libraries(ibtool PRIVATE App)
set_target_properties(ibtool PROPERTIES ENABLE_EXPORTS ON)

add_executable(ibtool_test ibtool_test.m)
target_link_libraries(ibtool_test PRIVATE App)
add_test(NAME appkit-ibtool COMMAND ibtool_test "$<TARGET_FILE:ibtool>")
set_tests_properties(appkit-ibtool PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE WORKSPACE SERVICES: WHAT IS RUNNING, WHAT OPENS A FILE, AND AN ICON.** The snapshot diff and the
# application objects need no compositor (the rows are fed in directly), and the registry-backed doors measure the
# identifier → bundle → name → icon chain against a fixture bundle the test writes itself.
add_executable(workspace_services workspace_services.m)
# **AND LAUNCH SERVICES ON THIS TEST'S OWN LINE**, because the test calls `LSRegisterURL` itself — the fixture bundle
# has to exist before the AppKit's doors can resolve it, and registering it is the fixture's job rather than the
# AppKit's. A shared library's PRIVATE dependency is not propagated, which is what the link error says.
target_link_libraries(workspace_services PRIVATE App AgoraLaunchServices::LaunchServices)
add_test(NAME appkit-workspace-services COMMAND workspace_services)
set_tests_properties(appkit-workspace-services PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE LAUNCH VERBS THE FILE MANAGER WALKS**: a fixture bundle registered with Launch Services, so an identifier
# resolves to a URL and to a path and the two doors are held to the same answer; the deprecated dictionary pair measured
# against a window list the probe feeds in; the icon and file questions; a launch that cannot happen answering nil AND
# an error; and every refused door answering its type's empty value — the type questions (no UTI database) and the
# "open with" family (no launch specification in the seam).
add_executable(workspace_launch workspace_launch.m)
target_link_libraries(workspace_launch PRIVATE App AgoraLaunchServices::LaunchServices)
# **THE FILE-OPERATION VERBS, MEASURED ON DISK.** Every operation is checked by what exists afterwards — a file that moved, a
# copy beside its original, a link that resolves, an item in the trash directory — because "the door answered YES" is not the
# claim. The two modern doors' HANDLERS are checked too (called once, with the failures), and the thirteen refusals answer
# their types' empty values.
add_executable(workspace_fileops workspace_fileops.m)
target_link_libraries(workspace_fileops PRIVATE App)

add_test(NAME appkit-workspace-fileops COMMAND workspace_fileops)
set_tests_properties(appkit-workspace-fileops PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

add_test(NAME appkit-workspace-launch COMMAND workspace_launch)
set_tests_properties(appkit-workspace-launch PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND WHERE A POPPED-UP MENU'S PANEL ACTUALLY GOES**, which is the one arithmetic a Dock at a screen edge exposed:
# the point is in the VIEW's coordinates and the frame is on the SCREEN, and taking the first as the second put the
# Dock's context menu at x = 20 on the left edge of the display. No compositor needed for the conversions; the
# right-edge clamp skips when no screen has described itself.
add_executable(menu_placement menu_placement.m)
target_link_libraries(menu_placement PRIVATE App)
add_test(NAME appkit-menu-placement COMMAND menu_placement)
set_tests_properties(appkit-menu-placement PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE TWO CONTROLS THAT RAISE ONE, WHICH SHARE AN ANCHOR.** `NSMenu` takes the point in the VIEW's coordinates;
# the pop-up button and the combo box both used to carry it into the window first, so their menus opened one
# window-origin too far right and up. This asserts the shared anchor and the panel each cell raises.
add_executable(popup_anchor popup_anchor.m)
target_link_libraries(popup_anchor PRIVATE App)
add_test(NAME appkit-popup-anchor COMMAND popup_anchor)
set_tests_properties(appkit-popup-anchor PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE FORMAT A TILE'S MENU CROSSES BY.** The Dock is another process, so an application's dock menu travels as
# a JSON description and comes back as ids: this asserts that the round trip is a FIXED POINT, that only the rows a
# person can choose are numbered, that the numbering runs across submenus, and that an id finds its own row again.
# No compositor and no window: the two conversions are pure NSMenu work, so this runs anywhere.
add_executable(appkit_dock_menu appkit_dock_menu.m)
target_link_libraries(appkit_dock_menu PRIVATE App)
add_test(NAME appkit-dock-menu COMMAND appkit_dock_menu)
set_tests_properties(appkit-dock-menu PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE SAME ROUND TRIP AGAINST AGORA'S OWN SERVER**, which is where the two PROCESSES' worth of machinery meet:
# the delegate's answer becomes a description, the description crosses `agora_shell` version 6, and a rebuilt `NSMenu`
# comes back with a pick going home by an id. It needs a compositor that speaks that protocol, so it runs against
# `window-server` and SKIPS (77) when there is none to run against.
add_executable(dock_menu dock_menu.m)
target_link_libraries(dock_menu PRIVATE App)
add_test(NAME appkit-dock-menu-wire
  COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/run-dock-menu.sh"
	  "$<TARGET_FILE:dock_menu>" "${AGORA_WINDOW_SERVER_BINARY}")
set_tests_properties(appkit-dock-menu-wire PROPERTIES SKIP_RETURN_CODE 77
  ENVIRONMENT "${_agora_app_test_env}")

# **THE 10.6 `NSGraphics.h` DOORS, PINNED BY PIXELS.** The API census can only see that these functions EXIST; this test
# is what separates existing from drawing. Each door is checked for the failure that would go wrong quietly — a fill
# that leaks outside its rectangle, a frame that straddles its edge, a clip that replaces instead of intersecting —
# because those are the errors a screenshot does not show and a scroll view does.
add_executable(graphics_functions graphics_functions.m)
target_link_libraries(graphics_functions PRIVATE App)

add_test(NAME appkit-graphics-functions COMMAND graphics_functions)
set_tests_properties(appkit-graphics-functions PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE SECOND FUNCTION SLICE, PINNED.** The alert panels, the accessibility utilities, the services doors and the
# file-type phrases — see the file's header for why the modal half is checked through its panel rather than by running
# it, and why NSApplicationMain is checked for linkage rather than called.
add_executable(functions_target2 functions_target2.m)
target_link_libraries(functions_target2 PRIVATE App)

add_test(NAME appkit-functions-target2 COMMAND functions_target2)
set_tests_properties(appkit-functions-target2 PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE PHANTOM FIXES AND THE LAST SIX FUNCTION DOORS.** The three phantoms were FOUND by `methods-declared-not-
# implemented`, so they are pinned by the behaviour a caller would have crashed without; the image composers are checked
# by COVERAGE rather than by slice colour, because the claim a nine-slice makes is geometric.
add_executable(functions_target3 functions_target3.m)
target_link_libraries(functions_target3 PRIVATE App)

add_test(NAME appkit-functions-target3 COMMAND functions_target3)
set_tests_properties(appkit-functions-target3 PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE FIRST SLAB OF THE TEXT SYSTEM'S REMAINING SURFACE** — the fragment queries, which need no cluster mapping. The
# test asserts the two claims the header makes (the flag's inertness, and container-range vs line-range), because a
# documented deviation nothing checks is how a comment and a behaviour drift apart.
add_executable(text_fragment_queries text_fragment_queries.m)
target_link_libraries(text_fragment_queries PRIVATE App)

add_test(NAME appkit-text-fragment-queries COMMAND text_fragment_queries)
set_tests_properties(appkit-text-fragment-queries PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE GLYPH-TO-CHARACTER SLAB.** The mapping is NOT the identity — a ligature is one glyph for two characters — so the
# round trip is a real check rather than a tautology, and the point doors are checked against a point built from
# `-locationForGlyphAtIndex:`, which forces the two halves to agree.
add_executable(text_glyph_mapping text_glyph_mapping.m)
target_link_libraries(text_glyph_mapping PRIVATE App)

add_test(NAME appkit-text-glyph-mapping COMMAND text_glyph_mapping)
set_tests_properties(appkit-text-glyph-mapping PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE GLYPH STORE.** The store is a SHADOW of the layout, so the test asserts both halves: it agrees with what it
# shadows (glyph, character, location come from the shaper, not from zeros) and it REMEMBERS a caller's edits, with the
# untouched neighbours checked too. The three count-changing doors are checked to refuse rather than to lie.
add_executable(text_glyph_store text_glyph_store.m)
target_link_libraries(text_glyph_store PRIVATE App)

add_test(NAME appkit-text-glyph-store COMMAND text_glyph_store)
set_tests_properties(appkit-text-glyph-store PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE SPELL CHECKER — the first class whose backing is the machine's own data.** The dictionary-dependent assertions
# are conditional on `availableLanguages`, so the test is honest on a machine with no word list as well as on this one.
add_executable(spell_checker spell_checker.m)
target_link_libraries(spell_checker PRIVATE App)

add_test(NAME appkit-spell-checker COMMAND spell_checker)
set_tests_properties(appkit-spell-checker PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE SQUIGGLE.** The previous slice recorded spelling state and said nothing drew it; this one draws it, so the
# assertion has to be about pixels: a marked view shows red under the text, an unmarked one does not, and clearing the
# state clears the ink.
add_executable(spelling_underline spelling_underline.m)
target_link_libraries(spelling_underline PRIVATE App)

add_test(NAME appkit-spelling-underline COMMAND spelling_underline)
set_tests_properties(appkit-spelling-underline PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE FIND ACTIONS THAT DO NOT NEED A PANEL.** Apple's API splits ten actions into three that want a panel and seven
# that do not, so a Find menu works with no find UI at all; the test drives those and checks wrapping in both directions,
# because a finder that stops at the end of the document is the bug users report as "find is broken".
add_executable(find_actions find_actions.m)
target_link_libraries(find_actions PRIVATE App)

add_test(NAME appkit-find-actions COMMAND find_actions)
set_tests_properties(appkit-find-actions PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE RULER, WHICH IS GEOMETRY RATHER THAN A SUBSYSTEM.** The claims are the four the class makes: the thickness sum
# the scroll view sizes by, the marker rectangle's orientation arithmetic, every list change going through the client's
# questions, and the hash marks being the UNIT's arithmetic — asserted by finding the tick row and checking that its ink
# lands on multiples of five, then again after the origin moves by three.
add_executable(ruler_view ruler_view.m)
target_link_libraries(ruler_view PRIVATE App)

add_test(NAME appkit-ruler-view COMMAND ruler_view)
set_tests_properties(appkit-ruler-view PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE TEXT SYSTEM'S RULER, WHICH IS A ROUND TRIP RATHER THAN A COUNT.** Showing the ruler asks the manager for a marker
# per tab stop; dragging one rebuilds the paragraph's tab stops; and the assertion is that the LAYOUT moved — the x of the
# character after a tab is measured before and after a fifty-point drag. Copy/paste of the ruler is the second round trip,
# read back out of the store.
add_executable(text_ruler text_ruler.m)
target_link_libraries(text_ruler PRIVATE App)

add_test(NAME appkit-text-ruler COMMAND text_ruler)
set_tests_properties(appkit-text-ruler PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE BLOCK'S TWO RECTANGLES AND AN ATTACHMENT'S SIZE.** The claims are checkable without knowing the layout's
# arithmetic: the bounds rect differs from the layout rect by exactly the block's own padding+border, a caller's stored
# rect is answered while the other stays computed, and an attachment size override MOVES the text after it — measured as a
# reflow rather than as a changed answer. The drawing doors then paint into a rectangle and are checked for ink inside it
# and none outside.
add_executable(text_block_rects text_block_rects.m)
target_link_libraries(text_block_rects PRIVATE App)

add_test(NAME appkit-text-block-rects COMMAND text_block_rects)
set_tests_properties(appkit-text-block-rects PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE TABLE THE LAYOUT SEES AND THE STORE DOES NOT, AND THE RECTS A RANGE OCCUPIES.** A temporary attribute is a
# find-highlight that is not an edit: the probe sets a red foreground, draws the line and counts red pixels, removes it and
# requires them gone, then makes a delegate DECLINE the table and requires the ink to stay the store's. The rect arrays are
# geometry: one rect per line at the line's height, a caret of no width, and the extra line drawn only when the selection
# covers it.
add_executable(text_temporary_attributes text_temporary_attributes.m)
target_link_libraries(text_temporary_attributes PRIVATE App)

add_test(NAME appkit-text-temporary-attributes COMMAND text_temporary_attributes)
set_tests_properties(appkit-text-temporary-attributes PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE MANAGER'S STATE DOORS: ensure, invalidate, and the container tidings.** Three kinds of staleness end in three
# observable places — the stale record (published as cg_invalidatedRange because Apple has no getter), the text view's
# damage rect, and a layout that exists — and each is checked where a caller could see it. The glyph→character translation
# is asserted against the manager's own map, and the two font doors against the font's own numbers.
add_executable(text_manager_state text_manager_state.m)
target_link_libraries(text_manager_state PRIVATE App)

add_test(NAME appkit-text-manager-state COMMAND text_manager_state)
set_tests_properties(appkit-text-manager-state PROPERTIES ENVIRONMENT "${_agora_app_test_env}")


# **THE MANAGER'S KNOBS AND THE CARET'S PLACES.** Most of these doors are stored, and the test says so by round-tripping
# them; the exception is -usesFontLeading, asserted where it matters — the line height grows by the font's leading AND the
# second line's BASELINE moves by exactly that, so the knob reaches the breaker rather than a field. The store is set in
# Helvetica because the default font's leading measures zero on this machine, which would make the claim untestable.
add_executable(text_manager_knobs text_manager_knobs.m)
target_link_libraries(text_manager_knobs PRIVATE App)

add_test(NAME appkit-text-manager-knobs COMMAND text_manager_knobs)
set_tests_properties(appkit-text-manager-knobs PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE GLYPH STORE'S RANGE DOORS AND THE STRIKE INK.** The bulk readers are compared against the one-at-a-time door on the
# same record; the two writers are read back where a caller would read them (a written line rect and a recorded container);
# and the strike pair is asserted as INK through the middle of the x-height, against the same draw without it.
add_executable(text_glyph_bulk text_glyph_bulk.m)
target_link_libraries(text_glyph_bulk PRIVATE App)

add_test(NAME appkit-text-glyph-bulk COMMAND text_glyph_bulk)
set_tests_properties(appkit-text-glyph-bulk PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **TWELVE CLASSES THAT WERE A SELECTOR OR TWO SHORT.** Each door is checked where a caller sees it: the event's window is
# the registry's answer, the descriptor's matrix reads back through its own matrix door, the PDF rep answers the bytes it
# parsed, the paragraph style carries its outline level through a copy and through -setParagraphStyle:, the field strips
# the mnemonic marker, and the column's boolean IS the mask bit. The two refusals (indexed bezier points, the screen's
# colour space) are asserted as UNCHANGED STATE rather than as stderr output.
add_executable(appkit_loose_ends appkit_loose_ends.m)
target_link_libraries(appkit_loose_ends PRIVATE App)

add_test(NAME appkit-loose-ends COMMAND appkit_loose_ends)
set_tests_properties(appkit-loose-ends PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE MANAGER'S LAST SIX SELECTORS.** The two objects are `id` doors (their classes are not in this tier) and are
# asserted as round trips plus the stated difference from Apple's on-demand typesetter; the behaviour is a real value whose
# five numbers are PINNED here, because an enum edit that changed one would move a caller's archived setting.
add_executable(text_typesetter_doors text_typesetter_doors.m)
target_link_libraries(text_typesetter_doors PRIVATE App)

add_test(NAME appkit-text-typesetter-doors COMMAND text_typesetter_doors)
set_tests_properties(appkit-text-typesetter-doors PROPERTIES ENVIRONMENT "${_agora_app_test_env}")


# **THE COLOUR AND DRAWING VALUES: NSColorSpace, NSShadow, NSGradient** — plus the two refusals the first of them retires
# (NSColor's colour-space pair and NSScreen's colour space). Round trips for the values, the interpolation's arithmetic, and
# pixels for the ramp and the shadow, because a value that computes right and draws nothing is invisible to a value test.
add_executable(color_and_shadow color_and_shadow.m)
target_link_libraries(color_and_shadow PRIVATE App)

add_test(NAME appkit-color-and-shadow COMMAND color_and_shadow)
set_tests_properties(appkit-color-and-shadow PROPERTIES ENVIRONMENT "${_agora_app_test_env}")


# **THE IMAGE REP FAMILY: five classes.** Each is checked at the door a caller reaches first — the custom rep's draw
# selector is INVOKED (and its rectangle checked by value), the cached rep is captured from a window whose content draws a
# known colour and then BLITTED so the pixels prove it, the EPS rep parses a real %%BoundingBox: line and refuses to render,
# and the two unavailable formats refuse at their constructors. The registry assertions include a format that has no class,
# so the nil answers cannot pass for want of a registry.
add_executable(image_rep_family image_rep_family.m)
target_link_libraries(image_rep_family PRIVATE App)

add_test(NAME appkit-image-rep-family COMMAND image_rep_family)
set_tests_properties(appkit-image-rep-family PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE GRID AND THE FORM.** The first control in this tier whose face is PLURAL: the grid's arithmetic both ways, a
# gap that is not a cell, selection stored apart from the highlight drawn, the four modes' click policies, cells that
# MOVE (rather than copy) through a shape change, a per-column stable sort, a prototype copied per position, the
# keyboard's click and key equivalent without a pointer, a field session on the RIGHT cell, and the ink — a selected
# plain cell in the accent, a cell background under it, the grid's background in the gap, and a form cell's label band
# stopping where the value band starts.
add_executable(matrix matrix.m)
target_link_libraries(matrix PRIVATE App)

add_test(NAME appkit-matrix COMMAND matrix)
set_tests_properties(appkit-matrix PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE COLOUR PANELS: A LIST, A WELL, THE SHARED PANEL AND THE PICKER IT HOSTS.** The chain is the claim — a list
# written to the standard directory is found by name, which is what `+[NSColor colorWithCatalogName:colorName:]` now
# reads; a well's swatch is its colour in pixels; the panel is ONE window whose chips choose a mode and whose swatch and
# alpha ramp are where the content view says they are; a click in the picker's grid sets the panel's colour to that
# cell's colour; and the drag door's pasteboard half round-trips through `+colorFromPasteboard:` while the session
# itself answers NO without a window.
add_executable(colour_panels colour_panels.m)
target_link_libraries(colour_panels PRIVATE App)

add_test(NAME appkit-colour-panels COMMAND colour_panels)
set_tests_properties(appkit-colour-panels PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE FONT MANAGER AND THE FONT PANEL.** The enumeration is the machine's faces (families, member rows, a name that
# resolves), the traits and weights agree with each other, every conversion answers a face, the four action doors record
# an action and send `-changeFont:` to a target that converts back through the manager, the collections store, the font
# menu builds and its one delegate door declines a family, and the panel's two clicks — a family row and a size chip —
# change the panel's font, install it as the manager's selection and fire the target.
add_executable(font_manager font_manager.m)
target_link_libraries(font_manager PRIVATE App)

# **NSFont'S OWN SURFACE, METRICS FROM THE FACE.** Every metric door asks Core Text (the class is a view of a CTFontRef), so
# the probe measures RELATIONS — a longer string is wider, a missing glyph advances nothing, the line height is its own three
# metrics added — and the seven refusals are checked to answer their types' empty values.
add_executable(font_surface font_surface.m)
target_link_libraries(font_surface PRIVATE App m)

add_test(NAME appkit-font-surface COMMAND font_surface)
set_tests_properties(appkit-font-surface PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

add_test(NAME appkit-font-manager COMMAND font_manager)
set_tests_properties(appkit-font-manager PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE PRINT SYSTEM: A TICKET, A PDF, AND THE PANELS.** One file of checks that a print job comes out as a PDF with the
# right pages, with no printer anywhere in sight: the ticket's arithmetic, the paper table, a view that knows its range
# (three pages) and one that does not (cut by the imageable height), the page range, save/preview/spool dispositions, the
# PDF and EPS copying operations, both panels' sessions without a run loop, and the document/application doors. A spool
# WITH a queue is not asserted here — a test that needs a printer is a test that fails everywhere.
add_executable(printing printing.m)
target_link_libraries(printing PRIVATE App)

add_test(NAME appkit-printing COMMAND printing)
set_tests_properties(appkit-printing PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE TEXT VIEW'S SELECTION RANGES, ITS ATTRIBUTES AND ITS COMMANDS.** The ranges and their clamping, the four
# granularities' expansion, the typing attributes reaching the next character typed, the selection band's ink read back
# out of a bitmap, the editing contract's two forms, and every run and paragraph command asserted against the STORE
# rather than against a flag — with a caret's command measured on the typing attributes instead.
add_executable(text_view_attributes text_view_attributes.m)
target_link_libraries(text_view_attributes PRIVATE App)

add_test(NAME appkit-text-view-attributes COMMAND text_view_attributes)
set_tests_properties(appkit-text-view-attributes PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE TEXT VIEW'S CLIPBOARD AND ITS DRAGS.** A real round trip through the general pasteboard: copy writes RTFD, RTF and
# the string; paste into another view reads the richest type and the run's font comes back; the plain and rich commands
# take different types off the same board; a cut empties the view and fills the board; and the drag source's image, type
# registration and operation are measured without a window (the drop side needs a session, which the drag suite builds).
add_executable(text_view_pasteboard text_view_pasteboard.m)
target_link_libraries(text_view_pasteboard PRIVATE App)

add_test(NAME appkit-text-view-pasteboard COMMAND text_view_pasteboard)
set_tests_properties(appkit-text-view-pasteboard PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE TEXT VIEW'S CONTAINER, ITS MARGIN AND THE POINT THAT MAPS TO A CHARACTER.** The margin is checked in PIXELS —
# the ink moves by exactly the inset that was set, in both directions — and the point-to-character door is checked in
# BOTH margins against the character boxes `-firstRectForCharacterRange:` reports, so the drawing and the hit test are
# held to one coordinate space rather than to their own arithmetic. The caret is the door's reader: no session, no ink;
# a session, dark ink in the control colour; a colour set, green ink in the same column and none of the old. The two
# doors no pixel can witness (the dirty rect and the insertion-point state) are checked with a recording subclass, and
# the container doors are checked from both sides: the manager's list, the container's back-pointer, and the size
# `-setTextContainer:` carries into a container that `-replaceTextContainer:` deliberately does not.
add_executable(text_view_container text_view_container.m)
target_link_libraries(text_view_container PRIVATE App m)

# **NSText'S OWN ERA SURFACE.** A field has ONE RUN, and most of this slice is about saying so honestly: the two range
# doors set that run, the RTF pair carries it out and takes only the characters back, the resizability flags are read by the
# edit path (a resizable field re-fits after every edit) and the limits clamp it, the spelling check selects the first
# misspelling, and the panel plus the four run commands refuse by name.
add_executable(text_surface text_surface.m)
target_link_libraries(text_surface PRIVATE App m)

# **THE TEXT VIEW'S LAST THIRTY-NINE.** The real third is three small features: a colour panel changing a document's
# background (gated by its flag), a link the delegate may route or that opens its URL, and word completion — the partial word
# at the caret, the document's words that start with it, and the insert that replaces exactly what was typed. The refusing
# two thirds is measured too: each door answers its type's empty value rather than crashing or inventing one.
add_executable(text_view_last text_view_last.m)
target_link_libraries(text_view_last PRIVATE App)

add_test(NAME appkit-text-view-last COMMAND text_view_last)
set_tests_properties(appkit-text-view-last PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

add_test(NAME appkit-text-surface COMMAND text_surface)
set_tests_properties(appkit-text-surface PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

add_test(NAME appkit-text-view-container COMMAND text_view_container)
set_tests_properties(appkit-text-view-container PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **WHAT TYPING DOES AROUND IT: THE SMART SPACE, THE SMART DELETE, AND THE UNDO GROUP.** Every claim here is about the TEXT
# afterwards — a space that is in the store, a space that is not, a word that comes back — so the probe compares `-string`
# before and after rather than reading the flags back. The undo half runs against a real `NSUndoManager` supplied by a
# window delegate, which is also the assertion that `-windowWillReturnUndoManager:` is SENT at last: the chain had the door
# declared on the delegate and the walk documented on the responder, and no caller between them until now.
add_executable(text_view_undo text_view_undo.m)
target_link_libraries(text_view_undo PRIVATE App)

add_test(NAME appkit-text-view-undo COMMAND text_view_undo)
set_tests_properties(appkit-text-view-undo PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE ERA'S WHOLE COMMAND SET, AND WHERE THE PAGE KEYS LAND.** `NSResponder` declares the fifty-seven commands a key
# binding can name — the movement families, the paragraph set, paging and scrolling, the mark and kill ring, the case and
# direction families — and every body is one `-nextResponder:` send. The probe registers ONE C function for all
# fifty-seven and records `_cmd`, so the assertion is that the message ARRIVED at the end of the chain rather than that a
# method exists; then it drives the commands a text view answers, including the KEYS themselves through the input
# context's binding, because a mapping that names a selector nobody answers is the shape this file exists to catch.
add_executable(responder_commands responder_commands.m)
target_link_libraries(responder_commands PRIVATE App m)

add_test(NAME appkit-responder-commands COMMAND responder_commands)
set_tests_properties(appkit-responder-commands PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE STEPPER PAIR AND THE SECURE FIELD PAIR.** The stepper's press IS the step: the probe drives the cell's own tracking
# hooks in each half of the control, in BOTH flips (a direction that a flip reverses), checks the clamp, the wrap, the action
# a target receives and that a drag does not step again — then renders the cell and counts ink. The secure field's claim is
# the ink: `-cg_contentText` answers bullets, and the field is rendered with the flag on and off so the two renderings'
# dark pixels can be compared — a substitution that is not drawn is not a password field.
add_executable(stepper_and_secure stepper_and_secure.m)
target_link_libraries(stepper_and_secure PRIVATE App)

add_test(NAME appkit-stepper-and-secure COMMAND stepper_and_secure)
set_tests_properties(appkit-stepper-and-secure PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE NIB CONNECTIONS AND THE PASTEBOARD ITEM.** A connector's claim is the graph it joins, so the probe checks the objects
# on the other side (an outlet through KVC, an action as a real target/selector pair) and that the base class changes
# nothing. The item is checked as round trips, as LAZINESS (a provider is not asked until its type is read, and is asked once
# because the answer is cached), and then through `NSPasteboard -writeObjects:` — the writer contract by
# -respondsToSelector:, which is how a class becomes a writer in a tier that has not got NSPasteboardWriting.
add_executable(nib_connectors_and_items nib_connectors_and_items.m)
target_link_libraries(nib_connectors_and_items PRIVATE App)

add_test(NAME appkit-nib-connectors-and-items COMMAND nib_connectors_and_items)
set_tests_properties(appkit-nib-connectors-and-items PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **NSGlyphInfo, NSImageCell, NSCollectionViewItem AND THE THREE PASTEBOARD PROTOCOLS.** The glyph info resolves a name
# through the face (and refuses one it has not got); the image cell's alignment and scaling are read off the PIXELS, in
# three renderings, because a stored fact the drawing ignores would pass every value check; the item's selection is checked
# to redraw its tile; and the protocols are checked as CONFORMANCE plus one `protocol_getMethodDescription`, which is what a
# declaration buys over the `-respondsToSelector:` spelling that worked before.
add_executable(glyph_info_image_cell glyph_info_image_cell.m)
target_link_libraries(glyph_info_image_cell PRIVATE App)

add_test(NAME appkit-glyph-info-image-cell COMMAND glyph_info_image_cell)
set_tests_properties(appkit-glyph-info-image-cell PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **NSBox.** The geometry first — the content inside the border and the margins, the title's band above the content, and
# `-setFrameFromContentFrame:` as the inverse — and then the FIVE KINDS as five pictures: a separator is a line across the
# middle, a custom box fills its rectangle with its own colour, and a primary box is ink at the edges with an empty middle,
# which is what "frame" means.
add_executable(box box.m)
target_link_libraries(box PRIVATE App)

add_test(NAME appkit-box COMMAND box)
set_tests_properties(appkit-box PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **NSTabView AND NSTabViewItem.** The claim is that selection is a SWAP OF PANES and not a pile of hidden views: exactly one
# pane is in the hierarchy at a time and it is the selected item's, checked before and after a selection. The delegate is
# asked before the change and may REFUSE — the probe counts the three messages and then refuses, requiring the panes not to
# move. Then the strip's geometry (a hit test per tab, the content shrinking on the edge the type names) and the ink.
add_executable(tab_view tab_view.m)
target_link_libraries(tab_view PRIVATE App)

add_test(NAME appkit-tab-view COMMAND tab_view)
set_tests_properties(appkit-tab-view PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE ANIMATION FAMILY.** The curves are checked against the properties their names promise (ease-in below the line, ease-out
# above it, ease-in-out symmetric), a delegate can REPLACE the curve, marks are announced once each, and the chains start a
# second animation at the mark they name. Then a REAL TIMED RUN: the run loop pumps a 0.15-second animation and it must end on
# its own — the assertion a hand-stepped animation cannot make. The view animation interpolates frames and fades by the value,
# and the context's grouping is a scope nesting restores.
add_executable(animation animation.m)
target_link_libraries(animation PRIVATE App)

add_test(NAME appkit-animation COMMAND animation)
set_tests_properties(appkit-animation PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE LEVEL INDICATOR.** The claim is that the value becomes a PICTURE and the thresholds become a COLOUR: half full is a bar
# whose left is the level colour and whose right is the ground, warning is the platform's orange, critical is red — and the
# discrete and rating styles are lit segments and filled stars. A value check cannot see any of that, which is why the probe
# reads pixels.
add_executable(level_indicator level_indicator.m)
target_link_libraries(level_indicator PRIVATE App)

add_test(NAME appkit-level-indicator COMMAND level_indicator)
set_tests_properties(appkit-level-indicator PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE DATE PICKER.** A date field is a text field whose text is a FORMATTED date of the cell's own locale, calendar and
# time zone, so the probe changes each door and requires the text to follow (de_DE's day-first order, a +12 zone that moves
# the day, an element flag that removes a field). The subfield a click selects is the run measured in that text, and stepping
# it is the CALENDAR's arithmetic (January 31 + 1 month is February 28). The delegate's one in/out message is exercised three
# ways — accept, replace, refuse — and the pictures are pixels: the hour hand at 03:00 and 09:00, the month grid's accent
# chip, and the stepper's arrows in a strip the text-only style leaves empty.
add_executable(date_picker date_picker.m)
target_link_libraries(date_picker PRIVATE App)

add_test(NAME appkit-date-picker COMMAND date_picker)
set_tests_properties(appkit-date-picker PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE DOCUMENTS.** A concrete NSDocument subclass implements ONLY the modern data pair; the probe creates one untitled,
# edits it, saves it through the URL door, opens it with a controller, reverts it, saves it again and closes it, with the
# default wrapper -> data path exercised in both directions. The change count follows the document's own undo manager
# through the notifications it subscribes to. The controller is a subclass with its own type table, so no Info.plist is
# needed: the base's type -> class -> make/open chain is what is being tested. Close-all refuses while a document is edited.
add_executable(document document.m)
target_link_libraries(document PRIVATE App)

add_test(NAME appkit-document COMMAND document)
set_tests_properties(appkit-document PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE DOCUMENT'S TAIL: AUTOSAVE, CLOSE REVIEW, THE FILENAME STATE AND THE ERROR CHAIN.** The autosave is measured as a
# separate file, a reopened document, and a real save that deletes the obsolete copy; close decisions use the private
# seam for the alert's answer; and the error chain is checked with a recorder as the controller's presenter.
add_executable(document_tail document_tail.m)
target_link_libraries(document_tail PRIVATE App m)
add_test(NAME appkit-document-tail COMMAND document_tail)
set_tests_properties(appkit-document-tail PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE SAVE AND OPEN PANELS.** A temp directory with files, a subdirectory, a hidden file and a file the delegate hides;
# a save panel accepts a name (with the allowed type's extension and the deprecated required type), navigates into a
# selected directory and back through ".."; the delegate vetoes a URL, renames one, and its filters remove entries from
# the listing. The open panel answers one file, many files, or a directory, and the type filter keeps a .rtf out of a
# text-only open panel while a save panel still shows it. The sheet and modeless forms call their blocks with the code, and
# the deprecated begin reaches the caller's selector.
add_executable(save_panel save_panel.m)
target_link_libraries(save_panel PRIVATE App)

add_test(NAME appkit-save-panel COMMAND save_panel)
set_tests_properties(appkit-save-panel PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE POP-UP'S ITEMS, THE COLOUR'S SPACE AND THE MENU'S FLAGS.** The item arithmetic (add, insert, remove, titles,
# the two index lookups) goes through the button into the cell's menu, and the cell's two flags are behaviour: a pick
# copies the item's title unless usesItemFromMenu is off, and altersStateOfSelectedItem toggles the chosen row's state
# instead of clearing the others. A colour answers its space name (calibrated for a named space, device for an unnamed
# one) and -set is checked by filling a bitmap and reading the pixel back red.
add_executable(popup_color_menu popup_color_menu.m)
target_link_libraries(popup_color_menu PRIVATE App)

add_test(NAME appkit-popup-color-menu COMMAND popup_color_menu)
set_tests_properties(appkit-popup-color-menu PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE FIRST ABSENT EDITOR ARRIVES: THE TOKEN FIELD AND ITS CELL.** The list is the base cell's one value, and the probe
# drives the four spellings of it: a typed string tokenized, an array set directly, an editor seeded with the EDITING
# strings (which a delegate makes differ from the display strings), and the chip INK a per-token style changes. The
# session's ending is where a typed run becomes a REVIEWED list, so the addition review is measured on both answers; the
# completion's sign is the switch and a unique offer's appended letters are selected; the pasteboard pair is checked on
# both sides of its gates; and the menu's hit test finds a chip without a window or an event.
add_executable(token_field token_field.m)
target_link_libraries(token_field PRIVATE App m)
add_test(NAME appkit-token-field COMMAND token_field)
set_tests_properties(appkit-token-field PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE FIRST ABSENT EDITOR'S NEIGHBOUR: THE DRAWER, AND THE CHILD WINDOW IT IS.** The probe measures the CHILD
# WINDOW's frame for every edge, because a drawer is a window rather than a stored size; the four states are read from
# inside the two Will/Did announcements, which is where the synchronous transition makes them observable. The parent
# relationship is checked from both sides (registration, the parent's retention, a swap, and the parent's death), and the
# user's resize is the one door where the minimum/maximum clamp and the delegate's review have an order.
add_executable(drawer drawer.m)
target_link_libraries(drawer PRIVATE App m)
add_test(NAME appkit-drawer COMMAND drawer)
set_tests_properties(appkit-drawer PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE VISIBILITY RULE NEEDS GLASS.** A drawer is shown only while its parent is visible, key and in an active
# application; key alone is not enough because deactivation keeps the key flag, and visible alone is not enough
# because ordering out does not resign it. This runs under the headless compositor and skips (77) when none starts.
add_executable(drawer_visibility drawer_visibility.m)
target_link_libraries(drawer_visibility PRIVATE App)
add_test(NAME appkit-drawer-visibility
  COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/run-appkit-headless.sh"
    "$<TARGET_FILE:drawer_visibility>" 2 "drawer_visibility: ok")
set_tests_properties(appkit-drawer-visibility PROPERTIES SKIP_RETURN_CODE 77
  ENVIRONMENT "${_agora_app_test_env}")

# **THE FIRST ABSENT COLLECTION: THE GRID, THE ITEM POOL AND THE TWO DRAG HALVES.** The layout is measured through
# `-frameForItemAtIndex:` and the tiles' own frames, the selection through both the index set and the items, and the
# backdrop through pixels (one colour flat, two a gradient). The item pool is checked by identity across a content
# change; the drag source and destination are driven through real delegate doors, with a fake NSDraggingInfo for the
# proposal arithmetic. No compositor and no run loop are needed.
add_executable(collection_view collection_view.m)
target_link_libraries(collection_view PRIVATE App m)
add_test(NAME appkit-collection-view COMMAND collection_view)
set_tests_properties(appkit-collection-view PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE RULE EDITOR: THE DELEGATE'S TREE, THE FLAT NUMBERING AND THE FOUR MODES.** The grid of checks is the row tree:
# the initial path (first root, first child to a leaf), a caller-set path extended the same way, `-reloadCriteria` keeping
# the longest valid prefix when the tree changes, the boundary rule that raises inside another subtree, and adoption on
# removal. The pointer is measured through a click (and ignored when not editable), the drawing through the accent band,
# the formatting dictionary's ink and a VIEW display value becoming a subview, and the predicate doors through the
# delegate's parts method before the nil answer.
add_executable(rule_editor rule_editor.m)
target_link_libraries(rule_editor PRIVATE App m)
add_test(NAME appkit-rule-editor COMMAND rule_editor)
set_tests_properties(appkit-rule-editor PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE GENERIC BINDING LAYER: ONE OBJECT OBSERVES ANOTHER AND WRITES THE VALUE THROUGH KVC.** No view and no
# controller: a target's `title` is bound to a source's `name`, and the probe reads the value the TARGET holds after each
# write. It covers the Initial notification, the automatic setter's delivery, `-infoForBinding:`, unbind, rebind, the
# NSNull placeholder, the marker pass-through and the raise option, `+exposeBinding:`/`-exposedBindings`, the
# placeholder table, and the NSEditor defaults (including the delegate's `-editor:didCommit:contextInfo:`).
add_executable(binding_base binding_base.m)
target_link_libraries(binding_base PRIVATE App m)
add_test(NAME appkit-binding-base COMMAND binding_base)
set_tests_properties(appkit-binding-base PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE FIRST CONTROLLER SLICE: `NSController`'S EDITING BOOKKEEPING AND `NSObjectController`'S CONTENT AND SELECTION.**
# No view and no display: the editing half is a VALUE test of who was asked and in what order (including the editor
# withdrawn by another editor's commit), the selection half is a value test of the proxy over nothing/one/several
# objects, and the KVO half is a DELIVERY test of the dependent-key announcements the controller sends by hand. The
# Core Data doors are read for their type's empty answers; the refusal itself is `appkit-refusal-census`'s to count.
add_executable(controller_base controller_base.m)
target_link_libraries(controller_base PRIVATE App m)
add_test(NAME appkit-controller-base COMMAND controller_base)
set_tests_properties(appkit-controller-base PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE ARRAY CONTROLLER: THE ARRANGEMENT, THE SELECTION INTO IT, AND THE INDEX TRANSLATION.** No view: the arrangement
# is measured by its ORDER and the filter by which objects survive, the insertion doors by where the object landed in
# the CONTENT (the arranged index is the argument; the content is where the translation shows), and each policy flag
# against the behaviour it changes. The KVO half is a delivery test of arrangedObjects/selectedObjects, and the binding
# half checks that a target bound to arrangedObjects receives the re-arranged array.
add_executable(array_controller array_controller.m)
target_link_libraries(array_controller PRIVATE App m)
add_test(NAME appkit-array-controller COMMAND array_controller)
set_tests_properties(appkit-array-controller PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE DEFAULTS CONTROLLER: THE `values` PROXY, THE THREE-LEVEL READ, AND THE PENDING STORE.** The chain is asked in
# all three spellings a caller has (the proxy, the `values.` key, the `values.` key path); the policy half is measured
# by WHERE the value landed and by the two announcements that describe it — the store's own for a committed write and
# `hasUnappliedChanges` for a held one. The observation boundary is pinned too: a `values.<key>` registration lives on
# the store, so the change's object is the store and its path is the bare key.
add_executable(user_defaults_controller user_defaults_controller.m)
target_link_libraries(user_defaults_controller PRIVATE App m)
add_test(NAME appkit-user-defaults-controller COMMAND user_defaults_controller)
set_tests_properties(appkit-user-defaults-controller PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE DICTIONARY CONTROLLER: A KEY/VALUE PROJECTION WHOSE ARRANGED OBJECTS ARE LIVE PAIRS.** The probe measures the
# three KVC names a column binds to, the visible-key rules (included then excluded), the arrangement over the pairs, a
# pair's writes landing in the dictionary, and — the part a value test would miss — that the pair for a key is the SAME
# OBJECT across a content replacement, which is what lets the inherited settle step keep the selection.
add_executable(dictionary_controller dictionary_controller.m)
target_link_libraries(dictionary_controller PRIVATE App m)
add_test(NAME appkit-dictionary-controller COMMAND dictionary_controller)
set_tests_properties(appkit-dictionary-controller PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE TREE CONTROLLER: A MODEL TREE, A REBUILT NODE GRAPH, AND PATHS IN BETWEEN.** The probe measures the shape as
# `indexPath`s and every mutation against the MODEL's arrays, because the node graph is the controller's reading and the
# model is what a caller owns; the selection is measured by OBJECT across a rebuild that renumbers it. The two model
# errors are measured by their REFUSAL (a truncated node) — the build runs inside a KVO announcement, so an exception
# there would leave the will half's records open.
add_executable(tree_controller tree_controller.m)
target_link_libraries(tree_controller PRIVATE App m)
add_test(NAME appkit-tree-controller COMMAND tree_controller)
set_tests_properties(appkit-tree-controller PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE PREDICATE WORK THE RESTORED FOUNDATION FAMILY UNBLOCKED.** Three layers, each measured by EVALUATION rather than
# shape: the rule editor assembles its delegate's parts into predicates that must evaluate the way the delegate meant,
# a row template's matching is measured by which predicates it accepts, and the predicate editor's round trip (predicate
# in, rows out, edit a row, predicate out) by what the second predicate evaluates to — a shape test would pass for a
# predicate assembled backwards. The attribute factory is driven with a real NSEntityDescription.
add_executable(predicate_editor predicate_editor.m)
target_link_libraries(predicate_editor PRIVATE App AgoraData::Data m)
add_test(NAME appkit-predicate-editor COMMAND predicate_editor)
set_tests_properties(appkit-predicate-editor PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE CROSS-IMAGE SELECTOR FIX: an item built HERE validates against a document and its controller.** This runtime
# gives each image its own selector struct for the same name, so the item's `-action` is a different address from the
# library's `@selector(saveDocument:)`; the two `validateUserInterfaceItem:` doors compare with `sel_isEqual` now, and a
# fix that went back to `==` fails here.
add_executable(validation_selectors validation_selectors.m)
target_link_libraries(validation_selectors PRIVATE App m)
add_test(NAME appkit-validation-selectors COMMAND validation_selectors)
set_tests_properties(appkit-validation-selectors PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **THE DOCK TILE: one object per application, a badge that is kept and pushed, and the Dock's lookup.** With no
# compositor there is nowhere for the label to go, so this measures the APPLICATION's contract; the travel is the window
# server's `window_list` probe (a badge arrives beside its window) and `dock`'s own drawing.
add_executable(dock_tile dock_tile.m)
target_link_libraries(dock_tile PRIVATE App m)
add_test(NAME appkit-dock-tile COMMAND dock_tile)
set_tests_properties(appkit-dock-tile PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# **AND THE CLIENT HALF OF HIDPI, WHICH NEEDS BOTH HALVES OF THE STACK IN ONE TEST.** The compositor runs at `--scale 2`
# and an AppKit window draws a shape at a known POINT; the checker measures where it landed in DEVICE pixels. A client
# that ignored the scale would draw it half the size, half the distance from the corner — the whole UI shrunk.
add_executable(appkit_hidpi appkit_hidpi.m)
target_link_libraries(appkit_hidpi PRIVATE App)

add_test(NAME appkit-hidpi
  COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/run-appkit-hidpi.sh"
    "${AGORA_WINDOW_SERVER_BINARY}" "$<TARGET_FILE:appkit_hidpi>"
    "${_agora_api_python}" "${CMAKE_CURRENT_SOURCE_DIR}/check_hidpi.py")
set_tests_properties(appkit-hidpi PROPERTIES SKIP_RETURN_CODE 77
  ENVIRONMENT "${_agora_app_test_env}")

# **AND THE SAME CASE ON AN ORDINARY SCREEN, because the assertions must hold at BOTH.** A test that passes only at 2x
# could be measuring "a shape twice the size" rather than "a shape the size the output says" — the pair is what makes
# the SCALE the variable, with the layout, the window's placement and the square's size in points unchanged.
add_test(NAME appkit-hidpi-scale1
  COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/run-appkit-hidpi.sh"
    "${AGORA_WINDOW_SERVER_BINARY}" "$<TARGET_FILE:appkit_hidpi>"
    "${_agora_api_python}" "${CMAKE_CURRENT_SOURCE_DIR}/check_hidpi.py" 1)
set_tests_properties(appkit-hidpi-scale1 PROPERTIES SKIP_RETURN_CODE 77
  ENVIRONMENT "${_agora_app_test_env}")

# **AND AT 1.5, WHICH IS THE CASE THE TWO HALVES HAVE TO DISAGREE ABOUT ON PURPOSE.** The compositor draws 1.5 device
# pixels per logical one, and `wl_output.scale` can only say 2 — so the client renders at 2x and the compositor
# downsamples 2 -> 1.5. A 20-point square must therefore measure 30 device pixels, not 20 and not 40.
add_test(NAME appkit-hidpi-1-5
  COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/run-appkit-hidpi.sh"
    "${AGORA_WINDOW_SERVER_BINARY}" "$<TARGET_FILE:appkit_hidpi>"
    "${_agora_api_python}" "${CMAKE_CURRENT_SOURCE_DIR}/check_hidpi.py" 1.5)
set_tests_properties(appkit-hidpi-1-5 PROPERTIES SKIP_RETURN_CODE 77
  ENVIRONMENT "${_agora_app_test_env}")

# **AND A SCALE THAT IS PARTLY THE PERSON'S, BECAUSE THAT IS ONE NUMBER TOO.** The compositor is told `--scale 2` and
# `--ui-scale 0.75`, so the output it composites at is 1.5 — and the client is told 1.5 through the same
# `agora_output.preferred_scale` it was always told, rasterises at it, and is placed 1:1. Nothing on the client side
# knows the factor exists; a 20-point square still measures 30 device pixels. This is the proof that the comfort
# factor is a compositor decision rather than a second scaling system in the toolkit.
add_test(NAME appkit-hidpi-ui-scale
  COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/run-appkit-hidpi.sh"
    "${AGORA_WINDOW_SERVER_BINARY}" "$<TARGET_FILE:appkit_hidpi>"
    "${_agora_api_python}" "${CMAKE_CURRENT_SOURCE_DIR}/check_hidpi.py" 2 0.75)
set_tests_properties(appkit-hidpi-ui-scale PROPERTIES SKIP_RETURN_CODE 77
  ENVIRONMENT "${_agora_app_test_env}")

# §11 W8.1: the AppKit's one Core Data class, over a real file.
add_executable(persistent_document persistent_document.m)
target_link_libraries(persistent_document PRIVATE App)

add_test(NAME appkit-persistent-document COMMAND persistent_document)
set_tests_properties(appkit-persistent-document PROPERTIES ENVIRONMENT "${_agora_app_test_env}")
