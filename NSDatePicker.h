/*
 * NSDatePicker.h — A DATE, SHOWN AS TEXT IN A FIELD, AND THE SUBFIELD THAT CHANGES WHEN YOU STEP IT.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **A DATE PICKER IS A FIELD WHOSE TEXT IS A FORMATTED DATE.** It is not a calendar widget with a text mode bolted on: the
 * cell takes a date, a set of ELEMENT FLAGS saying which parts of it to show, and a locale, calendar and time zone, and the
 * text it draws is `NSDateFormatter`'s answer for exactly those facts. So the three "presentation" doors are not decoration —
 * every one of them is read by the formatter on every draw, and the probe changes each of them and requires the text to
 * follow (a locale that swaps day and month, a time zone that moves the hour and even the day, an element flag that removes a
 * whole field).
 *
 * **THE SUBFIELDS ARE THE FIELDS OF THE FORMATTED TEXT, NOT A SECOND LAYOUT.** The cell asks the locale's pattern which
 * fields it produced and in what order, formats each one on its own, and LOCATES that piece in the finished string — so the
 * rectangle a click selects is measured from the text that is actually on screen. Hit-testing and drawing therefore cannot
 * disagree, which is the class of bug a date field is otherwise very good at growing.
 *
 * **THE THREE STYLES ARE THREE FRAMES AROUND THAT TEXT:**
 *
 *   NSTextFieldDatePickerStyle          the text alone, in a field
 *   NSTextFieldAndStepperDatePickerStyle  the text, with Apple's two-arrow stepper at the right edge
 *   NSClockAndCalendarDatePickerStyle   a picture of the date instead of its text
 *
 * **THIS TIER'S READING OF THE THIRD STYLE IS STATED RATHER THAN HIDDEN**: it draws the half of the date its ELEMENT FLAGS
 * name — a time-only picker gets a CLOCK FACE (a ring, twelve ticks, and three hands at the date's hour, minute and second),
 * and a picker that asks for any of the year/month/day flags gets a MONTH GRID (the month's name and year, the weekday row in
 * the calendar's first-weekday order, and the month's days numbered, the selected day in the platform accent). Apple's real
 * control shows a clock *and* a calendar and swaps between them on a click; that swap is a state machine this tier does not
 * have, and pretending to have it would be a style that draws one picture under another's name.
 *
 * **AND THE ONE THING A DATE FIELD MUST GET RIGHT IS WHAT A CHANGE IS.** Every edit the user can make — a click on a
 * subfield then the stepper's arrows, an up/down arrow key, a typed digit — builds a PROPOSED date and interval and offers
 * them to `NSDatePickerCellDelegate`'s one message before they are stored, in the era's out-parameter form: the delegate may
 * replace either value, and answering a nil date REFUSES the change. That protocol is declared here because this cell is what
 * actually sends it, and `tests/date_picker.m` exercises the accept, the replace and the refusal.
 *
 * **THE RANGE MODE IS THE START DATE PLUS AN INTERVAL.** `NSRangeDateMode` draws `dateValue` and `dateValue +
 * timeInterval` as two formatted dates, separated by an ASCII hyphen; the interval door is the duration, not a second date. Stepping in range mode steps
 * the START, because that is the only date the class stores.
 */
#ifndef APPKIT_NSDATEPICKER_H
#define APPKIT_NSDATEPICKER_H

#import <Foundation/NSDate.h>
#import <AppKit/NSControl.h>
#import <AppKit/NSActionCell.h>

NS_ASSUME_NONNULL_BEGIN

@class NSCalendar, NSLocale, NSTimeZone;

/* THE THREE STYLES, in Apple's order and with Apple's numbers. */
typedef NSUInteger NSDatePickerStyle;
enum {
	NSTextFieldAndStepperDatePickerStyle = 0,
	NSClockAndCalendarDatePickerStyle = 1,
	NSTextFieldDatePickerStyle = 2
};

/* SINGLE, OR A START AND A LENGTH. */
typedef NSUInteger NSDatePickerMode;
enum {
	NSSingleDateMode = 0,
	NSRangeDateMode = 1
};

/* **THE ELEMENT FLAGS ARE APPLE'S BIT VALUES, NOT A CONVENIENCE ENUM.** They are a mask over the parts of a date, and their
 * numbers are load-bearing: `NSYearMonthDayDatePickerElementFlag` is `NSYearMonthDatePickerElementFlag | NSDay`'s bit, and
 * `NSHourMinuteSecondDatePickerElementFlag` is `NSHourMinuteDatePickerElementFlag | NSSecond`'s. The header keeps the 10.6
 * values so a nib's number means the same thing here. */
typedef NSUInteger NSDatePickerElementFlags;
enum {
	/* Time Elements */
	NSHourMinuteDatePickerElementFlag = 0x000c,
	NSHourMinuteSecondDatePickerElementFlag = 0x000e,
	NSTimeZoneDatePickerElementFlag = 0x0010,

	/* Date Elements */
	NSYearMonthDatePickerElementFlag = 0x00c0,
	NSYearMonthDayDatePickerElementFlag = 0x00e0,
	NSEraDatePickerElementFlag = 0x0100
};

@protocol NSDatePickerCellDelegate;

/* ==================================================================================================================
 * THE CELL: THE DATE, THE DOORS THAT DECIDE HOW IT READS, AND THE EDIT.
 * ================================================================================================================ */

@interface NSDatePickerCell : NSActionCell
{
	NSDatePickerStyle _datePickerStyle;
	NSDatePickerMode _datePickerMode;
	NSDatePickerElementFlags _datePickerElements;

	NSDate *_dateValue;		/* RETAINED — the start date in range mode */
	NSDate *_minDate;		/* RETAINED, or nil for no floor */
	NSDate *_maxDate;		/* RETAINED, or nil for no ceiling */
	NSTimeInterval _timeInterval;	/* the LENGTH in range mode; 0 in single mode */

	NSCalendar *_calendar;		/* RETAINED, or nil for +currentCalendar */
	NSLocale *_locale;		/* RETAINED, or nil for +currentLocale */
	NSTimeZone *_timeZone;		/* RETAINED, or nil for the calendar's own */
	NSColor *_backgroundColor;	/* RETAINED */
	NSColor *_textColor;		/* RETAINED */
	BOOL _drawsBackground;

	id _delegate;			/* ASSIGNED, like target and like every delegate in this tier */
	NSInteger _indexOfSelectedSubfield;	/* which element the next step applies to; -1 until a press or key picks one */
	NSString *_cg_digitBuffer;	/* RETAINED — the digits typed into one subfield, mid-entry */
	NSInteger _cg_pressedArrow;	/* +1 the upper arrow, -1 the lower, 0 neither */
}

/* ---- APPEARANCE ----------------------------------------------------------------------------------- */

- (NSDatePickerStyle)datePickerStyle;
- (void)setDatePickerStyle:(NSDatePickerStyle)newStyle;

- (BOOL)drawsBackground;
- (void)setDrawsBackground:(BOOL)flag;
- (nullable NSColor *)backgroundColor;
- (void)setBackgroundColor:(nullable NSColor *)color;
- (nullable NSColor *)textColor;
- (void)setTextColor:(nullable NSColor *)color;

/* ---- RANGE MODE ----------------------------------------------------------------------------------- */

- (NSDatePickerMode)datePickerMode;
- (void)setDatePickerMode:(NSDatePickerMode)newMode;

/* ---- PRESENTATION --------------------------------------------------------------------------------- */

- (NSDatePickerElementFlags)datePickerElements;
- (void)setDatePickerElements:(NSDatePickerElementFlags)elementFlags;

/* **THESE THREE ARE THE FORMATTER'S CONFIGURATION AND THE ARITHMETIC'S CALENDAR, NOT STORED DECORATION.** The locale is
 * handed to the `NSDateFormatter` that produces the text; the time zone is set on the formatter AND on a copy of the calendar
 * used to read components and step fields; the calendar supplies the field arithmetic (`-dateByAddingUnit:`) and the month
 * grid's symbols. nil means "the platform's", and a caller who sets one sees the text follow. */
- (nullable NSCalendar *)calendar;
- (void)setCalendar:(nullable NSCalendar *)newCalendar;
- (nullable NSLocale *)locale;
- (void)setLocale:(nullable NSLocale *)newLocale;
- (nullable NSTimeZone *)timeZone;
- (void)setTimeZone:(nullable NSTimeZone *)newTimeZone;

/* ---- THE VALUE ------------------------------------------------------------------------------------ */

/* **THE DATE IS CLAMPED INTO [minDate, maxDate] AT ITS ONE SETTER**, because a picker showing a date outside the range it was
 * given is a picker that has already lied about its state. Setting either bound re-clamps the standing date; setting one
 * bound past the other PUSHES THE OTHER (the level indicator's range rule), so the interval never inverts.
 *
 * The default date is `+[NSDate date]` at construction; the default bounds are nil. */
- (nullable NSDate *)dateValue;
- (void)setDateValue:(nullable NSDate *)newStartDate;

/* The duration in range mode. Negative lengths are clamped to zero, because a range that ends before it starts is not a
 * range. */
- (NSTimeInterval)timeInterval;
- (void)setTimeInterval:(NSTimeInterval)newTimeInterval;

- (nullable NSDate *)minDate;
- (void)setMinDate:(nullable NSDate *)date;
- (nullable NSDate *)maxDate;
- (void)setMaxDate:(nullable NSDate *)date;

/* THE BASE CLASS'S VALUE IS THIS CELL'S DATE. `NSCell`'s object value is a generic slot; a date picker's value is a date, so
 * both doors are overridden rather than left to hold a second, divergent copy. A caller who sets a non-date object gets
 * nil-and-ignore, which is the same contract the base keeps for a value it cannot use. */
- (nullable id)objectValue;
- (void)setObjectValue:(nullable id)value;

/* ---- DELEGATE ------------------------------------------------------------------------------------- */

- (nullable id <NSDatePickerCellDelegate>)delegate;
- (void)setDelegate:(nullable id <NSDatePickerCellDelegate>)anObject;

/* ---- THE INSTRUMENT'S DOORS (cg_, NOT APPLE'S) ---------------------------------------------------- */

/* These exist because a probe has to read what the cell DRAWS and what a point SELECTS, which Apple's public header has no
 * door for. They are documented as this tree's, not the era's, exactly as `-cg_lineHeight` and `-cg_invalidatedRange` are. */

/* The finished text: one date in single mode, "start – end" in range mode. */
- (nullable NSString *)cg_displayText;
/* The pattern the element flags produced, through `+dateFormatFromTemplate:options:locale:`. */
- (nullable NSString *)cg_displayPattern;
/* How many subfields the text has (0 in range mode, where the two dates are not separately selectable). */
- (NSInteger)cg_numberOfSubfields;
/* Which element the Nth subfield is, as ONE of the six element flags (never a combination). */
- (NSDatePickerElementFlags)cg_elementAtIndex:(NSInteger)index;
/* Where the Nth subfield's run sits inside `frame`, measured from the text the cell would draw in that frame. */
- (NSRect)cg_rectOfSubfieldAtIndex:(NSInteger)index inFrame:(NSRect)frame;
- (NSInteger)cg_indexOfSelectedSubfield;

/* Select the subfield under a point — the press's hit test. YES when a run was found. In the stepper's strip this answers NO;
 * the arrows are not subfields. */
- (BOOL)cg_selectSubfieldAtPoint:(NSPoint)point inFrame:(NSRect)frame;

/* A REAL EDIT: step the selected element by `direction` calendar units, offer the proposal to the delegate, and store what
 * comes back. YES when the date changed. This is the door the arrows, the arrow keys and the tests all use. */
- (BOOL)cg_stepSelectedElementBy:(NSInteger)direction;

/* The cell's key handling: up/down step, left/right move the selection, a digit starts or extends this cell's digit buffer,
 * and any other key ends the buffer. YES when the CELL CONSUMED the key (a selection move counts), so the control can keep a
 * consumed key from travelling on to the window; the control decides whether the DATE changed and therefore whether the
 * action should speak. */
- (BOOL)cg_handleKeyDown:(NSEvent *)event;

/* THE MONTH GRID'S GEOMETRY, for the style that draws one: the rectangle of a day's cell, or NSZeroRect when the grid is
 * not the picture or the day is outside the shown month. */
- (NSRect)cg_rectForDay:(NSInteger)day inFrame:(NSRect)frame;

@end

/* ==================================================================================================================
 * THE DELEGATE: ONE MESSAGE, TWO OUT-PARAMETERS, AND A REFUSAL THAT IS A NIL DATE.
 * ================================================================================================================ */

/* **APPLE'S 10.6 PROTOCOL HAS EXACTLY THIS ONE OPTIONAL MESSAGE** (see the SDK's `NSDatePickerCell.h`), and it is the
 * interesting kind of delegate contract: the values are IN/OUT, so the delegate validates by REPLACING either one. A nil
 * proposed date is a refusal — the cell keeps the date it had — and a replaced interval is stored with the replaced date. The
 * cell sends it for every user-originated edit (stepping, typing, the arrows); it does not send it for a programmatic
 * `-setDateValue:`, which is Apple's split between "what a person asked for" and "what the application said". */
@protocol NSDatePickerCellDelegate <NSObject>
@optional
- (void)datePickerCell:(NSDatePickerCell *)aDatePickerCell
    validateProposedDateValue:(NSDate * _Nullable * _Nonnull)proposedDateValue
             timeInterval:(NSTimeInterval * _Nonnull)proposedTimeInterval;
@end

/* ==================================================================================================================
 * THE CONTROL: THIRTY FORWARDS AND THE KEY PATH.
 * ================================================================================================================ */

@interface NSDatePicker : NSControl

- (instancetype)initWithFrame:(NSRect)frameRect;

/* ---- APPEARANCE ----------------------------------------------------------------------------------- */
- (NSDatePickerStyle)datePickerStyle;
- (void)setDatePickerStyle:(NSDatePickerStyle)newStyle;
- (BOOL)isBezeled;
- (void)setBezeled:(BOOL)flag;
- (BOOL)isBordered;
- (void)setBordered:(BOOL)flag;
- (BOOL)drawsBackground;
- (void)setDrawsBackground:(BOOL)flag;
- (nullable NSColor *)backgroundColor;
- (void)setBackgroundColor:(nullable NSColor *)color;
- (nullable NSColor *)textColor;
- (void)setTextColor:(nullable NSColor *)color;

/* ---- RANGE MODE ----------------------------------------------------------------------------------- */
- (NSDatePickerMode)datePickerMode;
- (void)setDatePickerMode:(NSDatePickerMode)newMode;

/* ---- PRESENTATION --------------------------------------------------------------------------------- */
- (NSDatePickerElementFlags)datePickerElements;
- (void)setDatePickerElements:(NSDatePickerElementFlags)elementFlags;
- (nullable NSCalendar *)calendar;
- (void)setCalendar:(nullable NSCalendar *)newCalendar;
- (nullable NSLocale *)locale;
- (void)setLocale:(nullable NSLocale *)newLocale;
- (nullable NSTimeZone *)timeZone;
- (void)setTimeZone:(nullable NSTimeZone *)newTimeZone;

/* ---- THE VALUE ------------------------------------------------------------------------------------ */
- (nullable NSDate *)dateValue;
- (void)setDateValue:(nullable NSDate *)newStartDate;
- (NSTimeInterval)timeInterval;
- (void)setTimeInterval:(NSTimeInterval)newTimeInterval;
- (nullable NSDate *)minDate;
- (void)setMinDate:(nullable NSDate *)date;
- (nullable NSDate *)maxDate;
- (void)setMaxDate:(nullable NSDate *)date;

/* ---- DELEGATE ------------------------------------------------------------------------------------- */
- (nullable id <NSDatePickerCellDelegate>)delegate;
- (void)setDelegate:(nullable id <NSDatePickerCellDelegate>)anObject;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSDATEPICKER_H */
