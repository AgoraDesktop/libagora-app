/*
 * NSAttributedString.m (AppKit) — the attribute names, defined once.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 */
#import "NSAttributedString.h"

/* **THE LITERALS ARE THIS TIER'S, AND THE HEADER SAYS WHY** (the era annotates each name with its value's TYPE
 * and default and publishes no literal). They are Apple's long-standing spellings, and what makes them correct
 * HERE is that they are the keys this library's own doors read: the probe passes one of these in a dictionary
 * and asserts that the ink changes, which is the only form of the claim that can be checked in this tier. */
NSString *NSFontAttributeName = @"NSFont";
NSString *NSForegroundColorAttributeName = @"NSColor";
/* **AND THE THREE THE MANAGER'S OWN INK READS, IN APPLE'S OWN SPELLINGS.** The two sides of a name do not have to
 * agree as STRINGS — this tier's Core Text spells `kCTFontAttributeName` "NSFontAttributeName" while the AppKit spells
 * the same key "NSFont", and the manager converts between them — but a key a caller WRITES has to be the one the
 * manager READS, which is what makes these three the important ones to pin. */
NSString *NSBackgroundColorAttributeName = @"NSBackgroundColor";
NSString *NSUnderlineStyleAttributeName = @"NSUnderline";
NSString *NSUnderlineColorAttributeName = @"NSUnderlineColor";
NSString *NSStrikethroughStyleAttributeName = @"NSStrikethrough";
NSString *NSStrikethroughColorAttributeName = @"NSStrikethroughColor";
NSString *NSParagraphStyleAttributeName = @"NSParagraphStyle";
NSString *NSAttachmentAttributeName = @"NSAttachment";

/* **AND THE DOCUMENT-LEVEL KEYS, WHICH ARE ABOUT THE FILE RATHER THAN A RUN.** The reader reports the type and the
 * encoding, and the type's two values are the two this tier can produce — RTF and the package form. The encoding's
 * value is an `NSNumber`, as the era header says in as many words; the reader decodes UTF-8, so that is the integer a
 * caller gets. See the declarations in the header for why only these four names are here. */
NSString *NSDocumentTypeDocumentAttribute = @"NSDocumentType";
NSString *NSRTFTextDocumentType = @"NSRTF";
NSString *NSRTFDTextDocumentType = @"NSRTFD";
NSString *NSCharacterEncodingDocumentAttribute = @"CharacterEncoding";
NSString *NSDefaultTabIntervalDocumentAttribute = @"DefaultTabInterval";
NSString *NSViewModeDocumentAttribute = @"ViewMode";
NSString *NSHyphenationFactorDocumentAttribute = @"HyphenationFactor";
