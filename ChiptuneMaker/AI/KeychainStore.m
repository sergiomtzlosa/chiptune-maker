#import "KeychainStore.h"
#import <Security/Security.h>

@implementation KeychainStore

+ (NSMutableDictionary *)baseQueryForKey:(NSString *)key service:(NSString *)service {
    NSMutableDictionary *query = [NSMutableDictionary dictionary];
    query[(__bridge id)kSecClass] = (__bridge id)kSecClassGenericPassword;
    query[(__bridge id)kSecAttrService] = service;
    query[(__bridge id)kSecAttrAccount] = key;
    return query;
}

+ (NSString *)stringForKey:(NSString *)key service:(NSString *)service {
    NSMutableDictionary *query = [self baseQueryForKey:key service:service];
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess || result == NULL) return nil;
    NSData *data = (__bridge_transfer NSData *)result;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

+ (BOOL)setString:(NSString *)string forKey:(NSString *)key service:(NSString *)service {
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return NO;
    NSMutableDictionary *query = [self baseQueryForKey:key service:service];
    NSDictionary *attributes = @{ (__bridge id)kSecValueData: data };
    OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)attributes);
    if (status == errSecSuccess) return YES;
    if (status != errSecItemNotFound) return NO;
    query[(__bridge id)kSecValueData] = data;
    return SecItemAdd((__bridge CFDictionaryRef)query, NULL) == errSecSuccess;
}

+ (void)removeStringForKey:(NSString *)key service:(NSString *)service {
    NSMutableDictionary *query = [self baseQueryForKey:key service:service];
    SecItemDelete((__bridge CFDictionaryRef)query);
}

@end
