/*
 * NSTrackingArea — a region of a view that wants the pointer's news.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE CLASS IS A VALUE PLUS ONE BIT OF LIVE STATE, AND THE BIT IS THE INTERESTING HALF.** The value — a rectangle,
 * an option word, an owner, a dictionary — is what the constructor stores and the accessors answer; the bit is
 * whether the pointer is inside the region RIGHT NOW, which is what makes an enter fire once and not on every motion.
 * It lives here rather than in a set on the window because it is a fact about THIS region: two areas in one view are
 * independent, and an area that dies takes its verdict with it, so a view removed from the hierarchy cannot leave the
 * window holding an "inside" that no longer refers to anything.
 *
 * THE WINDOW RESOLVES THE REGION, NOT THIS CLASS. `-rect` is in the VIEW's coordinates, and only a walk that knows
 * where the view currently sits can turn that into a place on the screen — so the arithmetic is the window's (see
 * `-cg_updateTrackingForPoint:`) and this class never converts anything. That split is deliberate: an area that
 * converted its own rect would have to know its view's whole ancestor chain, and would go stale the moment anything
 * above it moved.
 */
#import <AppKit/NSTrackingArea.h>

#include <stdio.h>

/* **THE ONE PIECE OF LIVE STATE, REACHED ONLY THROUGH HERE.** The ivar is protected, so the engine's doors have to be
 * implemented in the file that can see it — declared again in the two files that USE them (`NSView.m` for the removal
 * case, `NSWindow.m` for the walk), which is this tree's shape for a `cg_` door that is the tier's own business. */
@interface NSTrackingArea (APPKITTrackingEngine)
- (BOOL)cg_isInside;
- (void)cg_setInside:(BOOL)flag;
@end

@implementation NSTrackingArea

- (instancetype)initWithRect:(NSRect)rect options:(NSTrackingAreaOptions)options
		       owner:(id)owner userInfo:(NSDictionary *)userInfo
{
	if (owner == nil) {
		/* **AN AREA WITH NO OWNER IS NOT AN AREA**, which is Apple's own sentence and the reason this is a refusal
		 * rather than a stored nil: every door this class exists for delivers a message to `-owner`, so an area
		 * without one is a region whose whole purpose is unreachable — and a nil that later reaches a `respondsTo`
		 * check would look like an owner who declined rather than a caller who forgot. */
		[self release];
		return nil;
	}
	self = [super init];
	if (self != nil) {
		_rect = rect;
		_options = options;
		_owner = owner;		/* NOT retained: see the header */
		_userInfo = [userInfo retain];
		_cg_inside = (options & NSTrackingAssumeInside) != 0;
	}
	return self;
}

- (void)dealloc
{
	[_userInfo release];
	[super dealloc];
}

/* ---- THE FOUR READ-BACK DOORS ----------------------------------------------------------------- */

- (NSRect)rect
{
	return _rect;
}

- (NSTrackingAreaOptions)options
{
	return _options;
}

- (id)owner
{
	return _owner;
}

- (NSDictionary *)userInfo
{
	return _userInfo;
}

/* ---- AND THE TWO PROTOCOLS, WHICH ARE THE REASON THIS CLASS CAN BE STORED ---------------------- */
/* **A COPY IS A SECOND AREA OVER THE SAME REGION WITH THE SAME OWNER**, and it is a REAL copy rather than a retain —
 * the rule `NSColor.m` states for an immutable value does not reach here, because an area carries the live "is the
 * pointer inside" bit and two names for one area would share one verdict, so one of them would never see its own
 * enter. The userInfo is shared, because the dictionary describes the region rather than the area's walk.
 *
 * AND THE DOOR IS SPELLED `-copy` RATHER THAN `-copyWithZone:,` BECAUSE THIS TREE HAS NO ZONES** — `NSZone` is
 * deliberately undeclared and `NSCopying`'s only member is `-copy` (`NSObject.h` states the decision and its cost: a
 * Cocoa class that spelled `-copyWithZone:` would not conform, which is the error this line used to be). */
- (id)copy
{
	return [[NSTrackingArea alloc] initWithRect:_rect
					    options:_options
					      owner:_owner
					   userInfo:_userInfo];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeRect:_rect forKey:@"NSRect"];
	[coder encodeInteger:(NSInteger)_options forKey:@"NSOptions"];
	[coder encodeObject:_userInfo forKey:@"NSUserInfo"];
	/* **AND THE OWNER IS NOT WRITTEN, WHICH IS NOT AN OMISSION.** An archive names objects, not addresses, and the
	 * owner is by construction NOT RETAINED by this area — so encoding it would archive a reference to an object the
	 * area does not own, and decoding would hand the copy an owner that the archive had to keep alive for it. Apple's
	 * region is a description of WHERE and WHEN, and who is listening is a runtime fact that the caller re-supplies
	 * by installing the decoded area again. */
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
	NSRect rect = [coder decodeRectForKey:@"NSRect"];
	NSTrackingAreaOptions options = (NSTrackingAreaOptions)[coder decodeIntegerForKey:@"NSOptions"];
	id userInfo = [coder decodeObjectForKey:@"NSUserInfo"];

	/* THE OWNER COMES BACK AS NIL, and the constructor refuses a nil owner — so a decoded area is NOT an area yet.
	 * That is the honest consequence of the paragraph above: `-initWithCoder:` answers an object with the region and
	 * the options and NO owner, and the caller installs it with `-addTrackingArea:` only after... which it cannot,
	 * because the owner is part of the constructor. SO THE DOOR REFUSES BY NAME rather than returning a half-object,
	 * which is this tree's rule for a door whose far side is a fact the archive does not carry. */
	(void)rect; (void)options; (void)userInfo;
	fprintf(stderr, "APPKIT-REFUSE: -[NSTrackingArea initWithCoder:] — an archive carries the REGION and the OPTIONS "
			"but not the OWNER, and an area without an owner is not an area. Install a fresh area on the decoded "
			"rect with -addTrackingArea: instead.\n");
	[self release];
	return nil;
}

@end

@implementation NSTrackingArea (APPKITTrackingEngine)

- (BOOL)cg_isInside
{
	return _cg_inside;
}

/* **THE WRITE IS DUMB ON PURPOSE, AND THE ENGINE OWNS THE MESSAGE.** This door records where the pointer is; deciding
 * that a transition happened — and therefore that the owner owes a callback — is the walk's business (see
 * `NSWindow -cg_updateTrackingForPoint:`), because only the walk can see the other areas and the pointer's path. */
- (void)cg_setInside:(BOOL)flag
{
	_cg_inside = flag;
}

@end
