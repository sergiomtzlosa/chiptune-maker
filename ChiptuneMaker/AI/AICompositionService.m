#import "AICompositionService.h"
#import "Song.h"
#import "Track.h"
#import "SongSection.h"
#import "NoteEvent.h"
#import "SongTypes.h"

static NSError *AIError(NSString *message) {
    return [NSError errorWithDomain:@"ChiptuneMaker.AI" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

static BOOL IsKnownInstrument(NSString *identifier) {
    for (NSInteger i = ChipInstrumentPulse12; i <= ChipInstrumentWavetable; i++) {
        if ([identifier isEqualToString:ChipInstrumentIdentifier((ChipInstrument)i)]) return YES;
    }
    return NO;
}

static BOOL ReadInteger(NSDictionary *dictionary, NSString *key, NSInteger *value) {
    id object = dictionary[key];
    if (![object isKindOfClass:[NSNumber class]]) return NO;
    double number = [object doubleValue];
    if (number != floor(number)) return NO;
    *value = [object integerValue];
    return YES;
}

static NSString *ExtractJSONText(NSString *response) {
    if (response.length == 0) return @"";
    NSString *text = [response stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([text hasPrefix:@"```"]) {
        NSRange firstNewline = [text rangeOfString:@"\n"];
        if (firstNewline.location != NSNotFound) {
            text = [text substringFromIndex:firstNewline.location + 1];
        }
        NSRange fence = [text rangeOfString:@"```" options:NSBackwardsSearch];
        if (fence.location != NSNotFound) {
            text = [text substringToIndex:fence.location];
        }
    }
    NSRange start = [text rangeOfString:@"{"];
    NSRange end = [text rangeOfString:@"}" options:NSBackwardsSearch];
    if (start.location == NSNotFound || end.location == NSNotFound || end.location <= start.location) {
        return text;
    }
    return [text substringWithRange:NSMakeRange(start.location, end.location - start.location + 1)];
}

@implementation AICompositionDraft
@end

@implementation AICompositionService

+ (NSString *)promptForSong:(Song *)song targetTrackIndex:(NSInteger)targetTrackIndex brief:(NSString *)brief {
    NSMutableString *prompt = [NSMutableString string];
    [prompt appendString:@"You are composing chiptune music for a tracker-style macOS app. Return JSON only, no markdown, no commentary.\n\n"];
    [prompt appendString:@"SONG CONTEXT\n"];
    [prompt appendFormat:@"Title: %@\n", song.title.length ? song.title : @"Untitled"];
    [prompt appendFormat:@"Tempo: %.0f BPM\n", song.tempo];
    [prompt appendFormat:@"Time signature: %ld/%ld\n", (long)song.timeSignatureNumerator, (long)song.timeSignatureDenominator];
    [prompt appendFormat:@"Key: %@ %@\n", NoteNames()[MAX(0, MIN(11, song.keyRoot))], MusicalScaleDisplayName(song.scale)];
    [prompt appendFormat:@"Length: %ld bars, 480 PPQ, %llu ticks per bar\n", (long)song.lengthBars, (unsigned long long)song.ticksPerBar];
    if (song.sections.count > 0) {
        [prompt appendString:@"Sections:\n"];
        for (SongSection *section in song.sections) {
            [prompt appendFormat:@"- %@: bar %ld, %ld bars\n", section.name, (long)section.startBar, (long)section.lengthBars];
        }
    }

    if (targetTrackIndex >= 0 && targetTrackIndex < (NSInteger)song.tracks.count) {
        Track *track = song.tracks[(NSUInteger)targetTrackIndex];
        [prompt appendFormat:@"\nTARGET\nReplace only track %ld, named “%@”, currently using %@. Return exactly one track.\n",
         (long)targetTrackIndex, track.name, ChipInstrumentDisplayName(track.instrument)];
    } else {
        [prompt appendString:@"\nTARGET\nCompose a complete arrangement. Return 1 to 8 tracks. Suggested roles: lead, harmony/arpeggio, bass, drums.\n"];
    }

    [prompt appendFormat:@"\nMUSICAL BRIEF\n%@\n", brief.length ? brief : @"A short, catchy chiptune loop."];
    [prompt appendString:@"\nINSTRUMENTS\nUse only these identifiers: pulse12, pulse25, pulse50, triangle, noise, wavetable. Use noise for drums.\n"];
    [prompt appendString:@"\nJSON SCHEMA\n"];
    [prompt appendString:@"{\"tracks\":[{\"name\":\"Lead\",\"instrument\":\"pulse25\",\"notes\":[{\"pitch\":69,\"startTick\":0,\"durationTicks\":240,\"velocity\":100}]}]}\n"];
    [prompt appendString:@"\nRULES\n"];
    [prompt appendString:@"- pitch is a MIDI note number from 0 to 127.\n"];
    [prompt appendString:@"- startTick and durationTicks are integer ticks at 480 PPQ.\n"];
    [prompt appendString:@"- Notes must start inside the song and must not extend past its final tick.\n"];
    [prompt appendString:@"- velocity is 1 to 127.\n"];
    [prompt appendString:@"- Use at most 2000 notes total. Quantize rhythm to 16th notes (120 ticks) or finer.\n"];
    [prompt appendString:@"- Stay in the selected key and scale. Keep bass notes low and lead notes in a singable range.\n"];
    [prompt appendString:@"- Return JSON only.\n"];
    return prompt;
}

+ (AICompositionDraft *)draftFromResponse:(NSString *)response
                                     song:(Song *)song
                         targetTrackIndex:(NSInteger)targetTrackIndex
                                    error:(NSError **)error {
    NSString *jsonText = ExtractJSONText(response);
    NSData *data = [jsonText dataUsingEncoding:NSUTF8StringEncoding];
    id object = data.length > 0 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    if (![object isKindOfClass:[NSDictionary class]]) {
        if (error) *error = AIError(@"The AI response did not contain a JSON object. Try regenerating.");
        return nil;
    }

    NSArray *trackEntries = object[@"tracks"];
    if (![trackEntries isKindOfClass:[NSArray class]]) {
        if (error) *error = AIError(@"The AI response is missing a “tracks” array.");
        return nil;
    }
    if (targetTrackIndex >= 0) {
        if (trackEntries.count != 1) {
            if (error) *error = AIError([NSString stringWithFormat:@"Expected exactly one track for this target, but the AI returned %lu.", (unsigned long)trackEntries.count]);
            return nil;
        }
    } else if (trackEntries.count < 1 || trackEntries.count > 8) {
        if (error) *error = AIError([NSString stringWithFormat:@"The AI returned %lu tracks; the song supports 1 to 8.", (unsigned long)trackEntries.count]);
        return nil;
    }

    uint64_t totalTicks = song.totalTicks;
    NSInteger totalNotes = 0;
    NSMutableArray<Track *> *tracks = [NSMutableArray array];
    NSMutableArray<NSString *> *summaries = [NSMutableArray array];

    for (id entry in trackEntries) {
        if (![entry isKindOfClass:[NSDictionary class]]) {
            if (error) *error = AIError(@"A track entry in the AI response is not an object.");
            return nil;
        }
        NSDictionary *trackDictionary = entry;
        NSString *instrumentIdentifier = trackDictionary[@"instrument"];
        if (![instrumentIdentifier isKindOfClass:[NSString class]] || !IsKnownInstrument(instrumentIdentifier)) {
            if (error) *error = AIError([NSString stringWithFormat:@"Unknown instrument “%@” in the AI response.", instrumentIdentifier ?: @"(missing)"]);
            return nil;
        }
        NSArray *noteEntries = trackDictionary[@"notes"];
        if (![noteEntries isKindOfClass:[NSArray class]]) {
            if (error) *error = AIError(@"A track in the AI response is missing a “notes” array.");
            return nil;
        }
        if (noteEntries.count == 0) {
            if (error) *error = AIError(@"The AI returned a track with no notes.");
            return nil;
        }
        totalNotes += (NSInteger)noteEntries.count;
        if (totalNotes > 2000) {
            if (error) *error = AIError(@"The AI response contains more than 2000 notes.");
            return nil;
        }

        NSString *name = trackDictionary[@"name"];
        Track *track = [Track trackWithName:([name isKindOfClass:[NSString class]] && name.length > 0 ? name : @"AI Track")
                                 instrument:ChipInstrumentFromIdentifier(instrumentIdentifier)];

        NSInteger minimumPitch = 128;
        NSInteger maximumPitch = -1;
        for (id noteEntry in noteEntries) {
            if (![noteEntry isKindOfClass:[NSDictionary class]]) {
                if (error) *error = AIError(@"A note in the AI response is not an object.");
                return nil;
            }
            NSDictionary *noteDictionary = noteEntry;
            NSInteger pitch = 0, startTick = 0, duration = 0, velocity = 0;
            if (!ReadInteger(noteDictionary, @"pitch", &pitch) ||
                !ReadInteger(noteDictionary, @"startTick", &startTick) ||
                !ReadInteger(noteDictionary, @"durationTicks", &duration) ||
                !ReadInteger(noteDictionary, @"velocity", &velocity)) {
                if (error) *error = AIError(@"Every note needs integer pitch, startTick, durationTicks, and velocity fields.");
                return nil;
            }
            if (pitch < 0 || pitch > 127) {
                if (error) *error = AIError([NSString stringWithFormat:@"Note pitch %ld is outside 0–127.", (long)pitch]);
                return nil;
            }
            if (startTick < 0 || duration <= 0) {
                if (error) *error = AIError(@"Notes must have a non-negative start tick and a positive duration.");
                return nil;
            }
            if (velocity < 1 || velocity > 127) {
                if (error) *error = AIError([NSString stringWithFormat:@"Note velocity %ld is outside 1–127.", (long)velocity]);
                return nil;
            }
            uint64_t start = (uint64_t)startTick;
            uint64_t length = (uint64_t)duration;
            if (start >= totalTicks) {
                if (error) *error = AIError([NSString stringWithFormat:@"A note starts at tick %llu, beyond the end of the song (%llu ticks).", (unsigned long long)start, (unsigned long long)totalTicks]);
                return nil;
            }
            if (length > totalTicks - start) {
                if (error) *error = AIError([NSString stringWithFormat:@"A note starting at tick %llu extends past the end of the song.", (unsigned long long)start]);
                return nil;
            }
            [track.notes addObject:[NoteEvent noteWithPitch:pitch startTick:start durationTicks:length velocity:velocity]];
            minimumPitch = MIN(minimumPitch, pitch);
            maximumPitch = MAX(maximumPitch, pitch);
        }
        [track sortNotes];
        [tracks addObject:track];
        [summaries addObject:[NSString stringWithFormat:@"%@: %lu notes, %@–%@",
                             track.name, (unsigned long)track.notes.count,
                             NoteNameForPitch(minimumPitch), NoteNameForPitch(maximumPitch)]];
    }

    AICompositionDraft *draft = [[AICompositionDraft alloc] init];
    draft.tracks = tracks;
    draft.rawResponse = response;
    draft.targetTrackIndex = targetTrackIndex;
    draft.summary = [summaries componentsJoinedByString:@"\n"];
    return draft;
}

+ (BOOL)applyDraft:(AICompositionDraft *)draft toSong:(Song *)song error:(NSError **)error {
    if (!draft || draft.tracks.count == 0) {
        if (error) *error = AIError(@"There is no AI draft to apply.");
        return NO;
    }
    if (draft.targetTrackIndex >= 0) {
        if (draft.targetTrackIndex >= (NSInteger)song.tracks.count) {
            if (error) *error = AIError(@"The target track no longer exists.");
            return NO;
        }
        Track *target = song.tracks[(NSUInteger)draft.targetTrackIndex];
        Track *source = draft.tracks.firstObject;
        target.instrument = source.instrument;
        target.notes = [NSMutableArray arrayWithArray:source.notes];
        return YES;
    }
    if (draft.tracks.count > 8) {
        if (error) *error = AIError(@"The AI draft contains too many tracks.");
        return NO;
    }
    [song.tracks setArray:draft.tracks];
    return YES;
}

@end
