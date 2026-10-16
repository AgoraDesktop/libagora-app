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
 * this slice asks the CONTAINER how wide a line may be, breaks the store's string into LINE FRAGMENTS with the same
 * TYPESETTER the text view uses, and answers where each fragment is — which is what `-usedRectForTextContainer:` is
 * the size of, and what a view will draw into.
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

/* **THE MAP IS COMPUTED FROM THE STORED GLYPHS, AND IT COMES OUT ONE TO ONE.** Apple's two doors exist because a glyph
 * store can hold FEWER or MORE glyphs than there are characters — a ligature is two characters and one glyph, a
 * precomposed character may be two. This tier's `CTLine` maps every character to exactly one glyph through
 * `CTFontGetGlyphsForCharacters`, so the arithmetic below finds the fragment a character is in, adds the glyphs of the
 * fragments before it, and answers a range the same length — which is the identity ARRIVED AT rather than assumed. */
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
 * layers and drawn by the block itself; a table that collapses its borders draws a shared edge ONCE, by whichever of
 * the two cells has the heavier border on it, so the block is handed the mask of edges it owns; the marked range is
 * the view's, drawn with the composition rule. Each run's
 * `NSBackgroundColorAttributeName` then fills the used rect of ITS OWN glyphs, which is what makes two backgrounds on
 * one line two rectangles instead of a band. */
- (void)drawBackgroundForGlyphRange:(NSRange)glyphsToShow atPoint:(NSPoint)origin;

/* **AND WHAT IS STILL NOT HERE, NAMED AT THE DOOR THAT WOULD BE IT.** The MARKED RANGE and the temporary-attribute
 * question belong to the marked-text family and the drawing delegate, neither of which is here: the marked range is the
 * unconfirmed text an input method is composing, and a temporary attribute is a run the layout sees and the store does
 * not. Both are the input-method slice's, and both are NAMED rather than half-drawn. */

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSLAYOUTMANAGER_H */
