#import <Foundation/Foundation.h>

@interface NoteEvent : NSObject <NSCopying>

@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, assign) NSInteger pitch;
@property (nonatomic, assign) uint64_t startTick;
@property (nonatomic, assign) uint64_t durationTicks;
@property (nonatomic, assign) NSInteger velocity;

+ (instancetype)noteWithPitch:(NSInteger)pitch
                    startTick:(uint64_t)startTick
                durationTicks:(uint64_t)durationTicks
                     velocity:(NSInteger)velocity;

- (NSDictionary *)dictionaryRepresentation;
+ (instancetype)noteFromDictionary:(NSDictionary *)dictionary;

@end
