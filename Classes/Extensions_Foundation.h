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

#import <Foundation/Foundation.h>

// All extensions methods in this file are thread-safe

static inline BOOL NSRangeContainsIndex(NSRange range, NSUInteger index) {
  if ((range.location != NSNotFound) && range.length) {
    return (index >= range.location) && (index < range.location + range.length);
  }
  return NO;
}

static inline BOOL NSRangeContainsRange(NSRange range1, NSRange range2) {
  if ((range1.location != NSNotFound) && range1.length && (range2.location != NSNotFound) && range2.length) {
    return (range2.location >= range1.location) && (range2.location < range1.location + range1.length) &&
           (range2.location + range2.length >= range1.location) && (range2.location + range2.length < range1.location + range1.length);
  }
  return NO;
}

@interface NSString (Extensions)
- (BOOL) hasCaseInsensitivePrefix:(NSString*)prefix;
- (NSString*) urlEscapedString;  // Uses UTF-8 encoding and also escapes characters that can confuse the parameter string part of the URL
- (NSString*) unescapeURLString;  // Uses UTF-8 encoding
- (NSString*) extractFirstSentence;
- (NSArray*) extractAllSentences;
- (NSIndexSet*) extractSentenceIndices;
- (NSString*) stripParenthesis;  // Remove all parenthesis and their content
- (BOOL) containsString:(NSString*)string;
- (NSArray*) extractAllWords;
- (NSRange) rangeOfWordAtLocation:(NSUInteger)location;
- (NSRange) rangeOfNextWordFromLocation:(NSUInteger)location;
- (NSString*) stringByDeletingPrefix:(NSString*)prefix;
- (NSString*) stringByDeletingSuffix:(NSString*)suffix;
- (NSString*) stringByReplacingPrefix:(NSString*)prefix withString:(NSString*)string;
- (NSString*) stringByReplacingSuffix:(NSString*)suffix withString:(NSString*)string;
- (BOOL) isIntegerNumber;
@end

@interface NSMutableString (Extensions)
- (void) trimWhitespaceAndNewlineCharacters;  // From both ends
@end

@interface NSArray (Extensions)
- (id) firstObject;
@end

@interface NSMutableArray (Extensions)
- (void) removeFirstObject;
@end

@interface NSDate (Extensions)
+ (NSDate*) dateWithYear:(NSUInteger)year month:(NSUInteger)month day:(NSUInteger)day;
+ (NSDate*) dateWithYear:(NSUInteger)year
                   month:(NSUInteger)month
                     day:(NSUInteger)day
                    hour:(NSUInteger)hour
                  minute:(NSUInteger)minute
                  second:(NSUInteger)second;  // All numbers are 1 based
+ (NSDate*) dateWithDaysSinceReferenceDate:(NSInteger)days;
+ (NSDate*) dateWithString:(NSString*)string cachedFormat:(NSString*)format;  // Uses current locale and timezone
+ (NSDate*) dateWithString:(NSString*)string cachedFormat:(NSString*)format localIdentifier:(NSString*)identifier;  // Uses current timezone
+ (NSDate*) dateWithString:(NSString*)string
              cachedFormat:(NSString*)format
           localIdentifier:(NSString*)identifier  // Pass nil for current locale
                  timeZone:(NSTimeZone*)timeZone;  // Pass nil for current timezone
- (void) getYear:(NSUInteger*)year month:(NSUInteger*)month day:(NSUInteger*)day;
- (void) getYear:(NSUInteger*)year
           month:(NSUInteger*)month
             day:(NSUInteger*)day
            hour:(NSUInteger*)hour
          minute:(NSUInteger*)minute
          second:(NSUInteger*)second;  // All numbers are 1 based
- (NSDate*) dateRoundedToMidnight;
- (NSUInteger) daySinceBeginningOfTheYear;
- (NSInteger) daysSinceReferenceDate;
- (NSString*) stringWithCachedFormat:(NSString*)format;  // Uses current locale and timezone
- (NSString*) stringWithCachedFormat:(NSString*)format localIdentifier:(NSString*)identifier;  // Uses current timezone
- (NSString*) stringWithCachedFormat:(NSString*)format localIdentifier:(NSString*)identifier timeZone:(NSTimeZone*)timeZone;  // Pass nil for current locale and timezone
@end

@interface NSFileManager (Extensions)
- (NSString*) mimeTypeFromFileExtension:(NSString*)extension;
- (BOOL) getExtendedAttributeBytes:(void*)bytes length:(NSUInteger)length withName:(NSString*)name forFileAtPath:(NSString*)path;
- (NSData*) extendedAttributeDataWithName:(NSString*)name forFileAtPath:(NSString*)path;
- (NSString*) extendedAttributeStringWithName:(NSString*)name forFileAtPath:(NSString*)path;  // Uses UTF8 encoding
- (BOOL) setExtendedAttributeBytes:(const void*)bytes length:(NSUInteger)length withName:(NSString*)name forFileAtPath:(NSString*)path;
- (BOOL) setExtendedAttributeData:(NSData*)data withName:(NSString*)name forFileAtPath:(NSString*)path;
- (BOOL) setExtendedAttributeString:(NSString*)string withName:(NSString*)name forFileAtPath:(NSString*)path;  // Uses UTF8 encoding
- (BOOL) removeItemAtPathIfExists:(NSString*)path;
- (NSArray*) directoriesInDirectoryAtPath:(NSString*)path includeInvisible:(BOOL)invisible;
- (NSArray*) filesInDirectoryAtPath:(NSString*)path includeInvisible:(BOOL)invisible includeSymlinks:(BOOL)symlinks;
@end

@interface NSProcessInfo (Extensions)
- (BOOL) isDebuggerAttached;
@end

@interface NSURL (Extensions)
- (NSDictionary*) parseQueryParameters:(BOOL)unescape;
@end

@interface NSMutableURLRequest (Extensions)
- (void) setHTTPBodyWithMultipartFormArguments:(NSDictionary*)arguments;
- (void) setHTTPBodyWithMultipartFormArguments:(NSDictionary*)arguments fileData:(NSData*)fileData withFileType:(NSString*)fileType;
@end

@interface NSTimeZone (Extensions)
+ (NSTimeZone*) GMTTimeZone;
@end
