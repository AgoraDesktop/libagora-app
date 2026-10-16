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
 * **WHAT IS NOT HERE, NAMED RATHER THAN STUBBED:** `+columnTerminatorsForLocale:` (it answers the characters that end
 * a decimal tab's column, which needs `NSLocale` and a per-locale table this tier has not got), and `-options` is
 * carried and answered and has no reader — Apple names no key for that dictionary anywhere in the era's headers.
 */
#ifndef APPKIT_NSTEXTAB_H
#define APPKIT_NSTEXTAB_H

#import <AppKit/NSText.h>

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

/* WHERE THE STOP IS ALONG THE LINE. */
- (CGFloat)location;

/* AND HOW THE TEXT LINES UP THERE. */
- (NSTextTabType)tabStopType;
- (NSTextAlignment)alignment;

/* THE OPTIONS AS THEY WERE GIVEN, borrowed rather than copied back — Apple names no key for them here. */
- (nullable NSDictionary *)options;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSTEXTAB_H */
