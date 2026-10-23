# libagora-app — a fifth handoff

*Written at the end of **twelve slices** that picked `HANDOFF-4.md` up where its §8 stopped — §9–§20 of that file are their
running record, one numbered section per slice, and they are still the long form of everything summarised here. **A
THIRTEENTH SLICE HAS LANDED SINCE, and §9 is its record.**
`HANDOFF.md`, `HANDOFF-2.md` and `HANDOFF-3.md` remain worth reading: nothing in any of them was wrong, and the second
file's §2 instrument rules and §4 traps are still the ones these sessions used most. **THIS FILE'S §2 NUMBERS SUPERSEDE
`HANDOFF-4.md`'s**, which are twelve slices old.*

*State at this handover: **thirteen slice commits** since the fourth handoff, tree clean, **155 tests passing in about
88 s**, `api-ledger check` holding **375 metrics** — **131 of 168 classes (78%), 4380 of 4505 selectors (97%), 39 of 56
protocols (70%), 86 of 86 functions**, 4909 methods declared with 8 having no body, **121 of the 129 classes with a surface
at COMPLETE coverage** — refusal census **382**, owed census **19**. **The "120 of 129" this paragraph first carried was a
recount error; §9 records it and the corrected 119 -> 121 movement.***

---

## 1. What these sessions did

Twelve slices, in the order they landed. Each is a commit (plus, twice, a commit in the **workspace** repository and a
gitlink advance in `$AGORA_ROOT`), and each ended green. **The thirteenth is `182bcd4`, listed below and recorded in
§9.**

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
classes   131 of 168   (78%)    37 missing
selectors 4380 of 4505 (97%)   125 missing   121 of 129 classes at COMPLETE coverage
protocols  39 of  56   (70%)    17 missing
functions  86 of  86  (100%)     0 missing    10 refuse by name
methods   4909 declared on this tree's own classes, 8 with NO body on the chain (0.2%)
```

**EIGHT CLASSES ARE COMPLETE FOR THE ERA, and every one of them finished with NAMED REFUSALS rather than a stub:**

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

**AND ONLY NINE CLASSES STILL HAVE ANY DEBT** — the tail, not a subsystem:

```
NSView 28        NSControl 28     NSTableView 20   NSDocument 19    NSWindow 18
NSDocumentController 8   NSSavePanel 3   NSWorkspace 1    NSFont 0*
```

`*` `NSWorkspace`'s one is an INSTRUMENT quirk, not a door: the manifest's row is `selector NSWorkspace openTempFile:`
**with a colon Apple's declaration does not have** (every other zero-argument door in the manifest has none), so no header
can answer it. It is the second row in this file's census that is off BY CONSTRUCTION rather than by omission — the first
is `NSFileWrapper`, which is Foundation's (see §3).

**THE 37 ABSENT CLASSES GROUP CLEANLY, and the grouping has not changed in thirteen slices:**

| Group | Classes | What it needs |
|---|---|---|
| Editors and containers | `NSImageView`, `NSDrawer`, `NSTokenField`, `NSTokenFieldCell` | real views over machinery that exists (the image family, the split view's collapse, the field editor). `NSCollectionView`/`NSCollectionViewItem` is 10.11-only and stays refused (the plan's §9.3). |
| Controllers / bindings | `NSController`, `NSObjectController`, `NSArrayController`, `NSDictionaryController`, `NSUserDefaultsController`, `NSTreeController`, `NSTreeNode` | KVO/KVC substrate — a design question before it is a slice. |
| Rules and tokens | `NSRuleEditor`, `NSPredicateEditor`, `NSPredicateEditorRowTemplate` | a predicate editor over the rule editor; both are views over controls that exist. |
| Still refused, per the plan's §A11 | `NSOpenGL*` (5), `NSMovie`, `NSMovieView`, `NSQuickDrawView`, the four typesetters, `NSSpeechSynthesizer`, `NSSpeechRecognizer`, `NSSound`, `NSInputManager`, `NSInputServer`, `NSDockTile`, `NSHelpManager`, `NSPersistentDocument` | GL, QuickDraw, movies, a PostScript/typesetting engine, platform services, an input-manager era that is gone, a Dock contract, a Help Viewer, and a document subclass that needs autosave. Each is named at the door that would have to refuse. |
| Not this component's | `NSFileWrapper` | Foundation's (`libagora-base/NSFileWrapper.h`). The real AppKit gap is 36. |

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
| `tests/refusal_census.txt` | **382** refusal sites, per FILE. |
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
* **A REFUSAL CENSUS IS A CENSUS, NOT A RATCHET.** It went 292 → 382 across these thirteen slices, and almost every move was
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

1. **`NSView` 28 and `NSControl` 28 — the two longest tails, and they are SPREAD OUT.** The view's remainder is
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
3. **`NSDocument` 19 and `NSDocumentController` 8** — the async-saving family
   (`-autosaveDocumentWithDelegate:didAutosaveSelector:contextInfo:`, the two autosave URLs and the file type), the script
   commands (which would REFUSE like every other script door), the page-layout pair, and the `-presentError:` family
   (`-willPresentError:` is real; the modal form refuses). The autosave family needs a decision about WHERE a document's
   state lives before it is code.
4. **`NSWindow` 18** — `-canBeVisibleOnAllSpaces` (a compositor contract this tier has not got), `-colorSpace`,
   `-deviceDescription`, `-discardEventsMatchingMask:beforeEvent:`, `-postEvent:atStart:`, the style queries
   (`-isMiniaturizable`/`-isResizable`/`-isZoomable`), `-setDefaultButtonCell:`, `-setFrame:display:animate:`,
   `-setRepresentedFilename:` and the rest — several are one-liners over the style mask.
5. **DONE in §9: `NSSlider` 30/30 and `NSSliderCell` 35/35.** The tick-mark and title families were the last "ink"
   doors, and the slice also found a flipped vertical scale drawn upside down. **The next "ink" class is `NSTableView`
   20** — its grid is arithmetic over machinery that exists — and then the two deepest tails above.
6. **`NSWorkspace`'s ONE**, which is not a door (see §2) — and `NSSavePanel`'s three
   (`-isExpanded`, `-treatsFilePackagesAsDirectories:`), which are two lines and a flag.
7. **Then the absent classes in §2's order**: the editors (`NSImageView` is the most useful — the image family is complete),
   the rules pair, and the controllers/bindings — **which are a DESIGN QUESTION before they are a slice**, because this tier
   has no KVO.
8. **And leave refused** (§A11 and this tree's record): OpenGL, QuickDraw, movies, the four typesetters, `NSCollectionView`
   (10.11), `NSFileWrapper` (Foundation's), `NSHelpManager`, speech, the input-manager era, the Dock contract, and
   `NSPersistentDocument`.

---

## 7. Things a reader should not have to rediscover

* **THE EIGHT COMPLETE CLASSES ARE COMPLETE IN A SPECIFIC SENSE**: every selector Apple's 10.6 header declares for them is
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
* **THE SUITE IS 155 TESTS IN ABOUT 88 SECONDS, AND `ctest --test-dir build -j4` IS THE GATE.** The exit status is the
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
