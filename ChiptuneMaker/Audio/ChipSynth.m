#import "ChipSynth.h"
#import <math.h>

static double PolyBLEP(double t, double dt) {
    if (dt <= 0.0) return 0.0;
    if (t < dt) {
        t /= dt;
        return t + t - t * t - 1.0;
    }
    if (t > 1.0 - dt) {
        t = (t - 1.0) / dt;
        return t * t + t + t + 1.0;
    }
    return 0.0;
}

static double FrequencyForNote(NSInteger note) {
    return 440.0 * pow(2.0, ((double)note - 69.0) / 12.0);
}

static double ClampFrequency(double frequency) {
    return MIN(20000.0, MAX(20.0, frequency));
}

static uint32_t NoiseShift(uint32_t lfsr) {
    uint32_t bit = ((lfsr >> 0) ^ (lfsr >> 1)) & 1u;
    lfsr = (lfsr >> 1) | (bit << 14);
    return lfsr & 0x7FFFu;
}

static const double kWavetable[32] = {
    0.000, 0.195, 0.383, 0.556, 0.707, 0.831, 0.924, 0.981,
    1.000, 0.981, 0.924, 0.831, 0.707, 0.556, 0.383, 0.195,
    0.000, -0.195, -0.383, -0.556, -0.707, -0.831, -0.924, -0.981,
    -1.000, -0.981, -0.924, -0.831, -0.707, -0.556, -0.383, -0.195
};

ChipInstrumentParams ChipInstrumentDefaultParams(ChipInstrument instrument) {
    ChipInstrumentParams params;
    memset(&params, 0, sizeof(params));
    params.attack = 0.004;
    params.decay = 0.05;
    params.sustain = 0.72;
    params.release = 0.06;
    params.vibratoDepth = 0.0;
    params.vibratoRate = 5.0;
    params.slide = NO;
    params.arpeggio = 0;
    switch (instrument) {
        case ChipInstrumentPulse12:
            params.duty = 0.125;
            break;
        case ChipInstrumentPulse25:
            params.duty = 0.25;
            break;
        case ChipInstrumentPulse50:
            params.duty = 0.5;
            break;
        case ChipInstrumentTriangle:
            params.duty = 0.5;
            params.attack = 0.002;
            params.decay = 0.02;
            params.sustain = 0.9;
            params.release = 0.04;
            break;
        case ChipInstrumentNoise:
            params.duty = 0.5;
            params.attack = 0.001;
            params.decay = 0.08;
            params.sustain = 0.0;
            params.release = 0.04;
            break;
        case ChipInstrumentWavetable:
            params.duty = 0.5;
            params.attack = 0.01;
            params.decay = 0.12;
            params.sustain = 0.65;
            params.release = 0.12;
            break;
    }
    return params;
}

void ChipVoiceStart(ChipVoice *voice,
                    NSInteger trackIndex,
                    NSInteger note,
                    double velocity,
                    ChipInstrument instrument,
                    ChipInstrumentParams params,
                    double sampleRate,
                    double previousFrequency) {
    memset(voice, 0, sizeof(*voice));
    voice->active = YES;
    voice->released = NO;
    voice->trackIndex = trackIndex;
    voice->note = note;
    voice->velocity = MIN(1.0, MAX(0.0, velocity));
    voice->instrument = instrument;
    voice->params = params;
    voice->frequency = FrequencyForNote(note);
    voice->targetFrequency = voice->frequency;
    voice->startFrequency = (params.slide && previousFrequency > 0.0) ? previousFrequency : voice->frequency;
    voice->glideDuration = (params.slide && previousFrequency > 0.0) ? 0.035 : 0.0;
    voice->glideProgress = 0.0;
    voice->phase = 0.0;
    voice->envelope = 0.0;
    voice->envelopeStage = 0;
    voice->envelopeTime = 0.0;
    voice->releaseLevel = 0.0;
    voice->vibratoPhase = 0.0;
    voice->arpeggioTimer = 0.0;
    voice->arpeggioIndex = 0;
    voice->lfsr = 1u;
    voice->noisePhase = 0.0;
    (void)sampleRate;
}

void ChipVoiceRelease(ChipVoice *voice) {
    if (!voice->active || voice->released) return;
    voice->released = YES;
    voice->envelopeStage = 3;
    voice->envelopeTime = 0.0;
    voice->releaseLevel = voice->envelope;
}

static double ArpeggioOffset(NSInteger arpeggio, NSInteger index) {
    if (arpeggio == 1) {
        static const double major[] = {0.0, 4.0, 7.0};
        return major[index % 3];
    }
    if (arpeggio == 2) {
        static const double minor[] = {0.0, 3.0, 7.0};
        return minor[index % 3];
    }
    if (arpeggio == 3) {
        static const double octave[] = {0.0, 12.0, 0.0};
        return octave[index % 3];
    }
    return 0.0;
}

double ChipVoiceRender(ChipVoice *voice, double sampleRate) {
    if (!voice->active) return 0.0;
    double dt = 1.0 / sampleRate;

    if (voice->envelopeStage == 0) {
        voice->envelopeTime += dt;
        if (voice->params.attack <= 0.0001) {
            voice->envelope = 1.0;
            voice->envelopeStage = 1;
            voice->envelopeTime = 0.0;
        } else {
            voice->envelope = MIN(1.0, voice->envelopeTime / voice->params.attack);
            if (voice->envelopeTime >= voice->params.attack) {
                voice->envelope = 1.0;
                voice->envelopeStage = 1;
                voice->envelopeTime = 0.0;
            }
        }
    } else if (voice->envelopeStage == 1) {
        voice->envelopeTime += dt;
        if (voice->params.decay <= 0.0001) {
            voice->envelope = voice->params.sustain;
            voice->envelopeStage = 2;
        } else {
            double progress = MIN(1.0, voice->envelopeTime / voice->params.decay);
            voice->envelope = 1.0 - (1.0 - voice->params.sustain) * progress;
            if (progress >= 1.0) {
                voice->envelope = voice->params.sustain;
                voice->envelopeStage = 2;
            }
        }
    } else if (voice->envelopeStage == 2) {
        voice->envelope = voice->params.sustain;
    } else if (voice->envelopeStage == 3) {
        voice->envelopeTime += dt;
        if (voice->params.release <= 0.0001) {
            voice->envelope = 0.0;
            voice->active = NO;
        } else {
            double progress = MIN(1.0, voice->envelopeTime / voice->params.release);
            voice->envelope = voice->releaseLevel * (1.0 - progress);
            if (progress >= 1.0 || voice->envelope <= 0.00001) {
                voice->envelope = 0.0;
                voice->active = NO;
            }
        }
    }

    if (!voice->active) return 0.0;

    if (voice->glideDuration > 0.0 && voice->glideProgress < 1.0) {
        voice->glideProgress = MIN(1.0, voice->glideProgress + dt / voice->glideDuration);
        voice->frequency = voice->startFrequency + (voice->targetFrequency - voice->startFrequency) * voice->glideProgress;
    }

    double frequency = voice->frequency;

    if (voice->params.vibratoDepth > 0.0001) {
        voice->vibratoPhase += 2.0 * M_PI * voice->params.vibratoRate * dt;
        if (voice->vibratoPhase > 2.0 * M_PI) voice->vibratoPhase -= 2.0 * M_PI;
        frequency *= pow(2.0, voice->params.vibratoDepth * sin(voice->vibratoPhase) / 12.0);
    }

    if (voice->params.arpeggio > 0) {
        voice->arpeggioTimer += dt;
        if (voice->arpeggioTimer >= (1.0 / 30.0)) {
            voice->arpeggioTimer = 0.0;
            voice->arpeggioIndex = (voice->arpeggioIndex + 1) % 3;
        }
        frequency *= pow(2.0, ArpeggioOffset(voice->params.arpeggio, voice->arpeggioIndex) / 12.0);
    }

    frequency = ClampFrequency(frequency);
    double phaseIncrement = frequency / sampleRate;
    double sample = 0.0;

    switch (voice->instrument) {
        case ChipInstrumentPulse12:
        case ChipInstrumentPulse25:
        case ChipInstrumentPulse50: {
            double duty = voice->params.duty;
            double value = (voice->phase < duty) ? 1.0 : -1.0;
            value += PolyBLEP(voice->phase, phaseIncrement);
            double phase2 = voice->phase + (1.0 - duty);
            if (phase2 >= 1.0) phase2 -= 1.0;
            value -= PolyBLEP(phase2, phaseIncrement);
            sample = value;
            break;
        }
        case ChipInstrumentTriangle: {
            double value = 1.0 - 4.0 * fabs(voice->phase - 0.5);
            sample = round(value * 8.0) / 8.0;
            break;
        }
        case ChipInstrumentNoise: {
            double rate = 4000.0 * pow(2.0, ((double)voice->note - 60.0) / 12.0);
            voice->noisePhase += rate / sampleRate;
            while (voice->noisePhase >= 1.0) {
                voice->noisePhase -= 1.0;
                voice->lfsr = NoiseShift(voice->lfsr);
            }
            sample = (voice->lfsr & 1u) ? 1.0 : -1.0;
            break;
        }
        case ChipInstrumentWavetable: {
            NSInteger index = (NSInteger)(voice->phase * 32.0) & 31;
            sample = kWavetable[index];
            break;
        }
    }

    voice->phase += phaseIncrement;
    if (voice->phase >= 1.0) voice->phase -= 1.0;

    return sample * voice->envelope * voice->velocity;
}
