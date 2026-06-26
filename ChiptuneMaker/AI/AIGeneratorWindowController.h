#import <Cocoa/Cocoa.h>

@class SongDocument;

NS_ASSUME_NONNULL_BEGIN

@interface AIGeneratorWindowController : NSWindowController

- (instancetype)initWithDocument:(SongDocument *)document;

@end

NS_ASSUME_NONNULL_END
