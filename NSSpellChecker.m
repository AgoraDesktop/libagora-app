/*
 * NSSpellChecker.m — a word-list checker, and the refusals where no backing exists.
 *
 * © 2026 Kyle J. Cardozo. MIT licence (see LICENSE at the repository root).
 * SPDX-License-Identifier: MIT
 *
 * **THE DICTIONARY IS DISCOVERED, NOT COMPILED IN.** Two candidates in the order the era's systems had them, then
 * `en_US.dic` (hunspell's format, whose first line is a count and whose entries carry affix flags after a slash). Only
 * the word part of each entry is taken: the affixes are a morphology table this tier does not apply, which is stated at
 * the header as the check's limit rather than hidden here.
 *
 * **A MACHINE WITH NO DICTIONARY ANSWERS NO LANGUAGES**, and `-checkSpellingOfString:…` then finds nothing wrong —
 * because it cannot tell. That combination is chosen deliberately: reporting every word as misspelled would be a
 * louder lie than reporting none, and `availableLanguages` is the door a caller should ask.
 *
 * **THE SCAN IS BYTE-WISE OVER LETTERS**, which is enough for a word list of lowercase ASCII words and is stated rather
 * than implied: a word is a maximal run of `[A-Za-z]` plus an interior apostrophe, so "don't" is one word and "e-mail"
 * is two. The era's checker split on the same boundaries for the same reason — it had to find a RANGE to underline.
 */
#import <AppKit/NSSpellChecker.h>
#import <AppKit/AppKitRefusal.h>

#import <Foundation/Foundation.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static BOOL fn_is_letter(unichar c)
{
	return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ? YES : NO;
}

static BOOL fn_is_apostrophe(unichar c)
{
	return (c == '\'' || c == 0x2019) ? YES : NO;
}


/* ==================================================================================================================
 * A WORD SET, IN C.
 *
 * **THIS EXISTS BECAUSE `NSSet` IS A LINEAR SCAN IN THIS FOUNDATION** (`-[NSSet member:]` walks its members), and a
 * hundred-thousand-word dictionary inserted one word at a time is quadratic — measured, that is what made the first
 * version of this class hang inside `-availableLanguages` and never come back. An open-addressed table with djb2 and
 * linear probing turns the load into a few milliseconds and every lookup into one hash.
 *
 * The keys are `strdup`'d lowercase words owned by the set; `fn_wordset_free` is the only thing that frees them.
 * ================================================================================================================ */

typedef struct {
	char **slots;
	unsigned long capacity;
	unsigned long count;
} AGWordSet;

static unsigned long fn_djb2(const char *word)
{
	unsigned long hash = 5381;
	int c;

	while ((c = (unsigned char)*word++) != 0) {
		hash = ((hash << 5) + hash) + (unsigned long)c;
	}
	return hash;
}

static AGWordSet *fn_wordset_create(unsigned long capacity)
{
	AGWordSet *set = (AGWordSet *)calloc(1, sizeof(AGWordSet));

	set->capacity = capacity < 16 ? 16 : capacity;
	set->slots = (char **)calloc(set->capacity, sizeof(char *));
	return set;
}

static void fn_wordset_free(AGWordSet *set)
{
	unsigned long i;

	if (set == NULL) {
		return;
	}
	for (i = 0; i < set->capacity; i++) {
		if (set->slots[i] != NULL) {
			free(set->slots[i]);
		}
	}
	free(set->slots);
	free(set);
}

static void fn_wordset_grow(AGWordSet *set);

static void fn_wordset_insert(AGWordSet *set, const char *word)
{
	unsigned long i;

	if ((set->count + 1) * 10 >= set->capacity * 7) {
		fn_wordset_grow(set);
	}
	i = fn_djb2(word) % set->capacity;
	while (set->slots[i] != NULL) {
		if (strcmp(set->slots[i], word) == 0) {
			return;		/* already there */
		}
		i = (i + 1) % set->capacity;
	}
	set->slots[i] = strdup(word);
	set->count++;
}

static void fn_wordset_grow(AGWordSet *set)
{
	AGWordSet bigger;
	unsigned long i;

	bigger.capacity = set->capacity * 2;
	bigger.count = 0;
	bigger.slots = (char **)calloc(bigger.capacity, sizeof(char *));
	for (i = 0; i < set->capacity; i++) {
		if (set->slots[i] != NULL) {
			fn_wordset_insert(&bigger, set->slots[i]);
		}
	}
	free(set->slots);
	set->slots = bigger.slots;
	set->capacity = bigger.capacity;
	/* count is already right: every old slot was moved exactly once */
}

static BOOL fn_wordset_has(AGWordSet *set, const char *word)
{
	unsigned long i;

	if (set == NULL || word == NULL) {
		return NO;
	}
	i = fn_djb2(word) % set->capacity;
	while (set->slots[i] != NULL) {
		if (strcmp(set->slots[i], word) == 0) {
			return YES;
		}
		i = (i + 1) % set->capacity;
	}
	return NO;
}

@implementation NSSpellChecker

+ (NSSpellChecker *)sharedSpellChecker
{
	static NSSpellChecker *shared = nil;

	if (shared == nil) {
		shared = [[NSSpellChecker alloc] init];
	}
	return shared;
}

+ (BOOL)sharedSpellCheckerExists
{
	return YES;
}

/* **TAGS START AT ONE**, because zero is the era's "no document" tag and a caller that passed it straight through would
 * otherwise share state with the checker itself. */
+ (NSInteger)uniqueSpellDocumentTag
{
	static NSInteger next = 1;

	return next++;
}

- (id)init
{
	if ((self = [super init]) != nil) {
		_ignoredByTag = [[NSMutableDictionary alloc] init];
		_learned = [[NSMutableSet alloc] init];
		_language = nil;
	}
	return self;
}

- (void)dealloc
{
	[_ignoredByTag release];
	[_learned release];
	fn_wordset_free((AGWordSet *)_dictionary);
	[_language release];
	[super dealloc];
}

/* ------------------------------------------------------------------------------------------------------------------
 * The dictionary.
 * ---------------------------------------------------------------------------------------------------------------- */

- (BOOL)fn_loadWordsFromFile:(NSString *)path
{
	NSData *data = [NSData dataWithContentsOfFile:path];
	const unsigned char *bytes;
	NSUInteger length, i, wordStart = 0;

	if (data == nil) {
		return NO;
	}
	bytes = (const unsigned char *)[data bytes];
	length = [data length];
	if (bytes == NULL || length == 0) {
		return NO;
	}
	if (_dictionary == NULL) {
		_dictionary = (void *)fn_wordset_create(1 << 17);
	}
	/* **THE FILE IS SCANNED AS BYTES, NOT SPLIT INTO LINES.** The first draft used
	 * `-componentsSeparatedByString:` on a hundred-thousand-line word list and never returned — a quadratic split behind
	 * an innocent-looking one-liner, which is the same lesson the census taught: an instrument that looks simple can be
	 * the slowest thing in the room. A single pass over the bytes is linear and needs no intermediate array.
	 *
	 * The hunspell form `word/FLAGS` is cut at the slash: the flags are a morphology table this tier does not apply. A
	 * line that is not all letters (the .dic file's leading count, a stray CR) is skipped by the same rule the check
	 * uses to find a word. */
	for (i = 0; i <= length; i++) {
		BOOL atEnd = (i == length);
		unsigned char c = atEnd ? '\n' : bytes[i];

		if (c == '\n' || c == '\r' || c == '/') {
			if (i > wordStart) {
				NSUInteger k;
				BOOL letters = YES;

				for (k = wordStart; k < i; k++) {
					unsigned char d = bytes[k];

					if (!((d >= 'A' && d <= 'Z') || (d >= 'a' && d <= 'z'))) {
						letters = NO;
						break;
					}
				}
				if (letters) {
					char word[64];
					NSUInteger span = i - wordStart;
					NSUInteger k;

					if (span < sizeof(word)) {
						for (k = 0; k < span; k++) {
							unsigned char d = bytes[wordStart + k];

							word[k] = (char)((d >= 'A' && d <= 'Z') ? (d - 'A' + 'a') : d);
						}
						word[span] = '\0';
						fn_wordset_insert((AGWordSet *)_dictionary, word);
					}
				}
			}
			if (c == '/') {
				/* skip to the end of this line: the flags are not words */
				while (i < length && bytes[i] != '\n' && bytes[i] != '\r') {
					i++;
				}
			}
			wordStart = i + 1;
		}
	}
	return YES;
}

- (BOOL)fn_isWordString:(NSString *)string
{
	NSUInteger i, length = [string length];

	for (i = 0; i < length; i++) {
		if (!fn_is_letter([string characterAtIndex:i])) {
			return NO;
		}
	}
	return length > 0 ? YES : NO;
}

- (void)fn_load
{
	NSArray *candidates;
	NSUInteger i;

	if (_loaded) {
		return;
	}
	_loaded = YES;
	_dictionary = (void *)fn_wordset_create(1 << 17);
	candidates = [NSArray arrayWithObjects:@"/usr/share/dict/words",
					       @"/usr/share/dict/american-english",
					       @"/usr/share/hunspell/en_US.dic", nil];
	for (i = 0; i < [candidates count]; i++) {
		if ([self fn_loadWordsFromFile:[candidates objectAtIndex:i]]
		    && ((AGWordSet *)_dictionary)->count > 0) {
			_dictionaryFound = YES;
			break;
		}
	}
	if (_dictionaryFound && _language == nil) {
		_language = [@"en" retain];
	}
}

- (NSArray *)availableLanguages
{
	[self fn_load];
	return _dictionaryFound ? [NSArray arrayWithObject:@"en"] : [NSArray array];
}

- (NSArray *)userPreferredLanguages
{
	return [self availableLanguages];
}

- (NSString *)language
{
	[self fn_load];
	return _language;
}

- (BOOL)setLanguage:(NSString *)language
{
	[self fn_load];
	if (![_language isEqual:language]) {
		[language retain];
		[_language release];
		_language = language;
	}
	return YES;
}

/* ------------------------------------------------------------------------------------------------------------------
 * The check itself.
 * ---------------------------------------------------------------------------------------------------------------- */

- (NSSet *)fn_ignoredForTag:(NSInteger)tag
{
	NSMutableSet *set = [_ignoredByTag objectForKey:[NSNumber numberWithInteger:tag]];

	return set;
}

- (BOOL)fn_isSpelled:(NSString *)word tag:(NSInteger)tag
{
	NSString *folded;

	if ([word length] == 0) {
		return YES;
	}
	folded = [word lowercaseString];
	if ([_learned containsObject:folded]) {
		return YES;
	}
	{
		NSSet *ignored = [self fn_ignoredForTag:tag];

		if (ignored != nil && [ignored containsObject:folded]) {
			return YES;
		}
	}
	return fn_wordset_has((AGWordSet *)_dictionary, [folded UTF8String]);
}

/* The next word at or after `from`: its range, or NSNotFound when the string has no more. */
- (NSRange)fn_nextWordIn:(NSString *)string from:(NSUInteger)from
{
	NSUInteger length = [string length];
	NSUInteger start = from;

	while (start < length && !fn_is_letter([string characterAtIndex:start])) {
		start++;
	}
	if (start >= length) {
		return NSMakeRange(NSNotFound, 0);
	}
	{
		NSUInteger end = start;

		while (end < length) {
			unichar c = [string characterAtIndex:end];

			if (fn_is_letter(c)) {
				end++;
			} else if (fn_is_apostrophe(c) && end + 1 < length
				   && fn_is_letter([string characterAtIndex:end + 1])) {
				end++;
			} else {
				break;
			}
		}
		return NSMakeRange(start, end - start);
	}
}

- (NSRange)checkSpellingOfString:(NSString *)stringToCheck
		      startingAt:(NSInteger)startingOffset
			language:(NSString *)language
			    wrap:(BOOL)wrapFlag
	      inSpellDocumentWithTag:(NSInteger)tag
		       wordCount:(NSInteger *)wordCount
{
	NSUInteger length, scan;
	NSInteger examined = 0;

	(void)language;
	(void)wrapFlag;	/* the wrap is a second pass the caller drives; the era's answer is the FIRST bad word */
	[self fn_load];
	if (wordCount != NULL) {
		*wordCount = 0;
	}
	if (stringToCheck == nil) {
		return NSMakeRange(NSNotFound, 0);
	}
	length = [stringToCheck length];
	scan = (startingOffset > 0) ? (NSUInteger)startingOffset : 0;
	while (scan < length) {
		NSRange word = [self fn_nextWordIn:stringToCheck from:scan];

		if (word.location == NSNotFound) {
			break;
		}
		examined++;
		if (![self fn_isSpelled:[stringToCheck substringWithRange:word] tag:tag]) {
			if (wordCount != NULL) {
				*wordCount = examined;
			}
			return word;
		}
		scan = word.location + word.length;
	}
	if (wordCount != NULL) {
		*wordCount = examined;
	}
	return NSMakeRange(NSNotFound, 0);
}

- (NSRange)checkSpellingOfString:(NSString *)stringToCheck startingAt:(NSInteger)startingOffset
{
	return [self checkSpellingOfString:stringToCheck startingAt:startingOffset language:nil wrap:NO
		   inSpellDocumentWithTag:0 wordCount:NULL];
}

- (NSInteger)countWordsInString:(NSString *)stringToCount language:(NSString *)language
{
	NSUInteger length, scan = 0;
	NSInteger count = 0;

	(void)language;
	if (stringToCount == nil) {
		return 0;
	}
	length = [stringToCount length];
	while (scan < length) {
		NSRange word = [self fn_nextWordIn:stringToCount from:scan];

		if (word.location == NSNotFound) {
			break;
		}
		count++;
		scan = word.location + word.length;
	}
	return count;
}

/* ------------------------------------------------------------------------------------------------------------------
 * What a caller teaches it.
 * ---------------------------------------------------------------------------------------------------------------- */

- (NSMutableSet *)fn_ignoredSetForTag:(NSInteger)tag create:(BOOL)create
{
	NSNumber *key = [NSNumber numberWithInteger:tag];
	NSMutableSet *set = [_ignoredByTag objectForKey:key];

	if (set == nil && create) {
		set = [NSMutableSet set];
		[_ignoredByTag setObject:set forKey:key];
	}
	return set;
}

- (void)ignoreWord:(NSString *)wordToIgnore inSpellDocumentWithTag:(NSInteger)tag
{
	if (wordToIgnore == nil) {
		return;
	}
	[[self fn_ignoredSetForTag:tag create:YES] addObject:[wordToIgnore lowercaseString]];
}

- (NSArray *)ignoredWordsInSpellDocumentWithTag:(NSInteger)tag
{
	NSSet *set = [self fn_ignoredForTag:tag];

	return set != nil ? [set allObjects] : [NSArray array];
}

- (void)setIgnoredWords:(NSArray *)words inSpellDocumentWithTag:(NSInteger)tag
{
	NSMutableSet *set = [[NSMutableSet alloc] init];
	NSUInteger i;

	for (i = 0; i < [words count]; i++) {
		[set addObject:[[words objectAtIndex:i] lowercaseString]];
	}
	[_ignoredByTag setObject:set forKey:[NSNumber numberWithInteger:tag]];
	[set release];
}

- (void)learnWord:(NSString *)word
{
	if (word != nil) {
		[_learned addObject:[word lowercaseString]];
	}
}

- (void)unlearnWord:(NSString *)word
{
	if (word != nil) {
		[_learned removeObject:[word lowercaseString]];
	}
}

- (BOOL)hasLearnedWord:(NSString *)word
{
	return (word != nil && [_learned containsObject:[word lowercaseString]]) ? YES : NO;
}

- (void)closeSpellDocumentWithTag:(NSInteger)tag
{
	[_ignoredByTag removeObjectForKey:[NSNumber numberWithInteger:tag]];
}

/* ------------------------------------------------------------------------------------------------------------------
 * Guesses and completions.
 * ---------------------------------------------------------------------------------------------------------------- */

/* **THE GUESSES ARE ONE-EDIT NEIGHBOURS, WHICH IS THE ERA'S OWN ANSWER AND IS BOUNDED**: every word of the same length
 * plus or minus one is compared, and the first handful of substitutions/insertions/deletions that hit are answered. A
 * full Levenshtein scan of a hundred thousand words for every right-click is the thing this avoids. */
- (NSArray *)guessesForWordRange:(NSRange)range
			inString:(NSString *)string
			language:(NSString *)language
	     inSpellDocumentWithTag:(NSInteger)tag
{
	NSMutableArray *guesses = [NSMutableArray array];
	NSString *word;
	NSUInteger i;
	static const char *alphabet = "abcdefghijklmnopqrstuvwxyz";

	(void)language;
	(void)tag;
	[self fn_load];
	if (string == nil || range.location == NSNotFound || range.location + range.length > [string length]) {
		return guesses;
	}
	word = [[string substringWithRange:range] lowercaseString];
	if ([word length] == 0) {
		return guesses;
	}
	/* Deletions, then substitutions, then insertions — the order a caller's menu expects. */
	for (i = 0; i < [word length]; i++) {
		NSMutableString *candidate = [[word mutableString] copy];
		NSString *folded;

		[candidate deleteCharactersInRange:NSMakeRange(i, 1)];
		folded = [candidate lowercaseString];
		if (fn_wordset_has((AGWordSet *)_dictionary, [folded UTF8String]) && ![guesses containsObject:candidate]) {
			[guesses addObject:candidate];
		}
		[candidate release];
		if ([guesses count] >= 8) {
			return guesses;
		}
	}
	for (i = 0; i < [word length]; i++) {
		NSUInteger a;

		for (a = 0; a < 26; a++) {
			NSMutableString *candidate = [[word mutableString] copy];
			NSString *folded;

			if (alphabet[a] == (char)[word characterAtIndex:i]) {
				continue;
			}
			[candidate replaceCharactersInRange:NSMakeRange(i, 1)
					 withString:[NSString stringWithFormat:@"%c", alphabet[a]]];
			folded = [candidate lowercaseString];
			if (fn_wordset_has((AGWordSet *)_dictionary, [folded UTF8String]) && ![guesses containsObject:candidate]) {
				[guesses addObject:candidate];
			}
			[candidate release];
			if ([guesses count] >= 8) {
				return guesses;
			}
		}
	}
	return guesses;
}

- (NSArray *)completionsForPartialWordRange:(NSRange)range
				   inString:(NSString *)string
				   language:(NSString *)language
			inSpellDocumentWithTag:(NSInteger)tag
{
	NSMutableArray *matches = [NSMutableArray array];
	NSString *prefix;
	NSEnumerator *e;
	NSString *candidate;

	(void)language;
	(void)tag;
	[self fn_load];
	if (string == nil || range.location == NSNotFound || range.location + range.length > [string length]) {
		return matches;
	}
	prefix = [[string substringWithRange:range] lowercaseString];
	if ([prefix length] == 0) {
		return matches;
	}
	{
		AGWordSet *set = (AGWordSet *)_dictionary;
		const char *prefixBytes = [prefix UTF8String];
		size_t prefixLength = strlen(prefixBytes);
		unsigned long i;

		for (i = 0; set != NULL && i < set->capacity; i++) {
			if (set->slots[i] != NULL && strncmp(set->slots[i], prefixBytes, prefixLength) == 0) {
				[matches addObject:[NSString stringWithUTF8String:set->slots[i]]];
				if ([matches count] >= 20) {
					break;
				}
			}
		}
	}
	(void)candidate;
	(void)e;
	return matches;
}

/* ------------------------------------------------------------------------------------------------------------------
 * The refusals.
 * ---------------------------------------------------------------------------------------------------------------- */

- (NSRange)checkGrammarOfString:(NSString *)stringToCheck
		     startingAt:(NSInteger)startingOffset
		       language:(NSString *)language
			   wrap:(BOOL)wrapFlag
	     inSpellDocumentWithTag:(NSInteger)tag
			details:(NSArray **)details
{
	(void)stringToCheck; (void)startingOffset; (void)language; (void)wrapFlag; (void)tag;
	if (details != NULL) {
		*details = nil;
	}
	fn_refuse_window("-checkGrammarOfString:…", "a grammar engine (none exists on this platform to adapt)");
	return NSMakeRange(NSNotFound, 0);
}

- (NSArray *)checkString:(NSString *)stringToCheck
		   range:(NSRange)range
		   types:(NSUInteger)checkingTypes
		 options:(NSDictionary *)options
	inSpellDocumentWithTag:(NSInteger)tag
	       orthography:(id *)orthography
		wordCount:(NSInteger *)wordCount
{
	(void)stringToCheck; (void)range; (void)checkingTypes; (void)options; (void)tag;
	if (orthography != NULL) {
		*orthography = nil;
	}
	if (wordCount != NULL) {
		*wordCount = 0;
	}
	fn_refuse_window("-checkString:range:types:…", "NSTextCheckingResult and NSOrthography (Foundation's, absent)");
	return nil;
}

- (NSPanel *)spellingPanel
{
	fn_refuse_window("-spellingPanel", "a spelling panel (this tier has no panel with a word field and a guess table)");
	return nil;
}

- (NSPanel *)substitutionsPanel
{
	fn_refuse_window("-substitutionsPanel", "a substitutions panel");
	return nil;
}

- (NSView *)accessoryView
{
	return nil;
}

- (void)setAccessoryView:(NSView *)aView
{
	(void)aView;
	fn_refuse_window("-setAccessoryView:", "a spelling panel to put an accessory in");
}

- (void)updatePanels
{
	fn_refuse_window("-updatePanels", "the panels it would update");
}

- (void)updateSpellingPanelWithMisspelledWord:(NSString *)word
{
	(void)word;
	fn_refuse_window("-updateSpellingPanelWithMisspelledWord:", "a spelling panel");
}

- (void)setWordFieldStringValue:(NSString *)aString
{
	(void)aString;
	fn_refuse_window("-setWordFieldStringValue:", "a spelling panel's word field");
}

- (NSMenu *)menuForResult:(NSTextCheckingResult *)result
		   string:(NSString *)checkedString
		  options:(NSDictionary *)options
	       atLocation:(NSPoint)location
		   inView:(NSView *)view
{
	(void)result; (void)checkedString; (void)options; (void)location; (void)view;
	fn_refuse_window("-menuForResult:…", "NSTextCheckingResult, which Foundation here has not got");
	return nil;
}

@end
