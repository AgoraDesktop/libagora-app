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

# Writing an image out. The class's encoder door refused for its whole life because Core Graphics had no
# `CGImageDestination`; this probe measures the answer with the class's own decoder and every refusal that
# remains beside it.
add_executable(appkit_bitmap_encode appkit_bitmap_encode.m)
target_link_libraries(appkit_bitmap_encode PRIVATE App)

add_test(NAME appkit-bitmap-encode COMMAND appkit_bitmap_encode)
set_tests_properties(appkit-bitmap-encode PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# The package form of the RTF document: TXT.rtf plus one file per attachment, and the reference between them.
add_executable(text_rtfd text_rtfd.m)
target_link_libraries(text_rtfd PRIVATE App)

add_test(NAME appkit-text-rtfd COMMAND text_rtfd)
set_tests_properties(appkit-text-rtfd PROPERTIES ENVIRONMENT "${_agora_app_test_env}")

# The refusal census: every `APPKIT-REFUSE` site in this library, counted against the committed table in BOTH
# directions. `nm` cannot answer here — every door in this layer is an Objective-C method, which is dispatched
# dynamically and appears in no symbol table — so the census counts the sites the prose itself makes.
add_test(NAME appkit-refusal-census
    COMMAND "${CMAKE_COMMAND}"
            "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}/.."
            "-DCENSUS=${CMAKE_CURRENT_SOURCE_DIR}/refusal_census.txt"
            "-DEXTENSION=.m"
            "-DNEEDLE=APPKIT-REFUSE"
            -P "${CMAKE_CURRENT_SOURCE_DIR}/claims_census.cmake")

# And the same instrument over the HEADERS, counting the OWED claims — as a WORD, so `ALLOWED` does not count.
add_test(NAME appkit-owed-census
    COMMAND "${CMAKE_COMMAND}"
            "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}/.."
            "-DCENSUS=${CMAKE_CURRENT_SOURCE_DIR}/owed_census.txt"
            "-DEXTENSION=.h"
            "-DNEEDLE=(^|[^A-Za-z_])OWED"
            -P "${CMAKE_CURRENT_SOURCE_DIR}/claims_census.cmake")

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
