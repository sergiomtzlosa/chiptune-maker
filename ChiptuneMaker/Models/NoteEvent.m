#import "NoteEvent.h"

@implementation NoteEvent

- (instancetype)init {
    self = [super init];
    if (self) {
        _identifier = [[NSUUID UUID] UUIDString];
        _pitch = 60;
        _startTick = 0;
        _durationTicks = 240;
        _velocity = 100;
    }
    return self;
}

+ (instancetype)noteWithPitch:(NSInteger)pitch
                    startTick:(uint64_t)startTick
                durationTicks:(uint64_t)durationTicks
                     velocity:(NSInteger)velocity {
    NoteEvent *note = [[self alloc] init];
    note.pitch = pitch;
    note.startTick = startTick;
    note.durationTicks = durationTicks;
    note.velocity = velocity;
    return note;
}

- (id)copyWithZone:(NSZone *)zone {
    NoteEvent *copy = [[NoteEvent allocWithZone:zone] init];
    copy.identifier = self.identifier;
    copy.pitch = self.pitch;
    copy.startTick = self.startTick;
    copy.durationTicks = self.durationTicks;
    copy.velocity = self.velocity;
    return copy;
}

- (NSDictionary *)dictionaryRepresentation {
    return @{
        @"id": self.identifier ?: [[NSUUID UUID] UUIDString],
        @"pitch": @(self.pitch),
        @"startTick": @(self.startTick),
        @"durationTicks": @(self.durationTicks),
        @"velocity": @(self.velocity)
    };
}

+ (instancetype)noteFromDictionary:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
    NoteEvent *note = [[self alloc] init];
    NSString *identifier = dictionary[@"id"];
    if ([identifier isKindOfClass:[NSString class]]) note.identifier = identifier;
    note.pitch = [dictionary[@"pitch"] integerValue];
    note.startTick = [dictionary[@"startTick"] unsignedLongLongValue];
    note.durationTicks = [dictionary[@"durationTicks"] unsignedLongLongValue];
    note.velocity = [dictionary[@"velocity"] integerValue];
    if (note.durationTicks == 0) note.durationTicks = 120;
    if (note.velocity <= 0) note.velocity = 100;
    return note;
}

@end
