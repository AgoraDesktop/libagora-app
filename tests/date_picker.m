/*
 * date_picker — NSDatePicker and NSDatePickerCell: a formatted date, the subfield a step applies to, and the delegate's veto.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE CLAIM IS THAT THE TEXT IS A FORMATTED DATE OF THE CELL'S OWN DOORS, NOT OF A HIDDEN DEFAULT.** The probe sets a UTC
 * calendar, an en_US locale and a UTC zone, formats a fixed instant, and requires the cell's text to equal a formatter built
 * from the same facts — then CHANGES EACH DOOR and requires the text to follow: de_DE orders the day before the month and
 * names it "Juni", a +12 zone moves the hour AND the day, and clearing the time flags removes the colon.
 *
 * **AND THE SUBFIELD A CLICK SELECTS IS THE RUN IN THAT TEXT.** The probe hit-tests the measured rectangles, steps the
 * element it found, and checks the CALENDAR's arithmetic (January 31 stepped by one month is February 28, the tree's own
 * normalization), not this cell's private guess at it.
 *
 * **THE DELEGATE'S ONE MESSAGE IS EXERCISED THREE WAYS** — accept, REPLACE (a proposal shifted by a day is what gets stored)
 * and REFUSE (a nil proposed date leaves the cell where it was) — because a protocol that is declared and never sent is a
 * contract nobody honours.
 *
 * **THE PICTURES ARE PIXELS**: the clock's hour hand points right at 03:00 and left at 09:00; the month grid's selected day is
 * a filled accent chip and its neighbour is not; the text+stepper style puts arrows in the strip the text style leaves empty.
 */
#import <AppKit/NSDatePicker.h>
#import <AppKit/NSView.h>
#import <AppKit/NSControl.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSEvent.h>
#import <Foundation/Foundation.h>

#include <math.h>
#include <stdio.h>
#include <string.h>

/* THE DAY BIT HAS NO SINGLE-FLAG NAME IN APPLE'S HEADER — it exists only inside the two combinations. */
#define AG_TEST_DAY_FLAG (NSYearMonthDayDatePickerElementFlag & ~NSYearMonthDatePickerElementFlag)

static int failures;

static void check(int ok, const char *what)
{
	printf("  %s %s\n", ok ? "ok   " : "FAIL ", what);
	if (!ok) {
		failures++;
	}
}

/* A WATCHER THAT COUNTS, and that can accept, replace or refuse the proposal. */
@interface AGDateWatcher : NSObject <NSDatePickerCellDelegate>
{
@public
	int asked;
	int fired;
	int refuse;
	int shiftDays;
	NSTimeInterval lastInterval;
}
- (void)datePickerCell:(NSDatePickerCell *)cell
    validateProposedDateValue:(NSDate **)proposedDateValue
	     timeInterval:(NSTimeInterval *)proposedTimeInterval;
- (void)clicked:(id)sender;
@end

@implementation AGDateWatcher

- (void)datePickerCell:(NSDatePickerCell *)cell
    validateProposedDateValue:(NSDate **)proposedDateValue
	     timeInterval:(NSTimeInterval *)proposedTimeInterval
{
	(void)cell;
	asked++;
	lastInterval = (proposedTimeInterval != NULL) ? *proposedTimeInterval : 0.0;
	if (refuse) {
		*proposedDateValue = nil;
		return;
	}
	if (shiftDays != 0) {
		*proposedDateValue = [*proposedDateValue dateByAddingTimeInterval:86400.0 * (double)shiftDays];
	}
}

- (void)clicked:(id)sender
{
	(void)sender;
	fired++;
}

@end

static NSCalendar *utc_calendar(void)
{
	NSCalendar *calendar = [[NSCalendar currentCalendar] copy];

	[calendar setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
	return [calendar autorelease];
}

static NSDate *make_date(NSCalendar *calendar, NSInteger year, NSInteger month, NSInteger day,
			 NSInteger hour, NSInteger minute, NSInteger second)
{
	NSDateComponents *components = [[[NSDateComponents alloc] init] autorelease];

	[components setYear:year];
	[components setMonth:month];
	[components setDay:day];
	[components setHour:hour];
	[components setMinute:minute];
	[components setSecond:second];
	return [calendar dateFromComponents:components];
}

static NSDateComponents *parts_of(NSDate *date, NSCalendar *calendar)
{
	return [calendar components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay |
				     NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond)
			    fromDate:date];
}

static NSDatePickerCell *date_cell(void)
{
	NSDatePickerCell *cell = [[[NSDatePickerCell alloc] init] autorelease];
	NSCalendar *calendar = utc_calendar();

	[cell setCalendar:calendar];
	[cell setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US"]];
	[cell setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
	[cell setDatePickerElements:(NSYearMonthDayDatePickerElementFlag | NSHourMinuteSecondDatePickerElementFlag)];
	[cell setDateValue:make_date(calendar, 2026, 6, 16, 14, 35, 7)];
	return cell;
}

static NSString *text_of(NSDatePickerCell *cell)
{
	NSString *text = [cell cg_displayText];

	return (text != nil) ? text : @"(nil)";
}

static NSBitmapImageRep *render_cell(NSDatePickerCell *cell, CGFloat width, CGFloat height, NSView *host)
{
	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
								      pixelsWide:(NSInteger)width
								      pixelsHigh:(NSInteger)height
								   bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
								    isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace
								     bytesPerRow:(NSInteger)width * 4 bitsPerPixel:32];

	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	[cell drawWithFrame:NSMakeRect(0.0, 0.0, width, height) inView:host];
	return rep;
}

/* **THE BITMAP'S ROWS RUN THE OPPOSITE WAY TO THE DRAWING COORDINATES** (the level indicator's probe found the same thing), so
 * every sample made from a drawn point converts y once, here. */
static NSColor *pixel_at(NSBitmapImageRep *rep, NSInteger height, NSInteger x, NSInteger y)
{
	return [rep colorAtX:x y:(height - 1 - y)];
}

static BOOL near(NSColor *colour, CGFloat r, CGFloat g, CGFloat b)
{
	return colour != nil
		&& fabs([colour redComponent] - r) < 0.06
		&& fabs([colour greenComponent] - g) < 0.06
		&& fabs([colour blueComponent] - b) < 0.06;
}

static BOOL is_accent(NSColor *colour)
{
	return near(colour, 0.643, 0.604, 1.0);
}

static BOOL is_face(NSColor *colour)
{
	return near(colour, 1.0, 1.0, 1.0);
}

static BOOL is_dark(NSColor *colour)
{
	return colour != nil && [colour redComponent] < 0.55
		&& [colour greenComponent] < 0.55 && [colour blueComponent] < 0.55;
}

static int count_where(NSBitmapImageRep *rep, NSInteger height,
		       NSInteger x0, NSInteger y0, NSInteger x1, NSInteger y1,
		       BOOL (*predicate)(NSColor *))
{
	NSInteger x, y;
	int count = 0;

	for (y = y0; y < y1; y++) {
		for (x = x0; x < x1; x++) {
			if (predicate(pixel_at(rep, height, x, y))) {
				count++;
			}
		}
	}
	return count;
}

static NSEvent *key_event(NSString *characters, unsigned short code)
{
	return [NSEvent keyEventWithType:NSKeyDown location:NSZeroPoint modifierFlags:0
			       timestamp:0.0 windowNumber:0 context:nil
			      characters:characters charactersIgnoringModifiers:characters
			      isARepeat:NO keyCode:code];
}

int main(void)
{
	@autoreleasepool {
		NSCalendar *calendar = utc_calendar();

		setvbuf(stdout, NULL, _IONBF, 0);

		/* ============================================================================================
		 * 1. THE FACTS AND THE DEFAULT DATE.
		 * ========================================================================================== */
		{
			NSDatePickerCell *cell = [[[NSDatePickerCell alloc] init] autorelease];

			check([cell datePickerStyle] == NSTextFieldAndStepperDatePickerStyle,
			      "a new cell is a text field with a stepper");
			check([cell datePickerMode] == NSSingleDateMode, "and a single date");
			check(([cell datePickerElements] & NSYearMonthDayDatePickerElementFlag)
				      == NSYearMonthDayDatePickerElementFlag
				      && ([cell datePickerElements] & NSHourMinuteSecondDatePickerElementFlag)
				      == NSHourMinuteSecondDatePickerElementFlag,
			      "showing the whole date and the whole time");
			check([cell timeInterval] == 0.0 && [cell minDate] == nil && [cell maxDate] == nil,
			      "with no length and no bounds");
			check([cell dateValue] != nil && [cell drawsBackground] && [cell isBezeled],
			      "and a date, a background and a bezel");
		}

		/* ============================================================================================
		 * 2. THE TEXT IS THE CELL'S OWN LOCALE, CALENDAR AND ZONE.
		 * ========================================================================================== */
		{
			NSDatePickerCell *cell = date_cell();
			NSDateFormatter *reference = [[[NSDateFormatter alloc] init] autorelease];
			NSString *pattern = [NSDateFormatter dateFormatFromTemplate:@"yMMMd jmmss"
									   options:0
									    locale:[NSLocale localeWithLocaleIdentifier:@"en_US"]];
			NSString *expected;

			[reference setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US"]];
			[reference setCalendar:calendar];
			[reference setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
			[reference setDateFormat:pattern];
			expected = [reference stringFromDate:[cell dateValue]];
			printf("  (note: en_US/UTC text is \"%s\")\n", [text_of(cell) UTF8String]);
			check([text_of(cell) isEqualToString:expected],
			      "the text is the formatter's answer for the same skeleton, locale, calendar and zone");
			check([[cell cg_displayPattern] rangeOfString:@"y"].location != NSNotFound,
			      "and the pattern is the locale's response to the element skeleton");

			/* THE LOCALE DOOR: de_DE puts the day first and calls June "Juni". */
			[cell setLocale:[NSLocale localeWithLocaleIdentifier:@"de_DE"]];
			printf("  (note: de_DE text is \"%s\")\n", [text_of(cell) UTF8String]);
			check([[cell cg_displayText] hasPrefix:@"16."], "de_DE puts the day before the month");
			check([[cell cg_displayText] rangeOfString:@"Juni"].location != NSNotFound,
			      "and names the month in German");
			[cell setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US"]];

			/* THE ZONE DOOR: +12 moves 14:35 to 02:35 THE NEXT DAY — an hour and a date change. */
			[cell setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:12 * 60 * 60]];
			printf("  (note: +12 text is \"%s\")\n", [text_of(cell) UTF8String]);
			check([[cell cg_displayText] rangeOfString:@"17"].location != NSNotFound,
			      "a +12 zone moves the date to the next day");
			check([[cell cg_displayText] rangeOfString:@"2:35:07"].location != NSNotFound,
			      "and the hour to 02");
			[cell setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];

			/* THE ELEMENT DOORS, one flag at a time. */
			[cell setDatePickerElements:NSYearMonthDayDatePickerElementFlag];
			printf("  (note: date-only text is \"%s\")\n", [text_of(cell) UTF8String]);
			check([[cell cg_displayText] rangeOfString:@":"].location == NSNotFound,
			      "clearing the time flags removes the time");
			[cell setDatePickerElements:NSHourMinuteSecondDatePickerElementFlag];
			printf("  (note: time-only text is \"%s\")\n", [text_of(cell) UTF8String]);
			check([[cell cg_displayText] rangeOfString:@"2026"].location == NSNotFound,
			      "clearing the date flags removes the year");
			[cell setDatePickerElements:(NSYearMonthDayDatePickerElementFlag | NSEraDatePickerElementFlag)];
			printf("  (note: era text is \"%s\")\n", [text_of(cell) UTF8String]);
			check([[cell cg_displayText] rangeOfString:@"AD"].location != NSNotFound,
			      "the era flag adds the era");
			[cell setDatePickerElements:NSYearMonthDayDatePickerElementFlag | NSTimeZoneDatePickerElementFlag];
			printf("  (note: zone text is \"%s\")\n", [text_of(cell) UTF8String]);
			check([[cell cg_displayText] rangeOfString:@"GMT"].location != NSNotFound,
			      "the time-zone flag adds the zone name");
		}

		/* ============================================================================================
		 * 3. RANGE MODE IS THE START AND THE LENGTH.
		 * ========================================================================================== */
		{
			NSDatePickerCell *cell = date_cell();

			[cell setDatePickerMode:NSRangeDateMode];
			[cell setTimeInterval:3600.0];
			printf("  (note: range text is \"%s\")\n", [text_of(cell) UTF8String]);
			check([[cell cg_displayText] rangeOfString:@" - "].location != NSNotFound,
			      "range mode draws a start and an end");
			check([cell timeInterval] == 3600.0 && [cell dateValue] != nil,
			      "the interval is the length, not a second date");
			check([cell cg_numberOfSubfields] == 6,
			      "the pattern still names six fields for the keyboard");
			check(NSIsEmptyRect([cell cg_rectOfSubfieldAtIndex:0 inFrame:NSMakeRect(0, 0, 240, 20)]),
			      "but a range's runs are not separately hit-testable");
			check(![cell cg_selectSubfieldAtPoint:NSMakePoint(20.0, 10.0) inFrame:NSMakeRect(0, 0, 240, 20)],
			      "and a click selects nothing in a range");
			[cell setTimeInterval:-5.0];
			check([cell timeInterval] == 0.0, "a negative length is clamped to zero");
		}

		/* ============================================================================================
		 * 4. THE BOUNDS CLAMP AT THE ONE SETTER, AND THE OBJECT VALUE IS THE DATE.
		 * ========================================================================================== */
		{
			NSDatePickerCell *cell = date_cell();
			NSDate *low = make_date(calendar, 2026, 6, 16, 12, 0, 0);
			NSDate *high = make_date(calendar, 2026, 6, 16, 16, 0, 0);

			[cell setMinDate:low];
			[cell setMaxDate:high];
			[cell setDateValue:make_date(calendar, 2026, 6, 16, 9, 0, 0)];
			check([[cell dateValue] isEqualToDate:low], "a date below the minimum is clamped to it");
			[cell setDateValue:make_date(calendar, 2026, 6, 16, 22, 0, 0)];
			check([[cell dateValue] isEqualToDate:high], "and a date above the maximum to that");
			[cell setMinDate:make_date(calendar, 2026, 6, 16, 20, 0, 0)];
			check([[cell minDate] isEqualToDate:[cell maxDate]]
				      && [[cell dateValue] isEqualToDate:[cell minDate]],
			      "a minimum past the maximum pushes the maximum and re-clamps the date");
			[cell setMinDate:nil];
			[cell setMaxDate:nil];
			[cell setDateValue:make_date(calendar, 2030, 1, 1, 0, 0, 0)];
			check([[cell dateValue] isEqualToDate:make_date(calendar, 2030, 1, 1, 0, 0, 0)],
			      "with no bounds the date is free");
			check([[cell objectValue] isEqualToDate:[cell dateValue]],
			      "objectValue and dateValue are one value");
			[cell setObjectValue:make_date(calendar, 2027, 2, 3, 4, 5, 6)];
			check([[[cell dateValue] description] rangeOfString:@"2027"].location != NSNotFound,
			      "and setObjectValue: stores a date");
			[cell setObjectValue:@"not a date"];
			check([[[cell dateValue] description] rangeOfString:@"2027"].location != NSNotFound,
			      "a non-date object leaves the date alone");
		}

		/* ============================================================================================
		 * 5. THE SUBFIELDS ARE MEASURED FROM THE TEXT AND HIT-TESTED.
		 * ========================================================================================== */
		{
			NSDatePickerCell *cell = date_cell();
			NSRect frame = NSMakeRect(0.0, 0.0, 240.0, 20.0);
			NSRect first, second, third;

			[cell setDatePickerStyle:NSTextFieldDatePickerStyle];
			[cell setDatePickerElements:NSYearMonthDayDatePickerElementFlag];
			printf("  (note: date-only pattern is \"%s\" with %ld subfields)\n",
			       [[cell cg_displayPattern] UTF8String], (long)[cell cg_numberOfSubfields]);
			check([cell cg_numberOfSubfields] == 3, "a year-month-day pattern has three subfields");
			first = [cell cg_rectOfSubfieldAtIndex:0 inFrame:frame];
			second = [cell cg_rectOfSubfieldAtIndex:1 inFrame:frame];
			third = [cell cg_rectOfSubfieldAtIndex:2 inFrame:frame];
			check(NSWidth(first) > 0.0 && NSWidth(second) > 0.0 && NSWidth(third) > 0.0,
			      "each one has a rectangle");
			check(NSMinX(first) < NSMinX(second) && NSMinX(second) < NSMinX(third),
			      "and they run left to right in the pattern's order");
			check(NSMaxX(third) <= NSMaxX(frame), "inside the cell");
			check([cell cg_selectSubfieldAtPoint:NSMakePoint(NSMidX(second), NSMidY(frame)) inFrame:frame]
				      && [cell cg_indexOfSelectedSubfield] == 1,
			      "a click on the second run selects it");
			check([cell cg_elementAtIndex:1] == AG_TEST_DAY_FLAG,
			      "and the second run is the DAY");
			check(![cell cg_selectSubfieldAtPoint:NSMakePoint(235.0, 10.0) inFrame:frame]
				      && [cell cg_indexOfSelectedSubfield] == -1,
			      "a click past the last run selects nothing");
		}

		/* ============================================================================================
		 * 6. STEPPING USES THE CALENDAR, AND THE DELEGATE CAN ACCEPT, REPLACE OR REFUSE.
		 * ========================================================================================== */
		{
			NSDatePickerCell *cell = date_cell();
			AGDateWatcher *watcher = [[[AGDateWatcher alloc] init] autorelease];
			NSRect frame = NSMakeRect(0.0, 0.0, 240.0, 20.0);
			NSDateComponents *parts;

			[cell setDatePickerStyle:NSTextFieldDatePickerStyle];
			[cell setDatePickerElements:NSYearMonthDayDatePickerElementFlag];
			[cell setDateValue:make_date(calendar, 2026, 1, 31, 0, 0, 0)];
			(void)[cell cg_selectSubfieldAtPoint:NSMakePoint(NSMidX([cell cg_rectOfSubfieldAtIndex:0 inFrame:frame]),
									NSMidY(frame))
						     inFrame:frame];
			check([cell cg_stepSelectedElementBy:1], "stepping the month changes the date");
			parts = parts_of([cell dateValue], calendar);
			printf("  (note: January 31 + 1 month = %ld/%ld)\n", (long)[parts month], (long)[parts day]);
			check([parts month] == 2 && [parts day] == 28,
			      "and the calendar normalizes January 31 to February 28");

			/* THE DELEGATE REPLACES the proposal: one more day on top of the step. */
			[cell setDelegate:watcher];
			[cell setDateValue:make_date(calendar, 2026, 1, 31, 0, 0, 0)];
			[cell setTimeInterval:7200.0];
			watcher->shiftDays = 1;
			check([cell cg_stepSelectedElementBy:1], "a replaced proposal is stored");
			parts = parts_of([cell dateValue], calendar);
			printf("  (note: with the delegate's +1 day the step lands on %ld/%ld, asked %d time(s), interval %.0f)\n",
			       (long)[parts month], (long)[parts day], watcher->asked, (double)watcher->lastInterval);
			check([parts month] == 3 && [parts day] == 1, "February 28 + the delegate's day is March 1");
			check(watcher->asked == 1, "and the delegate was asked exactly once");
			check(watcher->lastInterval == 7200.0, "with the cell's interval in the in/out parameter");

			/* THE DELEGATE REFUSES with a nil date: the cell keeps what it had. */
			[cell setDateValue:make_date(calendar, 2026, 1, 31, 0, 0, 0)];
			watcher->shiftDays = 0;
			watcher->refuse = 1;
			check(![cell cg_stepSelectedElementBy:1], "a nil proposal refuses the step");
			parts = parts_of([cell dateValue], calendar);
			check([parts month] == 1 && [parts day] == 31, "and the date did not move");
			watcher->refuse = 0;

			/* A PROGRAMMATIC SET DOES NOT ASK THE DELEGATE — the era's split between a person and an application. */
			watcher->asked = 0;
			[cell setDateValue:make_date(calendar, 2026, 5, 1, 0, 0, 0)];
			check(watcher->asked == 0, "setDateValue: does not consult the delegate");
			[cell setDelegate:nil];
		}

		/* ============================================================================================
		 * 7. THE CONTROL'S KEY PATH, AND ITS ACTION.
		 * ========================================================================================== */
		{
			NSDatePicker *picker = [[[NSDatePicker alloc] initWithFrame:NSMakeRect(0.0, 0.0, 240.0, 20.0)] autorelease];
			AGDateWatcher *watcher = [[[AGDateWatcher alloc] init] autorelease];
			NSDatePickerCell *cell = (NSDatePickerCell *)[picker cell];
			NSDateComponents *parts;

			[picker setCalendar:calendar];
			[picker setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US"]];
			[picker setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
			[picker setDatePickerStyle:NSTextFieldDatePickerStyle];
			[picker setDatePickerElements:NSYearMonthDayDatePickerElementFlag];
			[picker setDateValue:make_date(calendar, 2026, 1, 31, 0, 0, 0)];
			[picker setTarget:watcher];
			[picker setAction:@selector(clicked:)];

			(void)[cell cg_selectSubfieldAtPoint:NSMakePoint(NSMidX([cell cg_rectOfSubfieldAtIndex:0
										    inFrame:[picker bounds]]),
									NSMidY([picker bounds]))
						     inFrame:[picker bounds]];
			[picker keyDown:key_event([NSString stringWithFormat:@"%C", (unichar)NSUpArrowFunctionKey], 126)];
			parts = parts_of([picker dateValue], calendar);
			check([parts month] == 2 && [parts day] == 28, "an UP arrow steps the selected month");
			check(watcher->fired == 1, "and the control sends its action once");

			[picker keyDown:key_event([NSString stringWithFormat:@"%C", (unichar)NSRightArrowFunctionKey], 124)];
			check([cell cg_indexOfSelectedSubfield] == 1, "a RIGHT arrow moves to the next subfield");
			check(watcher->fired == 1, "without speaking, because the date did not change");

			[picker keyDown:key_event(@"1", 18)];
			[picker keyDown:key_event(@"5", 19)];
			parts = parts_of([picker dateValue], calendar);
			printf("  (note: typing 1 then 5 into the day field gives %ld/%ld, action fired %d time(s))\n",
			       (long)[parts month], (long)[parts day], watcher->fired);
			check([parts day] == 15, "typing 1 then 5 sets the day to 15");
			check(watcher->fired == 3, "and each typed digit that changes the date speaks");
			[picker setTarget:nil];
		}

		/* ============================================================================================
		 * 8. TRACKING: THE ARROWS AND THE SUBFIELDS.
		 * ========================================================================================== */
		{
			NSDatePickerCell *cell = date_cell();
			NSView *host = [[[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 20.0)] autorelease];
			NSDateComponents *parts;

			[cell setDatePickerElements:NSYearMonthDayDatePickerElementFlag];
			[cell setDateValue:make_date(calendar, 2026, 1, 15, 0, 0, 0)];
			check([cell cg_selectSubfieldAtPoint:NSMakePoint(NSMidX([cell cg_rectOfSubfieldAtIndex:0
										   inFrame:[host bounds]]), 10.0)
						inFrame:[host bounds]],
			      "the press selects the month");
			check([cell startTrackingAt:NSMakePoint(193.0, 15.0) inView:host], "a press on the upper arrow tracks");
			parts = parts_of([cell dateValue], calendar);
			check([parts month] == 2 && [parts day] == 15, "and steps the selected element forward");
			[cell stopTracking:NSMakePoint(193.0, 15.0) at:NSMakePoint(193.0, 15.0) inView:host mouseIsUp:YES];
			check([cell startTrackingAt:NSMakePoint(193.0, 5.0) inView:host], "a press on the lower arrow tracks");
			parts = parts_of([cell dateValue], calendar);
			check([parts month] == 1, "and steps it back");
			[cell stopTracking:NSMakePoint(193.0, 5.0) at:NSMakePoint(193.0, 5.0) inView:host mouseIsUp:YES];
		}

		/* ============================================================================================
		 * 9. THE PICTURES: TEXT, THE SELECTED RUN, THE STEPPER, THE CLOCK AND THE GRID.
		 * ========================================================================================== */
		{
			NSDatePickerCell *cell = date_cell();
			NSView *host = [[[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 240.0, 20.0)] autorelease];
			NSBitmapImageRep *rep;

			[cell setDatePickerStyle:NSTextFieldDatePickerStyle];
			[cell setDatePickerElements:NSYearMonthDayDatePickerElementFlag];
			rep = render_cell(cell, 240.0, 20.0, host);
			printf("  (note: the date-only field has %d dark pixels, %d accent)\n",
			       count_where(rep, 20, 0, 0, 240, 20, is_dark),
			       count_where(rep, 20, 0, 0, 240, 20, is_accent));
			check(count_where(rep, 20, 0, 0, 240, 20, is_dark) > 30, "the text field style draws its date");
			check(count_where(rep, 20, 0, 0, 240, 20, is_accent) == 0,
			      "with no accent while nothing is selected");
			(void)[cell cg_selectSubfieldAtPoint:NSMakePoint(NSMidX([cell cg_rectOfSubfieldAtIndex:0
										   inFrame:[host bounds]]),
									NSMidY([host bounds]))
						inFrame:[host bounds]];
			[rep release];
			rep = render_cell(cell, 240.0, 20.0, host);
			printf("  (note: with the month selected the field has %d accent pixels)\n",
			       count_where(rep, 20, 0, 0, 240, 20, is_accent));
			check(count_where(rep, 20, 0, 0, 240, 20, is_accent) > 5,
			      "and the selected run is redrawn in the accent");
			[rep release];

			/* THE STEPPER'S STRIP: ink where the text-only style has none. */
			[cell setDatePickerStyle:NSTextFieldAndStepperDatePickerStyle];
			rep = render_cell(cell, 240.0, 20.0, host);
			printf("  (note: the stepper strip has %d ink pixels; the text area %d)\n",
			       count_where(rep, 20, 226, 0, 240, 20, is_dark),
			       count_where(rep, 20, 0, 0, 200, 20, is_dark));
			check(count_where(rep, 20, 226, 0, 240, 20, is_dark) > 8,
			      "the text-and-stepper style draws two arrows in the strip");
			check(count_where(rep, 20, 0, 0, 200, 20, is_dark) > 20, "and still draws the date");
			[rep release];

			/* THE CLOCK: 03:00 points right, 09:00 points left — the same picture, a different date. */
			[cell setDatePickerStyle:NSClockAndCalendarDatePickerStyle];
			[cell setDatePickerElements:NSHourMinuteSecondDatePickerElementFlag];
			[cell setDateValue:make_date(calendar, 2026, 6, 16, 3, 0, 0)];
			rep = render_cell(cell, 100.0, 100.0, host);
			printf("  (note: at 03:00 the right of centre is %s and the left is %s)\n",
			       is_dark(pixel_at(rep, 100, 62, 50)) ? "ink" : "ground",
			       is_dark(pixel_at(rep, 100, 38, 50)) ? "ink" : "ground");
			check(is_dark(pixel_at(rep, 100, 62, 50)), "at 03:00 the clock's hour hand points right");
			check(!is_dark(pixel_at(rep, 100, 38, 50)), "and not left");
			[rep release];
			[cell setDateValue:make_date(calendar, 2026, 6, 16, 9, 0, 0)];
			rep = render_cell(cell, 100.0, 100.0, host);
			check(is_dark(pixel_at(rep, 100, 38, 50)), "at 09:00 the hour hand points left");
			check(!is_dark(pixel_at(rep, 100, 62, 50)), "and not right");
			[rep release];

			/* THE MONTH GRID: the selected day is a filled accent chip, and it MOVES when the date does. */
			[cell setDatePickerElements:NSYearMonthDayDatePickerElementFlag];
			[cell setDateValue:make_date(calendar, 2026, 6, 16, 0, 0, 0)];
			check(!NSIsEmptyRect([cell cg_rectForDay:16 inFrame:NSMakeRect(0, 0, 140, 120)]),
			      "the grid names a rectangle for the selected day");
			check(!NSIsEmptyRect([cell cg_rectForDay:1 inFrame:NSMakeRect(0, 0, 140, 120)]),
			      "and for day 1");
			check(NSIsEmptyRect([cell cg_rectForDay:31 inFrame:NSMakeRect(0, 0, 140, 120)]),
			      "but not for a day June does not have");
			{
				NSRect day16 = [cell cg_rectForDay:16 inFrame:NSMakeRect(0, 0, 140, 120)];
				NSRect day15 = [cell cg_rectForDay:15 inFrame:NSMakeRect(0, 0, 140, 120)];
				int chip, neighbour;

				rep = render_cell(cell, 140.0, 120.0, host);
				/* THE CHIP'S CENTRE IS THE WHITE NUMBER, so the cell is COUNTED rather than sampled at one point — the
				 * same lesson the segmented control's plate taught. */
				chip = count_where(rep, 120, (NSInteger)NSMinX(day16), (NSInteger)NSMinY(day16),
						   (NSInteger)NSMaxX(day16), (NSInteger)NSMaxY(day16), is_accent);
				neighbour = count_where(rep, 120, (NSInteger)NSMinX(day15), (NSInteger)NSMinY(day15),
							(NSInteger)NSMaxX(day15), (NSInteger)NSMaxY(day15), is_accent);
				printf("  (note: June 16's cell has %d accent pixels; June 15's has %d)\n", chip, neighbour);
				check(chip > 10, "the selected day is a filled accent chip");
				check(neighbour == 0, "and its neighbour is not");
				[rep release];
			}
			[cell setDateValue:make_date(calendar, 2026, 6, 20, 0, 0, 0)];
			{
				NSRect day20 = [cell cg_rectForDay:20 inFrame:NSMakeRect(0, 0, 140, 120)];
				NSRect day16 = [cell cg_rectForDay:16 inFrame:NSMakeRect(0, 0, 140, 120)];
				NSBitmapImageRep *moved = render_cell(cell, 140.0, 120.0, host);

				check(count_where(moved, 120, (NSInteger)NSMinX(day20), (NSInteger)NSMinY(day20),
						  (NSInteger)NSMaxX(day20), (NSInteger)NSMaxY(day20), is_accent) > 10,
				      "moving the date moves the chip to June 20");
				check(count_where(moved, 120, (NSInteger)NSMinX(day16), (NSInteger)NSMinY(day16),
						  (NSInteger)NSMaxX(day16), (NSInteger)NSMaxY(day16), is_accent) == 0,
				      "and June 16 is plain again");
				[moved release];
			}
			check(NSIsEmptyRect([cell cg_rectForDay:16 inFrame:NSMakeRect(0, 0, 140, 120)]) == NO,
			      "the door keeps answering for the shown month");
		}

		if (failures == 0) {
			printf("date_picker: all checks passed\n");
			return 0;
		}
		printf("date_picker: FAILURES\n");
		return 1;
	}
}
