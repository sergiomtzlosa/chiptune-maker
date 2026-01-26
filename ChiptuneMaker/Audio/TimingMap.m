#import "TimingMap.h"

@implementation TimingMap

+ (uint64_t)playbackTickForTick:(uint64_t)tick ppq:(uint64_t)ppq swing:(double)swing {
    if (swing <= 0.0001 || ppq == 0) return tick;
    double clamped = MIN(1.0, MAX(0.0, swing));
    uint64_t eighth = ppq / 2;
    if (eighth == 0) return tick;
    uint64_t pairIndex = tick / eighth;
    if (pairIndex % 2 == 1) {
        uint64_t offset = (uint64_t)llround(clamped * (double)ppq / 4.0);
        return tick + offset;
    }
    return tick;
}

@end
