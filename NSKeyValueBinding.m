/*
 * NSKeyValueBinding.m — the binding registry, the markers, the placeholders and the NSEditor defaults.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **TWO TABLES AND A PRIVATE OBSERVER.** The registry is a process-global array of binding records (the receiver and
 * the observable are references, not owners); the exposed-binding names and the placeholders are class-keyed tables.
 * The observer is a private object rather than the receiver, so a receiver that implements
 * `-observeValueForKeyPath:...` for its own reasons does not collide with a binding, and so the binding can be removed
 * without touching the receiver's observation code at all.
 *
 * **THE VALUE GOES THROUGH KVC, WHICH IS THE FALLBACK APPLE DOCUMENTS.** The observer writes the new value to the
 * receiver under the binding name; a controller or a view that has a better idea overrides the binding doors (or the
 * setter), and the generic path is what a plain model object gets.
 */
#import <AppKit/NSKeyValueBinding.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSString.h>
#import <Foundation/NSException.h>
#import <Foundation/NSValue.h>
#import <Foundation/NSNull.h>
#import <Foundation/NSKeyValueCoding.h>
#import <Foundation/NSKeyValueObserving.h>

#import <objc/message.h>
#import <objc/runtime.h>

/* THE THREE MARKERS. Their identity is the whole API; the class is private and the instances are immortal. */
@interface FNBindingMarker : NSObject
{
@public
	NSString *_name;
}
@end

@implementation FNBindingMarker
- (NSString *)description
{
	return _name;
}
- (id)retain { return self; }
- (void)release { }
- (id)autorelease { return self; }
- (NSUInteger)retainCount { return NSUIntegerMax; }
@end

static FNBindingMarker *fn_marker(NSString *name)
{
	FNBindingMarker *marker = [[FNBindingMarker alloc] init];

	marker->_name = [name copy];
	return marker;	/* immortal by the overrides above */
}

id NSMultipleValuesMarker = nil;
id NSNoSelectionMarker = nil;
id NSNotApplicableMarker = nil;

/* **THE MARKERS ARE VALID BEFORE ANY BINDING CALL.** A caller may compare against them, or ask
 * `NSIsControllerMarker`, without having bound anything; a lazy init inside the binding functions would answer three
 * nils to that first question. The constructor is the one hook this file needs. */
__attribute__((constructor)) static void fn_binding_constructor(void);

static void fn_binding_init(void)
{
	if (NSMultipleValuesMarker == nil) {
		NSMultipleValuesMarker = fn_marker(@"NSMultipleValuesMarker");
		NSNoSelectionMarker = fn_marker(@"NSNoSelectionMarker");
		NSNotApplicableMarker = fn_marker(@"NSNotApplicableMarker");
	}
}

__attribute__((constructor)) static void fn_binding_constructor(void)
{
	fn_binding_init();
}

BOOL NSIsControllerMarker(id object)
{
	fn_binding_init();
	return (object == NSMultipleValuesMarker || object == NSNoSelectionMarker
		|| object == NSNotApplicableMarker);
}

/* ONE BINDING: who is bound to whom, at which key path, with which options, and the observer that carries it. */
@interface FNBinding : NSObject
{
@public
	__unsafe_unretained id _target;		/* NOT retained: the receiver */
	NSString *_binding;			/* RETAINED (a copy) */
	__unsafe_unretained id _observable;	/* NOT retained: the observed object */
	NSString *_keyPath;			/* RETAINED (a copy) */
	NSDictionary *_options;			/* RETAINED (a copy) */
	id _observer;				/* RETAINED */
}
@end

@implementation FNBinding
- (void)dealloc
{
	[_binding release];
	[_keyPath release];
	[_options release];
	[_observer release];
	[super dealloc];
}
@end

/* ONE PLACEHOLDER RULE. */
@interface FNPlaceholder : NSObject
{
@public
	Class _owner;
	id _marker;		/* may be nil */
	NSString *_binding;	/* may be nil */
	id _placeholder;	/* may be nil */
}
@end

@implementation FNPlaceholder
- (void)dealloc
{
	[_marker release];
	[_binding release];
	[_placeholder release];
	[super dealloc];
}
@end

static NSMutableArray *fn_bindings = nil;
static NSMutableArray *fn_placeholders = nil;
static NSMutableArray *fn_exposed = nil;	/* FNExposed {Class, NSString name} */

@interface FNExposed : NSObject
{
@public
	Class _owner;
	NSString *_name;
}
@end
@implementation FNExposed
- (void)dealloc { [_name release]; [super dealloc]; }
@end

static void fn_binding_tables(void)
{
	if (fn_bindings == nil) {
		fn_bindings = [[NSMutableArray alloc] init];
		fn_placeholders = [[NSMutableArray alloc] init];
		fn_exposed = [[NSMutableArray alloc] init];
	}
	fn_binding_init();
}

static FNBinding *fn_binding_for(id target, NSString *binding)
{
	NSUInteger i;

	fn_binding_tables();
	for (i = 0; i < [fn_bindings count]; i++) {
		FNBinding *held = [fn_bindings objectAtIndex:i];

		if (held->_target == target && [held->_binding isEqualToString:binding]) {
			return held;
		}
	}
	return nil;
}

/* THE OBSERVER: one per binding, so the receiver's own KVO code is never involved. */
@interface FNBindingObserver : NSObject
{
@public
	FNBinding *_binding;	/* NOT retained: the binding record owns the observer */
}
@end

@implementation FNBindingObserver

- (void)observeValueForKeyPath:(NSString *)keyPath
		      ofObject:(id)object
			change:(NSDictionary *)change
		       context:(void *)context
{
	id value;

	(void)keyPath;
	(void)object;
	(void)context;
	if ([[change objectForKey:NSKeyValueChangeNotificationIsPriorKey] boolValue]) {
		return;		/* the before-notification is not a value */
	}
	value = [change objectForKey:NSKeyValueChangeNewKey];
	if (value == [NSNull null]) {
		id placeholder = [_binding->_options objectForKey:NSNullPlaceholderBindingOption];

		value = (placeholder != nil) ? placeholder : nil;
	}
	/* **A MARKER IS NOT A VALUE, AND THE OPTION SAYS WHICH ANSWER THE CALLER WANTS.** Without the option the marker
	 * is written through (a view or controller knows what to do with it); with it, the binding raises, because a
	 * receiver that cannot take a marker is better told than silently handed one. */
	if (NSIsControllerMarker(value) &&
	    [[_binding->_options objectForKey:NSRaisesForNotApplicableKeysBindingOption] boolValue]) {
		[NSException raise:NSInvalidArgumentException
			    format:@"binding \"%@\" received the marker %@ and the options ask it to raise",
				   _binding->_binding, value];
	}
	[_binding->_target setValue:value forKey:_binding->_binding];
}

@end

@implementation NSObject (NSKeyValueBindingCreation)

+ (void)exposeBinding:(NSString *)binding
{
	FNExposed *entry;

	if (binding == nil) {
		return;
	}
	fn_binding_tables();
	{
		NSUInteger i;

		for (i = 0; i < [fn_exposed count]; i++) {
			FNExposed *held = [fn_exposed objectAtIndex:i];

			if (held->_owner == self && [held->_name isEqualToString:binding]) {
				return;
			}
		}
	}
	entry = [[FNExposed alloc] init];
	entry->_owner = self;
	entry->_name = [binding copy];
	[fn_exposed addObject:entry];
	[entry release];
}

- (NSArray *)exposedBindings
{
	NSMutableArray *names = [NSMutableArray array];
	NSUInteger i;
	Class cls;

	fn_binding_tables();
	/* THE CLASS CHAIN, because a subclass inherits its superclass's exposed names. */
	for (cls = object_getClass(self); cls != Nil; cls = class_getSuperclass(cls)) {
		for (i = 0; i < [fn_exposed count]; i++) {
			FNExposed *held = [fn_exposed objectAtIndex:i];

			if (held->_owner == cls && ![names containsObject:held->_name]) {
				[names addObject:held->_name];
			}
		}
	}
	return names;
}

- (Class)valueClassForBinding:(NSString *)binding
{
	(void)binding;
	return Nil;
}

- (void)bind:(NSString *)binding
    toObject:(id)observable
 withKeyPath:(NSString *)keyPath
     options:(NSDictionary *)options
{
	FNBinding *entry;
	FNBindingObserver *observer;

	if (binding == nil || observable == nil || keyPath == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"-bind:toObject:withKeyPath:options: needs a binding name, an observed "
				   "object and a key path"];
	}
	[self unbind:binding];
	entry = [[FNBinding alloc] init];
	entry->_target = self;
	entry->_binding = [binding copy];
	entry->_observable = observable;
	entry->_keyPath = [keyPath copy];
	entry->_options = [options copy];
	observer = [[FNBindingObserver alloc] init];
	observer->_binding = entry;
	entry->_observer = observer;
	fn_binding_tables();
	[fn_bindings addObject:entry];
	[entry release];
	/* **THE INITIAL CHANGE IS WHY THE RECORD IS STORED FIRST.** `addObserver:` delivers it before returning, and the
	 * observer has to find a complete binding when it does. */
	[observable addObserver:observer
		     forKeyPath:keyPath
			options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial)
			context:(void *)entry];
}

- (void)unbind:(NSString *)binding
{
	FNBinding *entry;

	if (binding == nil) {
		return;
	}
	entry = fn_binding_for(self, binding);
	if (entry == nil) {
		return;		/* unbinding a name that was never bound is a no-op, not an exception */
	}
	[entry->_observable removeObserver:entry->_observer forKeyPath:entry->_keyPath];
	[fn_bindings removeObjectIdenticalTo:entry];
}

- (NSDictionary *)infoForBinding:(NSString *)binding
{
	FNBinding *entry = fn_binding_for(self, binding);

	if (entry == nil) {
		return nil;
	}
	return [NSDictionary dictionaryWithObjectsAndKeys:
		entry->_observable, NSObservedObjectKey,
		entry->_keyPath, NSObservedKeyPathKey,
		(entry->_options != nil ? entry->_options : (id)[NSDictionary dictionary]), NSOptionsKey,
		nil];
}

- (NSArray *)optionDescriptionsForBinding:(NSString *)binding
{
	(void)binding;
	return [NSArray array];
}

@end

@implementation NSObject (NSPlaceholders)

+ (void)setDefaultPlaceholder:(id)placeholder
		    forMarker:(id)marker
		  withBinding:(NSString *)binding
{
	FNPlaceholder *entry;
	NSUInteger i;

	fn_binding_tables();
	for (i = 0; i < [fn_placeholders count]; i++) {
		FNPlaceholder *held = [fn_placeholders objectAtIndex:i];

		if (held->_owner == self && held->_marker == marker &&
		    ((held->_binding == nil && binding == nil) ||
		     [held->_binding isEqualToString:binding])) {
			[placeholder retain];
			[held->_placeholder release];
			held->_placeholder = placeholder;
			return;
		}
	}
	entry = [[FNPlaceholder alloc] init];
	entry->_owner = self;
	entry->_marker = [(marker != nil ? marker : (id)[NSNull null]) retain];
	entry->_binding = [binding copy];
	entry->_placeholder = [placeholder retain];
	[fn_placeholders addObject:entry];
	[entry release];
}

+ (id)defaultPlaceholderForMarker:(id)marker withBinding:(NSString *)binding
{
	Class cls;

	fn_binding_tables();
	for (cls = self; cls != Nil; cls = class_getSuperclass(cls)) {
		NSUInteger i;

		for (i = 0; i < [fn_placeholders count]; i++) {
			FNPlaceholder *held = [fn_placeholders objectAtIndex:i];
			id heldMarker = (held->_marker == [NSNull null]) ? nil : held->_marker;

			if (held->_owner != cls || heldMarker != marker) {
				continue;
			}
			if (held->_binding == nil) {
				return held->_placeholder;	/* the class-wide rule */
			}
			if (binding != nil && [held->_binding isEqualToString:binding]) {
				return held->_placeholder;
			}
		}
	}
	return nil;
}

@end

@implementation NSObject (NSEditorRegistration)

- (void)objectDidBeginEditing:(id)editor
{
	(void)editor;
}

- (void)objectDidEndEditing:(id)editor
{
	(void)editor;
}

@end

@implementation NSObject (NSEditor)

- (void)discardEditing
{
}

- (BOOL)commitEditing
{
	return YES;
}

- (void)commitEditingWithDelegate:(id)delegate
		didCommitSelector:(SEL)didCommitSelector
		      contextInfo:(void *)contextInfo
{
	if (delegate != nil && didCommitSelector != NULL) {
		((void (*)(id, SEL, id, BOOL, void *))objc_msgSend)(delegate, didCommitSelector, self, YES,
								   contextInfo);
	}
}

@end

/* THE CONSTANTS, EACH ITS OWN NAME. */
NSString *NSAlignmentBinding = @"NSAlignmentBinding";
NSString *NSAlternateImageBinding = @"NSAlternateImageBinding";
NSString *NSAlternateTitleBinding = @"NSAlternateTitleBinding";
NSString *NSAnimateBinding = @"NSAnimateBinding";
NSString *NSAnimationDelayBinding = @"NSAnimationDelayBinding";
NSString *NSArgumentBinding = @"NSArgumentBinding";
NSString *NSAttributedStringBinding = @"NSAttributedStringBinding";
NSString *NSContentArrayBinding = @"NSContentArrayBinding";
NSString *NSContentArrayForMultipleSelectionBinding = @"NSContentArrayForMultipleSelectionBinding";
NSString *NSContentBinding = @"NSContentBinding";
NSString *NSContentDictionaryBinding = @"NSContentDictionaryBinding";
NSString *NSContentHeightBinding = @"NSContentHeightBinding";
NSString *NSContentObjectBinding = @"NSContentObjectBinding";
NSString *NSContentObjectsBinding = @"NSContentObjectsBinding";
NSString *NSContentSetBinding = @"NSContentSetBinding";
NSString *NSContentValuesBinding = @"NSContentValuesBinding";
NSString *NSContentWidthBinding = @"NSContentWidthBinding";
NSString *NSCriticalValueBinding = @"NSCriticalValueBinding";
NSString *NSDataBinding = @"NSDataBinding";
NSString *NSDisplayPatternTitleBinding = @"NSDisplayPatternTitleBinding";
NSString *NSDisplayPatternValueBinding = @"NSDisplayPatternValueBinding";
NSString *NSDocumentEditedBinding = @"NSDocumentEditedBinding";
NSString *NSDoubleClickArgumentBinding = @"NSDoubleClickArgumentBinding";
NSString *NSDoubleClickTargetBinding = @"NSDoubleClickTargetBinding";
NSString *NSEditableBinding = @"NSEditableBinding";
NSString *NSEnabledBinding = @"NSEnabledBinding";
NSString *NSExcludedKeysBinding = @"NSExcludedKeysBinding";
NSString *NSFilterPredicateBinding = @"NSFilterPredicateBinding";
NSString *NSFontBinding = @"NSFontBinding";
NSString *NSFontBoldBinding = @"NSFontBoldBinding";
NSString *NSFontFamilyNameBinding = @"NSFontFamilyNameBinding";
NSString *NSFontItalicBinding = @"NSFontItalicBinding";
NSString *NSFontNameBinding = @"NSFontNameBinding";
NSString *NSFontSizeBinding = @"NSFontSizeBinding";
NSString *NSHeaderTitleBinding = @"NSHeaderTitleBinding";
NSString *NSHiddenBinding = @"NSHiddenBinding";
NSString *NSImageBinding = @"NSImageBinding";
NSString *NSIncludedKeysBinding = @"NSIncludedKeysBinding";
NSString *NSInitialKeyBinding = @"NSInitialKeyBinding";
NSString *NSInitialValueBinding = @"NSInitialValueBinding";
NSString *NSIsIndeterminateBinding = @"NSIsIndeterminateBinding";
NSString *NSLabelBinding = @"NSLabelBinding";
NSString *NSLocalizedKeyDictionaryBinding = @"NSLocalizedKeyDictionaryBinding";
NSString *NSManagedObjectContextBinding = @"NSManagedObjectContextBinding";
NSString *NSMaximumRecentsBinding = @"NSMaximumRecentsBinding";
NSString *NSMaxValueBinding = @"NSMaxValueBinding";
NSString *NSMaxWidthBinding = @"NSMaxWidthBinding";
NSString *NSMinValueBinding = @"NSMinValueBinding";
NSString *NSMinWidthBinding = @"NSMinWidthBinding";
NSString *NSMixedStateImageBinding = @"NSMixedStateImageBinding";
NSString *NSOffStateImageBinding = @"NSOffStateImageBinding";
NSString *NSOnStateImageBinding = @"NSOnStateImageBinding";
NSString *NSPredicateBinding = @"NSPredicateBinding";
NSString *NSRecentSearchesBinding = @"NSRecentSearchesBinding";
NSString *NSRepresentedFilenameBinding = @"NSRepresentedFilenameBinding";
NSString *NSRowHeightBinding = @"NSRowHeightBinding";
NSString *NSSelectedIdentifierBinding = @"NSSelectedIdentifierBinding";
NSString *NSSelectedIndexBinding = @"NSSelectedIndexBinding";
NSString *NSSelectedLabelBinding = @"NSSelectedLabelBinding";
NSString *NSSelectedObjectBinding = @"NSSelectedObjectBinding";
NSString *NSSelectedObjectsBinding = @"NSSelectedObjectsBinding";
NSString *NSSelectedTagBinding = @"NSSelectedTagBinding";
NSString *NSSelectedValueBinding = @"NSSelectedValueBinding";
NSString *NSSelectedValuesBinding = @"NSSelectedValuesBinding";
NSString *NSSelectionIndexesBinding = @"NSSelectionIndexesBinding";
NSString *NSSelectionIndexPathsBinding = @"NSSelectionIndexPathsBinding";
NSString *NSSortDescriptorsBinding = @"NSSortDescriptorsBinding";
NSString *NSTargetBinding = @"NSTargetBinding";
NSString *NSTextColorBinding = @"NSTextColorBinding";
NSString *NSTitleBinding = @"NSTitleBinding";
NSString *NSToolTipBinding = @"NSToolTipBinding";
NSString *NSTransparentBinding = @"NSTransparentBinding";
NSString *NSValueBinding = @"NSValueBinding";
NSString *NSValuePathBinding = @"NSValuePathBinding";
NSString *NSValueURLBinding = @"NSValueURLBinding";
NSString *NSVisibleBinding = @"NSVisibleBinding";
NSString *NSWarningValueBinding = @"NSWarningValueBinding";
NSString *NSWidthBinding = @"NSWidthBinding";
NSString *NSAllowsEditingMultipleValuesSelectionBindingOption = @"NSAllowsEditingMultipleValuesSelectionBindingOption";
NSString *NSAllowsNullArgumentBindingOption = @"NSAllowsNullArgumentBindingOption";
NSString *NSAlwaysPresentsApplicationModalAlertsBindingOption = @"NSAlwaysPresentsApplicationModalAlertsBindingOption";
NSString *NSConditionallySetsEditableBindingOption = @"NSConditionallySetsEditableBindingOption";
NSString *NSConditionallySetsEnabledBindingOption = @"NSConditionallySetsEnabledBindingOption";
NSString *NSConditionallySetsHiddenBindingOption = @"NSConditionallySetsHiddenBindingOption";
NSString *NSContinuouslyUpdatesValueBindingOption = @"NSContinuouslyUpdatesValueBindingOption";
NSString *NSCreatesSortDescriptorBindingOption = @"NSCreatesSortDescriptorBindingOption";
NSString *NSDeletesObjectsOnRemoveBindingsOption = @"NSDeletesObjectsOnRemoveBindingsOption";
NSString *NSDisplayNameBindingOption = @"NSDisplayNameBindingOption";
NSString *NSDisplayPatternBindingOption = @"NSDisplayPatternBindingOption";
NSString *NSContentPlacementTagBindingOption = @"NSContentPlacementTagBindingOption";
NSString *NSHandlesContentAsCompoundValueBindingOption = @"NSHandlesContentAsCompoundValueBindingOption";
NSString *NSInsertsNullPlaceholderBindingOption = @"NSInsertsNullPlaceholderBindingOption";
NSString *NSInvokesSeparatelyWithArrayObjectsBindingOption = @"NSInvokesSeparatelyWithArrayObjectsBindingOption";
NSString *NSMultipleValuesPlaceholderBindingOption = @"NSMultipleValuesPlaceholderBindingOption";
NSString *NSNoSelectionPlaceholderBindingOption = @"NSNoSelectionPlaceholderBindingOption";
NSString *NSNotApplicablePlaceholderBindingOption = @"NSNotApplicablePlaceholderBindingOption";
NSString *NSNullPlaceholderBindingOption = @"NSNullPlaceholderBindingOption";
NSString *NSRaisesForNotApplicableKeysBindingOption = @"NSRaisesForNotApplicableKeysBindingOption";
NSString *NSPredicateFormatBindingOption = @"NSPredicateFormatBindingOption";
NSString *NSSelectorNameBindingOption = @"NSSelectorNameBindingOption";
NSString *NSSelectsAllWhenSettingContentBindingOption = @"NSSelectsAllWhenSettingContentBindingOption";
NSString *NSValidatesImmediatelyBindingOption = @"NSValidatesImmediatelyBindingOption";
NSString *NSValueTransformerNameBindingOption = @"NSValueTransformerNameBindingOption";
NSString *NSValueTransformerBindingOption = @"NSValueTransformerBindingOption";

/* THE THREE INFO KEYS (the binding names and options above are generated from Apple's list). */
NSString *NSObservedObjectKey = @"NSObservedObjectKey";
NSString *NSObservedKeyPathKey = @"NSObservedKeyPathKey";
NSString *NSOptionsKey = @"NSOptionsKey";
