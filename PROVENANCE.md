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
translation — and `tests/`. They are why this component can build at all: the AppKit it came from is linked
against an X server and this one is not.

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

## Keeping in sync

The Fiwix AppKit is the origin and this repository has now diverged from it in the seam. A fix made there
does not arrive here automatically: it has to be ported by hand, and a fix made here does not travel back.
That is the cost of the seam decision, and it is stated rather than discovered.
