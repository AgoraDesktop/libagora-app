/*
 * NSNib — the source of a nib, and the refusal at the door that would decode one.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 *
 * See the header for WHY the split falls where it does. What is worth repeating here is that the refusal is not
 * a placeholder: it names the thing that is missing (a reader for a nib archive's object graph), the reason it
 * is not guessed (an unpublished schema), and what would close it (a first-party interface format).
 */
#import <AppKit/NSNib.h>

#include <stdio.h>

/* THE TWO KEYS, whose values are their own names. */
NSString *NSNibOwner = @"NSNibOwner";
NSString *NSNibTopLevelObjects = @"NSNibTopLevelObjects";

/* AND THE ONE REFUSAL, in one place because both doors speak it: a second copy of this sentence would be a
 * second thing to keep true, and the door that refuses is named in it. */
static BOOL fn_refuse(const char *door)
{
	fprintf(stderr, "APPKIT-REFUSE: %s needs a reader for a nib archive's OBJECT GRAPH, and this tier has "
			"none: a nib is an archived object graph in Apple's own schema (class names, connection "
			"records, the keyed shape of a whole window), that schema is not published, and this tree will "
			"not guess it — a guessed schema is a wrong value rather than an unfinished feature. What IS "
			"here is the nib as a SOURCE: `-initWithContentsOfURL:` and `-initWithNibNamed:bundle:` hold it, "
			"and the decoding doors answer NO. See NSNib.h.\n", door);
	return NO;
}

@implementation NSNib

- (instancetype)initWithContentsOfURL:(NSURL *)nibFileURL
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	/* A SOURCE THAT IS NOT THERE IS NOT A NIB. The URL is recorded rather than read, which is Apple's own
	 * contract — a nib is loaded when it is INSTANTIATED — but a nil one is refused here rather than carried
	 * to a door that would refuse it for a different reason. */
	if (nibFileURL == nil) {
		[self release];
		return nil;
	}
	_url = [nibFileURL retain];
	return self;
}

- (instancetype)initWithNibNamed:(NSString *)nibName bundle:(NSBundle *)bundle
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	/* AND A NIB WITH NO NAME IS REFUSED FOR THE SAME REASON, while a nil BUNDLE is not: Apple's contract is
	 * that a nil bundle means the main one, so it is recorded as given and resolved later. */
	if (nibName == nil) {
		[self release];
		return nil;
	}
	_name = [nibName retain];
	_bundle = [bundle retain];
	return self;
}

- (void)dealloc
{
	[_url release];
	[_name release];
	[_bundle release];
	[super dealloc];
}

- (BOOL)instantiateNibWithExternalNameTable:(NSDictionary *)nameTable
{
	(void)nameTable;
	return fn_refuse("-instantiateNibWithExternalNameTable:");
}

- (BOOL)instantiateNibWithOwner:(id)owner topLevelObjects:(NSArray **)topLevelObjects
{
	(void)owner;
	/* NOT EVEN THE OUT-PARAMETER IS TOUCHED, which is the header's promise and is worth the line: a caller that
	 * reads its array after a NO sees its own value, not an empty array that would read as a success. */
	(void)topLevelObjects;
	return fn_refuse("-instantiateNibWithOwner:topLevelObjects:");
}

@end
