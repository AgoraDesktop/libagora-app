/* NSClipView.h — the view that clips and scrolls a document.
 *
 * © 2026 Kyle J. Cardozo. MIT licence (see LICENSE at the repository root).
 *
 * **THE ARITHMETIC IN THIS CLASS IS THE WHOLE OF IT**, and it is checked in exact points rather than by drawing:
 * where a short document SITS, where a long one STOPS, and what a scroll request becomes once it has been
 * constrained. `NSScrollView` is not here — it is the frame, the scrollers and the ruler, and a clip view without
 * one is still useful and still testable.
 *
 * THE SURFACE IS APPLE'S 10.6 HEADER, read for the era's members: the document view and its geometry, the
 * background and its cursor, the copy-on-scroll flag, and the three scrolling doors. The post-10.6 members
 * (`-constrainBoundsRect:`, the content insets) are STRUCK WITH THIS CLASS.
 */
#ifndef APPKIT_NSCLIPVIEW_H
#define APPKIT_NSCLIPVIEW_H

#import <AppKit/NSView.h>
#import <AppKit/NSColor.h>

NS_ASSUME_NONNULL_BEGIN

@class NSCursor;
@class NSEvent;
@class NSNotification;

@interface NSClipView : NSView
{
	/* BORROWED: the document view is a SUBVIEW, so the superview relationship already owns it and a second
	 * retained pointer would be a second owner. */
	NSView *_docView;
	NSColor *_backgroundColor;	/* RETAINED */
	NSCursor *_documentCursor;	/* BORROWED, as `NSCursor`'s shared instances are used */
	BOOL _drawsBackground;
	BOOL _copiesOnScroll;
}

- (void)setDocumentView:(nullable NSView *)aView;
- (nullable NSView *)documentView;

/* THE DOCUMENT'S GEOMETRY, IN TWO COORDINATE SYSTEMS ON PURPOSE: `-documentRect` is in the CLIP VIEW's (it is
 * what the scrolling arithmetic works in), and `-documentVisibleRect` is in the DOCUMENT's (it is what a caller
 * asks "what of my content is showing?"). */
- (NSRect)documentRect;
- (NSRect)documentVisibleRect;

- (void)setBackgroundColor:(NSColor *)color;
- (NSColor *)backgroundColor;
- (void)setDrawsBackground:(BOOL)flag;
- (BOOL)drawsBackground;
- (void)setDocumentCursor:(nullable NSCursor *)anObj;
- (nullable NSCursor *)documentCursor;

/* AND THE THREE SCROLLING DOORS. `-scrollToPoint:` is the one a caller uses, and it CONSTRAINS FIRST — which is
 * why a scroll past the end is not a way to see blank space. */
- (void)scrollToPoint:(NSPoint)newOrigin;
- (NSPoint)constrainScrollPoint:(NSPoint)newOrigin;
- (BOOL)autoscroll:(NSEvent *)theEvent;

/* THE TWO NOTIFICATIONS THE DOCUMENT VIEW SENDS WHEN IT CHANGES, and the handlers here re-constrain the scroll so
 * a document that SHRANK pulls the visible area back with it. */
- (void)viewFrameChanged:(nullable NSNotification *)notification;
- (void)viewBoundsChanged:(nullable NSNotification *)notification;

- (void)setCopiesOnScroll:(BOOL)flag;
- (BOOL)copiesOnScroll;

@end

/* AND THE TWO DOORS APPLE PUTS ON THE CLIP VIEW'S ENCLOSING VIEW — the notification a scrolled clip view sends to
 * whatever holds it, and the door through which a target does the moving. They are `NSView` members in Apple's
 * header too, and they are declared here because this is the class whose behaviour they carry. */
@interface NSView (NSClipViewSuperview)
- (void)reflectScrolledClipView:(NSClipView *)aClipView;
- (void)scrollClipView:(NSClipView *)aClipView toPoint:(NSPoint)aPoint;
@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSCLIPVIEW_H */
