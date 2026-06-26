#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// Posted when the user scrolls a timeline view directly (for example with a
/// mouse wheel). The main controller uses it to stop playhead following so the
/// user can inspect another part of the song during playback.
FOUNDATION_EXPORT NSNotificationName const ChiptuneTimelineDidScrollByUserNotification;

/// Handles a scroll-wheel event for a horizontally scrolling timeline view.
/// Returns YES when the event was consumed. Set `convertVerticalWheel` for
/// views that usually do not scroll vertically (such as the step grid), so a
/// normal wheel moves the timeline sideways.
BOOL ChiptuneHandleTimelineScrollWheel(NSView *documentView, NSEvent *event, BOOL convertVerticalWheel);

NS_ASSUME_NONNULL_END
