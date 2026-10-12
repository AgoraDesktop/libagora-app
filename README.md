# libagora-app

**The Application Kit for Agora** — the Cocoa-compatible window, view, control and menu classes
(`NSWindow`, `NSView`, `NSApplication`, `NSMenu` and the rest).

Agora is an installable desktop environment for Linux and BSD; see the project README in the parent
directory (`../README.md`). `libagora-app` is the top of its stack: above it there are only applications.

## Status

**The AppKit is imported and its windows run on Agora's window server. The X11 seam is gone.**

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
- **The seam alone** (`ctest`): exactly 60 of 60 frames headless, and the keymap translation checked against
  a pinned `us` keymap.
- **`ctest`: 3 of 3 passed** (keyboard, window-headless, appkit-window-headless).

### What a Wayland client does not get, and where each is recorded

These are properties of the protocol rather than gaps, and each is written at the door that carries it:

- **A client does not place its own window.** `-setFrameOrigin:` moves the Cocoa frame and not the window;
  the compositor places it.
- **There is no unmap, no iconify and no stacking.** `-orderOut:`, `-miniaturize:`, `-orderBack:` and
  `-orderFrontRegardless` change *this object's* state and not the screen's.
- **There is no Expose.** The client owns the pixels; a repaint is asked for by the frame callback, which is
  why `-display` and the seam's frame handler both end in the same draw.
- **The screen is an output.** `NSScreen` asks the seam, which learns the size from `wl_output`; with no
  output described yet the frame is a zero rect rather than an invented size.

### Still absent, and why

The sheets, the toolbar, the drawer, the frame-autosave strings, the script-command doors, the cursor-rect
invalidation and the child-window list all need subsystems this stage has not reached; the window's
minimise/close BUTTONS are a window manager's (Kestrel is parked). Each is absent rather than stubbed, and
the refusals name themselves.

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
