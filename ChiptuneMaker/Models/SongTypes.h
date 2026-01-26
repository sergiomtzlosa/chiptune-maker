#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, ChipInstrument) {
    ChipInstrumentPulse12 = 0,
    ChipInstrumentPulse25,
    ChipInstrumentPulse50,
    ChipInstrumentTriangle,
    ChipInstrumentNoise,
    ChipInstrumentWavetable
};

typedef NS_ENUM(NSInteger, MusicalScale) {
    MusicalScaleMajor = 0,
    MusicalScaleMinor,
    MusicalScaleDorian,
    MusicalScalePhrygian,
    MusicalScaleLydian,
    MusicalScaleMixolydian,
    MusicalScalePentatonicMajor,
    MusicalScalePentatonicMinor,
    MusicalScaleBlues,
    MusicalScaleChromatic
};

FOUNDATION_EXPORT NSString *ChipInstrumentIdentifier(ChipInstrument instrument);
FOUNDATION_EXPORT ChipInstrument ChipInstrumentFromIdentifier(NSString *identifier);
FOUNDATION_EXPORT NSString *ChipInstrumentDisplayName(ChipInstrument instrument);

FOUNDATION_EXPORT NSString *MusicalScaleIdentifier(MusicalScale scale);
FOUNDATION_EXPORT MusicalScale MusicalScaleFromIdentifier(NSString *identifier);
FOUNDATION_EXPORT NSString *MusicalScaleDisplayName(MusicalScale scale);
FOUNDATION_EXPORT NSArray<NSNumber *> *MusicalScaleIntervals(MusicalScale scale);

FOUNDATION_EXPORT NSString *NoteNameForPitch(NSInteger pitch);
FOUNDATION_EXPORT NSString *NoteNameWithoutOctave(NSInteger pitch);
FOUNDATION_EXPORT NSArray<NSString *> *NoteNames(void);
