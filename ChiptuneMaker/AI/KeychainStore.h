#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface KeychainStore : NSObject

+ (nullable NSString *)stringForKey:(NSString *)key service:(NSString *)service;
+ (BOOL)setString:(NSString *)string forKey:(NSString *)key service:(NSString *)service;
+ (void)removeStringForKey:(NSString *)key service:(NSString *)service;

@end

NS_ASSUME_NONNULL_END
