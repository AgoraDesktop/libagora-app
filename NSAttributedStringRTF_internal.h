/*
 * NSAttributedStringRTF_internal.h — the RTF writer as a FUNCTION, so a package document can build on it.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * NOT INSTALLED. `NSAttributedStringRTF.m` holds the codec in both directions; this declares the writer's body to the
 * one other caller that needs it — `NSAttributedStringRTFD.m`, whose document is a DIRECTORY whose text part is an RTF
 * document. The two must not be two writers: a package's `TXT.rtf` written by a second implementation would drift
 * from what the plain RTF door writes, and a reader could then disagree with both.
 */
#ifndef AGORA_APPKIT_NSATTRIBUTEDSTRINGRTF_INTERNAL_H
#define AGORA_APPKIT_NSATTRIBUTEDSTRINGRTF_INTERNAL_H

#import <Foundation/Foundation.h>

/* THE RTF DOCUMENT FOR A STRING, as text. `attachmentFiles` says what to do with an attachment:
 *
 *   NULL  — write it INLINE, as `{\pict\pngblip…}` — the plain RTF door's answer, and the only one a standalone RTF
 *           file can carry;
 *   else  — write a REFERENCE to a file in the package (`{\NeXTGraphic <name> …}`) and put the bytes under that name
 *           in the dictionary, which is what RTFD is.
 *
 * The answer is autoreleased, and nil only when the string is nil. */
extern NSString *fn_rtf_text(NSAttributedString *source, NSMutableDictionary *attachmentFiles);

#endif /* AGORA_APPKIT_NSATTRIBUTEDSTRINGRTF_INTERNAL_H */
