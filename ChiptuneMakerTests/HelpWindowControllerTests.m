#import <XCTest/XCTest.h>
#import "HelpWindowController.h"

@interface HelpWindowControllerTests : XCTestCase
@end

@implementation HelpWindowControllerTests

- (void)testHelpWindowHasAllTopics {
    HelpWindowController *controller = [[HelpWindowController alloc] init];
    XCTAssertGreaterThanOrEqual(controller.topicCount, 10);
    XCTAssertEqualObjects(controller.selectedTopicTitle, @"Welcome");

    [controller showTopicWithIdentifier:ChiptuneHelpTopicAI];
    XCTAssertEqualObjects(controller.selectedTopicTitle, @"AI Composition");

    [controller showTopicWithIdentifier:ChiptuneHelpTopicShortcuts];
    XCTAssertEqualObjects(controller.selectedTopicTitle, @"Keyboard Shortcuts");

    [controller showTopicWithIdentifier:ChiptuneHelpTopicImporting];
    XCTAssertEqualObjects(controller.selectedTopicTitle, @"Importing Audio");

    [controller.window close];
}

@end
