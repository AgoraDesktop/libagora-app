/*
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
/*
 * NSSearchFieldCell.h — a field cell with two ornaments: the magnifier that opens the recents and the circle that
 * clears the field.
 *
 * **THE ORNAMENTS ARE CELLS, AND THE HOST IS A FIELD CELL.** Apple's shape is not "draw two glyphs in the field": a
 * search field cell owns a `-searchButtonCell` and a `-cancelButtonCell`, each an `NSButtonCell`, and a caller may
 * replace either or reset it to the default. The host computes their rectangles, draws them over its own face and
 * answers their clicks, which is why the geometry is published (`-searchButtonRectForBounds:`,
 * `-cancelButtonRectForBounds:`, `-searchTextRectForBounds:`) rather than hidden in the drawing.
 *
 * **THE TEXT RECT IS THE FACE MINUS THE ORNAMENTS, AND THE CANCEL SLOT IS ALWAYS RESERVED.** A cancel button that
 * appeared with the first typed character would otherwise move the editor under the caret on that same keystroke.
 * So the slot is part of the layout from the beginning, the button is simply not drawn until there is text, and the
 * editor can be placed before anybody has typed anything.
 *
 * **THE RECENTS ARE A MENU BUILT FROM A TEMPLATE, AND THE TAGS SAY WHERE THE PIECES GO.** `-searchMenuTemplate` is
 * Apple's opt-in: it holds placeholder items tagged `NSSearchFieldRecentsTitleMenuItemTag`,
 * `NSSearchFieldRecentsMenuItemTag`, `NSSearchFieldClearRecentsMenuItemTag` and
 * `NSSearchFieldNoRecentsMenuItemTag`, and the cell builds the menu a person actually sees by placing the recents,
 * the clear item or the "no recents" item where those placeholders are. With no template the cell tracks no recents
 * UI at all, which is the SDK's own sentence. The list itself is the cell's, bounded by `-maximumRecents`, and a
 * `-recentsAutosaveName` stores it in `NSUserDefaults` under that name.
 *
 * **TYPING SENDS THE CONTROL'S ACTION, WITH THREE RULES.** `-sendsWholeSearchString` means "only on Return or the
 * magnifier"; otherwise a change schedules a short timer and sends when it fires, unless
 * `-sendsSearchStringImmediately` asks for every keystroke. The action sent is the CONTROL's target/action, because a
 * caller writes its handler against the field; the ornament cells' own target/action is this cell, so replacing one
 * does not disturb the search action.
 *
 * Written from `NSSearchFieldCell.h` in the MacOSX10.6 SDK.
 */
#ifndef APPKIT_NSSEARCHFIELDCELL_H
#define APPKIT_NSSEARCHFIELDCELL_H

#import <AppKit/NSTextFieldCell.h>

@class NSArray;
@class NSButtonCell;
@class NSMenu;
@class NSMutableArray;
@class NSTimer;
@class NSView;

NS_ASSUME_NONNULL_BEGIN

/* **THE FOUR TAGS, WITH APPLE'S OWN VALUES.** They are `#define`s rather than an enum in the SDK, and a caller's
 * template is built by setting `-tag` on ordinary items. */
#define NSSearchFieldRecentsTitleMenuItemTag	1000
#define NSSearchFieldRecentsMenuItemTag		1001
#define NSSearchFieldClearRecentsMenuItemTag	1002
#define NSSearchFieldNoRecentsMenuItemTag	1003

@interface NSSearchFieldCell : NSTextFieldCell <NSSecureCoding>
{
	/* **THE THREE FLAGS THE SDK PACKS INTO A BITFIELD, KEPT AS THE VALUES THEY ARE.** A bitfield here would save
	 * nothing worth the code that reads it, and the era's limits are enforced in the setters where a caller can see
	 * them (0...254 for the recents, and -1 meaning "the default"). */
	BOOL _sendsWholeSearchString;
	BOOL _sendsSearchStringImmediately;
	NSInteger _maximumRecents;
	/* **THE TWO ORNAMENT CELLS ARE RETAINED, AND SO IS THE ONE A CALLER HANDED OVER.** The host owns them; a
	 * caller that asked for one by name gets the host's object back, which is what makes "modify the search button
	 * cell" a thing a person can do rather than a copy nobody draws. */
	NSButtonCell *_searchButtonCell;	/* RETAINED */
	NSButtonCell *_cancelButtonCell;	/* RETAINED */
	NSMenu *_searchMenuTemplate;		/* RETAINED */
	NSString *_recentsAutosaveName;		/* RETAINED (a copy) */
	NSMutableArray *_recentSearches;	/* RETAINED */
	NSTimer *_partialStringTimer;		/* RETAINED while pending */
	BOOL _cancelVisible;
	/* **AND WHETHER THE CURRENT STRING CHANGE CAME FROM CODE RATHER THAN A KEY.** A programmatic value — a chosen
	 * recent, a clear, a caller's `-setStringValue:` — is written through `-setStringValue:`, which tells a live
	 * editor and therefore produces the same change notification a keystroke does. The flag keeps that notification
	 * from sending the search a second time: the door that wrote the value sends once, deliberately. */
	BOOL _programmaticChange;
}

/* ---- THE ORNAMENTS ---------------------------------------------------------------------------------- */

/* **THE TWO CELLS, READ AND REPLACED.** `-setSearchButtonCell:` and `-setCancelButtonCell:` take ownership of what
 * they are given and point its target at this cell, so a custom cell's click reaches `-search:`/`-cancel:` without the
 * caller wiring it. `-reset…` builds the default again — a cell that draws the platform's glyph — and restores that
 * target/action. Passing nil clears the ornament, which is Apple's own "set or clear". */
- (nullable NSButtonCell *)searchButtonCell;
- (void)setSearchButtonCell:(nullable NSButtonCell *)cell;
- (nullable NSButtonCell *)cancelButtonCell;
- (void)setCancelButtonCell:(nullable NSButtonCell *)cell;
- (void)resetSearchButtonCell;
- (void)resetCancelButtonCell;

/* **AND THE THREE RECTANGLES, WHICH ARE THE LAYOUT'S OWN ANSWER.** The text rect is what the editor and the drawn
 * string both use; the two ornament rects are where the cells draw and where a press is hit-tested. They are public
 * because Apple publishes them — a caller that replaces an ornament with a different size needs the same arithmetic,
 * and a test can read a rectangle without reading pixels. */
- (NSRect)searchTextRectForBounds:(NSRect)rect;
- (NSRect)searchButtonRectForBounds:(NSRect)rect;
- (NSRect)cancelButtonRectForBounds:(NSRect)rect;

/* ---- THE RECENTS ------------------------------------------------------------------------------------ */

/* **A TEMPLATE IS THE OPT-IN, AND NIL MEANS "NO RECENTS UI".** The menu returned by `-cg_searchMenu` is built from
 * it on demand rather than stored, so changing the recents or the template changes the next menu without a second
 * copy to keep in step. */
- (void)setSearchMenuTemplate:(nullable NSMenu *)menu;
- (nullable NSMenu *)searchMenuTemplate;

/* **THE LIST ITSELF IS BOUNDED AND OPTIONALLY SAVED.** `-setMaximumRecents:` clamps to 0...254 (and -1 restores the
 * default of ten); a shorter limit truncates what is already there. `-setRecentsAutosaveName:` both stores the name
 * and loads what is under that key, so a field that is built again remembers its searches. An empty string is a real
 * search only if it is non-empty; the cell drops anything that is not a string. */
- (void)setMaximumRecents:(NSInteger)maxRecents;
- (NSInteger)maximumRecents;
- (void)setRecentSearches:(nullable NSArray *)searches;
- (NSArray *)recentSearches;
- (void)setRecentsAutosaveName:(nullable NSString *)string;
- (nullable NSString *)recentsAutosaveName;

/* ---- WHAT TYPING MEANS ------------------------------------------------------------------------------ */

- (void)setSendsWholeSearchString:(BOOL)flag;
- (BOOL)sendsWholeSearchString;
- (void)setSendsSearchStringImmediately:(BOOL)flag;
- (BOOL)sendsSearchStringImmediately;

/* ---- THE TWO ACTIONS THE ORNAMENTS SEND ------------------------------------------------------------- */

/* **THE MAGNIFIER'S CLICK EITHER SHOWS THE TEMPLATE'S MENU OR SENDS THE SEARCH.** With a template the menu is built
 * and popped up under the button; with none there is nothing to show, so the click is the "search now" gesture and
 * sends the control's action. The button adds the current term to the recents first, because that is what a person
 * pressing it is confirming. */
- (void)search:(nullable id)sender;

/* **AND THE CANCEL CLICK CLEARS, HIDES ITSELF AND SENDS.** The field is empty afterwards, which is a real search
 * result, so the action goes out — Apple's behaviour, and the reason a live filter returns to its unfiltered state
 * without a second gesture. */
- (void)cancel:(nullable id)sender;

/* ---- THE PROBE'S DOORS ------------------------------------------------------------------------------- */

/* **THE STATE AND THE MENU A PROBE CANNOT READ ANY OTHER WAY.** A test may not wait for a timer or pop up a menu (the
 * second is a blocking tracking loop), so the pending timer and the built menu are readable by name, and
 * `-cg_handleClickAtPoint:inView:` is the same hit test a press runs — the press path itself converts the event and
 * calls it. */
- (BOOL)cg_isCancelVisible;
- (nullable NSTimer *)cg_partialStringTimer;
- (nullable NSMenu *)cg_searchMenu;
- (BOOL)cg_handleClickAtPoint:(NSPoint)point inView:(nullable NSView *)view;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSSEARCHFIELDCELL_H */
