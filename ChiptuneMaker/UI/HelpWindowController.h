#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ChiptuneHelpTopicWelcome;
extern NSString *const ChiptuneHelpTopicInterface;
extern NSString *const ChiptuneHelpTopicSteps;
extern NSString *const ChiptuneHelpTopicPianoRoll;
extern NSString *const ChiptuneHelpTopicPlayback;
extern NSString *const ChiptuneHelpTopicGeneration;
extern NSString *const ChiptuneHelpTopicSaving;
extern NSString *const ChiptuneHelpTopicAI;
extern NSString *const ChiptuneHelpTopicShortcuts;
extern NSString *const ChiptuneHelpTopicTroubleshooting;

@interface HelpWindowController : NSWindowController

@property (nonatomic, readonly) NSInteger topicCount;
@property (nonatomic, readonly, copy, nullable) NSString *selectedTopicTitle;

- (instancetype)init;
- (void)showTopicWithIdentifier:(NSString *)identifier;

@end

NS_ASSUME_NONNULL_END
