/*
 * NSLayoutManager.h — THE WEB: A MANAGER TIED TO A STORE AND FILLING CONTAINERS.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **APPLE'S OWN HEADER SAYS WHAT THE CLASS IS IN ONE SENTENCE, AND THIS SLICE IS THE FIRST HALF OF IT.** "An
 * NSLayoutManager stores glyphs, attributes, and layout information generated from an NSTextStorage. It can map between
 * ranges of characters in the NSTextStorage and ranges of glyphs within itself. It understands and keeps track of two
 * types of range invalidation: a character range can need GLYPHS generated for it or it can need its glyphs LAID OUT."
 *
 * **WHAT IS HERE IS THE WHOLE OF APPLE'S SENTENCE NOW, AND EACH PART ARRIVED AS ITS OWN SLICE.** The manager knows its
 * STORE, it holds its CONTAINERS, an edit in the store REACHES it, and it records that its layout is stale — the
 * second type of invalidation. It also GENERATES GLYPHS (a `CTLine` per fragment, KEPT as the glyph store), LAYS the
 * store into line fragments with the same TYPESETTER the text view uses, FLOWS what does not fit one container into
 * the NEXT, DRAWS the glyphs and the two rules beside them (a background and an underline), and answers the
 * character-to-glyph map by WALKING the store it generated. THAT LAST PART IS THE ONE STILL ONE-TO-ONE: Core Text maps
 * one glyph per character here, so the map arrives at the identity rather than being declared as it — and a shaper that
 * made a ligature would make the arithmetic wrong rather than making a declared identity wrong.
 *
 * **AND THE LAYOUT IS THE SECOND KIND OF INVALIDATION MADE REAL.** Apple's sentence names two: a range can need
 * GLYPHS generated, or it can need its glyphs LAID OUT. Slice one built the web and recorded which ranges were stale;
 * this slice asks the CONTAINER for the band a line may occupy — its SIZE for a simple rectangle, and its
 * `-lineFragmentRectForProposedRect:sweepDirection:movementDirection:remainingRect:` answer for a shaped region —
 * breaks the store's string into LINE FRAGMENTS with the same TYPESETTER the text view uses, and answers where each
 * fragment is — which is what `-usedRectForTextContainer:` is the size of, and what a view will draw into.
 *
 * **AND THE GLYPH STORE IS THE GENERATED LINES, WHICH IS WHAT KEEPS THE MAP HONEST.** Apple's manager "stores glyphs,
 * attributes, and layout information"; the glyphs a `CTLine` maps its string to ARE the store here, and the layout
 * keeps the line it generated for each fragment rather than throwing it away and rebuilding it per draw. The two
 * conversion doors therefore COUNT AND SLICE STORED GLYPHS rather than declaring the identity: they happen to come out
 * one to one — `CTLine` maps one glyph per character through `CTFontGetGlyphsForCharacters`, notdef included — and the
 * day a shaper makes them differ, the arithmetic already walks a store to say so. `NSTextStorage.h` refused
 * `-addLayoutManager:`/`-removeLayoutManager:`/`-layoutManagers` because they name a class that did not exist, and
 * `NSTextContainer.h` refused `-layoutManager`/`-setLayoutManager:` for the same reason. Both are here now: the
 * storage owns a LIST of managers and calls `-setTextStorage:` on the way in and out, and the container holds a
 * BORROWED pointer to the one that lays it out.
 */
#ifndef APPKIT_NSLAYOUTMANAGER_H
#define APPKIT_NSLAYOUTMANAGER_H

#import <Foundation/Foundation.h>
/* `NSGlyph` is declared in `NSFont.h` and the glyph store's doors take it, so this header imports it for the same
 * reason Apple's does: a type a signature names has to be visible where the signature is read. */
#import <AppKit/NSFont.h>
/* FOR `NSImageScaling` AND `NSCell`: two of the doors below name them, and a forward declaration cannot stand in for a
 * typedef. `NSCell.h` imports this tier's view/text headers, never this one, so the dependency runs one way. */
#import <AppKit/NSCell.h>

NS_ASSUME_NONNULL_BEGIN

@class NSTextStorage;
@class NSTextContainer;
@class NSLayoutManager;
@class NSTextView;
@class NSParagraphStyle;
@class NSRulerView;
@class NSView;
@class NSTextBlock;

/* **THE TWO THINGS A MANAGER TELLS ITS DELEGATE, OF THE ERA'S THREE.** `-layoutManagerDidInvalidateLayout:` is the one
 * this slice can send — the layout IS invalidated, because the store said so — and the other two
 * (`-layoutManager:didCompleteLayoutForTextContainer:atEnd:` and the temporary-attribute question) belong to laying
 * out and drawing, so they are named here and sent by the slices that do those. A delegate that implements neither is
 * told nothing, which is what `@optional` and the `-respondsToSelector:` guards are for. */
@protocol NSLayoutManagerDelegate <NSObject>
@optional
- (void)layoutManagerDidInvalidateLayout:(NSLayoutManager *)sender;
- (void)layoutManager:(NSLayoutManager *)layoutManager
	didCompleteLayoutForTextContainer:(nullable NSTextContainer *)textContainer
	atEnd:(BOOL)layoutFinishedFlag;
- (BOOL)layoutManager:(NSLayoutManager *)layoutManager
	shouldUseTemporaryAttributes:(NSDictionary *)attrs
	forDrawingToScreen:(BOOL)toScreen
	atCharacterIndex:(NSUInteger)charIndex
	effectiveRange:(nullable NSRangePointer)effectiveCharRange;
@end

@interface NSLayoutManager : NSObject
{
	NSTextStorage *_textStorage;		/* RETAINED */
	NSMutableArray *_textContainers;	/* RETAINED */
	id _delegate;				/* NOT RETAINED */
	/* **AND THE ONE PIECE OF LAYOUT STATE THIS SLICE HAS: WHICH CHARACTERS ARE STALE.** The union of everything the
	 * store has reported since the last time a caller asked — `NSNotFound` as the location meaning NOTHING IS STALE,
	 * which is the same "no edit" sentinel `NSTextStorage` uses for its own record. */
	NSRange _invalidatedRange;
	/* **AND THE FRAGMENTS EACH CONTAINER HAS BEEN FILLED WITH, index-matched to `_textContainers`.** An `NSMutableArray`
	 * per container, each holding `FNFragment` objects (a glyph range and two rects) — rebuilt whenever the container
	 * list changes, which is what keeps the two arrays in step BY CONSTRUCTION rather than by a rule somebody has to
	 * remember. Nil until a layout is asked for. */
	NSMutableArray *_fragments;	/* RETAINED; one array per container */
	/* **AND THE GLYPH STORE — ONE RECORD PER GLYPH, REBUILT WITH THE FRAGMENTS.** Apple's layout manager is a glyph
	 * store first and a line breaker second: its typesetter WRITES glyphs into the store, and the doors that read or
	 * move one glyph (`-glyphAtIndex:`, `-setLocation:forStartOfGlyphRange:`, `-setNotShownAttribute:…`) are doors onto
	 * that array. This tier's authority is the TEXT — the fragments' `CTLine`s are the shaped glyphs — so the store is a
	 * SHADOW: it is built from the fragments whenever the layout is rebuilt, and it records what a caller changes so the
	 * read doors can answer. A shadow is the honest shape here because the alternative, making the store authoritative,
	 * would mean re-implementing line breaking so a glyph edit could survive one. */
	NSMutableArray *_glyphStore;	/* RETAINED; FNGlyph records, in layout order, or nil before the first build */
	BOOL _glyphStoreStale;		/* YES when the fragments have moved under it */
	/* ============================================================================================
	 * AND THE THREE THINGS A CALLER CAN DICTATE RATHER THAN MEASURE.
	 *
	 * **A TEXT BLOCK'S TWO RECTANGLES ARE COMPUTED FROM THE FRAGMENTS — AND A SUBCLASS MAY OVERRIDE THEM.** Apple's
	 * `-setBoundsRect:forTextBlock:glyphRange:` exists for a layout manager's SUBCLASS to say where it put a block,
	 * so this tier keeps the overrides in one list (a borrowed block object and two rects) and consults it before it
	 * computes. The list is searched linearly: a table has few blocks, and a dictionary keyed by a borrowed pointer
	 * needs the same lifetime argument anyway.
	 *
	 * **AN ATTACHMENT'S SIZE IS THE ONE NUMBER THE ENGINE TOOK FROM THE CELL**, so a caller that disagrees stores its
	 * own here, keyed by character index, and `-cg_boxesForRange:` reads it when it builds the run delegate — which is
	 * how the override reaches the LAYOUT rather than only the answer. Setting one invalidates that range.
	 * ========================================================================================== */
	NSMutableArray *_blockRectOverrides;	/* RETAINED; FNBlockRect objects, one per overridden block */
	NSMutableDictionary *_attachmentSizes;	/* RETAINED; NSNumber(character index) -> NSValue(NSSize) */
	NSImageScaling _defaultAttachmentScaling;
	/* **AND THE TYPESETTER TRIO, WHICH THIS TIER STORES AND DOES NOT CONSULT.** The layout here is Core Text's — a
	 * `CTTypesetter` built from the store — so there is no `NSTypesetter` object in the flow at all; a caller that sets one
	 * gets it back, and nothing reads it. The behaviour is a real value with a real default (`NSTypesetterLatestBehavior`),
	 * which is what a caller checking `-typesetterBehavior` expects to see. */
	id _typesetter;		/* NOT RETAINED: Apple's contract is a borrowed pointer */
	id _glyphGenerator;		/* NOT RETAINED */
	NSInteger _typesetterBehavior;
	/* **AND THE TWO TABLES THE DRAWING PASS READS BESIDE THE STORE.** The marks are the temporary attributes, as a
	 * sorted list of runs (an `FNTextMark`: a range and its dictionary); the rect array is the buffer the `rectArray…`
	 * doors answer with, kept here because Apple's answer is a pointer valid until the next call. */
	NSMutableArray *_temporaryMarks;	/* RETAINED; FNTextMark objects, sorted by range, non-overlapping */
	NSRect *_rectArray;		/* OWNED; reallocated per call, freed with the manager */
	NSUInteger _rectArrayCount;
	/* **AND THE EXTRA LINE FRAGMENT'S RECORD.** Nothing in this tier's layout writes it; the door that sets it does, and
	 * the getters answer it, which is what a layout subclass needs to publish the line it made. */
	/* ============================================================================================
	 * AND THE MANAGER'S OWN KNOBS. Each is a number or a bit a caller sets and reads back; only two of them change what
	 * the layout does (`_usesFontLeading` adds the font's leading to the line height), and each one that does not says so
	 * at its door rather than implying an effect it has not got.
	 * ========================================================================================== */
	BOOL _allowsNonContiguousLayout;
	BOOL _backgroundLayoutEnabled;
	BOOL _showsInvisibleCharacters;
	BOOL _showsControlCharacters;
	BOOL _usesFontLeading;
	BOOL _usesScreenFonts;
	float _hyphenationFactor;
	/* **AND THE CONTAINER A GLYPH RANGE WAS LAID OUT IN, WHEN A SUBCLASS SAYS SO.** `-setTextContainer:forGlyphRange:` is
	 * the door a layout manager's subclass uses to tell the receiver where it put a range; this list is consulted before the
	 * fragment scan, and a range with no entry is answered by the fragments as usual. */
	NSMutableArray *_glyphContainerOverrides;	/* RETAINED; FNContainerOverride objects */
	NSUInteger _layoutOptions;
	NSRect _extraLineRect;
	NSRect _extraLineUsedRect;
	NSTextContainer *_extraLineContainer;	/* BORROWED: the container owns no record of it */

}

/* ---- THE STORE, WHICH THE STORAGE DRIVES ------------------------------------------------------------ */

/* **THE PRIMITIVE IS CALLED BY THE STORAGE AND NOT BY A CALLER.** Apple's comment: "The set method is generally
 * called by NSTextStorage's addLayoutManager:/removeLayoutManager: methods." So `[store addLayoutManager:manager]` is
 * the way to tie the two, and `-setTextStorage:` on its own stores the pointer WITHOUT registering for edits — which is
 * why the door is documented rather than merely declared. `-replaceTextStorage:` is the one a caller DOES use to move a
 * manager between stores, and it does the two halves a caller cannot: out of the old list, into the new. */
- (nullable NSTextStorage *)textStorage;
- (void)setTextStorage:(nullable NSTextStorage *)textStorage;
- (void)replaceTextStorage:(NSTextStorage *)newTextStorage;

/* **AND THE STORE SEEN AS AN ATTRIBUTED STRING.** This is the `NSGlyphStorage` protocol's door, and for a layout
 * manager the string IS the storage — Apple says so in as many words, and it is the answer a glyph generator will ask
 * for when there is one. */
- (nullable NSAttributedString *)attributedString;

/* ---- THE CONTAINERS, WHICH THIS MANAGER OWNS AND THEY BORROW ---------------------------------------- */

- (NSArray *)textContainers;
- (void)addTextContainer:(NSTextContainer *)container;
- (void)insertTextContainer:(NSTextContainer *)container atIndex:(NSUInteger)index;
- (void)removeTextContainerAtIndex:(NSUInteger)index;
- (void)setTextContainer:(NSTextContainer *)aContainer;

/* ---- STALENESS, WHICH IS THIS SLICE'S WHOLE OBSERVABLE BEHAVIOUR ------------------------------------ */

/* **THE DOOR THE STORAGE CALLS, AND THE ONE METHOD THAT MAKES THIS A MANAGER RATHER THAN A HOLDER.** Apple's comment
 * gives the two ranges' meanings and they are different: `range` is the range in the OLD string (which is what the
 * storage's own record holds) and `invalidatedRange` is what changed in the NEW one, which may be LARGER because
 * attribute fixing can touch neighbours. There is no attribute fixing here, so the two are the same span measured in
 * the two strings. */
- (void)textStorage:(NSTextStorage *)aTextStorage
	     edited:(NSUInteger)editedMask
	      range:(NSRange)oldRange
   changeInLength:(NSInteger)delta
  invalidatedRange:(NSRange)newCharRange;

/* AND THE DOOR EVERYTHING ELSE USES TO MARK A RANGE STALE, which the edit above is spelled in. */
- (void)invalidateLayoutForCharacterRange:(NSRange)charRange actualCharacterRange:(nullable NSRangePointer)actualCharRange;

/* ==================================================================================================================
 * THE INVALIDATION AND ENSURE FAMILY — how a caller says "this changed" and "make sure that is laid out".
 *
 * **THREE KINDS OF STALENESS, AND ONLY ONE OF THEM IS THIS TIER'S LAYOUT.** Apple separates GLYPH GENERATION (the
 * shaping), LAYOUT (the line breaking and placement) and DISPLAY (the pixels). This tier regenerates all three together
 * from the store, on demand — the fragments ARE the layout and the lines carry the glyphs — so the three doors all end in
 * one invalidation and are separate only because a caller sends them separately. What each one still does on its own is
 * what the caller can observe: `-invalidateGlyphsOnLayoutInvalidationForGlyphRange:` converts GLYPHS to characters before
 * marking (its argument is a glyph range and the layout is keyed by characters), and the two DISPLAY doors reach the
 * container's text view instead of the layout.
 *
 * **`-invalidateLayoutForCharacterRange:isSoft:` RECORDS ITS SOFTNESS AND ACTS ON NONE OF IT**, which is stated rather
 * than implied: a soft invalidation is Apple's deferral for marked text, and this tier already lays out only when asked,
 * so there is no eager pass to defer.
 *
 * **A DISPLAY INVALIDATION ASKS THE VIEW FOR THE BOUNDING RECT**, not for the whole view: the rect is the layout's own
 * (container coordinates) offset by the container's line-fragment padding, which is where this tier's text views put
 * their container. A view that places its container elsewhere still gets a correct — if wider — damage rect, because the
 * rect is grown by the padding on both axes.
 * ================================================================================================================ */

- (void)ensureGlyphsForCharacterRange:(NSRange)charRange;
- (void)ensureGlyphsForGlyphRange:(NSRange)glyphRange;

- (void)invalidateGlyphsForCharacterRange:(NSRange)charRange
			   changeInLength:(NSInteger)delta
		     actualCharacterRange:(nullable NSRangePointer)actualCharRange;
- (void)invalidateGlyphsOnLayoutInvalidationForGlyphRange:(NSRange)glyphRange;
- (void)invalidateLayoutForCharacterRange:(NSRange)charRange
				 isSoft:(BOOL)flag
		     actualCharacterRange:(nullable NSRangePointer)actualCharRange;
- (void)invalidateDisplayForCharacterRange:(NSRange)charRange;
- (void)invalidateDisplayForGlyphRange:(NSRange)glyphRange;

/* WHAT IS NOT LAID OUT YET, BY REFERENCE — the pair Apple's single-answer doors answer one at a time. */
- (void)getFirstUnlaidCharacterIndex:(nullable NSUInteger *)charIndex glyphIndex:(nullable NSUInteger *)glyphIndex;

/* **AND WHICH GLYPHS A RECTANGLE COVERS, which is how an editor decides what to redraw from a damage rect.** The
 * `withoutAdditionalLayout:` spelling is taken and ignored for the same reason the line-fragment pair's is: this tier
 * lays a container out in full when anything is asked of it. */
- (NSRange)glyphRangeForBoundingRect:(NSRect)bounds inTextContainer:(NSTextContainer *)container;
- (NSRange)glyphRangeForBoundingRectWithoutAdditionalLayout:(NSRect)bounds inTextContainer:(NSTextContainer *)container;

/* **AND THE TWO THINGS ABOUT A CONTAINER'S SURROUNDINGS THAT CHANGE A LAYOUT AND A PICTURE.** A geometry change
 * re-wraps everything; a text-view change is a picture that moved and needs repainting. */
- (void)textContainerChangedGeometry:(NSTextContainer *)container;
- (void)textContainerChangedTextView:(NSTextContainer *)container;

/* ==================================================================================================================
 * THE EXTRA LINE FRAGMENT — the line after a trailing newline, stored and answered.
 *
 * **THIS TIER'S BREAKER DOES NOT PRODUCE ONE** (the newline's glyph belongs to the line it ends — see the rect-array
 * doors' note), so the getters answer what a subclass last set and `NSZeroRect`/nil before that. The pair is not a stub:
 * a custom layout manager that DOES produce the fragment stores it here and every reader of these doors — including a
 * view drawing a caret past the last newline — sees what it said.
 * ================================================================================================================ */

- (NSRect)extraLineFragmentRect;
- (NSRect)extraLineFragmentUsedRect;
- (nullable NSTextContainer *)extraLineFragmentTextContainer;
- (void)setExtraLineFragmentRect:(NSRect)aRect usedRect:(NSRect)usedRect textContainer:(NSTextContainer *)aContainer;

/* ==================================================================================================================
 * AND THE TWO FONT MEASUREMENTS THE LAYOUT ANSWERS WITHOUT A LAYOUT.
 *
 * `-defaultLineHeightForFont:` is the line a font asks for — ascender minus the (negative) descender, plus its leading —
 * and `-defaultBaselineOffsetForFont:` is where the baseline sits in that line, which is the ascender. They are the
 * numbers `-cg_lineHeight` uses, asked for one font instead of the manager's own.
 * ================================================================================================================ */

- (CGFloat)defaultLineHeightForFont:(NSFont *)aFont;
- (CGFloat)defaultBaselineOffsetForFont:(NSFont *)aFont;

/* **AND THE RECORD, ASKED — THIS TIER'S OWN NAME FOR IT.** Apple exposes the invalidation only through the DELEGATE
 * (there is no getter), and a probe cannot watch a delegate method and also read what it was told about; this door is
 * `cg_`-named for that reason, like every other door in this tree that exists because the tier's own instruments needed
 * it. `NSNotFound` means nothing is stale. */
- (NSRange)cg_invalidatedRange;

/* THE DELEGATE, NOT RETAINED — this tree's rule for every delegate. */
- (nullable id <NSLayoutManagerDelegate>)delegate;
- (void)setDelegate:(nullable id <NSLayoutManagerDelegate>)anObject;

/* ---- THE CHARACTER-TO-GLYPH MAP, WHICH WALKS THE GLYPH STORE ----------------------------------------- */

/* **THE MAP IS THE LINE'S OWN, AND IT IS NOT ONE TO ONE.** Apple's two doors exist because a glyph store can hold
 * FEWER or MORE glyphs than there are characters — a ligature is three characters and one glyph, a composed mark is
 * one character and one, and a hyphenated line has a glyph the text does not — and both are true of this tier now:
 * `CTLine` SHAPES, through HarfBuzz. So the manager's glyph space is built from the glyph count of each line it lays
 * out, and both doors translate through the runs' own string indices (`CTRunGetStringIndices`) rather than by
 * arithmetic. A fragment with no line — an empty one a trailing newline opened — has no glyphs and no map, and is the
 * one case answered arithmetically. */
- (NSUInteger)numberOfGlyphs;
- (NSRange)glyphRangeForCharacterRange:(NSRange)charRange actualCharacterRange:(nullable NSRangePointer)actualCharRange;
- (NSRange)characterRangeForGlyphRange:(NSRange)glyphRange actualGlyphRange:(nullable NSRangePointer)actualGlyphRange;

/* ---- THE LAYOUT: THE FRAGMENTS A CONTAINER IS FILLED WITH -------------------------------------------- */

/* **THE QUESTION THE CONTAINER EXISTS TO ANSWER, ASKED AND ANSWERED.** `-ensureLayoutForTextContainer:` fills it (the
 * other two are the same request narrowed by a range, and with one container they are the whole of it);
 * `-usedRectForTextContainer:` is the size a view would need to show what is laid in it; and the two fragment doors
 * answer where ONE glyph sits and which range shares its line. ALL COORDINATES ARE THE CONTAINER'S, as Apple's own
 * comments insist. **AND THE FLOW IS THE CONTAINERS'**: text that does not fit one is carried to the NEXT on the
 * manager's list, in order, each container's own fragments in its own coordinates. */
- (void)ensureLayoutForTextContainer:(NSTextContainer *)container;
- (void)ensureLayoutForCharacterRange:(NSRange)charRange;
- (void)ensureLayoutForGlyphRange:(NSRange)glyphRange;
- (NSRange)glyphRangeForTextContainer:(NSTextContainer *)container;
- (NSRect)usedRectForTextContainer:(NSTextContainer *)container;
- (NSRect)lineFragmentRectForGlyphAtIndex:(NSUInteger)glyphIndex effectiveRange:(nullable NSRangePointer)effectiveGlyphRange;
- (NSRect)lineFragmentUsedRectForGlyphAtIndex:(NSUInteger)glyphIndex effectiveRange:(nullable NSRangePointer)effectiveGlyphRange;

/* AND HOW MANY FRAGMENTS THERE ARE, which is THIS TIER'S OWN DOOR for the same reason `-cg_invalidatedRange` is: a
 * probe that counts lines must be able to, and Apple answers only through the geometry. */
- (NSUInteger)cg_lineFragmentCountForTextContainer:(NSTextContainer *)container;

/* **AND THE FOUR REVERSE-LOOKUP DOORS A VIEW NEEDS, EACH `cg_`-NAMED FOR THE SAME REASON.** Apple's own view asks
 * these questions through doors a view holds privately; putting them here is what lets `NSTextView` stop carrying a
 * layout of its own and read the manager's instead. The RANGE is the ordinal fragment's glyph range — trailing
 * whitespace and all, exactly as the breaker kept it — and the INDEX is the fragment a glyph is in; the OFFSET is the
 * x of a glyph from the CONTAINER's left edge (the fragment padding INCLUDED, which is what a caret is drawn at); and
 * the POINT door is the inverse, the glyph nearest a container point. */
- (NSRange)cg_lineFragmentRangeAtIndex:(NSUInteger)index inTextContainer:(NSTextContainer *)container;
- (NSUInteger)cg_lineFragmentIndexForGlyphAtIndex:(NSUInteger)glyphIndex inTextContainer:(NSTextContainer *)container;
- (CGFloat)cg_offsetForGlyphAtIndex:(NSUInteger)glyphIndex;
- (NSUInteger)cg_glyphIndexForPoint:(NSPoint)point inTextContainer:(NSTextContainer *)container;

/* AND THE BASELINE A GLYPH SITS ON, which is PER-FRAGMENT once a paragraph style can change the line height: the
 * fragment records its own when it is laid out, and a caller holding a caret does not have to reconstruct the
 * arithmetic that put it there. */
- (CGFloat)cg_baselineForGlyphAtIndex:(NSUInteger)glyphIndex;

/* AND THE LINE HEIGHT THE FRAGMENTS ARE LAID IN, so a caller that owns a view's height does not have to guess the
 * font the manager measured with. */
- (CGFloat)cg_lineHeight;

/* ---- THE DRAWING, WHICH IS WHAT A VIEW CALLS AND WHO ELSE WOULD --------------------------------------- */

/* **THE INK, AND THE DOOR `NSTextView` CALLS.** Apple's comment gives the contract exactly: "draws the actual glyphs,
 * including attachments, as well as any underlines or strikethroughs… all of the specified glyphs must lie in a single
 * container. The origin point … is that container's origin in the currently focused view's coordinates." So the
 * fragments are read, each one's line is set at the origin the caller gave, and THE FOCUS MUST ALREADY BE LOCKED —
 * which is why this door does no locking of its own. */
- (void)drawGlyphsForGlyphRange:(NSRange)glyphsToShow atPoint:(NSPoint)origin;

/* **AND THE RECT A RANGE OCCUPIES, WHICH IS WHAT AN INVALIDATION IS SPELLED IN.** "The smallest bounding rect which
 * completely encloses the glyphs in the given glyphRange that are in the given container… always in container
 * coordinates." It is the union of the fragments the range touches — the same arithmetic `-usedRectForTextContainer:`
 * does for the whole store. */
- (NSRect)boundingRectForGlyphRange:(NSRange)glyphRange inTextContainer:(NSTextContainer *)container;

/* **THE BACKGROUND THE GLYPHS SIT ON, WHICH IS A RUN WALK OVER THE BLOCKS.** Apple's door paints "the background
 * color and selection and marked range aspects of the text display, along with block decoration such as table
 * backgrounds and borders". THE DIVISION THIS TIER DRAWS IS: the background-COLOUR ATTRIBUTE and the BLOCK DECORATION
 * are the manager's (both are in the store's runs and paragraph styles), and the SELECTION is the VIEW's (only the
 * view knows where it is). The blocks go down first — a box is behind every run background — each one grown by its own
 * layers and drawn by the block itself; a table that collapses its borders draws a shared edge ONCE, by whichever
 * block — the table itself on an outer edge, a neighbouring cell on an inner one — has the heavier border on it, so
 * each block is handed the mask of edges it owns; the marked range is the view's, drawn with the composition rule.
 * Each run's
 * `NSBackgroundColorAttributeName` then fills the used rect of ITS OWN glyphs, which is what makes two backgrounds on
 * one line two rectangles instead of a band. */
- (void)drawBackgroundForGlyphRange:(NSRange)glyphsToShow atPoint:(NSPoint)origin;

/* ==================================================================================================================
 * THE TEMPORARY ATTRIBUTES — runs the LAYOUT sees and the STORE does not.
 *
 * **A TEMPORARY ATTRIBUTE IS A HIGHLIGHT THAT IS NOT AN EDIT.** The classic user is a find: the results are painted while
 * the search is showing and must vanish when it closes, and putting them in the store would make them undoable text. So
 * Apple keeps a second table beside the store, read only by the DRAWING pass — which is why this tier's `-drawGlyphs…`
 * and `-drawBackground…` now read their runs through one helper that merges the two tables, temporary winning, and why
 * every door here is a table operation and nothing else.
 *
 * **AND THE DRAWING PASS ASKS THE DELEGATE FIRST.** `-layoutManager:shouldUseTemporaryAttributes:forDrawingToScreen:
 * atCharacterIndex:effectiveRange:` is the era's way for a view to switch the whole table off for a pass (a print
 * operation does, and so does a screen that would rather not show the flash); a delegate that answers NO gets the
 * store's attributes and no temporary ink.
 *
 * **THE EFFECTIVE-RANGE DOORS REPORT THE RUN, NOT THE QUERY.** An attribute set over `{2, 6}` answers `{2, 6}` when
 * asked about index 4, and the `longestEffectiveRange:inRange:` pair clips that to the caller's limit — the same
 * longest-run contract the store's own doors keep, which is what lets a caller walk the table without seeing the same
 * value twice.
 * ================================================================================================================ */

- (void)addTemporaryAttribute:(NSString *)attrName value:(id)value forCharacterRange:(NSRange)charRange;
- (void)addTemporaryAttributes:(NSDictionary *)attrs forCharacterRange:(NSRange)charRange;
- (void)removeTemporaryAttribute:(NSString *)attrName forCharacterRange:(NSRange)charRange;
- (void)setTemporaryAttributes:(NSDictionary *)attrs forCharacterRange:(NSRange)charRange;

- (nullable id)temporaryAttribute:(NSString *)attrName atCharacterIndex:(NSUInteger)location
		    effectiveRange:(nullable NSRangePointer)range;
- (nullable id)temporaryAttribute:(NSString *)attrName atCharacterIndex:(NSUInteger)location
	     longestEffectiveRange:(nullable NSRangePointer)range inRange:(NSRange)rangeLimit;
- (nullable NSDictionary *)temporaryAttributesAtCharacterIndex:(NSUInteger)location
					       effectiveRange:(nullable NSRangePointer)range;
- (nullable NSDictionary *)temporaryAttributesAtCharacterIndex:(NSUInteger)location
					longestEffectiveRange:(nullable NSRangePointer)range
						      inRange:(NSRange)rangeLimit;

/* **AND WHAT IS STILL NOT HERE, NAMED AT THE DOOR THAT WOULD BE IT.** The MARKED RANGE belongs to the marked-text
 * family: it is the unconfirmed text an input method is composing, and `NSTextView` already carries it (`_cg_markedRange`)
 * — the manager's door for it arrives with the input-method slice, and is named rather than half-drawn. */

/* ==================================================================================================================
 * THE RECT ARRAYS — the boxes a range OCCUPIES, one per line, which is what a selection redraw is spelled in.
 *
 * **APPLE'S RETURN IS A POINTER, NOT AN ARRAY OBJECT**, and that is the door's whole shape: the manager fills its own
 * buffer and answers a pointer valid until the next call, so a caller that walks a selection's rects does not allocate
 * one array per line. This tier keeps that buffer for the same reason.
 *
 * **THE `withinSelected…` ARGUMENT IS TAKEN AND CONSULTED, AND THIS TIER'S BREAKER GIVES IT NOTHING TO DECIDE.** A
 * line's rects are its glyphs' extent; the one place a selection changes the answer in Apple's text system is the EMPTY
 * fragment at the end of a trailing newline, whose rect is included only when the selection reaches it. THIS TIER'S
 * BREAKER DOES NOT PRODUCE THAT FRAGMENT — a trailing newline's glyph belongs to the line it ends, and the only
 * zero-glyph fragment is an empty document's, which is the caret case — so both selections answer the same rects. The
 * branch is kept because the rule is the DOOR's rather than the layout's: a breaker that produced the fragment would get
 * the behaviour for free, and the test asserts the state that is true today rather than the one the parameter is named
 * for.
 * ================================================================================================================ */

- (NSRect *)rectArrayForCharacterRange:(NSRange)charRange
	   withinSelectedCharacterRange:(NSRange)selCharRange
			inTextContainer:(NSTextContainer *)container
			     rectCount:(NSUInteger *)rectCount;

- (NSRect *)rectArrayForGlyphRange:(NSRange)glyphRange
	withinSelectedGlyphRange:(NSRange)selGlyphRange
		 inTextContainer:(NSTextContainer *)container
		      rectCount:(NSUInteger *)rectCount;

/* ==================================================================================================================
 * THE FRAGMENT QUERIES — what is laid out, and which container holds a given glyph.
 *
 * **THESE ARE THE DOORS THAT NEED NO CLUSTER MAPPING**, which is why they come first. A fragment here carries the
 * CHARACTER span the breaker decided, the GLYPH span the shaper produced, the line's two rects and its baseline — so
 * "which line is this glyph in", "where does that line start", "is this index real" and "which container is it in" are
 * arithmetic over that record. The glyph-to-character doors need the shaper's cluster table and were LEFT OUT of this
 * slab on purpose — a mapping invented without it would answer a plausible wrong index, which is worse than answering
 * nothing — and they arrive in the block AFTER this one, built on the table the manager already keeps.
 *
 * **`withoutAdditionalLayout:` IS TAKEN AND IGNORED**, and that is stated rather than implied: this tier lays a
 * container out in full when it is asked for anything, so there is no partially-laid state for the flag to protect.
 * The two-argument doors and the three-argument doors therefore answer the same rect, and the test asserts exactly that
 * so the claim stays true.
 * ================================================================================================================ */

/* Is this a glyph index the manager has? Apple's own question, and it is the guard every other door needs. */
- (BOOL)isValidGlyphIndex:(NSUInteger)glyphIndex;

/* How much has NOT been laid out. This tier lays out on demand and in full, so after asking these are the totals: the
 * store's length and the manager's glyph count. */
- (NSUInteger)firstUnlaidCharacterIndex;
- (NSUInteger)firstUnlaidGlyphIndex;

/* THE CONTAINER THAT HOLDS A GLYPH, and by reference the whole range that container carries — NOT the line's range,
 * which is what `-lineFragmentRectForGlyphAtIndex:…` answers. */
- (nullable NSTextContainer *)textContainerForGlyphAtIndex:(NSUInteger)glyphIndex
					    effectiveRange:(nullable NSRangePointer)effectiveGlyphRange;
- (nullable NSTextContainer *)textContainerForGlyphAtIndex:(NSUInteger)glyphIndex
					    effectiveRange:(nullable NSRangePointer)effectiveGlyphRange
				     withoutAdditionalLayout:(BOOL)flag;

/* THE LINE'S TWO RECTS, asking-the-same-question forms of the pair above them. */
- (NSRect)lineFragmentRectForGlyphAtIndex:(NSUInteger)glyphIndex
			   effectiveRange:(nullable NSRangePointer)effectiveGlyphRange
		    withoutAdditionalLayout:(BOOL)flag;
- (NSRect)lineFragmentUsedRectForGlyphAtIndex:(NSUInteger)glyphIndex
			       effectiveRange:(nullable NSRangePointer)effectiveGlyphRange
			withoutAdditionalLayout:(BOOL)flag;


/* ==================================================================================================================
 * THE GLYPH-TO-CHARACTER MAPPING — the doors the slab above deliberately left out.
 *
 * **A CHARACTER SPAN AND A GLYPH SPAN ARE NOT THE SAME WIDTH**, which is why a fragment keeps both: an `fi` ligature is
 * one glyph for two characters, and a combining mark is a glyph of its own with no character of its own. This tier
 * already had the cluster table the mapping needs — `fn_characterForGlyphOffsetInLine` and
 * `fn_glyphOffsetForCharacterInLine` walk `CTRunGetStringIndices`, and were written for
 * `-glyphRangeForCharacterRange:` — so these are that machinery given Apple's names rather than a second mapping.
 *
 * **`-locationForGlyphAtIndex:` ANSWERS IN LINE-FRAGMENT COORDINATES**, which is Apple's contract for it and the reason
 * its y is the baseline's offset WITHIN the fragment: a caller adding the fragment rect's origin gets the container
 * point back, and a caller placing something inside a fragment does not have to subtract it.
 *
 * **AN OUT-OF-RANGE INDEX ANSWERS `NSNotFound` WHERE APPLE RAISES.** This tier's drawing doors answer their type's
 * empty value instead of throwing (the rule `AppKitRefusal.h` states), and a hit test that throws takes the window down
 * with it — so the guard is an answer, not an exception.
 * ================================================================================================================ */

/* The first character the given glyph stands for. */
- (NSUInteger)characterIndexForGlyphAtIndex:(NSUInteger)glyphIndex;
/* The first glyph the given character contributes to. */
- (NSUInteger)glyphIndexForCharacterAtIndex:(NSUInteger)charIndex;

/* The glyph's location RELATIVE TO ITS LINE FRAGMENT's origin, on its baseline. */
- (NSPoint)locationForGlyphAtIndex:(NSUInteger)glyphIndex;

/* THE POINT DOORS. `partialFraction` is how far INTO the character or glyph the point fell — the number a selection drag
 * needs to decide whether the caret sits before or after a ligature. */
- (NSUInteger)characterIndexForPoint:(NSPoint)point
		     inTextContainer:(NSTextContainer *)container
     fractionOfDistanceBetweenInsertionPoints:(nullable CGFloat *)partialFraction;
- (NSUInteger)glyphIndexForPoint:(NSPoint)point inTextContainer:(NSTextContainer *)container;
- (NSUInteger)glyphIndexForPoint:(NSPoint)point
		 inTextContainer:(NSTextContainer *)container
     fractionOfDistanceThroughGlyph:(nullable CGFloat *)partialFraction;
- (CGFloat)fractionOfDistanceThroughGlyphForPoint:(NSPoint)point inTextContainer:(NSTextContainer *)container;



/* ==================================================================================================================
 * THE GLYPH STORE AND ITS DOORS.
 *
 * **THE STORE IS A SHADOW OF THE LAYOUT RATHER THAN ITS SOURCE.** Apple's typesetter writes glyphs into a store and the
 * breaker reads them; this tier's breaker produces `CTLine`s and the glyphs are read back OUT of what it shaped. So the
 * store is built from the fragments whenever the layout is rebuilt, and these doors read and write THAT record. A
 * caller's edits — a moved location, a hidden glyph, an integer attribute — therefore survive until the text changes,
 * which is exactly the lifetime Apple gives them before its own layout invalidates.
 *
 * **THE THREE COUNT-CHANGING DOORS REFUSE BY NAME** (`insertGlyph:`, `insertGlyphs:…`, `deleteGlyphsInRange:`), and
 * the reason is the shadow rather than a missing subsystem: adding or removing a glyph means the text and the store
 * disagree about how many glyphs there are, and the next re-layout would discard the edit anyway. A door that appears
 * to succeed and is undone by the next keystroke is worse than one that says why.
 * ================================================================================================================ */

/* The glyph at an index, and the flag-carrying form Apple also declares. */
- (NSGlyph)glyphAtIndex:(NSUInteger)glyphIndex;
- (NSGlyph)glyphAtIndex:(NSUInteger)glyphIndex isValidIndex:(nullable BOOL *)isValidIndex;
/* Fill a caller's buffer with a glyph range. */
- (void)getGlyphs:(NSGlyph *)glyphArray range:(NSRange)glyphRange;

/* THE PER-GLYPH FLAGS AND ATTRIBUTES: what a typesetter records about a glyph that is not its identity. */
- (BOOL)notShownAttributeForGlyphAtIndex:(NSUInteger)glyphIndex;
- (void)setNotShownAttribute:(BOOL)flag forGlyphAtIndex:(NSUInteger)glyphIndex;
- (BOOL)drawsOutsideLineFragmentForGlyphAtIndex:(NSUInteger)glyphIndex;
- (void)setDrawsOutsideLineFragment:(BOOL)flag forGlyphAtIndex:(NSUInteger)glyphIndex;
- (NSInteger)intAttribute:(NSInteger)attributeTag forGlyphAtIndex:(NSUInteger)glyphIndex;
- (void)setIntAttribute:(NSInteger)attributeTag value:(NSInteger)val forGlyphAtIndex:(NSUInteger)glyphIndex;

/* THE RECORD'S OWN FIELDS, WRITABLE: where the glyph sits, which character it stands for, and which glyph it is. */
- (void)setLocation:(NSPoint)location forStartOfGlyphRange:(NSRange)glyphRange;
- (void)setCharacterIndex:(NSUInteger)charIndex forGlyphAtIndex:(NSUInteger)glyphIndex;
- (void)replaceGlyphAtIndex:(NSUInteger)glyphIndex withGlyph:(NSGlyph)newGlyph;

/* THE COUNT-CHANGING THREE, DECLARED AND REFUSED. */
- (void)insertGlyph:(NSGlyph)glyph atGlyphIndex:(NSUInteger)glyphIndex characterIndex:(NSUInteger)characterIndex;
- (void)insertGlyphs:(const NSGlyph *)glyphs length:(NSUInteger)length
	forStartingGlyphAtIndex:(NSUInteger)glyphIndex characterIndex:(NSUInteger)characterIndex;
- (void)deleteGlyphsInRange:(NSRange)glyphRange;

/* Rebuild the shadow from the fragments. Public as a `cg_` door because the store's correctness is what the test
 * asserts, and a caller that mutated the fragments by hand needs a way to say so. */
- (void)cg_rebuildGlyphStore;

/* ==================================================================================================================
 * THE STORE'S BULK DOORS — the same record, read and written a range at a time.
 *
 * **`NSGlyphInscription` IS THE ERA'S VOCABULARY FOR WHERE A GLYPH SITS RELATIVE TO THE BASELINE**, and this tier lays
 * every glyph on it: the four values are declared here because Apple declares them in this header, and every glyph
 * answers `NSGlyphInscribeBase`. A caller that wants an overstrike composes it from two runs, which is what the era's
 * own text system did too.
 *
 * **THE TWO `getGlyphsInRange:` DOORS FILL FOUR OR FIVE PARALLEL BUFFERS**, and every one of them is optional except
 * the glyphs: the character each glyph stands for, its inscription, whether it is elastic (this tier's are not, because
 * the breaker does not stretch), and — in the longer spelling — its bidi level, which is 0 in one direction. The count
 * is the RANGE's, not the store's: a buffer is filled for every index the caller named, with `NSNullGlyph` past the end,
 * which is how a caller asks for a run that overlaps the edge of the text.
 *
 * **AND THE TWO WRITERS ARE THE SUB-CLASS DOORS.** `-setLocations:startingGlyphIndexes:count:forGlyphRange:` is
 * `-setLocation:forStartOfGlyphRange:` a range at a time (Apple's arrays name the START of each stretch and its point);
 * `-setLineFragmentRect:forGlyphRange:usedRect:` moves the line fragments the range covers, which is what a manager
 * that placed its own lines would do. Both write the SHADOW, so both survive until the next re-layout — the lifetime
 * the section above explains.
 * ================================================================================================================ */

enum {
	NSGlyphInscribeBase = 0,
	NSGlyphInscribeBelow = 1,
	NSGlyphInscribeAbove = 2,
	NSGlyphInscribeOverstrike = 3,
	NSGlyphInscribeOverBelow = 4
};
typedef NSUInteger NSGlyphInscription;

- (void)getGlyphsInRange:(NSRange)glyphRange
		  glyphs:(NSGlyph *)glyphBuffer
	characterIndexes:(NSUInteger *)charIndexBuffer
       glyphInscriptions:(NSGlyphInscription *)inscribeBuffer
	     elasticBits:(nullable BOOL *)elasticBuffer;

- (void)getGlyphsInRange:(NSRange)glyphRange
		  glyphs:(NSGlyph *)glyphBuffer
	characterIndexes:(NSUInteger *)charIndexBuffer
       glyphInscriptions:(NSGlyphInscription *)inscribeBuffer
	     elasticBits:(nullable BOOL *)elasticBuffer
	      bidiLevels:(nullable unsigned char *)bidiLevelBuffer;

- (void)setLocations:(NSPoint *)locations
startingGlyphIndexes:(NSUInteger *)glyphIndexes
	       count:(NSUInteger)count
      forGlyphRange:(NSRange)glyphRange;

- (void)setLineFragmentRect:(NSRect)fragmentRect
	       forGlyphRange:(NSRange)glyphRange
		    usedRect:(NSRect)usedRect;

/* **WHICH CONTAINER A GLYPH RANGE IS IN, WHEN A CALLER KNOWS BETTER THAN THE FRAGMENTS DO.** A subclass that lays out
 * by its own rules says so here; the read doors consult the record before their own scan, and a range with no entry is
 * answered by the layout as usual. */
- (void)setTextContainer:(NSTextContainer *)container forGlyphRange:(NSRange)glyphRange;

/* ==================================================================================================================
 * THE STRIKETHROUGH PAIR, AND THE BACKGROUND FILL — the ink doors that pair with the underline pair above.
 *
 * **THE SAME TWO HALVES AS THE UNDERLINE, FOR THE SAME REASON.** `-strikethroughGlyphRange:…` decides WHICH glyphs get
 * the rule (it trims the leading and trailing whitespace, so a struck-through run does not begin with a ruled space) and
 * `-drawStrikethroughForGlyphRange:…` puts it down, through the mid-x-height instead of under the baseline. The ink is
 * the run's `NSStrikethroughColorAttributeName`, then its foreground, then the caller's default — which is the order the
 * manager's own drawing pass uses, because it is the same run walk.
 *
 * **AND `-fillBackgroundRectArray:count:forCharacterRange:color:` IS THE FILL A VIEW DOES WITH THE RECTS IT WAS
 * GIVEN.** It takes an array rather than computing one: the caller already knows which pieces of a selection or a
 * background it wants painted, and asking the layout again would be a second answer to a question already answered.
 * ================================================================================================================ */

- (void)drawStrikethroughForGlyphRange:(NSRange)glyphRange
		     strikethroughType:(NSInteger)strikethroughVal
			baselineOffset:(CGFloat)baselineOffset
		      lineFragmentRect:(NSRect)lineRect
	       lineFragmentGlyphRange:(NSRange)lineGlyphRange
		       containerOrigin:(NSPoint)containerOrigin;

- (void)strikethroughGlyphRange:(NSRange)glyphRange
	     strikethroughType:(NSInteger)strikethroughVal
		lineFragmentRect:(NSRect)lineRect
	 lineFragmentGlyphRange:(NSRange)lineGlyphRange
		 containerOrigin:(NSPoint)containerOrigin;

- (void)fillBackgroundRectArray:(const NSRect *)rectArray
			  count:(NSUInteger)rectCount
	     forCharacterRange:(NSRange)charRange
			  color:(NSColor *)color;

/* ==================================================================================================================
 * TWO LAST SINGLES.
 *
 * **`-rangeOfNominallySpacedGlyphsContainingIndex:` IS A KERNING QUESTION.** A glyph is nominally spaced when its advance
 * is the font's own for that glyph; a run of them is the range a caller can measure without consulting every kern pair,
 * and it ENDS at the first glyph whose advance differs. This tier's layout applies no kerning of its own — the shaper's
 * positions are the font's — so the answer is normally the line's glyphs; the walk is written anyway, because "normally"
 * is not a contract and the door's name promises the boundary rather than the common case.
 *
 * **`-showPackedGlyphs:…` REFUSES BY NAME.** "Packed glyphs" are the pre-10.4 encoding (`NSPackedGlyphs`) that the
 * Carbon text path consumed; this tier's `CGContext` takes a `CGGlyph` array, so the door answers nothing and says why
 * rather than reinterpreting bytes that mean something else. `-substituteFontForFont:` is real, and quick, because this
 * tier has no screen-font variants and the answer is the font itself.
 * ================================================================================================================ */

- (NSRange)rangeOfNominallySpacedGlyphsContainingIndex:(NSUInteger)glyphIndex;
- (void)showPackedGlyphs:(char *)glyphs length:(NSUInteger)glyphLen glyphRange:(NSRange)glyphRange
		  atPoint:(NSPoint)point font:(NSFont *)font color:(NSColor *)color
      printingAdjustment:(NSSize)printingAdjustment;
- (NSFont *)substituteFontForFont:(NSFont *)originalFont;


/* ==================================================================================================================
 * THE UNDERLINE DOORS — and the spell-check squiggle they exist for.
 *
 * **TWO DOORS BECAUSE APPLE HAS TWO, AND THE SPLIT IS THE INTERESTING PART.** `-underlineGlyphRange:…` decides WHICH
 * glyphs get ink — it trims the leading and trailing whitespace off a range, because underlining the space after a
 * misspelled word looks like a bug — and `-drawUnderlineForGlyphRange:…` puts the ink down. A caller that only wants a
 * line under exactly what it named calls the second; a caller underlining a run that may include spaces calls the first.
 *
 * **THE INK IS THE CALLER'S STROKE COLOUR.** Apple reads it from the temporary-attribute table, which this tier has not
 * got; a colour parameter that the caller sets is the honest stand-in, and it is stated here rather than left for a
 * reader to discover when their underline comes out black.
 *
 * `underlineType` IS `NSUnderlineStyle`: the low bits choose the SHAPE (single, thick, double) and the high byte the
 * PATTERN (solid, dot, dash). This tier draws single, thick and double, and solid or dotted — the shapes a spell checker
 * and a link need. Any other pattern falls back to solid rather than to nothing, because a line at the wrong pattern is
 * still a line and a missing one reads as "not underlined".
 * ================================================================================================================ */

- (void)drawUnderlineForGlyphRange:(NSRange)glyphRange
		     underlineType:(NSInteger)underlineVal
		    baselineOffset:(CGFloat)baselineOffset
		  lineFragmentRect:(NSRect)lineRect
	   lineFragmentGlyphRange:(NSRange)lineGlyphRange
		   containerOrigin:(NSPoint)containerOrigin;

- (void)underlineGlyphRange:(NSRange)glyphRange
	      underlineType:(NSInteger)underlineVal
	   lineFragmentRect:(NSRect)lineRect
    lineFragmentGlyphRange:(NSRange)lineGlyphRange
	    containerOrigin:(NSPoint)containerOrigin;

/* ==================================================================================================================
 * THE BLOCK'S TWO RECTANGLES, AND THE ATTACHMENT'S SIZE.
 *
 * **A TEXT BLOCK OCCUPIES TWO RECTANGLES AND THE DIFFERENCE IS ITS OWN LAYERS.** The LAYOUT rect is where the block's
 * content is laid out — this tier's answer is the union of the used rects of the fragments that share the block, in the
 * text container's coordinates, which is where the glyphs actually are. The BOUNDS rect is what the block's padding,
 * border and margin make of that content, and it is computed by the block itself
 * (`-boundsRectForContentRect:inRect:textContainer:characterRange:`), so the frame a caller reads back is the frame
 * `-drawGlyphRange:…` draws. A block that is not in the layout answers `NSZeroRect`, which is Apple's answer and the
 * only honest one: there is no rectangle for something that was never laid out.
 *
 * **THE FOUR ACCESSORS COME IN TWO PAIRS: BY GLYPH RANGE AND BY ONE GLYPH.** Apple's `atIndex:` doors take a GLYPH
 * index and report a GLYPH range through `effectiveRange:` — the names in Apple's own header are `glyphIndex` and
 * `glyphRange` — which is why the effective range here is the block's glyphs and not its characters.
 *
 * **AND THE TWO SETTERS ARE A SUBCLASS'S, NOT A CALLER'S.** They store an override the getters consult first, which is
 * what a layout manager that places blocks by its own rules needs; nothing in this tier calls them.
 *
 * **AN ATTACHMENT'S SIZE IS WHAT THE LAYOUT RESERVED, AND IT CAN BE OVERRIDDEN.** `-attachmentSizeForGlyphAtIndex:`
 * answers the size the glyph's box occupies (which is the attachment cell's size unless a caller said otherwise), and
 * `-setAttachmentSize:forGlyphRange:` stores a size for a range and invalidates it, so the next layout reserves THAT
 * width. `-defaultAttachmentScaling` is the mode `-showAttachmentCell:inRect:characterIndex:` uses when a cell's own
 * size does not fit the rectangle it was given; its default is proportionally-down, which is what keeps an oversized
 * picture inside its line.
 * ================================================================================================================ */

- (NSRect)boundsRectForTextBlock:(NSTextBlock *)block glyphRange:(NSRange)glyphRange;
- (NSRect)layoutRectForTextBlock:(NSTextBlock *)block glyphRange:(NSRange)glyphRange;
- (void)setBoundsRect:(NSRect)rect forTextBlock:(NSTextBlock *)block glyphRange:(NSRange)glyphRange;
- (void)setLayoutRect:(NSRect)rect forTextBlock:(NSTextBlock *)block glyphRange:(NSRange)glyphRange;

- (NSRect)boundsRectForTextBlock:(NSTextBlock *)block atIndex:(NSUInteger)glyphIndex
		  effectiveRange:(nullable NSRangePointer)glyphRange;
- (NSRect)layoutRectForTextBlock:(NSTextBlock *)block atIndex:(NSUInteger)glyphIndex
		  effectiveRange:(nullable NSRangePointer)glyphRange;

- (void)setAttachmentSize:(NSSize)attachmentSize forGlyphRange:(NSRange)glyphRange;
- (NSSize)attachmentSizeForGlyphAtIndex:(NSUInteger)glyphIndex;

- (NSImageScaling)defaultAttachmentScaling;
- (void)setDefaultAttachmentScaling:(NSImageScaling)newScaling;

- (void)showAttachmentCell:(NSCell *)cell inRect:(NSRect)rect characterIndex:(NSUInteger)characterIndex;

/* ==================================================================================================================
 * THE MANAGER'S OWN KNOBS — and the one of them that changes the layout.
 *
 * **A KNOB THAT IS STORED AND NOT CONSULTED IS STILL A REAL DOOR, AND EACH ONE SAYS WHICH IT IS.** `-usesFontLeading`
 * is the live one: the line height this manager hands the breaker is the font's ascender minus its (negative) descender,
 * and leading on top of that when the flag is set — so a caller that turns it on gets taller lines. IT DEFAULTS TO NO,
 * WHICH IS A STATED DEVIATION FROM APPLE'S YES: this tier's layout has never included leading, and flipping the default
 * with the flag's arrival would move every document on screen by the font's leading — a change that belongs to a layout
 * slice, not to a flag's first appearance.
 *
 * The rest are stored and answered, and what each would MEAN is named at its door: non-contiguous layout (this tier lays
 * out in full, so it never has a hole), background layout (there is no background pass), screen fonts (this tier has no
 * screen-font variants), invisible and control characters (the drawing pass does not substitute for them yet), the
 * hyphenation factor (Apple deprecated it in 10.6 in favour of the paragraph style's, which is what this tier reads),
 * and `-layoutOptions` (a bitfield with no bits defined here).
 * ================================================================================================================ */

- (BOOL)allowsNonContiguousLayout;
- (void)setAllowsNonContiguousLayout:(BOOL)flag;
- (BOOL)hasNonContiguousLayout;

- (BOOL)backgroundLayoutEnabled;
- (void)setBackgroundLayoutEnabled:(BOOL)flag;

- (BOOL)showsInvisibleCharacters;
- (void)setShowsInvisibleCharacters:(BOOL)flag;
- (BOOL)showsControlCharacters;
- (void)setShowsControlCharacters:(BOOL)flag;

/* THE ONE LIVE KNOB: whether the line height carries the font's leading. See this section's note for the default. */
- (BOOL)usesFontLeading;
- (void)setUsesFontLeading:(BOOL)flag;

- (BOOL)usesScreenFonts;
- (void)setUsesScreenFonts:(BOOL)flag;

/* **THE 10.6 DEPRECATION IS THE HONEST ANSWER HERE.** Apple's own header says to use `NSParagraphStyle`'s
 * `-hyphenationFactor` instead, and that is exactly what this tier's breaker reads; this door stores the value so a
 * caller can read it back, and does not fall back to it, because a second source for one number is how two paragraphs
 * come to hyphenate differently from the same factor. */
- (float)hyphenationFactor;
- (void)setHyphenationFactor:(float)aFactor;

- (NSUInteger)layoutOptions;

/* ==================================================================================================================
 * AND THE CARET'S PLACES ON A LINE.
 *
 * **A LINE HAS ONE INSERTION POINT PER CHARACTER PLUS ONE AT ITS END, AND THAT IS WHAT THIS DOOR FILLS.** Apple's arrays
 * carry up to two positions per character for the bidirectional alternates — a position in the left-to-right run and one
 * in the right-to-left — and this tier lays out ONE direction, so `alternatePositions:` is taken and every character
 * answers once. The count is the number of points written, and `inDisplayOrder:` is ascending x, which is the order the
 * layout produces by construction.
 * ================================================================================================================ */

- (NSUInteger)getLineFragmentInsertionPointsForCharacterAtIndex:(NSUInteger)charIndex
					    alternatePositions:(BOOL)aFlag
						inDisplayOrder:(BOOL)dFlag
						     positions:(CGFloat *)positions
					    characterIndexes:(NSUInteger *)charIndexes;

/* **AND "MAKE SURE THIS RECTANGLE IS LAID OUT" is this tier's whole layout, because a container is laid out in full
 * when anything is asked of it.** The rect is taken and not narrowed, for the same reason the `withoutAdditionalLayout:`
 * flags are. */
- (void)ensureLayoutForBoundingRect:(NSRect)bounds inTextContainer:(NSTextContainer *)container;

/* ==================================================================================================================
 * THE THREE QUESTIONS ABOUT THE VIEW A DOCUMENT IS SHOWN IN.
 * ================================================================================================================ */

/* The text view of the FIRST container — Apple's answer for a document laid out in one view, which is every document this
 * tier lays out. */
- (nullable NSTextView *)firstTextView;

/* **THE MANAGER DOES NOT KNOW WHERE THE SELECTION IS**, so the beginning of it is answered as the first view: the
 * selection is the VIEW's (this tier's `NSTextView` owns it) and a manager asked this without one has exactly that answer
 * to give. */
- (nullable NSTextView *)textViewForBeginningOfSelection;

/* And whether this manager's first view is the window's first responder, which is a real question with a real answer. */
- (BOOL)layoutManagerOwnsFirstResponderInWindow:(nullable NSWindow *)window;

/* ==================================================================================================================
 * THE RULER'S TWO DOORS, WHICH ARE THE TEXT SYSTEM'S HALF OF IT.
 *
 * **A TAB STOP IS A MARKER ON A RULER, AND THAT IDENTITY IS THE WHOLE OF THESE TWO METHODS.** `NSTextTab` is a location
 * and a kind; `NSRulerMarker` is a location and an image; so the manager builds one marker per tab stop, hands the tab
 * over as the marker's `representedObject`, and the ruler draws and drags it — after which the client view reads the
 * marker list back and writes the paragraph's tab stops from it. The kind is carried by the IMAGE (left, centre, right,
 * decimal), which is why four small bitmaps are the manager's rather than the ruler's: they are what a `NSTextTabType`
 * looks like.
 *
 * **THE LOCATION IS IN THE RULER'S OWN COORDINATES, WHICH MEANS IT INCLUDES THE ORIGIN OFFSET.** The offset is what
 * puts the ruler's zero at the text's left inset — the same number a tab stop is measured from — so a one-inch tab and
 * the one-inch hash mark land in the same place. A manager that returned the bare tab location would put every marker
 * four points to the left of the mark it names.
 *
 * **THE ACCESSORY STRIP IS DECLARED AND REFUSED**, which is this tier's vocabulary rather than an omission: Apple's is
 * the little control cluster that changes a tab's type, and it is a CONTROL this tier has not built, so the door
 * answers nil — the empty value of its type — and says so on stderr. A ruler that reserved room for nothing would be
 * worse than one that reserves none.
 * ================================================================================================================ */

- (NSArray *)rulerMarkersForTextView:(nullable NSTextView *)aTextView
		      paragraphStyle:(NSParagraphStyle *)style
			       ruler:(NSRulerView *)aRulerView;

- (nullable NSView *)rulerAccessoryViewForTextView:(nullable NSTextView *)aTextView
				    paragraphStyle:(NSParagraphStyle *)style
					      ruler:(NSRulerView *)aRulerView
					    enabled:(BOOL)isEnabled;

/* ==================================================================================================================
 * THE TYPESETTER TRIO — the last six selectors this class owed, and the two types this tier has not got.
 *
 * **THE OBJECTS ARE SPELLED `id`, AND THAT IS THE TREE'S RECORDED RULE RATHER THAN A SHORTCUT.** Apple's doors name
 * `NSTypesetter *` and `NSGlyphGenerator *`; this tier has neither class, and naming one in a header is exactly the trap
 * `NSScreen.h` records — a name in a header can CREDIT a class row that no implementation answers to. So the doors are
 * `id`, the way `NSEvent -trackingArea` is, and each answers its type's empty value (nil) until a caller sets one.
 *
 * **AND NOTHING CONSULTS THEM, WHICH IS SAID RATHER THAN IMPLIED.** The breaker here builds a `CTTypesetter` from the
 * store on every layout; there is no `NSTypesetter` in the flow, and a glyph generator is what Core Text's shaper does
 * with `CTLine`. A caller that sets either gets it back — round trip, nil clears, borrowed rather than retained — and a
 * caller expecting the object to DO something should know that it does not.
 *
 * **THE BEHAVIOUR IS A REAL VALUE WITH A REAL DEFAULT.** Apple's enum is declared in `NSTypesetter.h`, a header this tier
 * has not got, so it is declared here beside its only users; it must MOVE to `NSTypesetter.h` on the day that class
 * arrives, because two declarations of one enum is how the two come to disagree. The default is
 * `NSTypesetterLatestBehavior`, Apple's own, and the numbers are Apple's (the test pins them).
 * ================================================================================================================ */

typedef NSInteger NSTypesetterBehavior;
enum {
	NSTypesetterOriginalBehavior = 0,
	NSTypesetterMacOSX10_2BehaviorWithBaselines = 1,
	NSTypesetterMacOSX10_2Behavior = 2,
	NSTypesetterMacOSX10_3Behavior = 3,
	NSTypesetterLatestBehavior = -1
};

/* **Apple's `-typesetter` CREATES a default one on first ask; this tier has none to make**, so the answer is nil until a
 * caller sets one. That is the one behavioural difference in the trio and it is stated here rather than left to be found. */
- (nullable id)typesetter;
- (void)setTypesetter:(nullable id)typesetter;

- (nullable id)glyphGenerator;
- (void)setGlyphGenerator:(nullable id)glyphGenerator;

- (NSTypesetterBehavior)typesetterBehavior;
- (void)setTypesetterBehavior:(NSTypesetterBehavior)behavior;

@end


NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSLAYOUTMANAGER_H */
