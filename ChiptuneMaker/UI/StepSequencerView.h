#import <Cocoa/Cocoa.h>

@class SongDocument;

@interface StepSequencerView : NSView

@property (nonatomic, weak) SongDocument *document;
@property (nonatomic, assign) NSInteger currentTrackIndex;
@property (nonatomic, assign) NSInteger selectedPitch;
@property (nonatomic, assign) uint64_t playheadTick;
@property (nonatomic, assign) BOOL followPlayhead;

- (void)reloadData;

@end
