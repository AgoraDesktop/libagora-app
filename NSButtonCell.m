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

#include <stdio.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSStringDrawing.h>
#import <AppKit/NSImage.h>
/* **AND THE CONTEXT, FOR ONE CALL: `CGContextSetAlpha`, which is how a disabled button's picture dims when it asked
 * to — `-drawInRect:` carries no fraction and the compositing doors do not scale. */
#import <AppKit/NSGraphicsContext.h>
#include <CoreGraphics/CGContext.h>

@implementation NSButtonCell

- (instancetype)init
{
	if ((self = [super init]) != nil) {
		/* THE TWO DEFAULTS THAT ARE NOT ZERO, written out because Objective-C zeroes storage: a button's image
		 * leads its title, and a fresh cell is opaque to the eye rather than see-through. */
		_imagePosition_bc = NSImageLeft;
		_transparent = NO;
		/* AND THE TWO THE DRAWING SLICE ADDS: a fresh button cell is a momentary light button with a rounded bezel,
		 * and THE BEZEL IS THE ONE THAT MATTERS — `NSRoundedBezelStyle` is 1, so zero is not a bezel style at all,
		 * and a cell left at zero would draw as the first enum case rather than as the button a caller made. */
		_buttonType = NSMomentaryLightButton;
		_bezelStyle = NSRoundedBezelStyle;
		/* AND THE DEFAULTS THE COMPLETING SLICE ADDS: a picture scales down proportionally when nothing says
		 * otherwise, and a repeating button's own pair is 0.4/0.075 — the CELL's 0.2/0.025 is a different pair, named
		 * where `-getPeriodicDelay:interval:` is. `-setButtonType:` below fills the two mask defaults. */
		_imageScaling = NSImageScaleProportionallyDown;
		_periodicDelay = 0.4f;
		_periodicInterval = 0.075f;
		_maxAcceleratorLevel = 0;
		[self setButtonType:NSMomentaryLightButton];
	}
	return self;
}

- (void)dealloc
{
	/* THE FIVE OWNED THINGS THIS CLASS ADDS. The background colour and the sound are not retained (see the header),
	 * so the alternate title, the alternate image, the two attributed strings and the key equivalent's font are the
	 * releases owed here. */
	[_alternateTitle release];
	[_alternateImage release];
	[_attributedTitle release];
	[_attributedAlternateTitle release];
	[_keyEquivalentFont release];
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

/* ---- AND THE TWO THAT DECIDE WHAT THE FACE IS ------------------------------------------------ */

- (NSButtonType)buttonType
{
	return _buttonType;
}

- (void)setButtonType:(NSButtonType)aType
{
	_buttonType = aType;
	/* **AND A TYPE CARRIES DEFAULTS FOR HOW THE FACE RESPONDS, WHICH IS THE HALF OF THIS DOOR THAT IS NOT A NAME.**
	 * Apple's "Button Programming Topics" gives the table: what the cell DRAWS OVER while it is pressed
	 * (`highlightsBy`) and what it shows its state WITH (`showsStateBy`) differ per type, so a caller that sets the
	 * type gets those defaults without asking for them. The masks are `NSCell.h`'s.
	 *
	 * IT IS A TRANSCRIPTION RATHER THAN A FETCH, AND THAT IS SAID RATHER THAN HIDDEN: the era header declares the two
	 * properties and NOT their per-type defaults, so the table is the documentation, and this is this tier's reading of
	 * it. A SWITCH AND A RADIO TAKE NO HIGHLIGHT AND SHOW THEIR STATE AS CONTENTS, which is the pair that matters most
	 * — the indicator is the state and the press must not paint over it. */
	switch (aType) {
	case NSSwitchButton:
	case NSRadioButton:
		_highlightsBy = NSNoCellMask;
		_showsStateBy = NSContentsCellMask;
		break;
	case NSMomentaryChangeButton:
		_highlightsBy = NSContentsCellMask;
		_showsStateBy = NSNoCellMask;
		break;
	case NSOnOffButton:
		_highlightsBy = NSContentsCellMask;
		_showsStateBy = NSContentsCellMask;
		break;
	case NSPushOnPushOffButton:
	case NSToggleButton:
	case NSAcceleratorButton:
	case NSMultiLevelAcceleratorButton:
		_highlightsBy = NSPushInCellMask;
		_showsStateBy = NSContentsCellMask;
		break;
	case NSMomentaryPushInButton:
	case NSMomentaryLightButton:
	case NSMomentaryPushButton:
	default:
		_highlightsBy = NSPushInCellMask;
		_showsStateBy = NSNoCellMask;
		break;
	}
}

- (NSBezelStyle)bezelStyle
{
	return _bezelStyle;
}

- (void)setBezelStyle:(NSBezelStyle)style
{
	_bezelStyle = style;
}

/* ---- AND THE REST OF A BUTTON'S FACE: THE PICTURES, THE ATTRIBUTED STRINGS, AND THE PERIODIC PAIR ---------- */

- (NSImage *)alternateImage
{
	return _alternateImage;
}

- (void)setAlternateImage:(NSImage *)anImage
{
	if (anImage != _alternateImage) {
		NSImage *held = [anImage retain];

		[_alternateImage release];
		_alternateImage = held;
	}
}

- (NSImageScaling)imageScaling
{
	return _imageScaling;
}

- (void)setImageScaling:(NSImageScaling)scaling
{
	_imageScaling = scaling;
}

/* **AN ATTRIBUTED STRING IS COPIED WITH `-initWithAttributedString:` RATHER THAN `-copy`,** for the measured reason
 * `NSCell -setAttributedStringValue:` records one class up: this tree's `NSAttributedString` declares `<NSCopying>`
 * and does NOT implement `-copyWithZone:`, so `-copy` would raise. A NIL IS THE QUIET CASE — "no attributed title,
 * fall back to the plain one" — so it is stored as nil rather than making an empty string that would win over a
 * perfectly good plain title. */
- (NSAttributedString *)attributedTitle
{
	return _attributedTitle;
}

- (void)setAttributedTitle:(NSAttributedString *)aString
{
	NSAttributedString *copy = nil;

	if (aString != nil) {
		copy = [[NSAttributedString alloc] initWithAttributedString:aString];
	}
	[_attributedTitle release];
	_attributedTitle = copy;
}

- (NSAttributedString *)attributedAlternateTitle
{
	return _attributedAlternateTitle;
}

- (void)setAttributedAlternateTitle:(NSAttributedString *)aString
{
	NSAttributedString *copy = nil;

	if (aString != nil) {
		copy = [[NSAttributedString alloc] initWithAttributedString:aString];
	}
	[_attributedAlternateTitle release];
	_attributedAlternateTitle = copy;
}

- (id)keyEquivalentFont
{
	return _keyEquivalentFont;
}

- (void)setKeyEquivalentFont:(id)font
{
	/* RETAINED, THE RULE THIS FAMILY USES FOR A FONT. */
	if (font != _keyEquivalentFont) {
		id held = [font retain];

		[_keyEquivalentFont release];
		_keyEquivalentFont = held;
	}
}

- (void)setPeriodicDelay:(float)delay interval:(float)interval
{
	_periodicDelay = delay;
	_periodicInterval = interval;
}

- (void)getPeriodicDelay:(float *)delay interval:(float *)interval
{
	if (delay != NULL) {
		*delay = _periodicDelay;
	}
	if (interval != NULL) {
		*interval = _periodicInterval;
	}
}

- (NSInteger)maxAcceleratorLevel
{
	return _maxAcceleratorLevel;
}

- (void)setMaxAcceleratorLevel:(NSInteger)level
{
	_maxAcceleratorLevel = level;
}

/* ============================================================================================ *
 * AND THE INK: A SWITCH'S BOX OR A RADIO'S RING, A PUSH BUTTON'S BEZEL, AND THE CONTENTS.      *
 * ============================================================================================ */

/* THE TWO BUTTON TYPES THAT ARE NOT A BEZEL WITH CONTENTS: a switch (`NSButtonType` `NSSwitchButton`) and a radio
 * (`NSRadioButton`) are an INDICATOR AND A LABEL, so both the face and the layout differ and both doors below ask
 * this. Everything else — momentary, push-on-push-off, toggle — is a bezel. */
- (BOOL)fn_isIndicatorButton
{
	return (_buttonType == NSSwitchButton || _buttonType == NSRadioButton);
}

/* **THE BEZEL'S OWN HEIGHT, WHICH IS A METRIC AND NOT A MEASUREMENT.** Aqua's push buttons are a FIXED height at a
 * given control size: the title is centred inside the bezel and the air around it is whatever is left over, so the
 * bezel does not grow with the words put in it. THAT DISTINCTION IS THE WHOLE OF THIS TABLE — before it, a push
 * button's height was its title's line height plus the cell's padding, which made the default height (35.2 points,
 * MEASURED) a property of the FONT rather than of the control, and left every title floating in ten points of surplus
 * air.
 *
 * REGULAR IS 23 POINTS — the era's standard Aqua push button, and the height its rounded bezel is laid out at. IT IS
 * A TRANSCRIBED NUMBER AND NOT A MEASURED ONE: it comes from Apple's Human Interface Guidelines, not from any header
 * (no header states it), and this tree has no 10.6 SDK copy on disk to re-measure it against — the same footing
 * `NSEvent`'s function keys and the pen-device constants are on.
 *
 * `AIR` IS THE SLACK A BEZEL KEEPS AROUND THE BASELINE BAND, and it is why the default font fits a 23-point bezel
 * without the bezel growing: the 13-point system font's band is 15.7 points (ascent 12.6 + descent 3.1), so
 * 15.7 + 2 x 3.0 = 21.7, which is inside 23. A caller with a larger font gets a TALLER bezel rather than a clipped
 * title — the metric is a floor, not a cage. */
#define NS_BUTTON_BEZEL_HEIGHT_REGULAR 23.0
#define NS_BUTTON_BEZEL_AIR            3.0

/* **AND THE TWO SIZES THIS TIER HAS NO METRIC FOR ARE REFUSED BY NAME.** `NSControlSize` has three members and a
 * bezel height is published for exactly one of them: no header states the small or mini heights, and this tree has no
 * 10.6 SDK copy to measure them against — so a plausible-looking 19 and 16 would be two invented numbers wearing the
 * HIG's authority, which is the one thing this table does not do. A caller who asks for one is TOLD, once per ask,
 * where they ask; the metric they get meanwhile is the REGULAR one, which is the only one there are grounds for. */
- (void)setControlSize:(NSControlSize)size
{
	[super setControlSize:size];
	if (size != NSRegularControlSize) {
		fprintf(stderr, "APPKIT-REFUSE: -[NSButtonCell setControlSize:] — the bezel height of a %s control is not "
				"published in any era header this tree has, so a bezelled button keeps the REGULAR metric "
				"(%.0f points)\n",
			(size == NSSmallControlSize) ? "small" : "mini", NS_BUTTON_BEZEL_HEIGHT_REGULAR);
	}
}

/* THE BASELINE BAND THE BEZEL HAS TO HOLD — ascent and descent, which is what a line of text occupies.
 *
 * **`fabs` ON THE DESCENT IS NOT DEFENSIVE CODING, IT IS THE CONTRACT.** `NSFont -descender` answers a NEGATIVE
 * number (that door's own documentation), so a band computed without it would be 12.6 - 3.1 = 9.5 points and the
 * bezel would come out shorter than the ink. The same `fabs` appears in `-drawInteriorWithFrame:` below, where the
 * title is centred in that band, and the two have to agree about how tall a line is. */
- (CGFloat)fn_titleLineHeight
{
	id font = [self font];

	if (font == nil) {
		font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
	}
	return (CGFloat)[font ascender] + (CGFloat)fabs((double)[font descender]);
}

/* THE INDICATOR'S OWN MEASURES: the air between the frame's left edge and the box, a fourteen-point box, a checkmark
 * drawn inside it, and the air between the box and the title. ONE PLACE, because the face, the title rect AND the
 * measurement all have to agree about where the box ends — and the margin a person sees is `NS_BUTTON_INDICATOR_GAP`,
 * which is why the label's left edge is spelled as the INSET plus the SIDE plus the GAP rather than as a fourth
 * number that would drift from these three. */
#define NS_BUTTON_INDICATOR_INSET 1.0
#define NS_BUTTON_INDICATOR_SIDE  14.0
#define NS_BUTTON_INDICATOR_GAP   4.0
#define NS_BUTTON_TITLE_LEAD      (NS_BUTTON_INDICATOR_INSET + NS_BUTTON_INDICATOR_SIDE + NS_BUTTON_INDICATOR_GAP)

/* **THE INDICATOR'S OWN FILL, WHICH IS THE SAME TWO SHADES A PUSH BUTTON WEARS.** A checkbox's square and a radio's
 * circle are the parts of those buttons that ANSWER the pointer — the label does not move — so they prelight with the
 * accent's lighter shade while the pointer is over the control, and take the accent itself while it is held down.
 *
 * **AND THE PRESS IS READ FROM `-isHighlighted` RATHER THAN FROM `-fn_faceIsPushed`.** That door asks whether the
 * cell's TYPE paints its press onto the FACE (`highlightsBy`), and the switch and radio rows of the table name
 * `NSNoCellMask` there — not because a press on a checkbox should be invisible, but because a checkbox says it in its
 * MARK, which is the thing this door is about. So the face's rule and the indicator's rule are two different
 * questions and get two answers, which is why the accent is decided twice rather than shared.
 *
 * THE TITLE'S INK IS LEFT ALONE. `-drawInteriorWithFrame:` still inks it through `-fn_wearsAccent`, which answers NO
 * for an indicator button — so a checkbox's LABEL does not change colour when its BOX prelights. That is the split the
 * face already draws: the box answers the pointer, and the words stay where they are. */
- (NSColor *)fn_indicatorFill
{
	if (!_enabled) {
		return [NSColor controlBackgroundColor];
	}
	if (_highlighted) {
		return [NSColor cg_accentColor];
	}
	if ([self cg_mouseIsInside]) {
		return [NSColor cg_accentPrelightColor];
	}
	return [NSColor controlBackgroundColor];
}

- (void)fn_drawIndicatorWithFrame:(NSRect)cellFrame
{
	NSRect box = NSMakeRect(cellFrame.origin.x + NS_BUTTON_INDICATOR_INSET,
				cellFrame.origin.y + (cellFrame.size.height - NS_BUTTON_INDICATOR_SIDE) / 2.0,
				NS_BUTTON_INDICATOR_SIDE, NS_BUTTON_INDICATOR_SIDE);
	BOOL on = (_state == NSOnState || _state == NSMixedState);
	NSColor *fill = [self fn_indicatorFill];

	/* **THE BOX IS FILLED WHOLE AND STROKED HALF A POINT IN, WHICH IS THE DIFFERENCE BETWEEN A DARK GREY BORDER AND A
	 * WASHED-OUT ONE.** A stroke is centred on its path, so a one-point border drawn AT the box's edge spends half its
	 * ink on either side of it — and MEASURED on the desktop that is what the indicator's border WAS: the stroke's band
	 * fell across two pixel columns and blended to 173 where the colour it named was 102, so a checkbox's border was
	 * half the colour it asked for and read as a light grey next to a push button's. Insetting the PATH by half the
	 * stroke puts the whole border on one side of the edge, on one pixel column, at the colour it names — the same fix,
	 * for the same reason, the face's takes one method up. The FILL keeps the full box: only the edge moves inward, so
	 * no gap appears between the frame and its border. */
	if (_buttonType == NSRadioButton) {
		NSBezierPath *ring = [NSBezierPath bezierPathWithOvalInRect:box];
		NSBezierPath *edge = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(box, 0.5, 0.5)];

		[fill setFill];
		[ring fill];
		[[NSColor controlDarkShadowColor] setStroke];
		[edge setLineWidth:1.0];
		[edge stroke];
		if (on) {
			[[NSColor controlTextColor] setFill];
			[[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(box, 4.0, 4.0)] fill];
		}
	} else {
		/* **AND A SWITCH'S BOX IS ROUNDED LIKE EVERYTHING ELSE'S, AT THE PLATFORM'S ONE RADIUS.** It was a plain
		 * rectangle, which made it the only control on the desktop whose corners were SQUARE — beside a push
		 * button's bezel, a radio's ring and a slider's channel, all of which round. THE BORDER KEEPS ITS
		 * HALF-POINT INSET AND DROPS THE RADIUS BY THE SAME HALF POINT, so the stroke stays CONCENTRIC with the
		 * face it is drawn on: a radius left at four inside a path inset by half a point bulges away from the
		 * face's own corner. */
		NSBezierPath *tile = [NSBezierPath bezierPathWithRoundedRect:box
								     xRadius:NS_CELL_BEZEL_RADIUS
								      yRadius:NS_CELL_BEZEL_RADIUS];
		NSBezierPath *edge = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(box, 0.5, 0.5)
								     xRadius:NS_CELL_BEZEL_RADIUS - 0.5
								      yRadius:NS_CELL_BEZEL_RADIUS - 0.5];

		[fill setFill];
		[tile fill];
		[[NSColor controlDarkShadowColor] setStroke];
		[edge setLineWidth:1.0];
		[edge stroke];
		if (on) {
			/* A CHECKMARK, DRAWN RATHER THAN TYPESET — the same reason the System menu's hamburger is: its shape is
			 * arithmetic, so it needs no font and no glyph that the host's registry may not have. A MIXED state draws
			 * the same mark, which is the era's own simplification and stated here rather than left to be discovered. */
			NSBezierPath *check = [NSBezierPath bezierPath];

			[[NSColor controlTextColor] setStroke];
			[check setLineWidth:2.0];
			[check moveToPoint:NSMakePoint(box.origin.x + 3.0, box.origin.y + 7.0)];
			[check lineToPoint:NSMakePoint(box.origin.x + 6.0, box.origin.y + 3.5)];
			[check lineToPoint:NSMakePoint(box.origin.x + 11.0, box.origin.y + 11.0)];
			[check stroke];
		}
	}
}

/* **THE STATE THE FACE IS DRAWN IN, DECIDED ONCE SO THE BEZEL AND THE CONTENTS AGREE.** A button is "pushed" when
 * the pointer holds it down AND its type highlights that way (`highlightsBy & NSPushInCellMask`), OR when it is ON
 * and its type shows state as a BACKGROUND (`showsStateBy & NSChangeBackgroundCellMask`) — which is what makes a
 * push-on-push-off button stay looking pressed between clicks. Both masks are the ones `-setButtonType:` fills, and a
 * switch and a radio take neither, so their press never paints over the indicator. */
- (BOOL)fn_faceIsPushed
{
	if (_highlighted && (_highlightsBy & NSPushInCellMask)) {
		return YES;
	}
	if (_state == NSOnState && (_showsStateBy & NSChangeBackgroundCellMask)) {
		return YES;
	}
	return NO;
}

/* **WHETHER THE FACE IS WEARING THE ACCENT, WHICH IS ONE QUESTION WITH TWO ANSWERS.** The fill and the ink are the
 * same decision — a periwinkle chip is LIGHT, so the title on it has to be black — and asking it twice is how the two
 * come to disagree. False for every face that is not a chip: a DISABLED button keeps its greyed face and grey ink, a
 * TRANSPARENT one has no face to colour, one with a `-backgroundColor:` of its own was told what colour to be, and an
 * INDICATOR button's face is its mark rather than a chip of its own. What is left is a push button, and it wears the
 * accent in its two live states: THE PRESSED ONE in the full accent, and THE PRELIGHT — the pointer over it, no
 * button down — in the lighter shade. */
- (BOOL)fn_wearsAccent
{
	/* AN INDICATOR BUTTON IS EXCLUDED HERE BECAUSE ITS FACE IS ITS MARK AND NOT A CHIP — the accent a checkbox
	 * answers the pointer with belongs to its BOX, and `-fn_indicatorFill` is where that is decided. */
	if (!_enabled || _transparent || _backgroundColor != nil || [self fn_isIndicatorButton]) {
		return NO;
	}
	return [self fn_faceIsPushed] || [self cg_mouseIsInside];
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	if ([self fn_isIndicatorButton]) {
		[self fn_drawIndicatorWithFrame:cellFrame];
		[self drawInteriorWithFrame:cellFrame inView:controlView];
		return;
	}
	/* **A PUSH BUTTON'S FACE: A ROUNDED BEZEL, FILLED AND THEN DARKENED WHILE THE BUTTON IS DOWN.** The radius is
	 * zero for the square bezel styles and four for the rounded ones, and a transparent button paints no face at all
	 * — which is what `-isTransparent` MEANS rather than a colour that happens to blend. */
	/* **`-showsBorderOnlyWhileMouseInside` IS THE ERA DOOR WHOSE WHOLE MEANING IS THE POINTER'S POSITION**, so it is
	 * honoured here rather than only stored: with the flag set, the face is drawn ONLY while the pointer is on the
	 * button, which is what makes a "borderless until you point at it" button borderless. It is false by default, so
	 * an ordinary button is unaffected — this is the door becoming real, not a repaint of every button. */
	if (!_transparent && !(_showsBorderOnlyWhileMouseInside && ![self cg_mouseIsInside])) {
		CGFloat radius = (_bezelStyle == NSRoundedBezelStyle || _bezelStyle == NSRoundRectBezelStyle ||
				  _bezelStyle == NSTexturedRoundedBezelStyle || _bezelStyle == NSRecessedBezelStyle)
				 ? NS_CELL_BEZEL_RADIUS : 0.0;
		/* **AND THE PATH IS INSET BY HALF THE STROKE, SO THE WHOLE BORDER IS INSIDE THE RECTANGLE IT BELONGS TO.**
		 * A stroke is centred on its path, so a face drawn AT the frame's edge puts half of its border outside the
		 * control — where a view's own clip now cuts it, because the drawing layer clips a child to its bounds (see
		 * `-displayRect:`). MEASURED, that is a bezel half a point thinner than the field's beside it, which is
		 * exactly what "the same border" rules out. */
		NSRect faceRect = NSInsetRect(cellFrame, NS_CELL_BEZEL_WIDTH / 2.0, NS_CELL_BEZEL_WIDTH / 2.0);
		NSBezierPath *face = [NSBezierPath bezierPathWithRoundedRect:faceRect xRadius:radius yRadius:radius];
		NSColor *fill;

		if (_backgroundColor != nil) {
			fill = (NSColor *)_backgroundColor;
		} else if (!_enabled) {
			/* **A DISABLED BUTTON'S FACE IS BELOW THE WINDOW'S, WHICH IS THE ONE THING ABOUT IT THAT IS NOT THE ERA'S.**
			 * A button is a raised thing and a disabled one is not, so its grey drops under the surface instead of over
			 * it (`NSColor -cg_disabledControlFaceColor` carries the three steps). It used to be
			 * `controlBackgroundColor` — WHITE, the field's surface — which put a disabled button ABOVE the window and
			 * an enabled one below it, and that is backwards twice: the disabled face was the brightest thing on the
			 * surface and the enabled face was the darkest. */
			fill = [NSColor cg_disabledControlFaceColor];
		} else if ([self fn_wearsAccent]) {
			/* PRESSED WEARS THE ACCENT ITSELF; PRELIGHTED WEARS ITS LIGHTER SHADE. Both come from `NSColor`'s one
			 * accent, which is also what the menu's selection chip is made of, so the platform has one highlight
			 * colour rather than a menu's and a button's that happen to look alike. */
			fill = [self fn_faceIsPushed] ? [NSColor cg_accentColor] : [NSColor cg_accentPrelightColor];
		} else {
			fill = [NSColor controlColor];
		}
		[fill setFill];
		[face fill];
		[[NSColor controlDarkShadowColor] setStroke];
		[face setLineWidth:NS_CELL_BEZEL_WIDTH];
		[face stroke];
	}
	[self drawInteriorWithFrame:cellFrame inView:controlView];
}

/* **THE RECTS A BUTTON'S CONTENTS LIVE IN, WHICH IS THE ONE PLACE ITS LAYOUT DIFFERS FROM THE CELL'S.** A switch's
 * title begins to the RIGHT of its indicator; a push button's title and image share the drawing rect and are laid
 * against each other by `-imagePosition`. */
- (NSRect)titleRectForBounds:(NSRect)theRect
{
	if ([self fn_isIndicatorButton]) {
		/* **THE LABEL BEGINS ONE MARGIN AFTER THE BOX, AND THE MARGIN IS THE INDICATOR'S OWN `GAP`.** The three
		 * constants above describe the box completely — where it starts, how wide it is, and how much air it owes its
		 * label — so the title's left edge is their SUM and not a fourth measure. THE VERTICAL INSET IS THE TWO POINTS
		 * the cell's other content rects use, and the RIGHT edge stays the frame's, so this rect is the room the label
		 * actually has rather than a box sized for it. */
		NSRect r = theRect;

		r.origin.x += NS_BUTTON_TITLE_LEAD;
		r.size.width -= NS_BUTTON_TITLE_LEAD;
		r.origin.y += 2.0;
		r.size.height -= 4.0;
		if (r.size.width < 0.0) {
			r.size.width = 0.0;
		}
		if (r.size.height < 0.0) {
			r.size.height = 0.0;
		}
		return r;
	}
	return [super titleRectForBounds:theRect];
}

/* **AND THE MEASUREMENT INCLUDES THE INDICATOR'S ZONE, WHICH THE SUPERCLASS CANNOT KNOW ABOUT.** `NSCell` measures a
 * text cell as its title plus the air its own rect doors leave, and `-fn_drawIndicatorWithFrame:` puts a box AND a
 * margin to the LEFT of that title — so a checkbox measured by the superclass alone comes out
 * `(inset + side + gap)` narrow, and `-sizeToFit` hands back a frame whose own label is clipped. The lead is added
 * HERE rather than folded into `-titleRectForBounds:` because that rect is what a caller ASKS about, while this is
 * what the cell ANSWERS when it is asked how big it wants to be. */
- (NSSize)cellSizeForBounds:(NSRect)aRect
{
	NSSize size = [super cellSizeForBounds:aRect];

	if ([self fn_isIndicatorButton]) {
		size.width += NS_BUTTON_TITLE_LEAD;
	} else if (!_transparent && (_bordered || _bezeled)) {
		/* **AND A BEZELLED BUTTON'S HEIGHT IS THE BEZEL'S, SO THE TITLE DOES NOT SET IT.** The superclass measured
		 * the title plus the air its rect doors leave, and that measurement is REPLACED here rather than adjusted —
		 * the whole point of a control metric is that two buttons with different words come out the same height. The
		 * WIDTH is still the superclass's, because a bezel DOES grow sideways with its title; and the height grows only
		 * when the band would not fit, which is what keeps a large font legible instead of clipped. */
		CGFloat band = [self fn_titleLineHeight];
		CGFloat height = NS_BUTTON_BEZEL_HEIGHT_REGULAR;

		if (height < band + 2.0 * NS_BUTTON_BEZEL_AIR) {
			height = band + 2.0 * NS_BUTTON_BEZEL_AIR;
		}
		size.height = height;
	}
	return size;
}

- (NSRect)imageRectForBounds:(NSRect)theRect
{
	if ([self fn_isIndicatorButton]) {
		return NSZeroRect;	/* an indicator button shows its state as the indicator, not as a picture */
	}
	return [super imageRectForBounds:theRect];
}

/* **HOW A PICTURE MEETS ITS RECTANGLE — `-imageScaling`, in four lines.** `None` keeps the natural size, `Axes`
 * fills the box and distorts, and the two proportional modes fit the picture inside the box; `…Down` additionally
 * refuses to ENLARGE, which is the difference between the two and the reason a 16-point icon is not blown up into a
 * 200-point button. */
static NSSize fn_button_image_size(NSSize image, NSSize box, NSImageScaling scaling)
{
	CGFloat sx, sy, s;

	if (image.width <= 0.0 || image.height <= 0.0) {
		return image;
	}
	switch (scaling) {
	case NSImageScaleNone:
		return image;
	case NSImageScaleAxesIndependently:
		return box;
	case NSImageScaleProportionallyUpOrDown:
	case NSImageScaleProportionallyDown:
	default:
		sx = box.width / image.width;
		sy = box.height / image.height;
		s = (sx < sy) ? sx : sy;
		if (scaling == NSImageScaleProportionallyDown && s > 1.0) {
			s = 1.0;
		}
		return NSMakeSize(image.width * s, image.height * s);
	}
}

/* **AND THE INK IS A DOOR RATHER THAN AN EXPRESSION, because a subclass draws beside the title.** A pop-up button's
 * arrow is the first caller: it has to be the same colour as the words next to it, and the rule that decides that is
 * `-fn_wearsAccent` plus the enabled flag — three answers to one question that must not be spelled twice. */
- (id)cg_inkColor
{
	return !_enabled ? [NSColor disabledControlTextColor]
			 : ([self fn_wearsAccent] ? [NSColor whiteColor] : [NSColor controlTextColor]);
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	NSRect content = [self fn_isIndicatorButton] ? [self titleRectForBounds:cellFrame]
						     : [self drawingRectForBounds:cellFrame];
	/* **AND THE INK FOLLOWS THE FACE, WHICH IS WHY BOTH ASK `-fn_wearsAccent`.** A button wearing the accent is in one of
	 * its two LIVE states — the pointer is on it or it is being pressed — and those are the states where a button says
	 * "yes, this one", so its title goes WHITE: the mark a person reads is the one under their finger, and it is the
	 * only thing on the surface drawn in white. A button that kept `controlTextColor` through both live states would be
	 * black-on-violet, which is legible and still reads as though nothing had happened to it. A DISABLED button keeps
	 * the era's dimmed grey, and that is a third state rather than a shade of these two: it is the only one whose ink
	 * is chosen for being QUIET. */
	NSColor *ink = [self cg_inkColor];
	BOOL useAlternate = NO;
	NSAttributedString *attributed;
	NSString *title;
	NSImage *image;
	id font = [self font];
	NSDictionary *attributes;
	NSSize tsize = NSZeroSize;
	NSSize draw = NSZeroSize;
	CGFloat gap, total, x, baseline;

	(void)controlView;
	/* **THE ALTERNATE TITLE AND IMAGE ARE WHAT A BUTTON SHOWS INSTEAD OF ITSELF, AND WHEN DEPENDS ON THE TYPE** — a
	 * momentary button while it is held, a push-on-push-off button while it is ON. Both are the two masks
	 * `-setButtonType:` filled, and an INDICATOR button takes neither: a checkbox's state is its mark, not a second
	 * title, which is exactly why the switch and radio rows of that table name `NSContentsCellMask` with no
	 * `highlightsBy`. */
	if (![self fn_isIndicatorButton]) {
		useAlternate = ((_highlighted && (_highlightsBy & NSContentsCellMask)) ||
				(_state == NSOnState && (_showsStateBy & NSContentsCellMask)));
	}
	attributed = (useAlternate && _attributedAlternateTitle != nil) ? _attributedAlternateTitle : _attributedTitle;
	title = (useAlternate && _alternateTitle != nil) ? _alternateTitle : _title;
	image = (useAlternate && _alternateImage != nil) ? _alternateImage : _image;
	if (font == nil) {
		font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
	}
	attributes = [NSDictionary dictionaryWithObjectsAndKeys:font, NSFontAttributeName, ink,
		      NSForegroundColorAttributeName, nil];
	/* **AN ATTRIBUTED TITLE WINS OVER THE PLAIN ONE, WHICH IS THE CELL'S DOCUMENTED ANSWER** — and its attributes are
	 * its own, so this tier draws it as it was given rather than imposing the cell's font and colour on it. */
	if (attributed != nil) {
		tsize = [attributed size];
	} else if (title != nil && [title length] > 0) {
		tsize = [title sizeWithAttributes:attributes];
	}
	if (image != nil) {
		draw = fn_button_image_size([image size], content.size, _imageScaling);
	}
	/* **THE CONTENTS ARE CENTRED AS A GROUP, WHICH IS WHAT MAKES AN IMAGE AND A TITLE SIT TOGETHER.** Laying each one
	 * out on its own would put the image in the middle of the cell and the title in the middle of the cell, on top of
	 * each other; the group's width is the two plus the gap, and the group starts where the cell can centre it.
	 *
	 * **AND AN INDICATOR BUTTON'S LABEL IS LEFT-ALIGNED, WHICH IS THE ONE PLACE THE GROUP IS NOT CENTRED.** A
	 * checkbox's title belongs to its box and sits immediately to the right of it; CENTRING it in whatever room is left
	 * makes the gap between the two depend on how long the words are, so a column of checkboxes comes out with its
	 * labels drifting away from their boxes — and the margin a caller asked for is a margin, not a coincidence of two
	 * widths. `-titleRectForBounds:` has already taken the indicator's zone out of `content`, so the LEFT EDGE of that
	 * rect IS the margin the box owes its label. */
	gap = (tsize.width > 0.0 && draw.width > 0.0) ? 4.0 : 0.0;
	total = draw.width + gap + tsize.width;
	if ([self fn_isIndicatorButton]) {
		x = content.origin.x;
	} else {
		x = content.origin.x + (content.size.width - total) / 2.0;
		if (x < content.origin.x) {
			x = content.origin.x;
		}
	}
	if (image != nil && draw.width > 0.0) {
		NSRect where = NSMakeRect(x, content.origin.y + (content.size.height - draw.height) / 2.0,
					  draw.width, draw.height);
		CGContextRef cg = [[NSGraphicsContext currentContext] CGContext];
		/* **A DISABLED PICTURE DIMS IF THE BUTTON ASKED IT TO** — an alpha on the current context, which is the one
		 * door this tier's image drawing offers for it (`-drawInRect:` carries no fraction, and the compositing
		 * doors do not scale). */
		BOOL dim = (!_enabled && _imageDimsWhenDisabled);

		if (dim && cg != NULL) {
			CGContextSetAlpha(cg, 0.5);
		}
		[image drawInRect:where];
		if (dim && cg != NULL) {
			CGContextSetAlpha(cg, 1.0);
		}
		x += draw.width + gap;
	}
	if (attributed != nil) {
		[attributed drawInRect:NSMakeRect(x, content.origin.y + (content.size.height - tsize.height) / 2.0,
						  tsize.width, tsize.height)];
	} else if (tsize.width > 0.0 && content.size.height > 0.0) {
		CGFloat ascent = [font ascender];
		CGFloat descent = (CGFloat)fabs((double)[font descender]);
		CGFloat band = ascent + descent;

		baseline = content.origin.y + (content.size.height - band) / 2.0 + descent;
		[title drawInRect:NSMakeRect(x, baseline - descent, tsize.width, band) withAttributes:attributes];
	}
}

@end
