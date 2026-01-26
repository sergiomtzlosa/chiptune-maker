#import <XCTest/XCTest.h>
#import "MIDIWriter.h"
#import "Song.h"
#import "Track.h"
#import "NoteEvent.h"

static NSUInteger ReadVLQ(const uint8_t *bytes, NSUInteger length, NSUInteger *offset) {
    NSUInteger value = 0;
    while (*offset < length) {
        uint8_t byte = bytes[(*offset)++];
        value = (value << 7) | (byte & 0x7F);
        if ((byte & 0x80) == 0) break;
    }
    return value;
}

static void CountTrackEvents(NSData *data, NSUInteger start, NSUInteger length, NSInteger *noteOn, NSInteger *noteOff) {
    const uint8_t *bytes = data.bytes;
    NSUInteger offset = start;
    NSUInteger end = start + length;
    uint8_t runningStatus = 0;
    while (offset < end) {
        ReadVLQ(bytes, end, &offset);
        if (offset >= end) break;
        uint8_t status = bytes[offset];
        if (status & 0x80) {
            offset++;
            runningStatus = status;
        } else {
            status = runningStatus;
        }
        if (status == 0xFF) {
            if (offset >= end) break;
            uint8_t type = bytes[offset++];
            NSUInteger metaLength = ReadVLQ(bytes, end, &offset);
            offset += metaLength;
            if (type == 0x2F) break;
        } else if ((status & 0xF0) == 0xC0 || (status & 0xF0) == 0xD0) {
            offset += 1;
        } else {
            if (offset + 2 > end) break;
            uint8_t data1 = bytes[offset++];
            uint8_t data2 = bytes[offset++];
            (void)data1;
            uint8_t kind = status & 0xF0;
            if (kind == 0x90 && data2 > 0) (*noteOn)++;
            if (kind == 0x80 || (kind == 0x90 && data2 == 0)) (*noteOff)++;
        }
    }
}

@interface MIDIWriterTests : XCTestCase
@end

@implementation MIDIWriterTests

- (Song *)testSong {
    Song *song = [Song defaultSong];
    song.title = @"MIDI Test";
    song.tempo = 120;
    [song.tracks[0].notes addObject:[NoteEvent noteWithPitch:69 startTick:0 durationTicks:240 velocity:100]];
    [song.tracks[0].notes addObject:[NoteEvent noteWithPitch:72 startTick:480 durationTicks:240 velocity:90]];
    [song.tracks[2].notes addObject:[NoteEvent noteWithPitch:36 startTick:0 durationTicks:480 velocity:110]];
    [song.tracks[3].notes addObject:[NoteEvent noteWithPitch:48 startTick:240 durationTicks:120 velocity:80]];
    return song;
}

- (void)testMIDIHeaderAndChunks {
    Song *song = [self testSong];
    NSData *data = [MIDIWriter dataForSong:song audibleOnly:NO];
    XCTAssertGreaterThan(data.length, 30);

    const uint8_t *bytes = data.bytes;
    XCTAssertEqual(memcmp(bytes, "MThd", 4), 0);
    uint32_t headerLength = ((uint32_t)bytes[4] << 24) | ((uint32_t)bytes[5] << 16) | ((uint32_t)bytes[6] << 8) | bytes[7];
    XCTAssertEqual(headerLength, 6);
    uint16_t format = (uint16_t)((bytes[8] << 8) | bytes[9]);
    uint16_t trackCount = (uint16_t)((bytes[10] << 8) | bytes[11]);
    uint16_t division = (uint16_t)((bytes[12] << 8) | bytes[13]);
    XCTAssertEqual(format, 1);
    XCTAssertEqual(trackCount, song.tracks.count + 1);
    XCTAssertEqual(division, 480);

    NSUInteger offset = 14;
    NSInteger chunks = 0;
    NSInteger noteOn = 0;
    NSInteger noteOff = 0;
    while (offset + 8 <= data.length) {
        if (memcmp(bytes + offset, "MTrk", 4) != 0) break;
        uint32_t length = ((uint32_t)bytes[offset + 4] << 24) | ((uint32_t)bytes[offset + 5] << 16) |
                          ((uint32_t)bytes[offset + 6] << 8) | bytes[offset + 7];
        offset += 8;
        if (offset + length > data.length) break;
        if (chunks > 0) {
            CountTrackEvents(data, offset, length, &noteOn, &noteOff);
        }
        offset += length;
        chunks++;
    }
    XCTAssertEqual((NSUInteger)chunks, song.tracks.count + 1);
    XCTAssertEqual(noteOn, 4);
    XCTAssertEqual(noteOff, 4);
}

- (void)testMIDITempoAndTrackNames {
    Song *song = [self testSong];
    NSData *data = [MIDIWriter dataForSong:song audibleOnly:NO];
    const uint8_t *bytes = data.bytes;
    BOOL foundTempo = NO;
    for (NSUInteger i = 0; i + 5 < data.length; i++) {
        if (bytes[i] == 0xFF && bytes[i + 1] == 0x51 && bytes[i + 2] == 0x03) {
            uint32_t micros = ((uint32_t)bytes[i + 3] << 16) | ((uint32_t)bytes[i + 4] << 8) | bytes[i + 5];
            XCTAssertEqual(micros, 500000);
            foundTempo = YES;
            break;
        }
    }
    XCTAssertTrue(foundTempo);
    NSString *text = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    XCTAssertTrue([text containsString:@"Pulse 1"]);
    XCTAssertTrue([text containsString:@"Noise"]);
}

- (void)testAudibleOnlyRespectsMute {
    Song *song = [self testSong];
    song.tracks[1].muted = YES;
    NSData *all = [MIDIWriter dataForSong:song audibleOnly:NO];
    NSData *audible = [MIDIWriter dataForSong:song audibleOnly:YES];
    XCTAssertLessThan(audible.length, all.length);
    const uint8_t *allBytes = all.bytes;
    const uint8_t *audibleBytes = audible.bytes;
    uint16_t allTracks = (uint16_t)((allBytes[10] << 8) | allBytes[11]);
    uint16_t audibleTracks = (uint16_t)((audibleBytes[10] << 8) | audibleBytes[11]);
    XCTAssertEqual(allTracks, song.tracks.count + 1);
    XCTAssertEqual(audibleTracks, song.tracks.count);
}

@end
