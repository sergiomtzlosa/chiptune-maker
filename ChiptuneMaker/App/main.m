#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"

static AppDelegate *gAppDelegate = nil;

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *application = [NSApplication sharedApplication];
        gAppDelegate = [[AppDelegate alloc] init];
        application.delegate = gAppDelegate;
        [application setActivationPolicy:NSApplicationActivationPolicyRegular];
        [application run];
    }
    return 0;
}
