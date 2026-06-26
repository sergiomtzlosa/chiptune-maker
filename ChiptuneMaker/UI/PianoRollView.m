#import "PianoRollView.h"
#import "SongDocument.h"
#import "Song.h"
#import "Track.h"
#import "NoteEvent.h"
#import "SongTypes.h"
#import "ChiptuneTheme.h"
#import "TimelineScrollSupport.h"

static const CGFloat kKeyboardWidth = 66.0;
static const CGFloat kHeaderHeight = 24.0;
static const CGFloat kPianoRowHeight = 12.0;
static const CGFloat kPixelsPerTick = 0.35;
static const NSInteger kLowPitch = 36;
static const NSInteger kHighPitch = 96;

typedef NS_ENUM(NSInteger, PianoDragMode) {
    PianoDragModeNone = 0,
    PianoDragModeMove,
    PianoDragModeResize
};

@interface PianoRollView ()
@property (nonatomic, strong) NSString *selectedNoteIdentifier;
@property (nonatomic, assign) uint64_t stepTicks;
@property (nonatomic, assign) uint64_t totalTicks;
@property (nonatomic, strong) NoteEvent *dragNote;
@property (nonatomic, assign) PianoDragMode dragMode;
@property (nonatomic, assign) NSPoint dragStart;
@property (nonatomic, assign) uint64_t originalStartTick;
@property (nonatomic, assign) uint64_t originalDuration;
@property (nonatomic, assign) NSInteger originalPitch;
@property (nonatomic, assign) BOOL didDrag;
@property (nonatomic, strong) Song *undoSnapshot;
@end

@implementation PianoRollView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _currentTrackIndex = 0;
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
    self.totalTicks = song.totalTicks;
    CGFloat width = kKeyboardWidth + (CGFloat)self.totalTicks * kPixelsPerTick + 40;
    CGFloat height = kHeaderHeight + (CGFloat)(kHighPitch - kLowPitch + 1) * kPianoRowHeight + 16;
    [self setFrameSize:NSMakeSize(MAX(width, 500), MAX(height, 300))];
    [self setNeedsDisplay:YES];
}

- (void)setCurrentTrackIndex:(NSInteger)currentTrackIndex {
    _currentTrackIndex = currentTrackIndex;
    [self setNeedsDisplay:YES];
}

- (void)setPlayheadTick:(uint64_t)playheadTick {
    if (_playheadTick == playheadTick) return;
    _playheadTick = playheadTick;
    [self setNeedsDisplay:YES];
    if (self.followPlayhead) {
        CGFloat x = kKeyboardWidth + (CGFloat)playheadTick * kPixelsPerTick;
        [self scrollRectToVisible:NSMakeRect(x - 200, 0, 400, self.bounds.size.height)];
    }
}

- (Track *)currentTrack {
    Song *song = self.document.song;
    if (!song) return nil;
    return [song trackAtIndex:self.currentTrackIndex];
}

- (NSRect)rectForNote:(NoteEvent *)note {
    CGFloat x = kKeyboardWidth + (CGFloat)note.startTick * kPixelsPerTick;
    CGFloat y = kHeaderHeight + (CGFloat)(kHighPitch - note.pitch) * kPianoRowHeight;
    CGFloat width = MAX(5.0, (CGFloat)note.durationTicks * kPixelsPerTick);
    return NSMakeRect(x, y + 1, width, kPianoRowHeight - 2);
}

- (NoteEvent *)noteAtPoint:(NSPoint)point {
    Track *track = [self currentTrack];
    for (NoteEvent *note in track.notes) {
        if (NSPointInRect(point, [self rectForNote:note])) return note;
    }
    return nil;
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    [[NSColor controlBackgroundColor] setFill];
    NSRectFill(dirtyRect);

    Song *song = self.document.song;
    Track *track = [self currentTrack];
    if (!song || !track) return;

    NSDictionary *keyAttributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:8 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: [NSColor secondaryLabelColor]
    };
    NSDictionary *noteAttributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:9 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: [NSColor whiteColor]
    };

    // Piano keyboard and horizontal rows.
    for (NSInteger pitch = kHighPitch; pitch >= kLowPitch; pitch--) {
        CGFloat y = kHeaderHeight + (CGFloat)(kHighPitch - pitch) * kPianoRowHeight;
        NSString *name = NoteNameWithoutOctave(pitch);
        BOOL black = [name containsString:@"#"];
        NSColor *rowColor = black ? [NSColor colorWithWhite:0.5 alpha:0.06] : [NSColor colorWithWhite:0.5 alpha:0.02];
        [rowColor setFill];
        NSRectFill(NSMakeRect(kKeyboardWidth, y, self.bounds.size.width - kKeyboardWidth, kPianoRowHeight));

        NSColor *keyColor = black ? [NSColor colorWithWhite:0.18 alpha:1.0] : [NSColor colorWithWhite:0.94 alpha:1.0];
        if ([NSApp.effectiveAppearance.name containsString:@"Dark"]) {
            keyColor = black ? [NSColor colorWithWhite:0.08 alpha:1.0] : [NSColor colorWithWhite:0.72 alpha:1.0];
        }
        [keyColor setFill];
        NSRectFill(NSMakeRect(0, y, black ? kKeyboardWidth * 0.62 : kKeyboardWidth, kPianoRowHeight - 1));
        if (pitch % 12 == 0) {
            [NoteNameForPitch(pitch) drawAtPoint:NSMakePoint(4, y + 1) withAttributes:keyAttributes];
        }
        [[NSColor.separatorColor colorWithAlphaComponent:0.25] setFill];
        NSRectFill(NSMakeRect(kKeyboardWidth, y, self.bounds.size.width - kKeyboardWidth, 1));
    }

    // Vertical grid.
    uint64_t stepTicks = MAX(1ULL, song.ppq / 4);
    for (uint64_t tick = 0; tick <= self.totalTicks; tick += stepTicks) {
        CGFloat x = kKeyboardWidth + (CGFloat)tick * kPixelsPerTick;
        BOOL isBar = (tick % song.ticksPerBar) == 0;
        BOOL isBeat = (tick % song.ppq) == 0;
        NSColor *color = isBar ? [NSColor.separatorColor colorWithAlphaComponent:0.7] : (isBeat ? ChiptuneGridColor() : [ChiptuneGridColor() colorWithAlphaComponent:0.45]);
        [color setFill];
        NSRectFill(NSMakeRect(x, kHeaderHeight, 1, self.bounds.size.height - kHeaderHeight));
    }

    // Bar labels.
    for (NSInteger bar = 0; bar < song.lengthBars; bar++) {
        uint64_t tick = (uint64_t)bar * song.ticksPerBar;
        CGFloat x = kKeyboardWidth + (CGFloat)tick * kPixelsPerTick;
        NSString *label = [NSString stringWithFormat:@"Bar %ld", (long)(bar + 1)];
        [label drawAtPoint:NSMakePoint(x + 5, 5) withAttributes:keyAttributes];
    }

    // Notes.
    for (NoteEvent *note in track.notes) {
        if (note.pitch < kLowPitch || note.pitch > kHighPitch) continue;
        NSRect rect = [self rectForNote:note];
        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:3 yRadius:3];
        [ChiptuneNoteColor(self.currentTrackIndex) setFill];
        [path fill];
        if ([note.identifier isEqualToString:self.selectedNoteIdentifier]) {
            [[NSColor whiteColor] setStroke];
            path.lineWidth = 2.0;
            [path stroke];
        }
        if (rect.size.width > 30) {
            NSString *name = NoteNameForPitch(note.pitch);
            [name drawAtPoint:NSMakePoint(rect.origin.x + 4, rect.origin.y + 2) withAttributes:noteAttributes];
        }
    }

    // Playhead.
    CGFloat playheadX = kKeyboardWidth + (CGFloat)self.playheadTick * kPixelsPerTick;
    if (playheadX >= kKeyboardWidth && playheadX <= self.bounds.size.width) {
        [[ChiptuneAccentColor() colorWithAlphaComponent:0.9] setFill];
        NSRectFill(NSMakeRect(playheadX, 0, 1.5, self.bounds.size.height));
    }
}

- (void)scrollWheel:(NSEvent *)event {
    if (ChiptuneHandleTimelineScrollWheel(self, event, NO)) return;
    [super scrollWheel:event];
}

- (void)scrollSelectedNoteToVisible {
    if (self.selectedNoteIdentifier.length == 0) return;
    for (NoteEvent *note in [self currentTrack].notes) {
        if (![note.identifier isEqualToString:self.selectedNoteIdentifier]) continue;
        [self scrollRectToVisible:NSInsetRect([self rectForNote:note], -60, -40)];
        break;
    }
}

- (CGFloat)autoScrollForDragPoint:(NSPoint)point {
    NSScrollView *scrollView = self.enclosingScrollView;
    NSClipView *clipView = scrollView.contentView;
    if (!scrollView || !clipView) return 0.0;
    NSRect visible = clipView.bounds;
    CGFloat margin = 32.0;
    CGFloat delta = 0.0;
    if (point.x > NSMaxX(visible) - margin) {
        delta = 40.0;
    } else if (point.x < NSMinX(visible) + margin) {
        delta = -40.0;
    }
    if (fabs(delta) < 0.01) return 0.0;
    CGFloat maxX = MAX(0.0, self.bounds.size.width - visible.size.width);
    CGFloat target = MAX(0.0, MIN(maxX, visible.origin.x + delta));
    CGFloat actual = target - visible.origin.x;
    if (fabs(actual) > 0.01) {
        [clipView scrollToPoint:NSMakePoint(target, visible.origin.y)];
        [scrollView reflectScrolledClipView:clipView];
    }
    return actual;
}

- (void)mouseDown:(NSEvent *)event {
    [self.window makeFirstResponder:self];
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NoteEvent *note = [self noteAtPoint:point];
    if (note) {
        self.selectedNoteIdentifier = note.identifier;
        self.dragNote = note;
        NSRect rect = [self rectForNote:note];
        self.dragMode = (point.x > NSMaxX(rect) - 6) ? PianoDragModeResize : PianoDragModeMove;
        self.dragStart = point;
        self.originalStartTick = note.startTick;
        self.originalDuration = note.durationTicks;
        self.originalPitch = note.pitch;
        self.didDrag = NO;
        self.undoSnapshot = [self.document.song copy];
        [self setNeedsDisplay:YES];
        return;
    }

    Song *song = self.document.song;
    if (!song) return;
    if (point.y < kHeaderHeight || point.x < kKeyboardWidth) return;
    NSInteger pitch = kHighPitch - (NSInteger)((point.y - kHeaderHeight) / kPianoRowHeight);
    pitch = MAX(kLowPitch, MIN(kHighPitch, pitch));
    double rawTick = (point.x - kKeyboardWidth) / kPixelsPerTick;
    uint64_t tick = [self snapTick:(uint64_t)MAX(0, rawTick)];
    if (tick >= song.totalTicks) return;
    NSInteger trackIndex = self.currentTrackIndex;
    uint64_t duration = self.stepTicks;
    NSInteger notePitch = pitch;
    [self.document performEditNamed:@"Add Note" block:^(Song *edited) {
        Track *editedTrack = edited.tracks[(NSUInteger)trackIndex];
        [editedTrack.notes addObject:[NoteEvent noteWithPitch:notePitch startTick:tick durationTicks:duration velocity:100]];
    }];
    self.selectedNoteIdentifier = nil;
    for (NoteEvent *candidate in [self currentTrack].notes) {
        if (candidate.startTick == tick && candidate.pitch == notePitch) {
            self.selectedNoteIdentifier = candidate.identifier;
            break;
        }
    }
    [self reloadData];
    [self scrollSelectedNoteToVisible];
}

- (void)mouseDragged:(NSEvent *)event {
    if (!self.dragNote) return;
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat scrolled = [self autoScrollForDragPoint:point];
    if (fabs(scrolled) > 0.01) {
        self.dragStart = NSMakePoint(self.dragStart.x - scrolled, self.dragStart.y);
        point = [self convertPoint:event.locationInWindow fromView:nil];
    }
    if (self.dragMode == PianoDragModeMove) {
        double deltaTicks = (point.x - self.dragStart.x) / kPixelsPerTick;
        NSInteger deltaPitch = -(NSInteger)llround((point.y - self.dragStart.y) / kPianoRowHeight);
        uint64_t newStart = [self snapTick:(uint64_t)MAX(0.0, (double)self.originalStartTick + deltaTicks)];
        NSInteger newPitch = MAX(0, MIN(127, self.originalPitch + deltaPitch));
        if (newStart != self.originalStartTick || newPitch != self.originalPitch) self.didDrag = YES;
        self.dragNote.startTick = newStart;
        self.dragNote.pitch = newPitch;
    } else if (self.dragMode == PianoDragModeResize) {
        double deltaTicks = (point.x - self.dragStart.x) / kPixelsPerTick;
        uint64_t newDuration = [self snapTick:(uint64_t)MAX((double)self.stepTicks, (double)self.originalDuration + deltaTicks)];
        if (newDuration != self.originalDuration) self.didDrag = YES;
        self.dragNote.durationTicks = newDuration;
    }
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event {
    if (self.dragNote && self.didDrag) {
        [self.document.undoManager registerUndoWithTarget:self.document selector:@selector(restoreSong:) object:self.undoSnapshot];
        [self.document.undoManager setActionName:(self.dragMode == PianoDragModeResize ? @"Resize Note" : @"Move Note")];
        [self.document updateChangeCount:NSChangeDone];
        [self.document notifySongChanged];
    }
    self.dragNote = nil;
    self.dragMode = PianoDragModeNone;
    self.undoSnapshot = nil;
    self.didDrag = NO;
    [self scrollSelectedNoteToVisible];
}

- (uint64_t)snapTick:(uint64_t)tick {
    uint64_t step = MAX(1ULL, self.stepTicks);
    return (tick / step) * step;
}

- (void)keyDown:(NSEvent *)event {
    if (event.keyCode == 51 || event.keyCode == 117) { // delete / forward delete
        [self deleteSelectedNote];
        return;
    }
    if (event.keyCode == 123 || event.keyCode == 124 || event.keyCode == 125 || event.keyCode == 126) {
        [self nudgeSelectedNoteWithKeyCode:event.keyCode];
        return;
    }
    [super keyDown:event];
}

- (void)delete:(id)sender {
    [self deleteSelectedNote];
}

- (void)deleteSelectedNote {
    if (!self.selectedNoteIdentifier) return;
    NSString *identifier = self.selectedNoteIdentifier;
    NSInteger trackIndex = self.currentTrackIndex;
    [self.document performEditNamed:@"Delete Note" block:^(Song *edited) {
        Track *track = edited.tracks[(NSUInteger)trackIndex];
        NSMutableArray *keep = [NSMutableArray array];
        for (NoteEvent *note in track.notes) {
            if (![note.identifier isEqualToString:identifier]) [keep addObject:note];
        }
        track.notes = keep;
    }];
    self.selectedNoteIdentifier = nil;
    [self reloadData];
}

- (void)nudgeSelectedNoteWithKeyCode:(unsigned short)keyCode {
    if (!self.selectedNoteIdentifier) return;
    NSString *identifier = self.selectedNoteIdentifier;
    NSInteger trackIndex = self.currentTrackIndex;
    uint64_t step = MAX(1ULL, self.stepTicks);
    [self.document performEditNamed:@"Nudge Note" block:^(Song *edited) {
        Track *track = edited.tracks[(NSUInteger)trackIndex];
        for (NoteEvent *note in track.notes) {
            if (![note.identifier isEqualToString:identifier]) continue;
            if (keyCode == 123) note.startTick = note.startTick > step ? note.startTick - step : 0;
            if (keyCode == 124) note.startTick += step;
            if (keyCode == 125) note.pitch = MAX(0, note.pitch - 1);
            if (keyCode == 126) note.pitch = MIN(127, note.pitch + 1);
            break;
        }
    }];
    [self reloadData];
    [self scrollSelectedNoteToVisible];
}

@end
