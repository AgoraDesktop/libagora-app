/*
 * ruler_view — NSRulerView, NSRulerMarker, and the scroll view that wears them.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE CLAIMS ARE THE FOUR THE CLASS MAKES.** First, the thickness is one sum three classes agree on. Second, a
 * marker's rectangle is its location plus its image plus its origin, in the orientation it was given. Third, every
 * change to the marker list goes through the client view's questions, and a client that refuses gets its refusal
 * honoured. Fourth — and this is the one a picture is needed for — the hash marks are the UNIT's arithmetic: in points
 * the ticks fall every five, and moving the origin moves all of them by the same amount.
 *
 * **THE DRAG IS ASSERTED ON THE STREAM, NOT ON A MODAL LOOP**, because that is how this tier runs a gesture: the
 * `shouldMove`/`willMove` questions on the down, the absolute location on each drag, one `didMove` on the release.
 *
 * **THE PIXEL CHECK FINDS THE TICK ROW BY COUNTING**, rather than assuming which end of the bitmap row zero is — the
 * handoff records that `-colorAtX:y:` indexes from the opposite end to the drawing coordinates, and a claim that
 * depends on that conversion is a claim about the sampler, not about the ruler.
 */
#import <AppKit/NSRulerView.h>
#import <AppKit/NSScrollView.h>
#import <AppKit/NSClipView.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSView.h>
#import <Foundation/Foundation.h>

#include <math.h>
#include <stdio.h>

static int failures;

static void check(int ok, const char *what)
{
	printf("  %s %s\n", ok ? "ok   " : "FAIL ", what);
	if (!ok) {
		failures++;
	}
}

static int close_enough(CGFloat a, CGFloat b)
{
	return fabs((double)(a - b)) < 0.01;
}

/* ==================================================================================================================
 * A CLIENT THAT ANSWERS THE EIGHT QUESTIONS AND REMEMBERS WHAT IT WAS ASKED.
 *
 * The defaults are YES, which is what a client that answers nothing gets; each one can be turned into a refusal so the
 * ruler's behaviour on a refusal is visible rather than assumed.
 * ================================================================================================================ */

@interface AGRulerClient : NSView
{
@public
	BOOL allowAdd;
	BOOL allowMove;
	BOOL allowRemove;
	CGFloat addLocation;		/* the location `-willAdd` insists on; ignored when `patchAdd` is NO */
	CGFloat moveLocation;		/* the location `-willMove` insists on */
	BOOL patchAdd;
	BOOL patchMove;
	BOOL addCursorClamp;		/* when YES, `-willMove` refuses any location past 200 and answers 200 */
	NSInteger shouldAddCount;
	NSInteger willAddCount;
	NSInteger didAddCount;
	NSInteger shouldMoveCount;
	NSInteger willMoveCount;
	NSInteger didMoveCount;
	NSInteger shouldRemoveCount;
	NSInteger didRemoveCount;
	NSInteger mouseDownCount;
	NSEvent *lastMouseDown;
}
@end

@implementation AGRulerClient

- (instancetype)initWithFrame:(NSRect)frame
{
	self = [super initWithFrame:frame];
	if (self != nil) {
		allowAdd = YES;
		allowMove = YES;
		allowRemove = YES;
		patchAdd = NO;
		patchMove = NO;
		addCursorClamp = NO;
	}
	return self;
}

- (void)dealloc
{
	[lastMouseDown release];
	[super dealloc];
}

- (BOOL)rulerView:(NSRulerView *)ruler shouldAddMarker:(NSRulerMarker *)marker
{
	(void)ruler;
	(void)marker;
	shouldAddCount++;
	return allowAdd;
}

- (CGFloat)rulerView:(NSRulerView *)ruler willAddMarker:(NSRulerMarker *)marker atLocation:(CGFloat)location
{
	(void)ruler;
	(void)marker;
	willAddCount++;
	return patchAdd ? addLocation : location;
}

- (void)rulerView:(NSRulerView *)ruler didAddMarker:(NSRulerMarker *)marker
{
	(void)ruler;
	(void)marker;
	didAddCount++;
}

- (BOOL)rulerView:(NSRulerView *)ruler shouldMoveMarker:(NSRulerMarker *)marker
{
	(void)ruler;
	(void)marker;
	shouldMoveCount++;
	return allowMove;
}

- (CGFloat)rulerView:(NSRulerView *)ruler willMoveMarker:(NSRulerMarker *)marker toLocation:(CGFloat)location
{
	(void)ruler;
	(void)marker;
	willMoveCount++;
	if (addCursorClamp && location > 200.0) {
		return 200.0;
	}
	return patchMove ? moveLocation : location;
}

- (void)rulerView:(NSRulerView *)ruler didMoveMarker:(NSRulerMarker *)marker
{
	(void)ruler;
	(void)marker;
	didMoveCount++;
}

- (BOOL)rulerView:(NSRulerView *)ruler shouldRemoveMarker:(NSRulerMarker *)marker
{
	(void)ruler;
	(void)marker;
	shouldRemoveCount++;
	return allowRemove;
}

- (void)rulerView:(NSRulerView *)ruler didRemoveMarker:(NSRulerMarker *)marker
{
	(void)ruler;
	(void)marker;
	didRemoveCount++;
}

- (void)rulerView:(NSRulerView *)ruler handleMouseDown:(NSEvent *)event
{
	(void)ruler;
	mouseDownCount++;
	[event retain];
	[lastMouseDown release];
	lastMouseDown = event;
}

@end

/* ==================================================================================================================
 * THE BITS THE TWO DIRECT TESTS NEED.
 * ================================================================================================================ */

static NSBitmapImageRep *new_rep(int w, int h)
{
	return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:w * 4 bitsPerPixel:32];
}

/* **DARK MEANS "THE MARK'S OWN INK, NOT THE FACE".** The face is `controlColor`, a light grey; a tick or a label is
 * `controlShadowColor`/`controlTextColor`, both dark. The threshold is deliberately generous so a different platform
 * theme does not turn a real tick into a failure. */
static int is_dark(NSColor *c)
{
	return c != nil && [c redComponent] < 0.75 && [c greenComponent] < 0.75 && [c blueComponent] < 0.75 &&
	       [c alphaComponent] > 0.5;
}

static NSEvent *mouse(NSEventType type, NSPoint point)
{
	return [NSEvent mouseEventWithType:type location:point modifierFlags:0 timestamp:0.0
			      windowNumber:0 context:nil eventNumber:0 clickCount:1 pressure:1.0f];
}

static NSImage *tab_image(void)
{
	NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(9.0, 8.0)];

	[image lockFocusFlipped:YES];
	[[NSColor redColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, 9.0, 8.0)] fill];
	[image unlockFocus];
	return image;
}

int main(void)
{
	@autoreleasepool {
		/* ============================================================================================
		 * 1. THE THICKNESS IS ONE SUM, AND THE MARKER'S SHARE IS THE ORIENTATION'S.
		 * ========================================================================================== */
		{
			NSRulerView *ruler = [[NSRulerView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 300.0, 20.0)];
			NSImage *image = tab_image();
			NSRulerMarker *horizontal;
			NSRulerMarker *vertical;

			check(close_enough([ruler ruleThickness], 15.0), "a ruler's rule strip is fifteen points by default");
			check(close_enough([ruler requiredThickness], 15.0), "and that alone is what it requires with no reserves");
			check([ruler orientation] == NSHorizontalRuler, "-initWithFrame: makes a horizontal ruler");
			check([ruler isFlipped], "and it is flipped, so a location grows rightward from the origin");
			check([[ruler measurementUnits] isEqualToString:NSRulerViewUnitInches], "and it measures inches by default");

			[ruler setRuleThickness:22.0];
			[ruler setReservedThicknessForMarkers:12.0];
			[ruler setReservedThicknessForAccessoryView:16.0];
			check(close_enough([ruler requiredThickness], 50.0),
			      "the requirement is the rule plus both reserves, which is the sum the scroll view sizes by");

			/* A HORIZONTAL MARKER SPENDS ITS HEIGHT. */
			horizontal = [[NSRulerMarker alloc] initWithRulerView:ruler markerLocation:100.0 image:image
								  imageOrigin:NSMakePoint(0.0, 27.0)];
			check(NSMaxY([horizontal imageRectInRuler]) == 35.0,
			      "a marker's rectangle is its location along the axis and its origin across it");
			check(close_enough([horizontal thicknessRequiredInRuler], 35.0),
			      "so a horizontal marker needs its image's height plus the origin's y");
			check([horizontal isMovable] && [horizontal isRemovable],
			      "and a marker is movable and removable until it is told otherwise");
			[horizontal release];

			/* A VERTICAL ONE SPENDS ITS WIDTH, AND ITS LOCATION IS THE Y. */
			[ruler setOrientation:NSVerticalRuler];
			vertical = [[NSRulerMarker alloc] initWithRulerView:ruler markerLocation:100.0 image:image
								imageOrigin:NSMakePoint(3.0, 0.0)];
			check([vertical imageRectInRuler].origin.x == 3.0 && [vertical imageRectInRuler].origin.y == 100.0,
			      "a vertical marker's location is an x-axis-independent y");
			check(close_enough([vertical thicknessRequiredInRuler], 12.0),
			      "and it needs the image's width plus the origin's x");
			[vertical release];
			[image release];
			[ruler release];
		}

		/* ============================================================================================
		 * 2. EVERY CHANGE IS THE CLIENT'S QUESTION, AND A REFUSAL IS HONOURED.
		 * ========================================================================================== */
		{
			NSRulerView *ruler = [[NSRulerView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 300.0, 20.0)];
			AGRulerClient *client = [[AGRulerClient alloc] initWithFrame:NSMakeRect(0.0, 0.0, 300.0, 200.0)];
			NSImage *image = tab_image();
			NSRulerMarker *marker;

			[ruler setClientView:client];

			/* REFUSED: nothing enters the array and nothing is announced. */
			client->allowAdd = NO;
			marker = [[NSRulerMarker alloc] initWithRulerView:nil markerLocation:40.0 image:image
							      imageOrigin:NSZeroPoint];
			[ruler addMarker:marker];
			check([[ruler markers] count] == 0, "a client that refuses an add keeps the marker out");
			check(client->shouldAddCount == 1 && client->didAddCount == 0,
			      "and it was asked once and told nothing");

			/* ALLOWED, BUT MOVED BY THE CLIENT: `willAdd` has the last word on the location. */
			client->allowAdd = YES;
			client->patchAdd = YES;
			client->addLocation = 25.0;
			[ruler addMarker:marker];
			check([[ruler markers] count] == 1, "an allowed marker is added");
			check(close_enough([marker markerLocation], 25.0), "and its location is the one -willAdd answered");
			check(client->willAddCount == 1 && client->didAddCount == 1,
			      "with one will and one did around it");
			check([marker ruler] == ruler, "and the ruler adopted it");

			/* A REFUSED REMOVE LEAVES IT IN PLACE. */
			client->allowRemove = NO;
			[ruler removeMarker:marker];
			check([[ruler markers] count] == 1, "a client that refuses a remove keeps the marker");
			client->allowRemove = YES;
			[ruler removeMarker:marker];
			check([[ruler markers] count] == 0 && client->didRemoveCount == 1,
			      "and an allowed one removes it and says so");
			check([marker ruler] == nil, "the removed marker no longer names the ruler");

			/* `-setMarkers:` IS THE CLIENT'S OWN ANSWER, SO IT IS NOT ASKED ABOUT IT. */
			[ruler setMarkers:[NSArray arrayWithObject:marker]];
			check([[ruler markers] count] == 1 && client->shouldAddCount == 2,
			      "-setMarkers: installs without a second round of questions");
			check([marker ruler] == ruler, "and adopts what it was given");

			[marker release];
			[image release];
			[client release];
			[ruler release];
		}

		/* ============================================================================================
		 * 3. THE DRAG IS A STREAM: ASK ONCE, MOVE ABSOLUTELY, ANNOUNCE ONCE.
		 * ========================================================================================== */
		{
			NSRulerView *ruler = [[NSRulerView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 300.0, 20.0)];
			AGRulerClient *client = [[AGRulerClient alloc] initWithFrame:NSMakeRect(0.0, 0.0, 300.0, 200.0)];
			NSImage *image = tab_image();
			NSRulerMarker *marker = [[NSRulerMarker alloc] initWithRulerView:ruler markerLocation:100.0
									   image:image imageOrigin:NSZeroPoint];

			[ruler setClientView:client];
			[ruler setMarkers:[NSArray arrayWithObject:marker]];

			check([ruler trackMarker:marker withMouseEvent:mouse(NSLeftMouseDown, NSMakePoint(100.0, 10.0))],
			      "a drag begins where the pointer grabbed the marker");
			check([marker isDragging], "and the marker knows it is being dragged");

			[ruler mouseDragged:mouse(NSLeftMouseDragged, NSMakePoint(130.0, 10.0))];
			check(close_enough([marker markerLocation], 130.0), "thirty points of drag move it thirty points");
			[ruler mouseDragged:mouse(NSLeftMouseDragged, NSMakePoint(250.0, 10.0))];
			check(close_enough([marker markerLocation], 250.0),
			      "and the move is ABSOLUTE, so a second drag from the original grab lands where the pointer is");
			check(client->didMoveCount == 0, "nothing is announced until the release");
			[ruler mouseUp:mouse(NSLeftMouseUp, NSMakePoint(250.0, 10.0))];
			check(client->didMoveCount == 1 && ![marker isDragging],
			      "the release announces the move once and ends the drag");

			/* A CLIENT THAT REFUSES THE MOVE IS OBEYED, AND THE ERROR DOES NOT ACCUMULATE. */
			client->addCursorClamp = YES;
			[ruler trackMarker:marker withMouseEvent:mouse(NSLeftMouseDown, NSMakePoint(250.0, 10.0))];
			[ruler mouseDragged:mouse(NSLeftMouseDragged, NSMakePoint(400.0, 10.0))];
			check(close_enough([marker markerLocation], 200.0), "a client's clamped location is the one the marker takes");
			[ruler mouseUp:mouse(NSLeftMouseUp, NSMakePoint(400.0, 10.0))];
			check(client->didMoveCount == 2, "and the release announces it as well");

			/* A REFUSED DRAG NEVER STARTS. */
			client->allowMove = NO;
			check(![ruler trackMarker:marker withMouseEvent:mouse(NSLeftMouseDown, NSMakePoint(200.0, 10.0))],
			      "a client that refuses the move gets no drag at all");
			check(![marker isDragging], "and the marker is not in a session");

			/* AND THE MODAL DOOR SAYS WHY IT IS NOT THERE. */
			check(![marker trackMouse:mouse(NSLeftMouseDown, NSMakePoint(200.0, 10.0)) adding:NO],
			      "-trackMouse:adding: refuses the modal loop rather than guessing one");

			[marker release];
			[image release];
			[client release];
			[ruler release];
		}

		/* ============================================================================================
		 * 4. THE UNITS ARE THE MARKS: POINTS TICK EVERY FIVE, AND THE ORIGIN MOVES ALL OF THEM.
		 * ========================================================================================== */
		{
			NSRulerView *ruler = [[NSRulerView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 300.0, 20.0)];
			NSBitmapImageRep *rep;

			[ruler setMeasurementUnits:NSRulerViewUnitPoints];
			check([[ruler measurementUnits] isEqualToString:NSRulerViewUnitPoints], "a registered unit is accepted");
			/* AN UNKNOWN UNIT IS REFUSED AND THE OLD ONE STAYS, which is the difference between a refusal and a stub. */
			[ruler setMeasurementUnits:@"Furlongs"];
			check([[ruler measurementUnits] isEqualToString:NSRulerViewUnitPoints],
			      "an unregistered unit is refused by name and the old one stays");
			/* AND A REGISTERED ONE IS TAKEN. */
			[NSRulerView registerUnitWithName:@"Furlongs" abbreviation:@"fl"
			   unitToPointsConversionFactor:7920.0
				   stepUpCycle:[NSArray arrayWithObject:[NSNumber numberWithInt:1]]
				 stepDownCycle:[NSArray arrayWithObject:[NSNumber numberWithInt:1]]];
			[ruler setMeasurementUnits:@"Furlongs"];
			check([[ruler measurementUnits] isEqualToString:@"Furlongs"], "a newly registered unit is accepted");
			[ruler setMeasurementUnits:NSRulerViewUnitPoints];

			/* THE TICK ROW IS THE ONE WITH THE MOST DARK PIXELS: one tick every five points across three hundred. */
			rep = new_rep(300, 20);
			[ruler cacheDisplayInRect:NSMakeRect(0.0, 0.0, 300.0, 20.0) toBitmapImageRep:rep];
			{
				int x;
				int y;
				int bestRow = -1;
				int bestCount = 0;
				int ok = 1;
				int found = 0;

				for (y = 0; y < 20; y++) {
					int count = 0;

					for (x = 0; x < 300; x++) {
						if (is_dark([rep colorAtX:x y:y])) {
							count++;
						}
					}
					if (count > bestCount) {
						bestCount = count;
						bestRow = y;
					}
				}
				check(bestRow >= 0 && bestCount >= 55,
				      "the tick row carries a mark every five points across the strip");
				if (bestRow >= 0) {
					for (x = 0; x < 300; x++) {
						int dark = is_dark([rep colorAtX:x y:bestRow]);

						if (dark != ((x % 5) == 0)) {
							ok = 0;
						}
						if (dark) {
							found++;
						}
					}
					check(ok && found == 60, "and every one of them is at a multiple of five, with none between");
				}
			}
			[rep release];

			/* THE ORIGIN SHIFTS THE WHOLE LADDER, which is what puts a text ruler's zero at the text's inset. */
			[ruler setOriginOffset:3.0];
			rep = new_rep(300, 20);
			[ruler cacheDisplayInRect:NSMakeRect(0.0, 0.0, 300.0, 20.0) toBitmapImageRep:rep];
			{
				int x;
				int y;
				int bestRow = -1;
				int bestCount = 0;
				int ok = 1;

				for (y = 0; y < 20; y++) {
					int count = 0;

					for (x = 0; x < 300; x++) {
						if (is_dark([rep colorAtX:x y:y])) {
							count++;
						}
					}
					if (count > bestCount) {
						bestCount = count;
						bestRow = y;
					}
				}
				if (bestRow >= 0) {
					for (x = 0; x < 300; x++) {
						int dark = is_dark([rep colorAtX:x y:bestRow]);

						if (dark != (((x - 3) % 5) == 0)) {
							ok = 0;
						}
					}
				}
				check(bestRow >= 0 && ok, "the origin offset moves every tick by the same three points");
			}
			[rep release];
			[ruler release];
		}

		/* ============================================================================================
		 * 5. THE SCROLL VIEW WEARS IT AND KEEPS IT ON THE DOCUMENT.
		 * ========================================================================================== */
		{
			NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 400.0, 300.0)];
			NSView *document = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 1200.0, 2000.0)];
			NSSize contentBefore;

			[scroll setHasVerticalScroller:YES];
			[scroll setDocumentView:document];
			contentBefore = [[scroll contentView] frame].size;
			check(![scroll hasVerticalRuler] && ![scroll rulersVisible],
			      "a scroll view starts with no ruler and nothing showing");

			[scroll setHasVerticalRuler:YES];
			check([scroll hasVerticalRuler], "asking for one is a flag, so it answers before a view exists");
			[scroll setRulersVisible:YES];
			{
				NSRulerView *ruler = [scroll verticalRulerView];
				NSRect frame = [ruler frame];
				NSRect content = [[scroll contentView] frame];

				check(ruler != nil, "showing it creates the ruler on demand");
				check([ruler orientation] == NSVerticalRuler, "with the orientation the scroll view asked for");
				check([ruler scrollView] == scroll, "and the scroll view it belongs to");
				check([ruler clientView] == document, "and the document it measures");
				check([ruler superview] == scroll, "and it is in the scroll view's own tree");
				check(close_enough(NSWidth(frame), [ruler requiredThickness]),
				      "its strip is exactly the thickness it requires");
				check(close_enough(NSWidth(content), contentBefore.width - NSWidth(frame)),
				      "and the document's content lost precisely that width");
				check(close_enough(NSMinX(content), NSMinX(frame) + NSWidth(frame)),
				      "which puts the content to the right of the ruler, not under it");
			}

			/* THE RULER'S WINDOW FOLLOWS THE DOCUMENT, AND ONLY ON ITS OWN AXIS. */
			[[scroll contentView] scrollToPoint:NSMakePoint(0.0, 250.0)];
			[scroll reflectScrolledClipView:[scroll contentView]];
			check(close_enough([[scroll verticalRulerView] bounds].origin.y, 250.0),
			      "scrolling the document moves the ruler's window down it");
			check(close_enough([[scroll verticalRulerView] bounds].origin.x, 0.0),
			      "and leaves the axis it does not measure alone");

			/* HIDING GIVES THE ROOM BACK AND KEEPS THE OBJECT, WITH ITS MARKERS. */
			{
				NSRulerView *ruler = [scroll verticalRulerView];
				NSImage *image = tab_image();
				NSRulerMarker *marker = [[NSRulerMarker alloc] initWithRulerView:ruler markerLocation:10.0
										   image:image imageOrigin:NSZeroPoint];

				[ruler setMarkers:[NSArray arrayWithObject:marker]];
				[scroll setRulersVisible:NO];
				check([scroll verticalRulerView] == ruler && [[ruler markers] count] == 1,
				      "hiding a ruler keeps both the ruler and its markers");
				check(close_enough(NSWidth([[scroll contentView] frame]), contentBefore.width),
				      "and the document gets its room back");
				[scroll setRulersVisible:YES];
				check(close_enough(NSWidth([[scroll contentView] frame]), contentBefore.width - [ruler requiredThickness]),
				      "showing it again takes the room once more");
				[marker release];
				[image release];
			}

			/* A HORIZONTAL RULER TAKES ITS OWN STRIP, ABOVE THE CONTENT AND RIGHT OF THE VERTICAL ONE. */
			[scroll setHasHorizontalRuler:YES];
			{
				NSRulerView *vr = [scroll verticalRulerView];
				NSRulerView *hr = [scroll horizontalRulerView];
				NSRect vf = [vr frame];
				NSRect hf = [hr frame];
				NSRect content = [[scroll contentView] frame];

				check(hr != nil, "a horizontal ruler is created the same way");
				check(close_enough(NSHeight(hf), [hr requiredThickness]), "it takes its own thickness off the top");
				check(close_enough(NSMinX(hf), NSMaxX(vf)), "and begins to the right of the vertical ruler");
				check(close_enough(NSMaxY(content), NSMinY(hf)),
				      "so the content's top is the ruler's bottom — no gap and no overlap");
				check(close_enough(NSMaxY(vf), NSMaxY([scroll bounds])),
				      "the vertical ruler runs the full height, corner included");
			}

			/* THE CLASS DOOR NAMES WHAT IS BUILT. */
			check([NSScrollView rulerViewClass] == [NSRulerView class], "the ruler class defaults to NSRulerView");
			[NSScrollView setRulerViewClass:[NSRulerView class]];
			check([NSScrollView rulerViewClass] == [NSRulerView class], "and setting it to the same class is a no-op");

			[document release];
			[scroll release];
		}

		if (failures == 0) {
			printf("ruler_view: all checks passed\n");
			return 0;
		}
		printf("ruler_view: FAILURES\n");
		return 1;
	}
}
