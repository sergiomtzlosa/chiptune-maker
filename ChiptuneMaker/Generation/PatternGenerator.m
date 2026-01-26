#import "PatternGenerator.h"
#import "Song.h"
#import "Track.h"
#import "SongSection.h"
#import "NoteEvent.h"
#import "SeededRandom.h"

static uint64_t SubSeed(uint64_t seed, NSInteger trackIndex, NSInteger sectionIndex) {
    uint64_t value = seed;
    value ^= 0x9E3779B97F4A7C15ULL * (uint64_t)(trackIndex + 1);
    value ^= 0xD1B54A32D192ED03ULL * (uint64_t)(sectionIndex + 1);
    return value;
}

static NSArray<NSNumber *> *PitchPool(NSInteger root, MusicalScale scale, NSInteger low, NSInteger high) {
    NSMutableArray<NSNumber *> *pool = [NSMutableArray array];
    NSArray<NSNumber *> *intervals = MusicalScaleIntervals(scale);
    for (NSInteger octave = -1; octave <= 9; octave++) {
        for (NSNumber *interval in intervals) {
            NSInteger pitch = (octave + 1) * 12 + root + interval.integerValue;
            if (pitch >= low && pitch <= high && pitch >= 0 && pitch <= 127) {
                [pool addObject:@(pitch)];
            }
        }
    }
    if (pool.count == 0) {
        for (NSInteger pitch = low; pitch <= high; pitch++) [pool addObject:@(pitch)];
    }
    return pool;
}

static NSInteger NearestIndex(NSArray<NSNumber *> *pool, NSInteger pitch) {
    NSInteger best = 0;
    NSInteger bestDistance = NSIntegerMax;
    for (NSInteger i = 0; i < (NSInteger)pool.count; i++) {
        NSInteger distance = labs(pool[(NSUInteger)i].integerValue - pitch);
        if (distance < bestDistance) {
            bestDistance = distance;
            best = i;
        }
    }
    return best;
}

static NSInteger RandomWalkPitch(SeededRandom *random, NSArray<NSNumber *> *pool, NSInteger current, NSInteger steps) {
    NSInteger index = NearestIndex(pool, current);
    index += [random nextIntFrom:-steps to:steps];
    index = MAX(0, MIN((NSInteger)pool.count - 1, index));
    return pool[(NSUInteger)index].integerValue;
}

@implementation PatternGenerator

+ (void)generateSong:(Song *)song seed:(uint64_t)seed {
    if (!song) return;
    song.generationSeed = seed;
    if (song.sections.count == 0) {
        [song.sections addObject:[SongSection sectionWithName:@"Main" startBar:0 lengthBars:MAX(1, song.lengthBars)]];
    }
    for (NSInteger trackIndex = 0; trackIndex < (NSInteger)song.tracks.count; trackIndex++) {
        Track *track = song.tracks[(NSUInteger)trackIndex];
        [track.notes removeAllObjects];
        for (NSInteger sectionIndex = 0; sectionIndex < (NSInteger)song.sections.count; sectionIndex++) {
            SongSection *section = song.sections[(NSUInteger)sectionIndex];
            [self generateTrack:track inSong:song seed:seed section:section trackIndex:trackIndex sectionIndex:sectionIndex];
        }
    }
    [song sortNotes];
}

+ (void)generateTrack:(Track *)track
             inSong:(Song *)song
               seed:(uint64_t)seed
            section:(SongSection *)section
           trackIndex:(NSInteger)trackIndex
        sectionIndex:(NSInteger)sectionIndex {
    if (!track || !song || !section) return;
    uint64_t ticksPerBar = song.ticksPerBar;
    uint64_t stepTicks = MAX(1ULL, song.ppq / 4);
    uint64_t startTick = (uint64_t)section.startBar * ticksPerBar;
    uint64_t endTick = startTick + (uint64_t)section.lengthBars * ticksPerBar;
    [track removeNotesInTickRange:startTick endTick:endTick];

    SeededRandom *random = [[SeededRandom alloc] initWithSeed:SubSeed(seed, trackIndex, sectionIndex)];
    double density = MIN(1.0, MAX(0.0, song.generationDensity));
    double complexity = MIN(1.0, MAX(0.0, song.generationComplexity));

    if (track.instrument == ChipInstrumentNoise) {
        [self generateDrumsForTrack:track song:song random:random startTick:startTick bars:section.lengthBars stepTicks:stepTicks];
        return;
    }
    if (track.instrument == ChipInstrumentTriangle) {
        [self generateBassForTrack:track song:song random:random startTick:startTick bars:section.lengthBars stepTicks:stepTicks density:density];
        return;
    }
    if (trackIndex == 1) {
        [self generateArpeggioForTrack:track song:song random:random startTick:startTick bars:section.lengthBars stepTicks:stepTicks density:density complexity:complexity];
        return;
    }
    [self generateLeadForTrack:track song:song random:random startTick:startTick bars:section.lengthBars stepTicks:stepTicks density:density complexity:complexity];
}

+ (void)generateLeadForTrack:(Track *)track
                        song:(Song *)song
                      random:(SeededRandom *)random
                   startTick:(uint64_t)startTick
                        bars:(NSInteger)bars
                   stepTicks:(uint64_t)stepTicks
                     density:(double)density
                  complexity:(double)complexity {
    NSArray<NSNumber *> *pool = PitchPool(song.keyRoot, song.scale, 57, 86);
    NSMutableArray<NSNumber *> *motif = [NSMutableArray arrayWithCapacity:16];
    for (NSInteger i = 0; i < 16; i++) [motif addObject:@(-1)];

    NSInteger currentPitch = pool[NearestIndex(pool, 69)].integerValue;
    for (NSInteger step = 0; step < 16; step++) {
        double probability = 0.28 + density * 0.55;
        if ([random chance:probability]) {
            currentPitch = RandomWalkPitch(random, pool, currentPitch, 2);
            motif[(NSUInteger)step] = @(currentPitch);
        }
    }

    uint64_t ticksPerBar = song.ticksPerBar;
    for (NSInteger bar = 0; bar < bars; bar++) {
        NSMutableArray<NSNumber *> *barMotif = [motif mutableCopy];
        if (bar > 0) {
            NSInteger mutations = (NSInteger)llround(complexity * 3.0);
            for (NSInteger m = 0; m < mutations; m++) {
                NSInteger index = [random nextIntFrom:0 to:15];
                if ([random chance:0.65]) {
                    barMotif[(NSUInteger)index] = @(RandomWalkPitch(random, pool, currentPitch, 2));
                } else {
                    barMotif[(NSUInteger)index] = @(-1);
                }
            }
        }
        uint64_t barStart = startTick + (uint64_t)bar * ticksPerBar;
        NSInteger step = 0;
        while (step < 16) {
            NSInteger pitch = barMotif[(NSUInteger)step].integerValue;
            if (pitch < 0) {
                step++;
                continue;
            }
            NSInteger length = 1;
            while (step + length < 16 && barMotif[(NSUInteger)(step + length)].integerValue == pitch) {
                length++;
            }
            uint64_t tick = barStart + (uint64_t)step * stepTicks;
            uint64_t duration = (uint64_t)length * stepTicks;
            NSInteger velocity = [random nextIntFrom:82 to:118];
            [track.notes addObject:[NoteEvent noteWithPitch:pitch startTick:tick durationTicks:duration velocity:velocity]];
            step += length;
        }
    }
}

+ (void)generateBassForTrack:(Track *)track
                        song:(Song *)song
                      random:(SeededRandom *)random
                   startTick:(uint64_t)startTick
                        bars:(NSInteger)bars
                   stepTicks:(uint64_t)stepTicks
                     density:(double)density {
    NSArray<NSNumber *> *pool = PitchPool(song.keyRoot, song.scale, 28, 55);
    NSInteger rootIndex = NearestIndex(pool, 36 + song.keyRoot);
    uint64_t ticksPerBar = song.ticksPerBar;
    NSInteger chordDegrees[] = {0, 2, 4, 2};
    for (NSInteger bar = 0; bar < bars; bar++) {
        uint64_t barStart = startTick + (uint64_t)bar * ticksPerBar;
        for (NSInteger beat = 0; beat < 4; beat++) {
            if (beat == 3 && [random chance:0.55]) continue;
            NSInteger degree = chordDegrees[(beat + bar) % 4];
            NSInteger index = MAX(0, MIN((NSInteger)pool.count - 1, rootIndex + degree));
            NSInteger pitch = pool[(NSUInteger)index].integerValue;
            uint64_t tick = barStart + (uint64_t)beat * song.ppq;
            uint64_t duration = (uint64_t)(beat == 0 ? 2 : 1) * song.ppq;
            NSInteger velocity = [random nextIntFrom:92 to:118];
            [track.notes addObject:[NoteEvent noteWithPitch:pitch startTick:tick durationTicks:duration velocity:velocity]];
            (void)density;
        }
    }
}

+ (void)generateArpeggioForTrack:(Track *)track
                            song:(Song *)song
                          random:(SeededRandom *)random
                       startTick:(uint64_t)startTick
                            bars:(NSInteger)bars
                       stepTicks:(uint64_t)stepTicks
                         density:(double)density
                      complexity:(double)complexity {
    NSArray<NSNumber *> *pool = PitchPool(song.keyRoot, song.scale, 60, 88);
    NSInteger baseIndex = NearestIndex(pool, 72 + song.keyRoot);
    NSInteger chord[] = {0, 2, 4, 7};
    uint64_t ticksPerBar = song.ticksPerBar;
    for (NSInteger bar = 0; bar < bars; bar++) {
        uint64_t barStart = startTick + (uint64_t)bar * ticksPerBar;
        for (NSInteger step = 0; step < 16; step += 2) {
            if ([random chance:0.15 + (1.0 - density) * 0.4]) continue;
            NSInteger degree = chord[(step / 2 + bar) % 4];
            NSInteger index = MAX(0, MIN((NSInteger)pool.count - 1, baseIndex + degree));
            NSInteger pitch = pool[(NSUInteger)index].integerValue;
            uint64_t tick = barStart + (uint64_t)step * stepTicks;
            uint64_t duration = stepTicks * (complexity > 0.7 ? 2 : 1);
            NSInteger velocity = [random nextIntFrom:62 to:94];
            [track.notes addObject:[NoteEvent noteWithPitch:pitch startTick:tick durationTicks:duration velocity:velocity]];
        }
    }
}

+ (void)generateDrumsForTrack:(Track *)track
                         song:(Song *)song
                       random:(SeededRandom *)random
                    startTick:(uint64_t)startTick
                         bars:(NSInteger)bars
                    stepTicks:(uint64_t)stepTicks {
    uint64_t ticksPerBar = song.ticksPerBar;
    for (NSInteger bar = 0; bar < bars; bar++) {
        uint64_t barStart = startTick + (uint64_t)bar * ticksPerBar;
        for (NSInteger step = 0; step < 16; step++) {
            NSInteger pitch = -1;
            NSInteger velocity = 100;
            if (step == 0 || step == 8) {
                pitch = 36;
                velocity = 112;
            } else if (step == 4 || step == 12) {
                pitch = 48;
                velocity = 104;
            } else if (step % 2 == 1 && [random chance:0.55]) {
                pitch = 72;
                velocity = [random nextIntFrom:46 to:76];
            }
            if (pitch < 0) continue;
            uint64_t tick = barStart + (uint64_t)step * stepTicks;
            uint64_t duration = MAX(1ULL, stepTicks / 2);
            [track.notes addObject:[NoteEvent noteWithPitch:pitch startTick:tick durationTicks:duration velocity:velocity]];
        }
    }
}

@end
