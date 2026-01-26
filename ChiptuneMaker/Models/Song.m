#import "Song.h"
#import "Track.h"
#import "SongSection.h"
#import "NoteEvent.h"

static NSError *SongError(NSString *message) {
    return [NSError errorWithDomain:@"ChiptuneMaker.Song" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSISO8601DateFormatter *SongDateFormatter(void) {
    static NSISO8601DateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSISO8601DateFormatter alloc] init];
        formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
    });
    return formatter;
}

@implementation Song

- (instancetype)init {
    self = [super init];
    if (self) {
        _formatVersion = 1;
        _title = @"Untitled";
        _author = @"";
        _tempo = 120.0;
        _timeSignatureNumerator = 4;
        _timeSignatureDenominator = 4;
        _keyRoot = 0;
        _scale = MusicalScaleMajor;
        _swing = 0.0;
        _lengthBars = 4;
        _generationSeed = 0;
        _generationDensity = 0.6;
        _generationComplexity = 0.5;
        _generationOctaveRange = 2;
        _sections = [NSMutableArray array];
        _tracks = [NSMutableArray array];
        _createdAt = [NSDate date];
        _modifiedAt = _createdAt;
    }
    return self;
}

+ (instancetype)defaultSong {
    Song *song = [[self alloc] init];
    [song.sections addObject:[SongSection sectionWithName:@"Main" startBar:0 lengthBars:4]];

    Track *lead = [Track trackWithName:@"Pulse 1" instrument:ChipInstrumentPulse25];
    lead.volume = 0.72;
    lead.vibratoDepth = 0.12;
    lead.vibratoRate = 5.5;

    Track *harmony = [Track trackWithName:@"Pulse 2" instrument:ChipInstrumentPulse12];
    harmony.volume = 0.55;
    harmony.pan = -0.15;
    harmony.vibratoDepth = 0.08;

    Track *bass = [Track trackWithName:@"Triangle" instrument:ChipInstrumentTriangle];
    bass.volume = 0.82;
    bass.pan = 0.05;

    Track *drums = [Track trackWithName:@"Noise" instrument:ChipInstrumentNoise];
    drums.volume = 0.48;
    drums.pan = 0.0;

    [song.tracks addObject:lead];
    [song.tracks addObject:harmony];
    [song.tracks addObject:bass];
    [song.tracks addObject:drums];
    return song;
}

- (id)copyWithZone:(NSZone *)zone {
    Song *copy = [[Song allocWithZone:zone] init];
    copy.formatVersion = self.formatVersion;
    copy.title = self.title;
    copy.author = self.author;
    copy.tempo = self.tempo;
    copy.timeSignatureNumerator = self.timeSignatureNumerator;
    copy.timeSignatureDenominator = self.timeSignatureDenominator;
    copy.keyRoot = self.keyRoot;
    copy.scale = self.scale;
    copy.swing = self.swing;
    copy.lengthBars = self.lengthBars;
    copy.generationSeed = self.generationSeed;
    copy.generationDensity = self.generationDensity;
    copy.generationComplexity = self.generationComplexity;
    copy.generationOctaveRange = self.generationOctaveRange;
    copy.createdAt = self.createdAt;
    copy.modifiedAt = self.modifiedAt;
    copy.sections = [NSMutableArray arrayWithCapacity:self.sections.count];
    for (SongSection *section in self.sections) {
        [copy.sections addObject:[section copy]];
    }
    copy.tracks = [NSMutableArray arrayWithCapacity:self.tracks.count];
    for (Track *track in self.tracks) {
        [copy.tracks addObject:[track copy]];
    }
    return copy;
}

- (uint64_t)ppq {
    return 480;
}

- (uint64_t)ticksPerBar {
    double beats = (double)self.timeSignatureNumerator * 4.0 / (double)self.timeSignatureDenominator;
    return (uint64_t)llround((double)self.ppq * beats);
}

- (uint64_t)totalTicks {
    return self.ticksPerBar * (uint64_t)MAX(0, self.lengthBars);
}

- (Track *)trackAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.tracks.count) return nil;
    return self.tracks[(NSUInteger)index];
}

- (void)sortNotes {
    for (Track *track in self.tracks) {
        [track sortNotes];
    }
}

- (void)transposePitchedNotesBySemitones:(NSInteger)semitones {
    if (semitones == 0) return;
    for (Track *track in self.tracks) {
        if (track.instrument == ChipInstrumentNoise) continue;
        for (NoteEvent *note in track.notes) {
            note.pitch = MAX(0, MIN(127, note.pitch + semitones));
        }
    }
}

- (void)quantizePitchedNotesToScale:(MusicalScale)scale root:(NSInteger)root {
    NSArray<NSNumber *> *intervals = MusicalScaleIntervals(scale);
    NSInteger normalizedRoot = ((root % 12) + 12) % 12;
    for (Track *track in self.tracks) {
        if (track.instrument == ChipInstrumentNoise) continue;
        for (NoteEvent *note in track.notes) {
            NSInteger pitchClass = ((note.pitch - normalizedRoot) % 12 + 12) % 12;
            if ([intervals containsObject:@(pitchClass)]) continue;

            NSInteger bestPitch = note.pitch;
            NSInteger bestDistance = NSIntegerMax;
            for (NSNumber *interval in intervals) {
                NSInteger base = note.pitch - pitchClass + interval.integerValue;
                for (NSInteger octave = -1; octave <= 1; octave++) {
                    NSInteger candidate = base + octave * 12;
                    if (candidate < 0 || candidate > 127) continue;
                    NSInteger distance = labs(candidate - note.pitch);
                    if (distance < bestDistance || (distance == bestDistance && candidate < bestPitch)) {
                        bestDistance = distance;
                        bestPitch = candidate;
                    }
                }
            }
            note.pitch = bestPitch;
        }
    }
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableArray *sectionDicts = [NSMutableArray arrayWithCapacity:self.sections.count];
    for (SongSection *section in self.sections) {
        [sectionDicts addObject:[section dictionaryRepresentation]];
    }
    NSMutableArray *trackDicts = [NSMutableArray arrayWithCapacity:self.tracks.count];
    for (Track *track in self.tracks) {
        [trackDicts addObject:[track dictionaryRepresentation]];
    }
    return @{
        @"formatVersion": @(self.formatVersion),
        @"metadata": @{
            @"title": self.title ?: @"Untitled",
            @"author": self.author ?: @"",
            @"createdAt": [SongDateFormatter() stringFromDate:self.createdAt ?: [NSDate date]],
            @"modifiedAt": [SongDateFormatter() stringFromDate:self.modifiedAt ?: [NSDate date]],
            @"appVersion": @"0.1.0"
        },
        @"tempo": @(self.tempo),
        @"timeSignature": @{
            @"numerator": @(self.timeSignatureNumerator),
            @"denominator": @(self.timeSignatureDenominator)
        },
        @"key": @{
            @"root": @(self.keyRoot),
            @"scale": MusicalScaleIdentifier(self.scale)
        },
        @"swing": @(self.swing),
        @"lengthBars": @(self.lengthBars),
        @"generation": @{
            @"seed": [NSString stringWithFormat:@"%llu", (unsigned long long)self.generationSeed],
            @"density": @(self.generationDensity),
            @"complexity": @(self.generationComplexity),
            @"octaveRange": @(self.generationOctaveRange)
        },
        @"sections": sectionDicts,
        @"tracks": trackDicts
    };
}

+ (instancetype)songFromDictionary:(NSDictionary *)dictionary error:(NSError **)error {
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        if (error) *error = SongError(@"The project file is not a JSON object.");
        return nil;
    }
    NSInteger version = [dictionary[@"formatVersion"] integerValue];
    if (version > 1) {
        if (error) *error = SongError([NSString stringWithFormat:@"Project format version %ld is newer than this app supports.", (long)version]);
        return nil;
    }
    Song *song = [[self alloc] init];
    song.formatVersion = MAX(1, version);

    NSDictionary *metadata = dictionary[@"metadata"];
    if ([metadata isKindOfClass:[NSDictionary class]]) {
        NSString *title = metadata[@"title"];
        if ([title isKindOfClass:[NSString class]]) song.title = title;
        NSString *author = metadata[@"author"];
        if ([author isKindOfClass:[NSString class]]) song.author = author;
        NSDate *created = [SongDateFormatter() dateFromString:metadata[@"createdAt"] ?: @""];
        if (created) song.createdAt = created;
        NSDate *modified = [SongDateFormatter() dateFromString:metadata[@"modifiedAt"] ?: @""];
        if (modified) song.modifiedAt = modified;
    }

    NSNumber *tempo = dictionary[@"tempo"];
    if ([tempo isKindOfClass:[NSNumber class]]) song.tempo = tempo.doubleValue;
    NSDictionary *timeSignature = dictionary[@"timeSignature"];
    if ([timeSignature isKindOfClass:[NSDictionary class]]) {
        song.timeSignatureNumerator = [timeSignature[@"numerator"] integerValue];
        song.timeSignatureDenominator = [timeSignature[@"denominator"] integerValue];
    }
    NSDictionary *key = dictionary[@"key"];
    if ([key isKindOfClass:[NSDictionary class]]) {
        song.keyRoot = [key[@"root"] integerValue];
        NSString *scale = key[@"scale"];
        if ([scale isKindOfClass:[NSString class]]) song.scale = MusicalScaleFromIdentifier(scale);
    }
    NSNumber *swing = dictionary[@"swing"];
    if ([swing isKindOfClass:[NSNumber class]]) song.swing = swing.doubleValue;
    NSNumber *lengthBars = dictionary[@"lengthBars"];
    if ([lengthBars isKindOfClass:[NSNumber class]]) song.lengthBars = lengthBars.integerValue;

    NSDictionary *generation = dictionary[@"generation"];
    if ([generation isKindOfClass:[NSDictionary class]]) {
        id seed = generation[@"seed"];
        if ([seed isKindOfClass:[NSString class]]) {
            song.generationSeed = strtoull([seed UTF8String], NULL, 10);
        } else if ([seed isKindOfClass:[NSNumber class]]) {
            song.generationSeed = [seed unsignedLongLongValue];
        }
        NSNumber *density = generation[@"density"];
        if ([density isKindOfClass:[NSNumber class]]) song.generationDensity = density.doubleValue;
        NSNumber *complexity = generation[@"complexity"];
        if ([complexity isKindOfClass:[NSNumber class]]) song.generationComplexity = complexity.doubleValue;
        NSNumber *octaveRange = generation[@"octaveRange"];
        if ([octaveRange isKindOfClass:[NSNumber class]]) song.generationOctaveRange = octaveRange.integerValue;
    }

    NSArray *sections = dictionary[@"sections"];
    if ([sections isKindOfClass:[NSArray class]]) {
        for (NSDictionary *sectionDict in sections) {
            SongSection *section = [SongSection sectionFromDictionary:sectionDict];
            if (section) [song.sections addObject:section];
        }
    }
    NSArray *tracks = dictionary[@"tracks"];
    if ([tracks isKindOfClass:[NSArray class]]) {
        for (NSDictionary *trackDict in tracks) {
            Track *track = [Track trackFromDictionary:trackDict];
            if (track) [song.tracks addObject:track];
        }
    }

    if (song.sections.count == 0) {
        [song.sections addObject:[SongSection sectionWithName:@"Main" startBar:0 lengthBars:MAX(1, song.lengthBars)]];
    }
    if (song.tracks.count == 0) {
        if (error) *error = SongError(@"The project file does not contain any tracks.");
        return nil;
    }
    if (![song validateWithError:error]) return nil;
    [song sortNotes];
    return song;
}

- (BOOL)validateWithError:(NSError **)error {
    if (self.tempo < 40 || self.tempo > 300) {
        if (error) *error = SongError(@"Tempo must be between 40 and 300 BPM.");
        return NO;
    }
    if (self.timeSignatureNumerator < 1 || self.timeSignatureNumerator > 16) {
        if (error) *error = SongError(@"Time signature numerator must be between 1 and 16.");
        return NO;
    }
    if (self.timeSignatureDenominator < 1 || self.timeSignatureDenominator > 32 ||
        (self.timeSignatureDenominator & (self.timeSignatureDenominator - 1)) != 0) {
        if (error) *error = SongError(@"Time signature denominator must be a power of two from 1 to 32.");
        return NO;
    }
    if (self.lengthBars < 1 || self.lengthBars > 256) {
        if (error) *error = SongError(@"Song length must be between 1 and 256 bars.");
        return NO;
    }
    if (self.tracks.count < 1 || self.tracks.count > 8) {
        if (error) *error = SongError(@"A song must have between 1 and 8 tracks.");
        return NO;
    }
    if (self.sections.count == 0) {
        if (error) *error = SongError(@"A song must have at least one section.");
        return NO;
    }

    NSInteger lastEnd = 0;
    for (SongSection *section in self.sections) {
        if (section.startBar < 0 || section.lengthBars < 1) {
            if (error) *error = SongError(@"Sections must have a non-negative start bar and positive length.");
            return NO;
        }
        if (section.startBar < lastEnd) {
            if (error) *error = SongError(@"Sections may not overlap.");
            return NO;
        }
        lastEnd = section.startBar + section.lengthBars;
    }
    if (lastEnd > self.lengthBars) {
        if (error) *error = SongError(@"A section extends beyond the end of the song.");
        return NO;
    }

    uint64_t totalTicks = self.totalTicks;
    for (Track *track in self.tracks) {
        if (track.notes.count > 20000) {
            if (error) *error = SongError([NSString stringWithFormat:@"Track “%@” contains too many notes.", track.name]);
            return NO;
        }
        if (track.volume < 0 || track.volume > 1.001) {
            if (error) *error = SongError([NSString stringWithFormat:@"Track “%@” has an invalid volume.", track.name]);
            return NO;
        }
        if (track.pan < -1.001 || track.pan > 1.001) {
            if (error) *error = SongError([NSString stringWithFormat:@"Track “%@” has an invalid pan value.", track.name]);
            return NO;
        }
        for (NoteEvent *note in track.notes) {
            if (note.pitch < 0 || note.pitch > 127) {
                if (error) *error = SongError([NSString stringWithFormat:@"Track “%@” contains a note outside the MIDI pitch range.", track.name]);
                return NO;
            }
            if (note.velocity < 0 || note.velocity > 127) {
                if (error) *error = SongError([NSString stringWithFormat:@"Track “%@” contains a note with an invalid velocity.", track.name]);
                return NO;
            }
            if (note.durationTicks == 0) {
                if (error) *error = SongError([NSString stringWithFormat:@"Track “%@” contains a zero-length note.", track.name]);
                return NO;
            }
            if (note.startTick >= totalTicks) {
                if (error) *error = SongError([NSString stringWithFormat:@"Track “%@” contains a note beyond the end of the song.", track.name]);
                return NO;
            }
        }
    }
    return YES;
}

@end
