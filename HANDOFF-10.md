# libagora-app — a tenth handoff

*Written at the end of the work that **made a cursor visible**: the wire `HANDOFF-9.md` said the platform did not have.
`HANDOFF-9.md` is not superseded — its §2 numbers are still the census to quote — and what it called "not started" is
now done, measured, and committed on both sides of the seam. **THIS IS A FEATURE HANDOFF.***

*State at this handover, measured: `window-server` at `ef155cb`, `libagora-app` at `019b381`, `libagora-webview` at
`db95947` — all three clean. The WPE WebKit fork is unchanged at `468fd5e45a` (`~/Development/wpewebkit`, branch
`agora`, installed into `agora/prefix`). The workspace has **two unrelated dirty entries** (`README.md`,
`AgoraDesktop.github.io`) — see §8.*

*Suites, run with `AGORA_ALLOW_NESTED=1`: `window-server` **28/28**, `libagora-app` **196/196**, `libagora-webview`
**14/14** against the fork (including `webengine-cursor`), `workspace` **15/15**.*

---

## 1. What landed, and where it lives

Four pieces, in dependency order, exactly as `HANDOFF-9.md` §3 planned them.

| Repository | Commit | What it landed |
|---|---|---|
| `window-server` | `ef155cb` | **The protocol and the server.** `agora_window.set_cursor` at version 11 (and the shell global at 11, because a window inherits the version of the object that made it), `cursor_name` on `struct aws_surface`, `aws_cursor_set_shape` / `aws_cursor_follow_focus` / `aws_cursor_report_shape` in `cursor.c`, and the one line in `seat.c`'s `pointer_set_focus` that makes the shape follow the window under the pointer. `AWS_CURSOR_DIAG` now says what a window asked for and what it resolved to. |
| `libagora-app` | `019b381` | **The client door and the name.** `AGWindowSetCursor` on the seam (`platform/AGWindowServer.h`, sent by `AGWindowServer-Wayland.c`), `NSCursor -name` with the mapping assigned where each singleton is made, and `-[NSWindow cg_applyCursor:]` — which is the whole of the client side: `-set` for the AppKit's stack, then the NAME, and only when it changed. |
| `libagora-webview` | `db95947` | **The thing that made it visible over a page**, and it was not the cursor at all: the view installs its own `NSTrackingArea` so it hears the pointer, because a window does not deliver a bare motion unless it was told to. See §3.6 — this is the finding of the session. |
| `~/Development/wpewebkit` | `468fd5e45a` | Unchanged. The port still reports the page's cursor through `cursor-changed`, and that half needed nothing. |

## 2. The pipeline, end to end, measured

This is the whole chain in one log, and it is the first time any of it has been visible outside a test. A page that is
one `<a>` filling the body, `demo/agora-webview.sh 1000x700 file:///tmp/link.html`, `AWS_CURSOR_DIAG=1` and
`WK_WEBVIEW_DIAG=1`:

```
  DIAG move: view (...)-> engine (...)                      (3 motions reached the view)
  DIAG cursor: 3 -> pointer                                 (the page's Hand, in the view)
  DIAG cursor: window 1 asks for pointer, which the theme has at 32x32, hotspot (16,4)
  DIAG cursor: the host cursor is 32x32 from the theme, hotspot (16,4)
```

Read it as the five hops: **page → `AGWebCursor` → `NSCursor` → its name → `agora_window.set_cursor` → the theme's
artwork → the host's X cursor**. The last line is `backend-x11.c`'s own, which is the one a screenshot can never
show — a nested session has the HOST draw the pointer.

The default is the same chain with `left_ptr`, and it appears on a pointer ENTER with no motion at all, which is the
new path in §3.5.

## 3. The decisions, so they are not re-litigated

**3.1 A NAME, NOT A PICTURE.** `wl_pointer.set_cursor` carries a surface of the client's own pixels; that is the wrong
shape of thing here. The desktop is designed with its pointers — the theme is installed, its variants exist so nothing
is resampled, and a 24-point pointer is the theme's 32×32 arrow on a 96-dpi panel — so what crosses is `text`,
`pointer`, `nwse-resize`, and the compositor picks the artwork for its own dots per inch. That is also what makes a
fractional scale work without the client knowing the scale.

**3.2 PER WINDOW, NOT PER SEAT.** Settled: the answer is a function of the view under the pointer, and two windows of one
application can disagree. The server keeps a name per surface and applies the one belonging to `pointer_focus`.

**3.3 `nil` IS A REAL ANSWER ON A CURSOR.** An image cursor and `disappearingItemCursor` have no name (no theme has a
poof of smoke, and `no-drop` means a refused drop); the window then asks for the compositor's DEFAULT. That is why
`AGWindowSetCursor(NULL)` and `""` are the same request.

**3.4 `none` IS A SHAPE.** `cursor: none` is a 1×1 transparent pixel the compositor makes, not a fallback to the arrow —
a video player with its own pointer must not have ours underneath. `AWS_CURSOR_NONE_NAME` is that name, and the server
resolves it before consulting the theme, because no theme has an invisible cursor.

**3.5 THREE PLACES RESOLVE, AND TWO OF THEM ARE NEW.** A motion (as before), a pointer entering the window (a dock tile
raises a window under a hand that is not moving — no motion follows), and a cursor-rect invalidation (a page
announcing a different cursor under a resting pointer). **A drag still resolves nothing**: the drag's owner has pushed
its own cursor and the window must not fight it, which is pinned by a check so it cannot be lost.

**3.6 THE VIEW HAS TO HEAR THE POINTER AT ALL — THE FINDING OF THIS SESSION.** `-acceptsMouseMovedEvents` is NO by
default on a window (Apple's), so a bare motion became NO `NSEvent`, `-mouseMoved:` never ran, WebKit never learned
what was under the pointer, and a page's cursor was never computed. Everything upstream was correct and nothing could
ever show. MEASURED before the fix: a page that is one big link sent the compositor `left_ptr` and nothing else, and
`WK_WEBVIEW_DIAG` counted **zero** motions reaching the view. The fix belongs in the VIEW (an `NSTrackingArea` with
`NSTrackingMouseMoved | NSTrackingActiveAlways | NSTrackingInVisibleRect`), not in an embedder, because an embedder that
had to know would be one that quietly lost every `:hover` in the page.

**3.7 A REQUEST PER CHANGE, NEVER PER MOTION.** `-[NSWindow cg_applyCursor:]` compares the resolved name with the one it
last sent; a motion is sixty events a second and a repeat is a `strcmp`. The server's `aws_cursor_set_shape` dedups the
same way, so a client that forgets still cannot make the compositor re-resolve per motion.

**3.8 THE NAME IS ASSIGNED WHERE THE SINGLETON IS MADE.** `+cg_sharedCursor:named:` sets it once. A second table keyed by
pointer identity would eventually disagree with the object it describes.

## 4. Measurements worth not paying for twice

- **The mapping was checked against the artwork, not against a second table.** `tests/cursor_name.m` reads
  `window-server/assets/cursors/Vimix/cursors` and asserts every non-nil name is a file there. A typo in a name costs a
  silent fallback to the arrow — the exact failure this work was about — and nothing else would catch it.
- **A name the theme lacks is the THEME's default, not Agora's drawn arrow.** `left_ptr` exists whenever any theme does,
  so `help` on a theme without it gives that theme's arrow rather than the polygon in `cursor.c`.
- **`AWS_CURSOR_DIAG` says which of the two happened**, once per request, with the window's number: `… which the theme
  has at 32x32, hotspot (16,4)` or `… which the theme has not got — the default is shown`.
- **The host's X cursor is re-applied, not re-created.** `aws_cursor_set_shape` calls `backend.apply_cursor`, which frees
  the previous `Cursor` and `XDefineCursor`s the new image — the startup path, unchanged, now taken for a name.
- **A shape change on a DRM output damages the WHOLE output**, not the pointer's box: the box arithmetic is a function of
  the image being replaced, so "where it was" is not a rectangle that can still be computed. One extra frame per shape
  change, and a stale arrow otherwise.
- **`--cursor-size`, `--dpi` and the theme are untouched by this work** — `HANDOFF-9.md` §5 and `AGENTS.md` still hold.
- **`libagora-webview`'s build must be configured with `-DAGORA_WPE_PREFIX=…` in a FRESH build directory.** The
  pkg-config results are cached variables, so re-running cmake on an existing `build/` keeps the distribution library and
  `webengine-cursor` then SKIPS — which is how this session nearly recorded 13+1 instead of 14/14.
- **The demo's pointer was moved by hand, once, to see it.** `XWarpPointer` into the nested window and back; the log above
  is from that run. No test does this — the cursor suites in `window-server` say why in as many words.

## 5. What is still not done, named rather than left to be discovered

1. **Animation.** `struct aws_cursor_frames` carries frames and frame delays, and the compositor draws frame 0. An
   animated `wait` on DRM is possible (it would be the first thing to make the frame delay matter); `XDefineCursor`
   cannot animate, so the two display paths would differ and that is a decision, not a detail.
2. **`wl_pointer.set_cursor`, the client's own pixels.** Still accepted and ignored (`pointer_set_cursor` in `seat.c`).
   A page's `cursor: url(...)` therefore arrives as `AGWebCursorOther` and shows the arrow. Carrying the *image* across
   the port is a second piece of fork work and a second protocol shape; the name path had to work first and now does.
3. **`+hide` / `+unhide` are still OWED.** `NSCursor.h` says so, and it is now the concrete gap: with `none` on the
   wire, hiding is a name the compositor already understands, so the missing part is on THIS side — a window's
   resolution would have to answer `none` while the counter is up, and `+hide` would have to reach the window under the
   pointer. `AGWebCursorNone` is mapped to the arrow in `libagora-webview`'s `ag_cursor_for` for exactly this reason, and
   that line is what would change. The `owed_census.txt` line moves with it.
4. **`NSTrackingMouseMoved` events carry no modifiers.** The tracking engine builds the `NSEvent` with
   `modifierFlags:0`, so a page sees a hover with no keys held while a key is held. Harmless today (a drag does not go
   through the tracking area) and worth fixing in `NSWindow -cg_eventForArea:` rather than in the web view.
5. **One cursor got no name.** `disappearingItemCursor` is nil on purpose (§3.3). If a theme ever ships a poof, that is
   the line to revisit.
6. **The `test/` half of `libagora-webview`'s nested runner is unchanged.** The cursor is visible in a nested session
   because the HOST draws it; the demonstration in §2 was a hand-run, not a ctest, and it stays that way.

## 6. Building and checking

```sh
# the platform work
cd ~/Development/Agora/window-server   && cmake --build build -j8 && AGORA_ALLOW_NESTED=1 ctest --test-dir build
cd ~/Development/Agora/libagora-app    && cmake --build build -j8 && cmake --install build && AGORA_ALLOW_NESTED=1 ctest --test-dir build
cd ~/Development/Agora/workspace       && cmake --build build -j8 && AGORA_ALLOW_NESTED=1 ctest --test-dir build

# the web view, which is where the cursor over a page is decided
cd ~/Development/Agora/libagora-webview
rm -rf build   # the WPE prefix is a cached pkg-config result; see §4
cmake -S . -B build -DCMAKE_C_COMPILER=/usr/bin/clang-19 -DCMAKE_OBJC_COMPILER=/usr/bin/clang-19 \
      -DCMAKE_CXX_COMPILER=/usr/bin/clang++-19 \
      -DCMAKE_PREFIX_PATH=~/Development/Agora/build-prefix -DAGORA_WPE_PREFIX=~/Development/wpewebkit/agora/prefix
cmake --build build -j8 && AGORA_ALLOW_NESTED=1 ctest --test-dir build     # 14/14

# the eye test
AWS_CURSOR_DIAG=1 WK_WEBVIEW_DIAG=1 AGORA_WPE_PREFIX=~/Development/wpewebkit/agora/prefix \
  demo/agora-webview.sh 1280x720 https://www.osnews.com
```

`LD_LIBRARY_PATH` order still decides what is tested (`AGENTS.md`): the component's `build` FIRST, then the prefix. And
`AGORA_CURSOR_THEME` is what makes a session read the checkout's Vimix rather than an installed one.

## 7. Tests, and what each one can and cannot see

- `window-server-cursor` — the resolution, as arithmetic: `text` is the theme's `text` (image, size and hotspot), `none`
  is one transparent pixel that draws nothing, a name the theme lacks is the DEFAULT arrow, the same name twice does
  nothing, and `""` is the default by name.
- `window-server-cursor-name` — a REAL client (maps a window, sends four kinds of name plus an over-long one) against a
  live headless server, asserting the server's own DIAG lines. No display needed, which is the point: the claim is the
  resolution, not the pixels.
- `window-server-seat-routing` — the seat's half: the shape in force is the one belonging to the window the pointer ended
  up over, and the default over no window at all.
- `appkit-cursor-name` (`libagora-app/tests/cursor_name.m`) — the mapping against the theme's directory, an image cursor
  answering nil, and the window's bookkeeping driven through the real `-cg_handleSeamEvent:`: one request for two
  motions, none while a button is down, one on release, one when a view changes its answer under a resting pointer, and
  none when an invalidation changes nothing.
- `appkit-webview` (`libagora-webview`) — `-ag_cursorName` per band at 0 ms, and now the tracking area: it exists, it is
  over the visible rectangle, and its owner is the view.
- **What none of them can see: the pointer itself.** A nested session's pointer is the host's; a DRM output's is
  composited into pixels no test is looking at. That is why §2 is a hand-run log and why the DIAG line exists.

## 8. Tree state — read this before committing

- `window-server` (`ef155cb`), `libagora-app` (`019b381`) and `libagora-webview` (`db95947`) are clean; `workspace` has
  only its own gitlinks changed, and `swift-*`/`release` are untouched.
- The workspace still has **two dirty entries that are not this work**: `README.md` and the `AgoraDesktop.github.io`
  submodule. **Do not run `git add -A` in the workspace** — `HANDOFF-7.md` and `HANDOFF-9.md` both say so, and it has
  already been paid for once (a `git add -A` in the fork committed a 16 000-file build tree).
- Commit per repository, in dependency order: `window-server` (protocol + handler + cursor module) → `libagora-app`
  (seam + `NSCursor` + `NSWindow`) → `libagora-webview` (the tracking area) → workspace pointer.
- `libagora-app`'s `PROVENANCE.md` §74 records this slice in that file's voice, and `tests/api-10.6-census.txt` moved
  `methods-declared` 5416 → 5417 with `sel:NSCursor` unchanged — `-name` is this tree's own door, not Apple's surface.
