/*
 * NSSpellChecker.h — the spell checker, backed by the system's own word list.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THIS ONE IS REAL, AND IT IS REAL BECAUSE THE BACKING EXISTS.** The plan's disposition table allows "adapted" when a
 * platform equivalent stands in for Apple's mechanism, and a spell checker is exactly that: Apple asks its own service,
 * this tier asks the machine's dictionary — `/usr/share/dict/words` or `/usr/share/dict/american-english` — and the
 * forty `NSTextView` doors that reach a checker stop being absence.
 *
 * **WHAT IS A WORD HERE AND WHAT IS NOT, STATED AT THE DOOR.** The check is a LOOKUP: a run of letters is a word, and it
 * is spelled if the dictionary has it, case-insensitively. There is no morphology, so a legitimate plural that the list
 * lacks is reported as wrong — which is what the era's simplest checkers did too, and is the honest limit of a word
 * list. Words a caller ignores or learns are honoured per SPELL DOCUMENT TAG, which is Apple's grouping.
 *
 * THE REFUSALS ARE THE PANELS AND THE GRAMMAR ENGINE: `spellingPanel`, `substitutionsPanel`, the accessory views and
 * `updatePanels` need a panel this tier has not built, `checkGrammarOfString:` needs a grammar engine that does not
 * exist anywhere on this platform, and `checkString:…` needs `NSTextCheckingResult`/`NSOrthography`, which are
 * Foundation's and absent. Each names what it wants rather than returning an empty success.
 */

#ifndef APPKIT_NSSPELLCHECKER_H
#define APPKIT_NSSPELLCHECKER_H

#import <Foundation/NSObject.h>
#import <Foundation/NSGeometry.h>
#import <Foundation/NSString.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSSet.h>

NS_ASSUME_NONNULL_BEGIN

@class NSString;
@class NSArray;
@class NSDictionary;
@class NSPanel;
@class NSMenu;
@class NSView;
@class NSViewController;
@class NSTextCheckingResult;

/* **THE FOUR TYPES THE CHECKING REQUEST TAKES, AND THE ONE OPTION WORD.** `NSTextCheckingType` is Foundation's (the
 * results this checker produces are `NSTextCheckingResult`s), the types array holds `NSNumber`s of it, and the options
 * dictionary is Apple's `NSSpellChecking…` bag of which this tier honours none — a request's options are advice about a
 * checker with modes, and this one has a dictionary and a language. */
@class NSTextCheckingResult;

@interface NSSpellChecker : NSObject
{
	/* TAG -> SET OF WORDS, so it is a DICTIONARY. The first draft made this an `NSSet` and looked tags up with
	 * `-member:`, which asks whether some element is EQUAL TO the key — so every lookup missed and an ignored word
	 * stayed reported. A set of sets is not a map. */
	NSMutableDictionary *_ignoredByTag;	/* NSNumber tag -> NSMutableSet of lowercase words */
	NSMutableSet *_learned;			/* words the user taught it, this process only */
	/* **THE DICTIONARY IS NOT AN `NSSet`, AND THAT IS A PERFORMANCE FACT RATHER THAN A STYLE CHOICE.** This tier's
	 * `-[NSSet member:]` is a LINEAR SCAN over its members, so inserting a hundred thousand words one at a time is
	 * quadratic and never returns — measured, that is what made the first version of this class hang inside
	 * `-availableLanguages`. The dictionary is an open-addressed C hash set here; the per-document ignore list and the
	 * learned words stay `NSSet`s, because a user adds tens of those and not a hundred thousand. */
	void *_dictionary;		/* struct AGWordSet, the loaded word list */
	NSString *_language;
	BOOL _loaded;
	BOOL _dictionaryFound;
	/* **AND THE THREE THE SWEEP ADDS.** `_identifiesLanguages` is Apple's flag (YES by default): when it is on, a check
	 * may re-identify the language, and with ONE dictionary here the identification can only ever answer "en" or leave
	 * the language alone — which the door's own note states rather than implying a detector. `_replacements` is the
	 * user's substitution table, which is the table the text view's automatic-substitution flags have been waiting for;
	 * it starts EMPTY, because a replacement nobody made is not a default. `_substitutionsAccessory` is a view
	 * CONTROLLER for a substitutions panel this tier has not got, which is why the pair refuses by name. */
	BOOL _identifiesLanguages;
	NSMutableDictionary *_replacements;
	id _substitutionsAccessory;	/* NOT RETAINED, and never set: the panel below refuses */
}

/* THE SINGLETON, and the era's two other class doors. `sharedSpellCheckerExists` is YES because the checker always
 * exists — whether a DICTIONARY was found is a different question, and `availableLanguages` answers it. */
+ (NSSpellChecker *)sharedSpellChecker;
+ (BOOL)sharedSpellCheckerExists;
+ (NSInteger)uniqueSpellDocumentTag;

/* THE CHECK. `startingOffset` is an index, `wrap` says whether to go round once, and the answer is the first misspelled
 * word's range or `(NSNotFound, 0)`. `wordCount` is how many words were EXAMINED, which is what the era's callers used
 * to size a progress bar. */
- (NSRange)checkSpellingOfString:(NSString *)stringToCheck
		      startingAt:(NSInteger)startingOffset
			language:(nullable NSString *)language
			    wrap:(BOOL)wrapFlag
	      inSpellDocumentWithTag:(NSInteger)tag
		       wordCount:(nullable NSInteger *)wordCount;
/* The 10.0 form, which skipped the language and the tag. */
- (NSRange)checkSpellingOfString:(NSString *)stringToCheck startingAt:(NSInteger)startingOffset;

/* Words, counted the same way the check finds them. */
- (NSInteger)countWordsInString:(nullable NSString *)stringToCount language:(nullable NSString *)language;

/* WHAT A CALLER TEACHES IT, per document tag and for the process. */
- (void)ignoreWord:(NSString *)wordToIgnore inSpellDocumentWithTag:(NSInteger)tag;
- (NSArray *)ignoredWordsInSpellDocumentWithTag:(NSInteger)tag;
- (void)setIgnoredWords:(NSArray *)words inSpellDocumentWithTag:(NSInteger)tag;
- (void)learnWord:(NSString *)word;
- (void)unlearnWord:(NSString *)word;
- (BOOL)hasLearnedWord:(NSString *)word;
- (void)closeSpellDocumentWithTag:(NSInteger)tag;

/* **AND THE TEN DOORS THE SWEEP ADDS, IN FOUR KINDS.** A FLAG (`-automaticallyIdentifiesLanguages`, whose reader is the
 * language a check may re-identify), TWO TABLES (`-userReplacementsDictionary` and `-userQuotesArrayForLanguage:`, which
 * are the substitution machinery's missing halves — the text view's automatic-substitution flags have been stored values
 * until now), a WORD the user forgets (`-forgetWord:`, whose reader is `-hasLearnedWord:`), a GUESSER
 * (`-guessesForWord:`, the single-word form of the range door that already exists), and the ASYNCHRONOUS CHECK
 * (`-requestCheckingOfString:…completionHandler:`; this tier has no background queue, so the handler runs BEFORE the
 * door returns — the same results, in the caller's stack, which the note there states). The three that need a PANEL or an
 * ENGINE — the substitutions accessory and the grammar string — refuse by name, because their subject does not exist. */
- (BOOL)automaticallyIdentifiesLanguages;
- (void)setAutomaticallyIdentifiesLanguages:(BOOL)flag;
- (NSDictionary *)userReplacementsDictionary;
- (nullable NSArray *)userQuotesArrayForLanguage:(nullable NSString *)language;
- (void)forgetWord:(NSString *)word;
- (NSArray *)guessesForWord:(nullable NSString *)word;
- (NSInteger)requestCheckingOfString:(NSString *)stringToCheck
			       range:(NSRange)range
			       types:(NSUInteger)checkingTypes
			     options:(nullable NSDictionary *)options
	      inSpellDocumentWithTag:(NSInteger)tag
		   completionHandler:(nullable void (^)(NSInteger sequenceNumber, NSArray *results))completionHandler;
- (nullable id)substitutionsPanelAccessoryViewController;
- (void)setSubstitutionsPanelAccessoryViewController:(nullable id)controller;
- (void)updateSpellingPanelWithGrammarString:(NSString *)string detail:(nullable NSDictionary *)detail;

/* THE LANGUAGES THIS MACHINE CAN CHECK, discovered from the dictionaries present rather than declared. An empty answer
 * is the honest one on a machine with no word list. */
- (NSArray *)availableLanguages;
- (NSArray *)userPreferredLanguages;
- (nullable NSString *)language;
- (BOOL)setLanguage:(nullable NSString *)language;

/* GUESSES AND COMPLETIONS. Guesses are the era's "did you mean" list; completions are the prefix list a field shows. */
- (NSArray *)guessesForWordRange:(NSRange)range
			inString:(NSString *)string
			language:(nullable NSString *)language
	     inSpellDocumentWithTag:(NSInteger)tag;
- (NSArray *)completionsForPartialWordRange:(NSRange)range
				   inString:(NSString *)string
				   language:(nullable NSString *)language
			inSpellDocumentWithTag:(NSInteger)tag;

/* THE REFUSALS. */
- (NSRange)checkGrammarOfString:(NSString *)stringToCheck
		     startingAt:(NSInteger)startingOffset
		       language:(nullable NSString *)language
			   wrap:(BOOL)wrapFlag
	     inSpellDocumentWithTag:(NSInteger)tag
			details:(NSArray * _Nullable * _Nullable)details;
- (nullable NSArray *)checkString:(NSString *)stringToCheck
			    range:(NSRange)range
			    types:(NSUInteger)checkingTypes
			  options:(nullable NSDictionary *)options
		inSpellDocumentWithTag:(NSInteger)tag
		       orthography:(id _Nullable * _Nullable)orthography
			wordCount:(nullable NSInteger *)wordCount;
- (nullable NSPanel *)spellingPanel;
- (nullable NSPanel *)substitutionsPanel;
- (nullable NSView *)accessoryView;
- (void)setAccessoryView:(nullable NSView *)aView;
- (void)updatePanels;
- (void)updateSpellingPanelWithMisspelledWord:(NSString *)word;
- (void)setWordFieldStringValue:(NSString *)aString;
- (nullable NSMenu *)menuForResult:(nullable NSTextCheckingResult *)result
			    string:(NSString *)checkedString
			   options:(nullable NSDictionary *)options
			atLocation:(NSPoint)location
			    inView:(nullable NSView *)view;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSSPELLCHECKER_H */
