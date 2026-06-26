#import "SongTypes.h"

NSString *ChipInstrumentIdentifier(ChipInstrument instrument) {
    switch (instrument) {
        case ChipInstrumentPulse12: return @"pulse12";
        case ChipInstrumentPulse25: return @"pulse25";
        case ChipInstrumentPulse50: return @"pulse50";
        case ChipInstrumentTriangle: return @"triangle";
        case ChipInstrumentNoise: return @"noise";
        case ChipInstrumentWavetable: return @"wavetable";
    }
    return @"pulse25";
}

ChipInstrument ChipInstrumentFromIdentifier(NSString *identifier) {
    if ([identifier isEqualToString:@"pulse12"]) return ChipInstrumentPulse12;
    if ([identifier isEqualToString:@"pulse25"]) return ChipInstrumentPulse25;
    if ([identifier isEqualToString:@"pulse50"]) return ChipInstrumentPulse50;
    if ([identifier isEqualToString:@"triangle"]) return ChipInstrumentTriangle;
    if ([identifier isEqualToString:@"noise"]) return ChipInstrumentNoise;
    if ([identifier isEqualToString:@"wavetable"]) return ChipInstrumentWavetable;
    return ChipInstrumentPulse25;
}

NSString *ChipInstrumentDisplayName(ChipInstrument instrument) {
    switch (instrument) {
        case ChipInstrumentPulse12: return @"Pulse 12.5%";
        case ChipInstrumentPulse25: return @"Pulse 25%";
        case ChipInstrumentPulse50: return @"Pulse 50%";
        case ChipInstrumentTriangle: return @"Triangle";
        case ChipInstrumentNoise: return @"Noise";
        case ChipInstrumentWavetable: return @"Wavetable";
    }
    return @"Pulse 25%";
}

NSString *MusicalScaleIdentifier(MusicalScale scale) {
    switch (scale) {
        case MusicalScaleMajor: return @"major";
        case MusicalScaleMinor: return @"minor";
        case MusicalScaleDorian: return @"dorian";
        case MusicalScalePhrygian: return @"phrygian";
        case MusicalScaleLydian: return @"lydian";
        case MusicalScaleMixolydian: return @"mixolydian";
        case MusicalScalePentatonicMajor: return @"pentatonicMajor";
        case MusicalScalePentatonicMinor: return @"pentatonicMinor";
        case MusicalScaleBlues: return @"blues";
        case MusicalScaleChromatic: return @"chromatic";
    }
    return @"major";
}

MusicalScale MusicalScaleFromIdentifier(NSString *identifier) {
    if ([identifier isEqualToString:@"major"]) return MusicalScaleMajor;
    if ([identifier isEqualToString:@"minor"]) return MusicalScaleMinor;
    if ([identifier isEqualToString:@"dorian"]) return MusicalScaleDorian;
    if ([identifier isEqualToString:@"phrygian"]) return MusicalScalePhrygian;
    if ([identifier isEqualToString:@"lydian"]) return MusicalScaleLydian;
    if ([identifier isEqualToString:@"mixolydian"]) return MusicalScaleMixolydian;
    if ([identifier isEqualToString:@"pentatonicMajor"]) return MusicalScalePentatonicMajor;
    if ([identifier isEqualToString:@"pentatonicMinor"]) return MusicalScalePentatonicMinor;
    if ([identifier isEqualToString:@"blues"]) return MusicalScaleBlues;
    if ([identifier isEqualToString:@"chromatic"]) return MusicalScaleChromatic;
    return MusicalScaleMajor;
}

NSString *MusicalScaleDisplayName(MusicalScale scale) {
    switch (scale) {
        case MusicalScaleMajor: return @"Major";
        case MusicalScaleMinor: return @"Natural Minor";
        case MusicalScaleDorian: return @"Dorian";
        case MusicalScalePhrygian: return @"Phrygian";
        case MusicalScaleLydian: return @"Lydian";
        case MusicalScaleMixolydian: return @"Mixolydian";
        case MusicalScalePentatonicMajor: return @"Major Pentatonic";
        case MusicalScalePentatonicMinor: return @"Minor Pentatonic";
        case MusicalScaleBlues: return @"Blues";
        case MusicalScaleChromatic: return @"Chromatic";
    }
    return @"Major";
}

NSArray<NSNumber *> *MusicalScaleIntervals(MusicalScale scale) {
    switch (scale) {
        case MusicalScaleMajor: return @[@0, @2, @4, @5, @7, @9, @11];
        case MusicalScaleMinor: return @[@0, @2, @3, @5, @7, @8, @10];
        case MusicalScaleDorian: return @[@0, @2, @3, @5, @7, @9, @10];
        case MusicalScalePhrygian: return @[@0, @1, @3, @5, @7, @8, @10];
        case MusicalScaleLydian: return @[@0, @2, @4, @6, @7, @9, @11];
        case MusicalScaleMixolydian: return @[@0, @2, @4, @5, @7, @9, @10];
        case MusicalScalePentatonicMajor: return @[@0, @2, @4, @7, @9];
        case MusicalScalePentatonicMinor: return @[@0, @3, @5, @7, @10];
        case MusicalScaleBlues: return @[@0, @3, @5, @6, @7, @10];
        case MusicalScaleChromatic: return @[@0, @1, @2, @3, @4, @5, @6, @7, @8, @9, @10, @11];
    }
    return @[@0, @2, @4, @5, @7, @9, @11];
}

static NSArray<NSString *> *gNoteNames = nil;

NSArray<NSString *> *NoteNames(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gNoteNames = @[@"C", @"C#", @"D", @"D#", @"E", @"F", @"F#", @"G", @"G#", @"A", @"A#", @"B"];
    });
    return gNoteNames;
}

NSString *NoteNameWithoutOctave(NSInteger pitch) {
    if (pitch < 0) pitch = 0;
    return NoteNames()[pitch % 12];
}

NSString *NoteNameForPitch(NSInteger pitch) {
    if (pitch < 0) pitch = 0;
    if (pitch > 127) pitch = 127;
    NSInteger octave = (pitch / 12) - 1;
    return [NSString stringWithFormat:@"%@%ld", NoteNames()[pitch % 12], (long)octave];
}
