#import "SongSection.h"

@implementation SongSection

- (instancetype)init {
    self = [super init];
    if (self) {
        _identifier = [[NSUUID UUID] UUIDString];
        _name = @"Section";
        _startBar = 0;
        _lengthBars = 4;
    }
    return self;
}

+ (instancetype)sectionWithName:(NSString *)name startBar:(NSInteger)startBar lengthBars:(NSInteger)lengthBars {
    SongSection *section = [[self alloc] init];
    section.name = name;
    section.startBar = startBar;
    section.lengthBars = lengthBars;
    return section;
}

- (id)copyWithZone:(NSZone *)zone {
    SongSection *copy = [[SongSection allocWithZone:zone] init];
    copy.identifier = self.identifier;
    copy.name = self.name;
    copy.startBar = self.startBar;
    copy.lengthBars = self.lengthBars;
    return copy;
}

- (NSDictionary *)dictionaryRepresentation {
    return @{
        @"id": self.identifier ?: [[NSUUID UUID] UUIDString],
        @"name": self.name ?: @"Section",
        @"startBar": @(self.startBar),
        @"lengthBars": @(self.lengthBars)
    };
}

+ (instancetype)sectionFromDictionary:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
    SongSection *section = [[self alloc] init];
    NSString *identifier = dictionary[@"id"];
    if ([identifier isKindOfClass:[NSString class]]) section.identifier = identifier;
    NSString *name = dictionary[@"name"];
    if ([name isKindOfClass:[NSString class]]) section.name = name;
    section.startBar = [dictionary[@"startBar"] integerValue];
    section.lengthBars = [dictionary[@"lengthBars"] integerValue];
    if (section.lengthBars <= 0) section.lengthBars = 4;
    return section;
}

@end
