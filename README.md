# libagora-app

**The Application Kit for Agora** — the Cocoa-compatible window, view, control and menu classes
(`NSWindow`, `NSView`, `NSApplication`, `NSMenu` and the rest).

Agora is an installable desktop environment for Linux and BSD; see the project README in the parent
directory (`../README.md`). `libagora-app` is the top of its stack: above it there are only applications.

## Status

**The AppKit is imported and its windows run on Agora's window server. The X11 seam is gone.** Above the
window and view classes there is now a cell and control layer (buttons, switches and sliders), a tracking-area
engine, one line of editable text with the standard key bindings, a title bar the client DRAWS itself, and the
menu subsystem — validation, a selection chip, and a pointer grab that lets a popup be dismissed by clicking
away.

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
  text_field_cell.m             a FIELD's cell: its string, its face, and one edit session end to end
  text_field_control.m          and the VIEW above it: a press that opens a session, and what commits it
  clip_view.m                   the INSIDE of a scroll view: the arithmetic, and the wire that re-runs it
  scroller.m                    and its BAR: a fraction into a knob, a point into a part, a drag back into a value
  scroll_view.m                 and the FRAME that joins them: the tiling, the loop, and -enclosingScrollView
  view_offset.m                 and the ONE THING a scroll moves: a non-zero `bounds` origin, drawn and converted
  window_chrome.m               the DRAWN chrome, offscreen: the symbols, the centred title and the pill
  menu_validation.m             validation and state, which the view tests do not reach
  appkit_activation.m           only the ACTIVE application's menu bar shows
  appkit_controls_draw.m        a window full of controls AND A SCROLL PANEL, for a person to look at and play with
  chrome_theme.m                the THEME: an XFWM `.xpm` set becomes the chrome's buttons, 1:1
  chrome_buttons.m              and what a chrome button DOES: a click through the seam, and what happened
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
- **And the field, which is a cell under a view** (`ctest`, offscreen): `NSTextFieldCell` owns the string, the face
  and the three doors of an edit; `NSTextField` is the control above it, and it contributes the two things a cell
  cannot — a PRESS that opens a session with the WINDOW's field editor, and `-selectText:` for the same session with
  no pointer. The editor is put in the FIELD at the field's own text rect and made the window's FIRST RESPONDER, so
  the keyboard goes to the editor rather than to the field, and a committed session reaches a caller's action through
  `NSControl -textDidEndEditing:`. MEASURED: Return COMMITS the typed value into the field and sends the action ONCE;
  Escape DISCARDS it and sends nothing; `-abortEditing` is that same discard through a door (and answers NO when no
  session is running); a press on a field that is not editable opens NOTHING; and focusing the field (`-makeFirstResponder:`)
  opens its session, leaving the EDITOR as the responder. `NSComboBox` now derives from `NSTextField` — Apple's own
  hierarchy, which its header had named as the row this control would close — so its press is the base's press and the
  chip is the only thing it adds.
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
- **`ctest`: 30 of 30 passed** (the keyboard and the seam, the AppKit and its input path, the controls and their
  metrics, the field control and its cell, what a drag costs, the resize by edge, the tracking engine, the text path,
  the clip view and the scroller and the scroll view and the drawn offset, the chrome and what its buttons do, the
  chrome theme, the menus and activation).
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
sliding off the X is how a hand changes its mind. THE PILL PERFORMS NOTHING, because it is the toolbar toggle and
`NSToolbar` does not exist here — `-toggleToolbarShown:` is the door that refuses by name. And THE MINUS MARKS THE
STATE AND ANNOUNCES IT RATHER THAN TAKING THE WINDOW OFF THE SCREEN: there is no Dock to put a miniaturized window
in and no iconify in the protocol, which `-miniaturize:` states where it stands. `tests/chrome_buttons.m` is what
holds all of that to account — it presses the buttons through the seam and asks what HAPPENED, which is the half
no test about pixels can see.

### Still absent, and why

The sheets, the drawer, the frame-autosave strings, the script-command doors, the cursor-rect invalidation and
the child-window list all need subsystems this stage has not reached; what the window's close, minimise and zoom
buttons DO is now this tier's — each goes through the `-perform…` door its menu item sends — but the MINIMISE is
still only a state the window marks and announces, because there is no Dock to put a miniaturized window in and no
iconify in the protocol (Kestrel is parked). The chrome's toolbar pill is drawn and performs nothing, because
there is no toolbar for it to toggle; the three symbols beside it ARE buttons now, and `tests/chrome_buttons.m`
presses them. The input-method half of the text system is
still absent (`-interpretKeyEvents:` does the direct mapping and says so), and the multi-line text view, the
word-granularity movement commands and the field editor are named rather than guessed. Each absence is stated
rather than stubbed, and the refusals name themselves.

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
