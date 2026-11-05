/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSSound.h — a sound a control can play, and the two debts its arrival paid off.
 *
 * **THIS CLASS WAS THE NAMED ABSENCE.** `NSBundleAdditions.h` said its sound door lives in one header with the
 * image pair "where Apple splits them across two" and that the split could happen "when a real `NSSound`
 * arrives"; `NSButtonCell.m` excluded its `_sound` from archiving because an archive cannot carry a class the
 * process has no implementation of. Both are now closed *here*, in the header Apple puts them in: the class,
 * `NSCoding` (so a button's sound survives an archive), and `-pathForSoundResource:` as a category on
 * `NSBundle`. It is built on `libagora-audio`: a file is decoded by `AudioFile`, buffered once, and played by
 * an `AudioQueue`.
 *
 * **THE FILE'S OWN FORMAT IS WHAT PLAYS.** NSSound does not convert samples: a queue takes the description the
 * file reports and the device layer resamples to the device. That is one code path instead of one per format,
 * and it is why an 8-bit AIFF and a 32-bit float CAF behave the same here.
 */
#ifndef APPKIT_NSSOUND_H
#define APPKIT_NSSOUND_H

#import <Foundation/Foundation.h>

@class NSSound;
@class NSPasteboard;

NS_ASSUME_NONNULL_BEGIN

@protocol NSSoundDelegate <NSObject>
@optional
- (void)sound:(NSSound *)sound didFinishPlaying:(BOOL)finishedPlaying;
@end

@interface NSSound : NSObject <NSCopying, NSCoding>
{
@public
	/* Public because the queue's completion callback is a C function, and it has to say "this sound finished"
	 * without going through a method the delegate could have replaced. */
	NSString *_name;
	NSData *_data;
	float _volume;
	BOOL _loops;
	BOOL _playing;
	BOOL _paused;
	/* WHETHER THE BUFFER IS CURRENTLY IN THE QUEUE. A non-looping sound's buffer is handed *back* to the
	 * completion callback when it finishes, so `_buffer != NULL` does not mean "queued": a second `-play` has
	 * to enqueue it again or the queue plays silence and the click is lost. */
	BOOL _inFlight;
	void *_queue;
	void *_buffer;
	/* The file's AudioStreamBasicDescription, stored as bytes so this header carries no audio API. */
	unsigned char _formatStorage[40] __attribute__((aligned(8)));
	double _duration;
	id _delegate;
}

/* The file types this tier can decode: the three containers `libagora-audio` reads. */
+ (NSArray *)soundUnfilteredFileTypes;
+ (NSArray *)soundUnfilteredTypes;

/* EVERY INITIALIZER HERE CAN FAIL: a path that is not there, bytes that are not audio, or a name the bundle
 * cannot resolve. That is Apple's contract for these doors and it is why they are `nullable`. */
- (nullable instancetype)initWithContentsOfFile:(NSString *)path byReference:(BOOL)byReference;
- (nullable instancetype)initWithContentsOfURL:(NSURL *)url byReference:(BOOL)byReference;
- (nullable instancetype)initWithData:(NSData *)data;
+ (nullable instancetype)soundNamed:(NSString *)name;

- (nullable NSString *)name;
- (void)setName:(nullable NSString *)name;

- (BOOL)play;
- (BOOL)stop;
- (BOOL)pause;
- (BOOL)resume;
- (BOOL)isPlaying;

- (BOOL)loops;
- (void)setLoops:(BOOL)loops;

- (float)volume;
- (void)setVolume:(float)volume;

- (NSTimeInterval)duration;

- (nullable id)delegate;
- (void)setDelegate:(nullable id)delegate;

@end

/* **THE SOUND RESOURCE DOOR, IN THE HEADER APPLE PUTS IT IN.** It was declared — and is still implemented —
 * beside the image pair in `NSBundleAdditions.h`, which promised the split "when a real `NSSound` arrives".
 * The lookup is shared with the image doors (one name, extension optional, the literal name winning), so only
 * the declaration moved: `-pathForSoundResource:` names files "recognized by the NSSound class", which is
 * why it belongs beside that class. */
@interface NSBundle (NSSoundAdditions)

- (nullable NSString *)pathForSoundResource:(NSString *)name;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSSOUND_H */
