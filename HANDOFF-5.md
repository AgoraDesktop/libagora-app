# libagora-app — a fifth handoff

*Written at the end of **twelve slices** that picked `HANDOFF-4.md` up where its §8 stopped — §9–§20 of that file are their
running record, one numbered section per slice, and they are still the long form of everything summarised here. **A
THIRTEENTH SLICE HAS LANDED SINCE, and §9 is its record.**
`HANDOFF.md`, `HANDOFF-2.md` and `HANDOFF-3.md` remain worth reading: nothing in any of them was wrong, and the second
file's §2 instrument rules and §4 traps are still the ones these sessions used most. **THIS FILE'S §2 NUMBERS SUPERSEDE
`HANDOFF-4.md`'s**, which are twelve slices old.*

*State at this handover: **twenty slice commits** since the fourth handoff, tree clean, **161 tests passing in about
87 s**, `api-ledger check` holding **375 metrics** — **132 of 168 classes (79%), 4519 of 4519 selectors (100%), 39 of 56
protocols (70%), 86 of 86 functions**, 5051 methods declared with 8 having no body, **ALL 130 classes with a surface at
COMPLETE coverage** — refusal census **387**, owed census **19**. **The "120 of 129" this paragraph first carried was a
recount error; §9 records it and the corrected movement, and §10–§16 take it to 130 of 130.***

---

## 1. What these sessions did

Twelve slices, in the order they landed. Each is a commit (plus, twice, a commit in the **workspace** repository and a
gitlink advance in `$AGORA_ROOT`), and each ended green. **The thirteenth through twentieth are `182bcd4`, `b0bd73c`,
`1c4be0a`, `db418e3`, `1d1d7f4`, `47b090e`, `e199a54` and `99baeca`, listed below and recorded in §9–§16.**

| Commit | What it landed |
|---|---|
| `6bc8dbe` | **The text view's container, its margin and the drop.** Sixteen `NSTextView` selectors: `-initWithFrame:textContainer:` as the designated initialiser, the three container doors, `-textContainerInset`/`-textContainerOrigin`/`-invalidateTextContainerOrigin`, `-setConstrainedFrameSize:`, the caret and backdrop doors, and **`-characterIndexForInsertionAtPoint:`** — which retires the "a drop lands at the insertion point" limit the clipboard slice recorded. |
| `92f4f41` | **What typing does around it.** The smart-insert pair and its whole door, smart delete, `-allowsUndo`/`-breakUndoCoalescing`/`-isCoalescingUndo` and `-didChangeText`, in a category file. **And the finding: `NSWindowDelegate -windowWillReturnUndoManager:` was declared and NEVER SENT** — `-[NSWindow undoManager]` is the caller now. |
| `741cdf3` | **The browser's columns have places.** A title strip (`-isTitled`, `-drawTitleOfColumn:inRect:`), the three frames and `-frameOfRow:inColumn:`, the inverse `-getRow:column:forPoint:`, the width conversions, `-defaultColumnWidth`, the click doors — and the document view FLIPPED. |
| `c3f629c` | **The era's command set.** All fifty-seven `NSResponder` selectors declared and forwarded (**the class is COMPLETE**), the Page Up/Down and Option-arrow bindings in `NSTextInputContext` (a mapping whose written excuse had expired), and `NSTextView`'s paging, paragraph and scroll implementations. |
| `afa0017` | **`NSWorkspace`'s launch verbs.** `-URLForApplicationWithBundleIdentifier:`, `-fullPathForApplication:`, the 10.6 launch spelling, Apple's launch funnel, the two deprecated dictionary doors, `-iconForFiles:`, `-getInfoForFile:application:type:` — and **nine named refusals** (the type questions need a UTI database; "open with" needs a launch specification). |
| `efd777b` | **The browser advertises the 10.6 item model.** The four item delegate doors and ten class doors; the item walk starts at the `nil` root and retains nothing; the NeXT cell contract becomes the FALLBACK. |
| `fe3cc3c` | **The browser is COMPLETE** (120/120): the drag quartet, the reload trio, display and scroll, the flags with readers, the width autosave, and five refusals (the matrix quartet, because its columns are tables; `-setReusesColumns:`). |
| `887965e` | **The menu view is COMPLETE** (42/42): the geometry the drawing already used, the seven metrics measured across the rows, the item lifecycle reached through `NSMenu`'s own notifications, the highlight by index — and ten refusals (`NSMenu` owns the tracking window; tear-off menus are dead). |
| `fac78a4` | **`NSText`'s own surface — COMPLETE** (70/70): one run, the automatic fit, the RTF/RTFD round trips, the font pasteboard, the spelling check that selects. |
| `bad047b` | **`NSFont` — COMPLETE** (71/71): every metric from the FACE, the screen/printer variants that ARE the receiver, the user-font defaults that survive a missing `$FNX_CONFIG_ROOT`, and eight refusals. |
| `e25be8e` | **`NSWorkspace`'s file operations** (57/58): the five verbs, the modern recycle/duplicate pair, `-openTempFile`, the volumes, the labels, the desktop-picture store, the change notifications — and thirteen refusals. **The per-volume trash rule, found by `EXDEV`.** |
| `7a447cb` | **`NSTextView` — COMPLETE** (186/186): document background, links (delegate first, URL second), word completion — and thirty refusals, four of them because their bit would have no reader. |
| `182bcd4` | **The slider pair — COMPLETE** (`NSSlider` 30/30, `NSSliderCell` 35/35): the tick marks as VALUES with a snap, the title as a CELL in a band taken off the top, the two no-argument ink doors answered from the control view, the background image drawn, and **a flipped vertical scale that was upside down** (§9). |
| `b0bd73c` | **`NSTableView` — COMPLETE** (123/123): the deprecated spellings mapped to the modern state, the autoresizing styles actually applied by `-tile`, the selection enumerators, both drag-image doors, the focused column's ring, the header indicator image, the three destination-feedback drawings, the cell-click door, and the vertical-motion gate (§10). |
| `1c4be0a` | **`NSControl` — COMPLETE** (65/65): the cell-class factory, the one-cell selection, the paint/invalidate quartet, the sender-value family, the formatter pair, the attributed value and writing direction, the keyboard refusal, and `-validateEditing` — which lands an editor's string without ending the session (§11). |
| `db418e3` | **`NSView` — COMPLETE** (221/221): the forced display family, the frame/rotation setters, the subview list, autoscroll, the four named refusals (focus lock, layer, definition range) and the nine ruler client defaults — with `…inContext:` corrected to Apple's spelling (§12). |
| `1d1d7f4` | **`NSWindow` — COMPLETE** (261/261): the mutable style mask, the three `is` aliases, the represented-filename setter, the default button/backing/order/colour state, the spaces flag, the screen initialiser, the direct animated frame set, and the local event queue's post/discard pair — plus a deferred window that can now drain its queue (§13). |
| `47b090e` | **`NSDocument` and `NSDocumentController` — COMPLETE** (104/104 and 51/51): a separate autosave file with a `~/Library/Autosave` registry and timer, the asynchronous close review wired into `-performClose:`, the filename/save-panel state, page-layout hooks, the document→controller→application error chain (with `NSResponder`'s stale alert refusals replaced), and three named scripting refusals (§14). |
| `e199a54` | **`NSSavePanel` and `NSWorkspace` — COMPLETE** (47/47 and 58/58): the package flag became a real listing/accept rule, and the deprecated `-openTempFile:` is `-openFile:`'s spelling — closing the last four selector rows over the 129 classes with a surface (§15). |
| `99baeca` | **`NSImageView` — the first ABSENT class to arrive** (14/14): a thin `NSControl` over `NSImageCell`, with the three placement forwards measured in ink, the two edit gates and the animation flag, and real paste/delete beside the encoder-owned copy/cut refusal (§16). |

Plus, in the **workspace** repository: `e31e44f` (the main-menu test's Print… case was asking a chain-routed row to resolve
with no key window, and expecting the item's target to be the stand-in) and `47d9a0c` (the file window opens a document
through `[[NSWorkspace sharedWorkspace] openFile:]` instead of calling Launch Services itself — the first real caller of
the launch verbs).

**AND THE HANDOFF'S OWN RECOUNT FOUND ONE MORE DOOR.** Writing this file re-ran the ledger per class, which is how
`-positionOfGlyph:forCharacter:struckOverRect:` (the fifth attachment-position door) turned up undeclared: `NSFont` was
70 of 71, not "70 of 70", and the §18 record said so. It is declared and refused now. **A number in a commit message is a
claim; the recount is the measurement.**

---

## 2. The surface, measured

```
classes   132 of 168   (79%)    36 missing
selectors 4519 of 4519 (100%)    0 missing   130 of 130 classes at COMPLETE coverage
protocols  39 of  56   (70%)    17 missing
functions  86 of  86  (100%)     0 missing    10 refuse by name
methods   5051 declared on this tree's own classes, 8 with NO body on the chain (0.2%)
```

**SEVENTEEN CLASSES ARE COMPLETE FOR THE ERA, and every one of them finished with NAMED REFUSALS rather than a stub:**

| Class | Selectors | Refusing by name |
|---|---|---|
| `NSTextView` | 186 of 186 | 30 |
| `NSResponder` | 145 of 145 | 0 (all forwarders) |
| `NSBrowser` | 120 of 120 | 5 |
| `NSText` | 70 of 70 | 5 |
| `NSFont` | 71 of 71 | 8 |
| `NSMenuView` | 42 of 42 | 10 |
| `NSSlider` | 30 of 30 | 0 (the image is drawn as a background) |
| `NSSliderCell` | 35 of 35 | 6 (five need a control view; one is the circular face) |
| `NSTableView` | 123 of 123 | 0 (the deprecated doors are answered; the drag session is the tier's) |
| `NSControl` | 65 of 65 | 0 (every door is a cell forward or a stated effect) |
| `NSView` | 221 of 221 | 20 sites (printing, focus lock, layer, definition, file drag, full screen) |
| `NSWindow` | 261 of 261 | 23 sites (server placement, DRM-less backings, the missing device/session pieces) |
| `NSDocument` | 104 of 104 | 5 sites (the scripting suite and the print script command) |
| `NSDocumentController` | 51 of 51 | 0 (the error chain forwards to the application) |
| `NSSavePanel` | 47 of 47 | 0 (the expanded layout is answered NO, not refused) |
| `NSWorkspace` | 58 of 58 | 23 sites (the platform services and the missing device/session pieces) |
| `NSImageView` | 14 of 14 | 0 (copy/cut reach the image class's own encoder refusal) |

**AND NO CLASS WITH A SURFACE HAS ANY DEBT.** Every one of the 129 classes the manifest shares is at COMPLETE coverage.
The 36 ABSENT classes remain absent for the reasons in the grouping above; the class count is 132 of 168, and their
selectors are not in the offered total.

`*` `NSWorkspace`'s one is an INSTRUMENT quirk, not a door: the manifest's row is `selector NSWorkspace openTempFile:`
**with a colon Apple's declaration does not have** (every other zero-argument door in the manifest has none), so no header
can answer it. It is the second row in this file's census that is off BY CONSTRUCTION rather than by omission — the first
is `NSFileWrapper`, which is Foundation's (see §3).

**THE 36 ABSENT CLASSES GROUP CLEANLY, and the grouping has not changed in thirteen slices:**

| Group | Classes | What it needs |
|---|---|---|
| Editors and containers | `NSDrawer`, `NSTokenField`, `NSTokenFieldCell` | real views over machinery that exists (the image family, the split view's collapse, the field editor). `NSCollectionView`/`NSCollectionViewItem` is 10.11-only and stays refused (the plan's §9.3). |
| Controllers / bindings | `NSController`, `NSObjectController`, `NSArrayController`, `NSDictionaryController`, `NSUserDefaultsController`, `NSTreeController`, `NSTreeNode` | KVO/KVC substrate — a design question before it is a slice. |
| Rules and tokens | `NSRuleEditor`, `NSPredicateEditor`, `NSPredicateEditorRowTemplate` | a predicate editor over the rule editor; both are views over controls that exist. |
| Still refused, per the plan's §A11 | `NSOpenGL*` (5), `NSMovie`, `NSMovieView`, `NSQuickDrawView`, the four typesetters, `NSSpeechSynthesizer`, `NSSpeechRecognizer`, `NSSound`, `NSInputManager`, `NSInputServer`, `NSDockTile`, `NSHelpManager`, `NSPersistentDocument` | GL, QuickDraw, movies, a PostScript/typesetting engine, platform services, an input-manager era that is gone, a Dock contract, a Help Viewer, and a document subclass that needs autosave. Each is named at the door that would have to refuse. |
| Not this component's | `NSFileWrapper` | Foundation's (`libagora-base/NSFileWrapper.h`). The real AppKit gap is 35. |

**THE 17 MISSING PROTOCOLS ARE ALMOST ALL CONTRACTS FOR CLASSES IN THAT TABLE**: `NSDrawerDelegate`,
`NSSpeechSynthesizerDelegate`, `NSSpeechRecognizerDelegate`, `NSSoundDelegate`, `NSInputServiceProvider`,
`NSInputServerMouseTracker`, `NSDockTilePlugIn`, `NSCollectionViewDelegate`, `NSGlyphStorage`, `NSTokenFieldDelegate`,
`NSTokenFieldCellDelegate`, `NSRuleEditorDelegate`, `NSAnimatablePropertyContainer`. Five exceptions have their classes and
are small slices: **`NSTextViewDelegate`** (the view has a delegate and now even calls `-textView:clickedOnLink:atIndex:`
through an informal category), `NSIgnoreMisspelledWords` and `NSChangeSpelling` (the field editor's spelling menus), and
`NSUserInterfaceItemSearching` (the application has a search-handler registry).

---

## 3. The instrument, which is still the deliverable

Four censuses and one ledger, all committed and all gated by `ctest`:

| Artifact | What it is |
|---|---|
| `api/10.6/appkit-manifest.txt` | The SDK's facts: 168 classes + superclasses, 56 protocols, 87 functions, 5208 selectors. |
| `tests/api-10.6-census.txt` | **375** pinned metrics — eight aggregates, one `sel:` line per class (129 of them), one `proto:` line per protocol, `fn:`/`fndecl:` per function, `selphantom:` per class. |
| `tests/api_census.cmake` | The gate: two-directional comparison, arithmetic check, two fault checks. |
| `tests/refusal_census.txt` | **387** refusal sites, per FILE. |
| `tests/owed_census.txt` | **19** headers' OWED notes, per file. |
| `tools/api-ledger` | The parser: `manifest`, `census`, `check`, `missing`. |

* **`missing` IS THE DOOR TO PICK A SLICE WITH** — `./tools/api-ledger missing api/10.6/appkit-manifest.txt . --library
  build/libagora-app.so` prints the absent classes, protocols, functions and the per-class debt list. Pass `--library` or
  the functions read 0 of 86 (the count is `nm -D`, not a header diff).
* **AND IT CAN BE ASKED PER CLASS** — this is the recount that caught `NSFont`'s fifth attachment door and, in §13 of
  `HANDOFF-4`, a header block that had swallowed two declarations. `parse_tree` twice and a `diff` of the per-class
  declaration counts names the class and the selectors in one line.
* **EVERY SLICE RE-PINS DELIBERATELY.** Let `ctest -R appkit-api-census` fail, recompute with `./tools/api-ledger census
  …`, write it in the same commit, and recompute the four hand-written summary lines from the numbers rather than editing
  them by eye.
* **A REFUSAL CENSUS IS A CENSUS, NOT A RATCHET.** It went 292 → 387 across these eighteen slices, and almost every move was
  UP: a door that used to be absent is now a NAMED refusal, so a caller gets a reason instead of a link error. Downward
  moves happened too (the browser's matrix form, the print doors). The diff says why, every time.
* **THE NEEDLE IS `(APPKIT-REFUSE|fn_refuse_[a-z]+)` NOW**, widened twice — the second time because a third helper
  (`fn_refuse_workspace`) and two files' local helpers were invisible to a needle that named `fn_refuse_window` literally.
  **A CENSUS WHOSE NEEDLE ENUMERATES HELPER NAMES WILL ALWAYS LAG THE HELPERS**; the pattern, not the list, is the fix.
* **THE LEDGER CANNOT SEE PROTOCOL DOORS.** All 5208 manifest selectors are attributed to CLASSES; a `proto:` line pins
  the protocol's PRESENCE, never its messages. So the item-based `NSBrowserDelegate` doors, `NSTextViewDelegate`'s link
  question and every other protocol contract are held by the header's prose and the probe ALONE. An instrument that read
  protocol bodies is a real gap, named here rather than discovered later.
* **TWO ROWS ARE OFF BY CONSTRUCTION AND THE CENSUS SAYS SO IN ITS OWN PROSE**: `NSFileWrapper` (Foundation's, counted
  because the 10.6 umbrella imports Foundation) and `NSWorkspace -openTempFile:` (the manifest's row has a colon).
* **`classes-present` counts two classes with no surface**, so "121 of 129" is 121 of the 129 with selectors, not 131.
  **AND THE OLDER "120" WAS WRONG BY ONE**: the previous pin's own `sel:` lines give 119 complete, because `NSSlider`
  and `NSSliderCell` were both incomplete. The slider pair makes 121. Recompute this number, do not inherit it.

---

## 4. Traps these sessions paid for

Each cost time; each is the same shape as a trap in `HANDOFF-2.md` §4. The long form of each is in `HANDOFF-4.md` §9–§20.

**A DECLARED DOOR WITH NO SENDER.**

* **`NSWindowDelegate -windowWillReturnUndoManager:` WAS PUBLISHED, DOCUMENTED AND NEVER SENT.** `NSResponder -undoManager`
  described the walk that reaches it; nothing answered. A text view in a window therefore found no manager and
  `-allowsUndo` could register nothing — a feature that would have looked implemented and done nothing. §7 carries the
  general rule: grep for the door's SENDER as well as for its row.
* **`NSMenuView`'s attachment family is the same shape from the other side**: Apple's view owned the popup, but in this
  tier `NSMenu` owns the tracking window — so the eight doors refuse rather than growing a second owner.

**A CELL-LESS `NSControl` HAS NOWHERE TO PUT AN ACTION.**

* **`NSBrowser` IS AN `NSControl` WITH NO CELL**, so `NSControl`'s cell-forwarding target/action answered `nil`/`NULL` for
  ever: `-doClick:` recorded where the click landed and **sent nothing**. The browser keeps its own pair now, where Apple's
  `NSControl` keeps it. The trap is waiting for any other cell-less control.

**A COMMENT EXPLAINING WHY SOMETHING IS ABSENT IS A CLAIM WITH A SHELF LIFE.**

* `NSTextInputContext`'s page binding said *"a page is a viewport's height and this tier has no viewport"* for three slices
  after the clip view arrived. **When a refusal's reason names a MISSING PIECE, grep for that piece before trusting the
  comment** — it may already be here.

**A HEADER EDIT THAT REPLACES A BLOCK DELETES DECLARATIONS SILENTLY.**

* Rewriting the icon block in `NSWorkspace.h` took `-iconForFile:` and `-iconForFileType:` with it. It compiled (ObjC only
  warns at a call site), the bodies were still in the `.m`, and the probe passed because it called `-iconForFiles:`. **The
  only witness was the census arithmetic** — seventeen declarations added, `methods-declared` up by fifteen.

**ENVIRONMENT FACTS THAT LOOK LIKE BUGS IN YOUR CODE.**

* **`NSApp` IS NULL UNTIL `-sharedApplication` RUNS** — `[NSApp sendAction:…]` on the global returns `NO` without a
  message. Ask the CLASS for the instance (`[NSApplication sharedApplication]`), as the rest of the tree does.
* **`NSUserDefaults` WRITES UNDER `$FNX_CONFIG_ROOT/…` AND THROWS WITHOUT IT.** A defaults write that cannot land must not
  abort a caller: the four `NSFont` user-font doors catch it (the preference does not persist, which is honest), and a
  PROBE that measures persistence sets a root first — that is a launcher's job, not a library's.
* **`NSTemporaryDirectory()` ANSWERS `/System/Temporary Files/`**, which need not exist — `-openTempFile` tries `$TMPDIR`,
  then the platform path, then `/tmp`.
* **`/proc/mounts` READS AS ZERO BYTES THROUGH THE STRING DOOR** — it is a symlink to a file whose `stat` size is 0, so
  `-mountedLocalVolumePaths` reads with stdio. And a mount filter that drops `overlay`/`squashfs` empties the list on a
  container's root: a live system's root can be either.
* **A RENAME CANNOT CROSS A DEVICE (`EXDEV`)**, which is exactly why Apple's trash rule is PER-VOLUME: `~/.Trash` on the
  home volume, `.Trash-<uid>` at another volume's root. The Workspace's `WSTrash` keeps the Put Back record; `NSWorkspace`
  only moves the item, and both headers say which.

**SELECTORS AND NUMBERS THAT LOOK ALIKE AND ARE NOT.**

* **SELECTORS ARE TYPED IN THIS RUNTIME**: `[panel action] == @selector(takeColorFrom:)` answered NO while both printed
  `takeColorFrom:`. Compare `sel_getName`, or `sel_isEqual`.
* **`NSWritingDirectionNatural` IS `-1`**, not zero (which is left-to-right). A zero-filled ivar claims left-to-right for
  every object before a caller says anything — the same error `NSCell.h` records.
* **AN UNDECLARED COMMAND IS UNREACHABLE, NOT MERELY UNIMPLEMENTED.** A key binding names a SELECTOR; if no header declares
  it, no binding can name it and no chain can deliver it. That is why the fifty-seven `NSResponder` doors were declared and
  forwarded rather than left to "the class that will implement them".

**PROBES THAT PASS OR FAIL FOR THE WRONG REASON.**

* **A NIL CHECK WRITTEN AS `[[door] isEqual:nil]` FAILS WHETHER OR NOT THE DOOR IS RIGHT** — the message goes to `nil`.
  Compare `== nil`.
* **A TEST THAT ASSERTS `-respondsToSelector:` FOR FIFTY-SEVEN FORWARDERS RESTSATES THE CENSUS.** Register ONE C function
  for all of them with `class_addMethod` and record `_cmd`, so the claim is that the message ARRIVED.
* **A CHAIN-ROUTED MENU ROW NEEDS A KEY WINDOW AND A FIRST RESPONDER THAT ACCEPTS.** `-makeKeyWindow` is abandoned for a
  window that cannot become key (borderless ones cannot), `NSResponder -acceptsFirstResponder` is NO by default, and
  `-targetForAction:` starts at `[keyWindow firstResponder]`. The row's ITEM also keeps a NIL target by design: the target
  is resolved when the action is SENT. (Fixed in the workspace's `main_menu` test.)
* **INSTALLING A VIEW AS A WINDOW'S CONTENT VIEW MAKES IT THE FIRST RESPONDER**, so a text view handed back by
  `-setContentView:` is already `_editing`. "There is no caret here" is a claim about a view whose session you ended.
* **A FLAG WHOSE BIT HAS NO READER IS THE FAILURE MODE**, and the honest dispositions are three, not two: a reader, a
  refusal by name — or (the one `NSTextView` chose for `-setAllowedInputSourceLocales:`) STORE IT, ANSWER IT, AND SAY IN
  THE REFUSAL THAT NOTHING READS IT.

---

## 5. How to add a slice without breaking the instruments

Unchanged from `HANDOFF-4.md` §5 and followed every time. Restated because it is the whole method:

1. **Measure first.** `./tools/api-ledger missing … --library …` names the clusters, and a per-class recount names the
   selectors. Pick by reachable surface.
2. **Write the header declaration where Apple declares it** — and check WHICH `@end` closes the block. A protocol inserted
   inside an `@interface` fails with an error that names a missing `@end` two hundred lines away.
3. **Implement**, and make every deviation a comment at the door: what it does not do, and why. A refusal that answers its
   type's empty value beats a stub that looks implemented.
4. **Test the claim, not the code**: pixels for drawing, round trips for mappings, files on disk for file operations, a
   *negative* assertion wherever the positive one could pass for the wrong reason, and **an assertion on the exit status**.
5. **Let the gate fail** (`ctest -R appkit-api-census`), re-pin in the same commit, recompute its prose from the numbers.
6. **Run the whole suite** (`ctest --test-dir build -j4`, ~84 s) and check the exit status. Then run the WORKSPACE suite: it
   is 14 tests and it catches the cross-component regressions a component's own suite cannot.
7. **If you add a protocol door, make the sending class say which messages it sends** (`NSMenuDelegate`,
   `NSComboBoxDelegate`, `NSAlertDelegate`, `NSMatrixDelegate`, and now `NSBrowserDelegate`'s two contracts are the models).
8. **If a door has no reader, say so at the door** — or refuse it by name. Where a door has a reader, the probe drives the
   READER: `-insertionPointColor` is checked by the caret's pixels, the smart space by the string afterwards, the item
   model by the cell the browser made.
9. **A deep class lands in a CATEGORY FILE of its own** once its main file is over a couple of thousand lines:
   `NSTextViewAttributes.m`, `NSTextViewPasteboard.m` and now `NSTextViewEditing.m` are the pattern, and the private doors
   a category needs are declared in a `(Private)` category at the top of the new file.
10. **Commit in the component first, then advance the gitlink in `$AGORA_ROOT`** (`git -C "$A" add libagora-app`), with a
    message that says what moved in the censuses.

**AND TWO HOUSEKEEPING NOTES.** The tree is **LGPL-3.0-or-later** (library sources and headers) and **GPL-3.0-or-later**
(tests and the application) with `SPDX-FileCopyrightText`/`SPDX-License-Identifier` lines — **a new file must carry that
block**, and a sweep that adds C comments to `.cmake`, `.sh` or Python files breaks the gates. And `CMakeLists.txt`
**globs** `*.m` and `*.h`, so a new source file needs no build-file edit — but a new TEST needs its `add_executable` /
`add_test` / `ENVIRONMENT` triple in `tests/CMakeLists.txt`, and a test that forgets the environment line fails for want of
a library path rather than for want of the code.

---

## 6. Where to spend the next hour

**THE SIX DEEPEST CLASSES OF THIS COMPONENT ARE DONE.** What is left is the long tail, and it is many small commits rather
than four big slices — so the next session should pick a CLASS, not a subsystem.

1. **DONE in §12: `NSView` 221/221 — and with it both of the two longest tails.** The view's last doors were
   `-display`/`-displayIfNeeded`/`-displayRectIgnoringOpacity:` and `-lockFocus`/`-unlockFocus` (which `NSView.h` says are
   ABSENT ON PURPOSE — "draw me where I live"), `-isHiddenOrHasHiddenAncestor`, the rotation queries and setters,
   `-addSubview:positioned:relativeTo:`, `-setSubviews:`, `-autoscroll:`, the layer pair, the definition-lookup door and
   the NINE ruler-view client doors (which `NSTextView` already implements — check whether the base should forward them).
   The control's remainder is the cell class and value doors (`-cellClass`, `-setCellClass:`, `-selectedCell`,
   `-selectCell:`, `-calcSize`, `-updateCell:`), the formatter pair, `-attributedStringValue` and its setter, the six
   `-take…ValueFrom:` doors, the `-drawCell:` pair and `-validateEditing`. **EXPECT SEVERAL TO BE REFUSALS**: a layer, a
   display link, the tool-tip machinery and the focus-lock pair have no substrate here.
2. **`NSTableView` 20** — the grid's own tail: `-columnsInRect:`, the two `dragImageForRows…` doors (the local drag exists
   and these are its image half), the selection-by-extending pair, the column/row enumerators, `-drawsGrid`, the focused
   column, the indicator images and `-verticalMotionCanBeginDrag`. Mostly arithmetic over machinery that exists.
3. **DONE in §14: `NSDocument` 104/104 and `NSDocumentController` 51/51.** The async-saving family
   (`-autosaveDocumentWithDelegate:didAutosaveSelector:contextInfo:`, the two autosave URLs and the file type), the script
   commands (which would REFUSE like every other script door), the page-layout pair, and the `-presentError:` family
   (`-willPresentError:` is real; the modal form refuses). The autosave family needs a decision about WHERE a document's
   state lives before it is code.
4. **DONE in §13: `NSWindow` 261/261.** The style queries, the mutable mask, the represented-filename setter, the
   default button/backing/order/colour state and the local event queue's post/discard pair — and with it the fixed
   deferred-window drain. **`NSDocument`'s autosave family is the design question that remains.**
5. **DONE in §9 and §10: `NSSlider`/`NSSliderCell` 30/30 and 35/35, and `NSTableView` 123/123.** The slider slice
   found a flipped vertical scale drawn upside down; the table slice made the deprecated spellings and the three
   feedback drawings real. **The two deepest tails above are what is left of the big classes**; `NSDocument`'s
   autosave family is the one that needs a design decision before code.
6. **DONE in §15: `NSSavePanel` 47/47 and `NSWorkspace` 58/58.** The package flag is a real listing rule and the
   deprecated temp-file verb is `-openFile:`'s spelling. **There is no class tail left.**
7. **Then the absent classes in §2's order**: `NSImageView` is DONE in §16; the remaining editors are `NSDrawer`,
   `NSTokenField` and `NSTokenFieldCell`,
   the rules pair, and the controllers/bindings — **which are a DESIGN QUESTION before they are a slice**, because this tier
   has no KVO.
8. **And leave refused** (§A11 and this tree's record): OpenGL, QuickDraw, movies, the four typesetters, `NSCollectionView`
   (10.11), `NSFileWrapper` (Foundation's), `NSHelpManager`, speech, the input-manager era, the Dock contract, and
   `NSPersistentDocument`.

---

## 7. Things a reader should not have to rediscover

* **THE SEVENTEEN COMPLETE CLASSES ARE COMPLETE IN A SPECIFIC SENSE**: every selector Apple's 10.6 header declares for them is
  DECLARED and ANSWERED, and a refused door is an ANSWERED door (it prints its reason and returns its type's empty value).
  `-respondsToSelector:` is YES for a refusal. That is the plan's own disposition rule, and it is why the ledger and the
  refusal census have to be read TOGETHER.
* **THE LEDGER COUNTS CLASSES, NOT PROTOCOLS' MESSAGES.** See §3: an instrument that read protocol bodies would measure
  something the census has never measured, and until it exists the delegate surface is prose plus probes.
* **THE PLAN'S PRINTING DECISION WAS AMENDED, AND THE RECORD IS THE PLAN.** `COCOA-10.11-SURFACE-PLAN.md` §4.4/§4.5 said
  "physical printers refused"; both now say implemented, with the transport as a seam. If a later session finds the plan
  and a handoff disagreeing about printing, the plan is the record.
* **THE TWO SEAMS OF THIS COMPONENT'S SHAPE ARE `platform/AGWindowServer.h` AND `platform/AGPrintService.h`**: a narrow C
  interface, a real implementation behind a `#define`, a null one otherwise. A third (`AGKeyboard`) is the input map.
  Launch Services and Icon Services are separate COMPONENTS, consumed through `build-prefix`.
* **"RUNNING" MEANS "HAS A WINDOW", STATED AT THE DOOR.** There is no session and no `launchd`, so the window server's
  connections are liveness: an application that closed every window but has not quit is NOT listed, which the Mac would
  list. `NSWorkspace.h` says so, and `NSRunningApplication.h` carries the rest of the same list.
* **THE TRASH RULE IS PER-VOLUME, AND THE WORKSPACE OWNS THE RECORD.** `NSWorkspace` moves the item (`~/.Trash`, or
  `.Trash-<uid>` at another volume's root, with a copy fallback); the Workspace's `WSTrash` additionally writes the Put
  Back record and owns the empty. Two implementations of one RULE, and both headers say which part is whose.
* **A `NSControl` WITH NO CELL MUST KEEP ITS OWN TARGET/ACTION.** `NSControl` forwards the pair to `_cell` in this tree, so
  a cell-less subclass answers `nil` and sends nothing. `NSBrowser` is the one that paid for it.
* **`NSWindow` SENDS `-windowWillReturnUndoManager:` NOW** (`-[NSWindow undoManager]` asks its delegate), which is what
  puts an undo manager in the responder chain for a document's text view. Before §10 of `HANDOFF-4` the chain ended at the
  application with `nil`.
* **THE BROWSER ADVERTISES THE 10.6 ITEM CONTRACT AND FALLS BACK TO THE NEXXT CELL ONE.** `-browser:numberOfChildrenOfItem:`
  is the test for which model a delegate speaks; the item walk starts at `nil`, retains nothing, and a delegate implements
  ONE contract (the one allowed overlap is a styling `-browser:willDisplayCell:atRow:column:`).
* **THE SUITE IS 161 TESTS IN ABOUT 87 SECONDS, AND `ctest --test-dir build -j4` IS THE GATE.** The exit status is the
  witness, not the tail of the output. The workspace's suite is 14 tests and belongs in the same gate run.

---

## 8. How this file is kept

**THE RUNNING RECORD GOES HERE, AS NUMBERED SECTIONS AFTER THIS ONE.** The earlier handoffs did the same: `HANDOFF-2.md`
§13–§20, `HANDOFF-3.md` §8–§14 and `HANDOFF-4.md` §9–§20 are the sessions that picked those files up, one numbered section
per slice, each recording what landed, the numbers before and after, the traps the slice paid for, and where the next hour
went. A session that lands a slice should:

1. Append a `## 9. …` (then `## 10. …`) section here with its commit, its census movement and its traps.
2. Re-pin `tests/api-10.6-census.txt` and/or `tests/refusal_census.txt` in the same commit, recomputing the summary lines
   from `./tools/api-ledger census` — and run the PER-CLASS recount, which is what catches a silently deleted declaration
   and a door counted complete one short.
3. Update the component `README.md` with a section for the slice and `PROVENANCE.md` with what a reader needs to know —
   both are read by people who will never open this file.
4. Leave §1–§7 above ALONE unless a slice changes a number in them; when it does, change that number and say in the new
   section that it moved. A handoff that quietly drifts is the thing these files exist to prevent.

---

## 9. The slider pair complete: ticks as values, a title as a cell, and a flipped scale that was upside down

**Commit `182bcd4`.** `NSSlider` and `NSSliderCell` are COMPLETE for the era — 30 of 30 and 35 of 35 — the seventh and
eighth classes to finish, and the change is 35 selector rows (4345 -> 4380 present, 160 -> 125 missing), 35 declarations
(4874 -> 4909), and two more classes at complete coverage (the recount below says 119 -> 121). The suite is 155 tests
(about 88 s), the refusal census went 376 -> 382, the owed census stayed 19, and `tests/slider_title_ticks.m` is the new
probe (52 checks). The workspace's 14 tests were run too.

**THE TICKS ARE A VALUE FAMILY NOW, NOT ONLY INK.** The marks were drawn three slices ago and a caller could not ask
what they were: `-tickMarkValueAtIndex:` is `min + (max-min)·n/(n-1)` with both ends included, `-closestTickMarkValueToValue:`
is the nearest mark, `-rectOfTickMarkAtIndex:` and `-indexOfTickMarkAtPoint:` place and hit-test them, and
`-allowsTickMarkValuesOnly` reads the nearest-mark arithmetic in `-setDoubleValue:` — the ONE door every value goes
through — so the standing value snaps when the flag is turned on, every later value snaps, and moving an end re-clamps and
re-snaps. With no marks, `-closestTickMarkValueToValue:` answers the value itself; with one mark, every value is the
minimum. Apple documents an `NSRangeException` for an out-of-range index; this tree has none in use, so the door answers
the minimum (the type's empty value) and says so at the door.

**THE PUBLIC MARK RECTANGLE FOUND AN OLD INK BUG.** The vertical mark's along-track position used the unflipped formula
for both y directions, so a FLIPPED vertical slider drew its scale upside down — the min mark at the top while its knob's
minimum was at the bottom. The probe matches every mark's centre to the knob's centre at that mark's value in both
orientations and both flips, and the one helper `-cg_tickRectAtIndex:inFrame:flipped:` is now what the public door and the
ink both call, so they cannot disagree again. `-trackRect` is the wider rectangle the knob TRAVELS in (the cell frame
with the title's band removed), not the four-point bar the ink fills; the SDK's own comment says its storage is "only
valid while tracking the mouse", and this tier can answer it from the control view at any time.

**THE TITLE IS A CELL, AND THE BAND IS TAKEN OFF THE TOP.** The default is a private `NSCell` subclass with a text colour
(the base cell has a font and an alignment but no colour); `-titleFont`/`-titleColor` are the conveniences over it, and
`-setTitle:` mirrors the label into it. `-drawWithFrame:inView:` removes the band before the track and knob are placed —
so a titled knob sits lower and an UNTITLED slider's geometry is exactly what it was — then draws the words last. A frame
too short for both keeps four points for the track rather than letting the label eat it. The probe counts the title's
pixels in the band and checks the knob's centre moved down by the band.

**THE TWO NO-ARGUMENT INK DOORS HAVE A FRAME NOW.** `-drawKnob` and the deprecated `-knobRectFlipped:` take theirs from
`-controlView` and REFUSE BY NAME when there is none, as does `-trackRect`; `-rectOfTickMarkAtIndex:` and
`-indexOfTickMarkAtPoint:` do the same, because a point or a mark has no coordinate space without a view. `-image` is
Apple's BACKGROUND image — the SDK's own parameter name is `backgroundImage` — so it is not a refused face: the cell draws
it under the track, the knob and the title, and the probe checks a corner pixel that is red while it is set and white
after it is removed. `-setImage:` on the CELL also marks the control for redisplay, which the base cell's storage does not.

**TRAPS THIS SLICE PAID FOR.**

* **A PROBE THAT COUNTS "DARK" PIXELS CALLS A RED TITLE INVISIBLE.** The title's colour is a caller's choice and the probe
  sets it red to prove `-setTitleColor:` has a reader; the first `ink_in` asked `redComponent < 0.72`, so every red glyph
  was "background". The check is now "not the white the probe filled with", which is what it always meant. The debugging
  detour also produced a false lead — `[NSFont systemFontOfSize:]` was suspected of answering nil — which a printed
  pointer and a measured `sizeWithAttributes:` dismissed. **Print the value before blaming the subsystem.**
* **A REFUSAL CAN COST TWO CENSUS SITES.** `-trackRect` has both the `APPKIT-REFUSE:` comment and the `fn_refuse_window`
  call, and the needle counts both (the helper's definition and each call are the same convention). Five new doors moved
  the census by six; the diff says why, which is the rule.
* **A PUBLIC GEOMETRY DOOR IS A SECOND READER FOR ARITHMETIC THAT HAD ONE.** The flipped vertical tick formula was
  unreachable and wrong; the moment a caller could ask for the rectangle, it became a test that could fail. The same
  shape is waiting wherever ink has arithmetic no door exposes.
* **THE HANDOFF'S "120 of 129 COMPLETE" WAS ONE HIGH.** Recomputing complete coverage from the OLD pin's `sel:` lines gives
  119 — `NSSlider` and `NSSliderCell` were both incomplete and the other ten are `NSControl`, `NSDocument`,
  `NSDocumentController`, `NSSavePanel`, `NSTableView`, `NSView`, `NSWindow` and `NSWorkspace`. The pair makes 121. The
  census file's prose now carries the correction at the number, and this file's §2 does too. **A number in a handoff is a
  claim; the recount is the measurement.**

**WHERE THE NEXT HOUR GOES.** The two longest tails are still `NSView` 28 and `NSControl` 28, and `NSTableView` 20 is the
next class whose doors are mostly arithmetic over machinery that exists (its grid, the drag image, the column/row
enumerators). `NSDocument` 19 needs the decision about where autosave state lives. `NSSavePanel`'s three are a flag and
two lines. §6's ordering is otherwise unchanged.

---

## 10. `NSTableView` complete: deprecated spellings, a drag image, and a focus ring around the selected cell

**Commit `b0bd73c`.** `NSTableView` is COMPLETE for the era — 123 of 123, the ninth class to finish — and the change is
20 selector rows (4380 -> 4400 present, 125 -> 105 missing), 20 declarations (4909 -> 4929), and one more class at
complete coverage (121 -> 122). The suite is 156 tests (about 88 s), the refusal census stayed 382 (this slice added no
refusal), the owed census stayed 19, and `tests/table_tail.m` is the new probe (34 checks). The workspace's 14 tests
were run too.

**THE DEPRECATED DOORS ARE SPELLINGS OF STATE THE TABLE ALREADY HAD, WHICH IS WHY THE MOVEMENT IS LARGE AND THE CODE IS
SMALL.** `-drawsGrid` reads and writes the grid style mask. `-autoresizesAllColumnsToFit` maps YES to Uniform and NO to
LastColumnOnly, exactly as the SDK's compatibility note says — and that mapping made the autoresizing styles worth
IMPLEMENTING, so `-tile` now applies all five: Uniform shares the difference proportionally with a clamp-and-re-share
loop, LastColumnOnly gives it all to the last column, and the sequential pair walks from one end. `_cgAutoresizingColumns`
is the re-entry guard, because `NSTableColumn -setWidth:` calls `-tile`. `-columnsInRect:` is the contiguous range
spelling of `-columnIndexesInRect:`; the single-index selection pair goes through the index-set doors; the two
enumerators answer an array of `NSNumber`s taken from the set.

**THE DRAWINGS ARE THE READERS, AND EACH ONE IS MEASURED.** `-focusedColumn` draws `keyboardFocusIndicatorColor` around
the SELECTED row's cell in that column (the SDK's own description, not a whole-column ring). The header draws
`-indicatorImageInTableColumn:` at its right edge, in the same zone as the sort mark. The destination feedback style
draws Regular's line, SourceList's inset line or DropOn plate, or None's nothing; a source-list selection style chooses
SourceList for the caller. `-verticalMotionCanBeginDrag` is a gate in the mouse-drag threshold, measured through a table
subclass whose drag entry point is a counter: with NO a vertical motion does not begin a drag, a horizontal one does, and
with YES either does.

**THE TWO DRAG-IMAGE DOORS ARE ONE SNAPSHOT.** The union of the named rows' cells over the named columns (or every
column when none is named) is captured through `-cacheDisplayInRect:toBitmapImageRep:`, so the image carries the
selection plate and the grid. The deprecated array spelling converts its `NSNumber`s and forwards. The offset is in/out
and stays at Apple's zero (centred under the mouse). The table's own mouse loop now calls the same helper, so the drag
image and the cursor cannot disagree.

**`-performClickOnCellAtColumn:row:` IS THE CELL'S CLICK, NOT THE TABLE'S ACTION.** The prepared cell is copied, clicked
through `-performClick:` (or `-performClickWithFrame:inView:` for a pop-up cell), and its object value written back to
the data source when the click changed it. Apple's door does no enabled-check; neither does this one.

**TRAPS THIS SLICE PAID FOR.**

* **THE SIGNATURES WERE IN THE SDK, AND TWO WERE GUESSED WRONG.** `-columnsInRect:` returns an `NSRange`, not an
  `NSIndexSet`, and `-dragImageForRows:` takes an `NSArray` of row numbers, not an index set. Both are deprecated, which
  is exactly why the newer spelling is the one a reader remembers. **Open the header before designing the door.**
* **`union` IS A C KEYWORD.** The drag-image helper's local rectangle was named `union`; the compiler's "declaration of
  anonymous union must be a definition" is the whole diagnosis. It is `unionBox` now.
* **A PROBE'S NEGATIVE CASE CAN PASS FOR THE WRONG REASON, AGAIN.** The grid-off rendering still had 185 pixels of the
  grid's grey, because antialiased glyphs pass through it; the first check wanted zero. The claim is now a structural
  ratio (2313 against 185), the same shape as §9's red-title trap. **"No ink" is rarely the right negative; "much less
  ink" is.**
* **`NSCell -copy` DOES NOT CARRY A NON-RETAINED TARGET.** This tree's copy archives the cell, and the archive has the
  action but not the target, so a click on the copy would send nothing. `-performClickOnCellAtColumn:row:` re-attaches
  the prepared cell's target/action to the copy, and the probe's `NSButtonCell` proves the action arrives.
* **`-setWidth:` CALLS `-tile`, AND `-tile` AUTORESIZES.** Without a re-entry guard the first style-driven resize
  recurses through itself. The nested `tile` still recomputes the frame; it simply does not resize again.

**WHERE THE NEXT HOUR GOES.** `NSView` 28 and `NSControl` 28 are the two longest tails, then `NSDocument` 19 (whose
autosave family needs a decision about where document state lives), `NSWindow` 18, `NSDocumentController` 8,
`NSSavePanel` 3 and `NSWorkspace` 1 (the instrument quirk). §6's ordering is otherwise unchanged.

---

## 11. `NSControl` complete: the cell factory, the one-cell selection, and validate-editing

**Commit `1c4be0a`.** `NSControl` is COMPLETE for the era — 65 of 65, the tenth class to finish — and the change is 28
selector rows (4400 -> 4428 present, 105 -> 77 missing), 28 declarations (4929 -> 4957), and one more class at complete
coverage (122 -> 123). The suite is 157 tests (about 88 s), the refusal census stayed 382 (no refusal was added), the
owed census stayed 19, and `tests/control_tail.m` is the new probe (32 checks). The workspace's 14 tests were run too.

**A CONTROL IS A VIEW WITH ONE CELL, SO THE TAIL IS MOSTLY FORWARDS.** The six `-take…ValueFrom:` doors go through the
cell's own `-take…` doors and redisplay; `-formatter`, `-setFloatingPointFormat:left:right:`,
`-attributedStringValue`, `-baseWritingDirection` and `-refusesFirstResponder` are the cell's state. The class factory
is the one new static: `+cellClass` answers `NSCell` until `+setCellClass:` names another, and the header says that a
subclass which makes a specific cell should override the getter rather than mutate the process-wide default. The
one-cell selection is `-selectedCell`/`-selectedTag`/`-selectCell:`; `-selectedCell` is the cell even when it is off,
and `-selectedTag` is -1 only when there is no cell at all.

**THE FOUR PAINT/INVALIDATE DOORS ARE EFFECTS AND THE PROBE MEASURES THEM.** `-drawCell:` and `-drawCellInside:` paint
the named cell only when it IS this control's, so a stale pointer cannot paint over a replaced cell; `-updateCell:`,
`-updateCellInside:` and the no-argument `-setNeedsDisplay` are invalidation; and `-calcSize` asks the cell's
`-calcDrawInfo:` for the control's real bounds. The probe uses a counting cell for all four.

**`-validateEditing` LANDS THE RUNNING EDITOR'S STRING IN THE CELL WITHOUT ENDING THE SESSION.** The editor owns the
string while it runs, so the cell is written through its own setter — which also tells the editor the value it now
shows — and ending remains the editor's or `-abortEditing`'s job. The probe opens a real field editor through
`-selectText:`, changes its string, validates, and checks both the new value and that the editor is still current.

**TRAPS THIS SLICE PAID FOR.**

* **THE FORMATTER SUPERSEDES THE DEPRECATED FLOAT FORMAT, AND THE FIRST PROBE CAUGHT IT BY BEING WRONG.** With an
  `NSNumberFormatter` attached, the value read "3.142" rather than "3.14": the float format was set, but the cell's own
  documented precedence lets the formatter win. The probe now asserts BOTH sides — with the formatter `3.142`, after
  `-setFormatter:nil` the float format's `3.14` — so the deprecated door's reader is visible rather than masked.
* **`+setCellClass:` IS PROCESS-WIDE, AND THAT IS A DELIBERATE TRANSCRIPTION.** Apple's base class has one factory
  class; a subclass that builds a specific cell overrides `+cellClass`. This tier's subclasses do not override it yet,
  which is stated at the door rather than papered over with per-class maps.
* **`-selectedCell` IS THE CELL, NOT "THE SELECTED ONE".** A single-cell control has no selection to be empty in the
  matrix sense; `-selectedTag` is -1 only when the control has no cell, and a cell whose state is off is still the
  answer. The GNUstep implementation and Apple's one-cell prose agree.
* **A CLASS METHOD NEEDS A CLASS-LEVEL STORE.** The factory is a file static (`sCellClass`) rather than an ivar, and
  the probe restores `[NSCell class]` after using it so a later case in the same process starts where the era starts.

**WHERE THE NEXT HOUR GOES.** `NSView` 28 is now the longest tail by a wide margin — the display/focus-lock pair
(absent on purpose), the rotation queries, `-addSubview:positioned:relativeTo:`, `-setSubviews:`, `-autoscroll:`, the
layer pair, and the nine ruler-view client doors that `NSTextView` already implements. Then `NSDocument` 19,
`NSWindow` 18, `NSDocumentController` 8, `NSSavePanel` 3 and `NSWorkspace` 1 (the instrument quirk). §6's ordering is
otherwise unchanged.

---

## 12. `NSView` complete: forced display, one rotation record, and the ruler client defaults

**Commit `db418e3`.** `NSView` is COMPLETE for the era — 221 of 221, the eleventh class to finish — and the change is 28
selector rows (4428 -> 4456 present, 77 -> 49 missing), 26 declarations (4957 -> 4983), and one more class at complete
coverage (123 -> 124). The suite is 158 tests (about 82 s), the refusal census went 382 -> 386 (four named refusals),
the owed census stayed 19, and `tests/view_tail.m` is the new probe (33 checks). The workspace's 14 tests were run too.

**THE DISPLAY FAMILY'S FORCED FORMS ARE THE `…InRect:` DOORS WITH THE BOUNDS SUPPLIED.** `-display` paints the tree now
and clears the damage; `-displayIfNeeded` paints only the invalidated region; `-displayRectIgnoringOpacity:` is the
context form with a nil context. The two-argument form's selector was `…context:` in this tree and is Apple's
`…inContext:` now, with the internal callers and `NSPrintOperation` updated.

**ONE STORED ROTATION, TWO SPELLINGS, AND AN IDENTITY SQUARE.** `-setFrameRotation:`/`-setBoundsRotation:` write the
record `-rotateByAngle:` already keeps; both getters report it; `-isRotatedFromBase` is that record plus the frame-centre
rotation, and `-isRotatedOrScaledFromBase` adds a unit square that is no longer 1,1. The identity square is set in both
initialisers now — a zero there made the scaled query true for every fresh view, which the probe would have caught as a
false positive rather than a false negative.

**THE SUBVIEW LIST RUNS THE NOTICES.** `-addSubview:positioned:relativeTo:` is `-addSubview:` plus a reorder; a relative
view that is not a child is treated as nil, which means top for Above and bottom for Below. `-setSubviews:` removes the
old list through `-removeFromSuperview` and adds the new one through `-addSubview:`, so the window link and both move
notices run exactly as they do for one view.

**FOUR REFUSALS, EACH NAMING ITS SUBSTRATE.** `-lockFocus`/`-unlockFocus` need a lockable per-view graphics-state
stack; `-setLayer:` needs a CALayer tree; and the range form of the definition look-up needs the same Dictionary
substrate the at-point form already refuses for.

**THE RULER CLIENT DEFAULTS ARE DECLARED ON `NSView` WHERE APPLE DECLARES THEM.** The nine doors allow every add, move
and remove, keep the location asked for, and do nothing for the notice doors — the same behaviour the ruler's
`-respondsToSelector:` guards assumed when nobody implemented anything, now checkable and overridable. `-setClientView:`
tells the OLD client through `-rulerView:willSetClientView:` before the link changes; that door had no sender before.

**TRAPS THIS SLICE PAID FOR.**

* **THE LAST ROW WAS A SELECTOR SPELLING, NOT A MISSING BEHAVIOUR.** The tree's `-displayRectIgnoringOpacity:context:`
  was implemented and called internally, but Apple's selector is `…inContext:`, so the ledger counted the door missing
  while the behaviour was there. Renaming it (and the internal callers) closed the class. **A public selector is part of
  the surface; an internal spelling is not the same door.**
* **THE RULER CLIENT DOORS WERE IN A PRIVATE PROTOCOL, NOT THE HEADER.** `NSRulerView.m` declared them as
  `AGRulerClient` so its sends type-checked, but the manifest attributes them to `NSView`; nothing counted until the
  category reached `NSRulerView.h`. The private protocol stays for the typed sends; the header category is the surface.
* **A ZERO UNIT SQUARE IS A LIE ABOUT SCALE.** `_cg_unitSquareSize` was nought until something scaled it, so a fresh
  view answered "scaled from base". Both initialisers now set 1,1 before any query can run.
* **THE SUBVIEW LIST HAS TO GO THROUGH THE DOORS.** Assigning the array directly would skip the window link and both
  move notices; `-setSubviews:` removes and adds, which is slower and correct.
* **AUTOSCROLL IS `-scrollRectToVisible:` WITH A ZERO-SIZE RECTANGLE.** One step per event, no invented speed, and it
  answers NO with no clip view — which is what a drag loop asks.

**WHERE THE NEXT HOUR GOES.** Five classes still carry debt: `NSDocument` 19 (the autosave family needs a decision about
where document state lives), `NSWindow` 18, `NSDocumentController` 8, `NSSavePanel` 3, and `NSWorkspace` 1 (the
instrument quirk). `NSWindow`'s list is mostly one-liners over the style mask and is the natural next slice; `NSDocument`
is the one that is a design question first.

---

## 13. `NSWindow` complete: a mutable style mask, the screen form, and a queue a deferred window can drain

**Commit `1d1d7f4`.** `NSWindow` is COMPLETE for the era — 261 of 261, the twelfth class to finish — and the change is
18 selector rows (4456 -> 4474 present, 49 -> 31 missing), 18 declarations (4983 -> 5001), and one more class at
complete coverage (124 -> 125). The suite is 159 tests (about 83 s), the refusal census stayed 386, the owed census
stayed 19, and `tests/window_tail.m` is the new probe (33 checks). The workspace's 14 tests were run too.

**THE STYLE MASK IS MUTABLE AND PRESERVES THE CONTENT RECT.** `-setStyleMask:` measures the content rectangle under the
old mask, changes the mask, and sets the frame that holds that content under the new one — so adding a title bar grows
the frame instead of shrinking the document. The three `-isResizable`/`-isMiniaturizable`/`-isZoomable` spellings are
aliases of the older getters and answer the same style bits.

**THE REPRESENTED FILENAME'S TWO SETTERS DIFFER, AND BOTH NOW EXIST.** `-setRepresentedFilename:` stores the path and
leaves the title alone; `-setTitleWithRepresentedFilename:` makes the file's name the title. The default button cell, the
preferred backing location (the ACTUAL location stays main memory), the ordered index and the colour space round-trip;
`-deviceDescription` is the screen's description, `-userSpaceScaleFactor` is 1.0, and the spaces flag is stored with the
one-space truth stated at the door. The screen initialiser makes the designated frame, and
`-setFrame:display:animate:` lands the geometry directly with no second placement path.

**THE EVENT QUEUE'S TWO WRITERS, AND THE DRAIN BUG THEY EXPOSED.** `-postEvent:atStart:` orders head/tail and adjusts
the process-wide queued count; `-discardEventsMatchingMask:beforeEvent:` removes the matching events before the named
one (identity) or all matching when the event is nil. The probe then found that `-nextEventMatchingMask:` returned nil
at the top when `_agwindow` was NULL — BEFORE looking at the local queue — so a deferred window's posted events were
unreachable. The drain now serves the queue first and returns nil only when there is nothing queued and nothing to wait
on; that is a behaviour change for every caller that posts to an unordered window.

**TRAPS THIS SLICE PAID FOR.**

* **A DEFERRED WINDOW'S QUEUE IS STILL A QUEUE.** The guard that made server-less windows answer nil was right about
  the WAIT and wrong about the POP: `-postEvent:` is public and works before `-orderFront:`, and Apple's window queues
  events for a window that is not on screen. The probe caught it because it posts and drains in the same case.
* **THE TWO REPRESENTED-FILENAME DOORS ARE NOT ONE DOOR.** The tree had the title-changing form; the setter that only
  remembers the path was missing, and making either call the other would have changed a documented behaviour in both
  directions.
* **`-setStyleMask:` IS GEOMETRY, NOT A STORE.** Writing `_styleMask` alone would leave the frame holding the old
  chrome's worth of content; measure the content, change the mask, then set the frame that keeps it.
* **THE `is` ALIASES ARE REAL ROWS.** `-resizable` and `-isResizable` are two manifest rows for one style bit; the
  older spelling is the implementation and the newer is the alias, which is the least surprising of the two orders.

**WHERE THE NEXT HOUR GOES.** Four classes remain: `NSDocument` 19 (the autosave family is a design decision about where
document state lives, not a list of one-liners), `NSDocumentController` 8, `NSSavePanel` 3 (a flag and two lines), and
`NSWorkspace` 1 (the `openTempFile:` instrument quirk that is off by construction). `NSSavePanel` and
`NSDocumentController` are the small clean slices; `NSDocument` is the one to decide before typing.

---

## 14. The document pair complete: autosave as a separate file, an asynchronous close review, and an error chain that ends in an alert

**Commit `47b090e`.** `NSDocument` and `NSDocumentController` are COMPLETE for the era — 104 of 104 and 51 of 51, the
thirteenth and fourteenth classes to finish — and the change is 27 selector rows (4474 -> 4501 present, 31 -> 4
missing), 27 declarations (5001 -> 5028), and two more classes at complete coverage (125 -> 127). The suite is 160 tests
(about 90 s), the refusal census went 386 -> 387 (three document scripting refusals in, two stale responder refusals
out), the owed census stayed 19, and `tests/document_tail.m` is the new probe (41 checks). The workspace's 14 tests
were run too. **Only `NSSavePanel` (3) and `NSWorkspace` (1, the instrument quirk) still carry debt.**

**AUTOSAVE IS A SEPARATE FILE, AND THE SAVE PATH NOW KNOWS IT.** `NSAutosaveOperation` sets
`-autosavedContentsFileURL` and `NSChangeAutosaved`; it never touches `fileURL`, `fileType`, the modification date or
the recent list. `-initForURL:withContentsOfURL:` records the contents URL; a real save, a revert or a close deletes the
obsolete copy. `-hasUnautosavedChanges` is a history flag independent of `-isDocumentEdited` (NO after
Cleared/Autosaved, YES after Done/Undone/Redone, unaffected by ReadOtherContents). The controller's
`-autosavingDelay` (default 0) drives a timer that autosaves only documents with that flag and a non-nil
`-autosavingFileType`.

**THE LOCATION IS `~/Library/Autosave`, WITH A TEMP FALLBACK AND A PLIST REGISTRY.** The files are named
`Agora-<process>-<index>.<ext>`; the registry records `documentURL` and `contentsURL`; `NSApplication -finishLaunching`
asks a fresh controller to reopen the entries before the launch delegate runs, and a stale record is dropped. This is
the crash-time reopen the SDK's `-setAutosavedContentsFileURL:` prose promises, not just a second file.

**CLOSE IS THE ASYNCHRONOUS REVIEW APPLE DOCUMENTS.** Save/Cancel/Don't Save is a sheet when there is a window and the
app is running, and application-modal otherwise; the delegate is messaged after the decision and any save. The context
objects own themselves for the duration of a sheet. `NSWindow -performClose:` now asks
`-shouldCloseWindowController:…` first, and `-closeAllDocuments…` walks the documents, closes the yeses and stops at the
first no. **The existing close-all test was corrected: an unedited document before a refusal has already closed, because
the walk is not a transaction.**

**THE ERROR CHAIN ENDS IN AN ALERT NOW.** `NSDocument` and `NSDocumentController` implement `-willPresentError:` and
both `-presentError:` forms; the document forwards to the controller, which forwards to the application.
`NSResponder`'s two error refusals — whose reason was "NSAlert is not in this tier" — are replaced by real `NSAlert`
presentation, so the refusal census lost two sites. The modal form uses a sheet when a window is available; the
caller's `didPresentSelector` gets `didRecover:NO` because this tier has no recovery delegate.

**THE REST IS SMALL AND HONEST.** `-preparePageLayout:`/`-runPageLayout:` reuse the existing panel and its callback;
`-lastComponentOfFileName` is a stored display/save-name override that `-displayName` prefers; the two save-panel
answers are recorded only after a panel runs; and the scripting trio refuses by name because there is no
`NSScriptCommand` in this tree.

**TRAPS THIS SLICE PAID FOR.**

* **`NSTemporaryDirectory()` ANSWERS `/System/Temporary Files/`, WHICH NEED NOT EXIST OR BE WRITABLE.** The first probe's
  autosave directory was created under it and every write failed; the test now uses `/tmp`. The controller's fallback
  chain (`~/Library/Autosave`, then `NSTemporaryDirectory()`, then `/tmp`) is the production version of the same lesson.
* **`-fileNameExtensionForType:saveOperation:` WAS DECLARED AND RETURNED NIL.** The base class never asked the
  controller's type table, so the autosave name had no extension and the save-panel extension list fell back to the
  document's type only. It now uses the controller's `-fileExtensionsFromType:`, which is what the SDK's prose says
  the 10.4-compatibility path does.
* **`NSSearchPathForDirectoriesInDomains` IS A NAMED REFUSAL IN THIS FOUNDATION.** `~/Library` is built from
  `NSHomeDirectory()` and created; `NSColorList` already establishes that precedent for user state.
* **A STALE REFUSAL IS A BUG WITH A SHELF LIFE.** `NSResponder -presentError:` still said NSAlert did not exist; it has
  existed for slices. The document slice could not honestly forward errors through a chain that ended in that message,
  so the two refusals became presentations.
* **A CLOSE WALK IS NOT A TRANSACTION.** `-closeAllDocuments…` asks each document in order; an unedited document before
  a refusal has already closed. The old test asserted "nothing was closed", which was the old refuse-everything rule.
* **AN ASYNCHRONOUS CONTEXT HAS TO OWN ITSELF.** A sheet does not retain a `void *contextInfo`; the close and error
  contexts retain the delegate and release themselves when the answer arrives.

**WHERE THE NEXT HOUR GOES.** `NSSavePanel`'s three (`-isExpanded`, `-treatsFilePackagesAsDirectories:` and its getter)
are a flag and two lines, and `NSWorkspace`'s one is the `openTempFile:` manifest quirk that is off by construction.
After those, the debt list is empty and the next work is the absent classes: `NSImageView` is the most useful, the
controllers are a KVO design question, and the plan's §A11 refusals stay refused.

---

## 15. The last two classes: a package is a directory only when told so, and the temp-file verb

**Commit `e199a54`.** `NSSavePanel` and `NSWorkspace` are COMPLETE for the era — 47 of 47 and 58 of 58, the fifteenth and
sixteenth classes to finish — and the change is 4 selector rows (4501 -> 4505 present, 4 -> 0 missing) and 4
declarations (5028 -> 5032). The suite is 160 tests (about 87 s), the refusal census stayed 387 (no refusal was added),
the owed census stayed 19, and the existing `save_panel` and `workspace_fileops` probes were extended rather than
duplicated. The workspace's 14 tests were run too.

**AND THAT CLOSES THE SURFACE THIS TREE CARRIES: 4505 of 4505 selectors over all 129 classes with a surface, every one
at COMPLETE coverage.** The 37 ABSENT classes are still absent for the reasons §2 groups them under; the class count is
131 of 168, and their selectors are not in the offered total. This is 100% of the manifest's surface OVER THIS TREE'S
CLASSES, not 100% of the 10.6 AppKit.

**THE SAVE PANEL'S PACKAGE FLAG IS A REAL LISTING RULE.** `-isExpanded` answers NO because this tier has no expanded
layout. `-treatsFilePackagesAsDirectories` now decides how a package is listed: with NO (the default) a directory whose
extension is `.app`, `.bundle`, `.framework`, `.plugin` or `.kext` AND which has a `Contents` inside is listed with the
files and cannot be entered; with YES it gains the directory slash and is navigable like any other directory, including
through the typed-path accept. The probe creates `Bundle.app/Contents` and checks both list positions.

**THE WORKSPACE'S DEPRECATED VERB IS A SPELLING OF `-openFile:`.** The hyphen-less `-openTempFile` CREATES a temporary
file and answers its path (the door this tree used); the 10.6 header's `-openTempFile:` takes an existing path and
OPENS it, and that is `-openFile:` through the Launch Services seam. The probe checks the nil and missing-file answers,
which are the two an offscreen harness can measure without launching a handler.

**TRAPS THIS SLICE PAID FOR.**

* **`-isFilePackageAtPath:` IS STRICTER THAN THE EXTENSION.** The first probe used `Bundle.agpackage` and the panel kept
  listing it as a directory; the workspace's own rule requires a KNOWN extension (`.app`, `.bundle`, `.framework`,
  `.plugin`, `.kext`) **and** a `Contents` child. The probe now builds `Bundle.app/Contents`, which is what the door's
  own comment says a package is.
* **"100% OF SELECTORS" IS 100% OF THE MANIFEST'S SURFACE OVER PRESENT CLASSES.** The four absent classes' selectors are
  not offered; the 37 absent classes are a separate number and stay in §2. A future reader should not read this as
  "the 10.6 AppKit is finished".
* **`-isExpanded` IS A GETTER WITH NO SETTER IN THIS ERA'S MANIFEST.** The truthful answer is NO; there is no expanded
  layout to set, and inventing a stored flag would be a bit nothing reads.
* **A FLAG'S READER SHOULD BE A LISTING, NOT A GETTER.** The package flag changes which column an entry lands in and
  whether it can be entered; the probe checks the slash, not just the bit.

**WHERE THE NEXT HOUR GOES.** There is no class tail left. The remaining work is the 37 absent classes in §2's order —
`NSImageView` is the most useful, the rules pair is a view over existing controls, and the controllers/bindings are a
KVO design question before they are a slice — plus the plan's §A11 refusals, which stay refused. The instruments are
green: 160 tests, 4505/4505 selectors over 129 classes, 387 refusal sites, 19 owed notes.

---

## 16. `NSImageView` arrives: the cell's face, two edit gates, and an encoder the image class owns

**Commit `99baeca`.** `NSImageView` is present and COMPLETE at 14 of 14 — the first class from the absent list to arrive,
and the seventeenth complete class. The change takes the class count 131 -> 132 (79% of 168), the offered selectors
4505 -> 4519, and the complete-coverage count 129 -> 130; the missing count is still 0. The suite is 161 tests, the
refusal census stayed 387, the owed census stayed 19, and `tests/image_view.m` is the new probe (22 checks). The
workspace's 14 tests were run too.

**THE VIEW IS THE CELL'S FACE AND THE TWO EDIT FLAGS.** The image, `-imageAlignment`, `-imageScaling` and
`-imageFrameStyle` are `NSImageCell`'s and the view forwards each with a redisplay; `-isEditable` is the cell's flag;
`-allowsCutCopyPaste` and `-animates` are the view's own storage. `+cellClass` answers `NSImageCell`, and the designated
initialiser makes one.

**THE ALIGNMENT FORWARD IS MEASURED IN INK.** The probe renders a 20-point red image at `NSImageAlignLeft` and
`NSImageAlignRight` and reads the red box's x-range; a value check alone would pass a setting that never reached the
drawing.

**THE COMMANDS ARE GATED BY BOTH FLAGS, AND THE ENCODER DECIDES THE REST.** `-paste:` with `-allowsCutCopyPaste` and
`-isEditable` on reads the pasteboard's PNG through `NSImage -initWithPasteboard:` and sets the image; `-delete:` clears
it. `-copy:`/`-cut:` reach `NSImage -TIFFRepresentation`, which refuses by name because this tree's CoreGraphics has no
`CGImageDestination`, so cut leaves the image in place rather than clearing a field it could not copy. `-animates` is
stored and answered, and the header says outright that no timer is made: this tier's `NSImage` has no animation clock.

**AND THE TYPE NAME IS APPLE'S NOW.** `NSImageCell.h` carries `typedef NSCellImageAlignment NSImageAlignment;` so an
`NSImageView` caller can spell the SDK's type while the cell keeps its older name; the values are the same.

**TRAPS THIS SLICE PAID FOR.**

* **A FLAG'S READER SHOULD BE AN EFFECT.** `-allowsCutCopyPaste` gates the four commands, and both `-paste:` and
  `-delete:` change the image only when it and `-isEditable` are on. `-animates` has no effect because `NSImage` has no
  animation clock, and that is SAID at the door rather than implied.
* **COPY/CUT CANNOT FINISH WITHOUT AN ENCODER, AND THE IMAGE CLASS ALREADY SAYS SO.** `NSImage -TIFFRepresentation`
  prints the refusal; the view does not add a second message. Cut tests the write's answer, so it does not clear the
  field when the copy failed.
* **THE INK IS THE ONLY WITNESS TO ALIGNMENT.** The `NSImageCell` stores the value and draws it; a new view that
  forwarded the setter but forgot the redisplay would pass a value check. The probe draws both alignments.
* **A NEW CLASS CHANGES THE DENOMINATOR.** The offered selector count rose with the class (4505 -> 4519) while the
  missing count stayed 0; the class count is 132 of 168, and the absent list is 36. **100% of the surface still means
  100% of the classes this tree HAS.**

**WHERE THE NEXT HOUR GOES.** The absent list is 36. The remaining editors are `NSDrawer`, `NSTokenField` and
`NSTokenFieldCell`; the rules pair is a view over controls that exist; the controllers/bindings are a KVO design
question. `NSDrawer` needs a parent/edge layout and a collapse animation (or a stated no-animation door), and
`NSTokenField` needs the field editor's token model — both are real slices, not one-liners.
