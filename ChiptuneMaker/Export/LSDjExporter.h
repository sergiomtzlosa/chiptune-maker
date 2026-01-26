#import <Foundation/Foundation.h>

@class Song;

@interface LSDjExporter : NSObject

/// Builds a Little Sound DJ single-song file (`.lsdsng`).
///
/// Each app bar becomes a 16-step phrase, groups of up to 16 bars become chains,
/// and every chain group is placed on one LSDj song row. Pulse tracks map to
/// PU1/PU2, triangle and wavetable tracks map to WAVE, and noise tracks map to
/// NOISE. One LSDj instrument is created per audible app track.
+ (NSData *)dataForSong:(Song *)song audibleOnly:(BOOL)audibleOnly error:(NSError **)error;

@end
