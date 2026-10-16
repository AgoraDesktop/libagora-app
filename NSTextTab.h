/*
 * NSTextTab.h — A STOP: the place a tab in a paragraph goes, and how the text lines up there.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **A TAB STOP IS A PLACE, AND THIS IS THE OBJECT THAT NAMES IT.** A tab character does not advance by a width; it
 * advances TO the next stop, and this class is that stop — a location in points along the line and the alignment the
 * text takes there (left, right, centre, or the decimal tab that lines numbers up on their point). A paragraph carries
 * an ordered array of them in `NSParagraphStyle -tabStops`, with `-defaultTabInterval` as the fallback after the last.
 *
 * **AND THE LAYOUT IS CORE TEXT'S.** `NSLayoutManager` builds a `CTParagraphStyle` whose TabStops and DefaultTabInterval
 * are this array's, and `CTLine`/`CTTypesetter` advance a `\t` to the next `CTTextTab` (see `libagora-text`'s
 * `CTTextTab.h`); so the ENGINE owns the walking and this class only says where the stops are. THE TYPES MAP 1:1:
 * `NSTextTabType`'s four values are `CTTextAlignment`'s four, which is why the initialiser that takes an alignment
 * and the one that takes a type agree.
 *
 * **AND THE COLUMN'S TERMINATORS ARE A LOCALE'S.** `+columnTerminatorsForLocale:` answers the characters that end a
 * decimal tab's column — the locale's decimal separator, which `NSLocale -decimalSeparator` reads from ICU — and
 * `NSTabColumnTerminatorsAttributeName` is the OPTIONS key that names them for one stop. WHAT IS STILL OWED IS
 * POSITIONING, NOT THE VOCABULARY: Core Text's `CTTextAlignment` has no decimal edge, so a `NSDecimalTabStopType`
 * stop is still carried into the engine as a LEFT stop and the terminators above are not yet read by the layout —
 * aligning a number ON its point is the slice behind this one.
 */
#ifndef APPKIT_NSTEXTAB_H
#define APPKIT_NSTEXTAB_H

#import <AppKit/NSText.h>

@class NSLocale;

NS_ASSUME_NONNULL_BEGIN

/* THE FOUR KINDS OF STOP, IN APPLE'S ORDER — which is `NSTextAlignment`'s order for the three that are an alignment,
 * with the decimal tab appended as the fourth. */
enum {
	NSLeftTabStopType = 0,
	NSRightTabStopType = 1,
	NSCenterTabStopType = 2,
	NSDecimalTabStopType = 3
};
typedef NSUInteger NSTextTabType;

/* **THE OPTIONS KEY FOR A DECIMAL TAB'S COLUMN TERMINATORS.** Its value is an array of strings — the characters a
 * number's point may be — and it rides in an `NSTextTab`'s `-options`; a stop with no entry uses
 * `+columnTerminatorsForLocale:`. */
extern NSString *const NSTabColumnTerminatorsAttributeName;

@interface NSTextTab : NSObject <NSCopying>
{
	CGFloat _location;
	NSTextTabType _tabStopType;
	NSDictionary *_options;		/* RETAINED */
}

/* THE TWO WAYS IN, WHICH AGREE: an alignment or a type, a location in points, and — for the alignment door — the
 * options Apple's newer API takes. `-initWithType:location:` is the older spelling and maps its type onto the
 * alignment the other door asks for. */
- (instancetype)initWithTextAlignment:(NSTextAlignment)alignment location:(CGFloat)loc
			      options:(nullable NSDictionary *)options;
- (instancetype)initWithType:(NSTextTabType)type location:(CGFloat)loc;

/* **THE CHARACTERS THAT END A DECIMAL TAB'S COLUMN FOR A LOCALE.** The answer is that locale's decimal separator —
 * "." in an English locale, "," in a German one — read from ICU through `NSLocale -decimalSeparator`; a nil locale
 * means `+[NSLocale currentLocale]`. */
+ (NSArray<NSString *> *)columnTerminatorsForLocale:(nullable NSLocale *)aLocale;

/* WHERE THE STOP IS ALONG THE LINE. */
- (CGFloat)location;

/* AND HOW THE TEXT LINES UP THERE. */
- (NSTextTabType)tabStopType;
- (NSTextAlignment)alignment;

/* THE OPTIONS AS THEY WERE GIVEN, borrowed rather than copied back. `NSTabColumnTerminatorsAttributeName` is the one
 * key this tier names; any other key is carried and answered and nothing more. */
- (nullable NSDictionary *)options;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSTEXTAB_H */
