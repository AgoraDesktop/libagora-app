/*
 * NSNibConnector.h — A CONNECTION BETWEEN TWO OBJECTS IN A NIB, AS AN OBJECT.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **A NIB'S CONNECTION IS TWO OBJECTS AND A NAME, AND THAT IS WHAT THIS CLASS HOLDS.** `-source` is the object the
 * connection is APPLIED TO (a view with an outlet, a control with an action), `-destination` is the object it names, and
 * `-label` is what kind of connection it is: the KEY PATH of an outlet, or the SELECTOR NAME of an action. The base class
 * does nothing with them — `-establishConnection` is the documented no-op — and the two subclasses are the two kinds.
 *
 * **THE TWO OBJECTS ARE BORROWED AND THE LABEL IS COPIED**, which is Apple's ownership contract and the reason a nib can be
 * loaded, its connections established, and then the connections dropped: the graph they joined is the objects' own, and a
 * connector that retained both ends would keep a window alive for as long as its loading record lived.
 *
 * **`-replaceObject:withObject:` IS THE DOOR A LOADER NEEDS**, and it exists because a nib's placeholders are substituted
 * AFTER the archive is decoded: "NSNibFileOwner" becomes the caller's owner, "NSApplication" the shared application, and
 * every connection that named one has to name the other. It compares by IDENTITY, which is the only comparison a placeholder
 * can have.
 */
#ifndef APPKIT_NSNIBCONNECTOR_H
#define APPKIT_NSNIBCONNECTOR_H

#import <Foundation/NSObject.h>
#import <Foundation/NSString.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSNibConnector : NSObject
{
	id _source;		/* NOT RETAINED: the object graph owns both ends */
	id _destination;	/* NOT RETAINED */
	NSString *_label;	/* RETAINED: a key path or a selector name */
}

- (nullable id)source;
- (void)setSource:(nullable id)source;
- (nullable id)destination;
- (void)setDestination:(nullable id)destination;

/* THE KIND OF CONNECTION, spelled as the thing to apply: a key path for an outlet, a selector name for an action. */
- (nullable NSString *)label;
- (void)setLabel:(nullable NSString *)label;

/* **NOTHING, IN THIS CLASS.** Apple's own documentation is that the base implementation does nothing and a subclass
 * overrides it — which is exactly the split here: `NSNibOutletConnector` sets a value by key path and
 * `NSNibControlConnector` sets a target and an action. */
- (void)establishConnection;

/* Substitute an object in either end (by identity), which is what a loader does with a nib's placeholders. */
- (void)replaceObject:(nullable id)oldObject withObject:(nullable id)newObject;

@end

/* ==================================================================================================================
 * AND THE TWO KINDS, EACH ONE `-establishConnection`.
 * ================================================================================================================ */

/* **AN OUTLET IS `-setValue:forKeyPath:` ON THE SOURCE**, with `-label` as the path and `-destination` as the value — so a
 * connector joins a view to the object it points at without the loader knowing what either is. A source that does not
 * answer KVC is left alone rather than raising: a connection to an object that cannot take it is a nib defect, and a load
 * should not take the process down over one. */
@interface NSNibOutletConnector : NSNibConnector
- (void)establishConnection;
@end

/* **AN ACTION IS THE TARGET/ACTION PAIR ON A CONTROL**, with `-label` as the selector NAME and `-destination` as the
 * target. Two `-respondsToSelector:` guards, because the two halves are separate protocols on a control and a connector
 * that assumed both would raise on an object that has one. */
@interface NSNibControlConnector : NSNibConnector
- (void)establishConnection;
@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSNIBCONNECTOR_H */
