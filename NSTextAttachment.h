/*
 * NSTextAttachment.h — THE OBJECT AN ATTRIBUTED STRING CARRIES WHERE A PICTURE GOES.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
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
 * **AND THE WRAPPER PAIR'S OLD GROUND HAS EXPIRED RATHER THAN ITS ROW.** The pair used to wait on an image ENCODER,
 * and the encoder exists now — `NSBitmapImageRep` writes PNG through Core Graphics' `CGImageDestination` — so
 * `-fileWrapper`/`-initWithFileWrapper:` are here, over `NSFileWrapper`, which has lived in `libagora-base` all along.
 * That is what an RTFD package is built out of: the attachment is not the package, it is the FILE inside it.
 *
 * **AND THE TRACKING FAMILY IS HERE, DRIVEN BY THE TEXT VIEW'S OWN EVENT STREAM RATHER THAN BY A MODAL LOOP.**
 * `NSCell` refuses `-trackMouse:inRect:ofView:untilMouseUp:` as a loop built from guessed coordination (see
 * `NSCell.h`), so this family does NOT re-introduce one: `NSTextView` asks an attachment's cell from its own
 * `-mouseDown:`/`-mouseDragged:`/`-mouseUp:`, and the cell's `-trackMouse:…` is asked ONCE PER EVENT instead of owning
 * the loop. A cell subclass that overrides it therefore sees the whole gesture — the down, every drag and the up —
 * which is the extension point Apple's loop exists for, without the loop.
 *
 * **THE ANSWER TO THAT DOOR IS THE EVENT'S, NOT THE SESSION'S, AND THE DIFFERENCE IS STATED RATHER THAN GLOSSED.**
 * Apple's whole-session call answers "did the button come up inside the frame"; here the DOWN event's YES means
 * "track me", a DRAG's means "keep tracking", and the UP event's is Apple's own answer for the end of the gesture.
 * `-highlight:withFrame:inView:` is where the cell says it is pressed, and the default cell paints a translucent
 * accent over its picture. A picture in a document can be pressed and dragged over now; the DELEGATE messages
 * (`-textView:clickedOnCell:inRect:atIndex:` and the dragging family) are a separate door and stay owed.
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

/* **WHAT THE LAYOUT AND THE TEXT VIEW ASK A CELL.** The simple half is the size, the baseline's place in the cell, the
 * drawing, and the three tracking hooks; the `characterIndex:` variants are the sophisticated half Apple asks a cell
 * that wants to know WHICH attachment it is drawing, and `NSTextAttachmentCell` implements them by forwarding to the
 * simple ones — exactly the arrangement the 10.6 header describes. THE TRACKING DOORS ARE ASKED PER EVENT (see the
 * file comment): the view calls `-trackMouse:…` on the down, on each drag and on the up. */
@protocol NSTextAttachmentCell <NSObject>
- (NSSize)cellSize;
- (NSPoint)cellBaselineOffset;
- (void)drawWithFrame:(NSRect)cellFrame inView:(nullable NSView *)controlView;
- (BOOL)wantsToTrackMouse;
- (void)highlight:(BOOL)flag withFrame:(NSRect)cellFrame inView:(nullable NSView *)controlView;
- (BOOL)trackMouse:(NSEvent *)theEvent inRect:(NSRect)cellFrame ofView:(nullable NSView *)controlView
      untilMouseUp:(BOOL)flag;

/* AND THE THREE WITH THE CHARACTER INDEX, which the view asks FIRST when a cell answers them. */
- (void)drawWithFrame:(NSRect)cellFrame inView:(nullable NSView *)controlView characterIndex:(NSUInteger)charIndex;
- (BOOL)wantsToTrackMouseForEvent:(NSEvent *)theEvent inRect:(NSRect)cellFrame ofView:(nullable NSView *)controlView
		 atCharacterIndex:(NSUInteger)charIndex;
- (BOOL)trackMouse:(NSEvent *)theEvent inRect:(NSRect)cellFrame ofView:(nullable NSView *)controlView
  atCharacterIndex:(NSUInteger)charIndex untilMouseUp:(BOOL)flag;
@end

/* **AND THE CELL THAT HOLDS A PICTURE, WHICH IS WHAT A FRESH ATTACHMENT GETS.** It is an `NSCell` because Apple's is,
 * and it draws its image into the frame it is given; `-cellSize` is the image's own size. IT TRACKS THE MOUSE: a
 * press highlights the picture with a translucent accent, a drag carries that highlight in and out of the cell's own
 * frame, and the release clears it — so the default cell shows the gesture while a subclass overrides the same doors
 * to give an attachment behaviour of its own. */
@interface NSTextAttachmentCell : NSCell <NSTextAttachmentCell>
@end

/* **AND THE ATTACHMENT: A VALUE A RUN CARRIES, WITH A CELL THAT KNOWS HOW TO DRAW IT.** The image doors and the
 * file-wrapper pair are both here; `-setImage:` also gives the attachment a `NSTextAttachmentCell` holding that image
 * if it has none, which is the convenience Apple's own `-setImage:` is. */
@interface NSTextAttachment : NSObject
{
	NSImage *_image;				/* RETAINED */
	NSFileWrapper *_fileWrapper;			/* RETAINED */
	NSCell<NSTextAttachmentCell> *_attachmentCell;	/* RETAINED */
}

+ (NSTextAttachment *)textAttachmentWithImage:(NSImage *)image;

- (nullable NSImage *)image;
- (void)setImage:(nullable NSImage *)image;

/* **THE FILE WRAPPER, WHICH IS THE HALF RTFD NEEDS AND THE PICTURE HALF NEVER DID.** An attachment in a *package*
 * document is not a picture pasted into the text: it is a FILE in the package, and the document refers to it by name.
 * `-fileWrapper` is that file — `NSFileWrapper` is `libagora-base`'s, and this is the pair Apple declares over it. The
 * designated initialiser of Apple's class is `-initWithFileWrapper:`; `-init` is the same as an empty wrapper here, and
 * the image is a SEPARATE fact, so an attachment can carry one, the other, or both (a wrapper whose bytes happen to be
 * a picture is still just a wrapper to this class — the two are not derived from each other). */
- (nullable NSFileWrapper *)fileWrapper;
- (instancetype)initWithFileWrapper:(nullable NSFileWrapper *)fileWrapper;
- (void)setFileWrapper:(nullable NSFileWrapper *)fileWrapper;

- (nullable NSCell<NSTextAttachmentCell> *)attachmentCell;
- (void)setAttachmentCell:(nullable NSCell<NSTextAttachmentCell> *)cell;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSTEXTATTACHMENT_H */
