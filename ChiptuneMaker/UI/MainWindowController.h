#import <Cocoa/Cocoa.h>

@class SongDocument;

@interface MainWindowController : NSWindowController

- (instancetype)initWithDocument:(SongDocument *)document;

@end
