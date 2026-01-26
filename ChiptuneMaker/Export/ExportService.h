#import <Foundation/Foundation.h>

@class Song;

typedef NS_ENUM(NSInteger, ExportFormat) {
    ExportFormatMIDI = 0,
    ExportFormatFLAC,
    ExportFormatWAV,
    ExportFormatMP3,
    ExportFormatLSDj
};

@interface ExportOptions : NSObject
@property (nonatomic, assign) ExportFormat format;
@property (nonatomic, assign) NSInteger sampleRate;
@property (nonatomic, assign) NSInteger mp3Bitrate;
@property (nonatomic, assign) BOOL normalize;
@property (nonatomic, assign) BOOL audibleOnly;
+ (instancetype)defaultOptions;
@end

@interface ExportService : NSObject

+ (void)exportSong:(Song *)song
             toURL:(NSURL *)url
           options:(ExportOptions *)options
          progress:(void (^)(double progress))progress
        completion:(void (^)(NSError *error))completion;

+ (NSString *)lameExecutablePath;

@end
