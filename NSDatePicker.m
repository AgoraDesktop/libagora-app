/*
 * NSDatePicker — a date shown as text, the subfield a step applies to, and the delegate that may refuse it.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * The cell owns the date, the two bounds, the interval and the six doors that decide how the date READS; the control forwards.
 * The text is produced by an `NSDateFormatter` configured from the cell's own calendar, locale and time zone, and the pattern
 * is the locale's answer to the element skeleton — so there is no second formatting path for the layout to disagree with.
 *
 * The subfields are located in the formatted string rather than laid out beside it: the pattern is walked in its own order,
 * each field is formatted on its own, and the piece is found in the finished text. The rectangle a click selects is therefore
 * measured from the text that was drawn (prefix widths of the same attributed string), which is what keeps a date field's hit
 * test and its picture from drifting apart.
 */
#import "NSDatePicker.h"
#import "NSColor.h"
#import "NSFont.h"
#import "NSBezierPath.h"
#import "NSGraphics.h"
#import "NSGraphicsContext.h"
#import "NSView.h"
#import "NSControl.h"
#import "NSEvent.h"
#import "NSStringDrawing.h"
#import <Foundation/NSCalendar.h>
#import <Foundation/NSDateComponents.h>
#import <Foundation/NSDateFormatter.h>
#import <Foundation/NSLocale.h>
#import <Foundation/NSTimeZone.h>
#import <Foundation/NSCharacterSet.h>
#import <Foundation/NSString.h>

#include <math.h>
#include <stdlib.h>
#include <string.h>

/* THE STEPPER'S STRIP AND THE FIELD'S INSET, so the text and the arrows are one layout rather than two guesses. */
#define AG_DATE_STEPPER_WIDTH 13.0
#define AG_DATE_TEXT_INSET 3.0
#define AG_DATE_MAX_FIELDS 8

/* THE MONTH GRID'S BANDS. A header with the month and year, a weekday row, then six weeks of days. */
#define AG_DATE_GRID_INSET 4.0
#define AG_DATE_GRID_HEADER 17.0
#define AG_DATE_GRID_WEEKDAY 12.0
#define AG_DATE_GRID_ROWS 6

/* THE DAY BIT IS THE ONE ELEMENT APPLE HAS NO SINGLE-FLAG NAME FOR — it exists only inside the two combinations. */
#define AG_DATE_DAY_FLAG (NSYearMonthDayDatePickerElementFlag & ~NSYearMonthDatePickerElementFlag)

/* ==================================================================================================================
 * THE ELEMENTS, INTERNALLY — one per field of a date, not one per flag value (the flags are masks).
 * ================================================================================================================ */

typedef enum {
	AGDateElementEra = 0,
	AGDateElementYear,
	AGDateElementMonth,
	AGDateElementDay,
	AGDateElementHour,
	AGDateElementMinute,
	AGDateElementSecond,
	AGDateElementTimeZone,
	AGDateElementDayPeriod,	/* "AM" — part of the HOUR's subfield, never a subfield of its own */
	AGDateElementCount
} AGDateElement;

static NSDatePickerElementFlags fn_flag_for_element(AGDateElement element)
{
	switch (element) {
	case AGDateElementEra: return NSEraDatePickerElementFlag;
	case AGDateElementYear: return 0x0040;		/* the year half of NSYearMonthDatePickerElementFlag */
	case AGDateElementMonth: return 0x0080;		/* the month half */
	case AGDateElementDay: return AG_DATE_DAY_FLAG;
	case AGDateElementHour: return 0x0004;
	case AGDateElementMinute: return 0x0008;
	case AGDateElementSecond: return 0x0002;
	case AGDateElementTimeZone: return NSTimeZoneDatePickerElementFlag;
	case AGDateElementDayPeriod: case AGDateElementCount: break;
	}
	return 0;
}

static AGDateElement fn_element_for_letter(unichar letter)
{
	switch (letter) {
	case 'G': return AGDateElementEra;
	case 'y': case 'Y': case 'u': case 'U': case 'r': return AGDateElementYear;
	case 'M': case 'L': return AGDateElementMonth;
	case 'd': return AGDateElementDay;
	case 'h': case 'H': case 'k': case 'K': return AGDateElementHour;
	/* THE DAY PERIOD IS THE HOUR'S, in this tier: "AM" is part of the hour a person clicks, not a seventh field. It is kept
	 * as its own pattern field here because it is not adjacent to the hour in the pattern ("h:mm:ss a"), and the layout
	 * attaches it to the hour's run after the fact. */
	case 'a': case 'b': case 'B': return AGDateElementDayPeriod;
	case 'm': return AGDateElementMinute;
	case 's': case 'S': return AGDateElementSecond;
	case 'z': case 'Z': case 'v': case 'V': case 'O': case 'X': case 'x': return AGDateElementTimeZone;
	default: break;		/* E, D, w, W, F, Q, q and the rest are not elements this picker shows */
	}
	return AGDateElementCount;
}

static NSCalendarUnit fn_unit_for_element(AGDateElement element)
{
	switch (element) {
	case AGDateElementEra: return NSCalendarUnitEra;
	case AGDateElementYear: return NSCalendarUnitYear;
	case AGDateElementMonth: return NSCalendarUnitMonth;
	case AGDateElementDay: return NSCalendarUnitDay;
	case AGDateElementHour: return NSCalendarUnitHour;
	case AGDateElementMinute: return NSCalendarUnitMinute;
	case AGDateElementSecond: return NSCalendarUnitSecond;
	case AGDateElementTimeZone: case AGDateElementDayPeriod: case AGDateElementCount: break;
	}
	return 0;
}

/* THE SKELETON, not a pattern: the locale decides the order and the separators (MEASURED: "yMMMd jmmss" is
 * "MMM d, y, h:mm:ss a" in en_US and "d. MMM y, HH:mm:ss" in de_DE). `j` is ICU's "the locale's preferred hour", which is
 * what makes a de_DE picker 24-hour without this file carrying a 24-hour table. */
static NSString *fn_skeleton_for_flags(NSDatePickerElementFlags flags)
{
	NSMutableString *skeleton = [NSMutableString string];

	if (flags & NSEraDatePickerElementFlag) {
		[skeleton appendString:@"G"];
	}
	if (flags & 0x0040) {
		[skeleton appendString:@"y"];
	}
	if (flags & 0x0080) {
		[skeleton appendString:@"MMM"];
	}
	if (flags & AG_DATE_DAY_FLAG) {
		[skeleton appendString:@"d"];
	}
	if (flags & 0x0004) {
		[skeleton appendString:@"j"];
	}
	if (flags & 0x0008) {
		[skeleton appendString:@"mm"];
	}
	if (flags & 0x0002) {
		[skeleton appendString:@"ss"];
	}
	if (flags & NSTimeZoneDatePickerElementFlag) {
		[skeleton appendString:@"z"];
	}
	return skeleton;
}

/* A FIELD OF THE PATTERN: the element it belongs to and the LETTERS to format it with ("MMM", "HH", "h", "a", "z"). */
typedef struct {
	AGDateElement element;
	char letters[8];
} AGDatePatternField;

/* Walk ICU's pattern, not its skeleton: the pattern is what the formatter will actually render, so its field order is the
 * order the text has. Quoted literals are skipped (an apostrophe toggles quoting, as ICU's syntax says). */
static NSInteger fn_pattern_fields(NSString *pattern, AGDatePatternField *out, NSInteger capacity)
{
	NSUInteger length = [pattern length];
	NSUInteger i;
	BOOL quoted = NO;
	char run[8];
	NSInteger runLength = 0;
	unichar runLetter = 0;
	NSInteger count = 0;

	if (pattern == nil || capacity <= 0) {
		return 0;
	}
	memset(out, 0, (size_t)capacity * sizeof *out);

#define FLUSH_RUN() do {									\
	if (runLength > 0 && count < capacity) {						\
		AGDateElement element = fn_element_for_letter(runLetter);			\
		if (element != AGDateElementCount) {						\
			run[runLength] = '\0';							\
			out[count].element = element;						\
			strncpy(out[count].letters, run, sizeof out[count].letters - 1);		\
			count++;								\
		}										\
	}											\
	runLength = 0;										\
} while (0)

	for (i = 0; i < length; i++) {
		unichar c = [pattern characterAtIndex:i];

		if (c == '\'') {
			/* ICU spells a literal apostrophe as '' inside a quoted run; two in a row are a literal. */
			quoted = !quoted;
			FLUSH_RUN();
			continue;
		}
		if (quoted) {
			FLUSH_RUN();
			continue;
		}
		if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')) {
			if (runLength > 0 && c == runLetter && runLength < (NSInteger)sizeof run - 1) {
				run[runLength++] = (char)c;
			} else {
				FLUSH_RUN();
				runLetter = c;
				run[runLength++] = (char)c;
			}
		} else {
			FLUSH_RUN();
		}
	}
	FLUSH_RUN();
#undef FLUSH_RUN
	return count;
}

/* The number of SUBFIELDS: the day period belongs to the hour, so "h ... a" is one subfield, not two. */
static NSInteger fn_unique_field_count(AGDatePatternField *fields, NSInteger count)
{
	NSInteger i, unique = 0;

	for (i = 0; i < count; i++) {
		if (fields[i].element != AGDateElementDayPeriod) {
			unique++;
		}
	}
	return unique;
}

/* ==================================================================================================================
 * THE LAYOUT: THE TEXT, ITS ROOM, AND EACH SUBFIELD'S RUN MEASURED INSIDE IT.
 * ================================================================================================================ */

typedef struct {
	NSString *text;			/* autoreleased */
	NSRect textRect;
	NSInteger count;
	AGDateElement elements[AG_DATE_MAX_FIELDS];
	NSRect rects[AG_DATE_MAX_FIELDS];	/* NSZeroRect for a field whose piece was not found */
	NSRange ranges[AG_DATE_MAX_FIELDS];
} AGDateLayout;

static NSDictionary *fn_text_attributes(NSFont *font, NSColor *ink)
{
	return [NSDictionary dictionaryWithObjectsAndKeys:font, NSFontAttributeName, ink, NSForegroundColorAttributeName, nil];
}

/* ==================================================================================================================
 * THE CELL.
 * ================================================================================================================ */

@implementation NSDatePickerCell

- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		/* **APPLE'S DEFAULTS, AS FAR AS THE ERA PUBLISHES THEM.** A date picker shows the whole date and the whole time, is
		 * a text field with a stepper, draws its background, is bezeled, and starts at NOW. The two bounds start nil,
		 * which means "no bound" rather than "bound at the epoch". */
		_datePickerStyle = NSTextFieldAndStepperDatePickerStyle;
		_datePickerMode = NSSingleDateMode;
		_datePickerElements = NSYearMonthDayDatePickerElementFlag | NSHourMinuteSecondDatePickerElementFlag;
		_dateValue = [[NSDate alloc] init];
		_minDate = nil;
		_maxDate = nil;
		_timeInterval = 0.0;
		_calendar = [[NSCalendar currentCalendar] retain];
		_locale = [[NSLocale currentLocale] retain];
		_timeZone = nil;
		_backgroundColor = nil;
		_textColor = nil;
		_drawsBackground = YES;
		_delegate = nil;
		_indexOfSelectedSubfield = -1;	/* nothing is selected until a press or a key picks a field */
		_cg_digitBuffer = nil;
		_cg_pressedArrow = 0;
		[self setBezeled:YES];
		[self setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
	}
	return self;
}

- (void)dealloc
{
	[_dateValue release];
	[_minDate release];
	[_maxDate release];
	[_calendar release];
	[_locale release];
	[_timeZone release];
	[_backgroundColor release];
	[_textColor release];
	[_cg_digitBuffer release];
	[super dealloc];
}

/* ---- APPEARANCE ----------------------------------------------------------------------------------- */

- (NSDatePickerStyle)datePickerStyle { return _datePickerStyle; }
- (void)setDatePickerStyle:(NSDatePickerStyle)newStyle
{
	_datePickerStyle = newStyle;
	[[self controlView] setNeedsDisplay:YES];
}

- (BOOL)drawsBackground { return _drawsBackground; }
- (void)setDrawsBackground:(BOOL)flag
{
	_drawsBackground = flag;
	[[self controlView] setNeedsDisplay:YES];
}

- (NSColor *)backgroundColor { return _backgroundColor; }
- (void)setBackgroundColor:(NSColor *)color
{
	NSColor *held = [color retain];

	[_backgroundColor release];
	_backgroundColor = held;
	[[self controlView] setNeedsDisplay:YES];
}

- (NSColor *)textColor { return _textColor; }
- (void)setTextColor:(NSColor *)color
{
	NSColor *held = [color retain];

	[_textColor release];
	_textColor = held;
	[[self controlView] setNeedsDisplay:YES];
}

/* ---- RANGE MODE ----------------------------------------------------------------------------------- */

- (NSDatePickerMode)datePickerMode { return _datePickerMode; }
- (void)setDatePickerMode:(NSDatePickerMode)newMode
{
	_datePickerMode = newMode;
	[[self controlView] setNeedsDisplay:YES];
}

/* ---- PRESENTATION --------------------------------------------------------------------------------- */

- (NSDatePickerElementFlags)datePickerElements { return _datePickerElements; }
- (void)setDatePickerElements:(NSDatePickerElementFlags)elementFlags
{
	_datePickerElements = elementFlags;
	/* A selection past the new field list would step nothing; the first field is a better answer than a dead cursor. */
	if (_indexOfSelectedSubfield >= [self cg_numberOfSubfields]) {
		_indexOfSelectedSubfield = ([self cg_numberOfSubfields] > 0) ? 0 : -1;
	}
	[[self controlView] setNeedsDisplay:YES];
}

- (NSCalendar *)calendar { return _calendar; }
- (void)setCalendar:(NSCalendar *)newCalendar
{
	NSCalendar *held = [newCalendar retain];

	[_calendar release];
	_calendar = held;
	[[self controlView] setNeedsDisplay:YES];
}

- (NSLocale *)locale { return _locale; }
- (void)setLocale:(NSLocale *)newLocale
{
	NSLocale *held = [newLocale retain];

	[_locale release];
	_locale = held;
	[[self controlView] setNeedsDisplay:YES];
}

- (NSTimeZone *)timeZone { return _timeZone; }
- (void)setTimeZone:(NSTimeZone *)newTimeZone
{
	NSTimeZone *held = [newTimeZone retain];

	[_timeZone release];
	_timeZone = held;
	[[self controlView] setNeedsDisplay:YES];
}

/* **THE CALENDAR THE FORMATTER AND THE ARITHMETIC BOTH USE.** The cell's time zone is a separate door from its calendar, so
 * the effective calendar is a COPY with that zone applied — the caller's calendar is not mutated under them, and "the hour
 * the text shows" and "the hour a step adds" come from the same calendar. nil zone means the calendar's own. */
- (NSCalendar *)cg_effectiveCalendar
{
	NSCalendar *base = (_calendar != nil) ? _calendar : [NSCalendar currentCalendar];
	NSCalendar *cal = [[base copy] autorelease];

	if (_timeZone != nil) {
		[cal setTimeZone:_timeZone];
	}
	return cal;
}

- (NSDateFormatter *)cg_formatterWithPattern:(NSString *)pattern
{
	NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];

	if (_locale != nil) {
		[formatter setLocale:_locale];
	}
	[formatter setCalendar:[self cg_effectiveCalendar]];
	if (_timeZone != nil) {
		[formatter setTimeZone:_timeZone];
	}
	if (pattern != nil) {
		[formatter setDateFormat:pattern];
	}
	return formatter;
}

- (NSString *)cg_displayPattern
{
	NSLocale *locale = (_locale != nil) ? _locale : [NSLocale currentLocale];
	NSString *skeleton = fn_skeleton_for_flags(_datePickerElements);

	if ([skeleton length] == 0) {
		return nil;
	}
	return [NSDateFormatter dateFormatFromTemplate:skeleton options:0 locale:locale];
}

- (NSDate *)cg_shownDate
{
	return (_dateValue != nil) ? _dateValue : [NSDate date];
}

- (NSString *)cg_displayText
{
	NSString *pattern = [self cg_displayPattern];
	NSDateFormatter *formatter;
	NSString *first;

	if (pattern == nil) {
		return nil;
	}
	formatter = [self cg_formatterWithPattern:pattern];
	first = [formatter stringFromDate:[self cg_shownDate]];
	if (first == nil) {
		return nil;
	}
	if (_datePickerMode == NSRangeDateMode) {
		NSDate *end = [[self cg_shownDate] dateByAddingTimeInterval:_timeInterval];
		NSString *second = [formatter stringFromDate:end];

		if (second != nil) {
			return [NSString stringWithFormat:@"%@ - %@", first, second];
		}
	}
	return first;
}

/* ---- THE VALUE ------------------------------------------------------------------------------------ */

- (NSDate *)dateValue { return _dateValue; }

- (void)setDateValue:(NSDate *)newStartDate
{
	NSDate *held;

	if (newStartDate == nil) {
		[_dateValue release];
		_dateValue = nil;
		[[self controlView] setNeedsDisplay:YES];
		return;
	}
	/* **THE ONE CLAMP.** A date outside the bounds is not a state a picker shows, so the two bounds are applied at the
	 * door every write goes through — programmatic and user alike. */
	held = [newStartDate copy];
	if (_minDate != nil && [held compare:_minDate] == NSOrderedAscending) {
		[held release];
		held = [_minDate copy];
	}
	if (_maxDate != nil && [held compare:_maxDate] == NSOrderedDescending) {
		[held release];
		held = [_maxDate copy];
	}
	[_dateValue release];
	_dateValue = held;
	[[self controlView] setNeedsDisplay:YES];
}

- (NSTimeInterval)timeInterval { return _timeInterval; }
- (void)setTimeInterval:(NSTimeInterval)newTimeInterval
{
	_timeInterval = (newTimeInterval > 0.0) ? newTimeInterval : 0.0;
	[[self controlView] setNeedsDisplay:YES];
}

- (NSDate *)minDate { return _minDate; }
- (void)setMinDate:(NSDate *)date
{
	NSDate *held = [date copy];

	[_minDate release];
	_minDate = held;
	/* A RANGE THAT INVERTS IS NOT A RANGE: the guard band and the level indicator both push the other end. */
	if (_minDate != nil && _maxDate != nil && [_minDate compare:_maxDate] == NSOrderedDescending) {
		NSDate *pushed = [_minDate copy];

		[_maxDate release];
		_maxDate = pushed;
	}
	if (_dateValue != nil) {
		[self setDateValue:_dateValue];		/* re-clamped */
	}
	[[self controlView] setNeedsDisplay:YES];
}

- (NSDate *)maxDate { return _maxDate; }
- (void)setMaxDate:(NSDate *)date
{
	NSDate *held = [date copy];

	[_maxDate release];
	_maxDate = held;
	if (_minDate != nil && _maxDate != nil && [_minDate compare:_maxDate] == NSOrderedDescending) {
		NSDate *pushed = [_maxDate copy];

		[_minDate release];
		_minDate = pushed;
	}
	if (_dateValue != nil) {
		[self setDateValue:_dateValue];
	}
	[[self controlView] setNeedsDisplay:YES];
}

/* **ONE VALUE, TWO DOORS.** `NSCell`'s object slot is generic; this cell's value is a date, so both doors are overridden
 * rather than leaving a second copy behind. A non-date object is ignored — the same contract the base keeps for a value it
 * cannot use — and nil clears the date (which draws nothing). */
- (id)objectValue
{
	return _dateValue;
}

- (void)setObjectValue:(id)value
{
	if (value == nil) {
		[self setDateValue:nil];
		return;
	}
	if ([value isKindOfClass:[NSDate class]]) {
		[self setDateValue:(NSDate *)value];
	}
}

/* ---- DELEGATE ------------------------------------------------------------------------------------- */

- (id <NSDatePickerCellDelegate>)delegate { return _delegate; }
- (void)setDelegate:(id <NSDatePickerCellDelegate>)anObject { _delegate = anObject; }

/* ==================================================================================================================
 * THE OFFER: THE ONE PLACE A USER EDIT BECOMES A STORED DATE.
 * ================================================================================================================ */

/* The delegate is asked in the era's in/out form. A nil date is a REFUSAL (the cell keeps what it had); a replaced date or
 * interval is what gets stored; and the store's own clamp still applies afterwards, so a delegate cannot widen the bounds by
 * answering past them. */
- (BOOL)cg_offerDateValue:(NSDate *)proposed timeInterval:(NSTimeInterval)interval
{
	if (proposed == nil) {
		return NO;
	}
	if (_delegate != nil && [_delegate respondsToSelector:
			@selector(datePickerCell:validateProposedDateValue:timeInterval:)]) {
		NSDate *candidate = proposed;
		NSTimeInterval candidateInterval = interval;

		[_delegate datePickerCell:self
			validateProposedDateValue:&candidate
				 timeInterval:&candidateInterval];
		if (candidate == nil) {
			return NO;
		}
		proposed = candidate;
		interval = candidateInterval;
	}
	[self setDateValue:proposed];
	[self setTimeInterval:interval];
	return YES;
}

/* ==================================================================================================================
 * THE LAYOUT.
 * ================================================================================================================ */

- (NSRect)cg_textRectForFrame:(NSRect)frame
{
	CGFloat inset = AG_DATE_TEXT_INSET + (([self isBezeled] || [self isBordered]) ? NS_CELL_BEZEL_WIDTH : 0.0);
	NSRect room = NSInsetRect(frame, inset, 1.0);

	if (_datePickerStyle == NSTextFieldAndStepperDatePickerStyle) {
		room.size.width -= AG_DATE_STEPPER_WIDTH;
	}
	if (room.size.width < 0.0) {
		room.size.width = 0.0;
	}
	if (room.size.height < 0.0) {
		room.size.height = 0.0;
	}
	return room;
}

- (NSRect)cg_stepperRectForFrame:(NSRect)frame
{
	return NSMakeRect(NSMaxX(frame) - AG_DATE_STEPPER_WIDTH, NSMinY(frame),
			  AG_DATE_STEPPER_WIDTH, NSHeight(frame));
}

- (NSColor *)cg_inkColor
{
	if (_textColor != nil) {
		return _textColor;
	}
	return [self isEnabled] ? [NSColor controlTextColor] : [NSColor disabledControlTextColor];
}

- (NSColor *)cg_fillColor
{
	return (_backgroundColor != nil) ? _backgroundColor : [NSColor controlBackgroundColor];
}

- (NSFont *)cg_font
{
	NSFont *font = (NSFont *)[self font];

	return (font != nil) ? font : [NSFont systemFontOfSize:[NSFont systemFontSize]];
}

/* The baseline rule is `NSTextFieldCell`'s, for the same measured reason: a bitmap and a flipped view have opposite CTMs, and
 * the sign belongs to the context rather than to a guess. */
- (CGFloat)cg_baselineInFrame:(NSRect)frame font:(NSFont *)font
{
	CGFloat ascender = [font ascender];
	CGFloat descent = (CGFloat)fabs((double)[font descender]);
	CGContextRef cg = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
	CGAffineTransform transform = cg != NULL ? CGContextGetCTM(cg) : CGAffineTransformIdentity;

	return NSMidY(frame) + (transform.d >= 0.0 ? 1.0 : -1.0) * ((ascender - descent) / 2.0);
}

/* Is the piece at `range` a whole token, or the tail of a longer number/word? "6" must not match inside "2026". */
static BOOL fn_token_boundary(NSString *text, NSRange range, NSString *piece)
{
	NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
	NSCharacterSet *letters = [NSCharacterSet letterCharacterSet];
	NSCharacterSet *set;

	if ([piece length] == 0) {
		return NO;
	}
	set = [digits characterIsMember:[piece characterAtIndex:0]] ? digits : letters;
	if (range.location > 0 && [set characterIsMember:[text characterAtIndex:range.location - 1]]) {
		return NO;
	}
	if (NSMaxRange(range) < [text length] && [set characterIsMember:[text characterAtIndex:NSMaxRange(range)]]) {
		return NO;
	}
	return YES;
}

static NSRange fn_find_piece(NSString *text, NSString *piece, NSUInteger from)
{
	NSUInteger length = [text length];
	NSUInteger start = (from < length) ? from : length;

	while (start < length) {
		NSRange found = [text rangeOfString:piece options:0 range:NSMakeRange(start, length - start)];

		if (found.location == NSNotFound) {
			break;
		}
		if (fn_token_boundary(text, found, piece)) {
			return found;
		}
		start = found.location + 1;
	}
	return NSMakeRange(NSNotFound, 0);
}

- (AGDateLayout)cg_layoutInFrame:(NSRect)frame
{
	AGDateLayout layout;
	NSString *pattern = [self cg_displayPattern];
	NSDictionary *attributes = fn_text_attributes([self cg_font], [self cg_inkColor]);
	AGDatePatternField fields[AG_DATE_MAX_FIELDS * 2];
	NSInteger fieldCount, i;
	NSDateFormatter *formatter;
	NSDate *date = [self cg_shownDate];
	CGFloat baseline = [self cg_baselineInFrame:frame font:[self cg_font]];
	NSUInteger cursor = 0;

	memset(&layout, 0, sizeof layout);
	layout.textRect = [self cg_textRectForFrame:frame];
	layout.text = [self cg_displayText];
	if (pattern == nil || layout.text == nil || [layout.text length] == 0) {
		return layout;
	}
	fieldCount = fn_pattern_fields(pattern, fields, AG_DATE_MAX_FIELDS * 2);
	formatter = [self cg_formatterWithPattern:nil];

	for (i = 0; i < fieldCount; i++) {
		NSString *letters = [NSString stringWithUTF8String:fields[i].letters];
		NSString *piece;
		NSRange found;
		NSInteger index;

		[formatter setDateFormat:letters];
		piece = [formatter stringFromDate:date];
		if (piece == nil || [piece length] == 0) {
			continue;
		}
		found = fn_find_piece(layout.text, piece, cursor);
		if (found.location == NSNotFound) {
			/* The field's own rendering did not survive the combination (a locale can widen or quote it). A day period is
			 * not a subfield at all, so it simply drops; any other field leaves a zero rect so the index stays aligned
			 * with -cg_elementAtIndex:. */
			if (fields[i].element == AGDateElementDayPeriod) {
				continue;
			}
			layout.elements[layout.count] = fields[i].element;
			layout.rects[layout.count] = NSZeroRect;
			layout.ranges[layout.count] = NSMakeRange(NSNotFound, 0);
			layout.count++;
			continue;
		}
		cursor = NSMaxRange(found);
		if (fields[i].element == AGDateElementDayPeriod) {
			/* **THE DAY PERIOD EXTENDS THE HOUR**, wherever the locale put it: one clickable "12 AM", not "12" and a
			 * separate "AM". */
			NSInteger j;

			for (j = 0; j < layout.count; j++) {
				if (layout.elements[j] == AGDateElementHour) {
					CGFloat x0 = NSMinX(layout.rects[j]);
					CGFloat x1 = NSMinX(layout.textRect) + [[layout.text substringToIndex:NSMaxRange(found)]
						sizeWithAttributes:attributes].width;
					CGFloat descent = (CGFloat)fabs((double)[[self cg_font] descender]);

					layout.rects[j] = NSMakeRect(x0, baseline + descent, x1 - x0,
								     [[self cg_font] ascender] - descent);
					layout.ranges[j] = NSMakeRange(layout.ranges[j].location,
								       NSMaxRange(found) - layout.ranges[j].location);
					break;
				}
			}
			continue;
		}
		if (layout.count >= AG_DATE_MAX_FIELDS) {
			continue;
		}
		index = layout.count;
		layout.elements[index] = fields[i].element;
		layout.ranges[index] = found;
		{
			CGFloat x0 = NSMinX(layout.textRect) + [[layout.text substringToIndex:found.location]
				sizeWithAttributes:attributes].width;
			CGFloat x1 = NSMinX(layout.textRect) + [[layout.text substringToIndex:NSMaxRange(found)]
				sizeWithAttributes:attributes].width;
			CGFloat descent = (CGFloat)fabs((double)[[self cg_font] descender]);

			layout.rects[index] = NSMakeRect(x0, baseline + descent, x1 - x0,
							 [[self cg_font] ascender] - descent);
		}
		layout.count++;
	}
	return layout;
}

/* ---- THE INSTRUMENT'S LAYOUT DOORS ---------------------------------------------------------------- */

- (NSInteger)cg_numberOfSubfields
{
	AGDatePatternField fields[AG_DATE_MAX_FIELDS * 2];
	NSInteger count;

	if ([self cg_displayPattern] == nil) {
		return 0;
	}
	count = fn_pattern_fields([self cg_displayPattern], fields, AG_DATE_MAX_FIELDS * 2);
	return fn_unique_field_count(fields, count);
}

- (NSDatePickerElementFlags)cg_elementAtIndex:(NSInteger)index
{
	AGDatePatternField fields[AG_DATE_MAX_FIELDS * 2];
	NSInteger count, i, unique = 0;

	if (index < 0 || [self cg_displayPattern] == nil) {
		return 0;
	}
	count = fn_pattern_fields([self cg_displayPattern], fields, AG_DATE_MAX_FIELDS * 2);
	for (i = 0; i < count; i++) {
		if (fields[i].element == AGDateElementDayPeriod) {
			continue;
		}
		if (unique == index) {
			return fn_flag_for_element(fields[i].element);
		}
		unique++;
	}
	return 0;
}

- (NSRect)cg_rectOfSubfieldAtIndex:(NSInteger)index inFrame:(NSRect)frame
{
	AGDateLayout layout;

	if (_datePickerMode == NSRangeDateMode) {
		/* Two dates share one pattern; a rectangle would name the wrong one of them. The selection still exists for the
		 * keyboard (see `-cg_elementAtIndex:`), which is why this is a zero rect and not a zero count. */
		return NSZeroRect;
	}
	layout = [self cg_layoutInFrame:frame];
	if (index < 0 || index >= layout.count) {
		return NSZeroRect;
	}
	return layout.rects[index];
}

- (NSInteger)cg_indexOfSelectedSubfield { return _indexOfSelectedSubfield; }

- (BOOL)cg_selectSubfieldAtPoint:(NSPoint)point inFrame:(NSRect)frame
{
	AGDateLayout layout;
	NSInteger i;

	if (_datePickerStyle == NSClockAndCalendarDatePickerStyle || _datePickerMode == NSRangeDateMode) {
		return NO;
	}
	layout = [self cg_layoutInFrame:frame];
	if (!NSPointInRect(point, layout.textRect)) {
		return NO;
	}
	for (i = 0; i < layout.count; i++) {
		NSRect run = layout.rects[i];

		if (NSWidth(run) <= 0.0) {
			continue;
		}
		/* The x IS the run's; the y only has to be in the field, because a date field selects its subfield from a click
		 * anywhere on the line, not only on the glyphs' band. */
		if (point.x >= NSMinX(run) && point.x < NSMaxX(run)) {
			_indexOfSelectedSubfield = i;
			[[self controlView] setNeedsDisplay:YES];
			return YES;
		}
	}
	_indexOfSelectedSubfield = -1;
	[[self controlView] setNeedsDisplay:YES];
	return NO;
}

- (AGDateElement)cg_selectedElement
{
	NSDatePickerElementFlags flag;
	AGDateElement element;

	if (_indexOfSelectedSubfield < 0) {
		/* A STEP WITH NOTHING SELECTED APPLIES TO THE FIRST FIELD, and showing it afterwards is the honest answer: the
		 * cursor is where the change happened. */
		_indexOfSelectedSubfield = 0;
	}
	flag = [self cg_elementAtIndex:_indexOfSelectedSubfield];
	for (element = AGDateElementEra; element < AGDateElementCount; element++) {
		if (flag != 0 && fn_flag_for_element(element) == flag) {
			return element;
		}
	}
	/* A mask-only match (year/month share a flag word) falls through the exact test; ask the bits. */
	if (flag & 0x0040) return AGDateElementYear;
	if (flag & 0x0080) return AGDateElementMonth;
	if (flag & AG_DATE_DAY_FLAG) return AGDateElementDay;
	if (flag & 0x0004) return AGDateElementHour;
	if (flag & 0x0008) return AGDateElementMinute;
	if (flag & 0x0002) return AGDateElementSecond;
	if (flag & NSEraDatePickerElementFlag) return AGDateElementEra;
	if (flag & NSTimeZoneDatePickerElementFlag) return AGDateElementTimeZone;
	return AGDateElementMonth;
}

/* ---- THE EDIT ------------------------------------------------------------------------------------- */

- (BOOL)cg_stepSelectedElementBy:(NSInteger)direction
{
	AGDateElement element = [self cg_selectedElement];
	NSCalendarUnit unit = fn_unit_for_element(element);
	NSDate *proposed;

	if (unit == 0) {
		return NO;		/* the time zone is a label here, not a field a step moves */
	}
	proposed = [[self cg_effectiveCalendar] dateByAddingUnit:unit
							  value:direction
							 toDate:[self cg_shownDate]
							options:0];
	return [self cg_offerDateValue:proposed timeInterval:_timeInterval];
}

/* The absolute width a field's digits can reach. Month/day's REAL maximum is the calendar's (February has 28), applied
 * after this check; the reset-on-overflow rule is the era's "typing replaces once the buffer cannot be a prefix". */
static NSInteger fn_digits_for_element(AGDateElement element)
{
	switch (element) {
	case AGDateElementYear: return 4;
	case AGDateElementEra: return 1;
	case AGDateElementTimeZone: return 0;
	default: return 2;
	}
}

static NSInteger fn_absolute_max_for_element(AGDateElement element)
{
	switch (element) {
	case AGDateElementYear: return 9999;
	case AGDateElementEra: return 1;
	case AGDateElementMonth: return 12;
	case AGDateElementDay: return 31;
	case AGDateElementHour: return 23;
	case AGDateElementMinute: return 59;
	case AGDateElementSecond: return 59;
	default: return 0;
	}
}

- (BOOL)cg_applyValue:(NSInteger)value toElement:(AGDateElement)element
{
	NSCalendar *calendar = [self cg_effectiveCalendar];
	NSDate *base = [self cg_shownDate];
	NSDateComponents *components = [calendar components:(NSCalendarUnitEra | NSCalendarUnitYear |
							     NSCalendarUnitMonth | NSCalendarUnitDay |
							     NSCalendarUnitHour | NSCalendarUnitMinute |
							     NSCalendarUnitSecond)
						    fromDate:base];
	NSDate *proposed;

	if (element == AGDateElementDay) {
		NSRange days = [calendar rangeOfUnit:NSCalendarUnitDay
					      inUnit:NSCalendarUnitMonth
					     forDate:base];

		if (value < 1) value = 1;
		if (value > (NSInteger)(days.location + days.length - 1)) {
			value = (NSInteger)(days.location + days.length - 1);
		}
	}
	if ((element == AGDateElementMonth || element == AGDateElementDay) && value < 1) {
		value = 1;
	}
	if (value < 0) {
		value = 0;
	}
	switch (element) {
	case AGDateElementEra: [components setEra:value]; break;
	case AGDateElementYear: [components setYear:value]; break;
	case AGDateElementMonth: [components setMonth:value]; break;
	case AGDateElementDay: [components setDay:value]; break;
	case AGDateElementHour: [components setHour:value]; break;
	case AGDateElementMinute: [components setMinute:value]; break;
	case AGDateElementSecond: [components setSecond:value]; break;
	case AGDateElementTimeZone: case AGDateElementDayPeriod: case AGDateElementCount: return NO;
	}
	proposed = [calendar dateFromComponents:components];
	return [self cg_offerDateValue:proposed timeInterval:_timeInterval];
}

- (BOOL)cg_handleKeyDown:(NSEvent *)event
{
	NSString *characters = [event characters];
	AGDateElement element = [self cg_selectedElement];
	NSInteger digits;
	NSString *buffer;
	NSInteger value;

	if (characters == nil || [characters length] == 0) {
		return NO;
	}
	{
		unichar key = [characters characterAtIndex:0];

		if (key == NSUpArrowFunctionKey || key == NSDownArrowFunctionKey) {
			[_cg_digitBuffer release];
			_cg_digitBuffer = nil;
			(void)[self cg_stepSelectedElementBy:(key == NSUpArrowFunctionKey) ? 1 : -1];
			return YES;
		}
		if (key == NSLeftArrowFunctionKey || key == NSRightArrowFunctionKey) {
			NSInteger count = [self cg_numberOfSubfields];

			[_cg_digitBuffer release];
			_cg_digitBuffer = nil;
			if (count > 0) {
				NSInteger index = _indexOfSelectedSubfield + ((key == NSRightArrowFunctionKey) ? 1 : -1);

				if (index < 0) index = count - 1;
				if (index >= count) index = 0;
				_indexOfSelectedSubfield = index;
				[[self controlView] setNeedsDisplay:YES];
			}
			return YES;
		}
	}
	{
		NSCharacterSet *digitsSet = [NSCharacterSet decimalDigitCharacterSet];
		NSUInteger i;

		for (i = 0; i < [characters length]; i++) {
			if (![digitsSet characterIsMember:[characters characterAtIndex:i]]) {
				[_cg_digitBuffer release];
				_cg_digitBuffer = nil;
				return NO;
			}
		}
	}
	digits = fn_digits_for_element(element);
	if (digits <= 0) {
		return NO;
	}
	buffer = [NSString stringWithFormat:@"%@%@", (_cg_digitBuffer != nil) ? _cg_digitBuffer : @"", characters];
	if ((NSInteger)[buffer length] > digits) {
		buffer = characters;
	}
	value = atoi([buffer UTF8String]);
	if (value > fn_absolute_max_for_element(element)) {
		buffer = characters;
		value = atoi([buffer UTF8String]);
	}
	[_cg_digitBuffer release];
	_cg_digitBuffer = ([buffer length] >= (NSUInteger)digits) ? nil : [buffer copy];
	return [self cg_applyValue:value toElement:element];
}

/* ---- TRACKING ------------------------------------------------------------------------------------- */

/* The press selects the subfield it is over; in the stepper's strip it is a step instead, and the side is the arrow's side.
 * `NSStepperCell` records why the flip matters: "up" is the larger y in an unflipped view and the smaller one in a flipped
 * view, and a date picker drawn upside down is still a date picker. */
- (BOOL)startTrackingAt:(NSPoint)startPoint inView:(NSView *)controlView
{
	NSRect frame = [controlView bounds];
	BOOL flipped = [controlView isFlipped];

	_cg_pressedArrow = 0;
	if (_datePickerStyle == NSTextFieldAndStepperDatePickerStyle
	    && NSPointInRect(startPoint, [self cg_stepperRectForFrame:frame])) {
		BOOL upper = flipped ? (startPoint.y < NSMidY(frame)) : (startPoint.y > NSMidY(frame));

		_cg_pressedArrow = upper ? 1 : -1;
		(void)[self cg_stepSelectedElementBy:_cg_pressedArrow];
	} else {
		(void)[self cg_selectSubfieldAtPoint:startPoint inFrame:frame];
	}
	[controlView setNeedsDisplay:YES];
	return YES;
}

- (BOOL)continueTracking:(NSPoint)lastPoint at:(NSPoint)currentPoint inView:(NSView *)controlView
{
	(void)lastPoint;
	(void)currentPoint;
	(void)controlView;
	/* A drag across the arrows does not step again: the press stepped once, and one gesture is one step. */
	return YES;
}

- (void)stopTracking:(NSPoint)lastPoint at:(NSPoint)stopPoint inView:(NSView *)controlView mouseIsUp:(BOOL)flag
{
	(void)lastPoint;
	(void)stopPoint;
	(void)flag;
	_cg_pressedArrow = 0;
	[controlView setNeedsDisplay:YES];
}

/* ==================================================================================================================
 * THE PICTURES.
 * ================================================================================================================ */

- (void)cg_drawFaceInFrame:(NSRect)frame
{
	CGFloat radius = NS_CELL_BEZEL_RADIUS;
	NSRect faceRect = NSInsetRect(frame, NS_CELL_BEZEL_WIDTH / 2.0, NS_CELL_BEZEL_WIDTH / 2.0);
	NSBezierPath *face;

	if (!_drawsBackground && ![self isBezeled] && ![self isBordered]) {
		return;
	}
	if (NSWidth(faceRect) <= 0.0 || NSHeight(faceRect) <= 0.0) {
		return;
	}
	face = [NSBezierPath bezierPathWithRoundedRect:faceRect xRadius:radius yRadius:radius];
	if (_drawsBackground) {
		[[self cg_fillColor] setFill];
		[face fill];
	}
	if ([self isBezeled] || [self isBordered]) {
		[[NSColor controlDarkShadowColor] setStroke];
		[face setLineWidth:NS_CELL_BEZEL_WIDTH];
		[face stroke];
	}
}

/* The text, then the selected run again in the accent — at the same baseline and the same measured x, so the highlight lands
 * on the glyphs it belongs to instead of beside them. */
- (void)cg_drawTextForLayout:(AGDateLayout)layout selected:(NSInteger)selected
{
	NSFont *font = [self cg_font];
	NSDictionary *attributes = fn_text_attributes(font, [self cg_inkColor]);
	CGFloat baseline = [self cg_baselineInFrame:layout.textRect font:font];

	if (layout.text == nil || NSWidth(layout.textRect) <= 0.0) {
		return;
	}
	[NSGraphicsContext saveGraphicsState];
	[[NSBezierPath bezierPathWithRect:layout.textRect] addClip];
	[layout.text drawAtPoint:NSMakePoint(NSMinX(layout.textRect), baseline) withAttributes:attributes];
	if (selected >= 0 && selected < layout.count && layout.ranges[selected].location != NSNotFound) {
		NSString *run = [layout.text substringWithRange:layout.ranges[selected]];
		NSDictionary *accent = fn_text_attributes(font, [NSColor cg_accentColor]);

		[run drawAtPoint:NSMakePoint(NSMinX(layout.rects[selected]), baseline) withAttributes:accent];
	}
	[NSGraphicsContext restoreGraphicsState];
}

- (void)cg_drawStepperInFrame:(NSRect)frame flipped:(BOOL)flipped
{
	NSRect strip = [self cg_stepperRectForFrame:frame];
	CGFloat mid = NSMidY(frame);
	NSRect upper = NSMakeRect(NSMinX(strip), mid, NSWidth(strip), NSHeight(frame) / 2.0);
	NSRect lower = NSMakeRect(NSMinX(strip), NSMinY(frame), NSWidth(strip), NSHeight(frame) / 2.0);
	/* **THE +1 ARROW IS THE ONE AT THE TOP OF THE SCREEN.** In an unflipped view that is the larger y; in a flipped
	 * one it is the smaller y. The tracking door uses the same test, so the arrow a click steps is the arrow it hit. */
	NSRect positive = flipped ? lower : upper;
	NSRect negative = flipped ? upper : lower;
	NSRect positiveBand = NSInsetRect(positive, 3.0, 3.0);
	NSRect negativeBand = NSInsetRect(negative, 3.0, 3.0);

	/* THE DIVIDER, so two triangles in one strip read as two arrows. */
	[[NSColor controlShadowColor] setFill];
	NSRectFill(NSMakeRect(NSMinX(strip), NSMinY(frame), 1.0, NSHeight(frame)));
	NSRectFill(NSMakeRect(NSMinX(strip) + 1.0, mid, NSWidth(strip) - 1.0, 1.0));

	{
		NSRect bands[2] = { positiveBand, negativeBand };
		/* A triangle points AWAY FROM THE MIDDLE, which is the top of the screen for +1 and the bottom for -1. */
		BOOL apexAtMax[2] = { !flipped, flipped };
		NSInteger sides[2] = { 1, -1 };
		NSInteger i;

		for (i = 0; i < 2; i++) {
			NSRect band = bands[i];
			NSBezierPath *path = [NSBezierPath bezierPath];
			CGFloat cx = NSMidX(band);
			CGFloat apexY = apexAtMax[i] ? NSMaxY(band) : NSMinY(band);
			CGFloat baseY = apexAtMax[i] ? NSMinY(band) : NSMaxY(band);

			[path moveToPoint:NSMakePoint(cx, apexY)];
			[path lineToPoint:NSMakePoint(cx - 3.5, baseY)];
			[path lineToPoint:NSMakePoint(cx + 3.5, baseY)];
			[path closePath];
			[((_cg_pressedArrow == sides[i]) ? [NSColor cg_accentColor] : [NSColor controlTextColor]) setFill];
			[path fill];
		}
	}
}

/* The clock: a ring, twelve ticks, and three hands whose angles are the date's own hour, minute and second. */
- (void)cg_drawClockInFrame:(NSRect)frame flipped:(BOOL)flipped
{
	CGFloat ySign = flipped ? -1.0 : 1.0;
	NSCalendar *calendar = [self cg_effectiveCalendar];
	NSDateComponents *components = [calendar components:(NSCalendarUnitHour | NSCalendarUnitMinute |
							     NSCalendarUnitSecond)
						    fromDate:[self cg_shownDate]];
	CGFloat radius = fmin(NSWidth(frame), NSHeight(frame)) / 2.0 - AG_DATE_GRID_INSET;
	NSPoint centre = NSMakePoint(NSMidX(frame), NSMidY(frame));
	NSInteger i;
	NSInteger hour = [components hour];
	NSInteger minute = [components minute];
	NSInteger second = [components second];
	CGFloat hourAngle = (((CGFloat)(hour % 12) + (CGFloat)minute / 60.0) * (CGFloat)M_PI / 6.0);
	CGFloat minuteAngle = ((CGFloat)minute + (CGFloat)second / 60.0) * (CGFloat)M_PI / 30.0;
	CGFloat secondAngle = (CGFloat)second * (CGFloat)M_PI / 30.0;

	if (radius < 4.0) {
		return;
	}
	{
		NSRect ring = NSMakeRect(centre.x - radius, centre.y - radius, radius * 2.0, radius * 2.0);
		NSBezierPath *path = [NSBezierPath bezierPathWithOvalInRect:ring];

		[[NSColor controlDarkShadowColor] setStroke];
		[path setLineWidth:1.5];
		[path stroke];
	}
	[[NSColor controlShadowColor] setStroke];
	for (i = 0; i < 12; i++) {
		CGFloat angle = (CGFloat)i * (CGFloat)M_PI / 6.0;
		NSBezierPath *tick = [NSBezierPath bezierPath];
		CGFloat inner = radius * 0.84;
		CGFloat outer = radius;

		[tick moveToPoint:NSMakePoint(centre.x + sin(angle) * inner, centre.y + ySign * cos(angle) * inner)];
		[tick lineToPoint:NSMakePoint(centre.x + sin(angle) * outer, centre.y + ySign * cos(angle) * outer)];
		[tick setLineWidth:(i % 3 == 0) ? 2.0 : 1.0];
		[tick stroke];
	}
	{
		/* 12 O'CLOCK IS UP: the y term is cos, the x term sin, which is the one line that makes a clock a clock. */
		NSBezierPath *hand = [NSBezierPath bezierPath];

		[hand moveToPoint:centre];
		[hand lineToPoint:NSMakePoint(centre.x + sin(hourAngle) * radius * 0.48,
					      centre.y + ySign * cos(hourAngle) * radius * 0.48)];
		[[self cg_inkColor] setStroke];
		[hand setLineWidth:3.0];
		[hand stroke];
	}
	{
		NSBezierPath *hand = [NSBezierPath bezierPath];

		[hand moveToPoint:centre];
		[hand lineToPoint:NSMakePoint(centre.x + sin(minuteAngle) * radius * 0.72,
					      centre.y + ySign * cos(minuteAngle) * radius * 0.72)];
		[[self cg_inkColor] setStroke];
		[hand setLineWidth:2.0];
		[hand stroke];
	}
	{
		NSBezierPath *hand = [NSBezierPath bezierPath];

		[hand moveToPoint:centre];
		[hand lineToPoint:NSMakePoint(centre.x + sin(secondAngle) * radius * 0.80,
					      centre.y + ySign * cos(secondAngle) * radius * 0.80)];
		[[NSColor cg_accentColor] setStroke];
		[hand setLineWidth:1.0];
		[hand stroke];
	}
	{
		NSRect hub = NSMakeRect(centre.x - 2.0, centre.y - 2.0, 4.0, 4.0);

		[[NSColor cg_accentColor] setFill];
		[[NSBezierPath bezierPathWithOvalInRect:hub] fill];
	}
}

/* Does this style draw the month grid? The rule the header states: a date flag asks for the calendar, a time-only picker asks
 * for the clock. */
- (BOOL)cg_showsMonthGrid
{
	return (_datePickerElements & (0x00c0 | AG_DATE_DAY_FLAG | NSEraDatePickerElementFlag)) != 0;
}

/* The grid's one geometry door. The drawing calls it per day, so the picture and `-cg_rectForDay:` cannot disagree. */
- (NSRect)cg_dayCellRectForSlot:(NSInteger)slot inFrame:(NSRect)frame flipped:(BOOL)flipped
{
	CGFloat width = NSWidth(frame) - 2.0 * AG_DATE_GRID_INSET;
	CGFloat cellWidth = width / 7.0;
	CGFloat top = NSMaxY(frame) - AG_DATE_GRID_INSET;
	CGFloat gridTop = top - AG_DATE_GRID_HEADER - AG_DATE_GRID_WEEKDAY;
	CGFloat gridBottom = NSMinY(frame) + AG_DATE_GRID_INSET;
	CGFloat cellHeight = (gridTop - gridBottom) / (CGFloat)AG_DATE_GRID_ROWS;
	NSInteger row = slot / 7;
	NSInteger column = slot % 7;
	CGFloat y;

	if (cellHeight <= 0.0 || cellWidth <= 0.0) {
		return NSZeroRect;
	}
	if (flipped) {
		y = gridBottom + (CGFloat)row * cellHeight;
	} else {
		y = gridTop - (CGFloat)(row + 1) * cellHeight;
	}
	return NSMakeRect(NSMinX(frame) + AG_DATE_GRID_INSET + (CGFloat)column * cellWidth,
			  y, cellWidth, cellHeight);
}

/* The slot of a day in the shown month, or -1 when the day is outside it. */
- (NSInteger)cg_slotForDay:(NSInteger)day calendar:(NSCalendar *)calendar date:(NSDate *)date
{
	NSDateComponents *components = [calendar components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay)
						    fromDate:date];
	NSRange days = [calendar rangeOfUnit:NSCalendarUnitDay inUnit:NSCalendarUnitMonth forDate:date];
	NSDateComponents *first;
	NSInteger weekday;
	NSInteger offset;

	if (day < (NSInteger)days.location || day >= (NSInteger)(days.location + days.length)) {
		return -1;
	}
	first = [calendar components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay) fromDate:date];
	[first setDay:(NSInteger)days.location];
	weekday = [[calendar components:NSCalendarUnitWeekday
				  fromDate:[calendar dateFromComponents:first]] weekday];
	offset = (weekday - (NSInteger)[calendar firstWeekday] + 7) % 7;
	return offset + (day - (NSInteger)days.location);
}

- (NSRect)cg_rectForDay:(NSInteger)day inFrame:(NSRect)frame
{
	NSCalendar *calendar = [self cg_effectiveCalendar];
	NSInteger slot;

	if (_datePickerStyle != NSClockAndCalendarDatePickerStyle || ![self cg_showsMonthGrid]) {
		return NSZeroRect;
	}
	slot = [self cg_slotForDay:day calendar:calendar date:[self cg_shownDate]];
	if (slot < 0) {
		return NSZeroRect;
	}
	return [self cg_dayCellRectForSlot:slot inFrame:frame
				   flipped:[[self controlView] isFlipped]];
}

- (void)cg_drawMonthGridInFrame:(NSRect)frame flipped:(BOOL)flipped
{
	NSCalendar *calendar = [self cg_effectiveCalendar];
	NSDate *date = [self cg_shownDate];
	NSDateComponents *components = [calendar components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay)
						    fromDate:date];
	NSArray *months = [calendar monthSymbols];
	NSArray *weekdays = [calendar veryShortWeekdaySymbols];
	NSRange days = [calendar rangeOfUnit:NSCalendarUnitDay inUnit:NSCalendarUnitMonth forDate:date];
	NSInteger month = [components month];
	NSInteger selectedDay = [components day];
	NSColor *ink = [self cg_inkColor];
	NSFont *headerFont = [NSFont systemFontOfSize:10.0];
	NSFont *smallFont = [NSFont systemFontOfSize:9.0];
	NSDictionary *headerAttributes = fn_text_attributes(headerFont, ink);
	NSDictionary *smallAttributes = fn_text_attributes(smallFont, ink);
	NSInteger column, day;

	/* THE HEADER: the month's own name from the calendar, then the year. */
	if (month >= 1 && months != nil && (NSUInteger)(month - 1) < [months count]) {
		NSString *title = [NSString stringWithFormat:@"%@ %ld", [months objectAtIndex:(NSUInteger)(month - 1)],
				   (long)[components year]];
		NSSize size = [title sizeWithAttributes:headerAttributes];
		CGFloat width = NSWidth(frame) - 2.0 * AG_DATE_GRID_INSET;
		CGFloat x = NSMinX(frame) + AG_DATE_GRID_INSET + (width - size.width) / 2.0;
		CGFloat y = flipped
			? NSMinY(frame) + AG_DATE_GRID_INSET + 3.0 + [headerFont ascender]
			: NSMaxY(frame) - AG_DATE_GRID_INSET - 3.0 - [headerFont ascender];

		[title drawAtPoint:NSMakePoint(x, y) withAttributes:headerAttributes];
	}
	/* THE WEEKDAY ROW, rotated into the calendar's first weekday rather than assuming Sunday — the firstWeekday door is a
	 * property of the calendar, and a picker that ignored it would be a picker for one locale. */
	if (weekdays != nil && [weekdays count] == 7) {
		CGFloat width = NSWidth(frame) - 2.0 * AG_DATE_GRID_INSET;
		CGFloat cellWidth = width / 7.0;
		CGFloat y = flipped
			? NSMinY(frame) + AG_DATE_GRID_INSET + AG_DATE_GRID_HEADER + [smallFont ascender]
			: NSMaxY(frame) - AG_DATE_GRID_INSET - AG_DATE_GRID_HEADER - [smallFont ascender];

		for (column = 0; column < 7; column++) {
			NSInteger index = ((NSInteger)[calendar firstWeekday] - 1 + column) % 7;
			NSString *symbol = [weekdays objectAtIndex:(NSUInteger)index];
			NSSize size = [symbol sizeWithAttributes:smallAttributes];
			CGFloat x = NSMinX(frame) + AG_DATE_GRID_INSET + (CGFloat)column * cellWidth
				+ (cellWidth - size.width) / 2.0;

			[symbol drawAtPoint:NSMakePoint(x, y) withAttributes:smallAttributes];
		}
	}
	/* THE DAYS. The selected one is a filled accent chip with the platform's selected-text ink, which is a picture claim
	 * a probe can read as "this cell has accent and its neighbour does not". */
	for (day = (NSInteger)days.location; day < (NSInteger)(days.location + days.length); day++) {
		NSInteger slot = [self cg_slotForDay:day calendar:calendar date:date];
		NSRect cell;
		NSString *number;
		NSDictionary *attributes;
		NSSize size;
		CGFloat baseline;

		if (slot < 0) {
			continue;
		}
		cell = [self cg_dayCellRectForSlot:slot inFrame:frame flipped:flipped];
		if (NSWidth(cell) <= 0.0) {
			continue;
		}
		if (day == selectedDay) {
			{
				CGFloat diameter = fmin(NSWidth(cell), NSHeight(cell)) - 2.0;
				NSRect chip = NSMakeRect(NSMidX(cell) - diameter / 2.0, NSMidY(cell) - diameter / 2.0,
							 diameter, diameter);

				[[NSColor cg_accentColor] setFill];
				[[NSBezierPath bezierPathWithOvalInRect:chip] fill];
			}
			attributes = fn_text_attributes(smallFont, [NSColor selectedControlTextColor]);
		} else {
			attributes = smallAttributes;
		}
		number = [NSString stringWithFormat:@"%ld", (long)day];
		size = [number sizeWithAttributes:attributes];
		baseline = [self cg_baselineInFrame:cell font:smallFont];
		[number drawAtPoint:NSMakePoint(NSMidX(cell) - size.width / 2.0, baseline) withAttributes:attributes];
	}
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	BOOL flipped = (controlView != nil && [controlView isKindOfClass:[NSView class]])
		? [(NSView *)controlView isFlipped] : NO;

	if (_datePickerStyle == NSClockAndCalendarDatePickerStyle) {
		[self cg_drawFaceInFrame:cellFrame];
		if ([self cg_showsMonthGrid]) {
			[self cg_drawMonthGridInFrame:cellFrame flipped:flipped];
		} else {
			[self cg_drawClockInFrame:cellFrame flipped:flipped];
		}
		return;
	}
	{
		AGDateLayout layout;

		[self cg_drawFaceInFrame:cellFrame];
		layout = [self cg_layoutInFrame:cellFrame];
		[self cg_drawTextForLayout:layout selected:_indexOfSelectedSubfield];
		if (_datePickerStyle == NSTextFieldAndStepperDatePickerStyle) {
			[self cg_drawStepperInFrame:cellFrame flipped:flipped];
		}
	}
}

@end

/* ==================================================================================================================
 * THE CONTROL.
 * ================================================================================================================ */

@implementation NSDatePicker

- (instancetype)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	if (self != nil) {
		NSDatePickerCell *cell = [[NSDatePickerCell alloc] init];

		[self setCell:cell];
		[cell release];
	}
	return self;
}

- (NSDatePickerCell *)cg_dateCell
{
	id cell = [self cell];

	return [cell isKindOfClass:[NSDatePickerCell class]] ? (NSDatePickerCell *)cell : nil;
}

/* ---- APPEARANCE ----------------------------------------------------------------------------------- */

- (NSDatePickerStyle)datePickerStyle { return [[self cg_dateCell] datePickerStyle]; }
- (void)setDatePickerStyle:(NSDatePickerStyle)newStyle { [[self cg_dateCell] setDatePickerStyle:newStyle]; }
- (BOOL)isBezeled { return [[self cg_dateCell] isBezeled]; }
- (void)setBezeled:(BOOL)flag { [[self cg_dateCell] setBezeled:flag]; }
- (BOOL)isBordered { return [[self cg_dateCell] isBordered]; }
- (void)setBordered:(BOOL)flag { [[self cg_dateCell] setBordered:flag]; }
- (BOOL)drawsBackground { return [[self cg_dateCell] drawsBackground]; }
- (void)setDrawsBackground:(BOOL)flag { [[self cg_dateCell] setDrawsBackground:flag]; }
- (NSColor *)backgroundColor { return [[self cg_dateCell] backgroundColor]; }
- (void)setBackgroundColor:(NSColor *)color { [[self cg_dateCell] setBackgroundColor:color]; }
- (NSColor *)textColor { return [[self cg_dateCell] textColor]; }
- (void)setTextColor:(NSColor *)color { [[self cg_dateCell] setTextColor:color]; }

/* ---- RANGE MODE ----------------------------------------------------------------------------------- */

- (NSDatePickerMode)datePickerMode { return [[self cg_dateCell] datePickerMode]; }
- (void)setDatePickerMode:(NSDatePickerMode)newMode { [[self cg_dateCell] setDatePickerMode:newMode]; }

/* ---- PRESENTATION --------------------------------------------------------------------------------- */

- (NSDatePickerElementFlags)datePickerElements { return [[self cg_dateCell] datePickerElements]; }
- (void)setDatePickerElements:(NSDatePickerElementFlags)elementFlags
{
	[[self cg_dateCell] setDatePickerElements:elementFlags];
}
- (NSCalendar *)calendar { return [[self cg_dateCell] calendar]; }
- (void)setCalendar:(NSCalendar *)newCalendar { [[self cg_dateCell] setCalendar:newCalendar]; }
- (NSLocale *)locale { return [[self cg_dateCell] locale]; }
- (void)setLocale:(NSLocale *)newLocale { [[self cg_dateCell] setLocale:newLocale]; }
- (NSTimeZone *)timeZone { return [[self cg_dateCell] timeZone]; }
- (void)setTimeZone:(NSTimeZone *)newTimeZone { [[self cg_dateCell] setTimeZone:newTimeZone]; }

/* ---- THE VALUE ------------------------------------------------------------------------------------ */

- (NSDate *)dateValue { return [[self cg_dateCell] dateValue]; }
- (void)setDateValue:(NSDate *)newStartDate { [[self cg_dateCell] setDateValue:newStartDate]; }
- (NSTimeInterval)timeInterval { return [[self cg_dateCell] timeInterval]; }
- (void)setTimeInterval:(NSTimeInterval)newTimeInterval
{
	[[self cg_dateCell] setTimeInterval:newTimeInterval];
}
- (NSDate *)minDate { return [[self cg_dateCell] minDate]; }
- (void)setMinDate:(NSDate *)date { [[self cg_dateCell] setMinDate:date]; }
- (NSDate *)maxDate { return [[self cg_dateCell] maxDate]; }
- (void)setMaxDate:(NSDate *)date { [[self cg_dateCell] setMaxDate:date]; }

/* ---- DELEGATE ------------------------------------------------------------------------------------- */

- (id <NSDatePickerCellDelegate>)delegate { return [[self cg_dateCell] delegate]; }
- (void)setDelegate:(id <NSDatePickerCellDelegate>)anObject
{
	[[self cg_dateCell] setDelegate:anObject];
}

/* ---- THE KEY PATH --------------------------------------------------------------------------------- */

/* **THE CONTROL OWNS THE KEY, THE CELL OWNS WHAT A KEY MEANS.** A date field is the one control whose arrow keys are an EDIT
 * rather than a focus move, and whose typed digits are a field replacement rather than text insertion. The cell answers
 * whether it consumed the key; the control compares the date before and after, so a keyboard move that changed nothing (a
 * left arrow across subfields) redraws without sending an action, and one that changed the date speaks once. */
- (BOOL)acceptsFirstResponder
{
	return [self isEnabled];
}

- (void)keyDown:(NSEvent *)event
{
	NSDatePickerCell *cell = [self cg_dateCell];
	double before;

	if (cell == nil) {
		[super keyDown:event];
		return;
	}
	before = ([[cell dateValue] isKindOfClass:[NSDate class]]) ? [[cell dateValue] timeIntervalSince1970] : 0.0;
	if ([cell cg_handleKeyDown:event]) {
		double after = ([[cell dateValue] isKindOfClass:[NSDate class]])
			? [[cell dateValue] timeIntervalSince1970] : 0.0;

		[self setNeedsDisplay:YES];
		if (after != before) {
			[self sendAction:[cell action] to:[cell target]];
		}
		return;
	}
	[super keyDown:event];
}

@end
