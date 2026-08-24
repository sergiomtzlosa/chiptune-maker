#import "HelpWindowController.h"

NSString *const ChiptuneHelpTopicWelcome = @"welcome";
NSString *const ChiptuneHelpTopicInterface = @"interface";
NSString *const ChiptuneHelpTopicSteps = @"steps";
NSString *const ChiptuneHelpTopicPianoRoll = @"piano-roll";
NSString *const ChiptuneHelpTopicPlayback = @"playback";
NSString *const ChiptuneHelpTopicGeneration = @"generation";
NSString *const ChiptuneHelpTopicSaving = @"saving";
NSString *const ChiptuneHelpTopicAI = @"ai";
NSString *const ChiptuneHelpTopicShortcuts = @"shortcuts";
NSString *const ChiptuneHelpTopicTroubleshooting = @"troubleshooting";

@interface HelpWindowController () <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, strong) NSArray<NSDictionary<NSString *, NSString *> *> *topics;
@property (nonatomic, strong) NSTableView *topicTable;
@property (nonatomic, strong) NSTextView *contentTextView;
@property (nonatomic, assign) NSInteger selectedTopicIndex;
@property (nonatomic, assign) BOOL didBuildInterface;

@end

@implementation HelpWindowController

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 880, 640)
                                                   styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"Chiptune Maker Help";
    window.minSize = NSMakeSize(720, 480);
    window.releasedWhenClosed = NO;
    window.tabbingMode = NSWindowTabbingModeDisallowed;
    window.restorable = NO;
    self = [super initWithWindow:window];
    if (self) {
        _selectedTopicIndex = 0;
        [self buildInterface];
        if (![window setFrameAutosaveName:@"ChiptuneMakerHelpWindow"]) {
            [window center];
        }
    }
    return self;
}

- (NSInteger)topicCount {
    return (NSInteger)self.topics.count;
}

- (nullable NSString *)selectedTopicTitle {
    if (self.selectedTopicIndex < 0 || self.selectedTopicIndex >= (NSInteger)self.topics.count) return nil;
    return self.topics[(NSUInteger)self.selectedTopicIndex][@"title"];
}

- (void)buildInterface {
    if (self.didBuildInterface) return;
    self.didBuildInterface = YES;

    self.topics = @[
        @{ @"id": ChiptuneHelpTopicWelcome,
           @"title": @"Welcome",
           @"body": @"# Welcome to Chiptune Maker\n"
                    "Chiptune Maker is a native macOS tracker for writing, generating, and exporting chiptune music. Everything except optional AI composition works offline.\n"
                    "## Quick start\n"
                    "- Open `Examples/Neon Circuit.chip` or press Cmd+N for a new song.\n"
                    "- Click cells in the **Steps** grid to place notes. Use the Pitch and Octave controls above the grid to choose the note.\n"
                    "- Press **Space** to play or pause, and **Return** to stop and rewind.\n"
                    "- Press Cmd+R to generate a complete seeded song, or edit notes by hand in the Steps and Piano Roll views.\n"
                    "- Press Cmd+E to export MIDI, FLAC, WAV, MP3, or an LSDj `.lsdsng` song.\n"
                    "## Where to get help\n"
                    "Use the topics on the left for the editor, playback, generation, export, AI composition, shortcuts, and troubleshooting. The same Help window is available from the **Help** menu at any time." },
        @{ @"id": ChiptuneHelpTopicInterface,
           @"title": @"The Main Window",
           @"body": @"# The Main Window\n"
                    "The document window has three columns and a toolbar.\n"
                    "## Toolbar\n"
                    "- **Play / Stop** controls playback. Tempo, Bars, Key, and Scale apply to the whole song. Changing Key transposes pitched notes by the shortest semitone distance; changing Scale snaps them to the selected key and scale.\n"
                    "- **Generate** creates a new song from the current seed. **AI…** opens optional AI composition. **Export…** opens the export sheet.\n"
                    "- The second toolbar row switches between **Steps** and **Piano Roll**, sets the note Pitch and Octave used by the step grid, toggles **Loop** and **Follow**, and edits the generation seed.\n"
                    "## Track list\n"
                    "The left column lists the tracks. Select a track to edit it. The M and S columns mute and solo tracks. Use **Add** and **Remove** below the list to change the track count (1–8).\n"
                    "## Editor\n"
                    "The center column shows the selected track in either the step sequencer or the piano roll. Scroll horizontally to see later bars. The status bar at the bottom shows transport and edit information.\n"
                    "## Inspector\n"
                    "The right column edits the selected track: name, instrument, volume, pan, mute, solo, vibrato depth and rate, pitch slide, and arpeggio. It also contains the Regenerate Track and AI Composition buttons." },
        @{ @"id": ChiptuneHelpTopicSteps,
           @"title": @"Step Sequencer",
           @"body": @"# Step Sequencer\n"
                    "The Steps view is a grid of tracks and 16th-note steps.\n"
                    "## Editing\n"
                    "- Each row is one track; each column is a 16th note. Bar lines are darker.\n"
                    "- Click an empty cell to add a note at the current **Pitch** and **Octave**. Click an existing note to remove it.\n"
                    "- Drag across cells to paint notes or erase them in one gesture. Each drag is one undoable edit.\n"
                    "- The selected track is highlighted. Click a track in the left list to switch rows.\n"
                    "- Notes show their pitch name when the cell is wide enough. Longer notes span multiple steps.\n"
                    "- Scroll the timeline with a mouse wheel, a horizontal trackpad swipe, or Shift+scroll. Dragging near the edge while painting scrolls automatically.\n"
                    "## Tips\n"
                    "Use the Pitch and Octave controls in the toolbar before clicking. For precise note lengths, move, or transposition, switch to the Piano Roll. Press Cmd+Z to undo a mistaken paint stroke." },
        @{ @"id": ChiptuneHelpTopicPianoRoll,
           @"title": @"Piano Roll",
           @"body": @"# Piano Roll\n"
                    "The Piano Roll edits the selected track with pitch on the vertical axis and time on the horizontal axis.\n"
                    "## Editing notes\n"
                    "- Click an empty area to add a 16th note at that pitch and time.\n"
                    "- Drag a note to move it in time and pitch. Drag the right edge of a note to resize it.\n"
                    "- Select a note and press Delete or Forward Delete to remove it.\n"
                    "- With a note selected, the arrow keys nudge it: Left/Right move by a 16th note, Up/Down transpose by a semitone.\n"
                    "- Note starts and lengths snap to 16th notes.\n"
                    "## Navigation\n"
                    "The piano keyboard is on the left. Shift+scroll or a horizontal trackpad swipe moves along the timeline; a normal wheel scrolls pitches. **Follow** is on by default and keeps the playhead visible during playback. If you scroll manually while playing, Follow turns off so you can inspect another part of the song. The playhead is drawn over the notes." },
        @{ @"id": ChiptuneHelpTopicPlayback,
           @"title": @"Playback & Transport",
           @"body": @"# Playback & Transport\n"
                    "Playback uses the same synthesizer and renderer as audio export, so what you hear matches the exported file.\n"
                    "## Controls\n"
                    "- **Space** plays or pauses when the editor has focus. **Return** stops and rewinds to the start.\n"
                    "- The toolbar **Play** button changes to **Pause** while playing. **Stop** stops and rewinds.\n"
                    "- **Loop** repeats the whole song. **Follow** is on by default and scrolls the editor to keep the playhead visible. If you scroll manually during playback, Follow turns off so the view stays where you put it.\n"
                    "- Playback stops automatically at the final bar. Press **Play** again to rewind and restart, or enable **Loop** to repeat the song.\n"
                    "- Tempo, volume, pan, mute, solo, instrument, vibrato, pitch slide, and arpeggio changes apply while the song is playing. Changing Key or Scale updates the note data and reloads the schedule without stopping playback.\n"
                    "## Track mixer\n"
                    "Use the left track list for quick mute and solo, or the inspector for volume and pan. Solo overrides mute for other tracks. The master output is soft-clipped to avoid harsh distortion." },
        @{ @"id": ChiptuneHelpTopicGeneration,
           @"title": @"Generating Music",
           @"body": @"# Generating Music\n"
                    "Chiptune Maker can compose a complete song offline with a deterministic pattern generator. No server or network is required.\n"
                    "## Generate a song\n"
                    "- Set Tempo, Bars, Key, and Scale, then click **Generate** or press Cmd+R.\n"
                    "- The **Seed** field controls the result. The same seed and settings always produce the same song. Change the seed for a different variation.\n"
                    "- Generation creates sections and fills all tracks with roles such as lead, harmony, bass, and drums, quantized to the selected scale.\n"
                    "## Regenerate one track\n"
                    "- Select a track and click **Regenerate Track** in the toolbar or inspector. This replaces only that track and leaves the others untouched.\n"
                    "- The song seed is reused, so regenerating the same track twice gives the same result.\n"
                    "## Editing generated material\n"
                    "Generated notes are ordinary notes. Edit them in the Steps or Piano Roll view, then save or export. Generation is undoable as a single action." },
        @{ @"id": ChiptuneHelpTopicSaving,
           @"title": @"Saving & Exporting",
           @"body": @"# Saving & Exporting\n"
                    "## Project files\n"
                    "- Chiptune Maker documents use the `.chip` extension and contain versioned JSON.\n"
                    "- **Cmd+S** saves, **Shift+Cmd+S** saves as, and the document autosaves after a short delay. Unsaved changes mark the window as edited.\n"
                    "- The file stores tempo, meter, key, swing, length, sections, tracks, notes, effects, and generation settings.\n"
                    "## Export\n"
                    "- Press **Cmd+E** or click **Export…** to open the export sheet.\n"
                    "- **MIDI** writes a Standard MIDI File at 480 PPQ with tempo, time signature, key, markers, track names, and notes.\n"
                    "- **FLAC** and **WAV** render through the same `ChipRenderer` used for playback. FLAC is 16-bit by default; WAV is also available.\n"
                    "- **MP3** uses a local `lame` executable. Install it with `brew install lame` if MP3 export reports that LAME is missing. FLAC, WAV, MIDI, and LSDj export do not need LAME.\n"
                    "- **LSDj** writes a single-song `.lsdsng` file for Little Sound DJ. Each bar becomes a 16-step phrase, up to 16 bars are grouped into a chain, and each chain group occupies one song row. Pulse tracks map to PU1/PU2, triangle and wavetable tracks to WAVE, and noise tracks to NOISE. One LSDj instrument is created per audible track; extra tracks on the same LSDj channel are merged, keeping the first note at each step.\n"
                    "- Audio and LSDj export run in the background with progress and cancel. Use **Reveal in Finder** after completion." },
        @{ @"id": ChiptuneHelpTopicAI,
           @"title": @"AI Composition",
           @"body": @"# AI Composition\n"
                    "AI composition is optional. Offline generation and every editing feature continue to work without OpenCode.\n"
                    "## Connect\n"
                    "- Start the server in Terminal with `opencode serve --port 4096`.\n"
                    "- Open **AI Composition…** from the toolbar, inspector, or Song menu.\n"
                    "- Enter the server URL (default `http://127.0.0.1:4096`) and the password printed by `opencode serve`, then click **Connect**.\n"
                    "- The app lists chat models reported by OpenCode. Click **Refresh** after changing providers or installing a local model.\n"
                    "## Generate a draft\n"
                    "- Choose a **Model**, write a **Musical brief**, and choose a **Target**: the whole song or one track.\n"
                    "- Click **Generate Draft**. The app asks for strict JSON, validates every track and note, and retries once with validation errors if the first response is invalid.\n"
                    "- Review the summary and raw response. **Accept Draft** applies it as one undoable edit; **Discard** throws it away.\n"
                    "## Reading the model menu\n"
                    "- **(local)** models run on this Mac through Ollama or llama.cpp. They have no cloud quota; quality and speed depend on the installed model.\n"
                    "- **(free)** models are hosted by OpenCode and are rate-limited. If you see **“Free usage limit reached”**, the quota is enforced by OpenCode, not by Chiptune Maker. Choose a local or paid model, wait for the retry time, or subscribe to OpenCode Go.\n"
                    "If a local model is available, the app retries with it automatically after a free-model quota error.\n"
                    "- Models without a suffix use the provider credentials configured in OpenCode. If a provider rejects its API key, check that provider's login in OpenCode.\n"
                    "## Privacy and troubleshooting\n"
                    "- The default URL is localhost. If you enter a remote URL, the musical brief and song context leave this Mac.\n"
                    "- A connection error usually means the server is not running, the URL is wrong, or the password is missing.\n"
                    "- If a model returns invalid JSON twice, try a stronger model or a shorter brief. Small local models may struggle with strict JSON." },
        @{ @"id": ChiptuneHelpTopicShortcuts,
           @"title": @"Keyboard Shortcuts",
           @"body": @"# Keyboard Shortcuts\n"
                    "@ Space\tPlay or pause\n"
                    "@ Return\tStop and rewind\n"
                    "@ Cmd+R\tGenerate a new seeded song\n"
                    "@ Cmd+E\tOpen the export sheet\n"
                    "@ Cmd+N\tNew document\n"
                    "@ Cmd+O\tOpen a document\n"
                    "@ Cmd+S\tSave\n"
                    "@ Shift+Cmd+S\tSave As\n"
                    "@ Cmd+W\tClose the document window\n"
                    "@ Cmd+Z\tUndo\n"
                    "@ Shift+Cmd+Z\tRedo\n"
                    "@ Cmd+1\tShow the Step Sequencer\n"
                    "@ Cmd+2\tShow the Piano Roll\n"
                    "@ Cmd+F\tToggle Follow Playhead\n"
                    "@ Cmd+?\tOpen this Help window\n"
                    "@ Delete\tDelete the selected piano-roll note\n"
                    "@ Arrow keys\tNudge the selected piano-roll note\n"
                    "@ Escape\tCancel a sheet or dialog\n"
                    "## Note\n"
                    "Space and Return work when the step or piano-roll editor has focus. Click the editor once if another control is active." },
        @{ @"id": ChiptuneHelpTopicTroubleshooting,
           @"title": @"Troubleshooting",
           @"body": @"# Troubleshooting\n"
                    "## No sound\n"
                    "- Press **Space** or click **Play**; the audio engine starts on demand.\n"
                    "- Playback stops at the final bar. Press **Play** again to rewind and restart, or enable **Loop** to repeat the song.\n"
                    "- Check the track's volume and pan, and make sure it is not muted. If any track is soloed, only soloed tracks are audible.\n"
                    "- Check the macOS output device and system volume. Audio follows the current default output.\n"
                    "## AI cannot connect\n"
                    "- Confirm OpenCode is running: `opencode serve --port 4096`. The default URL is `http://127.0.0.1:4096`.\n"
                    "- Use the password printed when the server starts. If you restarted the server, the password may have changed.\n"
                    "- Click **Connect** again, then **Refresh** to reload the model list.\n"
                    "## “Free usage limit reached”\n"
                    "- This message comes from OpenCode's hosted free models. Chiptune Maker cannot bypass it.\n"
                    "- Choose a model labeled **(local)** or a paid provider model, or wait until the retry time shown in the error.\n"
                    "- You can install a local Ollama model and click **Refresh** to make it appear in the list.\n"
                    "## AI returns invalid JSON\n"
                    "- The app validates the response and retries once. If it still fails, try a stronger model or simplify the brief.\n"
                    "- Very small local models may not follow the strict JSON schema reliably.\n"
                    "## MP3 export fails\n"
                    "- Install LAME with `brew install lame`. The app checks `/opt/homebrew/bin/lame`, `/usr/local/bin/lame`, `/usr/bin/lame`, and `PATH`.\n"
                    "- FLAC, WAV, MIDI, and LSDj export do not require LAME.\n"
                    "## A `.chip` file will not open\n"
                    "- The file may use a newer format version than this app supports. The error message names the version.\n"
                    "- Unknown JSON fields are ignored; malformed or out-of-range values are rejected with a description.\n"
                    "## Extra windows after launch\n"
                    "- macOS may restore the previous session's document windows. Opening a `.chip` file directly keeps the requested document and closes restored or duplicate windows." }
    ];

    NSViewController *sidebarController = [[NSViewController alloc] init];
    NSView *sidebarView = [[NSView alloc] init];
    sidebarController.view = sidebarView;

    self.topicTable = [[NSTableView alloc] init];
    self.topicTable.dataSource = self;
    self.topicTable.delegate = self;
    self.topicTable.headerView = nil;
    self.topicTable.rowHeight = 32;
    self.topicTable.style = NSTableViewStylePlain;
    self.topicTable.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
    self.topicTable.backgroundColor = [NSColor clearColor];
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"title"];
    column.width = 190;
    [self.topicTable addTableColumn:column];

    NSScrollView *tableScroll = [[NSScrollView alloc] init];
    tableScroll.translatesAutoresizingMaskIntoConstraints = NO;
    tableScroll.hasVerticalScroller = YES;
    tableScroll.autohidesScrollers = YES;
    tableScroll.borderType = NSNoBorder;
    tableScroll.drawsBackground = NO;
    tableScroll.documentView = self.topicTable;
    [sidebarView addSubview:tableScroll];
    [NSLayoutConstraint activateConstraints:@[
        [tableScroll.topAnchor constraintEqualToAnchor:sidebarView.topAnchor constant:8],
        [tableScroll.leadingAnchor constraintEqualToAnchor:sidebarView.leadingAnchor],
        [tableScroll.trailingAnchor constraintEqualToAnchor:sidebarView.trailingAnchor],
        [tableScroll.bottomAnchor constraintEqualToAnchor:sidebarView.bottomAnchor]
    ]];

    NSSplitViewController *splitController = [[NSSplitViewController alloc] init];
    NSSplitViewItem *sidebarItem = [NSSplitViewItem sidebarWithViewController:sidebarController];
    sidebarItem.minimumThickness = 180;
    sidebarItem.maximumThickness = 260;
    sidebarItem.canCollapse = NO;
    [splitController addSplitViewItem:sidebarItem];

    NSViewController *contentController = [[NSViewController alloc] init];
    NSView *contentView = [[NSView alloc] init];
    contentController.view = contentView;

    self.contentTextView = [[NSTextView alloc] init];
    self.contentTextView.editable = NO;
    self.contentTextView.selectable = YES;
    self.contentTextView.drawsBackground = YES;
    self.contentTextView.backgroundColor = [NSColor textBackgroundColor];
    self.contentTextView.textContainerInset = NSMakeSize(30, 24);
    self.contentTextView.minSize = NSMakeSize(0, 0);
    self.contentTextView.maxSize = NSMakeSize(FLT_MAX, FLT_MAX);
    self.contentTextView.verticallyResizable = YES;
    self.contentTextView.horizontallyResizable = NO;
    self.contentTextView.autoresizingMask = NSViewWidthSizable;
    self.contentTextView.textContainer.widthTracksTextView = YES;

    NSScrollView *contentScroll = [[NSScrollView alloc] init];
    contentScroll.translatesAutoresizingMaskIntoConstraints = NO;
    contentScroll.hasVerticalScroller = YES;
    contentScroll.autohidesScrollers = YES;
    contentScroll.borderType = NSNoBorder;
    contentScroll.drawsBackground = YES;
    contentScroll.backgroundColor = [NSColor textBackgroundColor];
    self.contentTextView.frame = contentScroll.contentView.bounds;
    self.contentTextView.textContainer.containerSize = NSMakeSize(contentScroll.contentView.bounds.size.width, FLT_MAX);
    contentScroll.documentView = self.contentTextView;
    [contentView addSubview:contentScroll];
    [NSLayoutConstraint activateConstraints:@[
        [contentScroll.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [contentScroll.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [contentScroll.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [contentScroll.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor]
    ]];

    NSSplitViewItem *contentItem = [NSSplitViewItem splitViewItemWithViewController:contentController];
    contentItem.minimumThickness = 420;
    [splitController addSplitViewItem:contentItem];

    self.window.contentViewController = splitController;
    [self.topicTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    [self updateContentForSelectedTopic];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)self.topics.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSTableCellView *cell = [tableView makeViewWithIdentifier:@"TopicCell" owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] init];
        cell.identifier = @"TopicCell";
        NSTextField *label = [NSTextField labelWithString:@""];
        label.font = [NSFont systemFontOfSize:13];
        label.lineBreakMode = NSLineBreakByTruncatingTail;
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [cell addSubview:label];
        cell.textField = label;
        [NSLayoutConstraint activateConstraints:@[
            [label.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:8],
            [label.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-8],
            [label.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]
        ]];
    }
    cell.textField.stringValue = self.topics[(NSUInteger)row][@"title"];
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    [self updateContentForSelectedTopic];
}

- (void)showTopicWithIdentifier:(NSString *)identifier {
    if (!self.didBuildInterface) [self buildInterface];
    NSInteger index = 0;
    for (NSInteger i = 0; i < (NSInteger)self.topics.count; i++) {
        if ([self.topics[(NSUInteger)i][@"id"] isEqualToString:identifier]) {
            index = i;
            break;
        }
    }
    [self.topicTable selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)index] byExtendingSelection:NO];
    [self.topicTable scrollRowToVisible:index];
    [self updateContentForSelectedTopic];
}

- (void)updateContentForSelectedTopic {
    NSInteger row = self.topicTable.selectedRow;
    if (row < 0 || row >= (NSInteger)self.topics.count) return;
    self.selectedTopicIndex = row;
    NSString *markup = self.topics[(NSUInteger)row][@"body"];
    [self.contentTextView.textStorage setAttributedString:[self attributedContentForMarkup:markup]];
    [self.contentTextView scrollRangeToVisible:NSMakeRange(0, 0)];
}

- (void)showWindow:(id)sender {
    [super showWindow:sender];
    [self.window makeKeyAndOrderFront:nil];
}

#pragma mark - Markup

- (NSAttributedString *)attributedContentForMarkup:(NSString *)markup {
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    NSArray<NSString *> *lines = [markup componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        if (line.length == 0) {
            continue;
        }
        if ([line hasPrefix:@"# "]) {
            [self appendLine:[line substringFromIndex:2]
                     toResult:result
                         font:[NSFont systemFontOfSize:25 weight:NSFontWeightBold]
                 paragraph:[self paragraphStyleWithSpacingBefore:0 spacingAfter:12]
                    color:[NSColor labelColor]];
        } else if ([line hasPrefix:@"## "]) {
            [self appendLine:[line substringFromIndex:3]
                     toResult:result
                         font:[NSFont systemFontOfSize:14.5 weight:NSFontWeightSemibold]
                 paragraph:[self paragraphStyleWithSpacingBefore:14 spacingAfter:4]
                    color:[NSColor labelColor]];
        } else if ([line hasPrefix:@"- "]) {
            [self appendBullet:[line substringFromIndex:2] toResult:result];
        } else if ([line hasPrefix:@"@ "]) {
            [self appendShortcut:[line substringFromIndex:2] toResult:result];
        } else if ([line hasPrefix:@"> "]) {
            [self appendLine:[line substringFromIndex:2]
                     toResult:result
                         font:[NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular]
                 paragraph:[self paragraphStyleWithSpacingBefore:0 spacingAfter:4]
                    color:[NSColor secondaryLabelColor]];
        } else {
            [self appendLine:line
                     toResult:result
                         font:[NSFont systemFontOfSize:13]
                 paragraph:[self paragraphStyleWithSpacingBefore:0 spacingAfter:8]
                    color:[NSColor labelColor]];
        }
    }
    return result;
}

- (NSParagraphStyle *)paragraphStyleWithSpacingBefore:(CGFloat)before spacingAfter:(CGFloat)after {
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.paragraphSpacingBefore = before;
    style.paragraphSpacing = after;
    style.lineSpacing = 2.0;
    return style;
}

- (void)appendLine:(NSString *)text
          toResult:(NSMutableAttributedString *)result
              font:(NSFont *)font
          paragraph:(NSParagraphStyle *)paragraph
             color:(NSColor *)color {
    NSDictionary *attributes = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: color,
        NSParagraphStyleAttributeName: paragraph
    };
    [result appendAttributedString:[self attributedInlineMarkup:text baseAttributes:attributes]];
    [result appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:attributes]];
}

- (void)appendBullet:(NSString *)text toResult:(NSMutableAttributedString *)result {
    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.paragraphSpacing = 4.0;
    paragraph.lineSpacing = 2.0;
    paragraph.headIndent = 18.0;
    paragraph.firstLineHeadIndent = 0.0;
    paragraph.tabStops = @[[[NSTextTab alloc] initWithTextAlignment:NSTextAlignmentLeft location:18.0 options:@{}]];
    NSDictionary *bulletAttributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:13],
        NSForegroundColorAttributeName: [NSColor secondaryLabelColor],
        NSParagraphStyleAttributeName: paragraph
    };
    NSDictionary *bodyAttributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:13],
        NSForegroundColorAttributeName: [NSColor labelColor],
        NSParagraphStyleAttributeName: paragraph
    };
    [result appendAttributedString:[[NSAttributedString alloc] initWithString:@"•\t" attributes:bulletAttributes]];
    [result appendAttributedString:[self attributedInlineMarkup:text baseAttributes:bodyAttributes]];
    [result appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:bodyAttributes]];
}

- (void)appendShortcut:(NSString *)text toResult:(NSMutableAttributedString *)result {
    NSArray<NSString *> *parts = [text componentsSeparatedByString:@"\t"];
    NSString *key = parts.firstObject ?: @"";
    NSString *description = parts.count > 1 ? parts[1] : @"";

    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.paragraphSpacing = 4.0;
    paragraph.lineSpacing = 2.0;
    paragraph.headIndent = 150.0;
    paragraph.firstLineHeadIndent = 0.0;
    paragraph.tabStops = @[[[NSTextTab alloc] initWithTextAlignment:NSTextAlignmentLeft location:150.0 options:@{}]];

    NSDictionary *keyAttributes = @{
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: [NSColor labelColor],
        NSParagraphStyleAttributeName: paragraph
    };
    NSDictionary *bodyAttributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:13],
        NSForegroundColorAttributeName: [NSColor labelColor],
        NSParagraphStyleAttributeName: paragraph
    };
    [result appendAttributedString:[[NSAttributedString alloc] initWithString:key attributes:keyAttributes]];
    [result appendAttributedString:[[NSAttributedString alloc] initWithString:@"\t" attributes:keyAttributes]];
    [result appendAttributedString:[self attributedInlineMarkup:description baseAttributes:bodyAttributes]];
    [result appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:bodyAttributes]];
}

- (NSAttributedString *)attributedInlineMarkup:(NSString *)text baseAttributes:(NSDictionary<NSAttributedStringKey, id> *)baseAttributes {
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    NSFont *baseFont = baseAttributes[NSFontAttributeName] ?: [NSFont systemFontOfSize:13];
    NSColor *baseColor = baseAttributes[NSForegroundColorAttributeName] ?: [NSColor labelColor];
    NSParagraphStyle *paragraph = baseAttributes[NSParagraphStyleAttributeName];

    __block BOOL bold = NO;
    __block BOOL code = NO;
    __block NSUInteger index = 0;
    while (index < text.length) {
        if (index + 1 < text.length && [[text substringWithRange:NSMakeRange(index, 2)] isEqualToString:@"**"]) {
            bold = !bold;
            index += 2;
            continue;
        }
        unichar character = [text characterAtIndex:index];
        if (character == '`') {
            code = !code;
            index += 1;
            continue;
        }

        NSRange run = [text rangeOfString:@"**" options:0 range:NSMakeRange(index, text.length - index)];
        NSRange codeRun = [text rangeOfString:@"`" options:0 range:NSMakeRange(index, text.length - index)];
        NSUInteger end = text.length;
        if (run.location != NSNotFound) end = MIN(end, run.location);
        if (codeRun.location != NSNotFound) end = MIN(end, codeRun.location);
        if (end <= index) end = index + 1;

        NSString *chunk = [text substringWithRange:NSMakeRange(index, end - index)];
        NSMutableDictionary<NSAttributedStringKey, id> *attributes = [baseAttributes mutableCopy];
        if (code) {
            attributes[NSFontAttributeName] = [NSFont monospacedSystemFontOfSize:MAX(10.0, baseFont.pointSize - 1.0) weight:NSFontWeightRegular];
            attributes[NSForegroundColorAttributeName] = [NSColor labelColor];
        } else if (bold) {
            attributes[NSFontAttributeName] = [NSFont systemFontOfSize:baseFont.pointSize weight:NSFontWeightSemibold];
        } else {
            attributes[NSForegroundColorAttributeName] = baseColor;
        }
        if (paragraph) attributes[NSParagraphStyleAttributeName] = paragraph;
        [result appendAttributedString:[[NSAttributedString alloc] initWithString:chunk attributes:attributes]];
        index = end;
    }
    return result;
}

@end
