/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 */

/* NSViewController.m — a controller for a view.
 *
 * © 2026 Kyle J. Cardozo. MIT licence (see LICENSE at the repository root).
 */
#import <AppKit/NSViewController.h>
#import <AppKit/NSNib.h>
#import <AppKit/NSView.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSException.h>
#import <Foundation/NSString.h>

#include <stdio.h>

/* **THE ARCHIVE KEYS ARE OURS, ON PURPOSE.** Apple archives a view controller INSIDE A NIB, and the keys that
 * format uses are that format's business — inventing them from a plausible reading would produce an archive that
 * decodes into nothing. A controller archived by THIS tier round trips through the four values below and says so;
 * a nib's own archive is not read. */
static NSString * const FNNibNameKey = @"NSViewControllerNibName";
static NSString * const FNNibBundleKey = @"NSViewControllerNibBundle";
static NSString * const FNRepresentedObjectKey = @"NSViewControllerRepresentedObject";
static NSString * const FNTitleKey = @"NSViewControllerTitle";
static NSString * const FNViewKey = @"NSViewControllerView";

@implementation NSViewController

+ (BOOL)supportsSecureCoding
{
	return YES;
}

/* AND THE TWO METHODS `NSCoding` REQUIRES. **THEY CHAIN NOW, WHICH IS WHAT THE NOTE HERE ASKED FOR.** `NSResponder`
 * gained its coding methods, so a controller's archive carries its responder state as well as the four values below —
 * and the omission this comment used to record ("they do not chain to the superclass, and that is a footprint of this
 * tier") is closed rather than left standing. */
- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[super encodeWithCoder:aCoder];
	[aCoder encodeObject:_nibName forKey:FNNibNameKey];
	[aCoder encodeObject:_nibBundle forKey:FNNibBundleKey];
	[aCoder encodeObject:_representedObject forKey:FNRepresentedObjectKey];
	[aCoder encodeObject:_title forKey:FNTitleKey];
	[aCoder encodeObject:_view forKey:FNViewKey];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
	self = [super initWithCoder:aDecoder];
	if (self != nil) {
		_nibName = [[aDecoder decodeObjectForKey:FNNibNameKey] retain];
		_nibBundle = [[aDecoder decodeObjectForKey:FNNibBundleKey] retain];
		_representedObject = [[aDecoder decodeObjectForKey:FNRepresentedObjectKey] retain];
		_title = [[aDecoder decodeObjectForKey:FNTitleKey] retain];
		_view = [[aDecoder decodeObjectForKey:FNViewKey] retain];
	}
	return self;
}

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
	self = [super init];
	if (self != nil) {
		_nibName = [nibNameOrNil copy];
		_nibBundle = [nibBundleOrNil retain];
	}
	return self;
}

- (void)dealloc
{
	[_nibName release];
	[_nibBundle release];
	[_representedObject release];
	[_title release];
	[_view release];
	[super dealloc];
}

- (NSString *)nibName
{
	/* WHATEVER WAS PASSED, which is the whole of Apple's default implementation — the name is remembered even
	 * though nothing here can load it, because a caller reading it back must get what it gave. */
	return _nibName;
}

- (NSBundle *)nibBundle
{
	return _nibBundle;
}

- (NSView *)view
{
	/* **THE DOOR LOADS THE VIEW, WHICH IS THE ONE PIECE OF ORDERING THIS CLASS OWNS.** A subclass overrides
	 * `-loadView`, and every caller is told to ask `-view` and let the controller decide — so the load happens
	 * here and not at the caller's discretion. */
	if (_view == nil) {
		[self loadView];
	}
	return _view;
}

- (void)setView:(NSView *)view
{
	if (_view == view) {
		return;
	}
	[view retain];
	[_view release];
	_view = view;
}

- (void)loadView
{
	if (_view != nil) {
		return;	/* a view is already there: Apple's implementation handles a redundant invocation too */
	}
	if (_nibName == nil) {
		/* APPLE RAISES HERE AND SO DOES THIS — its own documentation says a nil nib name means `-loadView` throws,
		 * and the exception is the honest answer for a controller that was built with nothing to load and no view
		 * to show. */
		[NSException raise:NSInternalInconsistencyException
			    format:@"-loadView: no nib name and no view: set a view with -setView: or override -loadView"];
	}
	/* **THE NIB IS LOADED WITH THIS CONTROLLER AS ITS OWNER**, which is what makes a `view` outlet on the file's
	 * owner land on `-setView:` and what makes an action wired to the owner reach this object. */
	{
		NSNib *nib = [[NSNib alloc] initWithNibNamed:_nibName bundle:_nibBundle];
		NSArray *objects = nil;

		if (nib == nil) {
			[NSException raise:NSInternalInconsistencyException
				    format:@"-loadView: `%@` is not a recordable nib name", _nibName];
		}
		if (![nib instantiateNibWithOwner:self topLevelObjects:&objects]) {
			[nib release];
			[NSException raise:NSInternalInconsistencyException
				    format:@"-loadView: the nib `%@` could not be instantiated (see NSNib's stderr for the "
					   "refusal)", _nibName];
		}
		[nib release];
		/* **AND IF THE FILE DID NOT WIRE THE OWNER'S `view` OUTLET, THE FIRST TOP-LEVEL VIEW IS THE VIEW.** Apple's
		 * nibs wire the outlet; a hand-written one need not, and taking the only view in the file is what makes the
		 * simple case simple without making the wired case ambiguous. */
		if (_view == nil && [objects isKindOfClass:[NSArray class]]) {
			NSUInteger i;

			for (i = 0; i < [objects count]; i++) {
				id object = [objects objectAtIndex:i];

				if ([object isKindOfClass:[NSView class]]) {
					[self setView:object];
					break;
				}
			}
		}
	}
	if (_view == nil) {
		[NSException raise:NSInternalInconsistencyException
			    format:@"-loadView: the nib `%@` instantiated but produced no view", _nibName];
	}
}

- (id)representedObject
{
	return _representedObject;
}

- (void)setRepresentedObject:(id)representedObject
{
	/* **RETAINED, NOT COPIED, WHICH IS APPLE'S OWN CONTRACT FOR THIS PROPERTY** and the opposite of the title's
	 * below: a controller stands for an object it does not own the identity of, while a title is a string the
	 * controller holds. The two setters differing is deliberate and the probe asserts both halves. */
	if (_representedObject == representedObject) {
		return;
	}
	[representedObject retain];
	[_representedObject release];
	_representedObject = representedObject;
}

- (NSString *)title
{
	return _title;
}

- (void)setTitle:(NSString *)title
{
	NSString *old = _title;

	_title = [title copy];	/* COPIED — see the note above */
	[old release];
}

/* ---- THE NSEditor INFORMAL PROTOCOL ---------------------------------------------------------- */

- (BOOL)commitEditing
{
	/* **YES, AND IT IS A REAL ANSWER RATHER THAN A SHRUG: there are no registered editors.** Apple's contract is
	 * that this answers YES when every editor has committed, and an editor here would be a control bound to this
	 * controller's `representedObject` — a binding, which needs the control classes this tier has not reached. With
	 * none registered there is nothing that can fail, so the commit succeeds. */
	return YES;
}

- (void)discardEditing
{
	/* AND THERE IS NOTHING TO DISCARD, for the reason above. Stated rather than left as an empty body that looks
	 * like a stub. */
}

- (void)commitEditingWithDelegate:(id)delegate
	       didCommitSelector:(SEL)didCommitSelector
		     contextInfo:(void *)contextInfo
{
	(void)delegate;
	(void)didCommitSelector;
	(void)contextInfo;
	/* **REFUSED BY NAME, WITH NOTHING TO REPORT.** Apple calls the delegate's selector with three arguments
	 * (`editor`, the BOOL, the context info), and a three-argument send is not something this tier's Foundation
	 * offers without a trampoline — so rather than calling it with the wrong arity, the door says why it is not
	 * calling it. There are no editors, so nothing is lost by not calling it: the callback exists to report how a
	 * commit went. */
	fprintf(stderr, "APPKIT-REFUSE: -commitEditingWithDelegate:didCommitSelector:contextInfo: has no editors to "
			"commit and no way to send a three-argument callback; the delegate is not called\n");
}

@end
