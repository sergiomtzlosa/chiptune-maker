#import <Foundation/Foundation.h>
#import "SongTypes.h"

@class Track;
@class SongSection;

@interface Song : NSObject <NSCopying>

@property (nonatomic, assign) NSInteger formatVersion;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *author;
@property (nonatomic, assign) double tempo;
@property (nonatomic, assign) NSInteger timeSignatureNumerator;
@property (nonatomic, assign) NSInteger timeSignatureDenominator;
@property (nonatomic, assign) NSInteger keyRoot;
@property (nonatomic, assign) MusicalScale scale;
@property (nonatomic, assign) double swing;
@property (nonatomic, assign) NSInteger lengthBars;
@property (nonatomic, assign) uint64_t generationSeed;
@property (nonatomic, assign) double generationDensity;
@property (nonatomic, assign) double generationComplexity;
@property (nonatomic, assign) NSInteger generationOctaveRange;
@property (nonatomic, strong) NSMutableArray<SongSection *> *sections;
@property (nonatomic, strong) NSMutableArray<Track *> *tracks;
@property (nonatomic, strong) NSDate *createdAt;
@property (nonatomic, strong) NSDate *modifiedAt;

+ (instancetype)defaultSong;

- (uint64_t)ppq;
- (uint64_t)ticksPerBar;
- (uint64_t)totalTicks;
- (Track *)trackAtIndex:(NSInteger)index;
- (void)sortNotes;

/// Transposes every pitched track by a number of semitones. Noise tracks are
/// left alone so drum patterns keep their character.
- (void)transposePitchedNotesBySemitones:(NSInteger)semitones;

/// Moves every pitched note to the nearest pitch in the given key and scale.
/// Noise tracks are left alone.
- (void)quantizePitchedNotesToScale:(MusicalScale)scale root:(NSInteger)root;

- (NSDictionary *)dictionaryRepresentation;
+ (instancetype)songFromDictionary:(NSDictionary *)dictionary error:(NSError **)error;
- (BOOL)validateWithError:(NSError **)error;

@end
