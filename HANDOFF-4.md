# libagora-app — a fourth handoff

*Written at the end of six slices that picked `HANDOFF-3.md` up where it stopped (§9–§14 of that file are their running
record) and spent them where the earlier handoffs said to: the grid, the colour panels, the font pair, the print system,
and two slices of `NSTextView`. `HANDOFF.md`, `HANDOFF-2.md` and `HANDOFF-3.md` are still worth reading — nothing in any
of them was wrong, and the second file's §2 instrument rules and §4 traps are the ones these sessions used most. **THIS
FILE'S §2 NUMBERS SUPERSEDE `HANDOFF-3.md`'s**, which are six slices old.*

*State at this handover: **six slice commits** since the eighth handoff (and the relicense sweep that touched every file
in the meantime), tree clean, **143 tests passing in about 77 s**, `api-ledger check` holding **375 metrics** —
**131 of 168 classes (78%), 4005 of 4505 selectors (89%), 39 of 56 protocols (70%), 86 of 86 functions**, 4530 methods
declared with 8 having no body, **113 of the 129 classes with a surface at COMPLETE coverage** — refusal census **292**.*

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
selectors 4005 of 4505 (89%)   500 missing   113 of 129 classes at COMPLETE coverage
protocols  39 of  56   (70%)    17 missing
functions  86 of  86  (100%)     0 missing    10 refuse by name
methods   4530 declared on this tree's own classes, 8 with NO body on the chain (0.2%)
```

**THE 500 MISSING SELECTORS ARE STILL CONCENTRATED, AND THE CONCENTRATION HAS MOVED INWARD.** The ledger's debt list,
largest first:

```
NSTextView 68   NSBrowser 64   NSResponder 57   NSWorkspace 49   NSMenuView 37
NSFont 35       NSText 31      NSView 28        NSControl 28     NSTableView 20
NSDocument 19   NSWindow 18    NSSlider 18      NSSliderCell 17  NSDocumentController 8
NSSavePanel 3
```

Everything below `NSSliderCell` is five doors or fewer in a class that is otherwise complete. **`NSTextView` IS NOW THE
ONLY CLASS WITH A SUBSYSTEM-SIZED DEBT** — its remaining 68 are three clusters (the container/insertion-point family, the
text-checking family, and the link/services pair), described in §6.

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

1. **`NSTextView`'s remaining 68 — the CONTAINER AND INSERTION-POINT family first.** `-initWithFrame:textContainer:`,
   `-textContainer`/`-setTextContainer:`/`-replaceTextContainer:`, `-textContainerInset`/`-setTextContainerInset:`,
   `-textContainerOrigin`/`-invalidateTextContainerOrigin`, `-setConstrainedFrameSize:`, `-drawViewBackgroundInRect:`,
   `-drawInsertionPointInRect:color:turnedOn:`, `-shouldDrawInsertionPoint`,
   `-updateInsertionPointStateAndRestartTimer:`, `-insertionPointColor`/`-setInsertionPointColor:`,
   `-setNeedsDisplayInRect:avoidAdditionalLayout:`, and `-characterIndexForInsertionAtPoint:`. **THE LAST ONE IS THE
   KEY**: it needs the layout manager's point-to-glyph door, and adding that door retires the "a drop lands at the
   insertion point" limit the clipboard slice recorded and gives the container family its arithmetic.
2. **The rest of `NSTextView`**: the LINK/SERVICES pair (`-clickedOnLink:atIndex:`, `-displaysLinkToolTips`,
   `-registerForServices`) which needs a link attribute constant; and the TEXT-CHECKING family (`-checkTextIn…`,
   `-enabledTextCheckingTypes`, `-handleTextCheckingResults:…`, the three automatic-detection toggles), which is BLOCKED
   on `NSTextCheckingResult`/`NSOrthography` — Foundation here has neither, and the asynchronous spell door already
   refuses for exactly that reason. **Do not open the checking family before Foundation has the classes**; the honest
   move is to name them absent and keep the flags refusing.
3. **`NSBrowser` 64.** The Workspace's column view is a table-backed browser; the class itself is a table per column and
   the remaining 64 are its delegate/data-source surface, drag and column management. It is the second-largest single
   debt and the one a file manager would feel.
4. **`NSResponder` 57.** Mostly the chain forwarders and the standard key-binding commands; each is small, and the
   census credits them to `NSResponder`, not to the views that inherit them.
5. **`NSWorkspace` 49.** The shell verbs: open/reveal, file operations, the running-application list. `libagora-launchservices`
   and `libagora-iconservices` are the seams, and the Workspace component is the caller.
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
* **THE SUITE IS 143 TESTS IN ABOUT 77 SECONDS, AND `ctest --test-dir build -j4` IS THE GATE.** The exit status is the
  witness, not the tail of the output.

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
