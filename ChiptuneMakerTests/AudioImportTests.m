#import <XCTest/XCTest.h>
#import <AVFoundation/AVFoundation.h>
#import "AudioImportService.h"
#import "ExportService.h"
#import "SongDocument.h"
#import "Song.h"
#import "SongSection.h"
#import "Track.h"
#import "NoteEvent.h"

@interface AudioImportTests : XCTestCase
@property (nonatomic, strong) NSMutableArray<NSURL *> *temporaryURLs;
@end

@implementation AudioImportTests

- (void)setUp {
    [super setUp];
    self.temporaryURLs = [NSMutableArray array];
}

- (void)tearDown {
    for (NSURL *url in self.temporaryURLs) {
        [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
    }
    self.temporaryURLs = nil;
    [super tearDown];
}

- (NSURL *)temporaryURLWithExtension:(NSString *)extension {
    NSString *name = [NSString stringWithFormat:@"audio-import-test-%@.%@", [[NSUUID UUID] UUIDString], extension];
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
    [self.temporaryURLs addObject:url];
    return url;
}

- (NSURL *)writeWAVWithFrequencies:(NSArray<NSNumber *> *)frequencies
                         durations:(NSArray<NSNumber *> *)durations
                        sampleRate:(double)sampleRate
                          channels:(AVAudioChannelCount)channels
                         amplitude:(float)amplitude {
    XCTAssertEqual(frequencies.count, durations.count);
    if (frequencies.count != durations.count || frequencies.count == 0) return nil;

    NSURL *url = [self temporaryURLWithExtension:@"wav"];
    NSUInteger totalFrames = 0;
    for (NSNumber *duration in durations) {
        totalFrames += (NSUInteger)llround(duration.doubleValue * sampleRate);
    }
    if (totalFrames == 0) return nil;

    __block BOOL wrote = NO;
    @autoreleasepool {
        AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:sampleRate channels:channels];
        NSError *error = nil;
        AVAudioFile *file = [[AVAudioFile alloc] initForWriting:url settings:format.settings error:&error];
        if (!file) return nil;
        AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:(AVAudioFrameCount)totalFrames];
        if (!buffer) return nil;
        buffer.frameLength = (AVAudioFrameCount)totalFrames;

        NSUInteger offset = 0;
        for (NSUInteger noteIndex = 0; noteIndex < frequencies.count; noteIndex++) {
            double frequency = frequencies[noteIndex].doubleValue;
            NSUInteger frames = (NSUInteger)llround(durations[noteIndex].doubleValue * sampleRate);
            const double twoPi = M_PI * 2.0;
            for (AVAudioChannelCount channel = 0; channel < channels; channel++) {
                float *samples = buffer.floatChannelData[channel];
                for (NSUInteger i = 0; i < frames; i++) {
                    double phase = twoPi * frequency * (double)i / sampleRate;
                    samples[offset + i] = frequency > 0.0 ? amplitude * (float)sin(phase) : 0.0f;
                }
            }
            offset += frames;
        }
        wrote = [file writeFromBuffer:buffer error:&error];
    }
    return wrote ? url : nil;
}

- (NSURL *)transcodeURL:(NSURL *)inputURL
              extension:(NSString *)extension
             executable:(NSString *)executable
              arguments:(NSArray<NSString *> *)arguments {
    if (executable.length == 0 || ![[NSFileManager defaultManager] isExecutableFileAtPath:executable]) return nil;
    NSURL *outputURL = [self temporaryURLWithExtension:extension];
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = executable;
    NSMutableArray<NSString *> *fullArguments = [NSMutableArray arrayWithArray:arguments];
    [fullArguments addObject:outputURL.path];
    task.arguments = fullArguments;
    task.standardOutput = [NSFileHandle fileHandleWithNullDevice];
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *exception) {
        return nil;
    }
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:outputURL.path error:NULL];
    if (task.terminationStatus != 0 || [attributes[NSFileSize] unsignedLongLongValue] == 0) return nil;
    return outputURL;
}

- (NSURL *)makeFLACFromWAV:(NSURL *)wavURL {
    return [self transcodeURL:wavURL
                    extension:@"flac"
                   executable:@"/usr/bin/afconvert"
                    arguments:@[@"-f", @"flac", @"-d", @"flac", wavURL.path]];
}

- (NSURL *)makeMP3FromWAV:(NSURL *)wavURL {
    NSString *lame = [ExportService lameExecutablePath];
    if (lame.length == 0) return nil;
    return [self transcodeURL:wavURL
                    extension:@"mp3"
                   executable:lame
                    arguments:@[@"--silent", wavURL.path]];
}

- (NSURL *)makeOGGFromWAV:(NSURL *)wavURL {
    NSString *ffmpeg = [AudioImportService ffmpegExecutablePath];
    if (ffmpeg.length == 0) return nil;
    NSURL *output = [self transcodeURL:wavURL
                             extension:@"ogg"
                            executable:ffmpeg
                             arguments:@[@"-v", @"error", @"-y", @"-i", wavURL.path, @"-c:a", @"libopus"]];
    if (output) return output;
    return [self transcodeURL:wavURL
                    extension:@"ogg"
                   executable:ffmpeg
                    arguments:@[@"-v", @"error", @"-y", @"-i", wavURL.path, @"-c:a", @"vorbis", @"-strict", @"-2"]];
}

- (NSURL *)writeMixedArrangementWAV {
    const double sampleRate = 44100.0;
    const double duration = 2.0;
    NSUInteger totalFrames = (NSUInteger)llround(duration * sampleRate);
    NSURL *url = [self temporaryURLWithExtension:@"wav"];

    NSArray<NSArray<NSNumber *> *> *leadNotes = @[
        @[@523.25, @0.0, @0.45],
        @[@659.25, @0.5, @0.45],
        @[@783.99, @1.0, @0.45],
        @[@1046.50, @1.5, @0.45]
    ];
    NSArray<NSArray<NSNumber *> *> *bassNotes = @[
        @[@65.41, @0.0, @0.95],
        @[@98.00, @1.0, @0.95]
    ];
    NSArray<NSNumber *> *kickTimes = @[@0.0, @1.0];
    NSArray<NSNumber *> *snareTimes = @[@0.5, @1.5];
    NSArray<NSNumber *> *hatTimes = @[@0.25, @0.75, @1.25, @1.75];
    uint32_t noiseState = 0x12345678u;

    __block BOOL wrote = NO;
    @autoreleasepool {
        AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:sampleRate channels:1];
        NSError *error = nil;
        AVAudioFile *file = [[AVAudioFile alloc] initForWriting:url settings:format.settings error:&error];
        if (!file) return nil;
        AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:(AVAudioFrameCount)totalFrames];
        if (!buffer) return nil;
        buffer.frameLength = (AVAudioFrameCount)totalFrames;
        float *samples = buffer.floatChannelData[0];

        for (NSUInteger i = 0; i < totalFrames; i++) {
            double time = (double)i / sampleRate;
            double value = 0.0;

            for (NSArray<NSNumber *> *note in leadNotes) {
                double frequency = note[0].doubleValue;
                double start = note[1].doubleValue;
                double noteDuration = note[2].doubleValue;
                if (time < start || time >= start + noteDuration) continue;
                double local = time - start;
                double envelope = MIN(1.0, local / 0.01) * MIN(1.0, (noteDuration - local) / 0.03);
                value += 0.18 * envelope * sin(2.0 * M_PI * frequency * local);
            }
            for (NSArray<NSNumber *> *note in bassNotes) {
                double frequency = note[0].doubleValue;
                double start = note[1].doubleValue;
                double noteDuration = note[2].doubleValue;
                if (time < start || time >= start + noteDuration) continue;
                double local = time - start;
                double envelope = MIN(1.0, local / 0.01) * MIN(1.0, (noteDuration - local) / 0.03);
                value += 0.32 * envelope * sin(2.0 * M_PI * frequency * local);
            }
            for (NSNumber *kick in kickTimes) {
                double local = time - kick.doubleValue;
                if (local < 0.0 || local >= 0.16) continue;
                value += 0.45 * exp(-local / 0.045) * sin(2.0 * M_PI * 58.0 * local);
            }
            for (NSNumber *snare in snareTimes) {
                double local = time - snare.doubleValue;
                if (local < 0.0 || local >= 0.14) continue;
                noiseState = noiseState * 1664525u + 1013904223u;
                double noise = ((double)(noiseState >> 8) / 16777216.0) * 2.0 - 1.0;
                value += 0.32 * exp(-local / 0.05) * noise;
            }
            for (NSNumber *hat in hatTimes) {
                double local = time - hat.doubleValue;
                if (local < 0.0 || local >= 0.08) continue;
                noiseState = noiseState * 1664525u + 1013904223u;
                double noise = ((double)(noiseState >> 8) / 16777216.0) * 2.0 - 1.0;
                double highNoise = (i % 2 == 0) ? noise : -noise;
                value += 0.14 * exp(-local / 0.018) * highNoise;
            }

            samples[i] = (float)MAX(-1.0, MIN(1.0, value));
        }
        wrote = [file writeFromBuffer:buffer error:&error];
    }
    return wrote ? url : nil;
}

- (NSURL *)writeBassLineWAV {
    return [self writeWAVWithFrequencies:@[@65.41, @98.00]
                               durations:@[@1.0, @1.0]
                              sampleRate:44100
                                channels:1
                               amplitude:0.4f];
}

- (void)testTranscribesMixedAudioIntoArrangementParts {
    NSURL *url = [self writeMixedArrangementWAV];
    XCTAssertNotNil(url);

    NSError *error = nil;
    AudioImportResult *result = [AudioImportService transcribeAudioAtURL:url
                                                                    song:[Song defaultSong]
                                                                 options:[AudioImportOptions defaultOptions]
                                                                   error:&error];
    XCTAssertNotNil(result, @"%@", error);
    XCTAssertNil(error);
    XCTAssertGreaterThanOrEqual(result.parts.count, 3, @"Expected lead, bass, and drums, got %@", result.parts);

    NSMutableDictionary<NSNumber *, AudioImportPart *> *partsByRole = [NSMutableDictionary dictionary];
    for (AudioImportPart *part in result.parts) {
        XCTAssertGreaterThan(part.notes.count, 0);
        partsByRole[@(part.role)] = part;
    }
    AudioImportPart *lead = partsByRole[@(AudioImportPartRoleLead)];
    AudioImportPart *bass = partsByRole[@(AudioImportPartRoleBass)];
    AudioImportPart *drums = partsByRole[@(AudioImportPartRoleDrums)];
    AudioImportPart *harmony = partsByRole[@(AudioImportPartRoleHarmony)];

    XCTAssertNotNil(lead);
    XCTAssertNotNil(bass);
    XCTAssertNotNil(drums);
    XCTAssertNotNil(harmony);
    XCTAssertEqual(lead.instrument, ChipInstrumentPulse25);
    XCTAssertEqual(bass.instrument, ChipInstrumentTriangle);
    XCTAssertEqual(drums.instrument, ChipInstrumentNoise);
    XCTAssertEqual(harmony.instrument, ChipInstrumentPulse12);
    XCTAssertEqualObjects(result.notes, lead.notes);

    bool foundLeadPitch = false;
    for (NoteEvent *note in lead.notes) {
        if (note.pitch == 72 || note.pitch == 76 || note.pitch == 79 || note.pitch == 84) foundLeadPitch = true;
        XCTAssertGreaterThan(note.durationTicks, 0);
        XCTAssertGreaterThan(note.velocity, 0);
        XCTAssertLessThanOrEqual(note.velocity, 127);
    }
    XCTAssertTrue(foundLeadPitch, @"Expected the lead melody in %@", lead.notes);

    for (NoteEvent *note in bass.notes) {
        XCTAssertGreaterThanOrEqual(note.pitch, 33);
        XCTAssertLessThanOrEqual(note.pitch, 55);
    }
    for (NoteEvent *note in drums.notes) {
        XCTAssertTrue(note.pitch == 36 || note.pitch == 48 || note.pitch == 72, @"Unexpected drum pitch %ld", (long)note.pitch);
        XCTAssertGreaterThan(note.durationTicks, 0);
    }
}

- (void)testTranscribesBassLineToBassPartWithoutLead {
    NSURL *url = [self writeBassLineWAV];
    XCTAssertNotNil(url);

    NSError *error = nil;
    AudioImportResult *result = [AudioImportService transcribeAudioAtURL:url
                                                                    song:[Song defaultSong]
                                                                 options:[AudioImportOptions defaultOptions]
                                                                   error:&error];
    XCTAssertNotNil(result, @"%@", error);
    AudioImportPart *bass = nil;
    for (AudioImportPart *part in result.parts) {
        if (part.role == AudioImportPartRoleBass) bass = part;
    }
    XCTAssertNotNil(bass, @"Expected a bass part, got %@", result.parts);
    XCTAssertGreaterThan(bass.notes.count, 0);
    XCTAssertTrue(result.notes.count == 0, @"A bass-only recording should not produce a lead line: %@", result.notes);
}

- (AudioImportPart *)partWithRole:(AudioImportPartRole)role
                        instrument:(ChipInstrument)instrument
                           pitches:(NSArray<NSNumber *> *)pitches {
    NSArray<NSString *> *names = @[@"Lead", @"Harmony", @"Bass", @"Drums"];
    AudioImportPart *part = [[AudioImportPart alloc] init];
    part.role = role;
    part.name = names[(NSUInteger)role];
    part.instrument = instrument;
    NSMutableArray<NoteEvent *> *notes = [NSMutableArray array];
    for (NSUInteger i = 0; i < pitches.count; i++) {
        [notes addObject:[NoteEvent noteWithPitch:pitches[i].integerValue
                                        startTick:i * 120
                                    durationTicks:120
                                         velocity:90]];
    }
    part.notes = notes;
    return part;
}

- (NSArray<AudioImportPart *> *)fourPartArrangement {
    return @[
        [self partWithRole:AudioImportPartRoleLead instrument:ChipInstrumentPulse25 pitches:@[@72, @74]],
        [self partWithRole:AudioImportPartRoleBass instrument:ChipInstrumentTriangle pitches:@[@36, @43]],
        [self partWithRole:AudioImportPartRoleDrums instrument:ChipInstrumentNoise pitches:@[@36, @48]],
        [self partWithRole:AudioImportPartRoleHarmony instrument:ChipInstrumentPulse12 pitches:@[@60, @64]]
    ];
}

- (void)testStartTickForAppendingToSongUsesLatestNoteOrPlayhead {
    Song *song = [Song defaultSong];
    XCTAssertEqual([AudioImportService startTickForAppendingToSong:song playheadTick:250], 240);

    [song.tracks[0].notes addObject:[NoteEvent noteWithPitch:60 startTick:0 durationTicks:480 velocity:100]];
    [song.tracks[2].notes addObject:[NoteEvent noteWithPitch:48 startTick:480 durationTicks:360 velocity:100]];
    XCTAssertEqual([AudioImportService startTickForAppendingToSong:song playheadTick:0], 840);
}

- (void)testAppendPartsCreatesTracksAtCommonStartTick {
    Song *song = [Song defaultSong];
    NSArray<AudioImportPart *> *parts = [self fourPartArrangement];
    NSError *error = nil;
    XCTAssertTrue([AudioImportService appendParts:parts toSong:song startTick:480 baseName:@"Demo" error:&error], @"%@", error);
    XCTAssertEqual(song.tracks.count, 8);
    XCTAssertTrue([song validateWithError:&error], @"%@", error);

    NSArray<NSString *> *expectedNames = @[@"Demo Lead", @"Demo Bass", @"Demo Drums", @"Demo Harmony"];
    NSArray<NSNumber *> *expectedInstruments = @[@(ChipInstrumentPulse25), @(ChipInstrumentTriangle),
                                                 @(ChipInstrumentNoise), @(ChipInstrumentPulse12)];
    for (NSUInteger i = 0; i < parts.count; i++) {
        Track *track = song.tracks[4 + i];
        XCTAssertEqualObjects(track.name, expectedNames[i]);
        XCTAssertEqual(track.instrument, expectedInstruments[i].integerValue);
        XCTAssertEqual(track.notes.count, parts[i].notes.count);
        XCTAssertEqual(track.notes.firstObject.startTick, 480);
        XCTAssertLessThanOrEqual(track.volume, 1.0);
    }
}

- (void)testAppendPartsGrowsSongAndSections {
    Song *song = [Song defaultSong];
    song.lengthBars = 1;
    song.sections = [@[[SongSection sectionWithName:@"Main" startBar:0 lengthBars:1]] mutableCopy];
    AudioImportPart *lead = [self partWithRole:AudioImportPartRoleLead instrument:ChipInstrumentPulse25 pitches:@[@72]];
    lead.notes = @[[NoteEvent noteWithPitch:72 startTick:0 durationTicks:4000 velocity:90]];

    NSError *error = nil;
    XCTAssertTrue([AudioImportService appendParts:@[lead] toSong:song startTick:480 baseName:@"Long" error:&error], @"%@", error);
    XCTAssertEqual(song.lengthBars, 3);
    XCTAssertEqual(song.sections.count, 2);
    XCTAssertEqualObjects(song.sections.lastObject.name, @"Imported Audio");
    XCTAssertEqual(song.tracks.lastObject.notes.firstObject.startTick, 480);
    XCTAssertTrue([song validateWithError:&error], @"%@", error);
}

- (void)testAppendPartsRejectsNinthTrackWithoutMutatingSong {
    Song *song = [Song defaultSong];
    for (NSInteger i = 0; i < 4; i++) {
        [song.tracks addObject:[Track trackWithName:[NSString stringWithFormat:@"Extra %ld", (long)i]
                                        instrument:ChipInstrumentPulse50]];
    }
    XCTAssertEqual(song.tracks.count, 8);

    NSError *error = nil;
    XCTAssertFalse([AudioImportService appendParts:[self fourPartArrangement] toSong:song startTick:0 baseName:@"Demo" error:&error]);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, AudioImportErrorDomain);
    XCTAssertEqual(song.tracks.count, 8);
    XCTAssertEqual(song.lengthBars, 4);
}

- (void)testAppendPartsRejectsSongBeyondBarLimitWithoutMutation {
    Song *song = [Song defaultSong];
    AudioImportPart *lead = [self partWithRole:AudioImportPartRoleLead instrument:ChipInstrumentPulse25 pitches:@[@72]];
    lead.notes = @[[NoteEvent noteWithPitch:72 startTick:0 durationTicks:1920ULL * 300ULL velocity:90]];

    NSError *error = nil;
    XCTAssertFalse([AudioImportService appendParts:@[lead] toSong:song startTick:0 baseName:@"Too Long" error:&error]);
    XCTAssertNotNil(error);
    XCTAssertEqual(song.tracks.count, 4);
    XCTAssertEqual(song.lengthBars, 4);
    XCTAssertEqual(song.sections.count, 1);
}

- (void)testArrangementImportIsSingleUndoableDocumentEdit {
    SongDocument *document = [[SongDocument alloc] init];
    document.song = [Song defaultSong];

    NSArray<AudioImportPart *> *parts = [self fourPartArrangement];
    [document performEditNamed:@"Import Audio as Chiptune" block:^(Song *edited) {
        NSError *error = nil;
        XCTAssertTrue([AudioImportService appendParts:parts toSong:edited startTick:0 baseName:@"Undo" error:&error], @"%@", error);
    }];

    XCTAssertEqual(document.song.tracks.count, 8);
    XCTAssertTrue(document.isDocumentEdited);
    [document.undoManager undo];
    XCTAssertEqual(document.song.tracks.count, 4);
    XCTAssertEqualObjects(document.song.tracks.lastObject.name, @"Noise");
}

- (void)testSupportedFileExtensionsAndContentTypes {
    NSArray<NSString *> *expected = @[@"flac", @"wav", @"ogg", @"mp3"];
    XCTAssertEqualObjects([AudioImportService supportedFileExtensions], expected);

    NSArray<UTType *> *types = [AudioImportService supportedContentTypes];
    XCTAssertEqual(types.count, expected.count);
    NSMutableSet<NSString *> *extensions = [NSMutableSet set];
    for (UTType *type in types) {
        if (type.preferredFilenameExtension.length > 0) {
            [extensions addObject:type.preferredFilenameExtension.lowercaseString];
        }
    }
    for (NSString *extension in expected) {
        XCTAssertTrue([extensions containsObject:extension], @"Missing UTType for .%@", extension);
    }
}

- (void)testTranscribesSineMelodyFromWAV {
    NSURL *url = [self writeWAVWithFrequencies:@[@440.0, @523.25]
                                     durations:@[@0.5, @0.5]
                                    sampleRate:44100
                                      channels:1
                                     amplitude:0.3f];
    XCTAssertNotNil(url);

    Song *song = [Song defaultSong];
    NSError *error = nil;
    AudioImportResult *result = [AudioImportService transcribeAudioAtURL:url
                                                                    song:song
                                                                 options:[AudioImportOptions defaultOptions]
                                                                   error:&error];
    XCTAssertNotNil(result, @"%@", error);
    XCTAssertNil(error);

    NoteEvent *a4 = nil;
    NoteEvent *c5 = nil;
    uint64_t previousEnd = 0;
    for (NoteEvent *note in result.notes) {
        XCTAssertGreaterThanOrEqual(note.startTick, previousEnd, @"Imported notes should be monophonic");
        previousEnd = note.startTick + note.durationTicks;
        if (note.pitch == 69 && !a4) a4 = note;
        if (note.pitch == 72 && !c5) c5 = note;
    }

    XCTAssertNotNil(a4, @"Expected A4 (MIDI 69) in %@", result.notes);
    XCTAssertNotNil(c5, @"Expected C5 (MIDI 72) in %@", result.notes);
    XCTAssertLessThanOrEqual(a4.startTick, 120);
    XCTAssertGreaterThanOrEqual(a4.durationTicks, 120);
    XCTAssertGreaterThan(c5.startTick, a4.startTick);
    XCTAssertLessThanOrEqual(c5.startTick, 600);
    XCTAssertGreaterThanOrEqual(c5.durationTicks, 120);
    XCTAssertGreaterThan(a4.velocity, 0);
    XCTAssertLessThanOrEqual(a4.velocity, 127);
}

- (void)testTranscribesStereo48kAudio {
    NSURL *url = [self writeWAVWithFrequencies:@[@440.0]
                                     durations:@[@0.5]
                                    sampleRate:48000
                                      channels:2
                                     amplitude:0.25f];
    XCTAssertNotNil(url);

    NSError *error = nil;
    AudioImportResult *result = [AudioImportService transcribeAudioAtURL:url
                                                                    song:[Song defaultSong]
                                                                 options:[AudioImportOptions defaultOptions]
                                                                   error:&error];
    XCTAssertNotNil(result, @"%@", error);
    bool found = false;
    for (NoteEvent *note in result.notes) {
        if (note.pitch == 69) found = true;
    }
    XCTAssertTrue(found, @"Expected A4 from stereo 48 kHz audio, got %@", result.notes);
    XCTAssertEqualWithAccuracy(result.sourceSampleRate, 48000, 0.1);
    XCTAssertEqual(result.sourceChannelCount, 2);
}

- (void)testSilenceProducesNoNotes {
    NSURL *url = [self writeWAVWithFrequencies:@[@0.0]
                                     durations:@[@1.0]
                                    sampleRate:44100
                                      channels:1
                                     amplitude:0.0f];
    XCTAssertNotNil(url);

    NSError *error = nil;
    AudioImportResult *result = [AudioImportService transcribeAudioAtURL:url
                                                                    song:[Song defaultSong]
                                                                 options:[AudioImportOptions defaultOptions]
                                                                   error:&error];
    XCTAssertNotNil(result);
    XCTAssertNil(error);
    XCTAssertEqual(result.notes.count, 0);
}

- (void)testMissingFileReturnsClearError {
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"does-not-exist-audio.wav"]];
    NSError *error = nil;
    AudioImportResult *result = [AudioImportService transcribeAudioAtURL:url
                                                                    song:[Song defaultSong]
                                                                 options:[AudioImportOptions defaultOptions]
                                                                   error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, AudioImportErrorDomain);
}

- (void)testStartTickUsesTrackEndOrPlayhead {
    Song *song = [Song defaultSong];
    Track *track = song.tracks[0];
    [track.notes removeAllObjects];
    [track.notes addObject:[NoteEvent noteWithPitch:60 startTick:0 durationTicks:480 velocity:100]];

    XCTAssertEqual([AudioImportService startTickForAppendingToTrack:track song:song playheadTick:0], 480);

    [track.notes removeAllObjects];
    XCTAssertEqual([AudioImportService startTickForAppendingToTrack:track song:song playheadTick:250], 240);
    XCTAssertEqual([AudioImportService startTickForAppendingToTrack:nil song:song playheadTick:250], 240);
}

- (void)testAppendQuantizesNotesAfterExistingContent {
    Song *song = [Song defaultSong];
    [song.tracks[0].notes removeAllObjects];
    [song.tracks[0].notes addObject:[NoteEvent noteWithPitch:60 startTick:0 durationTicks:480 velocity:100]];

    NSArray<NoteEvent *> *notes = @[
        [NoteEvent noteWithPitch:72 startTick:0 durationTicks:240 velocity:90],
        [NoteEvent noteWithPitch:74 startTick:240 durationTicks:240 velocity:90]
    ];
    NSError *error = nil;
    XCTAssertTrue([AudioImportService appendNotes:notes toSong:song trackIndex:0 startTick:480 error:&error], @"%@", error);
    XCTAssertEqual(song.tracks[0].notes.count, 3);
    XCTAssertEqual([song.tracks[0] noteStartingAtTick:480 tolerance:1].pitch, 72);
    XCTAssertEqual([song.tracks[0] noteStartingAtTick:720 tolerance:1].pitch, 74);
    XCTAssertTrue([song validateWithError:&error], @"%@", error);
}

- (void)testAppendExtendsSongAndSections {
    Song *song = [Song defaultSong];
    song.lengthBars = 1;
    song.sections = [@[[SongSection sectionWithName:@"Main" startBar:0 lengthBars:1]] mutableCopy];
    [song.tracks[0].notes removeAllObjects];

    NSArray<NoteEvent *> *notes = @[
        [NoteEvent noteWithPitch:72 startTick:0 durationTicks:4800 velocity:90]
    ];
    NSError *error = nil;
    XCTAssertTrue([AudioImportService appendNotes:notes toSong:song trackIndex:0 startTick:0 error:&error], @"%@", error);
    XCTAssertEqual(song.lengthBars, 3);
    XCTAssertEqual(song.sections.count, 2);
    XCTAssertEqualObjects(song.sections.lastObject.name, @"Imported Audio");
    XCTAssertEqual(song.sections.lastObject.startBar, 1);
    XCTAssertEqual(song.sections.lastObject.lengthBars, 2);
    XCTAssertTrue([song validateWithError:&error], @"%@", error);
}

- (void)testAppendRejectsMelodyBeyondSongLimit {
    Song *song = [Song defaultSong];
    NSUInteger before = song.tracks[0].notes.count;
    NSArray<NoteEvent *> *notes = @[
        [NoteEvent noteWithPitch:72 startTick:0 durationTicks:1920ULL * 300ULL velocity:90]
    ];
    NSError *error = nil;
    XCTAssertFalse([AudioImportService appendNotes:notes toSong:song trackIndex:0 startTick:0 error:&error]);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, AudioImportErrorDomain);
    XCTAssertEqual(song.tracks[0].notes.count, before);
    XCTAssertEqual(song.lengthBars, 4);
}

- (void)testImportIsSingleUndoableDocumentEdit {
    SongDocument *document = [[SongDocument alloc] init];
    Song *song = [Song defaultSong];
    [song.tracks[0].notes removeAllObjects];
    document.song = song;

    NSArray<NoteEvent *> *notes = @[
        [NoteEvent noteWithPitch:72 startTick:0 durationTicks:240 velocity:90],
        [NoteEvent noteWithPitch:74 startTick:240 durationTicks:240 velocity:90]
    ];
    [document performEditNamed:@"Import Audio as Chiptune" block:^(Song *edited) {
        NSError *error = nil;
        XCTAssertTrue([AudioImportService appendNotes:notes toSong:edited trackIndex:0 startTick:0 error:&error], @"%@", error);
    }];

    XCTAssertEqual(document.song.tracks[0].notes.count, 2);
    XCTAssertTrue(document.isDocumentEdited);
    [document.undoManager undo];
    XCTAssertEqual(document.song.tracks[0].notes.count, 0);
}

- (void)testDecodesFLAC {
    NSURL *wavURL = [self writeWAVWithFrequencies:@[@440.0]
                                        durations:@[@0.5]
                                       sampleRate:44100
                                         channels:1
                                        amplitude:0.3f];
    XCTAssertNotNil(wavURL);
    NSURL *flacURL = [self makeFLACFromWAV:wavURL];
    XCTAssertNotNil(flacURL, @"afconvert should create a FLAC fixture");

    NSError *error = nil;
    AudioImportResult *result = [AudioImportService transcribeAudioAtURL:flacURL
                                                                    song:[Song defaultSong]
                                                                 options:[AudioImportOptions defaultOptions]
                                                                   error:&error];
    XCTAssertNotNil(result, @"%@", error);
    XCTAssertGreaterThan(result.notes.count, 0);
}

- (void)testDecodesMP3WhenLAMEIsAvailable {
    if ([ExportService lameExecutablePath] == nil) {
        XCTSkip(@"LAME is not installed; skipping MP3 import test.");
    }
    NSURL *wavURL = [self writeWAVWithFrequencies:@[@440.0]
                                        durations:@[@0.6]
                                       sampleRate:44100
                                         channels:1
                                        amplitude:0.3f];
    XCTAssertNotNil(wavURL);
    NSURL *mp3URL = [self makeMP3FromWAV:wavURL];
    XCTAssertNotNil(mp3URL);

    NSError *error = nil;
    AudioImportResult *result = [AudioImportService transcribeAudioAtURL:mp3URL
                                                                    song:[Song defaultSong]
                                                                 options:[AudioImportOptions defaultOptions]
                                                                   error:&error];
    XCTAssertNotNil(result, @"%@", error);
    XCTAssertGreaterThan(result.notes.count, 0);
}

- (void)testDecodesOggWhenFFmpegIsAvailable {
    if ([AudioImportService ffmpegExecutablePath] == nil) {
        XCTSkip(@"ffmpeg is not installed; skipping Ogg import test.");
    }
    NSURL *wavURL = [self writeWAVWithFrequencies:@[@440.0]
                                        durations:@[@0.6]
                                       sampleRate:44100
                                         channels:1
                                        amplitude:0.3f];
    XCTAssertNotNil(wavURL);
    NSURL *oggURL = [self makeOGGFromWAV:wavURL];
    if (!oggURL) {
        XCTSkip(@"ffmpeg could not create an Ogg fixture.");
    }

    NSError *error = nil;
    AudioImportResult *result = [AudioImportService transcribeAudioAtURL:oggURL
                                                                    song:[Song defaultSong]
                                                                 options:[AudioImportOptions defaultOptions]
                                                                   error:&error];
    XCTAssertNotNil(result, @"%@", error);
    XCTAssertGreaterThan(result.notes.count, 0);
}

@end
