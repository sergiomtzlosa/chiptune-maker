#import <Foundation/Foundation.h>
#import "SongTypes.h"

typedef struct {
    double attack;
    double decay;
    double sustain;
    double release;
    double duty;
    double vibratoDepth;
    double vibratoRate;
    BOOL slide;
    NSInteger arpeggio;
} ChipInstrumentParams;

typedef struct {
    BOOL active;
    BOOL released;
    NSInteger trackIndex;
    NSInteger note;
    double velocity;
    double phase;
    double frequency;
    double targetFrequency;
    double startFrequency;
    double glideProgress;
    double glideDuration;
    double envelope;
    NSInteger envelopeStage;
    double envelopeTime;
    double releaseLevel;
    double vibratoPhase;
    double arpeggioTimer;
    NSInteger arpeggioIndex;
    uint32_t lfsr;
    double noisePhase;
    ChipInstrument instrument;
    ChipInstrumentParams params;
} ChipVoice;

ChipInstrumentParams ChipInstrumentDefaultParams(ChipInstrument instrument);
void ChipVoiceStart(ChipVoice *voice,
                    NSInteger trackIndex,
                    NSInteger note,
                    double velocity,
                    ChipInstrument instrument,
                    ChipInstrumentParams params,
                    double sampleRate,
                    double previousFrequency);
void ChipVoiceRelease(ChipVoice *voice);
double ChipVoiceRender(ChipVoice *voice, double sampleRate);
