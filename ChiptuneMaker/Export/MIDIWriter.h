#import <Foundation/Foundation.h>

@class Song;

@interface MIDIWriter : NSObject

+ (NSData *)dataForSong:(Song *)song audibleOnly:(BOOL)audibleOnly;

@end
