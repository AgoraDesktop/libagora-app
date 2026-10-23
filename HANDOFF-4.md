# libagora-app — a fourth handoff

*Written at the end of six slices that picked `HANDOFF-3.md` up where it stopped (§9–§14 of that file are their running
record) and spent them where the earlier handoffs said to: the grid, the colour panels, the font pair, the print system,
and two slices of `NSTextView`. `HANDOFF.md`, `HANDOFF-2.md` and `HANDOFF-3.md` are still worth reading — nothing in any
of them was wrong, and the second file's §2 instrument rules and §4 traps are the ones these sessions used most. **THIS
FILE'S §2 NUMBERS SUPERSEDE `HANDOFF-3.md`'s**, which are six slices old.*

*State at this handover: **nine slice commits** since the eighth handoff (and the relicense sweep that touched every
file in the meantime), tree clean, **146 tests passing in about 84 s**, `api-ledger check` holding **375 metrics** —
**131 of 168 classes (78%), 4050 of 4505 selectors (90%), 39 of 56 protocols (70%), 86 of 86 functions**, 4579 methods
declared with 8 having no body, **113 of the 129 classes with a surface at COMPLETE coverage** — refusal census **292**.*
*(`HANDOFF-3.md`'s §2 numbers are five slices older than these; the numbers in this file's §2 are current as of §11.)*

---

## 1. What these sessions did

Six slices, in the order they landed. Each one is a commit (or a commit plus the sweep's relicense of the same tree),
and each ended green.

| Commit | What it landed |
|---|---|
| `74fdd36` | **The grid** — `NSMatrix` 95/95, `NSForm` 20/20, `NSFormCell` 19/19, `NSMatrixDelegate`. Three classes and 134 selectors: the last big VIEW. Plus the two fixes it needed one level down (`NSCell -copy`, `NSTextFieldCell`'s windowless-session guard) and a refusal whose reason had expired (`NSBrowser`'s matrix form). |
| `4cae874` + `5fbfde1` | **The colour panels** — `NSColorList` 13, `NSColorWell` 9, `NSColorPanel` 20, `NSColorPicker` 10, `NSColorPickingDefault`/`Custom`. The catalog doors got their reader (`+[NSColor colorWithCatalogName:colorName:]`). The sweep committed the sources; the second commit is the slice's record and both censuses. |
| `66babaf` | **The font pair** — `NSFontManager` 51/51, `NSFontPanel` 10/10. Enumeration, conversions, the action loop, the collections, the font menu, and a panel whose family list scrolls. |
| `e6f1429` | **Printing** — `NSPrintInfo` 46, `NSPrintOperation` 41, `NSPrintPanel` 20, `NSPageLayout` 12, `NSPrinter` 27, `NSPrintPanelAccessorizing`; the twelve `NSView` printing doors, `-print:` on `NSView`/`NSWindow`, eleven `NSDocument` doors that had been ABSENT, and `NSApplication`'s two. Plus `platform/AGPrintService.h` — libcups when configured, a null service when not. |
| `53594ab` | **The text view's attributes** — 42 selectors: selection ranges/affinity/granularity, the `-rangeForUser…` pairs, the attributes the view carries, the two `-shouldChangeTextInRange…` gates, and the kerning/baseline/ligature/alignment/writing-direction commands. In a category file of its own. |
| `98c1ca1` | **The text view's clipboard** — 17 selectors and the six `NSResponder` commands: the type registry, the read/write doors, copy/cut/paste/delete/plain/rich, `-allowsImageEditing`, and the drag source and destination. **And the RTF reader fix** it found: every font name was being discarded. |

Plus, in the **workspace** repository, `cc3c642`: **`File > Print…`**, which prints a listing through
`-[NSApplication application:printFiles:]` — the launch print door's first real caller. That is a different repository
and a different commit line; it is recorded here because the AppKit slice is what made it possible.

---

## 2. The surface, measured

```
classes   131 of 168   (78%)    37 missing
selectors 4050 of 4505 (90%)   455 missing   113 of 129 classes at COMPLETE coverage
protocols  39 of  56   (70%)    17 missing
functions  86 of  86  (100%)     0 missing    10 refuse by name
methods   4579 declared on this tree's own classes, 8 with NO body on the chain (0.2%)
```

**THE 455 MISSING SELECTORS ARE STILL CONCENTRATED, AND `NSBrowser` HAS MOVED FROM FIRST TO THIRD IN ONE SLICE.**
The ledger's debt list, largest first:

```
NSResponder 57  NSWorkspace 49   NSBrowser 47     NSTextView 40   NSMenuView 37
NSFont 35       NSText 31      NSView 28        NSControl 28     NSTableView 20
NSDocument 19   NSWindow 18    NSSlider 18      NSSliderCell 17  NSDocumentController 8
NSSavePanel 3
```

Everything below `NSSliderCell` is five doors or fewer in a class that is otherwise complete. **THE THREE DEEPEST TEXT
AND REFERENCE CLASSES HAVE ALL FALLEN IN THREE SLICES**: `NSTextView` 68 → 52 (§9) → 40 (§10) → 40, and `NSBrowser`
64 → 47 (§11). What is left of `NSTextView` is almost entirely BLOCKED or REFUSED — the text-checking family (Foundation
here has no `NSTextCheckingResult` or `NSOrthography`), the link/services pair, speech, the panels it has not built — and
`NSBrowser`'s remaining 47 are now its ITEM-BASED family (`-itemAtIndexPath:`, `-itemAtRow:inColumn:`,
`-parentForItemsInColumn:`, `-isLeafItem:`), its index paths, its drag doors and its autosave name, which is a design step
rather than a cluster of one-line doors.

**THE 37 ABSENT CLASSES GROUP CLEANLY:**

| Group | Classes | What it needs |
|---|---|---|
| Editors and containers | `NSImageView`, `NSDrawer`, `NSTokenField`, `NSTokenFieldCell` | real views over machinery that exists (the image family, the split view's collapse, the field editor). `NSCollectionView`/`NSCollectionViewItem` is 10.11-only and stays refused (the plan's §9.3). |
| Controllers / bindings | `NSController`, `NSObjectController`, `NSArrayController`, `NSDictionaryController`, `NSUserDefaultsController`, `NSTreeController`, `NSTreeNode` | KVO/KVC substrate — a design question before it is a slice. |
| Rules and tokens | `NSRuleEditor`, `NSPredicateEditor`, `NSPredicateEditorRowTemplate` | a predicate editor over the rule editor; both are views over controls that exist. |
| Still refused, per the plan's §A11 | `NSOpenGL*` (5), `NSMovie`, `NSMovieView`, `NSQuickDrawView`, the four typesetters, `NSSpeechSynthesizer`, `NSSpeechRecognizer`, `NSSound`, `NSInputManager`, `NSInputServer`, `NSDockTile`, `NSHelpManager`, `NSPersistentDocument` | GL, QuickDraw, movies, a PostScript/typesetting engine, platform services, an input-manager era that is gone, a Dock contract, a Help Viewer, and a document subclass that needs autosave. Each is named at the door that would have to refuse. |
| Not this component's | `NSFileWrapper` | Foundation's (`libagora-base/NSFileWrapper.h`), counted here because the 10.6 umbrella imports Foundation. The real AppKit gap is 36. |

**THE 17 MISSING PROTOCOLS ARE ALMOST ALL CONTRACTS FOR CLASSES IN THAT TABLE.** Four exceptions have their classes:
`NSTextViewDelegate` (the view has a delegate property and inherits a text delegate), `NSIgnoreMisspelledWords` and
`NSChangeSpelling` (the field editor's spelling menus), and `NSUserInterfaceItemSearching` (the application has a
search-handler registry). Each is a small slice, and each must follow §5's rule: declare it AND say which messages are
sent.

---

## 3. The instrument, which is still the deliverable

Four censuses and one ledger, all committed and all gated by `ctest`:

| Artifact | What it is |
|---|---|
| `api/10.6/appkit-manifest.txt` | The SDK's facts: 168 classes + superclasses, 56 protocols, 87 functions, 5208 selectors. |
| `tests/api-10.6-census.txt` | **375** pinned metrics — eight aggregates, one `sel:` line per class, one `proto:` line per protocol, `fn:`/`fndecl:` per function, `selphantom:` per class. |
| `tests/api_census.cmake` | The gate: two-directional comparison, arithmetic check, two fault checks. |
| `tests/refusal_census.txt` | **292** refusal sites, per FILE. |
| `tests/owed_census.txt` | The headers' OWED notes, per file. |
| `tools/api-ledger` | The parser: `manifest`, `census`, `check`, `missing`. |

* **`missing` IS THE DOOR TO PICK A SLICE WITH.** `./tools/api-ledger missing api/10.6/appkit-manifest.txt .` prints the
  absent classes, the absent protocols, the absent functions AND the per-class debt list; it is what every slice here
  started from.
* **AND EVERY SLICE RE-PINS DELIBERATELY.** Let `ctest -R appkit-api-census` fail, recompute with
  `./tools/api-ledger census …`, write it in the same commit, and recompute the four hand-written summary lines at the
  top of the file from the numbers rather than editing them by eye.
* **A REFUSAL CENSUS IS A CENSUS, NOT A RATCHET.** The printing slice took it DOWN from 294 to 292 — twelve `NSView`
  doors, two `NSApplication` doors and `NSWindow -print:` became real — while adding thirteen new named refusals
  (the Carbon handles, the seam's failures, the print script command). A count that may only fall says nothing about
  WHERE a refusal is; this one moves both ways and the diff says why.
* **THE LEDGER'S CLASS ARITHMETIC IS STILL ONE OFF BY CONSTRUCTION**: `NSFileWrapper` is Foundation's here and Apple's
  own home for it, and the manifest lists it because the 10.6 umbrella imports Foundation. 168 − 131 = 37, of which one
  is not this component's. The census says so in its own prose rather than special-casing it in the tool.
* **`classes-present` counts two classes with no surface**, so "113 of 129" is 113 of the 129 with selectors, not 131.

---

## 4. Traps these sessions paid for

Recorded because each cost time, and each is the same shape as a trap in `HANDOFF-2.md` §4.

**A CLASS THAT DECLARES A PROTOCOL AND HAS NO METHOD.**

* **`NSCell` DECLARED `<NSCopying>` AND HAD NO `-copy`.** `NSMatrix -setPrototype:` promises Apple's contract — every
  position gets a copy — and `-copy` was a `doesNotRecognizeSelector:`. The fix is the archiving pair taken one step
  further (encode, decode), which cannot drift from the coding. **AND THE DOOR IS `-copy`, NOT `-copyWithZone:`**: this
  Foundation removed every `NSZone`-taking method, so `NSCopying` here declares the entry point.

**A DECLARED METHOD THAT IS NOT IMPLEMENTED AT ALL.**

* **`-[NSDocument window]` DOES NOT EXIST** (only `-windowForSheet`). A print operation that asked for it aborted the
  process with `NSInvalidArgumentException`, which is how the slice learned to read the document's `_window` ivar.
* **`-addAccessoryController:` CALLED `-loadView` ON WHATEVER IT WAS GIVEN.** The parameter is an `NSViewController` in
  Apple's header; a probe's `NSObject` conformer made the panel abort. Both panels now ask `-respondsToSelector:` first.

**THE WINDOW AND THE CONTEXT, MEASURED RATHER THAN ASSUMED.**

* **A WINDOW MADE BY `-initWithContentRect:…` HAS NO CONTENT VIEW.** `_contentView` is nil until someone sets one, so
  every control added to it was a no-op, the factory's `-release` freed it, and the NEXT allocation reused the memory —
  which surfaced as an `NSTextField` receiving `-removeAllItems:`. Both print panels now make and set a content view.
* **THE EPS CONTEXT HAS ONE PAGE, AND THE COPYING RENDERER DREW THREE.** `+EPSOperationWithView:insideRect:toData:` was
  asking the view's own pagination instead of drawing its one rectangle.
* **THIS TREE'S FONT DESCRIPTORS CARRY NO TRAITS.** The matcher returns URL, PostScript name and family only, so
  `kCTFontTraitsAttribute` is always absent and a descriptor-based reader calls every face on the machine regular. Traits
  and weight must come from the FACE (`CTFontGetSymbolicTraits`, `CTFontCopyTraits`).

**A MUTABLE BUFFER STORED BY REFERENCE.**

* **THE RTF READER DISCARDED EVERY FONT NAME.** It stored its mutable name buffer into the font table and then cleared
  it, so every entry was `@""`, `[NSFont fontWithName:@"" size:]` failed, and every run of every RTF read in this tree
  became the system font — silently. A copy fixes it; a probe that pastes a bold selection and asserts the face is the
  guard.
* **`NSParagraphStyle -copy` ON A *MUTABLE* STYLE RETURNS THE SAME OBJECT** (no zones; the immutable copy is a retain),
  so `-setDefaultParagraphStyle:` keeps a caller's mutable style by reference. Recorded, not "fixed" in a slice about the
  view.

**IDENTITY AND EQUALITY.**

* **SELECTORS ARE TYPED IN THIS RUNTIME.** `[panel action] == @selector(takeColorFrom:)` answered NO while both names
  printed `takeColorFrom:`. Compare `sel_getName`, or `sel_isEqual`.
* **A TARGET THE PANEL DOES NOT RETAIN IS THE PROBE'S TO CLEAR.** Releasing a target without clearing the panel left a
  dangling send that crashed one test-case later, in `-sendAction:to:from:`.

**ARITHMETIC AND LIFETIME THAT ONLY A PIXEL OR A COUNT SHOWS.**

* **THE STANDARD COLOUR-LIST PATH NEEDS INTERMEDIATE DIRECTORIES.** `~/Library` need not exist, so the one-directory
  creator failed and every standard-path write looked like an uneditable list.
* **AN INSERTION SORT THAT RETAINED AND THEN RELEASED THE GRID'S OWN REFERENCES** freed cells still in the matrix.
* **AN ACTIVE WELL THAT PUSHED ITS COLOUR TO THE PANEL RECURSED FOREVER** — the panel's target IS the well, so
  `-setColor:` → panel → `-takeColorFrom:` → well. A well tells the panel where its colour starts, at activation, once.
* **`-currentPage` IS LEFT WHERE THE LAST PAGE PUT IT**; a cleanup that reset it made "the last page drawn" unanswerable.

---

## 5. How to add a slice without breaking the instruments

Unchanged from `HANDOFF-3.md` §5, and these sessions followed it every time. Restated because it is the whole method:

1. **Measure first.** `./tools/api-ledger missing …` names the cluster sizes, so you pick by reachable surface.
2. **Write the header declaration where Apple declares it** — and check WHICH `@end` closes the block. A protocol
   inserted inside an `@interface` fails with an error that names a missing `@end` two hundred lines away.
3. **Implement**, and make every deviation a comment at the door: what it does not do, and why. A refusal that answers
   its type's empty value beats a stub that looks implemented.
4. **Test the claim, not the code**: pixels for drawing, round trips for mappings, a *negative* assertion wherever the
   positive one could pass for the wrong reason, and **an assertion on the exit status**.
5. **Let the gate fail** (`ctest -R appkit-api-census`), re-pin in the same commit, recompute its prose from the numbers.
6. **Run the whole suite** (`ctest --test-dir build -j4`, ~77 s) and check the exit status.
7. **If you add a protocol, make the sending class say which messages it sends** (`NSMenuDelegate`, `NSComboBoxDelegate`,
   `NSAlertDelegate`, `NSMatrixDelegate` are the models).
8. **If a door has no reader, say so at the door** — or refuse it by name. A stored bit nobody reads is the failure this
   tree keeps re-learning. Where a door has a reader, the probe should drive the READER, not just the setter: the
   typing-attributes dictionary is checked by what the next keystroke wears, the selection attributes by the pixel the
   band is filled with.
9. **A deep class lands in a CATEGORY FILE of its own** once its main file is over a couple of thousand lines:
   `NSTextViewAttributes.m` and `NSTextViewPasteboard.m` are the pattern, and the private doors a category needs from the
   main file are declared in a `(Private)` category at the top of the new file.
10. **Commit in the component first, then advance the gitlink in `$AGORA_ROOT`** (`git -C "$A" add libagora-app`), with a
    message that says what moved in the censuses.

**AND ONE HOUSEKEEPING NOTE THIS BRANCH ADDED: the per-file licence header.** The tree was relicensed to
LGPL-3.0-or-later (library sources and headers) and GPL-3.0-or-later (tests and the application) with
`SPDX-FileCopyrightText`/`SPDX-License-Identifier` lines. **A NEW FILE MUST CARRY THAT BLOCK**, and a sweep that adds C
comments to `.cmake`, `.sh` or Python files breaks the gates — that happened, and was fixed in `af67555`.

---

## 6. Where to spend the next hour

Ranked by reachable surface per unit of work, and the ranking now starts with the class this tree has and has not
finished:

1. **`NSResponder` 57 — now the component's largest debt, and the cheapest per door.** Mostly the chain forwarders and the
   standard key-binding commands; each is small, and the census credits them to `NSResponder` rather than to the views
   that inherit them. **The window's `-undoManager` was one of these rows and is a real answer in `NSWindow` now** (§10),
   which is the shape the rest of the family wants: find the natural sender, give it the door.
2. **`NSWorkspace` 49.** The shell verbs: open/reveal, file operations, the running-application list.
   `libagora-launchservices` and `libagora-iconservices` are the seams, and the Workspace component is the caller — but
   NOTE that nothing in the workspace repository calls `NSWorkspace` yet (§11 measured it), so this is reach the tier
   does not have a consumer for. It is real API and a real gap; it is not the highest VALUE per hour.
3. **`NSBrowser` 47.** What is left is the ITEM-BASED half (`-itemAtIndexPath:`, `-itemAtRow:inColumn:`,
   `-parentForItemsInColumn:`, `-isLeafItem:`, `-pathToColumn:`, `-indexPathForColumn:`), the selection index paths, the
   drag doors (`-canDragRowsWithIndexes:inColumn:withEvent:`, `-draggingImageForRowsWithIndexes:…`) and the autosave/column
   furniture. **The item-based family is a DESIGN QUESTION before it is a slice**: it needs the item-based delegate doors
   (`-browser:child:ofItem:`, `-browser:isLeafItem:`, `-browser:objectValueForItem:`, `-rootItemForBrowser:`) which the
   protocol does not declare yet, and a browser can be cell-based or item-based but this class is built as the former.
4. **`NSTextView`'s remaining 40**, which are now almost all BLOCKED or REFUSED rather than absent: the TEXT-CHECKING
   family (`-checkTextIn…`, `-enabledTextCheckingTypes`, `-handleTextCheckingResults:…`, the three automatic-detection
   toggles) is blocked on `NSTextCheckingResult`/`NSOrthography`, which Foundation here has not got; the LINK/SERVICES
   pair needs a link attribute constant and a services transport; `-startSpeaking:`/`-stopSpeaking:` are speech, refused
   by name; the five `-orderFront…Panel:` doors are panels this tier has not built; and `-complete:`/`-insertCompletion:`
   are the WORD-COMPLETION family, which is the one cluster there that is genuinely a slice. **Do not open the checking
   family before Foundation has the classes** — name them absent and keep the flags refusing.
5. **`NSText` 31 and `NSFont` 35**, which are siblings rather than subsystems: `NSText`'s remaining doors are the RTF
   write/read pair, `-changeFont:`/`-copyFont:`/`-pasteFont:`, the resizability and size limits, and `-showGuessPanel:`;
   `NSFont`'s are the descriptor and traits surface.
6. **The absent-class groups in §2**, in this order: the editors (`NSImageView`, `NSDrawer`, `NSTokenField`), the rules
   pair, and the controllers/bindings — which are a DESIGN QUESTION before they are a slice, because this tier has no KVO.
7. **Leave refused** (§A11 and this tree's record): OpenGL, QuickDraw, movies, the four typesetters, `NSCollectionView`
   (10.11), `NSFileWrapper` (Foundation's), `NSHelpManager` until there is a Help Viewer, speech until the platform
   services exist, and the input-manager era.

---

## 7. Things a reader should not have to rediscover

* **THE PLAN'S PRINTING DECISION WAS AMENDED, AND THE RECORD IS THE PLAN.** `COCOA-10.11-SURFACE-PLAN.md` §4.4/§4.5
  said "physical printers refused"; both now say implemented, with the transport as a seam (`libcups` optional, PDF
  always). If a later session finds the plan and this file disagreeing about printing, the plan is the record and this
  file is the state.
* **THE PRINT SEAM IS `platform/AGPrintService.h`**, and it is the second seam of its shape after `AGWindowServer.h`:
  a narrow C interface, a libcups implementation behind `AG_HAVE_CUPS`, a null one otherwise. A build without it answers
  every print door and refuses a spool by name.
* **A JOB IS ALWAYS A PDF**, rendered through the same `CGPDFContext` path `-dataWithPDFInsideRect:` uses. Driverless
  printers take PDF natively; CUPS filters it for everything older.
* **`NSPrintPanel` AND `NSPageLayout` ANSWER `NSOKButton` WITHOUT A RUN LOOP**, which is what makes them testable. The
  page range is the one value the ticket cannot hold, so the panel keeps it and the operation reads it through a `cg_`
  door.
* **THE WORKSPACE'S PRINT VERB IS THE FIRST REAL CALLER OF `-application:printFiles:`** (`workspace` commit `cc3c642`).
  It prints a LISTING, not a document's contents: printing a file's contents needs the application that owns it, and
  there is no Apple Event transport here. The component's README says so; the plan's stage numbers are taken (W7 is the
  drag session), so it is recorded there unnumbered.
* **A TEXT VIEW'S CARET IS A COMMAND'S TARGET, NOT A NO-OP.** A selection's run gets the attribute; a caret's command
  mutates the TYPING attributes, which is what `-typingAttributes` and `-insertText:` are for. The three decorative
  dictionaries are read where they are drawn.
* **THE CLIPBOARD IS ONE PATH IN AND ONE PATH OUT.** A paste inserts the characters through `-insertText:` and then
  applies the runs, so the mirror, the selection, the notifications and the layout all follow from one edit.
* **`-selectedRanges` IS THE ARRAY AND `-selectedRange` IS ITS FIRST MEMBER.** The array exists only when there is more
  than one range, so the single-selection shape stays the cheap one and every inherited door keeps working.
* **THIS TREE'S STRINGS ARE BYTE SEQUENCES, NOT CHARACTER SEQUENCES** for non-ASCII (`HANDOFF-2.md` §4): the word and
  paragraph granularities use ASCII `isalnum` and `_`, and say so.
* **THE SUITE IS 146 TESTS IN ABOUT 84 SECONDS, AND `ctest --test-dir build -j4` IS THE GATE.** The exit status is the
  witness, not the tail of the output.
* **A CELL-LESS `NSControl` ANSWERS NIL FOR `-target` AND NULL FOR `-action`**, because this tree keeps that pair in the
  control's CELL. A subclass with no cell — `NSBrowser` is one — has to keep its own, or a click silently sends nothing.
  Found in §11; the same trap is waiting for any other cell-less control.
* **A RESPONDER-CHAIN TEST NEEDS A KEY WINDOW AND A FIRST RESPONDER THAT ACCEPTS.** `-makeKeyWindow` is abandoned for a
  window that cannot become key (borderless ones cannot, by Apple's rule), `NSResponder -acceptsFirstResponder` is NO by
  default, and `-targetForAction:` starts at `[keyWindow firstResponder]` — so a probe that installs a stand-in target and
  asks a menu to update, with no window, is measuring an empty chain and will call every chain-routed row disabled. And a
  chain-routed row's ITEM keeps a nil target by design: the target is resolved when the action is SENT.
* **A DECLARED DELEGATE DOOR WITH NO SENDER IS THE SAME DEFECT AS A DECLARED METHOD WITH NO BODY**, and §10 found one:
  `NSWindowDelegate -windowWillReturnUndoManager:` was published, `NSResponder -undoManager` documented the walk that was
  supposed to reach it, and nothing in between sent or answered it. A reader looking for "what is missing" should grep
  for the door as well as for the row: the ledger counts DECLARATIONS, and a door declared on a protocol whose natural
  sender never asks it counts as present while doing nothing.
* **INSTALLING A VIEW AS A WINDOW'S CONTENT VIEW MAKES IT THE WINDOW'S FIRST RESPONDER**, so a text view handed back by
  `-setContentView:` is already `_editing`. "There is no caret here" is a claim you can make only about a view whose
  session you ended (`-resignFirstResponder`), not about a fresh one — this cost §9's slice two false failures.

---

## 8. How this file is kept

**THE RUNNING RECORD GOES HERE, AS NUMBERED SECTIONS AFTER THIS ONE.** The earlier handoffs did the same: `HANDOFF-2.md`
§13–§20 and `HANDOFF-3.md` §8–§14 are the sessions that picked those files up, one numbered section per slice, each
recording what landed, the numbers before and after, the traps the slice paid for, and where the next hour went. A
session that lands a slice should:

1. Append a `## 9. …` (then `## 10. …`) section here with its commit, its census movement and its traps.
2. Re-pin `tests/api-10.6-census.txt` and/or `tests/refusal_census.txt` in the same commit, recomputing the summary
   lines from `./tools/api-ledger census`.
3. Update the component `README.md` with a section for the slice and `PROVENANCE.md` with what a reader needs to know —
   both are read by people who will never open this file.
4. Leave §1–§7 above ALONE unless a slice changes a number in them; when it does, change that number and say in the new
   section that it moved. A handoff that quietly drifts is the thing these files exist to prevent.

## 9. The text view's container, its margin and the drop — one coordinate space

*Session of the seventh slice, picking §6's first item off the list above. Its commit is "AppKit: the text view's
container, its margin, and the drop's own door"; tree clean; `ctest --test-dir build -j4` green at **144 tests in 75 s**
with `appkit-api-census` re-pinned in the same commit. (The subject rather than the hash, because the file lives inside
the commit and a hash cannot name its own.)*

**WHAT LANDED.** Sixteen selectors, all of them `NSTextView`'s, in the family §6 ranked first:
`-initWithFrame:textContainer:` (now the designated initialiser), `-setTextContainer:`, `-replaceTextContainer:`,
`-textContainerInset`/`-setTextContainerInset:`, `-textContainerOrigin`/`-invalidateTextContainerOrigin`,
`-setConstrainedFrameSize:`, `-drawViewBackgroundInRect:`, `-shouldDrawInsertionPoint`,
`-drawInsertionPointInRect:color:turnedOn:`, `-insertionPointColor`/`-setInsertionPointColor:`,
`-updateInsertionPointStateAndRestartTimer:`, `-setNeedsDisplayInRect:avoidAdditionalLayout:` and
**`-characterIndexForInsertionAtPoint:`**. The last one is the point of the slice: the manager's point-to-glyph door was
already there, so the drop's limit was a missing SUM, not a missing engine — `-performDragOperation:` now sets the
insertion point from `-[NSDraggingInfo draggingLocation]` before it reads the pasteboard, and the "a drop lands at the
insertion point" note in `NSTextView.h`, `PROVENANCE.md` §35 and `NSTextViewPasteboard.m` is retired in all three
places rather than left to contradict the code.

**THE ARITHMETIC THAT HAD TO MOVE WITH IT.** The view had been spelling one number twice: `-cg_xForIndex:` subtracted
the container's line-fragment padding and every call site added `NS_TEXT_INSET` back, which agrees only while the two
constants are equal. The helper now answers a VIEW x (origin + the manager's offset), the call sites stopped adding,
`-cg_indexForPoint:`, `-cg_indexOnLine:atX:`, `-cg_clampBandX:toLine:`, the attachment hit box, the selection band, the
composition rule, the find indicator and the spelling underline all take their origin from `-textContainerOrigin`
instead of the module constant. **THE DEFAULT INSET IS (0, `NS_TEXT_INSET`) AND NOT APPLE'S (0, 0)** — a deviation
written in the header, because every existing pixel of every document is measured down from the field's four-point air
and a default of zero would have moved all of it to buy nothing.

**THE NUMBERS MOVED, SO §1, §2, §6 AND §7 ABOVE CHANGED WITH THEM** (see §8's rule 4):

```
selectors       4005 -> 4021 of 4505   (missing 500 -> 484)
methods-declared 4530 -> 4546
NSTextView       118 -> 134 of 186     (debt 68 -> 52)
tests            143 -> 144            (the new suite)
```

`classes`, `protocols`, `functions` and the refusal census (**292**) did NOT move: no class, protocol or function was
added, and no refusal was added or retired — the drop's comment was the only refusal-adjacent thing and it was a limit,
not a named refusal. `tests/api-10.6-census.txt` is re-pinned with its prose block recomputed from
`./tools/api-ledger census` (the four summary lines now read 4021/484/4546) and its "offered/answered" history line
extended to 4021.

**TRAPS THIS SLICE PAID FOR, each one caught by its own probe.**

* **A NEW CONTAINER WIDTH IS A NEW WRAP, AND THE MANAGER CANNOT SEE IT.** Nothing observes `NSTextContainer
  -setContainerSize:`, so `-setConstrainedFrameSize:` with a narrow width laid the OLD lines out in the new container and
  the probe counted one line where five were asked for. The size change and `-invalidateLayoutForCharacterRange:` have
  to happen together — they are one private door (`-cg_sizeContainerToFrame`) now, which is also what `-setFrameSize:`
  and `-setTextContainerInset:` call.
* **A CONTAINER IS ON ONE MANAGER, AND `-addTextContainer:` APPENDS WITHOUT CHECKING.** Adopting a container this manager
  already holds would list it twice and lay the text out twice, so the adoption asks `-layoutManager` first. The removal
  path clears the old container's `-textView:` BEFORE it leaves the list, because a detached container that still names a
  view is the shape that sends to freed memory.
* **INSTALLING A VIEW AS A CONTENT VIEW MAKES IT THE FIRST RESPONDER.** §7 now carries this as a general trap; here it
  produced two false failures — "no caret outside an editing session" was asked of a view that had a session, and "no
  text with no container" was answered by a caret drawn at a zeroed x.
* **A ONE-POINT BAR AT A FRACTIONAL x HAS NO DARK COLUMN.** The caret is drawn at the layout's own 19.344, so it straddles
  two pixel columns and neither is the pure pen colour. The probe counts ink over both columns; asserting "dark" of one
  would have been asserting that the layout landed on a whole number.
* **A PROBE THAT MEASURES "WHERE THE INK BEGINS" MEASURES THE ANTIALIAS TOO.** The first stem's leftmost DARK column is 5
  when the padding is 4, so the absolute assertion is a range and the DELTA is exact — 12 points for a 12-point margin,
  which is the claim anyway.

**WHERE THE NEXT HOUR GOES.** §6's ranking is rewritten above: `NSTextView`'s remaining 52 with the smart-insert and undo
doors first (measuring whether Foundation here has an undo manager before storing a flag), then `NSBrowser` 64 — which is
now the component's largest single debt and the one the Workspace's column view would feel.

## 10. What typing does around it: the smart space, the smart delete, and the undo group

*Session of the eighth slice, taking §6's first item as it then stood (the smart-insert and undo cluster). Its commit is
"What typing does around it: smart insert, smart delete and the undo group"; tree clean; `ctest --test-dir build -j4`
green at **145 tests in 79 s** with `appkit-api-census` re-pinned in the same commit.*

**THE MEASUREMENT §6 ASKED FOR FIRST, AND THE ANSWER.** `libagora-base` ships `NSUndoManager` — a full one, with grouping,
`-isUndoing`/`-isRedoing`, `-groupingLevel`, `-undoCount`, the eight notifications and `-registerUndoWithTarget:handler:`
— and `NSResponder` implements `-undoManager` as a walk of the chain. So the undo half was never blocked; what was missing
was a caller, and §10 found it (§"the dead door" below). No flag was stored that nothing reads.

**TWELVE SELECTORS LANDED**, all `NSTextView`'s: `-smartInsertDeleteEnabled`/`-setSmartInsertDeleteEnabled:`/
`-toggleSmartInsertDelete:`, `-smartInsertForString:replacingRange:beforeString:afterString:` and the two halves,
`-smartDeleteRangeForProposedRange:`, `-allowsUndo`/`-setAllowsUndo:`, `-breakUndoCoalescing`, `-isCoalescingUndo` and
`-didChangeText`. They live in a NEW CATEGORY FILE, `NSTextViewEditing.m` — §5's rule 9, because `NSTextView.m` is over
two thousand lines — with the private doors declared once in each file so the two cannot disagree.

**THE RULES, STATED BECAUSE EACH IS A DECISION.** Smart insert adds a space exactly where the neighbouring character and
the inserted edge are both WORD characters (ASCII letter, digit, underscore — the same set `NSText`'s word movement uses,
and the same deviation §4 records for non-ASCII), and nowhere else. Smart delete grows a non-empty range over the
trailing run of spaces and tabs, else over the leading run — one direction, never both, or the survivors would have no
space between them — and never over a newline, because a newline is a paragraph break rather than a gap. Both are applied
in the EDIT PATH (`-insertText:` for the space, `-delete:` for the range) so typing, pasting and dropping agree, the
delegate is asked about the string that will really be inserted, and the undo record is one action rather than three.

**AND THE UNDO GROUP IS THE ONE PLACE THE ERA'S MECHANISM IS ABSENT.** Apple leans on `NSUndoManager`'s EVENT-DRIVEN
grouping to know where a typing run ends; this Foundation's manager has none, so the view keeps the one fact that answers
the same question — `_cg_lastEditEnd`, where the previous edit finished — and a non-adjacent edit closes the top-level
group before it registers. The behaviour is the era's: one undo takes back a typed word, a run of backspaces is one undo,
a keystroke elsewhere starts a new group, and `-breakUndoCoalescing` is the explicit boundary. `-isCoalescingUndo` is the
manager's grouping level rather than a flag of the view's, so the two cannot disagree. The undo action carries the range
the edit inserted over and the text it replaced, and replaying it calls `-replaceCharactersInRange:withString:` — the
view's own door, so no second edit path exists for an undo to forget.

**THE DEAD DOOR, WHICH IS THIS SLICE'S REAL FINDING.** `NSWindowDelegate` published `-windowWillReturnUndoManager:`;
`NSResponder -undoManager` documented its walk and named that door as the window's answer; **nothing sent it and nothing
answered it.** A text view in a window therefore found no manager, and `-allowsUndo` would have recorded nothing while
looking perfectly implemented — the exact failure mode §4 of `HANDOFF-2.md` collects, in its delegate-door form. The fix
is `-[NSWindow undoManager]` asking its delegate, and the probe asserts both halves (no delegate → nil, delegate → its
manager). §7 carries the general lesson now.

**THE NUMBERS MOVED, so §1, §2, §6 and §7 above changed with them** (§8's rule 4):

```
selectors       4021 -> 4033 of 4505   (missing 484 -> 472)
methods-declared 4546 -> 4558
NSTextView        134 -> 146 of 186    (debt 52 -> 40 — from FIRST to FOURTH largest)
tests             144 -> 145           (the new suite: 44 checks)
```

`classes`, `protocols`, `functions` and the refusal census (**292**) did not move again: no class, protocol or function
was added and no refusal was added or retired. `NSWindow`'s new `-undoManager` is an OVERRIDE of a selector it already
inherited, so the ledger's `sel:NSWindow` is unchanged — a fact worth knowing when reading the census, because it means
the instrument cannot see this slice's most important fix. The census's prose block is re-pinned from
`./tools/api-ledger census` (4033/472/4558) and its answered-history line extended.

**TRAPS AND NOTES FOR THE NEXT SESSION.**

* **`-string` IS THE ASSERTION, NOT THE FLAG.** Every claim in the new suite compares the store's text before and after,
  because a smart space that is *decided* and not *inserted* would pass a flag assertion and fail a person.
* **A GROUP WHOSE EDITS CANCEL OUT UNDOES TO NOTHING**, which is correct and looked like a bug: typing `abc` and then
  backspacing it inside ONE group leaves `""` after `-undo`, because the group's net effect is zero. The probe breaks
  coalescing between the two runs, which is what a person's pause does in the era's manager.
* **`-insertText:` ASKS `-shouldChangeTextInRange:` ABOUT THE SMART-EXPANDED STRING**, so a delegate that measures the
  replacement sees what will really arrive. That ordering is deliberate and is the reason the expansion is applied before
  the `Should` pair rather than inside the primitive.
* **NOTHING LAYS OUT ON A REDRAW**, so `-setNeedsDisplayInRect:avoidAdditionalLayout:` is a forward with a comment (§9).
  The same shape was checked here: the flag does not silently suppress anything because there is nothing to suppress.

**WHERE THE NEXT HOUR GOES.** §6's ranking is rewritten above and now starts with `NSBrowser` 64 — a real subsystem rather
than a cluster of doors — with `NSResponder` 57 and `NSWorkspace` 49 behind it. `NSTextView`'s remaining 40 is now
mostly blocked or refused; its one genuine slice left is the WORD-COMPLETION family (`-complete:`,
`-insertCompletion:forPartialWordRange:movement:isFinal:`, `-completionsForPartialWordRange:indexOfSelectedItem:`,
`-rangeForUserCompletion`).

## 11. The browser's title strip, its three frames, and the control with no cell

*Session of the ninth slice, taking §6's first item as it then stood (`NSBrowser` 64, the component's largest debt). Its
commit is "AppKit: the browser's columns have places, a title strip and a click"; tree clean; `ctest --test-dir build -j4`
green at **146 tests in 84 s** with `appkit-api-census` re-pinned in the same commit.*

**THE HEADER WAS RIGHT ABOUT THE GAP AND THE GAP WAS IN THE PIXELS.** `-titleHeight` was stored, the delegate's
`-browser:titleOfColumn:` was asked and remembered, and `NSBrowser.h` said the columns "do not draw a title strip". So the
slice is that strip: `-isTitled` (Apple's default, YES), the strip reserved out of each column's height in `-tile`, the
title drawn through `-drawTitleOfColumn:inRect:` by the document view, and **THE DOCUMENT VIEW FLIPPED** — a title belongs
above its list, a flipped document says that with y = 0 at the top, the table inside each column is flipped too so a row's
rect converts without a mirror, and a text draw in an unflipped context is a mirror this tree has already paid for.

**SEVENTEEN SELECTORS LANDED**: the three frames and `-frameOfRow:inColumn:` (which are one rect cut four ways, in the
BROWSER's coordinates because a caller wants the place on screen rather than the place in a scrolled document), the inverse
`-getRow:column:forPoint:`, `-isTitled`/`-setTitled:`, `-drawTitleOfColumn:inRect:`, the two width conversions and the two
width defaults, `-clickedRow`/`-clickedColumn` with `-doClick:`/`-doDoubleClick:`, and `-updateScroller`. `-defaultColumnWidth`
and `-setDefaultColumnWidth:` exist to be the width NEW columns get, which is the one thing `-setColumnWidth:` (re-widths
every column) does not answer.

**THE EDGES OF THE INVERSE ARE THE CLASS'S OWN SHAPE, AND SAYING SO IS THE HONEST PART.** A point in the title strip names
a COLUMN and no row. A point past the loaded columns names an EMPTY SLOT and no row, because this browser lays its 256
slots out to fill the visible width — that is the header's own design, not a bug, and the probe asserts it as such. A point
outside the document names nothing, which needed an explicit guard: without it the band walk lands in slot 3 of a 620-point
browser, because the slots continue past the document's width.

**THE FINDING: A CELL-LESS `NSControl` HAD NOWHERE TO PUT AN ACTION.** `NSControl` keeps target/action in the control's
CELL here, so `-action`/`-target` answered NULL/nil for a browser, and `-doClick:` recorded where the click landed and then
sent nothing at all. Nothing could have caught it from the outside, because nothing had checked. The browser keeps its own
pair now (where Apple's `NSControl` keeps it), and §7 carries the general trap.

**AND VERIFYING THE SLICE FOUND A PRE-EXISTING FAILURE IN THE WORKSPACE RE POSITORY, WHICH IS FIXED THERE.** The workspace's
`workspace-main-menu` case "File > Print… is the file window's row, through the chain" was failing — and it failed at HEAD
*before* this slice too, which was measured rather than assumed (rebuilt at `6bc8dbe`, the container slice, and it still
failed). Two mistakes, both in the test: it installed a stand-in target and asked the menu to update **with no key window and
no first responder**, so the walk started at nil and every chain-routed row was disabled; and it asserted the ITEM's target
was the stand-in, which a chain-routed row never has — the target is resolved when the action is SENT. The fix makes the
stand-in an `NSResponder` that accepts first responder (both opt-ins in this tier), makes it a TITLED window's first
responder (`-makeKeyWindow` is abandoned for a window that cannot become key, and borderless ones cannot), checks the row is
DISABLED with no key window and ENABLED with one, and moves the block to the END of the test because making a window key
changes what several other chain-routed rows answer. Workspace is 14 tests green again; the fix is a commit in that
repository, not this one.

**THE NUMBERS MOVED** (§8's rule 4, applied to §1, §2, §6 and §7):

```
selectors       4033 -> 4050 of 4505   (missing 472 -> 455)
methods-declared 4558 -> 4579
NSBrowser        56 -> 73 of 120       (debt 64 -> 47 — from FIRST to THIRD largest)
tests            145 -> 146            (the new suite: 40 checks)
```

`classes`, `protocols`, `functions` and the refusal census (**292**) did not move: no class, protocol or function was added
and no refusal was added or retired. The census's prose block is re-pinned from `./tools/api-ledger census`
(4050/455/4579) and the answered-history line extended to 4050.

**WHERE THE NEXT HOUR GOES.** §6's ranking is rewritten above and now starts with `NSResponder` 57 — the cheapest doors in
the component, each of which wants the same treatment `-undoManager` got: find the natural sender and give it the door.
`NSWorkspace`'s 49 is bigger but measured to have NO consumer in the workspace repository yet, and `NSBrowser`'s remaining
47 are its item-based half, which is a design decision (cell-based vs item-based) before it is a slice.
