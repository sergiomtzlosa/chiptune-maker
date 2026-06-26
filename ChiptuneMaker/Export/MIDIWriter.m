#import "MIDIWriter.h"
#import "Song.h"
#import "Track.h"
#import "NoteEvent.h"
#import "SongSection.h"
#import "TimingMap.h"
#import <stdlib.h>

typedef struct {
    uint64_t tick;
    int order;
    uint8_t status;
    uint8_t data1;
    uint8_t data2;
} MIDIEvent;

static int MIDIEventCompare(const void *a, const void *b) {
    const MIDIEvent *ea = (const MIDIEvent *)a;
    const MIDIEvent *eb = (const MIDIEvent *)b;
    if (ea->tick < eb->tick) return -1;
    if (ea->tick > eb->tick) return 1;
    if (ea->order != eb->order) return ea->order < eb->order ? -1 : 1;
    return 0;
}

static void AppendBE16(NSMutableData *data, uint16_t value) {
    uint8_t bytes[2] = {(uint8_t)(value >> 8), (uint8_t)(value & 0xFF)};
    [data appendBytes:bytes length:2];
}

static void AppendBE32(NSMutableData *data, uint32_t value) {
    uint8_t bytes[4] = {(uint8_t)(value >> 24), (uint8_t)((value >> 16) & 0xFF), (uint8_t)((value >> 8) & 0xFF), (uint8_t)(value & 0xFF)};
    [data appendBytes:bytes length:4];
}

static void AppendVLQ(NSMutableData *data, uint32_t value) {
    uint8_t buffer[5];
    NSInteger index = 0;
    buffer[index++] = value & 0x7F;
    while ((value >>= 7) > 0) {
        buffer[index++] = (value & 0x7F) | 0x80;
    }
    for (NSInteger i = index - 1; i >= 0; i--) {
        [data appendBytes:&buffer[i] length:1];
    }
}

static void AppendMeta(NSMutableData *data, uint8_t type, NSData *payload) {
    uint8_t prefix[2] = {0xFF, type};
    [data appendBytes:prefix length:2];
    AppendVLQ(data, (uint32_t)payload.length);
    [data appendData:payload];
}

static void AppendTrackChunk(NSMutableData *output, NSMutableData *trackData) {
    [output appendBytes:"MTrk" length:4];
    AppendBE32(output, (uint32_t)trackData.length);
    [output appendData:trackData];
}

static uint8_t ChannelForTrack(NSInteger index, ChipInstrument instrument) {
    if (instrument == ChipInstrumentNoise) return 9;
    if (index < 9) return (uint8_t)index;
    return (uint8_t)(index + 1);
}

static uint8_t ProgramForInstrument(ChipInstrument instrument) {
    switch (instrument) {
        case ChipInstrumentPulse12: return 81;
        case ChipInstrumentPulse25: return 80;
        case ChipInstrumentPulse50: return 80;
        case ChipInstrumentTriangle: return 38;
        case ChipInstrumentNoise: return 0;
        case ChipInstrumentWavetable: return 81;
    }
    return 80;
}

@implementation MIDIWriter

+ (NSData *)dataForSong:(Song *)song audibleOnly:(BOOL)audibleOnly {
    BOOL anySolo = NO;
    for (Track *track in song.tracks) {
        if (track.soloed) { anySolo = YES; break; }
    }
    NSMutableArray<Track *> *tracks = [NSMutableArray array];
    for (Track *track in song.tracks) {
        BOOL audible = !track.muted && (!anySolo || track.soloed);
        if (!audibleOnly || audible) [tracks addObject:track];
    }
    if (tracks.count == 0) tracks = [song.tracks mutableCopy];

    NSMutableData *output = [NSMutableData data];
    [output appendBytes:"MThd" length:4];
    AppendBE32(output, 6);
    AppendBE16(output, 1);
    AppendBE16(output, (uint16_t)(tracks.count + 1));
    AppendBE16(output, 480);

    NSMutableData *tempoTrack = [NSMutableData data];
    AppendVLQ(tempoTrack, 0);
    AppendMeta(tempoTrack, 0x03, [song.title dataUsingEncoding:NSUTF8StringEncoding]);
    uint32_t microsPerQuarter = (uint32_t)llround(60000000.0 / MAX(1.0, song.tempo));
    uint8_t tempoBytes[3] = {(uint8_t)(microsPerQuarter >> 16), (uint8_t)((microsPerQuarter >> 8) & 0xFF), (uint8_t)(microsPerQuarter & 0xFF)};
    AppendVLQ(tempoTrack, 0);
    AppendMeta(tempoTrack, 0x51, [NSData dataWithBytes:tempoBytes length:3]);
    NSInteger denominatorPower = 0;
    NSInteger denominator = song.timeSignatureDenominator;
    while (denominator > 1) { denominator >>= 1; denominatorPower++; }
    uint8_t timeSignature[4] = {(uint8_t)song.timeSignatureNumerator, (uint8_t)denominatorPower, 24, 8};
    AppendVLQ(tempoTrack, 0);
    AppendMeta(tempoTrack, 0x58, [NSData dataWithBytes:timeSignature length:4]);

    uint64_t lastMarkerTick = 0;
    for (SongSection *section in song.sections) {
        uint64_t tick = (uint64_t)section.startBar * song.ticksPerBar;
        uint32_t delta = (uint32_t)(tick - lastMarkerTick);
        AppendVLQ(tempoTrack, delta);
        AppendMeta(tempoTrack, 0x06, [section.name dataUsingEncoding:NSUTF8StringEncoding]);
        lastMarkerTick = tick;
    }
    AppendVLQ(tempoTrack, 0);
    AppendMeta(tempoTrack, 0x2F, [NSData data]);
    AppendTrackChunk(output, tempoTrack);

    for (NSInteger trackIndex = 0; trackIndex < (NSInteger)tracks.count; trackIndex++) {
        Track *track = tracks[(NSUInteger)trackIndex];
        uint8_t channel = ChannelForTrack(trackIndex, track.instrument);
        NSMutableData *trackData = [NSMutableData data];
        AppendVLQ(trackData, 0);
        AppendMeta(trackData, 0x03, [track.name dataUsingEncoding:NSUTF8StringEncoding]);
        AppendVLQ(trackData, 0);
        uint8_t program[2] = {(uint8_t)(0xC0 | channel), ProgramForInstrument(track.instrument)};
        [trackData appendBytes:program length:2];

        NSUInteger capacity = track.notes.count * 2;
        MIDIEvent *events = capacity > 0 ? calloc(capacity, sizeof(MIDIEvent)) : NULL;
        NSUInteger count = 0;
        uint64_t ppq = song.ppq;
        for (NoteEvent *note in track.notes) {
            uint64_t start = [TimingMap playbackTickForTick:note.startTick ppq:ppq swing:song.swing];
            uint64_t duration = MAX(1ULL, note.durationTicks);
            uint64_t end = start + duration;
            events[count++] = (MIDIEvent){.tick = start, .order = 1, .status = (uint8_t)(0x90 | channel), .data1 = (uint8_t)MAX(0, MIN(127, note.pitch)), .data2 = (uint8_t)MAX(0, MIN(127, note.velocity))};
            events[count++] = (MIDIEvent){.tick = end, .order = 0, .status = (uint8_t)(0x80 | channel), .data1 = (uint8_t)MAX(0, MIN(127, note.pitch)), .data2 = 0};
        }
        if (count > 0) qsort(events, count, sizeof(MIDIEvent), MIDIEventCompare);

        uint64_t previousTick = 0;
        for (NSUInteger i = 0; i < count; i++) {
            uint64_t tick = events[i].tick;
            uint32_t delta = (uint32_t)(tick - previousTick);
            AppendVLQ(trackData, delta);
            uint8_t bytes[3] = {events[i].status, events[i].data1, events[i].data2};
            [trackData appendBytes:bytes length:3];
            previousTick = tick;
        }
        free(events);
        AppendVLQ(trackData, 0);
        AppendMeta(trackData, 0x2F, [NSData data]);
        AppendTrackChunk(output, trackData);
    }
    return output;
}

@end
