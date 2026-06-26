#import <Foundation/Foundation.h>

@interface TimingMap : NSObject

/// Converts a musical tick to the tick used for playback and MIDI export.
/// Swing delays the second eighth-note of each pair.
+ (uint64_t)playbackTickForTick:(uint64_t)tick ppq:(uint64_t)ppq swing:(double)swing;

@end
