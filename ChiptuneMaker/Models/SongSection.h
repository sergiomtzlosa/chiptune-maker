#import <Foundation/Foundation.h>

@interface SongSection : NSObject <NSCopying>

@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) NSInteger startBar;
@property (nonatomic, assign) NSInteger lengthBars;

+ (instancetype)sectionWithName:(NSString *)name startBar:(NSInteger)startBar lengthBars:(NSInteger)lengthBars;
- (NSDictionary *)dictionaryRepresentation;
+ (instancetype)sectionFromDictionary:(NSDictionary *)dictionary;

@end
