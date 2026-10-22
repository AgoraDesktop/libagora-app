/*
 * NSButton — a control whose cell is a button cell.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * EVERY DOOR HERE IS A FORWARD, and the one thing the class decides is what KIND of cell it makes: a text cell, so a
 * title can be set on it; bordered and bezeled, so it has a face; and momentary by default, because that is what a
 * caller who says nothing means by "button". A caller that wants a checkbox says `-setButtonType:NSSwitchButton` and
 * the SAME cell draws an indicator instead of a bezel — which is why the button type is on the cell and not here.
 */
#import <AppKit/NSButton.h>

@implementation NSButton

/* ============================================================================================
 * ARCHIVING: ONE FLAG, BECAUSE THE BUTTON'S FACE IS ITS CELL'S.
 * ============================================================================================ */
/* **A BUTTON ADDS ONE IVAR AND IT IS NOT ITS TITLE.** Everything a caller thinks of as the button — the title, the
 * alternate title, the image, the bezel, the button type — lives on the CELL, which is why `NSButtonCell`'s coding is
 * the long one and this class's is a single flag. Spring-loading is the button's own. */
static NSString * const AGCoderButtonSpringLoadedKey = @"springLoaded";

- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[super encodeWithCoder:aCoder];
	[aCoder encodeBool:_springLoaded forKey:AGCoderButtonSpringLoadedKey];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
	self = [super initWithCoder:aDecoder];
	if (self == nil) {
		return nil;
	}
	if ([aDecoder containsValueForKey:AGCoderButtonSpringLoadedKey]) {
		_springLoaded = [aDecoder decodeBoolForKey:AGCoderButtonSpringLoadedKey];
	}
	return self;
}

+ (BOOL)supportsSecureCoding
{
	return YES;
}


- (instancetype)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	if (self != nil) {
		/* A BUTTON'S CELL IS MADE HERE AND NOWHERE ELSE. Bordered and bezeled, so it has a face without the caller
		 * asking; a momentary light button with a rounded bezel, which are the cell's own defaults and are re-stated
		 * here only to say that a button wants them. */
		NSButtonCell *cell = [[NSButtonCell alloc] initTextCell:@""];

		[cell setBordered:YES];
		[cell setBezeled:YES];
		[self setCell:cell];
		[cell release];
		/* **AND A DEGENERATE FRAME IS FILLED IN BY `-sizeToFit`, WHICH IS THIS TIER'S CHOICE RATHER THAN APPLE'S.**
		 * AppKit leaves `NSZeroRect` alone — the frame is what the caller passed — but this tier's `NSSlider` already
		 * fills in a default for a zero frame, and a push button that answered `0 x 0` while a slider answered `96 x 20`
		 * would be two controls disagreeing about what a degenerate frame means. THE HEIGHT IT LANDS ON IS THE
		 * STANDARD ONE (see `NS_BUTTON_BEZEL_HEIGHT_REGULAR`), so this is the door that makes "a push button is 23
		 * points tall by default" true for a button nobody sized at all. */
		if (frameRect.size.width <= 0.0 || frameRect.size.height <= 0.0) {
			[self sizeToFit];
		}
	}
	return self;
}

/* ---- THE TITLE, AND THE ALTERNATE ONE ------------------------------------------------------------ */

- (NSString *)title
{
	return [[self cell] title];
}

- (void)setTitle:(NSString *)aTitle
{
	[[self cell] setTitle:aTitle];
	[self setNeedsDisplay:YES];
}

- (NSString *)alternateTitle
{
	return [(NSButtonCell *)[self cell] alternateTitle];
}

- (void)setAlternateTitle:(NSString *)aTitle
{
	[(NSButtonCell *)[self cell] setAlternateTitle:aTitle];
	[self setNeedsDisplay:YES];
}

/* ---- THE STATE, AND THE MIXED STATE THAT ONLY A CHECKBOX CAN BE IN -------------------------------- */

- (NSInteger)state
{
	return [[self cell] state];
}

- (void)setState:(NSInteger)value
{
	[[self cell] setState:value];
	[self setNeedsDisplay:YES];
}

- (void)setAllowsMixedState:(BOOL)flag
{
	[[self cell] setAllowsMixedState:flag];
}

- (BOOL)allowsMixedState
{
	return [[self cell] allowsMixedState];
}

/* ---- WHAT KIND OF BUTTON IT IS -------------------------------------------------------------------- */

- (NSButtonType)buttonType
{
	return [(NSButtonCell *)[self cell] buttonType];
}

- (void)setButtonType:(NSButtonType)aType
{
	[(NSButtonCell *)[self cell] setButtonType:aType];
	[self setNeedsDisplay:YES];
}

- (NSBezelStyle)bezelStyle
{
	return [(NSButtonCell *)[self cell] bezelStyle];
}

- (void)setBezelStyle:(NSBezelStyle)style
{
	[(NSButtonCell *)[self cell] setBezelStyle:style];
	[self setNeedsDisplay:YES];
}

/* ---- THE KEY EQUIVALENT AND THE IMAGE, BOTH THE CELL'S -------------------------------------------- */

- (NSString *)keyEquivalent
{
	return [[self cell] keyEquivalent];
}

- (void)setKeyEquivalent:(NSString *)aKeyEquivalent
{
	[[self cell] setKeyEquivalent:aKeyEquivalent];
}

- (id)image
{
	return [[self cell] image];
}

- (void)setImage:(id)anImage
{
	[[self cell] setImage:anImage];
	[self setNeedsDisplay:YES];
}

- (NSCellImagePosition)imagePosition
{
	return [(NSButtonCell *)[self cell] imagePosition];
}

- (void)setImagePosition:(NSCellImagePosition)aPosition
{
	[(NSButtonCell *)[self cell] setImagePosition:aPosition];
	[self setNeedsDisplay:YES];
}

/* ---- THE TWO ATTRIBUTED TITLES, AND THE PICTURE THAT REPLACES THE OTHER ONE ON A PRESS -------------- */

- (NSAttributedString *)attributedTitle
{
	return [(NSButtonCell *)[self cell] attributedTitle];
}

- (void)setAttributedTitle:(NSAttributedString *)aTitle
{
	[(NSButtonCell *)[self cell] setAttributedTitle:aTitle];
	[self setNeedsDisplay:YES];
}

- (NSAttributedString *)attributedAlternateTitle
{
	return [(NSButtonCell *)[self cell] attributedAlternateTitle];
}

- (void)setAttributedAlternateTitle:(NSAttributedString *)aTitle
{
	[(NSButtonCell *)[self cell] setAttributedAlternateTitle:aTitle];
	[self setNeedsDisplay:YES];
}

- (NSImage *)alternateImage
{
	return [(NSButtonCell *)[self cell] alternateImage];
}

- (void)setAlternateImage:(NSImage *)anImage
{
	[(NSButtonCell *)[self cell] setAlternateImage:anImage];
	[self setNeedsDisplay:YES];
}

- (NSImageScaling)imageScaling
{
	return [(NSButtonCell *)[self cell] imageScaling];
}

- (void)setImageScaling:(NSImageScaling)scaling
{
	[(NSButtonCell *)[self cell] setImageScaling:scaling];
	[self setNeedsDisplay:YES];
}

/* ---- THE FOUR FLAGS AND THE SOUND, ALL THE CELL'S ---------------------------------------------- */

/* **FOUR FLAGS AND A SOUND, FORWARDED WITHOUT A SECOND COPY OF ANY OF THEM.** The face is the cell's, so the flags that
 * change it are the cell's too; a button keeping its own `_bordered` would be a second answer to one question, and
 * the cell that draws is the one that must be right. The two that change the INK ask for a redisplay; the other two
 * are read the next time the cell draws for any other reason. */
- (BOOL)isBordered
{
	return [[self cell] isBordered];
}

- (void)setBordered:(BOOL)flag
{
	[[self cell] setBordered:flag];
	[self setNeedsDisplay:YES];
}

- (BOOL)isTransparent
{
	return [(NSButtonCell *)[self cell] isTransparent];
}

- (void)setTransparent:(BOOL)flag
{
	[(NSButtonCell *)[self cell] setTransparent:flag];
	[self setNeedsDisplay:YES];
}

- (BOOL)showsBorderOnlyWhileMouseInside
{
	return [(NSButtonCell *)[self cell] showsBorderOnlyWhileMouseInside];
}

- (void)setShowsBorderOnlyWhileMouseInside:(BOOL)flag
{
	[(NSButtonCell *)[self cell] setShowsBorderOnlyWhileMouseInside:flag];
	[self setNeedsDisplay:YES];
}

- (id)sound
{
	return [(NSButtonCell *)[self cell] sound];
}

- (void)setSound:(id)aSound
{
	[(NSButtonCell *)[self cell] setSound:aSound];
}

/* ---- THE KEY EQUIVALENT'S MASK, THE PERIODIC PAIR, AND THE STATE WALK --------------------------------- */

- (NSUInteger)keyEquivalentModifierMask
{
	return [(NSButtonCell *)[self cell] keyEquivalentModifierMask];
}

- (void)setKeyEquivalentModifierMask:(NSUInteger)mask
{
	[(NSButtonCell *)[self cell] setKeyEquivalentModifierMask:mask];
}

- (void)setPeriodicDelay:(float)delay interval:(float)interval
{
	[(NSButtonCell *)[self cell] setPeriodicDelay:delay interval:interval];
}

- (void)getPeriodicDelay:(float *)delay interval:(float *)interval
{
	[(NSButtonCell *)[self cell] getPeriodicDelay:delay interval:interval];
}

- (void)setNextState
{
	/* THE WALK IS THE CELL'S, so this is the forward plus the redisplay every state change owes. */
	[[self cell] setNextState];
	[self setNeedsDisplay:YES];
}

/* ---- AND THE THREE THAT ARE THE BUTTON'S OWN RATHER THAN THE CELL'S --------------------------------- */

- (void)setTitleWithMnemonic:(NSString *)titleWithMnemonic
{
	/* THE MNEMONIC IS THE CELL'S RULE (the index is into the CELL's title) and this is a forward plus a redisplay. */
	[[self cell] setTitleWithMnemonic:titleWithMnemonic];
	[self setNeedsDisplay:YES];
}

- (BOOL)isSpringLoaded
{
	return _springLoaded;
}

- (void)setSpringLoaded:(BOOL)flag
{
	_springLoaded = flag;
}

- (void)setMaxAcceleratorLevel:(NSInteger)level
{
	[(NSButtonCell *)[self cell] setMaxAcceleratorLevel:level];
}

/* ---- AND THE PRESS: THE CELL'S STATE, ON THE VIEW'S TERMS ----------------------------------------- */

- (void)highlight:(BOOL)flag
{
	[[self cell] highlight:flag withFrame:[self bounds] inView:self];
	[self setNeedsDisplay:YES];
}

@end
