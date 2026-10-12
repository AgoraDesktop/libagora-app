/* NSViewController.m — a controller for a view.
 *
 * © 2026 Kyle J. Cardozo. MIT licence (see LICENSE at the repository root).
 */
#import <AppKit/NSViewController.h>
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

@implementation NSViewController

/* AND THE TWO METHODS `NSCoding` REQUIRES. **THEY DO NOT CHAIN TO THE SUPERCLASS, AND THAT IS A FOOTPRINT OF THIS
 * TIER RATHER THAN A CHOICE**: Apple's `NSResponder` is archivable, this tree's is not, so there is no super
 * implementation to reach. When it gains one, these two must chain — and the note is here rather than in a commit
 * message because that is where the person making the change will be. */
- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[aCoder encodeObject:_nibName forKey:FNNibNameKey];
	[aCoder encodeObject:_nibBundle forKey:FNNibBundleKey];
	[aCoder encodeObject:_representedObject forKey:FNRepresentedObjectKey];
	[aCoder encodeObject:_title forKey:FNTitleKey];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
	self = [super init];
	if (self != nil) {
		_nibName = [[aDecoder decodeObjectForKey:FNNibNameKey] retain];
		_nibBundle = [[aDecoder decodeObjectForKey:FNNibBundleKey] retain];
		_representedObject = [[aDecoder decodeObjectForKey:FNRepresentedObjectKey] retain];
		_title = [[aDecoder decodeObjectForKey:FNTitleKey] retain];
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
	[NSException raise:NSInternalInconsistencyException
		    format:@"-loadView: loading nib `%@` needs NSNib, which this tier does not ship yet — set the view "
			   "with -setView: or override -loadView", _nibName];
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
