# libagora-app — a sixth handoff

*Written at the end of **ten slices** that picked `HANDOFF-5.md` up where its §8 stopped — §9–§16 of that file are
their running record, one numbered section per slice, and they are still the long form of everything summarised here.
`HANDOFF.md`, `HANDOFF-2.md`, `HANDOFF-3.md` and `HANDOFF-4.md` remain worth reading: nothing in any of them was wrong,
and the second file's §2 instrument rules and §4 traps are still the ones these sessions used most. **THIS FILE'S §2
NUMBERS SUPERSEDE EVERY EARLIER HANDOFF'S.***

*State at this handover: **ten slice commits** since the fifth handoff, tree clean, **163 tests passing in about 88 s**,
`api-ledger check` holding **379 metrics** — **135 of 168 classes (80%), 4566 of 4566 selectors (100%), 42 of 56
protocols (75%), 86 of 86 functions**, 5113 methods declared with 8 having no body, **all 133 classes with a surface at
COMPLETE coverage** — refusal census **387**, owed census **19**. **The 33 absent classes and the 14 absent protocols are
the remaining surface; the 100% on selectors is 100% of the classes this tree HAS, not of the 10.6 AppKit.***

---

## 1. What these sessions did

Ten slices, in the order they landed. Each is a commit in this repository and each ended green. There were no
workspace commits in this arc, and the ninth also needed a Foundation fix, which is its own commit in `libagora-base`.

| Commit | What it landed |
|---|---|
| `182bcd4` | **The slider pair — COMPLETE** (`NSSlider` 30/30, `NSSliderCell` 35/35). The tick marks became VALUES with a snap, the title became a CELL drawn in a band taken off the top, the knob's thickness became a setting, the two no-argument ink doors took their frame from the control view, the background image was drawn — and **a flipped vertical scale that had been upside down was fixed** (§9 of `HANDOFF-5`). |
| `b0bd73c` | **`NSTableView` — COMPLETE** (123/123). The deprecated spellings were mapped to the modern state (`-drawsGrid` to the mask, `-autoresizesAllColumnsToFit` to the style), `-tile` now applies all five autoresizing styles, the selection enumerators and both drag-image doors became real, the focused column got its ring, the header got its indicator image, the destination feedback became three drawings, the cell-click door was implemented, and the vertical-motion gate got a counted probe (§10). |
| `1c4be0a` | **`NSControl` — COMPLETE** (65/65). The class factory, the one-cell selection, the paint/invalidate quartet, the six `-take…ValueFrom:` doors, the formatter and float-format pair, the attributed value and writing direction, `-refusesFirstResponder` and `-validateEditing` — which lands an editor's string without ending the session (§11). |
| `db418e3` | **`NSView` — COMPLETE** (221/221). The forced display family, `-setFrameOrigin:`, the rotation setters and the `is…` aliases, the subview list and positioned add, `-autoscroll:`, the focus-lock/layer/definition refusals, the nine ruler client defaults, and the `-displayRectIgnoringOpacity:inContext:` spelling corrected to Apple's (§12). |
| `1d1d7f4` | **`NSWindow` — COMPLETE** (261/261). The mutable style mask that preserves the content rect, the three `is` aliases, the represented-filename setter, the default button/backing/order/colour/spaces state, the screen initialiser, the direct animated frame set, and the local event queue's post/discard pair — plus **a deferred window that can now drain its queue** (§13). |
| `47b090e` | **The document pair — COMPLETE** (`NSDocument` 104/104, `NSDocumentController` 51/51). Autosave as a separate file with a `~/Library/Autosave` registry and timer, the asynchronous close review wired into `-performClose:`, the filename/save-panel state, page-layout hooks, the document→controller→application error chain (with `NSResponder`'s stale alert refusals replaced), and three named scripting refusals (§14). |
| `e199a54` | **`NSSavePanel` and `NSWorkspace` — COMPLETE** (47/47 and 58/58). The package flag became a real listing and accept rule; the deprecated `-openTempFile:` became `-openFile:`'s spelling — closing the last selector rows over the classes already present (§15). |
| `99baeca` | **`NSImageView` — the first ABSENT class to arrive** (14/14). A thin `NSControl` over `NSImageCell`: the image and its three placement facts forwarded with redisplay, the two edit gates and the animation flag, real paste/delete, and copy/cut reaching the image class's encoder refusal (§16). |
| `929bba3` | **`NSTokenField` and `NSTokenFieldCell` — the first ABSENT EDITOR to arrive** (10/10 and 10/10) and the two protocols that came with them. The list is the base cell's one value, the three conversions (display/editing/represented) fall back to the object, the chips are one layout shared by drawing/measurement/hit test, a session opens on EDITING strings and commits through `-shouldAddObjects:atIndex:`, the completion delay's sign is the switch, and the field is the ten forwards plus a relay. **It also found a Foundation hang with no caller**, fixed in `libagora-base` `a72b102` (§9). |
| `ffaef0d` | **`NSDrawer` — the first ABSENT CONTAINER to arrive** (27/27) and `NSDrawerDelegate`. A child window attached at the parent's edge, the four states announced synchronously (the middle is observable inside a handler), the two-axis size with the parent as the absolute limit, the min/max on the USER path only, and the parent's `-drawers` list as the owner. It also fixed two `NSWindow` teardown leaks: the child list was never released and a surviving child kept a dangling parent pointer (§10). |

**AND THE LAST FOUR ROWS OF THE FIFTH HANDOFF WERE NOT A CLASS TAIL AT ALL; THEY WERE THE END OF THE PRESENT SET.**
`e199a54` closed every class this tree already had. `99baeca` began the other list: the classes the 10.6 manifest names
that this tree has never had. **The next slices are that list, and they are bigger than the tail was.** The ninth row is
the first of them to be an EDITOR — the token pair, twenty selector rows and two protocols — and it is the shape the
remaining editors will take: a cell that owns the model and a view that forwards and relays.

---

## 2. The surface, measured

```
classes   135 of 168   (80%)    33 missing
selectors 4566 of 4566 (100%)    0 missing   133 of 133 classes at COMPLETE coverage
protocols  42 of  56   (75%)    14 missing
functions  86 of  86  (100%)     0 missing    10 refuse by name
methods   5113 declared on this tree's own classes, 8 with NO body on the chain (0.2%)
```

**THE SELECTOR FRACTION IS NOW 100% OF THE CLASSES THIS TREE HAS, AND THE CLASS FRACTION IS 80%.** The manifest
offers selectors only for the classes that are present; the 33 absent classes contribute no rows to either side. So
`4566 of 4566` says "every selector 10.6 declares for the 135 classes that exist here is answered", not "the 10.6
AppKit is finished". The class number, 135 of 168, is the honest headline.

**TWO OF THE 135 PRESENT CLASSES HAVE NO SELECTORS:** `NSSecureTextField` and `NSTextAttachmentCell`. The complete
coverage denominator is therefore 133, not 135. (`NSSecureTextField` inherits everything from `NSTextField`;
`NSTextAttachmentCell` inherits everything from `NSCell`.) The earlier handoffs said "two classes with no surface" and
did not name them; these are the two.

**THE TWENTY CLASSES THESE TEN SLICES FINISHED**, in the order they landed. Every one of them finished with named
refusals or a stated effect rather than a stub:

| Class | Selectors | Refusing by name |
|---|---|---|
| `NSTextView` | 186 of 186 | 30 |
| `NSResponder` | 145 of 145 | 0 (all forwarders) |
| `NSBrowser` | 120 of 120 | 5 |
| `NSText` | 70 of 70 | 5 |
| `NSFont` | 71 of 71 | 8 |
| `NSMenuView` | 42 of 42 | 10 |
| `NSSlider` | 30 of 30 | 0 (the background image is drawn) |
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
| `NSTokenFieldCell` | 10 of 10 | 0 (the list, the three conversions and the chips are all real) |
| `NSTokenField` | 10 of 10 | 0 (ten forwards and a relay; every delegate door has a sender) |
| `NSDrawer` | 27 of 27 | 0 (the child window, the four states, the edges and the reviewed user resize) |

(The table lists the twenty completions since `HANDOFF-4`; the other 113 classes with a surface were already
complete before that arc. `NSFont`'s fifth attachment door was found by `HANDOFF-5`'s own recount and is refused now.)

**AND THE 33 ABSENT CLASSES GROUP CLEANLY. THIS IS THE LIST THE NEXT SLICES PICK FROM:**

| Group | Classes | What it needs |
|---|---|---|
| Controllers / bindings | `NSController`, `NSObjectController`, `NSArrayController`, `NSDictionaryController`, `NSUserDefaultsController`, `NSTreeController`, `NSTreeNode` | KVO/KVC substrate — a design question before it is a slice, because this tier has no KVO. |
| Rules and tokens | `NSRuleEditor`, `NSPredicateEditor`, `NSPredicateEditorRowTemplate` | A predicate editor over the rule editor; both are views over controls that exist, but the predicate model is substantial. |
| Collection view | `NSCollectionView` | The ITEM exists (`NSCollectionViewItem`); the view is the missing half. |
| Still refused, per the plan's §A11 | `NSOpenGL*` (5), `NSMovie`, `NSMovieView`, `NSQuickDrawView`, the four typesetters (`NSATSTypesetter`, `NSGlyphGenerator`, `NSSimpleHorizontalTypesetter`, `NSTypesetter`), `NSSpeechSynthesizer`, `NSSpeechRecognizer`, `NSSound`, `NSInputManager`, `NSInputServer`, `NSDockTile`, `NSHelpManager`, `NSPersistentDocument`, `NSTouch` | GL, QuickDraw, movies, a PostScript/typesetting engine, speech, sound, the input-manager era, a Dock contract, a Help Viewer, a document subclass that needs autosave, and touch input with no hardware. Each is named at the door that would have to refuse. |
| Not this component's | `NSFileWrapper` | Foundation's (`libagora-base/NSFileWrapper.h`). The real AppKit gap is 32. |

**THE 14 MISSING PROTOCOLS ARE ALMOST ALL CONTRACTS FOR CLASSES IN THAT TABLE:** `NSRuleEditorDelegate`,
`NSCollectionViewDelegate`,
`NSSpeechSynthesizerDelegate`, `NSSpeechRecognizerDelegate`, `NSSoundDelegate`, `NSInputServiceProvider`,
`NSInputServerMouseTracker`, `NSDockTilePlugIn`, `NSGlyphStorage`, `NSAnimatablePropertyContainer`. Four exceptions
have their classes and are small slices on their own: **`NSTextViewDelegate`** (the view has a delegate and calls
`-textView:clickedOnLink:atIndex:` through an informal category), **`NSIgnoreMisspelledWords`** and
**`NSChangeSpelling`** (the field editor's spelling menus), and **`NSUserInterfaceItemSearching`** (the application has
a search-handler registry).

---

## 3. The instrument, which is still the deliverable

Four censuses and one ledger, all committed and all gated by `ctest`:

| Artifact | What it is |
|---|---|
| `api/10.6/appkit-manifest.txt` | The SDK's facts: 168 classes + superclasses, 56 protocols, 87 functions, 5208 selectors. |
| `tests/api-10.6-census.txt` | **379** pinned metrics — the aggregates, one `sel:` line per present class (133 of them), one `proto:` line per protocol, `fn:`/`fndecl:` per function, `selphantom:` per class with a phantom. |
| `tests/api_census.cmake` | The gate: two-directional comparison, arithmetic check, two fault checks. |
| `tests/refusal_census.txt` | **387** refusal sites, per FILE. |
| `tests/owed_census.txt` | **19** headers' OWED notes, per file. |
| `tools/api-ledger` | The parser: `manifest`, `census`, `check`, `missing`. |

* **THE METRIC COUNT RISES BY ONE PER NEW CLASS, AND THAT IS NOT DRIFT.** `NSImageView` added one `sel:` line (375 ->
  376); the token pair added two more (376 -> 378); the drawer added one (378 -> **379**). A new class adds a metric; a
  new test does not.
* **`missing` IS NOW THE ABSENT-CLASS DOOR, NOT THE SLICE-PICKING DOOR.** `./tools/api-ledger missing
  api/10.6/appkit-manifest.txt . --library build/libagora-app.so` prints **33 classes, 14 protocols, 0 functions, and
  no selector debt at all**. The "largest selector debt" section is gone because every present class is complete. A
  slice now starts by picking a class from that list or a protocol from the list beside it.
* **THE PER-CLASS RECOUNT IS STILL THE MEASUREMENT THAT CATCHES A SILENT DELETION.** `parse_tree` twice and a `diff`
  of the per-class declaration counts is how `NSFont`'s fifth attachment door and the header block that swallowed two
  declarations were found. Do not skip it because the aggregate says 0 missing: an aggregate can be right while a class
  is one short and another is one long.
* **ADDING A CLASS CHANGES THE DENOMINATORS, NOT ONLY THE NUMERATORS.** `NSImageView` took `classes-present` 131 -> 132
  and `selectors-offered`/`present` 4505 -> 4519; the token pair took them 132 -> 134 and 4519 -> 4539, complete coverage
  130 -> 132, and protocols 39 -> 41; the drawer took them 134 -> 135 and 4539 -> 4566, complete coverage 132 -> 133, and
  protocols 41 -> 42. The four hand-written summary lines had to be recomputed: 135 of 168 (80%), 4566 of 4566 (100%),
  133 of 133. **A class that arrives is a new denominator on both sides, and a protocol that arrives is a `proto:` line
  moving 0 -> 1.**
* **EVERY SLICE RE-PINS DELIBERATELY.** Let `ctest -R appkit-api-census` fail, recompute with `./tools/api-ledger census
  …`, write it in the same commit, and recompute the four hand-written summary lines from `api-ledger census` rather
  than editing them by eye.
* **A REFUSAL CENSUS IS A CENSUS, NOT A RATCHET.** It went 382 -> 387 across these eight slices. The view slice added
  four named focus-lock/layer/definition refusals, the document slice added three scripting refusals and removed two
  `NSResponder` refusals whose reason ("NSAlert is not in this tier") had expired. The diff says why, every time.
* **THE NEEDLE IS `(APPKIT-REFUSE|fn_refuse_[a-z]+)`.** A helper's definition and each call both match; that is the
  convention. A census whose needle enumerates helper names will lag the helpers — the pattern, not the list, is the fix.
* **THE LEDGER CANNOT SEE PROTOCOL DOORS.** All 5208 manifest selectors are attributed to CLASSES; a `proto:` line pins
  the protocol's PRESENCE, never its messages. The delegate surface is still held by the header's prose and the probe
  alone. An instrument that read protocol bodies is the real gap, and it is still named rather than discovered later.
* **ONE ROW IS OFF BY CONSTRUCTION: `NSFileWrapper`.** It is Foundation's in this stack, counted because the 10.6
  umbrella imports Foundation. The previous handoff also called `NSWorkspace -openTempFile:` an off-by-construction
  row; **THAT WAS WRONG.** The manifest's `openTempFile:` is Apple's deprecated BOOL-taking door, and the tree had a
  different hyphen-less `openTempFile` that CREATES a file and answers its path. They are two doors with two
  signatures; implementing the colon one closed the class. **A row that looks like a spelling is still a door.**

---

## 4. Traps these sessions paid for

Each cost time; each is the same shape as a trap in `HANDOFF-2.md` §4. The long form of each is in `HANDOFF-5.md`
§9–§16.

**A PROBE'S NEGATIVE CASE CAN PASS FOR THE WRONG REASON.**

* **A PROBE THAT COUNTED "DARK" PIXELS CALLED A RED TITLE INVISIBLE.** The slider's title color was set red to prove the
  colour door had a reader; `redComponent < 0.72` called every red glyph background. The check became "not the white
  the probe filled with". **The grid probe made the same mistake in the table slice**: the grid-off rendering still had
  185 pixels of the grid's grey because antialiased glyphs pass through it, so "zero" was the wrong negative; the claim
  became a structural ratio. **"No ink" is rarely the right negative; "much less ink" is.**

**A PUBLIC GEOMETRY DOOR IS A SECOND READER FOR ARITHMETIC THAT HAD ONE.**

* **THE SLIDER'S VERTICAL TICK SCALE WAS UPSIDE DOWN IN A FLIPPED VIEW.** The old inline ink used the unflipped formula
  for both flips; the moment `-rectOfTickMarkAtIndex:` made the scale askable, the probe could compare each mark's
  centre with the knob's centre and the bug appeared. The same shape is waiting wherever ink has arithmetic no door
  exposes.

**SIGNATURES GUESSED FROM MEMORY ARE WRONG OFTEN ENOUGH TO OPEN THE HEADER.**

* **`-columnsInRect:` RETURNS AN `NSRange`, NOT AN `NSIndexSet`; `-dragImageForRows:` TAKES AN `NSArray` OF ROW NUMBERS.**
  Both are deprecated, which is exactly why the newer spelling is the one a reader remembers. Open the SDK header before
  designing the door.
* **`-displayRectIgnoringOpacity:context:` WAS THE TREE'S SPELLING; APPLE'S IS `…inContext:`.** The behaviour was
  implemented and called internally for slices, and the ledger counted the public door missing because the selector
  name was wrong. A public selector is part of the surface; an internal spelling is not the same door.

**A DECLARED DOOR WITH NO SENDER.**

* **`NSWindowDelegate -windowWillReturnUndoManager:` WAS PUBLISHED AND NEVER SENT** (the smart-insert/undo slice): the
  text view's undo manager now comes from `-[NSWindow undoManager]`, which asks its delegate.
* **`NSRulerView -setClientView:` DID NOT SEND `-rulerView:willSetClientView:`** until the view tail added the send and
  the probe's old client recorded its own farewell. **A protocol door without a sender is a comment.**
* **`-shouldCloseWindowController:…` HAD NO CALLER** until `NSWindow -performClose:` was wired to ask it. The close
  button now starts the document review; the window delegate is asked on the second pass.

**A FLAG'S READER SHOULD BE AN EFFECT, NOT A GETTER.**

* **`-allowsCutCopyPaste` GATES FOUR COMMANDS; `-animates` HAS NO CLOCK.** The image view's cut/copy/paste flag changes
  what paste and delete do. `-animates` is stored and answered, and the header says outright that no timer is made
  because `NSImage` has no animation clock. The honest dispositions are three: a reader, a named refusal, or
  store-answer-and-say-nothing-reads-it.
* **`-setVerticalMotionCanBeginDrag:` IS A GATE IN THE MOUSE-DRAG THRESHOLD**, measured through a table subclass whose
  drag entry point is a counter. A flag whose only reader is its getter is a stored bit.

**CELL AND CONTROL SEMANTICS THAT LOOK LIKE FIELDS.**

* **`-selectedCell` IS THE CELL, NOT "THE SELECTED ONE".** A single-cell control has no selection to be empty; a cell
  whose state is off is still the answer, and `-selectedTag` is -1 only when there is no cell.
* **A FORMATTER SUPERSEDES THE DEPRECATED FLOAT FORMAT.** The control slice set a number formatter and then the float
  format and read "3.142" rather than "3.14"; the formatter wins by the cell's own documented precedence. Clearing it is
  what makes the deprecated door's reader visible.
* **`-validateEditing` LANDS THE RUNNING EDITOR'S STRING WITHOUT ENDING THE SESSION.** The cell's setter also tells the
  editor the value it now shows; ending remains the editor's or `-abortEditing`'s job.
* **`NSCell -copy` DOES NOT CARRY A NON-RETAINED TARGET.** The table's `-performClickOnCellAtColumn:row:` re-attaches the
  prepared cell's target/action to the copy, which is why the action arrives.

**ENVIRONMENT FACTS THAT LOOK LIKE BUGS IN YOUR CODE.**

* **`NSTemporaryDirectory()` ANSWERS `/System/Temporary Files/`, WHICH NEED NOT EXIST OR BE WRITABLE.** The document
  probe's first autosave directory was created under it and every write failed; the test now uses `/tmp`, and the
  production autosave path falls back `~/Library/Autosave` -> `NSTemporaryDirectory()` -> `/tmp`.
* **`NSSearchPathForDirectoriesInDomains` IS A NAMED REFUSAL IN THIS FOUNDATION.** `~/Library` is built from
  `NSHomeDirectory()` and created; `NSColorList` already established that path for user state.
* **`-fileNameExtensionForType:saveOperation:` WAS DECLARED AND RETURNED NIL.** The base class never asked the
  controller's type table, so the autosave name had no extension and the save-panel extension list fell back. It now uses
  the controller's `-fileExtensionsFromType:`.
* **`-isFilePackageAtPath:` IS STRICTER THAN THE EXTENSION.** It needs a known extension (`.app`, `.bundle`,
  `.framework`, `.plugin`, `.kext`) **and** a `Contents` child. The save-panel probe's first package had a made-up
  extension and was not recognized.
* **`NSApp` IS NULL UNTIL `-sharedApplication` RUNS**; `NSUserDefaults` writes under `$FNX_CONFIG_ROOT` and throws
  without it; `/proc/mounts` reads as zero bytes through the string door; a rename cannot cross a device (`EXDEV`), which
  is why the trash rule is per-volume.

**SELECTORS AND NUMBERS THAT LOOK ALIKE AND ARE NOT.**

* **SELECTORS ARE TYPED IN THIS RUNTIME**: compare `sel_getName` or `sel_isEqual`, not `==`.
* **`NSWritingDirectionNatural` IS `-1`**, not zero. A zero-filled ivar claims left-to-right for every object before a
  caller says anything.
* **AN UNDECLARED COMMAND IS UNREACHABLE, NOT MERELY UNIMPLEMENTED.** A key binding names a SELECTOR; if no header
  declares it, no binding can name it and no chain can deliver it.
* **A ZERO UNIT SQUARE IS A LIE ABOUT SCALE.** `_cg_unitSquareSize` was nought until something scaled it, so a fresh view
  answered "scaled from base". Both view initialisers now set 1,1 before any query can run.

**ASYNCHRONY AND CLOSE, WHICH THE DOCUMENT SLICE ADDED.**

* **A CLOSE WALK IS NOT A TRANSACTION.** `-closeAllDocuments…` asks each document in order, closes the yeses and stops at
  the first no; an unedited document before a refusal has already closed. The old test asserted "nothing was closed",
  which was the old refuse-everything rule. The test was corrected.
* **AN ASYNCHRONOUS CONTEXT HAS TO OWN ITSELF.** A sheet does not retain a `void *contextInfo`; the close and error
  contexts retain the delegate and release themselves when the answer arrives.
* **A STALE REFUSAL IS A BUG WITH A SHELF LIFE.** `NSResponder -presentError:` still said NSAlert did not exist; it has
  existed for slices. The document slice could not honestly forward errors through a chain that ended in that message, so
  the two refusals became presentations.

---

## 5. How to add a slice without breaking the instruments

Unchanged in shape from `HANDOFF-5.md` §5 and followed every time. Restated because it is the whole method:

1. **Measure first.** `./tools/api-ledger missing … --library …` names the absent classes and protocols; there is no
   selector debt left. Pick by reachable surface. If the class is absent, read Apple's 10.6 header for its full selector
   set and its superclass before writing anything.
2. **Write the header declaration where Apple declares it** — and check WHICH `@end` closes the block. A protocol
   inserted inside an `@interface` fails with an error that names a missing `@end` two hundred lines away.
3. **Implement, reusing a cell or a view that exists.** `NSImageView` is the model: it is a thin `NSControl` over
   `NSImageCell`, not a second drawing routine. Make every deviation a comment at the door: what it does not do, and why.
   A refusal that answers its type's empty value beats a stub that looks implemented.
4. **Test the claim, not the code**: pixels for drawing, round trips for mappings, files on disk for file operations, a
   *negative* assertion wherever the positive one could pass for the wrong reason, and **an assertion on the exit status**.
5. **Let the gate fail** (`ctest -R appkit-api-census`), re-pin in the same commit, recompute the four summary lines from
   `./tools/api-ledger census`. **A new class changes `classes-present`, `selectors-offered`, `selectors-present` and the
   complete-coverage denominator**; say so in the commit and in the section.
6. **Run the whole suite** (`ctest --test-dir build -j4`, ~87 s) and check the exit status. Then run the WORKSPACE suite:
   it is 14 tests and it catches the cross-component regressions a component's own suite cannot.
7. **If you add a protocol door, make the sending class say which messages it sends** (`NSMenuDelegate`,
   `NSComboBoxDelegate`, `NSAlertDelegate`, `NSMatrixDelegate`, `NSBrowserDelegate`, now `NSRulerMarkerClientViewDelegation`
   are the models). A protocol without a sender is prose.
8. **If a door has no reader, say so at the door** — or refuse it by name. Where a door has a reader, the probe drives the
   READER: `-insertionPointColor` by the caret's pixels, the smart space by the string afterwards, the package flag by
   the listing's slash.
9. **A deep class lands in a CATEGORY FILE of its own** once its main file is over a couple of thousand lines:
   `NSTextViewAttributes.m`, `NSTextViewPasteboard.m` and `NSTextViewEditing.m` are the pattern, and the private doors
   a category needs are declared in a `(Private)` category at the top of the new file.
10. **Commit in the component first, then advance the gitlink in `$AGORA_ROOT`** (`git -C "$A" add libagora-app`), with a
    message that says what moved in the censuses.

**AND TWO HOUSEKEEPING NOTES.** The tree is **LGPL-3.0-or-later** (library sources and headers) and **GPL-3.0-or-later**
(tests and the application) with `SPDX-FileCopyrightText`/`SPDX-License-Identifier` lines — **a new file must carry that
block**, and a sweep that adds C comments to `.cmake`, `.sh` or Python files breaks the gates. And `CMakeLists.txt`
**globs** `*.m` and `*.h`, so a new source file needs no build-file edit — but a new TEST needs its `add_executable` /
`add_test` / `ENVIRONMENT` triple in `tests/CMakeLists.txt`, and a test that forgets the environment line fails for want
of a library path rather than for want of the code.

---

## 6. Where to spend the next hour

**THERE IS NO CLASS TAIL LEFT. THE NEXT WORK IS THE 33 ABSENT CLASSES, AND THEY ARE NOT ONE-LINERS.** The order below
is by reachable surface and by what the tree already has to build on.

1. **DONE: `NSTokenField` and `NSTokenFieldCell`** — the first absent editor, landed as `929bba3` with both protocols
   (§9). The remaining editors are the same shape: a cell that owns a model the tree does not have yet, and a control
   that forwards and relays.
2. **DONE: `NSDrawer`** — the first absent container, landed as `ffaef0d` with `NSDrawerDelegate` (§10). It took the
   child window as the drawer's surface and made the synchronous transition the stated deviation; a later slice can
   animate the two middle states without moving any other door.
3. **`NSCollectionView`** — the ITEM (`NSCollectionViewItem`) already exists; the view is the missing half. It is a
   layout-and-recycling problem over the view tree and the item, not a new drawing engine; `NSCollectionViewDelegate`
   comes with it.
4. **`NSRuleEditor` and then `NSPredicateEditor`/`NSPredicateEditorRowTemplate`** — views over controls that exist, but
   the predicate model is substantial. Build the rule editor's rows/criteria first and make the predicate editor its
   consumer, or refuse the predicate half by name until the model is decided.
5. **The controllers/bindings family** — `NSController`, the four object controllers, `NSTreeController` and
   `NSTreeNode`. This tier has no KVO, so this is a **design question before it is a slice**: what observes what, and
   whether the tree grows a KVO substrate or the controllers remain a stored-value façade. Do not start with a header.
6. **The small protocol slices** — `NSTextViewDelegate`, `NSIgnoreMisspelledWords`, `NSChangeSpelling`,
   `NSUserInterfaceItemSearching`. Each has its class already; each is a contract the class can start sending.
7. **And leave refused** (§A11 and this tree's record): OpenGL, QuickDraw, movies, the four typesetters,
   `NSSpeechSynthesizer`, `NSSpeechRecognizer`, `NSSound`, `NSInputManager`, `NSInputServer`, `NSDockTile`,
   `NSHelpManager`, `NSPersistentDocument`, `NSTouch`, and `NSFileWrapper` (Foundation's). Each is named at the door
   that would have to refuse.

**A CAUTION ABOUT THE 100%.** The selector fraction is finished over the present classes and that is a real milestone,
but the class fraction is 79% and the protocol fraction is 70%. The next slice starts by choosing a class or a protocol,
not by looking for a selector debt; the ledger's `missing` output is the map.

---

## 7. Things a reader should not have to rediscover

* **THE 100% IS OVER PRESENT CLASSES.** 4566 of 4566 selectors over 135 present classes; 133 of those have a surface and
  all 133 are complete. The 33 absent classes contribute no offered selectors. The class number is 135 of 168 (80%).
* **THE `openTempFile:` ROW WAS REAL, NOT AN INSTRUMENT QUIRK.** The tree had a hyphen-less `-openTempFile` that CREATES
  a temp file and answers its path; Apple's deprecated `-openTempFile:` takes a path and OPENS it, and it is
  `-openFile:` by another name. The previous handoff's "off by construction" note was wrong; the row is implemented now.
  The only off-by-construction class left is `NSFileWrapper` (Foundation's).
* **AUTOSAVE IS A SEPARATE FILE, AND THE LOCATION IS `~/Library/Autosave` WITH A TEMP FALLBACK.** `NSAutosaveOperation`
  sets `autosavedContentsFileURL` and `NSChangeAutosaved`, never `fileURL`/`fileType`/modification date/recent list. A
  real save, a revert or a close deletes the copy. The registry is a plist; `NSApplication -finishLaunching` asks a
  fresh controller to reopen it. `-hasUnautosavedChanges` is independent of `-isDocumentEdited`.
* **CLOSE IS ASYNCHRONOUS AND `NSWindow -performClose:` ASKS THE DOCUMENT FIRST.** Save/Cancel/Don't Save is a sheet
  when there is a window and the app is running, application-modal otherwise. `-closeAllDocuments…` is a walk that
  stops at the first refusal, not a transaction.
* **THE ERROR CHAIN IS DOCUMENT -> CONTROLLER -> APPLICATION, AND IT ENDS IN AN `NSAlert`.** `NSResponder`'s two old
  refusals are gone; the modal form's caller gets `didRecover:NO`.
* **`NSImageView` IS A THIN `NSControl` OVER `NSImageCell`.** The placement forwards are measured in ink; `-paste:` and
  `-delete:` are real where the flags allow; `-copy:`/`-cut:` reach `NSImage -TIFFRepresentation`'s encoder refusal;
  `-animates` has no timer because `NSImage` has no animation clock.
* **THE SAVE PANEL'S PACKAGE FLAG IS A LISTING RULE.** With `-treatsFilePackagesAsDirectories` NO, a package (known
  extension **and** a `Contents` child) is a file; with YES it is a directory and can be entered. `-isExpanded` is NO;
  there is no expanded layout.
* **THE TWO SEAMS OF THIS COMPONENT'S SHAPE ARE `platform/AGWindowServer.h` AND `platform/AGPrintService.h`**: a narrow
  C interface, a real implementation behind a `#define`, a null one otherwise. A third (`AGKeyboard`) is the input map.
  Launch Services and Icon Services are separate COMPONENTS, consumed through `build-prefix`.
* **"RUNNING" MEANS "HAS A WINDOW", STATED AT THE DOOR.** There is no session and no `launchd`, so the window server's
  connections are liveness; an application that closed every window but has not quit is NOT listed.
* **THE TRASH RULE IS PER-VOLUME, AND THE WORKSPACE OWNS THE RECORD.** `NSWorkspace` moves the item (`~/.Trash`, or
  `.Trash-<uid>` at another volume's root, with a copy fallback); the Workspace's `WSTrash` writes the Put Back record
  and owns the empty.
* **A `NSControl` WITH NO CELL MUST KEEP ITS OWN TARGET/ACTION.** `NSControl` forwards the pair to `_cell`, so a
  cell-less subclass answers nil and sends nothing. `NSBrowser` paid for it.
* **THE PLAN'S PRINTING DECISION WAS AMENDED, AND THE RECORD IS THE PLAN.** `COCOA-10.11-SURFACE-PLAN.md` §4.4/§4.5
  said "physical printers refused"; both now say implemented, with the transport as a seam.
* **THE SUITE IS 163 TESTS IN ABOUT 88 SECONDS, AND `ctest --test-dir build -j4` IS THE GATE.** The exit status is the
  witness, not the tail of the output. The workspace's suite is 14 tests and belongs in the same gate run.
* **THE CENSUS IS 379 METRICS, 387 REFUSAL SITES, 19 OWED NOTES.** A new class adds a `sel:` metric; a new refusal
  moves the refusal total; a new OWED note moves the owed total. Re-pin all three in the same commit when they move.

---

## 8. How this file is kept

**THE RUNNING RECORD GOES HERE, AS NUMBERED SECTIONS AFTER THIS ONE.** The earlier handoffs did the same: `HANDOFF-2.md`
§13–§20, `HANDOFF-3.md` §8–§14, `HANDOFF-4.md` §9–§20 and `HANDOFF-5.md` §9–§16 are the sessions that picked those files
up, one numbered section per slice, each recording what landed, the numbers before and after, the traps the slice paid
for, and where the next hour went. A session that lands a slice should:

1. Append a `## 9. …` (then `## 10. …`) section here with its commit, its census movement and its traps.
2. Re-pin `tests/api-10.6-census.txt` and/or `tests/refusal_census.txt` in the same commit, recomputing the summary
   lines from `./tools/api-ledger census` — and run the PER-CLASS recount. **If the slice ADDED a class, re-pin the
   offered and complete denominators too, and say in the section that the class count moved.**
3. Update the component `README.md` with a section for the slice and `PROVENANCE.md` with what a reader needs to know —
   both are read by people who will never open this file.
4. Leave §1–§7 above ALONE unless a slice changes a number in them; when it does, change that number and say in the new
   section that it moved. A handoff that quietly drifts is the thing these files exist to prevent.

## 9. The first absent editor arrives: one list, four spellings, and a Foundation door that hung

**Commit `929bba3`, with the Foundation fix in `libagora-base` `a72b102`.** `NSTokenField` and `NSTokenFieldCell` are
present and COMPLETE at 10 of 10 each — the eighteenth and nineteenth complete classes, and the first classes off the
absent list since `NSImageView`. The change takes the class count 132 -> 134 (80% of 168), the offered and present
selectors 4519 -> 4539, complete coverage 130 -> 132, the protocols 39 -> 41, and the declaration count 5051 -> 5083;
the missing count is still 0. The census holds 378 metrics, the suite is 162 tests (about 89 s), the refusal census
stayed 387, the owed census stayed 19, and `tests/token_field.m` is the new probe (62 checks). The workspace's 14 tests
were run too.

**THE MODEL IS THE BASE CELL'S ONE VALUE, SEEN FOUR WAYS.** A token cell's `-objectValue` IS the ordered list of
represented objects (NSCell's own `-_objectValue`), so there is no second array. `-stringValue` is the DISPLAY strings
joined by ", "; `-cg_editingText` is the EDITING strings joined the same way; the drawing is the same list as chips. A
string handed to `-setObjectValue:` is tokenized into the list, an array IS the list, a single object becomes a
one-token list, and nil is an empty list rather than a nil value. Every mutation — a typed string, a committed session, a
pasteboard read, a cut — goes through one store, so there is one place the list changes and one place an open editor is
told about it.

**THE THREE CONVERSIONS FALL BACK TO THE OBJECT, AND THE FIELD IS A RELAY.** Display, editing and represented-object each
ask the delegate and fall back to the object's own text, which is Apple's "editing string = display string = represented
object" made literal and what makes the class usable over `NSString`s without a delegate. The FIELD installs itself as
the cell's delegate and turns each `tokenFieldCell:` question into the caller's `tokenField:` one — the `NSComboBox`
arrangement one class over — and where the caller has no opinion the FIELD answers the protocol's default (accept the
addition, no menu, the identity conversion, the cell's own style). The default is not the same at every door: nil means
"no opinion" for the conversions and the menu, but the INPUT for `-shouldAddObjects:atIndex:`, because nil is Apple's
error case there and a field that returned it would refuse every typed token.

**ONE LAYOUT SERVES THE DRAWING, THE MEASUREMENT AND THE HIT TEST.** `-cg_tokenFramesInFrame:` is the only place a
token's rectangle is computed: the drawing paints those rects, `-cellSizeForBounds:` takes the last one's right edge,
and `-cg_tokenIndexAtPoint:inFrame:` contains a point in them, so a chip cannot be painted in one place and clicked in
another. A rounded token is a pill with the control-grey fill and the shadow-grey border; a plain token is its words
with the ", " separator, so two plain tokens read as the string `-stringValue` answers. The baseline comes from
`NSTextFieldCell`'s one centring door, so a flipped context moves a chip's words exactly as it moves a field's.

**A SESSION OPENS ON THE EDITING STRINGS, AND ITS END IS A REVIEWED LIST.** The base session seeds its editor from
`-stringValue:` (the display text); this cell replaces that seed with the editing text and selects the whole run,
because a token's range is not a string's range. `-fn_finishEditing:keep:movement:` then tokenizes the editor's string
and passes it through `-shouldAddObjects:atIndex:` before storing it, and asks the base to tear down WITHOUT a second
write-back — the movement travels unchanged, so Return and Tab still send the control's action and Escape still does not.

**THE COMPLETION DELAY'S SIGN IS THE SWITCH, AND THE PASTEBOARD MOVES THE WHOLE LIST.** A negative delay asks nothing;
zero or positive asks the delegate on every change to the partial token after the last separator, flattens nested offer
arrays, and inserts a UNIQUE offer longer than the substring with the appended letters selected. Several offers insert
nothing, because this tier has no pop-up list; no timer is made, and the question is asked at the change. Copy/cut/paste
write and read every token through the delegate's pasteboard pair (the default write is the editing-string join, and a
NO from the delegate clears the board), because this tier has no token selection. A right-click finds the chip through
the same layout and asks the delegate's `has` door before its menu door.

### The traps this slice paid for

**A FOUNDATION DOOR WITH NO CALLER HAD TWO BUGS.** The first tokenize HUNG, and the stack named
`-[NSString componentsSeparatedByCharactersInSet:]` in `libagora-base`. Reading it found the end case setting the break
flag without advancing, so `offset == size` re-entered the loop forever; the same loop also walked BYTES while indexing
CHARACTERS and then handed byte offsets to `-substringWithRange:`, which reads UTF-16 code units. **NOTHING IN THE TREE
HAD EVER CALLED THE DOOR**, which is why both survived; the fix is a UTF-16 loop with a `break`, and
`libagora-base/tests/string_split.m` is the caller it never had. A dependency's untested door is this slice's problem the
moment it is used.

**`NSCharacterSet -copy` ANSWERS `[self retain]`, AND THAT IS WRONG FOR A MUTABLE RECEIVER.** The cell copies a caller's
separator so later mutation cannot change its parsing; the probe set a mutable set, mutated it after handing it over, and
the cell's parsing followed. `-mutableCopy` is the only door in this class family that allocates and replays the ranges,
so the stored set is built with it and the door says why. A "copy" that is an identity is an optimisation for an
immutable object and a leak of the caller's state for a mutable one.

**A PROBE THAT SET THE CELL'S STYLE WHILE THE DELEGATE ANSWERED PER TOKEN MEASURED THE DELEGATE.** The rounded-vs-plain
ink check rendered the same 1154 grey pixels twice: `-setTokenStyle:` was correct, but the probe's delegate implemented
`-tokenFieldCell:styleForRepresentedObject:` and returned `NSRoundedTokenStyle` for every token, which correctly wins.
The check had to remove the caller's delegate and let the field's own style be the only opinion — the difference between
testing a setting and testing the answer that supersedes it.

**AN ALL-REJECTED COMMIT EMPTIES THE LIST; IT DOES NOT RESTORE THE OLD ONE.** The first expectation was that refusing
every addition would leave the previous tokens standing. It cannot: the session edited the WHOLE string, the old tokens
were replaced on screen by the typed text, and keeping them would resurrect a value the person deleted. The probe now
asserts the empty list, and the door's comment says why rather than leaving the next reader to re-derive it.

**THE README GATE READS A CITATION TO ANOTHER COMPONENT'S TEST AS A MISSING FILE.** `appkit-readme-refs` matches every
`tests/<name>.m` in the README against THIS component's tests directory, so naming the Foundation probe the way the
AppKit probes are named failed the gate. The sentence now names the probe without the path pattern; the gate is right,
and the citation was the thing that had to change.

**Where the next hour goes:** §6 item 2, `NSDrawer` — the parent/edge layout and the collapse/expand state, with
`NSDrawerDelegate`. The token pair's shape is the model to follow: a cell (or a view that owns one) carrying the state
the tree has not had, every deviation named at the door, and a probe that measures the INK and the round trip rather than
the getters.

## 10. `NSDrawer` arrives: a child window at the edge, four states, and two axes of size

**Commit `ffaef0d`.** `NSDrawer` is present and COMPLETE at 27 of 27 — the twentieth complete class, and the first
container off the absent list. The change takes the class count 134 -> 135 (80% of 168), the offered and present
selectors 4539 -> 4566, complete coverage 132 -> 133, the protocols 41 -> 42, and the declaration count 5083 -> 5113;
the missing count is still 0. The census holds 379 metrics, the suite is 163 tests (about 88 s), the refusal census
stayed 387, the owed census stayed 19, and `tests/drawer.m` is the new probe (57 checks). The workspace's 14 tests
were run too.

**THE DRAWER IS A CHILD WINDOW, WHICH IS APPLE'S MODEL RATHER THAN AN ANALOGY.** `NSDrawer` is an `NSResponder`; the
class owns a borderless window made at init, `-contentView` IS that window's content view, and opening attaches the
window to the parent with `-addChildWindow:ordered:` and frames it immediately beyond the parent's edge. The class
therefore contributes the relationship and the arithmetic, not a second surface: `-setFrame:display:` on the child is
the layout, and the parent's own move propagation carries the drawer with it.

**THE FOUR STATES ARE REAL BUT SYNCHRONOUS, WHICH IS THE SLICE'S ONE STATED DEVIATION.** `-open` sets
`NSDrawerOpeningState`, announces `WillOpen`, lays out and attaches, sets `NSDrawerOpenState`, and announces `DidOpen`;
`-close` does the reverse. The middle states are therefore observable from inside the handler — the probe reads
`willOpen:1` and `didOpen:2` — and never from a caller waiting for the door to return. **No slide is animated**, because
this tier has no drawer animation clock; a later slice replaces two assignments and nothing else. A transition owns
itself: `-close` called from inside `-drawerWillOpen:` is ignored by a re-entrancy flag rather than nested.

**THE SIZE HAS TWO AXES AND THE PARENT LIMITS BOTH.** The content size is the thickness in the motion direction; the
transverse extent is the parent's minus `-leadingOffset` and `-trailingOffset`; and both clamp to the parent, because
Apple's one absolute restriction is that a drawer can never be larger than its window. `-setContentSize:` is plain
storage — Apple says programmatic changes are not limited by the minimum and maximum — while
`-cg_resizeContentByUserToSize:` is the USER path: it clamps the proposal to `-minContentSize`/`-maxContentSize` first
and then asks `-drawerWillResizeContents:toSize:`, whose answer is the size that lands. **NO DRAWER-EDGE GESTURE IS
WIRED**: the door is the user path, and a caller that tracks a pointer can drive it.

**AND THE PARENT OWNS THE DRAWER, WHICH IS WHY THE LIST NEEDED A HOME.** `-setParentWindow:` registers the receiver in
`NSWindow`'s `-drawers` list; that list retains it, `-parentWindow` is the borrowed back-pointer, and a parent swap
unregisters and re-registers while moving the attached child. Releasing a drawer that is still attached does not destroy
it — the probe checks that the parent's list still holds it — and detaching is what lets the next release free it.

### The traps this slice paid for

**THE WINDOW ALREADY ANSWERED `-drawers`.** `NSWindow.h` and `.m` had `-drawers` parsed as a present selector answering
an empty array, with a comment saying the drawer CLASS was the absent half. A category implementation in `NSDrawer.m`
would have been a SECOND implementation of one selector, and which one wins is a load-order accident — so the list moved
into `NSWindow` where the answer already lived, with two `cg_` registration doors for the drawer class to call. The
lesson is the ledger's own: a selector declared is a door answered, and finding the existing answer is cheaper than
adding a second one.

**`-setFrame:display:` DOES NOT RESIZE THE CONTENT VIEW.** A drawer whose child window changed size while its content
view kept the old frame would draw at the wrong size after the first edge change or offset move. The layout therefore
sets the window's frame and the content view's frame in one door, and the probe reads the CONTENT VIEW's frame as well as
the window's.

**ORDERING A CHILD OF AN OFFSCREEN PARENT ASKS FOR A SERVER THAT IS NOT THERE.** `-addChildWindow:ordered:` with a real
order ends in `-orderFront:`, whose first act is `-cg_ensureWindow` — and with no compositor that prints a refusal and
returns. The attach uses `NSWindowOut` when the parent is not visible (recording the relationship and ordering nothing)
and orders the child above the parent only when the parent is on screen. That is also what keeps the probe silent and
deterministic without a display.

**A CHILD THAT OUTLIVED ITS PARENT KEPT A DANGLING POINTER, AND THE CHILD LIST WAS NEVER RELEASED.** `NSWindow -dealloc`
had no `[_cg_childWindows release]` at all, and a child's `_cg_parentWindow` was left pointing at the freed window — the
next `-orderOut:` on that child would reach freed memory. Dealloc now tells each drawer its parent is gone first (which
detaches the drawer's child and takes it out of the list), then clears the remaining children's back-pointers and
releases the list. The probe releases a parent while still holding its open drawer and asserts that both the drawer's
and the child's `-parentWindow` answer nil.

**Where the next hour goes:** §6 item 3, `NSCollectionView` — the ITEM (`NSCollectionViewItem`) already exists and the
view is the missing half. It is a layout-and-recycling problem over the view tree and the item, with
`NSCollectionViewDelegate`; the drawer's shape is the model to follow (the item owns the model, the view owns the
layout, and every deviation is named at the door).
