#import <Foundation/Foundation.h>

@interface SeededRandom : NSObject

@property (nonatomic, assign, readonly) uint64_t seed;

- (instancetype)initWithSeed:(uint64_t)seed;

- (uint64_t)nextUInt64;
- (double)nextDouble;
- (NSInteger)nextIntFrom:(NSInteger)minimum to:(NSInteger)maximum;
- (BOOL)chance:(double)probability;

@end
