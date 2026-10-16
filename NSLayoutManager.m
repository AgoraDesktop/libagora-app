/*
 * NSLayoutManager.m — the web: a store it is told about, containers it owns, and staleness it records.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE ONE THING THIS SLICE COMPUTES IS A UNION.** Everything else is a retained pointer, a borrowed pointer and an
 * array — and the union is what "the layout is stale from here" means once there are no glyphs to be stale ABOUT: the
 * store reports an edit, the manager folds the report into one range, and the delegate is told. THAT IS THE SEAM the
 * glyph slice will hang everything on, and it is deliberately the part that does not need glyphs.
 */
#import <AppKit/NSLayoutManager.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSTextContainer.h>
#import <Foundation/NSArray.h>

@implementation NSLayoutManager

- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		/* **A MANAGER STARTS WITHOUT A STORE AND WITHOUT A CONTAINER, WHICH IS APPLE'S OWN DESIGNATED-INITIALISER
		 * NOTE.** "The NSLayoutManager starts off without an NSTextStorage" — the store is added by
		 * `-addLayoutManager:` and the containers by this class's own doors. And NOTHING IS STALE, which is
		 * `NSNotFound` rather than a zero-length range at the start. */
		_textStorage = nil;
		_textContainers = [[NSMutableArray alloc] init];
		_invalidatedRange = NSMakeRange(NSNotFound, 0);
	}
	return self;
}

- (void)dealloc
{
	/* THE CONTAINERS' BACK-POINTERS GO FIRST, while both objects are still alive: a container that outlived this
	 * manager would otherwise hold a pointer to freed memory. */
	while ([_textContainers count] > 0) {
		NSTextContainer *container = [_textContainers lastObject];

		[container setLayoutManager:nil];
		[_textContainers removeLastObject];
	}
	[_textContainers release];
	[_textStorage release];
	[super dealloc];
}

/* ============================================================================================ *
 * THE STORE, WHICH THE STORAGE DRIVES                                                           *
 * ============================================================================================ */

- (NSTextStorage *)textStorage
{
	return _textStorage;
}

/* **THE PRIMITIVE STORES AND NOTHING ELSE.** It does NOT reach back into the storage's manager list, because that list
 * is what CALLS it — `-addLayoutManager:` sets this and then owns the reference — and a primitive that registered itself
 * would recurse. What a caller wants is `[store addLayoutManager:manager]` or `-replaceTextStorage:`. */
- (void)setTextStorage:(NSTextStorage *)aTextStorage
{
	if (aTextStorage != _textStorage) {
		NSTextStorage *held = [aTextStorage retain];

		[_textStorage release];
		_textStorage = held;
		[self invalidateLayoutForCharacterRange:NSMakeRange(0, [_textStorage length]) actualCharacterRange:NULL];
	}
}

/* **AND THIS IS THE DOOR A CALLER USES TO MOVE A MANAGER BETWEEN STORES.** Apple's comment says it is to be used
 * "instead of the primitive" precisely because the primitive cannot do the two halves that cross the object boundary:
 * OFF the old storage's list and ONTO the new one's. Each of those calls the primitive on this side, so the pointer is
 * never written by hand here. */
- (void)replaceTextStorage:(NSTextStorage *)newTextStorage
{
	if (_textStorage != nil) {
		[_textStorage removeLayoutManager:self];
	}
	if (newTextStorage != nil) {
		[newTextStorage addLayoutManager:self];
	}
}

- (NSAttributedString *)attributedString
{
	/* THE STORE, SEEN AS AN ATTRIBUTED STRING — which for a layout manager it IS, and Apple's own header says so. Nil
	 * when there is no store, because a glyph generator asking this before the web is built has nothing to be given. */
	return _textStorage;
}

/* ============================================================================================ *
 * THE CONTAINERS, WHICH THIS MANAGER OWNS AND THEY BORROW                                       *
 * ============================================================================================ */

- (NSArray *)textContainers
{
	return [[_textContainers copy] autorelease];
}

- (void)addTextContainer:(NSTextContainer *)container
{
	[self insertTextContainer:container atIndex:[_textContainers count]];
}

/* **THE CONTAINER IS TOLD WHO LAID IT OUT, WHICH IS THE OTHER HALF OF OWNERSHIP.** This manager RETAINS the container
 * (the array does), and the container holds a BORROWED pointer back — the same split `-superview` uses, and the reason
 * the container's `-setLayoutManager:` does not retain. Adding a container makes every character after the previous
 * last one stale, which is Apple's own note on the door and is the truth here too: the new container is room that did
 * not exist. */
- (void)insertTextContainer:(NSTextContainer *)container atIndex:(NSUInteger)index
{
	if (container == nil) {
		return;
	}
	/* **A CONTAINER IS LAID OUT IN ONE PLACE, SO IT LEAVES THE MANAGER IT WAS ON.** A container holds ONE borrowed
	 * pointer, so a manager that adopted it without releasing it from the previous one would leave the old manager
	 * LISTING a container that says it belongs to somebody else — and laying it out. MEASURED: an earlier version did
	 * exactly that, and the probe caught it from the other side (`[first textContainers]` still held it). */
	{
		NSLayoutManager *previous = [container layoutManager];

		if (previous != nil && previous != self) {
			NSArray *held = [[previous textContainers] retain];
			NSUInteger i;

			for (i = 0; i < [held count]; i++) {
				if ([held objectAtIndex:i] == container) {
					[previous removeTextContainerAtIndex:i];
					break;
				}
			}
			[held release];
		}
	}
	[_textContainers insertObject:container atIndex:index];
	[container setLayoutManager:self];
	[self invalidateLayoutForCharacterRange:NSMakeRange(0, [_textStorage length]) actualCharacterRange:NULL];
}

- (void)removeTextContainerAtIndex:(NSUInteger)index
{
	NSTextContainer *container = [[_textContainers objectAtIndex:index] retain];

	[container setLayoutManager:nil];
	[_textContainers removeObjectAtIndex:index];
	[container release];
	[self invalidateLayoutForCharacterRange:NSMakeRange(0, [_textStorage length]) actualCharacterRange:NULL];
}

- (void)setTextContainer:(NSTextContainer *)aContainer
{
	while ([_textContainers count] > 0) {
		[self removeTextContainerAtIndex:([_textContainers count] - 1)];
	}
	if (aContainer != nil) {
		[self addTextContainer:aContainer];
	}
}

/* ============================================================================================ *
 * STALENESS                                                                                     *
 * ============================================================================================ */

/* **THE STORE'S REPORT, WHICH IS SPELLED IN THE DOOR BELOW.** The two ranges mean different things — the OLD range is
 * what the storage's record holds, the NEW one is what changed in the string it holds now, and attribute fixing is what
 * could make the second larger — and with no attribute fixing to do here they are the same span in the two strings. */
- (void)textStorage:(NSTextStorage *)aTextStorage
	     edited:(NSUInteger)editedMask
	      range:(NSRange)oldRange
   changeInLength:(NSInteger)delta
  invalidatedRange:(NSRange)newCharRange
{
	(void)aTextStorage;
	(void)editedMask;
	(void)oldRange;
	(void)delta;
	[self invalidateLayoutForCharacterRange:newCharRange actualCharacterRange:NULL];
}

/* AND THE DOOR EVERYTHING ELSE USES, which folds the range into the stale one and tells the delegate. */
- (void)invalidateLayoutForCharacterRange:(NSRange)charRange actualCharacterRange:(NSRange *)actualCharRange
{
	if (charRange.location == NSNotFound) {
		return;		/* nothing to mark: an empty record is not an edit */
	}
	if (_invalidatedRange.location == NSNotFound) {
		_invalidatedRange = charRange;
	} else {
		NSUInteger lo = (_invalidatedRange.location < charRange.location) ? _invalidatedRange.location
										 : charRange.location;
		NSUInteger a = _invalidatedRange.location + _invalidatedRange.length;
		NSUInteger b = charRange.location + charRange.length;

		_invalidatedRange = NSMakeRange(lo, ((a > b) ? a : b) - lo);
	}
	if (actualCharRange != NULL) {
		/* **THE RANGE THAT WAS ACTUALLY INVALIDATED**, which a caller uses to know how much of its request was
		 * answered. Nothing narrows the request here — there are no runs to walk — so it is the range asked for. */
		*actualCharRange = charRange;
	}
	if (_delegate != nil && [_delegate respondsToSelector:@selector(layoutManagerDidInvalidateLayout:)]) {
		[_delegate layoutManagerDidInvalidateLayout:self];
	}
}

- (NSRange)cg_invalidatedRange
{
	return _invalidatedRange;
}

- (id <NSLayoutManagerDelegate>)delegate
{
	return _delegate;
}

- (void)setDelegate:(id <NSLayoutManagerDelegate>)anObject
{
	/* NOT RETAINED, and not released on the way out: this tree's rule for every delegate. */
	_delegate = anObject;
}

@end
