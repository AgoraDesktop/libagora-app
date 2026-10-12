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

## Keeping in sync

The Fiwix AppKit is the origin and this repository has now diverged from it in the seam. A fix made there
does not arrive here automatically: it has to be ported by hand, and a fix made here does not travel back.
That is the cost of the seam decision, and it is stated rather than discovered.
