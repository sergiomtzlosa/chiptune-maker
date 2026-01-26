#import <Foundation/Foundation.h>
#import "ChipSynth.h"

@class Song;
@class Track;

/// Builds the renderer parameter set for a track's instrument and effects.
ChipInstrumentParams ChipInstrumentParamsForTrack(Track *track);

@interface ChipRenderer : NSObject

@property (nonatomic, assign) double sampleRate;
@property (nonatomic, assign) BOOL playing;
@property (nonatomic, assign) BOOL loopEnabled;
@property (nonatomic, assign) uint64_t loopStartTick;
@property (nonatomic, assign) uint64_t loopEndTick;
@property (nonatomic, assign, readonly) double currentTick;
@property (nonatomic, assign, readonly) float masterPeak;

- (instancetype)initWithSampleRate:(double)sampleRate;

- (void)prepareWithSong:(Song *)song;
- (void)seekToTick:(uint64_t)tick;
- (void)renderFrames:(NSUInteger)frames left:(float *)left right:(float *)right;

/// Updates tempo without rebuilding the note schedule, so playback can keep
/// running while the tempo field changes.
- (void)updateTempo:(double)tempo;

- (void)setTrackVolume:(double)volume atIndex:(NSInteger)index;
- (void)setTrackPan:(double)pan atIndex:(NSInteger)index;
- (void)setTrackMuted:(BOOL)muted atIndex:(NSInteger)index;
- (void)setTrackSoloed:(BOOL)soloed atIndex:(NSInteger)index;

/// Updates a track's instrument and effect parameters in place. Active voices
/// adopt the new sound immediately instead of waiting for the next note.
- (void)setTrackInstrument:(ChipInstrument)instrument
                    params:(ChipInstrumentParams)params
                   atIndex:(NSInteger)index;

@end
