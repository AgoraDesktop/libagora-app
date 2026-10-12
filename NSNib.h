/*
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
/*
 * NSNib.h — a nib, and exactly how far this tier goes with one (stage C).
 *
 * **A NIB IS AN ARCHIVED OBJECT GRAPH, AND THIS TIER HAS NO READER FOR ONE.** Apple's nib file is its own
 * schema — class names, connection records, the keyed shape of a whole window — and that schema is not
 * published. So the split this class makes is the honest one, stated here rather than discovered by a caller:
 *
 *   * THE SOURCE IS REAL. `-initWithContentsOfURL:` and `-initWithNibNamed:bundle:` resolve and HOLD the nib,
 *     which is also Apple's own contract — a nib is not read until it is instantiated, so recording the source
 *     is the whole of what these two doors do in Apple's implementation too.
 *   * THE DECODING IS REFUSED BY NAME. `-instantiateNibWithExternalNameTable:` and its owner/top-level-objects
 *     form are what would walk the archive and build the objects; they answer NO and say why, because a
 *     guessed nib schema would be a WRONG VALUE rather than an unfinished feature — the same ground this
 *     tree's other refusals stand on.
 *
 * WHAT WOULD CLOSE THE GAP is a first-party interface format for THIS AppKit — an emitter and a reader this
 * tree owns, the way the interface side of the retired C++ kit owned one — and that is a unit of its own
 * rather than something to infer from Apple's bytes.
 *
 * AND `NSCoding` IS DELIBERATELY NOT ADOPTED, though Apple's class conforms: a conformance PROMISES
 * `-initWithCoder:` and `-encodeWithCoder:`, and no row in this class's ledger carries either. A conformance
 * whose methods are missing is a promise the class cannot keep at run time — the trap this tree has recorded
 * under declared-but-undefined — so it is absent and said so.
 */
#ifndef APPKIT_NSNIB_H
#define APPKIT_NSNIB_H

#import <Foundation/NSArray.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSObject.h>
#import <Foundation/NSString.h>
#import <Foundation/NSURL.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSNib : NSObject
{
	/* THE SOURCE, one of the two spellings a caller may give: a URL, or a name and (nullable) bundle. Loading is
	 * deferred to instantiation, so these are all this object holds. */
	NSURL *_url;
	NSString *_name;
	NSBundle *_bundle;
}

/* THE TWO WAYS IN. Both answer nil for a source they cannot even RECORD — a nil URL or a nil name — which is
 * stricter than Apple's nonnull spelling and is what the implementation accepts; the header says what it does
 * rather than what Apple's does. */
- (nullable instancetype)initWithContentsOfURL:(nullable NSURL *)nibFileURL;
- (nullable instancetype)initWithNibNamed:(nullable NSString *)nibName bundle:(nullable NSBundle *)bundle;

/* AND THE TWO DOORS THAT WOULD DECODE ONE — REFUSED BY NAME, answering NO, for the reason the class note gives.
 * `-instantiateNibWithOwner:topLevelObjects:` does not even write through its out-parameter when it refuses:
 * a caller's array is left exactly as it was rather than set to an empty one that would read as "instantiated,
 * nothing in it". */
- (BOOL)instantiateNibWithExternalNameTable:(NSDictionary *)nameTable;
/* AND THE OUT-PARAMETER IS ANNOTATED AT BOTH LEVELS, which an `NSArray **` requires and Apple's own era
 * header — written before nullability — leaves bare: the ARRAY POINTER may be nil and the array it would
 * receive is nil until a decode succeeds, which here is never. */
- (BOOL)instantiateNibWithOwner:(nullable id)owner
               topLevelObjects:(NSArray * _Nullable * _Nullable)topLevelObjects;

@end

/* THE TWO KEYS A NAME TABLE CARRIES, whose values are their own names — this tree's rule wherever Apple
 * publishes a symbol and no string. `NSNibOwner` is the object the nib's connections are made TO, and
 * `NSNibTopLevelObjects` is what a name table receives them IN. */
extern NSString *NSNibOwner;
extern NSString *NSNibTopLevelObjects;

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSNIB_H */
