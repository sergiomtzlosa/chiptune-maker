#import "SeededRandom.h"

@implementation SeededRandom

- (instancetype)initWithSeed:(uint64_t)seed {
    self = [super init];
    if (self) {
        _seed = seed;
    }
    return self;
}

- (uint64_t)nextUInt64 {
    _seed += 0x9E3779B97F4A7C15ULL;
    uint64_t z = _seed;
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
    return z ^ (z >> 31);
}

- (double)nextDouble {
    return (double)(self.nextUInt64 >> 11) / (double)(1ULL << 53);
}

- (NSInteger)nextIntFrom:(NSInteger)minimum to:(NSInteger)maximum {
    if (maximum <= minimum) return minimum;
    uint64_t span = (uint64_t)(maximum - minimum + 1);
    return minimum + (NSInteger)(self.nextUInt64 % span);
}

- (BOOL)chance:(double)probability {
    return self.nextDouble < probability;
}

@end
