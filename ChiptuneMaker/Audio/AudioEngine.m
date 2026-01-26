#import "AudioEngine.h"
#import "ChipRenderer.h"
#import "Song.h"

@interface AudioEngine ()
@property (nonatomic, strong) AVAudioEngine *engine;
@property (nonatomic, strong) AVAudioSourceNode *sourceNode;
@property (nonatomic, assign) BOOL prepared;
@property (nonatomic, assign) BOOL playing;
@property (nonatomic, assign) float *scratchLeft;
@property (nonatomic, assign) float *scratchRight;
@property (nonatomic, assign) NSUInteger scratchCapacity;
@end

@implementation AudioEngine

- (instancetype)init {
    self = [super init];
    if (self) {
        _renderer = [[ChipRenderer alloc] initWithSampleRate:44100.0];
        _scratchCapacity = 4096;
        _scratchLeft = calloc(_scratchCapacity, sizeof(float));
        _scratchRight = calloc(_scratchCapacity, sizeof(float));
    }
    return self;
}

- (void)dealloc {
    [_engine stop];
    free(_scratchLeft);
    free(_scratchRight);
}

- (BOOL)isPlaying {
    // The renderer stops itself at the end of the song. Reflect that in the
    // transport state as soon as the UI asks, without waiting for another
    // document edit.
    if (self.playing && !self.renderer.playing) {
        self.playing = NO;
    }
    return self.playing;
}

- (BOOL)isPrepared {
    return self.prepared;
}

- (BOOL)prepareWithError:(NSError **)error {
    if (self.prepared) return YES;
    self.engine = [[AVAudioEngine alloc] init];
    AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100.0 channels:2];
    if (!format) {
        if (error) *error = [NSError errorWithDomain:@"ChiptuneMaker.Audio" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Could not create the audio format."}];
        return NO;
    }

    ChipRenderer *renderer = self.renderer;
    float *scratchLeft = self.scratchLeft;
    float *scratchRight = self.scratchRight;
    NSUInteger scratchCapacity = self.scratchCapacity;

    self.sourceNode = [[AVAudioSourceNode alloc] initWithFormat:format renderBlock:^OSStatus(BOOL *isSilence, const AudioTimeStamp *timestamp, AVAudioFrameCount frameCount, AudioBufferList *outputData) {
        if (outputData->mNumberBuffers >= 2) {
            float *left = (float *)outputData->mBuffers[0].mData;
            float *right = (float *)outputData->mBuffers[1].mData;
            [renderer renderFrames:frameCount left:left right:right];
        } else if (outputData->mNumberBuffers == 1) {
            float *interleaved = (float *)outputData->mBuffers[0].mData;
            NSUInteger remaining = frameCount;
            NSUInteger offset = 0;
            while (remaining > 0) {
                NSUInteger chunk = MIN(remaining, scratchCapacity);
                [renderer renderFrames:chunk left:scratchLeft right:scratchRight];
                for (NSUInteger i = 0; i < chunk; i++) {
                    interleaved[(offset + i) * 2] = scratchLeft[i];
                    interleaved[(offset + i) * 2 + 1] = scratchRight[i];
                }
                offset += chunk;
                remaining -= chunk;
            }
        }
        *isSilence = !renderer.playing;
        return noErr;
    }];

    [self.engine attachNode:self.sourceNode];
    [self.engine connect:self.sourceNode to:self.engine.mainMixerNode format:format];
    self.prepared = YES;
    [self reloadSong];
    return YES;
}

- (void)setSong:(Song *)song {
    _song = song;
    [self reloadSong];
}

- (void)reloadSong {
    if (!self.song) return;
    BOOL wasPlaying = self.isPlaying;
    uint64_t tick = (uint64_t)self.renderer.currentTick;
    if (self.prepared && self.engine.isRunning) {
        [self.engine stop];
    }
    [self.renderer prepareWithSong:self.song];
    [self.renderer seekToTick:tick];
    self.playing = wasPlaying;
    self.renderer.playing = wasPlaying;
    if (self.prepared) {
        [self.engine prepare];
        if (wasPlaying) {
            [self.engine startAndReturnError:nil];
        }
    }
}

- (void)play {
    if (!self.prepared) {
        NSError *error = nil;
        if (![self prepareWithError:&error]) {
            NSLog(@"AudioEngine failed to start: %@", error);
            return;
        }
    }
    self.playing = YES;
    self.renderer.playing = YES;
    if (!self.engine.isRunning) {
        [self.engine startAndReturnError:nil];
    }
}

- (void)pause {
    self.playing = NO;
    self.renderer.playing = NO;
}

- (void)stop {
    self.playing = NO;
    self.renderer.playing = NO;
    [self.renderer seekToTick:0];
}

- (void)seekToTick:(uint64_t)tick {
    [self.renderer seekToTick:tick];
}

- (double)currentTick {
    return self.renderer.currentTick;
}

- (void)setTrackVolume:(double)volume atIndex:(NSInteger)index {
    [self.renderer setTrackVolume:volume atIndex:index];
}

- (void)setTrackPan:(double)pan atIndex:(NSInteger)index {
    [self.renderer setTrackPan:pan atIndex:index];
}

- (void)setTrackMuted:(BOOL)muted atIndex:(NSInteger)index {
    [self.renderer setTrackMuted:muted atIndex:index];
}

- (void)setTrackSoloed:(BOOL)soloed atIndex:(NSInteger)index {
    [self.renderer setTrackSoloed:soloed atIndex:index];
}

- (void)setLoopStartTick:(uint64_t)startTick endTick:(uint64_t)endTick enabled:(BOOL)enabled {
    self.renderer.loopStartTick = startTick;
    self.renderer.loopEndTick = endTick;
    self.renderer.loopEnabled = enabled;
}

- (void)setTempo:(double)tempo {
    [self.renderer updateTempo:tempo];
}

- (void)setTrackInstrument:(ChipInstrument)instrument
                    params:(ChipInstrumentParams)params
                   atIndex:(NSInteger)index {
    [self.renderer setTrackInstrument:instrument params:params atIndex:index];
}

@end
