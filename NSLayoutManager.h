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

NS_ASSUME_NONNULL_BEGIN

@class NSTextStorage;
@class NSTextContainer;
@class NSLayoutManager;

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

/* **AND WHAT IS STILL NOT HERE, NAMED AT THE DOOR THAT WOULD BE IT.** The MARKED RANGE and the temporary-attribute
 * question belong to the marked-text family and the drawing delegate, neither of which is here: the marked range is the
 * unconfirmed text an input method is composing, and a temporary attribute is a run the layout sees and the store does
 * not. Both are the input-method slice's, and both are NAMED rather than half-drawn. */

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

@end


NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSLAYOUTMANAGER_H */
