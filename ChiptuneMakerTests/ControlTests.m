#import <XCTest/XCTest.h>
#import "MainViewController.h"
#import "MainWindowController.h"
#import "SongDocument.h"
#import "Song.h"
#import "Track.h"
#import "NoteEvent.h"
#import "SongTypes.h"
#import "StepSequencerView.h"
#import "AudioEngine.h"

@interface MainViewController (ControlTesting)
- (void)keyChanged:(id)sender;
- (void)scaleChanged:(id)sender;
- (void)tempoChanged:(id)sender;
- (void)pitchChanged:(id)sender;
- (void)octaveChanged:(id)sender;
- (void)instrumentChanged:(id)sender;
- (void)documentDidChange:(NSNotification *)notification;
@end

@interface ControlTests : XCTestCase
@property (nonatomic, strong) SongDocument *document;
@end

@implementation ControlTests

- (MainViewController *)controllerWithSong:(Song *)song {
    self.document = [[SongDocument alloc] init];
    self.document.song = song;
    MainViewController *controller = [[MainViewController alloc] initWithDocument:self.document];
    [controller loadView];
    return controller;
}

- (void)testKeyControlTransposesByShortestSignedDelta {
    Song *song = [Song defaultSong];
    NoteEvent *note = [NoteEvent noteWithPitch:60 startTick:0 durationTicks:240 velocity:100];
    [song.tracks[0].notes addObject:note];
    MainViewController *controller = [self controllerWithSong:song];
    NSPopUpButton *keyPopup = [controller valueForKey:@"keyPopup"];

    [keyPopup selectItemAtIndex:11]; // B: one semitone below C
    [controller keyChanged:keyPopup];

    XCTAssertEqual(song.keyRoot, 11);
    XCTAssertEqual(note.pitch, 59, @"Changing C to B should transpose down one semitone");
}

- (void)testKeyControlWrapsUpwardWhenThatIsShorter {
    Song *song = [Song defaultSong];
    NoteEvent *note = [NoteEvent noteWithPitch:60 startTick:0 durationTicks:240 velocity:100];
    [song.tracks[0].notes addObject:note];
    MainViewController *controller = [self controllerWithSong:song];
    NSPopUpButton *keyPopup = [controller valueForKey:@"keyPopup"];

    [keyPopup selectItemAtIndex:11]; // C -> B, -1
    [controller keyChanged:keyPopup];
    [keyPopup selectItemAtIndex:2]; // B -> D, +3
    [controller keyChanged:keyPopup];

    XCTAssertEqual(song.keyRoot, 2);
    XCTAssertEqual(note.pitch, 62);
}

- (void)testScaleControlQuantizesNotesToSelectedScale {
    Song *song = [Song defaultSong];
    NoteEvent *note = [NoteEvent noteWithPitch:61 startTick:0 durationTicks:240 velocity:100]; // C#
    [song.tracks[0].notes addObject:note];
    MainViewController *controller = [self controllerWithSong:song];
    NSPopUpButton *scalePopup = [controller valueForKey:@"scalePopup"];

    [scalePopup selectItemAtIndex:MusicalScaleMinor];
    [controller scaleChanged:scalePopup];

    XCTAssertEqual(song.scale, MusicalScaleMinor);
    XCTAssertEqual(note.pitch, 60, @"C# should snap down to C in C natural minor");
}

- (void)testTempoControlUpdatesTheSongModel {
    Song *song = [Song defaultSong];
    MainViewController *controller = [self controllerWithSong:song];
    NSTextField *tempoField = [controller valueForKey:@"tempoField"];

    tempoField.stringValue = @"240";
    [controller tempoChanged:tempoField];

    XCTAssertEqualWithAccuracy(song.tempo, 240.0, 0.001);
}

- (void)testPitchAndOctaveControlsUpdateStepEntryPitch {
    Song *song = [Song defaultSong];
    MainViewController *controller = [self controllerWithSong:song];
    NSPopUpButton *pitchPopup = [controller valueForKey:@"pitchPopup"];
    NSStepper *octaveStepper = [controller valueForKey:@"octaveStepper"];
    StepSequencerView *stepView = [controller valueForKey:@"stepView"];

    [pitchPopup selectItemAtIndex:4]; // E
    octaveStepper.integerValue = 3;
    [controller pitchChanged:pitchPopup];
    [controller octaveChanged:octaveStepper];

    NSInteger expected = (3 + 1) * 12 + 4;
    XCTAssertEqual([[controller valueForKey:@"selectedPitch"] integerValue], expected);
    XCTAssertEqual(stepView.selectedPitch, expected);
    XCTAssertNotEqual(stepView.selectedPitch, 72);
}

- (void)testInstrumentControlUpdatesTheSelectedTrack {
    Song *song = [Song defaultSong];
    MainViewController *controller = [self controllerWithSong:song];
    NSPopUpButton *instrumentPopup = [controller valueForKey:@"instrumentPopup"];

    [instrumentPopup selectItemAtIndex:ChipInstrumentTriangle];
    [controller instrumentChanged:instrumentPopup];

    XCTAssertEqual(song.tracks[0].instrument, ChipInstrumentTriangle);
}

- (void)testDocumentChangePointsAudioEngineAtTheNewSong {
    Song *original = [Song defaultSong];
    MainViewController *controller = [self controllerWithSong:original];
    AudioEngine *engine = [[AudioEngine alloc] init];
    [controller setValue:engine forKey:@"audioEngine"];

    Song *replacement = [Song defaultSong];
    replacement.title = @"Replacement";
    self.document.song = replacement;
    [controller documentDidChange:nil];

    XCTAssertEqual(engine.song, replacement);
}

- (void)testWindowUsesStepViewAsInitialFirstResponder {
    self.document = [[SongDocument alloc] init];
    MainWindowController *windowController = [[MainWindowController alloc] initWithDocument:self.document];
    MainViewController *controller = (MainViewController *)windowController.window.contentViewController;
    NSView *preferred = controller.preferredFirstResponder;

    XCTAssertNotNil(preferred);
    XCTAssertTrue([preferred isKindOfClass:[StepSequencerView class]]);
    XCTAssertEqual(windowController.window.initialFirstResponder, preferred);
}

@end
