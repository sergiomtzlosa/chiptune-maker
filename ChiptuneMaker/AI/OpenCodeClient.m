#import "OpenCodeClient.h"

static NSString *ProviderDisplayName(NSString *providerID) {
    if ([providerID isEqualToString:@"anthropic"]) return @"Anthropic";
    if ([providerID isEqualToString:@"opencode"]) return @"OpenCode";
    if ([providerID isEqualToString:@"ollama"]) return @"Ollama";
    if ([providerID isEqualToString:@"llamacpp"]) return @"llama.cpp";
    if ([providerID isEqualToString:@"charrasmia"]) return @"Charrasmia";
    if (providerID.length == 0) return @"Unknown provider";
    return [providerID stringByReplacingOccurrencesOfString:@"-" withString:@" "];
}

static BOOL ProviderIsLocal(NSString *providerID) {
    NSString *lower = providerID.lowercaseString;
    return [lower isEqualToString:@"ollama"] ||
           [lower isEqualToString:@"llamacpp"] ||
           [lower isEqualToString:@"llama.cpp"] ||
           [lower isEqualToString:@"lmstudio"] ||
           [lower isEqualToString:@"local"];
}

static BOOL DictionaryHasPositiveCost(NSDictionary *dictionary) {
    for (NSString *key in @[@"input", @"output"]) {
        id value = dictionary[key];
        if ([value isKindOfClass:[NSNumber class]] && [value doubleValue] > 0.0) return YES;
    }
    id cache = dictionary[@"cache"];
    if ([cache isKindOfClass:[NSDictionary class]]) {
        for (NSString *key in @[@"read", @"write"]) {
            id value = cache[key];
            if ([value isKindOfClass:[NSNumber class]] && [value doubleValue] > 0.0) return YES;
        }
    }
    return NO;
}

static BOOL ModelIsFree(NSDictionary *entry) {
    NSString *name = entry[@"name"];
    NSString *requestID = entry[@"id"];
    NSString *modelID = entry[@"modelID"];
    for (NSString *value in @[name ?: @"", requestID ?: @"", modelID ?: @""]) {
        if ([value rangeOfString:@"free" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return YES;
        }
    }
    id cost = entry[@"cost"];
    if (![cost isKindOfClass:[NSArray class]] || [cost count] == 0) return NO;
    for (id tier in (NSArray *)cost) {
        if ([tier isKindOfClass:[NSDictionary class]] && DictionaryHasPositiveCost(tier)) {
            return NO;
        }
    }
    return YES;
}

@implementation OpenCodeModel

- (NSString *)displayName {
    if (self.name.length > 0) return self.name;
    if (self.requestID.length > 0) return self.requestID;
    return self.modelID.length > 0 ? self.modelID : @"Unknown Model";
}

- (NSString *)qualifiedName {
    NSString *identifier = self.requestID.length > 0 ? self.requestID : self.modelID;
    return [NSString stringWithFormat:@"%@/%@", self.providerID, identifier];
}

- (NSString *)menuTitle {
    NSMutableString *title = [NSMutableString stringWithFormat:@"%@ — %@", self.displayName, ProviderDisplayName(self.providerID)];
    if (self.isLocal) {
        [title appendString:@" (local)"];
    } else if (self.isFree) {
        [title appendString:@" (free)"];
    }
    return title;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%@ (%@, request %@, upstream %@)",
            self.displayName, self.providerID, self.requestID, self.modelID];
}

@end

@implementation OpenCodeClient

- (instancetype)initWithBaseURLString:(NSString *)baseURLString password:(NSString *)password {
    self = [super init];
    if (self) {
        NSString *trimmed = [baseURLString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        while (trimmed.length > 1 && [trimmed hasSuffix:@"/"]) {
            trimmed = [trimmed substringToIndex:trimmed.length - 1];
        }
        _baseURLString = trimmed.length > 0 ? [trimmed copy] : @"http://127.0.0.1:4096";
        _password = [password copy];
    }
    return self;
}

- (NSError *)errorWithMessage:(NSString *)message code:(NSInteger)code {
    return [NSError errorWithDomain:@"ChiptuneMaker.OpenCode"
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"OpenCode request failed."}];
}

- (NSError *)errorWithMessage:(NSString *)message {
    return [self errorWithMessage:message code:OpenCodeErrorGeneric];
}

- (NSURL *)URLForPath:(NSString *)path query:(nullable NSString *)query {
    NSString *string = [self.baseURLString stringByAppendingString:path];
    if (query.length > 0) {
        string = [string stringByAppendingFormat:@"?%@", query];
    }
    return [NSURL URLWithString:string];
}

- (NSURLRequest *)requestForURL:(NSURL *)url method:(NSString *)method body:(nullable NSData *)body timeout:(NSTimeInterval)timeout {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:timeout];
    request.HTTPMethod = method;
    if (body) {
        request.HTTPBody = body;
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    }
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    if (self.password.length > 0) {
        NSString *credentials = [NSString stringWithFormat:@"opencode:%@", self.password];
        NSString *encoded = [[credentials dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
        [request setValue:[NSString stringWithFormat:@"Basic %@", encoded] forHTTPHeaderField:@"Authorization"];
    }
    return request;
}

- (NSString *)retryTextForMilliseconds:(NSInteger)milliseconds {
    if (milliseconds <= 0) return @"";
    double seconds = (double)milliseconds / 1000.0;
    if (seconds < 60.0) {
        return [NSString stringWithFormat:@" Try again in about %.0f seconds.", MAX(1.0, ceil(seconds))];
    }
    if (seconds < 3600.0) {
        return [NSString stringWithFormat:@" Try again in about %.0f minutes.", ceil(seconds / 60.0)];
    }
    return [NSString stringWithFormat:@" Try again in about %.0f hours.", ceil(seconds / 3600.0)];
}

- (nullable NSError *)errorForHTTPStatus:(NSInteger)status object:(id)object data:(NSData *)data {
    NSString *providerID = nil;
    NSString *reason = nil;
    NSString *message = nil;
    NSString *tag = nil;
    NSInteger retryAfterMs = 0;

    if ([object isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dictionary = object;
        tag = [dictionary[@"_tag"] isKindOfClass:[NSString class]] ? dictionary[@"_tag"] : nil;
        message = [dictionary[@"message"] isKindOfClass:[NSString class]] ? dictionary[@"message"] : nil;
        providerID = [dictionary[@"providerID"] isKindOfClass:[NSString class]] ? dictionary[@"providerID"] : nil;
        reason = [dictionary[@"reason"] isKindOfClass:[NSString class]] ? dictionary[@"reason"] : nil;
        id retry = dictionary[@"retryAfterMs"];
        if ([retry isKindOfClass:[NSNumber class]]) retryAfterMs = [retry integerValue];
    }

    if ([tag isEqualToString:@"ProviderRequestError"] || reason.length > 0) {
        NSString *provider = ProviderDisplayName(providerID ?: @"");
        if ([reason isEqualToString:@"rate_limit"] || status == 429) {
            NSString *base = message.length > 0 ? message : @"The model provider is rate-limiting requests.";
            return [self errorWithMessage:[NSString stringWithFormat:@"%@%@ Choose a local or paid model, or wait and try again.",
                                           base, [self retryTextForMilliseconds:retryAfterMs]]
                                     code:OpenCodeErrorRateLimit];
        }
        if ([reason isEqualToString:@"authentication"] || status == 401 || status == 403) {
            NSString *base = message.length > 0 ? message : @"The provider rejected its credentials.";
            return [self errorWithMessage:[NSString stringWithFormat:@"%@ (%@) Check the provider login or API key configured in OpenCode.",
                                           base, provider]
                                     code:OpenCodeErrorAuthentication];
        }
        if ([reason isEqualToString:@"content_filter"]) {
            return [self errorWithMessage:[NSString stringWithFormat:@"%@ (%@) Rephrase the musical brief and try again.",
                                           message.length > 0 ? message : @"The provider blocked the request.", provider]
                                     code:OpenCodeErrorProvider];
        }
        if ([reason isEqualToString:@"overloaded"]) {
            return [self errorWithMessage:[NSString stringWithFormat:@"%@ (%@) The provider is busy. Try again in a moment.",
                                           message.length > 0 ? message : @"The provider is overloaded.", provider]
                                     code:OpenCodeErrorProvider];
        }
        if ([reason isEqualToString:@"invalid_request"]) {
            return [self errorWithMessage:[NSString stringWithFormat:@"%@ (%@) The selected model rejected the request.",
                                           message.length > 0 ? message : @"The provider rejected the request.", provider]
                                     code:OpenCodeErrorProvider];
        }
        if (message.length > 0) {
            return [self errorWithMessage:[NSString stringWithFormat:@"%@ (%@)", message, provider]
                                     code:OpenCodeErrorProvider];
        }
    }

    if (status == 401 || status == 403) {
        return [self errorWithMessage:@"OpenCode requires authentication. Enter the server password printed by “opencode serve”."
                                 code:OpenCodeErrorAuthentication];
    }
    if (status == 429) {
        return [self errorWithMessage:@"OpenCode is rate-limiting requests. Wait a moment, or choose a local or paid model."
                                 code:OpenCodeErrorRateLimit];
    }
    if ([tag isEqualToString:@"ModelNotFoundError"]) {
        return [self errorWithMessage:@"That model is no longer available in OpenCode. Click Refresh and choose another model."
                                 code:OpenCodeErrorProvider];
    }
    if ([tag isEqualToString:@"UnsupportedModelError"]) {
        return [self errorWithMessage:@"That model does not support text generation. Choose another chat model."
                                 code:OpenCodeErrorProvider];
    }
    if ([tag isEqualToString:@"ServiceUnavailableError"]) {
        return [self errorWithMessage:@"OpenCode is temporarily unavailable. Try again in a moment."
                                 code:OpenCodeErrorProvider];
    }

    if (message.length > 0) {
        return [self errorWithMessage:message];
    }
    if (tag.length > 0) {
        return [self errorWithMessage:tag];
    }
    if (data.length > 0) {
        NSString *raw = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (raw.length > 0) {
            return [self errorWithMessage:[NSString stringWithFormat:@"OpenCode returned HTTP %ld: %@", (long)status, raw]];
        }
    }
    return [self errorWithMessage:[NSString stringWithFormat:@"OpenCode returned HTTP %ld.", (long)status]];
}

- (void)performRequest:(NSURLRequest *)request completion:(void (^)(id _Nullable object, NSError * _Nullable error))completion {
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    configuration.timeoutIntervalForRequest = request.timeoutInterval;
    configuration.timeoutIntervalForResource = MAX(request.timeoutInterval, 180.0);
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        [session finishTasksAndInvalidate];
        if (error) {
            NSString *message = error.localizedDescription ?: @"Could not reach OpenCode.";
            if (error.code == NSURLErrorCannotConnectToHost || error.code == NSURLErrorCannotFindHost) {
                message = [NSString stringWithFormat:@"Could not connect to OpenCode at %@. Start it with “opencode serve --port 4096”.", self.baseURLString];
            } else if (error.code == NSURLErrorTimedOut) {
                message = @"OpenCode did not respond in time. The model may be busy; try again or choose a faster model.";
            }
            completion(nil, [self errorWithMessage:message]);
            return;
        }

        NSHTTPURLResponse *http = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
        id object = nil;
        if (data.length > 0) {
            object = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        }

        if (http.statusCode < 200 || http.statusCode >= 300) {
            NSError *requestError = [self errorForHTTPStatus:http.statusCode object:object data:data];
            completion(nil, requestError ?: [self errorWithMessage:[NSString stringWithFormat:@"OpenCode returned HTTP %ld.", (long)http.statusCode]]);
            return;
        }

        completion(object, nil);
    }];
    [task resume];
}

- (void)checkConnectionWithCompletion:(void (^)(NSString *version, NSError *error))completion {
    NSURL *url = [self URLForPath:@"/api/info" query:nil];
    NSURLRequest *request = [self requestForURL:url method:@"GET" body:nil timeout:6.0];
    [self performRequest:request completion:^(id object, NSError *error) {
        if (error) {
            completion(@"", error);
            return;
        }
        if (![object isKindOfClass:[NSDictionary class]]) {
            completion(@"", [self errorWithMessage:@"OpenCode returned an unexpected response for /api/info."]);
            return;
        }
        NSString *version = object[@"version"];
        completion([version isKindOfClass:[NSString class]] ? version : @"unknown", nil);
    }];
}

+ (nullable NSArray<OpenCodeModel *> *)modelsFromResponseObject:(id)object error:(NSError **)error {
    NSArray *entries = nil;
    if ([object isKindOfClass:[NSDictionary class]]) {
        id data = object[@"data"];
        if ([data isKindOfClass:[NSArray class]]) entries = data;
    } else if ([object isKindOfClass:[NSArray class]]) {
        entries = object;
    }
    if (!entries) {
        if (error) {
            *error = [NSError errorWithDomain:@"ChiptuneMaker.OpenCode"
                                         code:OpenCodeErrorGeneric
                                     userInfo:@{NSLocalizedDescriptionKey: @"OpenCode returned an unexpected model list."}];
        }
        return nil;
    }

    NSMutableArray<OpenCodeModel *> *models = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (id entry in entries) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *dictionary = entry;
        NSString *providerID = dictionary[@"providerID"];
        if (![providerID isKindOfClass:[NSString class]] || providerID.length == 0) continue;

        NSString *requestID = dictionary[@"id"];
        if (![requestID isKindOfClass:[NSString class]] || requestID.length == 0) {
            requestID = dictionary[@"modelID"];
        }
        if (![requestID isKindOfClass:[NSString class]] || requestID.length == 0) continue;

        NSString *modelID = dictionary[@"modelID"];
        if (![modelID isKindOfClass:[NSString class]] || modelID.length == 0) {
            modelID = requestID;
        }

        NSString *key = [NSString stringWithFormat:@"%@/%@", providerID, requestID];
        if ([seen containsObject:key]) continue;
        [seen addObject:key];

        OpenCodeModel *model = [[OpenCodeModel alloc] init];
        model.providerID = providerID;
        model.requestID = requestID;
        model.modelID = modelID;
        NSString *name = dictionary[@"name"];
        model.name = [name isKindOfClass:[NSString class]] ? name : modelID;
        model.isLocal = ProviderIsLocal(providerID);
        model.isFree = !model.isLocal && ModelIsFree(dictionary);
        [models addObject:model];
    }

    [models sortUsingComparator:^NSComparisonResult(OpenCodeModel *a, OpenCodeModel *b) {
        NSInteger rankA = a.isLocal ? 0 : (a.isFree ? 2 : 1);
        NSInteger rankB = b.isLocal ? 0 : (b.isFree ? 2 : 1);
        if (rankA != rankB) return rankA < rankB ? NSOrderedAscending : NSOrderedDescending;
        return [a.displayName localizedCaseInsensitiveCompare:b.displayName];
    }];
    return models;
}

- (void)listModelsWithCompletion:(void (^)(NSArray<OpenCodeModel *> *models, NSError *error))completion {
    NSURL *url = [self URLForPath:@"/api/model" query:@"types=chat"];
    NSURLRequest *request = [self requestForURL:url method:@"GET" body:nil timeout:12.0];
    [self performRequest:request completion:^(id object, NSError *error) {
        if (error) {
            completion(@[], error);
            return;
        }
        NSError *parseError = nil;
        NSArray<OpenCodeModel *> *models = [[self class] modelsFromResponseObject:object error:&parseError];
        if (!models) {
            completion(@[], parseError ?: [self errorWithMessage:@"OpenCode returned an unexpected model list."]);
            return;
        }
        completion(models, nil);
    }];
}

- (void)generateTextWithPrompt:(NSString *)prompt
                         model:(OpenCodeModel *)model
                    completion:(void (^)(NSString *text, NSError *error))completion {
    if (prompt.length == 0) {
        completion(@"", [self errorWithMessage:@"The musical brief is empty."]);
        return;
    }
    if (!model) {
        completion(@"", [self errorWithMessage:@"Choose an OpenCode model first."]);
        return;
    }
    NSString *requestID = model.requestID.length > 0 ? model.requestID : model.modelID;
    if (requestID.length == 0) {
        completion(@"", [self errorWithMessage:@"The selected model has no identifier. Click Refresh and choose another model."]);
        return;
    }
    NSDictionary *body = @{
        @"prompt": prompt,
        @"model": @{
            @"providerID": model.providerID,
            @"id": requestID
        }
    };
    NSError *jsonError = nil;
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];
    if (!bodyData) {
        completion(@"", jsonError ?: [self errorWithMessage:@"Could not encode the generation request."]);
        return;
    }
    NSURL *url = [self URLForPath:@"/api/experimental/generate/text" query:nil];
    NSURLRequest *request = [self requestForURL:url method:@"POST" body:bodyData timeout:120.0];
    [self performRequest:request completion:^(id object, NSError *error) {
        if (error) {
            completion(@"", error);
            return;
        }
        NSString *text = nil;
        if ([object isKindOfClass:[NSDictionary class]]) {
            id data = object[@"data"];
            if ([data isKindOfClass:[NSDictionary class]]) {
                id value = data[@"text"];
                if ([value isKindOfClass:[NSString class]]) text = value;
            }
            if (!text) {
                id value = object[@"text"];
                if ([value isKindOfClass:[NSString class]]) text = value;
            }
        } else if ([object isKindOfClass:[NSString class]]) {
            text = object;
        }
        if (!text) {
            completion(@"", [self errorWithMessage:@"OpenCode returned no text for the generation request."]);
            return;
        }
        completion(text, nil);
    }];
}

@end
