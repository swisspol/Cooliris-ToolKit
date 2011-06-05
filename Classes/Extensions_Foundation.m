// Copyright 2011 Cooliris, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#import <AvailabilityMacros.h>
#if TARGET_OS_IPHONE
#import <MobileCoreServices/MobileCoreServices.h>
#else
#import <CoreServices/CoreServices.h>
#endif
#import <libkern/OSAtomic.h>
#import <sys/xattr.h>
#import <sys/sysctl.h>
#import <unistd.h>
#import <dirent.h>
#import <sys/stat.h>

#import "Extensions_Foundation.h"
#import "Logging.h"

static OSSpinLock _calendarSpinLock = 0;
static OSSpinLock _formattersSpinLock = 0;
static OSSpinLock _staticSpinLock = 0;

typedef enum {
  kCharacterSet_Newline = 0,
  kCharacterSet_WhitespaceAndNewline,
  kCharacterSet_WhitespaceAndNewline_Inverted,
  kCharacterSet_UppercaseLetters,
  kCharacterSet_DecimalDigits_Inverted,
  kCharacterSet_WordBoundaries,
  kCharacterSet_SentenceBoundaries,
  kCharacterSet_SentenceBoundariesAndNewlineCharacter,
  kNumCharacterSets
} CharacterSet;

static NSCharacterSet* _GetCachedCharacterSet(CharacterSet set) {
  static NSCharacterSet* cache[kNumCharacterSets] = {0};
  if (cache[set] == nil) {
    OSSpinLockLock(&_staticSpinLock);
    if (cache[set] == nil) {
      switch (set) {
        case kCharacterSet_Newline:
          cache[set] = [[NSCharacterSet newlineCharacterSet] retain];
          break;
        case kCharacterSet_WhitespaceAndNewline:
          cache[set] = [[NSCharacterSet whitespaceAndNewlineCharacterSet] retain];
          break;
        case kCharacterSet_WhitespaceAndNewline_Inverted:
          cache[set] = [[[NSCharacterSet whitespaceAndNewlineCharacterSet] invertedSet] retain];
          break;
        case kCharacterSet_UppercaseLetters:
          cache[set] = [[NSCharacterSet uppercaseLetterCharacterSet] retain];
          break;
        case kCharacterSet_DecimalDigits_Inverted:
          cache[set] = [[[NSCharacterSet decimalDigitCharacterSet] invertedSet] retain];
          break;
        case kCharacterSet_WordBoundaries:
          cache[set] = [[NSMutableCharacterSet alloc] init];
          [(NSMutableCharacterSet*)cache[set] formUnionWithCharacterSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
          [(NSMutableCharacterSet*)cache[set] formUnionWithCharacterSet:[NSCharacterSet punctuationCharacterSet]];
          [(NSMutableCharacterSet*)cache[set] removeCharactersInString:@"-"];
          break;
        case kCharacterSet_SentenceBoundaries:
          cache[set] = [[NSMutableCharacterSet alloc] init];
          [(NSMutableCharacterSet*)cache[set] addCharactersInString:@".?!"];
          break;
        case kCharacterSet_SentenceBoundariesAndNewlineCharacter:
          cache[set] = [[NSMutableCharacterSet alloc] init];
          [(NSMutableCharacterSet*)cache[set] formUnionWithCharacterSet:[NSCharacterSet newlineCharacterSet]];
          [(NSMutableCharacterSet*)cache[set] addCharactersInString:@".?!"];
          break;
        case kNumCharacterSets:
          break;
      }
    }
    OSSpinLockUnlock(&_staticSpinLock);
  }
  return cache[set];
}

@implementation NSString (Extensions)

- (BOOL) hasCaseInsensitivePrefix:(NSString*)prefix {
  NSRange range = [self rangeOfString:prefix options:(NSCaseInsensitiveSearch | NSAnchoredSearch)];
  return range.location != NSNotFound;
}

- (NSString*) urlEscapedString {
  return [(id)CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, (CFStringRef)self, NULL, CFSTR(":@/?&=+"),
                                                      kCFStringEncodingUTF8) autorelease];
}

- (NSString*) unescapeURLString {
  return [(id)CFURLCreateStringByReplacingPercentEscapesUsingEncoding(kCFAllocatorDefault, (CFStringRef)self, CFSTR(""),
                                                                      kCFStringEncodingUTF8) autorelease];
}

static NSArray* _SpecialAbreviations() {
  static NSArray* array = nil;
  if (array == nil) {
    OSSpinLockLock(&_staticSpinLock);
    if (array == nil) {
      array = [[NSArray alloc] initWithObjects:@"vs", @"st", nil];
    }
    OSSpinLockUnlock(&_staticSpinLock);
  }
  return array;
}

// http://www.attivio.com/blog/57-unified-information-access/263-doing-things-with-words-part-two-sentence-boundary-detection.html
static void _ScanSentence(NSScanner* scanner) {
  NSUInteger initialLocation = scanner.scanLocation;
  while (1) {
    // Find next sentence boundary (return if at end)
    [scanner scanUpToCharactersFromSet:_GetCachedCharacterSet(kCharacterSet_SentenceBoundariesAndNewlineCharacter) intoString:NULL];
    if ([scanner isAtEnd]) {
      break;
    }
    NSUInteger boundaryLocation = scanner.scanLocation;
    
    // Skip sentence boundary (return if boundary is a newline or if at end)
    if (![scanner scanCharactersFromSet:_GetCachedCharacterSet(kCharacterSet_SentenceBoundaries) intoString:NULL]) {
      break;
    }
    if ([scanner isAtEnd]) {
      break;
    }
    
    // Make sure sentence boundary is followed by whitespace or newline
    NSRange range = [scanner.string rangeOfCharacterFromSet:_GetCachedCharacterSet(kCharacterSet_WhitespaceAndNewline)
                                                    options:NSAnchoredSearch
                                                      range:NSMakeRange(scanner.scanLocation, 1)];
    if (range.location == NSNotFound) {
      continue;
    }
    
    // Extract previous token
    range = [scanner.string rangeOfCharacterFromSet:_GetCachedCharacterSet(kCharacterSet_WhitespaceAndNewline)
                                            options:NSBackwardsSearch
                                              range:NSMakeRange(initialLocation, boundaryLocation - initialLocation)];
    if (range.location == NSNotFound) {
      continue;
    }
    range = NSMakeRange(range.location + 1, boundaryLocation - range.location - 1);
    
    // Make sure previous token is a not special abreviation
    BOOL match = NO;
    for (NSString* abreviation in _SpecialAbreviations()) {
      if (abreviation.length == range.length) {
        NSRange temp = [scanner.string rangeOfString:abreviation options:(NSAnchoredSearch | NSCaseInsensitiveSearch) range:range];
        if (temp.location != NSNotFound) {
          match = YES;
          break;
        }
      }
    }
    if (match) {
      continue;
    }
    
    // Make sure previous token does not contain a period or is more than 4 characters long or is followed by an uppercase letter
    NSRange subrange = [scanner.string rangeOfString:@"." options:0 range:range];
    if ((subrange.location != NSNotFound) && (range.length < 4)) {
      subrange = [scanner.string rangeOfCharacterFromSet:_GetCachedCharacterSet(kCharacterSet_WhitespaceAndNewline_Inverted)
                                                 options:0
                                                   range:NSMakeRange(scanner.scanLocation,
                                                                     scanner.string.length - scanner.scanLocation)];
      subrange = [scanner.string rangeOfCharacterFromSet:_GetCachedCharacterSet(kCharacterSet_UppercaseLetters)
                                                 options:NSAnchoredSearch
                                                   range:NSMakeRange(subrange.location != NSNotFound ?
                                                                     subrange.location : scanner.scanLocation, 1)];
      if (subrange.location == NSNotFound) {
        continue;
      }
    }
    
    // We have found a sentence
    break;
  }
}

- (NSString*) extractFirstSentence {
  NSScanner* scanner = [[NSScanner alloc] initWithString:self];
  scanner.charactersToBeSkipped = nil;
  _ScanSentence(scanner);
  self = [self substringToIndex:scanner.scanLocation];
  [scanner release];
  return self;
}

- (NSArray*) extractAllSentences {
  NSMutableArray* array = [NSMutableArray array];
  NSScanner* scanner = [[NSScanner alloc] initWithString:self];
  scanner.charactersToBeSkipped = nil;
  while (1) {
    [scanner scanCharactersFromSet:_GetCachedCharacterSet(kCharacterSet_WhitespaceAndNewline) intoString:NULL];
    if ([scanner isAtEnd]) {
      break;
    }
    NSUInteger location = scanner.scanLocation;
    _ScanSentence(scanner);
    if (scanner.scanLocation > location) {
      [array addObject:[self substringWithRange:NSMakeRange(location, scanner.scanLocation - location)]];
    }
  }
  [scanner release];
  return array;
}

- (NSIndexSet*) extractSentenceIndices {
  NSMutableIndexSet* set = [NSMutableIndexSet indexSet];
  NSScanner* scanner = [[NSScanner alloc] initWithString:self];
  scanner.charactersToBeSkipped = nil;
  while (1) {
    NSUInteger location = scanner.scanLocation;
    _ScanSentence(scanner);
    if (scanner.scanLocation > location) {
      [set addIndex:location];
    }
    [scanner scanCharactersFromSet:_GetCachedCharacterSet(kCharacterSet_WhitespaceAndNewline) intoString:NULL];
    if ([scanner isAtEnd]) {
      break;
    }
  }
  [scanner release];
  return set;
}

- (NSString*) stripParenthesis {
  NSMutableString* string = [NSMutableString string];
  NSRange range = NSMakeRange(0, self.length);
  while (range.length) {
    // Find location of start of parenthesis or end of string otherwise
    NSRange subrange = [self rangeOfString:@"(" options:0 range:range];
    if (subrange.location == NSNotFound) {
      subrange.location = range.location + range.length;
    } else {
      // Adjust the location to contain whitespace preceding the parenthesis
      NSRange subrange2 = [self rangeOfCharacterFromSet:_GetCachedCharacterSet(kCharacterSet_WhitespaceAndNewline_Inverted)
                                                options:NSBackwardsSearch
                                                  range:NSMakeRange(range.location, subrange.location - range.location)];
      if (subrange2.location + 1 < subrange.location) {
        subrange.length += subrange.location - subrange2.location - 1;
        subrange.location = subrange2.location + 1;
      }
    }
    
    // Copy characters until location
    [string appendString:[self substringWithRange:NSMakeRange(range.location, subrange.location - range.location)]];
    range.length -= subrange.location - range.location;
    range.location = subrange.location;
    
    // Skip characters from location to end of parenthesis or end of string otherwise
    if (range.length) {
      subrange = [self rangeOfString:@")" options:0 range:range];
      if (subrange.location == NSNotFound) {
        subrange.location = range.location + range.length;
      } else {
        subrange.location += 1;
      }
      range.length -= subrange.location - range.location;
      range.location = subrange.location;
    }
  }
  return string;
}

- (BOOL) containsString:(NSString*)string {
  NSRange range = [self rangeOfString:string];
  return range.location != NSNotFound;
}

- (NSArray*) extractAllWords {
  NSCharacterSet* characterSet = _GetCachedCharacterSet(kCharacterSet_WordBoundaries);
  if (self.length) {
    NSMutableArray* array = [NSMutableArray array];
    NSScanner* scanner = [[NSScanner alloc] initWithString:self];
    scanner.charactersToBeSkipped = nil;
    while (1) {
      [scanner scanCharactersFromSet:characterSet intoString:NULL];
      NSString* string;
      if (![scanner scanUpToCharactersFromSet:characterSet intoString:&string]) {
        break;
      }
      [array addObject:string];
    }
    [scanner release];
    return array;
  }
  return nil;
}

- (NSRange) rangeOfWordAtLocation:(NSUInteger)location {
  NSCharacterSet* characterSet = _GetCachedCharacterSet(kCharacterSet_WordBoundaries);
  if (![characterSet characterIsMember:[self characterAtIndex:location]]) {
    NSRange start = [self rangeOfCharacterFromSet:characterSet options:NSBackwardsSearch range:NSMakeRange(0, location)];
    if (start.location == NSNotFound) {
      start.location = 0;
    } else {
      start.location = start.location + 1;
    }
    NSRange end = [self rangeOfCharacterFromSet:characterSet options:0 range:NSMakeRange(location + 1, self.length - location - 1)];
    if (end.location == NSNotFound) {
      end.location = self.length;
    }
    return NSMakeRange(start.location, end.location - start.location);
  }
  return NSMakeRange(NSNotFound, 0);
}

- (NSRange) rangeOfNextWordFromLocation:(NSUInteger)location {
  NSCharacterSet* characterSet = _GetCachedCharacterSet(kCharacterSet_WordBoundaries);
  if ([characterSet characterIsMember:[self characterAtIndex:location]]) {
    NSRange start = [self rangeOfCharacterFromSet:[characterSet invertedSet] options:0 range:NSMakeRange(location,
                                                                                                         self.length - location)];
    if (start.location != NSNotFound) {
      NSRange end = [self rangeOfCharacterFromSet:characterSet options:0 range:NSMakeRange(start.location,
                                                                                           self.length - start.location)];
      if (end.location == NSNotFound) {
        end.location = self.length;
      }
      return NSMakeRange(start.location, end.location - start.location);
    }
  }
  return NSMakeRange(NSNotFound, 0);
}

- (NSString*) stringByDeletingPrefix:(NSString*)prefix {
  if ([self hasPrefix:prefix]) {
    return [self substringFromIndex:prefix.length];
  }
  return self;
}

- (NSString*) stringByDeletingSuffix:(NSString*)suffix {
  if ([self hasSuffix:suffix]) {
    return [self substringToIndex:(self.length - suffix.length)];
  }
  return self;
}

- (NSString*) stringByReplacingPrefix:(NSString*)prefix withString:(NSString*)string {
  if ([self hasPrefix:prefix]) {
    return [string stringByAppendingString:[self substringFromIndex:prefix.length]];
  }
  return self;
}

- (NSString*) stringByReplacingSuffix:(NSString*)suffix withString:(NSString*)string {
  if ([self hasSuffix:suffix]) {
    return [[self substringToIndex:(self.length - suffix.length)] stringByAppendingString:string];
  }
  return self;
}

- (BOOL) isIntegerNumber {
  NSRange range = NSMakeRange(0, self.length);
  if (range.length) {
    unichar character = [self characterAtIndex:0];
    if ((character == '+') || (character == '-')) {
      range.location = 1;
      range.length -= 1;
    }
    range = [self rangeOfCharacterFromSet:_GetCachedCharacterSet(kCharacterSet_DecimalDigits_Inverted) options:0 range:range];
    return range.location == NSNotFound;
  }
  return NO;
}

@end

@implementation NSMutableString (Extensions)

- (void) trimWhitespaceAndNewlineCharacters {
  NSRange range = [self rangeOfCharacterFromSet:_GetCachedCharacterSet(kCharacterSet_WhitespaceAndNewline_Inverted)];
  if ((range.location != NSNotFound) && (range.location > 0)) {
    [self deleteCharactersInRange:NSMakeRange(0, range.location)];
  }
  range = [self rangeOfCharacterFromSet:_GetCachedCharacterSet(kCharacterSet_WhitespaceAndNewline_Inverted)
                                options:NSBackwardsSearch];
  if ((range.location != NSNotFound) && (range.location < self.length - 1)) {
    [self deleteCharactersInRange:NSMakeRange(range.location, self.length - range.location)];
  }
}

@end

@implementation NSArray (Extensions)

- (id) firstObject {
  return self.count ? [self objectAtIndex:0] : nil;
}

@end

@implementation NSMutableArray (Extensions)

- (void) removeFirstObject {
  [self removeObjectAtIndex:0];
}

@end

@implementation NSDate (Extensions)

// NSCalendar is not thread-safe so we use a singleton protected by a spinlock
static inline NSCalendar* _GetSharedCalendar() {
  static NSCalendar* calendar = nil;
  if (calendar == nil) {
    calendar = [[NSCalendar currentCalendar] retain];
  }
  DCHECK(calendar.timeZone == [NSTimeZone defaultTimeZone]);
  calendar.timeZone = [NSTimeZone defaultTimeZone];  // This should be a no-op if the timezone hasn't changed
  return calendar;
}

+ (NSDate*) dateWithYear:(NSUInteger)year month:(NSUInteger)month day:(NSUInteger)day {
  return [self dateWithYear:year month:month day:day hour:0 minute:0 second:0];
}

+ (NSDate*) dateWithYear:(NSUInteger)year
                   month:(NSUInteger)month
                     day:(NSUInteger)day
                    hour:(NSUInteger)hour
                  minute:(NSUInteger)minute
                  second:(NSUInteger)second {
  NSDateComponents* components = [[NSDateComponents alloc] init];
  components.year = year;
  components.month = month;
  components.day = day;
  components.hour = hour;
  components.minute = minute;
  components.second = second;
  OSSpinLockLock(&_calendarSpinLock);
  NSDate* date = [_GetSharedCalendar() dateFromComponents:components];
  OSSpinLockUnlock(&_calendarSpinLock);
  [components release];
  return date;
}

- (void) getYear:(NSUInteger*)year month:(NSUInteger*)month day:(NSUInteger*)day {
  [self getYear:year month:month day:day hour:NULL minute:NULL second:NULL];
}

- (void) getYear:(NSUInteger*)year
           month:(NSUInteger*)month
             day:(NSUInteger*)day
            hour:(NSUInteger*)hour
          minute:(NSUInteger*)minute
          second:(NSUInteger*)second {
  NSUInteger flags = NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit;
  OSSpinLockLock(&_calendarSpinLock);
  NSDateComponents* components = [_GetSharedCalendar() components:flags fromDate:self];
  OSSpinLockUnlock(&_calendarSpinLock);
  if (year) {
    *year = components.year;
  }
  if (month) {
    *month = components.month;
  }
  if (day) {
    *day = components.day;
  }
  if (hour) {
    *hour = components.hour;
  }
  if (minute) {
    *minute = components.minute;
  }
  if (second) {
    *second = components.second;
  }
}

- (NSUInteger) daySinceBeginningOfTheYear {
  OSSpinLockLock(&_calendarSpinLock);
  NSDateComponents* components = [_GetSharedCalendar() components:NSYearCalendarUnit fromDate:self];
  NSDate* date = [_GetSharedCalendar() dateFromComponents:components];
  components = [_GetSharedCalendar() components:NSDayCalendarUnit fromDate:date toDate:self options:0];
  OSSpinLockUnlock(&_calendarSpinLock);
  return components.day + 1;
}

- (NSDate*) dateRoundedToMidnight {
  NSUInteger year;
  NSUInteger month;
  NSUInteger day;
  [self getYear:&year month:&month day:&day];
  return [NSDate dateWithYear:year month:month day:day];
}

static NSDate* _GetReferenceDay() {
  static NSDate* date = nil;
  if (date == nil) {
    OSSpinLockLock(&_staticSpinLock);
    if (date == nil) {
      date = [[NSDate dateWithYear:2001 month:1 day:1] retain];
    }
    OSSpinLockUnlock(&_staticSpinLock);
  }
  return date;
}

+ (NSDate*) dateWithDaysSinceReferenceDate:(NSInteger)days {
  NSDate* date = _GetReferenceDay();
  NSDateComponents* components = [[NSDateComponents alloc] init];
  components.day = days;
  OSSpinLockLock(&_calendarSpinLock);
  date = [_GetSharedCalendar() dateByAddingComponents:components toDate:date options:0];
  OSSpinLockUnlock(&_calendarSpinLock);
  [components release];
  return date;
}

- (NSInteger) daysSinceReferenceDate {
  NSDate* date = _GetReferenceDay();
  OSSpinLockLock(&_calendarSpinLock);
  NSDateComponents* components = [_GetSharedCalendar() components:NSDayCalendarUnit fromDate:date toDate:self options:0];
  OSSpinLockUnlock(&_calendarSpinLock);
  return components.day;
}

// NSDateFormatter is not thread-safe so this function is protected with a spinlock
static NSDateFormatter* _GetDateFormatter(NSString* format, NSString* identifier, NSTimeZone* timeZone) {
  static NSMutableDictionary* cacheLevel0 = nil;
  if (cacheLevel0 == nil) {
    cacheLevel0 = [[NSMutableDictionary alloc] init];
  }
  
  NSMutableDictionary* cacheLevel1 = [cacheLevel0 objectForKey:(identifier ? identifier : @"")];
  if (cacheLevel1 == nil) {
    cacheLevel1 = [[NSMutableDictionary alloc] init];
    [cacheLevel0 setObject:cacheLevel1 forKey:(identifier ? identifier : @"")];
    [cacheLevel1 release];
  }
  
  NSMutableDictionary* cacheLevel2 = [cacheLevel1 objectForKey:(timeZone ? [timeZone name] : @"")];
  if (cacheLevel2 == nil) {
    cacheLevel2 = [[NSMutableDictionary alloc] init];
    [cacheLevel1 setObject:cacheLevel2 forKey:(timeZone ? [timeZone name] : @"")];
    [cacheLevel2 release];
  }
  
  NSDateFormatter* formatter = [cacheLevel2 objectForKey:format];
  if (formatter == nil) {
    formatter = [[NSDateFormatter alloc] init];
    formatter.locale = identifier ? [[[NSLocale alloc] initWithLocaleIdentifier:identifier] autorelease] : [NSLocale currentLocale];
    formatter.timeZone = timeZone ? timeZone : [NSTimeZone defaultTimeZone];
    formatter.dateFormat = format;
    [cacheLevel2 setObject:formatter forKey:format];
    [formatter release];
  }
  
  return formatter;
}

+ (NSDate*) dateWithString:(NSString*)string cachedFormat:(NSString*)format {
  return [self dateWithString:string cachedFormat:format localIdentifier:nil timeZone:nil];
}

+ (NSDate*) dateWithString:(NSString*)string cachedFormat:(NSString*)format localIdentifier:(NSString*)identifier {
  return [self dateWithString:string cachedFormat:format localIdentifier:identifier timeZone:nil];
}

+ (NSDate*) dateWithString:(NSString*)string
              cachedFormat:(NSString*)format
           localIdentifier:(NSString*)identifier
                  timeZone:(NSTimeZone*)timeZone {
  OSSpinLockLock(&_formattersSpinLock);
  NSDateFormatter* formatter = _GetDateFormatter(format, identifier, timeZone);
  NSDate* date = [formatter dateFromString:string];
  OSSpinLockUnlock(&_formattersSpinLock);
  return date;
}

- (NSString*) stringWithCachedFormat:(NSString*)format {
  return [self stringWithCachedFormat:format localIdentifier:nil timeZone:nil];
}

- (NSString*) stringWithCachedFormat:(NSString*)format localIdentifier:(NSString*)identifier {
  return [self stringWithCachedFormat:format localIdentifier:identifier timeZone:nil];
}
- (NSString*) stringWithCachedFormat:(NSString*)format localIdentifier:(NSString*)identifier timeZone:(NSTimeZone*)timeZone {
  OSSpinLockLock(&_formattersSpinLock);
  NSDateFormatter* formatter = _GetDateFormatter(format, identifier, timeZone);
  NSString* string = [formatter stringFromDate:self];
  OSSpinLockUnlock(&_formattersSpinLock);
  return string;
}

@end

@implementation NSFileManager (Extensions)

- (NSString*) mimeTypeFromFileExtension:(NSString*)extension {
  NSString* type = nil;
  extension = [extension lowercaseString];
  if (extension.length) {
    CFStringRef identifier = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (CFStringRef)extension, NULL);
    if (identifier) {
      type = [(id)UTTypeCopyPreferredTagWithClass(identifier, kUTTagClassMIMEType) autorelease];
      CFRelease(identifier);
    }
  }
  if (!type.length) {
    type = @"application/octet-stream";
  }
  return type;
}

- (BOOL) getExtendedAttributeBytes:(void*)bytes length:(NSUInteger)length withName:(NSString*)name forFileAtPath:(NSString*)path {
  if (bytes) {
    const char* utf8Name = [name UTF8String];
    const char* utf8Path = [path UTF8String];
    ssize_t result = getxattr(utf8Path, utf8Name, bytes, length, 0, 0);
    if (result == length) {
      return YES;
    }
  }
  return NO;
}

- (NSData*) extendedAttributeDataWithName:(NSString*)name forFileAtPath:(NSString*)path {
  const char* utf8Name = [name UTF8String];
  const char* utf8Path = [path UTF8String];
  ssize_t result = getxattr(utf8Path, utf8Name, NULL, 0, 0, 0);
  if (result >= 0) {
    NSMutableData* data = [NSMutableData dataWithLength:result];
    if ([self getExtendedAttributeBytes:data.mutableBytes length:data.length withName:name forFileAtPath:path]) {
      return data;
    }
  }
  return nil;
}

- (NSString*) extendedAttributeStringWithName:(NSString*)name forFileAtPath:(NSString*)path {
  NSData* data = [self extendedAttributeDataWithName:name forFileAtPath:path];
  return data ? [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease] : nil;
}

- (BOOL) setExtendedAttributeBytes:(const void*)bytes length:(NSUInteger)length withName:(NSString*)name forFileAtPath:(NSString*)path {
  if (bytes || !length) {
    const char* utf8Name = [name UTF8String];
    const char* utf8Path = [path UTF8String];
    int result = setxattr(utf8Path, utf8Name, bytes, length, 0, 0);
    return (result >= 0 ? YES : NO);
  }
  return NO;
}

- (BOOL) setExtendedAttributeData:(NSData*)data withName:(NSString*)name forFileAtPath:(NSString*)path {
  return [self setExtendedAttributeBytes:data.bytes length:data.length withName:name forFileAtPath:path];
}

- (BOOL) setExtendedAttributeString:(NSString*)string withName:(NSString*)name forFileAtPath:(NSString*)path {
  NSData* data = [string dataUsingEncoding:NSUTF8StringEncoding];
  return data ? [self setExtendedAttributeData:data withName:name forFileAtPath:path] : NO;
}

- (BOOL) removeItemAtPathIfExists:(NSString*)path {
  if ([self fileExistsAtPath:path]) {
    return [self removeItemAtPath:path error:NULL];
  }
  return YES;
}

- (NSArray*) _itemsInDirectoryAtPath:(NSString*)path invisible:(BOOL)invisible type1:(mode_t)type1 type2:(mode_t)type2 {
  NSMutableArray* array = nil;
  const char* systemPath = [path fileSystemRepresentation];
  DIR* directory;
  if ((directory = opendir(systemPath))) {
    array = [NSMutableArray array];
    size_t baseLength = strlen(systemPath);
    struct dirent storage;
    struct dirent* entry;
    while(1) {
      if ((readdir_r(directory, &storage, &entry) != 0) || !entry) {
        break;
      }
      if (entry->d_ino == 0) {
        continue;
      }
      if (entry->d_name[0] == '.') {
        if ((entry->d_namlen == 1) || ((entry->d_namlen == 2) && (entry->d_name[1] == '.')) || !invisible) {
          continue;
        }
      }
      
      char* buffer = malloc(baseLength + 1 + entry->d_namlen + 1);
      bcopy(systemPath, buffer, baseLength);
      buffer[baseLength] = '/';
      bcopy(entry->d_name, &buffer[baseLength + 1], entry->d_namlen + 1);
      struct stat fileInfo;
      if (lstat(buffer, &fileInfo) == 0) {
        if (((fileInfo.st_mode & S_IFMT) == type1) || ((fileInfo.st_mode & S_IFMT) == type2)) {
          NSString* item = [self stringWithFileSystemRepresentation:entry->d_name length:entry->d_namlen];
          if (item) {
            [array addObject:item];
          }
        }
      }
      free(buffer);
    }
    closedir(directory);
  }
  return array;
}

- (NSArray*) directoriesInDirectoryAtPath:(NSString*)path includeInvisible:(BOOL)invisible {
  return [self _itemsInDirectoryAtPath:path invisible:invisible type1:S_IFDIR type2:0];
}

- (NSArray*) filesInDirectoryAtPath:(NSString*)path includeInvisible:(BOOL)invisible includeSymlinks:(BOOL)symlinks {
  return [self _itemsInDirectoryAtPath:path invisible:invisible type1:S_IFREG type2:(symlinks ? S_IFLNK : 0)];
}

@end

@implementation NSProcessInfo (Extensions)

// From http://developer.apple.com/mac/library/qa/qa2004/qa1361.html
- (BOOL) isDebuggerAttached {
  struct kinfo_proc info;
  info.kp_proc.p_flag = 0;
  
  int mib[4];
  mib[0] = CTL_KERN;
  mib[1] = KERN_PROC;
  mib[2] = KERN_PROC_PID;
  mib[3] = getpid();
  size_t size = sizeof(info);
  int result = sysctl(mib, sizeof(mib) / sizeof(*mib), &info, &size, NULL, 0);
  
  return !result && (info.kp_proc.p_flag & P_TRACED);  // We're being debugged if the P_TRACED flag is set
}

@end

@implementation NSURL (Extensions)

- (NSDictionary*) parseQueryParameters:(BOOL)unescape {
  NSMutableDictionary* parameters = nil;
  NSString* query = [self query];
  if (query) {
    parameters = [NSMutableDictionary dictionary];
    NSScanner* scanner = [[NSScanner alloc] initWithString:query];
    [scanner setCharactersToBeSkipped:nil];
    while (1) {
      NSString* key = nil;
      if (![scanner scanUpToString:@"=" intoString:&key] || [scanner isAtEnd]) {
        break;
      }
      [scanner setScanLocation:([scanner scanLocation] + 1)];
      
      NSString* value = nil;
      if (![scanner scanUpToString:@"&" intoString:&value]) {
        break;
      }
      
      if (unescape) {
        [parameters setObject:[value unescapeURLString] forKey:[key unescapeURLString]];
      } else {
        [parameters setObject:value forKey:key];
      }
      
      if ([scanner isAtEnd]) {
        break;
      }
      [scanner setScanLocation:([scanner scanLocation] + 1)];
    }
    [scanner release];
  }
  return parameters;
}

@end

@implementation NSMutableURLRequest (Extensions)

- (void) setHTTPBodyWithMultipartFormArguments:(NSDictionary*)arguments {
  [self setHTTPBodyWithMultipartFormArguments:arguments fileData:nil withFileType:nil];
}

- (void) setHTTPBodyWithMultipartFormArguments:(NSDictionary*)arguments fileData:(NSData*)fileData withFileType:(NSString*)fileType {
  NSString* boundary = @"0xKhTmLbOuNdArY";
  [self setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary] forHTTPHeaderField:@"Content-Type"];
  
  NSMutableData* body = [[NSMutableData alloc] init];
  for (NSString* key in arguments) {
    id value = [arguments objectForKey:key];
    if ([value isKindOfClass:[NSString class]]) {
      value = [(NSString*)value dataUsingEncoding:NSUTF8StringEncoding];
    } else if (![value isKindOfClass:[NSData class]]) {
      DNOT_REACHED();
      continue;
    }
    [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    NSString* disposition = [NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n\r\n", key];
    [body appendData:[disposition dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:value];
    [body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
  }
  if (fileData && fileType) {
    [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"Content-Disposition: form-data; name=\"file\"; filename=\"file\"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"Content-Type: %@\r\n\r\n", fileType] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:fileData];
    [body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
  }
  [body appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
  [self setHTTPBody:body];
  [body release];
}

@end

@implementation NSTimeZone (Extensions)

+ (NSTimeZone*) GMTTimeZone {
  static NSTimeZone* timeZone = nil;
  if (timeZone == nil) {
    timeZone = [[NSTimeZone alloc] initWithName:@"GMT"];
    CHECK(timeZone);
  }
  return timeZone;
}

@end
