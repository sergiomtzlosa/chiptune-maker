#import <XCTest/XCTest.h>
#import "Song.h"
#import "Track.h"
#import "NoteEvent.h"
#import "SongSection.h"
#import "PatternGenerator.h"

@interface GenerationTests : XCTestCase
@end

@implementation GenerationTests

- (void)testGenerationIsDeterministic {
    Song *a = [Song defaultSong];
    Song *b = [Song defaultSong];
    [PatternGenerator generateSong:a seed:0x1234567890ABCDEFULL];
    [PatternGenerator generateSong:b seed:0x1234567890ABCDEFULL];

    XCTAssertEqual(a.tracks.count, b.tracks.count);
    for (NSInteger i = 0; i < (NSInteger)a.tracks.count; i++) {
        Track *ta = a.tracks[(NSUInteger)i];
        Track *tb = b.tracks[(NSUInteger)i];
        XCTAssertEqual(ta.notes.count, tb.notes.count);
        for (NSInteger n = 0; n < (NSInteger)MIN(ta.notes.count, tb.notes.count); n++) {
            NoteEvent *na = ta.notes[(NSUInteger)n];
            NoteEvent *nb = tb.notes[(NSUInteger)n];
            XCTAssertEqual(na.pitch, nb.pitch);
            XCTAssertEqual(na.startTick, nb.startTick);
            XCTAssertEqual(na.durationTicks, nb.durationTicks);
            XCTAssertEqual(na.velocity, nb.velocity);
        }
    }
}

- (void)testDifferentSeedsProduceDifferentMusic {
    Song *a = [Song defaultSong];
    Song *b = [Song defaultSong];
    [PatternGenerator generateSong:a seed:1];
    [PatternGenerator generateSong:b seed:2];
    NSMutableArray<NSString *> *signatureA = [NSMutableArray array];
    NSMutableArray<NSString *> *signatureB = [NSMutableArray array];
    for (Track *track in a.tracks) {
        for (NoteEvent *note in track.notes) {
            [signatureA addObject:[NSString stringWithFormat:@"%ld:%llu:%llu", (long)note.pitch, note.startTick, note.durationTicks]];
        }
    }
    for (Track *track in b.tracks) {
        for (NoteEvent *note in track.notes) {
            [signatureB addObject:[NSString stringWithFormat:@"%ld:%llu:%llu", (long)note.pitch, note.startTick, note.durationTicks]];
        }
    }
    XCTAssertNotEqualObjects(signatureA, signatureB);
}

- (void)testGeneratedNotesStayInSongAndScale {
    Song *song = [Song defaultSong];
    song.keyRoot = 2;
    song.scale = MusicalScaleMinor;
    song.lengthBars = 8;
    song.sections = [@[[SongSection sectionWithName:@"Main" startBar:0 lengthBars:8]] mutableCopy];
    [PatternGenerator generateSong:song seed:987654321];

    NSArray<NSNumber *> *intervals = MusicalScaleIntervals(song.scale);
    uint64_t totalTicks = song.totalTicks;
    for (NSInteger t = 0; t < (NSInteger)song.tracks.count; t++) {
        Track *track = song.tracks[(NSUInteger)t];
        XCTAssertGreaterThan(track.notes.count, 0, @"Track %@ should contain notes", track.name);
        for (NoteEvent *note in track.notes) {
            XCTAssertGreaterThanOrEqual(note.pitch, 0);
            XCTAssertLessThanOrEqual(note.pitch, 127);
            XCTAssertLessThan(note.startTick, totalTicks);
            XCTAssertLessThanOrEqual(note.startTick + note.durationTicks, totalTicks);
            XCTAssertGreaterThan(note.durationTicks, 0);
            XCTAssertGreaterThan(note.velocity, 0);
            XCTAssertLessThanOrEqual(note.velocity, 127);
            if (track.instrument != ChipInstrumentNoise) {
                NSInteger pitchClass = ((note.pitch - song.keyRoot) % 12 + 12) % 12;
                XCTAssertTrue([intervals containsObject:@(pitchClass)],
                              @"Pitch %@ is outside %@", NoteNameForPitch(note.pitch), MusicalScaleDisplayName(song.scale));
            }
        }
    }
}

- (void)testRegeneratingOneTrackLeavesOthersUntouched {
    Song *song = [Song defaultSong];
    song.lengthBars = 8;
    song.sections = [@[[SongSection sectionWithName:@"Main" startBar:0 lengthBars:8]] mutableCopy];
    [PatternGenerator generateSong:song seed:42];

    Track *untouched = song.tracks[0];
    NSMutableArray<NSString *> *before = [NSMutableArray array];
    for (NoteEvent *note in untouched.notes) {
        [before addObject:[NSString stringWithFormat:@"%ld:%llu:%llu", (long)note.pitch, note.startTick, note.durationTicks]];
    }

    Track *regenerated = song.tracks[1];
    [regenerated.notes removeAllObjects];
    for (NSInteger i = 0; i < (NSInteger)song.sections.count; i++) {
        [PatternGenerator generateTrack:regenerated inSong:song seed:42 section:song.sections[(NSUInteger)i] trackIndex:1 sectionIndex:i];
    }

    NSMutableArray<NSString *> *after = [NSMutableArray array];
    for (NoteEvent *note in untouched.notes) {
        [after addObject:[NSString stringWithFormat:@"%ld:%llu:%llu", (long)note.pitch, note.startTick, note.durationTicks]];
    }
    XCTAssertEqualObjects(before, after);
}

@end
