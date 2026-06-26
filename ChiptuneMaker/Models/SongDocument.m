#import "SongDocument.h"
#import "MainWindowController.h"

NSNotificationName const SongDocumentDidChangeNotification = @"SongDocumentDidChangeNotification";

@implementation SongDocument

- (instancetype)init {
    self = [super init];
    if (self) {
        _song = [Song defaultSong];
    }
    return self;
}

- (instancetype)initWithType:(NSString *)typeName error:(NSError **)outError {
    self = [super initWithType:typeName error:outError];
    if (self) {
        _song = [Song defaultSong];
    }
    return self;
}

- (void)makeWindowControllers {
    MainWindowController *controller = [[MainWindowController alloc] initWithDocument:self];
    [self addWindowController:controller];
}

- (BOOL)autosavesInPlace {
    return YES;
}

- (BOOL)isEntireFileLoaded {
    return YES;
}

- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError {
    self.song.modifiedAt = [NSDate date];
    NSError *validationError = nil;
    if (![self.song validateWithError:&validationError]) {
        if (outError) *outError = validationError;
        return nil;
    }
    NSDictionary *dictionary = [self.song dictionaryRepresentation];
    NSJSONWritingOptions options = NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys;
    NSData *data = [NSJSONSerialization dataWithJSONObject:dictionary options:options error:outError];
    return data;
}

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)outError {
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:outError];
    if (!object) return NO;
    NSError *songError = nil;
    Song *song = [Song songFromDictionary:object error:&songError];
    if (!song) {
        if (outError) *outError = songError;
        return NO;
    }
    self.song = song;
    [self notifySongChanged];
    return YES;
}

- (void)performEditNamed:(NSString *)actionName block:(void (^)(Song *song))block {
    if (!block) return;
    Song *previous = [self.song copy];
    [self.undoManager registerUndoWithTarget:self selector:@selector(restoreSong:) object:previous];
    [self.undoManager setActionName:actionName];
    block(self.song);
    [self.song sortNotes];
    [self updateChangeCount:NSChangeDone];
    [self notifySongChanged];
}

- (void)restoreSong:(Song *)song {
    if (!song) return;
    Song *current = [self.song copy];
    [self.undoManager registerUndoWithTarget:self selector:@selector(restoreSong:) object:current];
    [self.undoManager setActionName:@"Edit"];
    self.song = song;
    [self updateChangeCount:NSChangeUndone];
    [self notifySongChanged];
}

- (void)notifySongChanged {
    [[NSNotificationCenter defaultCenter] postNotificationName:SongDocumentDidChangeNotification object:self];
}

@end
