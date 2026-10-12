# libagora-app

**The Application Kit for Agora** — the Cocoa-compatible window, view, control and menu classes
(`NSWindow`, `NSView`, `NSApplication`, `NSMenu` and the rest).

Agora is an installable desktop environment for Linux and BSD; see the project README in the parent
directory (`../README.md`). `libagora-app` is the top of its stack: above it there are only applications.

## Status

**The window-server seam is made. AppKit itself is next.**

`NSWindow` has to put pixels on a screen and get events back, and it must not know HOW. The Fiwix AppKit
this component is being built from knows: it calls `XOpenDisplay`, `XCreateSimpleWindow`, `XMapWindow`,
`XPutImage` and `XNextEvent` directly, in `NSWindow.m` and `NSScreen.m`. Agora's target is **Wayland**, with
no X11-native target, so those calls go — and `platform/` replaces them.

```
platform/
  AGWindowServer.h              the seam: connection, windows, frames, events
  AGWindowServer-Wayland.c      its first implementation: an xdg-shell client
  AGKeyboard.h / AGKeyboard.c   evdev key codes -> text and modifiers, through xkbcommon
tests/
  window.c                      the seam driven the way NSWindow will drive it
  keyboard.c                    the keymap translation, with no compositor anywhere
  run-window-headless.sh        ctest: asserts the frame count against a headless compositor
  run-window-nested.sh          a person's test: nested compositor, screenshots, inspect.py
  inspect.py                    reads the pixels back out of a screenshot
```

### Why the seam is an interface, and why `xdg-shell` is not the destination

Agora's own window server — `window-server`, the compositor — does not exist yet. While it is written, the
seam's implementation is a client of a **stock** compositor; afterwards it has to speak to Agora's own. And
Agora's window management (client-side chrome, a system-owned menu bar, a dock, sheets, the drag session)
needs more than `xdg-shell` carries. So the protocol is behind an interface and can change without
`NSWindow` noticing, and `xdg-shell` is the bootstrap: the thing that makes the seam measurable today.

### What is measured, not assumed

`AGWindowServer.h` is the only header `tests/window.c` includes — no Wayland type, no xdg-shell name, no
shm. Two tests hold it up:

- **Frame callbacks** (`ctest`): a headless compositor and an exact frame count.

  ```
  $ ctest
      1/2 Test #1: keyboard ......... Passed
      2/2 Test #2: window-headless .. Passed
  100% tests passed, 0 tests failed out of 2
  ```

  The count is the assertion: 0 means the configure/present path is broken, and more than asked for means
  more than one frame callback is in flight — which is how a double-scheduling bug was found (61 frames
  when 60 were asked for).

- **Pixels and motion** (`tests/run-window-nested.sh`): a nested compositor on the desktop, two captured
  screenshots a second apart, read back by `inspect.py`:

  ```
  red marker   : 701 px at (691,384)..(725,418)      upper-left   (a wedge is eaten by corner rounding)
  green marker : 1225 px at (1193,692)..(1227,726)   lower-right  (a solid 35x35)
  window on screen: 537x343 at (691,384)             (the 720x460 buffer, compositor-scaled)
  bar moved    : +215 px between the two captures
    [ok] red top-left   [ok] green bottom-right   [ok] square markers
    [ok] gradient R rises left->right (53 -> 222) [ok] gradient G rises top->bottom (45 -> 163)
    [ok] bar present    [ok] bar MOVED
  ```

  The red square at buffer `(0,0)` and green at `(W-1,H-1)` make **orientation a measurement**: a bottom-up
  buffer or a stride in the wrong unit puts them in the wrong corners. The moving bar can only move if the
  frame handler is being called repeatedly. The red marker's missing quarter is the compositor's window
  corner rounding — a clean arc, identical in both captures, and the reason the test asserts a *square*
  marker rather than a solid one.

- **Keymap translation** (`ctest`): a `us` keymap in the form `wl_keyboard.keymap` sends, fed known evdev
  codes — `30 -> "a"`, with shift `30 -> "A"` and `2 -> "!"`, caps lock `30 -> "A"`, `57 -> " "`, `42`
  (Shift) and Escape -> `U+001B`, and a keymap that does not compile is refused.

## Build

**clang is required.** Agora builds with clang only, and this is an Objective-C component: the seam is C,
but AppKit's classes arrive as `.m` files and the language is enabled for them now.

```sh
cmake -S . -B build -DCMAKE_C_COMPILER=clang -DCMAKE_OBJC_COMPILER=clang
cmake --build build
cd build && ctest
```

A plain `cmake -S . -B build` will take the system `cc`, which on a machine without GCC's Objective-C
frontend fails at the language check before it ever reaches this tree.

Requires `wayland-client`, `xkbcommon` and `wayland-protocols` (system packages, not vendored — the same
terms as ICU and OpenSSL elsewhere in Agora). The `xdg-shell` bindings are **generated** at build time by
`wayland-scanner` from the system's protocol XML, so they cannot silently age against the protocol on the
machine.

## Licence

MIT — see [`LICENSE`](LICENSE). The seam is Agora's own code. The AppKit classes being imported are the same
author's and the same licence; that will be recorded in `PROVENANCE.md` when they land.
