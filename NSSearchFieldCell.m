/*
 * NSSearchFieldCell.m — the field face, two ornament cells and the recents behind the magnifier.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
#import <AppKit/NSSearchFieldCell.h>
#import <AppKit/NSButtonCell.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSControl.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/NSText.h>
#import <AppKit/NSView.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSTimer.h>
#import <Foundation/NSUserDefaults.h>
#include <math.h>

/* **THE LAYOUT'S THREE NUMBERS, WHICH BOTH THE RECTANGLES AND THE MEASUREMENT USE.** The glyph is at most sixteen
 * points — a toolbar item's small size, and what this tier's field heights can hold — with three points of air at the
 * field's edge and two between the glyph and the text. A field shorter than twenty points shrinks the glyph rather
 * than letting it cross the border. */
#define AG_SEARCH_GLYPH_MAX	16.0
#define AG_SEARCH_GLYPH_EDGE	3.0
#define AG_SEARCH_GLYPH_GAP	2.0

/* **AND THE DELAY BEFORE A PARTIAL STRING IS SENT.** Apple's own field is deliberately not on every keystroke: the
 * timer restarts on each change, so a person typing a word produces one search rather than six. It is short enough
 * that a pause reads as "done", which is the whole heuristic. */
#define AG_SEARCH_DELAY		0.25

/* **THE BASE IMPLEMENTS THE EDITOR'S DELEGATE METHODS WITHOUT DECLARING THEM IN ITS HEADER** — they are the
 * `NSTextDelegate` methods it becomes while a session runs — so the two this subclass overrides are declared here,
 * where the compiler can see the signatures. */
@interface NSTextFieldCell (AGSearchFieldSession)
- (void)textDidChange:(NSNotification *)notification;
- (void)textDidEndEditing:(NSNotification *)notification;
@end

/* ============================================================================================ *
 * THE ORNAMENT CELL: A BUTTON CELL THAT DRAWS A GLYPH                                             *
 * ============================================================================================ */

typedef enum {
	AGSearchGlyphMagnifier = 0,
	AGSearchGlyphCancel
} AGSearchGlyph;

/* **THE DEFAULT ORNAMENTS ARE BUTTON CELLS, BECAUSE THAT IS WHAT THE SDK SAYS THEY ARE.** They have no image: the
 * magnifier and the circle are DRAWN, the same way the window chrome's marks are numbers in `NSWindow.m` rather than
 * resource files. A caller that sets an image gets the ordinary button drawing back — the check at the top of
 * `-drawWithFrame:` — so "replace the search button's picture" is one setter rather than a subclass. */
@interface AGSearchGlyphCell : NSButtonCell
{
	AGSearchGlyph _glyph;
}
- (instancetype)initWithGlyph:(AGSearchGlyph)glyph;
@end

static BOOL fn_is_y_down(void)
{
	CGContextRef cg = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
	CGAffineTransform transform = (cg != NULL) ? CGContextGetCTM(cg) : CGAffineTransformIdentity;

	return transform.d < 0.0;
}

/* **AND THE INK IS THE CONTROL'S ANSWER RATHER THAN THE ORNAMENT'S OWN.** The two button cells are not the control
 * being enabled or disabled, so reading their own flag would leave a magnifier at full strength in a disabled search
 * field. The view they are drawn into is the control, and its `-isEnabled` is the answer. */
static NSColor *fn_glyph_ink(id controlView)
{
	BOOL enabled = YES;

	if ([controlView isKindOfClass:[NSControl class]]) {
		enabled = [(NSControl *)controlView isEnabled];
	}
	return enabled ? [NSColor controlDarkShadowColor] : [NSColor disabledControlTextColor];
}

@implementation AGSearchGlyphCell

- (instancetype)initWithGlyph:(AGSearchGlyph)glyph
{
	self = [super initImageCell:nil];
	if (self != nil) {
		_glyph = glyph;
		/* AND THE FACE IS NONE: these are marks drawn on the FIELD's face, not small buttons standing on it. */
		[self setBordered:NO];
		[self setBezeled:NO];
		[self setButtonType:NSMomentaryChangeButton];
		[self setImagePosition:NSImageOnly];
		[self setEnabled:YES];
	}
	return self;
}

/* **THE MAGNIFIER IS A RING AND A HANDLE, AND THE HANDLE POINTS DOWN IN EITHER Y DIRECTION.** The circle sits a little
 * above and left of centre and the handle falls to the lower right, which is the shape a person reads as a magnifier
 * whatever the context's sign. `fn_is_y_down` is what makes "down" the same direction in a window (y up) and in a
 * flipped bitmap (y down), the same question `NSTextFieldCell` asks before it places a baseline. */
- (void)cg_drawMagnifierInRect:(NSRect)rect ink:(NSColor *)ink
{
	CGFloat side = MIN(NSWidth(rect), NSHeight(rect));
	CGFloat down = fn_is_y_down() ? 1.0 : -1.0;
	CGFloat cx = NSMidX(rect) - side * 0.06;
	CGFloat cy = NSMidY(rect) - down * side * 0.06;
	CGFloat radius = side * 0.26;
	NSBezierPath *glass = [NSBezierPath bezierPathWithOvalInRect:
		NSMakeRect(cx - radius, cy - radius, radius * 2.0, radius * 2.0)];
	NSBezierPath *handle = [NSBezierPath bezierPath];
	NSPoint from = NSMakePoint(cx + radius * 0.72, cy + down * radius * 0.72);
	NSPoint to = NSMakePoint(cx + side * 0.40, cy + down * side * 0.40);

	[ink setStroke];
	[glass setLineWidth:1.5];
	[glass stroke];
	[handle moveToPoint:from];
	[handle lineToPoint:to];
	[handle setLineWidth:1.5];
	[handle setLineCapStyle:NSRoundLineCapStyle];
	[handle stroke];
}

/* **AND THE CANCEL IS A DISC WITH A CROSS CUT OUT OF IT.** It is the same shape in both directions, so this one needs
 * no flip: a circle and two diagonals are their own mirror. The cross is the field's own white, which is what makes
 * the mark read as a hole in the disc rather than as a second grey ring. */
- (void)cg_drawCancelInRect:(NSRect)rect ink:(NSColor *)ink
{
	CGFloat side = MIN(NSWidth(rect), NSHeight(rect));
	CGFloat radius = side * 0.40;
	CGFloat cx = NSMidX(rect);
	CGFloat cy = NSMidY(rect);
	CGFloat reach = side * 0.16;
	NSBezierPath *disc = [NSBezierPath bezierPathWithOvalInRect:
		NSMakeRect(cx - radius, cy - radius, radius * 2.0, radius * 2.0)];
	NSBezierPath *cross = [NSBezierPath bezierPath];

	[ink setFill];
	[disc fill];
	[cross moveToPoint:NSMakePoint(cx - reach, cy - reach)];
	[cross lineToPoint:NSMakePoint(cx + reach, cy + reach)];
	[cross moveToPoint:NSMakePoint(cx - reach, cy + reach)];
	[cross lineToPoint:NSMakePoint(cx + reach, cy - reach)];
	[[NSColor whiteColor] setStroke];
	[cross setLineWidth:1.5];
	[cross setLineCapStyle:NSRoundLineCapStyle];
	[cross stroke];
}

/* **AN IMAGE, IF A CALLER SET ONE, IS ORDINARY BUTTON INK.** That is what makes `-setImage:` on the returned cell
 * meaningful rather than ignored: the glyph is the DEFAULT picture, not the only one the cell can have. */
- (void)drawWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	if ([self image] != nil) {
		[super drawWithFrame:cellFrame inView:controlView];
		return;
	}
	/* **THE FACE IS THE FIELD'S, SO ONLY THE MARK IS DRAWN — AND ITS INK IS THE CONTROL'S ENABLE STATE.** The
	 * default button face would put a bezel under every glyph, which is why this is not `-super`. */
	if (_glyph == AGSearchGlyphMagnifier) {
		[self cg_drawMagnifierInRect:cellFrame ink:fn_glyph_ink(controlView)];
	} else {
		[self cg_drawCancelInRect:cellFrame ink:fn_glyph_ink(controlView)];
	}
}

@end

/* ============================================================================================ *
 * THE SEARCH FIELD CELL                                                                       *
 * ============================================================================================ */

static CGFloat fn_glyph_size(NSRect rect)
{
	CGFloat height = NSHeight(rect) - 2.0 * AG_SEARCH_GLYPH_EDGE;
	CGFloat width = NSWidth(rect) / 3.0;

	if (height > AG_SEARCH_GLYPH_MAX) {
		height = AG_SEARCH_GLYPH_MAX;
	}
	if (height < 8.0) {
		height = 8.0;
	}
	if (width > 0.0 && height > width) {
		height = width;
	}
	return height;
}

/* **A TEMPLATE ITEM IS COPIED, BECAUSE THE MENU A PERSON SEES IS NOT THE TEMPLATE.** The template holds placeholders;
 * the built menu holds the recents and the two items about them. Copying keeps the caller's menu untouched while the
 * built one carries the same titles, key equivalents, targets and tags. */
static NSMenuItem *fn_copy_menu_item(NSMenuItem *source)
{
	NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[source title]
						     action:[source action]
					      keyEquivalent:[source keyEquivalent]];

	[item setTarget:[source target]];
	[item setTag:[source tag]];
	[item setEnabled:[source isEnabled]];
	[item setState:[source state]];
	[item setRepresentedObject:[source representedObject]];
	[item setKeyEquivalentModifierMask:[source keyEquivalentModifierMask]];
	return [item autorelease];
}

@implementation NSSearchFieldCell

/* ============================================================================================
 * ARCHIVING: A SEARCH FIELD'S TWO ORNAMENTS, ITS MENU AND ITS BEHAVIOUR.
 * ============================================================================================ */
/* **THE USER'S RECENT SEARCHES ARE NOT A DESIGN.** `_recentSearches` is what somebody typed on a machine, and a nib that
 * carried it would hand one person's history to the next. `_partialStringTimer`, `_cancelVisible` and
 * `_programmaticChange` are the state of a session. The two ornament cells and the menu template are the design, and
 * they are archivable objects. */
static NSString * const AGCoderSearchWholeStringKey = @"sendsWholeSearchString";
static NSString * const AGCoderSearchImmediatelyKey = @"sendsSearchStringImmediately";
static NSString * const AGCoderSearchMaximumRecentsKey = @"maximumRecents";
static NSString * const AGCoderSearchButtonCellKey = @"searchButtonCell";
static NSString * const AGCoderSearchCancelCellKey = @"cancelButtonCell";
static NSString * const AGCoderSearchMenuTemplateKey = @"searchMenuTemplate";
static NSString * const AGCoderSearchAutosaveNameKey = @"recentsAutosaveName";

- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[super encodeWithCoder:aCoder];
	[aCoder encodeBool:_sendsWholeSearchString forKey:AGCoderSearchWholeStringKey];
	[aCoder encodeBool:_sendsSearchStringImmediately forKey:AGCoderSearchImmediatelyKey];
	[aCoder encodeInteger:_maximumRecents forKey:AGCoderSearchMaximumRecentsKey];
	[aCoder encodeObject:_searchButtonCell forKey:AGCoderSearchButtonCellKey];
	[aCoder encodeObject:_cancelButtonCell forKey:AGCoderSearchCancelCellKey];
	[aCoder encodeObject:_searchMenuTemplate forKey:AGCoderSearchMenuTemplateKey];
	[aCoder encodeObject:_recentsAutosaveName forKey:AGCoderSearchAutosaveNameKey];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
	self = [super initWithCoder:aDecoder];
	if (self == nil) {
		return nil;
	}
	if ([aDecoder containsValueForKey:AGCoderSearchWholeStringKey]) {
		_sendsWholeSearchString = [aDecoder decodeBoolForKey:AGCoderSearchWholeStringKey];
	}
	if ([aDecoder containsValueForKey:AGCoderSearchImmediatelyKey]) {
		_sendsSearchStringImmediately = [aDecoder decodeBoolForKey:AGCoderSearchImmediatelyKey];
	}
	if ([aDecoder containsValueForKey:AGCoderSearchMaximumRecentsKey]) {
		_maximumRecents = [aDecoder decodeIntegerForKey:AGCoderSearchMaximumRecentsKey];
	}
	if ([aDecoder containsValueForKey:AGCoderSearchButtonCellKey]) {
		_searchButtonCell = [[aDecoder decodeObjectForKey:AGCoderSearchButtonCellKey] retain];
	}
	if ([aDecoder containsValueForKey:AGCoderSearchCancelCellKey]) {
		_cancelButtonCell = [[aDecoder decodeObjectForKey:AGCoderSearchCancelCellKey] retain];
	}
	if ([aDecoder containsValueForKey:AGCoderSearchMenuTemplateKey]) {
		_searchMenuTemplate = [[aDecoder decodeObjectForKey:AGCoderSearchMenuTemplateKey] retain];
	}
	if ([aDecoder containsValueForKey:AGCoderSearchAutosaveNameKey]) {
		_recentsAutosaveName = [[aDecoder decodeObjectForKey:AGCoderSearchAutosaveNameKey] copy];
	}
	return self;
}

+ (BOOL)supportsSecureCoding
{
	return YES;
}


- (instancetype)initTextCell:(NSString *)stringValue
{
	self = [super initTextCell:stringValue];
	if (self != nil) {
		/* **A SEARCH FIELD'S OWN DEFAULTS.** Ten recents is Apple's -1; the two sending flags are off, which is the
		 * delayed-search behaviour; and the field opens saying "Search", which is what a search field with no value
		 * says. */
		_maximumRecents = 10;
		_sendsWholeSearchString = NO;
		_sendsSearchStringImmediately = NO;
		_recentSearches = [[NSMutableArray alloc] init];
		_cancelVisible = NO;
		[self setPlaceholderString:@"Search"];
		[self resetSearchButtonCell];
		[self resetCancelButtonCell];
	}
	return self;
}

- (void)dealloc
{
	[_partialStringTimer invalidate];
	[_partialStringTimer release];
	[_searchButtonCell release];
	[_cancelButtonCell release];
	[_searchMenuTemplate release];
	[_recentsAutosaveName release];
	[_recentSearches release];
	[super dealloc];
}

/* ---- THE ORNAMENTS ---------------------------------------------------------------------------------- */

- (NSButtonCell *)searchButtonCell
{
	return _searchButtonCell;
}

- (void)setSearchButtonCell:(NSButtonCell *)cell
{
	if (cell != _searchButtonCell) {
		[cell retain];
		[_searchButtonCell release];
		_searchButtonCell = cell;
	}
	/* **THE TARGET IS THIS CELL AND THE ACTION IS THE MAGNIFIER'S, WHICH IS WHAT MAKES A REPLACEMENT WORK.** A caller
	 * that hands over its own cell should not have to know which selector the host listens for; the setter is where
	 * that knowledge lives. */
	[_searchButtonCell setTarget:self];
	[_searchButtonCell setAction:@selector(search:)];
	[(NSView *)[self controlView] setNeedsDisplay:YES];
}

- (NSButtonCell *)cancelButtonCell
{
	return _cancelButtonCell;
}

- (void)setCancelButtonCell:(NSButtonCell *)cell
{
	if (cell != _cancelButtonCell) {
		[cell retain];
		[_cancelButtonCell release];
		_cancelButtonCell = cell;
	}
	[_cancelButtonCell setTarget:self];
	[_cancelButtonCell setAction:@selector(cancel:)];
	[(NSView *)[self controlView] setNeedsDisplay:YES];
}

- (void)resetSearchButtonCell
{
	AGSearchGlyphCell *cell = [[AGSearchGlyphCell alloc] initWithGlyph:AGSearchGlyphMagnifier];

	[self setSearchButtonCell:cell];
	[cell release];
}

- (void)resetCancelButtonCell
{
	AGSearchGlyphCell *cell = [[AGSearchGlyphCell alloc] initWithGlyph:AGSearchGlyphCancel];

	[self setCancelButtonCell:cell];
	[cell release];
}

/* **THE THREE RECTANGLES COME FROM ONE SET OF NUMBERS, SO THEY CANNOT DISAGREE.** The glyph's size shrinks with a very
 * short field; the slots are otherwise fixed, and the text rect is what remains between them. */
- (NSRect)searchButtonRectForBounds:(NSRect)rect
{
	CGFloat size = fn_glyph_size(rect);

	return NSMakeRect(NSMinX(rect) + AG_SEARCH_GLYPH_EDGE,
			  NSMidY(rect) - size / 2.0, size, size);
}

- (NSRect)cancelButtonRectForBounds:(NSRect)rect
{
	CGFloat size = fn_glyph_size(rect);

	return NSMakeRect(NSMaxX(rect) - AG_SEARCH_GLYPH_EDGE - size,
			  NSMidY(rect) - size / 2.0, size, size);
}

- (NSRect)searchTextRectForBounds:(NSRect)rect
{
	NSRect search = [self searchButtonRectForBounds:rect];
	NSRect cancel = [self cancelButtonRectForBounds:rect];
	CGFloat left = NSMaxX(search) + AG_SEARCH_GLYPH_GAP;
	CGFloat right = NSMinX(cancel) - AG_SEARCH_GLYPH_GAP;
	NSRect room = NSMakeRect(left, NSMinY(rect) + NS_TEXT_INSET,
				 right - left, NSHeight(rect) - 2.0 * NS_TEXT_INSET);

	if (NSWidth(room) < 0.0) {
		room.size.width = 0.0;
	}
	if (NSHeight(room) < 0.0) {
		room.size.height = 0.0;
	}
	return room;
}

/* **AND THE FIELD'S TEXT RECT IS THE SEARCH TEXT RECT.** Everything above this class uses
 * `-drawingRectForBounds:` — the drawn string, the placeholder and the editor's frame — so this one override is what
 * keeps the ornaments and the words from sharing a column. The cancel slot is reserved whether or not the button is
 * visible, which is what keeps the editor still when the first typed character reveals it. */
- (NSRect)drawingRectForBounds:(NSRect)theRect
{
	return [self searchTextRectForBounds:theRect];
}

/* **AND THE MEASUREMENT PAYS FOR BOTH ORNAMENT SLOTS.** The base measures the value and the field's padding; a search
 * field also has to hold the magnifier and the cancel circle, so its natural width is the text's plus one slot at
 * each end. The cancel slot is counted even while the button is hidden, for the same reason the text rect reserves
 * it: a field that changed width when somebody typed would be a field that moved under the caret. */
- (NSSize)cellSizeForBounds:(NSRect)aRect
{
	NSSize size = [super cellSizeForBounds:aRect];

	size.width += 2.0 * (AG_SEARCH_GLYPH_EDGE + AG_SEARCH_GLYPH_MAX + AG_SEARCH_GLYPH_GAP);
	return size;
}

/* **THE FACE AND THE WORDS ARE THE BASE'S; THE ORNAMENTS ARE DRAWN OVER THEM AFTERWARDS.** The text is already
 * clipped to the search text rect by `-drawingRectForBounds:`, so a glyph drawn at the edge cannot be covered by a
 * long value. */
- (void)drawWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	[super drawWithFrame:cellFrame inView:controlView];
	if (_searchButtonCell != nil) {
		[_searchButtonCell drawWithFrame:[self searchButtonRectForBounds:cellFrame] inView:controlView];
	}
	if (_cancelVisible && _cancelButtonCell != nil) {
		[_cancelButtonCell drawWithFrame:[self cancelButtonRectForBounds:cellFrame] inView:controlView];
	}
}

/* ---- THE CANCEL BUTTON'S VISIBILITY --------------------------------------------------------------- */

/* **THE LIVE TEXT IS THE EDITOR'S WHILE A SESSION RUNS.** The cell's own value is the value the session started
 * with, so asking it would leave the cancel button hidden until the edit ended — which is the opposite of what the
 * button is for. */
- (BOOL)cg_hasLiveText
{
	NSString *text = _cg_textEditing ? [(NSText *)_cg_editor string] : [self cg_contentText];

	return [text length] > 0;
}

/* **AND THE BUTTON APPEARS THE MOMENT THERE IS SOMETHING TO CLEAR.** Only a change of the answer redraws, so a
 * keystroke in a field that already has text costs no extra invalidation; the editor is drawing those pixels. */
- (void)cg_syncCancelButton
{
	BOOL want = [self cg_hasLiveText];

	if (want != _cancelVisible) {
		_cancelVisible = want;
		[(NSView *)[self controlView] setNeedsDisplay:YES];
	}
}

- (BOOL)cg_isCancelVisible
{
	return _cancelVisible;
}

/* **A VALUE SET FROM CODE GOES THROUGH ONE PLACE, WHETHER IT NAMED THE STRING OR THE OBJECT.** `-setStringValue:`
 * spells `-setObjectValue:`, but a control may call either, so both sync the ornament. */
- (void)setObjectValue:(id)value
{
	BOOL was = _programmaticChange;

	_programmaticChange = YES;
	[super setObjectValue:value];
	_programmaticChange = was;
	[self cg_syncCancelButton];
}

- (void)setStringValue:(NSString *)aString
{
	BOOL was = _programmaticChange;

	_programmaticChange = YES;
	[super setStringValue:aString];
	_programmaticChange = was;
	[self cg_syncCancelButton];
}

/* ---- THE RECENTS ------------------------------------------------------------------------------------ */

- (void)setMaximumRecents:(NSInteger)maxRecents
{
	if (maxRecents < 0) {
		maxRecents = 10;
	}
	if (maxRecents > 254) {
		maxRecents = 254;
	}
	_maximumRecents = maxRecents;
	while ((NSInteger)[_recentSearches count] > _maximumRecents) {
		[_recentSearches removeLastObject];
	}
	[self cg_saveRecents];
}

- (NSInteger)maximumRecents
{
	return _maximumRecents;
}

- (void)setRecentSearches:(NSArray *)searches
{
	NSMutableArray *copy = [[NSMutableArray alloc] init];
	NSUInteger i;

	if (searches != nil) {
		for (i = 0; i < [searches count]; i++) {
			id term = [searches objectAtIndex:i];

			if ([term isKindOfClass:[NSString class]] && [(NSString *)term length] > 0) {
				[copy addObject:term];
			}
		}
	}
	while ((NSInteger)[copy count] > _maximumRecents) {
		[copy removeLastObject];
	}
	[_recentSearches release];
	_recentSearches = copy;
	[self cg_saveRecents];
}

- (NSArray *)recentSearches
{
	return [NSArray arrayWithArray:_recentSearches];
}

- (void)setRecentsAutosaveName:(NSString *)string
{
	NSString *copy = [string copy];

	[_recentsAutosaveName release];
	_recentsAutosaveName = copy;
	/* **SETTING THE NAME IS ALSO LOADING WHAT IT NAMED.** A field that is built again with the same autosave name
	 * should open with the searches it had; a name with nothing stored leaves the list as it was. */
	if (copy != nil) {
		NSArray *stored = [[NSUserDefaults standardUserDefaults] arrayForKey:copy];

		if (stored != nil) {
			[self setRecentSearches:stored];
		}
	}
	/* **AND A NAME GIVEN TO A LIST THAT ALREADY EXISTS ADOPTS IT.** The other order — name first, searches second —
	 * saves on the setter below; this one has nothing to load and would otherwise leave the current list unsaved
	 * until its next change. Writing it here makes both orders mean the same thing. */
	[self cg_saveRecents];
}

- (NSString *)recentsAutosaveName
{
	return _recentsAutosaveName;
}

- (void)cg_saveRecents
{
	if (_recentsAutosaveName != nil && _recentSearches != nil) {
		[[NSUserDefaults standardUserDefaults] setObject:_recentSearches
							  forKey:_recentsAutosaveName];
	}
}

/* **A TERM IS REMEMBERED ONCE, AT THE FRONT, AND ONLY IF IT IS A TERM.** An empty string is not a search; a repeat
 * moves to the front rather than appearing twice; and the list stops at `-maximumRecents`. */
- (void)cg_addRecentSearch:(NSString *)term
{
	NSUInteger existing;

	if (term == nil || [term length] == 0) {
		return;
	}
	existing = [_recentSearches indexOfObject:term];
	if (existing != NSNotFound) {
		[_recentSearches removeObjectAtIndex:existing];
	}
	[_recentSearches insertObject:term atIndex:0];
	while ((NSInteger)[_recentSearches count] > _maximumRecents) {
		[_recentSearches removeLastObject];
	}
	[self cg_saveRecents];
}

- (void)cg_addRecentItemsToMenu:(NSMenu *)menu
{
	NSUInteger i;

	for (i = 0; i < [_recentSearches count]; i++) {
		NSString *term = [_recentSearches objectAtIndex:i];
		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:term
							     action:@selector(cg_chooseRecent:)
						      keyEquivalent:@""];

		[item setTarget:self];
		[item setRepresentedObject:term];
		[menu addItem:item];
		[item release];
	}
}

/* **THE MENU IS BUILT WHERE THE TEMPLATE'S TAGS SAY.** The four tags are placeholders, not items: the recents title
 * appears only when there are recents, each recent is inserted where the template asked, the clear item is offered
 * only when there is something to clear, and the "no recents" item only when there is not. A template with no tags
 * gets the recents appended, which is the only sensible place left when nobody named one. */
- (NSMenu *)cg_searchMenu
{
	NSMenu *menu;
	NSArray *items;
	NSUInteger i;
	BOOL placedRecents = NO;

	if (_searchMenuTemplate == nil) {
		return nil;
	}
	menu = [[[NSMenu alloc] initWithTitle:@""] autorelease];
	[menu setAutoenablesItems:NO];
	items = [_searchMenuTemplate itemArray];
	for (i = 0; i < [items count]; i++) {
		NSMenuItem *source = [items objectAtIndex:i];
		NSInteger tag = [source tag];

		if (tag == NSSearchFieldRecentsTitleMenuItemTag) {
			if ([_recentSearches count] > 0) {
				[menu addItem:fn_copy_menu_item(source)];
				[self cg_addRecentItemsToMenu:menu];
				placedRecents = YES;
			}
		} else if (tag == NSSearchFieldRecentsMenuItemTag) {
			[self cg_addRecentItemsToMenu:menu];
			placedRecents = YES;
		} else if (tag == NSSearchFieldClearRecentsMenuItemTag) {
			if ([_recentSearches count] > 0) {
				NSMenuItem *item = fn_copy_menu_item(source);

				[item setAction:@selector(cg_clearRecents:)];
				[item setTarget:self];
				[item setEnabled:YES];
				[menu addItem:item];
			}
		} else if (tag == NSSearchFieldNoRecentsMenuItemTag) {
			if ([_recentSearches count] == 0) {
				NSMenuItem *item = fn_copy_menu_item(source);

				[item setEnabled:NO];
				[menu addItem:item];
			}
		} else {
			[menu addItem:fn_copy_menu_item(source)];
		}
	}
	if (!placedRecents && [_recentSearches count] > 0) {
		[self cg_addRecentItemsToMenu:menu];
	}
	return menu;
}

- (void)setSearchMenuTemplate:(NSMenu *)menu
{
	[menu retain];
	[_searchMenuTemplate release];
	_searchMenuTemplate = menu;
}

- (NSMenu *)searchMenuTemplate
{
	return _searchMenuTemplate;
}

- (void)cg_chooseRecent:(id)sender
{
	NSString *term = [(NSMenuItem *)sender representedObject];

	if (term != nil) {
		[self setStringValue:term];
		[self cg_stopPartialStringTimer];
		[self cg_sendSearchAction];
	}
}

- (void)cg_clearRecents:(id)sender
{
	(void)sender;
	[_recentSearches removeAllObjects];
	[self cg_saveRecents];
}

/* ---- WHAT TYPING MEANS ------------------------------------------------------------------------------ */

- (void)setSendsWholeSearchString:(BOOL)flag
{
	_sendsWholeSearchString = flag;
}

- (BOOL)sendsWholeSearchString
{
	return _sendsWholeSearchString;
}

- (void)setSendsSearchStringImmediately:(BOOL)flag
{
	_sendsSearchStringImmediately = flag;
}

- (BOOL)sendsSearchStringImmediately
{
	return _sendsSearchStringImmediately;
}

/* **THE CONTROL'S ACTION, NOT THIS CELL'S.** The cell's own target/action pair is the search TERM's owner, and the
 * ornament cells' target is this cell; the handler a caller wrote belongs to the CONTROL, so that is the pair sent.
 * A search field with no target and no action sends nothing, which is what a nil action means everywhere. */
- (void)cg_sendSearchAction
{
	id view = [self controlView];

	if (![view isKindOfClass:[NSControl class]]) {
		return;
	}
	if ([(NSControl *)view action] != NULL) {
		[(NSControl *)view sendAction:[(NSControl *)view action] to:[(NSControl *)view target]];
	}
}

- (void)cg_stopPartialStringTimer
{
	[_partialStringTimer invalidate];
	[_partialStringTimer release];
	_partialStringTimer = nil;
}

- (void)cg_partialStringTimerFired:(NSTimer *)timer
{
	(void)timer;
	[self cg_stopPartialStringTimer];
	[self cg_sendSearchAction];
}

- (NSTimer *)cg_partialStringTimer
{
	return _partialStringTimer;
}

/* **A CHANGE RESTS THE TIMER AND THEN DECIDES WHETHER TO SEND NOW, LATER, OR NOT UNTIL RETURN.** The relay to the
 * control happens first — that is the notification a listener registered for — and the ornament's visibility follows
 * the live text. */
- (void)textDidChange:(NSNotification *)notification
{
	[super textDidChange:notification];
	[self cg_syncCancelButton];
	/* **A CHANGE THE CODE MADE IS NOT A KEYSTROKE.** The door that wrote it sends once itself; letting the editor's
	 * notification send again would be two searches for one choice. */
	if (_programmaticChange) {
		return;
	}
	if (_sendsWholeSearchString) {
		return;
	}
	[self cg_stopPartialStringTimer];
	if (_sendsSearchStringImmediately) {
		[self cg_sendSearchAction];
	} else {
		_partialStringTimer = [[NSTimer scheduledTimerWithTimeInterval:AG_SEARCH_DELAY
								       target:self
								     selector:@selector(cg_partialStringTimerFired:)
								     userInfo:nil
								      repeats:NO] retain];
	}
}

/* **RETURN IS THE COMMIT: THE TERM IS REMEMBERED, THE TIMER IS DROPPED, AND THE BASE SENDS THE ACTION.** The base
 * sends on Return and Tab, so a pending partial search does not also fire; the cancel reason is the one ending that
 * commits nothing. The string read for the recents is the EDITOR's, because this runs before the base takes the
 * editor's text back into the cell. */
- (void)textDidEndEditing:(NSNotification *)notification
{
	id raw = [[notification userInfo] objectForKey:NSTextMovementUserInfoKey];
	NSTextMovement movement = (raw != nil) ? (NSTextMovement)[raw integerValue] : NSTextMovementOther;
	NSString *term = _cg_textEditing ? [(NSText *)_cg_editor string] : [self cg_contentText];

	[self cg_stopPartialStringTimer];
	if (movement == NSTextMovementReturn && _searchMenuTemplate != nil) {
		[self cg_addRecentSearch:term];
	}
	[super textDidEndEditing:notification];
	[self cg_syncCancelButton];
}

/* **AND AN ABORT IS THE SAME ENDING WITH THE SAME TIDYING.** The base throws the session away; the timer has nothing
 * left to send and the cancel button follows the value the field went back to. */
- (BOOL)cg_abortEditing
{
	BOOL aborted = [super cg_abortEditing];

	[self cg_stopPartialStringTimer];
	[self cg_syncCancelButton];
	return aborted;
}

/* ---- THE TWO ORNAMENT ACTIONS ----------------------------------------------------------------------- */

/* **THE MAGNIFIER EITHER SHOWS THE TEMPLATE'S MENU OR SENDS.** With a template the current term is remembered first,
 * so the menu the click opens contains it; with no template there is no recents UI to show and the click is a
 * "search now". The popup itself is `NSMenu`'s blocking session, which is why no test calls this door with a template
 * set — it is read through `-cg_searchMenu` instead. */
- (void)search:(id)sender
{
	NSMenu *menu;

	(void)sender;
	/* **THE RECENTS ARE TRACKED ONLY WHEN THERE IS A RECENTS UI TO SHOW THEM.** The SDK's sentence about the template
	 * is "if cleared, then we don't track recents", so the magnifier remembers the term only when a template is set;
	 * without one it is a plain "search now" and the list is the caller's. */
	if (_searchMenuTemplate != nil) {
		NSString *term = _cg_textEditing ? [(NSText *)_cg_editor string] : [self cg_contentText];

		[self cg_addRecentSearch:([term length] > 0) ? term : nil];
	}
	menu = [self cg_searchMenu];
	if (menu != nil && [menu numberOfItems] > 0 && [[self controlView] isKindOfClass:[NSView class]]) {
		NSRect rect = [self searchButtonRectForBounds:[(NSView *)[self controlView] bounds]];

		[menu popUpMenuPositioningItem:nil
				    atLocation:NSMakePoint(NSMinX(rect), NSMinY(rect))
				       inView:(NSView *)[self controlView]];
		return;
	}
	[self cg_sendSearchAction];
}

/* **AND THE CANCEL CLEARS, HIDES ITSELF AND SENDS.** An empty search is a real result — the filter is gone — so the
 * control's action goes out with an empty value rather than staying silent. */
- (void)cancel:(id)sender
{
	(void)sender;
	/* **THE STRING GOES FIRST AND THE TIMER IS STOPPED AFTER IT.** Writing the value tells a live editor, which
	 * produces the change notification; the programmatic flag keeps that from arming or sending anything, and the
	 * stop is still here because the door should not depend on the flag's ordering to be quiet. */
	[self setStringValue:@""];
	[self cg_stopPartialStringTimer];
	[self cg_syncCancelButton];
	[(NSView *)[self controlView] setNeedsDisplay:YES];
	[self cg_sendSearchAction];
}

/* ---- THE PRESS'S HIT TEST --------------------------------------------------------------------------- */

/* **THE SAME TEST A PRESS RUNS, NAMED SO A PROBE CAN RUN IT WITHOUT AN EVENT.** The search field converts the event's
 * point and calls this; a point in the cancel circle clears, a point in the magnifier searches, and anything else is
 * the field's own press and belongs to the base class. */
- (BOOL)cg_handleClickAtPoint:(NSPoint)point inView:(NSView *)view
{
	NSRect bounds = (view != nil) ? [view bounds] : NSMakeRect(0.0, 0.0, 0.0, 0.0);

	if (_cancelVisible && NSPointInRect(point, [self cancelButtonRectForBounds:bounds])) {
		[self cancel:nil];
		return YES;
	}
	if (NSPointInRect(point, [self searchButtonRectForBounds:bounds])) {
		[self search:nil];
		return YES;
	}
	return NO;
}

@end
