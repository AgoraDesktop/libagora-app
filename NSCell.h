/*
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
/*
 * NSCell.h — THE ROOT OF THE CELL FAMILY (stage E).
 *
 * THIS FILE IS THE FAMILY'S FIRST UNIT, AND IT IS ITS TYPES RATHER THAN ITS DOORS, which is the order the plan
 * derives: every door Apple declares on a cell is declared IN TERMS OF these — `-cellType` answers an `NSCellType`,
 * `-controlSize` an `NSControlSize`, `-backgroundStyle` an `NSBackgroundStyle` — so a class whose types are absent
 * cannot be written at all. IT IS ALSO WHERE `NSControl`'S HALF OF THE CYCLE WILL LAND: `NSCell <-> NSControl` is a
 * measured cycle, and the types are the part of it that is genuinely shared.
 *
 * **THE VALUES ARE THE ERA'S, READ OUT OF THE 10.6 HEADER RATHER THAN RECALLED**, which the standing grant covers:
 * declarations may be read, for compatibility only. That matters more here than anywhere else this plan has been,
 * because AppKit's cell constants are a DENSE bitfield of small integers where the numbers ARE the interface — a
 * caller composes `NSCellAttribute` bits, compares `NSCellStateValue` against `-1` for the mixed state, and passes
 * `NSControlSize` to a control. A guessed number in this file would not be an unfinished door; it would be a WRONG
 * CELL, silently, in a place where a compiler cannot help.
 *
 * **AND THE FOUR `NSCellHit*` CONSTANTS, WHICH THIS FILE'S FIRST SLICE LEFT ABSENT ON PURPOSE, HAVE ARRIVED** — the
 * block that declares them has been read, and it carries the values AND the era's own account of what each one means
 * and what the default implementation answers for each kind of cell. "A guessed constant is worse than an absent one"
 * was the rule that kept those four rows OPEN, which is what an open row is for; READING THE BLOCK is what closes
 * them, and nothing cheaper would have. See §A10bk, and the declarations at the end of this file.
 */
#ifndef APPKIT_NSCELL_H
#define APPKIT_NSCELL_H

#import <Foundation/Foundation.h>
/* AND ONE IMPORT THIS CLASS USED NOT TO NEED: `NSBackgroundStyle`, the enum behind `-backgroundStyle` and
 * `-interiorBackgroundStyle`, IS DECLARED IN `NSView.h` — WHERE STAGE A PUT IT, because a view's background style is
 * what that stage needed first and where the ledger's two `var` rows for it were answered. APPLE PUTS THE ENUM ON
 * THE CELL, and this file followed the era until the enum's one home became a compiler error: two identical
 * declarations of one enum are a REDEFINITION, and it only appears in a file that includes both headers — which is
 * what a menu cell does. See appkit-plan.md §A10av and §A10aw.
 *
 * AND THE IMPORT STANDS HERE RATHER THAN WHERE THE DUPLICATE WAS, which is not a preference: CLANG REFUSES AN
 * INCLUDE INSIDE AN `NS_ASSUME_NONNULL` REGION, and the duplicate sat in the middle of one. That is a whole
 * attempt's worth of finding, and it is why the line is above the pragma rather than beside the class. */
#import <AppKit/NSView.h>
/* **AND THE THREE IMPORTS THAT BRING THE LAYOUT TYPES — WHICH ARE APPLE'S OWN FIVE IMPORTS FOR THIS HEADER, IN ITS
 * OWN ORDER.** The era's `NSCell.h` imports `NSText.h`, `NSParagraphStyle.h` and `NSApplication.h` beside Foundation,
 * because `-alignment` is an `NSTextAlignment`, `-lineBreakMode` an `NSLineBreakMode`, and
 * `-userInterfaceLayoutDirection` an `NSUserInterfaceLayoutDirection` — the last of which lives on the APPLICATION and
 * is reached from here by an import rather than by a redeclaration. THE BLANKET RULE THIS PLAN WORKS UNDER IS "MATCH
 * APPLE, INCLUDING WHICH HEADER", so these three lines are transcriptions of Apple's include graph and not choices:
 * the alternative would have put fifteen ledger rows' types in a file the ledger does not hold them against. */
#import <AppKit/NSText.h>
#import <AppKit/NSParagraphStyle.h>
#import <AppKit/NSApplication.h>

NS_ASSUME_NONNULL_BEGIN

/* THE CELL'S DATA TYPES, which say what kind of value `-objectValue` is allowed to hold. The numbers skip 5, and
 * that gap is the artefact's — Apple's own sequence runs 0,1,2,3,4,6,7 — so it is kept rather than tidied. */
enum {
	NSAnyType = 0,
	NSIntType = 1,
	NSPositiveIntType = 2,
	NSFloatType = 3,
	NSPositiveFloatType = 4,
	NSDoubleType = 6,
	NSPositiveDoubleType = 7
};

/* WHAT A CELL IS: nothing, text, or an image. Everything else about a cell is state. */
enum {
	NSNullCellType = 0,
	NSTextCellType = 1,
	NSImageCellType = 2
};
typedef NSUInteger NSCellType;

/* AND THE ATTRIBUTES, WHICH ARE A BITFIELD — a caller ORs them into `-setCellAttribute:to:`. The order is the
 * artefact's and the numbers are the interface. */
enum {
	NSCellDisabled = 0,
	NSCellState = 1,
	NSPushInCell = 2,
	NSCellEditable = 3,
	NSChangeGrayCell = 4,
	NSCellHighlighted = 5,
	NSCellLightsByContents = 6,
	NSCellLightsByGray = 7,
	NSChangeBackgroundCell = 8,
	NSCellLightsByBackground = 9,
	NSCellIsBordered = 10,
	NSCellHasOverlappingImage = 11,
	NSCellHasImageHorizontal = 12,
	NSCellHasImageOnLeftOrBottom = 13,
	NSCellChangesContents = 14,
	NSCellIsInsetButton = 15,
	NSCellAllowsMixedState = 16
};
typedef NSUInteger NSCellAttribute;

/* WHERE AN IMAGE SITS IN A CELL, and whether it is scaled to fit. */
enum {
	NSNoImage = 0,
	NSImageOnly = 1,
	NSImageLeft = 2,
	NSImageRight = 3,
	NSImageBelow = 4,
	NSImageAbove = 5,
	NSImageOverlaps = 6
};
typedef NSUInteger NSCellImagePosition;

enum {
	NSImageScaleProportionallyDown = 0,
	NSImageScaleAxesIndependently = 1,
	NSImageScaleNone = 2,
	NSImageScaleProportionallyUpOrDown = 3
};
typedef NSUInteger NSImageScaling;

/* THE STATE, AND `NSMixedState` IS `-1` — the one negative constant in this file, and the one a caller's `if` is
 * most likely to get wrong: off is 0, on is 1, and MIXED is what neither of those is. */
enum {
	NSMixedState = -1,
	NSOffState = 0,
	NSOnState = 1
};
typedef NSInteger NSCellStateValue;

/* THE BUTTON CELL'S TWO MASKS: what a cell lights by, and what it changes. */
enum {
	NSNoCellMask = 0,
	NSContentsCellMask = 1,
	NSPushInCellMask = 2,
	NSChangeGrayCellMask = 4,
	NSChangeBackgroundCellMask = 8
};

/* **AND THE CONTROL TINT IS THIS FILE'S TYPE RATHER THAN `NSColor`'S, WHICH IS THE ERA'S OWN DIRECTION AND THE ONE
 * THIS TREE NOW FOLLOWS.** The 10.6 header declares the enum and its typedef HERE — a cell is what carries a tint —
 * and its `NSColor.h` reaches across for the type with `#import <AppKit/NSCell.h>`, exactly as this file imports
 * `NSView.h` for `NSBackgroundStyle`. It was ALSO declared in this tree's `NSColor.h` (stage B, where
 * `+colorForControlTint:` needed the type before this class existed) until the re-base of `NSMenuItemCell` pulled
 * both headers into one file and four redefinitions fired; that header now imports this one instead. See
 * appkit-plan.md §A10bf and §A10bg. */
enum {
	NSDefaultControlTint = 0,
	NSBlueControlTint = 1,
	NSGraphiteControlTint = 6,
	NSClearControlTint = 7
};
typedef NSUInteger NSControlTint;

enum {
	NSRegularControlSize = 0,
	NSSmallControlSize = 1,
	NSMiniControlSize = 2
};
typedef NSUInteger NSControlSize;

/* **AND THE SURFACE A CELL IS DRAWN ONTO — `NSBackgroundStyle` — IS NOT DECLARED HERE, WHICH IS A DECISION RATHER
 * THAN AN OMISSION.** It lived at this line until the re-base of `NSMenuItemCell` found that `NSView.h` declares the
 * same enum, and that two identical declarations of one enum are a REDEFINITION the moment a file includes both —
 * which is exactly what a menu cell including its item and its button cell does. `NSView.h` OWNS IT: stage A declared
 * it there first, because a view's background style is what that stage needed, and the ledger's two `var` rows for it
 * were answered there. So this file IMPORTS it at the top of the header instead, and the enum means what it always
 * meant — it simply has one home. See appkit-plan.md §A10av and §A10aw. */

/* ============================================================================================ *
 * AND THE CLASS ITSELF, WITH THE STATE THAT COSTS NO INK.                                     *
 * ============================================================================================ */

/* The plan's stages are closed by CLASS, and this is the class's first slice: the types above and the four pieces of
 * state whose doors need nothing from a font or a view. The rest of Apple's cell — the value accessors, the format
 * and the object formatter, the drawing — stays OWED, row by row, in the ledger, and is what the next slices of
 * stage E will close. */
/* ============================================================================================ *
 * AND THE STANDARD BEZEL'S TWO NUMBERS, IN ONE PLACE BECAUSE TWO CLASSES DRAW IT.                 *
 *                                                                                                *
 * A push button's face is this rounded rectangle (`NSButtonCell`) and a text field's border is    *
 * THE SAME ONE (`NSText`) — matching them is the whole point — so they are named here rather than *
 * written twice: a second copy of `4.0` in the other file is exactly how two borders that are     *
 * supposed to be identical come to differ by a point, and the difference is invisible until       *
 * somebody puts them side by side.                                                                *
 *                                                                                                *
 * THE RADIUS IS THE REGULAR CONTROL SIZE'S, which is the only size this tier draws a bezel for —   *
 * the same footing the bezel's HEIGHT is on (`NSButtonCell`'s `NS_BUTTON_BEZEL_HEIGHT_REGULAR`,    *
 * transcribed from the era's guidelines because no header states it).                              *
 * ============================================================================================ */
#define NS_CELL_BEZEL_RADIUS 4.0
#define NS_CELL_BEZEL_WIDTH  1.0

/* ============================================================================================ *
 * AND THE AIR A CONTROL LEAVES BETWEEN ITS EDGE AND ITS WORDS, FOR THE SAME REASON.                *
 *                                                                                                *
 * A checkbox's label begins one gap after its box and a pop-up's title begins one gap after the    *
 * field's left edge — four points either way, under two different neighbours. They were 4.0 and    *
 * 2.0 until the two controls were put side by side, which is the drift this block exists to stop:  *
 * `NSButtonCell` called it `NS_BUTTON_INDICATOR_GAP`, `NSPopUpButtonCell` called it                *
 * `NS_POPUP_TITLE_INSET`, and neither file could see the other's number.                           *
 *                                                                                                *
 * IT IS A GAP RATHER THAN AN INSET because it is measured from something already drawn — a box, or *
 * a field's border — and not from the frame.                                                       *
 * ============================================================================================ */
#define NS_CELL_CONTENT_GAP 4.0

/* **AND THE AIR A BORDER TAKES, WHICH `NSCell` INSETS ITS DRAWING RECT BY.** It lived in `NSCell.m` until a second
 * class needed it: a field measures its text from its own edge, and `NS_CELL_BORDER_INSET` is what the base has
 * already taken before a subclass's rect begins. Two points, and one name. */
#define NS_CELL_BORDER_INSET   2.0

/* ============================================================================================ *
 * AND THE FIELD-WITH-A-CHIP'S FIVE NUMBERS, WHICH TWO CONTROLS DRAW AND ONE OF THEM DOUBLES.       *
 *                                                                                                *
 * A pop-up button and a combo box are the SAME field with the SAME chip at its right end; what     *
 * differs between them is how many triangles are knocked out of that chip. THE SAMPLE'S NUMBERS:   *
 * its field is 26 points tall, its chip 20 x 20 inset five points from the field's right border,   *
 * each triangle 10 points across and 5 tall, and 2 points between them. Said as FRACTIONS OF THE   *
 * FIELD'S HEIGHT rather than in points, because the chip belongs to the field it is drawn in and a *
 * small control's field is shorter — the same reason the bezel's radius is a constant and a        *
 * button's height is not.                                                                          *
 * ============================================================================================ */
#define NS_CELL_CHIP_FRACTION            0.769 /* 20/26 of the field's height, and square */
#define NS_CELL_CHIP_INSET_FRACTION      0.192 /* 5/26, from the field's right border to the chip's */
#define NS_CELL_CHIP_MARK_WIDTH_FRACTION 0.500 /* of the chip, across */
#define NS_CELL_CHIP_MARK_HEIGHT_FRACTION 0.250 /* of the chip, apex to base */
#define NS_CELL_CHIP_MARK_GAP_FRACTION   0.100 /* of the chip, between a doubled pair */




@interface NSCell : NSObject
{
	/* APPLE'S OWN LAYOUT IS A BITFIELD STRUCT (`struct __CFlags`), and this tier's is plain ivars: the layout is
	 * ours, which is the rule the plan applies to every private field — what must match Apple is the SURFACE. */
	BOOL _enabled;
	BOOL _highlighted;
	BOOL _bordered;
	BOOL _editable;
	/* AND THE STATE THE SECOND SLICE ADDS. The three enums are typed by this file's own typedefs, the six flags are
	 * plain bits, and `_objectValue` is THE ONE THING HERE THAT IS OWNED — a cell retains the value it was given, so
	 * it is the one ivar `-dealloc` has to release. These ivars are written out rather than left to the compiler
	 * because the accessors are hand-written too, and CLANG SYNTHESISES AN IVAR ONLY WHEN IT SYNTHESISES THE
	 * ACCESSORS: a property whose getter and setter are both implemented gets no storage from anyone. */
	BOOL _bezeled;
	BOOL _continuous;
	BOOL _allowsUndo;
	BOOL _allowsEditingTextAttributes;
	BOOL _importsGraphics;
	BOOL _allowsMixedState;
	NSControlSize _controlSize;
	NSControlTint _controlTint;
	NSBackgroundStyle _backgroundStyle;
	id _objectValue;			/* RETAINED */
	/* AND THE FLAGS THE THIRD SLICE ADDS, all plain bits, none needing an initialiser for the reason the enums
	 * did not: OFF is the quiet answer for every one of them, and Objective-C zeroes storage. */
	BOOL _selectable;
	BOOL _scrollable;
	BOOL _wraps;
	BOOL _truncatesLastVisibleLine;
	BOOL _usesSingleLineMode;
	BOOL _sendsActionOnEndEditing;
	BOOL _refusesFirstResponder;
	BOOL _showsFirstResponder;
	BOOL _wantsNotificationForMarkedText;
	BOOL _opaque;
	/* AND WHAT THE CELL IS FOR, one slice later: the target/action pair, the identity, and the two strings this
	 * class OWNS. `_title` and `_keyEquivalent` are RETAINED (they are copies), so they are two more things
	 * `-dealloc` has to release alongside `_objectValue`. */
	id _target;				/* NOT RETAINED: the tree's rule for a target */
	SEL _action;
	NSCellType _type;
	NSString *_title;			/* RETAINED (a copy of what was set) */
	NSInteger _state;
	NSInteger _tag;
	NSString *_keyEquivalent;		/* RETAINED (a copy of what was set) */
	id _menu;				/* NOT RETAINED: a menu outlives the cell that may raise it */
	NSInteger _mouseDownFlags;
	id _controlView;			/* NOT RETAINED */
	/* **AND WHERE THE POINTER IS, WHICH IS THE ONE PIECE OF STATE THIS CLASS HOLDS FOR A FACE IT DOES NOT DRAW.**
	 * Apple's AppKit learns this through `NSTrackingArea` — a class this tier does not ship, which is why
	 * `-addTrackingArea:` here takes an `id` — so the CONTROL catches `-mouseEntered:`/`-mouseExited:` and stores the
	 * answer on the cell, and a cell that wants to look different under the pointer (`NSButtonCell`'s prelight,
	 * and `-showsBorderOnlyWhileMouseInside`'s whole reason for existing) has somewhere to read it. It is a plain
	 * bit because OFF is the quiet answer: a cell with no view in front of it has no pointer over it. */
	BOOL _mouseInside;
	/* AND THE ATTRIBUTE WORD, WHICH IS WHERE `NSCellAttribute` LIVES. That enum has been declared since this class's
	 * first slice and NOTHING STORED IT, so all seventeen of its values were unreadable — a declared vocabulary with
	 * no word to read. One unsigned word, wide enough for the enum's highest position and for the era's `NSInteger`
	 * answer to be handed back without narrowing. */
	unsigned long _cellAttribute;
	/* AND THE ACTION MASK, THE SECOND PIECE OF STATE THIS CLASS HOLDS FOR A LOOP IT DOES NOT HAVE YET: what
	 * `-sendActionOn:` stores is which EVENTS make the cell send its action, and the door that READS it is
	 * `-trackMouse:inRect:ofView:untilMouseUp:` — a modal tracking loop, owed with the rest of that family. THE MASK
	 * LANDS NOW BECAUSE THE ACCESSOR IS APPLE'S OWN and a caller can already set it; see the implementation. */
	NSInteger _actionMask;
	/* AND THE MNEMONIC, WHICH THIS CLASS DERIVES RATHER THAN STORES — the reading `NSMenuItem` already ships one
	 * class over: `_mnemonicLocation` is the index into the title of the character a caller marked, or `NSNotFound`
	 * when there is none, and `-mnemonic` reads the character OUT of the title at that index rather than keeping a
	 * second copy that could drift. **IT IS THE ONE DEFAULT IN THIS CLASS WHOSE ZERO IS A LIE**: index 0 is a
	 * perfectly good mnemonic (the title's first character), so `-init` has to say `NSNotFound` out loud — the same
	 * trap the four starting flags taught, in the one place a zero is not merely wrong but plausible. */
	NSUInteger _mnemonicLocation;
	/* AND THE IMAGE THE CELL SHOWS — the state `NSImageCellType` is FOR, and the third thing this class owns beside
	 * `_objectValue` and the two strings. **IT IS RETAINED, WHICH IS THIS TREE'S RULE FOR AN IMAGE**: a caller hands
	 * one over and keeps using it, `NSMenuItem` holds its own `_image` the same way, and neither copies it. AND THE
	 * POINTER TYPE NEEDS NO DECLARATION OF ITS OWN — `NSView.h`, which this header imports, forward-declares
	 * `NSImage`, and the implementation imports the real header. */
	NSImage *_image;
	/* **AND THE FORMATTER, THE FIFTH THING THIS CLASS OWNS — and the only one of the five whose ownership rule is
	 * APPLE'S stated one rather than this tree's.** A retained-and-not-copied image is this tree's own choice; a
	 * formatter is RETAINED because Apple's Data Formatting Guide says so in as many words ("when a cell with a
	 * formatter object is copied, the new cell retains the formatter object rather than copying it"), and the reason
	 * it gives there is the reason here: a formatter is immutable, so a copy would be an equal object the caller
	 * could not recognise as its own.
	 *
	 * IT IS THE OBJECT THAT TURNS THE VALUE INTO TEXT AND THE USER'S TEXT BACK INTO A VALUE, which is why
	 * `-stringValue` consults it and why assigning one RE-INTERPRETS what is already in the cell. Both halves are
	 * doors below, beside the value they act on, and both are Apple's documented sentences rather than readings of
	 * them. A nil formatter is the documented "no formatter", so the storage's own zeroing is the answer and `-init`
	 * says nothing about it — the third default in this class that costs no line. See appkit-plan.md §A10bm. */
	NSFormatter *_formatter;
	/* **AND THE FONT THE TITLE IS SET IN, RETAINED, WHICH THE DRAWING SLICE ADDS.** It is the sixth owned thing in
	 * this class beside the value, the two strings, the image and the formatter, and it is the one a TITLE cannot
	 * be drawn without — see the header. */
	id _font;
	/* **AND THE LAYOUT STATE — FIVE VALUES, TWO OF WHOSE DEFAULTS ARE NOT ZERO.** The line-break mode, the focus ring
	 * and the user interface layout direction all start at the first member of their type, which IS zero, so the
	 * storage's own zeroing is the documented answer. THE OTHER TWO ARE NOT: `-alignment`'s documented default is
	 * `NSNaturalTextAlignment` — 4, the fifth case, "the default alignment for script" — and `-baseWritingDirection`'s
	 * is `NSWritingDirectionNatural`, which is `-1`. So `-init` writes both out by hand, the third and fourth times this
	 * class has had to say a default that Objective-C's zeroing would get wrong, after the four starting flags and
	 * `NSNotFound`. */
	NSTextAlignment _alignment;
	NSLineBreakMode _lineBreakMode;
	NSWritingDirection _baseWritingDirection;
	NSFocusRingType _focusRingType;
	NSUserInterfaceLayoutDirection _userInterfaceLayoutDirection;
	/* **AND THE DEPRECATED ENTRY TYPE, WHICH IS AN `NSInteger` RATHER THAN ONE OF THIS FILE'S TYPEDEFS** — the era's
	 * spelling for it (`int` in 10.2 and `NSInteger` from 10.5 on), and the reason the "Data Entry Types" vocabulary
	 * at the top of this file is an ANONYMOUS enum: a cell answers the NUMBER, not a named type. ITS DEFAULT IS THE
	 * STORAGE'S ZERO, WHICH THE VOCABULARY ITSELF SPELLS `NSAnyType` — "any value is allowed" — so `-init` says
	 * nothing about it, and that is the difference between it and the four starting flags and `NSNotFound`. See
	 * appkit-plan.md §A10bn. */
	NSInteger _entryType;
}

/* **AND ITS TWO DOORS, DECLARED HERE BESIDE THE WORD THEY READ RATHER THAN IN THE DOORS SECTION BELOW** — the one
 * place in this header where a door is not with its siblings, and the reason is that the word and its doors arrived
 * together as ONE FEATURE: `NSCellAttribute` was a vocabulary nothing could read until `_cellAttribute` existed, so
 * separating the declaration from the storage would have separated the two halves of a single gap being closed.
 *
 * AND THE SETTER'S SELECTOR IS `-setCellAttribute:to:`, WHICH IS THE ERA'S SPELLING AND NOT THE ONE A GUESS PICKS.
 * The 10.2 SDK declares `to:(int)value` and the 10.5 SDK declares THE SAME SELECTOR with `NSInteger` — Apple renamed
 * the TYPE between those two eras and left the selector alone. That is what fetching the era settles and memory does
 * not (appkit-plan.md §A10ba). */
- (NSInteger)cellAttribute:(NSCellAttribute)aParameter;
- (void)setCellAttribute:(NSCellAttribute)aParameter to:(NSInteger)value;

/* AND THE ACTION MASK'S ONE DOOR, whose READER IS THE TRACKING LOOP THIS TIER HAS NOT WRITTEN (see the storage
 * above). It carries the era's signature exactly — `NSInteger` in, `NSInteger` out — and THE OUT IS THE MASK THAT WAS
 * THERE, because that is the one thing the signature settles on its own: a caller must be able to put a mask back
 * without having asked for it first. */
- (NSInteger)sendActionOn:(NSInteger)mask;

/* **AND TWO DOORS ABOUT BEING PRESSED, WHICH ARE THE LAST PART OF THIS CLASS THAT NEEDS NO INK.** Both carry the
 * era's own signatures (10.6, fetched in §A10ba): `-highlight:withFrame:inView:` is what a control calls while the
 * mouse is down, and `-performClick:` is what it calls for a keyboard equivalent.
 *
 * AND THE FIRST IS A HALF DOOR OF THE KIND THIS TIER HAS EVERYWHERE — THE STATE IS REAL AND THE DRAWING IS NOT.
 * Setting `highlighted` is behaviour a caller can observe and every other door in this class already asks about;
 * the greying of the cell's face inside the frame is ink. A HALF DOOR IS ONLY HONEST IF IT SAYS WHICH HALF, so the
 * refused half is named in the implementation, where a reader looking for the drawing will find it and not have to
 * infer it from a frame parameter that is never read. */
- (void)highlight:(BOOL)flag withFrame:(NSRect)cellFrame inView:(nullable id)controlView;
- (void)performClick:(nullable id)sender;

/* **AND WHERE THE POINTER GOES OVER A CELL, WHICH IS THE ONE DOOR IN THIS CLASS WHOSE CONTRACT CAME FROM APPLE'S
 * DOCUMENTATION RATHER THAN FROM A HEADER** — all three eras declare it and none of them says what it does. It is
 * declared here BESIDE THE TWO PRESSED DOORS rather than with the drawing, because it is a control's hook: the view
 * calls it from `-resetCursorRects`, and the cell answers by handing a cursor rect back to that view.
 *
 * THE CONTROL VIEW IS NULLABLE BECAUSE THE IMPLEMENTATION TAKES NIL AS THE QUIET CASE, which is this class's
 * standing answer for a sender that is not there — see appkit-plan.md §A10bg for the fetched contract and the probe
 * that checks both halves. */
- (void)resetCursorRect:(NSRect)cellFrame inView:(nullable NSView *)controlView;

/* THE FOUR DOORS. Each is a field with a question's name — `-isEnabled` and not `-enabled`, Apple's spelling, and
 * the property carries the `getter=` so both ends are named where the ledger can see them. */
@property (getter=isEnabled) BOOL enabled;
- (void)setEnabled:(BOOL)flag;
@property (getter=isHighlighted) BOOL highlighted;
- (void)setHighlighted:(BOOL)flag;
@property (getter=isBordered) BOOL bordered;
- (void)setBordered:(BOOL)flag;
@property (getter=isEditable) BOOL editable;
- (void)setEditable:(BOOL)flag;

/* **AND THE TWO DOORS THE TIER ADDS, WHICH ARE HOW A CELL LEARNS WHERE THE POINTER IS.** They are spelled `cg_`
 * because they are this tree's, exactly as `-cg_clearDirtyRegion` on `NSView` is: APPLE HAS NO SUCH PAIR, because
 * `NSTrackingArea` is the class that carries this fact on the other platform and this tier does not ship it. The
 * CONTROL is what calls the setter — from the `-mouseEntered:`/`-mouseExited:` the WINDOW synthesises out of the
 * pointer's motion — and the getter is what a face reads: `NSButtonCell`'s prelight, and
 * `-showsBorderOnlyWhileMouseInside`, whose entire meaning is this one bit.
 *
 * IT IS ON THE BASE CLASS RATHER THAN ON THE BUTTON'S CELL because it is a fact about the pointer and the control,
 * not about any face: a checkbox, a slider and a text field are all equally "under the pointer or not", and a
 * subclass that finds a use for it should not have to ask its control for a second copy of the answer. */
- (BOOL)cg_mouseIsInside;
- (void)cg_setMouseInside:(BOOL)flag;

/* **AND THE ONE HOOK A TRACKING LOOP ASKS ON ITS OWN CLOCK: HAS THE CELL SOMETHING MORE TO SAY?** A press that
 * STEPS — a scroller's page or a line — goes on stepping while the button is held, and the control's tracking loop
 * is the only thing that knows time is passing: it wakes on a deadline whether or not an event arrived, so it is the
 * one place the question can be asked. THE CELL OWNS THE TIMING and the loop only polls, because the numbers (the
 * delay before the first repeat and the interval after it) belong to the control that repeats and not to the loop
 * that pumps. The default answers NO, which is every cell with nothing to repeat. */
- (BOOL)cg_trackingShouldRepeat;

/* ============================================================================================ *
 * AND THE REST OF THE STATE, WHICH IS THE SAME SHAPE AND TWO MORE KINDS.                        *
 * ============================================================================================ */

/* THE SIX FLAGS, each a field with a question's name where Apple spells one, and EACH SETTER DECLARED AS WELL AS
 * ITS PROPERTY — the ledger holds a row for every setter BY NAME, which is the lesson this plan has recorded three
 * times and is not going to record a fourth. */
@property (getter=isBezeled) BOOL bezeled;
- (void)setBezeled:(BOOL)flag;
@property (getter=isContinuous) BOOL continuous;
- (void)setContinuous:(BOOL)flag;
@property BOOL allowsUndo;
- (void)setAllowsUndo:(BOOL)flag;
@property BOOL allowsEditingTextAttributes;
- (void)setAllowsEditingTextAttributes:(BOOL)flag;
@property BOOL importsGraphics;
- (void)setImportsGraphics:(BOOL)flag;
@property BOOL allowsMixedState;
- (void)setAllowsMixedState:(BOOL)flag;
/* AND A QUESTION WITH NO SETTER, which is Apple's shape rather than an omission: whether a cell wants the first
 * click is the cell's own business, so nothing outside it sets the answer. */
@property (readonly) BOOL acceptsFirstResponder;

/* THE THREE ENUMS, TYPED BY THE typedefs AT THE TOP OF THIS FILE — which is exactly why the types had to ship
 * first: these doors could not be declared at all without them. */
@property NSControlSize controlSize;
- (void)setControlSize:(NSControlSize)size;
@property NSControlTint controlTint;
- (void)setControlTint:(NSControlTint)tint;
@property NSBackgroundStyle backgroundStyle;
- (void)setBackgroundStyle:(NSBackgroundStyle)style;

/* ============================================================================================ *
 * AND THE FLAGS A CONTROL AND ITS USER DRIVE, NONE OF WHICH NEEDS INK.                           *
 * ============================================================================================ */

/* TEN FLAGS, AND ONE OF THEM HAS BEHAVIOUR RATHER THAN STORAGE: `-setScrollable:` SETS `wraps` TO NO, which the
 * era header spells out in the setter's own comment and which the probe asserts — a cell that scrolls cannot also
 * wrap, because the two describe the same axis. The rest are plain state, and each setter is declared as well as
 * its property for the reason this class now says three times: the ledger holds a row for a SETTER's name. */
@property (getter=isSelectable) BOOL selectable;
- (void)setSelectable:(BOOL)flag;
@property (getter=isScrollable) BOOL scrollable;
- (void)setScrollable:(BOOL)flag;
@property BOOL wraps;
- (void)setWraps:(BOOL)flag;
@property BOOL truncatesLastVisibleLine;
- (void)setTruncatesLastVisibleLine:(BOOL)flag;
@property BOOL usesSingleLineMode;
- (void)setUsesSingleLineMode:(BOOL)flag;
@property BOOL sendsActionOnEndEditing;
- (void)setSendsActionOnEndEditing:(BOOL)flag;
@property BOOL refusesFirstResponder;
- (void)setRefusesFirstResponder:(BOOL)flag;
@property BOOL showsFirstResponder;
- (void)setShowsFirstResponder:(BOOL)flag;
@property BOOL wantsNotificationForMarkedText;
- (void)setWantsNotificationForMarkedText:(BOOL)flag;
@property (getter=isOpaque) BOOL opaque;
- (void)setOpaque:(BOOL)flag;

/* AND THE ONE QUESTION THAT BELONGS TO THE CLASS RATHER THAN AN INSTANCE, which is why it is spelled `+`: whether
 * a cell prefers to track the mouse until the button comes up is a property of the KIND of cell. */
+ (BOOL)prefersTrackingUntilMouseUp;

/* AND A DOOR THAT DERIVES ITS ANSWER RATHER THAN STORING ONE: the style of surface behind the cell's own interior
 * differs from `backgroundStyle` when the cell draws a bezel, so the interior is one step away from the background
 * and this says so instead of repeating it. */
@property (readonly) NSBackgroundStyle interiorBackgroundStyle;

/* ============================================================================================ *
 * AND WHAT A CELL IS FOR: its identity, the action it sends, and the menu it may raise.          *
 * ============================================================================================ */

/* THE TARGET/ACTION PAIR, which is what a control does WITH a cell: the object and the selector. `target` is an
 * `id` and NOT retained — the tree's rule for a target everywhere, since an owner that retained its target could
 * not be freed while the target lived. */
@property (nullable, assign) id target;
- (void)setTarget:(nullable id)anObject;
@property (nullable) SEL action;
- (void)setAction:(nullable SEL)aSelector;

/* THE CELL'S IDENTITY: which KIND it is, its title, the tag a caller hangs on it, and the state a user drives —
 * and the type is this file's own typedef, which is the third time that ordering has paid for itself. */
@property NSCellType type;
- (void)setType:(NSCellType)aType;
@property (copy) NSString *title;
- (void)setTitle:(NSString *)aString;
@property NSInteger state;
- (void)setState:(NSInteger)value;
@property NSInteger tag;
- (void)setTag:(NSInteger)anInt;

/* **AND THE FOUR DOORS OF APPLE'S `NSKeyboardUI` CATEGORY — the one family in this class whose rule this tree had
 * ALREADY decided before this class existed.** `NSMenuItem` parses a mnemonic out of a title and its probe protects
 * the behaviour, so these doors are that rule rather than a fresh reading of it, and the era's own parameter name
 * states it: `-setTitleWithMnemonic:` takes a `stringWithAmpersand`. What the era header settles, and what a mirror
 * of `NSMenuItem` would have got WRONG, is the RETURN TYPE — `-mnemonic` answers an `NSString *` on a cell where the
 * menu item answers a `unichar`, so the same rule has two spellings in this tree. Apple documents the returns: the
 * location is an index into the title or `NSNotFound`, and the mnemonic is the character "or an empty string if no
 * mnemonic character is set" — which is why this door answers `@""` rather than nil.
 *
 * AND THE PAIR IS A RELATION RATHER THAN TWO FIELDS, which is the half that goes wrong if it is treated as storage:
 * the location is an INDEX INTO THE TITLE, so a new title clears it. `NSMenuItem` ships that invariant and its probe
 * asserts it; `-setTitle:` below does the same here, and the implementation says so where the clearing happens.
 *
 * APPLE'S OWN DOCUMENTATION CALLS `-setTitleWithMnemonic:` DEPRECATED — "Mnemonics are not supported in macOS" — AND
 * NEITHER GROUND THIS TREE GATES ON DOES: the 10.6 header declares it plainly, and the modern index carries no
 * attribute for it (it flags the `-entryType` family instead). So the row is OWED in both ledgers rather than struck,
 * and `-strict` is clean with these declared. Recorded here rather than acted on: the gate is the ledger. */
- (void)setMnemonicLocation:(NSUInteger)location;
- (NSUInteger)mnemonicLocation;
- (NSString *)mnemonic;
- (void)setTitleWithMnemonic:(nullable NSString *)stringWithAmpersand;
/* AND A DOOR THAT WALKS THE STATE RATHER THAN SETTING IT, which is why it is not a setter: `-setNextState` CYCLES,
 * and the cycle's length depends on whether the cell allows a mixed state — so its behaviour is this class's and
 * not its caller's. */
- (void)setNextState;

/* AND THE INITIALISER, DECLARED HERE BECAUSE THE LEDGER ASKS FOR A DECLARATION RATHER THAN A DEFINITION. The
 * implementation has been in this class since its first slice; the header never named it, so the row stood OPEN with
 * the behaviour already shipped — the same shape of UNDER-CREDIT §A10ax found one class over, where a row was open
 * because a spelling differed rather than because anything was missing. */
- (instancetype)init;

/* **AND THE TWO DESIGNATED INITIALISERS — THE DOORS THAT DECIDE WHAT KIND OF CELL THIS IS**, which is why Apple calls
 * them designated and why `-init` is not one of them. Both are published contracts rather than guesses:
 * `-initTextCell:` makes the receiver a TEXT cell whose title is the string, `-initImageCell:` makes it an IMAGE cell
 * holding the image. THE TYPE IS THE POINT OF EACH — until this unit a caller who wanted an image cell had no door to
 * make one with (`-setType:` stores a kind, and `-image` did not exist to fill it).
 *
 * AND TWO DEFAULTS ARE DOCUMENTED, WHICH IS WHY THEY ARE SPELLED OUT RATHER THAN LEFT TO ZERO: a text cell made with
 * a NIL string gets the title `"Cell"` — the OpenStep Programming Reference says so in this door's own words ("its
 * title is set to aString, or "Cell" if aString is NULL") and repeats the value under `-setType:` — and an image cell
 * made with a nil image gets NO image, which is Apple's own modern sentence ("if nil, no image is set").
 *
 * AND THE SECOND OF THOSE IS A STATED DIVERGENCE, NAMED WHERE THE DOOR IS: OpenStep says a nil image leaves the cell
 * with a DEFAULT ICON, `NSsquare16`, and that is refused by name in the implementation, because a named image needs
 * the image catalog this tier does not have.
 *
 * AND A THIRD DUTY APPLE STATES IS DISCHARGED BY A FACT RATHER THAN A LINE: both doors "set the cell to have the
 * cell's default menu", which is `+defaultMenu` — shipped, and answering nil here, because a default menu belongs to
 * a view hierarchy no cell in this tier is drawn into. */
- (instancetype)initTextCell:(nullable NSString *)aString;
- (instancetype)initImageCell:(nullable NSImage *)image;

/* **AND THE IMAGE ITSELF, WHICH IS THE STATE `NSImageCellType` IS FOR — AND THE ERA'S SPELLING IS THE ACCESSOR PAIR
 * RATHER THAN A PROPERTY.** That is not a style preference: the era ledgers hold `- image` as a METHOD row, and the
 * sweep credits a method only when the OWNER declares that whole selector — so a `@property` alone left the row a
 * STALE SHIPPED CLAIM the moment it was flipped, which is exactly what `--check` said. `NSMenuItem` declares its own
 * image the same way. RETAINED, which is this tree's rule for an image, and a nil image is the documented "no image"
 * rather than an error. */
- (nullable NSImage *)image;
- (void)setImage:(nullable NSImage *)anImage;

/* AND THE FIRST FAMILY IN THIS CLASS THAT NEEDS NOTHING BUT OBJECTIVE-C. A `-take*ValueFrom:` door reads a value OFF
 * ANOTHER OBJECT and puts this cell's own coercion of it into the cell: THERE IS NO INK IN ANY OF THEM and no enum
 * either, which is why they are the slice that follows the types and the state.
 *
 * THE SENDER IS TYPED `id` BECAUSE THE QUESTION IS NOT ABOUT A CLASS: a value-taking door asks its sender for
 * `-intValue` or `-stringValue`, and the sender's only duty is to answer — the coercion is the cell's. That is also
 * why `-takeObjectValueFrom:` and `-takeStringValueFrom:` can disagree about the same sender and both be right. */
- (void)takeIntValueFrom:(nullable id)sender;
- (void)takeIntegerValueFrom:(nullable id)sender;
- (void)takeFloatValueFrom:(nullable id)sender;
- (void)takeDoubleValueFrom:(nullable id)sender;
- (void)takeStringValueFrom:(nullable id)sender;
- (void)takeObjectValueFrom:(nullable id)sender;

/* AND THE STATE CYCLE'S OTHER END, WHICH IS A GETTER THE ERA SPELLS AS A METHOD rather than a property — the same
 * lesson `NSMenuItemCell`'s `-tag` taught and §A10az records: the 10.6 header declares `- (NSInteger)nextState;`
 * with the comment "get next state state in cycle". It answers what the cycle WOULD produce; `-setNextState` is what
 * stores it; and the arithmetic behind both is written once, in the implementation. */
- (NSInteger)nextState;

/* AND WHAT A CELL CARRIES FOR SOMEBODY ELSE: an object whose MEANING belongs to the caller, an optional key
 * equivalent, and the context menu a cell may raise. THE MENU IS TYPED `id` WHERE APPLE TYPES NSMenu, and the
 * reason is the mirror of the over-crediting rule rather than the rule itself: NSMenu IS in this tree, so naming it
 * would be no over-credit — but this header does not include NSMenu.h, and pulling a framework's menu inventory
 * into every cell that includes this file is a cost with no reader. */
@property (nullable, retain) id representedObject;
- (void)setRepresentedObject:(nullable id)object;
@property (nullable, copy) NSString *keyEquivalent;
- (void)setKeyEquivalent:(NSString *)aString;
@property (nullable, assign) id menu;
- (void)setMenu:(nullable id)aMenu;
/* AND THE CLASS'S OWN DEFAULT MENU, which is a question about the KIND — and the answer here is nil, because a
 * default menu belongs to a VIEW hierarchy this tier's cells are not yet drawn into. */
+ (nullable id)defaultMenu;

/* AND TWO THINGS ABOUT INPUT. The mouse-down flags are stored (they are the modifiers of the event that started
 * the current tracking); `controlView` is the view a cell draws into, typed `id` for the same reason `menu` is. */
@property NSInteger mouseDownFlags;
- (void)setMouseDownFlags:(NSInteger)flags;
@property (nullable, assign) id controlView;
- (void)setControlView:(nullable id)view;

/* ============================================================================================ *
 * AND THE ONE OBJECT A CELL CARRIES, WITH THE FIVE COERCIONS APPLE DERIVES FROM IT.              *
 * ============================================================================================ */

/* `objectValue` IS THE CELL'S VALUE AND THERE IS ONLY ONE OF IT: the five typed answers below are DERIVED, not
 * stored, because a cell holding `@"42"` *is* 42 — Apple's shape, and the reason a cell needs one object rather
 * than five fields. THE OBJECT IS RETAINED (a cell owns what it was given) and is the only thing in this class that
 * has to be released. */
@property (nullable, retain) id objectValue;
- (void)setObjectValue:(nullable id)value;
@property (readonly) BOOL hasValidObjectValue;
@property (readonly, nullable) NSString *stringValue;
@property (readonly) int intValue;
@property (readonly) float floatValue;
@property (readonly) double doubleValue;
@property (readonly) NSInteger integerValue;

/* **AND THE FIVE TYPED SETTERS — THE HALF OF THIS FAMILY THAT CARRIES A DOCUMENTED TYPE RULE.** The getters above
 * answer QUESTIONS about the one value; these five WRITE it, and the era's contract (the 10.6-era class reference,
 * and the OpenStep reference behind it) is not one rule but TWO:
 *
 *   * `-setStringValue:` COPIES the string and, IF THE CELL IS NOT A TEXT CELL, CONVERTS IT TO ONE. The same sentence
 *     gives that conversion a font — the system font at 12.0 points — and the font half is refused by name in the
 *     implementation: ⚠ **NOT BECAUSE "A FONT IS INK IN THIS TIER", WHICH THIS FILE USED TO SAY AND WHICH IS FALSE.**
 *     THE ENGINE IS HERE — `CGFont` over FreeType with metrics, advances and glyph outlines, `CGFontCreateWithFontName`
 *     resolving a name to a face over a real registry, the whole `CGContext` text surface, and `NSGraphicsContext`'s
 *     `-CGContext` to reach it — and what is missing is the `NSFont` OBJECT, because AppKit's font class has not been
 *     written. That is a LAYER and not a capability. See appkit-plan.md §A10bt, which retracts the claim everywhere it
 *     was written.
 *   * THE FOUR NUMERIC SETTERS DO NOTHING IF THE RECEIVER IS NOT A TEXT CELL: "does nothing if the receiver isn't a
 *     text cell" is stated for `-setIntValue:`, `-setFloatValue:` and `-setDoubleValue:`, and `-setIntegerValue:`
 *     (10.5 and later) says the same of itself. Their other clause — "ignoring the cell entry type" — is about the
 *     ENTRY TYPE and not about the cell's kind. ⚠ **AND THAT HALF-SENTENCE USED TO END "a deprecated vocabulary this
 *     tier does not have", WHICH WAS WRONG**: the vocabulary has been declared in this file since its FIRST SLICE —
 *     the seven constants at the top of it, all seven of whose `case` rows are shipped. What was missing was the DOOR
 *     that reads it, and §A10bn brought the door and retired the note.
 *
 * SO THE ASYMMETRY IS THE CONTRACT, AND THE PROBE ASSERTS BOTH SIDES OF IT: assigning TEXT turns a null cell into a
 * text cell; assigning a NUMBER to one does nothing at all. A reader who assumed the five were one shape would have
 * written the opposite for both, which is why the rule is stated here rather than left to the implementation. */
- (void)setStringValue:(nullable NSString *)aString;
- (void)setIntValue:(int)anInt;
- (void)setIntegerValue:(NSInteger)anInteger;
- (void)setFloatValue:(float)aFloat;
- (void)setDoubleValue:(double)aDouble;

/* **AND THE FORMATTER — THE ONE DOOR PAIR THAT CHANGES WHAT `-stringValue` ANSWERS.** Apple declares it in the same
 * cluster as the value doors (between `-keyEquivalent` and `-objectValue` in the 10.6 header), and that placement is
 * the statement the doors themselves make: a formatter is not an ornament on a cell, it is the object the cell's
 * value is READ THROUGH.
 *
 * IT DOES THREE DOCUMENTED THINGS RATHER THAN ONE, which is why it is not a plain setting:
 *
 *   * THE CELL RETAINS IT AND DOES NOT COPY IT. Apple's Data Formatting Guide says so in as many words ("when a cell
 *     with a formatter object is copied, the new cell retains the formatter object rather than copying it"), and the
 *     reason it gives is the reason here: a formatter is immutable, so a copy would be an equal object the caller
 *     could not recognise as its own. It is therefore the fifth thing this class owns, beside the value, the title,
 *     the key equivalent and the image.
 *   * IT IS WHAT `-stringValue` ASKS. "When the cell needs to display or edit its value, it passes its object to the
 *     formatter which returns the formatted string" — so with a formatter set that door answers
 *     `-stringForObjectValue:`, and with none it keeps the answer it shipped with (the object's own `-description`,
 *     §A10bj). Nothing that was already measured changes: this unit ADDS a branch.
 *   * AND ASSIGNING ONE RE-INTERPRETS THE VALUE ALREADY IN THE CELL: "the formatter attempts to interpret the cell's
 *     current value. If it cannot do so, the formatter converts the current value to a string object." That sentence
 *     does not say WHAT the formatter is handed, so the reading this unit takes — the current value's TEXT, through
 *     the protocol's string-to-object half, with the text left standing when the interpretation fails — is written
 *     out at the implementation rather than assumed. A door that guessed silently would rewrite a caller's value the
 *     moment a formatter was attached.
 *
 * AND THE RETURN TYPE IS THIS TREE'S `NSFormatter *` RATHER THAN THE ERA'S `id`: the two are source-compatible at
 * every call site, this tree HAS the class (Foundation F13, so the era's forward declaration is not needed here), and
 * the modern index's row for it is a typed property. Naming it is the blanket rule rather than a liberty.
 *
 * AND THE PAIR IS DECLARED AS ACCESSORS RATHER THAN A `@property` FOR THE REASON §A10bi MEASURED: the era ledgers
 * hold `- formatter` and `- setFormatter:` as METHOD rows, and the sweep credits a method only when the owner
 * declares that whole selector — which a `@property` does not do. The modern property row is credited by the same
 * pair, which is what §A10bl proved five doors over. */
- (nullable NSFormatter *)formatter;
- (void)setFormatter:(nullable NSFormatter *)newFormatter;

/* **AND THE FOUR `NSCellHit*` CONSTANTS, WHICH THIS FILE'S FIRST SLICE LEFT ABSENT ON PURPOSE AND WHICH HAVE NOW
 * ARRIVED** — the block that declares them has been read, and it carries the values AND the era's own account of what
 * each means and what the default implementation answers for each kind of cell. "A guessed constant is worse than an
 * absent one" was the rule that kept those four rows open; READING THE BLOCK IS WHAT CLOSES THEM, and nothing cheaper
 * would have.
 *
 * THE VALUES ARE A BITMASK RATHER THAN A SEQUENCE — 0, 1, 2, 4 — which is why they are transcribed instead of numbered
 * in order, and why the era's own comment says a caller should "use a bit-wise mask to look for a specific value" when
 * it calls the door. THE RETURN TYPE IS `NSUInteger`, WHICH IS THE ERA'S OWN SPELLING: the modern ledger has since
 * STRUCK the name `NSCellHitResult` as after-10.6, so declaring a type by that name would be declaring a struck row —
 * the same instrument rule §A10bf records, one level over.
 *
 * AND THE DOOR THEY ARE FOR, WHOSE CONTRACT IS THE ERA'S OWN COMMENT RATHER THAN A GUESS: "By default, NSCell will look
 * at the cell type" — an image cell answers on its image, a text cell on its text (adding the editable area when the
 * cell is enabled), and a NULL cell answers `NSCellHitContentArea` unconditionally, adding the trackable area "if the
 * cell not disabled, and it would track". The implementation decides every branch this class can decide and NAMES the
 * two it cannot, which is what makes it a HALF DOOR rather than a stub. */
enum {
	NSCellHitNone = 0,
	NSCellHitContentArea = 1 << 0,
	NSCellHitEditableTextArea = 1 << 1,
	NSCellHitTrackableArea = 1 << 2
};
- (NSUInteger)hitTestForEvent:(NSEvent *)event inRect:(NSRect)cellFrame ofView:(nullable NSView *)controlView;

/* **AND THE LAYOUT STATE'S DOORS — FIVE PIECES OF STATE, WRITTEN OUT IN THE ERA'S OWN SPELLING BECAUSE APPLE DECLARES
 * THEM AS ACCESSOR PAIRS RATHER THAN PROPERTIES** (the era's `NSCell.h` is accessor-based, and the modern index's
 * `property` rows for all five are satisfied by the same pair — which is why both are declared here and neither is a
 * `@property`). The signatures are transcriptions, including the two whose types differ in SIGNEDNESS:
 * `-alignment` answers an `NSUInteger`-based `NSTextAlignment` while `-baseWritingDirection` answers an
 * `NSInteger`-based `NSWritingDirection`, because one of that type's cases is `-1`.
 *
 * AND THE FIRST TWO DOORS ARE THE ONES WITH SOMETHING TO GET WRONG: THE DEFAULTS OF `-alignment` AND
 * `-baseWritingDirection` ARE NOT THEIR ZERO. Apple's own class reference states both — "the default value is
 * `NSNaturalTextAlignment`" and "the default value is `NSWritingDirectionNatural`" — and neither the era header nor any
 * comment in it says anything, so a reader who took the storage's zeroing for the answer would ship a cell that
 * announces the WRONG ALIGNMENT for every script it is asked about. The other three doors' defaults ARE their zero, and
 * the implementation says so by not touching them.
 *
 * AND ONE ROW THIS DECLARATION CANNOT FLIP, RECORDED HERE RATHER THAN DISCOVERED LATER: the modern ledger holds
 * `+defaultFocusRingType` as a `property` ROW whose credit test is an INSTANCE accessor, and Apple declares it a CLASS
 * method — so no honest declaration in this file can satisfy that test, and the row stays open. It is the same shape as
 * the `category` rows (§A10bh): the file says what the artefact carries, and the artefact's shape is not the surface's.
 * THE DOOR IS DECLARED ALL THE SAME, because it is Apple's API and the era's row for it is a METHOD row that flips. */
- (NSTextAlignment)alignment;
- (void)setAlignment:(NSTextAlignment)mode;
- (NSLineBreakMode)lineBreakMode;
- (void)setLineBreakMode:(NSLineBreakMode)mode;
- (NSWritingDirection)baseWritingDirection;
- (void)setBaseWritingDirection:(NSWritingDirection)writingDirection;
- (NSFocusRingType)focusRingType;
- (void)setFocusRingType:(NSFocusRingType)focusRingType;
+ (NSFocusRingType)defaultFocusRingType;
- (NSUserInterfaceLayoutDirection)userInterfaceLayoutDirection;
- (void)setUserInterfaceLayoutDirection:(NSUserInterfaceLayoutDirection)layoutDirection;

/* ============================================================================================ *
 * AND THE SIZE TRIO — AND THE THREE RECT DOORS THIS PLAN REFUSES BECAUSE THE DOCUMENTATION IS   *
 * QUALITATIVE RATHER THAN WRONG.                                                                *
 * ============================================================================================ */

/* **THE FIRST TWO OF THESE ARE ONE FAMILY, THEY ARE ASKED THE SAME QUESTION, AND THEY ANSWER DIFFERENTLY — WHICH IS
 * THE TRAP AND THE REASON THEY ARE DECLARED TOGETHER.** Apple's own table, which THREE INDEPENDENT VINTAGES agree on
 * (the current `cellSize` page, the archived 10.0-era `NSCell` class reference, and the Java bridge shipped with the
 * same SDK):
 *
 *     cell kind                        `-cellSize`                `-cellSizeForBounds:`
 *     neither text nor image           (10000, 10000)             the size of the RECT passed in
 *     image cell with NO image         NSZeroSize                 NSZeroSize
 *     image cell WITH an image         content size + border      content size constrained to the rect
 *     text cell                        content size + border      the text resized to fit the rect
 *
 * SO A CELL WITH NO CONTENT CLAIMS TEN THOUSAND POINTS SQUARE FROM ONE DOOR AND THE CALLER'S OWN RECT FROM THE OTHER,
 * and an image cell with no image is the ONLY branch the two share. The sentinel is not a size at all: it is the
 * class's published way of saying "I have no opinion", and it is the third empty answer this class's units have met
 * (§A10bo's `NSZeroRect` and `nil`) and the only one that is a LARGE number rather than a small one — which is why a
 * caller who tests `size.width == 0` for "no opinion" gets the image-cell case right and the null-cell case wrong.
 *
 * AND THE TWO CONTENT BRANCHES ARE REFUSED BY NAME, EACH BECAUSE ITS NUMBER IS PUBLISHED NOWHERE THIS PLAN MAY READ:
 * a TEXT cell's size is its title's measured extent and needs the FONT the whole geometry family is blocked on; an
 * IMAGE cell's is "the size of the image ... within a certain offset determined by the border type of the cell", and
 * THAT OFFSET IS A PHRASE, not a number, in every vintage — the image's own `-size` IS available (`NSImage` ships it),
 * so the refused part is precisely the offset. A refused branch answers `(10000, 10000)`, THE CLASS'S OWN PUBLISHED
 * "NO OPINION" SENTINEL, rather than a zero a caller could mistake for a measurement: a text cell answering NSZeroSize
 * would read as an image cell with no image, and a WRONG rect in a control is the one outcome this plan's refusal rule
 * exists to prevent.
 *
 * AND THE THIRD DOOR OF THE TRIO IS A DOCUMENTED NO-OP, which is why it is declared here rather than left out: Apple
 * says subclasses implement it "to recalculate drawing sizes" and that "the default implementation does nothing", and a
 * CONTROL CALLS IT BEFORE DISPLAY once a cell has been marked modified — so the call must be ANSWERED. This class
 * computes `-cellSize` on demand instead, which is why the door can ignore its rect and still be right. */
- (NSSize)cellSize;
- (NSSize)cellSizeForBounds:(NSRect)aRect;
- (void)calcDrawInfo:(NSRect)aRect;

/* ============================================================================================ *
 * AND THE THREE TRACKING HOOKS — THE DOORS A SUBCLASS OVERRIDES, AND THE ONE DOOR THAT WOULD    *
 * DRIVE THEM, WHICH IS REFUSED.                                                                 *
 * ============================================================================================ */

/* **THE THREE ARE ONE FAMILY: THE HOOKS AN `NSCell` SUBCLASS OVERRIDES TO GIVE A CELL A DRAG BEHAVIOUR, AND THEY
 * SHIP TOGETHER OR NOT AT ALL.** Apple's own sentence about the fourth door says why — `-trackMouse:inRect:ofView:
 * untilMouseUp:` is "generally not overridden because the default implementation invokes other `NSCell` methods that
 * can be overridden to handle specific events in a dragging session" — so THESE THREE ARE THE INTERFACE, and the loop
 * is the machinery.
 *
 * `-startTrackingAt:inView:` ANSWERS "true if the receiver is set to respond continuously or when the mouse is
 * dragged; otherwise false", AND THIS TIER CAN ANSWER BOTH OF ITS CLAUSES WITH STATE THIS CLASS ALREADY SHIPS:
 * "respond continuously" is `-isContinuous` (whose own documentation is about sending action messages while the button
 * is held), and "or when the mouse is dragged" is the ACTION MASK §A10bc ships — `-sendActionOn:` stores WHICH EVENTS
 * make the cell send its action, so a cell whose mask contains `NSLeftMouseDraggedMask` IS, in the class's own
 * vocabulary, a cell set to respond when the mouse is dragged. THE SECOND READING IS A CHOICE AND IS STATED HERE: the
 * other candidate (that the phrase merely restates `continuous`) would leave half the sentence with nothing to say,
 * while this one is asked of two doors this class already has. See appkit-plan.md §A10bq.
 *
 * `-continueTracking:at:inView:` IS THE UNAMBIGUOUS ONE — "the default implementation returns true if the cell is set
 * to continuously send action messages to its target when the mouse button is down or the mouse is being dragged" —
 * so it answers `-isContinuous` and the two points are not read: A NON-CONTINUOUS CELL ENDS THE DRAG ON THE FIRST
 * DRAGGED EVENT, which is what a one-shot button wants.
 *
 * `-stopTracking:at:inView:mouseIsUp:` IS THE DOCUMENTED NO-OP — "the default NSCell implementation of this method
 * does nothing" — and it is where a subclass does its work (Apple's own example is a tristate cell advancing on a
 * click). The `mouseIsUp` flag is the reason the door takes four arguments: it distinguishes "released" from "left the
 * tracking rectangle", and both invocations reach here. */
- (BOOL)startTrackingAt:(NSPoint)startPoint inView:(nullable NSView *)controlView;
- (BOOL)continueTracking:(NSPoint)lastPoint at:(NSPoint)currentPoint inView:(nullable NSView *)controlView;
- (void)stopTracking:(NSPoint)lastPoint at:(NSPoint)stopPoint inView:(nullable NSView *)controlView mouseIsUp:(BOOL)flag;

/* **AND `-trackMouse:inRect:ofView:untilMouseUp:` STAYS OPEN, WHICH IS THIS UNIT'S REFUSAL AND THE MOST INTERESTING
 * ONE — IT IS THE DOOR THAT WOULD DRIVE THE THREE ABOVE.** Apple documents its SKELETON exactly (start; then
 * `-continueTracking:at:inView:` on each dragged event until it answers NO or the button goes up; then
 * `-stopTracking:...`; and the return value's rule about where the button went up — anywhere when `untilMouseUp` is
 * YES, inside `cellFrame` when it is NO). WHAT IT DOES NOT DOCUMENT IS THE LOOP ITSELF: WHICH EVENT MASK IT PULLS AND
 * IN WHICH RUN-LOOP MODE, WHAT HAPPENS WHEN THE CURSOR LEAVES `cellFrame` WHILE THE BUTTON IS STILL DOWN, AND WHAT PART
 * `+prefersTrackingUntilMouseUp` PLAYS IN THAT DECISION (its own page says only that overriding it lets the cell track
 * outside its frame — which is the ANSWER to the third question, not the mechanism of the second).
 *
 * AND THIS TIER HAS EVERY PIECE THE LOOP NEEDS — `NSApplication` ships `-nextEventMatchingMask:untilDate:inMode:
 * dequeue:` and `-sendEvent:`, `NSEvent` ships the three mouse types and their masks, and the app's pump is real — SO
 * THE REFUSAL IS NOT ABOUT MISSING PARTS. IT IS ABOUT THE ONE FAILURE MODE A LIBRARY CANNOT PROBE ITS WAY OUT OF: A
 * MODAL EVENT LOOP BUILT FROM GUESSED COORDINATION IS A LOOP THAT CAN HANG THE GUEST, and a hang is not a wrong rect
 * that a probe can catch — it is a boot that never comes back. The four questions above are what the unit that ships
 * this door has to settle first, and the three hooks land now because they are exactly, completely documented and they
 * are the half a SUBCLASS touches. */

/* **AND THE THREE RECT DOORS STAY OPEN, WHICH IS THE FIRST TIME THIS PLAN HAS REFUSED A ROW BECAUSE ITS DOCUMENTATION
 * IS QUALITATIVE RATHER THAN BECAUSE SOMETHING WAS MISSING.** `-drawingRectForBounds:`, `-titleRectForBounds:` and
 * `-imageRectForBounds:` are all declared in all three eras and carry NO COMMENT IN ANY OF THEM (measured over the
 * three headers), so the only ground is Apple's prose — and that prose is:
 *
 *   * `-drawingRectForBounds:` returns "the rectangle within which the receiver draws itself", and "this rectangle is
 *     slightly inset from the one in `theRect`" to take the border into account.
 *   * `-imageRectForBounds:` is "slightly offset from the one in the passed rect (typically offset to make room for the
 *     cell border)".
 *   * `-titleRectForBounds:` "resizes the drawing rectangle for the title inward by a small offset" for a text cell,
 *     and "does nothing" otherwise.
 *
 * "SLIGHTLY", "A SMALL OFFSET" AND "TYPICALLY OFFSET" ARE NOT NUMBERS, and the border type those offsets are said to
 * be "determined by" publishes no thickness either. A guessed inset would be a WRONG RECT IN EVERY CELL THAT HAS A
 * BORDER — silently, in the one place a caller cannot check — so all three rows stay open with this reason written
 * down, and the unit that closes them is the one that finds a number rather than the one that picks a plausible one. */

/* ============================================================================================ *
 * AND THE TWO DOORS WHOSE ANSWER IS A PUBLISHED CONSTANT — THE EXPANSION FRAME AND THE PERIODIC *
 * DELAY, WHICH ARE THE LAST TWO DOORS OF THIS CLASS THAT NEED NEITHER INK NOR AN EVENT LOOP.     *
 * ============================================================================================ */

/* **THE EXPANSION FRAME'S CONTRACT IS THE ERA HEADER'S OWN COMMENT, WHICH IS WHY THIS ROW CLOSES WITHOUT A
 * DOCUMENTATION FETCH** — the §A10bk model, and the same `NSCell (NSCellExpansion)` category:
 *
 *   "Allows the cell to return an expansion cell frame if cellFrame is too small for the entire contents in the view.
 *    When the mouse is hovered over the cell in certain controls, the full cell contents will be shown in a special
 *    floating tool tip view. If the frame is not too small, return an empty rect, and no expansion tool tip view will
 *    be shown. By default, NSCell returns NSZeroRect, while some subclasses (such as NSTextFieldCell) will return the
 *    proper frame when required."
 *
 * SO THE EMPTY RECT IS NOT A PLACEHOLDER: it is the byte-for-byte documented default, and the sentence says WHAT IT
 * MEANS — "no expansion tool tip view will be shown". AND THE BASE CLASS'S INABILITY TO DO BETTER IS THE SAME INK
 * THE REST OF THIS CLASS AWAITS: "too small for the entire contents" is a MEASUREMENT, and measuring a title needs
 * the font the geometry family is blocked on while measuring an image needs `-imageRectForBounds:`. A subclass with a
 * font — Apple's own example is `NSTextFieldCell` — overrides exactly this door, which is what makes it an override
 * point rather than a gap; the probe proves it by being the overrider.
 *
 * AND THE DOOR'S SIBLING STAYS OPEN, NAMED HERE RATHER THAN HALF-WRITTEN: `-drawWithExpansionFrame:inView:`'s
 * published default is "simply calls drawWithFrame:inView:", and drawing is the ink family — `-drawWithFrame:inView:`
 * and `-drawInteriorWithFrame:inView:` are both owed. A door whose whole implementation is a call to a door that does
 * not exist is not a half door, it is a stub, and this plan does not ship stubs. */
- (NSRect)expansionFrameWithFrame:(NSRect)cellFrame inView:(nullable NSView *)view;

/* **AND THE PERIODIC DELAY IS THE ONE DOOR IN THIS CLASS WHOSE ANSWER APPLE'S OWN TWO DOCUMENTATION VINTAGES
 * DISAGREE ABOUT**, which is worth stating where the constants are written rather than leaving a caller to discover
 * it. The Leopard-era `NSCell` class reference — DOCUMENTATION CONTEMPORANEOUS WITH THE 10.5 AND 10.6 PINS THIS PLAN
 * WORKS AGAINST — says "the default implementation returns a delay of 0.2 and an interval of 0.025 seconds"; the
 * CURRENT page for the same selector says "a delay of 0 and an interval of 0 seconds". Neither is a deviation from
 * the other — it is a change in what Apple DOCUMENTS, and this tree takes the ERA's, because the era is this plan's
 * ground (§11.5). The modern pair is written out at the implementation, so the choice is visible where it is made
 * and reversible in those two lines.
 *
 * AND THE VALUES ARE NOT THE BUTTON'S, WHICH IS THE TRAP THIS DOOR SETS: `NSButtonCell` — a class this tree does ship
 * — answers 0.4 and 0.075, and Apple's "Control and Cell Programming Topics" quotes those two numbers in the same
 * breath as a cell's. A reader who took the button's pair for the cell's would ship a key-repeat nearly twice too
 * slow. The probe pins the CELL's pair, and the button's is named here so the two cannot be confused in this file. */
- (void)getPeriodicDelay:(nullable float *)delay interval:(nullable float *)interval;

/* ============================================================================================ *
 * AND THE DEPRECATED VOCABULARY THE FORMATTER REPLACED — WHICH IS APPLE'S OWN COUPLING, IN ITS   *
 * OWN WORDS: in the 10.6 header these doors carry the comment "Use formatters instead. See       *
 * -[NSCell formatter] and -[NSCell setFormatter:]". So this section is §A10bm's sequel, and the  *
 * doors here are the ones a ported application still calls.                                      *
 * ============================================================================================ */

/* **THE THREE CONSTANTS ARE THE SAME THREE NUMBERS THE MODERN NAMES ABOVE ALREADY CARRY**, which is the one
 * interesting thing about them and the reason they are declared rather than refused: Apple's own comments give the
 * mapping ("Deprecated. Use NSScaleProportionallyDown", "Use NSScaleAxesIndependently", "Use NSImageScaleNone"), and
 * THOSE old names are not in this tree — the modern `NSImageScale*` set is (the vocabulary near the top of this file).
 * So `NSScaleProportionally` IS `NSImageScaleProportionallyDown` (0), `NSScaleToFit` IS
 * `NSImageScaleAxesIndependently` (1) and `NSScaleNone` IS `NSImageScaleNone` (2). THE PROBE ASSERTS THAT IDENTITY,
 * because a caller porting old code hands one of these over where a modern enumeration is expected and it is the
 * VALUES that make that work.
 *
 * THE VALUES ARE THE ERA'S, TRANSCRIBED FROM THE 10.6 HEADER'S `NSCell (NSDeprecated)` BLOCK — the same ground
 * §A10bk's four hit-test constants came from — and the 10.2 header's copy of that block (in `NSImageCell.h` there)
 * carries the same three numbers, so nothing about them moved between the pins. */
enum {
	NSScaleProportionally = 0,
	NSScaleToFit = 1,
	NSScaleNone = 2
};

/* **AND THE DOORS. APPLE MARKED THEM DEPRECATED IN 10.0 AND THIS TREE SHIPS THEM ANYWAY, WHICH IS THE USER'S POLICY
 * RATHER THAN AN OVERSIGHT**: deprecated API is OWED here so that older Mac applications can port (§11.5), and the
 * ledger carries these rows with `deprecated` in their `why` column rather than struck.
 *
 * `-entryType` AND `-setEntryType:` ARE TYPED BY THE **DATA ENTRY TYPES** VOCABULARY — the seven constants at the top
 * of this file — WHICH IS A CORRECTION TO A NOTE THIS CLASS'S OWN HEADER HAS CARRIED SINCE §A10bj: that comment calls
 * `-entryType` "a deprecated vocabulary this tier does not have", and the vocabulary has been declared in this file
 * since its FIRST SLICE (all seven of its `case` rows are shipped). What was missing was the door that READS it. And
 * what the door DOES is Apple's own sentence: `-setEntryType:` "sets how numeric data is formatted in the receiver and
 * places restrictions on acceptable input", and "if the receiver isn't a text-type cell, it is converted to one (which
 * changes its title to \"Cell\" and sets the font to the system font at 12 points)". THE CONVERSION AND THE TITLE ARE
 * IMPLEMENTED AND THE FONT IS REFUSED BY NAME — the same split, out of the same sentence, that §A10bj's
 * `-setStringValue:` already has.
 *
 * AND ONE CLAUSE OF THAT SENTENCE IS REFUSED RATHER THAN OBEYED: "the formatter associated with the receiver is
 * replaced with a newly instantiated formatter appropriate to the entry type". WHICH formatter is appropriate to which
 * entry type IS NOT PUBLISHED — Apple names the entry types' MEANINGS ("Integer", "Positive float") and stops — so the
 * mapping would be invented; and this tier HAS the formatter (§A10bm), so a caller who wants one sets it and gets that
 * unit's documented two-way conversion instead of a guess. Inventing it would also make `-isEntryAcceptable:`'s answer
 * ambiguous between the two sources its documentation gives it.
 *
 * `-isEntryAcceptable:` IS THE ONE DOOR HERE THAT IS PURE ARITHMETIC, and its sentence names the test: "whether a
 * string representing a numeric or date value is formatted in a suitable way for the cell's entry type". So the ENTRY
 * TYPE decides, over the vocabulary above — `NSAnyType` accepts any string ("any value is allowed"), and each numeric
 * entry type accepts a number of ITS OWN KIND. The two readings the sentence does not spell out are stated where the
 * code is: the check is over the WHOLE string, and an EMPTY string is accepted by `NSAnyType` and refused by every
 * numeric type. */
- (NSInteger)entryType;
- (void)setEntryType:(NSInteger)aType;
- (BOOL)isEntryAcceptable:(nullable NSString *)aString;

/* **AND THE FOURTH DOOR OF THAT BLOCK IS LEFT OPEN ON PURPOSE, WHICH IS NAMED HERE RATHER THAN HALF-WRITTEN.**
 * `-setFloatingPointFormat:left:right:` is the one whose documented behaviour is a RENDERING rule — with `autoRange`
 * NO, `left` is the maximum integer digits and `right` the fraction digits, zero-padded, and "the integer portion of a
 * number is never truncated"; with YES, the two are "simply added to form a maximum total field width … plus 1 for the
 * decimal point" — and every one of those rules belongs to the formatter that `-setEntryType:` refuses to invent BY
 * NAME, two paragraphs up. It is the next slice of this family, and what it needs is stated rather than guessed. */

/* ============================================================================================ *
 * AND THE TWO DOORS THAT ANSWER FROM WHAT THE CELL HOLDS — ITS VALUE'S TEXT, AND ITS MENU.       *
 * ============================================================================================ */

/* **TWO DOORS, TWO ARGUMENTS SETS, AND NEITHER READS THE ARGUMENT IT IS GIVEN.** That is the shape that puts them
 * together: a caller hands each one a context a SUBCLASS would use, and the base cell answers from state it already
 * holds — which is why both are one-liners whose whole contract is a sentence.
 *
 * `-compare:` IS DOCUMENTED IN ONE SENTENCE WITH THREE CLAUSES, AND TWO OF THEM ARE EASY TO MISS: it "compares the
 * string values of the receiver and another cell, DISREGARDING CASE", and the other object "must be of type `NSCell`;
 * IF IT IS NOT, THIS METHOD RAISES `NSBadComparisonException`". SO THE DOOR READS NEITHER CELL'S KIND NOR ITS VALUE:
 * it compares `-stringValue`s — the class's own door for "the value as text", which §A10bm even gave a formatter to
 * answer through — and a cell holding `@"apple"` orders against one holding `@"Banana"` by their TEXT, case-blind.
 *
 * AND THE EXCEPTION'S NAME IS A CONSTANT OF ITS OWN, DECLARED WHERE APPLE DECLARES IT: `NSBadComparisonException` is
 * `AppKit/NSErrors.h`'s one name in the 10.6 SDK (line 45), so this tree grew that header — the third file created to
 * match Apple's layout, after §A10bl's `NSText.h` and `NSParagraphStyle.h`. Raising the AppKit's own name is the
 * difference between a caller catching a documented exception and catching whatever a wrong type happens to produce.
 *
 * AND APPLE LEAVES ONE CASE OPEN RATHER THAN UNDEFINED-BY-ACCIDENT: "if the value is `nil`, the behavior is undefined
 * and may change in future versions of macOS". This tier RAISES for nil too, and says so — a nil is not an `NSCell`,
 * which is exactly the condition the sentence names, and returning an ordering for it would be inventing a fourth
 * answer to a three-valued question. */
- (NSComparisonResult)compare:(nullable id)otherCell;

/* **AND THE MENU DOOR IS THE OPPOSITE KIND OF ONE-LINER**: "the default implementation gets the value of the `menu`
 * property and returns `nil` if no menu has been set" — and it returns nil THROUGH that door rather than by a branch of
 * its own, because a cell with no menu answers nil from `-menu` already. The event and the rect are what a subclass
 * overrides this for ("subclasses can override to customize the returned menu according to the event received and the
 * area in which the mouse event occurs"), and the base cell reads neither.
 *
 * AND THE RETURN TYPE IS `id` FOR THE REASON THIS CLASS'S `-menu` ALREADY IS: Apple types it `NSMenu *`, `NSMenu` IS in
 * this tree, and naming it here would pull the menu inventory into every cell that includes this header — the trade
 * §A10ay recorded for the property, applied to the door that hands the same object back. */
- (nullable id)menuForEvent:(NSEvent *)event inRect:(NSRect)cellFrame ofView:(nullable NSView *)view;

/* ============================================================================================ *
 * AND THE ATTRIBUTED-STRING PAIR — THE SECOND KIND OF VALUE THE CELL CAN HOLD, AND THE ONE      *
 * WHOSE DOOR THIS TIER CAN ONLY HALF ANSWER.                                                    *
 * ============================================================================================ */

/* **APPLE DECLARES THIS PAIR IN `NSCellAttributedStringMethods`, A CATEGORY THIS TREE FLATTENS INTO THE CLASS** — the
 * treatment §A10bk recorded for `NSKeyboardUI` and `NSCellHitTest`, and the reason an era artefact's `category` row for
 * it stays open while its members ship.
 *
 * AND THE VALUE IS A REAL KIND HERE, WHICH IS WHY THE PAIR CAN SHIP AT ALL: `NSAttributedString` exists in this tree
 * (Foundation, with `-string`, `-length`, `-initWithString:attributes:`, `-initWithAttributedString:` and
 * `-isEqualToAttributedString:`), so a cell can hold one and hand it back. Apple declares the property `@NSCopying`,
 * which is why the setter stores a COPY rather than the caller's object — and it makes that copy through
 * `-initWithAttributedString:` because THIS TREE'S `NSAttributedString` DECLARES `<NSCopying>` AND DOES NOT IMPLEMENT
 * `-copyWithZone:`, so `-copy` would be a `doesNotRecognizeSelector:` at runtime rather than a copy. That is a measured
 * fact about the tier and not a preference, and it is recorded where the setter uses it.
 *
 * `-setAttributedStringValue:` HAS TWO DOCUMENTED CLAUSES AND BOTH ARE IMPLEMENTABLE: "if the receiver is not a
 * text-type cell, IT IS CONVERTED TO ONE before the value is set" — the SAME conversion §A10bj's `-setStringValue:`
 * performs, which is why this door reuses that shape and not a new one — and the value is then set, so a null cell
 * handed an attributed string IS a text cell by the time it holds one. ITS THIRD CLAUSE IS REFUSED BY NAME (a formatter
 * that cannot understand the string "marks the cell's object as invalid", and this tier has no such flag:
 * `-hasValidObjectValue` answers "is there a value", §A10az).
 *
 * `-attributedStringValue` IS THE HALF THAT CANNOT BE FINISHED, WHICH IS WHY IT IS DECLARED `nullable`: Apple's page
 * says the property is the cell's value as an attributed string WHOSE ATTRIBUTES ARE "the default paragraph style, the
 * cell's font and alignment, and whether the cell is enabled and scrollable" — so the branch that SYNTHESISES a string
 * from a plain value needs three things this tier cannot supply: the FONT (there is no `NSFont` class), the paragraph
 * STYLE (a class this tier has not written — §A10bl shipped only the type's header), and an attribute NAME for "enabled
 * and scrollable" that APPLE DOES NOT PUBLISH. A value that IS an attributed string is answered as itself; every other
 * value answers `nil`, which is this tier's empty value for the type and NOT an empty attributed string, so a caller can
 * tell "there is no attributed answer here" from "the text is empty". See appkit-plan.md §A10bs. */
- (nullable NSAttributedString *)attributedStringValue;
- (void)setAttributedStringValue:(NSAttributedString *)obj;

/* ============================================================================================ *
 * AND THE INK: THE FONT, THE THREE RECTS THAT PLACE A TITLE, AND THE TWO DOORS THAT PAINT.       *
 * ============================================================================================ */

/* **THE CELL'S FONT, WHICH THIS CLASS HAS TO HAVE THE MOMENT IT DRAWS A TITLE.** Apple declares `-font`/`-setFont:`
 * on `NSCell`; this tier's cell had no such door because NOTHING IN IT DREW — a font is what a TITLE is set in, and a
 * cell that drew no title needed none. It is RETAINED (this tree's rule for a font: a caller hands one over and keeps
 * using it) and it is typed `id` where Apple types `NSFont` for the reason this header's other cross-class doors are:
 * the header includes Foundation and not the AppKit. A nil font is the documented "the default", which the drawing
 * door answers with the system font. */
- (nullable id)font;
- (void)setFont:(nullable id)font;

/* **THE THREE RECT DOORS, WHOSE NUMBERS APPLE DOES NOT PUBLISH — SO THIS TIER'S ARE NOW ITS OWN AND SAID SO.** All
 * three eras declare them and comment NONE of them; the prose says only "slightly inset" and "a small offset", which
 * is not a number, and a guessed inset is a wrong rect in every bordered cell with nothing to check it against. THE
 * ROWS CLOSE HERE RATHER THAN STAY OPEN because the drawing DOES need an answer: a title has to be placed somewhere,
 * so the arithmetic is stated as THIS TIER'S — the drawing rect is the bounds inset by the border, the title and the
 * image share it — and a subclass that wants different arithmetic overrides the door, which is what the doors are
 * for. ONE CONSTANT (`NS_CELL_BORDER_INSET`) is the whole of the choice. */
- (NSRect)drawingRectForBounds:(NSRect)theRect;

/* **AND WHERE A MENU OR A LIST RAISED BY THIS CELL IS ANCHORED, WHICH IS THE CONTROL'S OWN LEFT EDGE.** `NSMenu`'s
 * placement puts the menu's window at `location.x` — MEASURED, `_trackingFrame = NSMakeRect(location.x, …)` — so the
 * point a cell hands over IS the menu's left edge, and "line the menu up with the control" is a statement about this
 * one number.
 *
 * IT LIVES HERE BECAUSE TWO CONTROLS RAISE THINGS AND BOTH MUST AGREE. The pop-up button raises a menu and the combo
 * box raises its list, and they were each doing this arithmetic in their own file — which is how the combo box came to
 * anchor at its CHIP rather than at its field, so its list hung under the arrow instead of under the control. The point
 * is the frame's bottom-left corner carried into the space a window frame lives in: the CELL's frame is in the view's
 * coordinates, `-convertPoint:toView:` with a nil view reaches the window's, and the window's own origin is where the
 * raised window will be placed. A control at its window's own origin hides the middle step, which is exactly the bug
 * that step exists to stop. */
- (NSPoint)cg_popUpAnchorForFrame:(NSRect)cellFrame inView:(nullable id)controlView;
- (NSRect)titleRectForBounds:(NSRect)theRect;
- (NSRect)imageRectForBounds:(NSRect)theRect;

/* **AND THE TWO DOORS THAT PAINT — APPLE'S SPLIT, AND IT IS WORTH KEEPING EXACTLY.** `-drawWithFrame:inView:`
 * paints the BORDER and the BACKGROUND and then calls `-drawInteriorWithFrame:inView:`, which paints what sits
 * INSIDE them. A subclass that changes only the face (a button's bezel) overrides the first and inherits the second;
 * one that changes only the contents overrides the second. THAT SPLIT IS THE WHOLE REASON `NSButtonCell` CAN BE A
 * THIN CLASS: it draws a bezel and hands the interior back to this one. The view is typed `id` because this header
 * does not include `NSView`. */
- (void)drawWithFrame:(NSRect)cellFrame inView:(nullable id)controlView;
- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(nullable id)controlView;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSCELL_H */
