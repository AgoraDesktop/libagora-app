/*
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
/*
 * NSMenu.h — a menu as a LIST OF ITEMS (stage D).
 *
 * THIS IS THE CONTAINER HALF OF NSMenu, AND IT IS THE HALF THAT HAS A READER FOR EVERY FIELD. The class is
 * being taken in slices the way NSColor was, because its eighty-five rows are four different jobs rather than
 * one surface: THE LIST (this unit — add, insert, remove, find, and the title), THE GEOMETRY (size, minimum
 * width, `-sizeToFit`, the font), THE TRACKING AND POPUP MACHINERY (`-popUpMenuPositioningItem:…`,
 * `-cancelTracking`, `-update`, `-performKeyEquivalent:`, the highlighted item, the attachments) and THE
 * REPRESENTATION OBJECTS (the three pairs Apple lets a caller swap). The last two are also where the plan's own
 * note points: "NSMenuView/NSMenuItemView (the drawing half)".
 *
 * AND THE RULE THAT DECIDED THE SPLIT IS THE ONE THIS SESSION KEEPS MEETING: A FIELD WITH NO READER IS NOT
 * SHIPPED. `-autoenablesItems` is read by `-update`'s enabling walk, `-highlightedItem` by the tracking loop,
 * `-tornOff` by the tear-off machinery, `-propertiesToUpdate` by the update machinery — so all four stay OWED
 * rather than being stored here and consulted by nobody, and each is named in this header as such.
 *
 * **AND THIS CLASS IS WHERE `NSMenuItem`'S TWO READWRITE DOORS GET THEIR CALLER**, which is the other reason the
 * list half lands first: `-setMenu:` and `-setParentItem:` were declared readwrite there (a stated deviation,
 * since Apple declares them readonly) precisely because the OWNER sets them, and the owner is this class —
 * `-insertItem:atIndex:` is what tells an item which menu holds it. A menu that stored its items without
 * telling them would be a container whose contents do not know where they are, and the item-side walk
 * `-isHiddenOrHasHiddenAncestor` would have nothing to climb.
 *
 * THE PARENT/CHILD LINKS ARE BOTH DIRECTIONS AND NEITHER RETAINS: a menu RETAINS its items (they are its
 * contents) and an item does NOT retain its menu or its parent (they point back — the header of NSMenuItem says
 * why). `-setSupermenu:` exists for the same reason `-setMenu:` does: the item's submenu needs to know which
 * item holds it, and only this class knows.
 */
#ifndef APPKIT_NSMENU_H
#define APPKIT_NSMENU_H

#import <Foundation/Foundation.h>
#import <AppKit/NSMenuItem.h>

NS_ASSUME_NONNULL_BEGIN

/* THE PROPERTY-CHANGE FLAGS, AND THEIR VALUES ARE THE ERA'S — read out of the 10.6 header rather than recalled,
 * which matters here because they are a BIT SET a caller combines: title, attributed title, key equivalent,
 * image, enabled and the accessibility description, in that order. `NSMenuPropertyItemImage` is bit 3 and
 * `…Enabled` bit 4, which is the artefact's own ordering and not the obvious one. */
enum {
	NSMenuPropertyItemTitle = 1 << 0,
	NSMenuPropertyItemAttributedTitle = 1 << 1,
	NSMenuPropertyItemKeyEquivalent = 1 << 2,
	NSMenuPropertyItemImage = 1 << 3,
	NSMenuPropertyItemEnabled = 1 << 4,
	NSMenuPropertyItemAccessibilityDescription = 1 << 5
};
typedef NSUInteger NSMenuProperties;

/* THE SEVEN NOTIFICATIONS THE CLASS ANNOUNCES, each a NAME THAT IS ITS OWN VALUE — this tree's convention for a
 * constant whose whole job is to be a name (NSNib's keys, NSInterfaceStyleDefault). */
extern NSString *NSMenuDidAddItemNotification;
extern NSString *NSMenuDidChangeItemNotification;
extern NSString *NSMenuDidRemoveItemNotification;
extern NSString *NSMenuDidSendActionNotification;
extern NSString *NSMenuWillSendActionNotification;
extern NSString *NSMenuDidBeginTrackingNotification;
extern NSString *NSMenuDidEndTrackingNotification;

/* **THE INFORMAL PROTOCOL AN ITEM'S TARGET IMPLEMENTS TO VALIDATE ITSELF — APPLE'S OWN `NSMenuValidation`.**
 * `-update`'s auto-enabling walk asks it when it can: a target that implements `-validateMenuItem:` decides
 * whether its item is enabled, AND MAY CHANGE THE ITEM WHILE IT ANSWERS — setting its state, its title, its
 * image — which is how a Check for Updates item shows a checkmark and how a title names the thing it will act on.
 * That second half is the reason the walk must call it rather than merely reading `-respondsToSelector:` of the
 * action. It is `@optional` because a target that does not implement it is the ordinary case, and `-update` asks
 * `-respondsToSelector:` first. */
@protocol NSMenuValidation <NSObject>
@optional
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem;
@end

@interface NSMenu : NSObject <NSSecureCoding>
{
	NSString *_title;			/* RETAINED (a copy of what was set) */
	NSMutableArray *_items;			/* RETAINED: the menu OWNS its items */
	/* NOT RETAINED, AND BOTH ARE THE TREE'S UPWARD POINTERS: a submenu knows the item that holds it and an
	 * item knows the menu that holds it, and neither may own the other or the tree is a cycle. */
	id _supermenu;				/* the item whose submenu this menu is, or nil */
	/* THE GEOMETRY'S FOUR FIELDS. `_font` is RETAINED (a menu owns the font it was given); the other three are
	 * plain values, and `_size` is what a CALLER set rather than what the menu answers — the answer is the floor
	 * and the state column applied on top of it, which is where `-showsStateColumn` gets its reader. */
	NSSize _size;
	CGFloat _minimumWidth;
	BOOL _showsStateColumn;
	id _font;
	/* AND THE TWO THE UPDATE WALK READS, plus the mask it hands its delegate: `_delegate` is NOT retained (the
	 * tree's rule for a delegate — an owner that retained its delegate could not be freed while the delegate is
	 * alive), and `_autoenablesItems` is the switch `-update` consults before it touches an item. */
	id _delegate;
	BOOL _autoenablesItems;
	NSMenuProperties _propertiesToUpdate;
	/* AND THE ONE SWITCH THAT IS NEITHER STORED-AND-IGNORED NOR OWED, because its reader is in this class: a menu
	 * that is asked to stay quiet while a caller makes a batch of edits consults this in the very door that would
	 * announce them. It starts ON, which is Apple's default and the only useful one — silence by default would
	 * make a menu that never tells anyone anything. */
	BOOL _menuChangedMessagesEnabled;
	/* AND THE TRACKING SESSION'S FOUR FIELDS, which exist because THAT SESSION NOW DOES. `_trackingWindow` is the
	 * borderless window a popped-up menu IS; `_tracking` says whether one is up; `_highlightedItem` is the row the
	 * pointer is over — written by the tracking step, READ BY THE PAINT; and `_trackingFrame` is the geometry the
	 * session hit-tests against, kept here rather than read back off the window because a session that could not
	 * get a window still tracks. */
	id _trackingWindow;
	/* **THE MENU'S OWN VIEW, WHICH IS WHAT THE TRACKING WINDOW'S CONTENT IS.** Not the menu's "representation"
	 * in Apple's sense — that door is separate — but the thing that draws the rows: a session that hand-painted
	 * its panel could never reach an output, because A WINDOW PRESENTS ONLY IN ITS OWN DRAW PATH. */
	id _menuView;
	BOOL _tracking;
	id _highlightedItem;
	NSRect _trackingFrame;
	/* AND THE ONE POINTER THE SUBMENU NEEDS: WHICH SUBMENU IS OPEN, OR NIL. The child's own window, frame and
	 * highlight live in the CHILD (it is an NSMenu whose session is its own), so the parent remembers exactly one
	 * thing about it — WHICH ONE IT IS — and everything else is asked of the child. Not retained: the ITEM that
	 * holds the submenu owns it, and a parent that owned it too would keep a menu alive after its item let go. */
	id _openSubmenu;
	/* AND THE TEAR-OFF FLAG, which is the last piece of the session's state: a menu that has been TORN OFF stays up
	 * instead of dismissing. */
	BOOL _tornOff;
	/* **AND WHETHER THE PRESS THAT OPENED THIS SESSION HAS BEEN RELEASED YET.** A menu opened by a CLICK stays
	 * open after the button comes up — that is what clicking a menu bar title does on the Mac, and what a
	 * right-click on a context menu does — so the FIRST release in a session is the gesture that opened it and is
	 * consumed. Without this the menu opened on press and closed on release, which reads as "the highlight only
	 * shows while the mouse is held down". */
	BOOL _openedByPress;
	/* **WHERE THE PRESS THAT ENDED THE SESSION LANDED, WHEN ONE DID.** A menu bar has to know this: clicking one
	 * title and then another must SWITCH menus, and the click that says "that one" is captured by the first menu's
	 * tracking loop — the loop owns the events. So the session records the point it was dismissed at, and the bar
	 * reads it back and opens whatever title is underneath. WITHOUT THIS THE SECOND CLICK IS SIMPLY EATEN, which is
	 * what "the menus do not work" is: press File, press Edit, and all you get is File's menu closing. */
	NSPoint _dismissedAt;
	BOOL _hasDismissedAt;
	/* **AND WHICH VIEW DRAWS THIS MENU'S ROWS.** Every menu in this tier is drawn by `NSMenuView`, which hard-coded
	 * it: the class was named at the one place the view is made, so a caller with a different idea about a row — a
	 * COMBO BOX'S LIST, whose rows are a list's and whose held row is marked — had no way to say so. `Nil` means the
	 * default, so a menu that nobody has told behaves exactly as before. */
	Class _cg_menuViewClass;
	/* **AND WHETHER THE CALLER IS DRIVING THIS SESSION RATHER THAN THE MENU.** One flag, because
	 * `-popUpMenuPositioningItem:` already does everything a session's beginning needs: the window, the view, the
	 * first repaint, the notification. With this set it RETURNS at the point the loop would start, which is exactly
	 * "begin a session without running it" and not one line of duplicate work. */
	BOOL _callerDrives;
}

/* ============================================================================================ *
 * THE TRACKING SESSION'S DOORS — the fields above are its state, these are what drives it.        *
 * ============================================================================================ */

/* **THE SESSION IS BOUNDED AND STEPPED, AND THE REASON IS NESTING RATHER THAN A MISSING LOOP.** This tier HAS an
 * application run loop — `NSApplication`'s `-run` — and the popup uses it when it is the OUTERMOST session; what a
 * stepped session buys is that A MENU OPENED FROM A MENU NEED NOT NEST ONE, since Apple's own tracking is a single
 * loop that walks between the windows. So the step is that loop's body and its only copy: the popup drives it when
 * there is a loop to drive it, and a caller without one drives it itself.
 *
 * **(THIS PARAGRAPH USED TO SAY THE TIER HAD NO RUN LOOP AND THAT `NSApplication` HAD NO `-run`. IT WAS WRONG —
 * `-run` is at NSApplication.m:377 — and it is corrected HERE rather than only in the plan, because a false claim
 * in a header is read by whoever is editing the code. The record of the mistake is appkit-plan.md §A10ag.)**
 *
 * AND ONE MENU IS UP AT A TIME, enforced rather than assumed: a menu already tracking REFUSES to begin a second
 * session by name, because the alternative to one at a time is two windows fighting over the pointer. */
@property (nullable, assign) id highlightedItem;
- (void)setHighlightedItem:(nullable id)item;
- (BOOL)cg_trackOneEvent:(nullable id)event;

/* **A MENU THAT HAS BEEN TORN OFF STAYS UP**, which is what this flag means and the whole of what it does: the
 * session consults it in the two places that would otherwise dismiss — a click outside and a pick — so a torn-off
 * menu behaves like the palette it is rather than like a popup. THE WRITER IS OURS (`-cg_setTornOff:`) because
 * Apple's is internal; a menu bar tears a menu off itself to set it, and this tier has no bar yet, which is why the
 * door is a seam rather than a gesture.
 *
 * AND IT IS IMPLEMENTED RATHER THAN STRUCK, WHICH THE ROW BESIDE IT IS NOT: `-tornOff` is marked deprecated in
 * Apple's documentation (it is not even in the 10.6 HEADER — the ledger's row rests on the docs index), and the
 * policy of 2026-09-26 keeps a deprecated item OWED rather than struck so that older applications can be ported.
 * `-allowsContextMenuPlugIns` was struck because it governs a mechanism macOS REMOVED, which is a different thing
 * and draws the other side of that line. */
@property (readonly) BOOL tornOff;
- (void)cg_setTornOff:(BOOL)flag;

/* THE TWO CONSTRUCTORS AND THE ONE FACTORY Apple gives a menu: a title, and the title-less one. */
- (instancetype)initWithTitle:(NSString *)aTitle;
- (instancetype)init;

@property (copy) NSString *title;
@property (nullable, assign, readonly) id supermenu;
/* AND THE DOOR THE SUBMENU NOTICE COMES THROUGH — Apple's own comment says "you should never call this, but you
 * may override it": the MENU that contains the item calls it, which is this class. */
- (void)setSupermenu:(nullable id)supermenu;

/* ============================================================================================ *
 * THE LIST: ADDING, INSERTING, REMOVING, AND FINDING.                                            *
 * ============================================================================================ */

/* THE ADDING PAIR. The plain one takes an item the caller built (which is how a program that wants its own
 * target, image or submenu does it); the other builds one from the three things a caller almost always has. */
- (void)addItem:(NSMenuItem *)newItem;
- (NSMenuItem *)addItemWithTitle:(NSString *)aString
			  action:(nullable SEL)aSelector
		  keyEquivalent:(NSString *)charCode;

/* AND THE INSERTING PAIR, at an index the caller names. AN OUT-OF-RANGE INDEX IS CLAMPED RATHER THAN REFUSED,
 * which is Apple's behaviour and the only useful one: an insertion index is almost always computed from the
 * list itself, so "one past the end" means "append" and a refusal would be noise. */
- (void)insertItem:(NSMenuItem *)newItem atIndex:(NSInteger)index;
- (NSMenuItem *)insertItemWithTitle:(NSString *)aString
			     action:(nullable SEL)aSelector
		      keyEquivalent:(NSString *)charCode
			    atIndex:(NSInteger)index;

/* THE REMOVALS. Removing detaches: the item leaves the list AND is told it has no menu any more, so a caller
 * holding it can put it in another menu without two menus believing they own it. */
- (void)removeItemAtIndex:(NSInteger)index;
- (void)removeItem:(NSMenuItem *)item;
- (void)removeAllItems;

/* THE LIST ITSELF, and the array is a COPY — Apple's own contract for `-itemArray`, and the reason is the same
 * one `+screens` has in NSScreen: a caller must not be able to mutate this menu's contents by holding the
 * answer. */
@property (nullable, readonly, copy) NSArray *itemArray;
@property (readonly) NSInteger numberOfItems;
- (nullable NSMenuItem *)itemAtIndex:(NSInteger)index;

/* THE SIX FINDS, each answering NSNotFound rather than raising when the item is not there — Apple's reading,
 * and the one a menu builder's `if` can use. */
- (NSInteger)indexOfItem:(NSMenuItem *)index;
- (NSInteger)indexOfItemWithTitle:(NSString *)aTitle;
- (NSInteger)indexOfItemWithTag:(NSInteger)aTag;
- (NSInteger)indexOfItemWithRepresentedObject:(nullable id)object;
- (NSInteger)indexOfItemWithSubmenu:(id)submenu;
- (NSInteger)indexOfItemWithTarget:(nullable id)target andAction:(nullable SEL)actionSelector;
- (nullable NSMenuItem *)itemWithTitle:(NSString *)aTitle;
- (nullable NSMenuItem *)itemWithTag:(NSInteger)tag;

/* AND ATTACHING A SUBMENU TO AN ITEM, which is one call rather than two because the two directions have to
 * agree: the item gets the menu AND the menu is told whose submenu it is. APPLE SAYS THE ITEM "MAY NOT BE NIL",
 * AND THIS DOOR ACCEPTS ONE SO THAT IT CAN SAY SO: the annotation is `nullable` because that is what the
 * IMPLEMENTATION does — it refuses a nil item by name rather than crashing on it — which is this tree's standing
 * rule for a nullability annotation, and the door is a better door for being callable with the thing a caller
 * got wrong. */
- (void)setSubmenu:(nullable id)aMenu forItem:(nullable NSMenuItem *)anItem;

/* ============================================================================================ *
 * THE GEOMETRY, AND THE WALK THAT READS THE SWITCHES.                                             *
 * ============================================================================================ */

/* THE SIZE A CALLER SET, AND THE FLOOR UNDER IT. `-size` answers the maximum of what was set and
 * `-minimumWidth` plus the state column's width when `-showsStateColumn` is on — WHICH IS THAT SWITCH'S READER,
 * and the reason it is shipped here rather than left owed: a stored flag with no reader is what this tree
 * refuses. A stated deviation: Apple computes a menu's width from its items and its font, and this tier has no
 * text metrics on this side, so the width is the caller's or the floor and the height is always the caller's. */
@property NSSize size;
@property CGFloat minimumWidth;
@property BOOL showsStateColumn;
/* AND THE FONT, TYPED `id` FOR THE OVER-CREDITING RULE: `NSFont` is a class this duplication has not got, so
 * naming it — even in a forward declaration — would put a row on the ledger's books for a class nobody wrote. */
@property (nullable, assign) id font;

/* `-sizeToFit` IS REFUSED BY NAME for the same missing measurement, and `+menuBarHeight` answers ZERO, which is
 * Apple's own answer for a menu that is NOT in a menu bar — and every menu in this tier is not, because the bar
 * belongs to the desktop and the desktop draws its own chrome (D6). */
- (void)sizeToFit;
+ (CGFloat)menuBarHeight;

/* AND THE TWO THE UPDATE WALK READS, plus the delegate it asks: `-update` is what gives `-autoenablesItems` its
 * reader (an item that names a target is enabled exactly when the target answers its action) and what makes
 * `-propertiesToUpdate` a door with a writer rather than a mask nobody sets. THE DELEGATE IS `id`, NOT
 * `NSMenuDelegate`: that protocol is not in this tree, and a forward declaration of it would be a row claimed for
 * a protocol nobody wrote. */
@property (nullable, assign) id delegate;
@property BOOL autoenablesItems;
@property (readonly) NSMenuProperties propertiesToUpdate;
- (void)update;

/* AND THE SETTERS ARE DECLARED AS WELL AS THE PROPERTIES, one for each property above, WHICH IS NOT REDUNDANT
 * HERE. THE LEDGER HOLDS A ROW FOR EACH SETTER BY NAME, and a property declaration does not put its setter's
 * name into the header text — so six doors implemented in the previous unit were INVISIBLE TO THE INSTRUMENT, and
 * these six lines are what makes them readable. NSBezierPath's header records the same thing about
 * `-setLineDash:count:phase:`; the previous unit's note records it being FORGOTTEN here, which is why it is said
 * twice: a lesson stated once is not a lesson learned. */
- (void)setSize:(NSSize)aSize;
- (void)setMinimumWidth:(CGFloat)width;
- (void)setShowsStateColumn:(BOOL)flag;
- (void)setFont:(nullable id)font;
- (void)setDelegate:(nullable id)anObject;
- (void)setAutoenablesItems:(BOOL)flag;

/* ============================================================================================ *
 * THE TRACKING, THE REPRESENTATIONS AND THE ATTACHMENTS — PRESENT, AND EACH REFUSING BY NAME.     *
 * ============================================================================================ */

/* EVERY DECLARATION BELOW IS A DOOR THIS TIER CANNOT ANSWER YET, AND EACH ONE IS DECLARED AND DEFINED and answers
 * its type's empty value from a body that SAYS WHAT IT NEEDED — the convention stage A's printing family and
 * stage B's `-print` established, and the reason they are here rather than omitted: a caller can compile against
 * Apple's surface and find out what is missing BY NAME, and a row is done when it is shipped or struck, where a
 * named refusal counts as shipped. THE SUBSYSTEM EACH ONE NAMES IS THE TRACKING HALF OF THIS CLASS (a session
 * that can open, draw, track and dismiss a menu), THIS TIER'S DESKTOP (for the bar and the zone pair), or the
 * REPRESENTATION CLASSES (the plan's own note: "the drawing half"). */

/* AND THE ONE DOOR OF THIS HALF THAT IS ANSWERED RATHER THAN REFUSED, SAID FIRST SO THAT THE REST READ AS THE
 * REFUSALS THEY ARE: a menu matches a key equivalent by asking ITS OWN ITEMS — the character and the modifier
 * mask — and the dispatch that follows is the target/action door this class already has, so NO TRACKING SESSION
 * IS NEEDED for it.
 *
 * AND IT IS DECLARED HERE ALSO BECAUSE ITS ABSENCE WAS AN OVER-CREDIT. This header's own introduction, one screen
 * above, SPELLS THIS SELECTOR while listing the tracking half as owed — and A NAME IN A COMMENT SATISFIES A
 * NAME-BASED DECLARATION TEST, so the ledger credited this class with a door it did not have. That is this tree's
 * recorded trap, and it arrived here through a comment written by the unit that was describing the gap. EARNING
 * THE ROW IS THE REPAIR rather than rewording the prose: this door is one the class can genuinely answer, and a
 * ledger argued out of a credit is worth less than one that earned it.
 *
 * THE PARAMETER IS TYPED `id` WHERE APPLE TYPES `NSEvent`, a stated deviation and a small one: this header cannot
 * name AppKit's event class without importing it, and the door asks an event for exactly TWO THINGS
 * (`-charactersIgnoringModifiers` and `-modifierFlags`). AN OBJECT THAT ANSWERS NEITHER IS REFUSED BY NAME rather
 * than messaged blind — this tree's runtime RAISES on a selector an object does not implement, so a door that did
 * not ask first would abort instead of answering.
 *
 * AND THE PARAMETER IS `nullable` FOR THE SAME REASON IT IS CHECKED IN THE BODY: the refusal above IS the door's
 * answer to an argument it cannot use, so a caller with no event in hand can ask and be told. That is this
 * project's rule for a nullability annotation — IT SAYS WHAT THE IMPLEMENTATION ACCEPTS — and this is the third
 * door in this class whose annotation had to be corrected for exactly that reason. */
- (BOOL)performKeyEquivalent:(nullable id)event;

/* THE TRACKING SESSION: there is nothing to cancel and nothing to attach, because no menu here can be open.
 * AND THE EVENT ARGUMENTS ARE `nullable` FOR THE USUAL REASON — IT IS WHAT THE IMPLEMENTATIONS ACCEPT: each of
 * these bodies NAMES what it needed and returns, so a caller with no event in hand can still ask and be told.
 * (The fifth time this session a probe has driven a non-null annotation with a literal nil, and the second time
 * the right fix was the HEADER rather than the probe: the annotation should describe the door, and these doors
 * are built to be asked with nothing.) */
/* **THE POINT A SESSION WAS DISMISSED AT, ONCE, AND ONLY IF A PRESS DISMISSED IT.** Read-and-clear: a caller that
 * acts on it is the only one that should, and a stale point would re-open a menu nobody asked for. NO when the
 * session ended any other way — a pick, a key, a programmatic cancel — because there is then nothing to re-open. */
- (BOOL)cg_takeDismissedAt:(NSPoint *)where;

- (void)cancelTracking;

/* **BEGIN A SESSION AND RETURN, LEAVING THE LOOP TO THE CALLER.** What the MENU BAR needs: it owns the session for a
 * menu opened from a title, because the events a menu bar must act on — a drag across the bar, a click on another
 * title — land in the BAR'S window and would otherwise be eaten by a loop the menu was running. The menu does
 * everything a session's beginning does and then hands the events back through `-cg_trackOneEvent:` and
 * `-cancelTracking`, which are already the two doors a session's driver needs. */
- (void)cg_beginSessionAt:(NSPoint)location;

/* **AND WHETHER AN EVENT BELONGS TO THIS SESSION** — this menu's window, or an open submenu's, recursively. The
 * routing inside `-cg_trackOneEvent:` asks the same question by hand for submenus; a caller driving the session has
 * to ask it BEFORE dispatching, since the alternative is guessing from coordinates that are in another window's
 * space. */
- (BOOL)cg_ownsEvent:(id)event;
- (void)cancelTrackingWithoutAnimation;
/* **AND THE ROWS OF THIS MENU MAY BE DRAWN BY A SUBCLASS OF `NSMenuView`.** Apple has no such door and needs none:
 * its combo box has a list window of its own. This tier reuses the SESSION — one traversal loop, one window, one
 * dismissal, none of it written twice — and lets the caller say what a ROW looks like, which is the part a list and a
 * menu genuinely disagree about. The class must be `NSMenuView` or a subclass of it; `Nil` restores the default. */
- (void)cg_setMenuViewClass:(nullable Class)aClass;
- (nullable Class)cg_menuViewClass;

- (BOOL)isAttached;
- (nullable id)attachedMenu;
- (NSPoint)locationForSubmenu:(nullable id)aSubmenu;
- (void)helpRequested:(nullable id)event;
- (void)submenuAction:(nullable id)sender;
/* AND THE TWO THAT OPEN ONE, the instance door and the class one a context menu comes through. */
- (void)popUpMenuPositioningItem:(nullable NSMenuItem *)item
		      atLocation:(NSPoint)location
			  inView:(nullable id)view;
+ (void)popUpContextMenu:(NSMenu *)menu withEvent:(nullable id)event forView:(nullable id)view;
/* THE MENU BAR IS THE DESKTOP'S, and the desktop draws its own chrome (D6); the zone pair needs zone-based
 * allocation, and this tier allocates through the runtime's default zone. */
+ (BOOL)menuBarVisible;
+ (void)setMenuBarVisible:(BOOL)visible;
+ (nullable void *)menuZone;
+ (void)setMenuZone:(nullable void *)zone;
/* AND THE THREE REPRESENTATION PAIRS, all `id` for the over-crediting rule: the classes Apple's representations
 * are (NSMenuView, NSMenuItemView) are not in this tree. */
- (nullable id)menuRepresentation;
- (void)setMenuRepresentation:(nullable id)menuRepresentation;
- (nullable id)contextMenuRepresentation;
- (void)setContextMenuRepresentation:(nullable id)contextMenuRepresentation;
- (nullable id)tearOffMenuRepresentation;
- (void)setTearOffMenuRepresentation:(nullable id)tearOffMenuRepresentation;

/* ============================================================================================ *
 * AND THE TWO THAT ACT ON AN ITEM.                                                               *
 * ============================================================================================ */

/* AND THE SWITCH THAT SILENCES AN ANNOUNCEMENT, WHICH IS THE ONE ROW OF THIS CLASS'S TAIL THAT IS SHIPPED RATHER
 * THAN OWED — because its reader is the door below it rather than the tracking loop. A caller rebuilding a menu
 * turns it off, edits, and turns it on again; it STARTS ON, which is Apple's default and the only useful one.
 * AND THE SETTER IS DECLARED AS WELL AS THE PROPERTY — the lesson this session has now recorded three times: the
 * ledger holds a row for the setter BY NAME, and a property declaration does not put its setter's name into the
 * header text. */
@property BOOL menuChangedMessagesEnabled;
- (void)setMenuChangedMessagesEnabled:(BOOL)flag;

/* AN ITEM CHANGED, WHICH THE CLASS ANNOUNCES. This is the door a program calls after editing an item it
 * already added — the menu cannot watch every field of every item, so the caller says so, and the menu posts
 * `NSMenuDidChangeItemNotification` and gives its delegate a chance to react. */
- (void)itemChanged:(NSMenuItem *)item;

/* AND SENDING AN ITEM'S ACTION, which is target/action dispatch and nothing else: the item's target is asked to
 * perform the item's action with the item as the argument, through the responder walk the `NSResponder` base
 * already implements. A nil target or a nil action sends nothing and answers NO. */
- (BOOL)performActionForItemAtIndex:(NSInteger)index;

/* AND THE DECODER DOOR, WHICH REFUSES FOR THE SAME REASON NSMenuItem's DOES: Apple's key set for an archived
 * menu is not published, and a guessed one is a wrong menu. */
- (nullable instancetype)initWithCoder:(NSCoder *)coder;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSMENU_H */
