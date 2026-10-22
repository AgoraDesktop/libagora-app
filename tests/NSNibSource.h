/*
 * NSNibSource.h — the nib format's TEXT SOURCE, and the compiler that turns it into the archive a nib is.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
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

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSNIBSOURCE_H */
