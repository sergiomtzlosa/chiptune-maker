#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, OpenCodeErrorCode) {
    OpenCodeErrorGeneric = 1,
    OpenCodeErrorRateLimit = 2,
    OpenCodeErrorAuthentication = 3,
    OpenCodeErrorProvider = 4,
};

@interface OpenCodeModel : NSObject

@property (nonatomic, copy) NSString *providerID;
/// The model identifier used by the upstream provider (for example
/// "zai-org/GLM-5.3-Flash").
@property (nonatomic, copy) NSString *modelID;
/// The OpenCode model identifier used in Model.Ref requests. This differs
/// from modelID for custom providers.
@property (nonatomic, copy) NSString *requestID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) BOOL isFree;
@property (nonatomic, assign) BOOL isLocal;

- (NSString *)displayName;
- (NSString *)qualifiedName;
- (NSString *)menuTitle;

@end

@interface OpenCodeClient : NSObject

@property (nonatomic, copy) NSString *baseURLString;
@property (nonatomic, copy, nullable) NSString *password;

- (instancetype)initWithBaseURLString:(NSString *)baseURLString password:(nullable NSString *)password;

+ (nullable NSArray<OpenCodeModel *> *)modelsFromResponseObject:(id)object
                                                          error:(NSError **)error;

- (void)checkConnectionWithCompletion:(void (^)(NSString *version, NSError *error))completion;
- (void)listModelsWithCompletion:(void (^)(NSArray<OpenCodeModel *> *models, NSError *error))completion;
- (void)generateTextWithPrompt:(NSString *)prompt
                         model:(OpenCodeModel *)model
                    completion:(void (^)(NSString *text, NSError *error))completion;

@end

NS_ASSUME_NONNULL_END
