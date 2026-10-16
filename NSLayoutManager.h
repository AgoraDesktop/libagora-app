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
 * WHAT IS HERE IS THE WEB RATHER THAN THE GLYPHS. The manager knows its STORE, it holds its CONTAINERS, an edit in the
 * store REACHES it, and it records that its layout is stale — which is the whole of the second type of invalidation and
 * the thing every later slice hangs off. WHAT IS NOT HERE IS THE FIRST TYPE: NO GLYPHS ARE GENERATED, NO LINES ARE LAID
 * OUT, nothing is drawn, and the character-to-glyph map is not built. Each of those is named at the door that would
 * answer it rather than stubbed, and the slice that lands glyphs is the one that can make them real.
 *
 * **AND THIS SLICE IS ALSO WHAT TURNS TWO DECLARATIONS INTO IMPLEMENTATIONS.** `NSTextStorage.h` refused
 * `-addLayoutManager:`/`-removeLayoutManager:`/`-layoutManagers` because they name a class that did not exist, and
 * `NSTextContainer.h` refused `-layoutManager`/`-setLayoutManager:` for the same reason. Both are here now, because the
 * class is: the storage owns a LIST of managers and calls `-setTextStorage:` on the way in and out, and the container
 * holds a BORROWED pointer to the one that lays it out.
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

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSLAYOUTMANAGER_H */
