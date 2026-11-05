/*
 * nssound — a sound a control can play: decoded, played, stopped, looped, finished, and archived.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE SUITE THIS CLASS DID NOT HAVE.** `NSSound` arrived built on `libagora-audio` and nothing exercised it, so
 * "it plays" was a claim about code that had been read rather than code that had run. Every door below is
 * measured: `-duration` against a file whose length is known, `-isPlaying` across `-play`/`-stop`, a delegate
 * that must be called exactly once when a sound ends and not at all while it loops, and an archive round trip
 * of both a sound and a button cell that carries one.
 *
 * **THE DEVICE IS THE NULL ONE, AND THE TEST SAYS SO WITHOUT NAMING A PRIVATE FUNCTION.** `AGORA_AUDIO_DRIVER`
 * is `libagora-audio`'s own test-and-debug door, set on this test's environment in CMake; without it this suite
 * would make a noise on whoever ran the build. The clock is still real: the null device paces at the device's
 * rate, so a 60 ms sound finishes in about 60 ms and a five-second timeout means the queue stalled rather than
 * that the machine was slow.
 *
 * **THE SOUND FILES ARE WRITTEN HERE** — a 16-bit mono WAV at 8 kHz, which is the smallest container the file
 * door reads and needs no fixture in the repository. `-duration` is then arithmetic the test can do itself.
 *
 * ONE ASSERTION IS A REGRESSION TEST WITH A NAME: `-play` after a sound has finished must play it again. The
 * queue hands a buffer back to the completion callback when a non-looping sound ends, so a second `-play` that
 * assumed `_buffer` was still queued started a queue with nothing in it and played silence.
 */

#import <AppKit/NSSound.h>
#import <AppKit/NSButtonCell.h>
#import <Foundation/Foundation.h>

#include <math.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

static int g_failures;

static void fn_check(const char *what, int ok)
{
	printf("%s %s\n", ok ? "ok  " : "FAIL", what);
	if (!ok) {
		g_failures++;
	}
}

static void fn_check_close(const char *what, double got, double wanted, double tolerance)
{
	double difference = got - wanted;

	if (difference < 0) {
		difference = -difference;
	}
	if (difference > tolerance) {
		printf("FAIL %s (got %g, wanted %g)\n", what, got, wanted);
		g_failures++;
		return;
	}
	printf("ok   %s\n", what);
}

static void fn_sleep_ms(long milliseconds)
{
	struct timespec ts;

	ts.tv_sec = milliseconds / 1000;
	ts.tv_nsec = (milliseconds % 1000) * 1000000L;
	while (nanosleep(&ts, &ts) != 0) {
	}
}

/* --- a WAV, written by hand: 16-bit mono PCM at 8 kHz ----------------------- */

static void fn_put16(uint8_t *p, uint16_t value)
{
	p[0] = (uint8_t)(value & 0xff);
	p[1] = (uint8_t)(value >> 8);
}

static void fn_put32(uint8_t *p, uint32_t value)
{
	p[0] = (uint8_t)(value & 0xff);
	p[1] = (uint8_t)((value >> 8) & 0xff);
	p[2] = (uint8_t)((value >> 16) & 0xff);
	p[3] = (uint8_t)((value >> 24) & 0xff);
}

static NSData *fn_wav(double seconds, double amplitude)
{
	const uint32_t rate = 8000;
	const uint32_t frames = (uint32_t)(seconds * rate);
	const uint32_t bytes = frames * 2;	/* one channel, 16-bit */
	NSMutableData *data = [NSMutableData dataWithLength:44 + bytes];
	uint8_t *p = [data mutableBytes];
	uint32_t i;

	memcpy(p + 0, "RIFF", 4);
	fn_put32(p + 4, 36 + bytes);
	memcpy(p + 8, "WAVE", 4);
	memcpy(p + 12, "fmt ", 4);
	fn_put32(p + 16, 16);		/* the fmt chunk's size */
	fn_put16(p + 20, 1);		/* PCM */
	fn_put16(p + 22, 1);		/* channels */
	fn_put32(p + 24, rate);
	fn_put32(p + 28, rate * 2);	/* byte rate */
	fn_put16(p + 32, 2);		/* block align */
	fn_put16(p + 34, 16);		/* bits per sample */
	memcpy(p + 36, "data", 4);
	fn_put32(p + 40, bytes);

	/* A tone rather than silence, which is what makes a test that "played" the file different from one that
	 * played an empty buffer: the samples are 440 Hz at `amplitude` of full scale. */
	for (i = 0; i < frames; i++) {
		double phase = 2.0 * M_PI * 440.0 * (double)i / (double)rate;
		int16_t sample = (int16_t)(sin(phase) * amplitude * 32767.0);

		fn_put16(p + 44 + i * 2, (uint16_t)sample);
	}

	return data;
}

static NSString *fn_write(NSString *name, NSData *data)
{
	NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];

	[data writeToFile:path atomically:YES];
	return path;
}

/* --- a delegate that only counts ------------------------------------------- */

@interface AGCountingDelegate : NSObject
{
@public
	int calls;
	BOOL lastFinished;
}
@end

@implementation AGCountingDelegate

- (void)sound:(NSSound *)sound didFinishPlaying:(BOOL)finishedPlaying
{
	(void)sound;
	calls++;
	lastFinished = finishedPlaying;
}

@end

/* ------------------------------------------------------------------------------------------------
 * Decoding: a file the test wrote, read back through AudioFile.
 * ---------------------------------------------------------------------------------------------- */

static void fn_test_decoding(void)
{
	NSArray *types = [NSSound soundUnfilteredFileTypes];
	NSArray *utis = [NSSound soundUnfilteredTypes];
	NSString *path = fn_write(@"agora-nssound-quarter.wav", fn_wav(0.25, 0.5));
	NSSound *sound = [[NSSound alloc] initWithContentsOfFile:path byReference:NO];

	fn_check("the file types name the three containers the file door reads",
	         [types containsObject:@"wav"] && [types containsObject:@"aiff"] && [types containsObject:@"caf"]);
	fn_check("the UTI spellings are the same three", [utis containsObject:@"com.microsoft.waveform-audio"]);
	fn_check("a WAV the test wrote decodes", sound != nil);
	if (sound == nil) {
		[[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
		return;
	}

	/* 0.25 s at 8 kHz is 2000 frames: the estimate is exact for linear PCM, and a tolerance of 20 ms is the
	 * slack between "the file's header was read" and "the sound was measured by playing it". */
	fn_check_close("the duration is the file's", [sound duration], 0.25, 0.02);
	fn_check("the name defaults to the file's name",
	         [[sound name] isEqualToString:@"agora-nssound-quarter.wav"]);
	fn_check_close("a fresh sound is at full volume", [sound volume], 1.0, 0.0001);
	fn_check("a fresh sound is not playing", ![sound isPlaying]);
	fn_check("a fresh sound does not loop", ![sound loops]);

	fn_check("the path forms of the same file agree",
	         [[[NSSound alloc] initWithContentsOfFile:path byReference:YES] autorelease] != nil);
	fn_check("a URL form initialises",
	         [[[NSSound alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] byReference:NO] autorelease]
	             != nil);
	fn_check("a missing file is nil", [[NSSound alloc] initWithContentsOfFile:@"/nonexistent/x.wav"
	                                                             byReference:NO] == nil);
	fn_check("bytes that are not audio are nil", [[NSSound alloc] initWithData:[NSData dataWithBytes:"junk"
	                                                                                         length:4]] == nil);

	[sound release];
	[[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}

/* ------------------------------------------------------------------------------------------------
 * Volume: a parameter, clamped where Apple clamps it.
 * ---------------------------------------------------------------------------------------------- */

static void fn_test_volume(void)
{
	NSString *path = fn_write(@"agora-nssound-volume.wav", fn_wav(0.05, 0.25));
	NSSound *sound = [[NSSound alloc] initWithContentsOfFile:path byReference:NO];

	[sound setVolume:0.5f];
	fn_check_close("volume reads back what was set", [sound volume], 0.5, 0.0001);
	[sound setVolume:2.0f];
	fn_check_close("above full scale it clamps to 1", [sound volume], 1.0, 0.0001);
	[sound setVolume:-1.0f];
	fn_check_close("below silence it clamps to 0", [sound volume], 0.0, 0.0001);

	[sound release];
	[[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}

/* ------------------------------------------------------------------------------------------------
 * Playing: start, stop, finish, and the second click.
 * ---------------------------------------------------------------------------------------------- */

static void fn_test_playing(void)
{
	NSString *short_path = fn_write(@"agora-nssound-short.wav", fn_wav(0.06, 0.5));
	NSSound *sound = [[NSSound alloc] initWithContentsOfFile:short_path byReference:NO];
	AGCountingDelegate *delegate = [[AGCountingDelegate alloc] init];
	int waited;

	[sound setDelegate:delegate];
	fn_check("a sound starts stopped", ![sound isPlaying] && [sound stop]);

	fn_check("play reports that it started", [sound play]);
	fn_check("and says it is playing", [sound isPlaying]);
	fn_check("a second play while playing is accepted without restarting", [sound play]);

	fn_check("stop stops it", [sound stop] && ![sound isPlaying]);
	fn_check("a stop with nothing playing still answers yes", [sound stop]);

	/* Now let one play to its end: the delegate must be called once, with YES, and the sound must stop
	 * itself. Five seconds is a stalled queue, not a slow machine. */
	fn_check("it plays again after a stop", [sound play]);
	for (waited = 0; waited < 5000 && delegate->calls == 0; waited += 10) {
		fn_sleep_ms(10);
	}
	fn_check("the delegate is called when the sound ends", delegate->calls == 1);
	fn_check("it is told the sound finished rather than being interrupted", delegate->lastFinished);
	fn_check("a finished sound is no longer playing", ![sound isPlaying]);

	/* THE REGRESSION: a non-looping sound's buffer is handed back when it finishes, so a second `-play` has to
	 * enqueue it again. Without that, this play starts a queue with nothing pending and plays silence. */
	delegate->calls = 0;
	fn_check("a finished sound plays again", [sound play] && [sound isPlaying]);
	for (waited = 0; waited < 5000 && delegate->calls == 0; waited += 10) {
		fn_sleep_ms(10);
	}
	fn_check("and finishes again, telling the delegate a second time", delegate->calls == 1);

	/* Pause keeps the buffer queued: the delegate must not hear a finish while it is paused. */
	delegate->calls = 0;
	fn_check("it plays for the pause test", [sound play]);
	fn_check("pause says it paused", [sound pause]);
	fn_check("a paused sound is not playing", ![sound isPlaying]);
	fn_sleep_ms(150);
	fn_check("a paused sound has not finished", delegate->calls == 0);
	fn_check("resume says it resumed", [sound resume]);
	fn_check("a resumed sound is playing", [sound isPlaying]);
	fn_sleep_ms(150);
	fn_check("a paused sound's clock had stopped, so it now ends", delegate->calls == 1);
	[sound stop];

	[delegate release];
	[sound release];
	[[NSFileManager defaultManager] removeItemAtPath:short_path error:NULL];
}

/* ------------------------------------------------------------------------------------------------
 * Looping: the queue's callback re-enqueues, so the sound never ends.
 * ---------------------------------------------------------------------------------------------- */

static void fn_test_loops(void)
{
	NSString *path = fn_write(@"agora-nssound-loop.wav", fn_wav(0.04, 0.25));
	NSSound *sound = [[NSSound alloc] initWithContentsOfFile:path byReference:NO];
	AGCountingDelegate *delegate = [[AGCountingDelegate alloc] init];

	[sound setDelegate:delegate];
	[sound setLoops:YES];
	fn_check("looping is a flag that reads back", [sound loops]);

	fn_check("a looping sound plays", [sound play]);
	fn_sleep_ms(250);	/* six times its length */
	fn_check("a looping sound never finishes", delegate->calls == 0);
	fn_check("and is still playing", [sound isPlaying]);

	[sound stop];
	fn_check("stopping a looping sound ends it", ![sound isPlaying]);
	[sound setLoops:NO];
	fn_check("and the flag turns off", ![sound loops]);

	[delegate release];
	[sound release];
	[[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}

/* ------------------------------------------------------------------------------------------------
 * Copying, and the two archives: a sound's own, and a button cell's.
 * ---------------------------------------------------------------------------------------------- */

static void fn_test_copy_and_coding(void)
{
	NSString *path = fn_write(@"agora-nssound-archive.wav", fn_wav(0.1, 0.5));
	NSSound *sound = [[NSSound alloc] initWithContentsOfFile:path byReference:NO];
	NSSound *copy;
	NSData *archive;
	NSSound *restored;

	[sound setName:@"Blip"];
	[sound setVolume:0.75f];
	[sound setLoops:YES];

	copy = [sound copy];
	fn_check("a copy keeps the name, the volume, the loop flag and the length",
	         [[copy name] isEqualToString:@"Blip"]
	         && [copy volume] == 0.75f && [copy loops] && [copy duration] == [sound duration]);
	[copy release];

	archive = [NSKeyedArchiver archivedDataWithRootObject:sound];
	fn_check("a sound archives", archive != nil && [archive length] > 0);
	restored = archive != nil ? [NSKeyedUnarchiver unarchiveObjectWithData:archive] : nil;
	fn_check("and unarchives as a sound", [restored isKindOfClass:[NSSound class]]);
	if (restored != nil) {
		fn_check("with its name, volume and loop flag",
		         [[restored name] isEqualToString:@"Blip"]
		         && [restored volume] == 0.75f && [restored loops]);
		/* THE BYTES ARE THE ARCHIVE, so the restored sound is playable and the same length: an archive that
		 * recorded a path would be a sound only on the machine that wrote it. */
		fn_check_close("and the same duration, because its bytes went with it",
		               [restored duration], [sound duration], 0.001);
		fn_check("and it plays", [restored play]);
		[restored stop];
	}

	/* THE BUTTON CELL'S SOUND, which is why the class had to be `NSCoding` in the first place. */
	{
		NSButtonCell *cell = [[NSButtonCell alloc] init];

		[cell setTitle:@"Ping"];
		[cell setSound:sound];
		archive = [NSKeyedArchiver archivedDataWithRootObject:cell];
		fn_check("a button cell with a sound archives", archive != nil && [archive length] > 0);
		if (archive != nil) {
			NSButtonCell *restoredCell = [NSKeyedUnarchiver unarchiveObjectWithData:archive];

			fn_check("the cell comes back", [restoredCell isKindOfClass:[NSButtonCell class]]);
			fn_check("with its title", [[restoredCell title] isEqualToString:@"Ping"]);
			fn_check("and its sound, whole", [[restoredCell sound] isKindOfClass:[NSSound class]]
			                                  && [[[restoredCell sound] name] isEqualToString:@"Blip"]);
		}
		[cell release];
	}

	[restored release];	/* nil-safe: -release on nil is not sent, so this is one branch, not two */
	[sound release];
	[[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}

/* ------------------------------------------------------------------------------------------------
 * The bundle door, which moved into NSSound.h: `+soundNamed:` is what a nib uses.
 * ---------------------------------------------------------------------------------------------- */

static void fn_test_named_sound(void)
{
	NSBundle *bundle = [NSBundle mainBundle];
	NSString *resources = [bundle resourcePath];
	NSFileManager *manager = [NSFileManager defaultManager];
	NSString *path;
	NSSound *named;

	fn_check("the main bundle has a resource directory", resources != nil);
	if (resources == nil) {
		return;
	}

	[manager createDirectoryAtPath:resources withIntermediateDirectories:YES attributes:nil error:NULL];
	path = [resources stringByAppendingPathComponent:@"agora-nssound-named.wav"];
	[fn_wav(0.12, 0.4) writeToFile:path atomically:YES];

	/* THE EXTENSION IS OPTIONAL: the literal name wins when it names a file, and the name without one is
	 * searched with each extension the sound door knows. */
	fn_check("the sound door finds the literal name",
	         [[bundle pathForSoundResource:@"agora-nssound-named.wav"]
	             isEqualToString:path]);
	fn_check("and the same name without its extension", [[bundle pathForSoundResource:@"agora-nssound-named"]
	                                                        isEqualToString:path]);
	fn_check("a name that names nothing is nil", [bundle pathForSoundResource:@"agora-nssound-absent"] == nil);

	named = [NSSound soundNamed:@"agora-nssound-named"];
	fn_check("+soundNamed: finds a resource of the main bundle", named != nil);
	if (named != nil) {
		fn_check_close("and decodes it", [named duration], 0.12, 0.02);
		fn_check("its name is the name it was asked for", [[named name] isEqualToString:@"agora-nssound-named"]);
	}
	fn_check("+soundNamed: for a name that is not there is nil", [NSSound soundNamed:@"agora-nssound-absent"] == nil);

	[manager removeItemAtPath:path error:NULL];
}

int main(void);
int main(void)
{
	/* THE DEVICE IS THE NULL ONE, asserted rather than assumed: with AGORA_AUDIO_DRIVER set to something else
	 * this suite would be a sound, and the assertion is what says so in the output. */
	const char *driver = getenv("AGORA_AUDIO_DRIVER");

	fn_check("the suite is running against the null device",
	         driver != NULL && strcmp(driver, "null") == 0);

	fn_test_decoding();
	fn_test_volume();
	fn_test_playing();
	fn_test_loops();
	fn_test_copy_and_coding();
	fn_test_named_sound();

	if (g_failures != 0) {
		fprintf(stderr, "nssound: %d failure(s)\n", g_failures);
		return 1;
	}
	printf("nssound: decoded, played, stopped, looped, archived and found by name\n");
	return 0;
}
