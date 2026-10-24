# libagora-app — a seventh handoff

*Written at the end of **three slices and one fix** that picked the controller question up where `HANDOFF-6.md` §6
stopped — the substrate first, in `libagora-base`, and then the binding layer in this repository. `HANDOFF-6.md` is
still the long form of everything up to §12 (the rule editor); §1–§7 of that file remain worth reading, and its §4
traps are still the ones these sessions used most. **THIS FILE'S §2 NUMBERS SUPERSEDE EVERY EARLIER HANDOFF'S.***

*State at this handover: **eleven slice commits** since the sixth handoff — four in `libagora-base`, seven here — tree
clean, **181 tests passing in about 98 s**, `api-ledger check` holding **391 metrics** — **147 of 168 classes (88%),
4827 of 4827 selectors (100%), 44 of 56 protocols (78%), 86 of 86 functions**, 5406 methods declared with 8 having no
body, **all 147 classes with a surface at COMPLETE coverage** — refusal census **404** (DOWN by one, the first fall in
this arc), owed census **21**. **The 21 absent classes and the 12 absent protocols are the remaining surface; the 100%
on selectors is 100% of the classes this tree HAS, not of the 10.6 AppKit.** The probes holding the substrate and its clients:
`libagora-base/tests/kvo_automatic.m` (34 checks), `libagora-base/tests/kvo_tomany.m` (37),
`libagora-base/tests/user_defaults_kvo.m` (25), `libagora-app/tests/binding_base.m` (26),
`libagora-app/tests/controller_base.m` (77), `libagora-app/tests/array_controller.m` (77),
`libagora-app/tests/user_defaults_controller.m` (43), `libagora-app/tests/dictionary_controller.m` (40) and
`libagora-app/tests/tree_controller.m` (55). The workspace's 14 tests were run too.*

---

## 1. What these sessions did

Three planned slices and one fix, in the order they landed. **THE FIRST THREE ARE `libagora-base` COMMITS** — a
Foundation change is not an AppKit slice and gets its own commit and its own gitlink — and the fourth is this
repository's. **THE DESIGN QUESTIONS FROM `HANDOFF-6` §6 ITEM 5 WERE ANSWERED BEFORE ANY CODE**: a generic binding
layer on `NSObject` over KVO; live content through collection proxies and to-many notifications; Core Data and
`NSPredicate` doors refused by name; a real `-selection` proxy; and the base controller first. §6 below records the
answers against the code.

| Commit | What it landed |
|---|---|
| `3463c5f` (base) | **KVO's automatic half.** The first observation of a simple key moves the object to a dynamic subclass (`NSKVONotifying_<Class>`) whose setter brackets the original IMP with `-willChangeValueForKey:`/`-didChangeValueForKey:`, so `[model setName:x]` — a setter called directly, which is what application code writes — notifies. Object/Class, `char`/`BOOL`, `short`, `int`, `long`, `long long`, `float` and `double` setters are wrapped; `-class` still answers the declared class. KVC's `-setValue:forKey:` asks an internal seam (`fn_kvo_auto_notifies`) whether the setter will announce, so one write is reported ONCE. `tests/kvo_automatic.m` — 34 checks. |
| `22b23ad` (base) | **KVC's live collection proxies and KVO's to-many pair.** `-mutableArrayValueForKey:`/`-mutableSetValueForKey:` (and `…KeyPath:`) are live views; an already-mutable property is changed in place and announced with `-willChange:valuesAtIndexes:forKey:` / `-didChange:…` — kind, indexes, and the OLD/NEW objects — while an immutable or nil value takes a mutable copy written back through KVC (a setting change). Set mutations map union → insertion, minus/intersect → removal, set → replacement, with NSSet values. `tests/kvo_tomany.m` — 37 checks. |
| `ef22eb7` (base) | **A nil reaches an `id` setter.** `-setValue:nil forKey:` refused every nil before asking the setter's type, so an `id` property raised "cannot set nil for the scalar key". The type is asked first: object/Class/pointer/block setters receive nil; a scalar still goes to `-setNilValueForKey:`. Found by the binding layer's `NSNullPlaceholderBindingOption`; `tests/kvo_automatic.m` keeps the case. |
| `0b3bd44` (this repo) | **The generic binding layer.** `NSKeyValueBinding` grows from the 26-line marker stub to Apple's layer, minus what belongs to a control: the three marker singletons and `NSIsControllerMarker`; the three info keys; `-bind:toObject:withKeyPath:options:` (one observation per binding, Initial applied at bind time, the value written through KVC), `-unbind:`, `-infoForBinding:`, `+exposeBinding:`/`-exposedBindings`, `-valueClassForBinding:`, the class-keyed placeholder table, the NSEditor defaults; 78 binding names and 26 option keys. `tests/binding_base.m` — 26 checks. |

**AND `NSKeyValueBinding` IS APPKIT'S FILE, WHICH COST A FALSE START.** The first version was written in
`libagora-base`; the build's `<AppKit/NSKeyValueBinding.h>` resolved to the INSTALLED AppKit header, and the new
declarations were invisible to the very file that had just written them. The component boundary decided the home — an
AppKit class belongs to this repository, and the base library owns only Foundation's own headers.

---

## 2. The surface, measured

```
classes   147 of 168   (88%)    21 missing
selectors 4827 of 4827 (100%)    0 missing   147 of 147 classes at COMPLETE coverage
protocols  44 of  56   (78%)    12 missing
functions  86 of  86  (100%)     0 missing    10 refuse by name
methods   5406 declared on this tree's own classes, 8 with NO body on the chain (0.2%)
```

**THESE LINES HAVE MOVED SEVEN TIMES: WITH THE COMMITS THAT LANDED AFTER THIS FILE WAS FIRST WRITTEN, WITH EACH OF THE
CONTROLLER SLICES (§9–§13), AND WITH THE PREDICATE EDITOR (§14).** The tree reached the controller slice at 138 classes,
4645 selectors and 5214 declared methods, not the 137 / 4636 / 5200 the original paragraph above this block recorded;
§9–§14 recount the movements rather than folding them into one.

**NONE OF THE SUBSTRATE SLICES ADDED A MANIFEST CLASS OR SELECTOR, AND THAT IS THE POINT OF A FOUNDATION ROW.** The
class, selector and protocol counts are unchanged since `HANDOFF-6` §12; what moved is `methods-declared`, 5186 ->
**5200**, for the fourteen `NSObject`-category declarations the binding layer adds (bind/unbind/info, the exposed-binding
pair, the value class, the option descriptions, the two placeholder doors, the two editor-registration doors and the
three NSEditor doors). The census records that movement with its reason. **`NSObject` is not one of the manifest's AppKit
classes**, so no `sel:` line changed and no denominator moved.

**THE CONTROLLER SLICES THEN ADDED THREE CLASSES AND LEFT `NSObject`'S PHANTOMS ALONE.** `classes-present` 138 -> 140
-> 141, `selectors-present`/`offered` 4645 -> 4682 -> 4729, `methods-declared` 5214 -> 5252 -> 5303, and three new
per-class lines (`sel:NSController 6`, `sel:NSObjectController 31`, `sel:NSArrayController 47`); §9 and §10 say what
landed, and why `methods-declared` moved by one more than the selector denominator in each (a declaration the 10.6
manifest does not carry, and the internal seam header's four declarations).

**AND THE SEVEN CONTROLLER CLASSES ARE STILL THE HEADLINE GAP:** `NSController` (6 selectors), `NSObjectController`
(31), `NSArrayController` (47), `NSDictionaryController` (13), `NSUserDefaultsController` (12), `NSTreeController` (45),
`NSTreeNode` (10) — **164 selectors on the absent list**, with the predicate pair beside them and the plan's §A11
refusals. Their substrate is the part this file's arc delivered.

**THE PREDICATE PAIR STAYS ABSENT ON PURPOSE, AND `NSFileWrapper` MAKES THE ABSENT COUNT ONE HIGH BY CONSTRUCTION.**
`NSPredicateEditor`/`NSPredicateEditorRowTemplate` need `NSPredicate`/`NSExpression`/`NSComparisonPredicate` and this
stack's Foundation has none of that family (§63.161); `NSRuleEditor`'s three predicate doors refuse by name.
`NSFileWrapper` is Foundation's in this stack, counted because the 10.6 umbrella imports Foundation. The real AppKit gap
is 30.

*One state note for the next reader: the `libagora-base` tree carried an **uncommitted, unrelated** `NSFileManager`
/`search_paths` change at handover (its suite therefore shows 9 tests in that tree while the committed suites are 8).
It is not part of this arc and was deliberately left untouched.*

---

## 3. The instrument, on both sides of the component boundary

The AppKit instruments are unchanged in kind — the census, the refusal census and the owed census, all gated by
`ctest` — and the three substrate probes are new:

| Artifact | What it measures |
|---|---|
| `libagora-base/tests/kvo_automatic.m` (34) | The automatic setter: the class lie, every wrapped argument type, Prior/Initial, the one-announcement rule for a KVC write, the unwrapped struct + manual pair, both removal spellings, the unobserved instance, and the silent-but-usable state after the last observer leaves. |
| `libagora-base/tests/kvo_tomany.m` (37) | The array proxy's four mutations with their index sets and OLD/NEW objects, Prior, the immutable and nil-property arms, the set's union/removal with NSSet values, the dotted path's head-object notification, and an unobserved proxy that still mutates. |
| `libagora-app/tests/binding_base.m` (26) | Markers and `NSIsControllerMarker`; Initial and automatic delivery; `-infoForBinding:`; unbind/rebind; the NSNull placeholder; marker pass-through and the raise option; `+exposeBinding:`/`-exposedBindings`; placeholders; NSEditor defaults including the delegate callback; the nil-argument raises. |

**THE BASE HAS NO CENSUS, AND THAT IS A REAL DIFFERENCE RATHER THAN AN OVERSIGHT.** Its claims are held by `ctest` and
by the component `README.md`/`PROVENANCE.md`; this file records the numbers the AppKit census measures and the base's
three probes, and does not pretend there is a Foundation ledger. **THE BASE'S SUITE IS 8 COMMITTED TESTS** (the file
count in a tree with unrelated work can read higher).

---

## 4. Traps these sessions paid for

**A SETTER CALLED DIRECTLY IS A DIFFERENT DOOR FROM `-setValue:forKey:`, AND THE FIX CREATES A SECOND ANNOUNCER.**

* KVO v1 announced KVC's writes and nothing else; application code writes `[model setName:x]`. The dynamic subclass is
  the fix — and it makes KVC's own wrapper a DUPLICATE unless the two ask each other. `fn_kvo_auto_notifies` is that
  seam: when the class carries the automatic setter, KVC stays quiet; otherwise KVC wraps the write. The probe
  "a KVC write announces exactly once after observation" exists for this specific failure.

**THE `-class` LIE IS PART OF THE CONTRACT, NOT AN ACCIDENT.**

* `object_getClass` shows `NSKVONotifying_<Class>`; `-class` answers the declared class; `-isKindOfClass:` is true
  because the dynamic class IS a subclass. A swizzle that leaks into `-class`, or an implementation that forgets the
  override, is a visible bug the probe pins.

**THE WRAPPER IS ONE C FUNCTION PER ARGUMENT TYPE, AND THE UNWRAPPED TYPES ARE NAMED.**

* A variadic trampoline cannot carry an arbitrary setter's argument, so there is one function per type (`id`/`Class`,
  `char`/`BOOL`, `short`, `int`, `long`, `long long`, `float`, `double`) chosen from the argument encoding. A setter
  taking a STRUCT, a pointer, a C string or a selector is deliberately NOT wrapped; a key with NO setter has nothing to
  wrap. Both fall back to the manual pair, and KVC still announces its own `-setValue:forKey:` write once.

**A REMOVAL FREES THE OBJECTS IT TOOK OUT, SO THE PENDING RECORD MUST RETAIN THEM.**

* The to-many OLD side is captured before the mutation and OWNED by the pending record; the probe reads the removed
  object after the removal. Borrowing it from the collection would be a use-after-free that passes on a quiet heap.

**THE ABSENT SIDE OF A TO-MANY CHANGE IS NSNull, NOT AN ABSENT KEY.**

* An insertion has no old objects; a removal has no new ones. An observer that asked for the option gets NSNull, which
  is Apple's contract and the difference between "nothing was there" and "nobody asked". The first run failed exactly
  this for insertion.

**A COLLECTION PROXY HAS TWO ARMS AND THE STORE DECIDES WHICH — AND THE SET'S COPY ARM MUST WRITE A MUTABLE COPY.**

* A property already holding an `NSMutableArray`/`NSMutableSet` is mutated IN PLACE and announced with the to-many pair;
  an immutable or nil value is replaced by a mutable copy through KVC and announced as a SETTING change. A proxy that
  always copies passes a value test and loses every index. The set's copy arm writes an `NSMutableSet`, or every later
  mutation would be a setting change and the to-many path would never be reached. And the set's single storage
  primitive is `-fnReplaceMembers:`: the mutation kind is recovered by diffing the current members against the new list.

**A LAZILY-INITIALISED MARKER IS NIL TO THE FIRST CALLER.**

* The three binding markers were created in a lazy init; a fresh process asked `NSIsControllerMarker`/compared against
  them before any binding call and saw three nils. The file now initialises them in a constructor, because the markers
  are part of the vocabulary before anything is bound.

**THE INITIAL NOTIFICATION FIRES INSIDE `-bind:`, SO A RAISING OPTION CAN RAISE THERE.**

* The binding test's raise case had to write a plain value before binding with
  `NSRaisesForNotApplicableKeysBindingOption`; otherwise the exception comes from `-bind:` itself, not from the write
  under test. A caller setting a raising binding on a marker-valued source gets the raise at bind time — which is
  defensible, and is why the test says so.

**A BINDING MUST BE UNBOUND BEFORE ITS RECEIVER DIES, AND A REBIND MUST REMOVE THE OLD OBSERVATION.**

* The registry is process-global (there is no per-object ivar to grow), so a binding outliving its receiver leaks the
  record and keeps writing to a dead address. Apple's own caveat for bindings on ordinary objects. A rebind that did
  not unbind first would deliver every write twice; `-bind:` unbinds the name first.

**`-setValue:nil forKey:` REFUSED EVERY NIL BEFORE ASKING THE SETTER'S TYPE.**

* An `id` property with a perfectly good `-setFoo:` raised "cannot set nil for the scalar key" — the message naming a
  scalar the property was not. The type is now asked first. The binding layer's NSNull placeholder is the caller that
  measured it, and the rule is the obvious one: object/Class/pointer/block setters take nil; scalars go to
  `-setNilValueForKey:`.

**AND THE COMPONENT BOUNDARY IS A TRAP OF ITS OWN: `NSKeyValueBinding` IS APPKIT'S.**

* The first version was written in `libagora-base`; `<AppKit/NSKeyValueBinding.h>` resolved to the INSTALLED AppKit
  header, so the file could not see its own declarations. The component-boundary rule in the skill's §1 — the
  repository boundary decides where a change is committed — is also the rule for which header a compiler sees.

---

## 5. How to add a slice without breaking the instruments

Unchanged in shape from `HANDOFF-6` §5 and followed every time. Restated because the next slice is the first controller:

1. **Measure first.** `./tools/api-ledger missing …` names the absent classes and protocols. The seven controllers are
   the list; pick by reachable surface and by what the substrate now makes possible.
2. **Write the header declaration where Apple declares it** — `NSController`'s and `NSObjectController`'s categories
   are part of the class's own surface, and `NSObjectController` inherits `NSController`'s doors.
3. **Implement, reusing what exists.** A controller is a **KVO client**: it observes `content` (a binding destination
   like any other), exposes KVC-compliant state (`content`, `contentObject`, `selection`, `selectedObjects`, `canAdd`,
   `canRemove`, `editable`) and lets the binding layer write through. The Core Data doors and `filterPredicate` are
   **named refusals**, not stubs.
4. **Test the claim, not the code**: a controller's selection and arrangement are VALUE tests; a binding is a DELIVERY
   test (what the receiver holds after a write); a refusal is an exit-status/empty-value test.
5. **Let the gate fail** (`ctest -R appkit-api-census`), re-pin in the same commit, recompute the four summary lines
   from `./tools/api-ledger census`. A new class changes `classes-present`, `selectors-offered`, `selectors-present`
   and the complete-coverage denominator; say so in the commit and in the section.
6. **Run the whole suite** (`ctest --test-dir build -j4`, ~90 s) and the WORKSPACE suite (14 tests).
7. **If you add a protocol door, make the sending class say which messages it sends.** A protocol without a sender is
   prose.
8. **If a door has no reader, say so at the door — or refuse it by name.** The three dispositions are still the three:
   a reader, a named refusal, or store-answer-and-say-nothing-reads-it.
9. **A deep class lands in a CATEGORY FILE of its own** once its main file is over a couple of thousand lines.
10. **Commit in the component first, then advance the gitlink in `$AGORA_ROOT`.** **AND IF THE WORK TOUCHES
    `libagora-base`, THAT IS A SEPARATE COMMIT AND A SEPARATE GITLINK ADVANCE, with its own README/PROVENANCE
    update** — a Foundation row is not an AppKit slice, even when an AppKit slice is what needed it.

**AND THE HOUSEKEEPING NOTES STILL HOLD.** The tree is **LGPL-3.0-or-later** (library sources and headers) and
**GPL-3.0-or-later** (tests and the application), with `SPDX-FileCopyrightText`/`SPDX-License-Identifier` lines — a new
file must carry that block. `CMakeLists.txt` **globs** `*.m` and `*.h`, so a new source needs no build-file edit — but a
new TEST needs its `add_executable` / `add_test` / `ENVIRONMENT` triple, and a test that forgets the environment line
fails for want of a library path rather than for want of the code.

---

## 6. Where to spend the next hour

**EVERY CONTROLLER AND THE PREDICATE PAIR HAVE LANDED (§9–§14), SO THE NEXT HOUR IS THE SMALL FIX THE FIRST SLICE
OWED — AND THEN THE REMAINING ABSENT CLASSES, WHICH ARE ALL THE PLAN'S §A11 REFUSALS.** `NSObjectController` is content and selection; `NSArrayController` the arrangement
and its policy; `NSUserDefaultsController` the settings store and its proxy; `NSDictionaryController` the key/value
projection; `NSTreeController` + `NSTreeNode` the tree and its paths. What is left:

1. **THE `==` SELECTOR FIX `HANDOFF-7` §9 RECORDED, WHICH IS THE LAST KNOWN LATENT BUG IN THIS TREE'S OWN CODE**:
   `NSDocument` and `NSDocumentController` still compare `[item action]` with `==`, which the cross-image selector
   identity makes wrong the day an application-built toolbar item is validated against a document. Two files,
   `sel_isEqual`, one probe with an item built outside the library.
2. **THE 21 ABSENT CLASSES ARE ALL THE PLAN'S §A11 REFUSALS** — OpenGL (the context, pixel format, view, layer and
   buffer), QuickDraw, the movies, the three typesetters, speech (recogniser and synthesiser), sound, the
   input-manager era (`NSInputManager`, `NSInputServer`), the Dock tile, the Help Viewer, `NSTouch`, and
   `NSFileWrapper` (Foundation's here). They are absent because the subsystems they wrap are, and the header of each
   one is where that reason belongs when it is written.

---

## 7. Things a reader should not have to rediscover

* **KVO'S AUTOMATIC HALF IS SIMPLE KEYS AND TYPED SETTERS.** Object/Class, `char`/`BOOL`, `short`, `int`, `long`,
  `long long`, `float`, `double` setters notify a direct call; struct/pointer/C-string/selector setters and keys with no
  setter need the manual pair; dotted key paths are not decomposed for automatic notification; dependent keys are not
  computed. `-class` lies by design, `object_getClass` shows `NSKVONotifying_<Class>`, and the subclass is never
  restored — a setter with no observers left announces to an empty registry and returns.
* **ONE WRITE IS ONE NOTIFICATION, WHICHEVER DOOR.** KVC's writer asks `fn_kvo_auto_notifies` (an internal seam) whether
  the setter will speak; if it will, KVC stays quiet. A double announcement is the failure mode this exists to prevent.
* **THE TO-MANY CHANGE DICTIONARY HAS A SHAPE.** Array forms: `NSKeyValueChangeKindKey` (Insertion/Removal/Replacement),
  `NSKeyValueChangeIndexesKey`, and `New`/`Old` as ARRAYS of the affected objects; the absent side is NSNull. Set forms:
  the kind, and `New`/`Old` as NSSets, with no indexes. `Old` is captured before the mutation and retained; `New` is
  read after it.
* **THE PROXIES ARE LIVE AND ONE-WAY, AND THEIR TARGET IS NOT RETAINED.** A mutable backing is changed in place
  (to-many change); an immutable or nil one is replaced by a mutable copy (setting change). `-mutableArrayValueForKey:`
  is built on the array's seven storage primitives, `-mutableSetValueForKey:` on the set's one
  (`-fnReplaceMembers:`). The ordered-set proxy is the remaining row and is named in both headers.
* **THE BINDING LAYER IS ONE-WAY AND EXPLICIT.** `-bind:` observes with `New | Initial`; the receiver is written through
  KVC under the binding name; rebind replaces; `-unbind:` of an unbound name is a no-op; `-infoForBinding:` answers the
  observed object, key path and options; placeholders are class-keyed and inherited; the NSEditor defaults are YES /
  no-op / the delegate callback. **Remove a binding before its receiver dies** — the registry is process-global.
* **TWO OPTIONS HAVE READERS HERE**: `NSNullPlaceholderBindingOption` (the value written for NSNull) and
  `NSRaisesForNotApplicableKeysBindingOption` (a marker raises rather than being written). The rest are stored and
  answered and wait for the controls/controllers that act on them; the header says which.
* **`NSKeyValueBinding` IS APPKIT'S FILE**, and its three markers are initialised by a constructor so the first caller
  sees them. The constants' values are their own names.
* **THE NUMBERS AND THE GATES.** 147 of 168 classes (88%), 4827 of 4827 selectors, 44 of 56 protocols, 86 of 86
  functions, 5406 methods declared (8 without a body), 391 metrics, refusal 404, owed 21, 181 tests in this repository
  (~97 s), **12 committed base suites** (the Foundation's own count, corrected here — this bullet said 8 for three
  slices), 14 workspace tests, the workspace suite passing against the installed library. `ctest --test-dir build -j4`
  is the gate; the exit status is the witness.
* **THE ABSENT SURFACE.** 21 classes, 12 protocols: **all of them the plan's §A11 refusals** — OpenGL (the context, pixel
  format, view, layer and buffer), QuickDraw, the movies, the three typesetters, speech, sound, the input-manager era,
  the Dock tile, the Help Viewer, `NSTouch`, and `NSFileWrapper` (Foundation's here). Nothing on the list is a
  controller, an editor or a view this tier promised and did not build.

---

## 8. How this file is kept

**THE RUNNING RECORD GOES HERE, AS NUMBERED SECTIONS AFTER THIS ONE.** The earlier handoffs did the same:
`HANDOFF-2.md` §13–§20, `HANDOFF-3.md` §8–§14, `HANDOFF-4.md` §9–§20, `HANDOFF-5.md` §9–§16 and `HANDOFF-6.md` §9–§12
are the sessions that picked those files up, one numbered section per slice, each recording what landed, the numbers
before and after, the traps the slice paid for, and where the next hour went. A session that lands a slice should:

1. Append a `## 9. …` (then `## 10. …`) section here with its commit, its census movement and its traps.
2. Re-pin `tests/api-10.6-census.txt` and/or `tests/refusal_census.txt` in the same commit, recomputing the summary
   lines from `./tools/api-ledger census` — and run the PER-CLASS recount. **If the slice ADDED a class, re-pin the
   offered and complete denominators too, and say in the section that the class count moved.**
3. Update the component `README.md` with a section for the slice and `PROVENANCE.md` with what a reader needs to know —
   both are read by people who will never open this file. **A `libagora-base` change updates THAT component's README and
   PROVENANCE and gets its own commit; this file records only the AppKit side and the boundary.**
4. Leave §1–§7 above ALONE unless a slice changes a number in them; when it does, change that number and say in the new
   section that it moved. A handoff that quietly drifts is the thing these files exist to prevent.

---

## 9. The first controllers: `NSController` and `NSObjectController`

**THE SLICE THE LAST THREE COMMITS WERE BUILDING, IN COMMIT `7a727e9`; THIS SECTION IS THE COMMIT AFTER IT.**
`NSController` (6 selectors) and `NSObjectController` (31, plus a `-contentObject` declaration the 10.6 manifest does
not carry) are in `NSController.{h,m}` and `NSObjectController.{h,m}`; the selection proxy is a private class in the
implementation file, the eleven Core Data and predicate doors refuse through a new `fn_refuse_controller` in
`AppKitRefusal.h`, and `tests/controller_base.m` — with its `add_executable`/`add_test`/`ENVIRONMENT` triple in
`tests/CMakeLists.txt` — measures the whole thing in **77 checks**. All 176 tests pass in about 95 s.

**THE NUMBERS MOVED, AND BY EXACTLY THE ARITHMETIC THE SLICE PREDICTS.** `classes-present` 138 -> **140** of 168
(`classes-missing` 30 -> 28), `selectors-present`/`selectors-offered` 4645 -> **4682**, `methods-declared` 5214 ->
**5252**, and `sel:NSController 6` / `sel:NSObjectController 31` are two new pinned lines. Metrics 382 -> **384**.
Refusal census 392 -> **403** (the eleven sites). Tests 175 -> **176**. **`methods-declared` moved by 38 while the
selector denominator moved by 37, and the one is not a counting error: the 10.6 manifest carries no `-contentObject`
row** (the binding name `NSContentObjectBinding` and the plan both name the door, and Apple's class answers it), so the
declaration is real surface that the ledger's Apple side does not measure. `-contentObject` is kept, and this paragraph
is why the two numbers differ.

**TRAP: A SELECTOR FROM ANOTHER IMAGE IS NOT `==` ITS LITERAL, AND THIS RUNTIME MAKES THAT VISIBLE.** The first run of
`-validateUserInterfaceItem:` enabled `remove:` with nothing to remove. `libagora-objc`'s selector table hands each
compilation unit its own `objc_selector` struct for the same name — the INDEX inside it is shared, so dispatch is
correct, but the `SEL` pointer is not — which means the item an APPLICATION built carries a different address from this
library's `@selector(remove:)`. **MEASURED**: the test binary's `[item action]` and the library's literal printed
different addresses with the same name and a null type encoding, and `==` answered NO for every action. The door uses
`sel_isEqual`, the runtime's documented name-fallback comparison. **`NSDocument` and `NSDocumentController` still use
`==`** and are the same hazard the day a toolbar or menu item built outside this library is validated against them;
they are left alone in this slice and named here so the next reader does not have to rediscover it.

**TRAP: ONE DEPENDENT-KEY PAIR TOO MANY IS A DOUBLE DELIVERY.** `-setContent:` announces `contentObject`, `selection`,
`selectedObjects`, `canAdd` and `canRemove` by hand (this Foundation does not compute
`+keyPathsForValuesAffectingValueForKey:`), and it deliberately does NOT announce `content`: KVO's automatic setter
wrapper already brackets `-setContent:` once anyone observes `content`, so a manual pair inside the method would deliver
the same write twice — the Foundation side's `fn_kvo_auto_notifies` trap, met from the AppKit side. The probe checks
ONE notification with the right old and new values.

**TRAP: A COMMIT THAT WALKS THE LIVE LIST MESSAGES AN EDITOR ANOTHER EDITOR JUST FINISHED WITH.** `-commitEditing`
walks a COPY, and skips an editor that is no longer registered when its turn comes; the probe's editor A withdraws
editor B during A's commit and B's commit count stays zero. The same non-retaining rule has a sharper edge the header
states: an editor that dies without `-objectDidEndEditing:` leaves an address the next commit messages, which is the
caller's contract, exactly as it is for a KVO observation.

**TRAP: THE FIRST OBJECT INTO A nil CONTENT IS A SETTING CHANGE, NOT AN INSERTION.** There is no collection to insert
into, so `-addObject:` on nil content makes a one-object array and writes it through `-setContent:`; only an EXISTING
mutable array or set takes the to-many pair (with the index, or as a union/minus set mutation). A probe that expected
an insertion on the nil-content path would be testing an arrangement the API does not have.

**AND `NSNotApplicableMarker` IS DECLARED AND STILL UNUSED HERE, WHICH IS A STATEMENT RATHER THAN AN OVERSIGHT.** A key
none of the selected objects answers makes this Foundation's KVC raise `NSInvalidArgumentException` (there is no
`NSUnknownKeyException` to catch), so the proxy lets the exception propagate instead of answering the marker: the only
ways to tell "no such key" from "the getter raised" would be to match on the diagnostic string or to duplicate KVC's
private search order, and a duplicated rule drifts. The header says which marker the proxy does answer
(`NSMultipleValuesMarker`, `NSNoSelectionMarker`) and why the third is absent.

**WHERE THE NEXT HOUR GOES: `NSArrayController` (47), and §6 above has been rewritten to say what its four open
questions are.** §2's measured block and §7's numbers/absent-surface bullets were updated in the same commit, and they
record that the tree had already moved past this file's original numbers before this slice began (138 classes, 4645
selectors, 5214 declared methods at the slice's start, not 137/4636/5200).

---

## 10. `NSArrayController`: the arrangement, the index translation, and the cache that fills itself in

**Commit `7d4c4d3`, with this section in the commit after it. THE SLICE THAT MAKES THE CONTROLLER USEFUL TO
A TABLE.** `NSArrayController` is present and COMPLETE at 47 of 47 — the class count 140 -> **141** of 168, the offered
and present selectors 4682 -> **4729**, the declaration count 5252 -> **5303** (+47 for the class, +4 for the internal
seam header), complete coverage 141 of 141, the metrics 384 -> **385**, the owed census 19 -> **21** (the
live-rearrangement pair, stated at the door), and the tests 176 -> **177** with `tests/array_controller.m` at **76
checks**. **THE REFUSAL CENSUS DID NOT MOVE (403), AND THAT IS THE SLICE'S HEADLINE: `filterPredicate` IS REAL.**

**`filterPredicate` FILTERS BECAUSE THE PREDICATE FAMILY CAME BACK, AND §6 OF THIS FILE SAID IT COULD NOT.** The plan
in §6 was written when `NSPredicate`/`NSExpression`/`NSComparisonPredicate` were absent (§63.161); `libagora-base`
restored them in `d4e75ec` and extended the grammar in `917c144`, and `-filteredArrayUsingPredicate:` has been sitting
in `NSPredicate.h` (NOT in `NSArray.h` — that distinction produced a wrong claim in this very session before the slice
started). So the arrangement is `-filteredArrayUsingPredicate:` then `-sortedArrayUsingDescriptors:`, and §6 item 4
has been rewritten to point at the predicate editor pair and the rule editor's three refusals, which are now unblocked.

**TRAP: THE WILL PHASE REPOPULATES THE CACHE THE DID PHASE MEANT TO DROP.** `fn_beginChange` drops the arrangement and
then announces; the will-side Old reads call `-arrangedObjects`, so the cache is full of the OLD arrangement again by
the time the mutation lands. The first version of `fn_settle` rebuilt only when the cache was nil and therefore
announced the OLD arrangement as the new value — measured by a re-sort whose KVO New value was the pre-sort array.
`fn_settle` now drops the cache a second time before rebuilding, and the probe's KVO section pins it.

**TRAP: AN ARRANGED INDEX IS NOT AN IDENTITY LOOKUP.** The first translation used `-indexOfObjectIdenticalTo:`, which
finds the FIRST occurrence — so a content holding the same object twice sent both arranged positions to one content
position, and the second insertion landed in the wrong place (or, in the plural door, collided in the dictionary keyed
by content index). The translation is POSITIONAL now: count the identical objects before the arranged position and take
that occurrence in the content.

**TRAP: TWO INSERTIONS AT TWO ANCHORS MUST RUN FROM THE HIGHEST CONTENT INDEX DOWN.** Inserting the lower one first
moves the higher one's anchor, so the objects land before each other instead of before their own anchors. The plural
door translates every anchor against the arrangement as it stands, then inserts in descending content order; the probe
checks the resulting CONTENT order, which is where the mistake is visible.

**TRAP: A WRONG-CLASS CONTENT RAISES FROM `-setContent:`, NOT FROM THE FIRST DRAW.** A single object as an array
controller's content is a caller using the wrong class, so `-arrangedObjects` raises `NSInvalidArgumentException` naming
the rule — and because a content change announces the arrangement, the raise arrives at the setter. The probe expects it
there, and the header says so, because "it will raise later" is the kind of surprise a table view turns into an abort.

**AND `automaticallyRearrangesObjects`/`automaticRearrangementKeyPaths` ARE STORED AND ANSWERED WITH NO READER.** The
observation half — watching every arranged object for the key paths a subclass names — is owed: the header carries the
OWED note, the flag is kept, and `-rearrangeObjects`/`-didChangeArrangementCriteria` are the doors a caller uses. The
owed census rose by two for that statement, which is the census doing what it exists to do.

**WHERE THE NEXT HOUR GOES:** §6 has been rewritten for it. `NSUserDefaultsController` (12) first — a defaults wrapper
with no arrangement at all — then `NSDictionaryController` (13), then `NSTreeController` + `NSTreeNode` (55), and the
predicate editor pair (18) with the rule editor's three refusals as the slice that makes a census fall.

---

## 11. The defaults controller: a proxy with no storage, and a read with three fallbacks

**Commit `06a92d1`, with this section in the commit after it.** `NSUserDefaultsController` is present and
COMPLETE at 12 of 12 — the class count 141 -> **142** of 168, the offered and present selectors 4729 -> **4741**, the
declaration count 5303 -> **5315**, complete coverage 142 of 142, the metrics 385 -> **386**, and the tests 177 -> **178**
with `tests/user_defaults_controller.m` at **43 checks**. The refusal census and the owed census did not move.

**THIS SLICE WAS BLOCKED ON A FOUNDATION ROW, AND THE ROW WAS LANDED FIRST.** `NSUserDefaults` had no KVO at all: its
write door is `-setObject:forKey:`, so KVO's automatic setter wrapping — which brackets `-setFoo:` — had nothing to
wrap. `libagora-base` `cb9e146` made the per-key doors send the manual pair themselves (outside the non-recursive lock,
in a `@finally`), added `-valueForKey:`/`-setValue:forKey:` because KVO fills the change dictionary through the read
door, and made `-registerDefaults:` announce only when a key's EFFECTIVE value moves. **`-valueForKey:` was not optional
and is the part a reader would skip**: without it an observation of an arbitrary key raises from `-valueForUndefinedKey:`
while the dictionary is being built.

**THE CONTROLLER'S THREE LEVELS ARE THE DESIGN.** A read is the pending store, then the store, then `initialValues`, and
`NSNull` in the pending dictionary means "remove this key" — so a held removal does not fall through to the store's OLD
value but past it to the fallback. `-valueForKey:`/`-setValue:forKey:` answer the `values.<key>` spelling directly,
because the binding layer hands over ONE string; `-valueForKeyPath:` reaches the same chain through the proxy, because
KVC splits a path and recurses.

**TRAP: A RELAY ON THE CONTROLLER CANNOT PRODUCE A CORRECT OLD VALUE, SO THE OBSERVATION GOES TO THE STORE.** The
tempting shape — keep the registration on the controller and forward from a private observer — runs AFTER the store has
changed, so its `will` half reads the new value and the change dictionary's Old is a lie. Registering on the store gives
correct Old and New at the price the header states: the change's object is the store and its path is the bare key. A
binding reads New; anything that cares about the object is told.

**TRAP: A PENDING WRITE MUST NOT BE ANNOUNCED AS A STORE CHANGE.** With `appliesImmediately` NO the store has not
changed, so a `values.` observer is correctly silent and the only key that moves is `-hasUnappliedChanges` — announced
when it CROSSES, not on every held write. `-save:` is what produces the store's notifications, one key at a time.
Turning the flag back ON flushes what was held, because the pending store is only ever written while the flag is NO and
would otherwise be stranded forever.

**TRAP THE PROBE FOUND: `-revertToInitialValues:` MOVES A KEY FROM THE FALLBACK INTO THE STORE.** The first version of
the test asked a key from `initialValues`, called `-revertToInitialValues:`, replaced the dictionary and expected the key
to be gone. It was not — the revert had WRITTEN it into the store, where it outlives the dictionary. That is the correct
behaviour (a Reset button is a store write), and the probe now measures the two facts separately: a key the store has
never had disappears with the dictionary, and a key the revert wrote stays with the store's value winning over the
fallback by the read order.

**WHERE THE NEXT HOUR GOES:** §6 has been rewritten for it. `NSDictionaryController` (13) first — an `NSArrayController`
subclass whose arranged objects are key/value pairs, so the one decision is what a pair is — then `NSTreeController` +
`NSTreeNode` (55), then the predicate editor pair (18) with `NSRuleEditor`'s two refusal sites as the slice that makes a
census fall.

---

## 12. The dictionary controller: a projection, one live pair per key, and the array controller's bug it found

**Commit `61fd249`, with this section in the commit after it.** `NSDictionaryController` is present and
COMPLETE at 13 of 13 — the class count 142 -> **143** of 168, the offered and present selectors 4741 -> **4754**, the
declaration count 5315 -> **5333** (+13 for the class, +5 for the new `NSArrayController_internal.h` seam), complete
coverage 143 of 143, the metrics 386 -> **387**, and the tests 178 -> **179** with
`tests/dictionary_controller.m` at **40 checks**. The refusal and owed censuses did not move.

**THE PROJECTION IS THE WHOLE CLASS, AND THE SEAM IS TWO METHODS.** `NSArrayController` supplies the arrangement, the
selection, the arrow keys and the policy; the dictionary controller answers `-fn_contentObjects` with one pair per
visible key, and `NSArrayController_internal.h` declares that door and the criteria announcement pair. Nothing else in
the base class needed to change — which is the point of having built the arrangement as a cache-and-settle machine
rather than as array-specific code.

**ONE PAIR PER KEY, KEPT, AND THE REASON IS THE SETTLE STEP, NOT SPEED.** The base class re-finds the selection by
IDENTITY (two equal model objects are two rows), so a controller that minted a fresh pair per rebuild would pass every
VALUE test in a probe and lose the selection on every content change, and `-setSelectedObjects:` could never find the
row a caller holds. The probe asserts the identity across a replacement content for exactly that reason.

**TRAP: THE ARRAY CONTROLLER'S WRONG-KIND CONTENT POISONED THE CONTROLLER, AND THIS PROBE FOUND IT.** `-setContent:`
used to announce the arrangement and THEN store the content, so a single object (or, for the dictionary controller, an
array) raised out of the did phase AFTER it had been assigned. The controller was left holding a content it could never
arrange again, and the NEXT `-setContent:` raised from its will phase while re-reading the poisoned content — the
dictionary probe aborted there, at a line that had nothing to do with the mistake. Both controllers now ask a VIRTUAL
question (`-fn_acceptsContent:`, with `-fn_contentRule` wording the refusal) BEFORE storing, so a refused content leaves
the previous one in place and the controller usable. **The array controller's probe gained the recovery case with the
fix** (76 -> 77 checks), and that is the general lesson: a test that only asserts the raise cannot see a state the raise
left behind.

**A PAIR IS LIVE, AND ADDING ONE HAS AN ORDER THAT MATTERS.** Attached, a pair reads and writes the content dictionary
through the controller; `-setValue:` changes the entry and announces, `-setKey:` renames it (a remove and an insert,
announced once, value read before the removal). Adding a detached pair puts it in the CACHE first and attaches it
second, so the arrangement the assignment rebuilds already holds that object and `selectsInsertedObjects` selects it by
identity; the value is read while the pair is still detached, because an attached pair reads the content — which does
not have the key yet.

**AND TWO THINGS A DICTIONARY CANNOT DO ARE SAID AT THE DOOR.** The arranged-index insertion doors accept the index and
ignore it, because a dictionary has no order; `localizedKeyTable` is stored and nothing loads it, because this
Foundation withdrew its `.strings` reader — the same withdrawal `NSRuleEditor`'s `-setFormattingStringsFilename:`
refuses by name — so `localizedKeyDictionary` is the only source of a displayed name.

**WHERE THE NEXT HOUR GOES:** §6 has been rewritten for it. One controller family remains — `NSTreeController` (45) +
`NSTreeNode` (10) — and it is the arrangement over `NSIndexPath`s, which is `NSOutlineView`'s data source in controller
form; then the predicate editor pair (18) with `NSRuleEditor`'s two refusal sites, the slice that makes the refusal
census fall.

---

## 13. The tree: an invisible root, a child array that keeps its links, and a build that must not throw

**Commit `fd4881b`, with this section in the commit after it.** `NSTreeController` and `NSTreeNode` are present
and COMPLETE at 45 of 45 and 10 of 10 — the class count 143 -> **145** of 168, the offered and present selectors
4754 -> **4809**, the declaration count 5333 -> **5386**, complete coverage 145 of 145, the metrics 387 -> **389**, the
refusal census 403 -> **405** (two deliberate model refusals), and the tests 179 -> **180** with
`tests/tree_controller.m` at **55 checks**. The owed census did not move.

**THE ROOTS HANG FROM A NODE NOBODY SEES.** `NSTreeNode -indexPath` walks to the node whose parent is nil, so with the
roots as the top of the graph every root's path would be the EMPTY path and no door could tell two roots apart. The
controller keeps one private root node whose children are `-arrangedObjects`; a root's path is `{i}`. That is the whole
of why `-insertObject:atArrangedObjectIndexPath:{2}` appends a root.

**`-mutableChildNodes` IS AN `NSMutableArray` SUBCLASS, BECAUSE THE PARENT LINKS ARE THE ARRAY'S JOB.** `-indexPath` walks
upward, so a child added to a node must learn who its parent is; the proxy overrides insert/add/replace, the three
removals, `-setArray:` and `-insertObjects:atIndexes:` and maintains the link, and `-setArray:` goes through the other
doors so "a child in this array has this node as its parent" is true at every moment. The node does not own its parent
(a cycle that never frees) and does not reach into another object's storage: the proxy asks through a private
`-fn_setParent:`/`-fn_clearParentIf:` pair.

**TRAP: AN EARLY RETURN OF AN UNINITIALISED NODE TURNED A CYCLE INTO A SEGFAULT.** The build's depth cap read
`if (depth > MAX) { print; return node; }` — and `node` was assigned FURTHER DOWN. The parent therefore added a garbage
pointer as a child, and the next walk followed it into nothing: 131,000 stack frames in gdb, `findNodeForObject:` all the
way down. The fix is the one line moved (assign, then check), and the shape is worth remembering because review cannot
see it: **every early return must come after the local it returns is assigned.**

**AND THE BUILD MUST NOT THROW, BECAUSE OF WHERE IT RUNS.** It happens in the DID half of an announcement; an exception
there leaves the will half's pending change records open for the life of the object — the KVO analogue of a leaked
lock. So a children key whose value is not an array, and the 512-level depth cap, print `APPKIT-REFUSE` and build the
node without the children they cannot represent. The refusal census rose by two, deliberately, and the probe asserts a
cyclic model is truncated rather than thrown.

**ONE KEY IN THE SELECTION PAIR BELONGS TO KVO.** An observer of `selectionIndexPaths` makes KVO wrap
`-setSelectionIndexPaths:`, so the wrapper announces that key; the manual pair announces only the five DEPENDENTS.
Announcing all six delivered every selection change twice — the probe measured `calls == 2` — which is the same "one
write, one notification" rule the controllers' `content` follows. The settle step announces `selectionIndexPaths` in the
criteria/derived list instead, because it changes the selection without going through that setter.

**TWO MORE THINGS SAID AT THE DOOR.** `countKeyPath` is stored and answered and builds nothing: this Foundation's KVC has
no `countOf<Key>`/`objectIn<Key>AtIndex:` synthesis, so children come from an array-valued `childrenKeyPath`. And a
destination path is read AFTER the removal, which is why a same-parent move lands in the gap the removal left — the
reading that makes `-moveNode:toIndexPath:` and `-moveNodes:toIndexPath:` mean the same thing.

**WHERE THE NEXT HOUR GOES:** §6 has been rewritten for it. One slice remains on the controller front —
`NSPredicateEditor` + `NSPredicateEditorRowTemplate` (18 selectors) with `NSRuleEditor`'s two predicate refusal sites, the
slice that makes the refusal census fall — and then the small `==`-selector fix in `NSDocument`/`NSDocumentController`
that §9 recorded.

---

## 14. The predicate editor: the rule editor assembles, and the refusal census falls

**Commit `8fc6cfd`, with this section in the commit after it.** `NSPredicateEditor` (2) and
`NSPredicateEditorRowTemplate` (16) are present and COMPLETE — `NSRuleEditor`'s two predicate refusal sites now ASSEMBLE —
and **the refusal census FELL, 405 -> 404, for the first time in this arc**. The class count 145 -> **147** of 168, the
offered and present selectors 4809 -> **4827**, the declaration count 5386 -> **5406**, complete coverage 147 of 147,
the metrics 389 -> **391**, and the tests 180 -> **181** with `tests/predicate_editor.m` at **41 checks**.

**THE SLICE §6 PREDICTED, AND THE PREDICTION WAS MOSTLY RIGHT.** `NSRuleEditor`'s `-predicate`/`-predicateForRow:` always
asked the delegate for a parts dictionary per criterion and then refused because this Foundation had no predicate family;
`libagora-base` restored it, and the doors build `NSComparisonPredicate`s from the parts now — a row's criteria combine
with the compound type a part names, or AND when none does, and the editor's predicate is the AND of its rows. A part
that cannot make a comparison contributes NOTHING rather than a half-filled predicate.

**FOUNDATION DECIDED ONE OF THE PARTS, AND THE CENSUS RECORDS IT.** `NSComparisonPredicate` refuses the custom-selector
operator by name (there is no `-performSelector:withObject:` here), so a custom-selector criterion is refused by the rule
editor — printed, and contributing no predicate — instead of the exception coming out of a getter. That is one new site
where the two old ones were, which is why the census fell by one rather than two.

**THE EDITOR IS ITS OWN DELEGATE, AND THE CRITERION IS THE ROW'S MEMORY.** The rule editor does not retain its delegate
(this tree's rule for every delegate), so the self-reference is not a cycle; the parts door answers from a private
criterion dictionary (key path, operator, modifier, options) with the display value as the right-hand side. That is what
lets an operator other than "is" survive the round trip — a parallel array of templates-per-row would desynchronise the
moment a user removed a row, which is exactly the kind of second source of truth §12's pair cache avoids by being the
only one.

**TRAP: TWO ORDINARY INITIALISERS DID NOT WORK, AND THE PROBE FOUND BOTH.** `[[NSRuleEditor alloc] init]` left its row
list nil, so an insertion was a message to nil — the row vanished and the selection then raised a range error about a row
that was never there, several lines away from the cause. `[[NSPopUpButton alloc] initWithFrame:]` left a plain button
cell, so `-addItemsWithTitles:` reached a cell that has never heard of a menu. Both now chain to their designated
initialisers, the rule `[[NSSlider alloc] initWithFrame:]` already followed: **a class a caller builds with `-init` must
not be a silently broken one**, and a template that builds its own views is a caller.

**WHERE THE NEXT HOUR GOES:** §6 has been rewritten. The only known latent bug left in this tree's own code is the
`==`-selector comparison in `NSDocument`/`NSDocumentController` that §9 recorded, and after that the 21 absent classes
are all the plan's §A11 refusals — subsystems this tier never promised, not surface it forgot.

---

## 15. The `==`-selector fix §9 owed: a validating item from another image

**Commit `15c19e0`, and it is the fix §9 recorded rather than a slice.** `NSDocument` and `NSDocumentController`
compared `[item action]` with `==`; this runtime gives each image its own selector struct for the same name, so an
application's toolbar item was never `==` the library's literal and Save, Revert and the controller's four were disabled
for every caller outside this library. Both doors use `sel_isEqual` now, which falls back to the name.

**THE PROBE RUNS AGAINST THE OLD CODE TO PROVE IT MEASURES THE FIX.** `tests/validation_selectors.m` builds its item in
the test binary — another image, which is the whole point — and with `==` restored exactly two checks fail: the titled
document's Save and its Revert. Nothing else in the suite moved, so the probe is not passing for a reason of its own.
Eleven checks: the untitled document's no, the titled one's two yeses, an action the class does not own, the controller's
four, and the runtime fact the fix rests on.

**WHERE THE NEXT HOUR GOES:** §6 has been rewritten. There is no known latent bug left in this tree's own code; the 21
absent classes are all the plan's §A11 refusals, and the next slice is whichever subsystem one of them would bring.

---

## 16. Desktop integration: `NSDockTile`, and a badge that is pushed through `agora-shell` 8

**Three commits, three components: `window-server` `6a0cc4c`, this repository `e3398ec`, `dock` `34ef3b3`.** Desktop
integration begins with the one absent class whose cost is mostly in the OTHER components: `NSDockTile` (9 of 9) is
thin, and the work is a protocol version, a seam function and a chip in the Dock's drawing.

**THE BADGE IS PUSHED, NOT ASKED FOR.** A Dock that asked each tile each refresh would spend a round trip to learn
"nothing" from every application without a badge — the ordinary case. So `agora-shell` 8 adds
`agora_window.set_badge`: the application sends the label, the server keeps it on every window of the CONNECTION (the
connection is the application, and a per-window store is the only application state this server has), and the Dock reads
it out of the window list it already takes.

**TRAP: THE BADGE IS ITS OWN EVENT, AND THAT IS COMPATIBILITY RATHER THAN STYLE.** Appending an argument to the existing
`window` event would hand a client bound at version 1 an opcode whose wire it parses with the old field list — the one
change a versioned protocol cannot absorb. `agora_window_list.badge` is `since 2`, sent beside its window and only to a
list resource at version 2 or above, so an older Dock is never handed it. The global moved to 8 and `agora_window` to 8
for the request; the list moved to 2 for the event.

**TRAP: THE SEAM'S VERSION IS `wl_proxy_get_version`, NOT `wl_resource_get_version`.** The client side has proxies, not
resources; the resource call is a server-side function and does not link here. The first version of `AGWindowSetDockBadge`
used it and the compiler said so, which is the cheaper of the two ways to learn it.

**AND TWO ORDINARY DOORS IN THE SEAM DID WHAT THEY SAID.** `AGWindowSetDockBadge` takes ANY of the application's window
ids and resolves the application through the snapshot's `app_id` — the ids are the only names the two sides share, which
is the same choice `NSDockMenu` makes — and `AGWindowListRows` hands the cached snapshot to the one caller that must read
it without waiting.

**TWO BOUNDARIES ARE STATED AND COUNTED.** `-contentView` is stored and answered and NOT drawn: a view belongs to this
process, and compositing it inside the Dock's tile needs the Dock to ask the application to render into a surface of the
Dock's own — a second protocol, which is what Apple's private Dock does. `-size` answers this tier's 48-point tile metric
because no request carries the Dock's real one. The owed census rose 21 -> 23 for those two sentences.

**MEASURED:** classes 147 -> **148** of 168, selectors 4827 -> **4836**, methods-declared 5406 -> **5416**, complete
coverage 148 of 148, owed 21 -> **23**, refusal unchanged at 404, and the tests 182 -> **183** with `tests/dock_tile.m` at
12 checks — plus the window server's `window_list` probe asserting a badge arrives beside its window, and the Dock's
`tests/dock_badge.m` counting the chip's ink in an offscreen draw.

**AND THE HELP SYSTEM IS DEFERRED BY DECISION.** `NSHelpManager` (10 selectors) waits for a WEB ENGINE: its help books
are HTML in Apple's world, and this tree has no HTML renderer at all, so a Help Viewer would be a rendering project
before it was a help one. The decision is recorded here so the next reader does not re-derive it: help stays absent, the
reason is the missing engine rather than the missing class, and `NSHelpManager` is not a candidate slice until a web
engine exists. `NSDockTile`'s content view and the deferred help are the two places where this tier's answer is "another
protocol" or "another engine" rather than "another class".
