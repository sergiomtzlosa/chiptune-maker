#import "AppDelegate.h"
#import "SongDocument.h"
#import "Track.h"
#import "MainWindowController.h"
#import "HelpWindowController.h"

@interface NSObject (ChiptuneMakerMenuActions)
- (void)togglePlayback:(id)sender;
- (void)stopPlayback:(id)sender;
- (void)generateSong:(id)sender;
- (void)showAIPanel:(id)sender;
- (void)addTrack:(id)sender;
- (void)removeTrack:(id)sender;
- (void)showStepSequencer:(id)sender;
- (void)showPianoRoll:(id)sender;
- (void)toggleFollowPlayhead:(id)sender;
- (void)exportSong:(id)sender;
- (void)showHelp:(id)sender;
- (void)showAIHelp:(id)sender;
- (void)undo:(id)sender;
- (void)redo:(id)sender;
@end

@interface AppDelegate ()
@property (nonatomic) BOOL launching;
@property (nonatomic, copy) NSArray<NSURL *> *launchURLs;
@property (nonatomic, strong) HelpWindowController *helpWindowController;
@end

@implementation AppDelegate

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
    self.launching = YES;
    [self buildMainMenu];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    if (NSClassFromString(@"XCTestCase") != nil) return;
    [[NSDocumentController sharedDocumentController] setAutosavingDelay:2.0];
    [NSApp activateIgnoringOtherApps:YES];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self cleanUpLaunchDocuments];
        self.launching = NO;
    });
}

- (BOOL)url:(NSURL *)url matchesURL:(NSURL *)otherURL {
    if (!url || !otherURL) return NO;
    return [[url.URLByStandardizingPath.path stringByStandardizingPath] isEqualToString:[otherURL.URLByStandardizingPath.path stringByStandardizingPath]];
}

- (NSString *)normalizedPathForURL:(NSURL *)url {
    return [url.URLByStandardizingPath.path stringByStandardizingPath];
}

- (void)closeDuplicateDocuments {
    NSDocumentController *controller = [NSDocumentController sharedDocumentController];
    NSMutableSet<NSString *> *seenURLs = [NSMutableSet set];
    for (NSDocument *document in [controller.documents copy]) {
        if (document.fileURL == nil) continue;
        NSString *path = [self normalizedPathForURL:document.fileURL];
        if ([seenURLs containsObject:path]) {
            if (document.isDocumentEdited) {
                [document updateChangeCount:NSChangeCleared];
            }
            [document close];
        } else {
            [seenURLs addObject:path];
        }
    }
}

- (void)closeUntitledDocumentsIfFileDocumentsExist {
    NSDocumentController *controller = [NSDocumentController sharedDocumentController];
    BOOL hasFileDocument = NO;
    for (NSDocument *document in controller.documents) {
        if (document.fileURL != nil) {
            hasFileDocument = YES;
            break;
        }
    }
    if (!hasFileDocument) return;
    for (NSDocument *document in [controller.documents copy]) {
        if (document.fileURL != nil) continue;
        if (document.isDocumentEdited) {
            [document updateChangeCount:NSChangeCleared];
        }
        [document close];
    }
}

- (void)cleanUpLaunchDocuments {
    [self closeDuplicateDocuments];
    if (self.launchURLs.count > 0) {
        [self closeDocumentsNotInLaunchURLs];
    } else {
        [self closeUntitledDocumentsIfFileDocumentsExist];
    }
}

- (void)closeDocumentsNotInLaunchURLs {
    if (self.launchURLs.count == 0) return;
    NSDocumentController *controller = [NSDocumentController sharedDocumentController];
    for (NSDocument *document in [controller.documents copy]) {
        BOOL requested = NO;
        for (NSURL *url in self.launchURLs) {
            if ([self url:document.fileURL matchesURL:url]) {
                requested = YES;
                break;
            }
        }
        if (requested) continue;
        // Restored documents from the previous session should not appear when the
        // user launched the app by opening a specific document. Clear the change
        // count first so closing does not show a save panel.
        if (document.isDocumentEdited) {
            [document updateChangeCount:NSChangeCleared];
        }
        [document close];
    }
}

- (void)application:(NSApplication *)application openFiles:(NSArray<NSString *> *)filenames {
    NSDocumentController *controller = [NSDocumentController sharedDocumentController];
    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    for (NSString *filename in filenames) {
        [urls addObject:[NSURL fileURLWithPath:filename]];
    }
    if (self.launching) {
        self.launchURLs = urls;
    }
    for (NSURL *url in urls) {
        if ([controller documentForURL:url]) continue;
        [controller openDocumentWithContentsOfURL:url
                                          display:YES
                                completionHandler:^(NSDocument *document, BOOL documentWasAlreadyOpen, NSError *error) {
            if (error) NSLog(@"Could not open %@: %@", url.path, error);
        }];
    }
    if (self.launching) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self cleanUpLaunchDocuments];
            self.launching = NO;
        });
    }
    [application replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
}

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender {
    return YES;
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return NO;
}

#pragma mark - Help

- (void)showHelp:(id)sender {
    if (!self.helpWindowController) {
        self.helpWindowController = [[HelpWindowController alloc] init];
    }
    [self.helpWindowController showTopicWithIdentifier:ChiptuneHelpTopicWelcome];
    [self.helpWindowController showWindow:sender];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)showAIHelp:(id)sender {
    if (!self.helpWindowController) {
        self.helpWindowController = [[HelpWindowController alloc] init];
    }
    [self.helpWindowController showTopicWithIdentifier:ChiptuneHelpTopicAI];
    [self.helpWindowController showWindow:sender];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)buildMainMenu {
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"Main"];

    NSMenuItem *appItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"Chiptune Maker"];
    [appMenu addItemWithTitle:@"About Chiptune Maker" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *servicesItem = [[NSMenuItem alloc] initWithTitle:@"Services" action:nil keyEquivalent:@""];
    NSMenu *servicesMenu = [[NSMenu alloc] initWithTitle:@"Services"];
    servicesItem.submenu = servicesMenu;
    [NSApp setServicesMenu:servicesMenu];
    [appMenu addItem:servicesItem];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Hide Chiptune Maker" action:@selector(hide:) keyEquivalent:@"h"];
    NSMenuItem *hideOthers = [appMenu addItemWithTitle:@"Hide Others" action:@selector(hideOtherApplications:) keyEquivalent:@"h"];
    hideOthers.keyEquivalentModifierMask = NSEventModifierFlagOption | NSEventModifierFlagCommand;
    [appMenu addItemWithTitle:@"Show All" action:@selector(unhideAllApplications:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit Chiptune Maker" action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = appMenu;
    [mainMenu addItem:appItem];

    NSMenuItem *fileItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    [fileMenu addItemWithTitle:@"New" action:@selector(newDocument:) keyEquivalent:@"n"];
    [fileMenu addItemWithTitle:@"Open…" action:@selector(openDocument:) keyEquivalent:@"o"];
    NSMenuItem *recent = [fileMenu addItemWithTitle:@"Open Recent" action:nil keyEquivalent:@""];
    NSMenu *recentMenu = [[NSMenu alloc] initWithTitle:@"Open Recent"];
    [recentMenu addItemWithTitle:@"Clear Menu" action:@selector(clearRecentDocuments:) keyEquivalent:@""];
    recent.submenu = recentMenu;
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"Close" action:@selector(performClose:) keyEquivalent:@"w"];
    [fileMenu addItemWithTitle:@"Save…" action:@selector(saveDocument:) keyEquivalent:@"s"];
    NSMenuItem *saveAs = [fileMenu addItemWithTitle:@"Save As…" action:@selector(saveDocumentAs:) keyEquivalent:@"S"];
    saveAs.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"Export…" action:@selector(exportSong:) keyEquivalent:@"e"];
    fileItem.submenu = fileMenu;
    [mainMenu addItem:fileItem];

    NSMenuItem *editItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
    NSMenuItem *redo = [editMenu addItemWithTitle:@"Redo" action:@selector(redo:) keyEquivalent:@"Z"];
    redo.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"Delete" action:@selector(delete:) keyEquivalent:@"\x7F"];
    editItem.submenu = editMenu;
    [mainMenu addItem:editItem];

    NSMenuItem *songItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    NSMenu *songMenu = [[NSMenu alloc] initWithTitle:@"Song"];
    [songMenu addItemWithTitle:@"Play / Stop" action:@selector(togglePlayback:) keyEquivalent:@""];
    [songMenu addItemWithTitle:@"Stop and Rewind" action:@selector(stopPlayback:) keyEquivalent:@"."];
    [songMenu addItem:[NSMenuItem separatorItem]];
    [songMenu addItemWithTitle:@"Generate Song" action:@selector(generateSong:) keyEquivalent:@"r"];
    [songMenu addItemWithTitle:@"AI Composition…" action:@selector(showAIPanel:) keyEquivalent:@"A"];
    [songMenu addItem:[NSMenuItem separatorItem]];
    [songMenu addItemWithTitle:@"Add Track" action:@selector(addTrack:) keyEquivalent:@""];
    [songMenu addItemWithTitle:@"Remove Track" action:@selector(removeTrack:) keyEquivalent:@""];
    songItem.submenu = songMenu;
    [mainMenu addItem:songItem];

    NSMenuItem *viewItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    [viewMenu addItemWithTitle:@"Step Sequencer" action:@selector(showStepSequencer:) keyEquivalent:@"1"];
    [viewMenu addItemWithTitle:@"Piano Roll" action:@selector(showPianoRoll:) keyEquivalent:@"2"];
    [viewMenu addItem:[NSMenuItem separatorItem]];
    [viewMenu addItemWithTitle:@"Follow Playhead" action:@selector(toggleFollowPlayhead:) keyEquivalent:@"f"];
    viewItem.submenu = viewMenu;
    [mainMenu addItem:viewItem];

    NSMenuItem *windowItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    [windowMenu addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
    [windowMenu addItemWithTitle:@"Zoom" action:@selector(performZoom:) keyEquivalent:@""];
    [windowMenu addItem:[NSMenuItem separatorItem]];
    [windowMenu addItemWithTitle:@"Bring All to Front" action:@selector(arrangeInFront:) keyEquivalent:@""];
    windowItem.submenu = windowMenu;
    [mainMenu addItem:windowItem];
    [NSApp setWindowsMenu:windowMenu];

    NSMenuItem *helpItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    NSMenu *helpMenu = [[NSMenu alloc] initWithTitle:@"Help"];
    NSMenuItem *helpMenuItem = [helpMenu addItemWithTitle:@"Chiptune Maker Help" action:@selector(showHelp:) keyEquivalent:@"?"];
    helpMenuItem.target = self;
    NSMenuItem *aiHelpMenuItem = [helpMenu addItemWithTitle:@"AI Composition Help" action:@selector(showAIHelp:) keyEquivalent:@""];
    aiHelpMenuItem.target = self;
    helpItem.submenu = helpMenu;
    [mainMenu addItem:helpItem];
    [NSApp setHelpMenu:helpMenu];

    [NSApp setMainMenu:mainMenu];
}

@end
