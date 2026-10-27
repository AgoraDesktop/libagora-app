/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSEvent.h — the event value type, and the constants a responder is written against (stage A).
 *
 * THE CONSTANT HALF CAME FIRST AND THE CLASS IS HERE NOW: `@interface NSEvent` — the accessors, the four
 * constructors, the periodic-event services, the event monitors — is what a responder's whole API takes,
 * which is why this value type is stage A's first unit and `NSResponder` its second.
 *
 * THE NAMES ARE THE 10.6 ERA'S, AND THAT IS A DECISION WITH A MEASURED REASON (user, 2026-10-07).
 * Apple renamed these families later — `NSLeftMouseDown` to `NSEventTypeLeftMouseDown`, `NSLeftMouseDownMask`
 * to `NSEventMaskLeftMouseDown` — so the ledger carries BOTH sets, and the two readings collide: the
 * era-faithful names are the rows whose `why` column says `deprecated`, while the modern names are the rows
 * that are absent from all three era pins. THE ERA WINS, because this duplication is pinned to the era (see
 * docs/design/appkit-plan.md §A7-A9) and a ported 10.6 application spells the names below.
 *
 * AND THE FEAR THAT THIS WOULD FIGHT THE TREE'S DEPRECATION POLICY WAS MISPLACED, which is worth recording
 * because it was the reason the question was asked: THE DEPRECATION GROUND WAS RETIRED ON 2026-09-26, so an
 * Apple-deprecated row is OWED rather than struck, and `tools/appkit-sweep.py` judges it by its declaration
 * "like any other" — the policy class fires only on a row the ledger STRIKES, and this ledger has none. So
 * NOTHING needs exempting and no gate changes: shipping the era names is ordinary work.
 *
 * THE VALUES ARE THE ARTEFACT'S, NOT RECALLED, and that covers the numbers that do not live in this header's
 * own era file: `NSUnknownPointingDevice` and its three siblings, the three pen button masks and the three
 * mouse subtypes are spelled here as the NUMBERS `.tmp/mac106/…/IOKit.framework/…/IOKit/hidsystem/
 * IOLLEvent.h` gives the `NX_*` macros Apple's own header assigns from (`NX_TABLET_POINTER_*`,
 * `NX_TABLET_BUTTON_*`, `NX_SUBTYPE_*`). Apple imports that header; this tree has no IOKit, so the values
 * are transcribed rather than included, which is the same treatment the function keys already get.
 *
 * AND THREE ROWS THIS FILE OWES WERE MISSED BY THE ERA LEDGER'S OWN READER, which is worth stating where the
 * declarations are: `NSEventMaskFromType` (an inline function, `NSEvent.h:98` at 10.6 and `NSEvent.h:63` at
 * 10.2), `NSDeviceIndependentModifierFlagsMask` (10.6 `NSEvent.h:111`) and `NSTouchEventSubtype` (10.6
 * `NSEvent.h:492`) appear in NONE of the three era worklists, so the strike ground reads them as post-era
 * API. They are era API and they are declared below; appkit-plan.md §A10h records the gap.
 */

#ifndef APPKIT_NSEVENT_H
#define APPKIT_NSEVENT_H

#import <Foundation/Foundation.h>
#import <AppKit/NSGraphicsContext.h>

/* FORWARD, because `NSEvent` names an `NSTrackingArea` and a tracking area may name an event: importing the class's
 * header here would close that circle. The forward declaration is all this header needs — every use of the type in it
 * is a pointer. */
@class NSTrackingArea;
@class NSWindow;

/* THE EVENT TYPES. A plain C enum plus a typedef, which is what Apple's own header does — `NSEventType`
 * is not an NS_ENUM in the 10.6 header and does not become one here, because the era is the ground. */
enum {
	NSLeftMouseDown = 1,
	NSLeftMouseUp = 2,
	NSRightMouseDown = 3,
	NSRightMouseUp = 4,
	NSMouseMoved = 5,
	NSLeftMouseDragged = 6,
	NSRightMouseDragged = 7,
	NSMouseEntered = 8,
	NSMouseExited = 9,
	NSKeyDown = 10,
	NSKeyUp = 11,
	NSFlagsChanged = 12,
	NSAppKitDefined = 13,
	NSSystemDefined = 14,
	NSApplicationDefined = 15,
	NSPeriodic = 16,
	NSCursorUpdate = 17,
	/* 18, 19 AND 20 ARRIVE LATER IN THIS ENUM AND 22 ARRIVES HERE, which is the artefact's own ordering and
	 * not a slip: the gesture and rotate types are declared with the 10.5 run at the bottom, and
	 * `NSScrollWheel` sits with the mouse types above them. */
	NSScrollWheel = 22,
	NSTabletPoint = 23,
	NSTabletProximity = 24,
	NSOtherMouseDown = 25,
	NSOtherMouseUp = 26,
	NSOtherMouseDragged = 27,
	NSEventTypeGesture = 29,
	NSEventTypeMagnify = 30,
	NSEventTypeSwipe = 31,
	NSEventTypeRotate = 18,
	NSEventTypeBeginGesture = 19,
	NSEventTypeEndGesture = 20
};
typedef NSUInteger NSEventType;

/* THE MASKS, ONE BIT PER TYPE ABOVE — which is why the two families are written together and why the
 * two names further down (`NSEventMask…`) are NOT here: they are the modern spelling and belong to a row
 * set the era strikes (appkit-plan.md §A9). */
typedef unsigned long long NSEventMask;

enum {
	NSLeftMouseDownMask = 1 << NSLeftMouseDown,
	NSLeftMouseUpMask = 1 << NSLeftMouseUp,
	NSRightMouseDownMask = 1 << NSRightMouseDown,
	NSRightMouseUpMask = 1 << NSRightMouseUp,
	NSMouseMovedMask = 1 << NSMouseMoved,
	NSLeftMouseDraggedMask = 1 << NSLeftMouseDragged,
	NSRightMouseDraggedMask = 1 << NSRightMouseDragged,
	NSMouseEnteredMask = 1 << NSMouseEntered,
	NSMouseExitedMask = 1 << NSMouseExited,
	NSKeyDownMask = 1 << NSKeyDown,
	NSKeyUpMask = 1 << NSKeyUp,
	NSFlagsChangedMask = 1 << NSFlagsChanged,
	NSAppKitDefinedMask = 1 << NSAppKitDefined,
	NSSystemDefinedMask = 1 << NSSystemDefined,
	NSApplicationDefinedMask = 1 << NSApplicationDefined,
	NSPeriodicMask = 1 << NSPeriodic,
	NSCursorUpdateMask = 1 << NSCursorUpdate,
	NSScrollWheelMask = 1 << NSScrollWheel,
	NSTabletPointMask = 1 << NSTabletPoint,
	NSTabletProximityMask = 1 << NSTabletProximity,
	NSOtherMouseDownMask = 1 << NSOtherMouseDown,
	NSOtherMouseUpMask = 1 << NSOtherMouseUp,
	NSOtherMouseDraggedMask = 1 << NSOtherMouseDragged,
	NSEventMaskGesture = 1 << NSEventTypeGesture,
	NSEventMaskMagnify = 1 << NSEventTypeMagnify,
	/* THE ONE MASK THE ARTEFACT WRITES WITH AN UNSUFFIXED SHIFT — `1U << NSEventTypeSwipe` — and the `U` is
	 * kept because it is what a 32-bit `int` shift needs to be well defined at bit 31. */
	NSEventMaskSwipe = 1U << NSEventTypeSwipe,
	NSEventMaskRotate = 1 << NSEventTypeRotate,
	NSEventMaskBeginGesture = 1 << NSEventTypeBeginGesture,
	NSEventMaskEndGesture = 1 << NSEventTypeEndGesture,
	NSAnyEventMask = 0xffffffffU
};

/* AND THE TYPE-TO-MASK RELATION, WHICH IS A FUNCTION AND NOT A THIRD TABLE: a run loop that has a type and
 * wants its bit calls this, and the artefact defines it as an inline function in both eras it exists in. */
NS_INLINE NSUInteger NSEventMaskFromType(NSEventType type) { return (1 << type); }

/* THE MODIFIER FLAGS IN AN EVENT'S `modifierFlags`, one bit each, and the high half is deliberate:
 * the low 16 bits are the character code's own modifiers and these start at 16. */
enum {
	NSAlphaShiftKeyMask = 1 << 16,
	NSShiftKeyMask = 1 << 17,
	NSControlKeyMask = 1 << 18,
	NSAlternateKeyMask = 1 << 19,
	NSCommandKeyMask = 1 << 20,
	NSNumericPadKeyMask = 1 << 21,
	NSHelpKeyMask = 1 << 22,
	NSFunctionKeyMask = 1 << 23,
	/* THE MASK THAT SEPARATES THE TWO HALVES: everything the KEYBOARD did, as opposed to everything the
	 * character code carries. It is the last member of the enum and has no comma, as the artefact has it. */
	NSDeviceIndependentModifierFlagsMask = 0xffff0000UL
};

/* THE FUNCTION KEYS — the values an arrow key, an F-key or a keypad key arrives AS inside `characters`,
 * and the whole 0xF700..0xF747 range the artefact lists. */
enum {
	NSUpArrowFunctionKey = 0xF700,
	NSDownArrowFunctionKey = 0xF701,
	NSLeftArrowFunctionKey = 0xF702,
	NSRightArrowFunctionKey = 0xF703,
	NSF1FunctionKey = 0xF704,
	NSF2FunctionKey = 0xF705,
	NSF3FunctionKey = 0xF706,
	NSF4FunctionKey = 0xF707,
	NSF5FunctionKey = 0xF708,
	NSF6FunctionKey = 0xF709,
	NSF7FunctionKey = 0xF70A,
	NSF8FunctionKey = 0xF70B,
	NSF9FunctionKey = 0xF70C,
	NSF10FunctionKey = 0xF70D,
	NSF11FunctionKey = 0xF70E,
	NSF12FunctionKey = 0xF70F,
	NSF13FunctionKey = 0xF710,
	NSF14FunctionKey = 0xF711,
	NSF15FunctionKey = 0xF712,
	NSF16FunctionKey = 0xF713,
	NSF17FunctionKey = 0xF714,
	NSF18FunctionKey = 0xF715,
	NSF19FunctionKey = 0xF716,
	NSF20FunctionKey = 0xF717,
	NSF21FunctionKey = 0xF718,
	NSF22FunctionKey = 0xF719,
	NSF23FunctionKey = 0xF71A,
	NSF24FunctionKey = 0xF71B,
	NSF25FunctionKey = 0xF71C,
	NSF26FunctionKey = 0xF71D,
	NSF27FunctionKey = 0xF71E,
	NSF28FunctionKey = 0xF71F,
	NSF29FunctionKey = 0xF720,
	NSF30FunctionKey = 0xF721,
	NSF31FunctionKey = 0xF722,
	NSF32FunctionKey = 0xF723,
	NSF33FunctionKey = 0xF724,
	NSF34FunctionKey = 0xF725,
	NSF35FunctionKey = 0xF726,
	NSInsertFunctionKey = 0xF727,
	NSDeleteFunctionKey = 0xF728,
	NSHomeFunctionKey = 0xF729,
	NSBeginFunctionKey = 0xF72A,
	NSEndFunctionKey = 0xF72B,
	NSPageUpFunctionKey = 0xF72C,
	NSPageDownFunctionKey = 0xF72D,
	NSPrintScreenFunctionKey = 0xF72E,
	NSScrollLockFunctionKey = 0xF72F,
	NSPauseFunctionKey = 0xF730,
	NSSysReqFunctionKey = 0xF731,
	NSBreakFunctionKey = 0xF732,
	NSResetFunctionKey = 0xF733,
	NSStopFunctionKey = 0xF734,
	NSMenuFunctionKey = 0xF735,
	NSUserFunctionKey = 0xF736,
	NSSystemFunctionKey = 0xF737,
	NSPrintFunctionKey = 0xF738,
	NSClearLineFunctionKey = 0xF739,
	NSClearDisplayFunctionKey = 0xF73A,
	NSInsertLineFunctionKey = 0xF73B,
	NSDeleteLineFunctionKey = 0xF73C,
	NSInsertCharFunctionKey = 0xF73D,
	NSDeleteCharFunctionKey = 0xF73E,
	NSPrevFunctionKey = 0xF73F,
	NSNextFunctionKey = 0xF740,
	NSSelectFunctionKey = 0xF741,
	NSExecuteFunctionKey = 0xF742,
	NSUndoFunctionKey = 0xF743,
	NSRedoFunctionKey = 0xF744,
	NSFindFunctionKey = 0xF745,
	NSHelpFunctionKey = 0xF746,
	NSModeSwitchFunctionKey = 0xF747
};

/* **AND THE CONTROL CHARACTERS, WHICH ARE THE OTHER HALF OF WHAT `characters` CARRIES.** A key that TYPES arrives as
 * the character it types, and a key that COMMANDS arrives as one of these — Apple's own split, and the reason a text
 * view can tell a Backspace from a left arrow without ever seeing a key code: THE CHARACTER IS THE COMMAND'S NAME.
 * Each value is the code point the character actually has in Unicode (or in ASCII, which agrees for all of these), so
 * nothing here is a transcription that could be wrong: `NSDeleteCharacter` is U+007F because DELETE is U+007F, and
 * `NSBackTabCharacter` is U+0019 because that is what a Shift-Tab sends.
 *
 * **AND TWO OF THEM ARE THE SAME GESTURE ON DIFFERENT KEYMAPS.** A Backspace key sends `NSBackspaceCharacter` on one
 * keymap and `NSDeleteCharacter` on another, which is why a text view treats BOTH as backward delete and reserves
 * `NSDeleteFunctionKey` (a FUNCTION key, in the enum above) for the forward one. It is stated here rather than left to
 * be discovered, because the alternative is a field that deletes the wrong way on someone else's keyboard. */
enum {
	NSEnterCharacter = 0x03,
	NSBackspaceCharacter = 0x08,
	NSTabCharacter = 0x09,
	NSNewlineCharacter = 0x0A,
	NSFormFeedCharacter = 0x0C,
	NSCarriageReturnCharacter = 0x0D,
	NSBackTabCharacter = 0x19,
	NSDeleteCharacter = 0x7F
};

/* THE POINTING-DEVICE TYPES a tablet proximity event reports, and the PEN BUTTON MASK a tablet point event
 * reports — two families from IOLLEvent.h's `NX_TABLET_*`, transcribed (see this file's top comment). */
enum {
	NSUnknownPointingDevice = 0,
	NSPenPointingDevice = 1,
	NSCursorPointingDevice = 2,
	NSEraserPointingDevice = 3
};
typedef NSUInteger NSPointingDeviceType;

enum {
	NSPenTipMask = 0x0001,
	NSPenLowerSideMask = 0x0002,
	NSPenUpperSideMask = 0x0004
};

/* THE EVENT SUBTYPES. Three families, each read off `-subtype` for a different event type: an
 * `NSAppKitDefined` event, a `NSSystemDefined` event, and a mouse event (`NSMouseEventSubtype` and the
 * tablet pair), which is what the artefact's own three enums separate. */
enum {
	NSWindowExposedEventType = 0,
	NSApplicationActivatedEventType = 1,
	NSApplicationDeactivatedEventType = 2,
	NSWindowMovedEventType = 4,
	NSScreenChangedEventType = 8,
	NSAWTEventType = 16
};

enum {
	NSPowerOffEventType = 1
};

enum {
	NSMouseEventSubtype = 0,
	NSTabletPointEventSubtype = 1,
	NSTabletProximityEventSubtype = 2,
	NSTouchEventSubtype = 3
};

NS_ASSUME_NONNULL_BEGIN

/* THE EVENT ITSELF. An event is a VALUE a seam produces and a responder consumes, so this class is
 * almost entirely storage: what the constructors are handed is what the accessors answer, and the only
 * arithmetic in it is the pressed-buttons mask.
 *
 * THE TABLET AND POINTING-DEVICE STORAGE IS THIS TIER'S OWN SHAPE, AND ITS SLOTS ARE OURS. Apple keeps
 * those fields in two raw `int[14]` arrays (`tabletPointData` / `tabletProximityData`) whose slot order its
 * header does not publish, so copying it would be inventing an ABI; what is copied is the SHAPE — an
 * accessor per field, answering storage the event owns. AND NOTHING IN THIS TIER FILLS IT: the seam's seat reports a
 * keyboard and a pointer and no tablet, so these answer the empty value exactly as `-deltaX` does for every
 * event the four constructors build. That is a statement about the SEAM, not a refusal — the accessors are
 * real readers, and they read a field a tablet device would write.
 *
 * THE CLASS-LEVEL STATE IS THIS TREE'S OWN, AND THAT IS A DEVIATION WORTH STATING PLAINLY. `+mouseLocation`,
 * `+modifierFlags` and `+pressedMouseButtons` describe the STATE OF THE INPUT DEVICES, and Apple reads
 * that from the window server. The display and event seam is `AGWindowServer` (an `xdg-shell` client), so they answer from THE
 * LAST EVENT THIS CLASS WAS ASKED TO CREATE — which is exactly as much as a caller can know from inside the
 * process, and is why those three are defined rather than refused. A fabricated event updates them; nothing
 * else can.
 *
 * AND THE MRC OWNERSHIP IS EXPLICIT, because a value type still owns its objects: `_characters`,
 * `_charactersIgnoringModifiers`, `_context` and `_vendorDefined` are RETAINED, and `_context` is an
 * NSGraphicsContext, which this tree has — so its header is imported rather than forward-declared.
 *
 * **AND `-window` IS HERE NOW, BECAUSE `NSWindow` IS.** The pair was split while the class did not exist — this
 * ledger's instrument counted a `@class` FORWARD DECLARATION as declaring the class, so naming NSWindow in this header
 * would have credited NSWindow's own row (the §58 over-crediting family, a defect in the instrument rather than in
 * Apple's spelling). The class exists, the number was always stored, and the object is the application's registry
 * lookup — so the door answers what Apple's does and the note that explained its absence is retired.
 * THE SAME RULE DECIDES THREE MORE DECLARATIONS BELOW, and each says so where it stands: `-trackingArea`
 * answers `id`, the touch door takes a word-sized phase and an `id` view, and the two CGEvent doors are
 * spelled with a `void *` — because `NSTrackingArea`, `NSTouchPhase` and `CGEventRef` are names whose class
 * or type rows this tier has not earned, and a header is not the place to earn them. */
@interface NSEvent : NSObject
{
	NSEventType _type;
	NSUInteger _modifierFlags;
	NSTimeInterval _timestamp;
	NSInteger _windowNumber;
	NSGraphicsContext *_context;	/* RETAINED */
	NSPoint _locationInWindow;
	/* **AND WHERE THE POINTER IS IN THE OUTPUT, WHEN THE COMPOSITOR SAID SO.** `-locationInWindow` is relative to
	 * the window, which a window being DRAGGED moves — so a title-bar drag needs the absolute pair, and it has to
	 * travel WITH the event: a single "latest" value is read after the seam has already advanced it past the press
	 * (MEASURED: the grab was recorded at the FINAL pointer and the window jumped to the origin instead). */
	NSPoint _cg_globalPoint;
	BOOL _cg_hasGlobalPoint;
	NSInteger _clickCount;
	NSInteger _buttonNumber;
	NSInteger _eventNumber;
	NSInteger _trackingNumber;
	/* **AND THE AREA THAT GENERATED THIS ENTER/EXIT EVENT, WHICH THE TIER'S OWN ENGINE SETS.** NOT RETAINED: an event is
	 * handed to a responder for the length of one call, and the area belongs to the view that installed it. A tracking
	 * RECT's event has no area and answers nil here, which is the same nil Apple's own header documents for it. */
	NSTrackingArea *_trackingArea;
	float _pressure;
	/* **THE SEAM'S THREE, KEPT ON THE EVENT RATHER THAN IN A SIDE TABLE.** A timestamp's ORIGIN and the keyboard tenure
	 * an event arrived under are facts about the event, and a lookup keyed by event would be a second source of truth
	 * for something the event already is. */
	BOOL _cg_hasSourceTimestamp;
	unsigned int _cg_sourceTimestamp;
	unsigned int _cg_focusSerial;
	/* **AND THE KEY'S OWN NAME, WHICH IS NOT ITS TEXT AND NOT ITS CODE.** See `-cg_keysym` below for why a key event
	 * cannot be understood without it: a dead key types nothing at all, and the character a plain key types is the
	 * same character two different physical keys can produce. Zero means the keymap named no symbol. */
	unsigned int _cg_keysym;
	CGFloat _deltaX;
	CGFloat _deltaY;
	CGFloat _deltaZ;
	NSString *_characters;			/* RETAINED */
	NSString *_charactersIgnoringModifiers;	/* RETAINED */
	BOOL _isARepeat;
	unsigned short _keyCode;
	void *_userData;
	short _subtype;
	NSInteger _data1;
	NSInteger _data2;
	/* THE TABLET AND POINTING-DEVICE FIELDS (see the note above). */
	NSUInteger _deviceID;
	float _rotation;
	NSInteger _absoluteX;
	NSInteger _absoluteY;
	NSInteger _absoluteZ;
	NSUInteger _buttonMask;
	NSPoint _tilt;
	float _tangentialPressure;
	NSArray *_vendorDefined;		/* RETAINED */
	NSUInteger _vendorID;
	NSUInteger _tabletID;
	NSUInteger _pointingDeviceID;
	NSUInteger _systemTabletID;
	NSUInteger _vendorPointingDeviceType;
	NSUInteger _pointingDeviceSerialNumber;
	unsigned long long _uniqueID;
	NSUInteger _capabilityMask;
	NSPointingDeviceType _pointingDeviceType;
	BOOL _enteringProximity;
	/* THE GESTURE FIELD, and it is the same story as the tablet block: one stored value, written by the
	 * gesture events a trackpad would produce. */
	CGFloat _magnification;
}

/* THE EVENT'S OWN PROPERTIES. `-characters` is nullable because a mouse event has none — the annotation
 * says what the IMPLEMENTATION answers, which is the standing rule for these headers. */
@property (readonly) NSEventType type;
@property (readonly) NSUInteger modifierFlags;
@property (readonly) NSTimeInterval timestamp;
@property (readonly) NSInteger windowNumber;
/* **AND THE WINDOW THE NUMBER NAMES, WHEN IT NAMES ONE.** An event with no window (a global mouse move, a periodic tick)
 * answers nil; the number is 0 for those, and the application's registry has no window with that number. */
- (nullable NSWindow *)window;
@property (readonly, nullable) NSGraphicsContext *context;
@property (readonly) NSPoint locationInWindow;
@property (readonly) NSInteger clickCount;
@property (readonly) NSInteger buttonNumber;
@property (readonly) NSInteger eventNumber;
@property (readonly) NSInteger trackingNumber;
@property (readonly) float pressure;
@property (readonly) CGFloat deltaX;
@property (readonly) CGFloat deltaY;
@property (readonly) CGFloat deltaZ;
/* **THE TWO STRINGS A KEY HAS, AND WHY ONE IS NOT THE OTHER.** `-characters` is what the keystroke MEANS, with every
 * modifier applied: xkbcommon folds Control into the C0 range, so `Ctrl+A` is `0x01`, `Ctrl+[` is `0x1b` and
 * `Ctrl+Space` is `0x00` — which is exactly what a text view wants to insert and exactly what makes a control
 * combination unnamed.
 *
 * `-charactersIgnoringModifiers` is what the KEY IS: the symbol it has with Shift kept and every other modifier dropped,
 * which is Apple's own sentence ("as if no modifier key (except for Shift) had been pressed"). It is where a key
 * EQUIVALENT is matched — `NSMenu -performKeyEquivalent:` reads this door, as Apple's does — and it is the only string
 * that can tell `Ctrl+Shift+C` from `Ctrl+C`, because both type `0x03`. The locks (Caps Lock, Num Lock) are dropped with
 * the rest: `Cmd+C` while Caps Lock is on must still match a `c` item in a menu.
 *
 * The seam carries both (`AGEvent.text` and `AGEvent.text_plain`, from `AGKeyboardTranslate` and
 * `AGKeyboardTranslateIgnoringModifiers`), and this tier used to put the SAME string in both — which left every control
 * combination unnameable to a menu. An event with no unmasked text (a fabricated one, or a key that types nothing and is
 * named by the `0xF700` block) answers the same string both ways, which is what AppKit does for a commanding key. */
@property (readonly, nullable) NSString *characters;
@property (readonly, nullable) NSString *charactersIgnoringModifiers;
@property (readonly) unsigned short keyCode;
@property (readonly) short subtype;
@property (readonly) NSInteger data1;
@property (readonly) NSInteger data2;
@property (readonly, nullable) void *userData;
@property (readonly) CGFloat magnification;

/* THE TABLET AND POINTING-DEVICE ACCESSORS, one per stored field. They are valid for the tablet event types
 * and for the mouse subtypes above, which is what the artefact's own comments say of each. */
@property (readonly) NSUInteger deviceID;
@property (readonly) float rotation;
@property (readonly) NSInteger absoluteX;
@property (readonly) NSInteger absoluteY;
@property (readonly) NSInteger absoluteZ;
@property (readonly) NSUInteger buttonMask;
@property (readonly) NSPoint tilt;
@property (readonly) float tangentialPressure;
@property (readonly, nullable) NSArray *vendorDefined;
@property (readonly) NSUInteger vendorID;
@property (readonly) NSUInteger tabletID;
@property (readonly) NSUInteger pointingDeviceID;
@property (readonly) NSUInteger systemTabletID;
@property (readonly) NSUInteger vendorPointingDeviceType;
@property (readonly) NSUInteger pointingDeviceSerialNumber;
@property (readonly) unsigned long long uniqueID;
@property (readonly) NSUInteger capabilityMask;
@property (readonly) NSPointingDeviceType pointingDeviceType;

/* APPLE'S OWN SPELLING IN THE ERA IS A METHOD, not a property, and that is how it is declared here — and
 * the same goes for the proximity flag, whose getter carries the `is` the property row does not spell. */
- (BOOL)isARepeat;
- (BOOL)isEnteringProximity;

/* AND THE INITIALISER NSEvent OVERRIDES: it answers an empty `NSAppKitDefined` event, which is what
 * Apple's does, and it is declared because a ledger row for it exists and this tree's rule is that a
 * row is shipped only when the header DECLARES the member. */
- (instancetype)init;

/* THE FOUR CONSTRUCTORS, and they are the whole reason a seam can exist: an event is not discovered,
 * it is BUILT by whoever read the device. Each takes the same preamble — type, location, flags,
 * timestamp, window number, context — and then what its kind adds. */
+ (nullable NSEvent *)mouseEventWithType:(NSEventType)type
				location:(NSPoint)location
			   modifierFlags:(NSUInteger)flags
			       timestamp:(NSTimeInterval)time
			    windowNumber:(NSInteger)windowNum
				 context:(nullable NSGraphicsContext *)context
			     eventNumber:(NSInteger)eventNum
			      clickCount:(NSInteger)clickNum
				pressure:(float)pressureValue;
/* **A WHEEL EVENT, WHICH APPLE'S OWN CONSTRUCTORS DO NOT BUILD.** Every `+mouseEventWithType:` in Cocoa makes an
 * event with no deltas, and a scroll with no delta is a scroll that does nothing. This is an Agora extension, not part
 * of the 10.6 surface, and it exists so the seam can hand the AppKit a wheel it can actually deliver.
 *
 * `dx`/`dy` ARE IN WHEEL LINES, the unit `-deltaY` has answered in since this era: one notch is 1.0, a trackpad's
 * fraction of a notch is a fraction of a line, and the SIGN is Cocoa's — positive is a scroll UP and to the LEFT.
 * Normalizing the protocol's opposite sense is the caller's job and happens once, at the seam, so nothing above it
 * has to know which direction the compositor counted in. */
/* **THE SOURCE'S OWN CHRONOLOGY, AND WHOSE FOCUS IT ARRIVED UNDER — the two facts `-timestamp` cannot carry.**
 *
 * `-timestamp` is a TRANSLATION time: when this process turned the event into an object. A nonblocking confirmation
 * needs the opposite question answered — "was this keystroke generated before my dialog appeared?" — and a client's own
 * clock cannot answer it, because the event may have been queued before the client looked.
 *
 * `-cg_sourceTimestamp` is the compositor's clock, in milliseconds, as it came off the wire; `-cg_hasSourceTimestamp`
 * says whether a compositor sent one at all (a stock `xdg-shell` compositor need not). `-cg_focusSerial` is the
 * KEYBOARD TENURE the event was delivered under: two events with the same serial were not interrupted by the keyboard
 * leaving this application and coming back, and a higher serial means they were. That distinction is a fact about
 * focus, not about elapsed time, which is why a timestamp cannot stand in for it.
 *
 * Agora extensions; neither is in Apple's 10.6 surface. */
@property (readonly) BOOL cg_hasSourceTimestamp;
@property (readonly) unsigned int cg_sourceTimestamp;
@property (readonly) unsigned int cg_focusSerial;

/* **THE KEYMAP'S NAME FOR THE KEY, CARRIED THROUGH TO THE CALLER THAT HAS TO ACT ON WHICH KEY IT WAS.** `-characters`
 * answers what the key TYPED, and there are two families of key for which that is the wrong question:
 *
 *   - A key that types NOTHING. The `0xF700` block names the commanding ones (`NSUpArrowFunctionKey` and its
 *     neighbours), and `-keyCode` names the physical switch — but a DEAD KEY types nothing and is in neither: `´` is
 *     not a character in `-characters` (xkbcommon answers no text at all for one) and `-keyCode` says only which
 *     piece of plastic moved. Without the keysym, a dead key is indistinguishable from a key the layout does not
 *     define, which is why `AGInputMethod` could not see one from real hardware.
 *
 *   - A key whose TEXT does not identify it. The keypad's `1` and the row's `1` both type "1"; `-` on a US layout and
 *     the ASCII grave it shares a key with are one character and two meanings. A terminal writing an escape sequence
 *     for the keypad needs the former, and a text view deciding whether a `` ` `` BEGINS a composition needs the
 *     latter — the answer is "no" on a US layout, where that key is `XKB_KEY_grave`, and "yes" on a French one,
 *     where it is `XKB_KEY_dead_grave`.
 *
 * It is an `XKB_KEY_…` value (`xkbcommon-keysyms.h`), the layout's own vocabulary, because that is what the seam
 * carries: `AGEvent.keysym`. Zero (`XKB_KEY_NoSymbol`) for a key whose code the map does not define, and for every
 * event this tier fabricates, since a fabricated event has no keymap behind it. Agora extension; not in Apple's 10.6
 * surface. */
@property (readonly) unsigned int cg_keysym;
/* **THE PRIVATE HALF, AND IT IS `cg_` SO THE PUBLIC SURFACE STAYS APPLE'S.** Only the seam's translation path knows a
 * key's keysym, so only it writes this — exactly the arrangement `-cg_setSourceTimestamp:…` has. */
- (void)cg_setKeysym:(unsigned int)keysym;

+ (nullable NSEvent *)cg_scrollEventWithDeltaX:(CGFloat)dx
				  deltaY:(CGFloat)dy
				location:(NSPoint)location
			   modifierFlags:(NSUInteger)flags
			       timestamp:(NSTimeInterval)time
			    windowNumber:(NSInteger)windowNum;

+ (nullable NSEvent *)keyEventWithType:(NSEventType)type
			      location:(NSPoint)location
			 modifierFlags:(NSUInteger)flags
			     timestamp:(NSTimeInterval)time
			  windowNumber:(NSInteger)windowNum
			       context:(nullable NSGraphicsContext *)context
			    characters:(NSString *)keys
	   charactersIgnoringModifiers:(NSString *)ukeys
			     isARepeat:(BOOL)isARepeat
			       keyCode:(unsigned short)code;
+ (nullable NSEvent *)enterExitEventWithType:(NSEventType)type
				    location:(NSPoint)location
			       modifierFlags:(NSUInteger)flags
				   timestamp:(NSTimeInterval)time
				windowNumber:(NSInteger)windowNum
				     context:(nullable NSGraphicsContext *)context
				 eventNumber:(NSInteger)eventNum
			      trackingNumber:(NSInteger)trackingNum
				    userData:(void *)userData;
+ (nullable NSEvent *)otherEventWithType:(NSEventType)type
				location:(NSPoint)location
			   modifierFlags:(NSUInteger)flags
			       timestamp:(NSTimeInterval)time
			    windowNumber:(NSInteger)windowNum
				 context:(nullable NSGraphicsContext *)context
				 subtype:(short)subtype
				   data1:(NSInteger)data1
				   data2:(NSInteger)data2;

/* AND THE THREE CLASS SERVICES. See the deviation note above: they describe the devices as far as this
 * class has been told about them, which is the last event it was asked to create. */
+ (NSPoint)mouseLocation;
+ (NSUInteger)modifierFlags;
+ (NSUInteger)pressedMouseButtons;

/* THE THREE INPUT INTERVALS, AND EACH IS REFUSED BY NAME. Apple reads them from the window server, which
 * is where a user's double-click speed and key-repeat settings live. THE COMPOSITOR OWNS THEM — `AGKeyboard`
 * reads the keymap it sends — but the seam exposes no door to either setting. ANSWERING A NUMBER HERE WOULD
 * BE A SECOND COPY THAT
 * DRIFTS, which is worse than an unfinished door, so each answers 0.0 and says so. */
+ (NSTimeInterval)doubleClickInterval;
+ (NSTimeInterval)keyRepeatDelay;
+ (NSTimeInterval)keyRepeatInterval;

/* MOUSE COALESCING, and this one IS this class's own state: a flag a program sets and reads back. What it
 * cannot do yet is change anything — coalescing happens in the compositor, which the seam does not surface —
 * so the stored flag is the honest half and the header says which half it is. Apple's default is YES. */
+ (void)setMouseCoalescingEnabled:(BOOL)flag;
+ (BOOL)isMouseCoalescingEnabled;

/* THE PERIODIC-EVENT SERVICES, used by tracking loops. `NSPeriodic` is one of the event types above, and
 * these two turn the source on and off; `-[NSApplication nextEventMatchingMask:…]` is where they are read,
 * which is the same door the run loop drains. */
+ (void)startPeriodicEventsAfterDelay:(NSTimeInterval)delay withPeriod:(NSTimeInterval)period;
+ (void)stopPeriodicEvents;

/* THE EVENT MONITORS. A LOCAL monitor sees every event before `-[NSApplication sendEvent:]` dispatches it
 * and may REPLACE it (by returning another event) or DROP it (by returning nil); that is Apple's contract
 * and it is implemented here, in the application's dispatch door. A GLOBAL monitor sees events posted to
 * OTHER applications, and this tier has no other applications and no event tap — so the monitor is
 * registered and refused by name, which keeps the object contract a caller relies on (`+removeMonitor:`
 * still accepts what these return). Each answers a retained object, as Apple's do. */
+ (nullable id)addLocalMonitorForEventsMatchingMask:(NSEventMask)mask
					    handler:(nullable NSEvent * (^)(NSEvent *event))block;
+ (nullable id)addGlobalMonitorForEventsMatchingMask:(NSEventMask)mask
					     handler:(nullable void (^)(NSEvent *event))block;
+ (void)removeMonitor:(nullable id)eventMonitor;

/* THE 10.5 DOORS THAT CROSS INTO ANOTHER SYSTEM, AND BOTH ARE REFUSED BY NAME. `-eventRef`/`+eventWithEventRef:`
 * belong to the CARBON Event Manager and `-CGEvent`/`+eventWithCGEvent:` to QUARTZ EVENT SERVICES; this tree
 * has neither, and the answers below are the ones Apple's own documentation gives for the case where no
 * such object corresponds — NULL and nil — so a caller that checks them reads the truth either way. */
- (nullable const void *)eventRef;
+ (nullable NSEvent *)eventWithEventRef:(nullable const void *)eventRef;
- (nullable void *)CGEvent;
+ (nullable NSEvent *)eventWithCGEvent:(nullable void *)cgEvent;

/* AND THE TRACKING AREA THAT GENERATED AN ENTER/EXIT EVENT. `NSTrackingArea` IS A CLASS THIS TIER SHIPS NOW, so this
 * door names it — the return was spelled `id` while the class was an unearned row, and the door's own comment said
 * naming it was the thing that would change. AN EVENT WITH NO AREA ANSWERS NIL, and that is a real case rather than a
 * failure: an enter/exit built for a tracking RECT (`-[NSView addTrackingRect:owner:userData:assumeInside:]`) has a
 * `-trackingNumber` and a `-userData` and no area, which is exactly what Apple's header says such an event returns. */
- (nullable NSTrackingArea *)trackingArea;

/* AND THE TOUCH DOOR, WHICH IS REFUSED BY NAME FOR A REASON THAT IS A DECISION AND NOT AN OMISSION:
 * `NSTouch` is PARKED (appkit-plan.md §3 — gesture and touch input have no source in the seam's seat).
 * The phase is a word-sized value because `NSTouchPhase` belongs to that parked class's header, and the
 * view is an `id` because `-touchesMatchingPhase:inView:` takes whatever view the caller was asking about. */
- (nullable NSSet *)touchesMatchingPhase:(NSUInteger)phase inView:(nullable id)view;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSEVENT_H */
