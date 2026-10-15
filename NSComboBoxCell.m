/*
 * NSComboBoxCell.m — the field, the chip, and the ONE triangle.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
#import <AppKit/NSComboBoxCell.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSStringDrawing.h>
#import <AppKit/NSView.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>
#import <Foundation/NSGeometry.h>

/* **A COMBO BOX IS A FIELD WITH A CHIP IN IT, AND THE CHIP IS THE POP-UP'S CHIP.** The five measures — the chip's
 * side and its inset, the mark's width and height, and the gap a doubled pair leaves — are `NSCell.h`'s, because the
 * two controls are the same field and two files keeping their own copy of a shared shape is how the pair the sample
 * draws TOGETHER comes to disagree with itself. What is this file's own is the NUMBER OF MARKS: one, and it points
 * DOWN. See `-cg_drawChipInFrame:` for the drawing and this header for why the count is a sentence about behaviour
 * rather than a decoration. */
@implementation NSComboBoxCell

- (instancetype)initTextCell:(NSString *)stringValue
{
	self = [super initTextCell:stringValue];
	if (self != nil) {
		/* **THE LIST STARTS EMPTY AND IS OURS TO OWN** — see the ivar's note on why it is retained rather than
		 * assigned: a caller who passes an array inline has nothing left to keep it alive with. */
		_objectValues = [[NSMutableArray alloc] init];
		_selectedIndex = -1;
		/* APPLE'S OWN DEFAULTS FOR THE TWO SHAPE FLAGS: a combo box completes as a person types and shows ten rows.
		 * Both are stored and neither is obeyed yet (see the header), so they are set here to the values a caller who
		 * asks will get rather than to zeroes that would read as "no list". */
		_numberOfVisibleItems = 10;
		_completes = YES;
	}
	return self;
}

- (void)dealloc
{
	[_objectValues release];
	[super dealloc];
}

/* ---- THE LIST ------------------------------------------------------------------------------------- */

- (NSInteger)numberOfItems
{
	return (NSInteger)[_objectValues count];
}

- (void)addItemWithObjectValue:(id)object
{
	if (object != nil) {
		[_objectValues addObject:object];
	}
}

- (void)addItemsWithObjectValues:(NSArray *)objects
{
	NSEnumerator *e = [objects objectEnumerator];
	id object;

	while ((object = [e nextObject]) != nil) {
		[self addItemWithObjectValue:object];
	}
}

/* **AND AN INSERT LEAVES THE SELECTION WHERE IT POINTED.** A caller who inserts above the chosen row has not changed
 * what is chosen, and a selection stored as a bare index WOULD have changed it — so the index is moved with the
 * insertion. This is the one place holding an index instead of an object costs anything, and it costs these four
 * lines rather than a rule anybody has to remember. */
- (void)insertItemWithObjectValue:(id)object atIndex:(NSInteger)index
{
	if (object == nil) {
		return;
	}
	if (index < 0 || index > (NSInteger)[_objectValues count]) {
		return;
	}
	[_objectValues insertObject:object atIndex:(NSUInteger)index];
	if (_selectedIndex >= index) {
		_selectedIndex++;
	}
}

- (void)removeAllItems
{
	[_objectValues removeAllObjects];
	/* NOTHING IS CHOSEN AND THE BOX HAS NOTHING TO SAY: the title goes with the list, because a box that kept the
	 * words of a row that no longer exists would be showing a value it no longer holds. */
	_selectedIndex = -1;
	[self setStringValue:@""];
}

- (void)removeItemAtIndex:(NSInteger)index
{
	if (index < 0 || index >= (NSInteger)[_objectValues count]) {
		return;
	}
	[_objectValues removeObjectAtIndex:(NSUInteger)index];
	if (index == _selectedIndex) {
		_selectedIndex = -1;
		[self setStringValue:@""];
	} else if (index < _selectedIndex) {
		_selectedIndex--;
	}
}

- (void)removeItemWithObjectValue:(id)object
{
	NSInteger index = [self indexOfItemWithObjectValue:object];

	if (index >= 0) {
		[self removeItemAtIndex:index];
	}
}

- (id)itemObjectValueAtIndex:(NSInteger)index
{
	if (index < 0 || index >= (NSInteger)[_objectValues count]) {
		return nil;
	}
	return [_objectValues objectAtIndex:(NSUInteger)index];
}

- (NSArray *)objectValues
{
	return _objectValues;
}

- (NSInteger)indexOfItemWithObjectValue:(id)object
{
	if (object == nil) {
		return -1;
	}
	return (NSInteger)[_objectValues indexOfObject:object];
}

/* ---- WHAT IS CHOSEN -------------------------------------------------------------------------------- */

- (NSInteger)indexOfSelectedItem
{
	return _selectedIndex;
}

/* **THE ONE SETTER, AND THE TITLE COMES FROM IT.** An index outside the list CLEARS the selection rather than being
 * refused, which is the same answer `-removeAllItems` gives and the same one Apple gives for `-1`: a box with nothing
 * chosen is a state this control has, not an error a caller made. The title is the object's own `-description`, which
 * is what makes a combo box able to hold something other than a string. */
- (void)selectItemAtIndex:(NSInteger)index
{
	id object = [self itemObjectValueAtIndex:index];

	if (object == nil) {
		_selectedIndex = -1;
		[self setStringValue:@""];
		return;
	}
	_selectedIndex = index;
	[self setStringValue:[object description]];
}

- (void)selectItemWithObjectValue:(id)object
{
	[self selectItemAtIndex:[self indexOfItemWithObjectValue:object]];
}

- (id)objectValueOfSelectedItem
{
	return [self itemObjectValueAtIndex:_selectedIndex];
}

/* ---- THE TWO SHAPE FLAGS, WHICH ARE STORED AND OBEY NOTHING YET ------------------------------------- */

- (NSInteger)numberOfVisibleItems
{
	return _numberOfVisibleItems;
}

- (void)setNumberOfVisibleItems:(NSInteger)count
{
	_numberOfVisibleItems = count;
}

- (BOOL)completes
{
	return _completes;
}

- (void)setCompletes:(BOOL)flag
{
	_completes = flag;
}

- (BOOL)usesDataSource
{
	return _usesDataSource;
}

- (void)setUsesDataSource:(BOOL)flag
{
	_usesDataSource = flag;
}

/* ---- THE INK -------------------------------------------------------------------------------------- */

/* **AND THE INK IS THE BASE'S TOO, WHICH FOLLOWS FROM THE FACE.** This class used to answer WHITE while its list was
 * open, because the face answered the accent then and white is what clears it. The face does not take the accent any
 * more — a combo box is a field, and a field is white in every state — so an ink that still turned white would be white
 * on white, which is the one defect this pairing exists to prevent. Both doors are gone together, which is the point:
 * the fill and the ink were one decision, and the decision now is the field's.
 */
/* ---- THE FACE ------------------------------------------------------------------------------------- */

/* **AND THE FIELD WEARS THE SAME FOUR FACES THE POP-UP BESIDE IT DOES, IN THE SAME ORDER — WHICH IS ALL THIS CLASS
 * HAS TO SAY ABOUT A FACE NOW.** `NSTextFieldCell` owns the border, the radius and the margin; what a CONTROL's field
 * adds is that its fill answers the pointer and the session, so the four answers are given here by NAME and the drawing
 * they are given to is inherited. `+controlColor` at rest, `+cg_prelightControlFaceColor` under the pointer,
 * `+cg_accentColor` while the list is open, and `+cg_disabledControlFaceColor` when it is disabled — the beats are the
 * pop-up's, and the WORDS move with the accent for the reason the ink door gives. */
/* **AND THE FIELD'S FACE IS THE FIELD'S FACE, IN EVERY STATE — WHICH IS WHAT "LIKE THE NORMAL TEXT FIELD" MEANS.**
 * There is NO override here any more, and its absence is the point: this class used to answer the accent while its list
 * was open and the prelight grey under the pointer, copying the POP-UP's behaviour because the sample draws the two
 * controls as a pair. A POP-UP IS A CONTROL — pressing it opens a menu — and a COMBO BOX IS A FIELD: a value is typed
 * into it, and a field does not change colour because a person is near it or typing in it. MEASURED, that grey was
 * also what the edit session painted, so it was visible as a box inside a white field the moment anybody clicked.
 *
 * WHAT IS GIVEN UP IS REAL AND IS NAMED HERE: the combo box no longer says "my list is open" by taking the accent. If
 * that signal is wanted back it is one method returning `+cg_accentColor` when `-isHighlighted`, and the LIST it belongs
 * to — which does not open yet — is the thing that should carry it.
 */
/* **AND THE ROOM THE WORDS GET IS THE FIELD'S LESS THE CHIP'S, WHICH IS THIS CLASS'S ONE MEASUREMENT OF THEM.** The
 * base insets the text by `NS_CELL_CONTENT_GAP`; a combo box's chip owns the right end of the field, so the rect stops
 * where the chip begins. IT IS OVERRIDDEN HERE RATHER THAN CLIPPED IN THE DRAWING because the same rect is what an
 * EDIT SESSION is handed — `NSTextFieldCell -selectWithFrame:...` puts the editor at `-drawingRectForBounds:` — so one
 * answer keeps a typed string from running under the chip, and a clip in the drawing alone would leave the editor
 * drawing over it. One rect, two callers. */
- (NSRect)drawingRectForBounds:(NSRect)theRect
{
	NSRect r = [super drawingRectForBounds:theRect];
	CGFloat limit = NSMinX([self cg_chipRectInFrame:theRect]);

	if (limit > NSMinX(r)) {
		r.size.width = limit - NSMinX(r);
	}
	return r;
}

/* **AND THE WORDS ARE THE BASE'S, WITH THE CHIP PUT ON AFTER THEM.** `NSTextFieldCell` draws the string left-aligned
 * at the text rect in the ink `-cg_inkColor` answers — which is why this class overrides THAT door and not the
 * drawing — so a combo box's title is drawn by the same code the field cell uses and cannot come out differently from
 * another field's. What is this class's own is the chip, and it goes on top because it is drawn over the field's
 * right end rather than beside the text. */
- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	[super drawInteriorWithFrame:cellFrame inView:controlView];
	[self cg_drawChipInFrame:cellFrame];
}

/* **THE CHIP'S RECT, WHICH IS WHERE THE DRAWING AND THE TITLE'S ROOM ARE BOTH MEASURED FROM.** At the sample's
 * position it is a square at the field's right end on the field's centre line. Its corner radius is
 * `NS_CELL_BEZEL_RADIUS`, the same four points the field's own corners take, because one control with two radii is the
 * sort of thing a person sees without being able to name. Defined before its callers so that a reader meets the
 * measurement before the drawing, which is the order the pop-up's file uses for the same method. */
- (NSRect)cg_chipRectInFrame:(NSRect)cellFrame
{
	CGFloat h = NSHeight(cellFrame);
	CGFloat side = h * NS_CELL_CHIP_FRACTION;
	CGFloat inset = h * NS_CELL_CHIP_INSET_FRACTION;
	CGFloat x = NSMaxX(cellFrame) - inset - side;
	CGFloat y = NSMidY(cellFrame) - side / 2.0;

	return NSMakeRect(x, y, side, side);
}

/* **THE CHIP, AND THE ONE TRIANGLE KNOCKED OUT OF IT.** A filled rounded square in the platform's accent with a
 * triangle drawn IN THE FIELD'S WHITE — the sample's construction, and the reason the arrow is white rather than
 * dark: it is not a mark ON the chip, it is a hole in it. The accent is `+cg_accentColor`, the same value the menu's
 * selection chip, a pressed button and the pop-up's chip wear, because a highlight is one statement wherever it is
 * made.
 *
 * **AND THE TRIANGLE POINTS DOWN, ALONE.** MEASURED from the sample: this chip carries ONE run of white down its
 * centre column (y=447..451) and the widest row of that run is its TOP, which is a triangle with its base up and its
 * apex down. The pop-up's chip beside it carries TWO runs (y=405..409 and y=414..418). A control that chose both ways
 * through its list would need both arrows; one that opens a single list needs the one that says "there is a list down
 * here".
 *
 * THE TRIANGLE IS FILLED WITH ANTIALIASING OFF, like every other triangle this tier draws and for the reason the
 * scroller's carries: a shape this small is almost entirely edge, and a blended fill reads as grey rather than as the
 * white it is. THE CHIP ITSELF IS NOT — it is a curve, and a curve wants the antialiasing this does not. */
- (void)cg_drawChipInFrame:(NSRect)cellFrame
{
	NSRect chip = [self cg_chipRectInFrame:cellFrame];
	NSBezierPath *face = [NSBezierPath bezierPathWithRoundedRect:chip xRadius:NS_CELL_BEZEL_RADIUS
							     yRadius:NS_CELL_BEZEL_RADIUS];
	CGFloat w = NSWidth(chip) * NS_CELL_CHIP_MARK_WIDTH_FRACTION;
	CGFloat h = NSHeight(chip) * NS_CELL_CHIP_MARK_HEIGHT_FRACTION;
	CGFloat cx = floor(NSMidX(chip)) + 0.5;
	CGFloat cy = floor(NSMidY(chip)) + 0.5;
	CGContextRef c = [[NSGraphicsContext currentContext] CGContext];
	NSBezierPath *mark;

	[[NSColor cg_accentColor] setFill];
	[face fill];
	if (c == NULL) {
		return;
	}
	CGContextSaveGState(c);
	CGContextSetShouldAntialias(c, false);
	[[NSColor controlBackgroundColor] setFill];
	/* ONE TRIANGLE, AND IT IS CENTRED ON THE CHIP rather than placed off the centre line the way a doubled pair has
	 * to be: with one mark there is no pair to centre, so the mark and the chip share a centre and the drawing says so
	 * rather than carrying a half-gap that would only be right for two. */
	mark = [NSBezierPath bezierPath];
	[mark moveToPoint:NSMakePoint(cx, cy - h / 2.0)];
	[mark lineToPoint:NSMakePoint(cx + w / 2.0, cy + h / 2.0)];
	[mark lineToPoint:NSMakePoint(cx - w / 2.0, cy + h / 2.0)];
	[mark closePath];
	[mark fill];
	CGContextRestoreGState(c);
}

/* ---- THE LIST, WHICH IS WHAT THE CHIP IS FOR ------------------------------------------------------- */

/* **AND THE CHIP OPENS THE LIST, WHICH IS THE ONE THING THE CHIP IS FOR.** MEASURED on the demonstration: clicking it
 * did nothing at all, because the chip's ink was drawn and the list behind it was never built — the row this control's
 * header has recorded since the first slice.
 *
 * **THE LIST IS DRAWN AS A MENU, AND THAT IS A DEPARTURE WORTH NAMING.** Apple's combo box opens a borderless LIST
 * WINDOW of its own; this tier opens the session `NSMenu` already has — the same one the pop-up beside it raises — and
 * builds the rows from `-_objectValues` on the way in. What that buys is a real session that starts, tracks, is
 * dismissed and sends a pick, none of which had to be written again; what it costs is that the rows wear a menu's ink
 * rather than a list's. The rows and the pick are the combo box's; the SKIN is borrowed, and a list window of its own
 * is the row that opens when the ink matters.
 *
 * THE ANCHOR IS THE CHIP'S BOTTOM-LEFT CORNER in the space a window frame lives in, which is the same three-space
 * arithmetic the pop-up's door records — the cell's frame in the view's coordinates, the view's with a nil view into
 * the window's, and the window's own origin where the list's window will be placed. */
- (void)cg_attachListWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	NSWindow *window = [controlView respondsToSelector:@selector(window)] ? [controlView window] : nil;
	NSMenu *list;
	NSRect chip = [self cg_chipRectInFrame:cellFrame];
	NSPoint where;
	NSUInteger i;

	if ([_objectValues count] == 0) {
		fprintf(stderr, "APPKIT-REFUSE: -cg_attachListWithFrame:inView: needs a list with rows — a combo box with "
				"nothing to choose from is not a combo box\n");
		return;
	}
	list = [[NSMenu alloc] initWithTitle:@"List"];
	for (i = 0; i < [_objectValues count]; i++) {
		/* **THE TAG IS THE INDEX, WHICH IS HOW THE PICK FINDS ITS WAY BACK.** A menu item's tag is a number a caller
		 * may use for anything, and what this control has to remember about a row is WHERE IT IS — the same fact
		 * `-indexOfItem:` recovers for the pop-up, kept directly because a combo box's rows are plain objects and there
		 * is no menu to ask. */
		NSMenuItem *item = [list addItemWithTitle:[[_objectValues objectAtIndex:i] description]
						   action:NULL keyEquivalent:@""];

		[item setTarget:self];
		[item setAction:@selector(itemSelected:)];
		[item setTag:(NSInteger)i];
	}
	/* **AND THE LIST IS ANCHORED WHERE THE POP-UP'S MENU IS: AT THE CONTROL'S OWN LEFT EDGE.** This door used to hand
	 * over the CHIP's corner, so the list hung under the arrow — and the two controls beside each other in the
	 * demonstration lined their raised windows up with different things, which is what "line it up with the control"
	 * was pointing at. `NSMenu` places its window at `location.x`, so that one number IS the alignment. */
	(void)window;
	where = [self cg_popUpAnchorForFrame:cellFrame inView:controlView];
	[list popUpMenuPositioningItem:nil atLocation:where inView:controlView];
	[list release];
}

/* **AND THE PICK IS THE SAME TWO THINGS THE POP-UP'S IS.** The row's index becomes the selection — which writes the
 * box's string, so the field shows what was chosen — and then the CELL's own action goes to the CELL's own target, with
 * the control as the sender, because that is what a caller who set a target is waiting for. */
- (void)itemSelected:(id)sender
{
	[self selectItemAtIndex:[sender tag]];
	[[NSApplication sharedApplication] sendAction:[self action] to:[self target] from:[self controlView]];
	if ([self controlView] != nil) {
		[[self controlView] setNeedsDisplay:YES];
	}
}

/* ---- WHAT IT MEASURES ------------------------------------------------------------------------------ */

/* **AND THE CHIP'S ZONE IS PART OF WHAT THIS CELL MEASURES, AND SO IS THE TITLE'S OWN MARGIN.** `NSActionCell` sizes
 * nothing, so the width is the title's plus the two things drawn beside it: the chip's zone — the chip and the inset
 * between it and the border, in the SAME fractions the drawing uses so the measurement and the ink cannot drift — and
 * `NS_CELL_CONTENT_GAP` — WHICH `NSCell`'S OWN MEASUREMENT ALREADY PAYS FOR A BORDERED CELL, so it is not added
 * here. See the pop-up's version of this door, which learned it the hard way: an extra four points is a band of
 * nothing at the frame's right end that no title can reach. */
- (NSSize)cellSizeForBounds:(NSRect)aRect
{
	NSSize size = [super cellSizeForBounds:aRect];

	size.width += size.height * (NS_CELL_CHIP_FRACTION + NS_CELL_CHIP_INSET_FRACTION);
	return size;
}

@end
