#import "StepSequencerView.h"
#import "SongDocument.h"
#import "Song.h"
#import "Track.h"
#import "NoteEvent.h"
#import "SongTypes.h"
#import "ChiptuneTheme.h"
#import "TimelineScrollSupport.h"

static const CGFloat kLabelWidth = 154.0;
static const CGFloat kHeaderHeight = 26.0;
static const CGFloat kCellWidth = 30.0;
static const CGFloat kRowHeight = 32.0;

@interface StepSequencerView ()
@property (nonatomic, strong) NSMutableSet<NSString *> *paintedSteps;
@property (nonatomic, assign) uint64_t stepTicks;
@property (nonatomic, assign) NSInteger stepsPerBar;
@property (nonatomic, assign) NSInteger totalSteps;
@end

@implementation StepSequencerView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _paintedSteps = [NSMutableSet set];
        _currentTrackIndex = 0;
        _selectedPitch = 72;
        self.wantsLayer = YES;
    }
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)reloadData {
    Song *song = self.document.song;
    if (!song) return;
    self.stepTicks = MAX(1ULL, song.ppq / 4);
    self.stepsPerBar = MAX(1, (NSInteger)(song.ticksPerBar / self.stepTicks));
    self.totalSteps = self.stepsPerBar * MAX(1, song.lengthBars);
    CGFloat width = kLabelWidth + (CGFloat)self.totalSteps * kCellWidth;
    CGFloat height = kHeaderHeight + (CGFloat)song.tracks.count * kRowHeight;
    [self setFrameSize:NSMakeSize(MAX(width, 400), MAX(height, 120))];
    [self setNeedsDisplay:YES];
}

- (void)setCurrentTrackIndex:(NSInteger)currentTrackIndex {
    _currentTrackIndex = currentTrackIndex;
    [self setNeedsDisplay:YES];
}

- (void)setSelectedPitch:(NSInteger)selectedPitch {
    _selectedPitch = MAX(0, MIN(127, selectedPitch));
}

- (void)setPlayheadTick:(uint64_t)playheadTick {
    if (_playheadTick == playheadTick) return;
    _playheadTick = playheadTick;
    [self setNeedsDisplay:YES];
    if (self.followPlayhead) {
        CGFloat x = kLabelWidth + (CGFloat)playheadTick / (CGFloat)MAX(1ULL, self.stepTicks) * kCellWidth;
        [self scrollRectToVisible:NSMakeRect(x - 120, 0, 240, self.bounds.size.height)];
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    [[NSColor controlBackgroundColor] setFill];
    NSRectFill(dirtyRect);

    Song *song = self.document.song;
    if (!song) return;

    NSDictionary *headerAttributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:10 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: [NSColor secondaryLabelColor]
    };
    NSDictionary *trackAttributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:11 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: [NSColor labelColor]
    };
    NSDictionary *instrumentAttributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:9],
        NSForegroundColorAttributeName: [NSColor tertiaryLabelColor]
    };

    // Header bar numbers.
    for (NSInteger bar = 0; bar < song.lengthBars; bar++) {
        CGFloat x = kLabelWidth + (CGFloat)(bar * self.stepsPerBar) * kCellWidth;
        NSString *label = [NSString stringWithFormat:@"Bar %ld", (long)(bar + 1)];
        [label drawAtPoint:NSMakePoint(x + 6, 6) withAttributes:headerAttributes];
    }

    // Track rows.
    for (NSInteger row = 0; row < (NSInteger)song.tracks.count; row++) {
        Track *track = song.tracks[(NSUInteger)row];
        CGFloat y = kHeaderHeight + (CGFloat)row * kRowHeight;
        if (row == self.currentTrackIndex) {
            [[ChiptuneTrackColor(row) colorWithAlphaComponent:0.10] setFill];
            NSRectFill(NSMakeRect(0, y, self.bounds.size.width, kRowHeight));
        }
        [[NSColor.separatorColor colorWithAlphaComponent:0.25] setFill];
        NSRectFill(NSMakeRect(0, y, self.bounds.size.width, 1));

        [track.name drawAtPoint:NSMakePoint(8, y + 6) withAttributes:trackAttributes];
        [ChipInstrumentDisplayName(track.instrument) drawAtPoint:NSMakePoint(8, y + 19) withAttributes:instrumentAttributes];

        for (NSInteger step = 0; step < self.totalSteps; step++) {
            CGFloat x = kLabelWidth + (CGFloat)step * kCellWidth;
            BOOL isBeat = (step % 4) == 0;
            BOOL isBar = (step % self.stepsPerBar) == 0;
            if (isBar) {
                [[NSColor.separatorColor colorWithAlphaComponent:0.7] setFill];
                NSRectFill(NSMakeRect(x, y, 1, kRowHeight));
            } else if (isBeat) {
                [[ChiptuneGridColor() colorWithAlphaComponent:0.7] setFill];
                NSRectFill(NSMakeRect(x, y, 1, kRowHeight));
            } else {
                [ChiptuneGridColor() setFill];
                NSRectFill(NSMakeRect(x, y + 6, 1, kRowHeight - 12));
            }
        }
    }

    // Notes.
    for (NSInteger row = 0; row < (NSInteger)song.tracks.count; row++) {
        Track *track = song.tracks[(NSUInteger)row];
        CGFloat y = kHeaderHeight + (CGFloat)row * kRowHeight;
        for (NoteEvent *note in track.notes) {
            if (note.startTick >= song.totalTicks) continue;
            CGFloat x = kLabelWidth + (CGFloat)note.startTick / (CGFloat)MAX(1ULL, self.stepTicks) * kCellWidth;
            CGFloat width = MAX(5.0, (CGFloat)note.durationTicks / (CGFloat)MAX(1ULL, self.stepTicks) * kCellWidth - 3.0);
            NSRect rect = NSMakeRect(x + 2, y + 5, width, kRowHeight - 10);
            NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:3 yRadius:3];
            [ChiptuneNoteColor(row) setFill];
            [path fill];
            if (width > 28) {
                NSDictionary *noteAttributes = @{
                    NSFontAttributeName: [NSFont systemFontOfSize:9 weight:NSFontWeightSemibold],
                    NSForegroundColorAttributeName: [NSColor whiteColor]
                };
                NSString *name = NoteNameForPitch(note.pitch);
                [name drawAtPoint:NSMakePoint(rect.origin.x + 4, rect.origin.y + 4) withAttributes:noteAttributes];
            }
        }
    }

    // Playhead.
    CGFloat playheadX = kLabelWidth + (CGFloat)self.playheadTick / (CGFloat)MAX(1ULL, self.stepTicks) * kCellWidth;
    if (playheadX >= kLabelWidth && playheadX <= self.bounds.size.width) {
        [[ChiptuneAccentColor() colorWithAlphaComponent:0.9] setFill];
        NSRectFill(NSMakeRect(playheadX, 0, 1.5, self.bounds.size.height));
    }
}

- (void)scrollWheel:(NSEvent *)event {
    if (ChiptuneHandleTimelineScrollWheel(self, event, YES)) return;
    [super scrollWheel:event];
}

- (void)autoScrollForDragPoint:(NSPoint)point {
    NSScrollView *scrollView = self.enclosingScrollView;
    NSClipView *clipView = scrollView.contentView;
    if (!scrollView || !clipView) return;
    NSRect visible = clipView.bounds;
    CGFloat margin = 28.0;
    CGFloat delta = 0.0;
    if (point.x > NSMaxX(visible) - margin) {
        delta = 32.0;
    } else if (point.x < NSMinX(visible) + margin) {
        delta = -32.0;
    }
    if (fabs(delta) < 0.01) return;
    CGFloat maxX = MAX(0.0, self.bounds.size.width - visible.size.width);
    CGFloat target = MAX(0.0, MIN(maxX, visible.origin.x + delta));
    if (fabs(target - visible.origin.x) > 0.01) {
        [clipView scrollToPoint:NSMakePoint(target, visible.origin.y)];
        [scrollView reflectScrolledClipView:clipView];
    }
}

- (void)mouseDown:(NSEvent *)event {
    [self.window makeFirstResponder:self];
    [self.paintedSteps removeAllObjects];
    [self toggleAtEvent:event];
}

- (void)mouseDragged:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    [self autoScrollForDragPoint:point];
    [self toggleAtEvent:event];
}

- (void)mouseUp:(NSEvent *)event {
    [self.paintedSteps removeAllObjects];
}

- (void)toggleAtEvent:(NSEvent *)event {
    Song *song = self.document.song;
    if (!song) return;
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (point.x < kLabelWidth || point.y < kHeaderHeight) return;
    NSInteger row = (NSInteger)((point.y - kHeaderHeight) / kRowHeight);
    NSInteger step = (NSInteger)((point.x - kLabelWidth) / kCellWidth);
    if (row < 0 || row >= (NSInteger)song.tracks.count) return;
    if (step < 0 || step >= self.totalSteps) return;
    NSString *key = [NSString stringWithFormat:@"%ld-%ld", (long)row, (long)step];
    if ([self.paintedSteps containsObject:key]) return;
    [self.paintedSteps addObject:key];

    uint64_t tick = (uint64_t)step * self.stepTicks;
    NSInteger trackIndex = row;
    NSInteger pitch = self.selectedPitch;
    [self.document performEditNamed:@"Toggle Step" block:^(Song *edited) {
        Track *track = edited.tracks[(NSUInteger)trackIndex];
        NoteEvent *existing = [track noteStartingAtTick:tick tolerance:1];
        if (existing) {
            [track.notes removeObject:existing];
        } else {
            [track.notes addObject:[NoteEvent noteWithPitch:pitch startTick:tick durationTicks:self.stepTicks velocity:100]];
        }
    }];
    [self reloadData];
}

@end
