# libagora-app — a second handoff

*Written at the end of a session that picked the first handoff up (§9–§25 of `HANDOFF.md` are its running record) and spent
its time where that document said to: the text system's last doors, then the classes the 10.6 surface was missing. This file is
written for whoever picks the tree up next — what exists now, what it cost, and where the next hour is best spent. The first
handoff is still worth reading; nothing in it was wrong, and §2's instrument rules are the ones this session used most.*

*State at this handover: **18 commits**, tree clean, **132 tests passing**, `api-ledger: 355 metrics hold (111 classes,
3096 selectors of 3835, 28 protocols, 86 functions)`. 101 files changed, +16,946/−140.*

---

## 1. What this session did

| Commit | What it landed |
|---|---|
| `48f4297` | **`NSRulerView`, `NSRulerMarker`**, and the `NSScrollView` strip that wears them — 32 + 19 selectors, both COMPLETE. |
| `007aa74` | **The text ruler** — tab stops as markers, a drag that rebuilds the paragraph's tab stops, `-copyRuler:`/`-pasteRuler:`. `NSText` becomes COMPLETE (39/39). |
| `5016cce` | **The layout's measurements** — block rects, attachment sizes, `-showAttachmentCell:inRect:characterIndex:`. |
| `e9e2a24` | **The highlight that is not an edit** — the temporary-attribute table, the delegate's veto, `-rectArrayForGlyphRange:…`. |
| `fa18df8` | **Being told what changed** — the ensure and invalidation family, the container tidings, the extra line, two font measures. |
| `0f0b7e3` | **The manager's knobs** — the flag family, the caret's insertion points, the three view questions. |
| `1c26201` | **The glyph store's range doors** — the bulk readers and sub-class writers, the strike pair, `-fillBackgroundRectArray:…`. |
| `9a4c408` | **The typesetter trio**, spelling the four object doors `id` — **`NSLayoutManager` COMPLETE at 136/136**. |
| `fd3cf7c` | **The loose ends** — twelve classes a selector or two short, finished (17 doors). |
| `22200bd` | **`NSColorSpace`, `NSShadow`, `NSGradient`** — the first three missing classes, retiring three refusals. |
| `5256f32` | **The image rep family** — `NSCustomImageRep`, `NSCachedImageRep`, `NSEPSImageRep`, and PICT/CI as declared, refusing classes. |
| `9ed98e7` | **`NSStepper`/Cell and `NSSecureTextField`/Cell.** |
| `30b47cc` | **`NSNibConnector` + its two subclasses, and `NSPasteboardItem`.** |
| `8695056` | **`NSGlyphInfo`, `NSImageCell`, `NSCollectionViewItem`**, and the three pasteboard protocols. |
| `b29a1d3` | **`NSBox`** — and a finding about the census (see §2). |
| `cf133d3` | **`NSTabView`/`NSTabViewItem`** and `NSTabViewDelegate` — the first protocol in this run the tree actually SENDS. |
| `87465bf` | **The animation family** — `NSAnimation`, `NSViewAnimation`, `NSAnimationContext`, `NSAnimationDelegate`. |
| `a23a9b1` | **`NSLevelIndicator`/Cell** — the value that becomes a colour. |

Plus, in the workspace: the gitlink advanced after each of those.

---

## 2. The instrument, and the one class it counts that this component cannot pay for

The census (`tools/api-ledger`, `tests/api-10.6-census.txt`, `tests/api_census.cmake`) is unchanged and still the deliverable:
measure first, pin what you measured, re-pin deliberately in the same commit.

**IT COUNTS ONE CLASS THAT IS NOT THIS COMPONENT'S.** `NSFileWrapper` is a **Foundation** class in this stack
(`libagora-base/NSFileWrapper.h`, 47 methods), which is also Apple's own home for it; the 10.6 AppKit umbrella imports
Foundation, so the manifest lists it and the census counts it missing because it scans THIS component's sources. **The class
count is one high by construction.** It is recorded in the census's own prose rather than special-cased in the tool, because a
census that quietly excused entries would stop being a measurement. Measured at the time: of the 57 classes the ledger calls
missing, exactly **one** is defined elsewhere in the installed prefix, and four are only forward-declared here
(`NSCollectionView`, `NSDocument`, `NSFileWrapper`, `NSOpenPanel`).

The same discovery retired a misreading: "the largest remaining class is `NSFileWrapper`, 35 selectors" is true of the
*manifest* and false of the *work*.

---

## 3. Current measured state

```
classes   111 of 168   (66%)    57 missing      (one of them Foundation's — see §2)
selectors 3096 of 3835 (81%)   739 missing     72 of 109 classes at COMPLETE coverage
protocols  28 of  56   (50%)    28 missing
functions  86 of  86  (100%)     0 missing      10 refuse by name
methods  3523 declared, 4 with no body (0.1%)

text system:  NSLayoutManager 136/136 (COMPLETE) · NSText 39/39 (COMPLETE) · NSTextView 60/186 ·
              NSTextStorage 13/25 · NSTextContainer 17/17 · NSRulerView 32/32 · NSRulerMarker 19/19

suites: 132 tests, ~60 s;  censuses: api-10.6 (355 metrics), refusal (140), owed (19)
```

The honest reading: **the manager and the text system's geometry are finished; the remaining 57 classes are the peripheries**
— the document and controller family, the panels (open/save, colour, font, print), the printing objects, the still-missing
controls (`NSDatePicker`, `NSMatrix`, `NSCollectionView`, `NSImageView`), the speech/sound/movie machinery, OpenGL, QuickDraw,
and the three typesetter classes (`NSTypesetter`, `NSATSTypesetter`, `NSSimpleHorizontalTypesetter`, `NSGlyphGenerator`), which
Core Text replaces here.

---

## 4. Traps this session paid for, so the next one need not

**Doors that answered a fact nobody read (three of these, so treat it as a class of bug, not bad luck):**

* **`-cg_lineHeight` HAD NO CALLERS.** It answered the line height while the breaker recomputed `ascender - descender` at its
  own site, so `-usesFontLeading` could change the door and change nothing on screen. The layout now stacks every fragment
  through the door, which is what made the knob live (and the second line's baseline move by exactly the font's leading).
* **`NSCell -setDoubleValue:` ANSWERS ONLY FOR AN `NSTextCellType` CELL** (`if (_type != NSTextCellType) return;`). Two classes
  needed it — the stepper and the level indicator — and both had arrows/values that moved nothing until the value pair was
  overridden and the number lived in the subclass. **In this tier, "a cell with a numeric value" means overriding the value
  pair.**
* **`NSInvocation` REFUSES A 32-BYTE ARGUMENT** ("marshals register arguments only", its own header says so), so
  `NSCustomImageRep` sends its draw selector through `-methodForSelector:`'s IMP with the method's real signature.

**Doors whose arithmetic was wrong in a way only pixels showed:**

* **`-ag_xForGlyph:inFragment:` ANSWERED THE LINE'S LEFT EDGE for a glyph past the fragment**, so a strikethrough (or an
  underline) over a range ending at the line's end came out `x1 <= x0` and RETURNED WITHOUT DRAWING — a whole line could not be
  underlined. Found by counting pixels: plain draw 0, struck draw 36.
* **A temporary attribute in the middle of a store run was STEPPED OVER.** The glyph walk advances by the effective range it is
  handed, so a store run that claimed the whole line skipped the temporary run inside it and drew a red character green. The
  delegate test passed anyway, because its temporary run started at index 0 — which is why the pixel test had to exist.
* **`NSBox`'s content rectangle subtracted the title's band TWICE** (folded into `NSInsetRect`'s `dy`) while
  `-setFrameFromContentFrame:` added it once. The round-trip test — a content frame in, the same frame back — is the only thing
  that holds the two formulas together.

**Placement traps, in their fourth and fifth shapes:**

* **`@end` IS NOT A UNIQUE ANCHOR IN A HEADER.** A door appended before a file's LAST `@end` landed inside the
  `NSTextFieldDelegate` PROTOCOL (it compiled; the warning was one line). Later, a protocol block landed inside
  `@interface NSPasteboard` twice — because the option typedefs it needed are inside the class body — and a line-based move then
  split a comment and left a fragment after the `#endif`. **Recovery is `git checkout` of the file and an anchor on the class's
  own `@end`**, not a cleverer script.
* **A PROPERTY DECLARED ON THE BASE CLASS MUST BE IMPLEMENTED ON THE BASE CLASS.** `-headerLevel` was written into
  `@implementation NSMutableParagraphStyle` (beside the other setters) and the first `[copiedStyle headerLevel]` aborted with
  "not implemented": a copy of a mutable style is answered by the base implementation.

**Test traps, all of which produced a GREEN RUN that meant less than it looked:**

* **A test that printed "all checks passed" and then segfaulted** in `emptyPool` at the pool's drain: `+imageRepWithData:`
  returns an AUTORELEASED rep and the probe released it too. Every check had printed `ok`. **The exit status is the witness.**
* **A test that reused a manager inherited its overrides** (a drawing check drew at the size a previous section had stored),
  so the failure looked like a scaling bug. The drawing checks now build their own manager.
* **Item order is INSERT order, not add order.** A tab-view probe added `one`, added `two`, inserted `three` at 1 — the strip is
  `one, three, two` — and the first stepping assertions read as if it were `one, two, three`.
* **A screen exists headlessly with `-depth` 0** (no output), so `NSScreen -colorSpace` answers nil; the probe asserts the
  CONTRACT (nil when the depth names no space) rather than a constant.

**And one environmental lesson worth its own line:** mid-slice, six unrelated tests failed — and they failed with the slice
STASHED too, because a concurrent session was rebuilding `build-prefix` while the suite ran. **A red suite is evidence only
once you know which libraries the binaries loaded.**

---

## 5. Where to spend the next hour

Ranked by reachable surface per unit of work.

### 5.1 `NSDatePicker` + `NSDatePickerCell` — 60 selectors

The biggest remaining control, and its substrate is all here — MEASURED: `libagora-base` has `NSCalendar`, `NSDateFormatter`,
`NSISO8601DateFormatter` and `NSLocale`, so a date field is a text field whose text is a formatted date rather than a new
subsystem. The slice is the formatting, the three styles (`NSTextFieldAndStepperDatePickerStyle`,
`NSClockAndCalendarDatePickerStyle`, `NSTextFieldDatePickerStyle`), the calendar's element flags
(`NSYearMonthDayDatePickerElementFlag` and its family) and the delegate's two questions — which is `NSDatePickerCellDelegate`,
one of the 28 missing protocols, and a protocol this class would actually SEND.

### 5.2 `NSCollectionView` + its delegate — 28 selectors + 1 protocol

`NSCollectionViewItem` already exists (§ the class list) and says so in its header: "it exists before the view it belongs to
does". This slice is the layout decision the header defers — a grid of item frames, selection indexes, item recycling, and the
delegate's `-collectionView:itemForRepresentedObjectAtIndexPath:` family. It wants a small design note before code.

### 5.3 `NSMatrix` + `NSForm` + `NSFormCell` — 134 selectors

Deprecated in 10.6 and the largest single remaining view. It is a rectangular grid of `NSCell`s with tracking, selection and
tab-order — all of which exists one class over (the table, the segmented control, the cell's tracking hooks). A big slice that
is mostly arithmetic over cells.

### 5.4 The 28 missing protocols, where a sender exists

Most missing protocols belong to classes this tier has not got, so declaring them would be a contract nobody sends.
**The honest ones** are the two whose classes exist and whose delegate doors are typed `id` today: `NSMenuDelegate` (the menu
has a delegate property and an update walk) and `NSTextViewDelegate` (which inherits `NSTextDelegate`). Both are small, and both
should say in their headers which of their messages this tier actually sends — the pasteboard protocols are the model here
(`NSPasteboardItem` conforms to `NSPasteboardWriting` and the test checks `conformsToProtocol:`).

### 5.5 Leave these as declared refusals

* **`NSFileWrapper`** — already Foundation's (§2). Do not write it here.
* **QuickDraw (`NSQuickDrawView`), OpenGL, movies (`NSMovie`, `NSMovieView`)** — the plan's §A11: declare and refuse, no
  reachable surface gained.
* **`NSTypesetter`, `NSATSTypesetter`, `NSSimpleHorizontalTypesetter`, `NSGlyphGenerator`** — Core Text does both jobs here; the
  manager's four object doors are `id` because of it (§ the manager's own header).

---

## 6. How to add a slice without breaking the instruments

Unchanged from the first handoff's §6, with one addition and one emphasis:

1. **Measure first.** `./tools/api-ledger missing …` tells you the cluster sizes, so you pick by reachable surface.
2. **Write the header declaration where Apple declares it**, inside the `@interface` — and check WHICH `@end` closes it
   (see §4).
3. **Implement**, and make every deviation a comment at the door.
4. **Test the claim, not the code**: pixels for drawing, round trips for mappings, and a *negative* assertion wherever the
   positive one could pass for the wrong reason.
5. **Let the gate fail** (`ctest -R appkit-api-census`), then re-pin `tests/api-10.6-census.txt` in the same commit. When the
   REFUSAL census moves (a refusal becoming real), re-pin that too — this session took it 142 → 140 in one commit.
6. **Run the whole suite** (`cd build && ctest -j4`, ~60 s). **AND CHECK THE EXIT STATUS**, not the tail of the output (§4).
7. **NEW: if you add a protocol, make the sending class say whether it sends it**, and put the messages it does send in the
   header. A protocol declared with no sender is a contract nobody honours.

---

## 7. Five things a reader should not have to rediscover

* **THE CENSUS'S CLASS COUNT IS ONE HIGH.** `NSFileWrapper` is Foundation's (§2). The prose above the metrics says so, and the
  prose is not a metric: when you re-pin, recompute it from `api-ledger census`, never edit it by eye.
* **A NUMERIC CELL'S VALUE PAIR IS ITS OWN.** Two classes learned it the hard way; a third will otherwise.
* **`-cg_lineHeight` IS THE LAYOUT'S ONE LINE-HEIGHT DOOR** (it reads `-usesFontLeading`), and `-defaultLineHeightForFont:` is
  the same arithmetic for one font. Two line heights are how a baseline and a rect come to disagree.
* **THIS RUNTIME KEEPS TYPED SELECTOR RECORDS**, so `NSSelectorFromString("x")` and the compiler's `@selector(x)` need not be
  the same POINTER. Compare NAMES (`NSStringFromSelector`) in a test; the name is also what a nib's connection label can
  promise.
* **THE `cg_`-NAMED DOORS ARE THE INSTRUMENT'S, NOT APPLE'S.** `-cg_invalidatedRange`, `-cg_lineHeight`,
  `-cg_offsetForGlyphAtIndex:`, `-cg_levelCell` and the rest exist because a probe needed to read what a delegate was merely
  told. They are documented as such; do not mistake them for the era's API.
