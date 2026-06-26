#import <Cocoa/Cocoa.h>
#import "Song.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const SongDocumentDidChangeNotification;

@interface SongDocument : NSDocument

@property (nonatomic, strong) Song *song;

- (void)performEditNamed:(NSString *)actionName block:(void (^)(Song *song))block;
- (void)restoreSong:(Song *)song;
- (void)notifySongChanged;

@end

NS_ASSUME_NONNULL_END
