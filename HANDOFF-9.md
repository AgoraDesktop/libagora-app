# libagora-app — a ninth handoff

*Written at the end of the work that put the **page's cursor** into the web view and found that the platform has no way
to show it. **THIS IS A FEATURE HANDOFF, NOT A NEW SURFACE CENSUS — §2 of `HANDOFF-7.md` is unchanged and its numbers
remain the ones to quote.** The property work below is measured; the platform work it needs is **not started**.*

*State at this handover, measured: `libagora-webview` at `a3269b2`, the WPE WebKit fork at `468fd5e45a`
(`~/Development/wpewebkit`, branch `agora`, installed into `agora/prefix`), the workspace pointer at `86f5d09`.
`libagora-app` is at `a23f905` and **clean**; `window-server` at `987ddae` and clean; `libagora-webview` clean. The
workspace has **two unrelated dirty entries** (`README.md`, `AgoraDesktop.github.io`) — see §9.*

*Suites, run with `AGORA_ALLOW_NESTED=1`: `libagora-webview` **14/14** against the fork and **14/14** against the
distribution's WebKit (where `webengine-cursor` SKIPS, by design). `libagora-app` unchanged by this work.*

---

## 1. What already works, and where it lives

The pipeline that produces a cursor name is finished and tested. **Nothing here needs to change** unless you find a defect.

| Repository | Commit | What it landed |
|---|---|---|
| `libagora-webview` | `468fd5e45a` (in `~/Development/wpewebkit`) | **The port stops throwing the cursor away.** `WPEWebView.h`'s `setCursor` was an empty virtual, so WPE's legacy view discarded what WebCore computed. Adds `WebKitCursorType`, `webkit_web_view_get_cursor_type()` and the **`cursor-changed` signal** (registered in `webkit_web_view_class_init`, emitted from the type-mapping lambda that also fills the getter, so the two cannot disagree). `ViewLegacy::setCursor` reports through `View::setCursorCallback`, installed by `WebKitWebView.cpp` when the view is created. *A cursor name was deliberately not exposed: `WebCore::Cursor` carries a type or an image, never a name.* |
| `libagora-webview` | `a3269b2` | **`AGWebCursor`** (21 values, `AGWebEngine.h`), `AGWebEngineCursorSupported()` / `AGWebEngineCursor()` (the getter, reached through `dlsym` so the component still builds against the distro library), and **`AGWebEngineCallbacks.cursor_changed`**. In `WKWebView`: `-ag_takeCursor:`, `-ag_refreshCursor`, `-ag_cursorName` (`"pointer"`, `"text"`, `"crosshair"`, …), `-resetCursorRects` (one rect over the bounds with the current cursor) and `-invalidateCursorRectsForView:` on change. |
| `libagora-webview` | `a3269b2` | Tests: `webengine-cursor` walks five bands of one page and asserts hand / I-beam / crosshair / not-allowed / none; `appkit_webview` asserts the link→hand and prose→I-beam changes reach the view in **0 ms**. |

MEASURED end of that pipeline, and this is all it proves: the engine reports the right value, the view installs the right
`NSCursor` and asks the AppKit to re-resolve its cursor rects. **Nothing visible changes, because the platform has no way to
show an `NSCursor`.** That is the work this handoff exists for.

## 2. The gap, precisely

Two facts, both measured, and they are independent:

**2a. Every `NSCursor` is an imageless singleton.** `libagora-app/NSCursor.m:182–188` (and its twenty-one
`+ (NSCursor *)` methods all go through it):

```objc
+ (NSCursor *)cg_sharedCursor:(NSCursor **)slot
{
    if (*slot == nil)
        *slot = [[self alloc] init];      // there is no -init override; _image stays nil
    return *slot;
}
```

So `+arrowCursor`, `+IBeamCursor`, `+pointingHandCursor` … are **twenty-one identical empty objects** — MEASURED:
`grep -c '^+ (NSCursor \*)' NSCursor.m` is 21, and `-init` is not overridden, so `_image` is nil in every one. `-set` (`NSCursor.m`)
only moves a `static NSCursor *s_current` and a retain-counted stack — it never reaches the window server.

**2b. Nothing tells the compositor which pointer to draw.** `window-server/protocol/agora-shell.xml` is 30 requests across
`agora_shell` (v10), `agora_window` (v10), `agora_window_list` (v2), `agora_output` (v2) and `agora_dock_menu` (v1) — and
**not one of them mentions a cursor**. The server sets the host pointer **once at startup** from the theme:
`window-server/src/backend-x11.c:195–212` builds an X cursor and calls `XDefineCursor()`; `src/cursor.c` draws it on DRM.
There is no per-window, per-surface or per-seat cursor anywhere.

The AppKit's own half is fine and should be reused: `NSWindow` resolves the pointer on every motion
(`NSWindow.m:802`, `cg_cursorForContentPoint:` at `:7227`), a drag suppresses resolution deliberately, `_cursorRectsEnabled`
/`_cursorRectsDirty` track staleness, and `-invalidateCursorRectsForView:` is the invalidation door. **The result of that
resolution is handed to `-set` and dies there.**

## 3. The work, in four pieces

Order matters: each piece is testable on its own, and piece D is the one that makes anything visible.

### A. Protocol — one request on `agora_window` (version 11)

The cursor belongs to the **window**, not the seat: the pointer's shape follows the window it is over, and a client that
has several windows may want different shapes in each. Something like:

```xml
<request name="set_cursor" since="11">
  <description summary="the pointer's shape over this window">
    A cursor name in the Xcursor vocabulary — "left_ptr", "text", "pointer", "crosshair", "not-allowed",
    "nwse-resize" … The compositor resolves it against its theme and shows it while this window is under the
    pointer. An empty string means the default. A name the theme does not have falls back to the default, which
    the compositor reports once rather than per move.
  </description>
  <arg name="name" type="string"/>
</request>
```

Regeneration: the protocol is generated from this XML by the existing build (see `window-server/CMakeLists.txt`).
**Bump `agora_window` to 11 and document it in the version comment at the top of the file, where every previous bump is
recorded** — versions 4 through 10 are described there and the next reader will look for 11 in the same place.

### B. Window server — a name per window, resolved once per change

- Store `char cursor_name[…]` on the window (or on the shell surface) and update it in the request handler.
- When the pointer moves to a different window **whose name differs from the name in force**, resolve it:
  `aws_cursor_theme_frames(theme, name, device_size)` already exists (`src/cursor-theme.h:76`, returning
  `struct aws_cursor_frames { int count; const struct aws_cursor_image *frames; }`).
- Nested X11: build an X cursor from frame 0 and `XDefineCursor` — the code path is `backend-x11.c:195–212`, already written
  for the startup cursor; it needs to become "for a name" rather than "for the theme's default".
- DRM: composite the frames in `src/cursor.c`, which already draws the pointer.
- The existing `DIAG cursor: the host cursor is %dx%d from the theme, hotspot (%d,%d)` line is the assertion hook for a
  test — see §7.

### C. `libagora-app` — the client door

`platform/AGWindowServer.h` gains one function beside the other window properties:

```c
/* The pointer's shape over this window, in the compositor's theme vocabulary. NULL or "" means the default. */
void AGWindowSetCursor(AGWindow *window, const char *name);
```

and `platform/AGWindowServer-Wayland.c` sends `agora_window.set_cursor`. Names cross the protocol as UTF-8; the AppKit side
(see D) is where the mapping from an `NSCursor` to a name lives, so nothing above this layer ever sees the string.

### D. `libagora-app` — `NSCursor` gets a name, and the window applies it

- Give `NSCursor` a `name` (declared in `NSCursor.h`, answered by every shared cursor, kept by
  `-initWithImage:hotSpot:` as the default process cursor's name). The mapping from a shared cursor to an Xcursor name is
  a table in `NSCursor.m`; §4 lists the names the vendored Vimix theme actually has, verified against
  `window-server/assets/cursors/Vimix/cursors/`.
- `NSWindow`: where it already calls `[(c != nil ? c : [NSCursor arrowCursor]) set]` (`NSWindow.m:802`), remember the
  resolved name and call `AGWindowSetCursor` **only when it changes** — a motion is 60 events a second and a request per
  motion is noise on the socket. A drag's early return must keep its behaviour: the drag owner has already pushed a
  resize cursor, and the window must not fight it.
- `-set`, `-pop` and the stack (`NSCursor.m`) are AppKit-global; if a name is applied there instead of in `NSWindow`, only
  the *window under the pointer* can receive it, which is another reason for the window to be the one that sends it.

**Acceptance for D:** hovering a link in `demo/agora-webview.sh` shows the hand; hovering text shows the I-beam; hovering
a window edge shows the resize cursor. Those three are the whole test, and the first two need no web-view change at all —
`WKWebView` already installs the right `NSCursor` rect.

## 4. The names, verified against the vendored theme

`ls window-server/assets/cursors/Vimix/cursors/` contains (among aliases): `default left_ptr arrow text xterm pointer
hand1 hand2 crosshair cross help question_arrow wait watch progress not-allowed no-drop move fleur col-resize row-resize
nwse-resize nesw-resize sb_h_double_arrow sb_v_double_arrow left_side right_side top_side bottom_side`. A mapping that uses
them:

| `AGWebCursor` | Xcursor name |
|---|---|
| Arrow | `left_ptr` |
| IBeam | `text` (`xterm` is the same artwork's alias) |
| Hand | `pointer` |
| Crosshair | `crosshair` |
| Busy | `wait` (`progress` if animation is ever implemented) |
| Help | `help` |
| NotAllowed | `not-allowed` |
| Move | `move` |
| ResizeEast / West / Column | `sb_h_double_arrow` / `col-resize` |
| ResizeNorth / South / Row | `sb_v_double_arrow` / `row-resize` |
| ResizeNorthWest / SouthEast | `nwse-resize` |
| ResizeNorthEast / SouthWest | `nesw-resize` |
| None (`cursor: none`) | **no theme entry** — build a blank cursor (transparent image) rather than falling back to the arrow |
| Other (custom image cursor) | default; the image is in `WebCore::Cursor` and is not carried across the port yet |

## 5. Measurements from this session, so they are not paid for twice

- **Polling for the cursor does not work; the signal does.** Asking the engine after each pointer move reported the
  **previous** band, and three seconds of pumping changed nothing. A repeat motion in the same turn did nothing. Retrying
  every 64 ms behind a pending flag still raced. Probing with `ag_now_ms()` (milliseconds since boot) did nothing at all,
  because the motions it followed carried the event's own timestamp and a jump of a million milliseconds is dropped as
  out of order. The fork's `cursor-changed` signal removed the whole question: **0 ms** in the offscreen test. Do not
  replace the callback with a poll.
- **Never release an `NSCursor`.** The class methods return one shared instance per class held by the AppKit; retaining the
  new cursor and releasing the old deallocated the singleton and left the class with a dangling pointer. Measured symptom:
  the cursor stopped changing entirely, and two hovers in a row read the earlier answer.
- **`WEBKIT_FORCE_VBLANK_TIMER`.** Any rebuild of the fork or any timing measurement without it hits a **6.4 s**
  `drmWaitVBlank()` stall inside `DisplayVBlankMonitorDRM::create` before the first load. The engine sets it
  (`ag_web_want_vblank_timer`) unless the environment already does; do not override it to "0" for a timing run.
- **`LD_LIBRARY_PATH` order is load-bearing** (also in `AGENTS.md`): the component's `build` directory **first**, then the
  prefix. A prefix first silently tests the installed copy.
- **`webengine-cursor` SKIPS** on the distribution's WebKit (2.48), which has neither the getter nor the signal. That is
  the intended behaviour, not a failure: the component runs there with its own pointer.

## 6. Building and checking

```sh
# the fork, only if it changes (it should not, for this work)
cd ~/Development/wpewebkit && ./agora/build.sh        # ~40 min on 24 cores; installs into agora/prefix

# the web view (produces the cursor; nothing to change, but the suite is the regression)
cd ~/Development/Agora/libagora-webview
cmake -S . -B build -DCMAKE_PREFIX_PATH=~/Development/Agora/build-prefix \
      -DAGORA_WPE_PREFIX=~/Development/wpewebkit/agora/prefix
cmake --build build -j8
AGORA_ALLOW_NESTED=1 ctest --test-dir build           # 14/14 with the fork; 13 + 1 SKIP on the distro library

# the platform work
cd ~/Development/Agora/window-server   && cmake -S . -B build -DCMAKE_PREFIX_PATH=~/Development/Agora/build-prefix && cmake --build build -j8 && AGORA_ALLOW_NESTED=1 ctest --test-dir build
cd ~/Development/Agora/libagora-app    && cmake -S . -B build -DCMAKE_PREFIX_PATH=~/Development/Agora/build-prefix && cmake --build build -j8 && cmake --install build

# the eye test
AGORA_WPE_PREFIX=~/Development/wpewebkit/agora/prefix demo/agora-webview.sh 1280x720 https://www.osnews.com
```

## 7. Tests to add

- **`window-server`:** a probe that binds a window, sends `set_cursor("pointer")`, and asserts the server reports it — the
  existing `DIAG cursor: the host cursor is … from the theme` line (`backend-x11.c:209`) is the hook, and the nested
  screenshot tests already know how to read the server's log. A name the theme does not have must not crash and must fall
  back to the default.
- **`libagora-app`:** a test that a window with a view adding a cursor rect asks for the *name* when the resolved cursor
  changes, and **does not ask again** when it does not — that second half is the guard against a request per motion.
- **`libagora-webview`:** nothing new; `appkit_webview` already asserts the view installs hand and I-beam. If piece D
  changes `NSCursor`, re-run it and confirm the 0 ms figures still hold.

## 8. Open questions

1. **Per-window or per-seat?** Per-window (proposed) means the server must track which window is under the pointer; a
   per-seat request would be one line of protocol less and would make two windows unable to disagree. The window is
   recommended because the AppKit already resolves per window.
2. **Animation.** `struct aws_cursor_frames` carries `count` frames — an animated theme cursor (a spinning `wait`) is
   possible on DRM, and X11's `XDefineCursor` cannot animate. Decide whether frame 0 is acceptable on both.
3. **`cursor: none`.** The theme has no blank cursor; build one (1×1 transparent) rather than falling back to the arrow,
   or a video player's own pointer will show ours underneath it.
4. **Custom image cursors** (`cursor: url(...)`) arrive as a `WebCore::Cursor` image and are currently reported as
   `Other`. Carrying the image across the port is a second piece of fork work; do not start it before the name path
   works end to end.

## 9. Tree state — read this before committing

- `libagora-app` (`a23f905`), `window-server` (`987ddae`) and `libagora-webview` (`a3269b2`) are **clean**.
- The workspace has **two dirty entries that are not this work**: `README.md` and the `AgoraDesktop.github.io`
  submodule. **Do not run `git add -A` in the workspace** — `HANDOFF-7.md` says so too, and it has already been paid for
  once (a `git add -A` in the fork committed a 16 000-file build tree and 2.4 GB of pack; it took a reset, a
  `.gitignore` and a `gc --prune=now` to undo).
- Commit per repository, in dependency order: `window-server` (protocol + handler) → `libagora-app` (client door +
  `NSCursor` + `NSWindow`) → workspace pointer.
