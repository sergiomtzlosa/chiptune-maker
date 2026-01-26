#import "AIGeneratorWindowController.h"
#import "SongDocument.h"
#import "Song.h"
#import "Track.h"
#import "SongTypes.h"
#import "OpenCodeClient.h"
#import "AICompositionService.h"
#import "KeychainStore.h"

@protocol ChiptuneHelpActions <NSObject>
- (void)showAIHelp:(id)sender;
@end

static NSString *const kOpenCodeServerKey = @"OpenCodeServerURL";
static NSString *const kOpenCodeModelKey = @"OpenCodeSelectedModel";
static NSString *const kOpenCodePasswordKey = @"server-password";
static NSString *const kOpenCodeKeychainService = @"com.sid.ChiptuneMaker.opencode";
static NSString *const kDefaultServerURL = @"http://127.0.0.1:4096";

@interface AIGeneratorWindowController ()

@property (nonatomic, weak) SongDocument *songDocument;
@property (nonatomic, strong) OpenCodeClient *client;
@property (nonatomic, strong) NSArray<OpenCodeModel *> *models;
@property (nonatomic, strong) AICompositionDraft *draft;
@property (nonatomic, assign) NSInteger retryCount;
@property (nonatomic, assign) BOOL didFallbackToLocalModel;

@property (nonatomic, strong) NSTextField *serverField;
@property (nonatomic, strong) NSSecureTextField *passwordField;
@property (nonatomic, strong) NSButton *connectButton;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSPopUpButton *modelPopup;
@property (nonatomic, strong) NSTextField *modelHintLabel;
@property (nonatomic, strong) NSButton *refreshModelsButton;
@property (nonatomic, strong) NSTextView *briefTextView;
@property (nonatomic, strong) NSPopUpButton *targetPopup;
@property (nonatomic, strong) NSButton *generateButton;
@property (nonatomic, strong) NSProgressIndicator *progressIndicator;
@property (nonatomic, strong) NSTextView *previewTextView;
@property (nonatomic, strong) NSButton *acceptButton;
@property (nonatomic, strong) NSButton *discardButton;
@property (nonatomic, assign) BOOL didBuildInterface;
#if DEBUG
@property (nonatomic, assign) BOOL suppressSettingsSave;
@property (nonatomic, assign) BOOL didRunAutoGeneration;
#endif

@end

@implementation AIGeneratorWindowController

- (instancetype)initWithDocument:(SongDocument *)document {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 680, 740)
                                                   styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"AI Composition";
    window.minSize = NSMakeSize(620, 660);
    window.releasedWhenClosed = NO;
    self = [super initWithWindow:window];
    if (self) {
        _songDocument = document;
        _models = @[];
        [self ensureInterfaceBuilt];
    }
    return self;
}

- (void)ensureInterfaceBuilt {
    if (self.didBuildInterface || !self.songDocument) return;
    self.didBuildInterface = YES;
    [self buildInterface];
    [self loadSettings];
#if DEBUG
    NSString *automationPassword = [NSProcessInfo processInfo].environment[@"CHIPTUNE_OPENCODE_PASSWORD"];
    if (automationPassword.length > 0) {
        self.suppressSettingsSave = YES;
        self.passwordField.stringValue = automationPassword;
    }
#endif
    [self connect:nil];
}

- (void)windowDidLoad {
    [super windowDidLoad];
    [self ensureInterfaceBuilt];
}

- (NSTextField *)label:(NSString *)text {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    label.textColor = [NSColor secondaryLabelColor];
    return label;
}

- (NSTextField *)heading:(NSString *)text {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold];
    return label;
}

- (NSScrollView *)scrollViewWithTextView:(NSTextView *)textView height:(CGFloat)height {
    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.hasVerticalScroller = YES;
    scroll.hasHorizontalScroller = NO;
    scroll.autohidesScrollers = YES;
    scroll.borderType = NSBezelBorder;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    textView.frame = scroll.contentView.bounds;
    textView.minSize = NSMakeSize(0, 0);
    textView.maxSize = NSMakeSize(FLT_MAX, FLT_MAX);
    textView.verticallyResizable = YES;
    textView.horizontallyResizable = NO;
    textView.autoresizingMask = NSViewWidthSizable;
    textView.textContainer.widthTracksTextView = YES;
    textView.textContainer.containerSize = NSMakeSize(scroll.contentView.bounds.size.width, FLT_MAX);
    scroll.documentView = textView;
    [scroll.heightAnchor constraintEqualToConstant:height].active = YES;
    return scroll;
}

- (NSView *)rowWithViews:(NSArray<NSView *> *)views {
    NSStackView *row = [NSStackView stackViewWithViews:views];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 8;
    return row;
}

- (void)buildInterface {
    NSView *root = self.window.contentView;
    root.wantsLayer = YES;

    NSTextField *title = [self heading:@"Compose with OpenCode"];
    NSButton *helpButton = [NSButton buttonWithTitle:@"Help" target:self action:@selector(showAIHelp:)];
    helpButton.bezelStyle = NSBezelStyleRounded;
    NSStackView *titleRow = [NSStackView stackViewWithViews:@[title, [NSView new], helpButton]];
    titleRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    titleRow.alignment = NSLayoutAttributeCenterY;
    titleRow.spacing = 8;
    [titleRow.widthAnchor constraintEqualToConstant:620].active = YES;
    NSTextField *subtitle = [self label:@"Optional local AI. Start “opencode serve --port 4096” first. Offline generation remains available in the main window."];
    subtitle.maximumNumberOfLines = 2;
    subtitle.lineBreakMode = NSLineBreakByWordWrapping;
    [subtitle.widthAnchor constraintEqualToConstant:620].active = YES;

    self.serverField = [NSTextField textFieldWithString:kDefaultServerURL];
    self.serverField.placeholderString = kDefaultServerURL;
    [self.serverField.widthAnchor constraintEqualToConstant:380].active = YES;

    self.passwordField = [[NSSecureTextField alloc] init];
    self.passwordField.placeholderString = @"Server password (if required)";
    self.passwordField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.passwordField.widthAnchor constraintEqualToConstant:230].active = YES;
    [self.passwordField.heightAnchor constraintEqualToConstant:24].active = YES;

    self.connectButton = [NSButton buttonWithTitle:@"Connect" target:self action:@selector(connect:)];
    self.connectButton.bezelStyle = NSBezelStyleRounded;

    self.statusLabel = [NSTextField labelWithString:@"Not connected."];
    self.statusLabel.font = [NSFont systemFontOfSize:11];
    self.statusLabel.textColor = [NSColor secondaryLabelColor];
    self.statusLabel.maximumNumberOfLines = 2;
    self.statusLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [self.statusLabel.widthAnchor constraintEqualToConstant:620].active = YES;

    self.modelPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.modelPopup.widthAnchor constraintEqualToConstant:500].active = YES;
    self.modelPopup.target = self;
    self.modelPopup.action = @selector(modelChanged:);

    self.refreshModelsButton = [NSButton buttonWithTitle:@"Refresh" target:self action:@selector(refreshModels:)];
    self.refreshModelsButton.bezelStyle = NSBezelStyleRounded;
    self.refreshModelsButton.enabled = NO;

    self.modelHintLabel = [self label:@"Local models run on this Mac. Free cloud models are rate-limited by OpenCode."];
    self.modelHintLabel.maximumNumberOfLines = 2;
    self.modelHintLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [self.modelHintLabel.widthAnchor constraintEqualToConstant:620].active = YES;

    self.briefTextView = [[NSTextView alloc] init];
    self.briefTextView.font = [NSFont systemFontOfSize:12];
    self.briefTextView.string = @"A driving 8-bar chiptune loop in the selected key, with a memorable lead, a walking bass line, and crisp noise drums.";
    NSScrollView *briefScroll = [self scrollViewWithTextView:self.briefTextView height:130];

    self.targetPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.targetPopup.widthAnchor constraintEqualToConstant:420].active = YES;

    self.generateButton = [NSButton buttonWithTitle:@"Generate Draft" target:self action:@selector(generate:)];
    self.generateButton.bezelStyle = NSBezelStyleRounded;
    self.generateButton.enabled = NO;

    self.progressIndicator = [[NSProgressIndicator alloc] init];
    self.progressIndicator.style = NSProgressIndicatorStyleSpinning;
    self.progressIndicator.controlSize = NSControlSizeSmall;
    self.progressIndicator.displayedWhenStopped = NO;
    [self.progressIndicator.widthAnchor constraintEqualToConstant:18].active = YES;

    self.previewTextView = [[NSTextView alloc] init];
    self.previewTextView.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    self.previewTextView.editable = NO;
    self.previewTextView.selectable = YES;
    self.previewTextView.string = @"No draft yet.";
    NSScrollView *previewScroll = [self scrollViewWithTextView:self.previewTextView height:130];

    self.acceptButton = [NSButton buttonWithTitle:@"Accept Draft" target:self action:@selector(acceptDraft:)];
    self.acceptButton.bezelStyle = NSBezelStyleRounded;
    self.acceptButton.keyEquivalent = @"\r";
    self.acceptButton.enabled = NO;

    self.discardButton = [NSButton buttonWithTitle:@"Discard" target:self action:@selector(discardDraft:)];
    self.discardButton.bezelStyle = NSBezelStyleRounded;
    self.discardButton.enabled = NO;

    NSButton *cancelButton = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancel:)];
    cancelButton.bezelStyle = NSBezelStyleRounded;
    cancelButton.keyEquivalent = @"\033";

    NSStackView *buttons = [NSStackView stackViewWithViews:@[self.discardButton, [NSView new], self.acceptButton, cancelButton]];
    buttons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttons.alignment = NSLayoutAttributeCenterY;
    buttons.spacing = 8;
    [buttons.widthAnchor constraintEqualToConstant:620].active = YES;
    [buttons setHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSStackView *stack = [NSStackView stackViewWithViews:@[
        titleRow,
        subtitle,
        [self rowWithViews:@[[self label:@"Server"], self.serverField, self.connectButton]],
        [self rowWithViews:@[[self label:@"Password"], self.passwordField]],
        self.statusLabel,
        [self rowWithViews:@[[self label:@"Model"], self.modelPopup, self.refreshModelsButton]],
        self.modelHintLabel,
        [self label:@"Musical brief"],
        briefScroll,
        [self rowWithViews:@[[self label:@"Target"], self.targetPopup]],
        [self rowWithViews:@[self.generateButton, self.progressIndicator]],
        [self label:@"Draft preview"],
        previewScroll,
        buttons
    ]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:root.topAnchor constant:18],
        [stack.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:24],
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:root.trailingAnchor constant:-24],
        [stack.bottomAnchor constraintLessThanOrEqualToAnchor:root.bottomAnchor constant:-18]
    ]];
}

- (void)loadSettings {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *server = [defaults stringForKey:kOpenCodeServerKey];
    self.serverField.stringValue = server.length > 0 ? server : kDefaultServerURL;
    NSString *password = [KeychainStore stringForKey:kOpenCodePasswordKey service:kOpenCodeKeychainService];
    if (password.length > 0) self.passwordField.stringValue = password;
    [self rebuildTargetPopup];
}

- (void)saveSettings {
#if DEBUG
    if (self.suppressSettingsSave) return;
#endif
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:self.serverField.stringValue forKey:kOpenCodeServerKey];
    OpenCodeModel *model = [self selectedModel];
    if (model) {
        [defaults setObject:model.qualifiedName forKey:kOpenCodeModelKey];
    }
    if (self.passwordField.stringValue.length > 0) {
        [KeychainStore setString:self.passwordField.stringValue forKey:kOpenCodePasswordKey service:kOpenCodeKeychainService];
    } else {
        [KeychainStore removeStringForKey:kOpenCodePasswordKey service:kOpenCodeKeychainService];
    }
}

- (void)rebuildTargetPopup {
    [self.targetPopup removeAllItems];
    [self.targetPopup addItemWithTitle:@"Whole song"];
    Song *song = self.songDocument.song;
    for (NSInteger i = 0; i < (NSInteger)song.tracks.count; i++) {
        Track *track = song.tracks[(NSUInteger)i];
        [self.targetPopup addItemWithTitle:[NSString stringWithFormat:@"Track %ld — %@", (long)(i + 1), track.name]];
    }
    if (self.targetPopup.numberOfItems > 1) {
        [self.targetPopup selectItemAtIndex:0];
    }
}

- (NSInteger)targetTrackIndex {
    NSInteger index = self.targetPopup.indexOfSelectedItem - 1;
    return index >= 0 ? index : -1;
}

- (OpenCodeModel *)selectedModel {
    NSMenuItem *item = self.modelPopup.selectedItem;
    id object = item.representedObject;
    return [object isKindOfClass:[OpenCodeModel class]] ? object : nil;
}

- (nullable OpenCodeModel *)firstLocalModel {
    OpenCodeModel *fallback = nil;
    for (OpenCodeModel *model in self.models) {
        if (!model.isLocal) continue;
        // Ollama is the most common local provider on macOS and reports real
        // model IDs. Prefer it over placeholder llama.cpp entries.
        if ([model.providerID.lowercaseString isEqualToString:@"ollama"]) return model;
        if (!fallback) fallback = model;
    }
    return fallback;
}

- (void)selectModel:(OpenCodeModel *)model {
    for (NSInteger i = 0; i < (NSInteger)self.modelPopup.numberOfItems; i++) {
        NSMenuItem *item = [self.modelPopup itemAtIndex:i];
        id object = item.representedObject;
        if (![object isKindOfClass:[OpenCodeModel class]]) continue;
        OpenCodeModel *candidate = object;
        if ([candidate.qualifiedName isEqualToString:model.qualifiedName]) {
            [self.modelPopup selectItemAtIndex:i];
            [self updateModelHint];
            return;
        }
    }
}

- (void)setStatus:(NSString *)status color:(NSColor *)color {
    self.statusLabel.stringValue = status;
    self.statusLabel.textColor = color ?: [NSColor secondaryLabelColor];
}

- (void)connect:(id)sender {
    [self saveSettings];
    self.client = [[OpenCodeClient alloc] initWithBaseURLString:self.serverField.stringValue
                                                       password:self.passwordField.stringValue];
    [self setStatus:@"Connecting…" color:[NSColor secondaryLabelColor]];
    [self.progressIndicator startAnimation:nil];
    self.connectButton.enabled = NO;
    __weak typeof(self) weakSelf = self;
    [self.client checkConnectionWithCompletion:^(NSString *version, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self.connectButton.enabled = YES;
            if (error) {
                [self.progressIndicator stopAnimation:nil];
                [self setStatus:error.localizedDescription color:[NSColor systemRedColor]];
                [self.modelPopup removeAllItems];
                [self.modelPopup addItemWithTitle:@"OpenCode unavailable"];
                self.modelHintLabel.stringValue = @"Start OpenCode with “opencode serve --port 4096”, then click Connect.";
                self.generateButton.enabled = NO;
                self.refreshModelsButton.enabled = NO;
#if DEBUG
                [self finishAutoGenerationWithDraft:nil text:nil errorMessage:error.localizedDescription];
#endif
                return;
            }
            [self setStatus:[NSString stringWithFormat:@"Connected to OpenCode %@.", version] color:[NSColor systemGreenColor]];
            [self loadModels];
        });
    }];
}

- (void)refreshModels:(id)sender {
    [self connect:nil];
}

- (void)loadModels {
    if (!self.client) return;
    self.refreshModelsButton.enabled = NO;
    [self.progressIndicator startAnimation:nil];
    __weak typeof(self) weakSelf = self;
    [self.client listModelsWithCompletion:^(NSArray<OpenCodeModel *> *models, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            [self.progressIndicator stopAnimation:nil];
            self.refreshModelsButton.enabled = YES;
            if (error) {
                [self setStatus:error.localizedDescription color:[NSColor systemRedColor]];
#if DEBUG
                [self finishAutoGenerationWithDraft:nil text:nil errorMessage:error.localizedDescription];
#endif
                return;
            }
            self.models = models;
            [self.modelPopup removeAllItems];
            for (OpenCodeModel *model in models) {
                [self.modelPopup addItemWithTitle:model.menuTitle];
                self.modelPopup.lastItem.representedObject = model;
            }
            if (models.count == 0) {
                [self.modelPopup addItemWithTitle:@"No chat models available"];
                self.modelHintLabel.stringValue = @"OpenCode reported no chat models. Check the provider configuration in OpenCode.";
                self.generateButton.enabled = NO;
                [self setStatus:@"OpenCode is running, but it reported no chat models." color:[NSColor systemOrangeColor]];
#if DEBUG
                [self finishAutoGenerationWithDraft:nil text:nil errorMessage:@"OpenCode reported no chat models."];
#endif
                return;
            }
            NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:kOpenCodeModelKey];
            if (saved.length > 0) {
                for (NSInteger i = 0; i < (NSInteger)models.count; i++) {
                    OpenCodeModel *model = models[(NSUInteger)i];
                    if ([model.qualifiedName isEqualToString:saved]) {
                        [self.modelPopup selectItemAtIndex:i];
                        break;
                    }
                }
            }
            [self updateModelHint];
            self.generateButton.enabled = YES;
            [self setStatus:[NSString stringWithFormat:@"Connected. %lu model%@ available.",
                             (unsigned long)models.count, models.count == 1 ? @"" : @"s"]
                      color:[NSColor systemGreenColor]];
#if DEBUG
            [self maybeRunAutoGeneration];
#endif
        });
    }];
}

- (void)modelChanged:(id)sender {
    [self saveSettings];
    [self updateModelHint];
}

- (void)updateModelHint {
    OpenCodeModel *model = [self selectedModel];
    if (!model) {
        self.modelHintLabel.stringValue = @"Choose a model after connecting.";
        self.modelPopup.toolTip = nil;
        return;
    }
    if (model.isLocal) {
        self.modelHintLabel.stringValue = @"Runs locally on this Mac. No cloud quota; quality depends on the installed model.";
    } else if (model.isFree) {
        self.modelHintLabel.stringValue = @"Free cloud models are rate-limited by OpenCode. If generation fails, choose a local or paid model.";
    } else {
        self.modelHintLabel.stringValue = @"Uses the provider credentials configured in OpenCode.";
    }
    self.modelPopup.toolTip = [NSString stringWithFormat:@"%@\nOpenCode ID: %@\nUpstream ID: %@\nProvider: %@",
                               model.displayName, model.requestID, model.modelID, model.providerID];
}

- (void)showAIHelp:(id)sender {
    id<ChiptuneHelpActions> delegate = (id<ChiptuneHelpActions>)NSApp.delegate;
    if ([delegate respondsToSelector:@selector(showAIHelp:)]) {
        [delegate showAIHelp:self];
    }
}

#if DEBUG
#pragma mark - Auto-generation verification

- (NSString *)autoGenerationReportPath {
    return [NSProcessInfo processInfo].environment[@"CHIPTUNE_AI_REPORT"];
}

- (BOOL)autoGenerationRequested {
    NSString *model = [NSProcessInfo processInfo].environment[@"CHIPTUNE_AI_AUTOGENERATE"];
    return model.length > 0 && [self autoGenerationReportPath].length > 0;
}

- (void)writeAutoGenerationReport:(NSDictionary *)report {
    NSString *path = [self autoGenerationReportPath];
    if (path.length == 0) return;
    NSMutableDictionary *payload = [report mutableCopy] ?: [NSMutableDictionary dictionary];
    NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
    payload[@"finishedAt"] = [formatter stringFromDate:[NSDate date]];
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload
                                                   options:(NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys)
                                                     error:NULL];
    [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    [json writeToFile:path atomically:YES];
    NSLog(@"CHIPTUNE_AI_REPORT %@", path);
    fflush(stdout);
}

- (void)finishAutoGenerationWithDraft:(AICompositionDraft *)draft
                                 text:(NSString *)text
                         errorMessage:(NSString *)errorMessage {
    if (![self autoGenerationRequested]) return;
    NSMutableDictionary *report = [NSMutableDictionary dictionary];
    report[@"requestedModel"] = [NSProcessInfo processInfo].environment[@"CHIPTUNE_AI_AUTOGENERATE"] ?: @"";
    OpenCodeModel *selected = [self selectedModel];
    if (selected) {
        report[@"selectedModel"] = selected.qualifiedName;
        report[@"selectedModelTitle"] = selected.menuTitle;
        report[@"selectedProvider"] = selected.providerID;
        report[@"selectedRequestID"] = selected.requestID;
    }
    report[@"usedFallback"] = @(self.didFallbackToLocalModel);
    if (errorMessage.length > 0) report[@"error"] = errorMessage;

    NSInteger noteCount = 0;
    NSMutableArray<NSDictionary *> *trackSummaries = [NSMutableArray array];
    for (Track *track in draft.tracks) {
        noteCount += (NSInteger)track.notes.count;
        [trackSummaries addObject:@{
            @"name": track.name ?: @"",
            @"instrument": ChipInstrumentIdentifier(track.instrument),
            @"notes": @(track.notes.count)
        }];
    }
    if (draft) {
        report[@"summary"] = draft.summary ?: @"";
        report[@"tracks"] = trackSummaries;
        report[@"noteCount"] = @(noteCount);
        report[@"rawResponse"] = text ?: @"";
    }

    BOOL passed = draft != nil && errorMessage.length == 0 && noteCount > 0;
    BOOL autoAccept = [[NSProcessInfo processInfo].environment[@"CHIPTUNE_AI_AUTOACCEPT"] boolValue];
    if (draft && autoAccept) {
        __block BOOL applied = NO;
        __block NSString *applyErrorMessage = nil;
        [self.songDocument performEditNamed:@"Accept AI Draft" block:^(Song *song) {
            NSError *applyError = nil;
            applied = [AICompositionService applyDraft:draft toSong:song error:&applyError];
            if (!applied) applyErrorMessage = applyError.localizedDescription ?: @"Unknown apply error.";
        }];
        report[@"accepted"] = @(applied);
        if (applied) {
            NSInteger totalNotes = 0;
            for (Track *track in self.songDocument.song.tracks) totalNotes += (NSInteger)track.notes.count;
            report[@"songNoteCount"] = @(totalNotes);
            passed = noteCount > 0 && totalNotes > 0;
        } else {
            report[@"applyError"] = applyErrorMessage ?: @"Unknown apply error.";
            passed = NO;
        }
    }
    report[@"passed"] = @(passed);
    [self writeAutoGenerationReport:report];
    if (draft && autoAccept) [self closeSheetWithCode:NSModalResponseOK];
}

- (void)maybeRunAutoGeneration {
    if (self.didRunAutoGeneration || ![self autoGenerationRequested]) return;
    self.didRunAutoGeneration = YES;

    NSString *requested = [NSProcessInfo processInfo].environment[@"CHIPTUNE_AI_AUTOGENERATE"];
    OpenCodeModel *target = nil;
    for (OpenCodeModel *model in self.models) {
        if ([model.qualifiedName isEqualToString:requested] ||
            [model.requestID isEqualToString:requested] ||
            [model.modelID isEqualToString:requested]) {
            target = model;
            break;
        }
    }
    if (!target) {
        [self finishAutoGenerationWithDraft:nil
                                       text:nil
                               errorMessage:[NSString stringWithFormat:@"Model “%@” was not reported by OpenCode.", requested]];
        return;
    }

    [self selectModel:target];
    NSString *brief = [NSProcessInfo processInfo].environment[@"CHIPTUNE_AI_BRIEF"];
    if (brief.length == 0) {
        brief = @"Compose a short two-bar chiptune loop with a lead, a bass line, and noise drums.";
    }
    self.briefTextView.string = brief;
    [self generate:nil];
}
#endif

- (void)generate:(id)sender {
    if (!self.client) {
        [self setStatus:@"Connect to OpenCode first." color:[NSColor systemRedColor]];
        return;
    }
    OpenCodeModel *model = [self selectedModel];
    if (!model) {
        [self setStatus:@"Choose a model first." color:[NSColor systemRedColor]];
        return;
    }
    NSString *brief = [self.briefTextView.string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (brief.length == 0) {
        [self setStatus:@"Enter a musical brief." color:[NSColor systemRedColor]];
        return;
    }
    self.draft = nil;
    self.retryCount = 0;
    self.didFallbackToLocalModel = NO;
    self.acceptButton.enabled = NO;
    self.discardButton.enabled = NO;
    self.generateButton.enabled = NO;
    [self.progressIndicator startAnimation:nil];
    [self setStatus:@"Asking OpenCode to compose…" color:[NSColor secondaryLabelColor]];
    self.previewTextView.string = @"Generating…";
    [self requestDraftWithBrief:brief model:model retryPrompt:nil];
}

- (void)requestDraftWithBrief:(NSString *)brief model:(OpenCodeModel *)model retryPrompt:(NSString *)retryPrompt {
    Song *song = [self.songDocument.song copy];
    NSInteger targetIndex = [self targetTrackIndex];
    NSString *prompt = [AICompositionService promptForSong:song targetTrackIndex:targetIndex brief:brief];
    if (retryPrompt.length > 0) {
        prompt = [prompt stringByAppendingFormat:@"\n\nYOUR PREVIOUS RESPONSE WAS INVALID\n%@\nReturn corrected JSON only.", retryPrompt];
    }
    __weak typeof(self) weakSelf = self;
    [self.client generateTextWithPrompt:prompt model:model completion:^(NSString *text, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            if (error) {
                if (error.code == OpenCodeErrorRateLimit && !self.didFallbackToLocalModel) {
                    OpenCodeModel *localModel = [self firstLocalModel];
                    if (localModel && ![localModel.qualifiedName isEqualToString:model.qualifiedName]) {
                        self.didFallbackToLocalModel = YES;
                        [self selectModel:localModel];
                        [self setStatus:[NSString stringWithFormat:@"Free model quota reached. Switched to %@ and retrying…", localModel.displayName]
                                  color:[NSColor systemOrangeColor]];
                        self.previewTextView.string = [NSString stringWithFormat:@"%@\n\nRetrying with local model %@…",
                                                       error.localizedDescription, localModel.displayName];
                        [self requestDraftWithBrief:brief model:localModel retryPrompt:nil];
                        return;
                    }
                }
                [self.progressIndicator stopAnimation:nil];
                self.generateButton.enabled = YES;
                NSString *message = error.localizedDescription ?: @"Generation failed.";
                if (error.code == OpenCodeErrorRateLimit) {
                    [self setStatus:@"Model quota or rate limit reached. Choose a local or paid model above, or wait and retry."
                              color:[NSColor systemRedColor]];
                } else {
                    [self setStatus:message color:[NSColor systemRedColor]];
                }
                self.previewTextView.string = message;
#if DEBUG
                [self finishAutoGenerationWithDraft:nil text:nil errorMessage:message];
#endif
                return;
            }
            NSError *validationError = nil;
            AICompositionDraft *draft = [AICompositionService draftFromResponse:text
                                                                          song:song
                                                              targetTrackIndex:targetIndex
                                                                         error:&validationError];
            if (!draft) {
                if (self.retryCount == 0) {
                    self.retryCount = 1;
                    NSString *reason = validationError.localizedDescription ?: @"The response was not valid JSON.";
                    [self setStatus:[NSString stringWithFormat:@"Retrying after invalid output: %@", reason]
                              color:[NSColor systemOrangeColor]];
                    [self requestDraftWithBrief:brief model:model retryPrompt:reason];
                    return;
                }
                [self.progressIndicator stopAnimation:nil];
                self.generateButton.enabled = YES;
                [self setStatus:validationError.localizedDescription ?: @"The AI response was invalid."
                          color:[NSColor systemRedColor]];
                self.previewTextView.string = [NSString stringWithFormat:@"Invalid response:\n%@\n\nRaw output:\n%@", validationError.localizedDescription ?: @"Unknown validation error.", text ?: @""];
#if DEBUG
                [self finishAutoGenerationWithDraft:nil
                                               text:text
                                       errorMessage:validationError.localizedDescription ?: @"The AI response was invalid."];
#endif
                return;
            }
            [self.progressIndicator stopAnimation:nil];
            self.generateButton.enabled = YES;
            self.draft = draft;
            self.acceptButton.enabled = YES;
            self.discardButton.enabled = YES;
            [self setStatus:@"Draft ready. Review it, then Accept or Discard." color:[NSColor systemGreenColor]];
            self.previewTextView.string = [NSString stringWithFormat:@"%@\n\nTarget: %@\n\nRaw response:\n%@",
                                           draft.summary,
                                           targetIndex >= 0 ? [NSString stringWithFormat:@"track %ld", (long)(targetIndex + 1)] : @"whole song",
                                           text ?: @""];
#if DEBUG
            [self finishAutoGenerationWithDraft:draft text:text errorMessage:nil];
#endif
        });
    }];
}

- (void)acceptDraft:(id)sender {
    if (!self.draft) return;
    [self saveSettings];
    AICompositionDraft *draft = self.draft;
    [self.songDocument performEditNamed:@"Accept AI Draft" block:^(Song *song) {
        NSError *error = nil;
        if (![AICompositionService applyDraft:draft toSong:song error:&error]) {
            NSLog(@"Failed to apply AI draft: %@", error);
        }
    }];
    [self closeSheetWithCode:NSModalResponseOK];
}

- (void)discardDraft:(id)sender {
    self.draft = nil;
    self.acceptButton.enabled = NO;
    self.discardButton.enabled = NO;
    self.previewTextView.string = @"Draft discarded. Generate another draft or cancel.";
    [self setStatus:@"Draft discarded." color:[NSColor secondaryLabelColor]];
}

- (void)cancel:(id)sender {
    [self closeSheetWithCode:NSModalResponseCancel];
}

- (void)closeSheetWithCode:(NSModalResponse)code {
    [self saveSettings];
    if (self.window.sheetParent) {
        [self.window.sheetParent endSheet:self.window returnCode:code];
    } else {
        [self.window close];
    }
}

@end
