/*
 * NSTextAttachment.h — THE OBJECT AN ATTRIBUTED STRING CARRIES WHERE A PICTURE GOES.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **AN ATTACHMENT IS A CHARACTER THAT STANDS FOR SOMETHING ELSE.** Apple's model is one character of
 * `NSAttachmentCharacter` (U+FFFC, the OBJECT REPLACEMENT CHARACTER) in the string, with an `NSTextAttachment` as
 * the value of `NSAttachmentAttributeName` over that character; the character is what the caret, the selection and
 * every range count, and the attachment is what is DRAWN there instead of a glyph. So a picture is not a special case
 * of the text — it is a character the text already has, with an attribute saying what to put in its place.
 *
 * **AND THE CELL IS WHERE A SIZE AND A DRAWING COME FROM.** `NSTextAttachmentCell` is the object the layout asks "how
 * big are you" and "draw yourself here"; `NSTextAttachment` holds one, and an `NSImage` attached to a fresh cell is
 * the common case the convenience door covers. THIS TIER'S READER IS THE LAYOUT MANAGER: at a run carrying
 * `NSAttachmentAttributeName` it asks the cell for its size, sets a CORE TEXT RUN DELEGATE of that size over the
 * character, and calls `-drawWithFrame:inView:` at the box's x instead of setting the glyphs — so the ENGINE reserves
 * the width and the text after an attachment flows past it rather than over it. See `CTRunDelegate.h` for the box
 * itself.
 *
 * **WHAT IS NOT HERE, AND ITS ROWS STAY OPEN — AND ONE OF THE TWO GROUNDS HAS EXPIRED.** `NSFileWrapper` IS here now
 * (`libagora-base`), so `-fileWrapper` and `-initWithFileWrapper:` are owed for a DIFFERENT reason than this note used
 * to give: the READ half is decodable (the tree reads PNG and JPEG), but the WRITE half has no image ENCODER to turn
 * the attachment's picture back into bytes, so the pair cannot round-trip and it lands with the ENCODER rather than
 * with the wrapper. AND THE TRACKING FAMILY (`-wantsToTrackMouse`, `-highlight:…`, `-trackMouse:…`) IS OWED WITH
 * `NSCell`'s OWN REFUSAL: the door that would drive it is `-trackMouse:inRect:ofView:untilMouseUp:`, a MODAL LOOP this
 * tree has refused by name (see `NSCell.h`) because a loop built from guessed coordination can hang the guest — so the
 * three hooks wait for that decision rather than being half-wired here. A picture in a document is not draggable yet.
 */
#ifndef APPKIT_NSTEXTATTACHMENT_H
#define APPKIT_NSTEXTATTACHMENT_H

#import <AppKit/NSCell.h>

@class NSImage;
@class NSView;
@class NSFileWrapper;

NS_ASSUME_NONNULL_BEGIN

/* **THE CHARACTER THAT STANDS FOR AN ATTACHMENT**, U+FFFC — "OBJECT REPLACEMENT CHARACTER" in Unicode's own words,
 * which is exactly what this is: a place in the text where an object goes. Apple spells it as a value of this name
 * rather than a bare literal so a caller writing `NSAttachmentCharacter` and a reader seeing `0xFFFC` cannot drift. */
enum {
	NSAttachmentCharacter = 0xFFFC
};

/* **WHAT THE LAYOUT ASKS A CELL.** Three doors of Apple's protocol are here — the size, the baseline's place in the
 * cell, and the drawing — and the tracking family is named as owed above. The `characterIndex:` variants exist so a
 * cell that wants to know WHICH attachment it is drawing can; this tier's manager calls the plain one. */
@protocol NSTextAttachmentCell <NSObject>
- (NSSize)cellSize;
- (NSPoint)cellBaselineOffset;
- (void)drawWithFrame:(NSRect)cellFrame inView:(nullable NSView *)controlView;
- (void)drawWithFrame:(NSRect)cellFrame inView:(nullable NSView *)controlView characterIndex:(NSUInteger)charIndex;
@end

/* **AND THE CELL THAT HOLDS A PICTURE, WHICH IS WHAT A FRESH ATTACHMENT GETS.** It is an `NSCell` because Apple's is,
 * and it draws its image into the frame it is given; `-cellSize` is the image's own size. */
@interface NSTextAttachmentCell : NSCell <NSTextAttachmentCell>
@end

/* **AND THE ATTACHMENT: A VALUE A RUN CARRIES, WITH A CELL THAT KNOWS HOW TO DRAW IT.** The image doors are the ones
 * this tier can honour; the file-wrapper pair is named as owed. `-setImage:` also gives the attachment a
 * `NSTextAttachmentCell` holding that image if it has none, which is the convenience Apple's own `-setImage:` is. */
@interface NSTextAttachment : NSObject
{
	NSImage *_image;				/* RETAINED */
	NSCell<NSTextAttachmentCell> *_attachmentCell;	/* RETAINED */
}

+ (NSTextAttachment *)textAttachmentWithImage:(NSImage *)image;

- (nullable NSImage *)image;
- (void)setImage:(nullable NSImage *)image;

- (nullable NSCell<NSTextAttachmentCell> *)attachmentCell;
- (void)setAttachmentCell:(nullable NSCell<NSTextAttachmentCell> *)cell;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSTEXTATTACHMENT_H */
