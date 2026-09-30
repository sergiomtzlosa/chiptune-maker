#import <Foundation/Foundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "SongTypes.h"

NS_ASSUME_NONNULL_BEGIN

@class NoteEvent;
@class Song;
@class Track;

FOUNDATION_EXPORT NSErrorDomain const AudioImportErrorDomain;

typedef NS_ENUM(NSInteger, AudioImportErrorCode) {
    AudioImportErrorInvalidFile = 1,
    AudioImportErrorDecodeFailed,
    AudioImportErrorUnsupportedFormat,
    AudioImportErrorTooLong,
    AudioImportErrorSongLimit
};

typedef NS_ENUM(NSInteger, AudioImportPartRole) {
    AudioImportPartRoleLead = 0,
    AudioImportPartRoleHarmony,
    AudioImportPartRoleBass,
    AudioImportPartRoleDrums
};

/// One extracted voice from an imported recording. Notes are relative to the
/// beginning of the audio; callers offset them when adding tracks to a song.
@interface AudioImportPart : NSObject

@property (nonatomic, assign) AudioImportPartRole role;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) ChipInstrument instrument;
@property (nonatomic, copy) NSArray<NoteEvent *> *notes;

@end

/// Options controlling how an audio file is transcribed into note events.
@interface AudioImportOptions : NSObject

/// Note grid in ticks. A value of 0 uses the song's sixteenth-note grid.
@property (nonatomic, assign) uint64_t gridTicks;
/// Minimum normalized autocorrelation confidence for a voiced frame.
@property (nonatomic, assign) double minimumConfidence;
/// Notes shorter than this are discarded.
@property (nonatomic, assign) double minimumNoteSeconds;
/// Detected pitches outside this MIDI range are ignored.
@property (nonatomic, assign) NSInteger lowPitch;
@property (nonatomic, assign) NSInteger highPitch;
/// Extract a low-register bass line onto its own track.
@property (nonatomic, assign) BOOL extractBass;
/// Generate arpeggiated chord tones from detected bass roots and the song scale.
@property (nonatomic, assign) BOOL extractHarmony;
/// Extract percussive onsets onto a Noise track.
@property (nonatomic, assign) BOOL extractDrums;

+ (instancetype)defaultOptions;

@end

/// The result of transcribing an audio file. `notes` contains the lead melody
/// for compatibility; `parts` contains every extracted voice.
@interface AudioImportResult : NSObject

@property (nonatomic, copy) NSArray<NoteEvent *> *notes;
@property (nonatomic, copy) NSArray<AudioImportPart *> *parts;
@property (nonatomic, assign) double durationSeconds;
@property (nonatomic, assign) double sourceSampleRate;
@property (nonatomic, assign) NSInteger sourceChannelCount;
@property (nonatomic, copy, nullable) NSString *decoderName;

@end

@interface AudioImportService : NSObject

/// Extensions accepted by the import panel: flac, wav, ogg, mp3.
+ (NSArray<NSString *> *)supportedFileExtensions;
+ (NSArray<UTType *> *)supportedContentTypes;
/// Optional external decoder used when CoreAudio cannot open a file (notably
/// Ogg on older macOS versions).
+ (nullable NSString *)ffmpegExecutablePath;

/// Decodes and transcribes a monophonic melody plus optional bass, harmony,
/// and drum parts. Returns an empty result when the file contains no
/// detectable musical material. Returns nil on a decoding or limit error.
+ (nullable AudioImportResult *)transcribeAudioAtURL:(NSURL *)url
                                                song:(Song *)song
                                             options:(AudioImportOptions *)options
                                               error:(NSError * _Nullable * _Nullable)error;

/// Returns the next grid-aligned tick after the target track's last note, or
/// the grid-aligned playhead when the track is empty or nil. Returns 0 when
/// there is no song.
+ (uint64_t)startTickForAppendingToTrack:(nullable Track *)track
                                    song:(Song *)song
                              playheadTick:(uint64_t)playheadTick;

/// Returns the next grid-aligned tick after the last note in the song, or the
/// grid-aligned playhead when the song is empty. Returns 0 when there is no
/// song.
+ (uint64_t)startTickForAppendingToSong:(Song *)song
                           playheadTick:(uint64_t)playheadTick;

/// Copies the relative notes into the song, offsets them by startTick, grows
/// the song if needed, and validates the result. All checks happen before any
/// mutation whenever possible.
+ (BOOL)appendNotes:(NSArray<NoteEvent *> *)notes
             toSong:(Song *)song
         trackIndex:(NSInteger)trackIndex
          startTick:(uint64_t)startTick
              error:(NSError * _Nullable * _Nullable)error;

/// Creates one track per non-empty part, appends all parts at `startTick`,
/// grows the song if needed, and validates the result. Fails if the song would
/// exceed eight tracks.
+ (BOOL)appendParts:(NSArray<AudioImportPart *> *)parts
             toSong:(Song *)song
          startTick:(uint64_t)startTick
           baseName:(NSString *)baseName
              error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
