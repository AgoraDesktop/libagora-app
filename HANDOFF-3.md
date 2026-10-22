# libagora-app — a third handoff

*Written at the end of eight sessions that picked `HANDOFF-2.md` up where it stopped (§13 of that file is the first of
them, and §13–§20 are their running record) and spent them where that document said to: the completion sweep's second part,
then the peripherals, the image family, the text layer, the input sources, the cell's own edit session, and one seam the
earlier handoffs had left named but unsent. This file is written for whoever picks the tree up next — what exists now, what
it cost, and where the next hour is best spent. `HANDOFF.md` and `HANDOFF-2.md` are still worth reading: nothing in either
was wrong, and the second file's §2 instrument rules and §4 traps are the ones these sessions used most.*

*State at this handover: **8 commits** since the seventh handoff — commits 24 to 31 of the pickup that began at `HANDOFF.md` —
tree clean, **137 tests passing in ~64 s**,
`api-ledger: 362 metrics hold — 117 of 168 classes, 3543 of 4112 selectors (86%), 35 of 56 protocols, 86 of 86 functions,
4031 methods declared with 8 having no body**, **99 of the 115 classes with a surface at COMPLETE coverage**, refusal census
**288**.*

---

## 1. What these sessions did

Eight commits, one slice each, in the order they landed.

| Commit | What it landed |
|---|---|
| `5ec9cc4` | **The completion sweep's part 2** — `NSButton` 39/39, `NSButtonCell` 55/55, `NSScrollView` 55/55, `NSScroller` 23/23, `NSProgressIndicator` 27/27 (51 selectors). The button's face split into Apple's three ink doors, `-gradientType` shading, per-axis scroll steps, a scroller that knows which parts FIT, and a caller-driven spinner. |
| `9e9759d` | **The combo box's rows** — `NSComboBox` 37/37, `NSComboBoxCell` 36/36, three protocols. A data source with one pair of private row doors, `-completes` that actually completes, and a list whose `-itemHeight`/`-intercellSpacing` reach `NSMenu`'s row arithmetic. |
| `3d6bd12` | **The image family** — `NSImage` 77/77, `NSImageRep` 40/40, `NSBitmapImageRep` 41/41. One drawing door (crop, operation, fraction, orientation, hints), a background, a delegate, and the registry's type lists. |
| `bd6e293` | **The four peripherals** — `NSAlert` 27/27, `NSStatusItem` 30/30, `NSRunningApplication` 21/21, `NSBrowserCell` 13/13, plus `NSAlertDelegate`. The alert's suppression box and help button, a status item that draws itself and FIRES ITS ACTION, a pid, and a branch chevron. |
| `0ea2dd3` | **The text layer's whole surface** — `NSTextStorage` 25/25, `NSTextBlock` 21/21, `NSSpellChecker` 39/39. The pre-attributed-string API, a block's own content width, the substitution tables, and a guesser that had never worked. |
| `282ac1c` | **The input sources** — `NSTextInputContext` 16/16. The keyboard layouts as an input-source registry, MEASURED with xkbcommon. |
| `11cf7c5` | **The cell's edit session and the application's last seven** — `NSCell` 148/148, `NSApplication` 95/95. The field-editor family on the base cell, the number format, the responder-chain target, the Help search, and the two modal relatives. |
| `5c67f07` | **The menu's delegate** — `NSMenuDelegate` declared and SENT (`-menuWillOpen:`, `-menu:willHighlightItem:`, `-menuDidClose:`), which gave `-comboBoxSelectionIsChanging:` the sender it had been waiting two slices for. |

Plus, in the workspace, the gitlink advanced after each; and the component's `README.md` grew one section per slice and
`HANDOFF-2.md` one numbered section per session.

---

## 2. The surface, measured

```
classes   117 of 168   (70%)    51 missing   (of which ONE is Foundation's — see §7)
selectors 3543 of 4112 (86%)   569 missing   99 of 115 classes with a surface at COMPLETE coverage
protocols  35 of  56   (62%)    21 missing
functions  86 of 86  (100%)      0 missing    10 refuse by name
methods   4031 declared on this tree's own classes, 8 with NO body on the chain (0.2%)
```

**THE 569 MISSING SELECTORS ARE CONCENTRATED, AND THE CONCENTRATION IS IN CLASSES THIS TREE ALREADY HAS.** The ledger's
debt list, largest first: `NSTextView` 126, `NSBrowser` 64, `NSResponder` 57, `NSWorkspace` 49, `NSMenuView` 37, `NSFont`
35, `NSText` 31, `NSDocument` 30, `NSView` 28, `NSControl` 28, `NSTableView` 20, `NSWindow` 18, `NSSlider` 18,
`NSSliderCell` 17, `NSDocumentController` 8, `NSSavePanel` 3 — and everything below that is five doors or fewer in a
class that is otherwise complete.

**THE 51 ABSENT CLASSES GROUP CLEANLY, AND THE GROUPS ARE SUBSYSTEMS RATHER THAN LOOSE DOORS:**

| Group | Classes | What it needs |
|---|---|---|
| Editors and containers | `NSMatrix`, `NSForm`, `NSFormCell`, `NSImageView`, `NSDrawer`, `NSCollectionView`, `NSRuleEditor`, `NSPredicateEditor`, `NSPredicateEditorRowTemplate`, `NSTokenField`, `NSTokenFieldCell`, `NSTouch`, `NSTreeNode` | real views. `NSMatrix`/`NSForm`/`NSFormCell` is 134 selectors and is the largest single piece left. |
| Printing | `NSPrintInfo`, `NSPrintOperation`, `NSPrintPanel`, `NSPageLayout`, `NSPrinter` | a print system. It is the absence recorded in more refusals than any other. |
| Controllers / bindings | `NSController`, `NSObjectController`, `NSArrayController`, `NSDictionaryController`, `NSUserDefaultsController`, `NSTreeController` | KVO/KVC substrate — a design question before it is a slice. |
| Colour and font panels | `NSColorPanel`, `NSColorPicker`, `NSColorList`, `NSColorWell`, `NSFontPanel`, `NSFontManager` | panels whose content is `NSColorSpace`/`NSFont`, both of which exist. |
| OpenGL | `NSOpenGLContext`, `NSOpenGLLayer`, `NSOpenGLPixelBuffer`, `NSOpenGLPixelFormat`, `NSOpenGLView` | GL. Declared refusals per the plan's §A11. |
| Typesetters | `NSTypesetter`, `NSATSTypesetter`, `NSSimpleHorizontalTypesetter`, `NSGlyphGenerator` | Core Text does both jobs here; the plan says refuse. |
| Speech and sound | `NSSpeechSynthesizer`, `NSSpeechRecognizer`, `NSSound` | platform services. |
| QuickDraw-era and movies | `NSQuickDrawView`, `NSMovie`, `NSMovieView` | refuse per §A11. |
| Input managers, dock tile, help, persistent documents | `NSInputManager`, `NSInputServer`, `NSDockTile`, `NSHelpManager`, `NSPersistentDocument` | one subsystem each. |

**THE 21 MISSING PROTOCOLS ARE ALMOST ALL CONTRACTS FOR CLASSES IN THAT TABLE.** The exceptions are the four whose
classes DO exist and which this tree could send tomorrow: `NSTextViewDelegate` (the view has a delegate property and a text
delegate it inherits), `NSIgnoreMisspelledWords` and `NSChangeSpelling` (the field editor's spelling menus), and
`NSUserInterfaceItemSearching` (the application already has a search-handler registry). Each is a small slice, and each
must follow the rule §5 states: declare it AND say which messages are sent.

---

## 3. The instrument, which is still the deliverable

Three censuses and one ledger, all committed and all gated by `ctest`:

| Artifact | What it is |
|---|---|
| `api/10.6/appkit-manifest.txt` | the SDK's facts: 168 classes + superclasses, 56 protocols, 87 functions, 5208 selectors. |
| `tests/api-10.6-census.txt` | 362 pinned metrics — eight aggregates, one `sel:` line per class, one `proto:` line per protocol, `fn:`/`fndecl:` per function, `selphantom:` per class. |
| `tests/api_census.cmake` | the gate: two-directional comparison, arithmetic check, two fault checks. |
| `tests/refusal_census.txt` | 288 refusal sites, per FILE. |
| `tests/owed_census.txt` | the headers' OWED notes, per file. |
| `tools/api-ledger` | the parser: `manifest`, `census`, `check`, `missing`. |

**ONE INSTRUMENT WAS CORRECTED, AND THE CORRECTION IS THE REASON ITS NUMBER MOVED.** The refusal census counted only the
`APPKIT-REFUSE` literal, so every refusal written through `fn_refuse_window` — the shared helper `AppKitRefusal.h` exists
for, and therefore every NEW refusal — moved no number at all. The needle is now
`(APPKIT-REFUSE|fn_refuse_window)`, and the census went 141 → 267 in that commit with NO refusal added or removed by the
widening. It has risen to 288 since, one to eight per slice, every time deliberately.

**AND EVERY SLICE RE-PINS DELIBERATELY.** The recipe has not changed: let `ctest -R appkit-api-census` fail, recompute the
census with `./tools/api-ledger census …`, write it in the same commit, and recompute the four hand-written summary lines
at the top of the file from the numbers rather than editing them by eye. The same for a refusal that became a door (the
census falls) or a door that became a refusal (it rises).

---

## 4. Traps these sessions paid for

Recorded because each cost time and each is the same shape as a trap already in `HANDOFF-2.md` §4.

**THE RUNTIME AND THE LAYER, MEASURED RATHER THAN ASSUMED:**

* **`NSText -string` ANSWERS THE LIVE MUTABLE STRING.** The combo box's completion read the typed length, called
  `-setString:`, then computed the suffix from `[typed length]` — which was now the COMPLETED length. The selection came out
  `(6,0)`, a caret at the end, instead of `(2,4)`, the offer selected. **Take the number before the edit.**
* **THIS LAYER'S ERROR-KEY *VALUES* ARE NOT APPLE'S.** `NSLocalizedDescriptionKey` is the string
  `"NSLocalizedDescriptionKey"`; `NSLocalizedFailureReasonKey` is `"NSLocalizedFailureReason"` — one with the suffix and one
  without. A test that writes the literals reads NOTHING and the failure looks like `+alertWithError:` being broken. Use
  the constants.
* **`-string`'s relatives:** `[[word mutableString] copy]` is a crash — this `NSString` has no `-mutableString` — and
  `-[NSAttributedString attributes]` is not implemented (ask at an index). Both were found by calling a door no test had
  ever called.
* **A CLASS CAN BE DECLARED AND STILL BE ABSENT.** `NSTextCheckingResult` and `NSOrthography` do not exist in this
  Foundation, which is why the asynchronous spell-check door is a named refusal; the compiler accepts a message to a
  `@class`-forward-declared class and the runtime sends it to Nil, so a door returning one compiles and then answers
  nothing. **Check that the class exists before writing the door that returns one.**

**DOORS THAT HAD NEVER BEEN CALLED:**

* **`-guessesForWordRange:…` WAS BROKEN TWICE OVER.** It crashed in `[[word mutableString] copy]`, and once fixed it
  answered six guesses for "helo" with none of them "hello" — its own comment promised an insertion pass the code did not
  have. A comment is not an implementation; a probe that calls the door is.
* **`-initTextCell:` STORED ONLY HALF THE STRING.** It set the cell's TITLE and left the object value nil, so
  `[[NSCell alloc] initTextCell:@"hello"]` answered `-stringValue` of nil, and the edit session handed the editor an empty
  string. A text cell has ONE string; both doors are views of it.
* **A MENU SESSION WITH NO RUN LOOP WAS NEVER CLOSED.** `-popUpMenuPositioningItem:` skips the tracking loop when the
  application is not running — and that loop's end is what calls `-cancelTracking` — so `_tracking` stayed YES, the window
  stayed up and the pointer grab stayed taken for the life of the process. Invisible until a delegate existed to notice
  `-menuDidClose:` never arrived.

**ARITHMETIC THAT ONLY A PIXEL OR A SEQUENCE SHOWS:**

* **A SCROLL VIEW GIVEN ITS BARS BEFORE ITS DOCUMENT WAS LEFT AT A NEGATIVE ORIGIN.** The centring rule read a
  document-less clip view's empty extent as a zero-sized document and answered `-(clip - 0)/2`; the first line step then
  clamped to 0 instead of stepping. `-constrainScrollPoint:` now leaves a document-less origin alone, and an arriving
  document is CLAMPED (not centred).
* **`autoRange` IS A MAXIMUM WIDTH, NOT A ZERO-PADDED ONE.** `-setFloatingPointFormat:YES left:2 right:2` renders 1.5 as
  `" 1.50"`; the first test asserted `"01.50"` and **the door was right**.
* **`NSTextBlock`'s TWO ENUMS CANNOT BE SPELLED THE WAY APPLE SPELLS THEM.** The LAYER enum's three values and the
  DIMENSION word's three layer bits share one C namespace, so this tree keeps the layer enum as Apple's (-1/0/1) and names
  the dimension bits `NSTextBlock…Dimension` (0x1000/0x2000/0x4000), with the door mapping one spelling to the other in
  one place.

**HARNESS AND LIFETIME:**

* **AN AUTORELEASED ANSWER PLUS `-release` IS `emptyPool` AT THE DRAIN.** `-bitmapImageRepByRetaggingWithColorSpace:`
  answers an autoreleased rep; the probe released it; every check printed ok and the process segfaulted at the drain.
  **The exit status is the witness** (`HANDOFF-2.md` §4 says this; it happened again).
* **A DOOR THAT NEEDS A WINDOW IS NOT A DOOR THAT REFUSED.** The base cell's `-selectWithFrame:…` undid a session for a
  view with no window, because `[nil makeFirstResponder:]` answers NO. Ask the question only when there is a window.
* **`-drawWithFrame:`'s sibling could not exist until `-drawWithFrame:` did.** Two doors in `HANDOFF-2.md` were left open
  for a reason that later expired (`-drawWithExpansionFrame:inView:` and `-bitmapImageRepByRetaggingWithColorSpace:`) —
  **when a slice lands the ground under an old refusal, re-read the refusal.**

---

## 5. How to add a slice without breaking the instruments

Unchanged from `HANDOFF-2.md` §6, and these sessions followed it every time. Restated because it is the whole method:

1. **Measure first.** `./tools/api-ledger missing …` tells you the cluster sizes, so you pick by reachable surface.
2. **Write the header declaration where Apple declares it** — and check WHICH `@end` closes the block. A protocol block
   inserted inside an `@interface` fails to compile with an error that names the missing `@end` two hundred lines away.
3. **Implement**, and make every deviation a comment at the door: what it does not do, and why. A refusal that answers its
   type's empty value beats a stub that looks implemented.
4. **Test the claim, not the code**: pixels for drawing, round trips for mappings, a *negative* assertion wherever the
   positive one could pass for the wrong reason, and **an assertion on the exit status**, not the tail of the output.
5. **Let the gate fail** (`ctest -R appkit-api-census`), then re-pin the census in the same commit and recompute its prose.
6. **Run the whole suite** (`cd build && ctest -j4`, ~64 s) **and check the exit status**.
7. **If you add a protocol, make the sending class say which messages it sends.** `NSMenuDelegate` is the model: three
   sent, five declared with what each would need; `NSComboBoxDelegate` is now all four; `NSAlertDelegate` is one.
8. **If a door has no reader, say so at the door** (`-acceptsGlyphInfo` records the flag and the header says nothing reads
   it) — or refuse it by name. A stored bit nobody reads is the failure this tree keeps re-learning.
9. **Commit in the component first, then advance the gitlink in `$AGORA_ROOT`** (`git -C "$A" add libagora-app`), with a
   message that says what moved in the censuses.

---

## 6. Where to spend the next hour

Ranked by reachable surface per unit of work, and the ranking is now about WHOLE CLASSES:

1. **`NSMatrix` + `NSForm` + `NSFormCell` — 134 selectors, and the last big VIEW.** A rectangular grid of `NSCell`s with
   tracking, selection and tab order; every piece of the arithmetic exists one class over (the table's selection, the
   cell's three tracking hooks, the segmented control's hit test). It is Apple's deprecated-in-10.6 class, so the era is a
   question to settle first: 10.6 declares it and this tree's pin is the era's, which is the same ground `NSPopUpButton`'s
   deprecated doors were kept on.
2. **The colour and font panels — `NSColorPanel`, `NSColorPicker`, `NSColorList`, `NSColorWell`, `NSFontPanel`,
   `NSFontManager`.** Six classes whose content is `NSColorSpace`, `NSColor` and `NSFont`, all of which exist; the panel
   shape is `NSPanel`'s. It would also give `NSColor`'s catalog doors their reader (`+colorWithCatalogName:` refuses
   because `NSColorList` does not exist).
3. **Printing — `NSPrintInfo`, `NSPrintOperation`, `NSPrintPanel`, `NSPageLayout`, `NSPrinter`.** The subsystem whose
   absence is recorded in the most refusals (`-print:`, `-application:printFiles:`, three in `NSDocument`, the alert's
   print paths). Five classes is more than one session, and `NSPrintInfo` + `NSPrintOperation` alone would retire most of
   them.
4. **`NSImageView` + `NSDrawer` + `NSTokenField`/`NSTokenFieldCell`** — a small group of real views, each one a
   `NSControl` subclass over machinery that exists (the image family, the split view's collapse, the field editor).
5. **The 569 outstanding selectors in classes this tree HAS**, in this order of return: `NSTextView`'s 126 (the text
   editing commands, the deepest subsystem), `NSBrowser`'s 64 (the Workspace's Column view), `NSWorkspace`'s 49 (the
   shell's launch and file verbs), `NSDocument`'s 30 + `NSDocumentController`'s 8 (print, autosave, error presentation).
6. **Leave these as declared refusals** (the plan's §A11 and this tree's own record): OpenGL, QuickDraw, movies, the four
   typesetters, `NSCollectionView` (10.11 only — the plan's §9.3), `NSFileWrapper` (Foundation's), `NSHelpManager` until
   there is a Help Viewer, and the speech classes until the platform services exist.

**AND THE LAST THREE SLICES CLOSED THE LAST LOOSE DOORS, NOT THE LAST SELECTORS.** The forty-odd selectors §13–§20 took
were spread across classes that were one or two doors short, and every class they TOUCHED is now COMPLETE. What is left
in classes this layer has is concentrated in a few large ones — `NSTextView` 126, `NSBrowser` 64, `NSResponder` 57,
`NSWorkspace` 49, `NSMenuView` 37, `NSFont` 35, `NSText` 31 — and each of those is a subsystem's surface rather than a
handful of loose ends. The 51 absent classes are the other half, and they are subsystems too.

---

## 7. Things a reader should not have to rediscover

* **THE LEDGER'S CLASS ARITHMETIC IS ONE OFF BY CONSTRUCTION.** `NSFileWrapper` is a **Foundation** class in this stack
  (`libagora-base/NSFileWrapper.h`) and Apple's own home for it, but the 10.6 AppKit umbrella imports Foundation, so the
  manifest lists it and the census counts it missing because it scans THIS component. It is one of the 51 — the real AppKit
  gap is 50 — and it is recorded in the census's own prose rather than special-cased in the tool.
* **`classes-present` IS 117 AND ONLY 115 OF THEM OFFER SELECTORS.** Two are counted present with nothing to answer; the
  `sel:` lines name the rest, so the "99 of 117 at COMPLETE coverage" figure is 99 of the 115 with a surface.
* **THE `cg_`-NAMED DOORS ARE THE INSTRUMENT'S, NOT APPLE'S.** `-cg_rowRectAtIndex:inFrame:`, `-cg_usableParts`,
  `-cg_willHighlightItem:`, `-cg_didSelectItemAtIndex:`, the `cg_` sheet doors — they exist because a
  probe needed to drive or read what a session merely performed. Each is documented as such where it is declared.
* **THIS TREE'S STRINGS ARE BYTE SEQUENCES, NOT CHARACTER SEQUENCES** for non-ASCII (`HANDOFF-2.md` §4). `-characters` and
  the date picker's separator are the two doors that say so out loud.
* **A MENU'S SESSION, A FIELD'S SESSION AND A MODAL SESSION ARE THREE DIFFERENT LOOPS** and each has its own guard for a
  program with no event source. All three answer "the press is the whole of what can be applied" rather than hanging, which
  is what makes the probes in `tests/popup_menu.m`, `tests/control_drag.m` and `tests/panel_alert.m` possible.
* **THE SUITE IS 137 TESTS IN ABOUT SIXTY-FOUR SECONDS.** It is runnable after every change, and a session that does not
  run it before committing is the one that ships a red gate — `HANDOFF-2.md`'s §4 account of a green-looking run that was
  loading the wrong library is the reason the exit status is part of step 6.

---

## 8. The first pick-up: the grid

*One session, one commit, and it is the first item of §6's ranking: `NSMatrix` + `NSForm` + `NSFormCell`, 134
selectors, three classes and `NSMatrixDelegate`.*

**WHAT LANDED.** All 134 selectors: the grid (a flat row-major `NSCell **`, because that is the shape `-cells`
publishes and the reason insertion and removal are memmoves), the selection (`_selected` stored apart from the cells'
highlight bits, because `-setSelectionFrom:to:anchor:highlight:NO` exists precisely to tell the two apart), the four
modes as four CLICK POLICIES rather than four geometries, the tracking loop (a copy of `NSControl`'s, including its
no-run-loop guard), the keyboard (arrows move the KEY cell, Tab traverses or leaves, a cell's key equivalent is a
click), the field session re-homed to the matrix, per-column stable sorting, tool tips keyed by cell, and archiving.
The form is a one-column radio matrix of cells that each draw a right-aligned label in a title band and an editable
field after it; `-setEntryWidth:` is the arithmetic that lines a form's fields up.

**THE NUMBERS.** classes 117 → 120 of 168, selectors 3543 → 3677 of 4112 → 4246, protocols 35 → 36, methods 4031 →
4166. `selectors-offered` MOVES WITH the present set (a class appearing adds its manifest rows to both sides of the
fraction), which is why the missing count — 569 — did not move at all. 102 of the 118 classes with a surface are now
at COMPLETE coverage. The suite is **138 tests in ~70 s**, 137 green plus the new `appkit-matrix` (75 checks).

**THREE THINGS THIS SESSION PAID FOR, each already the shape of a trap in §4:**

* **`NSCell` DECLARED `<NSCopying>` AND HAD NO `-copy`.** `NSMatrix -setPrototype:` promises Apple's contract — every
  position gets a copy — and `-copy` was a `doesNotRecognizeSelector:`. It is now the coding pair taken one step
  further (encode, decode), so it cannot drift from the archive. **AND THE DOOR IS `-copy`, NOT `-copyWithZone:`**:
  this Foundation removed every `NSZone`-taking method, so `NSCopying` here declares the entry point itself.
* **`NSTextFieldCell -selectWithFrame:…` ASKED A WINDOWLESS VIEW FOR FIRST RESPONDER.** `[nil makeFirstResponder:]`
  answers NO and NO there means "refused", so an offscreen matrix's session was placed and then torn down. `NSCell`'s
  copy of the same method had already recorded and fixed this; the subclass's copy had not. The guard is now in both.
* **AN INSERTION SORT THAT RETAINED AND THEN RELEASED THE GRID'S OWN REFERENCES** freed cells still in the matrix —
  a crash in the first check after the door. The shuffle is over borrowed addresses only.

**AND ONE REFUSAL HAD ITS GROUND REMOVED RATHER THAN ITS REASON.** `NSBrowser`'s
`-browser:createRowsForColumn:inMatrix:` was refused "because `NSMatrix` does not exist". It does now, and the refusal
is STILL RIGHT for a different reason: Apple's columns ARE matrices, this tree's are tables, so there is no matrix to
hand the delegate. `NSBrowser.h`, `NSBrowser.m`, `README.md` and `PROVENANCE.md` say the new reason. That is §4's
last trap ("when a slice lands the ground under an old refusal, re-read the refusal") paying out on the first slice
after it was written.

**WHERE THE NEXT HOUR IS, given §6's ranking and this session's cost:** the palette/panel group (§6 item 2) is now
the cheapest — six classes over `NSColorSpace`/`NSColor`/`NSFont`, all of which exist, and it would give
`NSColor +colorWithCatalogName:` its reader. Printing (§6 item 3) is the largest single debt by refusal count.
`NSTextView`'s 126 selectors remain the deepest subsystem in the tree and are still not a one-session slice.

---

## 9. The second pick-up: the colour panels

*One session, one commit, and §6's item 2 cut in half: the four COLOUR classes plus their two protocols — 52
selectors — leaving `NSFontManager` (51) and `NSFontPanel` (10) for the next one.*

**WHAT LANDED.** `NSColorList` (an ordered, file-backed named collection; the file is a property list of this tree's
own shape, and a system list's mutators refuse by name), `NSColorWell` (a cell-less control that draws its swatch,
installs itself as the shared panel's target on activation and reports back through `-takeColorFrom:`),
`NSColorPanel` (the singleton, with two CLASS configuration doors, a private content view for the chips/swatch/alpha
ramp, the accessory band and the picker host), `NSColorPicker` (a 40-cell palette conforming to both era protocols),
and `NSColorPickingDefault` + `NSColorPickingCustom`. **AND THE CATALOG DOORS GOT THEIR READER**:
`+[NSColor colorWithCatalogName:colorName:]` was a refusal "because `NSColorList` does not exist" and now reads the
list; the four COMPONENT doors still refuse, for the reason that survived — a colour does not remember the list it
came from.

**THE NUMBERS.** classes 120 → 124 of 168, selectors 3677 → 3729 of 4246 → 4298, protocols 36 → 38, methods 4166 →
4230. Missing selectors: still 569 (all 52 new ones are answered, and `selectors-offered` grows with the present set).
106 of the 122 classes with a surface are at COMPLETE coverage. Refusal census **288 → 293** — `NSColorList`'s four
deliberate ones and one in `NSColor.m` for the two cases the catalog lookup still cannot answer. The suite is **139
tests**, with `appkit-colour-panels` (62 checks) as the new one.

**THREE THINGS THIS SESSION PAID FOR:**

* **A WELL THAT PUSHED ITS COLOUR TO THE PANEL RECURSED FOREVER.** The panel's target IS the active well, so
  `-setColor:` → panel `-setColor:` → `-takeColorFrom:` → well `-setColor:` — measured as a stack overflow in the
  first probe run. A well tells the panel where its colour starts (at `-activate:`) and never again.
* **THE STANDARD COLOUR-LIST PATH NEEDS INTERMEDIATE DIRECTORIES.** `~/Library` need not exist on this system, so the
  one-directory `-createDirectoryAtPath:` failed and every standard-path write looked like an uneditable list.
* **THE PANEL'S TARGET IS NOT RETAINED, AND THE PROBE HAD TO SAY SO.** Releasing the target without clearing the
  panel left a dangling send that crashed one test-case later, in `-sendAction:to:from:` — the shape `HANDOFF-2.md`
  §4 records for a freed delegate, one class over.

**A CONCURRENT SESSION IS RELICENSING THIS REPOSITORY**, on branch `relicense-lgpl3-gpl3`, and its header sweep has
written C-style headers into `.cmake` scripts, `#` lines ABOVE the shebang in `.sh` runners, and `/*` at the top of
the Python `tools/api-ledger`. Three gates (`appkit-api-census`, `appkit-refusal-census`, `appkit-readme-refs`) and
`appkit-menu-headless` therefore fail for reasons OUTSIDE this slice; the API census was verified directly with
`tools/api-ledger check` and the refusal census by re-counting, both holding. **WHOEVER PICKS THIS UP SHOULD RE-RUN
THE SUITE AFTER THAT SWEEP LANDS**, and the sweep must not put a C comment in a CMake file or a `#` line above a
shebang.

**WHERE THE NEXT HOUR IS:** `NSFontManager` + `NSFontPanel` finish §6's item 2 (61 selectors), and `libagora-text`
already has `CTFontCollection`, `CTFontDescriptor` and `CTFontManager`, so enumeration is not the blocker. Printing
(§6 item 3) remains the largest single debt by refusal count; `NSTextView`'s 126 selectors remain the deepest.
