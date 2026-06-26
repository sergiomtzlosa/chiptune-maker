#import <XCTest/XCTest.h>
#import "AICompositionService.h"
#import "Song.h"
#import "Track.h"
#import "NoteEvent.h"

@interface AICompositionTests : XCTestCase
@end

@implementation AICompositionTests

- (void)testParsesFencedJSON {
    NSString *response = @"```json\n{\"tracks\":[{\"name\":\"Lead\",\"instrument\":\"pulse25\",\"notes\":[{\"pitch\":69,\"startTick\":0,\"durationTicks\":240,\"velocity\":100}]}]}\n```";
    Song *song = [Song defaultSong];
    NSError *error = nil;
    AICompositionDraft *draft = [AICompositionService draftFromResponse:response song:song targetTrackIndex:-1 error:&error];
    XCTAssertNotNil(draft, @"%@", error);
    XCTAssertEqual(draft.tracks.count, 1);
    XCTAssertEqualObjects(draft.tracks[0].name, @"Lead");
    XCTAssertEqual(draft.tracks[0].notes.count, 1);
    XCTAssertEqual(draft.tracks[0].notes[0].pitch, 69);
    XCTAssertTrue([draft.summary containsString:@"Lead"]);
}

- (void)testRejectsOutOfRangePitch {
    NSString *response = @"{\"tracks\":[{\"name\":\"Lead\",\"instrument\":\"pulse25\",\"notes\":[{\"pitch\":200,\"startTick\":0,\"durationTicks\":240,\"velocity\":100}]}]}";
    Song *song = [Song defaultSong];
    NSError *error = nil;
    AICompositionDraft *draft = [AICompositionService draftFromResponse:response song:song targetTrackIndex:-1 error:&error];
    XCTAssertNil(draft);
    XCTAssertNotNil(error);
    XCTAssertTrue([error.localizedDescription containsString:@"pitch"]);
}

- (void)testRejectsNoteBeyondSongEnd {
    NSString *response = @"{\"tracks\":[{\"name\":\"Lead\",\"instrument\":\"pulse25\",\"notes\":[{\"pitch\":69,\"startTick\":7600,\"durationTicks\":480,\"velocity\":100}]}]}";
    Song *song = [Song defaultSong];
    NSError *error = nil;
    AICompositionDraft *draft = [AICompositionService draftFromResponse:response song:song targetTrackIndex:-1 error:&error];
    XCTAssertNil(draft);
    XCTAssertNotNil(error);
}

- (void)testRejectsUnknownInstrument {
    NSString *response = @"{\"tracks\":[{\"name\":\"Lead\",\"instrument\":\"sawtooth\",\"notes\":[{\"pitch\":69,\"startTick\":0,\"durationTicks\":240,\"velocity\":100}]}]}";
    Song *song = [Song defaultSong];
    NSError *error = nil;
    AICompositionDraft *draft = [AICompositionService draftFromResponse:response song:song targetTrackIndex:-1 error:&error];
    XCTAssertNil(draft);
    XCTAssertNotNil(error);
}

- (void)testTrackTargetRequiresOneTrack {
    NSString *response = @"{\"tracks\":[{\"name\":\"A\",\"instrument\":\"pulse25\",\"notes\":[{\"pitch\":69,\"startTick\":0,\"durationTicks\":240,\"velocity\":100}]},{\"name\":\"B\",\"instrument\":\"triangle\",\"notes\":[{\"pitch\":48,\"startTick\":0,\"durationTicks\":240,\"velocity\":100}]}]}";
    Song *song = [Song defaultSong];
    NSError *error = nil;
    AICompositionDraft *draft = [AICompositionService draftFromResponse:response song:song targetTrackIndex:1 error:&error];
    XCTAssertNil(draft);
    XCTAssertNotNil(error);
}

- (void)testApplyDraftToTargetTrack {
    Song *song = [Song defaultSong];
    NSString *response = @"{\"tracks\":[{\"name\":\"Bass AI\",\"instrument\":\"triangle\",\"notes\":[{\"pitch\":36,\"startTick\":0,\"durationTicks\":480,\"velocity\":110},{\"pitch\":43,\"startTick\":480,\"durationTicks\":480,\"velocity\":100}]}]}";
    NSError *error = nil;
    AICompositionDraft *draft = [AICompositionService draftFromResponse:response song:song targetTrackIndex:2 error:&error];
    XCTAssertNotNil(draft, @"%@", error);
    XCTAssertTrue([AICompositionService applyDraft:draft toSong:song error:&error], @"%@", error);
    XCTAssertEqual(song.tracks.count, 4);
    XCTAssertEqual(song.tracks[2].notes.count, 2);
    XCTAssertEqual(song.tracks[2].instrument, ChipInstrumentTriangle);
    XCTAssertEqualObjects(song.tracks[2].name, @"Triangle");
}

- (void)testApplyWholeSongReplacesTracks {
    Song *song = [Song defaultSong];
    NSString *response = @"{\"tracks\":[{\"name\":\"Lead\",\"instrument\":\"pulse25\",\"notes\":[{\"pitch\":72,\"startTick\":0,\"durationTicks\":240,\"velocity\":100}]},{\"name\":\"Bass\",\"instrument\":\"triangle\",\"notes\":[{\"pitch\":36,\"startTick\":0,\"durationTicks\":480,\"velocity\":110}]}]}";
    NSError *error = nil;
    AICompositionDraft *draft = [AICompositionService draftFromResponse:response song:song targetTrackIndex:-1 error:&error];
    XCTAssertNotNil(draft, @"%@", error);
    XCTAssertTrue([AICompositionService applyDraft:draft toSong:song error:&error], @"%@", error);
    XCTAssertEqual(song.tracks.count, 2);
    XCTAssertEqualObjects(song.tracks[0].name, @"Lead");
    XCTAssertEqualObjects(song.tracks[1].name, @"Bass");
}

- (void)testPromptContainsSchemaAndContext {
    Song *song = [Song defaultSong];
    NSString *prompt = [AICompositionService promptForSong:song targetTrackIndex:2 brief:@"A funky bass line"];
    XCTAssertTrue([prompt containsString:@"JSON"]);
    XCTAssertTrue([prompt containsString:@"startTick"]);
    XCTAssertTrue([prompt containsString:@"A funky bass line"]);
    XCTAssertTrue([prompt containsString:@"Triangle"]);
    XCTAssertTrue([prompt containsString:@"120 BPM"]);
}

@end
