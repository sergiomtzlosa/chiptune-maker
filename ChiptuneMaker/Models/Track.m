#import "Track.h"
#import "NoteEvent.h"

@implementation Track

- (instancetype)init {
    self = [super init];
    if (self) {
        _identifier = [[NSUUID UUID] UUIDString];
        _name = @"Track";
        _instrument = ChipInstrumentPulse25;
        _volume = 0.7;
        _pan = 0.0;
        _muted = NO;
        _soloed = NO;
        _vibratoDepth = 0.0;
        _vibratoRate = 5.0;
        _slideEnabled = NO;
        _arpeggio = 0;
        _notes = [NSMutableArray array];
    }
    return self;
}

+ (instancetype)trackWithName:(NSString *)name instrument:(ChipInstrument)instrument {
    Track *track = [[self alloc] init];
    track.name = name;
    track.instrument = instrument;
    return track;
}

- (id)copyWithZone:(NSZone *)zone {
    Track *copy = [[Track allocWithZone:zone] init];
    copy.identifier = self.identifier;
    copy.name = self.name;
    copy.instrument = self.instrument;
    copy.volume = self.volume;
    copy.pan = self.pan;
    copy.muted = self.muted;
    copy.soloed = self.soloed;
    copy.vibratoDepth = self.vibratoDepth;
    copy.vibratoRate = self.vibratoRate;
    copy.slideEnabled = self.slideEnabled;
    copy.arpeggio = self.arpeggio;
    copy.notes = [NSMutableArray arrayWithCapacity:self.notes.count];
    for (NoteEvent *note in self.notes) {
        [copy.notes addObject:[note copy]];
    }
    return copy;
}

- (void)sortNotes {
    [self.notes sortUsingComparator:^NSComparisonResult(NoteEvent *a, NoteEvent *b) {
        if (a.startTick < b.startTick) return NSOrderedAscending;
        if (a.startTick > b.startTick) return NSOrderedDescending;
        if (a.pitch < b.pitch) return NSOrderedAscending;
        if (a.pitch > b.pitch) return NSOrderedDescending;
        return NSOrderedSame;
    }];
}

- (NoteEvent *)noteStartingAtTick:(uint64_t)tick tolerance:(uint64_t)tolerance {
    for (NoteEvent *note in self.notes) {
        uint64_t delta = note.startTick > tick ? note.startTick - tick : tick - note.startTick;
        if (delta <= tolerance) return note;
    }
    return nil;
}

- (NSArray<NoteEvent *> *)notesInRange:(NSRange)range {
    NSMutableArray *result = [NSMutableArray array];
    uint64_t start = range.location;
    uint64_t end = range.location + range.length;
    for (NoteEvent *note in self.notes) {
        if (note.startTick >= start && note.startTick < end) {
            [result addObject:note];
        }
    }
    return result;
}

- (void)removeNotesInTickRange:(uint64_t)startTick endTick:(uint64_t)endTick {
    NSMutableArray *keep = [NSMutableArray array];
    for (NoteEvent *note in self.notes) {
        if (note.startTick < startTick || note.startTick >= endTick) {
            [keep addObject:note];
        }
    }
    self.notes = keep;
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableArray *noteDicts = [NSMutableArray arrayWithCapacity:self.notes.count];
    for (NoteEvent *note in self.notes) {
        [noteDicts addObject:[note dictionaryRepresentation]];
    }
    return @{
        @"id": self.identifier ?: [[NSUUID UUID] UUIDString],
        @"name": self.name ?: @"Track",
        @"instrument": ChipInstrumentIdentifier(self.instrument),
        @"volume": @(self.volume),
        @"pan": @(self.pan),
        @"mute": @(self.muted),
        @"solo": @(self.soloed),
        @"effects": @{
            @"vibratoDepth": @(self.vibratoDepth),
            @"vibratoRate": @(self.vibratoRate),
            @"slide": @(self.slideEnabled),
            @"arpeggio": @(self.arpeggio)
        },
        @"notes": noteDicts
    };
}

+ (instancetype)trackFromDictionary:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
    Track *track = [[self alloc] init];
    NSString *identifier = dictionary[@"id"];
    if ([identifier isKindOfClass:[NSString class]]) track.identifier = identifier;
    NSString *name = dictionary[@"name"];
    if ([name isKindOfClass:[NSString class]]) track.name = name;
    NSString *instrument = dictionary[@"instrument"];
    if ([instrument isKindOfClass:[NSString class]]) track.instrument = ChipInstrumentFromIdentifier(instrument);
    track.volume = [dictionary[@"volume"] doubleValue];
    track.pan = [dictionary[@"pan"] doubleValue];
    track.muted = [dictionary[@"mute"] boolValue];
    track.soloed = [dictionary[@"solo"] boolValue];
    NSDictionary *effects = dictionary[@"effects"];
    if ([effects isKindOfClass:[NSDictionary class]]) {
        track.vibratoDepth = [effects[@"vibratoDepth"] doubleValue];
        track.vibratoRate = [effects[@"vibratoRate"] doubleValue];
        track.slideEnabled = [effects[@"slide"] boolValue];
        track.arpeggio = [effects[@"arpeggio"] integerValue];
    }
    NSArray *notes = dictionary[@"notes"];
    if ([notes isKindOfClass:[NSArray class]]) {
        for (NSDictionary *noteDict in notes) {
            NoteEvent *note = [NoteEvent noteFromDictionary:noteDict];
            if (note) [track.notes addObject:note];
        }
    }
    if (track.vibratoRate <= 0) track.vibratoRate = 5.0;
    if (track.volume <= 0) track.volume = 0.7;
    [track sortNotes];
    return track;
}

@end
