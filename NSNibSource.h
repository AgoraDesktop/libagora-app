/*
 * NSNibSource.h — the nib format's TEXT SOURCE, and the compiler that turns it into the archive a nib is.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE ARCHIVE IS THE PRODUCT AND THE SOURCE IS WHAT A PERSON EDITS.** `NSNib.h` describes a keyed archive, which is
 * `btree`/XML plist bytes: correct for a runtime to read and useless to review. This is the other half of that split,
 * the one Apple made when `.xib` (text) became `.nib` (binary): a design is AUTHORED as text, COMPILED into the archive,
 * and the archive is a build artifact. Text merges; bytes do not, and a federation of git repositories needs files that
 * merge.
 *
 * ============================ THE SYNTAX ============================
 *
 * A source file is a dictionary, in `NSPropertyListOpenStepFormat`'s spelling, with ONE extension: a bare word is TYPED.
 * `41` is a number, `4.5` is a real, `YES`/`NO` are booleans, and anything else is a string. That extension is the whole
 * difference from Apple's OpenStep reader, and it exists because a design says `tag = 41` rather than `tag = "41"` and a
 * compiler should not have to guess which one a caller meant.
 *
 * **AND ONE VALUE FORM THAT IS NOT A WORD: THE LITERAL.** A property whose value is an OBJECT — a colour, a font, an
 * image — is written with an `@`, a name and a parenthesised body, because `properties` otherwise holds only what a
 * person can type:
 *
 *   textColor = @color(#ff0000);          // six digits, opaque
 *   themeColor = @color(#0a0a0aff);       // eight digits, with alpha
 *   tint       = @color(orange);          // one of a dozen names
 *   font       = @font("Helvetica Neue" 13);
 *   image      = @image(icon-run);
 *
 * A literal is built by the compiler and applied through KVC like any other value; one it cannot build — a colour that
 * is not hex, a font this machine has not got, an image nothing is named — is a refusal that names the property.
 *
 * Comments are a double slash to the end of the line, and the usual block form.
 *
 *   {
 *     version = 1;
 *     objects = (
 *       {
 *         id = "root";
 *         class = NSView;
 *         properties = { frame = "0 0 320 240"; tag = 41; };
 *         subviews = (
 *           { id = "subject"; class = NSView;
 *             properties = { translatesAutoresizingMaskIntoConstraints = NO; }; }
 *         );
 *         constraints = (
 *           { first = "subject"; firstAttribute = width; multiplier = 1; constant = 120; }
 *           { first = "subject"; firstAttribute = left; second = "root";
 *             secondAttribute = left; relation = equal; constant = 10; }
 *         );
 *       }
 *     );
 *     connections = (
 *       { source = "subject"; action = "go:"; destination = owner; }
 *     );
 *   }
 *
 * ============================ THE SCHEMA ============================
 *
 * An OBJECT is a dictionary with `class` (required), and optionally `id` (a name other entries refer to), `properties`
 * (applied through Key Value Coding), `cell` (an object, for an `NSControl`), `contentView` (an object, for a window),
 * `subviews` (objects, in back-to-front order) and `constraints`. A key that is not one of those is REFUSED BY NAME
 * rather than ignored, because a compiler that silently drops a typo is a compiler that silently drops a design.
 *
 * A CONSTRAINT names its two sides by `id` — `first`, and `second` when the equation has one — and its attributes and
 * relation by NAME (`left`, `width`, `centerY`, …; `equal`, `lessThanOrEqual`, `greaterThanOrEqual`). The name
 * `NSLayoutAttributeNotAnAttribute` is spelled `none`.
 *
 * A CONNECTION is an outlet (`source`, `keyPath`, `destination`) or an action (`source`, `action`, `destination`). The
 * name `owner` means the file's owner — the placeholder `NSNib.h` documents — and any other name must be an `id`
 * declared earlier in the file.
 */
#ifndef APPKIT_NSNIBSOURCE_H
#define APPKIT_NSNIBSOURCE_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSNibSource : NSObject

/* **THE PARSER.** Answers the source's property list, or nil with a sentence in `error` naming the line and the problem.
 * It is public because it is what a future `format` verb or an editor's syntax check would use, and because a parser that
 * can only be reached through the compiler cannot be tested on its own. */
+ (nullable id)propertyListFromSourceData:(NSData *)data error:(NSString * _Nullable * _Nullable)error;

/* **THE COMPILER, AND IT IS A COMPILER RATHER THAN A CONVERTER.** It checks the version, refuses a key it does not
 * understand, refuses a class that is not on `NSNib`'s allow-list, refuses a reference to an `id` that was never
 * declared, and only then builds the objects, applies their properties through KVC, wires the constraints and archives
 * the result. Every refusal is a sentence naming the object, the key and — where there is one — the line. */
+ (nullable NSData *)archiveFromSourceData:(NSData *)data error:(NSString * _Nullable * _Nullable)error;

/* AND THE SAME TWO OVER A FILE, which is how the tool uses them and how a caller will. */
+ (nullable NSData *)archiveFromSourceFile:(NSString *)path error:(NSString * _Nullable * _Nullable)error;

/* **THE OTHER DIRECTION: AN ARCHIVE BACK INTO SOURCE.** This is what makes the format CLOSED — a file can be opened,
 * edited as text and compiled again — and it is also how an archive produced by an older tree becomes text a person can
 * read. It is deliberately limited, and it fails closed on what it cannot express:
 *
 *   * A SCALAR PROPERTY IS EMITTED. Numbers, booleans, strings, and the three geometry values (a rect, a size, a point)
 *     become the words and strings this grammar already has.
 *   * A STRUCTURAL ONE IS EMITTED AS STRUCTURE: `subviews`, `cell`, `contentView` and a window's `contentView` become
 *     nested objects, and the connections are rebuilt from the archive's own records.
 *   * A COLOUR, A FONT AND AN IMAGE ARE WRITTEN AS LITERALS (`@color(…)`, `@font(…)`, `@image(…)`), so the three objects a
 *     property map cannot otherwise hold round-trip.
 *   * AN OBJECT-VALUED PROPERTY THAT IS NONE OF THOSE — a menu on a cell, a formatter, anything with no literal — is a
 *     REFUSAL that names the object and the key, rather than a line quietly left out.
 *
 * It also cannot recover what the archive never carried: a class's own idea of what a property MEANT, and any state the
 * coding methods deliberately leave out (a target, a delegate, a window's surface). */
+ (nullable NSData *)sourceFromArchiveData:(NSData *)archive error:(NSString * _Nullable * _Nullable)error;

/* ============================ THE TWO DOORS A DESIGN TOOL NEEDS ============================ */

/* **AN EDITOR NEEDS THE GRAPH AND THE NAMES, WHICH IS THE ONE THING THE ARCHIVE DOOR CANNOT GIVE IT.** The compiler
 * answers archive bytes: the objects are inside them and the names the source used to refer to them are GONE, because an
 * archive has no `id`. A builder holds the tree it read, shows the live object behind each node, and writes the tree back
 * — so it needs what this door returns: the top-level objects in file order, and the `id` → object table for EVERY object
 * in the file, nested ones included, because the object a connection or a constraint names is usually a subview.
 *
 * The objects are made by the same code that makes them for the archive, so what an editor shows and what a runtime
 * instantiates are the same graph, made by the same refusals. **CONNECTIONS ARE NOT APPLIED AND THE OWNER IS NOT A
 * PARAMETER**: at design time the owner does not exist and a connection to it is a record in the source rather than a
 * message to send, and the connections are already in the property list this door takes. Applying them is
 * `NSNib -instantiateNibWithOwner:topLevelObjects:`, at the other end of the format. */
+ (nullable NSArray *)objectsFromPropertyList:(id)propertyList
				 objectsByID:(NSDictionary * _Nullable * _Nullable)outObjectsByID
				       error:(NSString * _Nullable * _Nullable)error;

/* **AND THE WAY BACK, FROM THE TREE RATHER THAN FROM LIVE OBJECTS.** `sourceFromArchiveData:` is a DECOMPILER: it asks
 * each class's coder which keys it codes, reads the live values and writes every one of them — right for an archive that
 * has no source text, wrong for an editor, which would then bake every class's defaults into the file and silently drop a
 * value KVC cannot box. This writes THE PROPERTY LIST THE PARSER BUILT: the keys it holds, once each, in an order that
 * depends on nothing but the tree, so saving an unedited file twice is byte-identical and a design file is reviewed as a
 * diff. `parse → emit → parse` is the identity it is held to.
 *
 * **THE ROOT IS VALIDATED BY THE COMPILER'S OWN RULES BEFORE ANYTHING IS WRITTEN**, so a file this door answers is a file
 * the door above can compile. Saving is therefore never the step at which a design became unreadable. */
+ (nullable NSData *)sourceDataFromPropertyList:(id)propertyList
					 error:(NSString * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSNIBSOURCE_H */
