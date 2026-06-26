#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "ChipSynth.h"

@class Song;
@class ChipRenderer;

@interface AudioEngine : NSObject

@property (nonatomic, strong) Song *song;
@property (nonatomic, assign, readonly) BOOL isPlaying;
@property (nonatomic, assign, readonly) BOOL isPrepared;
@property (nonatomic, strong, readonly) ChipRenderer *renderer;

- (BOOL)prepareWithError:(NSError **)error;
- (void)play;
- (void)pause;
- (void)stop;
- (void)seekToTick:(uint64_t)tick;
- (double)currentTick;
- (void)reloadSong;

- (void)setTrackVolume:(double)volume atIndex:(NSInteger)index;
- (void)setTrackPan:(double)pan atIndex:(NSInteger)index;
- (void)setTrackMuted:(BOOL)muted atIndex:(NSInteger)index;
- (void)setTrackSoloed:(BOOL)soloed atIndex:(NSInteger)index;
- (void)setLoopStartTick:(uint64_t)startTick endTick:(uint64_t)endTick enabled:(BOOL)enabled;

/// Applies tempo and instrument changes without rebuilding the audio graph.
- (void)setTempo:(double)tempo;
- (void)setTrackInstrument:(ChipInstrument)instrument
                    params:(ChipInstrumentParams)params
                   atIndex:(NSInteger)index;

@end
