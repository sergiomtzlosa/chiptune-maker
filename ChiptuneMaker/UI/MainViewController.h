#import <Cocoa/Cocoa.h>

@class SongDocument;

@interface MainViewController : NSViewController

/// View that should receive keyboard focus when the window first appears.
@property (nonatomic, strong, readonly) NSView *preferredFirstResponder;

- (instancetype)initWithDocument:(SongDocument *)document;

@end
