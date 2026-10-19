/*
 * NSToolbarItemGroup — several toolbar items that move as one.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed.
 * SPDX-License-Identifier: MIT
 *
 * The class is deliberately thin: the toolbar's own layout flattens a group without a custom view into its subitems,
 * so the group needs only to own them and to refuse a member that would make the adjacency undefined.
 */
#import <AppKit/NSToolbarItemGroup.h>
#import <AppKit/NSToolbarItem.h>

#import "NSToolbar_internal.h"

#import <Foundation/NSArray.h>
#import <Foundation/NSException.h>
#import <Foundation/NSString.h>

@implementation NSToolbarItemGroup

- (instancetype)initWithItemIdentifier:(NSString *)itemIdentifier
{
	self = [super initWithItemIdentifier:itemIdentifier];
	if (self != nil) {
		_subitems = [[NSArray alloc] init];
	}
	return self;
}

- (void)dealloc
{
	[_subitems release];
	[super dealloc];
}

- (void)setSubitems:(NSArray *)subitems
{
	NSArray *copy;
	NSUInteger i;

	if (subitems == nil) {
		subitems = [NSArray array];
	}
	for (i = 0; i < [subitems count]; i++) {
		id item = [subitems objectAtIndex:i];

		if (![item isKindOfClass:[NSToolbarItem class]]) {
			[NSException raise:NSInvalidArgumentException
				    format:@"NSToolbarItemGroup subitems must be NSToolbarItems, not %@",
					   [item class]];
		}
		if ([item isKindOfClass:[NSToolbarItemGroup class]]) {
			[NSException raise:NSInvalidArgumentException
				    format:@"NSToolbarItemGroup may not contain another NSToolbarItemGroup "
					   @"(subitem %@)", [item itemIdentifier]];
		}
	}
	copy = [subitems copy];
	[_subitems release];
	_subitems = copy;
	[self cg_changed];
}

- (NSArray *)subitems
{
	return _subitems;
}

@end
