# libagora-app — a sixth handoff

*Written at the end of **eight slices** that picked `HANDOFF-5.md` up where its §8 stopped — §9–§16 of that file are
their running record, one numbered section per slice, and they are still the long form of everything summarised here.
`HANDOFF.md`, `HANDOFF-2.md`, `HANDOFF-3.md` and `HANDOFF-4.md` remain worth reading: nothing in any of them was wrong,
and the second file's §2 instrument rules and §4 traps are still the ones these sessions used most. **THIS FILE'S §2
NUMBERS SUPERSEDE EVERY EARLIER HANDOFF'S.***

*State at this handover: **eight slice commits** since the fifth handoff, tree clean, **161 tests passing in about 87 s**,
`api-ledger check` holding **376 metrics** — **132 of 168 classes (79%), 4519 of 4519 selectors (100%), 39 of 56
protocols (70%), 86 of 86 functions**, 5051 methods declared with 8 having no body, **all 130 classes with a surface at
COMPLETE coverage** — refusal census **387**, owed census **19**. **The 36 absent classes and the 17 absent protocols are
the remaining surface; the 100% on selectors is 100% of the classes this tree HAS, not of the 10.6 AppKit.***

---

## 1. What these sessions did

Eight slices, in the order they landed. Each is a commit in this repository and each ended green. There were no
workspace commits in this arc.

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

**AND THE LAST FOUR ROWS OF THE FIFTH HANDOFF WERE NOT A CLASS TAIL AT ALL; THEY WERE THE END OF THE PRESENT SET.**
`e199a54` closed every class this tree already had. `99baeca` began the other list: the classes the 10.6 manifest names
that this tree has never had. **The next slices are that list, and they are bigger than the tail was.**

---

## 2. The surface, measured

```
classes   132 of 168   (79%)    36 missing
selectors 4519 of 4519 (100%)    0 missing   130 of 130 classes at COMPLETE coverage
protocols  39 of  56   (70%)    17 missing
functions  86 of  86  (100%)     0 missing    10 refuse by name
methods   5051 declared on this tree's own classes, 8 with NO body on the chain (0.2%)
```

**THE SELECTOR FRACTION IS NOW 100% OF THE CLASSES THIS TREE HAS, AND THE CLASS FRACTION IS STILL 79%.** The manifest
offers selectors only for the classes that are present; the 36 absent classes contribute no rows to either side. So
`4519 of 4519` says "every selector 10.6 declares for the 132 classes that exist here is answered", not "the 10.6
AppKit is finished". The class number, 132 of 168, is the honest headline.

**TWO OF THE 132 PRESENT CLASSES HAVE NO SELECTORS:** `NSSecureTextField` and `NSTextAttachmentCell`. The complete
coverage denominator is therefore 130, not 132. (`NSSecureTextField` inherits everything from `NSTextField`;
`NSTextAttachmentCell` inherits everything from `NSCell`.) The earlier handoffs said "two classes with no surface" and
did not name them; these are the two.

**THE SEVENTEEN CLASSES THESE EIGHT SLICES FINISHED**, in the order they landed. Every one of them finished with named
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

(The table lists the seventeen completions since `HANDOFF-4`; the other 113 classes with a surface were already
complete before that arc. `NSFont`'s fifth attachment door was found by `HANDOFF-5`'s own recount and is refused now.)

**AND THE 36 ABSENT CLASSES GROUP CLEANLY. THIS IS THE LIST THE NEXT SLICES PICK FROM:**

| Group | Classes | What it needs |
|---|---|---|
| Editors and containers | `NSDrawer`, `NSTokenField`, `NSTokenFieldCell` | A parent/edge layout for the drawer, and the field editor's token model for the token field. `NSImageView` is DONE now; these three are the remaining editors. |
| Controllers / bindings | `NSController`, `NSObjectController`, `NSArrayController`, `NSDictionaryController`, `NSUserDefaultsController`, `NSTreeController`, `NSTreeNode` | KVO/KVC substrate — a design question before it is a slice, because this tier has no KVO. |
| Rules and tokens | `NSRuleEditor`, `NSPredicateEditor`, `NSPredicateEditorRowTemplate` | A predicate editor over the rule editor; both are views over controls that exist, but the predicate model is substantial. |
| Collection view | `NSCollectionView` | The ITEM exists (`NSCollectionViewItem`); the view is the missing half. |
| Still refused, per the plan's §A11 | `NSOpenGL*` (5), `NSMovie`, `NSMovieView`, `NSQuickDrawView`, the four typesetters (`NSATSTypesetter`, `NSGlyphGenerator`, `NSSimpleHorizontalTypesetter`, `NSTypesetter`), `NSSpeechSynthesizer`, `NSSpeechRecognizer`, `NSSound`, `NSInputManager`, `NSInputServer`, `NSDockTile`, `NSHelpManager`, `NSPersistentDocument`, `NSTouch` | GL, QuickDraw, movies, a PostScript/typesetting engine, speech, sound, the input-manager era, a Dock contract, a Help Viewer, a document subclass that needs autosave, and touch input with no hardware. Each is named at the door that would have to refuse. |
| Not this component's | `NSFileWrapper` | Foundation's (`libagora-base/NSFileWrapper.h`). The real AppKit gap is 35. |

**THE 17 MISSING PROTOCOLS ARE ALMOST ALL CONTRACTS FOR CLASSES IN THAT TABLE:** `NSDrawerDelegate`,
`NSTokenFieldDelegate`, `NSTokenFieldCellDelegate`, `NSRuleEditorDelegate`, `NSCollectionViewDelegate`,
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
| `tests/api-10.6-census.txt` | **376** pinned metrics — the aggregates, one `sel:` line per present class (130 of them), one `proto:` line per protocol, `fn:`/`fndecl:` per function, `selphantom:` per class with a phantom. |
| `tests/api_census.cmake` | The gate: two-directional comparison, arithmetic check, two fault checks. |
| `tests/refusal_census.txt` | **387** refusal sites, per FILE. |
| `tests/owed_census.txt` | **19** headers' OWED notes, per file. |
| `tools/api-ledger` | The parser: `manifest`, `census`, `check`, `missing`. |

* **THE METRIC COUNT ROSE BY ONE IN THE LAST SLICE, AND THAT IS NOT DRIFT.** `NSImageView` added one `sel:` line, so
  the census holds **376** metrics now, not 375. A new class adds a metric; a new test does not.
* **`missing` IS NOW THE ABSENT-CLASS DOOR, NOT THE SLICE-PICKING DOOR.** `./tools/api-ledger missing
  api/10.6/appkit-manifest.txt . --library build/libagora-app.so` prints **36 classes, 17 protocols, 0 functions, and
  no selector debt at all**. The "largest selector debt" section is gone because every present class is complete. A
  slice now starts by picking a class from that list or a protocol from the list beside it.
* **THE PER-CLASS RECOUNT IS STILL THE MEASUREMENT THAT CATCHES A SILENT DELETION.** `parse_tree` twice and a `diff`
  of the per-class declaration counts is how `NSFont`'s fifth attachment door and the header block that swallowed two
  declarations were found. Do not skip it because the aggregate says 0 missing: an aggregate can be right while a class
  is one short and another is one long.
* **ADDING A CLASS CHANGES THE DENOMINATORS, NOT ONLY THE NUMERATORS.** `NSImageView` took `classes-present` 131 -> 132,
  `classes-offered` stayed 168, `selectors-offered` 4505 -> 4519, `selectors-present` 4505 -> 4519, and complete
  coverage 129 -> 130. The four hand-written summary lines had to be recomputed: 132 of 168 (79%), 4519 of 4519 (100%),
  130 of 130. **A class that arrives is a new denominator on both sides.**
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

**THERE IS NO CLASS TAIL LEFT. THE NEXT WORK IS THE 36 ABSENT CLASSES, AND THEY ARE NOT ONE-LINERS.** The order below
is by reachable surface and by what the tree already has to build on.

1. **`NSTokenField` and `NSTokenFieldCell`** — the most natural next editor. The field editor, the cell's string, the
   completion table and the delegate machinery all exist; the missing model is the TOKEN: a represented object, a
   display string, a separator/completion rule, and the two delegate protocols (`NSTokenFieldDelegate`,
   `NSTokenFieldCellDelegate`). That is a real slice, not a forward.
2. **`NSDrawer`** — the parent/edge layout and the collapse/expand state. The split view's collapse is the nearest
   machinery; `NSDrawerDelegate` is the contract. Decide up front whether the collapse animates (the animation family
   exists) or is a stated no-animation door.
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

* **THE 100% IS OVER PRESENT CLASSES.** 4519 of 4519 selectors over 132 present classes; 130 of those have a surface and
  all 130 are complete. The 36 absent classes contribute no offered selectors. The class number is 132 of 168 (79%).
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
* **THE SUITE IS 161 TESTS IN ABOUT 87 SECONDS, AND `ctest --test-dir build -j4` IS THE GATE.** The exit status is the
  witness, not the tail of the output. The workspace's suite is 14 tests and belongs in the same gate run.
* **THE CENSUS IS 376 METRICS, 387 REFUSAL SITES, 19 OWED NOTES.** A new class adds a `sel:` metric; a new refusal
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
