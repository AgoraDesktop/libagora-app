# libagora-app — a handoff

*Written at the end of a session that built the AppKit's function layer, the API census that
measures it, and the first four slices of the text system. It is written for whoever picks the
tree up next: what exists, what it cost to make trustworthy, and where the next hour is best
spent.*

*State at handover: **8 commits**, tree clean, **114 tests passing**, `api-ledger: 327 metrics
hold (82 classes, 2652 selectors of 3517, 23 protocols, 86 functions)`.*

*State after the session that picked it up (§9–§25): **26 commits**, tree clean, **132 tests passing**,
`api-ledger: 355 metrics hold (111 classes, 3096 selectors of 3835, 28 protocols, 86 functions)`.*

**That session left its own handoff — `HANDOFF-2.md`** — which is the place to start: this file is the record of how the tree
reached its state, and that one is what a reader needs to go on from it. §9–§25 below are the same session's running notes.

---

## 1. What this session did

| Commit | What it landed |
|---|---|
| `f4d0581` | **The function layer** — 86 of 86 non-inline 10.6 C functions (10 refuse by name), plus `tools/api-ledger`, the committed SDK manifest, and the census gate. |
| `0e62918` | `NSLayoutManager` **fragment queries** (7 selectors): what is laid out, which container holds a glyph, `withoutAdditionalLayout:` forms. |
| `bc82650` | **Glyph↔character mapping** (7): the cluster-table doors, on machinery the tree already had. |
| `f929843` | **The glyph store** (15): per-glyph records as a *shadow* of the layout, with real field mutation and three count-changing refusals. |
| `da6afbd` | **`NSSpellChecker`** (29 of 39) over the machine's own dictionary, plus the 18 `NSTextView` doors it unblocks. |
| `325de1b` | **The squiggle** — underline doors on the manager, and `-setSpellingState:range:` reaching the pixels. |
| `a54fed4` | **Finding** — `NSFindPanelAction`, next/previous with wrap, and a static find indicator. |
| `c1f3b3e` | Housekeeping: a committed `.pyc` removed and ignored. |

67 files, ~15.4k lines. Two new test binaries per slice on average; 114 tests in total.

---

## 2. The instrument, which is the real deliverable

**Before this session the tree had no way to answer "how much of the AppKit do we have?"** Three
hand counts gave 4%, 44% and 54%, each measuring a different thing. That is now recomputable.

```
tools/api-ledger manifest <framework-dir> [<other> ...]      -> the SDK's facts, as a file
tools/api-ledger census   <manifest> <src> [--library <so>] -> "name count" metrics
tools/api-ledger check    <manifest> <src> <census> [--library <so>]
tools/api-ledger missing  <manifest> <src> [--library <so>] -> what is absent, ranked
```

| Artifact | What it is |
|---|---|
| `api/10.6/appkit-manifest.txt` | 5,519 lines of **facts** from the real 10.6 SDK: 168 classes + superclasses, 56 protocols, 87 functions, 5,208 selectors. No Apple prose, no redistributable headers. |
| `api/10.6/README.md` | The recipe to regenerate it (`phracker/MacOSX-SDKs`), and the two-measurements explanation. |
| `tests/api-10.6-census.txt` | 436 lines of pinned metrics — eight aggregates, one `sel:` line per shared class, `fn:`/`fndecl:` per function, `selphantom:` per class that declares a body it never built. |
| `tests/api_census.cmake` | The gate: two-directional comparison, arithmetic check, and two **fault** checks that are not drift. |
| `tools/api-ledger` | 695 lines of parser. All the parsing lives here; CMake keeps the comparison visible. |

**Run it:**

```sh
cd libagora-app/build && cmake .. && make -j4 App
ctest -R appkit-api-census --output-on-failure
cd .. && ./tools/api-ledger missing api/10.6/appkit-manifest.txt . --library build/libagora-app.so
```

### What it measures, and the four things it learned to stop getting wrong

* **A function counts when `nm -D --defined-only` reports it**, not when a header mentions it.
  `functions-declared` is kept beside it, and the two disagreement counts
  (`functions-declared-not-defined`, `functions-defined-not-declared`) are checked as **faults**,
  because neither is a number to move. This is what caught five depth functions that had been
  declared since `NSGraphics.h` was written, called by `NSScreen`, and **never defined** — the
  shared library carried unresolved references to four of them.
* **Inheritance is resolved** (the plan's §2.4 requirement). Not doing so reported
  `NSTextView 0 of 130` for a class that inherits its editing surface from `NSText`.
* **`methods-declared-not-implemented`** turns the same question on *this tree*: 2,989 declared
  selectors, **4 with no body on the chain** — all four informal-protocol hooks on `NSObject`.
  Its measurement history is the argument for keeping it: **1,138 → 118 → 47 → 4**, each step a
  reader blind spot, not a change in the tree (subclass-summed; `@synthesize`; `getter=`; the
  tree's `FN_FLAG_PAIR` accessor macros). Each is documented at the code that fixed it.
* **`functions-offered` is 86, not 87**, because `NSEventMaskFromType` is `NS_INLINE` — a bodied
  door that is *supposed* to have no symbol.

### The disposition vocabulary

Every door is one of: **real** (does what Apple documents), **refused by name** (answers its
type's empty value and says on stderr what it wants — `AppKitRefusal.h`), or **pinned debt**
(a count in a census that may only move deliberately). 10 of the 86 functions refuse.

---

## 3. Current measured state

```
classes   111 of 168   (66%)    57 missing
selectors 3096 of 3835 (81%)   739 missing    72 of 109 classes at COMPLETE coverage
protocols  28 of  56   (50%)    28 missing
functions  86 of  86 (100%)     0 missing     10 refuse by name
methods  3289 declared, 4 with no body (0.1%)

text system:  NSLayoutManager 136/136 (COMPLETE) · NSTextView 60/186 · NSTextStorage 13/25 · NSTextContainer 17/17
              NSText 39/39 (COMPLETE) · NSRulerView 32/32 (COMPLETE) · NSRulerMarker 19/19 (COMPLETE)
```

The honest reading: **the desktop core is deep, the periphery is empty, and the functions are
done.** The remaining 86 classes are dominated by the 10.6 debts the plan named — documents,
open/save panels, printing, the controller family, colour/font panels — plus the post-10.6 pile
(`NSCollectionView` layouts, `NSAppearance`, gestures) that is *not owed* under the current pin.

---

## 4. Traps this session paid for, so the next one need not

**Parser traps** (all documented in `tools/api-ledger`'s header, with the wrong answer each produced):

* A pattern that consumed the delimiter after a name put `m.end()` past the `;`, so a forward
  declaration was read as a definition and swallowed a 113-selector class block.
* `^\s*([-+])` line-anchored matching plus `m.start()` gives an **empty prefix** — the `typedef`
  and `inline` guards were dead code for three revisions because the prefix ran to the line start.
* `@synthesize`, `@property (getter=isHidden)`, and `FN_FLAG_PAIR(setOneShot, isOneShot, _iv)`
  all create accessors with **no method line to find**. Any new metric must decide about all three.

**Foundation traps** — `libagora-base` is a from-scratch reimplementation, not Apple's:

* `-[NSSet member:]` is a **linear scan**. Inserting 100k dictionary words is quadratic and hangs;
  `NSSpellChecker` uses an open-addressed C hash set instead. **Check what an operation costs
  before using it for bulk data.**
* `NSMutableSet` is not a map: looking a tag up with `-member:` silently misses (an `NSMutableSet`
  can never be `isEqual:` to an `NSNumber`). That was the ignore-list bug.
* `NSBitmapImageRep -colorAtX:y:` indexes rows from the **opposite end** to the drawing
  coordinates. Five confident wrong test failures came from that; the sampler now converts once.

**Test traps:**

* A one-point dotted rule on a fractional y is **antialiased**. A "near-pure colour" assertion
  calls a correct line absent; ask whether the colour *dominates* instead.
* Sampling one pixel to assert a *region's* property is the same class of bug as counting a
  substring — the segmented-control test sampled a pixel inside the letter `B` and called the
  plate wrong.
* Several tests are **region** assertions on purpose: the nine-part image composer fills all 768
  pixels of its frame and nothing outside it, which fails if any corner, edge or centre is wrong.

**Placement traps** (four occurrences, one cause):

Inserting a declaration into an existing header or implementation is where this session lost the
most time. `NS_ASSUME_NONNULL_END` sits **after `@end`** in most headers here, so inserting before
it puts methods outside the class; ivar blocks end with a bare `}` that is easy to overshoot; and
appending to a `.m` lands after the last `@end`. **Anchor on a unique adjacent line, verify the
result compiles before writing more, and never `git checkout --` a file that carries intended
changes** (that mistake wiped 36 declarations once and had to be rebuilt by hand).

---

## 5. Where to spend the next hour

Ranked by reachable surface per unit of work, with entry points.

### 5.1 `NSRulerView` — LANDED, see §9

*Was: 15 `NSTextView` doors + 2 `NSLayoutManager` ones.*

The last piece of the text system that is **geometry** (which this tree now does well) rather than
a new subsystem. One class, plus `NSRulerMarker`.

* Declare `NSRulerView.h`/`.m`; `NSTextView` gains `rulerView:didAddMarker:`, `…didMoveMarker:`,
  `…didRemoveMarker:`, `…handleMouseDown:`, `…willMoveMarker:`, and `isRulerVisible` /
  `setRulerVisible:`; the manager gains `rulerAccessoryViewForTextView:paragraphStyle:ruler:enabled:`
  and `rulerMarkersForTextView:paragraphStyle:ruler:`.
* The markers are tab stops, which `NSTextTab` and `NSParagraphStyle` already carry.

### 5.2 The substitution machinery — ~12 doors, and the tables already exist

The five flags are stored (`_automaticQuoteSubstitution`, …). What is missing is the *tables*:
`NSSpellChecker` has `userQuotesArrayForLanguage:` and `userReplacementsDictionary`. Wire typing
through them and the `toggle*Substitution:` pair becomes visible behaviour instead of a stored bit.

### 5.3 `NSLayoutManager` text-block and attachment rects — 11 doors

`boundsRectForTextBlock:atIndex:effectiveRange:`, `layoutRectForTextBlock:glyphRange:`,
`attachmentSizeForGlyphAtIndex:`, `showAttachmentCell:inRect:characterIndex:`. The boxes exist
(`FNBox`, `cg_drawBlocksForGlyphRange:`); these doors expose what is already computed.

### 5.4 Leave these as declared refusals

* **Sharing/links** (10 in `NSTextView`) — need a services registry the tree has no equivalent of.
* **Grammar** — `checkGrammarOfString:` needs an engine that does not exist on this platform.
* **OpenGL, QuickDraw, movies** — the plan's A11: declare and refuse, ~2 days total, no reachable
  surface gained.

---

## 6. How to add a slice without breaking the instruments

1. **Measure first**: `./tools/api-ledger missing …` tells you the cluster sizes, so you pick by
   reachable surface rather than by name recognition.
2. **Write the header declaration where Apple declares it**, inside the `@interface`.
3. **Implement**, and make every deviation a comment at the door: what it does not do, and why.
   A refusal that answers its type's empty value beats a stub that looks implemented.
4. **Test the claim, not the code**: pixel tests for drawing, round trips for mappings, and a
   *negative* assertion wherever the positive one could pass for the wrong reason (unmarked view
   draws no red; second draw leaves no find ring).
5. **Let the gate fail** (`ctest -R appkit-api-census`), then re-pin `tests/api-10.6-census.txt`
   in the same commit and say in the message what moved. That failure is the instrument working.
6. **Run the whole suite**: `cd build && ctest -j4` — it is 50 seconds, and there is no excuse.

If a metric's meaning changes (as `functions-present` did, from declared to defined), the gate
will report drift in every affected line. That is correct: re-pin deliberately.

---

## 7. Two things a reader should not have to rediscover

* **A CENSUS'S METRICS ARE PINNED AND ITS PROSE IS NOT.** `tests/api-10.6-census.txt` carries hand-written summary
  lines above the 436 metrics; this session left one of them reading "80 declared" for three slices after the number
  became 86, and the gate did not notice, because a comment is not a metric. A warning now sits beside that block.
  When re-pinning, recompute the prose from `api-ledger census` instead of editing it by eye.
* **The censuses are claims, and they are checked in both directions per file.** Changing one is a
  deliberate act with a diff. `tests/refusal_census.txt` (141) and `tests/owed_census.txt` (19)
  count what the tree says it *cannot* do; `tests/api-10.6-census.txt` counts what it *can*. Both
  kinds drift the same way, which is why `claims_census.cmake` holds them identically — and why it
  now strips comment lines before splitting, because a semicolon in prose used to fragment the
  census into a line that was not `file count`.
* **The refusal census only counts inline `APPKIT-REFUSE` literals.** Doors that call the shared
  `fn_refuse_window` helper — which is most of the new ones — are invisible to it. Ten function
  refusals and a handful of method refusals therefore do not appear in the 141. If that matters,
  the fix is a second needle for `fn_refuse_window(` call sites, not a bigger comment.

---

## 9. The session that picked this up

*What landed, in two commits, and what it cost.*

**`NSRulerView` and `NSRulerMarker`, plus the strip `NSScrollView` tiles.** 32 and 19 selectors, both COMPLETE —
which is what the ledger shows and the first time since `NSText` that a whole pair has come over at once. The view owns
the thickness arithmetic (`ruleThickness` + two reserves, the sum `-tile` takes off the content's edge), the unit table
with four built-in units and `+registerUnitWithName:…`, the hash marks, the marker list and the drag session. The
marker owns an image at a location plus an origin across the ruler.

**The text system's half.** `NSText -copyRuler:`/`-pasteRuler:`/`-toggleRuler:`/`-isRulerVisible`, `NSTextView`'s five
ruler doors and the nine client messages, and `NSLayoutManager`'s two: a marker per `NSTextTab` at the tab's location
plus the ruler's origin offset, with the tab as `representedObject`. `NSText` is COMPLETE now (39/39), which nobody
predicted: the four ruler commands were the last four selectors it owed.

**Four decisions worth not rediscovering:**

* **The ruler does not scroll — it moves its BOUNDS ORIGIN**, which the scroll view keeps equal to the clip view's on the
  ruler's own axis. That is the whole of "a mark at document 300 is under the character at 300", and it is one line in
  `-reflectScrolledClipView:` per orientation.
* **BOTH ORIENTATIONS ARE FLIPPED, against Apple**, whose vertical ruler is not. A vertical marker location then grows
  downward with the text it measures, and no conversion is needed anywhere the manager and the ruler meet. Documented at
  `-isFlipped`.
* **A DRAG IS A STREAM, NOT A MODAL LOOP.** `-trackMouse:adding:` refuses by name (the same refusal `NSCell` makes); the
  ruler's `-mouseDown:`/`-mouseDragged:`/`-mouseUp:` run the drag from the event stream the application already pumps,
  absolutely from the grab point, with ONE `didMove` on the release. A `didMove` per dragged event would rewrite the
  paragraph's tab stops a hundred times for one gesture.
* **THE UNIT TABLE'S CYCLE RUNS FINE TO COARSE**, so the subdivisions are the reciprocal of its FIRST entry. Reading the
  last entry made points and inches subdivide once, and the ruler drew only its labelled ticks — a wrong answer that
  looked like a style choice until a pixel count said 6 marks instead of 60.

**Traps this session paid for:**

* A header with `NS_ASSUME_NONNULL_BEGIN` and a **forward declaration missing for the class's own forward use**
  (`NSRulerMarker` naming `NSRulerView` before `@class NSRulerView;`) fails as "unknown type name" on a line that looks
  unrelated. And `NSLayoutManager.h` needed `@class NSView;` before the new door — an appkit header that imports only
  `NSFont.h` has never needed `NSView` before.
* **A category interface placed inside an `@implementation` is not a category.** Two `@end`s and one implementation, and
  the compiler's message ("missing '@end'") names the wrong line. Declare the private category BEFORE the class's
  `@implementation`, or the methods land outside it.
* **The census prose went stale exactly as §7 warned**: the summary block still called the C functions the weakest part
  and said the tree "does not yet fill a rectangle" — nine slices after `NSRectFill` landed. It is recomputed now, and
  the sentence says so.

**Where to go next, re-ranked by reachable surface:**

1. **THE MISSING CLASSES CONTINUE (§17–§21): 103 of 168 classes and 26 of 56 protocols.** What is left among the SMALL
   ones is `NSTouch` (6 selectors — but it has no public initialiser, so nothing in this tier can produce one) and
   `NSCollectionView` (28) around the item just added. The largest remaining single class is `NSFileWrapper` (35 — the RTFD
   and attachment substrate, and `NSImageRep`'s file doors already name its shape); then the surface is the big subsystems
   the plan names — documents (104 + 51), printing (46 + 41 + 27 + 20), the panels, and the controller family — which want a
   design rather than a slice. The 30 MISSING PROTOCOLS are a cheaper axis: most are delegate protocols a class already
   sends informally (`NSTableViewDelegate` is present, the drag and collection ones are not).

2. **`NSLayoutManager` IS COMPLETE (§16) — all 136 selectors — and so are the twelve one-selector-short classes (§15).**
   The manager's last six were the typesetter trio, spelled `id` for the reason §16 records. What is left in the text
   system is the two classes those doors name, if anyone wants them: `NSTypesetter` (61 selectors — the era's own line
   breaker, which Core Text replaces here) and `NSGlyphGenerator` (2). Everything else in the manager is reachable, so the
   next hour belongs elsewhere: the panels (open/save, colour, font, print), the document and controller family, and the
   33 missing protocols, all of which the surface plan names as the 10.6 periphery.
2. **The substitution machinery** (the old §5.2, ~12 doors): the five flags are stored; the tables
   (`userQuotesArrayForLanguage:`, `userReplacementsDictionary`) are what would make typing through them real.
3. **`NSTextView`'s ruler accessory** — the one door this slice refused. A tab-type control cluster is an
   `NSPopUpButton` and an action; the reserve arithmetic already accounts for whatever is installed.

---

## 10. And then the layout's measurements

*Third commit of the pickup: the eleven text-block and attachment doors.*

`boundsRectForTextBlock:…`, `layoutRectForTextBlock:…` (both spellings each), the two setters, `setAttachmentSize:`,
`attachmentSizeForGlyphAtIndex:`, `defaultAttachmentScaling` and `showAttachmentCell:inRect:characterIndex:`. The manager
keeps an OVERRIDE TABLE for the two rects (a caller's value wins; the getter computes otherwise) and a per-character size
table for attachments that `-cg_boxesForRange:` consults when it builds the run delegate — so the override reaches the
ENGINE, not only the answer. `NSLayoutManager` is 70 of 136 now.

**Three things this slice learned, all recorded at the code:**

* **A table cell's bounds are measured from its column band, not its text.** `-cg_addCell:` unions `fragment->rect` for a
  cell and `fragment->used` for a plain block, so a door that used the text band would answer a rectangle the drawing
  pass never painted. The MEASURED shape: a custom block grows its layout rect by exactly padding+border (sixteen points
  for six and two), while a cell's bounds exceed its text by MORE than its layers because the band is the cell's width.
* **`-colorAtX:y:` indexes from the opposite end to the drawing coordinates**, which the §4 trap list already said and
  this slice paid for again: a 40x40 picture filled its rect exactly and the naive band called 80 of its pixels
  "outside". The probe now converts the rect to a row band once (`row = H - 1 - y`) and says why.
* **A test that reuses a manager inherits its overrides.** The drawing checks drew at the size a previous section had
  overridden (40x30) rather than the cell's 12x12, and the failure looked like a scaling bug. The drawing checks now build
  their own manager, which is the cheap version of "a test that passes for the wrong reason is worse than one that
  fails".

---

## 11. The highlight that is not an edit, and the rects a selection redraws

*Fourth commit of the pickup: 8 temporary-attribute doors and the 2 rect arrays. `NSLayoutManager` is 80 of 136.*

**The temporary table is the find-highlight slice, and it cost one real bug.** The table is a sorted, non-overlapping run
list beside the store; the drawing pass reads its ink through ONE helper that merges the two and asks the delegate's
`shouldUseTemporaryAttributes:` question. THE FIRST VERSION STEPPED OVER THE ATTRIBUTE: a store run with a uniform colour
returned its whole range as the "longest effective range", so the glyph walk drew the line in one colour and never reached
the temporary run in the middle of it. A red character in a green line drew green — and the delegate test passed, because
its temporary run started at index 0. The fix is that a store run's effective range stops at the NEXT TEMPORARY RUN even
when the index is not inside one; that is the contract the walk depends on, and it is now stated at the helper.

**Two smaller things worth keeping:**

* The run table SPLITS on set, MERGES on add, deletes one key on remove, and merges equal neighbours after every change —
  which is what makes `longestEffectiveRange:` answer the range over which a value does not change rather than the range
  of one stored record.
* `-rectArrayForGlyphRange:…` answers a POINTER into the manager's buffer, valid until the next call, which is Apple's
  shape and the reason a selection redraw allocates nothing. Its caret case asks `-cg_fragmentForGlyphAtIndex:` rather
  than scanning, because a boundary index belongs to the line it OPENS.
* **`withinSelected…` has nothing to decide in this tier**, and the door says so: the breaker produces no extra-line
  fragment for a trailing newline (the newline's glyph belongs to the line it ends), so both selections answer the same
  rects. The branch is kept — the rule is the door's, not the layout's — and the test asserts today's state.

---

## 12. Being told what changed, three ways

*Fifth commit of the pickup: 18 doors — ensure, invalidate, the container tidings, the extra line and two font
measurements. `NSLayoutManager` is 98 of 136.*

**The three kinds of staleness Apple separates are one in this tier, and the doors still differ in what a caller
observes.** Glyph, layout and display invalidation all mark the same record (the fragments are rebuilt from the store), so
the interesting part of the slice is where each one LANDS: the record, the view's damage rect, or a full re-wrap for a
geometry change. That is also how the test is written — each door is checked where a caller could see it, not by reading
the flag it set.

**Three smaller decisions, all stated at the door:**

* **`-invalidateLayoutForCharacterRange:isSoft:` records softness in prose and acts on none of it** — Apple's soft
  invalidation defers the layout of marked text, and this tier already lays out only when asked.
* **A display invalidation offsets the bounding rect by the container's line-fragment padding** before asking the view,
  because that is where this tier's text views put their container. The padding is added on BOTH axes, so a view that
  placed its container elsewhere gets a wider damage rect rather than a wrong one.
* **`-glyphRangeForBoundingRect:` hits a fragment by its FLOW BAND, not its ink.** A rect that clips the end of an
  indented line still covers that line, and the used rect would answer "no glyphs here" for the leading space.

**And one thing worth remembering about the tier's own test tools:** `-[NSView display]` is not implemented here (only
`-displayRect:` and the `-displayIfNeeded…` family), so a probe that wants to clear pending damage before asserting on it
sets `-setNeedsDisplay:NO`. The first version of this test aborted on the missing door, which is the same class of
surprise as `-NSTextBlock setWidth:…forEdge:` in §10: a declared door is not an implemented one, and only the probe finds
out.

---

## 13. Knobs, and the door that had no callers

*Sixth commit of the pickup: 21 doors — the flag family, the caret's insertion points, the three view questions.
`NSLayoutManager` is 119 of 136.*

**`-cg_lineHeight` HAD NO CALLERS.** It answered the line height, and the breaker computed `ascender - descender` again at
its own site, so a knob that changed the door changed nothing on screen. The layout now stacks every fragment through
that one door, which is what makes `-usesFontLeading` live: with the flag on, the line is the font's leading taller and the
SECOND line's baseline moves by exactly that — the assertion the test makes, in Helvetica, because the default font's
leading measures zero on this machine and the claim would be untestable with it.

**Two other things worth keeping:**

* **`-usesFontLeading` defaults to NO, a stated deviation from Apple's YES.** Leading has never been in this tier's
  layout; flipping the default with the flag's arrival would move every document on screen by the font's leading, which is
  a layout decision and not a flag's side effect.
* **The stored knobs say what they would mean.** `-hasNonContiguousLayout` is `NO` by construction (a layout here is
  complete), `-hyphenationFactor` does not fall back to the paragraph style's (a second source for one number is how two
  paragraphs come to hyphenate differently from the same factor), and `-layoutOptions` has no bits defined.

**And one trap in the test, not the code:** `-layoutManagerOwnsFirstResponderInWindow:` compares the responder's manager
with the receiver, so a hand-built manager attached to a view's container is a DIFFERENT manager and the positive case is
false for the right reason. The probe now uses the view's own trio, and the negative case hands responder status to a
field — a real handover rather than a `makeFirstResponder:` that quietly failed.

---

## 14. The shadow's bulk doors, and a rule that drew nothing

*Seventh commit of the pickup: 11 doors — the glyph store's range readers and sub-class writers, the strike pair, the
background fill, and three singles. `NSLayoutManager` is 130 of 136, with only the typesetter trio's six left.*

**A PRE-EXISTING BUG FELL OUT OF THE STRIKE TEST.** `-ag_xForGlyph:inFragment:` answered the line's LEFT edge for a glyph
past the fragment (`-characterIndexForGlyphAtIndex:` says `NSNotFound`, and the fallback was the used rect's origin). Both
rule doors ask for `glyphRange.location + glyphRange.length`, so a strike — or an underline — over a range that ended at
the line's end came out with `x1 <= x0` and RETURNED WITHOUT DRAWING. A whole line could not be underlined. The fix is
one line, and the test that found it is the one that counts pixels: plain draw 0, struck draw 36.

**The rest of the slice, and what each group decided:**

* The two `getGlyphsInRange:` spellings fill their buffers from the SAME shadow `-glyphAtIndex:` reads, so the test can
  compare them; past the end every slot still gets an answer (`NSNullGlyph`, the index asked for), because a caller named a
  count.
* `-setLineFragmentRect:forGlyphRange:usedRect:` writes the fragments' own rects and marks the glyph store stale; its
  effect is checked through `-lineFragmentRectForGlyphAtIndex:` and `-lineFragmentUsedRectForGlyphAtIndex:` rather than by
  reading the fragment.
* `-setTextContainer:forGlyphRange:` is the one door that needed a new table: a record consulted BEFORE the fragment scan
  in both `-textContainerForGlyphAtIndex:` spellings, trimming any earlier record it overlaps — the same split the
  temporary-attribute table uses.
* `-rangeOfNominallySpacedGlyphsContainingIndex:` really compares the shaper's advance against `CTFontGetAdvancesForGlyphs`
  per glyph. This tier kerns nothing, so the answer is normally the line — and the walk is still written, because the
  door's name promises a BOUNDARY rather than the common case.
* `-showPackedGlyphs:…` refuses by name (the pre-10.4 `NSPackedGlyphs` encoding is not a `CGGlyph` array) and
  `-substituteFontForFont:` answers the font itself (no screen-font variants).

---

## 15. The loose ends: twelve classes, seventeen doors

*Eighth commit of the pickup: everything that was a selector or two short, so the "almost complete" list is empty.
Complete coverage went from 33 to 45 of the 83 present classes.*

| Class | Doors | What it does |
|---|---|---|
| `NSEvent` | `-window` | the application's registry lookup by number — the class it names exists now, so §4's note about the instrument is retired |
| `NSFontDescriptor` | `+fontDescriptorWithName:matrix:` | the name and matrix attributes composed, and read back through `-matrix` |
| `NSPDFImageRep` | `-PDFRepresentation` | the bytes it parsed, not a re-encode |
| `NSParagraphStyle` / `NSMutableParagraphStyle` | `-headerLevel`, `-setHeaderLevel:`, `-setParagraphStyle:` | stored, copied, and carried by the bulk assignment (whose arrays are copies) |
| `NSScreen` | `-colorSpace` | **refused by name**: `NSColorSpace` is not in this tier |
| `NSTextField` | `-setTitleWithMnemonic:` | the era's marker rule: `&&` → `&`, a single `&` dropped |
| `NSMenuItemCell` | `-menuView`/`-setMenuView:` | borrowed back-pointer |
| `NSOutlineView` | `-setDropItem:dropChildIndex:`, `-shouldCollapseAutoExpandedItemsForDeposited:` | the drop record (and a redraw) and a policy that answers YES |
| `NSTableColumn` | `-isResizable`/`-setResizable:` | the mask's USER bit, so the boolean and a header drag cannot disagree |
| `NSTextFieldCell` | `-allowedInputSourceLocales`/setter | stored, copied with the cell |
| `NSBezierPath` | `-setAssociatedPoints:atIndex:` | **refused by name**: a CGPath is append-only, the same reason its unindexed twin gives |

**What this slice learned to be careful about, twice:**

* **`@end` IS NOT A UNIQUE ANCHOR IN A HEADER.** A door appended before a file's LAST `@end` landed inside the
  `NSTextFieldDelegate` PROTOCOL — it compiled, and the warning was one line in a `-may not respond` note. The lesson is
  the §4 placement trap in a new place: anchor on a unique ADJACENT LINE, and check that the door is inside the class the
  header is about.
* **A PROPERTY DECLARED ON THE BASE CLASS MUST BE IMPLEMENTED ON THE BASE CLASS.** `-headerLevel` was written into
  `@implementation NSMutableParagraphStyle` (next to the other setters) and the first `[style headerLevel]` on a copied
  style aborted with "not implemented": a copy of a mutable style is still answered by the base implementation's
  `-copy`, and the base class did not have the getter. The fix is placement, not logic.

**And one honest gap recorded in the test rather than papered over:** the event's window has NO positive case headlessly.
A window's number is assigned when its surface is made, which needs a compositor, so `-windowNumber` answers -1 and the
registry is empty. The probe asserts the CONTRACT — the door is exactly the application's lookup for the number — and says
why a live window cannot appear in it.

---

## 16. Completing the layout manager: the typesetter trio

*Ninth commit of the pickup: six doors, and `NSLayoutManager` is 136 of 136 — complete against the 10.6 manifest, and the
first class of this size to finish.*

**THE DOORS ARE SPELLED `id`, AND THAT IS THE TREE'S OWN RULE APPLIED TO A NEW CASE.** Apple names `NSTypesetter *` and
`NSGlyphGenerator *`. This tier has neither class, and naming one in a header is exactly the trap `NSScreen.h` records: a
name in a header can CREDIT a class row that no implementation answers to (NSScreen itself was "shipped" for three commits
while no such class existed, because a `@class` in `NSWindow.h` was taken for a declaration). So the four object doors are
`id` — the same spelling `NSEvent -trackingArea` uses — they round-trip, nil clears them, and the header says in as many
words that NOTHING CONSULTS THEM: the breaker builds a `CTTypesetter` from the store and Core Text's shaper is the glyph
generator, so there is no `NSTypesetter` in this tier's flow at all.

**The behaviour is a real value, so it is treated as one.** Apple's `NSTypesetterBehavior` is `NSInteger`, its default is
`NSTypesetterLatestBehavior` (-1), and the five numbers are pinned in the test — an enum edit that changed one would move a
caller's archived setting without moving anything visible. Its home in Apple's headers is `NSTypesetter.h`, which this tier
has not got, so the enum is declared beside its only users and the header says where it must MOVE when that class arrives:
two declarations of one enum is how the two come to disagree.

**The one behavioural difference from Apple is stated, not hidden:** `-typesetter` in Apple CREATES a default typesetter on
first ask; this tier has none to make, so the answer is nil until a caller sets one.

**What the census says now:** `NSLayoutManager` 136/136; complete classes 46 of the 83 present; selectors 2829 of 3568
(79%). The text system's remaining debt is the two classes those doors name, and neither is a slice anyone needs: Core Text
does both jobs here.

---

## 17. The first of the missing classes: the colour-and-drawing values

*Tenth commit of the pickup: `NSColorSpace` (19), `NSShadow` (8), `NSGradient` (14) — 41 selectors and three classes off the
84 that had none. Complete coverage 46 → 49 of the 86 present classes; 87 of 168 classes present.*

**THE CHOICE WAS MEASURED, NOT GUESSED.** The ledger lists 84 classes and 1640 selectors of debt; the plan's own priority is
the 10.6 periphery (documents, panels, printing, controllers), and those are subsystems — a first slice that tried one would
be a partial subsystem rather than a finished class. The three values were chosen because each has a SUBSTRATE THAT ALREADY
EXISTS (`CGColorSpace`, `CGContextSetShadowWithColor`, `CGGradient`), each is COMPLETE at its manifest size, and two of them
RETIRE REFUSALS the tree had recorded: `NSColor`'s colour-space pair and `NSScreen -colorSpace`.

**Four decisions worth not rediscovering:**

* **THE NINE NAMED SPACES ARE SINGLETONS.** A space is a value; two objects for one value is how a comparison comes to be
  false, and `+availableColorSpacesWithModel:` would answer duplicates if each door made a new one.
* **`-set` NEGATES THE SHADOW'S Y.** AppKit's offset is in the era's y-down drawing space and `CGContextSetShadow`'s
  positive y is up, so (0, −3) — a shadow BELOW the ink — is `(0, +3)` to the engine. Everything else about the shadow is a
  value, which is why the class has one state door.
* **THE GRADIENT'S PLACEMENT ARITHMETIC IS OURS BECAUSE THE ENGINE HAS NO DOOR FOR IT.** An angle across a rect is the
  ramp's line through the middle with length |w·cos| + |h·sin|; a relative centre is (−1..1) of half the rect with a radius
  to the corners. Both are stated at the door.
* **`-colorUsingColorSpace:` DOES ARITHMETIC AND SAYS SO.** Same model → RELABEL (the numbers are unchanged and the result is
  in the space asked for); gray↔RGB and RGB↔CMYK → the standard formulas, named in the comment; Lab/indexed/pattern →
  refuse, because this tier has no ColorSync and a managed conversion it cannot do is worse than a stated refusal. The
  refusal census moved 142 → 140 as the two old literals went.

**One test trap, again the same family:** a screen exists headlessly but its `-depth` is 0 (no output), so `-colorSpace`
answers nil — and the probe now asserts the CONTRACT (nil when the depth names no space, the RGB space when it does) rather
than a constant. The first version failed for the right reason and the wrong claim.

---

## 18. The image rep family: five classes, three real and two named

*Eleventh commit of the pickup: `NSCustomImageRep`, `NSCachedImageRep`, `NSEPSImageRep`, `NSPICTImageRep`, `NSCIImageRep` —
19 selectors, five classes. Complete coverage 49 → 54 of the 91 present classes; 92 of 168 classes present.*

**THE FAMILY WAS THE RIGHT NEXT SLICE BECAUSE `NSImageRep` ALREADY DISPATCHES TO IT.** The registry, the sniff contract and
the base class's `-CGImage` blit were all here; what was missing was the five classes that use them. Three are real and two
are honest absences, and each says which at its door:

* `NSCustomImageRep` invokes its draw selector with the era's three arguments — the rep, the rectangle **by value**, and
  YES for a screen draw — through `-methodForSelector:`'s IMP, because `-performSelector:` cannot carry an `NSRect` and
  **this tier's `NSInvocation` refuses a 32-byte argument** ("marshals register arguments only", which its own header
  states). The signature is checked at construction, so a rep that cannot draw is never made.
* `NSCachedImageRep` is a real cache: a blank canvas, or a window rectangle rendered ONCE through the view's own
  `-cacheDisplayInRect:toBitmapImageRep:` and blitted by the base's `-CGImage`. MEASURED: a capture of a red view blits
  2400 of 2400 pixels red.
* `NSEPSImageRep` parses the header — `%!PS` for the sniff, `%%BoundingBox:` for the size — and REFUSES TO RENDER, because
  rendering PostScript needs an interpreter and `CGPSConverter` is not in this tier. It registers itself, which is what
  makes `+imageRepClassForData:` answer it for an EPS file.
* `NSPICTImageRep` and `NSCIImageRep` refuse at their constructors (no QuickDraw player, no Core Image) and their sniffs
  answer NO rather than promising a decode they cannot do. The test also asks about a format with **no** rep and about PNG,
  so their nil answers cannot pass merely because the registry is empty.

**A test that passed and still crashed, which is the worst shape a bug can take.** `+imageRepWithData:` returns an
AUTORELEASED rep and the test released it as well; every check printed `ok`, the summary printed "all checks passed", and
the process segfaulted in `emptyPool` at the pool's drain. The fix is one line in the test, and the lesson is the handoff's
own: a suite that reports from stdout cannot see a failure that happens after the last printf — the exit status can.

**And one environment scare worth recording:** mid-slice, six unrelated tests failed. They failed with this slice STASHED
too — the concurrent Swift session was rebuilding `build-prefix` (libobjc, libagora-base, libagora-drawing) while the suite
ran. After it settled, 124 of 125 passed again with the slice in place. A failing suite is evidence only once you know
which libraries the binaries actually loaded.

---

## 19. The stepper and the secure field: a control that steps, and a cell that hides

*Twelfth commit of the pickup: `NSStepper`/`NSStepperCell` (20 selectors) and `NSSecureTextField`/`NSSecureTextFieldCell`
(2). Complete coverage 54 → 57 of the 94 present classes; 96 of 168 classes present.*

**`NSCell -setDoubleValue:` ANSWERS ONLY FOR A TEXT CELL.** `if (_type != NSTextCellType) return;` — so the first stepper,
which inherited the value pair, had arrows that moved nothing. The probe caught it as four failures that all read "the value
did not change", and the fix is the cell's own field with both doors overridden. This is the third door in this session
whose *declared* behaviour differed from what a subclass needed (`-cg_lineHeight` had no callers; `NSInvocation` refuses a
32-byte argument); a tier this thin keeps its surprises in the seams between a base class's contract and a subclass's use.

**Two more things worth keeping:**

* **THE FLIP DECIDES WHICH ARROW IS "UP".** The cell reads the direction through `-isFlipped`, so the same press point steps
  up in an unflipped view and down in a flipped one — the probe drives both and requires opposite answers, which is the
  slider's tick-direction trap in another control.
* **A CELL'S ACTION GOES THROUGH ITS CONTROL.** `-sendAction:to:` is `NSControl`'s, so a cell whose "control view" is a bare
  `NSView` steps silently and sends nothing — MEASURED, and the probe now hands the cell the stepper itself.
* **THE SECURE FIELD IS ONE OVERRIDE, IN THE DOOR THAT IS BOTH DRAWN AND MEASURED.** `-cg_contentText` is what the base
  draws AND what it measures, so bullets are the width of the password and the caret sits on them by construction. The
  probe renders the field twice (flag on and off) and compares the dark ink: 40 pixels of bullets against 146 of letters.

---

## 20. The nib's connections, and a pasteboard item

*Thirteenth commit of the pickup: `NSNibConnector` and its two subclasses, and `NSPasteboardItem` — 19 selectors, four
classes. **100 of 168 classes are now present**; complete coverage 57 → 61 of the 98 present classes.*

**THE CONNECTOR IS AN OBJECT BECAUSE A NIB'S CONNECTION IS DATA, AND ITS TWO SUBCLASSES ARE TWO APPLICATIONS.** The base
holds `source`, `destination` and `label`, and its `-establishConnection` does nothing — Apple's own contract. The outlet
subclass writes a key path; the control subclass sets a target and an action, with the label as the selector NAME. The
identity substitution (`-replaceObject:withObject:`) is the loader's door, and it compares by pointer because a nib's
placeholder is a stand-in OBJECT rather than a name.

**The one that had to catch an exception:** `NSObject` answers `-setValue:forKeyPath:` for EVERY object, so a
`-respondsToSelector:` guard cannot tell a view with an outlet from a string with none — the only test is the write, and it
raises. `NSNib`'s own connection pass already catches that exception for that reason; the connector now does too, so a
defective connection is SKIPPED with a message rather than taking the load down.

**`NSPasteboardItem` is a writer without declaring the protocol it writes by.** `NSPasteboard -writeObjects:` sends
`-writableTypesForPasteboard:` and `-pasteboardPropertyListForType:` through `-respondsToSelector:` — the file's own stated
rule, because `NSPasteboardWriting` is a row this tier has not got. So the item implements the two METHODS and a board
accepts it; the test writes an item and reads its string back off the board. Its provider is asked LAZILY (zero asks until
its type is read) and the answer is cached (one ask, not two).

**And a runtime detail the test had to learn:** this runtime keeps TYPED selector records, so `NSSelectorFromString("x")`
and the compiler's `@selector(x)` need not be the same POINTER. A probe comparing actions must compare NAMES; the
connector's job is the name, which is what a nib's label can promise.

---

## 21. Small classes and the protocols that were owed

*Fourteenth commit of the pickup: `NSGlyphInfo` (6), `NSImageCell` (6), `NSCollectionViewItem` (3), and the three pasteboard
protocols. **103 of 168 classes, 26 of 56 protocols.***

**`NSGlyphInfo` REFUSES BOTH OF THE ENGINE'S "NO" ANSWERS.** `CTFontGetGlyphWithName` says `.notdef` (0) for a name a face
maps to nothing and `kCGFontIndexInvalid` (0xFFFF) for one it has never heard of — two different answers for one question, and
a glyph info that took either would be naming a glyph nobody asked for. The index factory keeps the documented gap: this tier
has no glyph-to-name lookup, so `-glyphName` is nil there and the header says so.

**THE IMAGE CELL'S THREE FACTS ARE PIXELS, SO THE PROBE READS PIXELS.** Alignment, scaling and frame style are stored values a
cell could ignore; the test renders the cell in three configurations and checks the RED INK'S EXTENT (`x 0..9` left, `W-10..W-1`
right, full cell under `NSImageScaleAxesIndependently`). A stored-and-ignored fact fails those and passes every value check.

**AND THE PROTOCOLS WERE THE CHEAPEST REMAINING AXIS.** `NSPasteboardWriting`, `NSPasteboardReading` and
`NSPasteboardItemDataProvider` are now declared, which lets `NSPasteboardItem` say it CONFORMS to the writer it already
implemented by `-respondsToSelector:` — the previous slice's note said the protocol was a row still owed, and this closes it.
The declaration also typed the provider's optional method, so the provider's answer is a declared contract rather than a
guessed selector.

**A placement lesson, again:** the protocol block's first two attempts landed INSIDE `@interface NSPasteboard` (the option
typedefs it needs live inside the class body, so "after the typedefs" is still inside), and a line-based move then split a
comment in half and left a fragment after the `#endif`. The fix was `git checkout` of the header and an anchor on the class's
own `@end` — the §4 placement trap, in its third shape this session.

---

## 22. A census that counts one class it cannot be paid for, and `NSBox`

*Fifteenth commit of the pickup: `NSBox` (30 selectors) — and a finding about the instrument that has been true since the
censuses began.*

**`NSFileWrapper` IS NOT THIS COMPONENT'S TO IMPLEMENT.** The session started on it, on the reasoning that it is the largest
remaining class with an existing substrate (35 selectors, the RTFD/attachment tree). The compiler answered in one line:
`redefinition of enumerator 'NSFileWrapperReadingImmediate'`. `NSFileWrapper` is a **Foundation** class in this stack —
`libagora-base/NSFileWrapper.h`, 47 methods — which is also Apple's own home for it; the 10.6 AppKit umbrella imports
Foundation, so `manifest` lists the class and `census` counts it MISSING, because the instrument scans THIS component's
sources. **The count is one high by construction**, and the census now says so in prose rather than excusing it in code. It
was found by trying to pay a debt that was already paid.

The check that measured it: of the 65 classes the ledger called missing, exactly **one** is defined elsewhere in the
installed prefix, and four are only forward-declared in this tree's headers (`NSCollectionView`, `NSDocument`,
`NSFileWrapper`, `NSOpenPanel`).

**`NSBox` WAS THE RIGHT CLASS AFTER THAT**, and its slice found an arithmetic error the value checks would not have: the
content rectangle subtracted the title's band from BOTH margins (`NSInsetRect` with the band folded into `dy`) while
`-setFrameFromContentFrame:` added it ONCE, so a round trip left the content seven points short. The test now goes round the
loop — a content frame in, the same frame back — which is the only assertion that holds those two formulas together.

**And the box's five kinds are checked as five pictures**, because a box that stored its kind and painted one face would pass
every value check: a separator is a line across the middle, a custom box fills its rectangle, and a primary box is ink at the
edges with an empty middle.

---

## 23. Tabs: a selection over views, and a protocol that is actually sent

*Sixteenth commit of the pickup: `NSTabView` (34) + `NSTabViewItem` (17) and the `NSTabViewDelegate` protocol — 51 selectors,
two classes, one protocol. **106 of 168 classes, 27 of 56 protocols.***

**THIS IS THE FIRST PROTOCOL IN THE RECENT RUN THAT THE TREE ACTUALLY SENDS.** The pasteboard protocols were contracts
implemented by `-respondsToSelector:`; `NSTabViewDelegate` is asked three questions on every selection, and the test counts
them. The one that makes it more than a notification is `-tabView:shouldSelectTabViewItem:`: a delegate that answers NO stops
the change, and the probe requires the panes NOT to have moved.

**A TAB VIEW IS A SELECTION OVER VIEWS, NOT A PILE OF HIDDEN VIEWS.** The selected item's view is a subview; the others are
not in the hierarchy at all. That is the difference the test is built on: three items with three panes, and after each
selection exactly one is a subview, and it is the selected one's.

**Two things the probe had to learn (both about the test, not the code):**

* **THE ITEM ORDER IS THE INSERT ORDER, NOT THE ADD ORDER.** The probe adds `one`, adds `two`, then INSERTS `three` at index 1,
  so the strip is `one, three, two` — and the first version of the stepping assertions read as if it were `one, two, three`.
  The test now states the order explicitly before stepping through it, which makes those assertions arithmetic rather than an
  assumption.
* **`-sizeOfLabel:` IS THE ONE MEASURE THE STRIP IS BUILT FROM.** A tab's width and the strip's thickness both come from it, so
  a view with a bigger font has a bigger strip and the least width is a floor rather than a second formula.

**And one structural note:** `NSTabViewItem`'s ivars are `@public`, which is the rule `NSFont`'s substrate ivar already
states — the tab view is the only thing that sets an item's state and adopts its pane, and a private setter triplet would be
three doors to keep in step with three fields.

---

## 24. Animation: a number that moves, and the difference between END and STOP

*Seventeenth commit of the pickup: `NSAnimation` (26), `NSAnimationContext` (5), `NSViewAnimation` (3) and the
`NSAnimationDelegate` protocol — 34 selectors, three classes, one protocol. **109 of 168 classes, 28 of 56 protocols.***

**THE WHOLE CLASS IS ONE NUMBER AND WHO HEARS ABOUT IT.** `-currentProgress` is the linear fraction of the duration,
`-currentValue` is that fraction mapped by the curve or by the delegate, and `-setCurrentProgress:` is the ONE door the timer
uses — which is why a probe can step an animation by hand and a caller with its own frame loop can drive one. The curves are
this tier's own arithmetic and the header says so: Apple publishes the names and not its Bézier control points, so `p²`,
`1-(1-p)²` and a smoothstep are used, monotonic, agreeing with the straight line at both ends — the properties the names
promise, which is what the test checks rather than an exact curve nobody published.

**A REAL TIMED RUN IS THE ASSERTION A HAND-STEPPED ANIMATION CANNOT MAKE.** The probe pumps the run loop for half a second on
a 0.15-second animation at 60 fps and requires `-isAnimating` NO and `animationDidEnd:` heard — which proves the `NSTimer`
went, the clock was read, and the finish path ran. The hand-stepped checks are there for the arithmetic; this one is there for
the machine.

**AND `END` IS NOT `STOP`, WHICH THE FIRST VERSION OF THE PROBE GOT WRONG.** It stepped a NOT-running animation to 1 and
expected an `animationDidEnd:`; the door correctly announced nothing, because the end belongs to a running animation — a
setter that announced one for an animation nobody started would be reporting a lifecycle that never happened. The test now
asserts the absence on purpose, and the real end is asserted where it happens.

**`-startWhenAnimation:reachesProgress:` IS THE ERA'S SEQUENCING**, there being no completion blocks: one animation starts (or
stops) another at a mark, and the probe checks the second is idle until the first crosses it.

---

## 25. The level indicator: a value that becomes a colour

*Eighteenth commit of the pickup: `NSLevelIndicator` (16) + `NSLevelIndicatorCell` (20) — 36 selectors, two classes. **111 of
168 classes.***

**THE CLASS'S OPINION IS THE REASON IT EXISTS.** A progress bar says how far; a level indicator says how far AND whether that is
bad — two thresholds (warning, critical) that change the fill's colour to the platform's orange and red. That is a PIXEL claim,
so the probe reads pixels: at 40% with a warning at 50 the bar's left is exactly `0.00/1.00/0.00` and its right is the control
face `0.90/0.90/0.90`; at 60 it is `1.00/0.50/0.00`; at 90 it is red.

**Four styles, four pictures:** a continuous bar, a discrete row of segments (2 of 4 lit at half the range), a rating of stars
(filled ones in the level colour, empty in the shadow colour, or a caller's image instead) and the relevancy bar in the accent
colour.

**And the same door the stepper's slice found:** `NSCell -setDoubleValue:` answers only for an `NSTextCellType` cell, so the
value lives in this cell and every write goes through one clamped setter. That is now the second class to need it, which is
worth saying plainly: **in this tier, "a cell with a numeric value" means overriding the value pair**, because the base's is a
text cell's.

**One detail worth having written down:** the ticks are `N` marks over `N − 1` intervals, so a five-mark bar has a tick at each
end and three between — the arithmetic `-tickMarkValueAtIndex:` is the definition, and `-rectOfTickMarkAtIndex:` is that
fraction of the bar's width.
