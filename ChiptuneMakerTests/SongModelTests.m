#import <XCTest/XCTest.h>
#import "Song.h"
#import "Track.h"
#import "NoteEvent.h"
#import "SongSection.h"

@interface SongModelTests : XCTestCase
@end

@implementation SongModelTests

- (void)testDefaultSongHasExpectedShape {
    Song *song = [Song defaultSong];
    XCTAssertEqual(song.tracks.count, 4);
    XCTAssertEqual(song.sections.count, 1);
    XCTAssertEqual(song.tempo, 120.0);
    XCTAssertEqual(song.lengthBars, 4);
    XCTAssertEqual(song.ppq, 480);
    XCTAssertEqual(song.ticksPerBar, 1920);
    NSError *error = nil;
    XCTAssertTrue([song validateWithError:&error], @"Default song should validate: %@", error);
}

- (void)testTicksPerBarHandlesCompoundMeters {
    Song *song = [Song defaultSong];
    song.timeSignatureNumerator = 3;
    song.timeSignatureDenominator = 4;
    XCTAssertEqual(song.ticksPerBar, 1440);
    song.timeSignatureNumerator = 6;
    song.timeSignatureDenominator = 8;
    XCTAssertEqual(song.ticksPerBar, 1440);
}

- (void)testJSONRoundTripPreservesSong {
    Song *song = [Song defaultSong];
    song.title = @"Round Trip";
    song.author = @"Tester";
    song.tempo = 143.5;
    song.keyRoot = 9;
    song.scale = MusicalScaleMinor;
    song.swing = 0.18;
    song.lengthBars = 8;
    song.generationSeed = 1234567890123456789ULL;
    song.sections = [@[[SongSection sectionWithName:@"Intro" startBar:0 lengthBars:4],
                       [SongSection sectionWithName:@"Verse" startBar:4 lengthBars:4]] mutableCopy];
    [song.tracks[0].notes addObject:[NoteEvent noteWithPitch:69 startTick:0 durationTicks:240 velocity:100]];
    [song.tracks[1].notes addObject:[NoteEvent noteWithPitch:64 startTick:240 durationTicks:480 velocity:80]];

    NSDictionary *dictionary = [song dictionaryRepresentation];
    NSData *data = [NSJSONSerialization dataWithJSONObject:dictionary options:0 error:NULL];
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    NSError *error = nil;
    Song *restored = [Song songFromDictionary:object error:&error];

    XCTAssertNotNil(restored, @"%@", error);
    XCTAssertEqualObjects(restored.title, @"Round Trip");
    XCTAssertEqualObjects(restored.author, @"Tester");
    XCTAssertEqualWithAccuracy(restored.tempo, 143.5, 0.0001);
    XCTAssertEqual(restored.keyRoot, 9);
    XCTAssertEqual(restored.scale, MusicalScaleMinor);
    XCTAssertEqualWithAccuracy(restored.swing, 0.18, 0.0001);
    XCTAssertEqual(restored.lengthBars, 8);
    XCTAssertEqual(restored.generationSeed, 1234567890123456789ULL);
    XCTAssertEqual(restored.sections.count, 2);
    XCTAssertEqual(restored.tracks.count, 4);
    XCTAssertEqual(restored.tracks[0].notes.count, 1);
    XCTAssertEqual(restored.tracks[0].notes[0].pitch, 69);
    XCTAssertEqual(restored.tracks[1].notes[0].durationTicks, 480);
}

- (void)testSeedRoundTripsAboveJSONIntegerPrecision {
    Song *song = [Song defaultSong];
    song.generationSeed = UINT64_MAX;
    NSDictionary *dictionary = [song dictionaryRepresentation];
    XCTAssertTrue([dictionary[@"generation"][@"seed"] isKindOfClass:[NSString class]]);
    NSError *error = nil;
    Song *restored = [Song songFromDictionary:dictionary error:&error];
    XCTAssertNotNil(restored, @"%@", error);
    XCTAssertEqual(restored.generationSeed, UINT64_MAX);
}

- (void)testValidationRejectsOverlappingSections {
    Song *song = [Song defaultSong];
    song.lengthBars = 8;
    song.sections = [@[[SongSection sectionWithName:@"A" startBar:0 lengthBars:4],
                       [SongSection sectionWithName:@"B" startBar:3 lengthBars:3]] mutableCopy];
    NSError *error = nil;
    XCTAssertFalse([song validateWithError:&error]);
    XCTAssertNotNil(error);
}

- (void)testValidationRejectsNotesBeyondSongEnd {
    Song *song = [Song defaultSong];
    [song.tracks[0].notes addObject:[NoteEvent noteWithPitch:60 startTick:song.totalTicks durationTicks:120 velocity:100]];
    NSError *error = nil;
    XCTAssertFalse([song validateWithError:&error]);
}

- (void)testFutureFormatVersionIsRejected {
    NSMutableDictionary *dictionary = [[Song defaultSong].dictionaryRepresentation mutableCopy];
    dictionary[@"formatVersion"] = @99;
    NSError *error = nil;
    Song *song = [Song songFromDictionary:dictionary error:&error];
    XCTAssertNil(song);
    XCTAssertNotNil(error);
    XCTAssertTrue([error.localizedDescription containsString:@"newer"]);
}

- (void)testUnknownJSONFieldsAreIgnored {
    NSMutableDictionary *dictionary = [[Song defaultSong].dictionaryRepresentation mutableCopy];
    dictionary[@"futureFeature"] = @{@"enabled": @YES};
    NSError *error = nil;
    Song *song = [Song songFromDictionary:dictionary error:&error];
    XCTAssertNotNil(song, @"%@", error);
}

- (void)testTransposePitchedNotesLeavesNoiseAlone {
    Song *song = [Song defaultSong];
    [song.tracks[0].notes addObject:[NoteEvent noteWithPitch:60 startTick:0 durationTicks:240 velocity:100]];
    [song.tracks[2].notes addObject:[NoteEvent noteWithPitch:48 startTick:0 durationTicks:240 velocity:100]];
    [song.tracks[3].notes addObject:[NoteEvent noteWithPitch:60 startTick:0 durationTicks:240 velocity:100]];

    [song transposePitchedNotesBySemitones:2];

    XCTAssertEqual(song.tracks[0].notes[0].pitch, 62);
    XCTAssertEqual(song.tracks[2].notes[0].pitch, 50);
    XCTAssertEqual(song.tracks[3].notes[0].pitch, 60, @"Noise tracks should keep their drum pitches");
}

- (void)testTransposeClampsToMIDIRange {
    Song *song = [Song defaultSong];
    [song.tracks[0].notes addObject:[NoteEvent noteWithPitch:126 startTick:0 durationTicks:240 velocity:100]];
    [song.tracks[1].notes addObject:[NoteEvent noteWithPitch:1 startTick:0 durationTicks:240 velocity:100]];

    [song transposePitchedNotesBySemitones:5];
    XCTAssertEqual(song.tracks[0].notes[0].pitch, 127);

    [song transposePitchedNotesBySemitones:-10];
    XCTAssertEqual(song.tracks[1].notes[0].pitch, 0);
}

- (void)testQuantizeSnapsPitchedNotesToScale {
    Song *song = [Song defaultSong];
    [song.tracks[0].notes addObject:[NoteEvent noteWithPitch:61 startTick:0 durationTicks:240 velocity:100]];
    [song.tracks[2].notes addObject:[NoteEvent noteWithPitch:63 startTick:0 durationTicks:240 velocity:100]];
    [song.tracks[3].notes addObject:[NoteEvent noteWithPitch:61 startTick:0 durationTicks:240 velocity:100]];

    [song quantizePitchedNotesToScale:MusicalScaleMajor root:0];

    XCTAssertEqual(song.tracks[0].notes[0].pitch, 60, @"C# should snap down to C in C major");
    XCTAssertEqual(song.tracks[2].notes[0].pitch, 62, @"D# should snap down to D in C major");
    XCTAssertEqual(song.tracks[3].notes[0].pitch, 61, @"Noise tracks should not be quantized");
}

- (void)testQuantizeRespectsRoot {
    Song *song = [Song defaultSong];
    [song.tracks[0].notes addObject:[NoteEvent noteWithPitch:60 startTick:0 durationTicks:240 velocity:100]];
    [song.tracks[1].notes addObject:[NoteEvent noteWithPitch:61 startTick:0 durationTicks:240 velocity:100]];

    [song quantizePitchedNotesToScale:MusicalScaleMajor root:2];

    XCTAssertEqual(song.tracks[0].notes[0].pitch, 59, @"C should snap to B in D major");
    XCTAssertEqual(song.tracks[1].notes[0].pitch, 61, @"C# already belongs to D major");
}

@end
