# libagora-app — a seventh handoff

*Written at the end of **three slices and one fix** that picked the controller question up where `HANDOFF-6.md` §6
stopped — the substrate first, in `libagora-base`, and then the binding layer in this repository. `HANDOFF-6.md` is
still the long form of everything up to §12 (the rule editor); §1–§7 of that file remain worth reading, and its §4
traps are still the ones these sessions used most. **THIS FILE'S §2 NUMBERS SUPERSEDE EVERY EARLIER HANDOFF'S.***

*State at this handover: **four slice commits** since the sixth handoff — three in `libagora-base`, one here — tree clean,
**166 tests passing in about 90 s**, `api-ledger check` holding **381 metrics** — **137 of 168 classes (81%), 4636 of
4636 selectors (100%), 44 of 56 protocols (78%), 86 of 86 functions**, 5200 methods declared with 8 having no body,
**all 135 classes with a surface at COMPLETE coverage** — refusal census **390**, owed census **19**. **The 31 absent
classes and the 12 absent protocols are the remaining surface; the 100% on selectors is 100% of the classes this tree
HAS, not of the 10.6 AppKit.** The three new probes hold the substrate: `libagora-base/tests/kvo_automatic.m` (34
checks), `libagora-base/tests/kvo_tomany.m` (37), and `libagora-app/tests/binding_base.m` (26). The workspace's 14
tests were run too.*

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
classes   137 of 168   (81%)    31 missing
selectors 4636 of 4636 (100%)    0 missing   135 of 135 classes at COMPLETE coverage
protocols  44 of  56   (78%)    12 missing
functions  86 of  86  (100%)     0 missing    10 refuse by name
methods   5200 declared on this tree's own classes, 8 with NO body on the chain (0.2%)
```

**NONE OF THE SUBSTRATE SLICES ADDED A MANIFEST CLASS OR SELECTOR, AND THAT IS THE POINT OF A FOUNDATION ROW.** The
class, selector and protocol counts are unchanged since `HANDOFF-6` §12; what moved is `methods-declared`, 5186 ->
**5200**, for the fourteen `NSObject`-category declarations the binding layer adds (bind/unbind/info, the exposed-binding
pair, the value class, the option descriptions, the two placeholder doors, the two editor-registration doors and the
three NSEditor doors). The census records that movement with its reason. **`NSObject` is not one of the manifest's AppKit
classes**, so no `sel:` line changed and no denominator moved.

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

**THE NEXT SLICE IS `NSController` AND `NSObjectController` — 37 selectors — AND THE DESIGN QUESTIONS ARE ALREADY
ANSWERED.** The three Foundation rows and the binding layer exist so that this slice can be a controller, not a
substrate:

1. **The layer is generic** (`NSObject`'s `-bind:`/`-unbind:`/`-infoForBinding:`), one-way observable -> receiver, with
   the options this tier reads named in `NSKeyValueBinding.h`. A controller's `content` is a binding destination like
   any other property.
2. **Content is live** through the proxies and the to-many pair: an object controller can observe its content object's
   properties, and an array controller can watch items arrive and leave instead of only whole-array replacement.
3. **Core Data and `NSPredicate` doors refuse by name**: `managedObjectContext`, `entityName`, `fetchPredicate`,
   `defaultFetchRequest`, `fetch:`, `fetchWithRequest:merge:error:`, `filterPredicate`, and their siblings. The useful
   80% — content, selection, arranged objects, sorting, add/remove — is real.
4. **`-selection` is a real proxy**: a singleton that forwards KVC to the selected object, with `NSNoSelectionMarker`
   when there is none and `NSMultipleValuesMarker` when several. The markers and `NSIsControllerMarker` are already
   there; the proxy class is the slice's own.
5. **The order is the base first**, then `NSArrayController` (47), `NSUserDefaultsController` (12),
   `NSDictionaryController` (13), `NSTreeController` + `NSTreeNode` (55).

**CONCRETELY, THE FIRST SLICE:**

* `NSController` (6): `-objectDidBeginEditing:`/`-objectDidEndEditing:` maintain a set of editors;
  `-isEditing` asks it; `-commitEditing`/`-discardEditing`/`-commitEditingWithDelegate:didCommitSelector:contextInfo:`
  run over the registered editors (the `NSObject` defaults in `NSKeyValueBinding` are the no-editor case).
* `NSObjectController` (31): `-content`/`-contentObject` (a single object; a collection content is the exception);
  `-selection` (the proxy) and `-selectedObjects`; `-objectClass` (default `NSMutableDictionary`) and `-newObject`;
  `-canAdd`/`-canRemove`; `-add:`/`-addObject:`/`-remove:`/`-removeObject:` against a mutable collection or the single
  content; `-automaticallyPreparesContent`/`-prepareContent`; `-isEditable`; the Core Data doors refused; the exposed
  bindings (`content`, `contentObject`, `selection`, `selectedObjects`, `editable`, `canAdd`, `canRemove`); and
  `-validateUserInterfaceItem:` for the add/remove actions.
* **AND THE ONE REAL DESIGN QUESTION LEFT IS THE MULTI-VALUE SELECTION.** `-selection` for one object is a forwarder;
  for several, Apple answers values with `NSMultipleValuesMarker` and writes through only when the values agree. Decide
  whether the first slice's proxy does that (the marker is already here) or returns the marker for the whole selection
  and leaves agreement to a later row — either is a statement, and the header should make it.

**THEN `NSArrayController`** is the one bindings actually use: `arrangedObjects` (the sorted/filtered array),
`selectionIndexes` into it, `sortDescriptors` (the class exists), `add:`/`insertObject:atArrangedObjectIndex:`/
`removeObjectAtArrangedObjectIndex:` over `content` with the proxies, and `preservesSelection`/`selectsInsertedObjects`/
`avoidsEmptySelection`. `filterPredicate` refuses by name.

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
* **THE NUMBERS AND THE GATES.** 137 of 168 classes (81%), 4636 of 4636 selectors, 44 of 56 protocols, 86 of 86
  functions, 5200 methods declared (8 without a body), 381 metrics, refusal 390, owed 19, 166 tests in this repository
  (~90 s), 8 committed base suites, 14 workspace tests. `ctest --test-dir build -j4` is the gate; the exit status is the
  witness.
* **THE ABSENT SURFACE.** 31 classes, 12 protocols: the seven controllers (164 selectors), the predicate pair (absent on
  purpose — no `NSPredicate` family), the Core Data doors inside the controllers (refused by name), and the plan's §A11
  refusals (OpenGL, QuickDraw, movies, the typesetters, speech, sound, the input-manager era, the Dock tile, the Help
  Viewer, `NSPersistentDocument`, `NSTouch`, and `NSFileWrapper`, which is Foundation's here).

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
