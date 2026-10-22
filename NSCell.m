/*
 * NSCell — the root of the cell family, and the state that costs no ink.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * THE CLASS IS MOSTLY A HEADER SO FAR, AND THAT IS THE HONEST SHAPE OF ITS FIRST SLICE: the types it is declared in
 * terms of, and the four pieces of state a caller can set without anything being drawn. The rest of Apple's cell —
 * the value accessors and their type coercions, the formatter, the drawing doors — is owed and recorded, and each
 * slice that lands here is a slice a control can build on.
 *
 * THE DEFAULTS ARE APPLE'S, AND THEY ARE NOT ALL ZERO, which is the trap this class's sibling found the hard way:
 * a fresh cell is ENABLED (a control that never says otherwise works), NOT highlighted, NOT bordered and NOT
 * editable. Objective-C zeroes storage, so each of those has to be written out — and the probe asserts the STARTING
 * POSITION rather than only the transitions, which is the lesson a wrong default taught two stages ago.
 */
#import <AppKit/NSCell.h>
/* **THE INK'S HEADERS, WHICH THIS FILE DID NOT NEED WHILE EVERY DRAWING DOOR REFUSED.** The face a title is set in,
 * the colour it is drawn in, the path a border is stroked with, the string measurement, and the context the current
 * view draws through — the same five `NSMenuItemCell` imports one class over. */
#import <AppKit/NSFont.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSStringDrawing.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSImage.h>

/* **THE CELL'S OWN MEASURES, WHICH APPLE DOES NOT PUBLISH AND THIS TIER THEREFORE OWNS.** The three rect doors are
 * "slightly inset" and "a small offset" in Apple's prose and nothing more, so here is the number: a bordered cell
 * insets its drawing rect by `NS_CELL_BORDER_INSET`, and the content inside takes `NS_CELL_CONTENT_PADDING` of air.
 * ONE PLACE, so a subclass that wants different arithmetic OVERRIDES A DOOR rather than chasing a constant. BOTH
 * numbers are declared in `NSCell.h` now — each moved there when a second class needed it — and the head of the file
 * is where a macro this door measures with has to be visible. */
/* AND THE ONE IMPORT THIS FILE'S LAST DOOR NEEDED — `NSCursor`, for the cursor a text cell declares over itself. It
 * stands here rather than beside the door for the reason §A10aw measured: a header that declares its own types would
 * collide with the tree's, and the head of the file is where an import belongs. `NSView.h` only FORWARD-declares
 * `NSCursor`, so the door cannot name `+IBeamCursor` without this line. See appkit-plan.md §A10bg. */
#import <AppKit/NSCursor.h>
/* AND THE ARCHIVER, WHICH `-copy` AT THE FOOT OF THIS FILE MAKES A CELL'S COPY THROUGH. Foundation's keyed
 * archiver is the one description of a cell's state that cannot drift from the two coding methods above. */
#import <Foundation/NSKeyedArchiver.h>/* AND THE ONE IMPORT §A10br'S DOOR NEEDED — `NSErrors.h`, for the AppKit's own exception name that `-compare:` is
 * documented to raise. It names a CONSTANT rather than a type, so nothing about it collides, and it stands beside the
 * other import for the same reason: the head of the file is where an import belongs. APPLE'S `NSCell.h` DOES NOT IMPORT
 * THIS HEADER EITHER — the SDK reaches the constant through the umbrella `AppKit.h` — so the include graph is Apple's,
 * one file over from the declaration. */
#import <AppKit/NSErrors.h>

@implementation NSCell

/* ============================================================================================
 * ARCHIVING: THE DESIGN SUBSET OF A CELL, WHICH IS MOST OF IT.
 * ============================================================================================ */

/* **THE KEYS ARE PROPERTY NAMES, AND THE OMISSIONS ARE THE INTERESTING PART.** What is NOT here: `_target` (a
 * connection — see `NSNib.h`, because the target is either the file's owner or another object in the same archive and
 * both are connections rather than values), `_controlView` (borrowed: the control sets it when it adopts the cell),
 * `_highlighted` (transient: a cell is lit while a mouse is down and a design has no mouse), `_mouseInside`,
 * `_mouseDownFlags` and `_actionMask` (tracking state). Everything else is what a design file may say, so everything
 * else is encoded — including the ones whose default is not zero, which are the ones a decode would otherwise get
 * silently wrong. */
static NSString * const AGCoderCellEnabledKey = @"enabled";
static NSString * const AGCoderCellBorderedKey = @"bordered";
static NSString * const AGCoderCellBezeledKey = @"bezeled";
static NSString * const AGCoderCellEditableKey = @"editable";
static NSString * const AGCoderCellSelectableKey = @"selectable";
static NSString * const AGCoderCellScrollableKey = @"scrollable";
static NSString * const AGCoderCellContinuousKey = @"continuous";
static NSString * const AGCoderCellAllowsUndoKey = @"allowsUndo";
static NSString * const AGCoderCellAllowsEditingAttrsKey = @"allowsEditingTextAttributes";
static NSString * const AGCoderCellImportsGraphicsKey = @"importsGraphics";
static NSString * const AGCoderCellAllowsMixedStateKey = @"allowsMixedState";
static NSString * const AGCoderCellWrapsKey = @"wraps";
static NSString * const AGCoderCellTruncatesKey = @"truncatesLastVisibleLine";
static NSString * const AGCoderCellSingleLineKey = @"usesSingleLineMode";
static NSString * const AGCoderCellSendsOnEndKey = @"sendsActionOnEndEditing";
static NSString * const AGCoderCellRefusesFirstResponderKey = @"refusesFirstResponder";
static NSString * const AGCoderCellShowsFirstResponderKey = @"showsFirstResponder";
static NSString * const AGCoderCellWantsMarkedTextKey = @"wantsNotificationForMarkedText";
static NSString * const AGCoderCellOpaqueKey = @"opaque";
static NSString * const AGCoderCellControlSizeKey = @"controlSize";
static NSString * const AGCoderCellControlTintKey = @"controlTint";
static NSString * const AGCoderCellBackgroundStyleKey = @"backgroundStyle";
static NSString * const AGCoderCellTypeKey = @"cellType";
static NSString * const AGCoderCellValueKey = @"objectValue";
static NSString * const AGCoderCellTitleKey = @"title";
static NSString * const AGCoderCellStateKey = @"state";
static NSString * const AGCoderCellTagKey = @"tag";
static NSString * const AGCoderCellKeyEquivalentKey = @"keyEquivalent";
static NSString * const AGCoderCellMnemonicKey = @"mnemonicLocation";
static NSString * const AGCoderCellFloatingFormatKey = @"floatingPointFormat";
static NSString * const AGCoderCellMenuKey = @"menu";
static NSString * const AGCoderCellImageKey = @"image";
static NSString * const AGCoderCellFormatterKey = @"formatter";
static NSString * const AGCoderCellFontKey = @"font";
static NSString * const AGCoderCellAlignmentKey = @"alignment";
static NSString * const AGCoderCellLineBreakKey = @"lineBreakMode";
static NSString * const AGCoderCellBaseWritingKey = @"baseWritingDirection";
static NSString * const AGCoderCellFocusRingKey = @"focusRingType";
static NSString * const AGCoderCellLayoutDirectionKey = @"userInterfaceLayoutDirection";
static NSString * const AGCoderCellAttributeKey = @"cellAttribute";
static NSString * const AGCoderCellActionKey = @"action";

- (void)encodeWithCoder:(NSCoder *)aCoder
{
	/* A CELL'S SUPERCLASS IS `NSObject`, which is not archivable, so this is the bottom of the chain for a cell —
	 * unlike a view's, which chains into `NSResponder`. */
	[aCoder encodeBool:_enabled forKey:AGCoderCellEnabledKey];
	[aCoder encodeBool:_bordered forKey:AGCoderCellBorderedKey];
	[aCoder encodeBool:_bezeled forKey:AGCoderCellBezeledKey];
	[aCoder encodeBool:_editable forKey:AGCoderCellEditableKey];
	[aCoder encodeBool:_selectable forKey:AGCoderCellSelectableKey];
	[aCoder encodeBool:_scrollable forKey:AGCoderCellScrollableKey];
	[aCoder encodeBool:_continuous forKey:AGCoderCellContinuousKey];
	[aCoder encodeBool:_allowsUndo forKey:AGCoderCellAllowsUndoKey];
	[aCoder encodeBool:_allowsEditingTextAttributes forKey:AGCoderCellAllowsEditingAttrsKey];
	[aCoder encodeBool:_importsGraphics forKey:AGCoderCellImportsGraphicsKey];
	[aCoder encodeBool:_allowsMixedState forKey:AGCoderCellAllowsMixedStateKey];
	[aCoder encodeBool:_wraps forKey:AGCoderCellWrapsKey];
	[aCoder encodeBool:_truncatesLastVisibleLine forKey:AGCoderCellTruncatesKey];
	[aCoder encodeBool:_usesSingleLineMode forKey:AGCoderCellSingleLineKey];
	[aCoder encodeBool:_sendsActionOnEndEditing forKey:AGCoderCellSendsOnEndKey];
	[aCoder encodeBool:_refusesFirstResponder forKey:AGCoderCellRefusesFirstResponderKey];
	[aCoder encodeBool:_showsFirstResponder forKey:AGCoderCellShowsFirstResponderKey];
	[aCoder encodeBool:_wantsNotificationForMarkedText forKey:AGCoderCellWantsMarkedTextKey];
	[aCoder encodeBool:_opaque forKey:AGCoderCellOpaqueKey];
	[aCoder encodeInteger:(NSInteger)_controlSize forKey:AGCoderCellControlSizeKey];
	[aCoder encodeInteger:(NSInteger)_controlTint forKey:AGCoderCellControlTintKey];
	[aCoder encodeInteger:(NSInteger)_backgroundStyle forKey:AGCoderCellBackgroundStyleKey];
	[aCoder encodeInteger:(NSInteger)_type forKey:AGCoderCellTypeKey];
	[aCoder encodeObject:_objectValue forKey:AGCoderCellValueKey];
	[aCoder encodeObject:_title forKey:AGCoderCellTitleKey];
	[aCoder encodeInteger:_state forKey:AGCoderCellStateKey];
	[aCoder encodeInteger:_tag forKey:AGCoderCellTagKey];
	[aCoder encodeObject:_keyEquivalent forKey:AGCoderCellKeyEquivalentKey];
	[aCoder encodeInteger:(NSInteger)_mnemonicLocation forKey:AGCoderCellMnemonicKey];
	if (_cgFloatingFormat) {
		[aCoder encodeBool:_cgFloatingAutoRange forKey:@"floatingAutoRange"];
		[aCoder encodeInteger:_cgFloatingLeft forKey:@"floatingLeft"];
		[aCoder encodeInteger:_cgFloatingRight forKey:@"floatingRight"];
	}
	[aCoder encodeObject:_menu forKey:AGCoderCellMenuKey];
	[aCoder encodeObject:_image forKey:AGCoderCellImageKey];
	[aCoder encodeObject:_formatter forKey:AGCoderCellFormatterKey];
	[aCoder encodeObject:_font forKey:AGCoderCellFontKey];
	[aCoder encodeInteger:(NSInteger)_alignment forKey:AGCoderCellAlignmentKey];
	[aCoder encodeInteger:(NSInteger)_lineBreakMode forKey:AGCoderCellLineBreakKey];
	[aCoder encodeInteger:(NSInteger)_baseWritingDirection forKey:AGCoderCellBaseWritingKey];
	[aCoder encodeInteger:(NSInteger)_focusRingType forKey:AGCoderCellFocusRingKey];
	[aCoder encodeInteger:(NSInteger)_userInterfaceLayoutDirection forKey:AGCoderCellLayoutDirectionKey];
	[aCoder encodeInteger:(NSInteger)_cellAttribute forKey:AGCoderCellAttributeKey];
	/* **THE ACTION IS AN OBJECT'S ABSENCE RATHER THAN AN OBJECT, so it is archived by NAME.** A `SEL` is not
	 * archivable — `-encodeObject:` on one would box a pointer — and `NSStringFromSelector` is the spelling both ends can
	 * agree on. A nil action is a nil string and comes back nil. */
	[aCoder encodeObject:(_action != NULL) ? NSStringFromSelector(_action) : nil forKey:AGCoderCellActionKey];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	/* **THE THREE DEFAULTS THAT ARE NOT ZERO, REPEATED FROM `-init` BECAUSE A DECODE DOES NOT RUN IT.** A decoded cell
	 * and a built cell must answer the same questions the same way, and these three are the ones storage's zeroing gets
	 * wrong: enabled, the mnemonic index and the two layout enums. */
	_enabled = YES;
	_mnemonicLocation = NSNotFound;
	_alignment = NSNaturalTextAlignment;
	_baseWritingDirection = NSWritingDirectionNatural;

	if ([aDecoder containsValueForKey:AGCoderCellEnabledKey]) {
		_enabled = [aDecoder decodeBoolForKey:AGCoderCellEnabledKey];
	}
	if ([aDecoder containsValueForKey:AGCoderCellBorderedKey]) {
		_bordered = [aDecoder decodeBoolForKey:AGCoderCellBorderedKey];
	}
	if ([aDecoder containsValueForKey:AGCoderCellBezeledKey]) {
		_bezeled = [aDecoder decodeBoolForKey:AGCoderCellBezeledKey];
	}
	if ([aDecoder containsValueForKey:AGCoderCellEditableKey]) {
		_editable = [aDecoder decodeBoolForKey:AGCoderCellEditableKey];
	}
	if ([aDecoder containsValueForKey:AGCoderCellSelectableKey]) {
		_selectable = [aDecoder decodeBoolForKey:AGCoderCellSelectableKey];
	}
	if ([aDecoder containsValueForKey:AGCoderCellScrollableKey]) {
		_scrollable = [aDecoder decodeBoolForKey:AGCoderCellScrollableKey];
	}
	if ([aDecoder containsValueForKey:AGCoderCellContinuousKey]) {
		_continuous = [aDecoder decodeBoolForKey:AGCoderCellContinuousKey];
	}
	if ([aDecoder containsValueForKey:AGCoderCellAllowsUndoKey]) {
		_allowsUndo = [aDecoder decodeBoolForKey:AGCoderCellAllowsUndoKey];
	}
	if ([aDecoder containsValueForKey:AGCoderCellAllowsEditingAttrsKey]) {
		_allowsEditingTextAttributes = [aDecoder decodeBoolForKey:AGCoderCellAllowsEditingAttrsKey];
	}
	if ([aDecoder containsValueForKey:AGCoderCellImportsGraphicsKey]) {
		_importsGraphics = [aDecoder decodeBoolForKey:AGCoderCellImportsGraphicsKey];
	}
	if ([aDecoder containsValueForKey:AGCoderCellAllowsMixedStateKey]) {
		_allowsMixedState = [aDecoder decodeBoolForKey:AGCoderCellAllowsMixedStateKey];
	}
	if ([aDecoder containsValueForKey:AGCoderCellWrapsKey]) {
		_wraps = [aDecoder decodeBoolForKey:AGCoderCellWrapsKey];
	}
	if ([aDecoder containsValueForKey:AGCoderCellTruncatesKey]) {
		_truncatesLastVisibleLine = [aDecoder decodeBoolForKey:AGCoderCellTruncatesKey];
	}
	if ([aDecoder containsValueForKey:AGCoderCellSingleLineKey]) {
		_usesSingleLineMode = [aDecoder decodeBoolForKey:AGCoderCellSingleLineKey];
	}
	if ([aDecoder containsValueForKey:AGCoderCellSendsOnEndKey]) {
		_sendsActionOnEndEditing = [aDecoder decodeBoolForKey:AGCoderCellSendsOnEndKey];
	}
	if ([aDecoder containsValueForKey:AGCoderCellRefusesFirstResponderKey]) {
		_refusesFirstResponder = [aDecoder decodeBoolForKey:AGCoderCellRefusesFirstResponderKey];
	}
	if ([aDecoder containsValueForKey:AGCoderCellShowsFirstResponderKey]) {
		_showsFirstResponder = [aDecoder decodeBoolForKey:AGCoderCellShowsFirstResponderKey];
	}
	if ([aDecoder containsValueForKey:AGCoderCellWantsMarkedTextKey]) {
		_wantsNotificationForMarkedText = [aDecoder decodeBoolForKey:AGCoderCellWantsMarkedTextKey];
	}
	if ([aDecoder containsValueForKey:AGCoderCellOpaqueKey]) {
		_opaque = [aDecoder decodeBoolForKey:AGCoderCellOpaqueKey];
	}
	if ([aDecoder containsValueForKey:AGCoderCellControlSizeKey]) {
		_controlSize = (NSControlSize)[aDecoder decodeIntegerForKey:AGCoderCellControlSizeKey];
	}
	if ([aDecoder containsValueForKey:AGCoderCellControlTintKey]) {
		_controlTint = (NSControlTint)[aDecoder decodeIntegerForKey:AGCoderCellControlTintKey];
	}
	if ([aDecoder containsValueForKey:AGCoderCellBackgroundStyleKey]) {
		_backgroundStyle = (NSBackgroundStyle)[aDecoder decodeIntegerForKey:AGCoderCellBackgroundStyleKey];
	}
	if ([aDecoder containsValueForKey:AGCoderCellTypeKey]) {
		_type = (NSCellType)[aDecoder decodeIntegerForKey:AGCoderCellTypeKey];
	}
	if ([aDecoder containsValueForKey:AGCoderCellAttributeKey]) {
		_cellAttribute = (unsigned long)[aDecoder decodeIntegerForKey:AGCoderCellAttributeKey];
	}
	if ([aDecoder containsValueForKey:AGCoderCellValueKey]) {
		_objectValue = [[aDecoder decodeObjectForKey:AGCoderCellValueKey] retain];
	}
	if ([aDecoder containsValueForKey:AGCoderCellTitleKey]) {
		_title = [[aDecoder decodeObjectForKey:AGCoderCellTitleKey] copy];
	}
	if ([aDecoder containsValueForKey:AGCoderCellStateKey]) {
		_state = [aDecoder decodeIntegerForKey:AGCoderCellStateKey];
	}
	if ([aDecoder containsValueForKey:AGCoderCellTagKey]) {
		_tag = [aDecoder decodeIntegerForKey:AGCoderCellTagKey];
	}
	if ([aDecoder containsValueForKey:AGCoderCellKeyEquivalentKey]) {
		_keyEquivalent = [[aDecoder decodeObjectForKey:AGCoderCellKeyEquivalentKey] copy];
	}
	if ([aDecoder containsValueForKey:AGCoderCellMnemonicKey]) {
		_mnemonicLocation = (NSUInteger)[aDecoder decodeIntegerForKey:AGCoderCellMnemonicKey];
	}
	if ([aDecoder containsValueForKey:AGCoderCellMenuKey]) {
		_menu = [[aDecoder decodeObjectForKey:AGCoderCellMenuKey] retain];
	}
	if ([aDecoder containsValueForKey:AGCoderCellImageKey]) {
		_image = [[aDecoder decodeObjectForKey:AGCoderCellImageKey] retain];
	}
	if ([aDecoder containsValueForKey:AGCoderCellFormatterKey]) {
		_formatter = [[aDecoder decodeObjectForKey:AGCoderCellFormatterKey] retain];
	}
	if ([aDecoder containsValueForKey:AGCoderCellFontKey]) {
		_font = [[aDecoder decodeObjectForKey:AGCoderCellFontKey] retain];
	}
	if ([aDecoder containsValueForKey:AGCoderCellAlignmentKey]) {
		_alignment = (NSTextAlignment)[aDecoder decodeIntegerForKey:AGCoderCellAlignmentKey];
	}
	if ([aDecoder containsValueForKey:AGCoderCellLineBreakKey]) {
		_lineBreakMode = (NSLineBreakMode)[aDecoder decodeIntegerForKey:AGCoderCellLineBreakKey];
	}
	if ([aDecoder containsValueForKey:AGCoderCellBaseWritingKey]) {
		_baseWritingDirection =
			(NSWritingDirection)[aDecoder decodeIntegerForKey:AGCoderCellBaseWritingKey];
	}
	if ([aDecoder containsValueForKey:AGCoderCellFocusRingKey]) {
		_focusRingType = (NSFocusRingType)[aDecoder decodeIntegerForKey:AGCoderCellFocusRingKey];
	}
	if ([aDecoder containsValueForKey:AGCoderCellLayoutDirectionKey]) {
		_userInterfaceLayoutDirection =
			(NSUserInterfaceLayoutDirection)[aDecoder decodeIntegerForKey:AGCoderCellLayoutDirectionKey];
	}
	if ([aDecoder containsValueForKey:AGCoderCellActionKey]) {
		NSString *name = [aDecoder decodeObjectForKey:AGCoderCellActionKey];

		if ([name isKindOfClass:[NSString class]]) {
			_action = NSSelectorFromString(name);
		}
	}
	return self;
}

+ (BOOL)supportsSecureCoding
{
	return YES;
}

/* ============================================================================================
 * ARCHIVING'S OTHER FACE: THE COPY.
 * ============================================================================================ */
/* **A CELL IS <NSCopying> IN APPLE'S HEADER AND THIS TREE DECLARED THE CONFORMANCE AND NO METHOD**, which was
 * MEASURED rather than suspected: `-copy` on a cell raised `doesNotRecognizeSelector:` where a copy was meant, and
 * `NSMatrix -setPrototype:` is the first caller that needs one — Apple's whole contract for a prototype is "each
 * position gets a copy of it". The archiving pair above is already a complete description of a cell's state, so the
 * copy is that description taken one step further: encode, decode, and the result is a cell of the SAME class with
 * the same values and none of the same storage. It is slower than a hand-written clone and it cannot drift from the
 * coding — which is the property that matters, because a hand-written copy would be a second list of the fields and
 * the two would disagree the first time one of them grew.
 *
 * THE RETURN IS OWNED (+1), as `-copy` must be; `+unarchiveObjectWithData:` answers an autoreleased object, so the
 * retain below is the difference. A subclass that declares extra state gets a correct copy for free as long as that
 * state is coded, which is the same requirement its archive already has.
 *
 * **THE DOOR IS `-copy` RATHER THAN COCOA'S `-copyWithZone:`** because THIS FOUNDATION REMOVED EVERY `NSZone`-TAKING
 * METHOD: `NSCopying` here declares `-copy` and the override point is the entry point (see `libagora-base/NSObject.h`).
 * A class written against Apple's spelling would not conform on this stack, which is the cost that header records. */
- (id)copy
{
	NSData *data;
	id copy;

	data = [NSKeyedArchiver archivedDataWithRootObject:self];
	if (data == nil) {
		return nil;
	}
	copy = [NSKeyedUnarchiver unarchiveObjectWithData:data];
	return [copy retain];
}

- (instancetype)init
{
	if ((self = [super init]) != nil) {
		/* A fresh cell is usable: enabled, unlit, plain and read-only. */
		_enabled = YES;
		_highlighted = NO;
		_bordered = NO;
		_editable = NO;
		/* **AND THE ONE DEFAULT HERE THAT IS NOT A ZERO, BECAUSE ZERO IS A VALID MNEMONIC**: `-mnemonicLocation`
		 * answers an index into the title and index 0 is the title's first character, so "this cell names no
		 * mnemonic" has to be spelled `NSNotFound` rather than left to Objective-C's zeroing. */
		_mnemonicLocation = NSNotFound;
		/* **AND TWO OF THE LAYOUT DEFAULTS ARE NOT ZERO EITHER — the same trap one unit later, and the reason they are
		 * written out rather than left to the storage.** Apple's own class reference states both: `-alignment` "default
		 * value is `NSNaturalTextAlignment`" and `-baseWritingDirection` "default value is `NSWritingDirectionNatural`",
		 * which are 4 and `-1` — neither is the first member of its type. A cell left at zero would claim to be
		 * LEFT-aligned in a right-to-left script, silently, and would tell the text system its writing direction was
		 * certain when the era says the Unicode Bidi Algorithm decides. THE OTHER THREE LAYOUT VALUES ARE THEIR ZERO —
		 * the line-break mode, the focus ring and the user interface layout direction all start at the first member of
		 * their type — so the storage's zeroing IS the documented answer for them, and the difference between the two
		 * groups is the whole reason both are named here. */
		_alignment = NSNaturalTextAlignment;
		_baseWritingDirection = NSWritingDirectionNatural;
	}
	return self;
}

- (void)dealloc
{
	/* THE FIVE OWNED THINGS IN THIS CLASS, and the reason every setter of theirs retains: a cell that kept a value
	 * without owning it would hand back a dangling object the moment the caller let go, and one that owned it without
	 * releasing would leak it. Both halves live here and in the setters, one apiece — the object value, the title, the
	 * key equivalent, the image and the formatter, in the order they arrived. */
	[_objectValue release];
	[_title release];
	[_keyEquivalent release];
	[_image release];
	[_formatter release];
	[_font release];
		[_representedObject release];
	[super dealloc];
}

/* ---- AND THE TWO DESIGNATED INITIALISERS, WHOSE WHOLE POINT IS THE KIND OF CELL THEY MAKE --------------------- */

/* **A CELL IS BORN AS ONE OF TWO KINDS AND THESE ARE THE DOORS THAT DECIDE IT**, which is why Apple calls them
 * designated and why `-init` — the door that sets the four common defaults — is not one of them. BOTH BUILD ON
 * `-init` THROUGH `self`, so a subclass's own `-init` still runs underneath: that is how `NSButtonCell` and the cells
 * above it keep their state while a caller uses Apple's designated door.
 *
 * AND THE TITLE'S DEFAULT IS THE DOCUMENTED ONE RATHER THAN A GUESS: the OpenStep Programming Reference says the
 * title "is set to aString, or \"Cell\" if aString is NULL", which is a published value and therefore the one this
 * door uses — NOT the empty string this tree's menu item answers for a nil title in the mnemonic door, which is a
 * different door with a different documented value.
 *
 * AND NOTHING ELSE IS TOUCHED: neither door makes the cell editable or selectable. The OpenStep spec states both
 * default to NO and that `-setEditable:` is what implies selectability, and a cell born editable would be a
 * behaviour no caller asked for — the same rule the four starting flags follow. */
- (instancetype)initTextCell:(NSString *)aString
{
	if ((self = [self init]) != nil) {
		_type = NSTextCellType;
		[self setTitle:(aString != nil ? aString : @"Cell")];
		/* **AND THE STRING VALUE TOO, WHICH IS APPLE'S OTHER HALF OF THIS INITIALISER.** This class keeps a TITLE (what a
		 * button or a field DRAWS) and an OBJECT VALUE (what `-stringValue` answers), and `-initTextCell:` used to set
		 * only the first — so a cell made with a string answered `-stringValue` of nil. MEASURED while writing the
		 * field-editor session: the editor was handed an empty string for a cell created with one. A text cell has one
		 * string, and both doors are views of it. */
		[self setStringValue:(aString != nil ? aString : @"Cell")];
	}
	return self;
}

- (instancetype)initImageCell:(NSImage *)image
{
	if ((self = [self init]) != nil) {
		_type = NSImageCellType;
		[self setImage:image];
		/* APPKIT-REFUSE: OpenStep's rule for a NIL image is the DEFAULT ICON `NSsquare16`, fetched by name — and a
		 * named image needs the image catalog this tier has no door for (`+imageNamed:` is not one here). Apple's
		 * modern sentence is the one obeyed instead: a nil image means NO image, which is what `-setImage:` stores.
		 * THE REFUSED HALF IS THE ICON, not the door: a cell made with an image gets it, exactly as documented. */
	}
	return self;
}

/* ---- AND THE IMAGE, THE STATE THE SECOND KIND IS FOR --------------------------------------------------------- */

- (NSImage *)image
{
	return _image;
}

- (void)setImage:(NSImage *)anImage
{
	if (anImage != _image) {
		[anImage retain];
		[_image release];
		_image = anImage;
	}
	/* **AND THIS DOOR DOES NOT CHANGE THE CELL'S KIND — WHICH IS A MEASURED ASYMMETRY NOW RATHER THAN AN OWED GAP**:
	 * §A10bi recorded the kind-changing side effects OpenStep attributes to assigning a value as belonging with the
	 * value doors' slice, and §A10bj is that slice. What it found is that exactly ONE of them converts:
	 * `-setStringValue:` turns a non-text cell into a text cell, and the four NUMERIC setters do nothing at all on a
	 * cell that is not text. `-setImage:` is the third shape — it stores the image and leaves the kind alone, which is
	 * the job `-initImageCell:` exists for. */
}

/* ---- THE FOUR PIECES OF STATE -------------------------------------------------------------------- */

- (BOOL)isEnabled
{
	return _enabled;
}

- (void)setEnabled:(BOOL)flag
{
	_enabled = flag;
}

- (BOOL)isHighlighted
{
	return _highlighted;
}

- (void)setHighlighted:(BOOL)flag
{
	_highlighted = flag;
}

/* ---- AND WHERE THE POINTER IS, WHICH IS THE TIER'S PAIR RATHER THAN APPLE'S ------------------------ */

- (BOOL)cg_mouseIsInside
{
	return _mouseInside;
}

- (void)cg_setMouseInside:(BOOL)flag
{
	if (flag == _mouseInside) {
		return;
	}
	_mouseInside = flag;
	/* **AND THE FACE IS REDRAWN, WHICH IS THE ONLY THING THIS DOOR OWES ANYONE.** A prelight IS the face — the whole
	 * button changes colour — so the whole control is invalidated rather than one rect, which is the same redisplay
	 * `-highlight:withFrame:inView:` performs one door over. THE EARLY RETURN ABOVE IS NOT AN OPTIMISATION: the window
	 * synthesises an enter and an exit from the pointer's motion, and a redraw per motion event with the pointer
	 * merely NEAR a control would repaint the window for nothing. */
	if (_controlView != nil && [_controlView respondsToSelector:@selector(setNeedsDisplay:)]) {
		[_controlView setNeedsDisplay:YES];
	}
}

- (BOOL)cg_trackingShouldRepeat
{
	/* NOTHING TO REPEAT: the default, and every cell but a stepping one. A cell that DOES step overrides this and
	 * watches its own clock — see `NSScrollerCell`, which is the one control in this tier whose press repeats. */
	return NO;
}

- (BOOL)isBordered
{
	return _bordered;
}

- (void)setBordered:(BOOL)flag
{
	_bordered = flag;
}

- (BOOL)isEditable
{
	return _editable;
}

- (void)setEditable:(BOOL)flag
{
	_editable = flag;
}

/* ---- THE STATE THIS SLICE ADDS ------------------------------------------------------------------ */

/* THE SIX FLAGS AND THREE ENUMS, all plain storage and all of a piece. NONE OF THEM NEEDS AN INITIALISER, and that
 * is worth saying because the last slice's flags did: the zero member of each of these enums IS ITS DEFAULT —
 * `NSRegularControlSize`, `NSDefaultControlTint`, `NSBackgroundStyleLight` — so Objective-C's zeroing lands on the
 * right answer, which is why the artefact orders the members the way it does. */
- (BOOL)isBezeled
{
	return _bezeled;
}

- (void)setBezeled:(BOOL)flag
{
	_bezeled = flag;
}

- (BOOL)isContinuous
{
	return _continuous;
}

- (void)setContinuous:(BOOL)flag
{
	_continuous = flag;
}

- (BOOL)allowsUndo
{
	return _allowsUndo;
}

- (void)setAllowsUndo:(BOOL)flag
{
	_allowsUndo = flag;
}

- (BOOL)allowsEditingTextAttributes
{
	return _allowsEditingTextAttributes;
}

- (void)setAllowsEditingTextAttributes:(BOOL)flag
{
	_allowsEditingTextAttributes = flag;
}

- (BOOL)importsGraphics
{
	return _importsGraphics;
}

- (void)setImportsGraphics:(BOOL)flag
{
	_importsGraphics = flag;
}

- (BOOL)allowsMixedState
{
	return _allowsMixedState;
}

- (void)setAllowsMixedState:(BOOL)flag
{
	_allowsMixedState = flag;
}

- (BOOL)acceptsFirstResponder
{
	/* NO, AND THE ANSWER IS THE WHOLE DOOR: a cell that wants the first click says so by overriding this, which is
	 * why there is no setter and why the base answer is the quiet one. */
	return NO;
}

- (NSControlSize)controlSize
{
	return _controlSize;
}

- (void)setControlSize:(NSControlSize)size
{
	_controlSize = size;
}

- (NSControlTint)controlTint
{
	return _controlTint;
}

- (void)setControlTint:(NSControlTint)tint
{
	_controlTint = tint;
}

- (NSBackgroundStyle)backgroundStyle
{
	return _backgroundStyle;
}

- (void)setBackgroundStyle:(NSBackgroundStyle)style
{
	_backgroundStyle = style;
}

/* ---- AND THE OBJECT, WITH ITS FIVE COERCIONS ------------------------------------------------------ */

- (id)objectValue
{
	return _objectValue;
}

- (void)setObjectValue:(id)value
{
	if (value != _objectValue) {
		id held = [value retain];

		[_objectValue release];
		_objectValue = held;
	}
}

- (BOOL)hasValidObjectValue
{
	/* THE QUESTION IS "IS THERE A VALUE", not "is it the right type": a cell holding a string where a number was
	 * expected still has a value, and Apple's answer says so. */
	return _objectValue != nil;
}

- (NSString *)stringValue
{
	if (_objectValue == nil) {
		return nil;
	}
	/* **AND A VALUE THAT IS ALREADY ATTRIBUTED ANSWERS ITS TEXT — THE BRANCH §A10bs ADDED, AND THE ONE APPLE'S OWN
	 * SENTENCE ASKS FOR**: "if the cell's object is not an NSString object OR CANNOT BE CONVERTED TO ONE, this property
	 * contains an empty string", and an `NSAttributedString` CAN be converted — it has `-string`. Without this branch the
	 * value below would be answered by `-description`, which is neither a conversion nor Apple's answer. IT COMES FIRST
	 * because it is the more specific question: a cell holding an attributed string WITH a formatter set would be asked
	 * about its text twice over, and the KIND is the fact the cell actually holds. */
	if ([_objectValue isKindOfClass:[NSAttributedString class]]) {
		return [(NSAttributedString *)_objectValue string];
	}
	/* **AND WITH A FORMATTER SET THE ANSWER IS THE FORMATTER'S RATHER THAN THE OBJECT'S `-description`** — the relation
	 * the era's own text states ("the cell invokes this object's `-stringForObjectValue:` method to obtain the
	 * correctly formatted string"). THE NO-FORMATTER BRANCH IS §A10bj'S SHIPPED ANSWER UNTOUCHED, which is why the nil
	 * test is the first thing here and not a rewrite: this unit ADDS a branch to a door that was already measured. */
	if (_formatter != nil) {
		NSString *formatted = [_formatter stringForObjectValue:_objectValue];

		/* AND A FORMATTER THAT DECLINES THE VALUE IS APPLE'S OTHER DOCUMENTED CASE: "if the cell's object is not an
		 * NSString object or cannot be converted to one, this property contains an empty string". AN EMPTY STRING
		 * AND NOT NIL — the nil above is for a cell with NO VALUE, which is a different question with a different
		 * documented answer, and conflating them would make "declined" read as "empty cell". */
		return (formatted != nil ? formatted : @"");
	}
	/* **AND THE 10.0 NUMBER FORMAT, WHEN ONE WAS SET AND NO FORMATTER SUPERSEDES IT.** Apple's precedence is the
	 * formatter's: this branch is reached only when `_formatter` is nil, which is why it sits after that test. A value
	 * that is not a number is untouched — the format is about numbers. */
	if (_cgFloatingFormat && [_objectValue isKindOfClass:[NSNumber class]]) {
		return fn_floating_string([(NSNumber *)_objectValue doubleValue], _cgFloatingAutoRange,
					  _cgFloatingLeft, _cgFloatingRight);
	}
	return [_objectValue description];
}

/* ---- AND THE FORMATTER, DECLARED BESIDE THE ONE ANSWER IT CHANGES -------------------------------------------- */

/* **THE ERA DECLARES THIS PAIR IN THE SAME CLUSTER AS THE VALUE DOORS**, and it stands here for the same reason: a
 * formatter is the object a cell's value is READ THROUGH, so its two doors belong beside `-stringValue` rather than in
 * a section of their own.
 *
 * AND THE PAIR DOES THREE DOCUMENTED THINGS, WHICH IS WHY NEITHER HALF IS A PLAIN ACCESSOR: RETAIN-NOT-COPY (Apple's
 * Data Formatting Guide, quoted at the ivar); `-stringValue` answers through it (the door above); and ASSIGNING ONE
 * RE-INTERPRETS THE VALUE ALREADY IN THE CELL ("the formatter attempts to interpret the cell's current value. If it
 * cannot do so, the formatter converts the current value to a string object").
 *
 * THAT LAST SENTENCE DOES NOT SAY WHAT THE FORMATTER IS HANDED, SO THE READING IS STATED RATHER THAN ASSUMED, and it
 * is the two steps the sentence names: ask the new formatter to INTERPRET the current value's TEXT
 * (`-getObjectValue:forString:errorDescription:`, the protocol's string-to-object half) and, when it answers nothing,
 * leave that text as the value — "the current value converted to a string object". The clause is guarded on the cell
 * HAVING a value, because otherwise attaching a formatter would mint one out of nothing. The probe pins both halves
 * and the guard, with a real two-way formatter (the base class refuses, so there is no other way to observe them). */
- (NSFormatter *)formatter
{
	return _formatter;
}

- (void)setFormatter:(NSFormatter *)newFormatter
{
	if (newFormatter != _formatter) {
		NSFormatter *held = [newFormatter retain];

		[_formatter release];
		_formatter = held;
		/* AND THE VALUE THAT WAS ALREADY HERE IS RE-INTERPRETED, in the order the sentence names it: interpret the
		 * current text first, and only fall back to that text when the interpretation does not answer. */
		if (_formatter != nil && _objectValue != nil) {
			NSString *text = [_objectValue isKindOfClass:[NSString class]]
					     ? (NSString *)_objectValue
					     : [_objectValue description];
			id interpreted = nil;

			if ([_formatter getObjectValue:&interpreted forString:text errorDescription:NULL] && interpreted != nil) {
				[self setObjectValue:interpreted];	/* the formatter INTERPRETED what was there */
			} else {
				[self setObjectValue:text];		/* it could not, so the value IS that text */
			}
		}
	}
}

/* THE FOUR NUMERIC COERCIONS ARE ONE SHAPE, AND THE GUARD IN EACH IS NOT DECORATION: this project's runtime RAISES
 * on a selector an object does not implement, so an arbitrary object asked for `-intValue` would ABORT the cell
 * rather than answer — and ZERO IS APPLE'S ANSWER for a value that cannot be coerced, which is what the guard
 * returns. So the guard is the behaviour, not a safety net. */
- (int)intValue
{
	if (_objectValue == nil || ![_objectValue respondsToSelector:@selector(intValue)]) {
		return 0;
	}
	return [_objectValue intValue];
}

- (float)floatValue
{
	if (_objectValue == nil || ![_objectValue respondsToSelector:@selector(floatValue)]) {
		return 0.0f;
	}
	return [_objectValue floatValue];
}

- (double)doubleValue
{
	if (_objectValue == nil || ![_objectValue respondsToSelector:@selector(doubleValue)]) {
		return 0.0;
	}
	return [_objectValue doubleValue];
}

- (NSInteger)integerValue
{
	if (_objectValue == nil || ![_objectValue respondsToSelector:@selector(integerValue)]) {
		return 0;
	}
	return [_objectValue integerValue];
}

/* ---- AND THE FIVE TYPED SETTERS, WHICH WRITE THAT ONE VALUE AND CARRY A TWO-PART TYPE RULE -------------------- */

/* **THE STRING DOOR CONVERTS AND THE FOUR NUMERIC DOORS DO NOTHING**, which is the asymmetry the era documents and
 * the reason these five are not one shape written five times: `-setStringValue:` says "if the receiver isn't a text
 * cell, this method converts it to that type", while `-setIntValue:`, `-setFloatValue:`, `-setDoubleValue:` and
 * `-setIntegerValue:` each say they do NOTHING if the receiver isn't a text cell. SO A CELL'S KIND DECIDES WHICH
 * SETTERS ARE EVEN DOORS, and a caller that assigns a number to a cell that is not text is not making a mistake the
 * library reports — it is sending a message the era defines as doing nothing. The probe asserts both halves.
 *
 * AND THE VALUE IS STORED AS THE OBJECT RATHER THAN AS ITS TEXT, which is this class's shape (§A10az: one value, five
 * derived answers). It is also what keeps `-doubleValue` EXACT: a round trip through a string would lose the digits
 * `%g` does not print, and the probe measures a double that would not survive it. */
- (void)setStringValue:(NSString *)aString
{
	NSString *copy = [aString copy];	/* the era says "a copy of aString", and a caller keeps its own string */

	[_objectValue release];
	_objectValue = copy;
	if (_type != NSTextCellType) {
		/* **AND ASSIGNING TEXT CONVERTS THE CELL, WHICH IS THE HALF THAT MAKES THIS DOOR THE ODD ONE.** The kind is
		 * changed rather than the message refused, because that is what the sentence says — and note what is NOT
		 * touched: the IMAGE. Apple's own text adds that an image cell's `NSImage` "is not freed" by this conversion,
		 * so this door leaves `_image` standing, and the probe checks that the cell still answers it. */
		_type = NSTextCellType;
		/* **AND THE FONT, WHICH THIS DOOR USED TO REFUSE ON A GROUND THAT HAS SINCE EXPIRED.** The same sentence
		 * gives the conversion "the user's system font at 12.0 points"; the refusal said the missing thing was
		 * AppKit's font CLASS — and `NSFont` EXISTS in this tree, and `-setFont:` is this class's own door (the
		 * control slice added it). So the third thing the sentence asks for is DONE rather than named, and the
		 * retraction §A10bt recorded is acted on instead of quoted. */
		[self setFont:[NSFont systemFontOfSize:12.0]];
	}
}

- (void)setIntValue:(int)anInt
{
	if (_type != NSTextCellType) {
		return;				/* the documented no-op: a numeric setter needs a text cell */
	}
	[self setObjectValue:[NSNumber numberWithInt:anInt]];
}

- (void)setIntegerValue:(NSInteger)anInteger
{
	if (_type != NSTextCellType) {
		return;
	}
	[self setObjectValue:[NSNumber numberWithInteger:anInteger]];
}

- (void)setFloatValue:(float)aFloat
{
	if (_type != NSTextCellType) {
		return;
	}
	[self setObjectValue:[NSNumber numberWithFloat:aFloat]];
}

- (void)setDoubleValue:(double)aDouble
{
	if (_type != NSTextCellType) {
		return;
	}
	[self setObjectValue:[NSNumber numberWithDouble:aDouble]];
}

/* ============================================================================================ *
 * THE FIELD-EDITOR FAMILY, AND THE THREE SMALL DOORS THE INK AND FORMAT FAMILIES LEFT OPEN.      *
 * ============================================================================================ */

/* **ONE EXPANSION DOOR, AND APPLE'S OWN SENTENCE IS THE WHOLE IMPLEMENTATION**: "the default implementation … simply
 * calls -drawWithFrame:inView:". It was left open while `-drawWithFrame:` did not exist; now it does, so this is the
 * published default rather than a stub. A cell that wants a different expansion (a Quick Look preview) overrides it. */
- (void)drawWithExpansionFrame:(NSRect)cellFrame inView:(NSView *)view
{
	[self drawWithFrame:cellFrame inView:view];
}

/* **THE HIGHLIGHT COLOUR IS THE ONE THE CELL IS DRAWN WITH, ASKED AS A DOOR.** A table, a browser and a menu all draw a
 * selected row differently, but they agree on WHICH COLOUR means selected — the platform's selection colour — and a cell
 * that is not highlighted answers the text colour, because a "highlight" that is not one is not a fill. */
- (NSColor *)highlightColorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
	(void)cellFrame;
	(void)controlView;
	return [self isHighlighted] ? [NSColor selectedControlColor] : [NSColor controlTextColor];
}

/* ---- THE SESSION ------------------------------------------------------------------------------- */

/* **THE EDITOR IS CONFIGURED FROM THE CELL, WHICH IS THE ONE THING THIS DOOR IS.** A cell with no font of its own leaves
 * the editor's; the base class cannot supply one (see the geometry family's note), and a subclass that has one
 * (`NSTextFieldCell`) overrides this door to say more. THE EDITOR DRAWS NO BACKGROUND: the CELL has already drawn the
 * face, and an editor that painted its own would be a second field inside the first. */
- (NSText *)setUpFieldEditorAttributes:(NSText *)textObj
{
	if (textObj == nil) {
		return nil;
	}
	[textObj setFieldEditor:YES];
	[textObj setDrawsBackground:NO];
	[textObj setEditable:[self isEditable]];
	[textObj setSelectable:YES];
	if ([self font] != nil) {
		[textObj setFont:[self font]];
	}
	[textObj setAlignment:[self alignment]];
	return textObj;
}

/* **A SESSION IS THE EDITOR IN THE VIEW, THE CELL'S STRING IN THE EDITOR, AND THE CELL AS ITS DELEGATE.** The delegate
 * a CALLER passes is kept beside this one and told afterwards — a control that wants to know when its field was edited
 * hears about it without owning the session. A refused first-responder answer UNDOES the whole thing, which is the
 * lesson `NSTextFieldCell` records at its own copy of this method: a field nobody may edit must not keep a caret. */
- (void)selectWithFrame:(NSRect)aRect inView:(NSView *)controlView editor:(NSText *)textObj
	       delegate:(id)anObject start:(NSInteger)selStart length:(NSInteger)selLength
{
	NSRect room = [self drawingRectForBounds:aRect];
	NSString *string = [self stringValue];

	if (textObj == nil) {
		return;
	}
	_cgFieldDelegate = anObject;
	textObj = [self setUpFieldEditorAttributes:textObj];
	_cgFieldEditor = textObj;
	[textObj setFrame:room];
	[textObj setString:(string != nil ? string : @"")];
	[textObj setDelegate:self];
	if (controlView != nil) {
		[controlView addSubview:textObj];
	}
	/* **A VIEW WITH NO WINDOW HAS NO RESPONDER CHAIN TO JOIN**, so the refusal test is only asked when there is one.
	 * MEASURED: treating a nil window's answer as a refusal undid a session that a caller with an offscreen cell — a
	 * probe, a cell drawn into a bitmap — had every right to begin; the editor is placed and its string set, and there is
	 * simply nobody to make first responder. */
	if ([controlView window] != nil && ![[controlView window] makeFirstResponder:textObj]) {
		[textObj setDelegate:nil];
		[textObj removeFromSuperview];
		_cgFieldEditor = nil;
		_cgFieldDelegate = nil;
		return;
	}
	[textObj setSelectedRange:NSMakeRange((NSUInteger)selStart, (NSUInteger)selLength)];
}

/* AND A POINTER'S EDIT SELECTS ALL OF IT, which is what a first click into a field does. */
- (void)editWithFrame:(NSRect)aRect inView:(NSView *)controlView editor:(NSText *)textObj
	     delegate:(id)anObject event:(NSEvent *)theEvent
{
	(void)theEvent;
	[self selectWithFrame:aRect inView:controlView editor:textObj delegate:anObject
			start:0 length:(NSInteger)[[self stringValue] length]];
}

/* **ENDING A SESSION IS THE CELL TAKING ITS STRING BACK.** A direct call takes the string — there is no key behind it and
 * therefore nothing to cancel — and the caller's delegate is told afterwards, in that order, so a delegate that reads the
 * cell finds the new value already in it. */
- (void)endEditing:(NSText *)textObj
{
	id caller = _cgFieldDelegate;

	if (textObj != nil) {
		[self setStringValue:[textObj string]];
		[textObj setDelegate:nil];
		[textObj removeFromSuperview];
	}
	_cgFieldEditor = nil;
	_cgFieldDelegate = nil;
	if (caller != nil && [caller respondsToSelector:@selector(textDidEndEditing:)]) {
		[caller textDidEndEditing:[NSNotification notificationWithName:NSTextDidEndEditingNotification
								       object:textObj
								     userInfo:nil]];
	}
}

/* THE TWO NOTIFICATIONS THE SESSION NEEDS. The `Should` answer is YES — the base has no reason to refuse a session it was
 * asked to begin — and the did-end takes the string back through `-endEditing:`, which is the whole of what a session
 * ending on its own means. */
- (BOOL)textShouldEndEditing:(NSText *)textObject
{
	(void)textObject;
	return YES;
}

- (void)textDidEndEditing:(NSNotification *)notification
{
	[self endEditing:[notification object]];
}

/* **AND THE WINDOW'S EDITOR, WHICH IS THE OBJECT THE FOUR ABOVE ARE LENT.** A window keeps one and lends it to whichever
 * field is being edited; asking it is why this door takes a view rather than a window. */
- (NSText *)fieldEditorForView:(NSView *)aView
{
	return [[aView window] fieldEditor:YES forObject:self];
}

/* **THE TRACKING LOOP, WHICH IS `NSControl -mouseDown:` WITHOUT THE CONTROL.** The same three hooks, the same highlight,
 * the same rule that the action goes out only if the button came up inside — and the same guard for a program with no
 * event source, which is the one path a probe can drive. The frame is the caller's (a table's row, a browser's cell), not
 * the view's bounds. */
- (BOOL)trackMouse:(NSEvent *)theEvent inRect:(NSRect)cellFrame ofView:(NSView *)controlView untilMouseUp:(BOOL)flag
{
	NSApplication *app = [NSApplication sharedApplication];
	NSWindow *window = [controlView window];
	NSPoint where = [controlView convertPoint:[theEvent locationInWindow] fromView:nil];
	BOOL inside = NSPointInRect(where, cellFrame);

	(void)flag;
	[self highlight:YES withFrame:cellFrame inView:controlView];
	(void)[self startTrackingAt:where inView:controlView];
	if ([controlView respondsToSelector:@selector(setNeedsDisplay:)]) {
		[controlView setNeedsDisplay:YES];
	}
	if (![app isRunning]) {
		/* NOTHING CAN BE TRACKED WITHOUT AN EVENT SOURCE: the press is the whole of what can be applied, and the answer
		 * says whether the pointer was inside when it began — the same shape `NSControl`'s loop has. */
		[self highlight:NO withFrame:cellFrame inView:controlView];
		return inside;
	}
	for (;;) {
		NSEvent *next = [app nextEventMatchingMask:(NSLeftMouseDraggedMask | NSLeftMouseUpMask)
						untilDate:[NSDate dateWithTimeIntervalSinceNow:1.0 / 60.0]
						   inMode:nil
						  dequeue:YES];
		NSPoint point;
		BOOL over;

		if (next == nil) {
			if (window != nil) {
				[window displayIfNeeded];
			}
			continue;
		}
		point = [controlView convertPoint:[next locationInWindow] fromView:nil];
		over = NSPointInRect(point, cellFrame);
		(void)[self continueTracking:where at:point inView:controlView];
		where = point;
		if (over != [self isHighlighted]) {
			[self highlight:over withFrame:cellFrame inView:controlView];
			[controlView setNeedsDisplay:YES];
		}
		if ([next type] == NSLeftMouseUp) {
			inside = over;
			break;
		}
		if (window != nil) {
			[window displayIfNeeded];
		}
	}
	[self stopTracking:where at:where inView:controlView mouseIsUp:inside];
	[self highlight:NO withFrame:cellFrame inView:controlView];
	return inside;
}

/* ---- THE NUMBER FORMAT ------------------------------------------------------------------------- */

/* **THE TWO RULES APPLE PUBLISHES, ONE FORMAT EACH.** With `autoRange` NO the total width is the integer digits plus the
 * point plus the fraction digits, ZERO-PADDED — and a value whose integer part is longer than `left` is NOT truncated
 * (printf's own behaviour, which is what the era's sentence describes). With YES the two numbers are a maximum total width
 * and the fraction digits are still the second one. A `left` or `right` below zero is clamped, because a negative width is
 * not a format. */
- (void)setFloatingPointFormat:(BOOL)autoRange left:(NSInteger)leftDigits right:(NSInteger)rightDigits
{
	_cgFloatingFormat = YES;
	_cgFloatingAutoRange = autoRange ? YES : NO;
	_cgFloatingLeft = (leftDigits > 0) ? leftDigits : 0;
	_cgFloatingRight = (rightDigits > 0) ? rightDigits : 0;
}

/* AND THE READER IS `-stringValue`, one door down: a numeric value WITH a format set is rendered by these rules unless a
 * formatter was set, which supersedes them. */
static NSString *fn_floating_string(double value, BOOL autoRange, NSInteger left, NSInteger right)
{
	char format[64];
	char buffer[256];
	NSInteger width;

	if (autoRange) {
		width = left + right;
		if (width < 0) {
			width = 0;
		}
		snprintf(format, sizeof(format), "%%%ld.%ldf", (long)(width + 1), (long)right);
	} else {
		width = left + ((right > 0) ? right + 1 : 0);
		snprintf(format, sizeof(format), "%%0%ld.%ldf", (long)width, (long)right);
	}
	snprintf(buffer, sizeof(buffer), format, value);
	return [NSString stringWithUTF8String:buffer];
}

/* ---- AND THE HIT TEST, WHOSE CONTRACT IS THE ERA'S OWN COMMENT RATHER THAN A GUESS ---------------------------- */

/* **THE ERA STATES ONE BRANCH PER KIND OF CELL, AND THIS CLASS CAN DECIDE MOST OF EACH ONE.** From the block that
 * declares the constants: an IMAGE cell answers on the image ("if the image exists, and the event point is in the
 * image return NSCellHitContentArea, else NSCellHitNone"); a TEXT cell answers on its text — the content area, "and,
 * if the cell is enabled", the editable one, while "if there is not text" it answers NSCellHitNone; and a NULL cell,
 * "the default that applies to non text or image cells", answers NSCellHitContentArea BY DEFAULT, adding the trackable
 * area only "if the cell not disabled, and it would track".
 *
 * AND TWO CLAUSES ARE REFUSED BY NAME RATHER THAN GUESSED, because each needs something this class does not have:
 *
 *   * "THE EVENT POINT IS IN THE IMAGE" AND "HITS IN THE TEXT" ARE TESTS AGAINST THE IMAGE RECT AND THE TITLE RECT,
 *     and this class owns neither — `-imageRectForBounds:` and `-titleRectForBounds:` are the geometry family, which
 *     needs a font. So the point is tested against the CELL FRAME, WHICH IS A STATED APPROXIMATION: exact for a cell
 *     whose content fills its frame, and WRONG FOR ONE WITH PADDING, where the era would answer NSCellHitNone and this
 *     answers the content area. It is named here, at the door, rather than left for a caller to discover.
 *   * "AND IT WOULD TRACK" HAS NO DEFINITION IN ANY ERA FETCHED: it is not a door on this class, and the two candidates
 *     a reader would reach for (`-isContinuous`, the target/action pair) are state the sentence does not name. So the
 *     TRACKABLE half is REFUSED, while the content half of that same sentence — which is unconditional — IS answered.
 *
 * APPKIT-REFUSE: "would track" is undefined in every era fetched, and the content area is what this door can stand on. */
- (NSUInteger)hitTestForEvent:(NSEvent *)event inRect:(NSRect)cellFrame ofView:(NSView *)controlView
{
	NSPoint point = [event locationInWindow];
	BOOL flipped = (controlView != nil) ? [controlView isFlipped] : NO;
	NSString *text;

	if (controlView != nil) {
		/* THE EVENT'S POINT ARRIVES IN WINDOW SPACE AND THE FRAME IS IN THE VIEW'S, which is the conversion every
		 * other frame-taking door in this class assumes (`-highlight:withFrame:inView:`, `-resetCursorRect:inView:`).
		 * WITHOUT A CONTROL VIEW THERE IS NO CONVERSION TO MAKE, so the point is taken as given — the reading this
		 * class gives a nil view one door over. */
		point = [controlView convertPoint:point fromView:nil];
	}
	if (_type == NSImageCellType) {
		/* THE HALF OF THE IMAGE SENTENCE THAT IS DECIDABLE: no image, no hit — its own "else NSCellHitNone". */
		if (_image == nil) {
			return NSCellHitNone;
		}
		return NSMouseInRect(point, cellFrame, flipped) ? NSCellHitContentArea : NSCellHitNone;
	}
	if (_type == NSTextCellType) {
		/* AND THE HALF OF THE TEXT SENTENCE THAT IS DECIDABLE FIRST: "if there is not text: returns NSCellHitNone". */
		text = [self stringValue];
		if (text == nil || [text length] == 0) {
			return NSCellHitNone;
		}
		if (!NSMouseInRect(point, cellFrame, flipped)) {
			return NSCellHitNone;
		}
		/* AND THE EDITABLE AREA IS THE ENABLED HALF OF THE SENTENCE, not a condition of this library's making. */
		return _enabled ? (NSCellHitContentArea | NSCellHitEditableTextArea) : NSCellHitContentArea;
	}
	/* **THE NULL CELL IS THE DOCUMENTED DEFAULT AND ITS CONTENT HALF IS UNCONDITIONAL** — the era's sentence has no
	 * frame test for it, so none is added here: a null cell asked about a point answers the content area. It is also
	 * the answer every subclass in Apple's design starts from before overriding. */
	return NSCellHitContentArea;
}

/* ---- AND THE LAYOUT STATE, FIVE ACCESSOR PAIRS OVER FIVE PLAIN VALUES ------------------------------- */

/* **NOT ONE OF THESE DOORS DOES ANYTHING BUT STORE AND ANSWER**, which is the right shape for state that the drawing
 * these cells do not have would read later. The two defaults that are NOT zero live in `-init` (see there); what these
 * pairs have to get right is the TYPES — `-alignment` answers an `NSUInteger`-based enum while `-baseWritingDirection`
 * answers a signed one whose natural case is `-1`, so a coercion between the two would be a defect with a plausible
 * value rather than a warning a compiler could give.
 *
 * AND THERE IS NOTHING ELSE FOR THEM TO DO: this class has no font and no layout, so a setter has nothing to invalidate
 * or recompute. That is why they arrive as one unit — five fields Apple declares, five fields this class can hold, and
 * no behaviour between them. */
- (NSTextAlignment)alignment
{
	return _alignment;
}

- (void)setAlignment:(NSTextAlignment)mode
{
	_alignment = mode;
}

- (NSLineBreakMode)lineBreakMode
{
	return _lineBreakMode;
}

- (void)setLineBreakMode:(NSLineBreakMode)mode
{
	_lineBreakMode = mode;
}

- (NSWritingDirection)baseWritingDirection
{
	return _baseWritingDirection;
}

- (void)setBaseWritingDirection:(NSWritingDirection)writingDirection
{
	_baseWritingDirection = writingDirection;
}

- (NSFocusRingType)focusRingType
{
	return _focusRingType;
}

- (void)setFocusRingType:(NSFocusRingType)focusRingType
{
	_focusRingType = focusRingType;
}

+ (NSFocusRingType)defaultFocusRingType
{
	/* A CLASS METHOD, WHICH IS APPLE'S OWN SPELLING — and the answer is THIS class's default for a fresh cell rather
	 * than a global: `NSView` declares the same selector for views, and the two doors answer for their own kind. */
	return NSFocusRingTypeDefault;
}

- (NSUserInterfaceLayoutDirection)userInterfaceLayoutDirection
{
	return _userInterfaceLayoutDirection;
}

- (void)setUserInterfaceLayoutDirection:(NSUserInterfaceLayoutDirection)layoutDirection
{
	_userInterfaceLayoutDirection = layoutDirection;
}

/* ---- THE FLAGS, AND THE ONE OF THEM THAT DOES SOMETHING ------------------------------------------- */

- (BOOL)isSelectable
{
	return _selectable;
}

- (void)setSelectable:(BOOL)flag
{
	_selectable = flag;
}

- (BOOL)isScrollable
{
	return _scrollable;
}

- (void)setScrollable:(BOOL)flag
{
	/* **AND THIS SETTER IS NOT STORAGE, WHICH IS WHY THE WHOLE BLOCK IS WORTH A COMMENT**: the era header's own
	 * comment on this door says "If YES, sets wraps to NO", and the pair describes one axis — a cell whose text
	 * scrolls cannot wrap and one that wraps cannot scroll. A cell that stored both would answer two contradictory
	 * questions, so the setter keeps them TRUE OF EACH OTHER, and the probe asserts the interaction rather than the
	 * two flags separately. */
	_scrollable = flag;
	if (flag) {
		_wraps = NO;
	}
}

- (BOOL)wraps
{
	return _wraps;
}

- (void)setWraps:(BOOL)flag
{
	_wraps = flag;
}

- (BOOL)truncatesLastVisibleLine
{
	return _truncatesLastVisibleLine;
}

- (void)setTruncatesLastVisibleLine:(BOOL)flag
{
	_truncatesLastVisibleLine = flag;
}

- (BOOL)usesSingleLineMode
{
	return _usesSingleLineMode;
}

- (void)setUsesSingleLineMode:(BOOL)flag
{
	_usesSingleLineMode = flag;
}

- (BOOL)sendsActionOnEndEditing
{
	return _sendsActionOnEndEditing;
}

- (void)setSendsActionOnEndEditing:(BOOL)flag
{
	_sendsActionOnEndEditing = flag;
}

- (BOOL)refusesFirstResponder
{
	return _refusesFirstResponder;
}

- (void)setRefusesFirstResponder:(BOOL)flag
{
	_refusesFirstResponder = flag;
}

- (BOOL)showsFirstResponder
{
	return _showsFirstResponder;
}

- (void)setShowsFirstResponder:(BOOL)flag
{
	_showsFirstResponder = flag;
}

- (BOOL)wantsNotificationForMarkedText
{
	return _wantsNotificationForMarkedText;
}

- (void)setWantsNotificationForMarkedText:(BOOL)flag
{
	_wantsNotificationForMarkedText = flag;
}

- (BOOL)isOpaque
{
	return _opaque;
}

- (void)setOpaque:(BOOL)flag
{
	_opaque = flag;
}

/* A CLASS QUESTION, so it is answered for the kind rather than for an instance — and the answer is the quiet one,
 * since a cell that does not say otherwise tracks the way every control expects. */
+ (BOOL)prefersTrackingUntilMouseUp
{
	return NO;
}

- (NSBackgroundStyle)interiorBackgroundStyle
{
	/* **THE DERIVATION, WHICH IS THE WHOLE OF THIS DOOR**: a bezeled cell's interior is one step from its
	 * background — a raised surface has a lowered interior and the other way round — because the bezel is drawn
	 * BETWEEN them. A cell with no bezel has no such step, so its interior IS its background, which is what the
	 * first clause answers. */
	if (!_bezeled) {
		return _backgroundStyle;
	}
	if (_backgroundStyle == NSBackgroundStyleRaised) {
		return NSBackgroundStyleLowered;
	}
	if (_backgroundStyle == NSBackgroundStyleLowered) {
		return NSBackgroundStyleRaised;
	}
	return _backgroundStyle;
}

/* ---- WHAT A CELL IS FOR: its identity, its action, and the menu it may raise ---------------------- */

/* THE TARGET/ACTION PAIR. The target is NOT retained, which is the tree's rule for every target; the action is a
 * bare selector and may be NULL, which is what a cell with nothing to send has. */
- (id)target
{
	return _target;
}

- (void)setTarget:(id)anObject
{
	_target = anObject;
}

- (SEL)action
{
	return _action;
}

- (void)setAction:(SEL)aSelector
{
	_action = aSelector;
}

/* THE IDENTITY, all plain storage except the title, which is COPIED — a cell owns its title because a caller that
 * handed over a mutable string and then changed it would otherwise change the cell's face. */
- (NSCellType)type
{
	return _type;
}

- (void)setType:(NSCellType)aType
{
	_type = aType;
}

- (NSString *)title
{
	return _title;
}

/* **AND THE ANSWER IS THE LABEL, BECAUSE THAT IS WHAT EVERY CELL THAT DOES NOT SAY OTHERWISE SHOWS.** A button's
 * caption, a menu item's row and a status item's line are all `-_title`; a FIELD's is its value, and `NSTextFieldCell`
 * overrides this to say so. See the header for why the two doors are both real and what went wrong when a measurement
 * read one of them while the drawing read the other. */
- (NSString *)cg_contentText
{
	return _title;
}

/* **AND THE TWO DOORS A SESSION PUTS ON A CELL, WHICH THIS BASE ANSWERS "NOTHING" TO.** The pair exists so that a
 * control can answer `-currentEditor` and `-abortEditing` without knowing which of its cells can hold a session: the
 * base's cell cannot, so it says so, and `NSTextFieldCell` overrides both. They live here rather than only on the
 * field cell because `NSControl` must be able to ask them of whatever cell it was given — the same reason
 * `-cg_contentText` is a base door and not a field-only one. */
- (NSText *)cg_currentEditor
{
	return nil;
}

- (BOOL)cg_abortEditing
{
	return NO;
}

- (void)setTitle:(NSString *)aString
{
	if (aString != _title) {
		NSString *copy = [aString copy];

		[_title release];
		_title = copy;
	}
	/* **AND A NEW TITLE CLEARS THE MNEMONIC, WHICH IS THE HALF THAT MAKES THE PAIR A RELATION**: the location is an
	 * INDEX INTO THIS STRING, so leaving it standing would point at a character nobody marked. The invariant is
	 * `NSMenuItem`'s, and it is also what makes `-setTitleWithMnemonic:` below honest — that door sets the title
	 * first, so every early return it takes afterwards leaves a cell naming no mnemonic rather than one naming a
	 * character out of a string it no longer carries. THE CLEAR IS UNCONDITIONAL, including when the string handed in
	 * is the same object: asking again is a statement about what the title is now. */
	_mnemonicLocation = NSNotFound;
}

/* **AND THE MNEMONIC FAMILY, WHOSE RULE THIS TREE HAD ALREADY DECIDED ONE CLASS OVER.** `NSMenuItem` parses the same
 * convention and its probe protects it, so these doors are that rule and not a fresh reading of it: `&` marks the
 * character that follows, the pair is stripped out of the title, and the parse is ONE PASS. The era's parameter name
 * (`stringWithAmpersand`) states the convention; Apple's documentation states the returns.
 *
 * AND THE RETURN TYPE IS WHERE A MIRROR OF `NSMenuItem` WOULD HAVE BEEN WRONG: `-mnemonic` answers an `NSString *` on
 * a cell and a `unichar` on a menu item, and the documented "or an empty string if no mnemonic character is set" is
 * why the answer here is `@""` rather than nil. */
- (NSString *)mnemonic
{
	if (_mnemonicLocation == NSNotFound || _mnemonicLocation >= [_title length]) {
		return @"";
	}
	return [_title substringWithRange:NSMakeRange(_mnemonicLocation, 1)];
}

- (NSUInteger)mnemonicLocation
{
	return _mnemonicLocation;
}

- (void)setMnemonicLocation:(NSUInteger)location
{
	/* A SETTER, AND NOTHING MORE: Apple documents this door as the one that marks a character in the title, and
	 * `NSButtonCell`'s alternate-title twin takes `NSNotFound` to mean "no mnemonic" — so no validation is invented
	 * here. An index that is out of range simply answers nothing through `-mnemonic`, which is the quiet answer
	 * rather than a refusal nobody asked for. */
	_mnemonicLocation = location;
}

- (void)setTitleWithMnemonic:(NSString *)stringWithAmpersand
{
	NSRange amp;

	if (stringWithAmpersand == nil) {
		/* **NIL IS THE EMPTY TITLE RATHER THAN A STORED NIL**, which is the reading `NSMenuItem` ships for this
		 * same selector — and the reason `-mnemonic` can promise a string instead of "a string or nil". */
		[self setTitle:@""];
		return;
	}
	[self setTitle:stringWithAmpersand];	/* which CLEARS the location, so every return below is honest */
	amp = [_title rangeOfString:@"&"];
	if (amp.location == NSNotFound) {
		return;				/* no `&`, so no mnemonic — which is the common case */
	}
	if (amp.location + 1 < [_title length] && [_title characterAtIndex:amp.location + 1] == '&') {
		/* `&&` IS A LITERAL AMPERSAND, Apple's convention, and it names no mnemonic: the pair collapses to ONE `&`
		 * and the scan does not resume — the one-pass rule `NSMenuItem` records. */
		NSString *collapsed = [[_title stringByReplacingCharactersInRange:NSMakeRange(amp.location, 2)
									 withString:@"&"] copy];

		[_title release];
		_title = collapsed;
		return;
	}
	if (amp.location + 1 >= [_title length]) {
		return;				/* a trailing `&` names nothing */
	}
	_mnemonicLocation = amp.location;
	{
		NSString *marked = [[_title stringByReplacingCharactersInRange:NSMakeRange(amp.location, 1)
								      withString:@""] copy];

		[_title release];
		_title = marked;
	}
}

- (NSInteger)state
{
	return _state;
}

- (void)setState:(NSInteger)value
{
	_state = value;
}

- (NSInteger)tag
{
	return _tag;
}

- (void)setTag:(NSInteger)anInt
{
	_tag = anInt;
}

/* ---- AND THE VALUE-TAKING FAMILY, THE FIRST DOORS IN THIS CLASS THAT NEED NOTHING BUT OBJECTIVE-C ------------ */

/* **EVERY DOOR IS THE SAME TWO STEPS, AND THE SECOND ONE IS WHY THEY ARE WORTH HAVING**: read the named value OFF
 * THE SENDER, then hand it to this cell's ONE VALUE DOOR, so `-setObjectValue:` stays the only place a value becomes
 * this cell's value. A door here never touches storage — it asks the sender a question and lets the class decide what
 * the answer means, which is what makes `-takeObjectValueFrom:` and `-takeStringValueFrom:` disagree about the same
 * sender and both be right.
 *
 * AND THE NUMERIC DOORS BOX, BECAUSE THAT IS WHAT THIS CELL'S VALUE IS: the class keeps an OBJECT and coerces on the
 * way out (the five getters above are those coercions), so a door that arrives with an `int` puts an `NSNumber` in.
 * A door that wrote a bare scalar into object storage would compile and be wrong.
 *
 * AND EVERY DOOR IS GUARDED, like the coercions one screen up: a sender that does not answer the question being
 * asked changes NOTHING — a caller's mistake refused quietly rather than a `-doesNotRecognizeSelector:` raised at a
 * cell that cannot help. NOTHING HERE CLEARS THE VALUE IT COULD NOT REPLACE. */

- (void)takeIntValueFrom:(id)sender
{
	if ([sender respondsToSelector:@selector(intValue)]) {
		[self setObjectValue:[NSNumber numberWithInt:[sender intValue]]];
	}
}

- (void)takeIntegerValueFrom:(id)sender
{
	if ([sender respondsToSelector:@selector(integerValue)]) {
		[self setObjectValue:[NSNumber numberWithInteger:[sender integerValue]]];
	}
}

- (void)takeFloatValueFrom:(id)sender
{
	if ([sender respondsToSelector:@selector(floatValue)]) {
		[self setObjectValue:[NSNumber numberWithFloat:[sender floatValue]]];
	}
}

- (void)takeDoubleValueFrom:(id)sender
{
	if ([sender respondsToSelector:@selector(doubleValue)]) {
		[self setObjectValue:[NSNumber numberWithDouble:[sender doubleValue]]];
	}
}

- (void)takeStringValueFrom:(id)sender
{
	if ([sender respondsToSelector:@selector(stringValue)]) {
		[self setObjectValue:[sender stringValue]];
	}
}

- (void)takeObjectValueFrom:(id)sender
{
	if ([sender respondsToSelector:@selector(objectValue)]) {
		[self setObjectValue:[sender objectValue]];
	}
}

/* ---- AND THE STATE CYCLE, WRITTEN ONCE BECAUSE TWO DOORS NOW NEED IT ---------------------------------------- */

/* **WHY A C FUNCTION RATHER THAN A PRIVATE METHOD: A METHOD USED BEFORE ITS DEFINITION WOULD HAVE TO BE DECLARED, AND
 * THIS CLASS DECLARES ITS SURFACE IN THE HEADER.** A file-static function has no such ordering problem, and the
 * arithmetic below is the part that has to exist once — the two doors differ ONLY in whether they store the answer. */
static NSInteger NSCellNextStateValue(BOOL allowsMixed, NSInteger state)
{
	if (allowsMixed) {
		if (state == NSOffState) {
			return NSOnState;
		}
		if (state == NSOnState) {
			return NSMixedState;
		}
		return NSOffState;
	}
	return (state == NSOffState) ? NSOnState : NSOffState;
}

- (void)setNextState
{
	/* **THE CYCLE, AND ITS LENGTH IS THIS CLASS'S ANSWER RATHER THAN ITS CALLER's** — which is the whole reason
	 * this is a door and not a setter for `state`: a cell that ALLOWS a mixed state walks OFF -> ON -> MIXED -> OFF,
	 * and one that does not walks OFF -> ON -> OFF. BOTH WALKS LIVE IN THE FUNCTION ABOVE, which is what this
	 * method became when `-nextState` arrived: a command and a question with one arithmetic. */
	_state = NSCellNextStateValue(_allowsMixedState, _state);
}

- (NSInteger)nextState
{
	/* THE SAME WALK, WITHOUT STORING IT — which is exactly what makes this a question rather than a command. */
	return NSCellNextStateValue(_allowsMixedState, _state);
}

/* ---- AND THE ATTRIBUTE WORD: ONE BIT READ, ONE BIT WRITE, AND NOTHING ELSE ---------------------------------- */

/* **THE ENUM HAS SEVENTEEN POSITIONS AND THESE TWO DOORS ARE HOW A CALLER REACHES ONE** — which is all
 * `NSCellAttribute` ever needed and all this class had never given it. THE READ IS A SHIFT AND A MASK rather than a
 * lookup, because the parameter IS the bit's position; the write sets or clears the same bit.
 *
 * AND NOTHING IS VALIDATED, DELIBERATELY: an out-of-range parameter shifts past the word, and refusing it would be
 * inventing a rule the era does not state — Apple's own signature promises no error, and a caller passing a
 * non-attribute gets the same quiet zero the rest of this class answers with. */
- (NSInteger)cellAttribute:(NSCellAttribute)aParameter
{
	return (NSInteger)((_cellAttribute >> (unsigned)aParameter) & 1UL);
}

- (void)setCellAttribute:(NSCellAttribute)aParameter to:(NSInteger)value
{
	if (value) {
		_cellAttribute |= (1UL << (unsigned)aParameter);
	} else {
		_cellAttribute &= ~(1UL << (unsigned)aParameter);
	}
}

/* ---- AND BEING PRESSED: THE LAST PART OF THIS CLASS THAT NEEDS NO INK -------------------------------- */

/* **THE STATE IS REAL AND THE DRAWING IS NOT.** A control calls this while the mouse is down — and again with NO on
 * the way up — and what it changes is the cell's `highlighted` flag, the thing every other door in this class already
 * asks about. THE GREYING OF THE CELL'S FACE IS INK, and this tier's drawing doors have refused that since their
 * first class. THE FRAME AND THE VIEW ARE ACCEPTED RATHER THAN USED, which is worth stating plainly: Apple's
 * signature promises a caller will have them, so a caller does; a door that dropped them would not be Apple's
 * selector, and a door that pretended to draw would be a lie with a frame argument in front of it. */
- (void)highlight:(BOOL)flag withFrame:(NSRect)cellFrame inView:(id)controlView
{
	[self setHighlighted:flag];
	/* **AND THE FACE IS REDRAWN, WHICH IS THE HALF THAT WAS REFUSED.** The STATE was always real; what was missing was
	 * the ink, and this is where it goes out — the control view is asked to redraw the cell's frame, and ITS
	 * `-drawRect:` calls `-drawWithFrame:inView:`, which paints the face in the state just set. A nil or non-view
	 * control (a caller driving a cell with no view in front of it) is the quiet case and nothing is asked. */
	if (controlView != nil && [controlView respondsToSelector:@selector(setNeedsDisplayInRect:)]) {
		[controlView setNeedsDisplayInRect:cellFrame];
	}
}

/* ---- AND THE ACTION MASK, WHOSE READER IS A LOOP THIS TIER HAS NOT WRITTEN ---------------------------- */

/* **THE MASK SAYS WHICH EVENTS MAKE THIS CELL SEND ITS ACTION** — it is built from the event masks `NSEvent` already
 * declares — AND THE DOOR THAT READS IT IS `-trackMouse:inRect:ofView:untilMouseUp:`, a modal tracking loop, and
 * therefore owed. SO THE STORAGE AND THE ACCESSOR LAND NOW AND THE READER LANDS WITH THE LOOP: a cell that remembers
 * its mask is not a cell that ignores it, it is a cell whose loop has not been written yet. THE DEFAULT IS ZERO,
 * which is also honest: a cell nobody has told what to listen for listens for nothing. */
- (NSInteger)sendActionOn:(NSInteger)mask
{
	NSInteger previous = _actionMask;

	_actionMask = mask;
	return previous;
}

/* ---- AND TWO ROWS THAT ARE NAMED REFUSALS RATHER THAN IMPLEMENTATIONS ---------------------------------------- */

/* **`-getPeriodicDelay:interval:` IS REFUSED BY NAME.** Apple's cell writes two `float *` out-parameters that its own
 * periodic-action machinery fills in, and THE 10.6 HEADER SAYS NOTHING ABOUT WHAT THEY CONTAIN — no defaults, no
 * units, no stated relationship to the mask above. Inventing two numbers would be exactly the kind of guess every
 * other row in this class has been measured instead of guessed, so the row stays open and the reason is HERE, at the
 * door, rather than in a ledger comment nobody opens.
 *
 * APPKIT-REFUSE: the periodic delay needs the periodic-action machinery, which is the tracking loop again. */

/* **AND `-compare:` IS REFUSED BY NAME FOR THE SAME REASON.** It is declared in the 10.2 AND 10.5 SDKs, and neither
 * of those headers nor the 10.6 one says WHAT it compares or in what order — an invented ordering would be neither
 * real behaviour nor a named refusal, which is the standard this plan holds every row to (appkit-plan.md §A10ba).
 *
 * APPKIT-REFUSE: the ordering contract is not published in any era fetched. */

/* **AND THE CURSOR OVER A CELL — §A10bf's row, AND THE FIRST DOOR IN THIS CLASS WHOSE CONTRACT HAD TO BE FETCHED
 * RATHER THAN READ OUT OF A HEADER.** All three eras declare `-resetCursorRect:inView:` and NOT ONE OF THEM SAYS WHAT
 * IT DOES: the 10.2 and 10.5 headers carry no comment on it and the 10.6 one carries none either. Apple's own
 * DOCUMENTATION does state it — the receiver is "set to show the I-beam cursor while it tracks the mouse" and "must
 * be an enabled and selectable (or editable) text-type cell" — and the OpenStep reference this descends from says the
 * same thing in the mechanism's own terms: a TEXT cell adds a cursor rectangle through `-addCursorRect:cursor:` and
 * EVERYTHING ELSE ADDS NOTHING, so the window's default arrow stands. That is one contract stated twice, two eras
 * apart, which is the ground this door is written on.
 *
 * SO THE THREE CONDITIONS ARE WRITTEN AS THREE GUARDS rather than folded into one boolean nobody can check: a control
 * view to declare into at all, ENABLED (a disabled cell does not take the pointer), text-type, and
 * selectable-or-editable. §A10bf's reconnaissance named `+arrowCursor` when it measured what `NSCursor` offers; the
 * arrow is what a cell that declares NOTHING gets, which is exactly why this door registers the I-BEAM instead, and
 * the probe checks both halves — the rect for the text cell, and the absence of one for every other kind.
 *
 * A NIL CONTROL VIEW AND A CELL OF ANY OTHER TYPE ARE THE QUIET CASES, NOT ERRORS: the same answer this class gives a
 * target that is not there. */
- (void)resetCursorRect:(NSRect)cellFrame inView:(NSView *)controlView
{
	if (controlView == nil) {
		return;
	}
	if (!_enabled) {
		return;
	}
	if (_type != NSTextCellType) {
		return;
	}
	if (!_selectable && !_editable) {
		return;
	}
	[controlView addCursorRect:cellFrame cursor:[NSCursor IBeamCursor]];
}

/* **AND `-performClick:` SENDS THE ACTION RATHER THAN IMITATING A MOUSE.** Apple's reading is that it highlights,
 * sends, and puts the highlight back — which is exactly what a keyboard equivalent needs, and exactly what a cell
 * holding a target and an action can already do. THE HIGHLIGHT IS RESTORED TO WHAT IT WAS rather than cleared,
 * because a click arriving DURING a tracking loop must not unhighlight a cell the mouse is still holding down.
 *
 * AND A CELL WITH NO TARGET IS NOT AN ERROR: it is a cell nobody is listening to, and this class's standing answer
 * to that is the quiet one rather than `-doesNotRecognizeSelector:`. */
- (void)performClick:(id)sender
{
	BOOL wasHighlighted = _highlighted;

	[self setHighlighted:YES];
	if (_action != NULL && _target != nil) {
		[_target performSelector:_action withObject:self];
	}
	[self setHighlighted:wasHighlighted];
}

/* AND WHAT THE CELL CARRIES FOR SOMEBODY ELSE. The key equivalent is copied (it is a string a caller may mutate)
 * and the menu is a bare pointer, since a menu outlives the cell that may raise it. */
- (NSString *)keyEquivalent
{
	return _keyEquivalent;
}

- (void)setKeyEquivalent:(NSString *)aString
{
	if (aString != _keyEquivalent) {
		NSString *copy = [aString copy];

		[_keyEquivalent release];
		_keyEquivalent = copy;
	}
}

- (id)menu
{
	return _menu;
}

- (void)setMenu:(id)aMenu
{
	_menu = aMenu;
}

+ (id)defaultMenu
{
	/* NIL, AND IT IS THE TRUE ANSWER RATHER THAN A REFUSAL: a default menu belongs to a VIEW hierarchy — it is what
	 * a view answers when an event arrives — and this tier's cells are not drawn into one yet. */
	return nil;
}

/* AND THE INPUT STATE: the modifiers of the mouse-down that started the current tracking, and the view the cell
 * draws into. */
- (NSInteger)mouseDownFlags
{
	return _mouseDownFlags;
}

- (void)setMouseDownFlags:(NSInteger)flags
{
	_mouseDownFlags = flags;
}

- (id)controlView
{
	return _controlView;
}

- (void)setControlView:(id)view
{
	_controlView = view;
}

/* ---- AND THE DEPRECATED ENTRY VOCABULARY, WHOSE DOORS APPLE ITSELF POINTS AT THE FORMATTER --------------------- */

/* **THE BLOCK IS APPLE'S `NSCell (NSDeprecated)` CATEGORY, DECLARED IN THE CLASS'S OWN INTERFACE** for the reason
 * §A10bk recorded when the `NSKeyboardUI` and `NSCellHitTest` members came here: this tree flattens Apple's categories
 * into the class, and the `category` row an era artefact carries for one STAYS OPEN, because it is a fact about the
 * era's FILE rather than about what the cell can do. The 10.6 work list has exactly one such row for this block.
 *
 * AND THE ONE PIECE OF ARITHMETIC IN THIS BLOCK IS WRITTEN OUT RATHER THAN BORROWED, BECAUSE THE KIND OF NUMBER IS THE
 * WHOLE QUESTION. `-intValue` and `-doubleValue` both answer ZERO for a string that is not a number at all, so NEITHER
 * CAN SAY WHETHER A STRING IS ONE — which is the question `-isEntryAcceptable:` asks. The accepted shape is therefore
 * the one the vocabulary's own names describe: an optional sign, then either digits alone (the INTEGER entries) or
 * digits with at most one fraction point and an optional decimal exponent (the FLOAT and DOUBLE ones). The sign is
 * refused OUTRIGHT for the POSITIVE members rather than checked afterwards, because being positive is what those
 * entries ARE; and the exponent is allowed only for the floating kinds, so `@"1e3"` is an entry for `NSFloatType` and
 * not for `NSIntType`. */
static BOOL fn_entry_is_number(NSString *string, BOOL allowFraction, BOOL allowSign)
{
	NSUInteger i = 0, n = [string length];
	BOOL seenDigit = NO, seenPoint = NO;

	if (n == 0) {
		return NO;
	}
	if ([string characterAtIndex:0] == '+' || [string characterAtIndex:0] == '-') {
		if (!allowSign) {
			return NO;
		}
		i = 1;
	}
	for (; i < n; i++) {
		unichar c = [string characterAtIndex:i];

		if (c >= '0' && c <= '9') {
			seenDigit = YES;
			continue;
		}
		if (c == '.' && allowFraction && !seenPoint) {
			seenPoint = YES;
			continue;
		}
		if ((c == 'e' || c == 'E') && allowFraction && seenDigit) {
			NSUInteger j = i + 1;
			BOOL exponentHasDigit = NO;

			if (j < n && ([string characterAtIndex:j] == '+' || [string characterAtIndex:j] == '-')) {
				j++;
			}
			for (; j < n; j++) {
				unichar d = [string characterAtIndex:j];

				if (d < '0' || d > '9') {
					return NO;
				}
				exponentHasDigit = YES;
			}
			return exponentHasDigit;
		}
		return NO;
	}
	return seenDigit;
}

- (NSInteger)entryType
{
	return _entryType;
}

/* **THE SETTER'S CONTRACT IS TWO SENTENCES AND THIS DOOR OBEYS ONE OF THEM IN FULL.** Apple: `-setEntryType:` "sets
 * how numeric data is formatted in the receiver and places restrictions on acceptable input", and then, in the same
 * paragraph, "the formatter associated with the receiver is replaced with a newly instantiated formatter appropriate
 * to the entry type. If the receiver isn't a text-type cell, it is converted to one (which changes its title to
 * \"Cell\" and sets the font to the system font at 12 points)".
 *
 * THE CONVERSION AND THE TITLE ARE THE HALF THAT NEEDS NO INK, and they are the SAME side effect OpenStep gives
 * `-setType:`. The conversion is guarded on the cell NOT already being text, because that is what the sentence says:
 * a text cell keeps the title it has. */
- (void)setEntryType:(NSInteger)aType
{
	_entryType = aType;
	if (_type != NSTextCellType) {
		_type = NSTextCellType;
		[self setTitle:@"Cell"];
		/* **AND THE FONT, FOR THE SAME REASON `-setStringValue:` NOW SETS IT** — the sentence names the system font
		 * at 12.0 points, and both the class and the door are here now, so it is set rather than refused. THE
		 * FORMATTER CLAUSE BELOW STILL STANDS, and on a different ground. */
		[self setFont:[NSFont systemFontOfSize:12.0]];
	}
	/* APPKIT-REFUSE: "the formatter associated with the receiver is replaced with a newly instantiated formatter
	 * appropriate to the entry type" — WHICH FORMATTER IS APPROPRIATE TO WHICH ENTRY TYPE IS NOT PUBLISHED. Apple
	 * names the entry types' MEANINGS and stops, so the mapping would be invented; and this tier HAS the formatter
	 * (§A10bm), so a caller who wants one sets it with `-setFormatter:` and gets that unit's documented two-way
	 * conversion rather than a guess. A cell that arrived here carrying a formatter keeps it. */
}

- (BOOL)isEntryAcceptable:(NSString *)aString
{
	/* **THE SENTENCE NAMES THE TEST, AND THE TEST IS THE ENTRY TYPE**: "whether a string representing a numeric or date
	 * value is formatted in a suitable way for the cell's entry type". So the vocabulary this file carries for
	 * `-entryType` decides which strings are entries, and the two readings the sentence does NOT spell out are stated
	 * where they are decided:
	 *
	 *   * THE CHECK IS OVER THE WHOLE STRING. Its subject is "a string representing a numeric value", so `@" 42"` is
	 *     refused where `-intValue` would answer 42 — the stricter reading, and the one a caller validating typed
	 *     input wants.
	 *   * AN EMPTY STRING IS ACCEPTED BY `NSAnyType` AND REFUSED BY EVERY NUMERIC TYPE. "Any value is allowed" is the
	 *     vocabulary's own gloss for `NSAnyType`, and no digits are not a number.
	 *
	 * AND THE CELL'S FORMATTER IS DELIBERATELY NOT CONSULTED: this door's own documentation answers from the ENTRY
	 * TYPE, and §A10bm's formatter is the MODERN route to a related question
	 * (`-getObjectValue:forString:errorDescription:`), which a caller who set one can ask directly instead of asking a
	 * door whose contract is about a vocabulary that predates it. */
	if (aString == nil) {
		return NO;
	}
	if (_entryType == NSAnyType) {
		return YES;
	}
	return fn_entry_is_number(aString,
				  _entryType == NSFloatType || _entryType == NSPositiveFloatType ||
				  _entryType == NSDoubleType || _entryType == NSPositiveDoubleType,
				  _entryType == NSIntType || _entryType == NSFloatType || _entryType == NSDoubleType);
}

/* ---- AND THE TWO DOORS WHOSE ANSWER IS A PUBLISHED CONSTANT --------------------------------------------------- */

- (NSRect)expansionFrameWithFrame:(NSRect)cellFrame inView:(NSView *)view
{
	/* **THE EMPTY RECT IS THE ERA'S OWN DOCUMENTED DEFAULT — "By default, NSCell returns NSZeroRect" — AND IT SAYS
	 * WHAT IT MEANS: "no expansion tool tip view will be shown".** Neither parameter is read, and that is the contract
	 * rather than an oversight: "too small for the entire contents" is a MEASUREMENT this class cannot make without
	 * the font the geometry family is blocked on. Apple's own example of a subclass that can is `NSTextFieldCell`, and
	 * that is why this is an OVERRIDE POINT a subclass replaces rather than a computation the base performs. The probe
	 * proves it the only way it can be proved — by overriding it. See appkit-plan.md §A10bo. */
	return NSZeroRect;
}

- (void)getPeriodicDelay:(float *)delay interval:(float *)interval
{
	/* **THE PAIR IS THE ERA'S, AND BOTH VINTAGES ARE NAMED HERE BECAUSE APPLE'S TWO PAGES DISAGREE.** The Leopard-era
	 * class reference says "a delay of 0.2 and an interval of 0.025 seconds"; the current page for the same selector
	 * says "a delay of 0 and an interval of 0 seconds". This tree takes the ERA's, because the era is this plan's
	 * ground (§11.5) — and the modern pair is named in this comment rather than hidden, so a reader who has the
	 * current page open is not left thinking the tree is wrong. */
	if (delay != NULL) {
		*delay = 0.2f;
	}
	if (interval != NULL) {
		*interval = 0.025f;
	}
	/* AND THE NULL GUARD IS NOT THE DOCUMENTED CONTRACT — Apple's page says the pointers "must not be NULL" — IT IS
	 * THIS TIER'S: a door that wrote through a null pointer would take the guest down rather than report anything, and
	 * this class's standing answer for a caller that is not there is to do the quiet thing (see
	 * `-resetCursorRect:inView:`'s nil control view, §A10bg). The probe calls it with two NULLs. */
}

/* ---- AND THE SIZE TRIO, WHOSE TWO SENTINELS ARE THE DOCUMENTED ANSWER AND WHOSE TWO CONTENT BRANCHES ARE NOT ------- */

/* **A REFUSED BRANCH ANSWERS THE CLASS'S OWN "NO OPINION" SENTINEL, WHICH IS WHY THE SAME PAIR OF NUMBERS APPEARS IN
 * BOTH DOORS BELOW.** `(10000, 10000)` is what Apple's `-cellSize` documents for a cell that is neither text nor image,
 * so it already MEANS "I cannot tell you" in this class's vocabulary — using it for the branches this tier cannot
 * compute keeps the meaning and keeps the two SENTINEL states distinguishable from each other, which NSZeroSize could
 * not do (a text cell answering zero would read as an image cell with no image). */
static const NSSize FN_CELL_NO_OPINION = { 10000.0, 10000.0 };

- (NSSize)cellSize
{
	/* **THE PUBLISHED SENTINELS FIRST, BECAUSE THEY ARE THE BRANCHES THAT ARE EXACTLY DEFINED**: "The size of the cell,
	 * or the size (10000, 10000) if the receiver is not a text or image cell. If the cell is an image cell but no image
	 * has been set, returns NSZeroSize."
	 *
	 * AND NOTE WHICH WAY ROUND THEY ARE: the NULL cell gets the LARGE number and the EMPTY image cell gets ZERO, so a
	 * caller scanning for "no opinion" by size finds it at 10,000 here and at nothing at all one notch over. See
	 * appkit-plan.md §A10bp. */
	if (_type == NSImageCellType && _image == nil) {
		return NSZeroSize;
	}
	if (_type == NSNullCellType) {
		return FN_CELL_NO_OPINION;
	}
	/* **AND THE MEASUREMENT IS THE SAME ONE `-cellSizeForBounds:` MAKES, WITH NO BOUND** — the sentinel above is
	 * exactly the large rectangle that means "no bound" here, so the two doors cannot disagree about what a cell
	 * measures. A TEXT cell's size is its title in the cell's font; an IMAGE cell's is its picture; both plus the
	 * air the rect doors leave. The empty-image and null-cell answers above stay the published exceptions. */
	return [self cellSizeForBounds:NSMakeRect(0.0, 0.0, FN_CELL_NO_OPINION.width, FN_CELL_NO_OPINION.height)];
}

- (NSSize)cellSizeForBounds:(NSRect)aRect
{
	/* **AND THIS DOOR'S NULL-CELL ANSWER IS NOT THE OTHER DOOR'S**, which is the trap the pair sets: "the size of the
	 * `aRect` parameter if the cell is not a text or image cell". Same cell, same question, one door answering a
	 * constant and the other answering the caller's own rect — and the only branch the two agree on is the image cell
	 * with no image. */
	if (_type == NSImageCellType && _image == nil) {
		return NSZeroSize;
	}
	if (_type == NSNullCellType) {
		return aRect.size;
	}
	/* **AND THE MEASUREMENT IS WHAT THIS DOOR WAS OWED.** A TEXT cell's size is its title in the cell's font PLUS the
	 * air the rect doors leave around it; an IMAGE cell's is its picture plus the same air. Both are CLAMPED to
	 * `aRect`, which is what "the text is resized to fit within `aRect`" says: a cell is being asked how large its
	 * CONTENTS are, and a caller's rectangle is the bound. The empty-image sentinel above stays the no-opinion
	 * exception, so "an image cell with no image" and "an image cell with an image" remain distinguishable. */
	{
		CGFloat pad = NS_CELL_CONTENT_PADDING + ((_bordered || _bezeled) ? NS_CELL_BORDER_INSET : 0.0);
		NSSize content = NSZeroSize;

		if (_type == NSTextCellType) {
			/* **AND IT MEASURES `-cg_contentText`, WHICH IS THE ONE DOOR THAT ANSWERS WHAT THIS CELL SHOWS.** This read
			 * `_title` directly, which is right for every cell whose text is a LABEL and wrong for every cell whose text
			 * is a VALUE — and a text field is the second kind. MEASURED, that is why a field cell made with a string
			 * measured nothing, and why one whose string arrived afterwards measured 19.61 points with two words in it. */
			NSString *text = [self cg_contentText];

			if (text != nil) {
				id font = [self fn_cellDrawFont];
				NSDictionary *attributes = (font != nil)
					? [NSDictionary dictionaryWithObject:font forKey:NSFontAttributeName]
					: [NSDictionary dictionary];

				content = [text sizeWithAttributes:attributes];
			}
		} else if (_image != nil) {
			content = [_image size];
		}
		content.width += 2.0 * pad;
		content.height += 2.0 * pad;
		if (content.width > aRect.size.width) {
			content.width = aRect.size.width;
		}
		if (content.height > aRect.size.height) {
			content.height = aRect.size.height;
		}
		return content;
	}
}

- (void)calcDrawInfo:(NSRect)aRect
{
	/* **THE EMPTY BODY IS THE CONTRACT, NOT AN OMISSION** — Apple's sentence is "the default implementation does
	 * nothing", and a control calls this "before display" once a cell has been marked modified, so what matters is that
	 * the call is ANSWERED. The rect is not read: a subclass recalculates ITS OWN cached sizes and this class keeps
	 * none, computing `-cellSize` on demand instead — which is exactly why the door can ignore its argument and still
	 * be right, and why the probe checks that it changes nothing rather than that it computes something. */
}

/* ---- AND THE THREE TRACKING HOOKS ---------------------------------------------------------------------------- */

/* **THE FIRST TWO ANSWER THE SAME FLAG AND THE THIRD ANSWERS NOTHING, WHICH IS THE WHOLE FAMILY.** Apple's sentences
 * are quoted at the declarations in the header; what is worth repeating here is the ONE READING this tier chooses,
 * because it is the only place in the family where the documentation leaves a choice: `-startTrackingAt:inView:`'s
 * "or when the mouse is dragged" is read as THE ACTION MASK (§A10bc's `-sendActionOn:`), not as a restatement of
 * `continuous` — a cell whose mask contains `NSLeftMouseDraggedMask` is a cell set to send its action on drags, which
 * is what "respond when the mouse is dragged" says. The probe takes all three states, so the reading is pinned. */
- (BOOL)startTrackingAt:(NSPoint)startPoint inView:(NSView *)controlView
{
	/* Neither point nor view is read: what the door answers is a question about the CELL's settings, and Apple's
	 * sentence names them. See appkit-plan.md §A10bq. */
	if (_continuous) {
		return YES;
	}
	return (_actionMask & NSLeftMouseDraggedMask) != 0;
}

- (BOOL)continueTracking:(NSPoint)lastPoint at:(NSPoint)currentPoint inView:(NSView *)controlView
{
	/* **ONE FLAG AND NO AMBIGUITY, WHICH IS WHY THIS DOOR IS THE SHORT ONE**: "the default implementation returns true
	 * if the cell is set to continuously send action messages to its target when the mouse button is down or the mouse
	 * is being dragged; otherwise false". A cell that is not continuous therefore ENDS the drag on the first dragged
	 * event — the one-shot button's behaviour — and the two points are left unread for the subclass that needs them. */
	return _continuous;
}

- (void)stopTracking:(NSPoint)lastPoint at:(NSPoint)stopPoint inView:(NSView *)controlView mouseIsUp:(BOOL)flag
{
	/* **THE EMPTY BODY IS THE CONTRACT**: "the default NSCell implementation of this method does nothing", and the loop
	 * invokes it "when the cursor has left the bounds of the receiver or the mouse button goes up" — which is why
	 * `mouseIsUp` exists and why a subclass reads it. Nothing is read here because nothing is promised here, and the
	 * door is DECLARED and ANSWERED rather than left out: it is the one an `NSCell` subclass is expected to implement. */
}

/* ---- AND THE TWO DOORS THAT ANSWER FROM WHAT THE CELL HOLDS --------------------------------------------------- */

- (NSComparisonResult)compare:(id)otherCell
{
	/* **APPLE'S SENTENCE HAS THREE CLAUSES AND THE PROBE TAKES ONE PAIR OF CELLS PER CLAUSE** — the whole reading is at
	 * the declaration in the header; what belongs HERE is the one decision the sentence leaves open. */
	if (otherCell == nil || ![otherCell isKindOfClass:[NSCell class]]) {
		/* APPLE: the other object "must be of type NSCell; if it is not, this method raises NSBadComparisonException",
		 * AND THE NAME RAISED IS THE APPKIT'S OWN CONSTANT — `NSErrors.h`, the file the ledger's row for the name
		 * carries, which is why this tree grew that header rather than inventing a name here. A nil falls under the
		 * same condition and is RAISED FOR rather than ordered against: Apple calls nil's behaviour "undefined and may
		 * change in future versions of macOS", and there is no fourth answer to a three-valued question. */
		[NSException raise:NSBadComparisonException format:@"-compare: needs an NSCell, not another kind of object"];
		return NSOrderedSame;	/* UNREACHABLE — `-raise:` does not return; the line exists because a compiler cannot
					 * know that, and a door that returned nothing would be undefined behaviour instead. */
	}
	/* AND THE COMPARISON ITSELF IS A DOOR THIS TREE ALREADY SHIPS — `NSString`'s `-caseInsensitiveCompare:` — so the
	 * "disregarding case" clause is a CALL rather than a reimplementation of a folding table, which is the whole reason
	 * this door is four lines and the reason §A10bm's formatter matters to it: the strings compared are what
	 * `-stringValue` answers, so a cell with a formatter orders by the text its formatter produces. */
	return [[self stringValue] caseInsensitiveCompare:[(NSCell *)otherCell stringValue]];
}

- (id)menuForEvent:(NSEvent *)event inRect:(NSRect)cellFrame ofView:(NSView *)view
{
	/* **ONE CALL, AND THE NIL CASE NEEDS NO BRANCH OF ITS OWN**: "the default implementation gets the value of the
	 * `menu` property and returns `nil` if no menu has been set" — and a cell with no menu answers nil from `-menu`
	 * already, so a second test here would be a branch that could only agree. THE EVENT AND THE RECT ARE UNREAD because
	 * that is what makes this an override point: "subclasses can override to customize the returned menu according to
	 * the event received and the area in which the mouse event occurs", and the base cell has no opinion about either. */
	return _menu;
}

/* ---- AND THE ATTRIBUTED-STRING PAIR -------------------------------------------------------------------------- */

- (NSAttributedString *)attributedStringValue
{
	/* **THE VALUE ITSELF WHEN THE VALUE IS ONE, AND THE TIER'S EMPTY ANSWER WHEN IT IS NOT.** The synthesis branch is
	 * refused BY NAME at the declaration in the header (the font, the paragraph style, and an attribute name Apple does
	 * not publish); what matters HERE is that a caller can tell the refusal from an empty string, which is why this
	 * answers nil rather than `@""` — the distinction §A10bp's sentinels were chosen for, one class of value over. */
	if ([_objectValue isKindOfClass:[NSAttributedString class]]) {
		return (NSAttributedString *)_objectValue;
	}
	return nil;
}

- (void)setAttributedStringValue:(NSAttributedString *)obj
{
	/* **THE COPY IS MADE WITH `-initWithAttributedString:` RATHER THAN `-copy`, AND THAT IS A MEASURED FACT ABOUT THIS
	 * TREE RATHER THAN A PREFERENCE**: `NSAttributedString` DECLARES `<NSCopying>` and DOES NOT IMPLEMENT
	 * `-copyWithZone:`, so `-copy` on this runtime would raise `doesNotRecognizeSelector:` — a crash where a copy was
	 * meant. Apple declares the property `@NSCopying`, so a copy is what this door owes, and the initialiser that takes
	 * an attributed string is how this tier makes one. */
	NSAttributedString *held = [[NSAttributedString alloc] initWithAttributedString:obj];

	[self setObjectValue:held];
	[held release];
	/* AND THE CONVERSION IS THE SECOND DUTY OF THE SAME SENTENCE — "if the receiver is not a text-type cell, it is
	 * converted to one before the value is set" — performed in that order, so a cell that was null IS text by the time a
	 * caller can ask about it. THE TITLE IS NOT TOUCHED, unlike §A10bi's designated initialisers: this door is not
	 * MAKING a cell, it is setting a value, and the sentence names only the kind. */
	if (_type != NSTextCellType) {
		_type = NSTextCellType;
	}
	/* APPKIT-REFUSE: the third clause of the same documentation — "if the cell has a formatter but the formatter does
	 * not understand the attributed string, the formatter marks the cell's object as invalid" — has no home in this
	 * tier: `-hasValidObjectValue` answers "is there a value" (§A10az) and nothing here can mark an object invalid.
	 * Named rather than half-built, and §A10bs records the divergence rather than leaving it to be discovered. */
}

/* ============================================================================================ *
 * AND THE INK, WHICH THIS CLASS NOW HAS: A FONT, THREE RECTS, AND TWO DOORS THAT PAINT.          *
 * ============================================================================================ */

- (id)font
{
	return _font;
}

- (void)setFont:(id)font
{
	/* RETAINED, THIS TREE'S RULE FOR A FONT — see the header. The one owned thing this slice adds. */
	if (font != _font) {
		id held = [font retain];

		[_font release];
		_font = held;
	}
}

/* THE FACE A TITLE IS DRAWN IN: the cell's own font, or the system font at the system's size. A nil `-font` is the
 * documented "the default", and the default is the system font — the SAME door `NSMenuItemCell` uses, so a control
 * with no font does not come out in a different face from a menu row two classes over. */
- (id)fn_cellDrawFont
{
	id font = _font;

	if (font == nil) {
		font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
	}
	return font;
}

/* ---- THE THREE RECTS, WITH THIS TIER'S NUMBERS ------------------------------------------------ */

/* **AND THE ANCHOR IS THE FRAME'S BOTTOM-LEFT CORNER IN THE SPACE A WINDOW FRAME LIVES IN.** Three spaces are in play
 * and only one arithmetic gets them in the right order; the header carries why it is one door rather than two copies.
 * NO WINDOW IS NOT A REFUSAL: `NSMenu`'s own note says a session with no reachable display is still a session — its
 * state is real and only its ink is missing — so the point falls back to the frame's own corner and every behaviour
 * above this stays testable offscreen. */
- (NSPoint)cg_popUpAnchorForFrame:(NSRect)cellFrame inView:(id)controlView
{
	id window = nil;

	if (controlView != nil && [controlView respondsToSelector:@selector(window)]) {
		window = [controlView window];
	}
	if (window != nil && [controlView respondsToSelector:@selector(convertPoint:toView:)]) {
		NSRect frame = [window frame];
		NSPoint corner = [controlView convertPoint:NSMakePoint(NSMinX(cellFrame), NSMinY(cellFrame)) toView:nil];

		return NSMakePoint(frame.origin.x + corner.x, frame.origin.y + corner.y);
	}
	return NSMakePoint(NSMinX(cellFrame), NSMinY(cellFrame));
}

- (NSRect)drawingRectForBounds:(NSRect)theRect
{
	/* THE BORDER'S AIR IS TAKEN ONLY WHEN THERE IS A BORDER TO TAKE IT FOR: an unbordered cell draws over its whole
	 * bounds, which is what a table cell and a menu row want. */
	if (_bordered || _bezeled) {
		return NSInsetRect(theRect, NS_CELL_BORDER_INSET, NS_CELL_BORDER_INSET);
	}
	return theRect;
}

- (NSRect)titleRectForBounds:(NSRect)theRect
{
	/* A TEXT CELL'S TITLE TAKES THE DRAWING RECT less the content padding. A cell of any other kind has no title to
	 * place and answers the EMPTY rect, which is Apple's own "does nothing" and — unlike a plausible inset — a
	 * something a caller can tell apart from a real rectangle. */
	if (_type != NSTextCellType) {
		return NSZeroRect;
	}
	return NSInsetRect([self drawingRectForBounds:theRect], NS_CELL_CONTENT_PADDING, NS_CELL_CONTENT_PADDING);
}

- (NSRect)imageRectForBounds:(NSRect)theRect
{
	/* **THE IMAGE'S RECT IS CENTRED ON ITS OWN SIZE RATHER THAN FILLING THE DRAWING RECT.** "Typically offset to make
	 * room for the cell border" is Apple's whole sentence; what an image cell actually needs is that offset AND a box
	 * its picture sits in the middle of, because a 16-point icon stretched into a 200-point button is not an icon. */
	NSRect rect = [self drawingRectForBounds:theRect];
	NSSize size = (_image != nil) ? [_image size] : NSZeroSize;

	return NSMakeRect(NSMidX(rect) - size.width / 2.0, NSMidY(rect) - size.height / 2.0, size.width, size.height);
}

/* ---- AND THE TWO DOORS THAT PAINT ------------------------------------------------------------- */

- (void)drawWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	/* **THE FACE, THEN THE CONTENTS — APPLE'S SPLIT, IN APPLE'S ORDER.** A bordered or bezeled cell paints its border
	 * and its background here; everything else belongs to the interior below, which is why a subclass that changes
	 * only the face overrides THIS door and inherits the other. THE HIGHLIGHTED STATE TAKES THE PLATFORM'S ACCENT,
	 * which is what "this control is being used" means everywhere in this tier — the same accent a pressed button, a
	 * menu's chip, a slider's fill and a selection wear. (This said the state DARKENS the face rather than changing
	 * its colour, which was never what the line below did: it swapped the face for the era's blue.) */
	if (_bezeled) {
		NSBezierPath *face = [NSBezierPath bezierPathWithRoundedRect:cellFrame xRadius:4.0 yRadius:4.0];

		[(_highlighted ? [NSColor cg_accentColor] : [NSColor controlColor]) setFill];
		[face fill];
		[[NSColor controlDarkShadowColor] setStroke];
		[face setLineWidth:1.0];
		[face stroke];
	} else if (_bordered) {
		NSBezierPath *edge = [NSBezierPath bezierPathWithRect:cellFrame];

		[[NSColor controlDarkShadowColor] setStroke];
		[edge setLineWidth:1.0];
		[edge stroke];
	}
	[self drawInteriorWithFrame:cellFrame inView:controlView];
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	NSColor *ink = _enabled ? [NSColor controlTextColor] : [NSColor disabledControlTextColor];

	(void)controlView;
	/* THE IMAGE FIRST, so a title that overlaps it lands ON TOP rather than under; then the title. */
	if (_image != nil) {
		NSRect where = [self imageRectForBounds:cellFrame];

		if (where.size.width > 0.0 && where.size.height > 0.0) {
			[_image drawInRect:where];
		}
	}
	if (_type == NSTextCellType && _title != nil && [_title length] > 0) {
		NSRect rect = [self titleRectForBounds:cellFrame];
		id font = [self fn_cellDrawFont];
		NSDictionary *attributes;
		NSSize text;
		CGFloat x;

		if (font == nil || rect.size.width <= 0.0 || rect.size.height <= 0.0) {
			return;
		}
		attributes = [NSDictionary dictionaryWithObjectsAndKeys:font, NSFontAttributeName, ink,
			      NSForegroundColorAttributeName, nil];
		text = [_title sizeWithAttributes:attributes];
		x = rect.origin.x;
		if (_alignment == NSCenterTextAlignment) {
			x = rect.origin.x + (rect.size.width - text.width) / 2.0;
		} else if (_alignment == NSRightTextAlignment) {
			x = rect.origin.x + rect.size.width - text.width;
		}
		if (x < rect.origin.x) {
			x = rect.origin.x;
		}
		/* VERTICALLY CENTRED ON THE FONT'S ASCENT AND DESCENT BAND, not on the measured line — the same arithmetic,
		 * and the same measurement, `NSMenuItemCell -drawTitleWithFrame:inView:` uses one class over. */
		{
			CGFloat ascent = [font ascender];
			CGFloat descent = (CGFloat)fabs((double)[font descender]);
			/* **ROUNDED UP FOR THE SAME REASON `NSButtonCell` ROUNDS ITS BAND**: a rect exactly as tall as a
			 * fractional band clips the last row of the frame it is drawn into. See that file for the measurement. */
			CGFloat band = ceil(ascent + descent);
			CGFloat baseline = rect.origin.y + (rect.size.height - band) / 2.0 + descent;

			[_title drawInRect:NSMakeRect(x, baseline - descent, ceil(text.width), band) withAttributes:attributes];
		}
	}
}

@end

/* THE OBJECT A CELL CARRIES FOR ITS CALLER, which the header has declared since the cell family landed and never
 * stored. It is a plain retained association: this tier has no binding controllers, so nothing reads it — but a caller
 * that SETS it must be able to read it back, and before this pair `-setRepresentedObject:` was an unrecognized
 * selector, which is a crash rather than a gap. */
@implementation NSCell (AGRepresentedObject)

- (id)representedObject
{
	return _representedObject;
}

- (void)setRepresentedObject:(id)object
{
	if (_representedObject != object) {
		[object retain];
		[_representedObject release];
		_representedObject = object;
	}
}

@end
