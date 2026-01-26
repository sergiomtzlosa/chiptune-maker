#import <XCTest/XCTest.h>
#import "ExportService.h"
#import "LSDjExporter.h"
#import "Song.h"
#import "Track.h"
#import "SongSection.h"
#import "NoteEvent.h"

#include "lsdj/project.h"
#include "lsdj/song.h"
#include "lsdj/phrase.h"
#include "lsdj/chain.h"
#include "lsdj/instrument.h"
#include <string.h>

@interface ExportTests : XCTestCase
@end

@implementation ExportTests

- (Song *)shortSong {
    Song *song = [Song defaultSong];
    song.title = @"Export Test";
    song.lengthBars = 1;
    song.tempo = 160;
    song.sections = [@[[SongSection sectionWithName:@"Main" startBar:0 lengthBars:1]] mutableCopy];
    [song.tracks[0].notes addObject:[NoteEvent noteWithPitch:69 startTick:0 durationTicks:240 velocity:100]];
    [song.tracks[2].notes addObject:[NoteEvent noteWithPitch:36 startTick:0 durationTicks:480 velocity:110]];
    return song;
}

- (NSURL *)temporaryURLWithExtension:(NSString *)extension {
    NSString *name = [NSString stringWithFormat:@"chiptune-test-%@.%@", [[NSUUID UUID] UUIDString], extension];
    return [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
}

- (void)exportSong:(Song *)song toURL:(NSURL *)url format:(ExportFormat)format completion:(void (^)(NSError *error))completion {
    ExportOptions *options = [ExportOptions defaultOptions];
    options.format = format;
    options.normalize = YES;
    [ExportService exportSong:song toURL:url options:options progress:nil completion:completion];
}

- (void)testFLACExport {
    Song *song = [self shortSong];
    NSURL *url = [self temporaryURLWithExtension:@"flac"];
    XCTestExpectation *expectation = [self expectationWithDescription:@"FLAC export"];
    [self exportSong:song toURL:url format:ExportFormatFLAC completion:^(NSError *error) {
        XCTAssertNil(error);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:90 handler:nil];
    NSData *data = [NSData dataWithContentsOfURL:url];
    XCTAssertNotNil(data);
    XCTAssertGreaterThan(data.length, 1000);
    if (data.length >= 4) {
        XCTAssertEqual(memcmp(data.bytes, "fLaC", 4), 0);
    }
    [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
}

- (void)testWAVExport {
    Song *song = [self shortSong];
    NSURL *url = [self temporaryURLWithExtension:@"wav"];
    XCTestExpectation *expectation = [self expectationWithDescription:@"WAV export"];
    [self exportSong:song toURL:url format:ExportFormatWAV completion:^(NSError *error) {
        XCTAssertNil(error);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:60 handler:nil];
    NSData *data = [NSData dataWithContentsOfURL:url];
    XCTAssertNotNil(data);
    XCTAssertGreaterThan(data.length, 1000);
    if (data.length >= 4) {
        XCTAssertEqual(memcmp(data.bytes, "RIFF", 4), 0);
    }
    [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
}

- (void)testMIDIExport {
    Song *song = [self shortSong];
    NSURL *url = [self temporaryURLWithExtension:@"mid"];
    XCTestExpectation *expectation = [self expectationWithDescription:@"MIDI export"];
    [self exportSong:song toURL:url format:ExportFormatMIDI completion:^(NSError *error) {
        XCTAssertNil(error);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:30 handler:nil];
    NSData *data = [NSData dataWithContentsOfURL:url];
    XCTAssertNotNil(data);
    XCTAssertGreaterThan(data.length, 30);
    if (data.length >= 4) {
        XCTAssertEqual(memcmp(data.bytes, "MThd", 4), 0);
    }
    [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
}

- (void)testMP3ExportWhenLAMEIsAvailable {
    if ([ExportService lameExecutablePath] == nil) {
        XCTSkip(@"LAME is not installed; skipping MP3 export test.");
    }
    Song *song = [self shortSong];
    NSURL *url = [self temporaryURLWithExtension:@"mp3"];
    XCTestExpectation *expectation = [self expectationWithDescription:@"MP3 export"];
    [self exportSong:song toURL:url format:ExportFormatMP3 completion:^(NSError *error) {
        XCTAssertNil(error);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:90 handler:nil];
    NSData *data = [NSData dataWithContentsOfURL:url];
    XCTAssertNotNil(data);
    XCTAssertGreaterThan(data.length, 1000);
    [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
}

- (NSData *)lsdjDataForSong:(Song *)song {
    NSError *error = nil;
    NSData *data = [LSDjExporter dataForSong:song audibleOnly:YES error:&error];
    XCTAssertNotNil(data, @"LSDj export failed: %@", error.localizedDescription);
    XCTAssertNil(error);
    return data;
}

- (lsdj_project_t *)readLSDjProject:(NSData *)data {
    lsdj_project_t *project = NULL;
    lsdj_error_t result = lsdj_project_read_lsdsng_from_memory(data.bytes, data.length, &project, NULL);
    XCTAssertEqual(result, LSDJ_SUCCESS);
    return result == LSDJ_SUCCESS ? project : NULL;
}

- (void)testLSDjExport {
    Song *song = [self shortSong];
    NSURL *url = [self temporaryURLWithExtension:@"lsdsng"];
    XCTestExpectation *expectation = [self expectationWithDescription:@"LSDj export"];
    [self exportSong:song toURL:url format:ExportFormatLSDj completion:^(NSError *error) {
        XCTAssertNil(error);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:30 handler:nil];

    NSData *data = [NSData dataWithContentsOfURL:url];
    XCTAssertNotNil(data);
    XCTAssertGreaterThan(data.length, 9);
    XCTAssertTrue(lsdj_project_is_likely_valid_lsdsng_memory(data.bytes, data.length));

    lsdj_project_t *project = [self readLSDjProject:data];
    if (!project) {
        [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
        return;
    }

    lsdj_song_t *lsdjSong = lsdj_project_get_song(project);
    XCTAssertEqual(lsdj_project_get_name_length(project), (size_t)8);
    XCTAssertEqual(memcmp(lsdj_project_get_name(project), "EXPORT T", 8), 0);
    XCTAssertEqual(lsdj_project_get_version(project), 0);
    XCTAssertEqual(lsdj_song_get_format_version(lsdjSong), 7);
    XCTAssertEqual(lsdj_song_get_tempo(lsdjSong), 160);

    XCTAssertEqual(lsdj_row_get_chain(lsdjSong, 0, LSDJ_CHANNEL_PULSE1), 0);
    XCTAssertEqual(lsdj_row_get_chain(lsdjSong, 0, LSDJ_CHANNEL_PULSE2), LSDJ_SONG_NO_CHAIN);
    XCTAssertEqual(lsdj_row_get_chain(lsdjSong, 0, LSDJ_CHANNEL_WAVE), 1);
    XCTAssertEqual(lsdj_row_get_chain(lsdjSong, 0, LSDJ_CHANNEL_NOISE), LSDJ_SONG_NO_CHAIN);

    XCTAssertTrue(lsdj_chain_is_allocated(lsdjSong, 0));
    XCTAssertTrue(lsdj_chain_is_allocated(lsdjSong, 1));
    XCTAssertFalse(lsdj_chain_is_allocated(lsdjSong, 2));
    XCTAssertEqual(lsdj_chain_get_phrase(lsdjSong, 0, 0), 0);
    XCTAssertEqual(lsdj_chain_get_phrase(lsdjSong, 1, 0), 1);
    for (uint8_t step = 1; step < LSDJ_CHAIN_LENGTH; step++) {
        XCTAssertEqual(lsdj_chain_get_phrase(lsdjSong, 0, step), LSDJ_CHAIN_NO_PHRASE);
        XCTAssertEqual(lsdj_chain_get_phrase(lsdjSong, 1, step), LSDJ_CHAIN_NO_PHRASE);
    }

    XCTAssertTrue(lsdj_phrase_is_allocated(lsdjSong, 0));
    XCTAssertTrue(lsdj_phrase_is_allocated(lsdjSong, 1));
    XCTAssertFalse(lsdj_phrase_is_allocated(lsdjSong, 2));
    XCTAssertEqual(lsdj_phrase_get_note(lsdjSong, 0, 0), 34);
    XCTAssertEqual(lsdj_phrase_get_instrument(lsdjSong, 0, 0), 0);
    XCTAssertEqual(lsdj_phrase_get_note(lsdjSong, 1, 0), 1);
    XCTAssertEqual(lsdj_phrase_get_instrument(lsdjSong, 1, 0), 2);
    for (uint8_t step = 1; step < LSDJ_PHRASE_LENGTH; step++) {
        XCTAssertEqual(lsdj_phrase_get_note(lsdjSong, 0, step), LSDJ_PHRASE_NO_NOTE);
        XCTAssertEqual(lsdj_phrase_get_instrument(lsdjSong, 0, step), LSDJ_PHRASE_NO_INSTRUMENT);
        XCTAssertEqual(lsdj_phrase_get_note(lsdjSong, 1, step), LSDJ_PHRASE_NO_NOTE);
        XCTAssertEqual(lsdj_phrase_get_instrument(lsdjSong, 1, step), LSDJ_PHRASE_NO_INSTRUMENT);
    }

    for (uint8_t instrument = 0; instrument < 4; instrument++) {
        XCTAssertTrue(lsdj_instrument_is_allocated(lsdjSong, instrument));
    }
    XCTAssertFalse(lsdj_instrument_is_allocated(lsdjSong, 4));
    XCTAssertEqual(lsdj_instrument_get_type(lsdjSong, 0), LSDJ_INSTRUMENT_TYPE_PULSE);
    XCTAssertEqual(lsdj_instrument_get_type(lsdjSong, 1), LSDJ_INSTRUMENT_TYPE_PULSE);
    XCTAssertEqual(lsdj_instrument_get_type(lsdjSong, 2), LSDJ_INSTRUMENT_TYPE_WAVE);
    XCTAssertEqual(lsdj_instrument_get_type(lsdjSong, 3), LSDJ_INSTRUMENT_TYPE_NOISE);
    XCTAssertEqual(lsdj_instrument_pulse_get_pulse_width(lsdjSong, 0), LSDJ_INSTRUMENT_PULSE_WIDTH_25);
    XCTAssertEqual(lsdj_instrument_pulse_get_pulse_width(lsdjSong, 1), LSDJ_INSTRUMENT_PULSE_WIDTH_125);

    lsdj_project_free(project);
    [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
}

- (void)testLSDjNoteMappingAndClamping {
    Song *song = [Song defaultSong];
    song.title = @"Note Map";
    song.lengthBars = 1;
    [song.tracks[0].notes removeAllObjects];

    NSArray<NSNumber *> *pitches = @[@36, @55, @95, @20, @127];
    for (NSUInteger i = 0; i < pitches.count; i++) {
        [song.tracks[0].notes addObject:[NoteEvent noteWithPitch:pitches[i].integerValue
                                                       startTick:(uint64_t)i * 240
                                                   durationTicks:120
                                                        velocity:100]];
    }

    NSData *data = [self lsdjDataForSong:song];
    lsdj_project_t *project = [self readLSDjProject:data];
    if (!project) return;

    lsdj_song_t *lsdjSong = lsdj_project_get_song(project);
    uint8_t expected[] = {1, 20, 60, 1, 60};
    for (NSUInteger i = 0; i < pitches.count; i++) {
        uint8_t step = (uint8_t)(i * 2);
        XCTAssertEqual(lsdj_phrase_get_note(lsdjSong, 0, step), expected[i]);
        XCTAssertEqual(lsdj_phrase_get_instrument(lsdjSong, 0, step), 0);
        XCTAssertEqual(lsdj_phrase_get_note(lsdjSong, 0, (uint8_t)(step + 1)), LSDJ_PHRASE_NO_NOTE);
    }

    lsdj_project_free(project);
}

- (void)testLSDjChainGroupingAndPhraseReuse {
    Song *song = [Song defaultSong];
    song.title = @"Chains";
    song.lengthBars = 18;
    [song.tracks[0].notes removeAllObjects];
    [song.tracks[0].notes addObject:[NoteEvent noteWithPitch:60 startTick:0 durationTicks:120 velocity:100]];
    [song.tracks[0].notes addObject:[NoteEvent noteWithPitch:60 startTick:1920 durationTicks:120 velocity:100]];
    [song.tracks[0].notes addObject:[NoteEvent noteWithPitch:62 startTick:16 * 1920 durationTicks:120 velocity:100]];
    [song.tracks[0].notes addObject:[NoteEvent noteWithPitch:62 startTick:17 * 1920 durationTicks:120 velocity:100]];

    NSData *data = [self lsdjDataForSong:song];
    lsdj_project_t *project = [self readLSDjProject:data];
    if (!project) return;

    lsdj_song_t *lsdjSong = lsdj_project_get_song(project);
    XCTAssertEqual(lsdj_row_get_chain(lsdjSong, 0, LSDJ_CHANNEL_PULSE1), 0);
    XCTAssertEqual(lsdj_row_get_chain(lsdjSong, 1, LSDJ_CHANNEL_PULSE1), 1);
    XCTAssertEqual(lsdj_row_get_chain(lsdjSong, 2, LSDJ_CHANNEL_PULSE1), LSDJ_SONG_NO_CHAIN);

    XCTAssertEqual(lsdj_chain_get_phrase(lsdjSong, 0, 0), 0);
    XCTAssertEqual(lsdj_chain_get_phrase(lsdjSong, 0, 1), 0);
    XCTAssertEqual(lsdj_chain_get_phrase(lsdjSong, 0, 2), LSDJ_CHAIN_NO_PHRASE);
    XCTAssertEqual(lsdj_chain_get_phrase(lsdjSong, 1, 0), 1);
    XCTAssertEqual(lsdj_chain_get_phrase(lsdjSong, 1, 1), 1);
    XCTAssertEqual(lsdj_chain_get_phrase(lsdjSong, 1, 2), LSDJ_CHAIN_NO_PHRASE);

    XCTAssertEqual(lsdj_phrase_get_note(lsdjSong, 0, 0), 25);
    XCTAssertEqual(lsdj_phrase_get_note(lsdjSong, 1, 0), 27);
    XCTAssertTrue(lsdj_phrase_is_allocated(lsdjSong, 0));
    XCTAssertTrue(lsdj_phrase_is_allocated(lsdjSong, 1));
    XCTAssertFalse(lsdj_phrase_is_allocated(lsdjSong, 2));
    XCTAssertTrue(lsdj_chain_is_allocated(lsdjSong, 0));
    XCTAssertTrue(lsdj_chain_is_allocated(lsdjSong, 1));
    XCTAssertFalse(lsdj_chain_is_allocated(lsdjSong, 2));

    lsdj_project_free(project);
}

- (void)testLSDjAudibleTrackFiltering {
    Song *song = [self shortSong];
    song.tracks[1].muted = YES;
    song.tracks[3].muted = YES;

    NSData *data = [self lsdjDataForSong:song];
    lsdj_project_t *project = [self readLSDjProject:data];
    if (!project) return;

    lsdj_song_t *lsdjSong = lsdj_project_get_song(project);
    XCTAssertTrue(lsdj_instrument_is_allocated(lsdjSong, 0));
    XCTAssertTrue(lsdj_instrument_is_allocated(lsdjSong, 1));
    XCTAssertFalse(lsdj_instrument_is_allocated(lsdjSong, 2));
    XCTAssertEqual(lsdj_instrument_get_type(lsdjSong, 0), LSDJ_INSTRUMENT_TYPE_PULSE);
    XCTAssertEqual(lsdj_instrument_get_type(lsdjSong, 1), LSDJ_INSTRUMENT_TYPE_WAVE);
    XCTAssertEqual(lsdj_phrase_get_instrument(lsdjSong, 1, 0), 1);

    lsdj_project_free(project);
}

@end
