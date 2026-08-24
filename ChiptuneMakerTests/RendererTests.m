#import <XCTest/XCTest.h>
#import <math.h>
#import "ChipRenderer.h"
#import "ChipSynth.h"
#import "Song.h"
#import "Track.h"
#import "NoteEvent.h"

@interface RendererTests : XCTestCase
@end

@implementation RendererTests

- (Song *)singleNoteSong {
    Song *song = [Song defaultSong];
    song.lengthBars = 2;
    [song.tracks[0].notes addObject:[NoteEvent noteWithPitch:69 startTick:0 durationTicks:960 velocity:110]];
    return song;
}

- (Song *)songWithPitch:(NSInteger)pitch tempo:(double)tempo {
    Song *song = [Song defaultSong];
    song.lengthBars = 2;
    song.tempo = tempo;
    for (Track *track in song.tracks) {
        [track.notes removeAllObjects];
    }
    Track *lead = song.tracks[0];
    lead.volume = 1.0;
    lead.pan = 0.0;
    lead.vibratoDepth = 0.0;
    [lead.notes addObject:[NoteEvent noteWithPitch:pitch startTick:0 durationTicks:960 velocity:127]];
    return song;
}

- (ChipRenderer *)rendererForSong:(Song *)song {
    ChipRenderer *renderer = [[ChipRenderer alloc] initWithSampleRate:44100.0];
    [renderer prepareWithSong:song];
    renderer.playing = YES;
    return renderer;
}

static NSUInteger ZeroCrossingCount(const float *samples, NSUInteger count) {
    NSUInteger crossings = 0;
    for (NSUInteger i = 1; i < count; i++) {
        if ((samples[i - 1] < 0.0f && samples[i] >= 0.0f) ||
            (samples[i - 1] >= 0.0f && samples[i] < 0.0f)) {
            crossings++;
        }
    }
    return crossings;
}

- (void)testRendererProducesFiniteAudio {
    Song *song = [self singleNoteSong];
    ChipRenderer *renderer = [[ChipRenderer alloc] initWithSampleRate:44100.0];
    [renderer prepareWithSong:song];
    renderer.playing = YES;

    float left[512];
    float right[512];
    float peak = 0.0f;
    for (NSInteger block = 0; block < 8; block++) {
        [renderer renderFrames:512 left:left right:right];
        for (NSInteger i = 0; i < 512; i++) {
            XCTAssertTrue(isfinite(left[i]));
            XCTAssertTrue(isfinite(right[i]));
            peak = MAX(peak, fabsf(left[i]));
            peak = MAX(peak, fabsf(right[i]));
        }
    }
    XCTAssertGreaterThan(peak, 0.0001f);
}

- (void)testRendererIsDeterministic {
    Song *song = [self singleNoteSong];
    ChipRenderer *a = [[ChipRenderer alloc] initWithSampleRate:44100.0];
    ChipRenderer *b = [[ChipRenderer alloc] initWithSampleRate:44100.0];
    [a prepareWithSong:song];
    [b prepareWithSong:song];
    a.playing = YES;
    b.playing = YES;

    float leftA[2048], rightA[2048], leftB[2048], rightB[2048];
    [a renderFrames:2048 left:leftA right:rightA];
    [b renderFrames:2048 left:leftB right:rightB];
    XCTAssertEqual(memcmp(leftA, leftB, sizeof(leftA)), 0);
    XCTAssertEqual(memcmp(rightA, rightB, sizeof(rightA)), 0);
}

- (void)testPausedRendererIsSilent {
    Song *song = [self singleNoteSong];
    ChipRenderer *renderer = [[ChipRenderer alloc] initWithSampleRate:44100.0];
    [renderer prepareWithSong:song];
    renderer.playing = NO;
    float left[256], right[256];
    [renderer renderFrames:256 left:left right:right];
    for (NSInteger i = 0; i < 256; i++) {
        XCTAssertEqual(left[i], 0.0f);
        XCTAssertEqual(right[i], 0.0f);
    }
}

- (void)testVoiceFrequencyTracksMIDIPitch {
    Song *song = [self singleNoteSong];
    ChipRenderer *renderer = [[ChipRenderer alloc] initWithSampleRate:44100.0];
    [renderer prepareWithSong:song];
    renderer.playing = YES;
    float left[44100], right[44100];
    [renderer renderFrames:44100 left:left right:right];
    XCTAssertGreaterThan(renderer.masterPeak, 0.0f);
}

- (void)testDifferentPitchesRenderDifferentAudio {
    float lowLeft[8192], lowRight[8192], highLeft[8192], highRight[8192];
    ChipRenderer *low = [self rendererForSong:[self songWithPitch:60 tempo:120]];
    ChipRenderer *high = [self rendererForSong:[self songWithPitch:72 tempo:120]];

    [low renderFrames:8192 left:lowLeft right:lowRight];
    [high renderFrames:8192 left:highLeft right:highRight];

    XCTAssertNotEqual(memcmp(lowLeft, highLeft, sizeof(lowLeft)), 0,
                      @"A one-octave pitch change must change the rendered waveform");
    NSUInteger lowCrossings = ZeroCrossingCount(lowLeft, 8192);
    NSUInteger highCrossings = ZeroCrossingCount(highLeft, 8192);
    XCTAssertGreaterThan(highCrossings, lowCrossings * 3 / 2,
                         @"The higher note should oscillate roughly twice as fast");
}

- (void)testTransposeChangesRenderedAudio {
    Song *song = [self songWithPitch:60 tempo:120];
    Song *transposed = [song copy];
    [transposed transposePitchedNotesBySemitones:12];

    XCTAssertEqual(song.tracks[0].notes[0].pitch, 60);
    XCTAssertEqual(transposed.tracks[0].notes[0].pitch, 72);

    float originalLeft[8192], originalRight[8192], transposedLeft[8192], transposedRight[8192];
    ChipRenderer *originalRenderer = [self rendererForSong:song];
    ChipRenderer *transposedRenderer = [self rendererForSong:transposed];
    [originalRenderer renderFrames:8192 left:originalLeft right:originalRight];
    [transposedRenderer renderFrames:8192 left:transposedLeft right:transposedRight];

    XCTAssertNotEqual(memcmp(originalLeft, transposedLeft, sizeof(originalLeft)), 0,
                      @"Transposing the song must change what is heard");
}

- (void)testScaleQuantizationChangesRenderedAudio {
    Song *song = [self songWithPitch:61 tempo:120]; // C#
    Song *quantized = [song copy];
    [quantized quantizePitchedNotesToScale:MusicalScaleMajor root:0];

    XCTAssertEqual(song.tracks[0].notes[0].pitch, 61);
    XCTAssertEqual(quantized.tracks[0].notes[0].pitch, 60);

    float originalLeft[8192], originalRight[8192], quantizedLeft[8192], quantizedRight[8192];
    ChipRenderer *originalRenderer = [self rendererForSong:song];
    ChipRenderer *quantizedRenderer = [self rendererForSong:quantized];
    [originalRenderer renderFrames:8192 left:originalLeft right:originalRight];
    [quantizedRenderer renderFrames:8192 left:quantizedLeft right:quantizedRight];

    XCTAssertNotEqual(memcmp(originalLeft, quantizedLeft, sizeof(originalLeft)), 0,
                      @"Scale quantization must change what is heard");
}

- (void)testTempoChangeUpdatesPlaybackSpeedLive {
    Song *song = [self songWithPitch:69 tempo:120];
    ChipRenderer *renderer = [self rendererForSong:song];
    float left[4410], right[4410];

    [renderer renderFrames:4410 left:left right:right];
    double firstBlockTicks = renderer.currentTick;
    XCTAssertGreaterThan(firstBlockTicks, 0.0);

    [renderer updateTempo:240];
    [renderer renderFrames:4410 left:left right:right];
    double secondBlockTicks = renderer.currentTick - firstBlockTicks;

    XCTAssertEqualWithAccuracy(secondBlockTicks, firstBlockTicks * 2.0, 2.0,
                               @"Doubling tempo while playing should double tick progress");
}

- (void)testLiveInstrumentChangeAltersActiveVoice {
    Song *song = [self songWithPitch:69 tempo:120];
    ChipRenderer *changed = [self rendererForSong:song];
    ChipRenderer *control = [self rendererForSong:song];
    float left[1024], right[1024];

    [changed renderFrames:1024 left:left right:right];
    [control renderFrames:1024 left:left right:right];

    ChipInstrumentParams triangle = ChipInstrumentDefaultParams(ChipInstrumentTriangle);
    [changed setTrackInstrument:ChipInstrumentTriangle params:triangle atIndex:0];

    float changedLeft[2048], changedRight[2048], controlLeft[2048], controlRight[2048];
    [changed renderFrames:2048 left:changedLeft right:changedRight];
    [control renderFrames:2048 left:controlLeft right:controlRight];

    XCTAssertNotEqual(memcmp(changedLeft, controlLeft, sizeof(changedLeft)), 0,
                      @"Changing instrument should affect the currently sounding note");
}

- (void)testLiveVolumeChangeSilencesActiveVoice {
    Song *song = [self songWithPitch:69 tempo:120];
    ChipRenderer *renderer = [self rendererForSong:song];
    float left[1024], right[1024];

    [renderer renderFrames:1024 left:left right:right];
    XCTAssertGreaterThan(renderer.masterPeak, 0.0001f);

    [renderer setTrackVolume:0.0 atIndex:0];
    [renderer renderFrames:1024 left:left right:right];
    for (NSInteger i = 0; i < 1024; i++) {
        XCTAssertEqualWithAccuracy(left[i], 0.0f, 0.000001f);
        XCTAssertEqualWithAccuracy(right[i], 0.0f, 0.000001f);
    }
}

- (void)testLiveMuteSilencesActiveVoice {
    Song *song = [self songWithPitch:69 tempo:120];
    ChipRenderer *renderer = [self rendererForSong:song];
    float left[1024], right[1024];

    [renderer renderFrames:1024 left:left right:right];
    XCTAssertGreaterThan(renderer.masterPeak, 0.0001f);

    [renderer setTrackMuted:YES atIndex:0];
    [renderer renderFrames:1024 left:left right:right];
    for (NSInteger i = 0; i < 1024; i++) {
        XCTAssertEqualWithAccuracy(left[i], 0.0f, 0.000001f);
        XCTAssertEqualWithAccuracy(right[i], 0.0f, 0.000001f);
    }
}

- (void)testRendererStopsAtEndOfSong {
    Song *song = [self songWithPitch:69 tempo:300];
    ChipRenderer *renderer = [self rendererForSong:song];
    float left[512], right[512];

    NSUInteger blocks = 0;
    while (renderer.playing && blocks < 1000) {
        [renderer renderFrames:512 left:left right:right];
        blocks++;
    }

    XCTAssertFalse(renderer.playing, @"Playback should stop at the final tick");
    XCTAssertEqual(renderer.currentTick, (double)song.totalTicks);

    [renderer renderFrames:512 left:left right:right];
    for (NSInteger i = 0; i < 512; i++) {
        XCTAssertEqual(left[i], 0.0f);
        XCTAssertEqual(right[i], 0.0f);
    }
}

- (void)testLoopKeepsPlayingPastSongEnd {
    Song *song = [self songWithPitch:69 tempo:300];
    ChipRenderer *renderer = [self rendererForSong:song];
    renderer.loopEnabled = YES;
    renderer.loopStartTick = 0;
    renderer.loopEndTick = song.totalTicks;
    float left[512], right[512];

    for (NSUInteger block = 0; block < 300; block++) {
        [renderer renderFrames:512 left:left right:right];
    }

    XCTAssertTrue(renderer.playing, @"Looping playback should not stop at the song end");
    XCTAssertLessThanOrEqual(renderer.currentTick, (double)song.totalTicks);
}

- (void)testExportCanRenderReleaseTailPastSongEnd {
    Song *song = [self songWithPitch:69 tempo:300];
    ChipRenderer *renderer = [self rendererForSong:song];
    renderer.stopsAtSongEnd = NO;
    float left[512], right[512];

    for (NSUInteger block = 0; block < 200; block++) {
        [renderer renderFrames:512 left:left right:right];
    }

    XCTAssertTrue(renderer.playing, @"Export rendering should continue past the final tick for the release tail");
    XCTAssertGreaterThan(renderer.currentTick, (double)song.totalTicks);
}

@end
