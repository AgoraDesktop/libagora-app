# libagora-app — a second handoff

*Written at the end of a session that picked the first handoff up (§9–§25 of `HANDOFF.md` are its running record) and spent
its time where that document said to: the text system's last doors, then the classes the 10.6 surface was missing. This file is
written for whoever picks the tree up next — what exists now, what it cost, and where the next hour is best spent. The first
handoff is still worth reading; nothing in it was wrong, and §2's instrument rules are the ones this session used most.*

*State at this handover: **18 commits**, tree clean, **132 tests passing**, `api-ledger: 355 metrics hold (111 classes,
3096 selectors of 3835, 28 protocols, 86 functions)`. 101 files changed, +16,946/−140.*

*State after the session that picked this file up (§8–§10): **21 commits**, tree clean, **134 tests passing**, `api-ledger: 359
metrics hold (115 classes, 3271 selectors of 4050, 29 protocols, 86 functions)`.*

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
| `e2e3e52` | **`NSDatePicker`/Cell** and `NSDatePickerCellDelegate` — a formatted date, the subfield a step applies to, the veto; and the stepper's arrows, which pointed inward (§8). |
| `e7ba264` | **The demonstration's new-controls strip**, and the two `NSBox` title bugs it found (§9). |
| `0420c08` | **`NSDocument` + `NSDocumentController`** — the file, the change count, the undo wiring, the window controllers and the type table (§10). |

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
classes   115 of 168   (68%)    53 missing      (one of them Foundation's — see §2)
selectors 3271 of 4050 (81%)   779 missing     74 of 115 classes at COMPLETE coverage
protocols  29 of  56   (52%)    27 missing
functions  86 of  86  (100%)     0 missing      10 refuse by name
methods  3713 declared, 4 with no body (0.1%)

text system:  NSLayoutManager 136/136 (COMPLETE) · NSText 39/39 (COMPLETE) · NSTextView 60/186 ·
              NSTextStorage 13/25 · NSTextContainer 17/17 · NSRulerView 32/32 · NSRulerMarker 19/19

suites: 134 tests, ~60 s;  censuses: api-10.6 (359 metrics), refusal (143), owed (19)
```

The honest reading: **the manager and the text system's geometry are finished, and the application model now exists; the
remaining 53 classes are the peripheries** — the REST of the document family (`NSPersistentDocument`, the controller family),
the panels (open/save, colour, font, print), the printing objects, the still-missing controls (`NSMatrix`, `NSCollectionView`,
`NSImageView`), the speech/sound/movie machinery, OpenGL, QuickDraw, and the three typesetter classes (`NSTypesetter`,
`NSATSTypesetter`, `NSSimpleHorizontalTypesetter`, `NSGlyphGenerator`), which Core Text replaces here.

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

**A NON-ASCII LITERAL IN THIS TREE IS A SEQUENCE OF BYTES, NOT A CHARACTER.** `@"\u2013"` has `-length` 3, its
`-characterAtIndex:` values are `0x00e2`, `0x0080`, `0x0093`, and `-rangeOfString:` cannot find it in a string built from the
same literal. MEASURED while writing the date picker's range separator, which is ASCII now. Drawing a non-ASCII glyph works
(the star in `NSLevelIndicator`), so the gap is in the string's character view rather than in its bytes; until it is fixed,
compare ASCII.

**A PATTERN'S FIELDS NEED NOT BE ADJACENT.** The day period is not beside the hour in "h:mm:ss a", so the date picker's
first merge rule ("a repeated element extends the previous field") counted SEVEN subfields for a six-field date. The fix is
to attach the day period to the hour by ELEMENT, wherever the locale put it. A probe that only printed the text would never
have seen it; the instrument door that answered the count did.

**A CHIP'S CENTRE IS THE GLYPH, NOT THE CHIP.** The month grid's selected day is a filled accent circle with a white number
on it, so sampling the cell's centre read the number's antialiasing — the segmented control's plate, one slice later. The
check counts the accent pixels in the CELL, which is a region assertion, and the neighbour's zero.

**AND THE SLICE FOUND A SIBLING'S PICTURE BUG, WHICH IS THE POINT OF §4's OWN CLASS OF BUG.** `NSStepperCell` chose its
arrow bands correctly and then drew each triangle's apex at `NSMaxY` regardless of the flip, so the TOP arrow pointed DOWN
and the bottom one pointed UP — both inward — while every press assertion passed, because a press reads a band rather than a
triangle. MEASURED by rendering 40 rows and counting ink: the top half's widest row was its top one. The fix takes the flip
in both the band and the apex, and the stepper's probe now reads the rendered rows (apex 2, base 4).

**And one environmental lesson worth its own line:** mid-slice, six unrelated tests failed — and they failed with the slice
STASHED too, because a concurrent session was rebuilding `build-prefix` while the suite ran. **A red suite is evidence only
once you know which libraries the binaries loaded.**

---

## 5. Where to spend the next hour

Ranked by reachable surface per unit of work.

### 5.1 `NSDatePicker` + `NSDatePickerCell` — LANDED, see §8

*Was: 60 selectors, the biggest remaining control, with `NSCalendar`/`NSDateFormatter`/`NSLocale` already here.*

**Corrected while landing it:** `NSDatePickerCellDelegate` is not "the delegate's two questions" — 10.6 declares ONE optional
message with TWO in/out parameters, `-datePickerCell:validateProposedDateValue:timeInterval:`, and the cell sends it. The rest
of the prediction held, including the substrate: the whole class is a text field whose text is the formatter's answer, and the
three styles are three frames around it.

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

---

## 8. The date picker: a formatted date, the run a click selects, and the veto

*Nineteenth commit of the pickup: `NSDatePicker` (30) + `NSDatePickerCell` (30, 2 inherited) + `NSDatePickerCellDelegate` —
60 selectors, two classes, one protocol. **113 of 168 classes, 29 of 56 protocols.***

**THE TEXT IS THE CELL'S OWN DOORS.** The element flags are a skeleton (`G y MMM d j mm ss z`), the locale turns it into a
pattern, and one `NSDateFormatter` — given the cell's calendar, locale and time zone — renders it. The probe does not trust
that sentence: it formats a fixed instant and requires the text to EQUAL a formatter built from the same facts in the test, then
changes each door. de_DE: day first, "Juni", 24-hour. A +12 zone: 14:35 becomes 02:35 **the next day**, which is the assertion
that catches a time zone stored and never read. An element flag removes a whole field; the era and zone flags add theirs.

**THE SUBFIELD IS A MEASURED RUN, NOT A SECOND LAYOUT.** The pattern is walked in its own order (`fn_pattern_fields`), each
field is formatted on its own with the same formatter configuration, and the piece is located in the finished string from the
last match with a token boundary — so day "6" cannot be found inside year "2026". The rect is the difference of two PREFIX
WIDTHS of the same attributed string, which is where the glyphs were drawn; the accent overdraw uses the same offset. The
selected-subfield highlight is ink in `+cg_accentColor` rather than a filled chip, and the header says so (a chip that is only
drawn when the control is first responder is a state this tier does not model in an offscreen probe).

**STEPPING IS THE CALENDAR'S.** `-dateByAddingUnit:value:toDate:options:` with the selected element's unit; January 31 + one
month is February 28 because `libagora-base`'s calendar normalizes it, and the probe reads that rather than trusting a formula.
Typed digits replace the selected field: the buffer resets when the number cannot be a prefix any more (month "1" then "5" is
May), the day is clamped to the shown month's length, and the year takes four digits. Up/down step, left/right move the
selection, and the CONTROL compares the date before and after so a selection move redraws without sending the action.

**THE DELEGATE IS SENT, THREE WAYS.** The 10.6 message is one optional method with two in/out parameters. The probe's watcher
accepts, REPLACES the proposal with one shifted a day (and the cell stores the replacement: February 28 + the delegate's day is
March 1), and REFUSES with a nil date (the step answers NO and the date does not move). `-setDateValue:` does not ask, which is
Apple's split between a person's edit and an application's.

**THE THREE STYLES ARE THREE PICTURES, AND THE THIRD IS STATED AS THIS TIER'S READING.** A time-only clock-and-calendar picker
draws a clock face — ring, twelve ticks, hour/minute/second hands from the date's own components — and a picker with any date
flag draws the month grid: the calendar's month name and year, the weekday row rotated by `-firstWeekday`, the month's days
numbered, and the selected day a filled accent chip with the platform's selected-text ink. The probe checks the hour hand right
at 03:00 and left at 09:00, and counts accent pixels inside June 16's cell and zero inside June 15's, then moves the date and
requires the chip to move. `-cg_rectForDay:inFrame:` is the one geometry door the drawing calls per day.

**AND THE RANGE MODE IS THE START PLUS A LENGTH.** `NSRangeDateMode` draws `dateValue` and `dateValue + timeInterval` as two
formatted dates with an ASCII hyphen (see §4's note on non-ASCII literals); the pattern's fields still exist for the keyboard,
but no run is separately hit-testable, and the header says why rather than answering a zero rect with no reason.

### Where §5 goes next

The ranking in §5 still holds: `NSCollectionView` + its delegate (5.2) is the next reachable slice, then `NSMatrix`/`NSForm`
(5.3), then the two protocols whose senders exist (5.4). Three more classes left §5's "biggest remaining control" category, and
the peripheries are what remain.

---

## 9. The demonstration, and the title it found missing

*Twentieth commit of the pickup: `tests/appkit_controls_draw.m` now shows every control class the later slices landed, and
the update found two `NSBox` bugs that no value check could see.*

**THE WINDOW IS STILL 760x420, AND THAT IS A CONSTRAINT RATHER THAN A PREFERENCE.** `run-controls.sh` opens a 900x600 nested
compositor by default and the controls window already fills it; widening or growing the window would push its chrome off the
screen. So the new strip is the RIGHT COLUMN's top 215 points in two 162-wide columns, and the scroll panel below it gave up
220 points of height (370 -> 150). The left column carries the value-shaped controls: `NSLevelIndicator` twice (a capacity
bar at 62 with warning 50 and critical 80, so the fill is the platform's orange, and a rating of three of five stars), an
`NSStepper` with a read-only label beside it, `NSSecureTextField` (holding a value, so it draws bullets), `NSSearchField`
(holding a value, so its cancel chip is there), `NSDatePicker` in the text-and-stepper style, and `NSProgressIndicator` as a
bar with a spinner beside it. The right column carries the two containers: an `NSBox` around a button, and an `NSTabView`
whose Clock pane is the date picker's clock-and-calendar style and whose Date pane is the text-field style (hour and minute,
because the full string clipped at 146 points). The third date-picker face is the one in the left column, so all three are in
the window, two of them a tab click apart.

**AND `--no-playground` EXISTS BECAUSE THE THING BEING LOOKED AT WAS BEHIND ANOTHER WINDOW.** The playground is mapped last so
it is in front, which is right for the text and wrong for the controls: it covers the right column. The flag leaves it
unmapped, and `run-controls.sh --no-playground` is how the screenshot in this session was taken.

**THE FIRST BUG: A BOX THAT CLEARED A GAP AND WROTE NOTHING IN IT.** `NSBox -setTitle:` wrote the title cell's VALUE
(`-setStringValue:`), while `-drawInteriorWithFrame:` draws its LABEL (`-_title`). So `-title` read back, `-titleRect`
measured a band, the clear cut the border open — and the words were never drawn. The title cell's label is now the title, and
the demonstration's screenshot is where that showed (the first render had a gap in the border and no "NSBox" in it).

**THE SECOND, WHICH ONLY APPEARED ONCE THE WORDS WERE DRAWN: THE BAND WAS ASTRIDE THE CLIP.** At `NSAtTop` the band was
centred on the top edge (`maxY - height / 2`), which is Apple's shape — and this tier's `-borderRect` IS the bounds, so half of
every letter fell outside the view and was cut off. The band is now wholly inside the frame (`maxY - height - 2`), and the
content's title band is the WHOLE band rather than its lower half, so nothing can be laid out underneath the words.

**AND `tests/box.m` NOW TESTS THE PICTURE, NOT THE GEOMETRY.** It counts the glyph pixels (a pixel dark with the title and not
without it), the border pixels the clear removes (dark without the title and not with it — which is the gap), and asserts the
band is inside the bounds. The old checks read the title's STRING and its BAND and passed through both bugs; the demonstration
is what saw them, which is what a demonstration is for.

**WHAT IS NOT THERE, AND WHY.** `NSImageView`, `NSMatrix`, `NSColorWell`, `NSTokenField`, `NSCollectionView` and `NSDrawer`
have no class in this tier, so the gallery cannot show them. `NSBrowser` exists but is a columned data view and belongs beside the table
and outline. Apart from it, the window now shows every control class the 10.6 surface here implements.

---

## 10. The document core: a file, a change count, and the windows that show it

*Twenty-first commit of the pickup: `NSDocument` 74 of 104 selectors and `NSDocumentController` 41 of 51 — 115 selectors,
two classes. **115 of 168 classes; selectors 3271 of 4050.***

**A DOCUMENT IS A FILE PLUS THE HISTORY OF ITS EDITS.** The probe's `AGDocTextDocument` implements ONLY
`-readFromData:ofType:error:` and `-dataOfType:error:`; the default `-readFromURL:` builds an `NSFileWrapper` and hands
`-regularFileContents` to the data door, and `-writeToURL:ofType:error:` asks `-fileWrapperOfType:` for a wrapper around the
same data and writes it atomically. The probe goes round that loop: untitled → edit → save-as to a temp file → close → open
with the controller → read the text back → revert from disk → save → close all. A package subclass overrides the wrapper pair
instead; the 10.3 data hooks (`-loadDataRepresentation:ofType:`/`-dataRepresentationOfType:`) are still tried when the modern
door declines, which is the one compatibility branch that matters.

**THE CHANGE COUNT HAS TWO SOURCES AND ONE WRITER.** `-updateChangeCount:` is the writer; the document registers for its undo
manager's did-undo/did-redo notifications, so an action undone takes the count to zero and a redone action brings it back
without the application calling the door. A save clears it; a revert clears it and empties the undo stack. Every window
controller is told `-setDocumentEdited:` as the predicate moves.

**THE CONTROLLER IS A CLASS, NOT A GLOBAL.** The base reads `CFBundleDocumentTypes` once (type name, `NSDocumentClass`,
extensions, Editor role) for `-documentClassForType:`, `-defaultType`, `-displayNameForType:`, `-typeFromFileExtension:` and
`-typeForContentsOfURL:error:`. The probe's subclass supplies those three answers from a table of its own, so no Info.plist is
needed and the base's type → class → make/open chain is what is exercised. `-openDocumentWithContentsOfURL:display:error:` adds
the document, makes its window controllers and notes it recent; opening a URL that is already open answers the SAME document.

**CLOSE-ALL IS SAFE RATHER THAN CLEVER.** There is no unsaved-changes alert in this tier, so if any document is edited,
`-closeAllDocumentsWithDelegate:didCloseAllSelector:contextInfo:` closes NONE and tells the delegate NO. Discarding edits
silently is the one failure a close-all must not have; when the alert exists that branch becomes the alert.

**THE PANELS ARE NAMED REFUSALS, NOT HALF-BUILT DOORS.** `-saveDocumentAs:`, `-saveDocumentTo:`,
`-runModalSavePanelForSaveOperation:…` and `-[NSDocumentController openDocument:]` refuse by name; `-saveDocument:` refuses
only when the document has no URL (the panel path), and a direct `-saveToURL:ofType:forSaveOperation:error:` is real. The
refusal census moved 140 → 143 for exactly those three sites.

**TWO FINDINGS WORTH KEEPING.** `NSTemporaryDirectory()` in this tree answers `/System/Temporary Files/`, which does not exist
on this host — MEASURED, `-createDirectoryAtPath:` failed EACCES and every save then failed ENOENT; the probe names `/tmp`
itself and the Foundation gap is recorded rather than silently worked around. And **an undo action must register its own
inverse or the redo stack is EMPTY**: the probe's first `-bump:` action did not, so `-canRedo` was NO after a successful undo
and the test looked like a document bug. That is the undo manager's model (Apple's too), and the test now registers the inverse.

### Where the next hour goes

1. **`NSSavePanel` (47) + `NSOpenPanel` (15) + `NSOpenSavePanelDelegate`.** The panel pair is what the three refusals above
   are waiting for, and it makes `-saveDocumentAs:`, `-openDocument:`, `-runModalSavePanelForSaveOperation:` and the
   document controller's UI actions real. `NSPanel` is 6/6 and sheets exist, so the substrate is present. This is the
   critical-path continuation, not a new direction.
2. **The completion sweep** (211 selectors over 23 classes, each ≤15 short) if a one-session, mostly-forward win is wanted:
   it would take the tree from 74 to ~97 complete classes and 81% to ~86%. It is a polished set of existing controls, not a
   new capability.
3. **`NSBrowser`'s 64** for the Workspace's Column view, **`NSWorkspace`'s 49** for the shell's launch/file verbs, or the text
   editing commands (`NSResponder` 57 + `NSTextView` 126) for the deepest subsystem.
4. **NOT 10.6 `NSCollectionView`.** §5.2 above predates this session's reading of the plan: §9.3 says the 10.6
   item-prototype API is deprecated and the 10.11 layout API is the target, so 28 selectors spent on the 10.6 shape would be
   a façade. The item controller can keep waiting for the layout stack.
