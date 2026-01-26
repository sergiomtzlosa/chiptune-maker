#import "MainViewController.h"
#import "SongDocument.h"
#import "Song.h"
#import "Track.h"
#import "NoteEvent.h"
#import "SongSection.h"
#import "SongTypes.h"
#import "AudioEngine.h"
#import "ChipRenderer.h"
#import "StepSequencerView.h"
#import "PianoRollView.h"
#import "PatternGenerator.h"
#import "ExportService.h"
#import "AIGeneratorWindowController.h"
#import "ChiptuneTheme.h"
#import "TimelineScrollSupport.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface MainViewController () <NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate>
@property (nonatomic, weak) SongDocument *document;
@property (nonatomic, strong) AudioEngine *audioEngine;
@property (nonatomic, strong) NSSplitView *splitView;
@property (nonatomic, strong) NSTableView *trackTable;
@property (nonatomic, strong) NSScrollView *editorScrollView;
@property (nonatomic, strong) StepSequencerView *stepView;
@property (nonatomic, strong) PianoRollView *pianoRollView;
@property (nonatomic, strong) NSSegmentedControl *modeControl;
@property (nonatomic, strong) NSTextField *tempoField;
@property (nonatomic, strong) NSStepper *barsStepper;
@property (nonatomic, strong) NSTextField *barsValueLabel;
@property (nonatomic, strong) NSPopUpButton *keyPopup;
@property (nonatomic, strong) NSPopUpButton *scalePopup;
@property (nonatomic, strong) NSPopUpButton *pitchPopup;
@property (nonatomic, strong) NSStepper *octaveStepper;
@property (nonatomic, strong) NSTextField *seedField;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSButton *playButton;
@property (nonatomic, strong) NSButton *loopCheck;
@property (nonatomic, strong) NSButton *followCheck;
@property (nonatomic, strong) NSProgressIndicator *progressIndicator;
@property (nonatomic, strong) NSTextField *trackNameField;
@property (nonatomic, strong) NSPopUpButton *instrumentPopup;
@property (nonatomic, strong) NSSlider *volumeSlider;
@property (nonatomic, strong) NSSlider *panSlider;
@property (nonatomic, strong) NSButton *muteCheck;
@property (nonatomic, strong) NSButton *soloCheck;
@property (nonatomic, strong) NSSlider *vibratoDepthSlider;
@property (nonatomic, strong) NSSlider *vibratoRateSlider;
@property (nonatomic, strong) NSButton *slideCheck;
@property (nonatomic, strong) NSPopUpButton *arpeggioPopup;
@property (nonatomic, strong) NSTextField *volumeValueLabel;
@property (nonatomic, strong) NSTextField *panValueLabel;
@property (nonatomic, strong) NSTextField *vibratoDepthValueLabel;
@property (nonatomic, strong) NSTextField *vibratoRateValueLabel;
@property (nonatomic, strong) NSTimer *playheadTimer;
@property (nonatomic, strong) AIGeneratorWindowController *aiWindowController;
@property (nonatomic, strong) NSSavePanel *activeSavePanel;
@property (nonatomic, strong) NSPopUpButton *exportFormatPopup;
@property (nonatomic, strong) NSPopUpButton *exportBitratePopup;
@property (nonatomic, strong) NSButton *exportNormalizeCheck;
@property (nonatomic, assign) NSInteger currentTrackIndex;
@property (nonatomic, assign) NSInteger selectedPitch;
@property (nonatomic, assign) BOOL refreshing;
@property (nonatomic, assign) BOOL suppressAudioReload;
@property (nonatomic, assign) BOOL followPlayhead;
@property (nonatomic, assign) BOOL didPrepareAudio;
@property (nonatomic, strong) NSLayoutYAxisAnchor *toolbarBottomAnchor;
@property (nonatomic, strong) NSLayoutYAxisAnchor *splitBottomAnchor;
#if DEBUG
@property (nonatomic, assign) BOOL didRunSnapshotAutomation;
@property (nonatomic, assign) BOOL didRunAIAutomation;
#endif
@end

@implementation MainViewController

- (instancetype)initWithDocument:(SongDocument *)document {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _document = document;
        _currentTrackIndex = 0;
        _selectedPitch = 72;
    }
    return self;
}

- (void)dealloc {
    [self.playheadTimer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.audioEngine stop];
}

- (void)loadView {
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1280, 820)];
    root.wantsLayer = YES;
    self.view = root;

    [self buildToolbarInView:root];
    [self buildSplitViewInView:root];
    [self buildStatusBarInView:root];
}

- (NSTextField *)labelWithString:(NSString *)string {
    NSTextField *label = [NSTextField labelWithString:string];
    label.font = [NSFont systemFontOfSize:11];
    label.textColor = [NSColor secondaryLabelColor];
    return label;
}

- (NSTextField *)sectionLabelWithString:(NSString *)string {
    NSTextField *label = [NSTextField labelWithString:string];
    label.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
    label.textColor = [NSColor labelColor];
    return label;
}

- (void)buildToolbarInView:(NSView *)root {
    self.playButton = [NSButton buttonWithTitle:@"▶ Play" target:self action:@selector(togglePlayback:)];
    self.playButton.bezelStyle = NSBezelStyleRounded;
    NSButton *stopButton = [NSButton buttonWithTitle:@"■ Stop" target:self action:@selector(stopPlayback:)];
    stopButton.bezelStyle = NSBezelStyleRounded;

    self.tempoField = [NSTextField textFieldWithString:@"120"];
    self.tempoField.alignment = NSTextAlignmentRight;
    self.tempoField.target = self;
    self.tempoField.action = @selector(tempoChanged:);
    [self.tempoField.widthAnchor constraintEqualToConstant:52].active = YES;

    self.barsValueLabel = [NSTextField labelWithString:@"4"];
    self.barsValueLabel.alignment = NSTextAlignmentRight;
    [self.barsValueLabel.widthAnchor constraintEqualToConstant:20].active = YES;
    self.barsStepper = [[NSStepper alloc] init];
    self.barsStepper.minValue = 1;
    self.barsStepper.maxValue = 16;
    self.barsStepper.increment = 1;
    self.barsStepper.integerValue = 4;
    self.barsStepper.target = self;
    self.barsStepper.action = @selector(barsChanged:);

    self.keyPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.keyPopup addItemsWithTitles:NoteNames()];
    self.keyPopup.target = self;
    self.keyPopup.action = @selector(keyChanged:);
    [self.keyPopup.widthAnchor constraintEqualToConstant:64].active = YES;

    self.scalePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (NSInteger i = MusicalScaleMajor; i <= MusicalScaleChromatic; i++) {
        [self.scalePopup addItemWithTitle:MusicalScaleDisplayName((MusicalScale)i)];
    }
    self.scalePopup.target = self;
    self.scalePopup.action = @selector(scaleChanged:);
    [self.scalePopup.widthAnchor constraintEqualToConstant:132].active = YES;

    NSButton *generateButton = [NSButton buttonWithTitle:@"Generate" target:self action:@selector(generateSong:)];
    generateButton.bezelStyle = NSBezelStyleRounded;
    NSButton *aiButton = [NSButton buttonWithTitle:@"AI…" target:self action:@selector(showAIPanel:)];
    aiButton.bezelStyle = NSBezelStyleRounded;
    NSButton *exportButton = [NSButton buttonWithTitle:@"Export…" target:self action:@selector(exportSong:)];
    exportButton.bezelStyle = NSBezelStyleRounded;

    self.progressIndicator = [[NSProgressIndicator alloc] init];
    self.progressIndicator.style = NSProgressIndicatorStyleSpinning;
    self.progressIndicator.controlSize = NSControlSizeSmall;
    self.progressIndicator.displayedWhenStopped = NO;
    [self.progressIndicator.widthAnchor constraintEqualToConstant:18].active = YES;

    NSStackView *row1 = [NSStackView stackViewWithViews:@[
        self.playButton, stopButton,
        [self labelWithString:@"Tempo"], self.tempoField,
        [self labelWithString:@"Bars"], self.barsValueLabel, self.barsStepper,
        [self labelWithString:@"Key"], self.keyPopup, self.scalePopup,
        generateButton, aiButton, exportButton, self.progressIndicator
    ]];
    row1.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row1.alignment = NSLayoutAttributeCenterY;
    row1.spacing = 8;

    self.modeControl = [NSSegmentedControl segmentedControlWithLabels:@[@"Steps", @"Piano Roll"]
                                                         trackingMode:NSSegmentSwitchTrackingSelectOne
                                                               target:self
                                                               action:@selector(modeChanged:)];
    self.modeControl.selectedSegment = 0;

    self.pitchPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.pitchPopup addItemsWithTitles:NoteNames()];
    self.pitchPopup.target = self;
    self.pitchPopup.action = @selector(pitchChanged:);
    [self.pitchPopup.widthAnchor constraintEqualToConstant:64].active = YES;

    self.octaveStepper = [[NSStepper alloc] init];
    self.octaveStepper.minValue = 0;
    self.octaveStepper.maxValue = 8;
    self.octaveStepper.increment = 1;
    self.octaveStepper.integerValue = 5;
    self.octaveStepper.target = self;
    self.octaveStepper.action = @selector(octaveChanged:);

    self.loopCheck = [NSButton checkboxWithTitle:@"Loop" target:self action:@selector(loopChanged:)];
    self.followCheck = [NSButton checkboxWithTitle:@"Follow" target:self action:@selector(followChanged:)];
    self.followCheck.state = NSControlStateValueOn;

    self.seedField = [NSTextField textFieldWithString:@"0"];
    self.seedField.target = self;
    self.seedField.action = @selector(seedChanged:);
    [self.seedField.widthAnchor constraintEqualToConstant:140].active = YES;

    NSButton *regenerateButton = [NSButton buttonWithTitle:@"Regenerate Track" target:self action:@selector(regenerateTrack:)];
    regenerateButton.bezelStyle = NSBezelStyleRounded;

    NSStackView *row2 = [NSStackView stackViewWithViews:@[
        self.modeControl,
        [self labelWithString:@"Pitch"], self.pitchPopup, self.octaveStepper,
        self.loopCheck, self.followCheck,
        [self labelWithString:@"Seed"], self.seedField, regenerateButton
    ]];
    row2.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row2.alignment = NSLayoutAttributeCenterY;
    row2.spacing = 8;

    NSStackView *toolbar = [NSStackView stackViewWithViews:@[row1, row2]];
    toolbar.orientation = NSUserInterfaceLayoutOrientationVertical;
    toolbar.alignment = NSLayoutAttributeLeading;
    toolbar.spacing = 8;
    toolbar.edgeInsets = NSEdgeInsetsMake(10, 12, 10, 12);
    toolbar.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:toolbar];
    [NSLayoutConstraint activateConstraints:@[
        [toolbar.topAnchor constraintEqualToAnchor:root.topAnchor],
        [toolbar.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [toolbar.trailingAnchor constraintLessThanOrEqualToAnchor:root.trailingAnchor]
    ]];
    self.toolbarBottomAnchor = toolbar.bottomAnchor;
}

- (void)buildSplitViewInView:(NSView *)root {
    self.stepView = [[StepSequencerView alloc] initWithFrame:NSMakeRect(0, 0, 900, 400)];
    self.stepView.document = self.document;
    self.stepView.currentTrackIndex = 0;
    self.stepView.selectedPitch = self.selectedPitch;

    self.pianoRollView = [[PianoRollView alloc] initWithFrame:NSMakeRect(0, 0, 900, 700)];
    self.pianoRollView.document = self.document;
    self.pianoRollView.currentTrackIndex = 0;

    self.editorScrollView = [[NSScrollView alloc] init];
    self.editorScrollView.hasVerticalScroller = YES;
    self.editorScrollView.hasHorizontalScroller = YES;
    self.editorScrollView.autohidesScrollers = NO;
    self.editorScrollView.borderType = NSNoBorder;
    self.editorScrollView.drawsBackground = NO;
    self.editorScrollView.documentView = self.stepView;

    NSView *leftPanel = [[NSView alloc] init];
    NSTextField *tracksTitle = [self sectionLabelWithString:@"Tracks"];
    tracksTitle.translatesAutoresizingMaskIntoConstraints = NO;
    [leftPanel addSubview:tracksTitle];

    self.trackTable = [[NSTableView alloc] init];
    self.trackTable.dataSource = self;
    self.trackTable.delegate = self;
    self.trackTable.headerView = nil;
    self.trackTable.rowHeight = 30;
    self.trackTable.allowsEmptySelection = NO;
    self.trackTable.usesAlternatingRowBackgroundColors = NO;
    self.trackTable.backgroundColor = [NSColor controlBackgroundColor];
    self.trackTable.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;

    NSTableColumn *nameColumn = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    nameColumn.width = 142;
    [self.trackTable addTableColumn:nameColumn];
    NSTableColumn *muteColumn = [[NSTableColumn alloc] initWithIdentifier:@"mute"];
    muteColumn.width = 30;
    [self.trackTable addTableColumn:muteColumn];
    NSTableColumn *soloColumn = [[NSTableColumn alloc] initWithIdentifier:@"solo"];
    soloColumn.width = 30;
    [self.trackTable addTableColumn:soloColumn];

    NSScrollView *tableScroll = [[NSScrollView alloc] init];
    tableScroll.documentView = self.trackTable;
    tableScroll.hasVerticalScroller = YES;
    tableScroll.borderType = NSBezelBorder;
    tableScroll.translatesAutoresizingMaskIntoConstraints = NO;
    [leftPanel addSubview:tableScroll];

    NSButton *addButton = [NSButton buttonWithTitle:@"Add" target:self action:@selector(addTrack:)];
    addButton.bezelStyle = NSBezelStyleRounded;
    NSButton *removeButton = [NSButton buttonWithTitle:@"Remove" target:self action:@selector(removeTrack:)];
    removeButton.bezelStyle = NSBezelStyleRounded;
    NSStackView *buttons = [NSStackView stackViewWithViews:@[addButton, removeButton]];
    buttons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttons.spacing = 8;
    buttons.translatesAutoresizingMaskIntoConstraints = NO;
    [leftPanel addSubview:buttons];

    [NSLayoutConstraint activateConstraints:@[
        [tracksTitle.topAnchor constraintEqualToAnchor:leftPanel.topAnchor constant:12],
        [tracksTitle.leadingAnchor constraintEqualToAnchor:leftPanel.leadingAnchor constant:12],
        [tableScroll.topAnchor constraintEqualToAnchor:tracksTitle.bottomAnchor constant:8],
        [tableScroll.leadingAnchor constraintEqualToAnchor:leftPanel.leadingAnchor constant:8],
        [tableScroll.trailingAnchor constraintEqualToAnchor:leftPanel.trailingAnchor constant:-8],
        [tableScroll.bottomAnchor constraintEqualToAnchor:buttons.topAnchor constant:-8],
        [buttons.leadingAnchor constraintEqualToAnchor:leftPanel.leadingAnchor constant:8],
        [buttons.trailingAnchor constraintEqualToAnchor:leftPanel.trailingAnchor constant:-8],
        [buttons.bottomAnchor constraintEqualToAnchor:leftPanel.bottomAnchor constant:-10],
        [buttons.heightAnchor constraintEqualToConstant:26]
    ]];

    NSView *centerPanel = [[NSView alloc] init];
    self.editorScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [centerPanel addSubview:self.editorScrollView];
    [NSLayoutConstraint activateConstraints:@[
        [self.editorScrollView.topAnchor constraintEqualToAnchor:centerPanel.topAnchor],
        [self.editorScrollView.leadingAnchor constraintEqualToAnchor:centerPanel.leadingAnchor],
        [self.editorScrollView.trailingAnchor constraintEqualToAnchor:centerPanel.trailingAnchor],
        [self.editorScrollView.bottomAnchor constraintEqualToAnchor:centerPanel.bottomAnchor]
    ]];

    NSView *rightPanel = [self buildInspectorPanel];

    self.splitView = [[NSSplitView alloc] init];
    self.splitView.vertical = YES;
    self.splitView.dividerStyle = NSSplitViewDividerStyleThin;
    self.splitView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.splitView addArrangedSubview:leftPanel];
    [self.splitView addArrangedSubview:centerPanel];
    [self.splitView addArrangedSubview:rightPanel];
    [self.splitView setHoldingPriority:260 forSubviewAtIndex:0];
    [self.splitView setHoldingPriority:250 forSubviewAtIndex:2];
    [root addSubview:self.splitView];
    [NSLayoutConstraint activateConstraints:@[
        [self.splitView.topAnchor constraintEqualToAnchor:self.toolbarBottomAnchor constant:2],
        [self.splitView.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [self.splitView.trailingAnchor constraintEqualToAnchor:root.trailingAnchor]
    ]];
    self.splitBottomAnchor = self.splitView.bottomAnchor;
}

- (NSView *)buildInspectorPanel {
    NSView *panel = [[NSView alloc] init];
    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 7;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [panel addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:panel.topAnchor constant:12],
        [stack.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:14],
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:panel.trailingAnchor constant:-14]
    ]];

    [stack addArrangedSubview:[self sectionLabelWithString:@"Track"]];
    self.trackNameField = [NSTextField textFieldWithString:@"Track"];
    self.trackNameField.target = self;
    self.trackNameField.action = @selector(trackNameFieldChanged:);
    [self.trackNameField.widthAnchor constraintEqualToConstant:210].active = YES;
    [stack addArrangedSubview:self.trackNameField];

    self.instrumentPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (NSInteger i = ChipInstrumentPulse12; i <= ChipInstrumentWavetable; i++) {
        [self.instrumentPopup addItemWithTitle:ChipInstrumentDisplayName((ChipInstrument)i)];
    }
    self.instrumentPopup.target = self;
    self.instrumentPopup.action = @selector(instrumentChanged:);
    [self.instrumentPopup.widthAnchor constraintEqualToConstant:210].active = YES;
    [stack addArrangedSubview:self.instrumentPopup];

    self.volumeSlider = [self sliderWithMin:0 max:1 value:0.7 action:@selector(volumeChanged:)];
    self.volumeValueLabel = [self valueLabel];
    [stack addArrangedSubview:[self rowWithLabel:@"Volume" control:self.volumeSlider value:self.volumeValueLabel]];
    self.panSlider = [self sliderWithMin:-1 max:1 value:0 action:@selector(panChanged:)];
    self.panValueLabel = [self valueLabel];
    [stack addArrangedSubview:[self rowWithLabel:@"Pan" control:self.panSlider value:self.panValueLabel]];

    self.muteCheck = [NSButton checkboxWithTitle:@"Mute" target:self action:@selector(muteChanged:)];
    self.soloCheck = [NSButton checkboxWithTitle:@"Solo" target:self action:@selector(soloChanged:)];
    NSStackView *muteSolo = [NSStackView stackViewWithViews:@[self.muteCheck, self.soloCheck]];
    muteSolo.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    muteSolo.spacing = 16;
    [stack addArrangedSubview:muteSolo];

    [stack addArrangedSubview:[self sectionLabelWithString:@"Effects"]];
    self.vibratoDepthSlider = [self sliderWithMin:0 max:1 value:0 action:@selector(vibratoDepthChanged:)];
    self.vibratoDepthValueLabel = [self valueLabel];
    [stack addArrangedSubview:[self rowWithLabel:@"Vibrato" control:self.vibratoDepthSlider value:self.vibratoDepthValueLabel]];
    self.vibratoRateSlider = [self sliderWithMin:0.1 max:12 value:5 action:@selector(vibratoRateChanged:)];
    self.vibratoRateValueLabel = [self valueLabel];
    [stack addArrangedSubview:[self rowWithLabel:@"Rate" control:self.vibratoRateSlider value:self.vibratoRateValueLabel]];
    self.slideCheck = [NSButton checkboxWithTitle:@"Pitch slide" target:self action:@selector(slideChanged:)];
    [stack addArrangedSubview:self.slideCheck];

    self.arpeggioPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.arpeggioPopup addItemsWithTitles:@[@"Arpeggio: Off", @"Arpeggio: Major", @"Arpeggio: Minor", @"Arpeggio: Octave"]];
    self.arpeggioPopup.target = self;
    self.arpeggioPopup.action = @selector(arpeggioChanged:);
    [self.arpeggioPopup.widthAnchor constraintEqualToConstant:210].active = YES;
    [stack addArrangedSubview:self.arpeggioPopup];

    [stack addArrangedSubview:[self sectionLabelWithString:@"Generation"]];
    NSTextField *hint = [self labelWithString:@"Generate creates a new seeded song.\nRegenerate Track keeps the seed."];
    hint.maximumNumberOfLines = 3;
    hint.lineBreakMode = NSLineBreakByWordWrapping;
    [hint.widthAnchor constraintEqualToConstant:210].active = YES;
    [stack addArrangedSubview:hint];
    NSButton *regenerate = [NSButton buttonWithTitle:@"Regenerate Track" target:self action:@selector(regenerateTrack:)];
    regenerate.bezelStyle = NSBezelStyleRounded;
    [regenerate.widthAnchor constraintEqualToConstant:210].active = YES;
    [stack addArrangedSubview:regenerate];
    NSButton *ai = [NSButton buttonWithTitle:@"AI Composition…" target:self action:@selector(showAIPanel:)];
    ai.bezelStyle = NSBezelStyleRounded;
    [ai.widthAnchor constraintEqualToConstant:210].active = YES;
    [stack addArrangedSubview:ai];

    return panel;
}

- (NSSlider *)sliderWithMin:(double)min max:(double)max value:(double)value action:(SEL)action {
    NSSlider *slider = [NSSlider sliderWithValue:value minValue:min maxValue:max target:self action:action];
    slider.continuous = YES;
    [slider.widthAnchor constraintEqualToConstant:142].active = YES;
    return slider;
}

- (NSTextField *)valueLabel {
    NSTextField *label = [NSTextField labelWithString:@"0"];
    label.font = [NSFont monospacedDigitSystemFontOfSize:9 weight:NSFontWeightRegular];
    label.alignment = NSTextAlignmentRight;
    [label.widthAnchor constraintEqualToConstant:46].active = YES;
    return label;
}

- (NSView *)rowWithLabel:(NSString *)text control:(NSControl *)control value:(NSTextField *)value {
    NSStackView *row = [NSStackView stackViewWithViews:@[[self labelWithString:text], control, value]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 6;
    return row;
}

- (void)buildStatusBarInView:(NSView *)root {
    NSView *statusBar = [[NSView alloc] init];
    statusBar.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:statusBar];
    self.statusLabel = [NSTextField labelWithString:@"Ready"];
    self.statusLabel.font = [NSFont monospacedDigitSystemFontOfSize:10 weight:NSFontWeightRegular];
    self.statusLabel.textColor = [NSColor secondaryLabelColor];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [statusBar addSubview:self.statusLabel];
    [NSLayoutConstraint activateConstraints:@[
        [statusBar.topAnchor constraintEqualToAnchor:self.splitBottomAnchor],
        [statusBar.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [statusBar.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [statusBar.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [statusBar.heightAnchor constraintEqualToConstant:24],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:statusBar.leadingAnchor constant:12],
        [self.statusLabel.centerYAnchor constraintEqualToAnchor:statusBar.centerYAnchor]
    ]];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.audioEngine = [[AudioEngine alloc] init];
    self.audioEngine.song = self.document.song;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(documentDidChange:) name:SongDocumentDidChangeNotification object:self.document];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(editorScrollViewDidLiveScroll:)
                                                 name:NSScrollViewDidLiveScrollNotification
                                               object:self.editorScrollView];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(timelineDidScrollByUser:)
                                                 name:ChiptuneTimelineDidScrollByUserNotification
                                               object:nil];
    [self refreshUI];
    [self followChanged:nil];

    self.playheadTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 30.0 target:self selector:@selector(updatePlayhead:) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.playheadTimer forMode:NSRunLoopCommonModes];
}

- (void)viewDidAppear {
    [super viewDidAppear];
    dispatch_async(dispatch_get_main_queue(), ^{
        CGFloat width = self.splitView.bounds.size.width;
        if (width > 700) {
            [self.splitView setPosition:224 ofDividerAtIndex:0];
            [self.splitView setPosition:width - 258 ofDividerAtIndex:1];
        }
    });
    if (!self.didPrepareAudio) {
        self.didPrepareAudio = YES;
        NSError *error = nil;
        if (![self.audioEngine prepareWithError:&error]) {
            self.statusLabel.stringValue = [NSString stringWithFormat:@"Audio unavailable: %@", error.localizedDescription ?: @"unknown error"];
        }
    }
#if DEBUG
    [self maybeRunSnapshotAutomation];
    [self maybeRunAIAutomation];
#endif
}

- (NSView *)preferredFirstResponder {
    return self.stepView;
}

- (Track *)selectedTrack {
    return [self.document.song trackAtIndex:self.currentTrackIndex];
}

- (void)documentDidChange:(NSNotification *)notification {
    Song *song = self.document.song;
    if (self.audioEngine.song != song) {
        // Opening, reverting, or undoing replaces the Song object. Point the
        // engine at the new model before rebuilding its event schedule.
        self.audioEngine.song = song;
    } else if (!self.suppressAudioReload) {
        [self.audioEngine reloadSong];
    }
    [self refreshUI];
}

- (void)performLiveEditNamed:(NSString *)actionName block:(void (^)(Song *song))block {
    self.suppressAudioReload = YES;
    [self.document performEditNamed:actionName block:block];
    self.suppressAudioReload = NO;
}

- (void)applyLiveTrackSettingsAtIndex:(NSInteger)index {
    Track *track = [self.document.song trackAtIndex:index];
    if (!track) return;
    [self.audioEngine setTrackInstrument:track.instrument
                                 params:ChipInstrumentParamsForTrack(track)
                                atIndex:index];
    [self.audioEngine setTrackVolume:track.volume atIndex:index];
    [self.audioEngine setTrackPan:track.pan atIndex:index];
    [self.audioEngine setTrackMuted:track.muted atIndex:index];
    [self.audioEngine setTrackSoloed:track.soloed atIndex:index];
}

- (void)refreshUI {
    if (self.refreshing) return;
    self.refreshing = YES;
    Song *song = self.document.song;
    self.tempoField.stringValue = [NSString stringWithFormat:@"%.0f", song.tempo];
    self.barsValueLabel.stringValue = [NSString stringWithFormat:@"%ld", (long)song.lengthBars];
    self.barsStepper.integerValue = song.lengthBars;
    [self.keyPopup selectItemAtIndex:MAX(0, MIN(11, song.keyRoot))];
    [self.scalePopup selectItemAtIndex:MAX(0, MIN(9, song.scale))];
    self.seedField.stringValue = [NSString stringWithFormat:@"%llu", (unsigned long long)song.generationSeed];
    if (self.currentTrackIndex >= (NSInteger)song.tracks.count) {
        self.currentTrackIndex = MAX(0, (NSInteger)song.tracks.count - 1);
    }
    [self.trackTable reloadData];
    if (song.tracks.count > 0) {
        [self.trackTable selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)self.currentTrackIndex] byExtendingSelection:NO];
    }
    [self updateInspector];
    self.stepView.currentTrackIndex = self.currentTrackIndex;
    self.stepView.selectedPitch = self.selectedPitch;
    [self.stepView reloadData];
    self.pianoRollView.currentTrackIndex = self.currentTrackIndex;
    [self.pianoRollView reloadData];
    self.playButton.title = self.audioEngine.isPlaying ? @"❚❚ Pause" : @"▶ Play";
    if (self.view.window) {
        self.view.window.title = song.title.length ? song.title : @"Untitled";
        self.view.window.representedURL = self.document.fileURL;
        self.view.window.documentEdited = self.document.isDocumentEdited;
    }
    self.refreshing = NO;
}

- (void)updateInspector {
    Track *track = [self selectedTrack];
    if (!track) return;
    self.trackNameField.stringValue = track.name;
    [self.instrumentPopup selectItemAtIndex:MAX(0, MIN(5, track.instrument))];
    self.volumeSlider.doubleValue = track.volume;
    self.volumeValueLabel.stringValue = [NSString stringWithFormat:@"%.2f", track.volume];
    self.panSlider.doubleValue = track.pan;
    self.panValueLabel.stringValue = [NSString stringWithFormat:@"%+.2f", track.pan];
    self.muteCheck.state = track.muted ? NSControlStateValueOn : NSControlStateValueOff;
    self.soloCheck.state = track.soloed ? NSControlStateValueOn : NSControlStateValueOff;
    self.vibratoDepthSlider.doubleValue = track.vibratoDepth;
    self.vibratoDepthValueLabel.stringValue = [NSString stringWithFormat:@"%.2f", track.vibratoDepth];
    self.vibratoRateSlider.doubleValue = track.vibratoRate;
    self.vibratoRateValueLabel.stringValue = [NSString stringWithFormat:@"%.1f", track.vibratoRate];
    self.slideCheck.state = track.slideEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    [self.arpeggioPopup selectItemAtIndex:MAX(0, MIN(3, track.arpeggio))];
}

- (void)updatePlayhead:(NSTimer *)timer {
    Song *song = self.document.song;
    double tick = self.audioEngine.currentTick;
    self.stepView.playheadTick = (uint64_t)MAX(0.0, tick);
    self.pianoRollView.playheadTick = (uint64_t)MAX(0.0, tick);
    uint64_t ticksPerBar = MAX(1ULL, song.ticksPerBar);
    NSInteger bar = (NSInteger)(tick / (double)ticksPerBar);
    double beatTick = fmod(tick, (double)ticksPerBar);
    NSInteger beat = (NSInteger)(beatTick / (double)song.ppq) + 1;
    NSInteger beatCount = song.timeSignatureNumerator;
    BOOL playing = self.audioEngine.isPlaying;
    NSString *transport = playing ? @"Playing" : @"Stopped";
    self.statusLabel.stringValue = [NSString stringWithFormat:@"Bar %ld/%ld · Beat %ld/%ld · %@",
                                    (long)MIN(bar + 1, song.lengthBars), (long)song.lengthBars,
                                    (long)MIN(beat, beatCount), (long)beatCount, transport];
    NSString *title = playing ? @"❚❚ Pause" : @"▶ Play";
    if (![self.playButton.title isEqualToString:title]) {
        self.playButton.title = title;
    }
}

#pragma mark - Transport

- (void)keyDown:(NSEvent *)event {
    NSEventModifierFlags modifiers = event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagControl);
    if (modifiers == 0) {
        if (event.keyCode == 49) { // Space
            [self togglePlayback:nil];
            return;
        }
        if (event.keyCode == 36 || event.keyCode == 76) { // Return / Enter
            [self stopPlayback:nil];
            return;
        }
    }
    [super keyDown:event];
}

- (void)togglePlayback:(id)sender {
    if (self.audioEngine.isPlaying) {
        [self.audioEngine pause];
    } else {
        if (self.audioEngine.currentTick >= (double)self.document.song.totalTicks) {
            [self.audioEngine seekToTick:0];
        }
        [self.audioEngine play];
    }
    self.playButton.title = self.audioEngine.isPlaying ? @"❚❚ Pause" : @"▶ Play";
}

- (void)stopPlayback:(id)sender {
    [self.audioEngine stop];
    self.playButton.title = @"▶ Play";
}

- (void)loopChanged:(id)sender {
    [self.audioEngine setLoopStartTick:0 endTick:self.document.song.totalTicks enabled:(self.loopCheck.state == NSControlStateValueOn)];
}

- (void)followChanged:(id)sender {
    self.followPlayhead = self.followCheck.state == NSControlStateValueOn;
    self.stepView.followPlayhead = self.followPlayhead;
    self.pianoRollView.followPlayhead = self.followPlayhead;
}

- (void)stopFollowingForManualScroll {
    // If the user manually scrolls during playback, stop chasing the playhead
    // so the timeline stays where they put it. Playback itself still runs.
    if (!self.followPlayhead || !self.audioEngine.isPlaying) return;
    self.followCheck.state = NSControlStateValueOff;
    [self followChanged:nil];
}

- (void)editorScrollViewDidLiveScroll:(NSNotification *)notification {
    [self stopFollowingForManualScroll];
}

- (void)timelineDidScrollByUser:(NSNotification *)notification {
    [self stopFollowingForManualScroll];
}

- (void)modeChanged:(id)sender {
    if (self.modeControl.selectedSegment == 0) {
        self.editorScrollView.documentView = self.stepView;
        [self.stepView reloadData];
    } else {
        self.editorScrollView.documentView = self.pianoRollView;
        [self.pianoRollView reloadData];
    }
}

- (void)showStepSequencer:(id)sender {
    self.modeControl.selectedSegment = 0;
    [self modeChanged:nil];
}

- (void)showPianoRoll:(id)sender {
    self.modeControl.selectedSegment = 1;
    [self modeChanged:nil];
}

- (void)toggleFollowPlayhead:(id)sender {
    self.followCheck.state = self.followCheck.state == NSControlStateValueOn ? NSControlStateValueOff : NSControlStateValueOn;
    [self followChanged:nil];
}

#pragma mark - Song settings

- (void)tempoChanged:(id)sender {
    if (self.refreshing) return;
    double value = self.tempoField.doubleValue;
    if (value < 40 || value > 300) {
        [self refreshUI];
        return;
    }
    [self performLiveEditNamed:@"Change Tempo" block:^(Song *song) { song.tempo = value; }];
    [self.audioEngine setTempo:value];
    [self refreshUI];
}

- (void)barsChanged:(id)sender {
    if (self.refreshing) return;
    NSInteger bars = MAX(1, MIN(16, self.barsStepper.integerValue));
    [self.document performEditNamed:@"Change Song Length" block:^(Song *song) {
        song.lengthBars = bars;
        NSMutableArray<SongSection *> *sections = [NSMutableArray array];
        for (SongSection *section in song.sections) {
            if (section.startBar >= bars) continue;
            section.lengthBars = MIN(section.lengthBars, bars - section.startBar);
            if (section.lengthBars > 0) [sections addObject:section];
        }
        if (sections.count == 0) {
            [sections addObject:[SongSection sectionWithName:@"Main" startBar:0 lengthBars:bars]];
        }
        song.sections = sections;
        uint64_t total = song.totalTicks;
        for (Track *track in song.tracks) {
            NSMutableArray<NoteEvent *> *keep = [NSMutableArray array];
            for (NoteEvent *note in track.notes) {
                if (note.startTick < total) [keep addObject:note];
            }
            track.notes = keep;
        }
    }];
    [self refreshUI];
}

- (void)keyChanged:(id)sender {
    if (self.refreshing) return;
    NSInteger root = self.keyPopup.indexOfSelectedItem;
    NSInteger previousRoot = self.document.song.keyRoot;
    NSInteger delta = ((root - previousRoot) % 12 + 12) % 12;
    if (delta > 6) delta -= 12;
    [self.document performEditNamed:@"Change Key" block:^(Song *song) {
        song.keyRoot = root;
        [song transposePitchedNotesBySemitones:delta];
    }];
    [self refreshUI];
}

- (void)scaleChanged:(id)sender {
    if (self.refreshing) return;
    MusicalScale scale = (MusicalScale)self.scalePopup.indexOfSelectedItem;
    [self.document performEditNamed:@"Change Scale" block:^(Song *song) {
        song.scale = scale;
        [song quantizePitchedNotesToScale:scale root:song.keyRoot];
    }];
    [self refreshUI];
}

- (void)pitchChanged:(id)sender {
    [self updateSelectedPitch];
}

- (void)octaveChanged:(id)sender {
    [self updateSelectedPitch];
}

- (void)updateSelectedPitch {
    NSInteger noteIndex = self.pitchPopup.indexOfSelectedItem;
    NSInteger octave = self.octaveStepper.integerValue;
    self.selectedPitch = MAX(0, MIN(127, (octave + 1) * 12 + noteIndex));
    self.stepView.selectedPitch = self.selectedPitch;
}

- (void)seedChanged:(id)sender {
    if (self.refreshing) return;
    uint64_t seed = strtoull(self.seedField.stringValue.UTF8String, NULL, 10);
    [self performLiveEditNamed:@"Change Seed" block:^(Song *song) { song.generationSeed = seed; }];
}

#pragma mark - Generation

- (void)generateSong:(id)sender {
    uint64_t seed = ((uint64_t)arc4random() << 32) | (uint64_t)arc4random();
    [self.document performEditNamed:@"Generate Song" block:^(Song *song) {
        [PatternGenerator generateSong:song seed:seed];
    }];
    [self refreshUI];
}

- (void)regenerateTrack:(id)sender {
    Song *song = self.document.song;
    NSInteger trackIndex = self.currentTrackIndex;
    uint64_t seed = song.generationSeed;
    if (seed == 0) {
        seed = ((uint64_t)arc4random() << 32) | (uint64_t)arc4random();
    }
    [self.document performEditNamed:@"Regenerate Track" block:^(Song *edited) {
        Track *track = [edited trackAtIndex:trackIndex];
        if (!track) return;
        [track.notes removeAllObjects];
        for (NSInteger i = 0; i < (NSInteger)edited.sections.count; i++) {
            [PatternGenerator generateTrack:track inSong:edited seed:seed section:edited.sections[(NSUInteger)i] trackIndex:trackIndex sectionIndex:i];
        }
    }];
    [self refreshUI];
}

#pragma mark - Tracks

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)self.document.song.tracks.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    Track *track = self.document.song.tracks[(NSUInteger)row];
    if ([tableColumn.identifier isEqualToString:@"name"]) {
        NSTableCellView *cell = [tableView makeViewWithIdentifier:@"NameCell" owner:self];
        if (!cell) {
            cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 142, 30)];
            cell.identifier = @"NameCell";
            NSTextField *field = [[NSTextField alloc] init];
            field.bordered = NO;
            field.drawsBackground = NO;
            field.editable = YES;
            field.delegate = self;
            field.target = self;
            field.action = @selector(trackNameAction:);
            field.translatesAutoresizingMaskIntoConstraints = NO;
            [cell addSubview:field];
            cell.textField = field;
            [NSLayoutConstraint activateConstraints:@[
                [field.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:4],
                [field.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4],
                [field.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]
            ]];
        }
        cell.textField.stringValue = track.name;
        cell.textField.tag = row;
        cell.textField.textColor = ChiptuneTrackColor(row);
        return cell;
    }
    BOOL isMute = [tableColumn.identifier isEqualToString:@"mute"];
    NSString *identifier = isMute ? @"MuteButton" : @"SoloButton";
    NSButton *button = [tableView makeViewWithIdentifier:identifier owner:self];
    if (!button) {
        button = [NSButton buttonWithTitle:(isMute ? @"M" : @"S") target:self action:(isMute ? @selector(toggleMute:) : @selector(toggleSolo:))];
        button.identifier = identifier;
        button.buttonType = NSButtonTypeToggle;
        button.bezelStyle = NSBezelStyleInline;
        button.font = [NSFont systemFontOfSize:10 weight:NSFontWeightSemibold];
    }
    button.tag = row;
    button.state = (isMute ? track.muted : track.soloed) ? NSControlStateValueOn : NSControlStateValueOff;
    return button;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = self.trackTable.selectedRow;
    if (row < 0) return;
    self.currentTrackIndex = row;
    self.stepView.currentTrackIndex = row;
    self.pianoRollView.currentTrackIndex = row;
    [self updateInspector];
    [self.stepView setNeedsDisplay:YES];
    [self.pianoRollView setNeedsDisplay:YES];
}

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    NSTextField *field = notification.object;
    if (field == self.trackNameField) {
        [self commitTrackName:field.stringValue atIndex:self.currentTrackIndex];
    } else if (field.tag >= 0) {
        [self commitTrackName:field.stringValue atIndex:field.tag];
    }
}

- (void)trackNameAction:(NSTextField *)sender {
    [self commitTrackName:sender.stringValue atIndex:sender.tag];
}

- (void)trackNameFieldChanged:(id)sender {
    [self commitTrackName:self.trackNameField.stringValue atIndex:self.currentTrackIndex];
}

- (void)commitTrackName:(NSString *)name atIndex:(NSInteger)index {
    if (self.refreshing) return;
    if (name.length == 0) name = @"Track";
    [self performLiveEditNamed:@"Rename Track" block:^(Song *song) {
        Track *track = [song trackAtIndex:index];
        if (track) track.name = name;
    }];
    [self refreshUI];
}

- (void)toggleMute:(NSButton *)sender {
    NSInteger index = sender.tag;
    [self performLiveEditNamed:@"Mute Track" block:^(Song *song) {
        Track *track = [song trackAtIndex:index];
        if (track) track.muted = !track.muted;
    }];
    Track *track = [self.document.song trackAtIndex:index];
    if (track) [self.audioEngine setTrackMuted:track.muted atIndex:index];
    [self refreshUI];
}

- (void)toggleSolo:(NSButton *)sender {
    NSInteger index = sender.tag;
    [self performLiveEditNamed:@"Solo Track" block:^(Song *song) {
        Track *track = [song trackAtIndex:index];
        if (track) track.soloed = !track.soloed;
    }];
    Track *track = [self.document.song trackAtIndex:index];
    if (track) [self.audioEngine setTrackSoloed:track.soloed atIndex:index];
    [self refreshUI];
}

- (void)addTrack:(id)sender {
    Song *song = self.document.song;
    if (song.tracks.count >= 8) {
        NSBeep();
        return;
    }
    ChipInstrument instruments[] = {ChipInstrumentPulse25, ChipInstrumentPulse12, ChipInstrumentTriangle, ChipInstrumentNoise, ChipInstrumentWavetable, ChipInstrumentPulse50, ChipInstrumentPulse12, ChipInstrumentPulse25};
    ChipInstrument instrument = instruments[song.tracks.count % 8];
    [self.document performEditNamed:@"Add Track" block:^(Song *edited) {
        Track *track = [Track trackWithName:[NSString stringWithFormat:@"Track %ld", (long)(edited.tracks.count + 1)] instrument:instrument];
        [edited.tracks addObject:track];
    }];
    self.currentTrackIndex = (NSInteger)song.tracks.count - 1;
    [self refreshUI];
}

- (void)removeTrack:(id)sender {
    Song *song = self.document.song;
    if (song.tracks.count <= 1) {
        NSBeep();
        return;
    }
    NSInteger index = self.currentTrackIndex;
    [self.document performEditNamed:@"Remove Track" block:^(Song *edited) {
        if (index >= 0 && index < (NSInteger)edited.tracks.count) {
            [edited.tracks removeObjectAtIndex:(NSUInteger)index];
        }
    }];
    self.currentTrackIndex = MAX(0, MIN(index, (NSInteger)song.tracks.count - 1));
    [self refreshUI];
}

#pragma mark - Track inspector actions

- (void)instrumentChanged:(id)sender {
    if (self.refreshing) return;
    ChipInstrument instrument = (ChipInstrument)self.instrumentPopup.indexOfSelectedItem;
    NSInteger index = self.currentTrackIndex;
    [self performLiveEditNamed:@"Change Instrument" block:^(Song *song) {
        Track *track = [song trackAtIndex:index];
        if (track) track.instrument = instrument;
    }];
    [self applyLiveTrackSettingsAtIndex:index];
    [self refreshUI];
}

- (void)volumeChanged:(id)sender {
    if (self.refreshing) return;
    double value = self.volumeSlider.doubleValue;
    NSInteger index = self.currentTrackIndex;
    [self performLiveEditNamed:@"Change Volume" block:^(Song *song) {
        Track *track = [song trackAtIndex:index];
        if (track) track.volume = value;
    }];
    self.volumeValueLabel.stringValue = [NSString stringWithFormat:@"%.2f", value];
    [self.audioEngine setTrackVolume:value atIndex:index];
}

- (void)panChanged:(id)sender {
    if (self.refreshing) return;
    double value = self.panSlider.doubleValue;
    NSInteger index = self.currentTrackIndex;
    [self performLiveEditNamed:@"Change Pan" block:^(Song *song) {
        Track *track = [song trackAtIndex:index];
        if (track) track.pan = value;
    }];
    self.panValueLabel.stringValue = [NSString stringWithFormat:@"%+.2f", value];
    [self.audioEngine setTrackPan:value atIndex:index];
}

- (void)muteChanged:(id)sender {
    if (self.refreshing) return;
    BOOL muted = self.muteCheck.state == NSControlStateValueOn;
    NSInteger index = self.currentTrackIndex;
    [self performLiveEditNamed:@"Mute Track" block:^(Song *song) {
        Track *track = [song trackAtIndex:index];
        if (track) track.muted = muted;
    }];
    [self.audioEngine setTrackMuted:muted atIndex:index];
}

- (void)soloChanged:(id)sender {
    if (self.refreshing) return;
    BOOL soloed = self.soloCheck.state == NSControlStateValueOn;
    NSInteger index = self.currentTrackIndex;
    [self performLiveEditNamed:@"Solo Track" block:^(Song *song) {
        Track *track = [song trackAtIndex:index];
        if (track) track.soloed = soloed;
    }];
    [self.audioEngine setTrackSoloed:soloed atIndex:index];
}

- (void)vibratoDepthChanged:(id)sender {
    if (self.refreshing) return;
    double value = self.vibratoDepthSlider.doubleValue;
    NSInteger index = self.currentTrackIndex;
    [self performLiveEditNamed:@"Change Vibrato" block:^(Song *song) {
        Track *track = [song trackAtIndex:index];
        if (track) track.vibratoDepth = value;
    }];
    self.vibratoDepthValueLabel.stringValue = [NSString stringWithFormat:@"%.2f", value];
    [self applyLiveTrackSettingsAtIndex:index];
}

- (void)vibratoRateChanged:(id)sender {
    if (self.refreshing) return;
    double value = self.vibratoRateSlider.doubleValue;
    NSInteger index = self.currentTrackIndex;
    [self performLiveEditNamed:@"Change Vibrato Rate" block:^(Song *song) {
        Track *track = [song trackAtIndex:index];
        if (track) track.vibratoRate = value;
    }];
    self.vibratoRateValueLabel.stringValue = [NSString stringWithFormat:@"%.1f", value];
    [self applyLiveTrackSettingsAtIndex:index];
}

- (void)slideChanged:(id)sender {
    if (self.refreshing) return;
    BOOL enabled = self.slideCheck.state == NSControlStateValueOn;
    NSInteger index = self.currentTrackIndex;
    [self performLiveEditNamed:@"Change Slide" block:^(Song *song) {
        Track *track = [song trackAtIndex:index];
        if (track) track.slideEnabled = enabled;
    }];
    [self applyLiveTrackSettingsAtIndex:index];
}

- (void)arpeggioChanged:(id)sender {
    if (self.refreshing) return;
    NSInteger value = self.arpeggioPopup.indexOfSelectedItem;
    NSInteger index = self.currentTrackIndex;
    [self performLiveEditNamed:@"Change Arpeggio" block:^(Song *song) {
        Track *track = [song trackAtIndex:index];
        if (track) track.arpeggio = value;
    }];
    [self applyLiveTrackSettingsAtIndex:index];
}

#pragma mark - Export

- (NSView *)buildExportAccessoryView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 104)];
    NSTextField *formatLabel = [self labelWithString:@"Format:"];
    formatLabel.frame = NSMakeRect(0, 74, 76, 20);
    [view addSubview:formatLabel];

    self.exportFormatPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(80, 69, 200, 26) pullsDown:NO];
    [self.exportFormatPopup addItemsWithTitles:@[@"FLAC (lossless)", @"MP3 (LAME)", @"WAV (16-bit)", @"MIDI", @"LSDj (.lsdsng)"]];
    self.exportFormatPopup.target = self;
    self.exportFormatPopup.action = @selector(exportFormatChanged:);
    [view addSubview:self.exportFormatPopup];

    NSTextField *bitrateLabel = [self labelWithString:@"Bitrate:"];
    bitrateLabel.frame = NSMakeRect(0, 42, 76, 20);
    [view addSubview:bitrateLabel];

    self.exportBitratePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(80, 37, 200, 26) pullsDown:NO];
    [self.exportBitratePopup addItemsWithTitles:@[@"128 kbps", @"192 kbps", @"256 kbps", @"320 kbps"]];
    [self.exportBitratePopup selectItemAtIndex:1];
    self.exportBitratePopup.enabled = NO;
    [view addSubview:self.exportBitratePopup];

    self.exportNormalizeCheck = [NSButton checkboxWithTitle:@"Normalize audio to -1 dBFS" target:nil action:nil];
    self.exportNormalizeCheck.frame = NSMakeRect(80, 8, 210, 20);
    self.exportNormalizeCheck.state = NSControlStateValueOn;
    [view addSubview:self.exportNormalizeCheck];
    return view;
}

- (void)exportFormatChanged:(id)sender {
    NSArray<NSString *> *extensions = @[@"flac", @"mp3", @"wav", @"mid", @"lsdsng"];
    NSInteger index = MAX(0, MIN((NSInteger)extensions.count - 1, self.exportFormatPopup.indexOfSelectedItem));
    NSString *extension = extensions[(NSUInteger)index];
    self.exportBitratePopup.enabled = (index == 1);
    self.exportNormalizeCheck.enabled = (index <= 2);
    if (self.activeSavePanel) {
        UTType *type = [UTType typeWithFilenameExtension:extension];
        if (type) self.activeSavePanel.allowedContentTypes = @[type];
        NSString *base = [self.document.song.title stringByDeletingPathExtension];
        if (base.length == 0) base = @"Untitled";
        self.activeSavePanel.nameFieldStringValue = [base stringByAppendingPathExtension:extension];
    }
}

- (void)exportSong:(id)sender {
    Song *song = self.document.song;
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.title = @"Export Song";
    NSString *exportBaseName = song.title.length > 0 ? song.title : @"Untitled";
    panel.nameFieldStringValue = [exportBaseName stringByAppendingPathExtension:@"flac"];
    UTType *flacType = [UTType typeWithFilenameExtension:@"flac"];
    if (flacType) panel.allowedContentTypes = @[flacType];
    panel.accessoryView = [self buildExportAccessoryView];
    self.activeSavePanel = panel;
    __weak typeof(self) weakSelf = self;
    [panel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse response) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        if (response != NSModalResponseOK || !panel.URL) {
            self.activeSavePanel = nil;
            return;
        }
        Song *snapshot = [self.document.song copy];
        ExportOptions *options = [ExportOptions defaultOptions];
        NSArray<NSNumber *> *formats = @[@(ExportFormatFLAC), @(ExportFormatMP3), @(ExportFormatWAV), @(ExportFormatMIDI), @(ExportFormatLSDj)];
        NSInteger index = MAX(0, MIN((NSInteger)formats.count - 1, self.exportFormatPopup.indexOfSelectedItem));
        options.format = formats[(NSUInteger)index].integerValue;
        NSArray<NSNumber *> *bitrates = @[@128, @192, @256, @320];
        options.mp3Bitrate = bitrates[(NSUInteger)MAX(0, MIN(3, self.exportBitratePopup.indexOfSelectedItem))].integerValue;
        options.normalize = self.exportNormalizeCheck.state == NSControlStateValueOn;
        self.progressIndicator.hidden = NO;
        [self.progressIndicator startAnimation:nil];
        self.statusLabel.stringValue = @"Exporting…";
        NSURL *url = panel.URL;
        [ExportService exportSong:snapshot toURL:url options:options progress:^(double progress) {
            self.statusLabel.stringValue = [NSString stringWithFormat:@"Exporting… %.0f%%", progress * 100.0];
        } completion:^(NSError *error) {
            [self.progressIndicator stopAnimation:nil];
            self.progressIndicator.hidden = YES;
            self.activeSavePanel = nil;
            if (error) {
                self.statusLabel.stringValue = @"Export failed";
                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = @"Export Failed";
                alert.informativeText = error.localizedDescription ?: @"Unknown export error.";
                [alert beginSheetModalForWindow:self.view.window completionHandler:nil];
            } else {
                self.statusLabel.stringValue = [NSString stringWithFormat:@"Exported %@", url.lastPathComponent];
                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = @"Export Complete";
                alert.informativeText = url.path;
                [alert addButtonWithTitle:@"Show in Finder"];
                [alert addButtonWithTitle:@"OK"];
                [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse response) {
                    if (response == NSAlertFirstButtonReturn) {
                        [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[url]];
                    }
                }];
            }
        }];
    }];
}

#pragma mark - AI

- (void)showAIPanel:(id)sender {
    if (!self.aiWindowController) {
        self.aiWindowController = [[AIGeneratorWindowController alloc] initWithDocument:self.document];
    }
    __weak typeof(self) weakSelf = self;
    [self.view.window beginSheet:self.aiWindowController.window completionHandler:^(NSModalResponse returnCode) {
        __strong typeof(weakSelf) self = weakSelf;
        self.aiWindowController = nil;
        [self refreshUI];
    }];
}

#if DEBUG
#pragma mark - Snapshot automation

- (void)maybeRunSnapshotAutomation {
    if (self.didRunSnapshotAutomation) return;
    NSString *directory = [NSProcessInfo processInfo].environment[@"CHIPTUNE_SNAPSHOT_DIR"];
    if (directory.length == 0) return;
    self.didRunSnapshotAutomation = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self runSnapshotAutomationInDirectory:directory];
    });
}

- (void)maybeRunAIAutomation {
    if (self.didRunAIAutomation) return;
    NSString *reportPath = [NSProcessInfo processInfo].environment[@"CHIPTUNE_AI_REPORT"];
    if (reportPath.length == 0) return;
    self.didRunAIAutomation = YES;
    [[NSFileManager defaultManager] removeItemAtPath:reportPath error:NULL];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self showAIPanel:nil];
        [self waitForAIReportAtPath:reportPath attempts:0];
    });
}

- (void)waitForAIReportAtPath:(NSString *)path attempts:(NSInteger)attempts {
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        NSLog(@"CHIPTUNE_AI_REPORT %@", path);
        fflush(stdout);
        exit(0);
    }
    if (attempts >= 360) {
        NSLog(@"CHIPTUNE_AI_REPORT_TIMEOUT %@", path);
        fflush(stdout);
        exit(2);
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self waitForAIReportAtPath:path attempts:attempts + 1];
    });
}

- (NSDictionary *)writeSnapshotOfView:(NSView *)view toFile:(NSString *)filename inDirectory:(NSString *)directory {
    if (!view) return nil;
    [view.window displayIfNeeded];
    [view layoutSubtreeIfNeeded];
    [view displayIfNeeded];
    NSRect bounds = view.bounds;
    if (bounds.size.width < 1 || bounds.size.height < 1) return nil;
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:bounds];
    if (!rep) return nil;
    [view cacheDisplayInRect:bounds toBitmapImageRep:rep];
    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    if (!png) return nil;
    NSString *path = [directory stringByAppendingPathComponent:filename];
    if (![png writeToFile:path atomically:YES]) return nil;
    return @{ @"path": path, @"bytes": @(png.length), @"width": @(rep.pixelsWide), @"height": @(rep.pixelsHigh) };
}

- (void)runSnapshotAutomationInDirectory:(NSString *)directory {
    if (!self.document || !self.view.window) return;
    NSMutableDictionary *report = [NSMutableDictionary dictionary];
    report[@"appVersion"] = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
    report[@"screenshots"] = [NSMutableDictionary dictionary];
    report[@"checks"] = [NSMutableDictionary dictionary];
    report[@"errors"] = [NSMutableArray array];

    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];

    [self.document performEditNamed:@"Snapshot Setup" block:^(Song *song) {
        song.title = @"Neon Circuit";
        song.author = @"Chiptune Maker";
        song.tempo = 132;
        song.timeSignatureNumerator = 4;
        song.timeSignatureDenominator = 4;
        song.keyRoot = 9;
        song.scale = MusicalScaleMinor;
        song.swing = 0.12;
        song.lengthBars = 8;
        song.generationDensity = 0.7;
        song.generationComplexity = 0.55;
        song.sections = [@[
            [SongSection sectionWithName:@"Intro" startBar:0 lengthBars:4],
            [SongSection sectionWithName:@"Chorus" startBar:4 lengthBars:4]
        ] mutableCopy];
        [PatternGenerator generateSong:song seed:0x5EEDC0FFEEULL];
    }];
    [self refreshUI];
    [self.stepView reloadData];
    [self.pianoRollView reloadData];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self captureScreenshotsAndContinueWithReport:report directory:directory];
    });
}

- (void)captureScreenshotsAndContinueWithReport:(NSMutableDictionary *)report directory:(NSString *)directory {
    if (!self.document || !self.view.window) return;
    NSMutableDictionary *screenshots = report[@"screenshots"];
    NSMutableArray *errors = report[@"errors"];
    NSMutableDictionary *checks = report[@"checks"];

    Song *song = self.document.song;
    checks[@"title"] = song.title ?: @"";
    checks[@"tracks"] = @(song.tracks.count);
    checks[@"sections"] = @(song.sections.count);
    NSUInteger visibleWindows = 0;
    for (NSWindow *window in NSApp.windows) {
        if (window.visible && window.windowController) visibleWindows++;
    }
    checks[@"launch"] = @{
        @"documents": @([NSDocumentController sharedDocumentController].documents.count),
        @"visibleDocumentWindows": @(visibleWindows)
    };
    NSMutableArray *documentInfo = [NSMutableArray array];
    for (NSDocument *document in [NSDocumentController sharedDocumentController].documents) {
        [documentInfo addObject:@{
            @"title": document.displayName ?: @"",
            @"url": document.fileURL.path ?: @"",
            @"edited": @(document.isDocumentEdited),
            @"windowControllers": @(document.windowControllers.count)
        }];
    }
    checks[@"launchDocuments"] = documentInfo;
    NSUInteger noteCount = 0;
    for (Track *track in song.tracks) noteCount += track.notes.count;
    checks[@"notes"] = @(noteCount);
    checks[@"windowFrame"] = NSStringFromRect(self.view.window.frame);
    checks[@"splitWidth"] = @(self.splitView.bounds.size.width);
    NSScroller *horizontalScroller = self.editorScrollView.horizontalScroller;
    checks[@"scrollView"] = @{
        @"frame": NSStringFromRect(self.editorScrollView.frame),
        @"documentFrame": NSStringFromRect(self.editorScrollView.documentView.frame),
        @"hasHorizontalScroller": @(self.editorScrollView.hasHorizontalScroller),
        @"autohidesScrollers": @(self.editorScrollView.autohidesScrollers),
        @"scrollerStyle": @(self.editorScrollView.scrollerStyle),
        @"horizontalScrollerHidden": @(horizontalScroller.hidden),
        @"horizontalScrollerFrame": NSStringFromRect(horizontalScroller.frame),
        @"horizontalScrollerAlpha": @(horizontalScroller.alphaValue)
    };

    NSDictionary *steps = [self writeSnapshotOfView:self.view.window.contentView toFile:@"01-steps.png" inDirectory:directory];
    if (steps) screenshots[@"steps"] = steps; else [errors addObject:@"Could not capture step sequencer screenshot."];

    [self showPianoRoll:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSDictionary *piano = [self writeSnapshotOfView:self.view.window.contentView toFile:@"02-piano-roll.png" inDirectory:directory];
        if (piano) screenshots[@"pianoRoll"] = piano; else [errors addObject:@"Could not capture piano roll screenshot."];

        [self showStepSequencer:nil];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self showAIPanel:nil];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                NSWindow *aiWindow = self.aiWindowController.window;
                NSDictionary *ai = [self writeSnapshotOfView:aiWindow.contentView toFile:@"03-ai-sheet.png" inDirectory:directory];
                if (ai) screenshots[@"aiSheet"] = ai; else [errors addObject:@"Could not capture AI sheet screenshot."];
                if (aiWindow.sheetParent) {
                    [aiWindow.sheetParent endSheet:aiWindow returnCode:NSModalResponseCancel];
                } else {
                    [aiWindow close];
                }
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    id delegate = NSApp.delegate;
                    if ([delegate respondsToSelector:@selector(showHelp:)]) {
                        [delegate performSelector:@selector(showHelp:) withObject:nil];
                    }
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        NSWindow *helpWindow = nil;
                        for (NSWindow *window in NSApp.windows) {
                            if ([window.title isEqualToString:@"Chiptune Maker Help"] && window.visible) {
                                helpWindow = window;
                                break;
                            }
                        }
                        if (helpWindow) {
                            NSDictionary *help = [self writeSnapshotOfView:helpWindow.contentView toFile:@"04-help.png" inDirectory:directory];
                            if (help) screenshots[@"help"] = help; else [errors addObject:@"Could not capture Help window screenshot."];
                            checks[@"help"] = @{ @"visible": @(helpWindow.visible), @"title": helpWindow.title ?: @"" };
                            [helpWindow close];
                        } else {
                            [errors addObject:@"Help window did not appear."];
                        }
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                            [self runRuntimeChecksWithReport:report directory:directory];
                        });
                    });
                });
            });
        });
    });
}

- (NSEvent *)mouseDownEventAtViewPoint:(NSPoint)viewPoint inView:(NSView *)view {
    NSPoint windowPoint = [view convertPoint:viewPoint toView:nil];
    return [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
                              location:windowPoint
                         modifierFlags:0
                             timestamp:[NSProcessInfo processInfo].systemUptime
                          windowNumber:view.window.windowNumber
                               context:nil
                           eventNumber:1
                            clickCount:1
                              pressure:1.0];
}

- (void)runRuntimeChecksWithReport:(NSMutableDictionary *)report directory:(NSString *)directory {
    if (!self.document || !self.view.window) return;
    NSMutableDictionary *checks = report[@"checks"];
    NSMutableArray *errors = report[@"errors"];
    Song *song = self.document.song;

    // Horizontal scrolling, mouse-wheel scrolling, and playhead following.
    NSClipView *clipView = self.editorScrollView.contentView;
    NSPoint originalOrigin = clipView.bounds.origin;
    CGFloat maxScrollX = MAX(0.0, self.stepView.bounds.size.width - clipView.bounds.size.width);
    CGFloat programmaticTarget = MIN(320.0, maxScrollX);
    [clipView scrollToPoint:NSMakePoint(programmaticTarget, originalOrigin.y)];
    [self.editorScrollView reflectScrolledClipView:clipView];
    BOOL programmaticScrollPassed = fabs(clipView.bounds.origin.x - programmaticTarget) < 1.0;
    [clipView scrollToPoint:originalOrigin];
    [self.editorScrollView reflectScrolledClipView:clipView];

    CGEventRef cgEvent = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitLine, 1, -4);
    NSEvent *wheelEvent = cgEvent ? [NSEvent eventWithCGEvent:cgEvent] : nil;
    if (cgEvent) CFRelease(cgEvent);
    if (wheelEvent) [self.stepView scrollWheel:wheelEvent];
    BOOL wheelScrollPassed = clipView.bounds.origin.x > originalOrigin.x + 1.0;
    [clipView scrollToPoint:originalOrigin];
    [self.editorScrollView reflectScrolledClipView:clipView];

    BOOL previousFollow = self.followPlayhead;
    self.followCheck.state = NSControlStateValueOn;
    [self followChanged:nil];
    uint64_t followTick = MAX(1ULL, song.totalTicks / 2);
    self.stepView.playheadTick = followTick;
    BOOL followScrollPassed = clipView.bounds.origin.x > originalOrigin.x + 1.0;
    BOOL followStillOn = self.followPlayhead;
    [clipView scrollToPoint:originalOrigin];
    [self.editorScrollView reflectScrolledClipView:clipView];
    self.followCheck.state = previousFollow ? NSControlStateValueOn : NSControlStateValueOff;
    [self followChanged:nil];

    checks[@"scrolling"] = @{
        @"maxScrollX": @(maxScrollX),
        @"programmatic": @(programmaticScrollPassed),
        @"wheel": @(wheelScrollPassed),
        @"follow": @(followScrollPassed),
        @"followStillOn": @(followStillOn)
    };
    if (!(programmaticScrollPassed && wheelScrollPassed && followScrollPassed && followStillOn)) {
        [errors addObject:@"Scrolling check failed."];
    }

    // Simulate a real click in the step sequencer.
    NSInteger freeStep = -1;
    for (NSInteger step = 0; step < 16; step++) {
        if (![song.tracks[0] noteStartingAtTick:(uint64_t)step * 120 tolerance:1]) {
            freeStep = step;
            break;
        }
    }
    BOOL stepClickPassed = NO;
    if (freeStep >= 0) {
        NSUInteger stepCountBefore = song.tracks[0].notes.count;
        NSPoint point = NSMakePoint(154.0 + (CGFloat)freeStep * 30.0 + 15.0, 26.0 + 16.0);
        NSEvent *event = [self mouseDownEventAtViewPoint:point inView:self.stepView];
        [self.stepView mouseDown:event];
        [self.stepView mouseUp:event];
        NSUInteger stepCountAfter = self.document.song.tracks[0].notes.count;
        NoteEvent *added = [self.document.song.tracks[0] noteStartingAtTick:(uint64_t)freeStep * 120 tolerance:1];
        stepClickPassed = (stepCountAfter == stepCountBefore + 1 && added && added.pitch == self.selectedPitch);
        [self.document.undoManager undo];
        if (self.document.song.tracks[0].notes.count != stepCountBefore) stepClickPassed = NO;
    }
    checks[@"stepClick"] = @{ @"freeStep": @(freeStep), @"passed": @(stepClickPassed) };
    if (!stepClickPassed) [errors addObject:@"Step sequencer click check failed."];

    // Simulate a real click in the piano roll.
    [self showPianoRoll:nil];
    Song *pianoSong = self.document.song;
    NSUInteger pianoCountBefore = pianoSong.tracks[0].notes.count;
    NSPoint pianoPoint = NSMakePoint(66.0 + 100.0, 24.0 + (96.0 - 37.0) * 12.0 + 6.0);
    NSEvent *pianoEvent = [self mouseDownEventAtViewPoint:pianoPoint inView:self.pianoRollView];
    [self.pianoRollView mouseDown:pianoEvent];
    [self.pianoRollView mouseUp:pianoEvent];
    NSUInteger pianoCountAfter = self.document.song.tracks[0].notes.count;
    NoteEvent *pianoAdded = [self.document.song.tracks[0] noteStartingAtTick:240 tolerance:1];
    BOOL pianoClickPassed = (pianoCountAfter == pianoCountBefore + 1 && pianoAdded && pianoAdded.pitch == 37);
    [self.document.undoManager undo];
    if (self.document.song.tracks[0].notes.count != pianoCountBefore) pianoClickPassed = NO;
    [self showStepSequencer:nil];
    checks[@"pianoRollClick"] = @{ @"passed": @(pianoClickPassed) };
    if (!pianoClickPassed) [errors addObject:@"Piano roll click check failed."];

    // Undo and redo.
    NSUInteger before = self.document.song.tracks[0].notes.count;
    [self.document performEditNamed:@"Smoke Add Note" block:^(Song *edited) {
        Track *track = edited.tracks[0];
        uint64_t start = edited.totalTicks > 240 ? edited.totalTicks - 240 : 0;
        [track.notes addObject:[NoteEvent noteWithPitch:127 startTick:start durationTicks:120 velocity:90]];
    }];
    NSUInteger afterAdd = self.document.song.tracks[0].notes.count;
    [self.document.undoManager undo];
    NSUInteger afterUndo = self.document.song.tracks[0].notes.count;
    [self.document.undoManager redo];
    NSUInteger afterRedo = self.document.song.tracks[0].notes.count;
    [self.document.undoManager undo];
    BOOL undoPassed = (afterAdd == before + 1 && afterUndo == before && afterRedo == afterAdd);
    checks[@"undo"] = @{
        @"before": @(before),
        @"afterAdd": @(afterAdd),
        @"afterUndo": @(afterUndo),
        @"afterRedo": @(afterRedo),
        @"passed": @(undoPassed)
    };
    if (!undoPassed) [errors addObject:@"Undo/redo check failed."];

    // Save and reopen.
    NSString *chipPath = [directory stringByAppendingPathComponent:@"Smoke Test.chip"];
    NSURL *chipURL = [NSURL fileURLWithPath:chipPath];
    NSError *writeError = nil;
    BOOL wrote = [self.document writeToURL:chipURL ofType:@"com.sid.chiptune.song" forSaveOperation:NSSaveOperation originalContentsURL:nil error:&writeError];
    BOOL reopenedMatches = NO;
    NSUInteger reopenedNotes = 0;
    NSString *reopenedTitle = nil;
    if (wrote) {
        NSData *data = [NSData dataWithContentsOfURL:chipURL];
        SongDocument *reopened = [[SongDocument alloc] init];
        NSError *readError = nil;
        if (data && [reopened readFromData:data ofType:@"com.sid.chiptune.song" error:&readError]) {
            NSUInteger originalNotes = 0;
            for (Track *track in self.document.song.tracks) originalNotes += track.notes.count;
            for (Track *track in reopened.song.tracks) reopenedNotes += track.notes.count;
            reopenedTitle = reopened.song.title;
            reopenedMatches = (reopenedNotes == originalNotes &&
                               reopened.song.tracks.count == self.document.song.tracks.count &&
                               [reopened.song.title isEqualToString:self.document.song.title] &&
                               fabs(reopened.song.tempo - self.document.song.tempo) < 0.001);
        } else if (readError) {
            [errors addObject:[NSString stringWithFormat:@"Reopen failed: %@", readError.localizedDescription]];
        }
    } else {
        [errors addObject:[NSString stringWithFormat:@"Save failed: %@", writeError.localizedDescription ?: @"unknown error"]];
    }
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:chipPath error:NULL];
    checks[@"saveOpen"] = @{
        @"wrote": @(wrote),
        @"path": chipPath,
        @"bytes": attributes[NSFileSize] ?: @0,
        @"reopenedTitle": reopenedTitle ?: @"",
        @"reopenedNotes": @(reopenedNotes),
        @"passed": @(wrote && reopenedMatches)
    };
    if (!(wrote && reopenedMatches)) {
        [errors addObject:@"Save/reopen check did not reproduce the song."];
    }

    // Audio playback advances the transport and follows the playhead. A manual
    // scroll during playback then turns Follow off so the user can edit ahead.
    BOOL followBeforePlayback = self.followPlayhead;
    self.followCheck.state = NSControlStateValueOn;
    [self followChanged:nil];
    double startTick = (double)MAX(1ULL, song.totalTicks / 2);
    [self.audioEngine seekToTick:startTick];
    [self.audioEngine play];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        double tick = [self.audioEngine currentTick];
        BOOL playing = self.audioEngine.isPlaying;
        float peak = self.audioEngine.renderer.masterPeak;
        BOOL prepared = self.audioEngine.isPrepared;
        BOOL playbackFollowed = clipView.bounds.origin.x > 1.0;

        CGEventRef manualEvent = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitLine, 1, -4);
        NSEvent *manualWheel = manualEvent ? [NSEvent eventWithCGEvent:manualEvent] : nil;
        if (manualEvent) CFRelease(manualEvent);
        BOOL followWasOn = self.followPlayhead;
        if (manualWheel) [self.stepView scrollWheel:manualWheel];
        BOOL manualScrollStoppedFollow = followWasOn && !self.followPlayhead;

        [self.audioEngine stop];
        self.followCheck.state = followBeforePlayback ? NSControlStateValueOn : NSControlStateValueOff;
        [self followChanged:nil];

        BOOL audioPassed = (prepared && playing && tick > startTick && isfinite(peak));
        checks[@"audio"] = @{
            @"prepared": @(prepared),
            @"wasPlaying": @(playing),
            @"currentTick": @(tick),
            @"masterPeak": @(peak),
            @"playbackFollowed": @(playbackFollowed),
            @"manualScrollStoppedFollow": @(manualScrollStoppedFollow),
            @"passed": @(audioPassed)
        };
        if (!audioPassed) [errors addObject:@"Audio playback did not advance the transport."];
        if (!playbackFollowed) [errors addObject:@"Playback did not scroll to follow the playhead."];
        if (!manualScrollStoppedFollow) [errors addObject:@"Manual scrolling did not stop playhead following."];

        checks[@"passed"] = @(errors.count == 0);
        NSString *reportPath = [directory stringByAppendingPathComponent:@"report.json"];
        NSData *json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:NULL];
        [json writeToFile:reportPath atomically:YES];
        NSLog(@"CHIPTUNE_SNAPSHOT_REPORT %@", reportPath);
        fflush(stdout);
        exit(0);
    });
}
#endif

@end
