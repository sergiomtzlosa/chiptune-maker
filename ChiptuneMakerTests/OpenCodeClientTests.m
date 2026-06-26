#import <XCTest/XCTest.h>
#import "OpenCodeClient.h"

@interface OpenCodeClientTests : XCTestCase
@end

@implementation OpenCodeClientTests

- (void)testModelParsingUsesOpenCodeRequestID {
    NSDictionary *response = @{@"data": @[
        @{@"id": @"glm-5.3-flash",
          @"modelID": @"zai-org/GLM-5.3-Flash",
          @"providerID": @"charrasmia",
          @"name": @"GLM-5.3-Flash",
          @"cost": @[]},
        @{@"id": @"big-pickle",
          @"modelID": @"big-pickle",
          @"providerID": @"opencode",
          @"name": @"Big Pickle",
          @"cost": @[@{@"input": @0, @"output": @0, @"cache": @{@"read": @0, @"write": @0}}]},
        @{@"id": @"llama3.2:3b",
          @"modelID": @"llama3.2:3b",
          @"providerID": @"ollama",
          @"name": @"llama3.2:3b",
          @"cost": @[]}
    ]};
    NSError *error = nil;
    NSArray<OpenCodeModel *> *models = [OpenCodeClient modelsFromResponseObject:response error:&error];
    XCTAssertNotNil(models, @"%@", error);
    XCTAssertEqual(models.count, 3);

    // Local models sort first so a fresh install does not default to a
    // rate-limited cloud model.
    XCTAssertEqualObjects(models[0].providerID, @"ollama");
    XCTAssertTrue(models[0].isLocal);
    XCTAssertTrue([models[0].menuTitle containsString:@"(local)"]);

    OpenCodeModel *glm = nil;
    OpenCodeModel *free = nil;
    for (OpenCodeModel *model in models) {
        if ([model.providerID isEqualToString:@"charrasmia"]) glm = model;
        if ([model.providerID isEqualToString:@"opencode"]) free = model;
    }
    XCTAssertNotNil(glm);
    XCTAssertEqualObjects(glm.requestID, @"glm-5.3-flash");
    XCTAssertEqualObjects(glm.modelID, @"zai-org/GLM-5.3-Flash");
    XCTAssertEqualObjects(glm.qualifiedName, @"charrasmia/glm-5.3-flash");
    XCTAssertEqualObjects(glm.menuTitle, @"GLM-5.3-Flash — Charrasmia");
    XCTAssertFalse(glm.isFree);

    XCTAssertNotNil(free);
    XCTAssertTrue(free.isFree);
    XCTAssertTrue([free.menuTitle containsString:@"(free)"]);
    XCTAssertEqualObjects(free.qualifiedName, @"opencode/big-pickle");
}

- (void)testModelParsingRejectsUnexpectedResponse {
    NSError *error = nil;
    NSArray<OpenCodeModel *> *models = [OpenCodeClient modelsFromResponseObject:@{} error:&error];
    XCTAssertNil(models);
    XCTAssertNotNil(error);
}

@end
