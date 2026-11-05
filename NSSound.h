/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSSound.h — a sound a control can play, and the class three TODOs in this tier were waiting for.
 *
 * **THIS CLASS WAS THE NAMED ABSENCE.** `NSBundleAdditions.h` says its sound door lives in one header with the
 * image pair "where Apple splits them across two" and that the split can happen "when a real `NSSound`
 * arrives"; `NSButtonCell.m` excludes its `_sound` from archiving because an archive cannot carry a class the
 * process has no implementation of. This is that class, and it is built on `libagora-audio`: a file is decoded
 * by `AudioFile`, buffered once, and played by an `AudioQueue`.
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

@protocol NSSoundDelegate <NSObject>
@optional
- (void)sound:(NSSound *)sound didFinishPlaying:(BOOL)finishedPlaying;
@end

@interface NSSound : NSObject <NSCopying>
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

- (instancetype)initWithContentsOfFile:(NSString *)path byReference:(BOOL)byReference;
- (instancetype)initWithContentsOfURL:(NSURL *)url byReference:(BOOL)byReference;
- (instancetype)initWithData:(NSData *)data;
+ (instancetype)soundNamed:(NSString *)name;

- (NSString *)name;
- (void)setName:(NSString *)name;

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

- (id)delegate;
- (void)setDelegate:(id)delegate;

@end

#endif /* APPKIT_NSSOUND_H */
