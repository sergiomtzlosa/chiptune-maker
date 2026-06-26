#import <Foundation/Foundation.h>
#import "SongTypes.h"

@class Song;
@class Track;
@class SongSection;

@interface PatternGenerator : NSObject

+ (void)generateSong:(Song *)song seed:(uint64_t)seed;
+ (void)generateTrack:(Track *)track
             inSong:(Song *)song
               seed:(uint64_t)seed
            section:(SongSection *)section
           trackIndex:(NSInteger)trackIndex
        sectionIndex:(NSInteger)sectionIndex;

@end
