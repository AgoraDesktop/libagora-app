/* NSScreen.h — THE SCREEN, AS THIS TREE CAN DESCRIBE IT.
 *
 * © 2026 Kyle J. Cardozo. MIT licence (see LICENSE at the repository root).
 *
 * **THIS CLASS EXISTS BECAUSE ITS ROW WAS CLAIMED BY A FORWARD DECLARATION FIRST.** `NSWindow`'s placement doors
 * take an `NSScreen *`, and adding `@class NSScreen;` to their header to name the parameter flipped the ledger's
 * `class NSScreen` row to SHIPPED — the ledger's own rule is that a class is declared when its name is declared,
 * and a `@class` is a declaration. That is a trap this tree has recorded, and it was walked into: the row said
 * "shipped" for three commits while no such class existed. The remedy is not to un-declare the forward — the
 * parameter needs its name — but to MAKE THE CLAIM TRUE, which is this file.
 *
 * AND IT ENDS A DEVIATION THAT WAS STATED AS A SEAM. Until now the window's placement doors answered about the X
 * ROOT and IGNORED a passed screen ("accepted and not consulted", which is honest but is not the contract). With a
 * real object the argument is consulted, and the seam that remains is a narrower and truer one: A SCREEN HERE IS
 * ONE X SCREEN — the default one of the server this process is talking to. A multi-head server reached through
 * a SECOND output, or a screen the compositor composes rather than a described output, is not modelled, and saying so is a
 * smaller claim than "the argument does not matter".
 */
#ifndef APPKIT_NSSCREEN_H
#define APPKIT_NSSCREEN_H

#import <Foundation/NSObject.h>
#import <Foundation/NSGeometry.h>
#import <AppKit/NSGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@class NSArray;
@class NSDictionary;
@class NSString;
@class NSColorSpace;

/* **AND `-depth` IS HERE NOW, BECAUSE ITS ENCODING IS NO LONGER A GUESS.** It was left out while
 * `NSBitsPerPixelFromDepth` and its family were unwritten, because a packed value with a guessed encoding and no
 * consumer is a wrong value — and the family has since arrived with the constants READ FROM APPLE'S HEADER. This
 * door answers by asking that family which of the published depths fits the X visual, so the two cannot disagree.
 */

@interface NSScreen : NSObject

/* THE SCREENS THIS PROCESS CAN SEE, and the one the menu bar and new windows go on. There is one of each here —
 * see the header note — and the array is a real array because a caller indexes it. */
+ (NSArray *)screens;
+ (nullable NSScreen *)mainScreen;
/* AND THE ONE WITH THE MOST BITS PER PIXEL — the era's own door, and the shape of it is the point: it is a
 * FUNCTION OF `+screens` rather than a constant, so it answers what the loop says even where the answer is
 * obvious. With one screen (this tier's X connection — see the note above) that is that screen; with none it is
 * nil, which is the same vocabulary `-depth` uses for "no depth". */
+ (nullable NSScreen *)deepestScreen;

/* THE GEOMETRY, IN THE GLOBAL COORDINATE SPACE COCOA USES: both screens' frames hang off the same origin, so two
 * of them can be compared. `-visibleFrame` is the part a window may be placed in — and here it is the frame
 * itself, because subtracting a menu bar and a dock is a WINDOW SERVER's knowledge and this tree has neither of
 * its own yet. That is a deviation, and it is stated rather than left for a caller to discover. */
@property (readonly) NSRect frame;
@property (readonly) NSRect visibleFrame;
/* THE DEPTH AND THE DEPTHS THAT CAN BE ASKED FOR — the latter `0`-terminated, Apple's own sentinel. */
@property (readonly) NSWindowDepth depth;
@property (readonly) const NSWindowDepth *supportedWindowDepths;
/* WHAT THE SCREEN SAYS ABOUT ITSELF, keyed by the device-description constants below — which is where Apple keeps
 * these constants too, and why they are declared here rather than beside the window that also uses them. */
@property (readonly, copy) NSDictionary *deviceDescription;

/* AND THE USER'S NAME FOR IT, plus the deprecated scale factor the era's code asks for. */
@property (readonly, copy) NSString *localizedName;
@property (readonly) CGFloat userSpaceScaleFactor;

/* **THE SCREEN'S COLOUR SPACE, MAPPED FROM THE DEPTH'S OWN NAME.** A depth in this tier carries the era's space NAME
 * (`NSColorSpaceFromDepth`), and this door answers the `NSColorSpace` that name denotes: calibrated or device RGB → the
 * generic RGB space, calibrated or device white → the generic gray one. A screen with no output (depth 0) answers nil,
 * because there is no space to name rather than an unknown one. */
- (nullable NSColorSpace *)colorSpace;

@end

/* ============================================================================================ *
 * THE DEVICE-DESCRIPTION CONSTANTS.                                                             *
 *                                                                                                *
 * THESE ARE APPLE'S OWN PLACEMENT — they describe a SCREEN and live in the screen's header —      *
 * and they moved here from `NSWindow.h`, where they were declared because the window was the    *
 * only thing that needed them. The ledger carries each under both owners, which is why the      *
 * move is invisible to the counts.                                                               *
 * ============================================================================================ */
extern NSString *NSDeviceSize;
extern NSString *NSDeviceResolution;
extern NSString *NSDeviceColorSpaceName;
extern NSString *NSDeviceBitsPerSample;
extern NSString *NSDeviceIsScreen;
extern NSString *NSDeviceIsPrinter;
/* AND THE ONE ANNOUNCEMENT A SCREEN MAKES. */
extern NSString *NSScreenColorSpaceDidChangeNotification;

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSSCREEN_H */
