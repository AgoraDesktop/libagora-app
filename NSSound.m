/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSSound.m — a sound over `libagora-audio`.
 *
 * THE FILE IS READ ONCE, AT INIT, AND PLAYED FROM MEMORY. A control's sound is short and is played on a click;
 * decoding it then would put a file parse on the interaction path, and a decoder that failed there would be a
 * click that did nothing. So `-initWithData:` keeps the bytes, reads the format and the duration through
 * `AudioFile`, and `-play` hands one buffer holding the whole sound to an `AudioQueue`.
 *
 * **THE QUEUE IS KEPT BETWEEN PLAYS.** Creating one per click allocates a queue and starts a device io proc on
 * a device that is already running; keeping it means a second click is a buffer enqueue. It is disposed in
 * `-dealloc` and when the format changes, which is the one case where it cannot be reused.
 *
 * **LOOPING IS THE QUEUE'S CALLBACK, NOT A TIMER.** The completion callback either re-enqueues the same buffer
 * (`_loops`) or marks the sound finished and tells the delegate — which is the shape Apple documents, and the
 * one a control relies on when it plays a sound and then forgets about it.
 */

#import <AppKit/NSSound.h>
#import <AppKit/NSGraphics.h>
#import <Foundation/NSBundle.h>
#import <AppKit/NSBundleAdditions.h>

#include <AudioToolbox/AudioToolbox.h>

@interface NSSound ()
- (BOOL)fn_prepareWithBytes:(const void *)bytes length:(NSUInteger)length;
- (void)fn_disposeQueue;
@end

static void fn_sound_finished(void *userData, AudioQueueRef queue, AudioQueueBufferRef buffer)
{
	NSSound *sound = (NSSound *)userData;

	(void)buffer;

	if ([sound loops]) {
		AudioQueueEnqueueBuffer(queue, buffer, 0, NULL);
		return;
	}

	sound->_playing = NO;

	{
		id delegate = sound->_delegate;

		if ([delegate respondsToSelector:@selector(sound:didFinishPlaying:)]) {
			[delegate sound:sound didFinishPlaying:YES];
		}
	}
}

@implementation NSSound

+ (NSArray *)soundUnfilteredFileTypes
{
	return [NSArray arrayWithObjects:@"wav", @"aif", @"aiff", @"caf", nil];
}

+ (NSArray *)soundUnfilteredTypes
{
	/* The UTI spellings of the same three containers. */
	return [NSArray arrayWithObjects:@"com.microsoft.waveform-audio", @"public.aiff-audio",
	                                 @"com.apple.coreaudio-format", nil];
}

- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		_volume = 1.0f;
	}
	return self;
}

- (instancetype)initWithContentsOfFile:(NSString *)path byReference:(BOOL)byReference
{
	NSData *data;

	(void)byReference;	/* every sound is read whole: a file that changes under a playing sound is not a case
	                     * worth the machinery a reference would need. */

	if (path == nil) {
		return nil;
	}

	data = [NSData dataWithContentsOfFile:path];
	if (data == nil) {
		return nil;
	}

	self = [self initWithData:data];
	if (self != nil && _name == nil) {
		[self setName:[path lastPathComponent]];
	}

	return self;
}

- (instancetype)initWithContentsOfURL:(NSURL *)url byReference:(BOOL)byReference
{
	if (url == nil || ![url isFileURL]) {
		return nil;
	}

	return [self initWithContentsOfFile:[url path] byReference:byReference];
}

- (instancetype)initWithData:(NSData *)data
{
	self = [self init];
	if (self == nil) {
		return nil;
	}

	if (data == nil || ![self fn_prepareWithBytes:[data bytes] length:[data length]]) {
		return nil;
	}

	_data = [data retain];
	return self;
}

+ (instancetype)soundNamed:(NSString *)name
{
	NSString *path;

	if (name == nil) {
		return nil;
	}

	/* The application bundle first, which is where a sound a nib names actually lives. */
	path = [[NSBundle mainBundle] pathForSoundResource:name];
	if (path == nil) {
		return nil;
	}

	return [[[self alloc] initWithContentsOfFile:path byReference:NO] autorelease];
}

/* Read the header through `AudioFile`, without keeping a file open: the bytes are already in memory, so the
 * callbacks door is the right one — it is `AudioFile.h`'s own answer for "my audio is a buffer". */
static OSStatus fn_data_read(void *client, SInt64 position, UInt32 requestCount, void *buffer, UInt32 *actual)
{
	NSData *data = (NSData *)client;
	NSUInteger length = [data length];

	*actual = 0;
	if (position < 0 || (NSUInteger)position >= length) {
		return 0;
	}

	{
		NSUInteger available = length - (NSUInteger)position;
		UInt32 count = requestCount < available ? requestCount : (UInt32)available;

		memcpy(buffer, (const uint8_t *)[data bytes] + position, count);
		*actual = count;
	}

	return 0;
}

static SInt64 fn_data_size(void *client)
{
	return (SInt64)[(NSData *)client length];
}

- (BOOL)fn_prepareWithBytes:(const void *)bytes length:(NSUInteger)length
{
	NSData *data = [NSData dataWithBytes:bytes length:length];
	AudioFileID file = NULL;
	OSStatus status;
	UInt32 size;

	status = AudioFileOpenWithCallbacks((__bridge void *)data, fn_data_read, NULL, fn_data_size, NULL, 0, &file);
	if (status != 0) {
		return NO;
	}

	size = (UInt32)sizeof(AudioStreamBasicDescription);
	status = AudioFileGetProperty(file, kAudioFilePropertyDataFormat, &size, _formatStorage);
	if (status != 0) {
		AudioFileClose(file);
		return NO;
	}

	{
		Float64 duration = 0.0;

		size = sizeof(duration);
		if (AudioFileGetProperty(file, kAudioFilePropertyEstimatedDuration, &size, &duration) == 0) {
			_duration = duration;
		}
	}

	AudioFileClose(file);
	return YES;
}

- (void)fn_disposeQueue
{
	if (_queue != NULL) {
		AudioQueueDispose((AudioQueueRef)_queue, true);
		_queue = NULL;
		_buffer = NULL;
	}
}

- (NSString *)name
{
	return _name;
}

- (void)setName:(NSString *)name
{
	if (_name != name) {
		[_name release];
		_name = [name copy];
	}
}

- (BOOL)play
{
	AudioQueueRef queue = (AudioQueueRef)_queue;
	OSStatus status;

	if (_data == nil) {
		return NO;
	}

	if (_playing) {
		return YES;	/* already playing: a second click does not restart it */
	}

	if (queue == NULL) {
		status = AudioQueueNewOutput((const AudioStreamBasicDescription *)_formatStorage, fn_sound_finished,
		                             (void *)self, NULL, NULL, 0, &queue);
		if (status != 0) {
			return NO;
		}
		_queue = queue;
	}

	if (_buffer == NULL) {
		AudioQueueBufferRef buffer = NULL;

		status = AudioQueueAllocateBuffer(queue, (UInt32)[_data length], &buffer);
		if (status != 0) {
			return NO;
		}

		memcpy(buffer->mAudioData, [_data bytes], [_data length]);
		buffer->mAudioDataByteSize = (UInt32)[_data length];

		status = AudioQueueEnqueueBuffer(queue, buffer, 0, NULL);
		if (status != 0) {
			AudioQueueFreeBuffer(queue, buffer);
			return NO;
		}

		_buffer = buffer;
	}

	if (_paused) {
		status = AudioQueueStart(queue, NULL);
	} else {
		status = AudioQueueStart(queue, NULL);
	}

	if (status != 0) {
		return NO;
	}

	AudioQueueSetParameter(queue, kAudioQueueParam_Volume, _volume);
	_playing = YES;
	_paused = NO;

	return YES;
}

- (BOOL)stop
{
	if (_queue != NULL) {
		AudioQueueStop((AudioQueueRef)_queue, true);
		AudioQueueReset((AudioQueueRef)_queue);
	}

	_playing = NO;
	_paused = NO;

	return YES;
}

- (BOOL)pause
{
	if (_queue == NULL || !_playing) {
		return NO;
	}

	AudioQueuePause((AudioQueueRef)_queue);
	_playing = NO;
	_paused = YES;

	return YES;
}

- (BOOL)resume
{
	if (_queue == NULL || !_paused) {
		return NO;
	}

	if (AudioQueueStart((AudioQueueRef)_queue, NULL) != 0) {
		return NO;
	}

	_playing = YES;
	_paused = NO;

	return YES;
}

- (BOOL)isPlaying
{
	return _playing;
}

- (BOOL)loops
{
	return _loops;
}

- (void)setLoops:(BOOL)loops
{
	_loops = loops;
}

- (float)volume
{
	return _volume;
}

- (void)setVolume:(float)volume
{
	if (volume < 0.0f) { volume = 0.0f; }
	if (volume > 1.0f) { volume = 1.0f; }
	_volume = volume;

	if (_queue != NULL) {
		AudioQueueSetParameter((AudioQueueRef)_queue, kAudioQueueParam_Volume, volume);
	}
}

- (NSTimeInterval)duration
{
	return _duration;
}

- (id)delegate
{
	return _delegate;
}

- (void)setDelegate:(id)delegate
{
	_delegate = delegate;
}

- (id)copyWithZone:(NSZone *)zone
{
	NSSound *copy = [[NSSound allocWithZone:zone] initWithData:_data];

	if (copy != nil) {
		[copy setName:_name];
		[copy setVolume:_volume];
		[copy setLoops:_loops];
		[copy setDelegate:_delegate];
	}

	return copy;
}

- (void)dealloc
{
	[self fn_disposeQueue];
	[_data release];
	[_name release];
	[super dealloc];
}

@end
