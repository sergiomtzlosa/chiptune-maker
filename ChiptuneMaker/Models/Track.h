#import <Foundation/Foundation.h>
#import "SongTypes.h"

@class NoteEvent;

@interface Track : NSObject <NSCopying>

@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) ChipInstrument instrument;
@property (nonatomic, assign) double volume;
@property (nonatomic, assign) double pan;
@property (nonatomic, assign) BOOL muted;
@property (nonatomic, assign) BOOL soloed;
@property (nonatomic, assign) double vibratoDepth;
@property (nonatomic, assign) double vibratoRate;
@property (nonatomic, assign) BOOL slideEnabled;
@property (nonatomic, assign) NSInteger arpeggio;
@property (nonatomic, strong) NSMutableArray<NoteEvent *> *notes;

+ (instancetype)trackWithName:(NSString *)name instrument:(ChipInstrument)instrument;

- (void)sortNotes;
- (NoteEvent *)noteStartingAtTick:(uint64_t)tick tolerance:(uint64_t)tolerance;
- (NSArray<NoteEvent *> *)notesInRange:(NSRange)range;
- (void)removeNotesInTickRange:(uint64_t)startTick endTick:(uint64_t)endTick;
- (NSDictionary *)dictionaryRepresentation;
+ (instancetype)trackFromDictionary:(NSDictionary *)dictionary;

@end
