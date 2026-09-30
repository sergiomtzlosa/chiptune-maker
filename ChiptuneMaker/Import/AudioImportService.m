#import "AudioImportService.h"
#import "Song.h"
#import "Track.h"
#import "NoteEvent.h"
#import "SongSection.h"
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <math.h>
#include <stdbool.h>

NSErrorDomain const AudioImportErrorDomain = @"ChiptuneMaker.AudioImport";

static const double AudioImportAnalysisSampleRate = 11025.0;
static const double AudioImportMaxSeconds = 300.0;
static const NSUInteger AudioImportMaxSegmentNotes = 5000;
static const NSUInteger AudioImportMaxLeadNotes = 3000;
static const NSUInteger AudioImportMaxBassNotes = 2000;
static const NSUInteger AudioImportMaxHarmonyNotes = 3000;
static const NSUInteger AudioImportMaxDrumNotes = 4000;

static const NSInteger AudioImportLeadLowPitch = 48;
static const NSInteger AudioImportLeadHighPitch = 100;
static const NSInteger AudioImportBassLowPitch = 33;
static const NSInteger AudioImportBassHighPitch = 55;
static const NSInteger AudioImportHarmonyLowPitch = 48;
static const NSInteger AudioImportHarmonyHighPitch = 84;

static NSError *AudioImportError(AudioImportErrorCode code, NSString *message) {
    return [NSError errorWithDomain:AudioImportErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static double AudioImportClamp(double value, double low, double high) {
    return MIN(MAX(value, low), high);
}

static double AudioImportRMS(const float *samples, NSUInteger count) {
    if (!samples || count == 0) return 0.0;
    double sum = 0.0;
    for (NSUInteger i = 0; i < count; i++) {
        double value = samples[i];
        sum += value * value;
    }
    return sqrt(sum / (double)count);
}

#pragma mark - Analysis structures

typedef struct {
    double time;
    double midi;
    double confidence;
    double rms;
    bool voiced;
} AudioPitchFrame;

typedef struct {
    double startTime;
    double endTime;
    double midi;
    double rms;
} AudioNoteSegment;

typedef struct {
    double time;
    double strength;
    double lowRatio;
    double highRatio;
} AudioDrumOnset;

@interface AudioImportDecodedAudio : NSObject
@property (nonatomic, strong) NSMutableData *monoData;
@property (nonatomic, assign) double analysisSampleRate;
@property (nonatomic, assign) double sourceSampleRate;
@property (nonatomic, assign) NSInteger sourceChannelCount;
@property (nonatomic, assign) double durationSeconds;
@property (nonatomic, copy) NSString *decoderName;
@end

@implementation AudioImportDecodedAudio
@end

@implementation AudioImportPart

- (instancetype)init {
    self = [super init];
    if (self) {
        _name = @"Part";
        _instrument = ChipInstrumentPulse25;
        _notes = @[];
    }
    return self;
}

@end

@implementation AudioImportOptions

+ (instancetype)defaultOptions {
    AudioImportOptions *options = [[self alloc] init];
    options.gridTicks = 0;
    options.minimumConfidence = 0.55;
    options.minimumNoteSeconds = 0.06;
    options.lowPitch = 24;
    options.highPitch = 108;
    options.extractBass = YES;
    options.extractHarmony = YES;
    options.extractDrums = YES;
    return options;
}

@end

@implementation AudioImportResult

- (instancetype)init {
    self = [super init];
    if (self) {
        _notes = @[];
        _parts = @[];
    }
    return self;
}

@end

@implementation AudioImportService

+ (NSArray<NSString *> *)supportedFileExtensions {
    return @[@"flac", @"wav", @"ogg", @"mp3"];
}

+ (NSArray<UTType *> *)supportedContentTypes {
    NSMutableArray<UTType *> *types = [NSMutableArray array];
    for (NSString *extension in [self supportedFileExtensions]) {
        UTType *type = [UTType typeWithFilenameExtension:extension];
        if (type) [types addObject:type];
    }
    return types;
}

+ (NSString *)ffmpegExecutablePath {
    NSArray<NSString *> *candidates = @[
        @"/opt/homebrew/bin/ffmpeg",
        @"/usr/local/bin/ffmpeg",
        @"/usr/bin/ffmpeg"
    ];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    for (NSString *path in candidates) {
        if ([fileManager isExecutableFileAtPath:path]) return path;
    }
    NSString *searchPath = [NSProcessInfo processInfo].environment[@"PATH"];
    for (NSString *directory in [searchPath componentsSeparatedByString:@":"]) {
        if (directory.length == 0) continue;
        NSString *path = [directory stringByAppendingPathComponent:@"ffmpeg"];
        if ([fileManager isExecutableFileAtPath:path]) return path;
    }
    return nil;
}

#pragma mark - Public entry points

+ (AudioImportResult *)transcribeAudioAtURL:(NSURL *)url
                                       song:(Song *)song
                                    options:(AudioImportOptions *)options
                                      error:(NSError **)error {
    if (!url.isFileURL || !song) {
        if (error) *error = AudioImportError(AudioImportErrorInvalidFile, @"Choose a local audio file to import.");
        return nil;
    }
    if (![[NSFileManager defaultManager] isReadableFileAtPath:url.path]) {
        if (error) *error = AudioImportError(AudioImportErrorInvalidFile,
                                             [NSString stringWithFormat:@"Could not read “%@”.", url.lastPathComponent]);
        return nil;
    }
    AudioImportOptions *effectiveOptions = options ?: [AudioImportOptions defaultOptions];
    NSString *extension = url.pathExtension.lowercaseString;
    if (![[self supportedFileExtensions] containsObject:extension]) {
        if (error) *error = AudioImportError(AudioImportErrorUnsupportedFormat,
                                             @"Choose a FLAC, WAV, OGG, or MP3 file.");
        return nil;
    }

    NSError *decodeError = nil;
    AudioImportDecodedAudio *decoded = [self decodeAudioAtURL:url error:&decodeError];
    if (!decoded) {
        if (error) *error = decodeError ?: AudioImportError(AudioImportErrorDecodeFailed, @"Could not decode the audio file.");
        return nil;
    }

    const float *samples = decoded.monoData.bytes;
    NSUInteger sampleCount = decoded.monoData.length / sizeof(float);
    double sampleRate = decoded.analysisSampleRate;
    if (sampleCount == 0 || sampleRate <= 0) {
        if (error) *error = AudioImportError(AudioImportErrorDecodeFailed, @"The audio file contains no samples.");
        return nil;
    }

    float peak = 0.0f;
    for (NSUInteger i = 0; i < sampleCount; i++) {
        peak = MAX(peak, fabsf(samples[i]));
    }

    AudioImportResult *result = [[AudioImportResult alloc] init];
    result.durationSeconds = decoded.durationSeconds;
    result.sourceSampleRate = decoded.sourceSampleRate;
    result.sourceChannelCount = decoded.sourceChannelCount;
    result.decoderName = decoded.decoderName;

    if (peak < 0.00001f) {
        return result;
    }

    NSUInteger frameSize = MAX((NSUInteger)64, (NSUInteger)llround(sampleRate * 0.046));
    NSUInteger hopSize = MAX((NSUInteger)16, (NSUInteger)llround(sampleRate * 0.012));
    if (sampleCount < frameSize) {
        return result;
    }

    double ticksPerSecond = (double)song.ppq * song.tempo / 60.0;
    uint64_t grid = effectiveOptions.gridTicks > 0 ? effectiveOptions.gridTicks : MAX(1ULL, song.ppq / 4);
    uint64_t maxTicks = MAX(1ULL, song.ticksPerBar) * 256ULL;

    NSInteger leadLow = MAX(effectiveOptions.lowPitch, AudioImportLeadLowPitch);
    NSInteger leadHigh = MIN(effectiveOptions.highPitch, AudioImportLeadHighPitch);
    NSInteger bassLow = MAX(effectiveOptions.lowPitch, AudioImportBassLowPitch);
    NSInteger bassHigh = MIN(effectiveOptions.highPitch, AudioImportBassHighPitch);

    NSMutableArray<AudioImportPart *> *parts = [NSMutableArray array];
    NSArray<NoteEvent *> *leadNotes = @[];
    AudioNoteSegment *bassSegments = NULL;
    NSUInteger bassSegmentCount = 0;

    float *leadSamples = NULL;
    float *bassSamples = NULL;
    float *bassFilterTemp = NULL;
    AudioPitchFrame *leadFrames = NULL;
    AudioPitchFrame *bassFrames = NULL;
    AudioNoteSegment *leadSegments = NULL;
    NSUInteger leadFrameCount = 0;
    NSUInteger bassFrameCount = 0;
    NSUInteger leadSegmentCount = 0;
    NSError *conversionError = nil;
    BOOL failed = NO;

    // The lead is high-passed so a bass line does not pull the melody down an
    // octave. Two cascaded low-pass stages isolate low notes for the bass part.
    leadSamples = [self highPassedSamples:samples count:sampleCount sampleRate:sampleRate cutoff:180.0];
    if (!leadSamples) {
        conversionError = AudioImportError(AudioImportErrorDecodeFailed, @"Not enough memory to analyze the audio.");
        failed = YES;
        goto cleanup;
    }

    leadFrames = [self analyzeSamples:leadSamples
                                 count:sampleCount
                            sampleRate:sampleRate
                             frameSize:frameSize
                               hopSize:hopSize
                              lowPitch:leadLow
                             highPitch:leadHigh
                     minimumConfidence:effectiveOptions.minimumConfidence
                              outCount:&leadFrameCount];
    if (!leadFrames || leadFrameCount == 0) {
        conversionError = AudioImportError(AudioImportErrorDecodeFailed, @"Not enough memory to analyze the audio.");
        failed = YES;
        goto cleanup;
    }

    leadSegments = [self segmentsFromFrames:leadFrames
                                      count:leadFrameCount
                                 frameHalf:(double)frameSize / (2.0 * sampleRate)
                             minimumSeconds:effectiveOptions.minimumNoteSeconds
                                   maxCount:AudioImportMaxSegmentNotes
                                   outCount:&leadSegmentCount];
    if (!leadSegments) {
        conversionError = AudioImportError(AudioImportErrorDecodeFailed, @"Not enough memory to analyze the audio.");
        failed = YES;
        goto cleanup;
    }

    if (leadSegmentCount > 0 && leadHigh >= leadLow) {
        NSError *notesError = nil;
        leadNotes = [self notesFromSegments:leadSegments
                                      count:leadSegmentCount
                            ticksPerSecond:ticksPerSecond
                                      grid:grid
                                  maxTicks:maxTicks
                                  lowPitch:leadLow
                                 highPitch:leadHigh
                                 maxNotes:AudioImportMaxLeadNotes
                               monophonic:YES
                                    error:&notesError];
        if (!leadNotes) {
            conversionError = notesError;
            failed = YES;
            goto cleanup;
        }
        if (leadNotes.count > 0) {
            AudioImportPart *part = [[AudioImportPart alloc] init];
            part.role = AudioImportPartRoleLead;
            part.name = @"Lead";
            part.instrument = ChipInstrumentPulse25;
            part.notes = leadNotes;
            [parts addObject:part];
        }
    }

    if (effectiveOptions.extractBass && bassHigh >= bassLow) {
        bassSamples = [self lowPassedSamples:samples count:sampleCount sampleRate:sampleRate cutoff:180.0];
        if (bassSamples) {
            bassFilterTemp = [self lowPassedSamples:bassSamples count:sampleCount sampleRate:sampleRate cutoff:180.0];
        }
        if (bassFilterTemp) {
            double fullRms = AudioImportRMS(samples, sampleCount);
            double bassRms = AudioImportRMS(bassFilterTemp, sampleCount);
            BOOL hasLowContent = fullRms > 0.00001 && bassRms > fullRms * 0.035;
            if (hasLowContent) {
                bassFrames = [self analyzeSamples:bassFilterTemp
                                            count:sampleCount
                                       sampleRate:sampleRate
                                        frameSize:frameSize
                                          hopSize:hopSize
                                         lowPitch:bassLow
                                        highPitch:bassHigh
                                minimumConfidence:MAX(0.45, effectiveOptions.minimumConfidence - 0.05)
                                         outCount:&bassFrameCount];
                if (bassFrames && bassFrameCount > 0) {
                    bassSegments = [self segmentsFromFrames:bassFrames
                                                     count:bassFrameCount
                                                frameHalf:(double)frameSize / (2.0 * sampleRate)
                                            minimumSeconds:MAX(0.08, effectiveOptions.minimumNoteSeconds)
                                                  maxCount:AudioImportMaxSegmentNotes
                                                  outCount:&bassSegmentCount];
                }
                if (bassSegments && bassSegmentCount > 0) {
                    NSError *notesError = nil;
                    NSArray<NoteEvent *> *bassNotes = [self notesFromSegments:bassSegments
                                                                       count:bassSegmentCount
                                                             ticksPerSecond:ticksPerSecond
                                                                       grid:grid
                                                                   maxTicks:maxTicks
                                                                   lowPitch:bassLow
                                                                  highPitch:bassHigh
                                                                  maxNotes:AudioImportMaxBassNotes
                                                                monophonic:YES
                                                                     error:&notesError];
                    if (!bassNotes) {
                        conversionError = notesError;
                        failed = YES;
                        goto cleanup;
                    }
                    if (bassNotes.count > 0) {
                        AudioImportPart *part = [[AudioImportPart alloc] init];
                        part.role = AudioImportPartRoleBass;
                        part.name = @"Bass";
                        part.instrument = ChipInstrumentTriangle;
                        part.notes = bassNotes;
                        [parts addObject:part];
                    }
                }
            }
        }
    }

    if (effectiveOptions.extractDrums) {
        NSUInteger onsetCount = 0;
        AudioDrumOnset *onsets = [self drumOnsetsInSamples:samples
                                                     count:sampleCount
                                                sampleRate:sampleRate
                                                  outCount:&onsetCount];
        if (onsets && onsetCount > 0) {
            NSError *notesError = nil;
            NSArray<NoteEvent *> *drumNotes = [self notesFromDrumOnsets:onsets
                                                                  count:onsetCount
                                                         ticksPerSecond:ticksPerSecond
                                                                   grid:grid
                                                               maxTicks:maxTicks
                                                               maxNotes:AudioImportMaxDrumNotes
                                                                    error:&notesError];
            free(onsets);
            if (!drumNotes) {
                conversionError = notesError;
                failed = YES;
                goto cleanup;
            }
            if (drumNotes.count > 0) {
                AudioImportPart *part = [[AudioImportPart alloc] init];
                part.role = AudioImportPartRoleDrums;
                part.name = @"Drums";
                part.instrument = ChipInstrumentNoise;
                part.notes = drumNotes;
                [parts addObject:part];
            }
        }
    }

    if (effectiveOptions.extractHarmony && leadNotes.count > 0) {
        NSArray<NoteEvent *> *harmonyNotes = [self harmonyNotesForSong:song
                                                             leadNotes:leadNotes
                                                          bassSegments:bassSegments
                                                             bassCount:bassSegmentCount
                                                        ticksPerSecond:ticksPerSecond
                                                                  grid:grid
                                                              maxTicks:maxTicks
                                                              maxNotes:AudioImportMaxHarmonyNotes];
        if (harmonyNotes.count > 0) {
            AudioImportPart *part = [[AudioImportPart alloc] init];
            part.role = AudioImportPartRoleHarmony;
            part.name = @"Harmony";
            part.instrument = ChipInstrumentPulse12;
            part.notes = harmonyNotes;
            [parts addObject:part];
        }
    }

cleanup:
    free(leadSamples);
    free(bassSamples);
    free(bassFilterTemp);
    free(leadFrames);
    free(bassFrames);
    free(leadSegments);
    free(bassSegments);
    if (failed) {
        if (error) *error = conversionError ?: AudioImportError(AudioImportErrorDecodeFailed, @"Could not analyze the audio.");
        return nil;
    }

    result.notes = leadNotes;
    result.parts = parts;
    return result;
}

#pragma mark - Pitch analysis

+ (AudioPitchFrame *)analyzeSamples:(const float *)samples
                              count:(NSUInteger)sampleCount
                         sampleRate:(double)sampleRate
                          frameSize:(NSUInteger)frameSize
                            hopSize:(NSUInteger)hopSize
                           lowPitch:(NSInteger)lowPitch
                          highPitch:(NSInteger)highPitch
                  minimumConfidence:(double)minimumConfidence
                           outCount:(NSUInteger *)outCount {
    if (outCount) *outCount = 0;
    if (!samples || sampleCount < frameSize || frameSize < 16 || hopSize == 0) return NULL;

    NSUInteger frameCount = (sampleCount - frameSize) / hopSize + 1;
    AudioPitchFrame *frames = calloc(frameCount, sizeof(AudioPitchFrame));
    if (!frames) return NULL;

    float peak = 0.0f;
    for (NSUInteger i = 0; i < sampleCount; i++) {
        peak = MAX(peak, fabsf(samples[i]));
    }
    if (peak < 0.00001f) {
        if (outCount) *outCount = frameCount;
        return frames;
    }

    double highestFrequency = 440.0 * pow(2.0, ((double)highPitch + 0.75 - 69.0) / 12.0);
    double lowestFrequency = 440.0 * pow(2.0, ((double)lowPitch - 0.75 - 69.0) / 12.0);
    NSUInteger minLag = MAX((NSUInteger)2, (NSUInteger)floor(sampleRate / highestFrequency));
    NSUInteger maxLag = MIN(frameSize - 2, (NSUInteger)ceil(sampleRate / lowestFrequency));
    if (maxLag <= minLag + 1) {
        if (outCount) *outCount = frameCount;
        return frames;
    }

    double *correlation = calloc(maxLag + 2, sizeof(double));
    if (!correlation) {
        free(frames);
        return NULL;
    }

    double silenceThreshold = MAX(0.0005, (double)peak * 0.02);
    for (NSUInteger frameIndex = 0; frameIndex < frameCount; frameIndex++) {
        NSUInteger start = frameIndex * hopSize;
        double sum = 0.0;
        for (NSUInteger i = 0; i < frameSize; i++) sum += samples[start + i];
        double mean = sum / (double)frameSize;

        double energy = 0.0;
        for (NSUInteger i = 0; i < frameSize; i++) {
            double value = (double)samples[start + i] - mean;
            energy += value * value;
        }
        double rms = sqrt(energy / (double)frameSize);
        frames[frameIndex].time = ((double)start + (double)frameSize * 0.5) / sampleRate;
        frames[frameIndex].rms = rms;
        frames[frameIndex].midi = -1.0;
        frames[frameIndex].voiced = false;
        if (rms < silenceThreshold) continue;

        double confidence = 0.0;
        double frequency = [self detectPitchInSamples:samples
                                                 start:start
                                              frameSize:frameSize
                                             sampleRate:sampleRate
                                                   mean:mean
                                        minimumConfidence:minimumConfidence
                                                  minLag:minLag
                                                  maxLag:maxLag
                                              correlation:correlation
                                             confidence:&confidence];
        if (frequency <= 0.0) continue;

        double midi = 69.0 + 12.0 * log2(frequency / 440.0);
        if (midi < (double)lowPitch - 0.75 || midi > (double)highPitch + 0.75) {
            continue;
        }
        frames[frameIndex].midi = midi;
        frames[frameIndex].confidence = confidence;
        frames[frameIndex].voiced = true;
    }

    free(correlation);
    if (outCount) *outCount = frameCount;
    return frames;
}

+ (AudioNoteSegment *)segmentsFromFrames:(const AudioPitchFrame *)frames
                                  count:(NSUInteger)frameCount
                             frameHalf:(double)frameHalfSeconds
                         minimumSeconds:(double)minimumSeconds
                               maxCount:(NSUInteger)maxCount
                               outCount:(NSUInteger *)outCount {
    if (outCount) *outCount = 0;
    if (!frames || frameCount == 0 || maxCount == 0) return NULL;

    AudioNoteSegment *segments = calloc(maxCount, sizeof(AudioNoteSegment));
    if (!segments) return NULL;

    NSUInteger segmentCount = 0;
    NSInteger segmentStart = -1;
    NSInteger segmentLastVoiced = -1;
    NSUInteger unvoicedGap = 0;
    double segmentPitchSum = 0.0;
    double segmentRmsSum = 0.0;
    NSUInteger segmentFrames = 0;

    for (NSUInteger i = 0; i <= frameCount; i++) {
        bool voiced = (i < frameCount) && frames[i].voiced;
        if (voiced) {
            double midi = frames[i].midi;
            if (segmentStart < 0) {
                segmentStart = (NSInteger)i;
                segmentLastVoiced = (NSInteger)i;
                segmentPitchSum = midi;
                segmentRmsSum = frames[i].rms;
                segmentFrames = 1;
                unvoicedGap = 0;
                continue;
            }
            double meanPitch = segmentPitchSum / (double)MAX((NSUInteger)1, segmentFrames);
            if (fabs(midi - meanPitch) > 0.9) {
                [self addSegmentToBuffer:segments
                                   count:&segmentCount
                               startTime:frames[segmentStart].time - frameHalfSeconds
                                 endTime:frames[segmentLastVoiced].time + frameHalfSeconds
                                    midi:segmentPitchSum / (double)MAX((NSUInteger)1, segmentFrames)
                                     rms:segmentRmsSum / (double)MAX((NSUInteger)1, segmentFrames)
                            minimumSeconds:minimumSeconds
                                  maxCount:maxCount];
                segmentStart = (NSInteger)i;
                segmentLastVoiced = (NSInteger)i;
                segmentPitchSum = midi;
                segmentRmsSum = frames[i].rms;
                segmentFrames = 1;
                unvoicedGap = 0;
            } else {
                segmentLastVoiced = (NSInteger)i;
                segmentPitchSum += midi;
                segmentRmsSum += frames[i].rms;
                segmentFrames++;
                unvoicedGap = 0;
            }
        } else if (segmentStart >= 0) {
            unvoicedGap++;
            if (unvoicedGap > 2 || i == frameCount) {
                [self addSegmentToBuffer:segments
                                   count:&segmentCount
                               startTime:frames[segmentStart].time - frameHalfSeconds
                                 endTime:frames[segmentLastVoiced].time + frameHalfSeconds
                                    midi:segmentPitchSum / (double)MAX((NSUInteger)1, segmentFrames)
                                     rms:segmentRmsSum / (double)MAX((NSUInteger)1, segmentFrames)
                            minimumSeconds:minimumSeconds
                                  maxCount:maxCount];
                segmentStart = -1;
                segmentLastVoiced = -1;
                segmentPitchSum = 0.0;
                segmentRmsSum = 0.0;
                segmentFrames = 0;
                unvoicedGap = 0;
            }
        }
    }

    if (outCount) *outCount = segmentCount;
    return segments;
}

+ (NSArray<NoteEvent *> *)notesFromSegments:(const AudioNoteSegment *)segments
                                      count:(NSUInteger)segmentCount
                            ticksPerSecond:(double)ticksPerSecond
                                      grid:(uint64_t)grid
                                  maxTicks:(uint64_t)maxTicks
                                  lowPitch:(NSInteger)lowPitch
                                 highPitch:(NSInteger)highPitch
                                 maxNotes:(NSUInteger)maxNotes
                               monophonic:(BOOL)monophonic
                                    error:(NSError **)error {
    if (segmentCount == 0) return @[];
    if (ticksPerSecond <= 0 || grid == 0 || maxTicks == 0) {
        if (error) *error = AudioImportError(AudioImportErrorDecodeFailed, @"The song tempo is invalid.");
        return nil;
    }

    double maxRms = 0.0;
    for (NSUInteger i = 0; i < segmentCount; i++) {
        maxRms = MAX(maxRms, segments[i].rms);
    }

    NSMutableArray<NoteEvent *> *notes = [NSMutableArray arrayWithCapacity:MIN(segmentCount, maxNotes)];
    uint64_t lastEndTick = 0;
    for (NSUInteger i = 0; i < segmentCount; i++) {
        double startSeconds = MAX(0.0, segments[i].startTime);
        double endSeconds = MAX(startSeconds, segments[i].endTime);
        uint64_t startTick = (uint64_t)llround(startSeconds * ticksPerSecond / (double)grid) * grid;
        uint64_t endTick = (uint64_t)llround(endSeconds * ticksPerSecond / (double)grid) * grid;
        if (endTick <= startTick) endTick = startTick + grid;
        if (monophonic && startTick < lastEndTick) startTick = lastEndTick;
        if (endTick <= startTick) endTick = startTick + grid;
        if (startTick >= maxTicks) {
            if (error) *error = AudioImportError(AudioImportErrorTooLong,
                                                 @"The audio is longer than the 256-bar song limit.");
            return nil;
        }
        NSInteger pitch = (NSInteger)llround(segments[i].midi);
        pitch = MAX(0, MIN(127, pitch));
        if (pitch < lowPitch || pitch > highPitch) continue;
        if (notes.count >= maxNotes) {
            if (error) *error = AudioImportError(AudioImportErrorTooLong,
                                                 @"The audio produced too many notes to import.");
            return nil;
        }
        double loudness = maxRms > 0.00001 ? segments[i].rms / maxRms : 0.5;
        NSInteger velocity = (NSInteger)llround(58.0 + 62.0 * MIN(1.0, MAX(0.0, loudness)));
        velocity = MAX(1, MIN(127, velocity));
        NoteEvent *note = [NoteEvent noteWithPitch:pitch
                                         startTick:startTick
                                     durationTicks:endTick - startTick
                                          velocity:velocity];
        [notes addObject:note];
        lastEndTick = startTick + (endTick - startTick);
    }
    return notes;
}

#pragma mark - Filters

+ (float *)highPassedSamples:(const float *)samples
                       count:(NSUInteger)count
                  sampleRate:(double)sampleRate
                      cutoff:(double)cutoff {
    if (!samples || count == 0 || sampleRate <= 0 || cutoff <= 0) return NULL;
    float *output = malloc(count * sizeof(float));
    if (!output) return NULL;
    double dt = 1.0 / sampleRate;
    double rc = 1.0 / (2.0 * M_PI * cutoff);
    double alpha = rc / (rc + dt);
    double previousInput = 0.0;
    double previousOutput = 0.0;
    for (NSUInteger i = 0; i < count; i++) {
        double input = samples[i];
        double value = alpha * (previousOutput + input - previousInput);
        previousInput = input;
        previousOutput = value;
        output[i] = (float)value;
    }
    return output;
}

+ (float *)lowPassedSamples:(const float *)samples
                      count:(NSUInteger)count
                 sampleRate:(double)sampleRate
                     cutoff:(double)cutoff {
    if (!samples || count == 0 || sampleRate <= 0 || cutoff <= 0) return NULL;
    float *output = malloc(count * sizeof(float));
    if (!output) return NULL;
    double dt = 1.0 / sampleRate;
    double rc = 1.0 / (2.0 * M_PI * cutoff);
    double alpha = dt / (rc + dt);
    double previousOutput = 0.0;
    for (NSUInteger i = 0; i < count; i++) {
        double input = samples[i];
        double value = previousOutput + alpha * (input - previousOutput);
        previousOutput = value;
        output[i] = (float)value;
    }
    return output;
}

#pragma mark - Drums

+ (AudioDrumOnset *)drumOnsetsInSamples:(const float *)samples
                                  count:(NSUInteger)sampleCount
                             sampleRate:(double)sampleRate
                               outCount:(NSUInteger *)outCount {
    if (outCount) *outCount = 0;
    if (!samples || sampleCount == 0 || sampleRate <= 0) return NULL;

    NSUInteger frameSize = MAX((NSUInteger)128, (NSUInteger)llround(sampleRate * 0.023));
    NSUInteger hopSize = MAX((NSUInteger)32, (NSUInteger)llround(sampleRate * 0.0116));
    if (sampleCount < frameSize) return NULL;
    NSUInteger frameCount = (sampleCount - frameSize) / hopSize + 1;
    if (frameCount == 0) return NULL;

    float *lowSamples = [self lowPassedSamples:samples count:sampleCount sampleRate:sampleRate cutoff:180.0];
    float *highSamples = [self highPassedSamples:samples count:sampleCount sampleRate:sampleRate cutoff:1800.0];
    if (!lowSamples || !highSamples) {
        free(lowSamples);
        free(highSamples);
        return NULL;
    }

    float peak = 0.0f;
    for (NSUInteger i = 0; i < sampleCount; i++) {
        peak = MAX(peak, fabsf(samples[i]));
    }
    if (peak < 0.00001f) {
        free(lowSamples);
        free(highSamples);
        return NULL;
    }

    AudioDrumOnset *onsets = calloc(frameCount, sizeof(AudioDrumOnset));
    if (!onsets) {
        free(lowSamples);
        free(highSamples);
        return NULL;
    }

    double baseline = 0.0;
    double lastOnsetTime = -1.0;
    NSUInteger onsetCount = 0;
    for (NSUInteger frameIndex = 0; frameIndex < frameCount; frameIndex++) {
        NSUInteger start = frameIndex * hopSize;
        double fullEnergy = 0.0;
        double lowEnergy = 0.0;
        double highEnergy = 0.0;
        for (NSUInteger i = 0; i < frameSize; i++) {
            double full = samples[start + i];
            double low = lowSamples[start + i];
            double high = highSamples[start + i];
            fullEnergy += full * full;
            lowEnergy += low * low;
            highEnergy += high * high;
        }
        double rms = sqrt(fullEnergy / (double)frameSize);
        double lowRms = sqrt(lowEnergy / (double)frameSize);
        double highRms = sqrt(highEnergy / (double)frameSize);
        double time = ((double)start + (double)frameSize * 0.5) / sampleRate;
        double threshold = MAX((double)peak * 0.012, baseline * 1.7);
        double rise = rms - baseline;

        if (rise > threshold && rms > (double)peak * 0.02 &&
            (lastOnsetTime < 0.0 || time - lastOnsetTime >= 0.055)) {
            double strength = AudioImportClamp(rise / MAX((double)peak, 1e-6), 0.0, 1.0);
            onsets[onsetCount].time = time;
            onsets[onsetCount].strength = strength;
            onsets[onsetCount].lowRatio = rms > 1e-9 ? AudioImportClamp(lowRms / rms, 0.0, 1.0) : 0.0;
            onsets[onsetCount].highRatio = rms > 1e-9 ? AudioImportClamp(highRms / rms, 0.0, 1.0) : 0.0;
            onsetCount++;
            lastOnsetTime = time;
            baseline = rms;
        } else {
            baseline = baseline * 0.82 + rms * 0.18;
        }
    }

    free(lowSamples);
    free(highSamples);
    if (onsetCount == 0) {
        free(onsets);
        return NULL;
    }
    if (outCount) *outCount = onsetCount;
    return onsets;
}

+ (NSArray<NoteEvent *> *)notesFromDrumOnsets:(const AudioDrumOnset *)onsets
                                         count:(NSUInteger)onsetCount
                                ticksPerSecond:(double)ticksPerSecond
                                          grid:(uint64_t)grid
                                      maxTicks:(uint64_t)maxTicks
                                      maxNotes:(NSUInteger)maxNotes
                                           error:(NSError **)error {
    if (onsetCount == 0) return @[];
    if (ticksPerSecond <= 0 || grid == 0 || maxTicks == 0) {
        if (error) *error = AudioImportError(AudioImportErrorDecodeFailed, @"The song tempo is invalid.");
        return nil;
    }

    NSMutableDictionary<NSNumber *, NSArray<NSNumber *> *> *hits = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < onsetCount; i++) {
        uint64_t tick = (uint64_t)llround(MAX(0.0, onsets[i].time) * ticksPerSecond / (double)grid) * grid;
        if (tick >= maxTicks) {
            if (error) *error = AudioImportError(AudioImportErrorTooLong,
                                                 @"The audio is longer than the 256-bar song limit.");
            return nil;
        }
        NSInteger pitch = [self drumPitchForOnset:onsets[i]];
        NSInteger velocity = (NSInteger)llround(52.0 + 75.0 * sqrt(AudioImportClamp(onsets[i].strength, 0.0, 1.0)));
        velocity = MAX(35, MIN(127, velocity));

        NSNumber *key = @(tick);
        NSArray<NSNumber *> *existing = hits[key];
        if (!existing || velocity > existing[1].integerValue) {
            hits[key] = @[@(pitch), @(velocity)];
        }
    }

    NSArray<NSNumber *> *sortedTicks = [hits.allKeys sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray<NoteEvent *> *notes = [NSMutableArray arrayWithCapacity:MIN(sortedTicks.count, maxNotes)];
    uint64_t duration = MAX(1ULL, grid / 2);
    for (NSNumber *key in sortedTicks) {
        if (notes.count >= maxNotes) break;
        uint64_t tick = key.unsignedLongLongValue;
        uint64_t noteDuration = MIN(duration, maxTicks - tick);
        if (noteDuration == 0) continue;
        NSArray<NSNumber *> *hit = hits[key];
        NoteEvent *note = [NoteEvent noteWithPitch:hit[0].integerValue
                                         startTick:tick
                                     durationTicks:noteDuration
                                          velocity:hit[1].integerValue];
        [notes addObject:note];
    }
    return notes;
}

+ (NSInteger)drumPitchForOnset:(AudioDrumOnset)onset {
    if (onset.lowRatio >= 0.55 && onset.highRatio < 0.30) {
        return 36; // kick
    }
    if (onset.highRatio >= 0.15 && onset.lowRatio >= 0.15) {
        return 48; // snare
    }
    if (onset.highRatio >= 0.15) {
        return 72; // hat
    }
    return 36;
}

#pragma mark - Harmony

+ (NSArray<NoteEvent *> *)harmonyNotesForSong:(Song *)song
                                    leadNotes:(NSArray<NoteEvent *> *)leadNotes
                                 bassSegments:(const AudioNoteSegment *)bassSegments
                                    bassCount:(NSUInteger)bassCount
                               ticksPerSecond:(double)ticksPerSecond
                                         grid:(uint64_t)grid
                                     maxTicks:(uint64_t)maxTicks
                                     maxNotes:(NSUInteger)maxNotes {
    if (leadNotes.count == 0 || ticksPerSecond <= 0 || grid == 0) return @[];

    uint64_t spanTicks = 0;
    for (NoteEvent *note in leadNotes) {
        uint64_t end = note.startTick + note.durationTicks;
        if (end > spanTicks) spanTicks = end;
    }
    for (NSUInteger i = 0; i < bassCount; i++) {
        double endSeconds = MAX(0.0, bassSegments[i].endTime);
        uint64_t endTick = (uint64_t)llround(endSeconds * ticksPerSecond / (double)grid) * grid;
        if (endTick > spanTicks) spanTicks = endTick;
    }
    spanTicks = MIN(spanTicks, maxTicks);
    if (spanTicks == 0) return @[];

    uint64_t step = MAX(1ULL, grid * 2);
    NSArray<NSNumber *> *scaleIntervals = MusicalScaleIntervals(song.scale);
    if (scaleIntervals.count == 0) scaleIntervals = @[@0, @2, @4, @5, @7, @9, @11];
    NSInteger scaleCount = (NSInteger)scaleIntervals.count;

    NSUInteger bassCapacity = MAX((NSUInteger)1, bassCount);
    uint64_t *bassStarts = calloc(bassCapacity, sizeof(uint64_t));
    uint64_t *bassEnds = calloc(bassCapacity, sizeof(uint64_t));
    NSInteger *bassPitches = calloc(bassCapacity, sizeof(NSInteger));
    if (!bassStarts || !bassEnds || !bassPitches) {
        free(bassStarts);
        free(bassEnds);
        free(bassPitches);
        return @[];
    }
    for (NSUInteger i = 0; i < bassCount; i++) {
        bassStarts[i] = (uint64_t)llround(MAX(0.0, bassSegments[i].startTime) * ticksPerSecond / (double)grid) * grid;
        bassEnds[i] = (uint64_t)llround(MAX(0.0, bassSegments[i].endTime) * ticksPerSecond / (double)grid) * grid;
        if (bassEnds[i] <= bassStarts[i]) bassEnds[i] = bassStarts[i] + grid;
        bassPitches[i] = MAX(0, MIN(127, (NSInteger)llround(bassSegments[i].midi)));
    }

    // Root, third, fifth, third: a compact chip arpeggio that follows the
    // detected bass roots and folds them into the song's scale.
    static const NSInteger pattern[] = {0, 2, 4, 2};
    static const NSUInteger patternCount = 4;
    NSMutableArray<NoteEvent *> *notes = [NSMutableArray arrayWithCapacity:MIN(maxNotes, (NSUInteger)(spanTicks / step) + 1)];
    NSUInteger bassIndex = 0;
    NSInteger currentRootPitch = 60;
    BOOL hasBassRoot = NO;

    for (uint64_t tick = 0; tick < spanTicks && notes.count < maxNotes; tick += step) {
        while (bassIndex < bassCount && bassStarts[bassIndex] <= tick) {
            currentRootPitch = bassPitches[bassIndex];
            hasBassRoot = YES;
            bassIndex++;
        }
        NSInteger rootPitchClass = hasBassRoot ? ((currentRootPitch % 12) + 12) % 12 : ((song.keyRoot % 12) + 12) % 12;
        NSInteger basePitch = rootPitchClass + 48;
        while (basePitch > 59) basePitch -= 12;
        while (basePitch < 48) basePitch += 12;

        NSUInteger stepIndex = (NSUInteger)(tick / step);
        NSInteger degree = pattern[stepIndex % patternCount];
        NSInteger octave = degree / scaleCount;
        NSInteger scaleDegree = degree % scaleCount;
        NSInteger interval = scaleIntervals[(NSUInteger)scaleDegree].integerValue + octave * 12;
        NSInteger pitch = basePitch + interval;
        while (pitch > AudioImportHarmonyHighPitch) pitch -= 12;
        while (pitch < AudioImportHarmonyLowPitch) pitch += 12;
        if (pitch < 0 || pitch > 127) continue;

        uint64_t duration = MAX(1ULL, step / 2);
        if (tick + duration > maxTicks) duration = maxTicks - tick;
        if (duration == 0) break;

        NSInteger velocity = (stepIndex % patternCount == 0) ? 76 : 66;
        NoteEvent *note = [NoteEvent noteWithPitch:pitch
                                         startTick:tick
                                     durationTicks:duration
                                          velocity:velocity];
        [notes addObject:note];
    }

    free(bassStarts);
    free(bassEnds);
    free(bassPitches);
    return notes;
}

#pragma mark - Pitch detection

+ (double)detectPitchInSamples:(const float *)samples
                          start:(NSUInteger)start
                       frameSize:(NSUInteger)frameSize
                      sampleRate:(double)sampleRate
                            mean:(double)mean
                 minimumConfidence:(double)minimumConfidence
                           minLag:(NSUInteger)minLag
                           maxLag:(NSUInteger)maxLag
                       correlation:(double *)correlation
                      confidence:(double *)outConfidence {
    double best = 0.0;
    NSUInteger bestLag = 0;
    for (NSUInteger lag = minLag; lag <= maxLag; lag++) {
        NSUInteger count = frameSize - lag;
        double dot = 0.0;
        double energyA = 0.0;
        double energyB = 0.0;
        for (NSUInteger i = 0; i < count; i++) {
            double a = (double)samples[start + i] - mean;
            double b = (double)samples[start + i + lag] - mean;
            dot += a * b;
            energyA += a * a;
            energyB += b * b;
        }
        double denominator = sqrt(energyA * energyB);
        double value = denominator > 1e-12 ? dot / denominator : 0.0;
        correlation[lag] = value;
        if (value > best) {
            best = value;
            bestLag = lag;
        }
    }
    if (best < minimumConfidence) return -1.0;

    double required = MAX(minimumConfidence, best * 0.9);
    NSUInteger chosenLag = 0;
    for (NSUInteger lag = minLag + 1; lag < maxLag; lag++) {
        if (correlation[lag] >= correlation[lag - 1] &&
            correlation[lag] >= correlation[lag + 1] &&
            correlation[lag] >= required) {
            chosenLag = lag;
            break;
        }
    }
    if (chosenLag == 0) {
        chosenLag = bestLag;
    }

    double refinedLag = (double)chosenLag;
    if (chosenLag > minLag && chosenLag < maxLag) {
        double a = correlation[chosenLag - 1];
        double b = correlation[chosenLag];
        double c = correlation[chosenLag + 1];
        double denominator = a - 2.0 * b + c;
        if (fabs(denominator) > 1e-9) {
            double delta = 0.5 * (a - c) / denominator;
            if (delta >= -0.5 && delta <= 0.5) refinedLag += delta;
        }
    }
    if (refinedLag <= 0.0) return -1.0;
    if (outConfidence) *outConfidence = correlation[chosenLag];
    return sampleRate / refinedLag;
}

+ (void)addSegmentToBuffer:(AudioNoteSegment *)segments
                     count:(NSUInteger *)count
                 startTime:(double)startTime
                   endTime:(double)endTime
                      midi:(double)midi
                       rms:(double)rms
              minimumSeconds:(double)minimumSeconds
                    maxCount:(NSUInteger)maxCount {
    if (!segments || !count) return;
    if (endTime <= startTime || endTime - startTime < minimumSeconds) return;
    if (midi < 0.0 || midi > 127.0) return;
    if (*count >= maxCount) return;
    segments[*count].startTime = startTime;
    segments[*count].endTime = endTime;
    segments[*count].midi = midi;
    segments[*count].rms = rms;
    (*count)++;
}

#pragma mark - Decoding

+ (AudioImportDecodedAudio *)decodeAudioAtURL:(NSURL *)url error:(NSError **)error {
    NSError *nativeError = nil;
    AudioImportDecodedAudio *decoded = [self decodeWithAVFoundationAtURL:url error:&nativeError];
    if (decoded) return decoded;
    if (nativeError.code == AudioImportErrorTooLong &&
        [nativeError.domain isEqualToString:AudioImportErrorDomain]) {
        if (error) *error = nativeError;
        return nil;
    }

    NSString *ffmpeg = [self ffmpegExecutablePath];
    if (!ffmpeg) {
        if (error) {
            if ([url.pathExtension.lowercaseString isEqualToString:@"ogg"]) {
                *error = AudioImportError(AudioImportErrorUnsupportedFormat,
                                          @"This macOS version cannot decode Ogg audio. Install ffmpeg with “brew install ffmpeg” and try again.");
            } else {
                *error = nativeError ?: AudioImportError(AudioImportErrorDecodeFailed, @"Could not decode the audio file.");
            }
        }
        return nil;
    }

    NSString *tempName = [NSString stringWithFormat:@"chiptune-import-%@.wav", [[NSUUID UUID] UUIDString]];
    NSURL *tempURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:tempName]];
    NSError *transcodeError = nil;
    if (![self transcodeWithFFmpegAtPath:ffmpeg inputURL:url outputURL:tempURL error:&transcodeError]) {
        [[NSFileManager defaultManager] removeItemAtURL:tempURL error:nil];
        if (error) *error = transcodeError ?: nativeError ?: AudioImportError(AudioImportErrorDecodeFailed, @"Could not decode the audio file.");
        return nil;
    }

    NSError *tempReadError = nil;
    decoded = [self decodeWithAVFoundationAtURL:tempURL error:&tempReadError];
    [[NSFileManager defaultManager] removeItemAtURL:tempURL error:nil];
    if (!decoded) {
        if (error) {
            *error = AudioImportError(AudioImportErrorDecodeFailed,
                                      [NSString stringWithFormat:@"Could not decode “%@”: %@",
                                       url.lastPathComponent,
                                       tempReadError.localizedDescription ?: @"unknown error"]);
        }
        return nil;
    }
    decoded.decoderName = @"ffmpeg";
    return decoded;
}

+ (AudioImportDecodedAudio *)decodeWithAVFoundationAtURL:(NSURL *)url error:(NSError **)error {
    NSError *openError = nil;
    AVAudioFile *file = [[AVAudioFile alloc] initForReading:url error:&openError];
    if (!file) {
        if (error) {
            *error = AudioImportError(AudioImportErrorDecodeFailed,
                                      [NSString stringWithFormat:@"Could not open “%@”: %@",
                                       url.lastPathComponent,
                                       openError.localizedDescription ?: @"unsupported audio format"]);
        }
        return nil;
    }

    AVAudioFormat *format = file.processingFormat;
    double sourceRate = format.sampleRate;
    AVAudioChannelCount channelCount = format.channelCount;
    if (sourceRate <= 0 || channelCount == 0) {
        if (error) *error = AudioImportError(AudioImportErrorDecodeFailed, @"The audio file has an invalid format.");
        return nil;
    }
    double declaredDuration = sourceRate > 0 ? (double)file.length / sourceRate : 0.0;
    if (declaredDuration > AudioImportMaxSeconds + 0.5) {
        if (error) *error = AudioImportError(AudioImportErrorTooLong, @"Audio files longer than 5 minutes are not supported.");
        return nil;
    }

    AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:8192];
    if (!buffer) {
        if (error) *error = AudioImportError(AudioImportErrorDecodeFailed, @"Could not allocate an audio buffer.");
        return nil;
    }

    NSMutableData *monoData = [NSMutableData dataWithCapacity:(NSUInteger)MAX(1024.0, declaredDuration * AudioImportAnalysisSampleRate) * sizeof(float)];
    double ratio = MAX(1.0, sourceRate / AudioImportAnalysisSampleRate);
    double bucketEnd = ratio;
    double bucketSum = 0.0;
    NSUInteger bucketCount = 0;
    NSUInteger totalSourceFrames = 0;
    NSUInteger totalLimit = (NSUInteger)ceil(sourceRate * AudioImportMaxSeconds);

    while (YES) {
        NSError *readError = nil;
        buffer.frameLength = 0;
        BOOL readSucceeded = [file readIntoBuffer:buffer error:&readError];
        AVAudioFrameCount frames = buffer.frameLength;
        if (!readSucceeded) {
            // macOS 27 reports end-of-file as kAudioFileEndOfFileError instead
            // of returning a successful read with frameLength == 0.
            BOOL reachedEnd = [readError.domain isEqualToString:NSOSStatusErrorDomain] &&
                              readError.code == kAudioFileEndOfFileError;
            if (reachedEnd && frames == 0) break;
            if (!reachedEnd) {
                if (error) {
                    *error = AudioImportError(AudioImportErrorDecodeFailed,
                                              [NSString stringWithFormat:@"Could not decode “%@”: %@",
                                               url.lastPathComponent,
                                               readError.localizedDescription ?: @"unknown error"]);
                }
                return nil;
            }
        }
        if (frames == 0) break;
        float *const *channels = buffer.floatChannelData;
        if (!channels) {
            if (error) *error = AudioImportError(AudioImportErrorDecodeFailed, @"The audio file is not in a supported PCM format.");
            return nil;
        }
        NSUInteger stride = buffer.stride;
        for (AVAudioFrameCount i = 0; i < frames; i++) {
            double mono = 0.0;
            for (AVAudioChannelCount channel = 0; channel < channelCount; channel++) {
                mono += (double)channels[channel][(NSUInteger)i * stride];
            }
            mono /= (double)channelCount;
            bucketSum += mono;
            bucketCount++;
            totalSourceFrames++;
            if (totalSourceFrames > totalLimit) {
                if (error) *error = AudioImportError(AudioImportErrorTooLong, @"Audio files longer than 5 minutes are not supported.");
                return nil;
            }
            if ((double)totalSourceFrames >= bucketEnd) {
                float output = (float)(bucketSum / (double)MAX((NSUInteger)1, bucketCount));
                [monoData appendBytes:&output length:sizeof(output)];
                bucketSum = 0.0;
                bucketCount = 0;
                bucketEnd += ratio;
            }
        }
    }

    if (bucketCount > 0 && (double)bucketCount >= ratio * 0.5) {
        float output = (float)(bucketSum / (double)bucketCount);
        [monoData appendBytes:&output length:sizeof(output)];
    }
    if (monoData.length == 0) {
        if (error) *error = AudioImportError(AudioImportErrorDecodeFailed, @"The audio file contains no samples.");
        return nil;
    }

    AudioImportDecodedAudio *decoded = [[AudioImportDecodedAudio alloc] init];
    decoded.monoData = monoData;
    decoded.analysisSampleRate = ratio > 1.0 ? AudioImportAnalysisSampleRate : sourceRate;
    decoded.sourceSampleRate = sourceRate;
    decoded.sourceChannelCount = (NSInteger)channelCount;
    decoded.durationSeconds = (double)totalSourceFrames / sourceRate;
    decoded.decoderName = @"CoreAudio";
    return decoded;
}

+ (BOOL)transcodeWithFFmpegAtPath:(NSString *)ffmpeg
                         inputURL:(NSURL *)inputURL
                        outputURL:(NSURL *)outputURL
                            error:(NSError **)error {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = ffmpeg;
    task.arguments = @[
        @"-v", @"error",
        @"-y",
        @"-i", inputURL.path,
        @"-ac", @"1",
        @"-ar", @"22050",
        @"-f", @"wav",
        outputURL.path
    ];
    NSPipe *errorPipe = [NSPipe pipe];
    task.standardError = errorPipe;
    @try {
        [task launch];
    } @catch (NSException *exception) {
        if (error) {
            *error = AudioImportError(AudioImportErrorDecodeFailed,
                                      [NSString stringWithFormat:@"Could not launch ffmpeg: %@", exception.reason ?: @"unknown error"]);
        }
        return NO;
    }
    // Drain stderr before waiting so a decoder that writes a lot of output
    // cannot fill the pipe and hang the task.
    NSData *errorData = [errorPipe.fileHandleForReading readDataToEndOfFile];
    [task waitUntilExit];
    if (task.terminationStatus != 0) {
        NSString *message = [[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding];
        message = [message stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (message.length == 0) message = @"ffmpeg could not decode the file.";
        if (error) *error = AudioImportError(AudioImportErrorDecodeFailed, message);
        return NO;
    }
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:outputURL.path error:NULL];
    if (!attributes || [attributes[NSFileSize] unsignedLongLongValue] == 0) {
        if (error) *error = AudioImportError(AudioImportErrorDecodeFailed, @"ffmpeg produced an empty audio file.");
        return NO;
    }
    return YES;
}

#pragma mark - Appending

+ (uint64_t)latestNoteEndTickInSong:(Song *)song {
    uint64_t lastEnd = 0;
    for (Track *track in song.tracks) {
        for (NoteEvent *note in track.notes) {
            uint64_t end = note.startTick + note.durationTicks;
            if (end > lastEnd) lastEnd = end;
        }
    }
    return lastEnd;
}

+ (uint64_t)startTickForAppendingToTrack:(Track *)track
                                    song:(Song *)song
                              playheadTick:(uint64_t)playheadTick {
    if (!song) return 0;
    uint64_t grid = MAX(1ULL, song.ppq / 4);
    uint64_t lastEnd = 0;
    if (track) {
        for (NoteEvent *note in track.notes) {
            uint64_t end = note.startTick + note.durationTicks;
            if (end > lastEnd) lastEnd = end;
        }
    }
    if (lastEnd > 0) {
        return ((lastEnd + grid - 1) / grid) * grid;
    }
    uint64_t tick = MIN(playheadTick, song.totalTicks);
    return (tick / grid) * grid;
}

+ (uint64_t)startTickForAppendingToSong:(Song *)song
                           playheadTick:(uint64_t)playheadTick {
    if (!song) return 0;
    uint64_t grid = MAX(1ULL, song.ppq / 4);
    uint64_t lastEnd = [self latestNoteEndTickInSong:song];
    if (lastEnd > 0) {
        return ((lastEnd + grid - 1) / grid) * grid;
    }
    uint64_t tick = MIN(playheadTick, song.totalTicks);
    return (tick / grid) * grid;
}

+ (BOOL)growSong:(Song *)song toFitEndTick:(uint64_t)endTick error:(NSError **)error {
    uint64_t ticksPerBar = MAX(1ULL, song.ticksPerBar);
    uint64_t requiredBars = (endTick + ticksPerBar - 1) / ticksPerBar;
    if (requiredBars < 1) requiredBars = 1;
    if (requiredBars > 256) {
        if (error) *error = AudioImportError(AudioImportErrorTooLong, @"The audio is longer than the 256-bar song limit.");
        return NO;
    }

    uint64_t oldBars = (uint64_t)MAX(0, song.lengthBars);
    if (requiredBars > oldBars) {
        song.lengthBars = (NSInteger)requiredBars;
        SongSection *lastSection = song.sections.lastObject;
        NSInteger lastEnd = lastSection ? lastSection.startBar + lastSection.lengthBars : 0;
        if (lastEnd <= (NSInteger)oldBars) {
            [song.sections addObject:[SongSection sectionWithName:@"Imported Audio"
                                                         startBar:(NSInteger)oldBars
                                                        lengthBars:(NSInteger)(requiredBars - oldBars)]];
        }
    }
    return YES;
}

+ (BOOL)appendNotes:(NSArray<NoteEvent *> *)notes
             toSong:(Song *)song
         trackIndex:(NSInteger)trackIndex
          startTick:(uint64_t)startTick
              error:(NSError **)error {
    Track *track = [song trackAtIndex:trackIndex];
    if (!track) {
        if (error) *error = AudioImportError(AudioImportErrorSongLimit, @"The target track no longer exists.");
        return NO;
    }
    if (notes.count == 0) return YES;
    if (track.notes.count + notes.count > 20000) {
        if (error) *error = AudioImportError(AudioImportErrorSongLimit, @"The target track would contain too many notes.");
        return NO;
    }

    uint64_t maxEnd = startTick;
    for (NoteEvent *note in notes) {
        if (note.pitch < 0 || note.pitch > 127 || note.velocity < 0 || note.velocity > 127 || note.durationTicks == 0) {
            if (error) *error = AudioImportError(AudioImportErrorSongLimit, @"The audio produced an invalid note.");
            return NO;
        }
        uint64_t end = startTick + note.startTick + note.durationTicks;
        if (end > maxEnd) maxEnd = end;
    }

    if (![self growSong:song toFitEndTick:maxEnd error:error]) return NO;

    for (NoteEvent *note in notes) {
        NoteEvent *copy = [note copy];
        copy.startTick = startTick + note.startTick;
        [track.notes addObject:copy];
    }
    [song sortNotes];

    NSError *validationError = nil;
    if (![song validateWithError:&validationError]) {
        if (error) *error = validationError;
        return NO;
    }
    return YES;
}

+ (NSString *)trackNameForPart:(AudioImportPart *)part baseName:(NSString *)baseName {
    switch (part.role) {
        case AudioImportPartRoleLead:
            return [NSString stringWithFormat:@"%@ Lead", baseName];
        case AudioImportPartRoleHarmony:
            return [NSString stringWithFormat:@"%@ Harmony", baseName];
        case AudioImportPartRoleBass:
            return [NSString stringWithFormat:@"%@ Bass", baseName];
        case AudioImportPartRoleDrums:
            return [NSString stringWithFormat:@"%@ Drums", baseName];
    }
    return [NSString stringWithFormat:@"%@ %@", baseName, part.name ?: @"Part"];
}

+ (void)configureTrack:(Track *)track forRole:(AudioImportPartRole)role {
    switch (role) {
        case AudioImportPartRoleLead:
            track.volume = 0.72;
            track.pan = 0.0;
            track.vibratoDepth = 0.12;
            track.vibratoRate = 5.5;
            break;
        case AudioImportPartRoleHarmony:
            track.volume = 0.50;
            track.pan = -0.25;
            track.vibratoDepth = 0.05;
            track.vibratoRate = 5.0;
            break;
        case AudioImportPartRoleBass:
            track.volume = 0.70;
            track.pan = 0.0;
            break;
        case AudioImportPartRoleDrums:
            track.volume = 0.58;
            track.pan = 0.12;
            break;
    }
}

+ (BOOL)appendParts:(NSArray<AudioImportPart *> *)parts
             toSong:(Song *)song
          startTick:(uint64_t)startTick
           baseName:(NSString *)baseName
              error:(NSError **)error {
    if (!song) {
        if (error) *error = AudioImportError(AudioImportErrorInvalidFile, @"There is no song to import into.");
        return NO;
    }

    NSMutableArray<AudioImportPart *> *nonEmptyParts = [NSMutableArray array];
    for (AudioImportPart *part in parts) {
        if (part.notes.count > 0) [nonEmptyParts addObject:part];
    }
    if (nonEmptyParts.count == 0) return YES;
    if (song.tracks.count + nonEmptyParts.count > 8) {
        if (error) *error = AudioImportError(AudioImportErrorSongLimit,
                                             @"This song already has eight tracks. Delete a track before importing the arrangement.");
        return NO;
    }

    NSString *effectiveBaseName = baseName.length > 0 ? baseName : @"Audio";
    uint64_t maxEnd = startTick;
    for (AudioImportPart *part in nonEmptyParts) {
        if (part.notes.count > 20000) {
            if (error) *error = AudioImportError(AudioImportErrorSongLimit, @"The audio produced too many notes for one track.");
            return NO;
        }
        for (NoteEvent *note in part.notes) {
            if (note.pitch < 0 || note.pitch > 127 || note.velocity < 0 ||
                note.velocity > 127 || note.durationTicks == 0) {
                if (error) *error = AudioImportError(AudioImportErrorSongLimit, @"The audio produced an invalid note.");
                return NO;
            }
            uint64_t end = startTick + note.startTick + note.durationTicks;
            if (end > maxEnd) maxEnd = end;
        }
    }

    uint64_t ticksPerBar = MAX(1ULL, song.ticksPerBar);
    uint64_t requiredBars = (maxEnd + ticksPerBar - 1) / ticksPerBar;
    if (requiredBars > 256) {
        if (error) *error = AudioImportError(AudioImportErrorTooLong, @"The audio is longer than the 256-bar song limit.");
        return NO;
    }

    // Keep a snapshot so a late validation failure cannot leave new tracks
    // behind in the caller's song.
    NSMutableArray<Track *> *oldTracks = [song.tracks mutableCopy];
    NSMutableArray<SongSection *> *oldSections = [song.sections mutableCopy];
    NSInteger oldLengthBars = song.lengthBars;

    if (![self growSong:song toFitEndTick:maxEnd error:error]) {
        return NO;
    }

    for (AudioImportPart *part in nonEmptyParts) {
        Track *track = [Track trackWithName:[self trackNameForPart:part baseName:effectiveBaseName]
                                 instrument:part.instrument];
        [self configureTrack:track forRole:part.role];
        track.notes = [NSMutableArray arrayWithCapacity:part.notes.count];
        for (NoteEvent *note in part.notes) {
            NoteEvent *copy = [note copy];
            copy.startTick = startTick + note.startTick;
            [track.notes addObject:copy];
        }
        [track sortNotes];
        [song.tracks addObject:track];
    }

    NSError *validationError = nil;
    if (![song validateWithError:&validationError]) {
        song.tracks = oldTracks;
        song.sections = oldSections;
        song.lengthBars = oldLengthBars;
        if (error) *error = validationError;
        return NO;
    }
    return YES;
}

@end
