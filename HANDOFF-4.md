# libagora-app — a fourth handoff

*Written at the end of six slices that picked `HANDOFF-3.md` up where it stopped (§9–§14 of that file are their running
record) and spent them where the earlier handoffs said to: the grid, the colour panels, the font pair, the print system,
and two slices of `NSTextView`. `HANDOFF.md`, `HANDOFF-2.md` and `HANDOFF-3.md` are still worth reading — nothing in any
of them was wrong, and the second file's §2 instrument rules and §4 traps are the ones these sessions used most. **THIS
FILE'S §2 NUMBERS SUPERSEDE `HANDOFF-3.md`'s**, which are six slices old.*

*State at this handover: **twelve slice commits** since the eighth handoff (and the relicense sweep that touched every
file in the meantime), tree clean, **149 tests passing in about 84 s**, `api-ledger check` holding **375 metrics** —
**131 of 168 classes (78%), 4135 of 4505 selectors (92%), 39 of 56 protocols (70%), 86 of 86 functions**, 4663 methods
declared with 8 having no body, **114 of the 129 classes with a surface at COMPLETE coverage** — refusal census **311**.*
*(`HANDOFF-3.md`'s §2 numbers are eight slices older than these; the numbers in this file's §2 are current as of §14.)*

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
selectors 4135 of 4505 (92%)   370 missing   114 of 129 classes at COMPLETE coverage
protocols  39 of  56   (70%)    17 missing
functions  86 of  86  (100%)     0 missing    10 refuse by name
methods   4663 declared on this tree's own classes, 8 with NO body on the chain (0.2%)
```

**THE 370 MISSING SELECTORS ARE STILL CONCENTRATED, AND `NSBrowser` IS STILL FIRST — BUT ITS REMAINDER IS NO LONGER THE
ITEM MODEL.** The ledger's debt list, largest first:

```
NSBrowser 37     NSTextView 39   NSMenuView 37    NSFont 35      NSWorkspace 32
NSText 31        NSView 28       NSControl 28     NSTableView 20   NSDocument 19
NSWindow 18      NSSlider 18     NSSliderCell 17  NSDocumentController 8   NSSavePanel 3
```

Everything below `NSSliderCell` is five doors or fewer in a class that is otherwise complete. **FIVE CLASSES HAVE LEFT
THE DEEPEST-DEBT LIST IN FIVE SLICES**: `NSTextView` 68 → 52 (§9) → 40 (§10) → 39 (§12, an INHERITANCE effect rather than
an implementation), `NSBrowser` 64 → 47 (§11) → 37 (§14, the item model), `NSResponder` 57 → **0** (§12, the first class
to reach COMPLETE coverage from the top of the list), and `NSWorkspace` 49 → 32 (§13). What is left of `NSBrowser` is the
DRAG and FURNITURE half; what is left of `NSTextView` is almost entirely blocked or refused.

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

1. **`NSBrowser` 37 — still the largest debt, and now the DRAG AND FURNITURE half.** §14 answered the item-model
   question (the protocol advertises the 10.6 contract; the cell contract is the fallback), so what is left is
   `-canDragRowsWithIndexes:inColumn:withEvent:`, `-draggingImageForRowsWithIndexes:inColumn:withEvent:offset:`,
   `-setDraggingSourceOperationMask:forLocal:`, `-editItemAtIndexPath:withEvent:select:`,
   `-reloadDataForRowIndexes:inColumn:`, `-noteHeightOfRowsWithIndexesChanged:inColumn:`, `-addColumn`, `-displayColumn:`,
   `-displayAllColumns`, `-lastColumn`/`-setLastColumn:`, `-isLoaded`, `-scrollColumnsLeftBy:`/`-scrollColumnsRightBy:`,
   `-scrollViaScroller:`, `-updateScroller`, the autosave trio, `-reusesColumns`, `-prefersAllColumnUserResizing`,
   `-sendAction`, `-doClick:`/`-doDoubleClick:` (done), and `-matrixClass`/`-setMatrixClass:`/`-matrixInColumn:`/
   `-columnOfMatrix:` — **those four must REFUSE by name and say why: this browser's columns are TABLES, and a matrix is
   what Apple's own columns were; the header already carries that decision, and a refusal is the disposition it owes.**
   The DRAG doors are what a file manager feels next.
2. **`NSTextView`'s remaining 39**, which are now almost all BLOCKED or REFUSED rather than absent: the TEXT-CHECKING
   family (`-checkTextIn…`, `-enabledTextCheckingTypes`, `-handleTextCheckingResults:…`, the three automatic-detection
   toggles) is blocked on `NSTextCheckingResult`/`NSOrthography`, which Foundation here has not got; the LINK/SERVICES
   pair needs a link attribute constant and a services transport; `-startSpeaking:`/`-stopSpeaking:` are speech, refused
   by name; the five `-orderFront…Panel:` doors are panels this tier has not built; and `-complete:`/`-insertCompletion:`
   are the WORD-COMPLETION family, which is the one cluster there that is genuinely a slice. **Do not open the checking
   family before Foundation has the classes** — name them absent and keep the flags refusing.
3. **`NSWorkspace` 32 — the largest remaining class-shaped gap, and now WITH A CALLER** (§13): the file window opens a
   document through `-openFile:` instead of calling Launch Services itself. What is left is the file-operation family
   (`-performFileOperation:source:destination:files:tag:`, `-recycleURLs:completionHandler:`,
   `-duplicateURLs:completionHandler:`, `-openTempFile:`), the Finder-service doors
   (`-selectFile:inFileViewerRootedAtPath:`, `-activateFileViewerSelectingURLs:` — which need the Workspace to be
   TELLABLE across processes, i.e. a session), the volume and media doors (`-mountedRemovableMedia`,
   `-unmountAndEjectDeviceAtURL:error:`, `-getFileSystemInfoForPath:…` — DiskArbitration), the desktop-picture pair, the
   labels, and the change-notification family. **The file operations are the honest next slice** — plain filesystem
   verbs — but the TRASH MUST NOT BE DUPLICATED: the Workspace's `WSTrash` owns the directories, the Put Back records and
   the empty, so an AppKit `-recycleURLs:completionHandler:` either agrees with that rule or states why it is a
   different one.
4. **`NSMenuView` 37 and `NSFont` 35**, which are thin classes rather than subsystems: the menu view is the popup's own
   drawing surface (37 doors, most of them `NSMenuView.NSDeprecated`'s), and `NSFont`'s 35 are the descriptor and traits
   surface — **with the recorded caveat that this tree's FONT DESCRIPTORS CARRY NO TRAITS** (§4), so the traits family
   must read the FACE (`CTFontGetSymbolicTraits`, `CTFontCopyTraits`) rather than the descriptor.
5. **`NSText` 31**, which are siblings of the text-view work: the RTF write/read pair (`-RTFFromRange:`,
   `-replaceCharactersInRange:withRTF:`, …), `-changeFont:`/`-copyFont:`/`-pasteFont:`, the resizability and size limits
   (`-minSize`, `-maxSize`, the two flags), and `-showGuessPanel:`.
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
* **THE SUITE IS 149 TESTS IN ABOUT 84 SECONDS, AND `ctest --test-dir build -j4` IS THE GATE.** The exit status is the
  witness, not the tail of the output.
* **`NSBrowser` HAS TWO DELEGATE CONTRACTS AND A DELEGATE IMPLEMENTS ONE.** `-browser:numberOfChildrenOfItem:` decides
  which: with it the browser is ITEM-based (model objects, browser-made cells); without it CELL-based (rows and cells the
  delegate fills). The one allowed overlap is a styling `-browser:willDisplayCell:atRow:column:` on top of the browser's
  item-made cell. The ROOT of the item model is `nil`, and no item is ever retained — they belong to the delegate.
* **A HEADER EDIT THAT REPLACES A BLOCK CAN DELETE DECLARATIONS SILENTLY.** §13 replaced the icon block in
  `NSWorkspace.h` and took `-iconForFile:` and `-iconForFileType:` with it: the compiler only warns at a call site, the
  bodies were still in the `.m`, and the probe passed because it called `-iconForFiles:`. The only witness was the
  census — seventeen declarations added and `methods-declared` moved by fifteen. **A per-class declaration count against
  the previous parse names the class and the selectors in one diff**; do it whenever a header block is rewritten rather
  than appended to.
* **AN UNDECLARED COMMAND IS UNREACHABLE, NOT MERELY UNIMPLEMENTED.** A key binding names a SELECTOR; if no header declares
  it, no binding can name it and no chain can deliver it — so a command family "left to the class that will implement it"
  is a family that does not exist. §12 declared the era's whole set on `NSResponder` and forwarded every one; that is
  cheap, honest, and it is what let the Page Up/Down binding finally name something.
* **A COMMENT EXPLAINING WHY SOMETHING IS ABSENT IS A CLAIM WITH A SHELF LIFE.** `NSTextInputContext`'s page binding said
  "this tier has no viewport" for three slices after the clip view arrived. When a refusal's or a limit's reason names a
  MISSING PIECE, grep for that piece before trusting the comment — the piece may already be here.
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

## 12. The era's command set, and a key binding whose reason had expired

*Session of the tenth slice, taking §6's first item (`NSResponder` 57, the cheapest doors). Its commit is "AppKit: the
era's command set, and the page keys that finally land"; tree clean; `ctest --test-dir build -j4` green at **147 tests in
84 s** with `appkit-api-census` re-pinned in the same commit.*

**THE 57 WERE NOT REFUSED, THEY WERE UNNAMEABLE.** A command is a selector a key binding names and a chain delivers; a
selector no header declares cannot be named, so the family was unreachable regardless of who could have answered it.
`NSResponder` declares the whole 10.6 set now — the movement families, the three unit selections, paging and scrolling,
the mark and kill ring, the case four, the six writing-direction doors, and the insertions whose model is still absent —
and **every body is one `-nextResponder:` send**. `NSResponder` is COMPLETE for the era: **145 of 145**.

**AND THE FIRST BINDING TO BENEFIT HAD A WRITTEN EXCUSE THAT HAD GONE STALE.** `NSTextInputContext` mapped Page Up/Down to
nothing with the comment *"a page is a viewport's height and this tier has no viewport — a clip view and its document
height are a later slice"*. The clip view, the wrapped document and `-scrollRangeToVisible:` had all arrived; the comment
had not. Page Up/Down name `-pageUp:`/`-pageDown:` now (Shift for the extensions), Option-Up/Down name the paragraph pair,
and `NSTextView` answers them: **a page is the clip view's height in lines**, the caret moves that many VISUAL lines on its
own column and the view follows, and both clamp at the document's ends.

**THE SCROLL FAMILY IS THE OTHER HALF AND IS DELIBERATELY DIFFERENT**: `-scrollPageUp:`/`-scrollPageDown:`/
`-scrollLineUp:`/`-scrollLineDown:`/`-scrollToBeginningOfDocument:`/`-scrollToEndOfDocument:`/`-centerSelectionInVisibleArea:`
move the VIEWPORT and leave the insertion point where it is. Each is `-scrollRectToVisible:` with a rect the size of the
visible area, so the clamping is the clip view's own arithmetic rather than a second copy of it.

**THE PARAGRAPH IS THE MODEL LINE.** `-moveToBeginningOfParagraph:` and its five siblings, the three unit selections and
the two deletions are all over the newline-terminated run, so moving to a paragraph's end crosses every wrap — the probe
uses a 165-character paragraph that the view lays out as eight visual lines. The unit selections are the existing
granularity door one line deep (so a menu item and a double-click cannot disagree), the deletions go through the edit path
(so they are undoable and the delegate is asked), and the three base-direction commands set the paragraph style while the
three text-direction ones stay forwarded and unanswered (a run's own direction is an attribute this tier has not built).

**TWO TRAPS, BOTH PAID FOR BY THE PROBE.**

* **A TEST ASSERTED THAT A FORWARDER EXISTS RATHER THAN THAT THE MESSAGE ARRIVED.** `-respondsToSelector:` for all
  fifty-seven would restate the census and prove nothing about the bodies. The recorder registers a SINGLE C function for
  all 57 selectors with `class_addMethod`, records `_cmd`, and the assertion becomes "the message reached the end of the
  chain" — which is the contract, and which fails if a body forwards the wrong selector, as one of mine did while the
  table was being typed.
* **THE CARET'S `-firstRectForCharacterRange:` IS IN SCREEN COORDINATES AND THE CLIP VIEW'S BOUNDS ARE IN THE DOCUMENT'S.**
  Comparing them directly produced "caret at 37, viewport middle at 464" and looked like a centring bug; converting the
  rect back into the view first (subtract the window's origin, `-convertPoint:fromView:nil`) made the two comparable. That
  conversion is the same pair `-characterIndexForPoint:` already spells.

**THE NUMBERS MOVED** (§8's rule 4, applied to §1, §2, §6 and §7):

```
selectors       4050 -> 4108 of 4505   (missing 455 -> 397)
methods-declared 4579 -> 4636
NSResponder      88 -> 145 of 145      (COMPLETE — off the debt list)
NSTextView       146 -> 147 of 186     (debt 40 -> 39, an INHERITANCE effect: `-complete:` left the list
                                        because the base declares it now, not because anything implements it)
tests            146 -> 147            (the new suite: 34 checks)
classes-complete 113 -> 114 of 129
```

`classes`, `protocols`, `functions` and the refusal census (**292**) did not move: no class or protocol appeared, no
function was added, and no refusal was added or retired — the doors whose model is absent are declared-and-forwarded
rather than refused, and the header says exactly which they are.

**WHERE THE NEXT HOUR GOES.** §6's ranking is rewritten above: `NSWorkspace` 49 is the largest debt now and the only
class-sized one left, but §11 measured that nothing in the workspace repository calls it — so a slice there should take
the verbs the FILE WINDOW needs (open, reveal, move to trash) AND wire one of them to the Workspace, or the doors will be
bodies without callers. `NSBrowser`'s 47 are its item-based half (a design decision first). `NSTextView`'s 39 are almost
all blocked on Foundation or on panels this tier has not built.

## 13. `NSWorkspace`'s launch verbs, the refusals beside them, and the caller they gained

*Session of the eleventh slice, taking §6's first item as it then stood (`NSWorkspace` 49, with the instruction to wire a
verb to the Workspace). Its commit is "AppKit: the launch verbs, the deprecated dictionaries and the refusals beside
them"; tree clean; `ctest --test-dir build -j4` green at **148 tests in 84 s** with `appkit-api-census` re-pinned in the
same commit.*

**THE FIRST THING THIS SLICE DID WAS NOTICE THAT §11'S OWN NOTE WAS STILL TRUE**: nothing in the workspace repository
called `NSWorkspace`, and it had a copy of the launch decision instead — `-openItem:` built a `CFURL` and called
`LSOpenCFURLRef` itself. **THE CALLER CAME FIRST**: the file window opens a document through
`[[NSWorkspace sharedWorkspace] openFile:]` now, which is the Workspace repository's commit, and it is what makes the
doors below worth having.

**SEVENTEEN DOORS, IN THREE KINDS.** The LAUNCH VERBS are real, because Launch Services answers them:
`-URLForApplicationWithBundleIdentifier:` (the modern spelling of the deprecated path door),
`-fullPathForApplication:` (an absolute path, a bundle identifier, or a plain name searched in four written-down
directories), `-launchApplication:showIcon:autolaunch:` (the 10.6 spelling; its two flags are named and not read),
`-launchApplicationAtURL:options:configuration:error:` (Apple's funnel: options are the launch flags passed to the seam,
the configuration dictionary has no counterpart and is not read, and a Launch Services refusal becomes an `NSError`),
and the two DEPRECATED DICTIONARIES derived from the live list with Apple's own keys and a process identifier of zero.
The FILE AND ICON QUESTIONS beside them: `-iconForFiles:` (the first path's picture — a stack is a drawing this tier has
no composition for) and `-getInfoForFile:application:type:` (the handler's path and the path's extension).

**NINE DOORS REFUSE BY NAME, IN TWO FAMILIES, AND EACH NAMES THE PIECE THAT IS MISSING.** The five TYPE QUESTIONS need a
UTI DATABASE, which Launch Services here has not got (it maps bundles to the types they claim and offers a kind string);
dressing an extension up as a UTI would be a wrong answer that looks right. The two `-openFile:withApplication:` doors
and `-openURLs:withAppBundleIdentifier:…` need a LAUNCH SPECIFICATION in the seam — `LSOpenCFURLRef` launches an
application or opens an item in its DEFAULT handler, and there is no argument for "this application, this file"; spawning
a process from AppKit to fake one would put a second launcher in the tree. `-hideOtherApplications:` needs a HIDE VERB in
the window server, where activation is per-surface.

**THE TRAP IS THE ONE THAT MATTERS, AND THE CENSUS IS WHAT CAUGHT IT.** Replacing the icon block in `NSWorkspace.h` to
insert the new doors DELETED `-iconForFile:` and `-iconForFileType:` — they were not in the replacement text. It
compiled (Object-C only warns at a call site), the bodies were still in the `.m`, and the probe passed because it calls
`-iconForFiles:`. What caught it was the arithmetic: seventeen declarations added, `methods-declared` up by FIFTEEN. A
per-class declaration count against the previous parse — `parse_tree` twice, one `diff` — named `NSWorkspace 12 → 27`
and the two selectors in one line. §7 carries it as a general rule now: **a header block REPLACED rather than appended to
is the one edit the compiler is silent about.**

**THE NUMBERS MOVED** (§8's rule 4, applied to §1, §2, §6 and §7):

```
selectors       4108 -> 4125 of 4505   (missing 397 -> 380)
methods-declared 4636 -> 4653
NSWorkspace      9 -> 26 of 58         (debt 49 -> 32 — FIRST to FIFTH largest)
refusal census   292 -> 311            (nine new named refusals in NSWorkspace.m, and the needle
                                       widened: ten pre-existing helper refusals it had missed)
tests            147 -> 148            (the new suite: 39 checks)
```

`classes`, `protocols` and `functions` did NOT move. The refusal census DID move this time and upward, which is the
documented behaviour of a census rather than a ratchet (§3): nine doors that used to be absent are now NAMED refusals, so
a caller gets a reason instead of a link error. `tests/api-10.6-census.txt` is re-pinned from
`./tools/api-ledger census` (4125/380/4653) and its answered-history line extended.

**WHERE THE NEXT HOUR GOES.** §6's ranking is rewritten above: `NSBrowser` 47 is the largest debt and its remaining half
is a design question; `NSTextView` 39 is almost all blocked or refused; and `NSWorkspace`'s remaining 32 are mostly the
FILE-OPERATION family, which is the honest next slice — plain filesystem verbs, **except that the TRASH MUST NOT BE
DUPLICATED**: the Workspace's `WSTrash` owns the directories, the Put Back records and the empty, so an AppKit
`-recycleURLs:completionHandler:` has to agree with that rule or say why it is a different one.

## 14. The browser advertises the 10.6 item model, and the cell model becomes its fallback

*Session of the twelfth slice. Unlike the others it began with a DECISION rather than a measurement: §11 had left
"`NSBrowser`'s remaining 47 are its item-based half, which is a design decision (cell- vs item-based) before it is a
slice", and the instruction was **"advertise the 10.6 one, not the NeXT one."** Its commit is "AppKit: the browser
advertises the 10.6 item model"; tree clean; `ctest --test-dir build -j4` green at **149 tests in 84 s** with
`appkit-api-census` re-pinned in the same commit.*

**THE DECISION AND WHAT IT MEANS CONCRETELY.** Apple has carried two delegate contracts on this class since 10.6: the
NeXT-era CELL contract (rows per column, delegate fills each cell) and the ITEM contract (the delegate answers with model
objects, the browser makes the cells). This tree had declared and asked only the cell one. The slice declares the item
doors — `-browser:numberOfChildrenOfItem:`, `-browser:child:ofItem:`, `-browser:isLeafItem:`,
`-browser:objectValueForItem:` — makes them the ones the browser ASKS FIRST, and leaves the cell doors declared and
working as the FALLBACK. That is Apple's own two-contract shape rather than a rewrite, and it is why the Workspace's
`WSColumnView` (written against the cell doors) needed no edit: its fourteen tests stayed green without being touched.

**TEN SELECTORS: the six walking doors and the four selection-path ones.** `-itemAtRow:inColumn:` (row −1 answers the
parent), `-itemAtIndexPath:`, `-parentForItemsInColumn:`, `-isLeafItem:`, `-indexPathForColumn:` (the path of the item
WHOSE CHILDREN a column shows — Apple's wording, and the reading that makes the walk terminate), `-pathToColumn:`,
`-selectionIndexPath`/`-setSelectionIndexPath:`, `-selectionIndexPaths`/`-setSelectionIndexPaths:`. Every reading door
follows `-browser:child:ofItem:` FROM NIL over the selected rows the class already keeps, so **there is no item cache to
fall out of step with the delegate and no item is retained** — items belong to the delegate, which is Apple's rule as
much as the seam's. Setting a path drives `-selectRow:inColumn:` down it, so the columns load exactly as a click loads
them, and a row past the end stops the walk instead of selecting a phantom.

**AND THE CELLS ARE THE BROWSER'S NOW** for an item-based delegate: `-tableView:willDisplayCell:forTableColumn:row:` asks
`-browser:objectValueForItem:` for the value and `-browser:isLeafItem:` for the branch flag, then still offers the styling
door — the one overlap Apple allows between the contracts.

**THE TWO PROBE TRAPS, both cheap and both worth the paragraph.** A nil check written as
`[[browser parentForItemsInColumn:0] isEqual:nil]` FAILS WHETHER OR NOT THE DOOR IS RIGHT — the message goes to nil and
answers nil — which is the "passes for the wrong reason" failure inverted: one that fails for the wrong reason. And a
selection assertion written before a later section had selected a second column was measuring a stale expectation rather
than a bug (the path really was two positions long). Both fixes were in the test, and both are the kind of thing a
recorded trap saves the next session.

**THE NUMBERS MOVED** (§8's rule 4):

```
selectors       4125 -> 4135 of 4505   (missing 380 -> 370)
methods-declared 4653 -> 4663
NSBrowser        73 -> 83 of 120       (debt 47 -> 37)
tests            148 -> 149            (the new suite: 40 checks)
```

`classes`, `protocols`, `functions` and the refusal census (**311**) did not move — the item doors are declared on the
protocol that already existed, so no protocol appeared, and nothing new refuses.

**AND A NOTE ON THE INSTRUMENT, LEARNED IN §13 AND CONFIRMED HERE.** The API census counts SELECTORS on CLASSES: Apple's
`NSBrowserDelegate` doors are invisible to it (the manifest has 5208 selector lines, none of them a protocol's). So the
four item doors this slice declared move only `methods-declared` by their own count, and the *delegate surface* — which
is the whole point of the slice — is held by the header's prose and by `tests/browser_items.m` alone. A future instrument
that reads protocol bodies would be measuring something the census has never measured.

**WHERE THE NEXT HOUR GOES.** `NSBrowser` 37: the DRAG doors first (`-canDragRowsWithIndexes:inColumn:withEvent:`,
`-draggingImageForRowsWithIndexes:inColumn:withEvent:offset:`, `-setDraggingSourceOperationMask:forLocal:`,
`-editItemAtIndexPath:withEvent:select:`) — a file manager's browser drags rows between columns — and then the furniture
(`-reloadDataForRowIndexes:inColumn:`, `-addColumn`, `-displayColumn:`, `-lastColumn`, the scroll pair, the autosave
name). **The `-matrixClass`/`-matrixInColumn:`/`-columnOfMatrix:` trio should REFUSE by name** with the reason the header
already gives: this browser's columns are tables, and a matrix is what Apple's own columns were.
