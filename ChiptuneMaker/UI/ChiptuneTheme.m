#import "ChiptuneTheme.h"

NSColor *ChiptuneTrackColor(NSInteger index) {
    static NSArray<NSColor *> *colors = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        colors = @[
            [NSColor systemBlueColor],
            [NSColor systemPinkColor],
            [NSColor systemGreenColor],
            [NSColor systemOrangeColor],
            [NSColor systemPurpleColor],
            [NSColor systemTealColor],
            [NSColor systemYellowColor],
            [NSColor systemRedColor]
        ];
    });
    return colors[(NSUInteger)MAX(0, index) % colors.count];
}

NSColor *ChiptuneNoteColor(NSInteger index) {
    return [ChiptuneTrackColor(index) colorWithAlphaComponent:0.85];
}

NSColor *ChiptuneGridColor(void) {
    return [NSColor.separatorColor colorWithAlphaComponent:0.45];
}

NSColor *ChiptuneAccentColor(void) {
    return [NSColor systemRedColor];
}
