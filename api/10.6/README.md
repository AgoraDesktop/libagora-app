# api/10.6 — the committed facts of Apple's 10.6 AppKit

**The SDK is not here, and must not be.** Apple's headers are not redistributable. What is here is a **name
manifest**: class names with their superclasses, protocol names, selector names per class, and C function
names — facts of the same kind as a symbol table, which is the arrangement `COCOA-10.11-SURFACE-PLAN.md` §2.1
commits to ("the recipe and the generated name manifest, which is a list of facts (names, versions, selectors),
not Apple's expression of them"). No declaration, comment, availability annotation, nullability or line of
Apple's prose is copied into this directory.

`appkit-manifest.txt` — 168 classes, 56 protocols, 87 C functions, 5,208 declared selectors.

## Why 10.6 and not 10.11

`libagora-app`'s era pins are 10.2/10.5/10.6, and the plan records the tree's own reference as 10.6 (§2.1). The
10.11 SDK is a **new** reference rather than a replacement, so it is the wrong denominator for "what is missing
today": measuring against it charges this tier for 47 classes that exist only in 10.7–10.11 and that no slice has
promised. The plan's own §0 says the same thing the census now measures — the gap is overwhelmingly the **10.6
surface this tree never finished** (91 of 138 missing classes, 33 of 75 protocols, 76 of 81 functions were already
in 10.6).

## Regenerating the manifest

Needs network access and a local checkout of the 10.6 SDK headers. Nothing is installed into the tree except the
manifest.

```sh
BASE=https://raw.githubusercontent.com/phracker/MacOSX-SDKs/master/MacOSX10.6.sdk/System/Library/Frameworks
mkdir -p /tmp/sdk106/AppKit /tmp/sdk106/Foundation

# the 10.6 frameworks put their headers in Versions/C/Headers; `Headers` is a symlink to it
for fw in AppKit Foundation; do
  curl -s "https://api.github.com/repos/phracker/MacOSX-SDKs/contents/MacOSX10.6.sdk/System/Library/Frameworks/$fw.framework/Versions/C/Headers" \
    | python3 -c 'import json,sys; [print(x["name"]) for x in json.load(sys.stdin) if x["type"]=="file"]' \
    > "/tmp/$fw.names"
  cat "/tmp/$fw.names" | xargs -P 12 -I{} curl -s -o "/tmp/sdk106/$fw/{}" \
    "$BASE/$fw.framework/Versions/C/Headers/{}"
done

tools/api-ledger manifest /tmp/sdk106/AppKit /tmp/sdk106/Foundation > api/10.6/appkit-manifest.txt
```

**Both framework directories are passed, and the order matters.** The first is the framework being measured; any
later one is used only to decide *ownership*. `NSFileWrapper` is the case that needs it: 10.6 ships
`AppKit/NSFileWrapper.h`, but in this tree the class is Foundation's (it lives in `libagora-base`), so measuring
would charge one class to two ledgers. Ownership goes to the framework that declares the class **primarily** —
`@interface NSFileWrapper : NSObject` rather than `@interface NSObject (NSCategory)` — which is also what keeps
`NSObject`, `NSURL` and `NSCoder` out of the AppKit column, where Apple's AppKit only reaches them through
categories.

## Using it

```sh
tools/api-ledger missing api/10.6/appkit-manifest.txt .    # what is absent, and the largest selector debts
tools/api-ledger census  api/10.6/appkit-manifest.txt .    # the `name count` metrics the census pins
tools/api-ledger check   api/10.6/appkit-manifest.txt . tests/api-10.6-census.txt
```

`check` is the developer-facing shortcut; the build gate is `tests/api_census.cmake`, which runs the same
`census` command and then does the two-directional comparison the other two censuses do. Both fail on a metric
that appeared, a metric that vanished, or a count that moved — so **changing the census is a deliberate act with
a diff**, and the only way to do it is to edit `tests/api-10.6-census.txt` in the same commit.

## Two measurements, not one

`census` reports both directions, and they answer different questions:

| Direction | Metrics | Question |
|---|---|---|
| **Against Apple** | `classes-*`, `selectors-*`, `protocols-*`, `functions-*` | how much of the 10.6 surface does this tree reach? |
| **Against itself** | `methods-declared`, `methods-declared-not-implemented`, `selphantom:<Class>` | does this tree keep its own promises? |

The second exists because the first cannot see a contradiction: `selectors-present` counts a selector when the tree
declares **or** implements it, so a header promising a door with no body behind it scores the same as a real one. A C
function has the same problem, which is why `functions-present` is answered by `nm -D --defined-only` on the built
library rather than by the headers, and why the two disagreement counts (`functions-declared-not-defined`,
`functions-defined-not-declared`) are pinned at zero and checked as **faults** rather than drift.

**In a method, `methods-declared-not-implemented` counts each declaration once, at the class that writes it, against
that class's implemented chain.** Summing the same question over every subclass instead reads ~10× higher — one absence
on `NSResponder` reappears in twenty descendants — which is how a one-off measurement of this first produced 1,138
instead of 4. A declaration lives where it is written; the census counts it there. Two further blind spots were found by
the same pin: `@synthesize`-generated accessors and the tree's `FN_FLAG_PAIR`-style accessor macros have no method line
to find, and `@property (getter=isHidden) BOOL hidden` declares `isHidden`, not `hidden`.

## How a selector is judged present

Three answers count, and the first is the one that matters:

1. **Implemented in a `.m` body** on the class or anywhere up its local superclass chain — this is what
   `respondsToSelector:` would answer.
2. Declared in a local header on the class or an ancestor.
3. A `@property` contributes its getter *and* its setter (unless `readonly`), because an accessor is a door a
   caller sends.

Inheritance is resolved because the plan requires it (§2.4) — and because not resolving it is the mistake that
first reported `NSTextView 0 of 130` for a class that inherits most of its surface from `NSText`. The parser bugs
found while building this instrument are recorded at the top of `tools/api-ledger`, each with the plausible wrong
answer it produced; a count is only worth keeping if it is recomputable, and a parser that fails silently toward
"missing" will always look like progress.
