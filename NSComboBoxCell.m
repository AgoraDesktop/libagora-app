/*
 * NSComboBoxCell.m — the field, the chip, and the ONE triangle.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
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
#import "AGComboListView.h"
#import <AppKit/NSWindow.h>
#import <Foundation/NSGeometry.h>
#import "AppKitRefusal.h"

/* **A COMBO BOX IS A FIELD WITH A CHIP IN IT, AND THE CHIP IS THE POP-UP'S CHIP.** The five measures — the chip's
 * side and its inset, the mark's width and height, and the gap a doubled pair leaves — are `NSCell.h`'s, because the
 * two controls are the same field and two files keeping their own copy of a shared shape is how the pair the sample
 * draws TOGETHER comes to disagree with itself. What is this file's own is the NUMBER OF MARKS: one, and it points
 * DOWN. See `-cg_drawChipInFrame:` for the drawing and this header for why the count is a sentence about behaviour
 * rather than a decoration. */
@implementation NSComboBoxCell

/* ============================================================================================
 * ARCHIVING: A COMBO BOX'S ITEMS, ITS SELECTION AND ITS BEHAVIOUR.
 * ============================================================================================ */
static NSString * const AGCoderComboValuesKey = @"objectValues";
static NSString * const AGCoderComboSelectedKey = @"selectedIndex";
static NSString * const AGCoderComboVisibleItemsKey = @"numberOfVisibleItems";
static NSString * const AGCoderComboCompletesKey = @"completes";
static NSString * const AGCoderComboDataSourceKey = @"usesDataSource";
static NSString * const AGCoderComboItemHeightKey = @"itemHeight";
static NSString * const AGCoderComboIntercellKey = @"intercellSpacing";
static NSString * const AGCoderComboButtonBorderedKey = @"buttonBordered";
/* **AND THE DATA SOURCE IS NOT ARCHIVED, WHICH IS A DECISION RATHER THAN AN OMISSION.** A source is an OBJECT the
 * caller owns and feeds — it is not a design property of the box, it has no coding protocol in this tier, and a nib
 * that carried one would be carrying a live graph. Apple's own answer is the same: what archives is the box's own
 * rows, and a box whose `-usesDataSource` is YES archives the flag but not the object it points at. */

- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[super encodeWithCoder:aCoder];
	[aCoder encodeObject:_objectValues forKey:AGCoderComboValuesKey];
	[aCoder encodeInteger:_selectedIndex forKey:AGCoderComboSelectedKey];
	[aCoder encodeInteger:_numberOfVisibleItems forKey:AGCoderComboVisibleItemsKey];
	[aCoder encodeBool:_completes forKey:AGCoderComboCompletesKey];
	[aCoder encodeBool:_usesDataSource forKey:AGCoderComboDataSourceKey];
	[aCoder encodeDouble:(double)_itemHeight forKey:AGCoderComboItemHeightKey];
	[aCoder encodeSize:_intercellSpacing forKey:AGCoderComboIntercellKey];
	[aCoder encodeBool:_buttonBordered forKey:AGCoderComboButtonBorderedKey];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
	self = [super initWithCoder:aDecoder];
	if (self == nil) {
		return nil;
	}
	if ([aDecoder containsValueForKey:AGCoderComboValuesKey]) {
		_objectValues = [[aDecoder decodeObjectForKey:AGCoderComboValuesKey] mutableCopy];
	}
	if ([aDecoder containsValueForKey:AGCoderComboSelectedKey]) {
		_selectedIndex = [aDecoder decodeIntegerForKey:AGCoderComboSelectedKey];
	}
	if ([aDecoder containsValueForKey:AGCoderComboVisibleItemsKey]) {
		_numberOfVisibleItems = [aDecoder decodeIntegerForKey:AGCoderComboVisibleItemsKey];
	}
	if ([aDecoder containsValueForKey:AGCoderComboCompletesKey]) {
		_completes = [aDecoder decodeBoolForKey:AGCoderComboCompletesKey];
	}
	if ([aDecoder containsValueForKey:AGCoderComboDataSourceKey]) {
		_usesDataSource = [aDecoder decodeBoolForKey:AGCoderComboDataSourceKey];
	}
	if ([aDecoder containsValueForKey:AGCoderComboItemHeightKey]) {
		_itemHeight = (CGFloat)[aDecoder decodeDoubleForKey:AGCoderComboItemHeightKey];
	}
	if ([aDecoder containsValueForKey:AGCoderComboIntercellKey]) {
		_intercellSpacing = [aDecoder decodeSizeForKey:AGCoderComboIntercellKey];
	}
	if ([aDecoder containsValueForKey:AGCoderComboButtonBorderedKey]) {
		_buttonBordered = [aDecoder decodeBoolForKey:AGCoderComboButtonBorderedKey];
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
		/* **THE LIST STARTS EMPTY AND IS OURS TO OWN** — see the ivar's note on why it is retained rather than
		 * assigned: a caller who passes an array inline has nothing left to keep it alive with. */
		_objectValues = [[NSMutableArray alloc] init];
		_selectedIndex = -1;
		/* APPLE'S OWN DEFAULTS FOR THE TWO SHAPE FLAGS: a combo box completes as a person types and shows ten rows.
		 * Both are stored and neither is obeyed yet (see the header), so they are set here to the values a caller who
		 * asks will get rather than to zeroes that would read as "no list". */
		_numberOfVisibleItems = 10;
		_completes = YES;
		/* **AND A COMBO BOX IS EDITABLE BY DEFAULT, WHICH IS APPLE'S ANSWER AND THE ONE THE VIEW NOW DEPENDS ON.**
		 * `NSCell`'s default is NO — a cell is not a field unless it says so — and this class inherited that while the
		 * CONTROL above opened a session on every press anyway, so the flag said one thing and the behaviour did another.
		 * The control's base is `NSTextField` now, whose press is gated on exactly this flag, so setting it here is what
		 * makes the two agree: a combo box IS a field, and a field IS editable. */
		[self setEditable:YES];
		/* **AND THE LIST'S SHAPE STARTS AT "THE SESSION'S OWN" AND THE CHIP BORDERED.** A height of 0 and a spacing
		 * of (0, 0) are what leave every menu's existing row arithmetic alone (see `-setItemHeight:`), and a bordered
		 * chip is the picture this class has always drawn. */
		_itemHeight = 0.0;
		_intercellSpacing = NSMakeSize(0.0, 0.0);
		_buttonBordered = YES;
	}
	return self;
}

- (void)dealloc
{
	[_objectValues release];
	[super dealloc];
}

/* ---- THE LIST ------------------------------------------------------------------------------------- */

/* **THE TWO DOORS EVERY OTHER ROW DOOR READS THROUGH, WHICH IS WHAT MAKES THE DATA SOURCE ONE DECISION.** A box with a
 * source takes its rows from the source; a box without one takes them from its own array. Everything that counts or
 * fetches a row asks these two — so there is exactly one place that knows the difference, and a door cannot honour the
 * source while its neighbour forgets it. The source answers the CELL protocol (see the header on why the noun differs
 * from the view's), and a source that does not implement a REQUIRED member is treated as absent rather than sent a
 * message it would not understand. */
- (BOOL)fn_usesDataSource
{
	return _usesDataSource && _dataSource != nil;
}

- (NSInteger)fn_itemCount
{
	if ([self fn_usesDataSource]) {
		if ([(id)_dataSource respondsToSelector:@selector(numberOfItemsInComboBoxCell:)]) {
			return (NSInteger)[(id)_dataSource numberOfItemsInComboBoxCell:self];
		}
		return 0;
	}
	return (NSInteger)[_objectValues count];
}

- (id)fn_itemObjectAtIndex:(NSInteger)index
{
	if (index < 0 || index >= [self fn_itemCount]) {
		return nil;
	}
	if ([self fn_usesDataSource]) {
		if ([(id)_dataSource respondsToSelector:@selector(comboBoxCell:objectValueForItemAtIndex:)]) {
			return [(id)_dataSource comboBoxCell:self objectValueForItemAtIndex:index];
		}
		return nil;
	}
	return [_objectValues objectAtIndex:(NSUInteger)index];
}

- (NSInteger)numberOfItems
{
	return [self fn_itemCount];
}

- (void)addItemWithObjectValue:(id)object
{
	if ([self fn_usesDataSource]) {
		fn_refuse_window("-[NSComboBoxCell addItemWithObjectValue:]",
				 "an own row list (this box has a data source, and a row written into the box would be a row "
				 "nothing reads — change the source instead)");
		return;
	}
	if (object != nil) {
		[_objectValues addObject:object];
	}
}

- (void)addItemsWithObjectValues:(NSArray *)objects
{
	NSEnumerator *e = [objects objectEnumerator];
	id object;

	if ([self fn_usesDataSource]) {
		fn_refuse_window("-[NSComboBoxCell addItemsWithObjectValues:]",
				 "an own row list (this box has a data source — see `-addItemWithObjectValue:`)");
		return;
	}

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
	if ([self fn_usesDataSource]) {
		fn_refuse_window("-[NSComboBoxCell insertItemWithObjectValue:atIndex:]",
				 "an own row list (this box has a data source — see `-addItemWithObjectValue:`)");
		return;
	}
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
	if ([self fn_usesDataSource]) {
		fn_refuse_window("-[NSComboBoxCell removeAllItems]",
				 "an own row list (this box has a data source — see `-addItemWithObjectValue:`)");
		return;
	}
	[_objectValues removeAllObjects];
	/* NOTHING IS CHOSEN AND THE BOX HAS NOTHING TO SAY: the title goes with the list, because a box that kept the
	 * words of a row that no longer exists would be showing a value it no longer holds. */
	_selectedIndex = -1;
	[self setStringValue:@""];
}

- (void)removeItemAtIndex:(NSInteger)index
{
	if ([self fn_usesDataSource]) {
		fn_refuse_window("-[NSComboBoxCell removeItemAtIndex:]",
				 "an own row list (this box has a data source — see `-addItemWithObjectValue:`)");
		return;
	}
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
	return [self fn_itemObjectAtIndex:index];
}

- (NSArray *)objectValues
{
	/* **AND WITH A SOURCE THE ANSWER IS STILL AN ARRAY, BECAUSE A CALLER ASKED FOR ONE.** Apple's array is the box's
	 * own list; with a source the rows are the source's, so they are gathered — the useful reading, and the one that
	 * keeps this door from answering an empty array for a box that visibly has rows. */
	if ([self fn_usesDataSource]) {
		NSInteger count = [self fn_itemCount];
		NSMutableArray *gathered = [NSMutableArray arrayWithCapacity:(NSUInteger)(count > 0 ? count : 0)];
		NSInteger i;

		for (i = 0; i < count; i++) {
			id row = [self fn_itemObjectAtIndex:i];

			if (row != nil) {
				[gathered addObject:row];
			}
		}
		return gathered;
	}
	return _objectValues;
}

- (NSInteger)indexOfItemWithObjectValue:(id)object
{
	if (object == nil) {
		return -1;
	}
	if ([self fn_usesDataSource]) {
		/* THE SOURCE'S OWN INDEX WHEN IT HAS ONE, for a STRING value: Apple's optional door is about a typed string,
		 * which is the only thing a source can index without comparing objects it never held. Anything else is a
		 * linear scan over the rows — a combo box's list is a handful of words, and a cache of identities would be a
		 * second thing to keep in step with a source that may change under it. */
		if ([object isKindOfClass:[NSString class]] &&
		    [(id)_dataSource respondsToSelector:@selector(comboBoxCell:indexOfItemWithStringValue:)]) {
			NSUInteger found = [(id)_dataSource comboBoxCell:self indexOfItemWithStringValue:object];

			return (found == NSNotFound) ? -1 : (NSInteger)found;
		}
		{
			NSInteger count = [self fn_itemCount];
			NSInteger i;

			for (i = 0; i < count; i++) {
				if ([[self fn_itemObjectAtIndex:i] isEqual:object]) {
					return i;
				}
			}
		}
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

/* ---- THE DATA SOURCE, AND THE TWO WAYS ITS OWNER SAYS THE ROWS MOVED ------------------------------ */

- (void)setDataSource:(id <NSComboBoxCellDataSource>)aSource
{
	/* **NOT RETAINED, AND THAT IS THE CONNECTION'S RULE RATHER THAN AN OVERSIGHT** — see the ivar. A source that
	 * ARRIVES is measured against the selection the box already has, because the rows it is replacing may be fewer: the
	 * selection is clamped into the new count and the shown value re-read, which is the same act the two doors below
	 * perform for a source that CHANGED. A source this box cannot read is still stored: `-fn_usesDataSource` asks the
	 * required members when a row is wanted, so a source that answers neither behaves as an empty list rather than as a
	 * crash at the first question. */
	_dataSource = aSource;
	[self fn_reclampSelection];
}

- (id <NSComboBoxCellDataSource>)dataSource
{
	return _dataSource;
}

/* **THE ONE ACT BOTH ``RELOAD'' DOORS PERFORM, AND THE REASON THEY ARE TWO DOORS WITH ONE BODY.** The rows are read
 * from the source on demand, so nothing is cached to throw away; what can be STALE is the SELECTION — an index into a
 * list that may have grown, shrunk, or changed its contents under it — and the value the box is SHOWING, which is the
 * selected row's words. So both doors clamp the index into the count and re-read the string, and the difference between
 * them is what the CALLER knows: `-noteNumberOfItemsChanged` says the count moved, `-reloadData` says the contents did
 * (which for this class is the same repair, and the header says so rather than inventing a second behaviour). */
- (void)fn_reclampSelection
{
	NSInteger count = [self fn_itemCount];

	if (_selectedIndex >= count) {
		_selectedIndex = count - 1;
	}
	if (_selectedIndex < -1) {
		_selectedIndex = -1;
	}
	if (_selectedIndex >= 0) {
		id object = [self fn_itemObjectAtIndex:_selectedIndex];

		[self setStringValue:(object != nil) ? [object description] : @""];
	} else {
		[self setStringValue:@""];
	}
	if ([self controlView] != nil && [[self controlView] respondsToSelector:@selector(setNeedsDisplay:)]) {
		[[self controlView] setNeedsDisplay:YES];
	}
}

- (void)reloadData
{
	[self fn_reclampSelection];
}

- (void)noteNumberOfItemsChanged
{
	[self fn_reclampSelection];
}

/* ---- AND THE COMPLETION OF A TYPED PREFIX ---------------------------------------------------------- */

/* **WHAT `-completes` IS THE SWITCH FOR, AND WHY THE COMPARISON IS CASE-INSENSITIVE.** The answer is the first row
 * whose words BEGIN with what has been typed; a source that implements `-comboBoxCell:completedString:` speaks for its
 * own rows (it knows which one a person would mean), and otherwise the rows are scanned in order. A completion that is
 * not LONGER than the prefix is not a completion — it is the same words back — so it answers nil, which is what lets
 * the typing path leave the editor alone. An EMPTY prefix completes nothing: a box that offered its first row the
 * moment it was clicked into would be choosing for the person who wanted to type. */
- (NSString *)completedString:(NSString *)uncompletedString
{
	NSString *prefix = (uncompletedString != nil) ? uncompletedString : @"";
	NSInteger count;
	NSInteger i;

	if ([prefix length] == 0) {
		return nil;
	}
	if ([self fn_usesDataSource] &&
	    [(id)_dataSource respondsToSelector:@selector(comboBoxCell:completedString:)]) {
		NSString *fromSource = [(id)_dataSource comboBoxCell:self completedString:prefix];

		return ([fromSource length] > [prefix length]) ? fromSource : nil;
	}
	count = [self fn_itemCount];
	for (i = 0; i < count; i++) {
		NSString *words = [[self fn_itemObjectAtIndex:i] description];

		if ([words length] > [prefix length] &&
		    [words compare:prefix options:NSCaseInsensitiveSearch
			     range:NSMakeRange(0, [prefix length])] == NSOrderedSame) {
			return words;
		}
	}
	return nil;
}

/* **AND THE TYPING PATH, WHICH IS WHERE THE FLAG BECOMES BEHAVIOUR.** The editor's own change notification reaches the
 * cell because the cell is the editor's delegate (see `NSTextFieldCell`), so this is the one place a keystroke can be
 * answered. When `-completes` is on, the prefix is completed and THE APPENDED PART IS SELECTED — so the next character
 * typed replaces the offer, which is the behaviour a person expects rather than a suggestion they must delete. The
 * guard is not an optimisation: setting the editor's string announces another change, and one completion is enough. */
- (void)textDidChange:(NSNotification *)notification
{
	NSText *editor = [notification object];
	static BOOL sCompleting;	/* one completion in flight; see above */

	if (_completes && !sCompleting && [editor isKindOfClass:[NSText class]]) {
		/* **THE LENGTH IS TAKEN BEFORE THE EDIT, BECAUSE `-string` ANSWERS THE LIVE MUTABLE STRING.** MEASURED: the
		 * first version read `[editor string]` into a variable, completed it, called `-setString:` — which mutates the
		 * very object the variable points at — and then computed the suffix's length from two lengths that were now the
		 * same. The selection came out as `(6, 0)`: a caret at the end of the completed word instead of the offer
		 * selected, so the next key typed appended to it rather than replacing it. A NUMBER TAKEN BEFORE THE EDIT IS
		 * NOT AN ALIAS OF ANYTHING. */
		NSUInteger typedLength = [[editor string] length];
		NSString *completed = [self completedString:[editor string]];

		if (completed != nil) {
			sCompleting = YES;
			[editor setString:completed];
			[editor setSelectedRange:NSMakeRange(typedLength, [completed length] - typedLength)];
			sCompleting = NO;
		}
	}
	[super textDidChange:notification];
}

/* ---- THE LIST'S SHAPE ------------------------------------------------------------------------------ */

- (CGFloat)itemHeight
{
	return _itemHeight;
}

- (void)setItemHeight:(CGFloat)itemHeight
{
	_itemHeight = (itemHeight > 0.0) ? itemHeight : 0.0;
}

- (NSSize)intercellSpacing
{
	return _intercellSpacing;
}

- (void)setIntercellSpacing:(NSSize)aSize
{
	_intercellSpacing = NSMakeSize((aSize.width > 0.0) ? aSize.width : 0.0,
				      (aSize.height > 0.0) ? aSize.height : 0.0);
}

- (BOOL)isButtonBordered
{
	return _buttonBordered;
}

- (void)setButtonBordered:(BOOL)flag
{
	_buttonBordered = flag;
	if ([self controlView] != nil && [[self controlView] respondsToSelector:@selector(setNeedsDisplay:)]) {
		[[self controlView] setNeedsDisplay:YES];
	}
}

/* **THE THREE LIST DOORS THIS SESSION HAS NO MECHANISM FOR, REFUSED BY NAME.** A list taller than its space needs a
 * scroll offset and a bar, and the session this tier reuses is `NSMenu`'s: it clamps itself to the screen and draws no
 * bar. Storing the flag and drawing nothing would be a caller believing their list scrolls; a scroll door that answered
 * silence would be worse, because the row would not move and nothing would say why. */
- (BOOL)hasVerticalScroller
{
	return NO;
}

- (void)setHasVerticalScroller:(BOOL)flag
{
	if (flag) {
		fn_refuse_window("-[NSComboBoxCell setHasVerticalScroller:]",
				 "a scroller in a list window (this tier's list is the menu session, which clamps to the "
				 "screen and draws no bar)");
	}
}

- (void)scrollItemAtIndexToTop:(NSInteger)index
{
	(void)index;
	fn_refuse_window("-[NSComboBoxCell scrollItemAtIndexToTop:]",
			 "a scrollable list (this tier's list has no scroll offset — see `-setHasVerticalScroller:`)");
}

- (void)scrollItemAtIndexToVisible:(NSInteger)index
{
	(void)index;
	fn_refuse_window("-[NSComboBoxCell scrollItemAtIndexToVisible:]",
			 "a scrollable list (this tier's list has no scroll offset — see `-setHasVerticalScroller:`)");
}

/* **AND THE ONE LIST DOOR THAT IS REAL WITHOUT A SCROLLER.** See the header: it un-chooses, and only when the index
 * given is the one held — which is Apple's reading and the only one under which the door is not a synonym. */
- (void)deselectItemAtIndex:(NSInteger)index
{
	if (index != _selectedIndex || index < 0) {
		return;
	}
	_selectedIndex = -1;
	[self setStringValue:@""];
	if ([self controlView] != nil && [[self controlView] respondsToSelector:@selector(setNeedsDisplay:)]) {
		[[self controlView] setNeedsDisplay:YES];
	}
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
 * at the text rect in the ink its own `-cg_inkColor` answers, and this class now leaves both the drawing AND the ink
 * alone — so a combo box's title is drawn by the same code the field cell uses and cannot come out differently from
 * another field's. What is this class's own is the chip, and it goes on top because it is drawn over the field's right
 * end rather than beside the text. */
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

	/* **AND `-isButtonBordered:` IS THE PLATE, WHICH IS THE ONE THING THIS DRAWING HAS A FLAG FOR.** A bordered chip is
	 * the accent square with the mark knocked OUT of it — so the mark is the FIELD's white, because it is a hole rather
	 * than ink. An UNBORDERED one has no square to be a hole in, so the mark is drawn in the field's INK instead; a
	 * white triangle on a white field would be the "borderless button" that is merely invisible. */
	if (_buttonBordered) {
		[[NSColor cg_accentColor] setFill];
		[face fill];
	}
	if (c == NULL) {
		return;
	}
	CGContextSaveGState(c);
	CGContextSetShouldAntialias(c, false);
	if (_buttonBordered) {
		[[NSColor controlBackgroundColor] setFill];
	} else {
		[[self cg_inkColor] setFill];
	}
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
/* **AND THE ROWS ARE BUILT ONCE, IN A DOOR OF THEIR OWN, BECAUSE THE ROWS ARE WHAT A PROBE CAN CHECK.** The session
 * needs a display; the LIST does not — its count, its titles, which row is marked and what each row is wired to are all
 * facts about a menu that has been built and never shown, so they are built here and popped up below. It is also the
 * honest place for the mark: the row this box holds is a fact about the LIST, not about the session that shows it. */
- (NSMenu *)cg_buildListMenu
{
	NSMenu *list = [[[NSMenu alloc] initWithTitle:@"List"] autorelease];
	NSUInteger i;

	/* **AND THE LIST'S SHAPE IS SAID HERE, BECAUSE THIS IS WHERE THE LIST IS BUILT.** A menu's rows are its own height
	 * with no air between them; a combo box may say otherwise through `-setItemHeight:`/`-setIntercellSpacing:`, and the
	 * session's paint, its hit test and the panel's height all read the two numbers back from the menu. */
	[list cg_setRowHeight:_itemHeight intercellSpacing:_intercellSpacing];

	for (i = 0; i < (NSUInteger)[self fn_itemCount]; i++) {
		/* **THE TAG IS THE INDEX, WHICH IS HOW THE PICK FINDS ITS WAY BACK.** A menu item's tag is a number a caller
		 * may use for anything, and what this control has to remember about a row is WHERE IT IS — the same fact
		 * `-indexOfItem:` recovers for the pop-up, kept directly because a combo box's rows are plain objects and there
		 * is no menu to ask. */
		NSMenuItem *item = [list addItemWithTitle:[[self fn_itemObjectAtIndex:(NSInteger)i] description]
						   action:NULL keyEquivalent:@""];

		[item setTarget:self];
		[item setAction:@selector(itemSelected:)];
		[item setTag:(NSInteger)i];
		/* **AND THE ROW THIS BOX HOLDS IS TURNED ON, WHICH IS HOW THIS SESSION SAYS "YOU ARE HERE".** MEASURED, the
		 * list opened with every row looking alike, so a person had to read the whole list to find the value they
		 * could already see in the field — and the one fact a combo box's list exists to answer is which row is the
		 * current one. `AGComboListView` reads this state back as the mark, because a menu already has a way to say an
		 * item is the current choice and this does not need a second one. */
		if ((NSInteger)i == _selectedIndex) {
			[item setState:NSOnState];
		}
	}
	/* **AND THE CELL IS THE LIST'S DELEGATE, WHICH IS WHAT MAKES THE HIGHLIGHT REACH ANYBODY.** The menu's session sends
	 * `-menu:willHighlightItem:` to its delegate; a list whose delegate was nil would leave the seam unused, so every list
	 * this door builds names the cell — the object that already owns the rows, their tags and the pick. IT IS SET HERE
	 * RATHER THAN WHERE THE LIST IS POPPED UP because a caller may BUILD a list without showing it (a probe does, and so
	 * does a caller measuring one), and the delegate is a property of the list rather than of the session. */
	[list setDelegate:(id <NSMenuDelegate>)self];
	return list;
}

/* **AND THE CHIP OPENS THE LIST, WHICH IS THE ONE THING THE CHIP IS FOR.** MEASURED on the demonstration: clicking it
 * did nothing at all, because the chip's ink was drawn and the list behind it was never built — the row this control's
 * header recorded from the first slice.
 *
 * **THE SESSION IS `NSMenu`'s AND THE ROWS ARE THIS CONTROL'S.** Apple's combo box opens a borderless LIST WINDOW of
 * its own; this tier reuses the session the pop-up beside it already raises — one traversal loop, one window, one
 * dismissal, one pick — and says what a ROW looks like through `-cg_setMenuViewClass:`. MEASURED, that trade is the
 * right way round for this tier: the session is two hundred lines of window and event handling that has now been
 * written once, and what a list and a menu actually disagree about is the row.
 *
 * THE ANCHOR IS THE CONTROL'S OWN LEFT EDGE, the same place the pop-up's menu opens; `NSMenu` places its window at
 * `location.x`, so that one number IS the alignment. */
- (void)cg_attachListWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	NSMenu *list;
	NSPoint where;

	if ([self fn_itemCount] == 0) {
		fprintf(stderr, "APPKIT-REFUSE: -cg_attachListWithFrame:inView: needs a list with rows — a combo box with "
				"nothing to choose from is not a combo box\n");
		return;
	}
	list = [self cg_buildListMenu];
	[list cg_setMenuViewClass:[AGComboListView class]];
	where = [self cg_popUpAnchorForFrame:cellFrame inView:controlView];
	[list popUpMenuPositioningItem:nil atLocation:where inView:controlView];
}

/* **AND THE PICK IS THE SAME TWO THINGS THE POP-UP'S IS.** The row's index becomes the selection — which writes the
 * box's string, so the field shows what was chosen — and then the CELL's own action goes to the CELL's own target, with
 * the control as the sender, because that is what a caller who set a target is waiting for. */
- (void)menu:(NSMenu *)menu willHighlightItem:(NSMenuItem *)item
{
	/* THE SAME ROUTE THE PICK TAKES: the row's TAG is the index, and the CONTROL is what tells its delegate. A nil item
	 * — the pointer leaving the menu — is a move to no row, which the control reports as -1 so a delegate clearing its
	 * state can hear it. */
	(void)menu;
	if ([[self controlView] respondsToSelector:@selector(cg_willHighlightItemAtIndex:)]) {
		[(id)[self controlView] cg_willHighlightItemAtIndex:(item != nil) ? [item tag] : -1];
	}
}

- (void)itemSelected:(id)sender
{
	[self selectItemAtIndex:[sender tag]];
	/* **AND THE CONTROL IS TOLD, BECAUSE THE DELEGATE MESSAGE IS THE VIEW'S.** A pick lands here (the list is a menu and
	 * the row's action points at this door), but `-comboBoxSelectionDidChange:` is a delegate's question and the delegate
	 * belongs to the control. Asking the control whether it wants to hear it is the same seam `-cg_inkColor` uses one
	 * class over, and it keeps the notification's construction where the delegate is. */
	if ([[self controlView] respondsToSelector:@selector(cg_didSelectItemAtIndex:)]) {
		[(id)[self controlView] cg_didSelectItemAtIndex:[sender tag]];
	}
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
