/*
 * NSKeyValueBinding.h — the generic binding layer: one object observes another and writes the value through KVC.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **A BINDING IS AN OBSERVATION WITH A DESTINATION.** `-bind:toObject:withKeyPath:options:` makes the receiver observe
 * `observable` at `keyPath` and, whenever the value changes (including the Initial one), write it to the receiver's
 * own `binding` key through `-setValue:forKey:`. That is the fallback Apple's header describes in as many words —
 * "for a new key exposed through this method, the default implementation simply falls back to key-value coding" —
 * and it is what lets a plain object be bound before any view or controller has an opinion. It is ONE-WAY
 * (observable -> receiver); the reverse direction (a control writing its edited value back) belongs to the control
 * classes and is a later row.
 *
 * **THE THREE MARKERS ARE THE "NOT A VALUE" VOCABULARY.** A binding that reads a selection may have no selection, or
 * several; `NSNoSelectionMarker`, `NSMultipleValuesMarker` and `NSNotApplicableMarker` are the singleton objects that
 * say which, and `NSIsControllerMarker` is the question a caller asks instead of comparing classes. They are the first
 * thing the controller family will need from this file.
 *
 * **THE OPTIONS ARE STORED, AND THE ONES THIS LAYER CAN HONOUR ARE HONOURED.** `NSNullPlaceholderBindingOption` supplies
 * the value written when the observed value is NSNull; `NSRaisesForNotApplicableKeysBindingOption` makes a marker value
 * raise instead of being written. The rest — continuous updates, compound values, the editing-multiple-values family,
 * value transformers — are STORED and ANSWERED through `-infoForBinding:` and have no reader HERE; each belongs to the
 * control or controller that would act on it. The header names that rather than implying the whole dictionary is live.
 *
 * **BINDINGS MUST BE REMOVED BEFORE THE RECEIVER DIES, AND APPLE SAYS SO TOO.** This library's registry is
 * process-global (there is no per-object ivar to grow), so a binding outliving its receiver leaks the info and, worse,
 * keeps writing to a dead address. `-unbind:` is the door; a receiver released with bindings still attached is a
 * caller error with a documented consequence, which is exactly Apple's caveat for bindings created on ordinary
 * objects.
 */
#ifndef APPKIT_NSKEYVALUEBINDING_H
#define APPKIT_NSKEYVALUEBINDING_H

#import <Foundation/NSObject.h>

@class NSArray;
@class NSDictionary;
@class NSString;

NS_ASSUME_NONNULL_BEGIN

/* THE THREE MARKERS — Apple's own names and its own three. */
extern id NSMultipleValuesMarker;
extern id NSNoSelectionMarker;
extern id NSNotApplicableMarker;

/* YES for one of the three markers above; NO for every other object, including a marker-shaped impostor. */
BOOL NSIsControllerMarker(id _Nullable object);

/* THE KEYS OF `-infoForBinding:`'S ANSWER: the observed object, the key path, and the options dictionary. */
extern NSString *NSObservedObjectKey;
extern NSString *NSObservedKeyPathKey;
extern NSString *NSOptionsKey;

@interface NSObject (NSKeyValueBindingCreation)

/* **THE CLASS-SIDE REGISTRY OF BINDABLE NAMES.** `+exposeBinding:` is how a class says "this binding name is mine";
 * `-exposedBindings` answers the names this class and its superclasses have exposed. */
+ (void)exposeBinding:(NSString *)binding;
- (NSArray *)exposedBindings;

/* The value's class for a binding, for a transformer to match; nil unless a class overrides it. */
- (nullable Class)valueClassForBinding:(NSString *)binding;

/* **THE PAIR THAT MAKES A BINDING.** Binding an already-bound name replaces the old binding (the old observation is
 * removed first), so a rebind cannot double-deliver. A nil binding, observable or key path raises
 * `NSInvalidArgumentException`. */
- (void)bind:(NSString *)binding
    toObject:(id)observable
 withKeyPath:(NSString *)keyPath
     options:(nullable NSDictionary *)options;
- (void)unbind:(NSString *)binding;

/* THE BINDING'S OWN RECORD, or nil; the dictionary has the three keys above. */
- (nullable NSDictionary *)infoForBinding:(NSString *)binding;

/* INTERFACE BUILDER'S OPTION DESCRIPTIONS. This tier has no IB; the answer is an empty array rather than a refusal,
 * because "no descriptions" is a truthful answer for a binding whose options are the generic dictionary. */
- (NSArray *)optionDescriptionsForBinding:(NSString *)binding;

@end

@interface NSObject (NSPlaceholders)

/* **A PLACEHOLDER IS WHAT A BINDING SHOWS FOR A MARKER INSTEAD OF THE MARKER.** The lookup walks the class chain, so a
 * subclass inherits its superclass's placeholder unless it sets its own; `binding` may be nil to mean "every binding
 * of this class". */
+ (void)setDefaultPlaceholder:(nullable id)placeholder
		    forMarker:(nullable id)marker
		  withBinding:(nullable NSString *)binding;
+ (nullable id)defaultPlaceholderForMarker:(nullable id)marker
			       withBinding:(nullable NSString *)binding;

@end

/* THE NSEditor INFORMAL PROTOCOL, DECLARED ON NSObject WITH WORKING DEFAULTS.** A plain object has no editors, so
 * registration is a no-op and committing is YES; a controller overrides them to track what is being edited. */
@interface NSObject (NSEditorRegistration)
- (void)objectDidBeginEditing:(id)editor;
- (void)objectDidEndEditing:(id)editor;
@end

@interface NSObject (NSEditor)
- (void)discardEditing;
- (BOOL)commitEditing;
- (void)commitEditingWithDelegate:(nullable id)delegate
		didCommitSelector:(nullable SEL)didCommitSelector
		      contextInfo:(nullable void *)contextInfo;
@end

/* ---- THE BINDING NAMES, WHICH ARE APPLE'S VOCABULARY AND ARE STRINGS THAT EQUAL THEIR OWN NAMES ------------------- */
extern NSString *NSAlignmentBinding;
extern NSString *NSAlternateImageBinding;
extern NSString *NSAlternateTitleBinding;
extern NSString *NSAnimateBinding;
extern NSString *NSAnimationDelayBinding;
extern NSString *NSArgumentBinding;
extern NSString *NSAttributedStringBinding;
extern NSString *NSContentArrayBinding;
extern NSString *NSContentArrayForMultipleSelectionBinding;
extern NSString *NSContentBinding;
extern NSString *NSContentDictionaryBinding;
extern NSString *NSContentHeightBinding;
extern NSString *NSContentObjectBinding;
extern NSString *NSContentObjectsBinding;
extern NSString *NSContentSetBinding;
extern NSString *NSContentValuesBinding;
extern NSString *NSContentWidthBinding;
extern NSString *NSCriticalValueBinding;
extern NSString *NSDataBinding;
extern NSString *NSDisplayPatternTitleBinding;
extern NSString *NSDisplayPatternValueBinding;
extern NSString *NSDocumentEditedBinding;
extern NSString *NSDoubleClickArgumentBinding;
extern NSString *NSDoubleClickTargetBinding;
extern NSString *NSEditableBinding;
extern NSString *NSEnabledBinding;
extern NSString *NSExcludedKeysBinding;
extern NSString *NSFilterPredicateBinding;
extern NSString *NSFontBinding;
extern NSString *NSFontBoldBinding;
extern NSString *NSFontFamilyNameBinding;
extern NSString *NSFontItalicBinding;
extern NSString *NSFontNameBinding;
extern NSString *NSFontSizeBinding;
extern NSString *NSHeaderTitleBinding;
extern NSString *NSHiddenBinding;
extern NSString *NSImageBinding;
extern NSString *NSIncludedKeysBinding;
extern NSString *NSInitialKeyBinding;
extern NSString *NSInitialValueBinding;
extern NSString *NSIsIndeterminateBinding;
extern NSString *NSLabelBinding;
extern NSString *NSLocalizedKeyDictionaryBinding;
extern NSString *NSManagedObjectContextBinding;
extern NSString *NSMaximumRecentsBinding;
extern NSString *NSMaxValueBinding;
extern NSString *NSMaxWidthBinding;
extern NSString *NSMinValueBinding;
extern NSString *NSMinWidthBinding;
extern NSString *NSMixedStateImageBinding;
extern NSString *NSOffStateImageBinding;
extern NSString *NSOnStateImageBinding;
extern NSString *NSPredicateBinding;
extern NSString *NSRecentSearchesBinding;
extern NSString *NSRepresentedFilenameBinding;
extern NSString *NSRowHeightBinding;
extern NSString *NSSelectedIdentifierBinding;
extern NSString *NSSelectedIndexBinding;
extern NSString *NSSelectedLabelBinding;
extern NSString *NSSelectedObjectBinding;
extern NSString *NSSelectedObjectsBinding;
extern NSString *NSSelectedTagBinding;
extern NSString *NSSelectedValueBinding;
extern NSString *NSSelectedValuesBinding;
extern NSString *NSSelectionIndexesBinding;
extern NSString *NSSelectionIndexPathsBinding;
extern NSString *NSSortDescriptorsBinding;
extern NSString *NSTargetBinding;
extern NSString *NSTextColorBinding;
extern NSString *NSTitleBinding;
extern NSString *NSToolTipBinding;
extern NSString *NSTransparentBinding;
extern NSString *NSValueBinding;
extern NSString *NSValuePathBinding;
extern NSString *NSValueURLBinding;
extern NSString *NSVisibleBinding;
extern NSString *NSWarningValueBinding;
extern NSString *NSWidthBinding;

/* ---- AND THE OPTION KEYS. See the header block for which of these this layer reads. ------------------------------- */
extern NSString *NSAllowsEditingMultipleValuesSelectionBindingOption;
extern NSString *NSAllowsNullArgumentBindingOption;
extern NSString *NSAlwaysPresentsApplicationModalAlertsBindingOption;
extern NSString *NSConditionallySetsEditableBindingOption;
extern NSString *NSConditionallySetsEnabledBindingOption;
extern NSString *NSConditionallySetsHiddenBindingOption;
extern NSString *NSContinuouslyUpdatesValueBindingOption;
extern NSString *NSCreatesSortDescriptorBindingOption;
extern NSString *NSDeletesObjectsOnRemoveBindingsOption;
extern NSString *NSDisplayNameBindingOption;
extern NSString *NSDisplayPatternBindingOption;
extern NSString *NSContentPlacementTagBindingOption;
extern NSString *NSHandlesContentAsCompoundValueBindingOption;
extern NSString *NSInsertsNullPlaceholderBindingOption;
extern NSString *NSInvokesSeparatelyWithArrayObjectsBindingOption;
extern NSString *NSMultipleValuesPlaceholderBindingOption;
extern NSString *NSNoSelectionPlaceholderBindingOption;
extern NSString *NSNotApplicablePlaceholderBindingOption;
extern NSString *NSNullPlaceholderBindingOption;
extern NSString *NSRaisesForNotApplicableKeysBindingOption;
extern NSString *NSPredicateFormatBindingOption;
extern NSString *NSSelectorNameBindingOption;
extern NSString *NSSelectsAllWhenSettingContentBindingOption;
extern NSString *NSValidatesImmediatelyBindingOption;
extern NSString *NSValueTransformerNameBindingOption;
extern NSString *NSValueTransformerBindingOption;

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSKEYVALUEBINDING_H */
