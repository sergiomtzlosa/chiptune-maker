#import <XCTest/XCTest.h>
#import "AppDelegate.h"
#import "MainViewController.h"
#import "MainWindowController.h"
#import "SongDocument.h"
#import "Song.h"
#import "Track.h"
#import "NoteEvent.h"
#import "SongTypes.h"
#import "AudioImportService.h"

@interface AppDelegate (AudioImportTesting)
- (void)buildMainMenu;
@end

@interface MainViewController (AudioImportTesting)
- (void)applyImportedAudioResult:(AudioImportResult *)result sourceURL:(NSURL *)url;
- (void)importAudio:(id)sender;
@end

@interface AudioImportUITests : XCTestCase
@property (nonatomic, strong) SongDocument *document;
@end

@implementation AudioImportUITests

- (MainViewController *)controllerWithSong:(Song *)song {
    self.document = [[SongDocument alloc] init];
    self.document.song = song;
    MainViewController *controller = [[MainViewController alloc] initWithDocument:self.document];
    [controller loadView];
    return controller;
}

- (NSMenuItem *)menuItemWithAction:(SEL)action inMenu:(NSMenu *)menu {
    for (NSMenuItem *item in menu.itemArray) {
        if (item.action == action) return item;
        if (item.submenu) {
            NSMenuItem *nested = [self menuItemWithAction:action inMenu:item.submenu];
            if (nested) return nested;
        }
    }
    return nil;
}

- (void)testFileMenuContainsImportAudioItem {
    AppDelegate *delegate = (AppDelegate *)NSApp.delegate;
    XCTAssertTrue([delegate isKindOfClass:[AppDelegate class]]);
    NSMenu *oldMainMenu = NSApp.mainMenu;
    NSMenu *oldHelpMenu = NSApp.helpMenu;
    [delegate buildMainMenu];

    NSMenuItem *item = [self menuItemWithAction:@selector(importAudio:) inMenu:NSApp.mainMenu];
    XCTAssertNotNil(item);
    XCTAssertTrue([item.title containsString:@"Import Audio"]);
    XCTAssertEqualObjects(item.keyEquivalent, @"i");
    XCTAssertTrue((item.keyEquivalentModifierMask & NSEventModifierFlagCommand) != 0);
    XCTAssertTrue((item.keyEquivalentModifierMask & NSEventModifierFlagShift) != 0);

    NSApp.mainMenu = oldMainMenu;
    NSApp.helpMenu = oldHelpMenu;
}

- (void)testToolbarHasImportAudioButton {
    MainViewController *controller = [self controllerWithSong:[Song defaultSong]];
    NSButton *button = [controller valueForKey:@"importAudioButton"];
    XCTAssertNotNil(button);
    XCTAssertTrue([button isKindOfClass:[NSButton class]]);
    XCTAssertEqualObjects(button.title, @"Import Audio…");
    XCTAssertEqual(button.target, controller);
    XCTAssertEqual(button.action, @selector(importAudio:));
    XCTAssertTrue([controller respondsToSelector:@selector(importAudio:)]);
}

- (AudioImportPart *)partWithRole:(AudioImportPartRole)role
                        instrument:(ChipInstrument)instrument
                            pitches:(NSArray<NSNumber *> *)pitches {
    AudioImportPart *part = [[AudioImportPart alloc] init];
    part.role = role;
    part.name = @[@"Lead", @"Harmony", @"Bass", @"Drums"][(NSUInteger)role];
    part.instrument = instrument;
    NSMutableArray<NoteEvent *> *notes = [NSMutableArray array];
    for (NSUInteger i = 0; i < pitches.count; i++) {
        [notes addObject:[NoteEvent noteWithPitch:pitches[i].integerValue
                                        startTick:i * 120
                                    durationTicks:120
                                         velocity:90]];
    }
    part.notes = notes;
    return part;
}

- (NSArray<AudioImportPart *> *)fourPartArrangement {
    return @[
        [self partWithRole:AudioImportPartRoleLead instrument:ChipInstrumentPulse25 pitches:@[@72]],
        [self partWithRole:AudioImportPartRoleBass instrument:ChipInstrumentTriangle pitches:@[@36]],
        [self partWithRole:AudioImportPartRoleDrums instrument:ChipInstrumentNoise pitches:@[@48]],
        [self partWithRole:AudioImportPartRoleHarmony instrument:ChipInstrumentPulse12 pitches:@[@64]]
    ];
}

- (void)testApplyImportedResultCreatesLeadTrackAndIsUndoable {
    Song *song = [Song defaultSong];
    [song.tracks[0].notes addObject:[NoteEvent noteWithPitch:60 startTick:0 durationTicks:480 velocity:100]];
    MainViewController *controller = [self controllerWithSong:song];

    AudioImportResult *result = [[AudioImportResult alloc] init];
    result.notes = @[
        [NoteEvent noteWithPitch:72 startTick:0 durationTicks:240 velocity:90],
        [NoteEvent noteWithPitch:74 startTick:240 durationTicks:240 velocity:90]
    ];
    [controller applyImportedAudioResult:result sourceURL:[NSURL fileURLWithPath:@"/tmp/Test Melody.wav"]];

    XCTAssertEqual(song.tracks.count, 5);
    Track *lead = song.tracks.lastObject;
    XCTAssertEqual(lead.instrument, ChipInstrumentPulse25);
    XCTAssertTrue([lead.name containsString:@"Test Melody Lead"]);
    XCTAssertEqual(lead.notes.count, 2);
    XCTAssertEqual(lead.notes[0].startTick, 480);
    XCTAssertEqual(lead.notes[1].startTick, 720);
    XCTAssertEqualObjects([controller valueForKey:@"currentTrackIndex"], @(4));
    XCTAssertTrue(self.document.isDocumentEdited);

    NSTextField *status = [controller valueForKey:@"statusLabel"];
    XCTAssertTrue([status.stringValue containsString:@"Imported 2 notes on 1 new track"]);

    [self.document.undoManager undo];
    XCTAssertEqual(self.document.song.tracks.count, 4);
    XCTAssertEqual(self.document.song.tracks[0].notes.count, 1);
    XCTAssertEqual(self.document.song.tracks[0].notes[0].pitch, 60);
}

- (void)testApplyArrangementCreatesOneTrackPerPart {
    Song *song = [Song defaultSong];
    MainViewController *controller = [self controllerWithSong:song];

    AudioImportResult *result = [[AudioImportResult alloc] init];
    result.parts = [self fourPartArrangement];
    [controller applyImportedAudioResult:result sourceURL:[NSURL fileURLWithPath:@"/tmp/Band.wav"]];

    XCTAssertEqual(song.tracks.count, 8);
    NSArray<NSString *> *names = @[@"Band Lead", @"Band Bass", @"Band Drums", @"Band Harmony"];
    NSArray<NSNumber *> *instruments = @[@(ChipInstrumentPulse25), @(ChipInstrumentTriangle),
                                         @(ChipInstrumentNoise), @(ChipInstrumentPulse12)];
    for (NSUInteger i = 0; i < 4; i++) {
        Track *track = song.tracks[4 + i];
        XCTAssertEqualObjects(track.name, names[i]);
        XCTAssertEqual(track.instrument, instruments[i].integerValue);
        XCTAssertEqual(track.notes.count, 1);
        XCTAssertEqual(track.notes.firstObject.startTick, 0);
    }
    XCTAssertEqualObjects([controller valueForKey:@"currentTrackIndex"], @(4));

    NSTextField *status = [controller valueForKey:@"statusLabel"];
    XCTAssertTrue([status.stringValue containsString:@"Imported 4 notes on 4 new tracks"]);

    [self.document.undoManager undo];
    XCTAssertEqual(self.document.song.tracks.count, 4);
}

- (void)testArrangementUsesRemainingSlotForLeadFirst {
    Song *song = [Song defaultSong];
    for (NSInteger i = 0; i < 3; i++) {
        [song.tracks addObject:[Track trackWithName:[NSString stringWithFormat:@"Extra %ld", (long)i]
                                        instrument:ChipInstrumentPulse50]];
    }
    MainViewController *controller = [self controllerWithSong:song];

    AudioImportResult *result = [[AudioImportResult alloc] init];
    result.parts = [self fourPartArrangement];
    [controller applyImportedAudioResult:result sourceURL:[NSURL fileURLWithPath:@"/tmp/Crowded.wav"]];

    XCTAssertEqual(song.tracks.count, 8);
    XCTAssertEqual(song.tracks.lastObject.instrument, ChipInstrumentPulse25);
    XCTAssertTrue([song.tracks.lastObject.name containsString:@"Lead"]);
    NSTextField *status = [controller valueForKey:@"statusLabel"];
    XCTAssertTrue([status.stringValue containsString:@"track limit reached"]);
}

- (void)testArrangementImportFailsWhenSongHasEightTracks {
    Song *song = [Song defaultSong];
    for (NSInteger i = 0; i < 4; i++) {
        [song.tracks addObject:[Track trackWithName:[NSString stringWithFormat:@"Extra %ld", (long)i]
                                        instrument:ChipInstrumentPulse50]];
    }
    MainViewController *controller = [self controllerWithSong:song];

    AudioImportResult *result = [[AudioImportResult alloc] init];
    result.parts = [self fourPartArrangement];
    [controller applyImportedAudioResult:result sourceURL:[NSURL fileURLWithPath:@"/tmp/Full.wav"]];

    XCTAssertEqual(song.tracks.count, 8);
    XCTAssertFalse(self.document.isDocumentEdited);
    NSTextField *status = [controller valueForKey:@"statusLabel"];
    XCTAssertTrue([status.stringValue containsString:@"Audio import failed"]);
}

- (void)testEmptyImportResultDoesNotChangeTheSong {
    Song *song = [Song defaultSong];
    NSUInteger before = song.tracks.count;
    MainViewController *controller = [self controllerWithSong:song];

    AudioImportResult *result = [[AudioImportResult alloc] init];
    [controller applyImportedAudioResult:result sourceURL:[NSURL fileURLWithPath:@"/tmp/Silence.wav"]];

    XCTAssertEqual(song.tracks.count, before);
    NSTextField *status = [controller valueForKey:@"statusLabel"];
    XCTAssertTrue([status.stringValue containsString:@"No musical parts detected"]);
}

@end
