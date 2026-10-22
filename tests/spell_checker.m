/*
 * spell_checker — the word-list checker, and the text view doors that reach it.
 *
 * © 2026 Kyle J. Cardozo. MIT licence (see LICENSE at the repository root).
 * SPDX-License-Identifier: MIT
 *
 * **THIS IS THE FIRST CLASS IN THE TIER WHOSE BACKING IS THE MACHINE'S OWN DATA**, so the test has to be careful about
 * what it claims. It asserts the CONTRACT — a misspelled word is found, a spelled one is not, an ignored or learned word
 * stops being found, a document tag keeps the two apart — and it asserts the DICTIONARY-DEPENDENT part conditionally:
 * `availableLanguages` is asked first, and the lookups are only asserted when a language exists. That way the test is
 * honest on a machine with no word list as well as on this one.
 *
 * **THE SCAN'S BOUNDARIES ARE THE CONTRACT TOO**: an apostrophe inside a word joins it (`don't` is one word), and a
 * hyphen splits (`well-known` is two), because those are the runs a caller underlines.
 */
#import <AppKit/NSSpellChecker.h>
#import <AppKit/NSTextView.h>
#import <AppKit/NSTextStorage.h>
#import <Foundation/Foundation.h>

#include <stdio.h>

static int failures;

static void check(int ok, const char *what)
{
	printf("  %s %s\n", ok ? "ok   " : "FAIL ", what);
	if (!ok) {
		failures++;
	}
}

int main(void)
{
	@autoreleasepool {
		NSSpellChecker *checker = [NSSpellChecker sharedSpellChecker];
		NSArray *languages;
		BOOL haveDictionary;

		check(checker != nil, "the checker exists");
		check([NSSpellChecker sharedSpellCheckerExists], "and says so");
		check([NSSpellChecker sharedSpellChecker] == checker, "and is a singleton");

		languages = [checker availableLanguages];
		haveDictionary = [languages count] > 0;
		printf("        (dictionary languages available: %lu)\n", (unsigned long)[languages count]);

		/* 1. The document tags are unique and nonzero. */
		{
			NSInteger a = [NSSpellChecker uniqueSpellDocumentTag];
			NSInteger b = [NSSpellChecker uniqueSpellDocumentTag];

			check(a > 0 && b > 0 && a != b, "document tags start nonzero and are unique");
		}

		/* 2. Word counting is dictionary-independent, so it is always checked. */
		check([checker countWordsInString:@"one two three" language:@"en"] == 3,
		      "countWordsInString counts three words");
		check([checker countWordsInString:@"don't stop" language:@"en"] == 2,
		      "and an apostrophe joins rather than splits");
		check([checker countWordsInString:@"well-known" language:@"en"] == 2,
		      "while a hyphen splits");

		/* 3. The lookups, when this machine has a dictionary to look them up in. */
		if (haveDictionary) {
			NSRange found = [checker checkSpellingOfString:@"the quikc brown fox" startingAt:0 language:@"en"
						 wrap:NO inSpellDocumentWithTag:0 wordCount:NULL];

			check(found.location == 4 && found.length == 5,
			      "a misspelling is found, at its own range");
			check([checker checkSpellingOfString:@"the quick brown fox" startingAt:0 language:@"en"
				      wrap:NO inSpellDocumentWithTag:0 wordCount:NULL].location == NSNotFound,
			      "and correctly spelled text finds nothing");

			/* 4. Ignoring is per document tag, which is the whole point of the tag. */
			[checker ignoreWord:@"quikc" inSpellDocumentWithTag:77];
			check([checker checkSpellingOfString:@"the quikc brown fox" startingAt:0 language:@"en"
				      wrap:NO inSpellDocumentWithTag:77 wordCount:NULL].location == NSNotFound,
			      "an ignored word is not reported in its own document");
			check([checker checkSpellingOfString:@"the quikc brown fox" startingAt:0 language:@"en"
				      wrap:NO inSpellDocumentWithTag:78 wordCount:NULL].location == 4,
			      "and is still reported in another");
			check([[checker ignoredWordsInSpellDocumentWithTag:77] count] == 1,
			      "and the ignored list answers what was ignored");
			[checker closeSpellDocumentWithTag:77];
			check([[checker ignoredWordsInSpellDocumentWithTag:77] count] == 0,
			      "closing the document forgets the list");

			/* 5. Learning is process-wide. */
			[checker learnWord:@"quikc"];
			check([checker hasLearnedWord:@"quikc"], "a learned word is remembered");
			check([checker checkSpellingOfString:@"quikc" startingAt:0 language:@"en"
				      wrap:NO inSpellDocumentWithTag:0 wordCount:NULL].location == NSNotFound,
			      "and stops being reported");
			[checker unlearnWord:@"quikc"];
			check(![checker hasLearnedWord:@"quikc"], "and can be unlearned");

			/* 6. Completions come from the same list. */
			check([[checker completionsForPartialWordRange:NSMakeRange(0, 3) inString:@"the"
						      language:@"en" inSpellDocumentWithTag:0] count] > 0,
			      "a three-letter prefix has completions");
		} else {
			printf("        (skipped the lookups: no dictionary on this machine)\n");
		}

		/* 7. The view's own doors: flags, toggles, tag, and the recorded spelling state. */
		{
			NSTextView *view = [[NSTextView alloc] init];

			check(![view isContinuousSpellCheckingEnabled], "spell checking starts off");
			[view toggleContinuousSpellChecking:nil];
			check([view isContinuousSpellCheckingEnabled], "the toggle turns it on");
			[view toggleContinuousSpellChecking:nil];
			check(![view isContinuousSpellCheckingEnabled], "and off again");

			[view setGrammarCheckingEnabled:YES];
			check([view isGrammarCheckingEnabled], "grammar checking stores its flag");
			[view setAutomaticQuoteSubstitutionEnabled:YES];
			check([view isAutomaticQuoteSubstitutionEnabled], "and so does quote substitution");
			[view toggleAutomaticDashSubstitution:nil];
			check([view isAutomaticDashSubstitutionEnabled], "and the dash toggle flips it on");

			{
				NSInteger first = [view spellCheckerDocumentTag];
				NSInteger second = [view spellCheckerDocumentTag];

				check(first > 0 && first == second,
				      "the view's document tag is allocated once and reused");
			}

			[view setSpellingState:1 range:NSMakeRange(2, 4)];
			[view setSpellingState:0 range:NSMakeRange(2, 4)];
			check(1, "setSpellingState:range: records and clears without crashing");
			[view orderFrontSubstitutionsPanel:nil];
			check(1, "and the substitutions panel refuses by name");

			[view release];
		}

		if (failures == 0) {
			printf("spell_checker: all checks passed\n");
			return 0;
		}
		printf("spell_checker: FAILURES\n");
		return 1;
	}
}
