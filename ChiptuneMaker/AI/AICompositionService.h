#import <Foundation/Foundation.h>

@class Song;
@class Track;

NS_ASSUME_NONNULL_BEGIN

@interface AICompositionDraft : NSObject

@property (nonatomic, copy) NSString *summary;
@property (nonatomic, copy) NSString *rawResponse;
@property (nonatomic, strong) NSArray<Track *> *tracks;
@property (nonatomic, assign) NSInteger targetTrackIndex;

@end

@interface AICompositionService : NSObject

+ (NSString *)promptForSong:(Song *)song
           targetTrackIndex:(NSInteger)targetTrackIndex
                      brief:(NSString *)brief;

+ (nullable AICompositionDraft *)draftFromResponse:(NSString *)response
                                              song:(Song *)song
                                  targetTrackIndex:(NSInteger)targetTrackIndex
                                             error:(NSError **)error;

+ (BOOL)applyDraft:(AICompositionDraft *)draft toSong:(Song *)song error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
