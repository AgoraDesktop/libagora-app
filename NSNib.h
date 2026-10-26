/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSNib.h — a nib, the first-party format it is written in, and the rules its reader keeps.
 *
 * **THIS HEADER USED TO REFUSE THE DECODING DOORS BY NAME, AND THAT REFUSAL HAS BEEN CLOSED RATHER THAN
 * OVERRIDDEN.** What it said was that a nib is an archived object graph in Apple's own unpublished schema, that a
 * guessed schema would be a WRONG VALUE rather than an unfinished feature, and that closing the gap needed "a
 * first-party interface format for THIS AppKit — an emitter and a reader this tree owns". That format now exists,
 * and it is described in full below.
 *
 * **AND APPLE'S COMPILED FORMAT IS A COMPATIBILITY DOOR, TRANSLATED RATHER THAN DECODED.** A file whose `$top`
 * names `IB.objectdata` is handed to `AGAppleNib`, which maps the classes and keys it states (AGAppleNib.h) into
 * THIS tree's coding keys and then runs the same connection pass below. It is deliberately NOT decoded by
 * `NSKeyedUnarchiver`: Apple's keys and this tree's keys are different (`NSFrame` vs `frame`, `NSContents` vs
 * `objectValue`, flag bitfields vs separate booleans), so a direct decode would answer every
 * `-containsValueForKey:` with NO and build default-valued objects — the wrong value this header has always
 * refused. A class outside the translator's table refuses the WHOLE file by name; an unmapped key stays at the
 * class's default and is reported by `+[AGAppleNib unmappedKeysForAppleNibArchive:]`. AGNib is still the format
 * this tree WRITES, and it is read first.
 *
 * ============================ THE FORMAT: "AGNib", version 1 ============================
 *
 * **THE ARCHIVE IS THE PRODUCT; THE SOURCE IS WHAT A PERSON EDITS.** This file describes the archive — the bytes a
 * runtime reads. The text a designer writes, and the compiler that turns one into the other, are `NSNibSource.h` (in this
 * repository's `tests/`, because the eventual home of a compiler is its own repository). The split is Apple's
 * `.xib`/`.nib` split, and it exists for the reason a federation of git repositories needs it: text merges, bytes do not.
 *
 * A NIB IS A KEYED ARCHIVE. The bytes are whatever `NSKeyedArchiver` writes — a property list with the `$objects`
 * table, the `$class` chain and object identity preserved — because that machinery already exists in
 * `libagora-base` and inventing a second serialiser would be inventing a second set of bugs. What this class OWNS
 * is the ROOT's shape, which is three keys:
 *
 *   {
 *     "AGNibVersion"          : 1,
 *     "AGNibTopLevelObjects"  : [ <object>, ... ],
 *     "AGNibConnections"      : [ <connection>, ... ]
 *   }
 *
 *   * A TOP-LEVEL OBJECT is a window or a view that the nib owns: the objects a caller receives in the
 *     `topLevelObjects` out-parameter, in the order the file lists them.
 *   * A CONNECTION is one of THREE dictionaries, and this is the whole connection vocabulary:
 *
 *       OUTLET  { "AGNibConnectionSource"      : <object>,
 *                 "AGNibConnectionKeyPath"     : "delegate",
 *                 "AGNibConnectionDestination" : <object> | "NSNibFileOwner" }
 *
 *       ACTION  { "AGNibConnectionSource"      : <control>,
 *                 "AGNibConnectionAction"      : "doTheThing:",
 *                 "AGNibConnectionDestination" : <object> | "NSNibFileOwner" }
 *
 *       BINDING { "AGNibConnectionSource"      : <object>,
 *                 "AGNibConnectionBinding"     : "stringValue",
 *                 "AGNibConnectionKeyPath"     : "content",
 *                 "AGNibConnectionDestination" : <object> | "NSNibFileOwner",
 *                 "AGNibConnectionOptions"     : <dictionary> }        (optional)
 *
 *     An OUTLET is applied with `-setValue:forKeyPath:` on the source. An ACTION is applied as the pair
 *     `-setTarget:`/`-setAction:` on the source, the destination being the target. A BINDING is applied with
 *     `-bind:toObject:withKeyPath:options:` on the source, the destination being the observed object; it is the
 *     third kind because Apple's `NSNibBindingConnector` is a kind of its own, not an outlet. `"NSNibFileOwner"` is the
 *     PLACEHOLDER for the owner handed to `-instantiateNibWithOwner:topLevelObjects:` — the owner is not in the
 *     archive, so it is named rather than encoded, which is the same reason Apple's nib has a file's owner. A binding
 *     connection without `AGNibConnectionOptions` binds without options, which is what the translator emits when the
 *     Apple archive's `NSOptions` names a transformer or formatter this tree cannot build.
 *
 * **IDENTITY IS THE REASON CONNECTIONS ARE SEPARATE FROM THE OBJECTS RATHER THAN A PROPERTY ON THEM.** A connection
 * names two objects, and `NSKeyedArchiver` writes an object reachable twice ONCE; so a connection's source and
 * destination are the same table entries the top-level objects use, and a graph where a control's target is also a
 * top-level object decodes to one object, not two. That is also why a CONTROL'S TARGET IS NOT ARCHIVED AS A VALUE:
 * a target is either the file's owner (absent from the archive) or another object in it, and both cases are a
 * connection. `NSCell`'s target is therefore not encoded, and a nib that wants one says so with an ACTION
 * connection.
 *
 * ============================ THE RULES THE READER KEEPS ============================
 *
 * 1. SECURE DECODING IS ON AND THE ALLOW-LIST IS THIS CLASS'S. The archive names classes, and decoding an archive
 *    of class names into a live process is the classic remote-code-execution shape — `NSCoding.h` records that the
 *    enforcement used to be missing, and `NSKeyedUnarchiver` now refuses a class that does not claim
 *    `NSSecureCoding` or is not in the allowed set, BEFORE it is instantiated. `+supportedClasses` is the set this
 *    reader passes, so a design file from outside the project cannot name a class this tree did not agree to build.
 *    Every class in that set conforms to `NSSecureCoding` and every one of them implements BOTH coding methods
 *    itself — see rule 3.
 * 2. AN UNKNOWN KEY IS IGNORED, AND A MISSING ONE LEAVES THE CLASS'S OWN DEFAULT. That is what makes the format
 *    forward-compatible in the direction that matters: a file written by a newer tree is read by an older one, with
 *    the properties that older tree does not know still at their defaults. It is NOT backwards-compatible — a file
 *    that needs a newer class will hit rule 3's census when the older tree tries to instantiate it.
 * 3. A CLASS THAT INHERITS CODING MAY LOSE STATE, AND THE READER MEASURES RATHER THAN ASSUMES. `-initWithCoder:` is
 *    inherited, so an `NSButtonCell` whose class forgot to implement it decodes through `NSCell`'s — silently, with
 *    the button's own ivars at their defaults. That is the drift trap this format has to survive, and the measurement
 *    is `class_getInstanceSize`: a subclass that adds NO instance storage has nothing an inherited method can drop and
 *    is accepted (a plain `NSView` subclass that exists to be one thing on screen is a legitimate design class), while
 *    a subclass that adds storage and inherits its coding is REFUSED. `+classesInheritingCoding` answers the classes
 *    on the allow-list that fail that measurement, and `-instantiateNibWithOwner:topLevelObjects:` refuses an archive
 *    that NAMES one rather than decoding it into a half-empty object.
 * 4. NOTHING RUNTIME IS ARCHIVED. A view's window, superview and cursor rects, a window's surface and framebuffer,
 *    a cell's control view, a menu item's parent menu: each is state of a LIVE OBJECT GRAPH and not of a design. A
 *    nib that carried them would resurrect pointers into a process that no longer exists. The classes' coding
 *    methods encode their DESIGN properties and say so where they do it.
 */

#ifndef APPKIT_NSNIB_H
#define APPKIT_NSNIB_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/* THE ROOT'S THREE KEYS, whose values are their own names — this tree's rule wherever a name is published. */
extern NSString * const NSNibFormatVersionKey;		/* "AGNibVersion" */
extern NSString * const NSNibTopLevelObjectsKey;	/* "AGNibTopLevelObjects" */
extern NSString * const NSNibConnectionsKey;		/* "AGNibConnections" */

/* AND A CONNECTION'S FOUR, of which an outlet uses three and an action uses three. */
extern NSString * const NSNibConnectionSourceKey;	/* "AGNibConnectionSource" */
extern NSString * const NSNibConnectionKeyPathKey;	/* "AGNibConnectionKeyPath" */
extern NSString * const NSNibConnectionActionKey;	/* "AGNibConnectionAction" */
extern NSString * const NSNibConnectionDestinationKey;	/* "AGNibConnectionDestination" */
/* AND THE BINDING'S TWO: a binding connection names the binding, the observed key path (the shared key above) and the
 * options dictionary. It is the third kind, added for Apple's `NSNibBindingConnector`; an archive without one reads
 * exactly as before. */
extern NSString * const NSNibConnectionBindingKey;	/* "AGNibConnectionBinding" */
extern NSString * const NSNibConnectionOptionsKey;	/* "AGNibConnectionOptions" */

/* THE OWNER'S PLACEHOLDER. A file that wires a control's action to its owner writes this where the target would be,
 * because the owner is the caller's object and not the archive's. Its value is a string rather than an object so that
 * a decoder can recognize it before it tries to send it a message. */
extern NSString * const NSNibFileOwner;

@interface NSNib : NSObject
{
	/* THE SOURCE, one of the two spellings a caller may give: a URL, or a name and (nullable) bundle. Loading is
	 * deferred to instantiation, so these are all this object holds. */
	NSURL *_url;
	NSString *_name;
	NSBundle *_bundle;
}

/* THE TWO WAYS IN. Both answer nil for a source they cannot even RECORD — a nil URL or a nil name — which is
 * stricter than Apple's nonnull spelling and is what the implementation accepts. */
- (nullable instancetype)initWithContentsOfURL:(nullable NSURL *)nibFileURL;
- (nullable instancetype)initWithNibNamed:(nullable NSString *)nibName bundle:(nullable NSBundle *)bundle;

/* ============================ READING ============================ */

/* THE DOOR THAT BUILDS THE GRAPH, AND IT IS THE ONE APPLE HAS. On success the top-level objects are written through
 * the out-parameter, in file order, and the connections have been applied; on FAILURE the out-parameter is left
 * EXACTLY AS IT WAS rather than set to an empty array that would read as "instantiated, nothing in it". An owner may
 * be nil, in which case a connection naming the file's owner is REFUSED — a nib that wires its owner's action to
 * nothing is an error, not a no-op. */
- (BOOL)instantiateNibWithOwner:(nullable id)owner
               topLevelObjects:(NSArray * _Nullable * _Nullable)topLevelObjects;

/* AND APPLE'S OLDER NAME TABLE FORM, kept because it is the door some callers use. It reads `NSNibOwner` out of the
 * table, and fills `NSNibTopLevelObjects` when that value is a mutable array. A table whose top-level slot is not a
 * mutable array is refused rather than silently ignored. */
- (BOOL)instantiateNibWithExternalNameTable:(NSDictionary *)nameTable;

/* THE TWO KEYS A NAME TABLE CARRIES, whose values are their own names. `NSNibOwner` is the object the nib's
 * connections are made TO, and `NSNibTopLevelObjects` is what a name table receives them IN. */
extern NSString *NSNibOwner;
extern NSString *NSNibTopLevelObjects;

/* ============================ WRITING ============================ */

/* THE FORMAT'S VERSION THIS TREE WRITES AND READS. */
+ (NSInteger)formatVersion;

/* **THE READER'S ALLOW-LIST, AND A WRITER'S CONTRACT WITH ITSELF.** Every class this set names conforms to
 * `NSSecureCoding` and implements both coding methods; rule 3 above is the check that stays true. A design file that
 * names a class outside this set is refused before instantiation, which is the whole security story.
 *
 * **A DESIGN FILE'S CLASSES ARE NOT ALL APPKIT'S, which is why the list is EXTENSIBLE RATHER THAN CLOSED.** A nib names
 * the APPLICATION's view subclasses — that is the whole point of a nib — and an application registers those with
 * `+registerDesignClass:` at launch. Registration is where rule 3 is enforced: a class that inherits its coding, or
 * that does not claim `NSSecureCoding`, is REFUSED at registration rather than at read time, so a program learns about
 * the mistake once rather than every time a file names the class. */
+ (NSSet *)supportedClasses;

/* REGISTERS ONE OF THE APPLICATION'S OWN DESIGN CLASSES. Answers NO — and registers nothing — for a class that
 * inherits either coding method or does not conform to `NSSecureCoding`, which is the same gate the AppKit's own list is
 * held to. Answers YES for a class already registered. */
+ (BOOL)registerDesignClass:(Class)cls;

/* AND WHETHER A CLASS IS ON THE ALLOW-LIST, asked before a caller bothers to archive with it. */
+ (BOOL)isSupportedClass:(Class)cls;

/* **THE VALIDATOR'S DOOR, AND IT IS FOR A TOOL RATHER THAN FOR AN APPLICATION.** The reader's checks are the same three
 * that guard `-instantiateNibWithOwner:topLevelObjects:` — the object table is a plist, so its class names can be checked
 * WITHOUT building anything — and a command-line validator wants exactly that: an answer of "this file would be refused,
 * and here is the name" with nothing instantiated and no owner required. Answers nil when the file would be accepted, and
 * a sentence naming the first problem when it would not (a class outside the allow-list, a class that would lose state, a
 * root of the wrong shape, or bytes that are not a property list at all). **AN APPLE ARCHIVE IS VALIDATED BY ITS
 * TRANSLATOR**, so the same door answers "it names NSBox, which this translator does not map" without building a view. */
+ (nullable NSString *)refusalReasonForArchiveData:(NSData *)data;

/* **THE CENSUS THAT KEEPS RULE 3 HONEST.** Answers the classes on the allow-list that add instance storage of their own
 * yet inherit a coding method instead of implementing it — the classes that would decode into a half-empty object. An
 * empty set is the only healthy answer, and the round-trip test asserts it. */
+ (NSSet *)classesInheritingCoding;

/* THE WRITER. Builds the three-key root from the objects and connections and answers the archive's bytes; nil for a
 * nil or empty object list, because a nib that owns nothing is not a nib. */
+ (nullable NSData *)archivedDataWithTopLevelObjects:(NSArray *)objects
                                         connections:(nullable NSArray *)connections;

/* AND THE TWO CONNECTION BUILDERS, so that a caller does not spell the four keys by hand. `destination` may be
 * `NSNibFileOwner` (the string) to name the file's owner. */
+ (NSDictionary *)outletConnectionFrom:(id)source
				    to:(nullable id)destination
			     keyPath:(NSString *)keyPath;
+ (NSDictionary *)actionConnectionFrom:(id)source
				    to:(nullable id)destination
				action:(NSString *)selectorName;
/* AND THE BINDING BUILDER: `source` is the bound object, `destination` the observed object, `binding` the binding name
 * and `keyPath` the observed path. `options` is stored as-is (this tier's binding stores its options but reads only the
 * three generic ones); nil is a binding without options. */
+ (NSDictionary *)bindingConnectionFrom:(id)source
				     to:(nullable id)destination
				binding:(NSString *)bindingName
				keyPath:(NSString *)keyPath
				options:(nullable NSDictionary *)options;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSNIB_H */
