#import "MainWindowController.h"
#import "MainViewController.h"
#import "SongDocument.h"

@implementation MainWindowController

- (instancetype)initWithDocument:(SongDocument *)document {
    NSRect frame = NSMakeRect(0, 0, 1280, 820);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"Chiptune Maker";
    window.minSize = NSMakeSize(1040, 680);
    window.tabbingMode = NSWindowTabbingModeDisallowed;
    window.releasedWhenClosed = NO;
    [window setFrameAutosaveName:@"ChiptuneMakerDocumentWindow"];
    self = [super initWithWindow:window];
    if (self) {
        MainViewController *controller = [[MainViewController alloc] initWithDocument:document];
        window.contentViewController = controller;
        // Let AppKit establish focus while the window is being shown instead of
        // calling makeFirstResponder: from viewDidAppear on the UI thread.
        window.initialFirstResponder = controller.preferredFirstResponder;
        [window center];
    }
    return self;
}

- (void)showWindow:(id)sender {
    [super showWindow:sender];
    [self.window makeKeyAndOrderFront:nil];
}

@end
