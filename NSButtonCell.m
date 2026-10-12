/*
 * NSButtonCell — a cell that knows it is a button, and the link that lets a menu item's cell be re-based.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * THE WHOLE SLICE IS STORAGE WITH ONE COPY, and the interesting parts are the two that could have been guessed at:
 * `-alternateTitle` is a copy (a caller's mutable string must not change the button's face later), and the sound and
 * the background colour are BARE POINTERS, because both outlive the cell that refers to them — the same split this
 * family has used since `NSCell` first kept an object value.
 *
 * AND THE DEFAULTS ARE APPLE'S RATHER THAN ZERO for the two that have one: a button's image sits to the LEFT of its
 * title (`NSImageLeft`, which is the era's default) and a fresh button cell is NOT transparent. Everything else is
 * the quiet answer, which Objective-C's zeroing supplies.
 */
#import <AppKit/NSButtonCell.h>

@implementation NSButtonCell

- (instancetype)init
{
	if ((self = [super init]) != nil) {
		/* THE TWO DEFAULTS THAT ARE NOT ZERO, written out because Objective-C zeroes storage: a button's image
		 * leads its title, and a fresh cell is opaque to the eye rather than see-through. */
		_imagePosition_bc = NSImageLeft;
		_transparent = NO;
	}
	return self;
}

- (void)dealloc
{
	/* THE ONE OWNED THING THIS SLICE ADDS. The background colour and the sound are not retained (see the header),
	 * so the alternate title is the only release owed here. */
	[_alternateTitle release];
	[super dealloc];
}

/* ---- THE FLAGS ------------------------------------------------------------------------------------ */

- (BOOL)isTransparent
{
	return _transparent;
}

- (void)setTransparent:(BOOL)flag
{
	_transparent = flag;
}

- (BOOL)showsBorderOnlyWhileMouseInside
{
	return _showsBorderOnlyWhileMouseInside;
}

- (void)setShowsBorderOnlyWhileMouseInside:(BOOL)flag
{
	_showsBorderOnlyWhileMouseInside = flag;
}

- (BOOL)imageDimsWhenDisabled
{
	return _imageDimsWhenDisabled;
}

- (void)setImageDimsWhenDisabled:(BOOL)flag
{
	_imageDimsWhenDisabled = flag;
}

/* ---- AND A BUTTON'S FACE, MINUS THE DRAWINGS ------------------------------------------------------ */

- (NSString *)alternateTitle
{
	return _alternateTitle;
}

- (void)setAlternateTitle:(NSString *)aString
{
	if (aString != _alternateTitle) {
		NSString *copy = [aString copy];

		[_alternateTitle release];
		_alternateTitle = copy;
	}
}

- (id)backgroundColor
{
	return _backgroundColor;
}

- (void)setBackgroundColor:(id)color
{
	_backgroundColor = color;
}

- (NSCellImagePosition)imagePosition
{
	return _imagePosition_bc;
}

- (void)setImagePosition:(NSCellImagePosition)aPosition
{
	_imagePosition_bc = aPosition;
}

- (NSInteger)highlightsBy
{
	return _highlightsBy;
}

- (void)setHighlightsBy:(NSInteger)aType
{
	_highlightsBy = aType;
}

- (NSInteger)showsStateBy
{
	return _showsStateBy;
}

- (void)setShowsStateBy:(NSInteger)aType
{
	_showsStateBy = aType;
}

- (NSUInteger)keyEquivalentModifierMask
{
	return _keyEquivalentModifierMask_bc;
}

- (void)setKeyEquivalentModifierMask:(NSUInteger)mask
{
	_keyEquivalentModifierMask_bc = mask;
}

- (id)sound
{
	return _sound;
}

- (void)setSound:(id)aSound
{
	_sound = aSound;
}

@end
