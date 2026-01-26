#import "TimelineScrollSupport.h"

NSNotificationName const ChiptuneTimelineDidScrollByUserNotification = @"ChiptuneTimelineDidScrollByUserNotification";

BOOL ChiptuneHandleTimelineScrollWheel(NSView *documentView, NSEvent *event, BOOL convertVerticalWheel) {
    NSScrollView *scrollView = documentView.enclosingScrollView;
    NSClipView *clipView = scrollView.contentView;
    if (!scrollView || !clipView) return NO;

    CGFloat dx = event.scrollingDeltaX;
    CGFloat dy = event.scrollingDeltaY;
    BOOL shift = (event.modifierFlags & NSEventModifierFlagShift) != 0;
    BOOL horizontalOverflow = documentView.bounds.size.width > clipView.bounds.size.width + 0.5;
    BOOL verticalOverflow = documentView.bounds.size.height > clipView.bounds.size.height + 0.5;

    // Shift+wheel always scrolls the timeline. A normal wheel also does so for
    // views without vertical overflow, where a vertical wheel would otherwise
    // do nothing at all.
    BOOL wantsHorizontal = horizontalOverflow &&
        (shift || (convertVerticalWheel && fabs(dx) < 0.01 && !verticalOverflow));
    if (!wantsHorizontal) return NO;

    CGFloat delta = fabs(dx) > 0.01 ? dx : dy;
    CGFloat x = clipView.bounds.origin.x;
    CGFloat maxX = MAX(0.0, documentView.bounds.size.width - clipView.bounds.size.width);
    CGFloat target = MAX(0.0, MIN(maxX, x - delta));
    if (fabs(target - x) > 0.01) {
        [clipView scrollToPoint:NSMakePoint(target, clipView.bounds.origin.y)];
        [scrollView reflectScrolledClipView:clipView];
        [[NSNotificationCenter defaultCenter] postNotificationName:ChiptuneTimelineDidScrollByUserNotification
                                                            object:documentView];
    }
    return YES;
}
