#import "ExportService.h"
#import "Song.h"
#import "MIDIWriter.h"
#import "LSDjExporter.h"
#import "ChipRenderer.h"
#import <AudioToolbox/AudioToolbox.h>
#import <math.h>
#import <stdlib.h>
#import <string.h>

static NSError *ExportError(NSString *message) {
    return [NSError errorWithDomain:@"ChiptuneMaker.Export" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

@implementation ExportOptions
+ (instancetype)defaultOptions {
    ExportOptions *options = [[self alloc] init];
    options.format = ExportFormatFLAC;
    options.sampleRate = 44100;
    options.mp3Bitrate = 192;
    options.normalize = YES;
    options.audibleOnly = YES;
    return options;
}
@end

@implementation ExportService

+ (NSString *)lameExecutablePath {
    NSArray<NSString *> *candidates = @[
        @"/opt/homebrew/bin/lame",
        @"/usr/local/bin/lame",
        @"/usr/bin/lame"
    ];
    for (NSString *path in candidates) {
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:path]) return path;
    }
    return nil;
}

+ (void)exportSong:(Song *)song
             toURL:(NSURL *)url
           options:(ExportOptions *)options
          progress:(void (^)(double progress))progress
        completion:(void (^)(NSError *error))completion {
    if (!song || !url || !options) {
        if (completion) completion(ExportError(@"Invalid export request."));
        return;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            NSError *error = nil;
            if (options.format == ExportFormatMIDI) {
                NSData *data = [MIDIWriter dataForSong:song audibleOnly:options.audibleOnly];
                if (![data writeToURL:url options:NSDataWritingAtomic error:&error]) {
                    if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
                    return;
                }
                if (progress) dispatch_async(dispatch_get_main_queue(), ^{ progress(1.0); });
                if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
                return;
            }

            if (options.format == ExportFormatLSDj) {
                NSError *lsdjError = nil;
                NSData *data = [LSDjExporter dataForSong:song audibleOnly:options.audibleOnly error:&lsdjError];
                if (!data) {
                    NSError *failure = lsdjError ?: ExportError(@"Could not export the LSDj file.");
                    if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(failure); });
                    return;
                }
                if (![data writeToURL:url options:NSDataWritingAtomic error:&error]) {
                    if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
                    return;
                }
                if (progress) dispatch_async(dispatch_get_main_queue(), ^{ progress(1.0); });
                if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
                return;
            }

            NSInteger sampleRate = options.sampleRate > 0 ? options.sampleRate : 44100;
            ChipRenderer *renderer = [[ChipRenderer alloc] initWithSampleRate:(double)sampleRate];
            [renderer prepareWithSong:song];
            renderer.playing = YES;
            double ticksPerSecond = (double)song.ppq * song.tempo / 60.0;
            NSUInteger musicFrames = (NSUInteger)ceil((double)song.totalTicks / ticksPerSecond * (double)sampleRate);
            NSUInteger tailFrames = (NSUInteger)sampleRate * 2;
            NSUInteger totalFrames = musicFrames + tailFrames;
            float *left = calloc(totalFrames, sizeof(float));
            float *right = calloc(totalFrames, sizeof(float));
            if (!left || !right) {
                free(left); free(right);
                if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(ExportError(@"Not enough memory to render the song.")); });
                return;
            }
            NSUInteger blockSize = 4096;
            NSUInteger rendered = 0;
            while (rendered < totalFrames) {
                NSUInteger block = MIN(blockSize, totalFrames - rendered);
                [renderer renderFrames:block left:left + rendered right:right + rendered];
                rendered += block;
                if (progress) {
                    double value = (double)rendered / (double)totalFrames;
                    dispatch_async(dispatch_get_main_queue(), ^{ progress(value); });
                }
            }

            float peak = 0.0f;
            for (NSUInteger i = 0; i < totalFrames; i++) {
                peak = MAX(peak, fabsf(left[i]));
                peak = MAX(peak, fabsf(right[i]));
            }
            if (options.normalize && peak > 0.0001f) {
                float scale = 0.89f / peak;
                for (NSUInteger i = 0; i < totalFrames; i++) {
                    left[i] *= scale;
                    right[i] *= scale;
                }
            }

            if (options.format == ExportFormatFLAC || options.format == ExportFormatWAV) {
                error = [self writePCMToURL:url sampleRate:sampleRate left:left right:right frames:totalFrames flac:(options.format == ExportFormatFLAC)];
            } else if (options.format == ExportFormatMP3) {
                NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"chiptune-%@.wav", [[NSUUID UUID] UUIDString]]];
                NSURL *tempURL = [NSURL fileURLWithPath:tempPath];
                NSError *wavError = [self writePCMToURL:tempURL sampleRate:sampleRate left:left right:right frames:totalFrames flac:NO];
                if (wavError) {
                    error = wavError;
                } else {
                    error = [self encodeMP3FromWAV:tempURL toURL:url bitrate:options.mp3Bitrate];
                    [[NSFileManager defaultManager] removeItemAtURL:tempURL error:nil];
                }
            } else {
                error = ExportError(@"Unsupported export format.");
            }
            free(left);
            free(right);
            if (progress) dispatch_async(dispatch_get_main_queue(), ^{ progress(1.0); });
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
        }
    });
}

+ (NSError *)writePCMToURL:(NSURL *)url
                sampleRate:(NSInteger)sampleRate
                     left:(float *)left
                    right:(float *)right
                   frames:(NSUInteger)frames
                     flac:(BOOL)flac {
    CFURLRef cfURL = (__bridge CFURLRef)url;
    AudioStreamBasicDescription fileFormat = {0};
    fileFormat.mSampleRate = sampleRate;
    fileFormat.mFormatID = flac ? kAudioFormatFLAC : kAudioFormatLinearPCM;
    fileFormat.mFormatFlags = flac ? 0 : (kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked);
    fileFormat.mChannelsPerFrame = 2;
    fileFormat.mBitsPerChannel = 16;
    fileFormat.mFramesPerPacket = flac ? 0 : 1;
    fileFormat.mBytesPerFrame = flac ? 0 : 4;
    fileFormat.mBytesPerPacket = flac ? 0 : 4;

    ExtAudioFileRef file = NULL;
    OSStatus status = ExtAudioFileCreateWithURL(cfURL, flac ? kAudioFileFLACType : kAudioFileWAVEType, &fileFormat, NULL, kAudioFileFlags_EraseFile, &file);
    if (status != noErr) {
        return ExportError([NSString stringWithFormat:@"Could not create the audio file (error %d).", (int)status]);
    }

    AudioStreamBasicDescription client = {0};
    client.mSampleRate = sampleRate;
    client.mFormatID = kAudioFormatLinearPCM;
    client.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    client.mChannelsPerFrame = 2;
    client.mBitsPerChannel = 16;
    client.mFramesPerPacket = 1;
    client.mBytesPerFrame = 4;
    client.mBytesPerPacket = 4;
    status = ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat, sizeof(client), &client);
    if (status != noErr) {
        ExtAudioFileDispose(file);
        return ExportError([NSString stringWithFormat:@"Could not configure the audio encoder (error %d).", (int)status]);
    }

    NSUInteger blockSize = 4096;
    int16_t *interleaved = calloc(blockSize * 2, sizeof(int16_t));
    if (!interleaved) {
        ExtAudioFileDispose(file);
        return ExportError(@"Not enough memory to encode audio.");
    }

    NSUInteger offset = 0;
    NSError *result = nil;
    while (offset < frames) {
        NSUInteger block = MIN(blockSize, frames - offset);
        for (NSUInteger i = 0; i < block; i++) {
            float l = MAX(-1.0f, MIN(1.0f, left[offset + i]));
            float r = MAX(-1.0f, MIN(1.0f, right[offset + i]));
            interleaved[i * 2] = (int16_t)lrintf(l * 32767.0f);
            interleaved[i * 2 + 1] = (int16_t)lrintf(r * 32767.0f);
        }
        AudioBufferList bufferList;
        bufferList.mNumberBuffers = 1;
        bufferList.mBuffers[0].mNumberChannels = 2;
        bufferList.mBuffers[0].mDataByteSize = (UInt32)(block * 2 * sizeof(int16_t));
        bufferList.mBuffers[0].mData = interleaved;
        status = ExtAudioFileWrite(file, (UInt32)block, &bufferList);
        if (status != noErr) {
            result = ExportError([NSString stringWithFormat:@"Audio encoding failed (error %d).", (int)status]);
            break;
        }
        offset += block;
    }
    free(interleaved);
    ExtAudioFileDispose(file);
    return result;
}

+ (NSError *)encodeMP3FromWAV:(NSURL *)wavURL toURL:(NSURL *)mp3URL bitrate:(NSInteger)bitrate {
    NSString *lame = [self lameExecutablePath];
    if (!lame) {
        return ExportError(@"MP3 export requires LAME. Install it with “brew install lame”, or export FLAC/WAV instead.");
    }
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = lame;
    task.arguments = @[@"--silent", @"-b", [NSString stringWithFormat:@"%ld", (long)MAX(64, MIN(320, bitrate))], wavURL.path, mp3URL.path];
    NSPipe *pipe = [NSPipe pipe];
    task.standardError = pipe;
    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *exception) {
        return ExportError([NSString stringWithFormat:@"Could not launch LAME: %@", exception.reason]);
    }
    if (task.terminationStatus != 0) {
        NSData *errorData = [pipe.fileHandleForReading readDataToEndOfFile];
        NSString *message = [[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding];
        if (message.length == 0) message = @"LAME exited with an error.";
        return ExportError(message);
    }
    return nil;
}

@end
