# libagora-app — an eighth handoff

*Written at the end of **nine commits in this repository** that made Apple's compiled `.nib` a format this tier can
read, plus the two `libagora-core` and two `libagora-base` commits that were required to read one. `HANDOFF-7.md` is
still the standing measurement of the surface and the long form of the controller work; **THIS FILE IS A FEATURE
HANDOFF, NOT A NEW SURFACE CENSUS — §2 of `HANDOFF-7.md` is unchanged and remains the number to quote.***

*State at this handover, measured: `libagora-app` at `607bf40`, the workspace pointer at `5ef8a16`, the install prefix
rebuilt from both. `tests/apple_nib.m` runs **105 checks**; the app suite group that covers this work is **39/39 in
about 95 s**; the whole `libagora-base` suite is **36/36** (the Foundation/CoreFoundation changes are below). The
translator is `AGAppleNib.m` at 2 528 lines, its header 92, its test 1 414.*

*The working trees are **NOT** clean, and none of the dirt is this work: `libagora-app` has the sheet/printing/panel
edits, `libagora-base` has the `NSFileCoordinator` and API-ledger edits. `libagora-core` is clean. **Do not run
`git add -A` in either repository** — `HANDOFF-7` says this too, and it was nearly paid for again here.*

---

## 1. What landed

The commits are in dependency order. Every `libagora-core` and `libagora-base` commit is load-bearing: the translator
could be written against the old tree and it would fault on the first zero-valued real or miss every object reference.

| Repository | Commit | What it landed |
|---|---|---|
| `libagora-core` | `40e38d8` | **`CFNumberGetType` dispatches to Foundation again.** The call was guarded by `#if DEPLOYMENT_RUNTIME_OBJC`, which this tree does not define, so a Foundation number was read as a CF struct: the binary writer stored a **double as an integer** (1.5 read back 1.0). |
| `libagora-core` | `a1cc697` | **The seven static CFNumber constants have a class.** `0.0`, `1.0` (float and double), NaN and both infinities were `const` with a compile-time-null isa and the binding write was optimised away. A real `0.0` decoded to a pointer with no class; `-isKindOfClass:` segfaulted. |
| `libagora-base` | `62c6f21` | **Binary property lists through Core Foundation.** `bplist00` is recognised and read/written with `CFPropertyListCreateWithData`/`CreateData`; `CF$UID` slots survive as CF's keyed-archiver UID objects; the mutability options and the format out-parameter work; `NSKeyedArchiver`'s binary output format finally produces bytes. Plus the bridge doors: `NSDictionary -__apply:context:`, `NSSet -__applyValues:context:`, `NSNumber -_cfNumberType`, `-_getValue:forType:`. |
| `libagora-base` | `487916c` | **The regression for the static-number fix**: a binary property list carrying a real `0.0` and asserting that it is an `NSNumber` with its value. |
| `libagora-app` | `bde7fc6` | **The translator's first slice**: the `IB.objectdata` walk, records, the calibration pass, the coder adapter, the owner placeholder, and `NSWindowTemplate`/`NSView`/controls/cells/`NSCustomObject`/the two `NSNib*Connector`s. |
| `libagora-app` | `ddf0899` | `NSBox`, `NSScrollView`, `NSClipView`, `NSMatrix`; the coding those classes needed, and `NSScrollView`'s scroller-presence keys. |
| `libagora-app` | `f467903` | Fonts (`NSFont`, a cell's `NSSupport`) and sliders (`NSSlider`/`NSSliderCell`). |
| `libagora-app` | `1641818` | Colour values: white, RGB and a catalog colour's resolved fallback → calibrated RGBA; cells' text/background, clip background, matrix colours, scroll background. |
| `libagora-app` | `d520eb9` | Menus: `NSMenu`/`NSMenuItem`, the item tree, key equivalents, actions, tags, state, mnemonics, separators, submenus. |
| `libagora-app` | `a595598` | `NSTextView`: its coding, and the string followed through `NSTextContainer → NSLayoutManager → NSTextStorage`. |
| `libagora-app` | `82376a6` | `NSImageView`/`NSImageCell`, named images through `NSCustomResource`, `NSBrowser`/`NSBrowserCell`, `NSClassSwapper`. |
| `libagora-app` | `2ddac35` | Autolayout constraints and bindings; the binding connector becomes the third AGNib connection kind. |
| `libagora-app` | `607bf40` | Toolbars, and **NSToolbar's item database**: `NSToolbarItem` coding, `_identifiedItems`, `-items` without a window, and `NSWindow`'s toolbar key. |

The workspace pointers, in order: `341f762`, `6dba155`, `67daf18`, `d7d620c`, `9b49a89`, `9ba0cc4`, `ca27bc5`,
`a261d89`, `5ef8a16`.

---

## 2. What Apple's compiled nib is, and what this reader is

Apple's `.nib` is a **keyed archive**, and the root is not an array of views:

```
$top       { "IB.objectdata" : <uid> }
$objects   [ "$null", <class entries>, <objects>, <collections>, <value leaves> ]
```

The object named by `IB.objectdata` is an **`NSIBObjectData`** with:

| Key | Meaning |
|---|---|
| `NSObjectsKeys` | an array of the archived objects, in object-id order |
| `NSObjectsValues` | a **parallel array of OWNERS**, not names: the object that owns each entry |
| `NSConnections` | the connectors (`NSNibOutletConnector`, `NSNibControlConnector`, `NSNibBindingConnector`) |
| `NSRoot` | the file's-owner placeholder |
| `NSVisibleWindows` | windows to show (ignored here; the caller owns visibility) |

The objects themselves are class instances archived with **Apple's coding keys** — `NSFrame`, `NSvFlags`,
`NSCellFlags`, `NSContents`, `NSWindowTemplate`, `NSCustomObject`, and so on. This tree's classes code **this tree's**
keys (`frame`, `hidden`, `objectView`, …). Handing Apple's bytes to `NSKeyedUnarchiver` therefore answers
`-containsValueForKey:` with NO everywhere and builds default-valued objects — the silent wrong value `NSNib.h` has
always refused.

**The reader is a translator, in three passes:**

1. **Table walk** — every `$objects` entry whose `$class` names a translated class becomes a **record**: a dictionary
   of this tree's coding keys. A reference is an `AGAppleNibRef` carrying the index, so identity and cycles survive.
   Collections and value leaves are not records; they are expanded inline.
2. **Calibration** — every kept reference is checked before anything is built. A reference to an untranslated object
   refuses the whole nib **by name**. This is why the format cannot half-load.
3. **Build** — each record is instantiated with `-initWithCoder:` through `AGAppleNibCoder`, which answers the
   translated keys and resolves refs lazily. The classes' own `-initWithCoder:` runs, with its defaults and its
   designated initialisers. Connections are handed back in AGNib's shape and `NSNib` applies them with the pass it
   already had.

`NSNib` integration is one branch in each of two doors:

- `-instantiateNibWithOwner:topLevelObjects:` parses the data, asks `+[AGAppleNib isAppleNibArchive:]`, and on a hit
  calls `+instantiateAppleNibArchive:topLevelObjects:connections:reason:`, then `-cg_applyConnections:owner:`. AGNib
  is untouched.
- `+refusalReasonForArchiveData:` asks `+validateAppleNibArchive:reason:`, which runs the walk **without building
  anything**. `ibtool validate` therefore validates Apple nibs too.

The owner is not in the archive. References to `NSRoot` become the string `NSNibFileOwner` in connections; the same
substitution is used for a binding destination and for a toolbar item's target. A connection endpoint that names the
**FirstResponder** or **NSApplication** proxy is treated as *nil* (responder chain / no delegate), not as a refusal.

---

## 3. What is translated

The table is the contract. Every key not named here is left at the class's own default and reported by
`+[AGAppleNib unmappedKeysForAppleNibArchive:]`; a class not here refuses the file.

| Apple class | Target / keys |
|---|---|
| `NSWindowTemplate` | `NSWindow` (or `NSWindowClass` if it is in the process and on `NSNib`'s allow-list). `NSWindowRect` is a **CONTENT** rect and is converted with `+frameRectForContentRect:styleMask:`; style mask, backing, title, frame/content min/max, autosave name, `NSWindowView` → `contentView`, `NSToolbar` → `toolbar`. |
| `NSView` / `NSControl` / `NSButton` / `NSTextField` / `NSSplitView` / `NSCustomView` | frame from `NSFrame`/`NSFrameSize` (size-only gets origin 0), `NSvFlags` → hidden (0x80000000), autoresizingMask (0x3F), autoresizesSubviews (0x100), `NSSubviews`, `NSToolTip`, `NSCell`. `NSCustomView` takes the class its `NSClassName` names. |
| `NSClassSwapper` | the class its `NSClassName` names, with the view keys. |
| `NSBox` | `NSContentView` → `contentView`, `NSTitleCell` → `titleCell`, `NSOffsets` → `contentViewMargins`, box/border/title-position/transparent. `NSSubviews` is skipped so the content view is not added twice. |
| `NSScrollView` | `NSContentView` → `contentView`; `NSsFlags` low 2 bits → border, 16/32 → the two scroller-presence booleans, 512 → autohides. Archived `NSScroller`s are dropped (the flags recreate the bars). |
| `NSClipView` | `NSDocView` → `documentView` (or the first subview), `NScvFlags` bits 4/2 → drawsBackground/no-copy-on-scroll, `NSBGColor` → background. |
| `NSMatrix` | flat `NSCells` regrouped into rows by `NSNumRows`/`NSNumCols`, `NSSelectedCell` → the per-slot selected array, `NSCellSize`/`NSIntercellSpacing`, cell prototype and the two colours. **`NSMatrixFlags` is deliberately not translated** (the historical bitfield's byte order); it is ledgered. |
| `NSSlider` / `NSSliderCell` | min/max/value, slider type, tick count/position, alt increment, tick-values-only, knob thickness. `NSVertical` is derived from the frame in this tree, so it is not a property. |
| `NSTextField` + `NSTextFieldCell`, `NSButton` + `NSButtonCell`, `NSCell`, `NSActionCell` | the cell flags (`NSCellFlags`/`NSCellFlags2` masks from GNUstep's decoders), `NSContents` → both `objectValue` and `title` (a field reads one, a button and a box title cell read the other), key equivalent, alternate contents, font (`NSSupport` when it is an `NSFont`), text/background colour, `NSDrawsBackground`, button bezel from `NSButtonFlags2`. |
| `NSImageView` / `NSImageCell` | view: cell, editable, animates, allows-cut-copy-paste; cell: `NSAlign`/`NSScale`/`NSStyle` → image alignment/scaling/frame style. |
| `NSCustomResource` | an **`NSImage`** record carrying `name` (`NSResourceName`), which is this tree's name-coded `NSImage`. A cell's `NSContents` or an item's image that names one becomes its `image`. A **direct** `NSImage` (reps/TIFF) is not translated. |
| `NSBrowser` / `NSBrowserCell` | `NSBrFlags` masks (scroller 0x10000, empty selection 0x20000 inverted, arrow keys 0x100000/0x40000, separators 0x4000000, title-from-previous 0x8000000, multiple selection 0x80000000), min column width, row height, visible columns, resizing type, path separator, cell class/prototype, background colour. |
| `NSTextView` | `NSMaxSize`, Apple's misspelled `NSMinize` (or `NSMinSize`), `NSTVFlags` bits 0/1 → horizontally/vertically resizable, and the string followed `NSTextContainer → NSLayoutManager → NSTextStorage → NSString`. The three text-system objects are not instantiated; the view's own initialiser builds its trio. |
| `NSMenu` / `NSMenuItem` | title, items, font; item title/action/key equivalent/modifiers/tag/state/mnemonic/separator/enabled (inverted from `NSIsDisabled`)/submenu/tooltip. The parent `NSMenu` back-reference is dropped. Apple's 0x7FFFFFFF mnemonic becomes `NSNotFound`. |
| `NSToolbar` / `NSToolbarItem` | identifier, identified items, default identifier list (items → identifiers), selected identifier, display/size/visible/customization/autosave/baseline; item identifier/labels/tooltip/action/tag/enabled/image/view/min/max/visibility-priority/autovalidates. Delegate and item target are **synthetic outlet connections**. |
| `NSLayoutConstraint` | constant, first/second item and attribute, relation, multiplier, priority, identifier. The **owner is not a key**: it is the object map's owner, and the record is attached to that view's `constraints` array so `-addConstraint:` installs it. A view's own `NSConstraints` array is honoured and de-duplicated. |
| `NSCustomObject` | the file's owner is skipped; `NSApplication`/`FirstResponder` are skipped proxies; any other class must exist **and** be on `NSNib`'s allow-list (`+registerDesignClass:`). |
| `NSFont` | `NSName` → `fontName`, `NSSize` → `pointSize`. |
| `NSColor` | `NSWhite`/`NSRGB` component text, plus a catalog colour's fallback → red/green/blue/alpha. Unreadable spaces refuse by name. |
| `NSNibOutletConnector`, `NSNibControlConnector`, `NSNibBindingConnector` | AGNib outlet/action/binding records. Binding options are **not** translated (§4). |

`NSNib`'s allow-list gained `NSBox`, `NSClipView`, `NSMatrix`, `NSImageView`, `NSImageCell`, `NSTextView` and
`NSToolbarItem`; each got the coding and `NSSecureCoding` conformance the reader's census demands. `NSWindow` gained a
`toolbar` key; `NSToolbarItem` gained its full design-state coding; `NSToolbar` gained `_identifiedItems`, the `items`
archive key, and `-items`/`-visibleItems` that load an archived identifier list **without requiring a window**.

The AGNib format itself gained one optional connection kind (documented in `NSNib.h`):

```
BINDING { "AGNibConnectionSource": <object>,
          "AGNibConnectionBinding": "stringValue",
          "AGNibConnectionKeyPath": "content",
          "AGNibConnectionDestination": <object> | "NSNibFileOwner",
          "AGNibConnectionOptions": <dictionary> }        /* optional */
```

---

## 4. What is not translated, and what a reader must not assume

- **A class outside the table refuses the file by name.** The corpus still names `NSPopUpButton`, `NSCursor`, and
  private application classes; modern nibs also carry `NSTabView`, `NSDatePicker`, `NSColorWell`,
  `NSProgressIndicator`, `NSSegmentedControl`, `NSComboBox`, `NSSearchField`, `NSTableView`/`NSOutlineView` cells, and
  so on. None of those is a bug in the translator; each is the next slice.
- **A direct `NSImage` with representations is not translated.** This tree's `NSImage` codes a name and no image data;
  a guessed rep would be the wrong value. Only `NSCustomResource` (named images) is read. Such a reference stays at
  the cell's default and the ledger names `NSCell.NSContents`.
- **`NSMenuItem.NSTarget` and the three state images are not translated.** A main-menu target is the responder chain,
  which a nil target means; the images need the image pipeline. The parent `NSMenu` is dropped because the owning
  menu's `-addItem:` establishes it.
- **`NSNibBindingConnector.NSOptions` is not translated.** The binding is established without it; a transformer or a
  formatter is named in `AGAppleNib.h` rather than guessed.
- **`NSTextView.NSSharedData` (typing attributes, selection) is not translated.** The string, sizes and resizable bits
  are; the rest keeps this tree's defaults.
- **`NSMatrixFlags` is not translated.** Its bitfield's byte order differs between the PowerPC-era archives and the
  little-endian host; the default list mode is the honest answer.
- **`NSWTFlags` (window-template flags) is ledgered, not mapped.** The window's design keys are; released-when-closed
  and the like keep this tree's defaults.
- **The text forms end at binary and XML AGNib.** A **typedstream** `objects.nib` (pre-10.2 Apple) has no reader here,
  and a `.xib` (XIB 5's keyed XML document) is a different schema. The corpus has two typedstream files and 33
  `IB.objectdata` files; the 10.5 SDK's `null.nib` is the only other compiled sample.
- **A system panel nib will still refuse** at its `NSWindowClass` (`NSFontPanel`, `NSColorPanel`, …), because this tree
  does not have the class. That is a class-availability refusal, not a format one.

---

## 5. The Foundation and CoreFoundation work underneath

### 5.1 Binary property lists

`libagora-base/NSPropertyListSerialization.m` now sniffs the first eight bytes. `bplist00` is read with
`CFPropertyListCreateWithData` and written with `CFPropertyListCreateData`; the text formats stay in `plist.c`. The
mutability options pass through, the format out-parameter reports binary, CFError becomes NSError, and `CF$UID` slots
come back as CF keyed-archiver UID objects. **That last fact is the translator's reference type**: `fn_uid_index` is
the one place the private `_CFKeyedArchiverUIDGetValue` is used.

Real macOS `Info.plist` files are binary too, so `NSBundle` started reading them for free.

### 5.2 The bridge doors Core Foundation asks for

Without these, a binary write aborted or a number was read as memory:

- `NSDictionary -__apply:context:` and `NSSet -__applyValues:context:` — `CFDictionaryApplyFunction` /
  `CFSetApplyFunction` dispatch these; the plist writer's validity walk uses the first. Measured before the fix:
  `-[AGDictionaryItems __apply:context:] is not implemented`.
- `NSNumber -_cfNumberType` and `-_getValue:forType:` — `CFNumberGetType`/`CFNumberGetValue` ask by name. Measured:
  `-[AGNumberSigned _cfNumberType] is not implemented`.

### 5.3 The two CFNumber defects

Both were found by the translator, not by a plist test:

1. **`CFNumberGetType` did not dispatch to Foundation.** Its `#if DEPLOYMENT_RUNTIME_OBJC` branch is dead in this
   build. A Foundation number was read as a CF struct, and the binary writer stored a **double as an integer**:
   1.5 read back 1.0. `CFNumberIsFloatType` and `CFNumberGetByteSize` were wrong through it. The fix is the always-live
   `CF_OBJC_FUNCDISPATCHV` that `_CFNumberGetType2` already used.
2. **The seven static float constants had no class.** `0.0`/`1.0` as float and double, NaN, ±infinity are compile-time
   objects whose isa is null in this build. The binder write was optimised away because the storage was `const`, so a
   binary plist carrying a real `0.0` produced a pointer whose `object_getClass` was nil; `-isKindOfClass:` segfaulted.
   The constants are writable now (the shape CFBoolean's two already used) and `cf_bridged_subclass` binds them when
   `__NSCFNumber` is made. A slider with a minimum of 0.0 is the reason this surfaced.

### 5.4 The ownership rule a future reader must not break

`NSPropertyListSerialization`'s read door answers **+1** in this file — both the text path and the new binary path.
That is not Cocoa's contract, but it is this tree's, and it is load-bearing: `NSKeyedUnarchiver` keeps `_table`/`_top`
without retaining them. If someone changes the read door to autorelease, **retain those two ivars first** or the
unarchiver will dangle after the caller's pool drains.

---

## 6. Traps these sessions paid for

1. **Apple references are UIDs, not `$ref` dictionaries.** `NSKeyedUnarchiver` only understands this tree's
   `{"$ref": n}` spelling. The translator never decodes Apple's archive with it; it reads the UID table itself. The
   first binary-plist work made the UIDs visible; the same work made them *usable*.
2. **`NSObjectsValues` is an owner map, not a name table.** The top-level objects are the ones whose owner is
   `NSRoot`, not the ones in `NSObjectsKeys` (that array is every object). The reversed reading makes every child a
   top-level object.
3. **`$null` is a string.** A `NSSecondItem`, `NSToolbarItemTarget` or `NSToolbarDelegate` may be `$null`; a reference
   helper that treats it as an object reference fails with “not an object reference”. `fnSetRefFrom:` and
   `fnSetColorRef:` both accept it as nil.
4. **Geometry is strings.** `NSFrame` is `"{{x, y}, {w, h}}"`, `NSFrameSize` is `"{w, h}"`, `NSOffsets`/`NSCellSize`/
   `NSIntercellSpacing` are size strings. `NSWindowRect` is a CONTENT rect and must be converted to a frame; a window
   restored from it otherwise sits a title bar too high.
5. **A view's child is not always `NSSubviews`.** `NSBox` uses `NSContentView` and `NSTitleCell`, `NSScrollView` uses
   `NSContentView`, `NSClipView` uses `NSDocView`, `NSMatrix` uses `NSCells`. Taking the generic array as well adds the
   same object twice (the box and scroll-view doors re-parent it). The class-specific branches skip it.
6. **`NSContents` is two things.** A string becomes both `objectValue` and `title`; a reference to `NSCustomResource`
   becomes `image`; a direct `NSImage` has no record and is ledgered. A box's title is its title cell's `title`, which
   is why the string is written under both names.
7. **Constraints have no owner key.** The object map owns them. A translated constraint that is only instantiated is
   inert; `fnAttachOwnedConstraints` appends it to the owner view's `constraints` array, where `-addConstraint:` makes
   it active. `NSConstraints` on a view is the second spelling and is de-duplicated.
8. **Binding connections substitute the owner BEFORE applying.** The first version inserted the binding branch before
   `NSNib`'s placeholder substitution and bound to the string `"NSNibFileOwner"`; the symptom was
   `[NSConstantString valueForKey:]: … not KVC-compliant for the key content`. The binding block now sits after the
   substitution.
9. **A toolbar's items are not loaded until asked, and asking used to require a window.** `-items` gated
   `fn_loadItemsIfNeeded` on `_window != nil`, and `fn_loadItemsIfNeeded` only asked the delegate's default list. An
   archived toolbar therefore answered zero items. Both halves are fixed: `-items`/`-visibleItems` always load, and a
   decoded `_itemIdentifiers` list is the fallback when the delegate is absent or does not implement the optional
   method. The identified items are the first source in `-itemForItemIdentifier:` (Apple's `_initPListDatabase`).
10. **A toolbar item's target and a toolbar's delegate are not coding keys in this tree.** They are live refs in
    Apple's archive, and the placeholders must go through the connection pass. The translator queues **synthetic
    outlet connections** (`target`, `delegate`) which `fnBuildConnections` resolves; a proxy destination means nil
    (responder chain / no delegate), not a refusal.
11. **The app tree is dirty with unrelated sheet/printing work.** Stage by path, and for a shared file stage by hunk.
    `NSWindow.m` was nearly staged whole (341 unrelated lines) while adding the eleven-line toolbar key; the filtered
    `git apply --cached` of only the `AGCoderWindowToolbarKey` hunks is the pattern that worked.
12. **The real fixtures are old system panels.** They are useful for refusal messages and for the text-system chain,
    but they will not validate: `NSFontPanel` refuses its window class, `NSColorPanel` likewise, a picker refuses a
    private view class, and six files are a different (non-`IB.objectdata`) schema. **The synthetic fixtures in
    `tests/apple_nib.m` are the tests.** They are built with `_CFKeyedArchiverUIDCreate`, real class entries, and the
    binary writer, which is the same shape Apple writes.
13. **`NSImageCell`/`NSBox`/`NSClipView`/`NSTextView`/`NSToolbarItem` had no coding at all.** The translator cannot
    translate a class this tree cannot archive; each got `encodeWithCoder:`/`initWithCoder:`/`supportsSecureCoding` and
    an allow-list entry. The `classesInheritingCoding` census in the nib tests is the check that a subclass with state
    did not inherit its parent's coding.

---

## 7. How to add the next class

1. **Find its keys, from evidence.** Search the corpus (`audit/corpus/**/keyedobjects.nib`) and, when there is no
   fixture, GNUstep's decoder for the class in `audit/corpus/libs-gui/Source/` (`NSView`, `NSCell`, `NSButtonCell`,
   `NSScrollView`, `NSBrowser`, `NSToolbar`, `NSToolbarItem`, `NSLayoutConstraint` all have one). Do not invent a key:
   the format's rule is the wrong value is worse than an unfinished class.
2. **Make the target class archivable if it is not.** `encodeWithCoder:`, `initWithCoder:`, `+supportsSecureCoding`,
   the `NSSecureCoding` conformance in the header, and an entry in `NSNib.m`'s `fn_design_classes`. Repeat the
   designated initialiser's defaults in `-initWithCoder:` (a decode does not run `-init`/`-initWithFrame:`).
3. **Add a translator builder.** A record is an `NSMutableDictionary` whose `AGAppleNibClassKey` is the target class.
   Scalars are `NSNumber`/`NSString`/`NSValue`; object children are `[AGAppleNibRef refWithIndex:]`; collections are
   `NSArray`s of those. Read helper methods in `AGAppleNib.m`: `fnStringValue:`, `fnNumberValue:`, `fnArrayValue:`,
   `fnSetRefFrom:key:inRecord:as:`, `fnSetColorRef:…`, `fnNoteUnmappedForEntry:className:consumed:`.
4. **Feed the walk.** Add the class to `fn_is_translated_view_class`/`fn_is_translated_cell_class` or a branch in
   `buildRecords`, and call the builder. Skip `NSSubviews` when the class owns its child through a typed door.
5. **Calibrate and connect.** Every record ref is checked by `fnCalibrateRecords`; every connector by
   `fnValidateConnections`. A delegate/target that is a live ref is queued with `fnQueueSyntheticOutletFromIndex:…` and
   resolved in `fnBuildConnections`.
6. **Ledger the rest.** Put every Apple key the builder consumed in its `consumed` set. Anything left is reported by
   `+unmappedKeysForAppleNibArchive:` and is the honest list of what the slice does not carry.
7. **Write a synthetic Apple archive in `tests/apple_nib.m`.** Use `add_class`/`add_object`/`add_array`, inline values
   for scalars, UIDs for refs, `add_object` for a dictionary (`NS.keys`/`NS.objects`) when a key needs one. Write it
   with `archive_data` (binary, through the new CF path), load it with `NSNib`, and assert the object graph — not just
   that it did not crash.
8. **Run the group and the base suite.** `ctest --test-dir libagora-app/build -R appkit-apple-nib`, then the group in
   §8, then `libagora-base` if you touched a bridge door.

---

## 8. Tests, and how to run them

```sh
# the translator's own 105 checks
ctest --test-dir libagora-app/build -R appkit-apple-nib -V

# every AppKit suite this work can affect (39 tests, ~95 s)
ctest --test-dir libagora-app/build \
  -R "appkit-(toolbar|nib|apple-nib|ibtool|auto-layout|binding|box|clip-view|scroller|scroll-view|matrix|slider|menu|browser|image|text-view)"

# the Foundation/CoreFoundation changes beneath it
ctest --test-dir libagora-base/build --output-on-failure      # 36/36
```

`tests/apple_nib.m` is the fixture corpus. It builds, in memory, Apple-shaped archives for:

| Function | What it proves |
|---|---|
| `build_archive` / `test_instantiation` | a view with a button and a text field, `NSFrame`/`NSvFlags`, cell classes and flags, `NSContents`, an outlet from the owner and the button's action. |
| `test_unmapped_ledger` | an Apple key left at the default is named. |
| `test_refusal_of_unsupported_class` | a class outside the table refuses by name (`NSToolbar` is used as the deliberate stranger now that it is translated). |
| `test_window_template_validation` / `test_window_class_refusal` | `NSWindowTemplate`'s content-rect conversion and the unavailable `NSWindowClass` refusal. |
| `build_layout_archive` / `test_layout_translation` | box + content view + title cell, scroll view + clip view + matrix document, slider, image view with a named resource, class swapper, text view through the chain, a two-view width constraint, and the font/colour/`NSDrawsBackground` keys — all in one tree. |
| `build_menu_archive` | menu tree, separators, disabled inversion, mnemonic, submenu. |
| `build_browser_archive` | browser flags, sizes, path separator, prototype. |
| `build_binding_archive` | `NSNibBindingConnector` → `infoForBinding:` + initial value. |
| `build_toolbar_archive(NO)` / `build_toolbar_archive(YES)` | identified items, default identifiers, delegate/target connections, separator, named image; and a window-template + toolbar validation. |

The corpus scan (`/tmp/apple_scan` was a temporary probe; the command is a `find` over
`audit/corpus/**/keyedobjects.nib`) is still useful for the refusal census: 33 `IB.objectdata` files, 2 typedstream,
the 10.5 SDK `null.nib`, and no modern Xcode-fixture on this machine.

---

## 9. Where to spend the next hour

In rough order of payoff against risk:

1. **`NSPopUpButton` / `NSPopUpButtonCell`.** Six corpus refusals name it; the menu work already exists, and the cell's
   keys are `NSPreferredEdge`, `NSArrowPosition`, `NSUsesItemFromMenu`, `NSMenuItem`, `NSMenu`, `NSButtonFlags2`.
   The menu item cell would need `NSMenu`/`NSMenuItem` records, which the translator already builds.
2. **`NSCursor` as an auxiliary class.** Four refusals name it; it is a value leaf on `NSClipView`, not a structural
   object. Adding it to `fn_is_auxiliary_class` lets those files reach the next real class (and the cursor is ledgered
   because `NSClipView.NSCursor` is not translated).
3. **`NSTabView` and `NSDatePicker`/`NSColorWell`.** Real app nibs; each needs its own key table and, for the tab view,
   an item class (`NSTabViewItem`).
4. **Direct `NSImage` reps.** The largest remaining fidelity gap for image cells: `NSBitmapImageRep` carries
   `NSTIFFRepresentation`, and `NSImage` carries `NSReps`/`NSImageFlags`/`NSColor`. This tree's `NSImage` would need a
   rep-coding path before the translator can carry the bytes; the named-resource path is already done.
5. **`NSTableView` / `NSOutlineView` / `NSTableColumn` / `NSTableHeaderView`.** The cells and the scroll view are
   translated; the table classes need columns, row/height and delegate wiring, and their archives are more private.
6. **`NSProgressIndicator`, `NSSegmentedControl`, `NSComboBox`, `NSSearchField`.** Simple controls whose cells already
   have coding; the same pattern as the slider.
7. **`NSTextView.NSSharedData`, `NSMatrixFlags`, `NSMenuItem` targets/state images, binding `NSOptions`.** Each is a
   stated ledger entry, not a silent loss.
8. **Typedstream and `.xib`.** Deliberately out of scope; each is a second format, not a missing key.

---

## 10. Things a reader should not have to rediscover

- **The working trees are dirty with other work.** See the preface. `git add -A` is wrong in both `libagora-app` and
  `libagora-base`. Use `git add <path>`, and `git apply --cached` with a filtered hunk for a shared file.
- **The read door answers +1.** Do not “fix” it to autorelease without retaining `NSKeyedUnarchiver`'s `_table`/`_top`.
- **`_identifiedItems` and `_items` are different.** `_identifiedItems` is the archive’s pre-made item dictionary;
  `_items` is the live order the toolbar has loaded. `-items` loads `_itemIdentifiers` into `_items` through
  `fn_itemForIdentifier:`, which checks the dictionary first. Do not make `-items` window-dependent again.
- **A constraint’s owner is the object map’s.** It is not a key on the constraint. Without
  `fnAttachOwnedConstraints` the equations exist and never install.
- **Synthetic outlets are connections.** A toolbar delegate or item target is queued with
  `fnQueueSyntheticOutletFromIndex:toValue:keyPath:` and applied by `fnBuildConnections`; the file’s-owner placeholder
  is substituted there, not in the record.
- **`NSNib`’s connection vocabulary now has three kinds.** `NSNib.h` documents outlet/action/binding; the binding key
  and options are `NSNibConnectionBindingKey`/`NSNibConnectionOptionsKey`. An archive without one reads as before.
- **The ledger is the fidelity statement.** `+unmappedKeysForAppleNibArchive:` is what a caller should print when it
  wants to say what a translated nib did not carry; an empty ledger is not the goal, an honest one is.
- **`AGAppleNib.m` is deliberately not in `tests/`.** The eventual home of a compiler/importer is its own repository
  (`NSNib.h` says so). The translator lives in the library because loading is a runtime door; `ibtool`'s text source
  remains the owned format.

---

## 11. Where the code is

| File | What to read it for |
|---|---|
| `AGAppleNib.h` | the contract: what is translated, what is refused, the three public doors (`isAppleNibArchive:`, `validateAppleNibArchive:reason:`, `instantiateAppleNibArchive:topLevelObjects:connections:reason:`), the ledger. |
| `AGAppleNib.m` | the importer: `fn_uid_index`, class-name resolution, `_records`/`AGAppleNibRef`, `buildRecords`, the class builders, `fnAttachOwnedConstraints`, `fnQueueSyntheticOutletFromIndex:`, `AGAppleNibCoder`, `fnDecodeObjectAtIndex:`. |
| `NSNib.h` / `NSNib.m` | the AGNib format (now including BINDING), the Apple branch in `-instantiateNibWithOwner:` and `+refusalReasonForArchiveData:`, and the apply pass. |
| `NSToolbar.h` / `NSToolbar.m` | `_identifiedItems`, the `items` coding key, `-items`/`-visibleItems`, `fn_loadItemsIfNeeded`, `fn_itemForIdentifier:`. |
| `NSToolbarItem.h` / `NSToolbarItem.m` | the item’s design-state coding. |
| `NSBox.m`, `NSClipView.m`, `NSImageCell.m`, `NSTextView.m`, `NSWindow.m` | the coding additions this work needed. |
| `NSNib.m` `fn_design_classes` | the allow-list a new design class must join. |
| `tests/apple_nib.m` | the fixture builders and 105 checks. |
| `libagora-base/NSPropertyListSerialization.m` | the binary plist path and its ownership rule. |
| `libagora-core/CFNumber.c`, `CFRuntime.c` | the two CFNumber defects and their binders. |
| `HANDOFF-7.md` | the standing surface measurement and the controller long form. |

---

## 12. State, and the checklist for the next handoff

- `libagora-app` HEAD `607bf40`; workspace pointer `5ef8a16`; install prefix rebuilt (`cmake --install` of app, base
  and core).
- `appkit-apple-nib`: 105 checks, passing. The affected AppKit group: 39/39. `libagora-base`: 36/36. `libagora-core`
  has no suite; its fixes are held by `core_values`, `bridges` and the translator’s slider/colour/constraint cases.
- Known-dirty and not this work: `libagora-app` sheet/printing/panel edits, `libagora-base` `NSFileCoordinator` and
  API-ledger edits. `libagora-core` clean.
- Before declaring a successor done: rebuild core → base → app in `release/components.conf` order, install, run
  `appkit-apple-nib`, the 39-test group, and `libagora-base`; then run the demo only if the change is runtime-visible.
  Quote the suite and the binary (`ldd`) as `HANDOFF-7` §8 asks.
