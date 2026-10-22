/*
 * NSNibConnector — a connection as an object, and the two kinds.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * Three fields, two substitutions and two applications. The interesting part is that the base is deliberately powerless: the
 * GRAPH is the objects', and the connector is only the instruction that joins them.
 */
#import "NSNibConnector.h"
#import "AppKitRefusal.h"

@implementation NSNibConnector

- (void)dealloc
{
	[_label release];
	[super dealloc];
}

- (id)source
{
	return _source;
}

- (void)setSource:(id)source
{
	_source = source;	/* NOT RETAINED: see the header */
}

- (id)destination
{
	return _destination;
}

- (void)setDestination:(id)destination
{
	_destination = destination;	/* NOT RETAINED */
}

- (NSString *)label
{
	return _label;
}

- (void)setLabel:(NSString *)label
{
	NSString *held = [label copy];

	[_label release];
	_label = held;
}

/* THE BASE DOES NOTHING, which is Apple's own contract for this door; the subclasses are what make a connection happen. */
- (void)establishConnection
{
}

/* **BY IDENTITY, AND EITHER END.** A placeholder is a stand-in OBJECT rather than a name, so `==` is the whole test; the
 * label is what a substituted source or destination still carries, which is why it is not touched. */
- (void)replaceObject:(id)oldObject withObject:(id)newObject
{
	if (oldObject == nil || oldObject == newObject) {
		return;
	}
	if (_source == oldObject) {
		_source = newObject;
	}
	if (_destination == oldObject) {
		_destination = newObject;
	}
}

/* A CONNECTION IS A VALUE IN A NIB'S RECORD, and its copy is a second object with the same ends (borrowed) and its own copy
 * of the label. */
- (id)copy
{
	NSNibConnector *copy = [[[self class] alloc] init];

	copy->_source = _source;
	copy->_destination = _destination;
	copy->_label = [_label copy];
	return copy;
}

@end

@implementation NSNibOutletConnector

/* **THE OUTLET.** `-label` is the key path and `-destination` the value; a source that cannot take a value by key path is
 * left alone, because a nib defect should not take a load down. */
- (void)establishConnection
{
	id source = [self source];
	NSString *path = [self label];

	if (source == nil || path == nil) {
		return;
	}
	if (![source respondsToSelector:@selector(setValue:forKeyPath:)]) {
		fn_refuse_window("-NSNibOutletConnector -establishConnection",
				 "a source that answers -setValue:forKeyPath:; this one cannot take an outlet, so the "
				 "connection is skipped rather than raised");
		return;
	}
	/* **THE KEY PATH IS THE RUNTIME'S TO CHECK, AND IT RAISES WHEN IT CANNOT.** `NSObject` answers
	 * `-setValue:forKeyPath:` for every object, so a `-respondsToSelector:` guard cannot tell a view from a string: the
	 * only test is the write. `NSNib`'s own connection pass catches the same exception for the same reason, and catching it
	 * here makes a defective connection a SKIPPED one instead of a load the process dies in. */
	@try {
		[source setValue:[self destination] forKeyPath:path];
	} @catch (NSException *exception) {
		(void)exception;
		fn_refuse_window("-NSNibOutletConnector -establishConnection",
				 "a source with that key path; the KVC write raised, so the connection is skipped rather than "
				 "taking the load down");
	}
}

@end

@implementation NSNibControlConnector

/* **THE ACTION: A TARGET AND A SELECTOR, IN THAT ORDER.** The name is turned into a selector here, which is where a nib's
 * spelling of an action meets the runtime's; a name that is not a selector is refused by `NSSelectorFromString` answering
 * something that will never be sent, and the guard below keeps the target half from being set twice. */
- (void)establishConnection
{
	id source = [self source];
	NSString *name = [self label];

	if (source == nil) {
		return;
	}
	if ([source respondsToSelector:@selector(setTarget:)]) {
		[source setTarget:[self destination]];
	}
	if (name != nil && [source respondsToSelector:@selector(setAction:)]) {
		[source setAction:NSSelectorFromString(name)];
	}
}

@end
