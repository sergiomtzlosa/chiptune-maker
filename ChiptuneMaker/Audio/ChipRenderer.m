#import "ChipRenderer.h"
#import "Song.h"
#import "Track.h"
#import "NoteEvent.h"
#import "TimingMap.h"
#import <math.h>
#import <stdlib.h>
#import <string.h>
#import <stdatomic.h>

typedef struct {
    uint64_t tick;
    int track;
    int note;
    int velocity;
    BOOL on;
} RenderEvent;

typedef struct {
    BOOL active;
    ChipVoice voices[8];
    double lastFrequency;
    uint64_t age;
} RenderTrack;

static int RenderEventCompare(const void *a, const void *b) {
    const RenderEvent *ea = (const RenderEvent *)a;
    const RenderEvent *eb = (const RenderEvent *)b;
    if (ea->tick < eb->tick) return -1;
    if (ea->tick > eb->tick) return 1;
    if (ea->on != eb->on) return ea->on ? 1 : -1;
    if (ea->track < eb->track) return -1;
    if (ea->track > eb->track) return 1;
    return 0;
}

ChipInstrumentParams ChipInstrumentParamsForTrack(Track *track) {
    ChipInstrumentParams params = ChipInstrumentDefaultParams(track.instrument);
    params.vibratoDepth = track.vibratoDepth;
    params.vibratoRate = track.vibratoRate > 0 ? track.vibratoRate : 5.0;
    params.slide = track.slideEnabled;
    params.arpeggio = track.arpeggio;
    return params;
}

@implementation ChipRenderer {
    RenderEvent *_events;
    // `playing` is read by the audio render thread and written by the main
    // thread when transport state changes, so keep it atomic.
    NSUInteger _eventCount;
    NSUInteger _eventIndex;
    RenderTrack _tracks[8];
    NSInteger _trackCount;
    ChipInstrument _instruments[8];
    ChipInstrumentParams _params[8];
    uint64_t _ppq;
    double _ticksPerSecond;
    double _ticksPerSample;
    double _currentTick;
    uint64_t _totalTicks;
    _Atomic(BOOL) _playingFlag;
    volatile float _volumes[8];
    volatile float _pans[8];
    volatile BOOL _mutes[8];
    volatile BOOL _solos[8];
    uint64_t _voiceAge;
    _Atomic(uint64_t) _playheadTick;
    volatile float _peak;
}

- (BOOL)playing {
    return atomic_load(&_playingFlag);
}

- (void)setPlaying:(BOOL)playing {
    atomic_store(&_playingFlag, playing);
}

- (instancetype)initWithSampleRate:(double)sampleRate {
    self = [super init];
    if (self) {
        _sampleRate = sampleRate;
        _loopEnabled = NO;
        _loopStartTick = 0;
        _loopEndTick = 0;
        _stopsAtSongEnd = YES;
        self.playing = NO;
        atomic_init(&_playheadTick, 0);
        for (NSInteger i = 0; i < 8; i++) {
            _volumes[i] = 0.7f;
            _pans[i] = 0.0f;
            _mutes[i] = NO;
            _solos[i] = NO;
            _instruments[i] = ChipInstrumentPulse25;
            _params[i] = ChipInstrumentDefaultParams(ChipInstrumentPulse25);
        }
    }
    return self;
}

- (void)dealloc {
    free(_events);
}

- (double)currentTick {
    return (double)atomic_load(&_playheadTick);
}

- (float)masterPeak {
    return _peak;
}

- (void)prepareWithSong:(Song *)song {
    free(_events);
    _events = NULL;
    _eventCount = 0;
    _eventIndex = 0;
    _currentTick = 0.0;
    _trackCount = MIN((NSInteger)8, (NSInteger)song.tracks.count);
    _ppq = song.ppq;
    _ticksPerSecond = (double)_ppq * song.tempo / 60.0;
    _ticksPerSample = _ticksPerSecond / self.sampleRate;
    _totalTicks = song.totalTicks;
    _voiceAge = 0;
    _peak = 0.0f;
    atomic_store(&_playheadTick, 0);

    for (NSInteger i = 0; i < 8; i++) {
        memset(&_tracks[i], 0, sizeof(RenderTrack));
        _volumes[i] = 0.7f;
        _pans[i] = 0.0f;
        _mutes[i] = NO;
        _solos[i] = NO;
    }

    NSUInteger capacity = 0;
    for (Track *track in song.tracks) {
        capacity += track.notes.count * 2;
    }
    if (capacity == 0) return;
    _events = calloc(capacity, sizeof(RenderEvent));
    if (!_events) return;

    uint64_t ppq = song.ppq;
    for (NSInteger trackIndex = 0; trackIndex < _trackCount; trackIndex++) {
        Track *track = song.tracks[(NSUInteger)trackIndex];
        _instruments[trackIndex] = track.instrument;
        _params[trackIndex] = ChipInstrumentParamsForTrack(track);
        _volumes[trackIndex] = (float)track.volume;
        _pans[trackIndex] = (float)track.pan;
        _mutes[trackIndex] = track.muted;
        _solos[trackIndex] = track.soloed;

        for (NoteEvent *note in track.notes) {
            uint64_t start = [TimingMap playbackTickForTick:note.startTick ppq:ppq swing:song.swing];
            uint64_t duration = note.durationTicks;
            if (duration == 0) duration = 1;
            uint64_t end = start + duration;
            RenderEvent on = {.tick = start, .track = (int)trackIndex, .note = (int)note.pitch, .velocity = (int)note.velocity, .on = YES};
            RenderEvent off = {.tick = end, .track = (int)trackIndex, .note = (int)note.pitch, .velocity = 0, .on = NO};
            _events[_eventCount++] = on;
            _events[_eventCount++] = off;
        }
    }
    qsort(_events, _eventCount, sizeof(RenderEvent), RenderEventCompare);

    self.loopStartTick = 0;
    self.loopEndTick = _totalTicks;
}

- (void)seekToTick:(uint64_t)tick {
    _currentTick = (double)tick;
    _eventIndex = 0;
    while (_eventIndex < _eventCount && _events[_eventIndex].tick < tick) {
        _eventIndex++;
    }
    for (NSInteger i = 0; i < 8; i++) {
        memset(_tracks[i].voices, 0, sizeof(_tracks[i].voices));
        _tracks[i].lastFrequency = 0.0;
    }
    atomic_store(&_playheadTick, tick);
}

- (void)updateTempo:(double)tempo {
    if (_ppq == 0) return;
    double clamped = MIN(300.0, MAX(40.0, tempo));
    _ticksPerSecond = (double)_ppq * clamped / 60.0;
    _ticksPerSample = _ticksPerSecond / self.sampleRate;
}

- (void)setTrackVolume:(double)volume atIndex:(NSInteger)index {
    if (index < 0 || index >= 8) return;
    _volumes[index] = (float)MIN(1.0, MAX(0.0, volume));
}

- (void)setTrackPan:(double)pan atIndex:(NSInteger)index {
    if (index < 0 || index >= 8) return;
    _pans[index] = (float)MIN(1.0, MAX(-1.0, pan));
}

- (void)setTrackMuted:(BOOL)muted atIndex:(NSInteger)index {
    if (index < 0 || index >= 8) return;
    _mutes[index] = muted;
}

- (void)setTrackSoloed:(BOOL)soloed atIndex:(NSInteger)index {
    if (index < 0 || index >= 8) return;
    _solos[index] = soloed;
}

- (void)setTrackInstrument:(ChipInstrument)instrument
                    params:(ChipInstrumentParams)params
                   atIndex:(NSInteger)index {
    if (index < 0 || index >= 8) return;
    _instruments[index] = instrument;
    _params[index] = params;
    for (NSInteger v = 0; v < 8; v++) {
        ChipVoice *voice = &_tracks[index].voices[v];
        if (voice->active) {
            voice->instrument = instrument;
            voice->params = params;
        }
    }
}

- (void)processEventsAtCurrentTick {
    while (_eventIndex < _eventCount && (double)_events[_eventIndex].tick <= _currentTick + 0.5) {
        RenderEvent event = _events[_eventIndex++];
        NSInteger trackIndex = event.track;
        if (trackIndex < 0 || trackIndex >= _trackCount) continue;
        if (event.on) {
            BOOL anySolo = NO;
            for (NSInteger i = 0; i < _trackCount; i++) {
                if (_solos[i]) { anySolo = YES; break; }
            }
            if (_mutes[trackIndex] || (anySolo && !_solos[trackIndex])) continue;

            RenderTrack *track = &_tracks[trackIndex];
            NSInteger slot = -1;
            for (NSInteger v = 0; v < 8; v++) {
                if (!track->voices[v].active) { slot = v; break; }
            }
            if (slot < 0) {
                double quietest = 2.0;
                for (NSInteger v = 0; v < 8; v++) {
                    if (track->voices[v].released && track->voices[v].envelope < quietest) {
                        quietest = track->voices[v].envelope;
                        slot = v;
                    }
                }
            }
            if (slot < 0) slot = 0;
            double previous = track->lastFrequency;
            ChipVoiceStart(&track->voices[slot], trackIndex, event.note, (double)event.velocity / 127.0,
                           _instruments[trackIndex], _params[trackIndex], self.sampleRate, previous);
            track->lastFrequency = 440.0 * pow(2.0, ((double)event.note - 69.0) / 12.0);
            track->age++;
        } else {
            RenderTrack *track = &_tracks[trackIndex];
            for (NSInteger v = 0; v < 8; v++) {
                ChipVoice *voice = &track->voices[v];
                if (voice->active && !voice->released && voice->note == event.note) {
                    ChipVoiceRelease(voice);
                    break;
                }
            }
        }
    }
}

- (void)performLoop {
    if (!self.loopEnabled || self.loopEndTick <= self.loopStartTick) return;
    _currentTick = (double)self.loopStartTick;
    for (NSInteger i = 0; i < 8; i++) {
        memset(_tracks[i].voices, 0, sizeof(_tracks[i].voices));
        _tracks[i].lastFrequency = 0.0;
    }
    _eventIndex = 0;
    while (_eventIndex < _eventCount && _events[_eventIndex].tick < self.loopStartTick) {
        _eventIndex++;
    }
}

- (void)renderSamples:(NSUInteger)frames left:(float *)left right:(float *)right {
    BOOL anySolo = NO;
    for (NSInteger i = 0; i < _trackCount; i++) {
        if (_solos[i]) { anySolo = YES; break; }
    }
    double panL[8], panR[8];
    for (NSInteger i = 0; i < 8; i++) {
        double angle = ((double)_pans[i] + 1.0) * M_PI_4;
        panL[i] = cos(angle);
        panR[i] = sin(angle);
    }

    float peak = 0.0f;
    for (NSUInteger frame = 0; frame < frames; frame++) {
        double mixL = 0.0;
        double mixR = 0.0;
        for (NSInteger t = 0; t < _trackCount; t++) {
            if (_mutes[t] || (anySolo && !_solos[t])) continue;
            double mono = 0.0;
            RenderTrack *track = &_tracks[t];
            for (NSInteger v = 0; v < 8; v++) {
                ChipVoice *voice = &track->voices[v];
                if (voice->active) {
                    mono += ChipVoiceRender(voice, self.sampleRate);
                }
            }
            double volume = _volumes[t];
            mixL += mono * volume * panL[t];
            mixR += mono * volume * panR[t];
        }
        mixL = tanh(mixL * 0.75);
        mixR = tanh(mixR * 0.75);
        left[frame] = (float)mixL;
        right[frame] = (float)mixR;
        peak = MAX(peak, (float)MAX(fabs(mixL), fabs(mixR)));
    }
    _peak = peak;
}

- (void)renderFrames:(NSUInteger)frames left:(float *)left right:(float *)right {
    if (!self.playing) {
        memset(left, 0, frames * sizeof(float));
        memset(right, 0, frames * sizeof(float));
        _peak = 0.0f;
        return;
    }

    BOOL looping = self.loopEnabled && self.loopEndTick > self.loopStartTick;
    BOOL stopAtEnd = self.stopsAtSongEnd;
    if (!looping && stopAtEnd && _totalTicks == 0) {
        memset(left, 0, frames * sizeof(float));
        memset(right, 0, frames * sizeof(float));
        _peak = 0.0f;
        self.playing = NO;
        atomic_store(&_playheadTick, 0);
        return;
    }

    NSUInteger rendered = 0;
    while (rendered < frames) {
        if (_ticksPerSample <= 0) {
            memset(left + rendered, 0, (frames - rendered) * sizeof(float));
            memset(right + rendered, 0, (frames - rendered) * sizeof(float));
            break;
        }

        if (!looping && stopAtEnd && _currentTick >= (double)_totalTicks - 0.5) {
            _currentTick = (double)_totalTicks;
            self.playing = NO;
            atomic_store(&_playheadTick, _totalTicks);
            memset(left + rendered, 0, (frames - rendered) * sizeof(float));
            memset(right + rendered, 0, (frames - rendered) * sizeof(float));
            break;
        }

        NSUInteger framesToRender = frames - rendered;
        if (_eventIndex < _eventCount) {
            uint64_t eventTick = _events[_eventIndex].tick;
            if ((double)eventTick <= _currentTick + 0.5) {
                [self processEventsAtCurrentTick];
                continue;
            }
            double deltaTicks = (double)eventTick - _currentTick;
            NSUInteger untilEvent = (NSUInteger)ceil(deltaTicks / _ticksPerSample);
            if (untilEvent < 1) untilEvent = 1;
            if (untilEvent < framesToRender) framesToRender = untilEvent;
        }

        if (looping) {
            double untilLoop = (double)self.loopEndTick - _currentTick;
            if (untilLoop <= 0.0) {
                [self performLoop];
                continue;
            }
            NSUInteger framesUntilLoop = (NSUInteger)ceil(untilLoop / _ticksPerSample);
            if (framesUntilLoop < 1) framesUntilLoop = 1;
            if (framesUntilLoop < framesToRender) framesToRender = framesUntilLoop;
        } else if (stopAtEnd) {
            double untilEnd = (double)_totalTicks - _currentTick;
            NSUInteger framesUntilEnd = (NSUInteger)ceil(untilEnd / _ticksPerSample);
            if (framesUntilEnd < 1) framesUntilEnd = 1;
            if (framesUntilEnd < framesToRender) framesToRender = framesUntilEnd;
        }

        [self renderSamples:framesToRender left:left + rendered right:right + rendered];
        rendered += framesToRender;
        _currentTick += (double)framesToRender * _ticksPerSample;

        if (_eventIndex < _eventCount && (double)_events[_eventIndex].tick <= _currentTick + 0.5) {
            [self processEventsAtCurrentTick];
        }

        if (looping) {
            if (_currentTick >= (double)self.loopEndTick) {
                [self performLoop];
            }
        } else if (stopAtEnd && _currentTick >= (double)_totalTicks - 0.5) {
            _currentTick = (double)_totalTicks;
            self.playing = NO;
            atomic_store(&_playheadTick, _totalTicks);
            memset(left + rendered, 0, (frames - rendered) * sizeof(float));
            memset(right + rendered, 0, (frames - rendered) * sizeof(float));
            break;
        }
    }

    if (self.playing) {
        atomic_store(&_playheadTick, (uint64_t)llround(_currentTick));
    }
}

@end
