#import "LSDjExporter.h"
#import "Song.h"
#import "Track.h"
#import "NoteEvent.h"

#include "lsdj/project.h"
#include "lsdj/song.h"
#include "lsdj/phrase.h"
#include "lsdj/chain.h"
#include "lsdj/instrument.h"
#include "lsdj/error.h"
#include "lsdj/compression.h"

#import <math.h>
#import <string.h>

// libLSDJ exposes read-only allocation queries, but no public setters for the
// allocation tables. These offsets are part of the on-disk song layout and are
// documented in libLSDJ's private src/song_offsets.h.
static const NSUInteger kLSDjPhraseAllocationOffset = 0x3E82;
static const NSUInteger kLSDjChainAllocationOffset = 0x3EA2;
static const NSUInteger kLSDjInstrumentAllocationOffset = 0x2040;

static NSError *LSDjExportError(NSString *message) {
    return [NSError errorWithDomain:@"ChiptuneMaker.LSDjExport"
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSString *LSDjSanitizedName(NSString *input, NSUInteger maximumLength, NSString *fallback) {
    NSString *uppercase = input.length > 0 ? input.uppercaseString : @"";
    NSMutableString *name = [NSMutableString stringWithCapacity:maximumLength];
    for (NSUInteger i = 0; i < uppercase.length && name.length < maximumLength; i++) {
        unichar character = [uppercase characterAtIndex:i];
        BOOL valid = (character >= 'A' && character <= 'Z') ||
                     (character >= '0' && character <= '9') ||
                     character == ' ';
        [name appendFormat:@"%C", (unichar)(valid ? character : ' ')];
    }
    return name.length > 0 ? name : fallback;
}

// LSDj note byte 0x01 is C-3 (MIDI 36) and byte 0x14 is G-4 (MIDI 55), so the
// byte is MIDI pitch minus 35. The playable range is C-3 through B-7.
static uint8_t LSDjNoteForMIDIPitch(NSInteger pitch) {
    NSInteger note = pitch - 35;
    if (note < 1) note = 1;
    if (note > 0x3C) note = 0x3C;
    return (uint8_t)note;
}

static lsdj_panning_t LSDjPanningForTrack(Track *track) {
    double pan = MAX(-1.0, MIN(1.0, track.pan));
    if (pan < -0.25) return LSDJ_PAN_LEFT;
    if (pan > 0.25) return LSDJ_PAN_RIGHT;
    return LSDJ_PAN_LEFT_RIGHT;
}

static lsdj_instrument_wave_volume_t LSDjWaveVolumeForTrack(Track *track) {
    double volume = MAX(0.0, MIN(1.0, track.volume));
    if (volume > 0.75) return LSDJ_INSTRUMENT_WAVE_VOLUME_3;
    if (volume > 0.50) return LSDJ_INSTRUMENT_WAVE_VOLUME_2;
    if (volume > 0.25) return LSDJ_INSTRUMENT_WAVE_VOLUME_1;
    return LSDJ_INSTRUMENT_WAVE_VOLUME_0;
}

static NSArray<Track *> *LSDjTracksForSong(Song *song, BOOL audibleOnly) {
    BOOL anySolo = NO;
    for (Track *track in song.tracks) {
        if (track.soloed) {
            anySolo = YES;
            break;
        }
    }

    NSMutableArray<Track *> *tracks = [NSMutableArray array];
    for (Track *track in song.tracks) {
        BOOL audible = !track.muted && (!anySolo || track.soloed);
        if (!audibleOnly || audible) [tracks addObject:track];
    }
    return tracks;
}

@interface LSDjBuilder : NSObject
- (instancetype)initWithSong:(Song *)song
                      tracks:(NSArray<Track *> *)tracks
                  songBuffer:(lsdj_song_t *)songBuffer;
- (BOOL)build:(NSError **)error;
@end

@implementation LSDjBuilder {
    Song *_song;
    NSArray<Track *> *_tracks;
    lsdj_song_t *_songBuffer;
    uint8_t _trackChannels[LSDJ_INSTRUMENT_COUNT];
    NSMutableDictionary<NSData *, NSNumber *> *_phraseCache;
    NSMutableDictionary<NSData *, NSNumber *> *_chainCache;
    NSUInteger _nextPhrase;
    NSUInteger _nextChain;
}

- (instancetype)initWithSong:(Song *)song
                      tracks:(NSArray<Track *> *)tracks
                  songBuffer:(lsdj_song_t *)songBuffer {
    self = [super init];
    if (self) {
        _song = song;
        _tracks = tracks;
        _songBuffer = songBuffer;
        _phraseCache = [NSMutableDictionary dictionary];
        _chainCache = [NSMutableDictionary dictionary];
    }
    return self;
}

- (BOOL)build:(NSError **)error {
    [self configureInstruments];

    uint64_t ticksPerBar = [_song ticksPerBar];
    if (ticksPerBar == 0) {
        if (error) *error = LSDjExportError(@"The song has an invalid bar length.");
        return NO;
    }

    NSInteger barCount = MAX(0, _song.lengthBars);
    NSInteger groupCount = (barCount + 15) / 16;
    if (groupCount > 256) {
        if (error) *error = LSDjExportError(@"The song is too long for LSDj. LSDj supports at most 4096 bars.");
        return NO;
    }

    for (NSInteger group = 0; group < groupCount; group++) {
        for (uint8_t channel = 0; channel < LSDJ_CHANNEL_COUNT; channel++) {
            uint8_t phrases[LSDJ_CHAIN_LENGTH];
            memset(phrases, LSDJ_CHAIN_NO_PHRASE, sizeof(phrases));

            BOOL hasPhrase = NO;
            for (NSInteger slot = 0; slot < LSDJ_CHAIN_LENGTH; slot++) {
                NSInteger bar = group * LSDJ_CHAIN_LENGTH + slot;
                if (bar >= barCount) break;

                NSNumber *phrase = [self phraseForChannel:(lsdj_channel_t)channel
                                                      bar:bar
                                               ticksPerBar:ticksPerBar
                                                    error:error];
                if (!phrase) {
                    if (error && *error) return NO;
                    continue;
                }
                phrases[slot] = (uint8_t)phrase.unsignedIntegerValue;
                hasPhrase = YES;
            }

            if (!hasPhrase) {
                lsdj_row_set_chain(_songBuffer, (uint8_t)group, (lsdj_channel_t)channel, LSDJ_SONG_NO_CHAIN);
                continue;
            }

            NSNumber *chain = [self chainForPhrases:phrases error:error];
            if (!chain) return NO;
            lsdj_row_set_chain(_songBuffer,
                               (uint8_t)group,
                               (lsdj_channel_t)channel,
                               (uint8_t)chain.unsignedIntegerValue);
        }
    }

    return YES;
}

- (void)configureInstruments {
    NSUInteger pulseIndex = 0;
    for (NSUInteger index = 0; index < _tracks.count; index++) {
        Track *track = _tracks[index];
        lsdj_channel_t channel = LSDJ_CHANNEL_PULSE1;
        switch (track.instrument) {
            case ChipInstrumentPulse12:
            case ChipInstrumentPulse25:
            case ChipInstrumentPulse50:
                channel = (pulseIndex % 2 == 0) ? LSDJ_CHANNEL_PULSE1 : LSDJ_CHANNEL_PULSE2;
                pulseIndex++;
                break;
            case ChipInstrumentTriangle:
            case ChipInstrumentWavetable:
                channel = LSDJ_CHANNEL_WAVE;
                break;
            case ChipInstrumentNoise:
                channel = LSDJ_CHANNEL_NOISE;
                break;
        }
        _trackChannels[index] = (uint8_t)channel;
        [self configureInstrument:(uint8_t)index forTrack:track];
    }
}

- (void)configureInstrument:(uint8_t)index forTrack:(Track *)track {
    _songBuffer->bytes[kLSDjInstrumentAllocationOffset + index] = 1;

    NSString *name = LSDjSanitizedName(track.name, LSDJ_INSTRUMENT_NAME_LENGTH, @"TRACK");
    lsdj_instrument_set_name(_songBuffer, index, name.UTF8String);

    switch (track.instrument) {
        case ChipInstrumentPulse12:
        case ChipInstrumentPulse25:
        case ChipInstrumentPulse50: {
            lsdj_instrument_set_type(_songBuffer, index, LSDJ_INSTRUMENT_TYPE_PULSE);
            lsdj_instrument_pulse_width_t width = LSDJ_INSTRUMENT_PULSE_WIDTH_125;
            if (track.instrument == ChipInstrumentPulse25) width = LSDJ_INSTRUMENT_PULSE_WIDTH_25;
            if (track.instrument == ChipInstrumentPulse50) width = LSDJ_INSTRUMENT_PULSE_WIDTH_50;
            lsdj_instrument_pulse_set_pulse_width(_songBuffer, index, width);
            break;
        }
        case ChipInstrumentTriangle:
        case ChipInstrumentWavetable:
            lsdj_instrument_set_type(_songBuffer, index, LSDJ_INSTRUMENT_TYPE_WAVE);
            lsdj_instrument_wave_set_wave(_songBuffer, index, 0);
            lsdj_instrument_wave_set_play_mode(_songBuffer, index, LSDJ_INSTRUMENT_WAVE_PLAY_LOOP);
            lsdj_instrument_wave_set_volume(_songBuffer, index, LSDjWaveVolumeForTrack(track));
            break;
        case ChipInstrumentNoise:
            lsdj_instrument_set_type(_songBuffer, index, LSDJ_INSTRUMENT_TYPE_NOISE);
            lsdj_instrument_noise_set_length(_songBuffer, index, LSDJ_INSTRUMENT_NOISE_LENGTH_INFINITE);
            break;
    }

    if (track.instrument != ChipInstrumentTriangle && track.instrument != ChipInstrumentWavetable) {
        double volume = MAX(0.0, MIN(1.0, track.volume));
        uint8_t level = (uint8_t)lrint(volume * 15.0);
        lsdj_instrument_set_envelope(_songBuffer, index, (uint8_t)((level << 4) | 0x08));
    }

    lsdj_instrument_set_panning(_songBuffer, index, LSDjPanningForTrack(track));
}

- (NSNumber *)phraseForChannel:(lsdj_channel_t)channel
                           bar:(NSInteger)bar
                    ticksPerBar:(uint64_t)ticksPerBar
                         error:(NSError **)error {
    uint8_t notes[LSDJ_PHRASE_LENGTH] = {0};
    uint8_t instruments[LSDJ_PHRASE_LENGTH];
    memset(instruments, LSDJ_PHRASE_NO_INSTRUMENT, sizeof(instruments));

    uint64_t barStart = (uint64_t)bar * ticksPerBar;
    uint64_t barEnd = barStart + ticksPerBar;

    for (NSUInteger trackIndex = 0; trackIndex < _tracks.count; trackIndex++) {
        if (_trackChannels[trackIndex] != (uint8_t)channel) continue;

        Track *track = _tracks[trackIndex];
        for (NoteEvent *note in track.notes) {
            if (note.startTick < barStart || note.startTick >= barEnd) continue;

            uint64_t offset = note.startTick - barStart;
            NSUInteger step = (NSUInteger)((offset * LSDJ_PHRASE_LENGTH) / ticksPerBar);
            if (step >= LSDJ_PHRASE_LENGTH) step = LSDJ_PHRASE_LENGTH - 1;

            // LSDj phrases can hold one note per channel per step. Keep the
            // first track's note when merged tracks collide on a step.
            if (notes[step] != LSDJ_PHRASE_NO_NOTE) continue;

            notes[step] = LSDjNoteForMIDIPitch(note.pitch);
            instruments[step] = (uint8_t)trackIndex;
        }
    }

    BOOL hasNote = NO;
    for (NSUInteger step = 0; step < LSDJ_PHRASE_LENGTH; step++) {
        if (notes[step] != LSDJ_PHRASE_NO_NOTE) {
            hasNote = YES;
            break;
        }
    }
    if (!hasNote) return nil;

    uint8_t keyBytes[LSDJ_PHRASE_LENGTH * 2];
    memcpy(keyBytes, notes, LSDJ_PHRASE_LENGTH);
    memcpy(keyBytes + LSDJ_PHRASE_LENGTH, instruments, LSDJ_PHRASE_LENGTH);
    NSData *key = [NSData dataWithBytes:keyBytes length:sizeof(keyBytes)];

    NSNumber *cached = _phraseCache[key];
    if (cached) return cached;

    if (_nextPhrase >= LSDJ_PHRASE_COUNT) {
        if (error) *error = LSDjExportError(@"The song needs more than 255 LSDj phrases. Shorten the song or reduce its density.");
        return nil;
    }

    uint8_t phrase = (uint8_t)_nextPhrase++;
    for (NSUInteger step = 0; step < LSDJ_PHRASE_LENGTH; step++) {
        lsdj_phrase_set_note(_songBuffer, phrase, (uint8_t)step, notes[step]);
        lsdj_phrase_set_instrument(_songBuffer, phrase, (uint8_t)step, instruments[step]);
    }
    _songBuffer->bytes[kLSDjPhraseAllocationOffset + phrase / 8] |= (uint8_t)(1u << (phrase % 8));
    _phraseCache[key] = @(phrase);
    return @(phrase);
}

- (NSNumber *)chainForPhrases:(const uint8_t *)phrases error:(NSError **)error {
    NSData *key = [NSData dataWithBytes:phrases length:LSDJ_CHAIN_LENGTH];
    NSNumber *cached = _chainCache[key];
    if (cached) return cached;

    if (_nextChain >= LSDJ_CHAIN_COUNT) {
        if (error) *error = LSDjExportError(@"The song needs more than 127 LSDj chains. Shorten the song.");
        return nil;
    }

    uint8_t chain = (uint8_t)_nextChain++;
    for (NSUInteger step = 0; step < LSDJ_CHAIN_LENGTH; step++) {
        lsdj_chain_set_phrase(_songBuffer, chain, (uint8_t)step, phrases[step]);
        lsdj_chain_set_transposition(_songBuffer, chain, (uint8_t)step, 0);
    }
    _songBuffer->bytes[kLSDjChainAllocationOffset + chain / 8] |= (uint8_t)(1u << (chain % 8));
    _chainCache[key] = @(chain);
    return @(chain);
}

@end

@implementation LSDjExporter

+ (NSData *)dataForSong:(Song *)song audibleOnly:(BOOL)audibleOnly error:(NSError **)error {
    if (!song) {
        if (error) *error = LSDjExportError(@"There is no song to export.");
        return nil;
    }

    NSArray<Track *> *tracks = LSDjTracksForSong(song, audibleOnly);
    if (tracks.count == 0) {
        if (error) *error = LSDjExportError(@"There are no audible tracks to export.");
        return nil;
    }
    if (tracks.count > LSDJ_INSTRUMENT_COUNT) {
        if (error) {
            *error = LSDjExportError([NSString stringWithFormat:@"LSDj supports at most %d instruments, but the song has %lu audible tracks.",
                                      LSDJ_INSTRUMENT_COUNT,
                                      (unsigned long)tracks.count]);
        }
        return nil;
    }

    lsdj_project_t *project = NULL;
    lsdj_error_t result = lsdj_project_new(&project, NULL);
    if (result != LSDJ_SUCCESS) {
        if (error) {
            *error = LSDjExportError([NSString stringWithFormat:@"Could not create an LSDj project: %s.",
                                      lsdj_error_get_description(result) ?: "unknown error"]);
        }
        return nil;
    }

    NSData *data = nil;
    NSError *buildError = nil;
    lsdj_song_t *lsdjSong = lsdj_project_get_song(project);

    NSString *projectName = LSDjSanitizedName(song.title, LSDJ_PROJECT_NAME_LENGTH, @"UNTITLED");
    lsdj_project_set_name(project, projectName.UTF8String);
    lsdj_project_set_version(project, 0);

    double tempo = MAX(40.0, MIN(295.0, song.tempo));
    lsdj_song_set_tempo(lsdjSong, (unsigned short)lround(tempo));

    LSDjBuilder *builder = [[LSDjBuilder alloc] initWithSong:song tracks:tracks songBuffer:lsdjSong];
    if ([builder build:&buildError]) {
        uint8_t *buffer = calloc(LSDSNG_MAX_SIZE, 1);
        if (!buffer) {
            buildError = LSDjExportError(@"Not enough memory to write the LSDj file.");
        } else {
            size_t written = 0;
            result = lsdj_project_write_lsdsng_to_memory(project, buffer, &written);
            if (result == LSDJ_SUCCESS) {
                data = [NSData dataWithBytes:buffer length:written];
            } else {
                buildError = LSDjExportError([NSString stringWithFormat:@"Could not write the LSDj file: %s.",
                                              lsdj_error_get_description(result) ?: "unknown error"]);
            }
            free(buffer);
        }
    }

    lsdj_project_free(project);

    if (!data && error) {
        *error = buildError ?: LSDjExportError(@"Could not export the LSDj file.");
    }
    return data;
}

@end
