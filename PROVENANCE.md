# Provenance

## What was imported

The AppKit classes in this repository are the **Fiwix AppKit**, taken from the tree this component is being
built from and then changed. Its author and its licence are the same as this repository's, so the import is
one repository's code moving to another's rather than third-party code arriving.

| | |
|---|---|
| Source | `Fiwix/userland/AppKit/` (sibling checkout, `../Fiwix`) |
| Revision | `e57439989dbfc3fdb5e60d2a4fe06a8d04c49c10` (2026-10-11) |
| Files | 32 `.m` and 34 `.h`, listed in this repository's first AppKit commit |
| Licence | MIT, © 2026 Kyle J. Cardoza — see [`LICENSE`](LICENSE) |

What is **not** imported, and is this repository's own: `platform/` — the window-server seam and the keyboard
translation — `tests/`, and the **workspace services** (`NSWorkspace.h`, `NSRunningApplication.h`), which are written
here from the 10.6 SDK's headers because the AppKit that came from Fiwix has no session backing to adapt. They are
why this component can build at all: the AppKit it came from is linked against an X server and this one is not.

`NSStatusItem.h`, `NSWorkspace.h` and `NSRunningApplication.h` are transcribed in Apple's spelling from the MacOSX10.6
SDK headers (`Versions/C/Headers/`), the same recipe `libagora-text/PROVENANCE.md` records for its own; the
IMPLEMENTATIONS are this repository's and are backs onto Agora's own components, never Apple's code. Where an Apple
door cannot be honoured here the header says so at the door (`NSRunningApplication -forceTerminate`, `-launchDate`),
and `tests/owed_census.txt` counts them like every other owed note in this library.

## What was changed, and why

### 1. Core Text is C here, and Objective-C there (5 files, 12 sites)

The Fiwix AppKit was written against a CoreText that is an Objective-C framework — `CTFontRef` was a class
pointer and the retain family was `CTFontRetain`/`CTFontRelease`. Agora's `libagora-text` is **plain C**:
`CTFontRef` is ``typedef const struct __CTFont *``, every door is a C function, and the retain family is
Core Foundation's. The adjustments are mechanical and complete:

- `NSFont.h`, `NSFontDescriptor.h` — the forward `@class` plus `typedef CTFont *CTFontRef` becomes a
  repeated typedef in Core Text's own spelling (``const struct __CTFont *``), which is what keeps the two
  headers independent;
- `NSFont.m`, `NSFontDescriptor.m`, `NSStringDrawing.m` — `CTFontRelease`, `CTFontDescriptorRelease`,
  `CTFontDescriptorRetain`, `CTLineRelease`, `CTFrameRelease` and `CTFramesetterRelease` become
  `CFRelease`/`CFRetain`, since a Core Text object IS a Core Foundation object here;
- `NSStringDrawing.m` — `NSMakeRange` becomes `CFRangeMake` where the result is handed to
  `CTFramesetterCreateFrame`, and the attribute dictionary the framesetter is given is built as a
  `CFMutableDictionaryRef`/`CFAttributedStringRef` rather than through `NSAttributedString`, because that
  initializer builds an Objective-C object where a CF one is required.

### 2. The window server is Agora's, not Xlib's (this is the substantive change)

`NSWindow.m` and `NSScreen.m` were X clients. All 42 Xlib calls are gone and the header no longer includes
`<X11/Xlib.h>` or `<X11/Xutil.h>`; the seam is `AGWindowServer.h`. The mapping, door by door:

| was | is |
|---|---|
| `XOpenDisplay` | `AGWindowServerConnect` (one connection per process, as before) |
| `XCreateSimpleWindow`, `XStoreName` | `AGWindowCreate`, `AGWindowSetTitle` |
| `XMapWindow` | `AGWindowShow` |
| `XDestroyWindow` | `AGWindowDestroy` |
| `XCreateImage` + `XPutImage` + `XDestroyImage` | `AGWindowBeginFrame`/`AGWindowEndFrame`, with the backing store copied into the frame the compositor hands over |
| `XPending`, `XNextEvent`, `XPeekEvent`, `XPutBackEvent` | a per-window `NSEvent` queue filled by the seam's event handler, and `AGWindowServerDispatchTimeout` for the wait |
| `XLookupString` | gone — `AGKeyboard` (xkbcommon) translates the evdev code to UTF-8 before the event is made |
| `XQueryPointer` | the last pointer position the seam reported (`wl_pointer.motion`) |
| `XFlush` | `AGWindowServerFlush` |
| `XMoveResizeWindow` | gone — a Wayland client does not place or move its toplevel |
| `XUnmapWindow` | gone — `xdg-shell` has no unmap |
| `XIconifyWindow` | gone — no iconify |
| `XLowerWindow`, `XRaiseWindow` | gone — no stacking |
| Expose handling in the pump | gone — the client owns the pixels; the frame callback is the repaint request |
| `DisplayWidth`/`DisplayHeight`, `DefaultDepth`, `DisplayString` | `AGWindowServerScreenSize`, which reads `wl_output` |

The three that are **not** a like-for-like replacement are deviations rather than gaps, and each is recorded
at the door that carries it in `NSWindow.m`/`NSWindow.h`: a client does not place its own window, there is no
unmap or iconify or stacking, and there is no Expose. `-windowNumber` also changed meaning — it was the X
window id and is now a per-process ordinal, because a Wayland client is given no window id.

### 3. Prose, which the two changes above made false

Comments across `NSWindow.h`, `NSEvent.h`, `NSCursor.h`, `NSScreen.h`, `NSApplication.h`, `NSEvent.m`,
`NSApplication.m`, `NSScreen.m`, `NSGraphicsContext.h` and `NSGraphicsContext.m` described the platform as
Xfb/X11 or named the X server as the authority for a value. Each was updated to name the seam, and where the
OLD behaviour was the reason a design exists, the reason was kept and re-stated (`NSWindow.m`'s header still
says why the coordinate conversion lives in one function).

### 4. Two defects in the import, found by testing the input path

Neither of these is a porting change — they are bugs the imported code had, found when the event path was
tested for the first time (`tests/appkit_events.m`, in this repository). Both are recorded here because they
are changes to imported behaviour rather than additions.

- **The responder chain between views was never wired.** `NSApplication.h` names the chain — `NSView` → its
  superview → … → the window → the application — and nothing ever set it: `-addSubview:` set `_superview` and
  left `-nextResponder` to `NSResponder`'s ivar, which is nil unless someone sets it. Because EVERY event
  method `NSResponder` implements is one line that forwards to `-nextResponder`, a view whose successor was
  nil SWALLOWED the event it did not override. `NSWindow.m` carried the workaround — `-makeFirstResponder:`
  linked the responder straight to the content view — which made a click arrive but skipped every ancestor
  between them. `-nextResponder` is computed from the hierarchy now, an explicit `-setNextResponder:` still
  wins, the window's successor is the application, and the workaround is gone.
- **`-[NSWindow sendEvent:]` never hit-tested.** Every mouse event went to the first responder, so a click on
  a control inside a subview reached that subview only if it happened to be the first responder. Mouse events
  now go to the deepest view containing the point, which is `NSView`'s own `-hitTest:`. And `-flagsChanged:`
  was unreachable — it was in `sendEvent:`'s switch and nothing ever produced the type — so the seam now
  reports whether a key is a MODIFIER (`AGKeyboardKeyIsModifier`, from the xkbcommon keysyms) and the AppKit
  chooses `NSFlagsChanged` from that answer rather than treating every key as a keystroke.

### 5. What was added rather than changed

- `platform/AGWindowServer.h`, `platform/AGWindowServer-Wayland.c` — the seam and its `xdg-shell`
  implementation, including the `wl_output` handling `NSScreen` needs.
- `platform/AGKeyboard.h`, `platform/AGKeyboard.c` — evdev codes to text and modifiers through xkbcommon.
- `tests/` — the seam's tests, the keymap test, and `appkit_window.m`, which drives a real `NSWindow`.

## 6. Transparent windows

The seam's buffers were `XRGB8888` — no alpha — and `NSWindow` forced its backing store opaque
(`kCGImageAlphaNoneSkipFirst`) and OR'd `0xFF000000` into every pixel on the way out. That makes every window
opaque, which the desktop's icon layer cannot be: it must show the WALLPAPER through. So:

- **`AGWindowSetTransparent`** (the seam) chooses `WL_SHM_FORMAT_ARGB8888` — and the compositor ALREADY blends such
  a buffer source-over (`window-server/src/output.c`), so nothing on the server side changed;
- **`NSWindow`** picks `kCGImageAlphaPremultipliedFirst` for a non-opaque window, CLEARS its pixels to alpha zero
  before the tree draws instead of filling them, and copies the alpha byte out instead of setting it.

**MEASURED, and one bug found by the probe:** `AGWindowSetTransparent` first LET the old buffer go without
remaking it, and `AGWindowBeginFrame` then refused to paint the window for ever — an icon window that showed
nothing at all. It now remakes the buffer through the same path a resize takes.

## 7. The menu bar's window needs a second chance at a door every loop passes

**MEASURED BUG, and it was a RACE.** `-[NSApplication setMainMenu:]` measures the bar's window from the MENU-BAR
REGION the compositor sends (`AGWindowServerMenuBarArea`), and a region that has not arrived yet is a region of no
width — so it returned early and **created no window at all**. The region arrives asynchronously with the rest of
the connection's first events, so whether it was known at `-setMainMenu:` time came down to timing: *the same
program against the same compositor produced a menu bar in one run and not in the next*.

`-run` already re-measures once for exactly this reason — its own comment says "a main menu set before the
connection existed has nowhere to go" — but a loop of its own never goes through `-run`. Workspace's W0 loop is
one, which is how the bug was found: an application with a main menu, a running loop, and no bar.

**FIX:** the re-measure now also happens at the top of `-nextEventMatchingMask:…`, which is the ONE door every
loop passes through — `-run`'s, the modal loop's and any application's own. It is a one-off: the guard is
`_mainMenu != nil && _menuBarWindow == nil`, so once the window exists it costs a nil test per event.

## 8. A release no longer ends a menu bar's session

**MEASURED BUG, found by putting a real menu bar in front of this tier's own diagnostic (`APPKIT_MENU_DIAG=1`) and
clicking the application menu once.** `NSMenuView -mouseDown:` begins a session and drives it, and it ended that
session on EVERY release after the opening one — so the menu was up for a frame and then gone. The trace, from one
click:

```
DIAG bar: type 1 win 2 at (44,12) -> item 0, current 0    the press that opened it
DIAG bar: type 6 ...            -> item 0, current 0    its drag
DIAG bar: type 2 ...            -> item 0, current 0    its release (consumed)
DIAG bar: type 5 ...            -> item 0, current 0    a move
DIAG bar: type 1 ...            -> item 0, current 0    a second press
DIAG bar: type 2 ...            -> item 0, current 0    ENDING the session here
```

The rule — "a release with no menu under it ends the session" — was written for a menu that OWNS its tracking loop,
where the next thing the loop sees after the press is that press's release. A BAR's loop does not own the events: it
drains every window's queue, so it sees the DOWN, the DRAG and the UP of the opening gesture and then whatever the
compositor sends next. On the Mac a RELEASE is inert; what dismisses a bar's menu is a PRESS somewhere else, and
what moves it to another title is a MOVE.

**FIX:** a release is skipped; a move, a drag, or a press over another title moves the session; a press that hits no
title ends it. The `APPKIT_MENU_DIAG` line also prints the point and the item it hit now, because "the session
ended" says nothing about why — that line is what made this findable.

## 9. The toolbar is written from the SDK header, not imported

**`NSToolbar`, `NSToolbarItem` and `NSUserInterfaceValidation` are this repository's own code**, written against the
classes' declarations in the MacOSX10.6 SDK rather than copied out of the Fiwix tree (which has no toolbar). They
follow the same era surface the imported classes do: the 10.6 selector set, the era's enum values, manual
retain/release, and the tree's `-cg_` seam where a private door has to cross a file.

Two decisions are this tier's rather than the SDK's, and both are recorded where they live:

- **the customization palette is a named refusal**, because it is a panel plus a drag-and-drop session and neither
  exists here; the toolbar itself, its items, validation, selection, display/size modes and the autosaved
  configuration dictionary are implemented;
- **the configuration dictionary's keys are ours** (`NSToolbarItemIdentifiers` and the five beside it), because
  Apple documents the dictionary's existence and keeps its keys private. A dictionary this class writes, it reads.

The window's side — the band's height in `-contentRectForFrameRect:`, the toolbar view as a subview at the content's
top edge, and the chrome pill's `-toggleToolbarShown:` — is likewise this repository's, and `tests/toolbar.m` holds
the geometry, the ink, the click and the configuration round trip.

## 10. The table view is written from the SDK headers, not imported

**`NSTableView`, `NSTableColumn`, `NSTableHeaderView`, `NSTableHeaderCell` and `NSOutlineView` are this repository's
own code**, written
against the declarations in the MacOSX10.6 SDK rather than copied from the Fiwix tree (which has no table). They follow
the era's cell-based shape: a column owns one data cell that each row lends, the data source supplies the value, and
the table supplies the geometry and the selection.

Two pieces are this tier's rather than the SDK's, and both are recorded where they live:

- **the header is installed through a private `NSScrollView` seam** (`-cg_setHeaderView:` in
  `NSScrollView_internal.h`). Apple's 10.6 scroll view keeps a private header clip view; this tier keeps the header as
  a plain subview in the top strip, which is the same relationship with one less object. The scroll view's public
  surface is unchanged.
- **the table class is FLIPPED**, as Apple's is, and the enclosing clip view already was. That is why the row geometry
  needs no second coordinate system.

The first slice is cell-based and deliberately does not do editing, drag and drop, type-select, variable row heights,
column reordering or autosave; `NSTableView.h` names the omissions. `NSOutlineView` is the same table with a
flattened tree, an identity-based expanded set and the disclosure triangle; `tests/table_view.m` and
`tests/outline_view.m` hold the geometry, the header gesture, the tree and the ink.

## 11. The split view is written from the SDK header, not imported

**`NSSplitView` is this repository's own code**, written against the class and delegate declarations in the
MacOSX10.6 SDK rather than copied from the Fiwix tree (which has no split view). It follows the era surface: the
three divider styles, `vertical`, `dividerStyle`, `autosaveName`, `adjustSubviews`, `isSubviewCollapsed:`, the
divider index doors, the deprecated pane-splitter pair, and every optional delegate method in the 10.6 header.

Four decisions are this tier's rather than the SDK's, and each is recorded where it lives:

- **the view is FLIPPED and a divider position is its LEADING edge.** The old documentation says a divider's
  rectangle is in flipped coordinates, but Apple's headers do not say whether `-setPosition:` names the leading
  edge, the centre or the trailing edge. This implementation names the leading edge: the pane before divider 0 is
  exactly the proposed number of points wide (or tall), which is the reading a caller writing a sidebar expects.
- **the thicknesses and the pane splitter's grip are ours.** Apple publishes the three style names and says only
  that the default thickness depends on the platform. This tree draws a six-point thick bar, a one-point thin
  hairline, and an 18-point pane splitter: a `windowBackgroundColor` gutter with THREE HOLLOW RINGS down its centre,
  `#BCBCBC` (`controlDarkShadowColor`), two-point radii eight points apart — the SAME GRIP `NSScrollerCell` draws,
  and the same border grey the rest of the tier uses. The pane splitter also rounds each non-final pane to a whole
  point, so its one-point pane borders land on the pixel grid as `#BCBCBC` rather than antialiasing into a lighter
  grey; the two ordinary styles keep the exact fractional arithmetic because a filled bar has no border to blur.
  Those ordinary styles are one filled rectangle; `dividerColor` is `controlDarkShadowColor` for all three. A
  subclass overrides `-dividerThickness`, `-dividerColor` or `-drawDividerInRect:` for anything else.
- **autosave uses this tier's dictionary.** `autosaveName` is the contract; the value under it is a dictionary of
  pane fractions and collapsed indexes (`fractions`, `collapsed`) under an `AgoraSplitView <name>` defaults key.
  Apple keeps its own format private, so there is nothing compatible to write.
- **the drag's tracking loop belongs to the running application.** A press takes `-nextEventMatchingMask:` until
  the release, so a drag survives the pointer leaving the view. When the application is not running there is no
  event source; `-mouseDragged:` and `-mouseUp:` then do the same work one event at a time, which is how
  `tests/split_view.m` drives it.

The collapse rule is Apple's documented half-minimum rule: a pane with a delegate-declared minimum collapses when a
drag has passed halfway between that minimum and zero. A double-click asks the delegate's
`shouldCollapse` question and toggles the pane. The later `NSSplitViewController` (10.10) and the holding-priority
doors (10.8) are absent because they are later than the vintage this tree pins.

## 12. A cell's text intersects the caller's clip; it does not replace it

**MEASURED in the split view demonstration:** a table in a narrow pane drew its size column's TEXT past the pane and
over the window beside it, while the row backgrounds stopped correctly at the edge. The cause was not the split view.
`NSTextFieldCell -drawInteriorWithFrame:inView:`, its placeholder path, and `NSPopUpButtonCell`'s title each did:

    [[NSBezierPath bezierPathWithRect:cellRect] setClip];

`-setClip` REPLACES the current clip. A cell is drawn inside a clip view, a table and a split view, and replacing their
clip with the cell's own rectangle threw all three away — so a column wider than its table let its words escape to the
window's edge. The row backgrounds were unaffected because they never set a clip of their own.

**FIX:** the three call sites use `-addClip`, which INTERSECTS the cell's rectangle with the clip the caller already
established. The visual result inside a cell is identical; the difference is that the enclosing view's edge now holds.
`tests/split_view.m` §17 renders a table whose column is 250 points wide inside a 100-point pane and asserts that no
dark text pixel reaches the blank pane beside it. It fails with `-setClip` and passes with `-addClip`, which is what
makes it a regression test rather than a description.

## 13. A click activates, raises and keys; a lone window is the one the application speaks through

Three window-management defects were measured together, because one click exposed all three.

**1. A CLICK DID NOT ACTIVATE, RAISE OR KEY.** `NSApplication -sendEvent:` wrote the two application ivars on a
mouse-down and stopped:

    _keyWindow = w;
    _mainWindow = w;

so `-isActive` stayed whatever it was, the window was never ordered front, and `-isKeyWindow`/`-isMainWindow` stayed
NO because the window's own flags were never set. The click path now calls the public doors: `-activate`,
`-orderFront:`, `-makeKeyWindow` and `-makeMainWindow`. `-orderFront:` also sends the server's `raise` now, and
`-orderBack:` sends the new `AGWindowLower` seam (`lower`), instead of both of them raising.

**2. THE APPLICATION'S KEY/MAIN ANSWERS COULD DISAGREE WITH THE WINDOW'S.** `-keyWindow`/`-mainWindow` were only
written by the click path and by window registration; `-makeKeyWindow`/`-makeMainWindow` changed the window's own
flags and posted the notifications but never told the application. `NSWindow -becomeKeyWindow`, `-resignKeyWindow`,
`-becomeMainWindow` and `-resignMainWindow` now call private `NSApplication` doors, so the two answers move together
whichever door caused the change.

**3. THE CHROME KEPT THE OLD INK UNTIL THE POINTER MOVED.** The stoplights draw their active/inactive art from
`-isKeyWindow`, but a key-state change did not mark the window stale. The bar repainted only when the pointer's
next motion happened to change the hover, which is the reported "the lights change only when the mouse moves over
them". Both key and main transitions now call `-setNeedsDisplay:YES`; `tests/chrome_theme.m` asserts the flag after
`-makeKeyWindow` and after `-resignKeyWindow`.

**AND AN ACTIVE APPLICATION ALWAYS HAS A KEY WINDOW.** `-cg_addWindow:` recorded `_keyWindow` when it was nil and
left the window's own key flag NO, so a single-window application launched with its chrome inactive until somebody
clicked it. `-cg_ensureKeyAndMainWindow` now runs from activation, window addition and window removal: it keeps the
remembered window when it can still take the state, otherwise picks the first visible window that can, and skips
windows that refuse (the desktop, borderless panels). With one usable window there is no choice to make — that
window is key and main — which is the measured rule `tests/appkit_activation.m` now holds with a titled window.

Apple's activation notifications are transitions, not counts: `-activateIgnoringOtherApps:` and `-deactivate` now
announce only when `_active` actually changes, so the compositor's keyboard-enter and a click in the same pass do not
make a delegate act twice. `tests/appkit_events.m` deactivates, resigns key/main, clicks, and asserts all three
states; it fails with the old direct-ivar assignment.

## 14. The segmented control and the toolbar group are written from the SDK headers

**`NSSegmentedControl`, `NSSegmentedCell` and `NSToolbarItemGroup` are this repository's own code**, written against
the MacOSX10.6 SDK declarations rather than imported. The segmented pair follows the era's surface exactly: the seven
segment styles, the three tracking modes, per-segment width/image/scaling/label/menu/tool-tip/tag/enabled/selected
doors, the cell's `-drawSegment:inFrame:withView:` content hook and `-interiorBackgroundStyleForSegment:`.

Three decisions are this tier's:

- **the cell owns one private record per segment.** A segment is not a view; its label, picture, scaling rule, width,
  tag, enabled flag, selected flag, menu and tool tip live in an `AGSegmentItem` and are released together. The
  geometry is derived from those records: zero width autosizes, surplus width goes to the auto-sized segments, and a
  frame narrower than the natural row scales it to fit.
- **the drawing is split into bezel and content.** The track, selected/pressed plates and separators are painted by
  `-drawWithFrame:inView:`; `-drawSegment:inFrame:withView:` paints one segment's content. The plate uses
  `selectedControlColor`, the track `controlColor`, the separators and border `controlDarkShadowColor`, and the
  selected label `selectedControlTextColor`. A segment menu and tool tip are STORED and read back, but the pop-up and
  the window tool tip are not yet wired; `NSSegmentedControl.h` names that omission.
- **the tracking is committed in `-stopTracking:`.** `SelectOne` moves the selection, `SelectAny` toggles the segment
  and leaves its neighbours, and `Momentary` exposes the pressed segment to the action while drawing it only for the
  duration of the press. `NSControl`'s existing loop does the event pumping; the cell only answers its three hooks.

**THE TOOLBAR GROUP IS ONE ITEM WITH SEVERAL FACES.** `NSToolbarItemGroup` stores its subitems, refuses a non-item or
a nested group, and marks the toolbar stale when the list changes. `NSToolbar` flattens a group WITHOUT a custom view
into its subitems for measurement, drawing and hit testing, while keeping a parallel owner list so `-items` and
`-visibleItems` still answer the GROUP and its members are laid out adjacent. A group WITH a custom view is one item
wearing that view. The 10.6 class has only `subitems`; the later selection-mode/selected-index doors are not part of
this vintage. The parent's label and target/action do not override a standard subitem's — the members carry their own,
and `NSToolbarItemGroup.h` states that gap rather than leaving it to be discovered.

`tests/segmented_control.m` measures the segment geometry (fixed, auto and scaled), all three tracking modes, the
per-segment storage, the action seeing the committed selection and the track/plate/separator/label ink.
`tests/toolbar.m` inserts a group of two custom-view subitems, checks that the group is the unit `-items` and
`-visibleItems` report, that both subitem views are adopted side by side, and that removing the group takes them out.

## 15. The path control is written from the SDK headers, not imported

**`NSPathControl`, `NSPathCell` and `NSPathComponentCell` are this repository's own code**, written against the
MacOSX10.6 SDK declarations. The control is a forwarder; the path cell owns the URL, the component array, the style,
the background, the placeholder and the clicked component; a component cell is an `NSTextFieldCell` with a URL and the
inherited picture.

Four decisions are this tier's:

- **the URL is decomposed into one component per path element.** A file URL's `/System/Library` becomes `/`, `System`,
  `Library`, each with its own prefix URL; a non-file URL is one component whose title is `-absoluteString`. The
  component class is `+pathComponentCellClass`, so a subclass can supply its own.
- **the middle truncates; the ends stay.** The first component and the last are always visible, an ellipsis takes the
  hidden middle's place, and middle components are kept from the last one backwards for as long as they fit. A
  component that is not visible answers `NSZeroRect` from `-rectOfPathComponentCell:…`, which is Apple's documented
  answer for "not currently displayed".
- **the three styles are three faces.** Standard fills a light-blue bar and uses small arrows; NavigationBar forces
  the small control size, fills the control face and draws chevrons; PopUp shows only the last component and raises a
  menu of the whole path. The component cells draw only their interiors, so the path cell owns every background and
  separator.
- **the editable/drop half is ABSENT and named.** The drag SESSION now exists (`NSDragging.h`, section 17), so what
  this class has not got is no longer the machinery: it does not register as a destination and has no editable text
  or drop target, and there is no `NSOpenPanel` for a Browse action. The drag-source/destination delegate methods are
  therefore declared and never called, which is a decision about this class rather than a missing session. File icons
  are not filled in either, because this tier has no `NSWorkspace` icon door. `NSPathControl.h` and `NSPathCell.h` say
  both things where a reader meets them.

The PopUp style's menu is built from the component cells and selecting a row sets `-clickedPathComponentCell` before
the action is sent; the delegate's `willPopUpMenu:` hook is forwarded from the cell to the control's delegate.
`tests/path_control.m` holds the decomposition, prefix URLs, geometry, middle truncation, three styles, single and
double actions, manual cells and the bar's ink.

## 16. The table's second half: heights, type-select, reordering, autosave, editing and a local drag

**THE CELL-BASED TABLE'S MISSING HALF IS IMPLEMENTED, AND IT IS STILL CELL-BASED.** No `NSTableCellView` or
`-viewForTableColumn:row:` was introduced; the era's cells, data source and delegate are the surface, and the six
features below are the era's doors.

- **VARIABLE ROW HEIGHTS** are cached as a top and an extent per row, rebuilt from
  `-tableView:heightOfRow:` (or `_rowHeight` when the delegate does not answer). `-rectOfRow:`, `-rowAtPoint:`,
  `-rowsInRect:` and `-tile` read the cache; `-reloadData`, `-noteNumberOfRowsChanged` and
  `-noteHeightOfRowsWithIndexesChanged:` invalidate it. A row's rect no longer assumes a constant pitch, and the
  row hit test binary-searches the cached tops.
- **TYPE-SELECT** accumulates a prefix for one second, searches the prepared cells' `-stringValue` or the delegate's
  `-tableView:typeSelectStringForTableColumn:row:`, starts at the selected row and wraps. A key that does not extend
  the prefix restarts it with that key, so `c`, `h`, `d` can select "Charlie" and then "Delta" without waiting out the
  timeout. `-allowsTypeSelect` turns it off.
- **COLUMN REORDERING** is the header's second gesture. A press on the body of a header asks
  `-tableView:shouldReorderColumn:toColumn:` with -1; a drag past four points moves the column through
  `-moveColumn:toColumn:`, asks the delegate again for the target, and `-tableView:didDragTableColumn:` is sent once.
  `-draggedColumn`/`-draggedDistance` report the gesture. The table's move door posts the move notification, sends
  the delegate's column-did-move hook and saves the autosave.
- **AUTOSAVE** stores, under `AgoraTableView <name>`, the column order, widths, hidden state and sort descriptors.
  It loads when the name and `-autosaveTableColumns` are both set, and saves on a move, a user resize and a sort
  descriptor change. The dictionary's keys are this tier's; Apple's format is private.
- **EDITING** uses `NSWindow -fieldEditor:forObject:`. `-editColumn:row:withEvent:select:` prepares the data cell,
  checks `-shouldFocusCell:atColumn:row:`, starts the cell's session with the table as the caller delegate, and the
  table's `-textDidEndEditing:` writes the cell's object value through the data source's
  `-tableView:setObjectValue:forTableColumn:row:`. `-editedRow`/`-editedColumn` answer -1 outside the session. A
  refused first responder clears the table's edit state, and a double-click on an editable cell with no
  double-action starts the session.
- **A ROW DRAG** writes the data source's pasteboard, snapshots the dragged rows into an image and begins the tier's
  DRAG SESSION (`NSDragging.h`, section 17). The table is both source and destination: its
  `-draggingEntered:`/`-draggingUpdated:` propose a row and call
  `-tableView:validateDrop:proposedRow:proposedDropOperation:`, and `-performDragOperation:` calls
  `-tableView:acceptDrop:row:dropOperation:`; the insertion line is still two points and follows the session's
  pointer. **THE CROSS-PROCESS HALF REMAINS ABSENT** — another application's destination and its pasteboard need the
  window server's transport — and `NSTableView.h` says so at the data-source protocol.

`tests/table_advanced.m` holds all six: the variable-height geometry and re-tile, the prefix/wrap/restart type-select,
the header reorder and its delegate, an autosave round trip through a second table, a field-editor session that writes
back to the data source, and a local drag that reaches all three data-source methods.

## 17. The drag session is this repository's own code

**`NSDragging.h` AND `NSDragging.m` ARE WRITTEN HERE, against the 10.6 `NSDraggingInfo`/`NSDraggingSource` protocol
declarations and the 10.7 `NSDraggingSession`/`NSDraggingItem` pair the shell plan names.** The four decisions below
are the ones a reader needs before changing it:

- **THE APPLICATION OWNS THE LOOP, NOT THE WINDOW SERVER.** A session captures the pointer on the source view's
  window with the seam's real grab, and `NSWindow -sendEvent:` routes the motions and the release to the active
  session before any view sees them. The destination is found by SCREEN point — the compositor's absolute pointer
  when the event carries it, the window's frame plus the event's own point otherwise — through
  `+[NSWindow windowNumberAtPoint:belowWindowWithWindowNumber:]` and the content view's `-hitTest:`, then up the
  superview chain to the first registered view. That is what lets a drag cross windows; a same-window drag is the
  same path with the source's window as the answer.
- **THE IMAGE IS A BORDERLESS WINDOW.** A client cannot draw over another window's surface, so the floating image is
  `NSBorderlessWindowMask`, `NSFloatingWindowLevel`, non-opaque with a clear ground, and
  `-setIgnoresMouseEvents:YES` — the last so the destination search cannot find the image instead of the view under
  it. The image is composed once at the beginning from the union of the items' frames; a motion moves the window by
  the pointer offset taken then.
- **THE PASTEBOARD IS THE CALLER'S, AND THE LEGACY DOOR IS ASYNCHRONOUS.** Apple derives a pasteboard from the
  items' pasteboard writers; this tree has no `NSPasteboardItem` or `NSPasteboardWriting`, so a writer is recorded
  and not consulted and the session uses `NSDragPboard` (or the pasteboard the 10.6 door was handed). The 10.6 door
  returns before the drag ends, and the operation reaches the source's ended callback rather than its return value.
  `-wantsPeriodicDraggingUpdates` is asked and recorded, but no timer sends updates: every motion already does.
- **THE INFO OBJECT IS NOT THE SESSION.** Apple's session answers `-draggingLocation` in SCREEN coordinates and
  `NSDraggingInfo` answers it in the DESTINATION window's; one selector cannot be both. A private object conforming
  to the protocol reads the session's live state, so a destination sees the pointer move without a second copy of it.

`tests/drag_session.m` measures the two-window crossing, the info's answers, the mask/modifier negotiation, the
callback sequence (entered/updated/prepared/performed/concluded/ended, and exited on a leave), Escape, the parent
climb, the type filter, a two-item union and the legacy door. `tests/drag_seam.m` measures the image window against
Agora's headless server.

## 18. The browser is table-backed, and the selection door's use-after-free

**`NSBrowser.h`, `NSBrowser.m`, `NSBrowserCell.h` AND `NSBrowserCell.m` ARE THIS REPOSITORY'S OWN CODE**, written
against the 10.6 declarations. Four decisions are the ones to know:

- **A COLUMN IS AN `NSTableView`.** The tree has no `NSMatrix`, so the browser owns one horizontal `NSScrollView`
  and a document view of side-by-side tables; the browser is their data source and delegate and maps a sender back
  to its column by identity. The public delegate surface is the cell-based 10.6 one; the old
  `-browser:createRowsForColumn:inMatrix:` form is absent because the class it names is absent.
- **A SELECTION ASKS FOR THE COLUMN TO ITS RIGHT.** `-tableViewSelectionDidChange:` records the row, truncates the
  columns after it, asks the delegate for `column + 1`, and builds or removes that column. A leaf returns zero rows
  and leaves the browser as it was. The browser's own `-selectRow:inColumn:` goes through the same table door.
- **THE PATH IS THE SELECTED CELLS' STRINGS.** `-path`, `-setPath:` and `-selectedPath` use the cells' `-stringValue`
  and `-pathSeparator`, so a delegate that fills cells through `willDisplayCell` automatically has a path.
- **THE CLIP VIEW CENTRES A SMALL DOCUMENT, SO THE DOCUMENT IS AT LEAST AS WIDE AS THE BROWSER.** With one column
  that would put the column in the middle of the browser; the document width is widened so the first column stays at
  the left edge.

**AND THE TABLE'S SELECTION DOOR HAD A USE-AFTER-FREE.** `NSTableView -selectRowIndexes:…` passed the proposed set to
`-tableView:selectionIndexesForProposedSelection:` and, when the delegate returned **that same set**, released it
before copying it into the table's own set. The copy read freed memory; the selection became empty. MEASURED through
`NSBrowser`, whose delegate returns the proposal unchanged. The table retains the answer across the release now, and
`tests/browser.m` is the regression. The fix is in `NSTableView.m`, not in the browser, because any table delegate may
answer with the proposal.

## 19. The progress indicator is this repository's own code

**`NSProgressIndicator.h`/`.m` ARE WRITTEN FROM THE 10.6 DECLARATIONS.** The determinate bar's track, hairline and
accent fill are drawn in `-drawRect:`; the value is clamped in `-setDoubleValue:` and the range setters keep the two
ends ordered. The spinning style is a ring plus a smaller ring while `-isAnimating`; there is no animation timer in
this tier, which is stated at the door rather than hidden behind a NO. `-isIndeterminate` records the mode and omits
the fill.

`tests/progress_indicator.m` measures the default range, both clamps, `-incrementBy:`, the spinner state, and a
bitmap whose filled half and empty half must be different ink. The file-operation progress window consumes this
class; the manager itself is Workspace's.

## 20. The panel and the alert are this repository's own code

**`NSPanel.h`/`.m` AND `NSAlert.h`/`.m` ARE WRITTEN FROM THE 10.6 DECLARATIONS.** The imported AppKit had no panel
class, so four `NSWindow` flags a panel is built from (`-isFloatingPanel`, `-worksWhenModal`, `-setModalPanel:`,
`hidesOnDeactivate`) were state with no owner, and `NSWindow -canBecomeMainWindow` shipped a paragraph explaining that
Apple's "is not an NSPanel object" clause could not be implemented because the class did not exist. That paragraph is
now a subclass override, which is the route Apple documents.

- **THE PANEL CHANGES THREE ANSWERS AND NOTHING ELSE.** `hidesOnDeactivate` is YES in its initialiser;
  `-canBecomeMainWindow` is always NO; and `-becomesKeyOnlyIfNeeded` is a real rule rather than a stored BOOL. The rule
  crosses a file boundary, so it travels on a private `NSWindow -cg_shouldBecomeKeyForClickAtPoint:` door answered YES
  by a window and overridden by a panel: the panel hit-tests its content and asks each view on the way up. `NSControl`
  supplies the per-view answer as its own `-acceptsFirstResponder` — YES for an editable field, NO for a button or a
  label — which is the half `NSView -needsPanelToBecomeKey` had been stubbing with "there is no panel here to need".
- **THE CLICK-TO-KEY CALL SITE IS `NSApplication -sendEvent:`**, the one place this tier turns a press into key/main
  state. A panel that did not ask for the restriction behaves like a window, so nothing about an ordinary window's
  click path changed.
- **AN ALERT IS A PANEL AT `NSModalPanelWindowLevel` WHOSE CONTENT IS CONTROLS.** It overrides the panel's
  `hidesOnDeactivate` back to NO, because a modal question that hid with the application would leave the loop running
  with nothing on the screen. The message and informative text are `NSTextField`s — one FIELD PER WRAPPED LINE, because
  this tier's field is one line tall, so `-layout` measures the wrap and makes as many fields as it needs — the icon is
  a private view that draws an `NSImage`, the buttons are
  `NSButton`s laid out right-to-left with the first rightmost, and an accessory view spans the width above the row.
- **THE ANSWER IS THE BUTTON'S INDEX.** A click turns its index into Apple's code (1000/1001/1002, then `1000 + index`)
  and then ends whichever session is running: `-stopModalWithCode:` for `-runModal`, `-endSheet:returnCode:` for the
  sheet form, and nothing for an alert that was only built. Return and Escape are handled by the alert's private panel
  subclass, because this tier's pump has no key-equivalent pass for windows; the first button also carries the
  key equivalents as state, for a caller that provides one.
- **`-runModal` ORDERS THE PANEL OUT; THE SHEET FORM DOES NOT.** That is Apple's split: a sheet's dismissal belongs to
  the caller's did-end method, which is the contract `NSApplication.h` already quotes for `-endSheet:returnCode:`.
- **THE THREE RETURN CONSTANTS MOVED TO `NSAlert.h`**, where Apple's own header declares them. They had lived in
  `NSApplication.h` only because the alert class did not exist; no consumer in this tree used the old location.

**AND THE FIRST OUTSIDE CLIENT OF THE MODAL SESSION DOORS FOUND AN ABI WART, WHICH IS FIXED.** `NSApplication.h`
declares `NSModalSession` as a pointer to an INCOMPLETE `struct _NSModalSession`, but `NSApplication.m` defined that
same tag before the implementation, so the method type encodings included the three fields and the runtime printed
"Calling [NSApplication -beginModalSessionForWindow:] with incorrect signature" for the first caller outside that file
(`tests/panel_alert.m`). The private struct now has its own tag (`struct AGModalSession`) and the public one stays
incomplete, so the encodings match the declaration; the calls are the same calls.

`tests/panel_alert.m` measures the panel's defaults, its click-to-key rule (field YES, button and background NO), the
alert's fields and button order, wrapping into several fields, re-layout after a text change, the accessory's placement
and removal, the three codes through a modal session, Return and Escape through `-sendEvent:`, and the sheet form's
attachment and reply — 55 checks. It does not call `-runModal`: that is an unbounded loop, and the test would hang rather
than fail.

## 21. Auto Layout's required projection needed a convergence loop

**THE SOLVER'S REQUIRED PASS WAS ONE VISIT PER SWEEP, AND TWO COUPLED DEMANDS ARE NOT SATISFIED BY ONE VISIT.** A
leading and a trailing constraint share the view's x and width, so projecting the trailing one moved the x the
leading one had just set. With no optional pull in the same axis the repeated sweeps eventually settled it; with a
control's intrinsic hugging/compression in that axis the pair settled at a compromise. MEASURED, found by Workspace's
file window: a text field pinned to both edges of a 700-point parent landed at x=76 with an intrinsic width of 10, and
the pass printed the unsatisfiable-required warning only when the residual crossed its 1e-3 threshold.

The required rows are now projected **inside each sweep until their own residual is gone**, and the convergence test
is the **net** move across a sweep rather than the sum of every projection. That second half is what keeps a required
step that exactly undoes an optional one from burning the whole sweep budget: an ordinary file window was running 400
sweeps per pass for a fraction of a point. The outer break is now in points (1e-5 for both the required residual and
the net move), which is far finer than the geometry the tier draws. A genuinely contradictory required set still
reaches the refusal, whose threshold is orders of magnitude larger.

`tests/auto_layout.m` case 16 is the regression: a control with an intrinsic size pinned to all four edges must fill
its parent. The fix is what makes `Workspace`'s file window lay out its path bar, split view and status bar with
constraints at all — see `workspace/PROVENANCE.md`.

## 22. The browser's frame set did not re-tile its own scroll view

**`NSBrowser` OVERRODE `-setFrameSize:` AND NOT `-setFrame:`, AND THIS TIER'S `NSView -setFrame:` DOES NOT CALL
`-resizeSubviewsWithOldSize:`.** The browser's whole face is the scroll view it owns, and `-tile` is what gives that
scroll view the browser's bounds. A caller that set the browser's FRAME — which is what a containing view does when it
lays a browser out beside a preview panel — left the scroll view at its old width. MEASURED in Workspace: widening
the file window opened a gap between the last browser column and the preview panel, because the browser had grown and
its scroll view had not.

`-setFrame:` now re-tiles whenever the size changes, which is the same rule `NSScrollView` and `NSSplitView` already
follow. `tests/browser.m` sets a frame and checks the scroll view's width; Workspace's `tests/column_view.m` checks the
same width through `-cg_documentView` after resizing the view beside the preview.

## 23. A browser selection scrolls to the newest column, at the document's end

**`-scrollColumnToVisible:` IS NOT THE ANSWER FOR A COLUMN A SELECTION JUST OPENED.** Its rule is "bring this column
into view", which puts the column's left edge at the clip view's left when it is off to the right — correct for a
column in the middle, wrong for the newest one, which should be against the right edge with the columns it came from
behind it. Workspace's column view made the difference visible: clicking a folder opened its children out of sight.

`NSBrowser -tableViewSelectionDidChange:` now scrolls to the document's end when a selection succeeds. The selected
column is a leaf or a branch, and either way the columns to its right have been truncated or the new one created, so
the selected/newest column IS the last one. Deselecting keeps the old "bring the selected column into view" rule. The
private `-cg_scrollToLastColumn` sets the clip view's origin to `documentWidth - clipWidth` (clamped at zero);
`tests/browser.m` checks that origin after opening a column, and Workspace's `tests/column_view.m` checks the same
through `-cg_documentView`.

## 24. An image rep drew the same bytes mirrored in a flipped view and an unflipped one

**`NSImageRep -drawInRect:` PASSED THE RECT STRAIGHT TO `CGContextDrawImage`, WHICH PAINTS THROUGH THE CURRENT
CTM.** The two coordinate systems AppKit builds are both ordinary here: Workspace's Desktop draws with a y-up
CTM and the file window's flipped `WSIconView` draws with a y-down one. The same image therefore arrived
vertically mirrored in the two. MEASURED with the vendored Frost theme: its folder icons were upright on the
Desktop and upside-down in the file window, and swapping the icon bytes' orientation merely moved the fault to
the other view. The drawn generics had the same split; symmetric document art hid it.

**THE FIX IS THE MIRROR THE Y-UP PATH WAS MISSING.** `-drawInRect:` reads `CGContextGetCTM` and, when the CTM's
`d` is positive (y grows up), translates to the rect's top and scales y by -1 before drawing, then restores the
state. `NSGraphicsContext -isFlipped` is not the test: that flag is the WINDOW's statement and stays NO for
both views, while the CTM is what the view walk actually installs. `tests/image_draw.m` is the regression —
one red-over-blue rep, one y-up and one y-down context, the same ink at the top of both buffers.

## 25. Browser columns got their own scroll views, and their own widths

**THE OUTER SCROLL VIEW WAS THE ONLY ONE, SO A TALL FOLDER MOVED EVERY COLUMN WITH IT.** The old shape was one
horizontal `NSScrollView` whose document was as tall as the tallest column; the user asked for columns that
scroll individually, which is what Finder does. Each column now owns a vertical `NSScrollView` inside the outer
horizontal one, and the table is that scroll view's document. The outer document is exactly the browser's content
height, so it has no vertical travel of its own.

**AND A WIDTH IS PER COLUMN.** `NSBrowser` gained `-widthOfColumn:`/`-setWidth:ofColumn:`; `-columnWidth` is now
the width a NEW column gets and what `-setColumnWidth:` applies to every existing one. `-tile` positions each
column from the running sum, so a width change moves the columns after it rather than changing a shared step.
`-widthOfColumn:` is the column's FRAME width, and the vertical scroller lives inside it: a visible bar narrows
the table rather than widening the column, so `-columnWidth` and the visible column stay the same measure and the
existing "column width reaches the table" check still holds when the bar is hidden.

**THE COLUMN LIST IS A 256-SLOT POOL, AND THE EMPTY SLOTS ARE COLUMNS.** Finder builds its column view with the
maximum number of columns already present and leaves the empty ones visible; that is what preserves a column's
width when navigation steps away from it. `NSBrowser` now builds `AG_BROWSER_COLUMN_POOL` (256) slots when it first
loads. An empty slot keeps its scroll view, table and width, and drawing it as an empty column is what replaces the
old gray document background. **ONLY THE VISIBLE COLUMNS SIZE THE HORIZONTAL DOCUMENT:** `-tile` ends the document at
the last ACTIVE column or the visible width, whichever is farther, and lays out only the active slots plus as many
empty ones as the visible area holds. The 256-slot pool therefore never becomes 256 columns of horizontal travel;
the empty slots past the visible area stay where they were built, outside the document. `-cg_activeColumnCount` is
the seam the tests use for "how many slots have rows".

**THE SEPARATOR IS `NSSplitView`'S PANE-SPLITTER GUTTER, NOT A HAIRLINE OR AN OVERLAY.** The document view owns
an eighteen-point gap between columns and draws it with the same numbers and colours the split view uses: a
`windowBackgroundColor` band, `controlDarkShadowColor` rings, two-point radii eight points apart, three of them down
the middle. That is the grip a person already knows from a split view, and it gives the pointer somewhere to land
without covering either neighbour's content or scrollbar. `NSBrowserDocumentView` gives the gutter a resize cursor
and tracks a user drag when `-columnResizingType` is `NSBrowserUserColumnResizing` (Workspace sets it). The
delegate's `-browser:shouldSizeColumn:forUserResize:toWidth:` may veto the proposal; a double-click asks
`-browser:sizeToFitWidthOfColumn:`.

`tests/browser.m` now checks the 256-slot pool (`-cg_columnCount` and `-cg_activeColumnCount`), that an empty slot
is a visible column, the per-column scrollers, that scrolling one column leaves its neighbour's clip view where it
was, that a width set on one column leaves the others alone, and that a forty-point separator drag widens the left
column by forty. Workspace's `column_view.m` checks the same pool and visibility, and that the view it builds is in
the user-resizing mode.

## 26. Scroll bars step aside when the document fits

**`NSScrollView` HAD NO AUTOHIDE, so a configured bar was ink on the window even when the clip view already showed
the whole document.** The browser columns made it obvious: an empty column and a three-row column each carried a
bar. `-autohidesScrollers` is now the era's opt-in, and the default stays NO — Apple's default, and the one the
existing frame arithmetic was written against.

**VISIBILITY IS A PAIR, BECAUSE ONE BAR MAKES THE OTHER NECESSARY.** A vertical bar takes width that can push a
wide document into needing a horizontal bar, and a horizontal bar takes height that can do the reverse. `-tile`
therefore asks a small fixed-point question — up to three passes over `(showV, showH)` — and lays the content out
with only the shown bars taking room. `-hasVerticalScroller`/`-hasHorizontalScroller` still answer YES for a hidden
bar; the view exists, it is `-isHidden`, and its content space is reclaimed. A document that changes shape announces
it through the clip view, so `-reflectScrolledClipView:` compares the desired pair with the drawn one and re-tiles
once when they differ, guarded against its own final reflect.

**THE BROWSER'S COLUMNS OPT IN, AND A WIDTH IS A FRAME WIDTH.** Each column scroll view sets
`-setAutohidesScrollers:YES`; a short column therefore has no bar, and its table widens into the space the bar
would have used. That is also why `-widthOfColumn:` is the column's FRAME width rather than its content width: a
visible bar narrows the table inside the same column. `tests/scroll_view.m` drives both-fits, horizontal-only and
both-needed, and turns autohide back off; `tests/browser.m` checks a short column hides and a tall one shows.

## 27. A mouse move that had not moved re-walked the whole tracking tree

**THE TRACKING ENGINE RAN ON EVERY POINTER-MOTION EVENT, EVEN WHEN THE POINT WAS THE SAME.** `-cg:walkTrackingInView:`
visits every subview and every tracking area to decide enters, exits and the cursor; the walk itself is correct, but a
repeat of the last position can change none of those answers. MEASURED on Workspace in column view after the browser
grew its 256-column pool: **500 CPU ticks in five seconds** (about one core), with the samples in
`-cg:walkTrackingInView:`, `-convertRect:toView:` and `-visibleRect` — the pointer was over the window and the event
stream repeated its position, so the whole tree was walked again and again.

**THE MOTION PATH NOW ASKS WHETHER THE POINT MOVED.** `-cg_updateTrackingIfMovedToPoint:` returns when the point is
the same as the last one; the motion path uses it, while the callers that need a re-evaluation at a stationary point
— a key/resign, a button changing under the pointer, a mouse exit — still use the full door. The same measurement
after the change: **23 ticks in five seconds** (about 5% of a core), with the cursor still resolved on every motion
before the gate. `tests/tracking_area.m` already pins the engine's enter/exit semantics; this gate only removes a
repeat that could not change them.

## 28. A gutter drag re-laid out the whole browser for every motion

**THE DIVIDER DRAG CALLED `-tile` ON EVERY MOTION EVENT, AND EVERY COLUMN SLOT WAS A SUBVIEW.** The first browser
drag profile showed two multipliers stacked: `-setWidth:ofColumn:` re-ran the browser's full layout (both passes,
every visible column's scroll view and table, the document frame, the cursor rects), and the 256-slot pool kept all
256 scroll views attached to the document view, so every draw, hit test and tracking walk saw the whole pool.
MEASURED: a two-second drag cost **146-217 CPU ticks** (73-108% of a core) for 80 motion events.

**THE DRAG NOW SHOWS A LINE, AND THE LAYOUT HAPPENS ONCE.** A divider drag draws a one-point preview line at the
pointer and nothing else, and **the window draws that line above the view tree** — a split view's own `-drawRect:`
would be covered by its panes, and a browser's by its column scroll views, so the guide is a window overlay in
content coordinates rather than a line in the divider's own view. The pane or column is resized when the button
comes up, with one `-tile` (or `-setWidth:ofColumn:`) for the whole gesture. The slots that are neither active nor inside the visible width are
**removed from the document view** (their state stays in the pool), which leaves a handful of column views instead
of 256 for every walk and draw. The tracking engine is suspended for the length of a drag (`NSWindow_internal.h`'s
two doors), and the hover cursor is no longer resolved mid-drag because the drag owner has already set the cursor it
wants. `NSWindow -displayIfNeeded` also draws the **union of the dirty subview rectangles** into the persistent
surface instead of repainting and clearing the whole window, so the preview line costs a few pixels and the release
costs one layout. The same treatment covers `NSSplitView`'s sidebar gutter and the browser's column gutters; the
idle fix in §27 remains about 23 ticks per five seconds.

`tests/browser.m` checks that an offscreen empty slot is not attached to the document while the visible one is, and
the existing drag check still widens exactly the left column by forty points after the release.

## 29. The search field's ornaments are cells, and its text rect is the one rect

**`NSSearchField` AND `NSSearchFieldCell` ARE WRITTEN FROM THE 10.6 DECLARATIONS.** The SDK publishes the two ornament
cells as `NSButtonCell`s, the three rectangles, the recents list and its autosave name, the template menu with four
placeholder tags, and the two sending flags. That is the surface here; the control adds only the recents forwards and a
press that hit-tests the ornaments before it opens a field session.

- **THE DEFAULT ORNAMENTS ARE DRAWN GLYPHS, NOT IMAGES.** The magnifier is a ring and a handle, the clear button a
  disc with a cross, both at the toolbar's sixteen-point measure. A caller that sets an image on either cell gets the
  ordinary button drawing instead, so the drawn mark is a default rather than a closed door. The magnifier's handle
  reads the CTM's sign, which is the same question `NSTextFieldCell` asks before it places a baseline: "down" is
  negative y in a window and positive y in a flipped bitmap.
- **THE TEXT RECT IS THE SINGLE LAYOUT ANSWER.** `-drawingRectForBounds:` returns `-searchTextRectForBounds:`, and
  the drawn string, the placeholder and the editor all read it. The editor is therefore placed between the ornaments
  by the same arithmetic that insets the text, which the probe checks by comparing the editor's frame with that rect.
- **THE CLEAR SLOT IS RESERVED WHETHER OR NOT THE BUTTON IS DRAWN.** The button appears with the first character, and
  a layout that gave it room only then would move the editor — under the caret — on that keystroke. Its visibility
  follows the LIVE text (the editor's while a session runs), so it appears and disappears as a person types rather
  than at the end of the edit.
- **A PROGRAMMATIC WRITE IS NOT A KEYSTROKE.** Writing a value through `-setStringValue:` tells a live editor, and
  the editor's change notification is the same one a key produces. A flag around the write keeps the clear button and
  a chosen recent from sending twice; the door that wrote the value sends once, deliberately.
- **THE RECENTS ADOPT THE LIST THEY ARE GIVEN, IN EITHER ORDER.** Setting the autosave name loads what is stored under
  it and also saves the list the cell already has, so "name first" and "searches first" mean the same thing. A repeat
  moves to the front, the limit clamps at 0...254 with -1 as ten, and the built menu is a copy of the template with the
  tagged placeholders replaced — the template itself is never mutated. **AND A TERM IS REMEMBERED ONLY WHEN A TEMPLATE
  IS SET**, which is the SDK's "if cleared, then we don't track recents": without one the magnifier is a plain
  "search now" and Return commits the value without adding it to a list no menu could show.
- **AND THE PROBE FOUND THAT SELECTOR IDENTITY IS NOT POINTER EQUALITY.** The test compared a cell's action with `==`
  against `@selector(search:)` and it failed while `sel_getName` answered `search:` for both: this runtime can hand out
  distinct selector pointers for one name across separately compiled images. `sel_isEqual` is the comparison, and the
  test uses it. `-sendAction:to:` resolves by name and was never affected.

`tests/search_field.m` measures the defaults, the three rectangles and the measured width that pays for both slots,
the glyph ink and the hidden clear button, the press that misses the text, the editor's rect, the delayed/immediate/
whole-string sending rules with the timer fired by hand, a programmatic write that adds no send, the bounded deduped
recents, both autosave orders, the template menu's tagged placement, choosing a recent, and the ornament cells'
target/action pairing — **74 checks**.

## 30. The toolbar band between its controls is the window's drag handle

**A PRESS ON THE BAND THAT MISSED EVERY CONTROL DID NOTHING.** It is outside the title bar's rectangle
(`fn_pointInChrome`), outside the content's, and the toolbar's own view answers "no item" for it — so the widest
part of a window with a toolbar was a strip of dead pixels, and in the demo's controls window that is the flexible
space, most of the band's width.

`NSWindow` now takes hold of the window there, by the same path, the same grab arithmetic and the same deferred
move the title bar already used: `fn_pointInToolbarBand` answers whether the point is in the band, and asks
`NSToolbar -cg_pointIsOverControl:` before saying yes. The toolbar answers with **`fn_item_acts`, the predicate its
own click path uses** — so a separator, a space and a flexible space are the window's (they are drawn, and they do
nothing), an item with a custom view is not, and a control cannot be inert for a click and a handle for a drag at
the same time. A borderless window keeps no handle: it is the same rule the title bar follows. `-isMovable` still
decides, and the resize bands are still asked first.

The seam is `NSToolbar_internal.h`'s fourth door, because the item rectangles live in the private `NSToolbarView`
and re-deriving them in `NSWindow.m` is how the two would drift.

`tests/toolbar.m` adds four checks: a drag between the controls moves the window by the pointer's own delta, a press
on a control does not move it, the run of non-control points is wider than any gap between items (which is the
flexible space being the handle rather than an item), and an immovable window does not move at all.

## Keeping in sync

The Fiwix AppKit is the origin and this repository has now diverged from it in the seam. A fix made there
does not arrive here automatically: it has to be ported by hand, and a fix made here does not travel back.
That is the cost of the seam decision, and it is stated rather than discovered.
