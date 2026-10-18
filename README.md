# libagora-app

**The Application Kit for Agora** — the Cocoa-compatible window, view, control and menu classes
(`NSWindow`, `NSView`, `NSApplication`, `NSMenu` and the rest).

Agora is an installable desktop environment for Linux and BSD; see the project README in the parent
directory (`../README.md`). `libagora-app` is the top of its stack: above it there are only applications.

## Status

**The AppKit is imported and its windows run on Agora's window server. The X11 seam is gone.** Above the
window and view classes there is now a cell and control layer (buttons, switches and sliders), a tracking-area
engine, one line of editable text with the standard key bindings, a title bar the client DRAWS itself, the menu
subsystem — validation, a selection chip, and a pointer grab that lets a popup be dismissed by clicking away —
and a TOOLBAR: items from a delegate, in a band the window reserves between its chrome and its content.

The classes here come from the Fiwix AppKit (same author, same licence — see `PROVENANCE.md`), and they
talked to an X server: `NSWindow.m` called `XOpenDisplay`, `XCreateSimpleWindow`, `XMapWindow`, `XPutImage`
and `XNextEvent` directly, and `NSScreen.m` opened the display for its own size. Agora's display target is
**Wayland**, with no X11-native target, so that seam was replaced by this repository's own
`platform/AGWindowServer.h` — an interface, with an `xdg-shell` client as its first implementation. The
library no longer links `libX11` at all:

```
$ readelf -d build/libagora-app.so | grep NEEDED
  libagora-base.so  libagora-text.so  libagora-drawing.so  libagora-core.so
  libobjc.so.4.6  libm.so.6  libwayland-client.so.0  libxkbcommon.so.0  libc.so.6
```

```
platform/
  AGWindowServer.h              the seam: connection, windows, frames, events
  AGWindowServer-Wayland.c      its first implementation: an xdg-shell client + wl_output
  AGKeyboard.h / AGKeyboard.c   evdev key codes -> text and modifiers, through xkbcommon
NS*.h / NS*.m                   the AppKit itself — window, view, application, controls, menus, fonts
tests/
  window.c                      the seam alone, with no AppKit
  keyboard.c                    the keymap translation, with no compositor anywhere
  appkit_window.m               THE APPkit: a real NSWindow with a real NSView
  appkit_events.m               the INPUT PATH: the seam's event, to the view that should get it
  control_ink.m                 the CONTROL layer: a view that draws its cell, and a button's face
  control_metrics.m             and the METRICS: a button's height and a line of text's
  slider_ink.m                  a control whose VALUE is a POSITION: the knob and its inverse
  tracking_area.m               an AREA's region, owner and SCOPE — and a control's own hover area
  text_input.m                  the first slice of the text system, driven a keystroke at a time
  text_storage.m                and the STORE the rich-text slice is built on: an attributed string that announces edits
  text_container.m              and the REGION that store is laid out in: a size, a padding, and the fragments that fit
  text_container_region.m       and a SHAPED region: the container's subrect places and narrows the line, holes split it
  text_layout_web.m             and the WEB that ties the trio together: the store, its managers, and what goes stale
  text_layout_fragments.m       and the FRAGMENTS that web produces: the store laid into the container's lines
  text_layout_draw.m            and the INK: the manager drawing the glyphs it laid out, where the origin says
  text_layout_attributes.m      and the BACKGROUND, UNDERLINE and STRIKETHROUGH keys the manager paints, run by run
  text_layout_overflow.m        and the SECOND CONTAINER: what does not fit the first is carried to the next
  text_layout_glyphs.m          and the GLYPH STORE: the generated lines, and the four reverse lookups
  text_paragraph_style.m        and the PARAGRAPH STYLE: the value object, and the alignment and line-break mode
  text_paragraph_geometry.m     and its GEOMETRY: the indents, the spacings and the line heights the layout reads
  text_attachment.m             and the ATTACHMENT: a character that stands for a picture, and the cell that draws it
  text_input_context.m          and the INPUT CONTEXT: where a key goes before the view, and where a composition lives
  text_input_method.m           and the METHOD: a dead key composes with the next keystroke, marked until it does
  text_candidate_list.m         and the CANDIDATE LIST: a letter's readings, the window under the caret, and the pick
  text_writing_direction.m      and the BASE DIRECTION: what NATURAL alignment means, and the locale's language direction
  text_editing_commands.m       and `-transpose:` plus the insertions that ignore a field's role
  text_table.m                  and the TABLE BLOCK: the box a paragraph is set in, drawn by the manager
  text_rtf.m                    and RTF: the reader's control words, and an AppKit-aware WRITER beside it
  text_table_grid.m             and the GRID: cells side by side, columns measured, rows as tall as their tallest cell
  text_table_collapse.m         and `-collapsesBorders`: an edge two cells share is drawn once, by the min-side cell
  text_table_flow.m             and the FLOW: a row that does not fit goes on in the next container, columns unmoved
  text_attachment_flow.m        and the attachment's BOX: a fixed-size run the text flows around
  text_attachment_tracking.m    and the attachment's TRACKING: the view presses it, the cell follows, one event per call
  text_tab_stops.m              and the TAB STOPS: a tab goes to its place, named by the paragraph style
  text_word_movement.m          and its WORD granularity: Option+arrow and Option+Delete, over the string
  text_view_lines.m             and the first slice of the MULTI-LINE view: the line model, and what reads it
  text_view_wrapping.m          and the slice above it: the same model WRAPPED to the view's width
  text_view_scrolling.m         and above that: the view in a SCROLL VIEW, and the doors that move it
  text_view_store.m             and the VIEW reading the store through the manager, its own layout gone
  text_marked_text.m            and the MARKED TEXT: the composition an input method drives through `NSTextInput`
  text_field_cell.m             a FIELD's cell: its string, its face, and one edit session end to end
  text_field_control.m          and the VIEW above it: a press that opens a session, and what commits it
  text_field_bezel.m            and its BORDER's two shapes, read out of the corner PIXELS
  text_field_placeholder.m      and what an EMPTY field says it is for: a hint, drawn DIMMER than a value
  text_field_attributes.m       and what it MAY HOLD: the two attributed-editing flags, and the editor they reach
  clip_view.m                   the INSIDE of a scroll view: the arithmetic, and the wire that re-runs it
  scroller.m                    and its BAR: a fraction into a knob, a point into a part, a drag back into a value
  scroll_view.m                 and the FRAME that joins them: the tiling, the loop, and -enclosingScrollView
  view_offset.m                 and the ONE THING a scroll moves: a non-zero `bounds` origin, drawn and converted
  window_chrome.m               the DRAWN chrome, offscreen: the symbols, the centred title and the pill
  menu_validation.m             validation and state, which the view tests do not reach
  appkit_activation.m           only the ACTIVE application's menu bar shows
  appkit_controls_draw.m        a window full of controls, a SCROLL PANEL, and a TEXT PLAYGROUND window
  chrome_theme.m                the THEME: an XFWM `.xpm` set becomes the chrome's buttons, 1:1
  chrome_buttons.m              and what a chrome button DOES: a click through the seam, and what happened
  toolbar.m                     the TOOLBAR: the delegate's items, the band, the ink and the click
  control_drag.m                and what a DRAG costs: forty motions, and how many frames the window committed
  run-*-headless.sh             ctest: a compositor with a virtual monitor (no desktop input involved)
  run-*-nested.sh, inspect.py   the PIXEL tests, and they are OPT-IN: `gnome-shell --nested` is a whole
                                nested session and it grabs the HOST's pointer while it lives
```

### What is measured, not assumed

Everything below ran on this machine against GNOME Shell / mutter 48.7.

- **The AppKit draws through a real window** (`ctest`, headless compositor with a virtual monitor): an
  `NSWindow`, an `NSView` overriding `-drawRect:`, pumped through `NSApplication`.
  `179 frame(s)` in three seconds, and the window came back **configured to 640x422** — the 640x400 content
  rect plus the 22-point title bar this AppKit draws itself.
**The two `run-*-nested.sh` runners are opt-in (`AGORA_ALLOW_NESTED=1`), and that is not caution for its own
sake:** a nested `gnome-shell` is a whole nested desktop session, and it takes over the pointer of the
desktop it is started from while it lives. A run that does not unwind leaves the host with a stuck
pointer grab — measured once: `XGrabPointer` answered `AlreadyGrabbed` while the keyboard grab was free,
which is exactly "the cursor moves and the buttons do nothing", cleared by restarting GNOME Shell in
place (`Alt+F2`, `r`, `Enter`). The script now refuses without the opt-in and escalates the kill until
the compositor is really gone.

- **The pixels reach an output** (`tests/run-appkit-nested.sh`, a nested compositor on the desktop, two
  screenshots read back by `inspect.py`): red marker at the top-left, green at the bottom-right, the R
  gradient rising left to right and the G gradient top to bottom, and the bar — positioned by the clock —
  moving `+290 px` between two captures 1.2 s apart. That is `NSView -drawRect:` → `NSWindow` → the seam →
  the compositor → a screenshot, with nothing mocked.
- **Events arrive where they should** (`ctest`, `tests/appkit_events.m`): the seam's `AGEvent` built by hand
  and pushed through the window, then pumped by `NSApplication` and dispatched by `-sendEvent:` — 10 checks,
  including that a key reaches the FIRST RESPONDER with the character xkbcommon produced, that a MODIFIER
  arrives as `-flagsChanged:` rather than as a keystroke, that a click lands on THE VIEW UNDER THE POINTER,
  and that a view which does not handle an event BUBBLES it up the responder chain.
- **The seam alone** (`ctest`): exactly 60 of 60 frames headless, and the keymap translation checked against
  a pinned `us` keymap.
- **The controls** (`ctest`, all offscreen): a button draws its bezel and title and sends its action; a switch
  draws an indicator and a radio a different one; a slider's `-knobRect:flipped:` and its inverse agree at the
  knob's centre and clamp past either end; and a push button's height is a bezel METRIC rather than a property
  of its title.
- **The tracking engine** (`ctest`): the same rectangle, the same owner and the same pointer produce an ENTER
  for `NSTrackingActiveAlways` and NOTHING for the default `NSTrackingActiveInKeyWindow` in a window that is not
  key — the scope word that keeps a background window's controls dark; `-mouseMoved:` fires when the point moves
  and not when it is repeated; `[event trackingArea]` names the area that fired; and a control entering a window
  installs a hover area.
- **The text path** (`ctest`): a key is built as an `NSEvent`, `-interpretKeyEvents:` turns it into a command,
  and the command edits the string — typing, both Backspace spellings, movement, Shift-extension, and the
  notification and its delegate both firing for one edit.
- **And its word granularity** (`ctest`): Option+arrow moves to the WORD boundary and Option+Delete deletes one, and
  the reason `NSResponder.h` gave for leaving them out — that the family "need[s] a LAYOUT MODEL — words, paragraphs,
  several lines" — WAS WRONG FOR THESE, because a word is a run of the STRING's own characters (`+alphanumericCharacterSet`)
  and needs no layout at all. The correction is in that header; what the probe holds is the arithmetic. MEASURED: from
  `one two three` Option+Left lands at the start of `three` (8) and then `two` (4), and Option+Right crosses `one` (3)
  then `two` (7); the same keys from INSIDE a word go to that word's own boundary; digits belong to their word
  (`abc123` is one) and punctuation does not (`a...b` is two with three non-word characters between); a SELECTION
  collapses to its near end like any movement; Shift extends by the word (four characters, not one); and Option+Delete
  removes a word — or a selection WHOLE, word key or not — while Option+ForwardDelete removes the one after the caret.
- **And the first slice of the multi-line text view** (`ctest`): `NSTextView` holds many lines where `NSText` holds one,
  and the whole model is ONE sentence — a line is a `\n`-terminated run — which everything else reads. MEASURED: the
  line's range EXCLUDES its own newline; a TRAILING newline is an EMPTY last line and an empty string is ONE line;
  Return and Tab INSERT where a field ends a session and moves the focus; `-moveToBeginningOfLine:` means the CARET's
  line rather than the document's; Up and Down move by line — and the arrow keys are mapped to them at last, a
  one-line field simply answering neither — with the ends staying put; a click lands on the line it is over; TWO lines
  write ink in TWO bands while one writes nothing in the second; and `-sizeToFit` grows with the line count (**23.7**
  points for one line, **55.2** for three). Slice I does NOT wrap and does NOT scroll — a line wider than the view is
  clipped — and the header names wrapping, scrolling and rich text as the slices above it rather than stubbing them.
- **And the slice above it, WRAPPING** (`ctest`): the model gains a width, so a paragraph too wide becomes several
  VISUAL LINES — and the breaking is not this class's, it is the tier's TYPESETTER (`CTTypesetterSuggestLineBreak`),
  which reads the paragraph style's mode, handles a hard break itself and backs off to a word boundary. MEASURED: one
  model line, one visual line at width **400** and **4** at width **96**, with the MODEL count unmoved at 1; the ranges
  are contiguous and cover all **39** characters; the first wrapped line ends on a SPACE; a trailing newline is still an
  empty last visual line; `-moveToEndOfLine:` stops at the visual line's own end (index **9**, not 39) and
  `-moveToBeginningOfLine:` at its start; a click in the second band lands on the second visual line; the ink is in the
  second band at the narrow width (**336** pixels) and NOWHERE below the first band at the wide one (**0**), so the wrap
  is DRAWN and not just counted; and `-sizeToFit` keeps the width and grows the height (**23.7** points wide against
  **70.9** narrow). A layout is rebuilt on the next read after the text or the width changes, which is the three doors
  that can change either, and the trailing-whitespace rule (`-cg_textRangeOfVisualLine:`) is what makes the boundary
  between two wrapped lines one index rather than two.
- **And SCROLLING, which is the slice above that** (`ctest`, against a REAL `NSScrollView`): `NSView -scrollRectToVisible:`
  and `-scrollPoint:` find the closest enclosing CLIP VIEW, work in its coordinates and move the origin just far
  enough — the far-edge case moving it so the rectangle's MAX edge meets the visible MAX edge rather than putting its
  minimum there — and `NSTextView -scrollRangeToVisible:` turns a caret into the rectangle those two take. The height
  is the other half: a text view settles its own height after every edit so a clip view has something to scroll
  (`-isVerticallyResizable`, Apple's door, YES by default; a caller that owns the frame says NO). MEASURED: a
  twenty-line document is **338.3** points in a 60-point clip view; `-scrollRectToVisible:` moves the origin from
  **274.3** to **4.0** and answers NO when asked again for the same rectangle; a caret moved to the end is SCROLLED
  into view; `-scrollPoint:` puts the origin at the point given and CONSTRAINS a point past the end to the far edge;
  there is no horizontal origin at all (a wrapped document has nothing to scroll sideways); and an edit that adds a
  line grows the document. **AND THE DOCUMENT'S ORIENTATION IS PART OF THE SLICE RATHER THAN AN AFTERTHOUGHT**: a text
  view is FLIPPED, so its FIRST line sits at the clip view's origin and the origin grows as a reader moves DOWN the
  document — MEASURED, with the origin at 0 the first line is on screen, and the caret moved to the end leaves the
  origin at **258.6**.
- **And the STORE the rich-text slice is built on** (`ctest`): `NSTextStorage` is an `NSMutableAttributedString` that
  ANNOUNCES ITS OWN EDITS — the two primitives (`-replaceCharactersInRange:withString:`, `-setAttributes:range:`)
  record a mask, a range and a length change, `-beginEditing`/`-endEditing` coalesce a group into ONE
  `-processEditing`, and the announcement reaches a delegate and a listener registered for the name. MEASURED: a fresh
  store's edited range is `NSNotFound` — NOT zero, which is a real place in the string; inserting six characters
  reports the mask **Characters**, the range **(5,0)** in the ORIGINAL string and the delta **+6**; an attribute edit
  reports **Attributes** with a zero delta; two edits inside a group produce ONE announcement over their UNION — and a
  group of `-1` then `+2` reports delta **1**, with the second range brought back to the original's coordinates before
  the union, which is the arithmetic a naive accumulator gets wrong; and `-insertAttributedString:atIndex:`, a door
  the store NEVER OVERRODE, is announced anyway — the routing, by dispatch. **AND MOST OF WHAT THIS NOTE ONCE CALLED OWED HAS SINCE LANDED**, which is the correction that matters:
  `NSLayoutManager` EXISTS (it is the largest class in this layer and the subject of nine probes), the layout-manager web
  it belongs to is built, and what genuinely remains of this list is the scripting category and lazy attribute fixing
  (there is nothing to defer, because nothing here defers an attribute).
- **And the REGION that store is laid out in** (`ctest`): `NSTextContainer` is the middle of the trio and the smallest
  — four facts (a size, a line-fragment padding, two flags about tracking a view, and the view itself) and ONE
  computation: given a proposed line fragment, the part of it that falls inside. MEASURED: the size is what it was
  made with, the padding default is **10** points, both tracking flags are off and it says it is a SIMPLE RECTANGLE; a
  fragment inside the region answers itself and leaves `remainingRect` EMPTY (a rectangle has no holes); one running
  50 points past the right edge comes back **50** wide; one entirely past the region is EMPTY when the line may not
  move and is CARRIED to the region's near edge — **(200,10 100x20)** — when it may; and a fragment ABOVE the region
  is carried DOWN to its top edge, because a text view's y grows downward. **AND THE LAYOUT-MANAGER END OF THE WEB EXISTS NOW**, which the container's own header states: `-layoutManager`,
  `-setLayoutManager:` and `-replaceLayoutManager:` are implemented, the pointer is BORROWED in one direction because the
  manager retains the container, and `-replaceLayoutManager:` does the half that crosses the object boundary. **AND
  THE NON-RECTANGULAR REGIONS A SUBCLASS DECLARES ARE LAID OUT NOW, WHICH THIS SENTENCE USED TO CALL OWED**:
  `NSLayoutManager` asks `-isSimpleRectangularTextContainer` once per container; a YES keeps the cheap arithmetic every
  document already took (including this tier's ZERO HEIGHT MEANS UNBOUNDED convention), and a NO makes it ask
  `-lineFragmentRectForProposedRect:sweepDirection:movementDirection:remainingRect:` for each line's band and use the
  answered subrect's x and width. MEASURED, `tests/text_container_region.m`: an inset first line (x=40, width=120)
  makes the fragment start at **40**, measure **120** and break EARLIER than the plain container; a line with a hole
  comes back in **two** fragments at the **same baseline** with contiguous ranges, the right one at **x=160**; and a
  point at x=200 on that line hit-tests into the RIGHT part rather than the left one's end.
- **And the WEB that ties the text system's three objects together** (`ctest`): `NSLayoutManager` slice one has no glyphs
  and no lines — what it has is the WIRING — and wiring is exactly the thing that can be checked from BOTH SIDES of
  every pair. MEASURED: a fresh manager has no store, no containers and NOTHING stale (`NSNotFound`); a storage that is
  given a manager HANDS IT ITSELF through `-setTextStorage:` and lists it, and wiring a five-character store marks
  **(0,5)** stale; a manager owns a container (its array) and the container BORROWS it back; an edit in the store
  REACHES the manager — the delegate is told and the stale range covers what changed; two reports are **UNIONED** rather
  than replaced (2,3 then 10,5 gives **(2,13)**); taking a manager off a store clears its pointer and its list entry;
  `-replaceTextStorage:` moves a manager between stores; and `-replaceLayoutManager:` TRANSFERS the containers — the new
  manager owns them and the old one no longer does. **AND THE PROBE FOUND ONE REAL DEFECT**: a container added to a
  second manager stayed on the FIRST one's list, because a container holds ONE borrowed pointer — a manager adopting one
  now RELEASES it from the manager it was on, since a container is laid out in one place.
- **And the FRAGMENTS that web produces** (`ctest`): `NSLayoutManager` slice two LAYS THE STORE INTO THE CONTAINER'S
  LINES — the same typesetter walk the text view makes, asked by the manager — and answers where each line is. MEASURED:
  the character-to-glyph map is the IDENTITY, clamped (`numberOfGlyphs` == the character count, a range past the store
  comes back **clamped**); three newline-separated lines give **3** fragments, each the container's whole width
  (**300**) and one line high (15.73), with the range INCLUDING the newline the typesetter kept; a glyph in `two` is in
  the fragment for `two` at **y=15.73** (container coordinates); `-usedRectForTextContainer:` is the UNION — x at the
  fragment padding, **3** lines tall, as wide as the text rather than the container — and a container that is not the
  manager's has nothing used in it; the SAME paragraph is **1** fragment in 300 points and **3** in 90, so the width is
  the container's; an edit makes the layout STALE and asking for the geometry REBUILDS it one line taller, clearing the
  record; and asking twice changes nothing. **WHAT WAS OWED HERE HAS SINCE LANDED**: drawing (`text_layout_draw.m`),
  the glyph store (`text_layout_glyphs.m`), the overflow into a second container (`text_layout_overflow.m`), and the
  background and underline keys (`text_layout_attributes.m`) — each its own probe below. What remains owed is a glyph
  map that is not the one-to-one Core Text produces.
- **And the INK the layout produces** (`ctest`): `NSLayoutManager -drawGlyphsForGlyphRange:atPoint:` reads the
  fragments and sets each line at the ORIGIN the caller gave — "that container's origin in the currently focused
  view's coordinates", as Apple's comment puts it — and `-boundingRectForGlyphRange:inTextContainer:` answers the union
  of the fragments a range touches, which is what an invalidation is spelled in. MEASURED: two lines are **2** bands of
  ink; drawing one line at (0,0) begins at **(11,5)** and at (30,12) at **(41,17)** — exactly the origin's offset; the
  FIRST line's ink spans rows **5..12** and the SECOND's **19..27**, so a glyph range draws its own line and not the
  other; the whole store's bounding rect is **2** lines tall from y=0 (31.46), the first line's **1** (15.73) from y=0,
  and the second's begins at **y=15.73**; and a RED foreground attribute in the store is the colour the glyphs come
  out, while no colour attribute leaves them the control's own ink. **AND THE PROBE FOUND ONE REAL DEFECT**: the
  bounding rect included a fragment the range only TOUCHED at its boundary, so a one-line range answered two lines —
  the overlap test is now strict on both ends. **AND THE ONE-COLOUR-PER-FRAGMENT LIMITATION IS RETIRED**: the draw
  walks the store's ATTRIBUTE RUNS, so a line whose text changes colour halfway is drawn in both colours.
- **And the BACKGROUND, UNDERLINE and STRIKETHROUGH the manager now paints** (`ctest`): `NSBackgroundColorAttributeName`,
  `NSUnderlineStyleAttributeName`, `NSUnderlineColorAttributeName`, `NSStrikethroughStyleAttributeName` and
  `NSStrikethroughColorAttributeName` arrived with the doors that read them, `-drawBackgroundForGlyphRange:atPoint:`
  fills the used rect of each run with its own colour, and the rule half of `-drawGlyphsForGlyphRange:atPoint:` is one
  helper called twice — below the baseline for an underline (`-underlinePosition`), through the middle of the x-height
  for a strikethrough. MEASURED: a GREEN background attribute puts **301** green pixels behind `abcd`; a blue underline
  draws a rule the plain draw does not (**0** blue pixels with no attribute, then some with one), and a DOUBLE
  underline draws TWO rules; a strikethrough is checked as its OWN key (a door reading the underline keys would fail
  it); two foreground runs on one line come out in BOTH colours (red **20**, blue **14**); and two backgrounds on one
  line are two rectangles in two colours (green **147**, yellow **154**).
- **And the SECOND CONTAINER, which is where text goes when it does not fit** (`ctest`): a container's OWN HEIGHT is
  the overflow edge, so `one\ntwo\nthree\nfour` in a first container TWO lines tall fills **2** fragments and carries
  the other **2** to the next; `-glyphRangeForTextContainer:` answers **(0,8)** for the first and **(8,10)** for the
  second; the overflow line sits at **y=0** in the SECOND container's own coordinates; each container's used rect is
  the two lines it took; a single tall container still takes everything; and text past the LAST container is clipped at
  the last line that fit.
- **And the GLYPH STORE, which is the generated lines themselves** (`ctest`): the layout KEEPS the `CTLine` it made for
  each fragment instead of rebuilding it per draw, and the character-to-glyph map WALKS that store rather than
  declaring the identity — `-numberOfGlyphs` is the last stored glyph's end, the two conversion doors find a
  character's fragment and count the glyphs before it, and the four reverse lookups the view needs are here too.
  MEASURED: **7** glyphs for a 7-character store; a range in the second line maps to itself and one spanning the break
  keeps its length; a glyph's x is its fragment's padding plus Core Text's offset (**10** at the first glyph, **33.05**
  at the end of `one`, and back to **10** at the start of `two`); the point door is that inverse; and the ORDINAL
  fragment doors put the boundary index in the fragment that STARTS there (glyph 4 of `one\ntwo` is fragment **1**).
- **And the VIEW reading the store through the manager** (`ctest`): `NSTextView` owns the trio, `-string` is the
  STORE's string, and the `malloc`'d visual array, the typesetter walk and the per-line `CTLine` are GONE from the
  class. MEASURED: a text view owns an `NSTextStorage`, an `NSLayoutManager` and an `NSTextContainer`; a direct store
  edit is mirrored into the view's string and an edit in the view reaches the store; the view's visual line count IS
  the manager's fragment count, before and after a re-wrap; a RED run in the store is the colour the VIEW draws; and a
  character typed at the end of a red run INHERITS the run. **THE `_string` MIRROR IS WHAT LETS THE BASE CLASS KEEP
  WORKING** — `NSText`'s movement and word commands read that string directly, so the store's own
  `NSTextStorageDidProcessEditingNotification` refreshes it.
- **And the PARAGRAPH STYLE, which is a value object with two readers** (`ctest`): `NSParagraphStyle` and
  `NSMutableParagraphStyle` arrived with `NSParagraphStyleAttributeName` — the default is natural-aligned,
  word-wrapping and zero everywhere, a `-mutableCopy` takes every setter, changing it leaves the shared DEFAULT alone,
  and a `-copy` freezes the builder. THE TWO PROPERTIES THE LAYOUT READS are the ALIGNMENT (it moves a line inside the
  width the container gave it, via `CTLineGetPenOffsetForFlush`, recorded in the fragment's used rect so the caret and
  the ink follow) and the LINE-BREAK MODE (it travels into the attributed string as a `CTParagraphStyle`, so the
  typesetter obeys it). MEASURED: glyph 0's x is **10** left-aligned, larger centred and larger still right-aligned;
  the same paragraph is word-wrapped with its first line ending on a space, char-wrapped ending mid-word and holding at
  least as much, and CLIPPED at **1** fragment; the view's `-setAlignment:` writes the style into its store while
  `-alignment` reads it back; and the PARAGRAPH COMMANDS (`-alignLeft:`/`-alignRight:`/`-alignCenter:`/`-alignJustified:`,
  declared on `NSText`) are one `-setAlignment:` each, so the view moves glyphs for them too. **AND THE PROBE FOUND ONE
  REAL DEFECT**: Foundation's `-addAttributes:range:` and
  `-removeAttribute:range:` edit their runs DIRECTLY, so `-addAttribute:` never reached `-setAttributes:range:` and
  announced nothing — a style put into a store that way never reached its manager. `NSTextStorage` now overrides both
  and announces, which is the exception its own header names.
- **And the PARAGRAPH STYLE'S GEOMETRY, which is read now** (`ctest`): `-lineSpacing`, `-paragraphSpacing`,
  `-paragraphSpacingBefore`, `-firstLineHeadIndent`, `-headIndent`, `-tailIndent`, `-lineHeightMultiple`,
  `-minimumLineHeight` and `-maximumLineHeight` all move the layout. Each fragment now records its OWN baseline and its
  own flow band (any leading space plus the line), so a line's height and its place are facts the fragment carries
  rather than arithmetic a caller reconstructs. MEASURED: the DEFAULTS are unmoved (padding at x=**10**, three natural
  lines); `-lineSpacing:5` adds its gap between a wrapping paragraph's lines; `-paragraphSpacing:6` plus
  `-paragraphSpacingBefore:4` add **10** at each paragraph boundary; a first-line indent of **20** and a head indent of
  **8** put line 0 at x=**30** and line 1 at x=**18**; a tail indent of **60** wraps the same paragraph into more
  lines; and a two-times multiple, a minimum and a maximum set the band to **2*base**, **base+12** and **base-4**. THE
  HYPHENATION FACTOR IS READ NOW (`tests/text_hyphenation.m`): the layout manager reads it as a hyphenation zone
  (`lineWidth < factor * width`) and a hyphenated line ends in a **U+2010 that is drawn and is not a character of the
  text** — the resource it asks is `libagora-core/CFHyphenation.c`, and at the default 0.0 nothing is hyphenated; the
  BASE WRITING DIRECTION is read as far as NATURAL ALIGNMENT (right for a
  right-to-left paragraph), while reordering a right-to-left script's glyphs is the engine's, named at its door.
- **And the INPUT CONTEXT, where a key goes before the text view** (`ctest`): `NSTextInputContext` is the object
  `NSResponder -interpretKeyEvents:` hands each event to, and the STANDARD KEY BINDING MOVED THERE FROM THE RESPONDER — the
  responder now only finds the receiver's context. MEASURED: a text view answers an input context whose client is the
  view, while a view that is not a text input client answers NONE; driving `-handleEvent:` directly maps a LEFT ARROW to
  a movement and a printable character to an insertion (and leaves a Command-modified key to the menu bar);
  `+currentInputContext` is nil until `-activate`, the context while active, and nil after `-deactivate`; the source
  doors name the one stock keyboard; and `-discardMarkedText` ends a composition through its client. **AND THE INPUT
  METHOD IS HERE TOO** (`ctest`, `tests/text_input_method.m`): `-setInputSource:` installs an `NSTextInputSource` and
  every key is sent to it FIRST — `AGInputMethod` is a dead-key table that holds the accent as MARKED text and composes
  it with the next letter, and a key it does not own is DECLINED and reaches the standard binding.
- **And `-transpose:` AND THE FIELD-ROLE INSERTIONS** (`ctest`): the one command in the responder's named list that
  needed no model this tier was missing — a position and two characters are arithmetic over the string. MEASURED:
  transposing at index **2** of `abcd` gives `acbd` with the caret at **3**; a selection of two swaps exactly those
  two; at either END the last two are the pair; one character is left alone; `-insertParagraphSeparator:` is a break a
  text view holds and a one-line field refuses at its insert door; and the `IgnoringFieldEditor` pair inserts a newline
  and a tab in the view. `-insertLineBreak:` (U+2028), `-insertContainerBreak:` and the substitution insertions stay
  named with the models they need.
- **And the TABLE BLOCK, the box a paragraph is set in** (`ctest`): `NSTextBlock` measures three LAYERS (padding,
  border, margin) on four EDGES and holds a ground and four border colours; `NSTextTableBlock` is a block that knows
  its cell of a grid and `NSTextTable` the grid's column count and algorithm; and `NSParagraphStyle` carries them in
  `-textBlocks`, which is where Apple puts a table cell. THE MANAGER DRAWS THEM: it groups consecutive lines by the
  block they carry, grows their union by the block's own layers, and calls `-drawBackgroundWithFrame:...`. MEASURED: a
  fresh block has no ground and no widths; a per-layer width sets all four edges and a per-edge colour is answered for
  that edge alone; a content rect of (10,10 30x10) with **5** on every side grows to (5,5 40x20); a fresh table is one
  automatic column and a cell answers its row/span/column; a style's `-textBlocks` survives `-copy`; and the manager
  puts the ground and the border around `ab` — read as green and red pixels. **AND THE GRID IS NO LONGER OWED, WHICH
  CORRECTS WHAT THIS NOTE SAID**: the three things it named are each implemented and each has a probe — shared column
  widths and rows as tall as their tallest cell (`tests/text_table_grid.m`: two cells in a row share a y, two in a column
  share an x, a row of long cells is measured and wrapped), columns re-measured across a container break so a cell keeps
  its x (`text_table_flow.m`), and `-collapsesBorders` (`text_table_collapse.m`: the shared edge drawn ONCE, owned by the
  HEAVIER cell rather than by the left one, with the table's own border joining the collapse on its outer edges).
  **AND THE DRAWING DOOR OF THAT FAMILY IS IMPLEMENTED AND MEASURED NOW**: `-drawBackgroundForBlock:withFrame:inView:
  characterRange:layoutManager:` is 10.6's hook, `NSTextTableBlock` forwards both of its drawing doors to its table, and
  the mask that Apple's signature has no room for travels THROUGH the hook in a private ivar so a subclass overrides ONE
  door and still sees what the manager handed down. MEASURED, `tests/text_table_delegation.m`, and the probe reads pixels
  rather than existence: the cell's own ground is GREEN, a table subclass paints BLUE over the frame it is handed, and the
  result is **300 blue pixels and 0 green** — the block never drew.
- **AND THE BOUNDS DOOR IS IMPLEMENTED AND MEASURED TOO**, by the same arrangement: `-boundsRectForBlock:contentRect:
  inRect:textContainer:characterRange:` defaults to the BLOCK's own growth (reached through an internal door, so a block
  that forwards here does not recurse), and `NSTextTableBlock` forwards its `-boundsRectForContentRect:...` to its table.
  MEASURED in the same probe: the identical cell is drawn through a plain table and through a subclass that grows the box
  eight points on each side, and the ground goes from **300 green pixels to 868** — the table's growth is honoured.
- **AND THE THIRD DELEGATION DOOR IS DONE, WHICH TOOK A SECOND ATTEMPT AND TWO FINDINGS.**
  `-rectForBlock:layoutAtPoint:inRect:textContainer:characterRange:` is wired: the table is PUBLISHED the column widths the
  manager measured (`-_setColumnWidths:count:padding:`) and answers a cell's content rect from them, `NSTextTableBlock`
  forwards to its table, and the manager asks the door instead of computing the arithmetic inline. MEASURED: the same cell
  is laid out at **x=10.00** through a plain table and **x=22.00** through a subclass that adds twelve — so an override
  moves its cells and the manager follows.
- **AND THE FIRST ATTEMPT WAS REVERTED BECAUSE IT WAS HALF-EFFECTIVE, WHICH IS WHERE THE TWO FINDINGS CAME FROM.** The
  four existing table probes passed with it in — the default reproduced the old geometry — but a subclass's override
  changed NOTHING observable: the layout, the drawn ground and the drawn ink all measured identically. **THE MANAGER HAS
  TWO PASSES AND ONLY ONE WAS ASKING THE DOOR**: a row's HEIGHT is measured in the first and the cell's text is PLACED in
  the second, so an override changed how much room a cell reserved and not where it was drawn. And the second finding is
  arithmetic: `-rectForBlock:layoutAtPoint:...` adds the table's own PADDING, so the manager must pass the table's ORIGIN
  — passing the padding counted it twice and put every cell ten points right, which the grid and collapse probes caught
  immediately.
- **AND THE FIRST ATTEMPT AT THIS WAS REVERTED BEFORE IT WAS RETRIED, WHICH IS WHY IT IS TWO SLICES.** The internal
  painter, the block's forwarding and a probe were written once and the probe failed: its table subclass never saw the
  override. The cause turned out to be two things — **`-copy` on `NSTextTable` and on `NSTextTableBlock` HARD-CODED ITS
  CLASS**, so a subclassed table became a plain one the moment a paragraph style copied its `-textBlocks`, which is every
  cell's path; and the mask needed to travel through the hook rather than around it. A half-wired extension point is worse
  than a named absence, so the first attempt was reverted rather than shipped, and the second one is measured.
- **And the RTF READER, which is the half Foundation does not have** (`ctest`): `libagora-base` already WRITES RTF (`-RTFFromRange:documentAttributes:`), but a reader has to turn control words into the APPKIT's attribute keys —
  `NSFontAttributeName`, `NSForegroundColorAttributeName`, … — which Foundation has no vocabulary for. MEASURED: a
  literal RTF document with a font table, a colour table, a centred underlined red paragraph and a plain one parses to
  the text (the `\par` break and the `\'hh`/`\uN?` escapes included), the size by `\fs`, the ink by `\cf`, the rule by
  `\ul`, the alignment by `\qc`, and a second paragraph that says `\ulnone`/`\cf0` is neither underlined nor coloured;
  a document with no RTF header answers **nil** rather than an empty string, and the document attributes report type
  **`NSRTF`** with encoding **4** (`NSUTF8StringEncoding`, an `NSNumber` — see the document-attributes note below). **A FACE THIS TIER CANNOT RESOLVE IS
  SUBSTITUTED** (the size is kept, which is what the layout measures with) — which is what an RTF reader is supposed
  to do. **AND THE APPKIT-AWARE WRITER IS HERE BESIDE IT** (`ctest`): Foundation's writer is keyed on its own
  presentation-intent bits and does not encode NSFont/NSColor/the two rules or the paragraph style, so
  `-RTFRepresentation` writes the vocabulary the reader understands — a font table and a colour table built in a first
  pass, then the runs, emitting a control word only where the state changes, escaping the three literals and writing
  anything non-ASCII as `\uN?`. MEASURED: an attributed string with a font, a red ink, a green ground, an underline, a
  strikethrough, a centred paragraph, a tab and a non-ASCII character writes and reads back to itself — **226** bytes
  carrying `\fonttbl`, `\colortbl`, `\ul`, `\qc` and `\tab`.
- **And the TABLE GRID, which is where cells stop being a stack and become a grid** (`ctest`): the layout manager reads
  the `NSTextTableBlock` each cell-paragraph's style carries, MEASURES the columns (automatic: the widest cell in each
  column, its span divided out, scaled to fit the container; fixed: equal shares), lays each cell's text out inside its
  own columns' width, and PLACES it at its column's x. Rows are as tall as their tallest cell, and the table's own box
  (with each cell's) is drawn behind the cells. MEASURED: two cells in one row share a y and differ in x; two cells in
  one column share an x and differ in y; a row of two long cells whose natural widths together exceed the container is
  SCALED and each cell wraps (more than the two one-line fragments); and a FIXED table's first column starts at the
  padding (**10**) with the second at padding plus half the table's width. **AND THE BORDERS COLLAPSE** (`ctest`): with
  `-collapsesBorders` YES, an edge two cells SHARE is drawn once — the min-side cell (left or top) keeps its MaxX/MaxY
  and the neighbour's MinX/MinY is suppressed — and a cell's box is its CELL rather than its text, so a short cell's
  edge still reaches its column; the vertical layers are reserved in the row's height so stacked cells' boxes meet. A
  lone cell is unchanged. **AND A SHARED EDGE FOLLOWS THE HEAVIER BORDER** (`ctest`): the two blocks' border weights on
  a shared edge are compared and the WIDER one draws it — in its own colour — with a tie going to the min-side one, so
  a 2-point edge beside a 6-point one collapses to the 6-point one and the light edge is the one suppressed. THE
  TABLE'S OWN BORDER JOINS IN on its four outer edges, and its box is the box around the cells, so a collapsed table
  ends with one outer border rather than the table's and the cells' drawn over each other. **AND A TABLE FLOWS ACROSS
  CONTAINERS** (`ctest`): a row that does not fit the container it is being laid into begins the NEXT one, with the
  columns measured from EVERY cell so they do not move across the break — MEASURED, three rows over a short container
  and a tall one give **2 + 1** fragments, the third row at the new container's top (y=0), and column two at x=**73.832**
  either side of the break; a table taller than every container is clipped at the last, like text past it.
- **And the ATTACHMENT, which is a character that stands for a picture** (`ctest`): `NSTextAttachment.h` declares
  `NSAttachmentCharacter` (U+FFFC), the `NSTextAttachmentCell` protocol and class, and the attachment itself, with
  `NSAttachmentAttributeName` carrying it; the layout manager's run walk asks the cell for its size and calls
  `-drawWithFrame:inView:` at the character's own x instead of setting that run's glyphs. MEASURED: a 12x12 picture
  gives `+textAttachmentWithImage:` an attachment whose cell is **12x12**; the cell draws the picture into the frame it
  is given; and a store carrying one attachment character draws the picture — read as the picture's colour in a pixel.
  **AND THE INLINE FLOW IS HERE NOW**: the manager records the difference between the box's width and the placeholder
  glyph's advance, and hit-tests a point inside the box to the attachment's own character — MEASURED in
  `tests/text_attachment_flow.m` (the character after an attachment is one box width past it, and the picture is drawn
  where the box is). **AND THE BOX IS THE ENGINE'S NOW**: the manager sets CORE TEXT'S `CTRunDelegate`
  (`kCTRunDelegateAttributeName`) over the attachment character, so `CTLine` and `CTTypesetter` reserve the width
  themselves — the manager's own `FNBox` arithmetic sees an advance that already IS the width and adds nothing. See
  `libagora-text`'s `CTRunDelegate.h`. **AND THE FILE-WRAPPER PAIR'S ROW IS NO LONGER OPEN**: `-fileWrapper`,
  `-initWithFileWrapper:` and `-setFileWrapper:` are here, because the encoder ground that used to hold them expired
  with the PNG writer — the picture and the file are two separate facts on one attachment, and the RTFD package is
  what that pair was for.
- **And the attachment's TRACKING FAMILY, WHICH IS DRIVEN BY THE VIEW RATHER THAN BY THE REFUSED MODAL LOOP** (`ctest`):
  `-wantsToTrackMouse`, `-highlight:withFrame:inView:` and `-trackMouse:inRect:ofView:untilMouseUp:` — plus the
  `characterIndex:` variants — are here. `NSTextView -mouseDown:` hit-tests the box, asks the cell whether it wants the
  mouse, selects the attachment character and sends the DOWN through the cell's tracking door; `-mouseDragged:` and
  `-mouseUp:` send every remaining event through the same door. THE CELL'S DOOR IS ASKED ONCE PER EVENT rather than
  owning a loop, which is the whole reason this family could land while `NSCell`'s own `-trackMouse:…` stays refused:
  the coordination is the view's, and a guest cannot hang in a loop that does not exist. MEASURED,
  `tests/text_attachment_tracking.m`: the cell answers both `-wantsToTrackMouse` doors; `-highlight:YES` puts **360**
  accent pixels on a red 30x12 picture and `-highlight:NO` takes them away; a press on the rendered view selects the
  attachment character and leaves **308** accent pixels; a drag OUT of the cell's frame clears the highlight and a drag
  back IN restores it; a recording cell sees exactly **1** down, **2** drags and **1** up, each carrying the
  attachment's character index, and the up answers **YES** inside the frame and **NO** outside; a cell that does not
  want the mouse (or that declines the press itself) leaves an ordinary caret rather than a swallowed click. **AND
  WHAT THIS DOES NOT DO IS STATED**: the delegate messages the 10.6 header promises a default attachment cell
  (`-textView:clickedOnCell:inRect:atIndex:` and the dragging/pasteboard family) are a separate door and stay owed.
- **And the TAB STOPS, which are a PLACE rather than a width** (`ctest`): `NSTextTab` names a location and a kind (left,
  right, centre, decimal), `NSParagraphStyle` carries them in `-tabStops` with `-defaultTabInterval` after the last, and
  the layout manager copies them into the `CTParagraphStyle` it builds — so `CTLine` advances a `\t` to the next stop.
  MEASURED: stops at **50** and **100** over `a\tb\tc` put the characters after the tabs exactly at **50** and **100**;
  an empty list with a **40**-point interval puts them at **40** and **80** (the manager sets an EMPTY TabStops so
  Core Text's own 28-point default does not win); and the view's `-insertTab:` puts the character in the store. **AND
  THE COLUMN'S TERMINATORS ARE A LOCALE'S** (`ctest`): `+[NSTextTab columnTerminatorsForLocale:]` answers the locale's
  decimal separator, read from ICU through `NSLocale -decimalSeparator` — `.` for en_US and `,` for de_DE — and
  `NSTabColumnTerminatorsAttributeName` names them in a stop's `-options`, which `-initWithType:location:options:` is
  the door that sets on a DECIMAL stop (the alignment door cannot name a decimal) — MEASURED, a stop at 100 whose
  terminator is the COMMA lands the comma of `12,5` at **100**, while the same stop with a PERIOD terminator finds no
  point and carries the number whole. **AND A DECIMAL TAB IS ALIGNED ON ITS POINT**
  (`ctest`): Core Text has no decimal edge, so the manager lays the line out with the stop as a LEFT one and REBUILDS
  it with the stop moved left by the integer part's width — MEASURED, a decimal stop at **100** puts the point of both
  `12.5` and `123.5` at **100**, so the integer part grows and the point does not move, which a left stop cannot do.
- **And the MARKED TEXT, which is what an input method composes through** (`ctest`): `NSTextInput.h` declares the eleven
  doors an input system drives a text view through, `NSTextView` adopts the protocol, and the composition is an ordinary
  edit with a remembered range — the marked characters really go into the store, so the caret and the layout work as
  usual, and the view draws the composition rule because a character range cannot carry the fact that it is marked.
  MEASURED: a fresh view has no marked text; the first keystroke of a composition marks one character in the store and
  the next REPLACES it rather than appending; `-insertText:` confirms over the MARKED range (not the selection, which
  sits inside the composition); `-unmarkText` takes a composition back; the candidate window's four questions answer
  (the valid attributes, the substring, a caret rectangle that MOVES with the caret, and the point door landing near
  it); and a composition draws measurably more ink than the same text unmarked. **AND THE PROBE FOUND ONE REAL
  DEFECT**: a store's `-attributesAtIndex:` hands back the RUN'S OWN dictionary, so the inherited run held across the
  edit that frees it was read after it was freed — MEASURED, a segfault on the second keystroke of a composition. The
  inheritance retains it now.
- **And the field, which is a cell under a view** (`ctest`, offscreen): `NSTextFieldCell` owns the string, the face
  and the three doors of an edit; `NSTextField` is the control above it, and it contributes the two things a cell
  cannot — a PRESS that opens a session with the WINDOW's field editor, and `-selectText:` for the same session with
  no pointer. The editor is put in the FIELD at the field's own text rect and made the window's FIRST RESPONDER, so
  the keyboard goes to the editor rather than to the field, and a committed session reaches a caller's action through
  `NSTextField -textDidEndEditing:`. MEASURED: Return COMMITS the typed value into the field and sends the action ONCE;
  Escape DISCARDS it and sends nothing; `-abortEditing` is that same discard through a door (and answers NO when no
  session is running); a press on a field that is not editable opens NOTHING; and focusing the field (`-makeFirstResponder:`)
  opens its session, leaving the EDITOR as the responder. `NSComboBox` now derives from `NSTextField` — Apple's own
  hierarchy, which its header had named as the row this control would close — so its press is the base's press and the
  chip is the only thing it adds.
- **And the field's delegate family** (`ctest`, offscreen): a control that edits text owes the THREE things Apple
  declares in `NSControl.h` — the `NSControlTextEditingDelegate` protocol (seven optional methods), the
  `NSControlSubclassNotifications` category that an object preferring to LISTEN is declared on, and three published
  notification names. The field's delegate is told with the `control…` spellings and can REFUSE two of them: NO to
  `-control:textShouldBeginEditing:` opens NO session (and the half-built one is torn down rather than left showing a
  caret), and NO to `-control:textShouldEndEditing:` keeps the caret exactly where it is. MEASURED: one session tells
  the delegate BEGIN once, CHANGE on an edit, and END once carrying the key's reason; every notification's object is
  the CONTROL, never the editor, and its `userInfo` names the editor under `NSFieldEditorUserInfoKey`; and a listener
  that conforms to NOTHING is told the same three by registering. The formatter trio and the two `NSTextView` methods
  are DECLARED AND NEVER ASKED, each named for what it needs (formatter-driven validation, and command interception).
- **And the field's border has two shapes** (`ctest`, offscreen): `NSTextFieldBezelStyle`'s square and rounded pair is
  the same face with its corners cut or not, and the claim is read where the INK falls — the four corner pixels carry
  the border for a square field and NONE for a rounded one, while the middle of an edge carries it at both settings,
  and the text rect and the cell's own measurement agree. A fresh field is ROUNDED, which is the default that matters
  because zero is SQUARE here: the opposite of the button family, where zero is not a bezel style at all. The whole
  thing is one path constructor with a radius that is `NS_CELL_BEZEL_RADIUS` or zero, so a square field is not a
  second drawing path — just this one with its corners not cut.
- **And what an empty field says it is for** (`ctest`, offscreen + one real session): a placeholder is drawn when the
  field has no text, and the claims are read out of the ink — an empty field with NO placeholder writes NOTHING, one
  WITH a placeholder writes a hint whose floor is **0.50** grey where the same words as a VALUE floor at **0.00**, and
  both begin in the same column (x=4), so a hint and a value are not two layouts. An ATTRIBUTED placeholder is drawn
  with its own attributes (a red one is measurably red, which the darkness threshold cannot even see). And the hint is
  a claim about the LIVE text, not the cell's value: it survives a click into an empty field, vanishes the moment the
  editor has a character, and comes back when the editor is emptied. **THE PROBE ALSO FOUND A MEASUREMENT GAP**: an
  empty field measured only its two padding bands — **6.00** points against **21.73** for the same field holding a
  value — so `-sizeToFit` on the empty field a placeholder implies handed back something with no room in it. A field's
  height is its font's line whatever it holds, and `NSTextFieldCell -cellSizeForBounds:` now measures the line when the
  text is empty (the width is left as the base computed it).
- **And what a field may hold** (`ctest`, offscreen + real sessions): the attributed-editing flags
  (`-allowsEditingTextAttributes`, `-importsGraphics`) were carried by the CELL since the cell family's first slice and
  by the field EDITOR since the text view's, and NOTHING CONNECTED THEM — a caller could set a field rich and get a
  plain editor. `-setUpFieldEditorAttributes:` is now the door that carries them, factored out of the session so a
  subclass with an editor of its own overrides one method. The probe checks the chain at all three objects: a flag set
  on the CONTROL reaches the CELL, and the NEXT session's EDITOR is configured from it — while a field with the flags
  OFF gets a plain editor, so the check cannot pass against an editor that is always rich. What still does not happen
  is named rather than implied: no paragraph model in the cell — so the flags travel and nothing obeys them yet.
- **The chrome** (`ctest`, offscreen): the title bar's symbols are SHAPES in pixels — ink on both diagonals of
  the X, a thick stroke across the minus, and a pill rounded at both caps — the title is centred and bold, and
  each symbol appears only for the style-mask bit that asks for it.
- **The menu subsystem** (`ctest`): a target's `-validateMenuItem:` decides enablement and MAY CHANGE the item
  while it answers, an item that is ON draws a checkmark, and a disabled title is drawn dimmed.
- **Activation** (`ctest`, against Agora's own server): the menu bar window is shown while the compositor says
  this client has the keyboard, hidden when it does not, and shown again — a window ordered out is not
  destroyed.
- **The window chrome, when a theme provides it** (`ctest`): an XFWM theme's `.xpm` files become the four
  buttons AND the title bar they sit on — corners at each end, title pieces tiled between — at the theme's own
  size, with each state (`active`/`inactive`/`prelight`/`pressed`) selected by the window's key state and the
  pointer, and a button's transparent pixel at its TOP. It runs against `tests/fixtures/chrome`, Agora's own MIT
  fixture.
- **What a chrome button DOES** (`ctest`): a pointer pressed and released through the seam's own door, and the
  question asked of the WINDOW rather than of the pixels — the plus zooms and a second click restores, a release
  that slid off the button performs nothing while one that slid back does, the minus miniaturizes, the pill
  changes nothing, and the X asks a delegate's `-windowShouldClose:` and honours a refusal.
- **What a DRAG costs** (`ctest`, a real run loop): a control's tracking is a MODAL LOOP, so everything the run loop
  does once per pass has to be done there by hand — and it did one full draw and one commit PER MOTION. Forty
  motions committed FORTY-THREE frames before, and ONE after: the values are all still applied and the action
  still speaks for each one, only the drawing waits for a frame. MEASURED on the live session at 82 motions a
  second: the client's CPU for the drag fell from 1.24 s (82 % of a core) to 0.73 s (48 %), and the value the drag
  ENDED at moved from 69.5 — seventeen points short of where the pointer stopped, because a client that cannot
  keep up loses motions — to 87.0, which is exactly where it was let go.
- **What a drag on a window's EDGE costs, and where it lands** (`ctest`, a real run loop): a press on one of the
  frame's four bands resizes the window and leaves the edge OPPOSITE it exactly where it was — the assertion a
  plausible implementation gets wrong, because a size and an origin are two numbers and the hand is holding one of
  them. A corner takes both axes; the middle of the bar still MOVES the window rather than resizing it; a window
  whose style mask does not allow resizing does not move; the delegate is asked through `-windowWillResize:toSize:`
  and its answer is the size USED, so a refusal is a delegate returning the size it already has; and the minimum
  size is honoured with the untouched edge still a constant while the clamp bites. MEASURED on the live session: a
  60-point drag on the right edge took the content from 420 to 480 and moved the left edge by zero.
  **AND A RESIZE OWES A REPAINT WHERE A MOVE DOES NOT** — a move changes no surface, while a resize remakes the
  backing store, so a window not marked stale has no buffer at its new size. MEASURED before that was fixed: a
  window dragged by its edge DISAPPEARED for the whole drag — a mid-drag capture had the wallpaper where it had
  been — and came back on the release, because the release was what marked it. The test now holds both halves of
  that asymmetry: a resize marks the window stale and a move leaves it alone.
  **AND THE OUTGOING BUFFER OUTLIVES THE ATTACH THAT REPLACES IT.** A surface's current buffer is the last one
  ATTACHED — a `wl_buffer`'s release means the compositor has finished drawing with it, NOT that the surface has
  stopped showing it — so a resize that freed the buffer it was replacing left the surface with none, and a surface
  with no buffer is not composited and not even hit-tested. MEASURED, with a capture at every step of a drag: 21 of
  25 captures had no window in them at all; after the seam keeps the outgoing buffer until the new one is attached,
  0 of 25. `tests/window.c` holds the half a headless test can: a deferred resize must finish, so a frame is asked
  for at the new size and the stride it arrives with is the size that was given.
- **The inside of a scroll view** (`ctest`, offscreen): `NSClipView`'s arithmetic in exact points — a short
  document is CENTRED rather than pinned (a 40-wide document in a 100-wide clip sits at -30), a long one stops at
  the far edge (300-100 by 200-100) and never shows blank space, `-documentVisibleRect` answers in the DOCUMENT's
  coordinates, a scroll tells its enclosing view where it landed, and a drag past an edge steps 16 points. **AND THE
  PART THAT WAS NOT THERE:** the two change handlers were written and NOTHING WAS REGISTERED for the document's own
  frame and bounds notifications, so a document that SHRANK did not pull the visible area back with it — the header
  promised it and the class did not do it. `-setDocumentView:` now observes the document (and stops observing the one
  it replaces), and `tests/clip_view.m` drives that through `-setFrame:` rather than by calling the handler.
- **And the bar that goes with it** (`ctest`, offscreen): `NSScroller` is two INVERSE arithmetics — the value pair
  (`-floatValue` in [0, 1] and `-knobProportion`) into a knob, and a point back into a PART — plus the drag between
  them. MEASURED: a 15-point regular metric (11 small and mini), a 15x100 frame with a half-track knob splits into a
  slot at y=15..85 and a 35-point knob at the top; a press on the knob remembers the grab 7.5 points into it, so a
  10-point drag moves the value by 10/35 of the travel rather than to the pointer; both ends clamp; a one-percent
  proportion still draws a knob as long as the control is THICK, because a knob too small to grab is not a knob; and
  `-NSScrollerArrowsNone` is a GEOMETRY change (the line parts vanish and the slot becomes the whole frame) and not
  an ink one. **AND A CLICK STEPS ONCE, WHILE A HELD PAGE KEEPS STEPPING:** the control's tracking loop speaks on the
  press AND on the release (right for a slider's absolute value, wrong for a step), so the part is REPORTED once — the
  release is a no-op — and a held PAGE or LINE repeats, which the loop polls on its own 1/60 s deadline
  (`-cg_trackingShouldRepeat`) and the CELL times, so the numbers (a delay before the first repeat, an interval after)
  never become the loop's. **AND THE ARROW IS RASTERIZED A POINT AT A TIME, NOT FILLED AS A PATH.** A seven-point
  triangle filled anti-aliased is a grey smudge, and the two did not even match: MEASURED on the live window, the top
  arrow came out five points wide at its base and the bottom three, because a fractional vertex lands on the pixel grid
  differently depending on which way the point faces. Whole-point rows make them CRISP and each other's mirror —
  MEASURED, 25 points each and no half-covered point between the grey and the ground.
- **And the frame that joins them** (`ctest`, offscreen): `NSScrollView` tiles its content view and its two bars —
  a 200x200 frame with both scrollers gives the content `(0,15)` 185x185, the vertical bar the right column and the
  horizontal one the bottom row — and the two class conversions are EXACT INVERSES of each other and of `-tile`. The
  loop runs both ways: `-reflectScrolledClipView:` sets the knob's SIZE from the visible fraction (185/400) and its
  PLACE from how far the clip view has scrolled, and a scroller's ACTION moves the clip view — a knob to its value's
  place, a page by the visible extent less a line, a line by `-lineScroll`. And `NSView -enclosingScrollView` is a
  walk now rather than a `nil` with a reason. **AND THE ONE THING A SCROLL ACTUALLY MOVES IS NOW DRAWN.** A scroll is
  a non-zero `bounds` origin, and the drawing layer did not render one — `fn_draw_view` refused it by name and
  `-displayRect:`, the path a window draws through, ignored it — so the arithmetic was exact and the picture never
  moved. The BOUNDS ORIGIN IS MODELLED IN ALL THREE PLACES it is read now (`fn_to_super`/`fn_from_super`, so a click
  on scrolled content lands where it is; `-displayRect:`; and `fn_draw_view:`, which translates instead of refusing),
  and the child clip is the child's FRAME region rather than its bounds rect — which was the same value only while the
  origin was zero. MEASURED: a mark at a document's own y 100..120 draws at 110 with the clip view at the top and at
  10 after a scroll of 100, in one run, through `-displayRect:`.
- **`ctest`: 62 of 62 passed** (the keyboard and the seam, the AppKit and its input path, the controls and their
  metrics, the field control and its cell and its bezel and its placeholder and what it may hold, the text path and its
  word granularity and the multi-line view and its wrapping and its scrolling and its READING OF THE STORE, the STORE
  the rich-text slice is built on and the REGION it is laid out in and the WEB that ties the three together and the
  FRAGMENTS it produces and the GLYPH STORE it keeps and the INK it draws and the BACKGROUND, UNDERLINE and
  STRIKETHROUGH it paints and the SECOND CONTAINER it overflows into and the PARAGRAPH STYLE it aligns and breaks by
  and the TABLE GRID whose shared borders collapse and whose rows flow into the next container and the INPUT METHOD
  whose dead key composes with the next keystroke and the CANDIDATE LIST a variants method shows under the caret and the
  BASE DIRECTION that decides what natural alignment means,
  what a drag costs, the resize by edge, the tracking engine, the clip view and the scroller and the scroll view and the
  drawn offset, the chrome and what its buttons do, the chrome theme, the menus and activation).
- **And the desktop's own text is SUB-PIXEL ANTIALIASED**, which is the AppKit's half of a renderer change in
  CoreGraphics: a window's surface is OPAQUE (`kCGImageAlphaNoneSkipFirst`), and the destination's opacity is
  exactly what decides whether a glyph is rasterised in colour. MEASURED on the live session: the window title's
  twenty-six ink pixels all carry a per-channel split and the checkbox's label carries it in 586 of 613.
- **AND THE FRAME IS HANDED OVER OPAQUE, WHICH IS A FACT ITS OWN FORMAT CANNOT CARRY.** The surface is the `X`
  spelling because that is what makes the text smoothed, and an `X` format has NO alpha channel: the fourth byte
  of every pixel is never written, so the compositor's own buffer arrives with every one of them ZERO. Read as
  ARGB the window is therefore FULLY TRANSPARENT — MEASURED, which is how this was found — and two accidents are
  what keep it on the glass: the seam's buffers are `XRGB8888`, so Agora's server never consults that byte and ORs
  in `0xFF000000` when it copies (`window-server/src/output.c`), and a stock compositor treats the format the same
  way. TWO ACCIDENTS HOLDING ONE PROMISE IS NOT A PROMISE, so `-cg_drawFrame` sets the byte where the pixels are
  handed over — the same pass over the same bytes, one word at a time where it used to be a `memcpy`, with the top
  byte DECIDED rather than copied. What that promise is NOT is a screenshot: the compositor masks exactly the byte
  a capture could read, so no pixel test in this tree can hold it, and the copy is the one place it is said.

### What a Wayland client does not get, and where each is recorded

These are properties of the protocol rather than gaps, and each is written at the door that carries it:

- **A STOCK Wayland client does not place its own window.** Under `xdg-shell` the compositor places it, and
  `-setFrameOrigin:` moves only the Cocoa frame. **Agora's own server is the exception, and it is the one that
  matters here**: `agora-shell`'s `set_frame` is the Mac's model — the application states a frame and the server
  honours it, position included — which is what makes the chrome DRAGGABLE (see the chrome section). The
  distinction is a property of the COMPOSITOR and not of `NSWindow`.
- **There is no unmap, no iconify and no stacking.** `-orderOut:`, `-miniaturize:`, `-orderBack:` and
  `-orderFrontRegardless` change *this object's* state and not the screen's.
- **There is no Expose.** The client owns the pixels; a repaint is asked for by the frame callback, which is
  why `-display` and the seam's frame handler both end in the same draw.
- **The screen is an output.** `NSScreen` asks the seam, which learns the size from `wl_output`; with no
  output described yet the frame is a zero rect rather than an invented size.

### Two things the import got wrong, found by testing the input path

- **The responder chain between views was never wired.** `NSApplication.h` names it — `NSView` → its superview
  → … → the window → the application — and nothing set it, so every event method `NSResponder` implements
  (each one a FORWARD to `-nextResponder`) stopped at the first view that did not override. `NSWindow.m`
  carried a workaround linking the first responder straight to the content view, which made a click arrive but
  SKIPPED every ancestor on the way. `-nextResponder` is computed from the hierarchy now and the workaround is
  gone.
- **`-sendEvent:` never hit-tested.** Every mouse event went to the first responder, so a click on a control
  inside a subview reached it only if the subview happened to be the first responder — a control you could see
  and not press. Mouse events now go to the deepest view containing the point (`NSView`'s own `-hitTest:`), and
  `-flagsChanged:` is reachable at all because the seam reports whether a key is a modifier (`xkbcommon`
  keysyms) rather than folding every key into a keystroke.

Both fixes were falsified before they were kept: removing the chain fails the bubbling check, and removing the
hit test fails the "click lands on the subview" check — which the first version of the test did NOT catch,
because it had made the clicked subview the first responder.

### And three things the controls, the text and the menus found

- **The first responder was assigned, never asked.** `-setContentView:` wrote `_firstResponder` straight and
  `-makeFirstResponder:` never called `-acceptsFirstResponder`, `-resignFirstResponder` or
  `-becomeFirstResponder`. The visible consequence was a text view with NO CARET: an editor opens its session in
  `-becomeFirstResponder`, and nothing in the tier ever called it.
- **A shown window was not visible.** `-orderOut:` sent a hide and the seam's show door never sent the opposite,
  so a window hidden once could never be shown again — the server's own log read
  `surface: mapped=1 visible=0 level=0 buffer=1` while the client drew into it. And the frame callback was
  treated as an instruction rather than an invitation, so every window redrew on every callback and the desktop
  ran at **517 composites a second**; a window with nothing new now declines, and `-updateWindows` is what acts
  on "stale" outside a session.
- **An NSTrackingArea's SCOPE is what a background window needed.** Before the option word, the window decided
  the crossing for the deepest view of whatever window the pointer was over, so a control in a window that was
  not key prelighted anyway. The area's own `Active…` bits are the fix, and the test pins both answers.
- **`CGContextDrawImage` wrote the destination in one byte order and nothing else did.** Its hand sampler wrote
  blue to `d[0]` whatever the surface was — right for a WINDOW's surface (`PremultipliedFirst |
  ByteOrder32Little`, memory B,G,R,A) and wrong for a bitmap rep's (`PremultipliedLast | ByteOrder32Big`, memory
  R,G,B,A) — so an image drawn into a rep came out with red and blue swapped while the same image on a window was
  right. It is fixed in `libagora-drawing`, by asking the surface which order it uses; the chrome's own test found
  it, because a themed button is the first saturated COLOUR anything here has drawn into a rep.

### The window chrome's buttons, and where they can come from

The chrome is the CLIENT's — the window server draws no title bar — and with no theme resolved it is the marks
`NSWindow` draws: an X, a minus, a plus and a toolbar pill. **A theme can replace them.** Point
`AGORA_CHROME_THEME` at an XFWM theme (the directory of `.xpm` files, or a theme root with an `xfwm4/` inside
it), or drop one at `~/.local/share/agora/chrome/xfwm4`. The buttons are then `close`, `hide`, `maximize` and
`menu` — the pill is what a toolbar toggle has no XFWM file for, and `menu` is the nearest thing the theme
offers — in the four states XFWM ships, `active`, `inactive`, `prelight` and `pressed`. They are drawn at their
OWN size: the strip grows to the theme's height and a 24x26 button IS 24x26 pixels. That is what "1:1" means,
and it is why `+contentRectForFrameRect:styleMask:` is a function of the theme rather than of a constant.

**AND THE BAR THE BUTTONS SIT ON IS THE THEME'S TOO.** XFWM composes a title bar from a corner at each end
(`top-left` / `top-right`) and a strip of `title-1`…`title-5` pieces tiled between them, and those files are the
ground the buttons were drawn against — so they are read as well, and a theme's buttons no longer sit on this
tier's flat grey. A theme missing any of them keeps the frame colour for that part, and a process with no theme at
all keeps the marks `NSWindow` draws.

**`tests/run-controls.sh` IS HOW TO LOOK AT A THEME WHILE CHANGING IT.** It opens the controls demonstration in a
nested Agora compositor — an ordinary X window that grabs nothing, unlike a nested `gnome-shell` — with the tree's
own `themes/` as the demonstration's default, and prints which theme resolved and its strip height.

**AND THE CHROME IS THE WINDOW'S HANDLE.** A press on the title bar that misses a button starts a MOVE: the window
follows the pointer and the grabbed point stays under it. `-locationInWindow` is relative to a window that MOVES
with the drag, so the pointer's place in the world is the frame's origin PLUS that point, and putting the grab back
under it is that sum minus the grab — one subtraction, with no accumulated delta to drift. `-isMovable` decides
whether it happens; a borderless window has no chrome and so no handle.

**AND ONE DARK GREY POINT DIVIDES THE CHROME FROM THE CONTENT.** A title bar and a content view are two surfaces,
and with nothing between them the boundary is wherever the reader guesses it is — so one 0.45-grey row runs the
full width across the top of the CONTENT (the chrome's bottom edge as a person reads the window), drawn last so a
theme's buttons cannot paint over it. It is GRAY rather than black on the ground `+controlDarkShadowColor` stands
on: a black line reads as something drawn ON the window, where a dark grey reads as the shadow of the surface
above it. A borderless window has no chrome and gets no line.

**A THEME IS NOT PART OF THIS LIBRARY AND MUST NOT BE.** It is somebody else's work under somebody else's
licence — the one this was built against is GPL — and reading it from disk is not linking it, so Agora's MIT is
untouched and the theme's provenance travels with the theme. No theme is committed and none is installed;
`/themes/` and `/resources/` are ignored, and a theme keeps its own licence file beside its `.xpm` files.
`tests/fixtures/chrome` is the one theme in the tree and it is Agora's OWN MIT fixture — sixteen hand-written
XPMs — so `tests/chrome_theme.m` never depends on a licence a checkout does not carry. The reader is `AGXPM.c`
(this tree decodes PNG and JPEG only; XPM is text, not a codec) and the loader is `AGChromeTheme`.

**WHAT A BUTTON DOES IS WIRED, AND EACH ONE GOES THROUGH THE DOOR ITS MENU ITEM SENDS.** The X performs
`-performClose:`, so a delegate's `-windowShouldClose:` is asked and can refuse it; the minus performs
`-performMiniaturize:` and the plus `-performZoom:`. A PRESS performs nothing on its own — it is remembered and
drawn pressed, and the RELEASE is what acts, and only if the pointer is still on the button that was pressed, so
sliding off the X is how a hand changes its mind. THE PILL IS THE TOOLBAR TOGGLE and sends `-toggleToolbarShown:`,
which toggles the window's toolbar when it has one and is quiet when it has none; `tests/toolbar.m` presses a window
with a toolbar and `tests/chrome_buttons.m` presses one without. And THE MINUS MARKS THE
STATE AND ANNOUNCES IT RATHER THAN TAKING THE WINDOW OFF THE SCREEN: there is no Dock to put a miniaturized window
in and no iconify in the protocol, which `-miniaturize:` states where it stands. `tests/chrome_buttons.m` is what
holds all of that to account — it presses the buttons through the seam and asks what HAPPENED, which is the half
no test about pixels can see.

### The toolbar, and the band it takes

**`NSToolbar` AND `NSToolbarItem` ARE HERE, AND THE BAND IS CARVED OUT OF THE FRAME.** Attaching a toolbar grows the
window's frame by the band's height — 52 points regular, 38 small — and leaves the CONTENT's size alone; hiding it
gives that height back. `-contentRectForFrameRect:` is the one place that knows, so the content view, the min/max
constraint conversion and the title bar all agree on where the content ends and the chrome begins. The chrome's pill
sends `-toggleToolbarShown:`, the same door a menu item would send and the same one the toolbar's own visibility uses.

**THE TOOLBAR IS A REAL VIEW AT THE CONTENT'S TOP EDGE.** It is a subview whose frame sits above its superview's
bounds, which works because `NSView` clips a child to its OWN frame rather than its parent's — the same fact the
chrome's painter relies on. That is what keeps a custom item view a real control with its own responder chain instead
of a bitmap painted by the window. The layout is left-to-right with the era's three spacers; a fixed space is eight
points and a flexible space shares what is left, and an item that does not fit is CLIPPED rather than moved into an
overflow menu (there is no toolbar overflow menu in this tier, and `-visibleItems` answers what is actually shown).

**WHAT THE CLASSES IMPLEMENT, AND WHAT THEY REFUSE.** The delegate supplies the default, allowed and selectable
identifier lists and the item for an identifier; insertion and removal announce `NSToolbarWillAddItemNotification`
and `NSToolbarDidRemoveItemNotification` and call the delegate's matching methods; display and size modes, selection,
validation (`-validateToolbarItem:` first, then `-validateUserInterfaceItem:`, then "does the target answer the
action") and the configuration dictionary are all real. Autosaving writes that dictionary to `NSUserDefaults`. The
CUSTOMIZATION PALETTE is the one absence: it is a panel and a drag session, and `-runCustomizationPalette:` refuses
by name while `-customizationPaletteIsRunning` answers NO. The dictionary's keys are this tier's own (`NSToolbarItemIdentifiers`
and friends) because Apple keeps its own keys private, and `-setConfigurationFromDictionary:` ignores a key it does not
know rather than pretending to understand one.

`tests/toolbar.m` is what holds the four contracts together: it attaches a toolbar and measures the frame, walks the
delegate's default list through insertions and removals, checks a validator that changes its item while answering,
clicks an item through the view and reads the selection, round-trips the configuration dictionary, and draws the band
into a bitmap to find its ground, its baseline and a label. `tests/chrome_buttons.m` still presses the pill on a window
with NO toolbar, where the door is correctly quiet.

### Still absent, and why

**FOUR THINGS THAT USED TO BE ON THIS LIST ARE NOT ANY MORE, AND THE LIST IS CORRECTED RATHER THAN QUIETLY SHRUNK:**
the SHEETS (`NSApplication -beginSheet:modalForWindow:…` and `-endSheet:returnCode:`, with the attachment and the
reply dance on `NSWindow`), the FRAME-AUTOSAVE strings, the CURSOR-RECT invalidation and the CHILD-WINDOW list are all
implemented. What is still absent is the DRAWER (the class — `-drawers` answers an empty array, which is Apple's own
contract), the TOOLBAR'S CUSTOMIZATION PALETTE (the toolbar itself is here; the palette refuses by name), and the
script-command doors, which are declared and REFUSE by name; what the window's close,
minimise and zoom buttons DO is now this tier's — each goes through the `-perform…` door its menu item sends — but
the MINIMISE is
still only a state the window marks and announces, because there is no Dock to put a miniaturized window in and no
iconify in the protocol (Kestrel is parked). The chrome's toolbar pill toggles the window's toolbar (`tests/toolbar.m`);
a window with no toolbar has nothing to toggle, which is the case `tests/chrome_buttons.m` presses. The three
symbols beside it ARE buttons, and that same probe presses them. The `NSTextInput` PROTOCOL is here and `NSTextView` answers it (`tests/text_marked_text.m`), and the
input-method CONTEXT is here too (`tests/text_input_context.m`), and SO IS THE METHOD (`tests/text_input_method.m`):
`AGInputMethod` is a dead-key table the context sends keys to first. AND THE CANDIDATE LIST IS HERE TOO — this
sentence said it was owed, and the note thirty lines below already said it had landed, so the two contradicted each
other: `AGVariantsInputMethod` offers a letter's readings in an `AGCandidateWindow` placed under the caret
(`tests/text_candidate_list.m`). And the
ALIGNMENT COMMANDS are NOT absent: `NSText` declares `-alignLeft:` and its three siblings and each is one `-setAlignment:`,
which the view moves glyphs for. **THE FIELD EDITOR IS NOT ON THAT LIST AND HAS NOT BEEN SINCE THE WINDOW LEARNED TO LEND ONE** —
`-fieldEditor:forObject:` is implemented and the field cells open their sessions with it, so what that clause used to
defer is a door that exists. The WORD commands are NOT in that list any more: `tests/text_word_movement.m`
drives Option+arrow and Option+Delete, because a word is a run of the string's own characters and needs no layout
model. And the MULTI-LINE TEXT VIEW has its FIRST SLICE: `NSTextView` holds many lines where `NSText` holds one
(`tests/text_view_lines.m`), and WRAPPING and SCROLLING are the slices above it (`tests/text_view_wrapping.m`,
`tests/text_view_scrolling.m` — the second including the FLIP that puts a document's first line at the clip view's
origin). **AND THE VIEW NOW READS A STORE THROUGH THE MANAGER** (`tests/text_view_store.m`): it owns the trio,
`-string` is the store's, the `malloc`'d visual array and the typesetter walk are GONE from the class, and a run put
in the store is the ink it draws — which is the rich-text half of the slice, with the BACKGROUND, UNDERLINE and
STRIKETHROUGH keys the manager paints (`tests/text_layout_attributes.m`) and the PARAGRAPH STYLE it aligns and breaks
by (`tests/text_paragraph_style.m`) and the GEOMETRY it lays out by (`tests/text_paragraph_geometry.m`) — the indents,
the two spacings and the three line-height properties, all read as the manager's own fragment geometry. **THE
HYPHENATION FACTOR HAS A READER NOW TOO** (`tests/text_hyphenation.m`): it is read as a hyphenation zone, a piece of the
word that did not fit is pulled onto the line, and the U+2010 that ends it is DRAWN INK rather than a character — so
the property that carried the longest "no reader" note in this file is read like the rest. The
BASE WRITING DIRECTION has a reader now (`tests/text_writing_direction.m`):
`+defaultWritingDirectionForLanguage:` asks the locale, and a natural paragraph in a right-to-left direction aligns
RIGHT; reordering a right-to-left script's glyphs stays the engine's, named at its door. The TABLE BLOCK is here
(`tests/text_table.m`), so a paragraph can carry a box with a ground and a border. **AND THE GRID IS HERE TOO**
(`tests/text_table_grid.m`): the manager measures the columns, lays each cell inside them and places the cells side by
side, rows as tall as their tallest cell. **AND THE BORDERS COLLAPSE** (`tests/text_table_collapse.m`): with
`-collapsesBorders` an edge two cells share is drawn once, by whichever block's border there is heavier (a tie going to
the min-side one), the table's own border competing with the outer cells on its four outer edges; and a cell's box is
its CELL rather than its text, and a table that does not fit FLOWS into the next container at a row boundary. The input-method
family is WHOLE: the `NSTextInput` protocol is here, the view ANSWERS it (`tests/text_marked_text.m`), the class that owns
a composition across keystrokes is here (`AGInputMethod`), and the CANDIDATE LIST is here — `AGVariantsInputMethod` offers
a letter's readings in an `AGCandidateWindow` placed under the caret (`tests/text_candidate_list.m`). It used to say all
of that was owed, and it has been true for several slices. ATTACHMENTS draw (`tests/text_attachment.m`) AND THEIR INLINE
ADVANCE IS THE RUN DELEGATE'S — a cell reserves its box in the line so the text after it flows around rather than over
it (`tests/text_attachment_flow.m`), which this sentence also used to call the flow slice still owed. Each absence is
stated rather than stubbed, and the refusals name themselves.

## Build

**clang is required** — Agora builds with clang only, and this is an Objective-C component.

```sh
cmake -S . -B build -DCMAKE_C_COMPILER=clang -DCMAKE_OBJC_COMPILER=clang \
      -DCMAKE_PREFIX_PATH="$PWD/../build-prefix"
cmake --build build
cd build && ctest
```

The siblings it builds on — `libagora-base` (Foundation), `libagora-drawing`, `libagora-text`,
`libagora-core` — come from the install prefix. `wayland-client`, `xkbcommon` and `wayland-protocols` are
system packages, not vendored, on the same terms as ICU and OpenSSL elsewhere in Agora; the `xdg-shell`
bindings are **generated** at build time by `wayland-scanner`, so a checked-in copy cannot silently age
against the protocol on the machine.

## Licence

MIT — see [`LICENSE`](LICENSE). The seam is Agora's own. The AppKit classes are the Fiwix AppKit's,
imported and then changed — the changes are recorded in [`PROVENANCE.md`](PROVENANCE.md).
- **AND THE MANAGER'S GLYPH SPACE IS THE LINE'S NOW, WHICH IS THE SHAPER'S AND NOT THE TEXT'S.** It was built ONE
  GLYPH PER CHARACTER: `cg_layOut` advanced its glyph base by the range's LENGTH and every fragment recorded that
  count, so the two mapping doors were arithmetic and the shape of the space was a convention of this class rather
  than a fact about the layout. With `CTLine` shaping, that convention was wrong — a ligature is three characters on
  one glyph and a hyphenated line has a glyph the text does not — so the base is advanced by
  **`CTLineGetGlyphCount`** and both doors translate through the run's own string indices
  (`CTRunGetStringIndices`), which is the rule the line's own caret doors already use. **AND THE END OF A RANGE IS
  MAPPED IN ITS OWN FRAGMENT**, because a range can span the break: mapping only the start and reporting the
  character length was right while the space was contiguous, and comes back short by whatever the two fragments'
  glyph counts differ by.
  MEASURED, and the whole slice is the difference between two numbers that used to be the same: a hyphenated
  twenty-three-character line reports **24** glyphs — the line HAS the `U+2010` its last fragment draws, and the store
  is still 23 characters — a three-row table's single-container glyph range is **(0,4)** and its next container's
  **(4,2)** where the old string-location convention gave 5, 6 and 2, and a seven-character store's inverse door
  answers `(4,3)` for `(4,3)` where it first answered `(4,7)`.
  **AND THREE OF THE FINDINGS ON THE WAY WERE THIS CLASS'S OWN, FOUND BECAUSE THE SUITE IS THE ONLY THING THAT
  MEASURES IT**: `-characterRangeForGlyphRange:` broke at the FIRST fragment holding a boundary index where every
  other door in the class lets the LAST one win; the map helper answered with a line's ABSOLUTE string range where
  every other answer it gives is line-relative, so a three-character range came back as five; and a table cell
  recorded its PARAGRAPH'S STRING INDEX as a glyph index, which was never this class's glyph space and only ever
  looked like it. MEASURED: `100% tests passed, 0 tests failed out of 63` — including `window-headless`, which had been
  failing on a headless Wayland compositor and passes now that it is there.
- **AND ONE TRAP IS WRITTEN DOWN, BECAUSE IT COST THE WHOLE SLICE'S MEASUREMENTS ONCE.** This suite's `ctest` sets
  `LD_LIBRARY_PATH` to the INSTALL PREFIX, and that takes precedence over the binary's own RUNPATH — so `ctest` tests
  the INSTALLED library and a `cmake --build` alone leaves it testing the previous one. **`cmake --install build`
  BEFORE `ctest`**, or the numbers are the numbers of the commit before. It is the same arrangement `libagora-text`'s
  suite has, and it presents as a plausible wrong measurement rather than as an error.
- **AND THE FACTOR IS A PARAGRAPH'S, WHICH IS WHY THIS LAYOUT MANAGER HYPHENATES ITSELF.** The engine learned to
  hyphenate in the previous slice (`kCTTypesetterOptionHyphenationFactor`), and the obvious tidy-up — pass the factor
  to the typesetter and delete `cg_hyphenatedLineForRange:` — is WRONG: **THIS CLASS MAKES ONE TYPESETTER FOR THE
  WHOLE STORE AND READS `hyphenationFactor` FROM EACH PARAGRAPH'S OWN STYLE.** An option is fixed when the typesetter
  is made, so one typesetter cannot carry two paragraphs' factors, and one per paragraph would re-typeset the whole
  string per paragraph. MEASURED, in `tests/text_hyphenation.m`: one store, two paragraphs, factors **0.0** and
  **1.0** — the first breaks at its space and the second reaches into its word, so one factor could only have got one
  of them right.
- **AND THAT CASE FOUND A BUG IN THE ENGINE'S TYPESETTER THAT NOTHING ELSE HAD SEEN.** Its first paragraph is
  `go internationalization\n` in a 74.7-point container, and it came back as **ONE 24-character fragment**: the
  typesetter returned the distance to the first newline WHATEVER the width was, so a paragraph longer than its
  container that ends in a newline was laid out as a single overflowing line. Apple's own sentence lists two triggers
  — "either by a hard break character in the stream or by FILLING THE SPECIFIED WIDTH" — and the fix compares them
  rather than ordering them. MEASURED after it: **8 fragments where there had been 1**, the first four
  `(0,3) (3,9) (12,9) (21,3)`. Every case in the engine's suite that involved a newline used a line short enough to
  fit, which is why it survived; the engine's suite now holds both sides of the rule.
- **AND A PICTURE SURVIVES A ROUND TRIP THROUGH RTF NOW, WHICH IS WHAT THE PNG ENCODER WAS FOR.** The writer emits RTF's
  own group — `{\\pict\\pngblip\\picw<px>\\pich<px>\\picwgoal<tw>\\pichgoal<tw> <hex>}` — with the bytes from
  `NSBitmapImageRep`'s encoder (Core Graphics' `CGImageDestination`), so the method has no image code in it either. The
  reader grew a PICTURE DESTINATION, the same mechanism its font and colour tables use: it collects the hex, decodes it
  through `NSImage`, and puts an `NSTextAttachment` on ONE character — a mark carrying it, the character, and a mark
  putting the plain attributes back. MEASURED, and the measurement is a round trip: a store of `A`, an attachment and
  `B` writes as **335 bytes** carrying `\\pict`/`\\pngblip` and the PNG signature's own hex, and reads back as **3
  characters** — `U+FFFC` in the middle, an attachment holding a **2.0x4.0** image, and the text either side untouched.
- **AND THE FIRST VERSION OF IT WROTE `{pictpngblip`.** The control words went out through a patch that ate their
  backslashes, so the group had the right shape and no control words at all — and the probe caught it only because it
  looks for `{\\pict` rather than for the word. A case that asserted "the RTF mentions a picture" would have passed.
  Same lesson as the level array indexed by the wrong number: the check has to be about the thing that can be wrong.
- **AND THE APP HAS HAD ITS SANITIZER SWEEP NOW, WHICH FOUND NO MEMORY DEFECT IN ITS OWN CODE.** `libagora-app` was
  rebuilt with `-fsanitize=address,undefined` (clang-19, `CMAKE_OBJC_FLAGS` as well as `CMAKE_C_FLAGS` — a purely C
  build would have left 71 of the 73 sources uninstrumented) and the whole suite re-run: **55 of the 68 test binaries
  clean, ZERO sanitizer reports**. The instrumented library was CONFIRMED to be the one loaded (`ldd` resolves
  `libagora-app.so` to the sanitizer build), because a sweep that silently ran the installed library would report
  nothing and mean nothing.
- **AND THE 13 THAT EXIT NON-ZERO ARE THE ENVIRONMENT, NOT THE SANITIZER — WHICH IS THE CONTROL THE RESULT NEEDS.**
  Each one was run a second time against the NORMAL build and exits IDENTICALLY (1, or 77 for the one that skips, or
  124 for the two that wait forever on a compositor this machine does not have). Same number, both builds, so they are
  not exercised rather than not passing — and saying so keeps "0 sanitizer reports" from quietly meaning "most tests
  never ran".
- **AND THE SWEEP MEASURED THE ONE COST THIS TREE HAS BEEN CARRYING, MUCH MORE SHARPLY THAN BEFORE.**
  `text_hyphenation` ran for **more than 280 seconds without finishing** under the sanitizer, and the stack showed why:
  per-character font fallback inside `fn_create_name_in_directory` → `fread`, the FONT-DIRECTORY WALK, which ASan makes
  an order of magnitude slower. With `FN_FONT_PATH` pointed at a single directory the same test finishes in **0
  seconds** with zero reports. So the defect recorded earlier as "a repeated miss still costs 7 ms" is worth far more
  than that on a real corpus, and the number now on the record is the honest one: a suite that takes NO MEASURABLE TIME
  with the walk bounded takes MINUTES without it.
- **AND BOTH VALUES ARCHIVE NOW, WHICH CORRECTED A CLAIM THIS README HAD BEEN MAKING.** `NSTextList` and `NSTextBlock`
  declare `<NSCoding, NSCopying>` in the 10.6 SDK — the list in its own header, the block in `NSTextTable.h`, which is
  where the SDK keeps it (its own header does not exist at 10.6, which a fetch proved) — and the note that said "no class
  in this layer archives" was simply false: `libagora-base` carries `NSCoder`, `NSArchiver`, `NSKeyedArchiver` and
  `NSUnarchiver`, and `NSArray`, `NSAttributedString`, `NSTrackingArea` and `NSFontDescriptor` already implement the pair.
  A list was one of the ones that had not.
- **AND WHAT EACH ARCHIVE CARRIES, AND WHAT IT MUST NOT.** A list carries its three facts and **NOT its enclosing list**,
  because that is a fact about the paragraph style's STACK rather than about the list: a decoded list is a LEVEL, and the
  style that receives it links it again. MEASURED — a linked list whose marker reads `3c` archives to a list whose marker
  reads `c`. A block carries its ground, its four edge colours, its twelve widths and its twelve value types, the widths
  and types as FLAT POSITIONAL arrays (layer-major) so a decoded block cannot disagree with itself about which width
  belongs to which edge.
- **AND A BLOCK'S COLOURS GO AS FOUR COMPONENTS, WHICH IS A DEVIATION WITH A REASON.** This layer's `NSColor` conforms to
  `NSCopying` and NOT to `NSCoding`, so archiving the OBJECT would produce an archive this tree could not read back. The
  components are what a colour IS, so a decoded block answers the same colour — and the day `NSColor` archives, that key
  can carry the object with old archives still decoding.
- **AND `NSTextListPrependEnclosingMarker` IS APPLIED, WHICH NEEDED A FACT NO PUBLIC API CARRIES.** The option means an
  item in a nested list is numbered `2a` rather than `a`, and applying it needs the ENCLOSING LIST — which 10.6 gives no
  setter for, because Apple keeps it in the private `_listSecondary` ivar its own header declares and fills it from the
  paragraph style's ARRAY, since the array IS the nesting ("nested from outermost to innermost"). So `NSTextList` uses
  that same slot, `NSParagraphStyle`'s `-setTextLists:` links the stack level by level, and `-markerForItemNumber:` walks
  outwards RECURSIVELY — three levels read `1a-`, not one level's answer. MEASURED: item 3 in a stack of decimal-outside
  and alpha-inside is **`3c`**, item 1 is **`1a`** (the same ITEM number, not a running count), and the same inner list
  outside a stack is still plain **`c`**.
- **AND THE STYLE NOW COPIES THE LISTS IT IS GIVEN, WHICH CHANGED AN ASSERTION THIS PROBE HAD.** Linking a stack is a fact
  about *that style's* nesting, so setting it on a caller's object would be changing it behind their back — the style
  takes copies, and the probe that used to assert pointer identity now asserts the copy explicitly and the ORDER by
  format. A copy of the style rebuilds the chain, so the option survives it.
- **AND THE TIE IS NOT CARRIED BY RTF**, which has no such option: a document round trip loses it, and that boundary is
  stated in `NSTextList.h` rather than left to be discovered.
- **AND WHAT IS STILL NOT CARRIED IS NAMED**: a `\\pict` whose blip is not PNG is decoded by `NSImage` or dropped with
  an `APPKIT-REFUSE` line rather than drawn as nothing; and the tracking family — which this note used to say waited on
  the modal loop `NSCell.h` refuses — is HERE now, driven by the text view's own event stream (see the attachment
  tracking bullet above), so that clause is a record of a ground that expired rather than an open row.
- **AND RTFD WRITES NOW — THE PACKAGE FORM — WHICH NEEDED TWO THINGS THAT DID NOT EXIST TOGETHER UNTIL THIS SLICE.**
  RTFD is not a different codec: it is the SAME RTF document, with its pictures stored as FILES beside it and its text
  REFERRING to them (`{\\NeXTGraphic <name> \\width<tw>\\height<tw>}`). So the RTF writer grew a SINK — `fn_rtf_text`
  (`NSAttributedStringRTF_internal.h`): with none it writes `{\\pict\\pngblip…}` inline as it always did, with one it
  writes the reference and hands back the bytes — and `NSAttributedStringRTFD.m` is the package around it. Two writers
  would be two chances for `TXT.rtf` to disagree with `-RTFRepresentation`, and a reader would have to guess.
  MEASURED, `tests/text_rtfd.m`: a store of `A`, an attachment and `B` makes a package that is a DIRECTORY holding
  exactly **2 files** — `TXT.rtf` and `pic.png`, the name the attachment's OWN FILE WRAPPER carried — whose text names
  `\\NeXTGraphic pic.png` and does **not** also carry the picture inline, whose picture file begins with the PNG
  signature, and whose SERIALIZED form reads back as the same directory with the same two names.
- **AND `NSTextAttachment` HAS THE FILE-WRAPPER PAIR AT LAST** (`-fileWrapper`, `-initWithFileWrapper:`,
  `-setFileWrapper:`), which is what a package document is built out of — the picture and the file are SEPARATE facts
  on one object, and the probe checks both. `-initWithFileWrapper:` is the designated initialiser, which is Apple's
  arrangement.
- **AND FOUNDATION HAD TO LEARN TO DEFER, WHICH THE FIRST ATTEMPT GOT WRONG.** `libagora-base` refuses RTFD because it
  has no attachment class — true, and still true. The obvious override is an AppKit CATEGORY on `NSAttributedString`
  implementing the same selectors, which is exactly how `-initWithRTF:` works (Foundation only DECLARES that one) —
  and it is MEASURED LOSING: the class's own method is what resolves, so the probe printed Foundation's refusal and no
  category method ran. The fix is a SEAM in Foundation — one function pointer, installed by the AppKit from a
  CONSTRUCTOR (this tree's recorded choice over `+load`, for loader ordering) — and `-RTFDFromRange:` serializes
  whatever the installed writer returns, so the two doors cannot disagree.
- **AND READING A PACKAGE BACK LANDED, WHICH THIS NOTE USED TO CALL THE NEXT CUT.** `-initWithRTFD:documentAttributes:`
  and `-initWithRTFDFileWrapper:documentAttributes:` are here, and the loop is CLOSED rather than inspected: write →
  serialize → read gives back the same three characters, the middle one U+FFFC with the picture at its written size and
  the FILE WRAPPER still carrying `pic.png`, and the in-memory package reads directly through the other door. The RTF
  reader learned `\NeXTGraphic`: the name is collected where a `\pict`'s hex would be, resolved against the package's
  children when the group closes, and the attachment it builds carries the wrapper as well as the decoded image. A
  name the package does not hold, and a package with no readable `TXT.rtf`, are refused by name rather than drawn as
  nothing or answered as an empty document.
- **AND THE READERS REPORT THE DOCUMENT NOW, WHICH THE OLD ONES DID NOT.** Both took a `documentAttributes:` out-
  parameter and wrote a single key whose value was a STRING naming `NSUTF8StringEncoding` rather than the `NSNumber`
  the 10.6 header specifies — and the document TYPE was not reported at all. The AppKit header now declares
  `NSDocumentTypeDocumentAttribute`, `NSRTFTextDocumentType`, `NSRTFDTextDocumentType` and
  `NSCharacterEncodingDocumentAttribute`, and the reader fills the dictionary with the TYPE (RTF, or RTFD when a
  package is behind the text) and the ENCODING as an `NSNumber` holding `NSUTF8StringEncoding`. MEASURED, in
  `tests/text_rtf.m` and `tests/text_rtfd.m`: the plain parse reports type **`NSRTF`** and encoding **4**; both package
  doors report **`NSRTFD`** with the same integer; and a FAILED parse leaves the dictionary UNTOUCHED rather than
  describing a document that is not there. **AND THE WRITERS' SIDE IS NO LONGER EMPTY**, which the next bullet is.
- **AND THE WRITERS CONSUME THREE DOCUMENT FACTS NOW — THE TAB INTERVAL, THE VIEW MODE AND THE HYPHENATION SWITCH.**
  `fn_rtf_text` takes the writer's document-attributes dictionary and the RTFD doors pass theirs through.
  `NSDefaultTabIntervalDocumentAttribute` is RTF's `\deftabN` in TWIPS (twenty to the point);
  `NSViewModeDocumentAttribute` is `\viewkindN` — the spec's own table says **1 is Page Layout** and **4 is Normal**,
  which are the attribute's two states; and `NSHyphenationFactorDocumentAttribute` is the on/off `\hyphautoN`.
  THE READER DOES NOT MERELY REPORT THEM: `\deftabN` becomes a `NSParagraphStyle` with `-defaultTabInterval` set and
  `\hyphauto` sets its `-hyphenationFactor`, because those are what the layout reads — Core Text's own default is
  twelve stops at 28 points, and a paragraph with no style would silently ignore both. MEASURED: 36 points writes
  `\deftab720` and reads back as **36.0** and applies **36.0**; page layout writes `\viewkind1`, normal writes
  `\viewkind4`, and **1**/**0** come back; a factor of **0.5** writes `\hyphauto1` and comes back as **1.0**, because
  RTF carries a switch rather than the 0..1 factor — THE MAGNITUDE ABOVE ZERO IS LOST, and that is stated here and at
  the key. A bare `\hyphauto` is the spec's own form of ON and reads as 1.0. `-RTFRepresentation` takes no dictionary,
  so its bytes are unchanged.
- **AND THE TWO THAT CANNOT BE WRITTEN HONESTLY ARE STILL NAMED.** A DOCUMENT BACKGROUND COLOUR is not written: the
  fetched 1.5/1.6 specs define `\cbN` as a CHARACTER background colour (the page background is a `\background` shape
  destination this codec neither reads nor writes), so mapping the document attribute onto `\cb` would paint every run
  and mean something else. And THE READ-ONLY FLAG is not written: those specs publish `\formprot`, `\revprot` and
  `\annotprot` — mutually exclusive protections for forms, revisions and annotations — and no read-only document
  control word at all; a guessed word would be a wrong document rather than an absent fact.
- **AND THE REFUSAL CENSUS IS A TEST NOW, NOT 129 PROSE CLAIMS.** This layer holds 129 `APPKIT-REFUSE` sites across 24
  files, and until this slice nothing watched them: a door quietly acquiring a real implementation was an improvement
  nobody recorded, and a real door quietly degrading into a refusal was a regression nobody saw. `tests/refusal_census.txt`
  is the count PER FILE, and `tests/refusal_census.cmake` recomputes it on every build IN BOTH DIRECTIONS — a file
  holding a refusal the census does not name fails, a census line whose count has moved fails, and the TOTAL is checked
  against `# total:` as well. MEASURED, and the guard was PROVED TO BITE rather than assumed to: appending one
  unrecorded refusal to `NSMenu.m` produced `NSMenu.m: the census says 19, the source has 20` and `the census says 129
  in total, the sources have 130`, and restoring the file passed again.
- **AND IT IS A CENSUS RATHER THAN A CEILING, WHICH IS THE DIFFERENCE BETWEEN HOLDING THE PROPERTY AND HOLDING A
  NUMBER.** A count that may only fall says nothing about WHERE a refusal is — moving one from a class that needed it
  to a class that did not would pass. Per-file counting means the only way to change the answer is to edit the census,
  so adding or removing a refusal becomes a deliberate act with a diff.
- **AND THE C SURFACE WAS CHECKED THE OTHER WAY, WITH THE INSTRUMENT `libagora-text` USES — AND IT HAS NO HOLES.** `nm
  -D` against the 18 C functions this layer declares leaves exactly ONE name out, `NSEventMaskFromType`, and that one is
  `NS_INLINE` in `NSEvent.h` — deliberately not a symbol, which is Apple's own shape for it. **THE LESSON IS ABOUT THE
  EXTRACTOR, NOT THE LIBRARY**: a declared-and-undefined check that does not skip inline definitions reports a hole
  where the header meant a function. The same check on Objective-C is impossible at all, because a method is dispatched
  dynamically and appears in no symbol table — which is why this half needed a census instead of an allowlist.
- **AND THE OWED NOTES ARE HELD THE SAME WAY, AND COUNTING THEM CORRECTED A NUMBER THIS README USED.** A refusal is what
  the IMPLEMENTATION says it cannot do; an owed note is what the HEADER says it does not do yet — the same kind of claim,
  drifting the same way. `claims_census.cmake` is now ONE script with two instantiations: `refusal_census.txt` (`.m`,
  `APPKIT-REFUSE`, **129 sites over 24 files**) and `owed_census.txt` (`.h`, the word OWED, **17 claims over 10 files**),
  each compared per file and in total, in both directions.
- **AND THE NUMBER FOR THE OWED NOTES HAD BEEN WRONG THE WHOLE TIME: 38 WAS A SUBSTRING, 17 IS THE COUNT.** The first
  count matched `OWED` anywhere — including inside `MAC_OS_X_VERSION_MAX_ALLOWED` and `BORROWED` — and **21 of the 38
  hits were parts of other words**, so the figure this README quoted was more than double the truth. The census counts a
  WORD now, and the instrument was proved to be about the thing it measures: appending
  `MAC_OS_X_VERSION_MAX_ALLOWED and BORROWED` to a header leaves the census passing, while appending one real
  `OWED` claim fails it with `NSView.h: the census says 0, the source has 1` and `the census says 17 in total, the
  sources have 18`.
- **AND WHAT THE MARKER DOES NOT COVER IS SAID RATHER THAN IMPLIED**: claims phrased "refuses by name" or "stays ABSENT"
  are the same kind of statement and carry no marker, so they are not counted. The census holds what the marker marks —
  the emphatic form this tree writes its owes in — and says so in its own header.
- **AND `NSTextList` EXISTS NOW, AND CHECKING IT AGAINST THE 10.6 SDK CHANGED WHAT WAS WRITTEN.** The class was to be
  built "with Apple's marker-format constants" — and **10.6's `NSTextList.h` IS THIRTY-FOUR LINES AND DECLARES NO
  MARKER-FORMAT CONSTANTS AT ALL**: no `NSTextListMarkerDecimal`, no `{decimal}` family, nothing. What it declares is
  `NSTextListPrependEnclosingMarker`, five doors and `NSCoding`/`NSCopying`, and that is what `NSTextList.h` here
  transcribes. So the header drops the invented constants, and the format VOCABULARY is documented as what it is — a
  reading of Apple's documentation rather than a transcription of its header — the distinction being the difference
  between a checkable claim and a guess.
- **AND `NSParagraphStyle` DECLARES `-textLists` TWO LINES FROM `-textBlocks`**, "nested from outermost to innermost",
  which settles where a list lives: `-textBlocks` has been on this class all along, so `-textLists` is its sibling —
  carried, coped with the style (both arrays copied item-by-item), and empty rather than nil when unset.
- **AND THE MARKER IS ARITHMETIC, SO THE PROBE MEASURES ARITHMETIC.** Every family is checked at the numbers an
  off-by-one breaks: the Roman subtractive pairs (4 `iv`, 9 `ix`, 40 `xl`, 90 `xc`, 1990 `mcmxc`), the ALPHABETIC
  ROLLOVER (26 `z` → 27 `aa` → 52 `az` → 53 `ba`, which is bijective base 26 and not base 26), the radix formats (255
  `ff`/`FF`, 64 octal `100`), and every bullet BY CODE POINT (U+2022, U+25E6, U+25AA, U+2610, U+2713, U+25C6, `-`) —
  because a format that returned its own name would pass any check that only asked for something non-empty.
- **AND TWO THINGS ARE NAMED RATHER THAN FAKED**: `NSCoding` is declared by 10.6 and not implemented (no class in this
  layer implements it), and `NSTextListPrependEnclosingMarker` is RECORDED and not yet APPLIED — prepending the
  enclosing marker needs the enclosing list, which is the paragraph style's array to link, and that link is a cut of
  its own rather than a guess here. An unknown format is refused by name and answered in decimal, because a caller with
  a newer format can act on a number and not on an empty string.
- **AND THE CENSUS CAUGHT THIS SLICE, WHICH IS THE POINT OF HAVING BUILT IT ONE SLICE EARLIER.** The two new refusals
  made `appkit-refusal-census` fail with `NSTextList.m: the census says 0, the source has 2` and
  `the census says 129 in total, the sources have 131`, so recording them was a deliberate edit with a diff rather than
  a side effect. That is exactly the drift the census exists to make visible, caught on its first real opportunity.
- **AND LISTS REACH RTF NOW, ON THE WRITING SIDE, WHICH IS THE HALF THAT MAKES THE CLASS USEFUL.** The writer emits the
  format's own three-part shape: a `{\listtable}` in the header with ONE `{\list}` per distinct *stack* of lists (a
  paragraph in two lists is identified by both formats, because the same inner bullet under different outers is a
  different list to a reader), each level stating its number format with `\levelnfc` — **0 decimal, 1/2 roman, 3/4
  alpha, 23 bullet**, which is Word's numbering and the only thing that survives the trip into `NSTextList` — and its
  start with `\levelstartat`, which is `-startingItemNumber`. Each paragraph then names its list with `\ls` and its depth
  with `\ilvl`. MEASURED: two stacks over three paragraphs produce a table with `\listid1`/`\listid2`, `\levelnfc0` and
  `\levelnfc23`, `\levelstartat5` for a list that begins at 5, and exactly TWO `\ls` — so the unlisted third paragraph
  stayed unlisted.
- **AND NOTHING IS INJECTED INTO THE TEXT, WHICH IS ASSERTED BECAUSE IT WOULD LOOK CORRECT HERE.** The marker is drawn
  from the paragraph style, so a writer that also wrote `5.` into the string would double the marker in every reader that
  honours the style — and would pass any check that only asked whether the text survived. The probe checks for the
  ABSENCE of marker text as well as the presence of the paragraphs.
- **AND `\leveltext`/`\levelnumbers` ARE NOT WRITTEN, WHICH IS A BOUNDARY RATHER THAN AN OMISSION**: those carry the
  placeholder text a reader uses to draw a marker *out of the file*, and this tier draws markers from `NSTextList`
  instead. A reader that renders markers from RTF's placeholders is a different reader from this one, and the READING
  HALF IS THE NEXT CUT — it will parse `{\listtable}`, `\levelnfc` and `\ls`/`\ilvl` back into `-textLists`, which is
  what closes the loop the way the picture slice did.
- **AND LISTS READ BACK NOW, WHICH CLOSES THE LOOP THE WAY PICTURES DID.** The reader grew a LIST TABLE destination —
  the fifth, beside the font, colour, picture and graphic ones — that turns each `\levelnfc` back into an `NSTextList`
  (`0` decimal, `1`/`2` roman, `3`/`4` alpha, `23` disc, and an unknown number REFUSED BY NAME and read as decimal), and
  `\ls`/`\ilvl` into the paragraph's `-textLists` — a STACK, outermost first, which is the shape 10.6 declares. The
  state is reset at `\par` and at `\pard`, so a paragraph with no `\ls` of its own does not inherit the previous one's.
  MEASURED by reading the writer's own document back: **1 list** on the first paragraph (decimal, **beginning at 5**, the
  number the document stated), **2** on the nested one (decimal outside, disc inside — the format the `\levelnfc23`
  named), and **0** on the third, which named none.
- **AND A STYLE EXISTS FOR A LISTED PARAGRAPH EVEN WHEN IT IS LEFT-ALIGNED**, which the mark machinery had never needed
  before: it built a paragraph style only to carry a non-default alignment, so a left-aligned paragraph in a list would
  have had nowhere to put its lists.
- **AND THE REFUSAL CENSUS CAUGHT THIS SLICE TOO** — the unknown-format refusal made it fail with
  `NSAttributedStringRTF.m: the census says 2, the source has 3` and `the census says 131 in total, the sources have
  132` — and the reader's own unknown-format refusal did it again one slice later (`4` and `133`), so recording it was
  again a deliberate edit.
- **AND THE COST THE SWEEP MEASURED IS FIXED, WHICH IS WHAT A MEASUREMENT IS FOR.** Two halves, and the numbers separated
  them: `CTFontMatchingCopyAvailableDescriptors` built the whole installed-font list — opening EVERY font file — on every
  call, and per-character fallback calls it once per character, so it is now built once per font set and keyed on TWO
  generations (the font set's own, and the matching layer's VISIBILITY state — **a one-generation cache was tried first
  and the engine's own suite refuted it in one case**, because a disabled face left the list and the cache kept offering
  it); and `libagora-drawing`'s name cache was sized for a CADENCE of 64 when a fallback search walks a whole font set
  (154 faces here), evicting its own entries, so it is 512 now. MEASURED: a repeated fallback miss **0.0001 s against
  0.0070 s**, and `text_hyphenation` under the sanitizer **13 SECONDS against MORE THAN 280** — zero reports either way,
  because the cost was pure file I/O and never a memory defect.
- **AND THE 60-SECOND CASE IS 4 SECONDS NOW, WHICH SETTLES WHERE ITS TIME WAS GOING.** `appkit-text-layout-overflow` was
  the reason this suite did not get run casually: MEASURED at ~60 s before the font-walk fix and **4 s** after it, with
  the case's own answer unchanged (`0 case(s) failed`, and the same `2 fragment(s)` it always reported). It was never
  doing slow WORK — it was paying the directory walk once per character that needed a fallback face, which is the same
  defect the sanitizer sweep found in `text_hyphenation` and the same one the two fixes behind it addressed.
- **AND THE WHOLE SUITE IS RUNNABLE NOW, WHICH IS THE POINT OF FIXING IT**: **70 of 70 tests pass in 107 SECONDS**, and
  the slowest case is a headless window test at **7.3 s** — not a text case, and not close to a minute. `window-headless`,
  `events-headless` and `menu-headless` pass in the same run, so the compositor cases are green here too. A suite that
  takes under two minutes is one somebody runs after every change; that is worth more than the feature the time was
  being spent on.
- **AND `NSTextInputClient` EXISTS NOW — THE PROTOCOL, WHICH WAS THE ONE PIECE OF THE INPUT-METHOD STORY THAT WAS NOT
  THERE.** The machinery has been here for slices: a marked-text composition (`tests/text_marked_text.m`), the context
  (`tests/text_input_context.m`), a dead-key table (`tests/text_input_method.m`), a candidate window
  (`tests/text_candidate_list.m`). What a THIRD-PARTY input method or a ported client declares against was not: 10.6
  declares fifteen doors on `NSTextInputClient` and this tree declared none of them. `NSTextView` conforms to both
  protocols now — the older `NSTextInput` it always answered, and this one — and nine of the fifteen are new methods, so
  the probe holds the view as `id <NSTextInputClient>` and calls EVERY door through the protocol, which is what a ported
  client actually needs.
- **AND TWO OF THE NEW DOORS ARE FACTS ABOUT THIS LAYER, STATED RATHER THAN FAKED**: `-baselineDeltaForCharacterAtIndex:`
  is 0 because every line here sits on its baseline, and `-drawsVerticallyForCharacterAtIndex:` is NO because there is no
  vertical text. `-windowLevel` is `NSWindow`'s own door rather than a second opinion, and
  `-attributedSubstringForProposedRange:actualRange:` CLAMPS the proposal and writes back what it actually got, which is
  the whole reason that door takes two ranges where `NSTextInput`'s takes one.
- **AND THE FRACTION DOOR MEASURES AGAINST A CHARACTER'S BOX, WITH THE DEVIATION NAMED, BECAUSE THE ALTERNATIVE WOULD BE
  WRONG.** The obvious source is `NSLayoutManager`'s `-boundingRectForGlyphRange:inTextContainer:`, and MEASURING IT gave
  **200 points for a single glyph** — that door answers the FLOW BAND (the column's width) rather than an ink box. So the
  fraction is measured against the view's own per-character rect, which is what the caret is placed from; the text has one
  glyph per character except where a face ligates or composes, so the two coincide for what this layer draws. The probe
  tests the CONTRACT (a fraction in [0,1], deterministic, non-decreasing across the line) rather than an absolute number,
  because a view with no window has degenerate character rects and an absolute check there would measure the geometry
  rather than the arithmetic.
- **AND THREE OF THE FIFTEEN WERE STILL MISSING, WHICH THE BUILD CAUGHT AND THE PROBE NOW HOLDS.** The view declared
  `NSTextInputClient` and answered twelve of its fifteen required doors: `-insertText:replacementRange:`,
  `-setMarkedText:selectedRange:replacementRange:` and `-firstRectForCharacterRange:actualRange:` were absent, so the
  conformance claim was false at runtime for any ported input method asking the modern spellings — and the compiler's
  `-Wprotocol` warning was the thing that said so. They are here now, and MEASURED through `id <NSTextInputClient>`:
  inserting `XY` over (1,2) of `abcd` gives **`aXYd`** with the caret at **3**; `NSNotFound` replaces the selection
  (`abZd`) or, during a composition, the MARKED range (composition `ab` confirmed by `q` gives **`q`**); marking `XY`
  over (1,2) gives **`aXYd`** with the mark at **(1,2)** and the selection at **(2,1)** inside it, and the next call
  with `NSNotFound` grows it to **`aZWd`** with the mark still at **(1,2)**; and
  `-firstRectForCharacterRange:actualRange:` writes back the CLAMPED range — (2,20) comes back as **(2,2)** and (10,5)
  as **(4,0)**, each answering the same rectangle the old one-range door does for that range. THE HONEST BOUNDARY IS
  NAMED TOO: the characters are inserted and inherit the run at the insertion point, so an `NSAttributedString`'s
  ATTRIBUTES are not applied by this pair.
- **AND THE CHECK THAT LED HERE WAS WRONG TWICE BEFORE IT WAS RIGHT, WHICH IS WORTH RECORDING**: a script comparing
  `NSTextInput`'s doors against `NSTextView.m` reported `-selectedRange` and `-doCommandBySelector:` as unimplemented —
  both are INHERITED (`NSText` and `NSResponder`), so THOSE TWO FINDINGS were artefacts of looking at one file. BUT THE
  CONFORMANCE WAS NOT COMPLETE, which the same honesty has to say: the compiler found the three range-carrying doors
  above, and they were real. The lesson is the one this file keeps re-learning: a check has to be about the thing
  it claims to measure, and INHERITANCE IS PART OF THAT THING — as is the COMPILER's view of a protocol.
