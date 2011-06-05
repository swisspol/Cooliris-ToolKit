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

#import "TextIndex.h"
#import "Crypto.h"
#import "Logging.h"

#define kInitialListSize 16
#define kMaxWordLength 128

typedef struct {
  MD5 md5;
  uint32_t rehash;
} WordHash;

static NSUInteger _minimumWordLength = 0;
static TextIndex* _stopWords = nil;
static CFMutableCharacterSetRef _boundaryCharacters = NULL;

// From Sigma source - SigmaPointerHash()
static inline uint32_t _HashFNV1a(const void* ptr, size_t len) {
  uint8_t* data = (uint8_t*)ptr;
  uint32_t hash = 2166136261u;
  for (size_t i = 0; i < len; i++) {
    hash ^= data[i];
    hash *= 16777619;
  }
  return hash;
}

// TODO: Use a binary search tree
static inline BOOL _HashListContainsHash(const WordHash* list, NSUInteger count, const WordHash* hash) {
  for (NSUInteger i = 0; i < count; ++i) {
    if ((list[i].rehash == hash->rehash) && MD5EqualToMD5(&list[i].md5, &hash->md5)) {
      return YES;
    }
  }
  return NO;
}

@implementation TextIndex

+ (void) initialize {
  if (_boundaryCharacters == NULL) {
    _boundaryCharacters = CFCharacterSetCreateMutable(kCFAllocatorDefault);
    CFCharacterSetUnion(_boundaryCharacters, CFCharacterSetGetPredefined(kCFCharacterSetWhitespaceAndNewline));
    CFCharacterSetUnion(_boundaryCharacters, CFCharacterSetGetPredefined(kCFCharacterSetPunctuation));
  }
}

+ (void) setMinimumWordLength:(NSUInteger)length {
  _minimumWordLength = length;
}

+ (void) setStopWords:(NSString*)stopWords {
  [_stopWords release];
  _stopWords = nil;
  TextIndex* index = [[TextIndex alloc] init];
  [index updateWithString:stopWords minimumWordLength:_minimumWordLength stopWords:0];
  if (index.empty) {
    [index release];
  } else {
    _stopWords = index;
  }
}

- (id) init {
  if ((self = [super init])) {
    _maxCount = kInitialListSize;
    _wordCount = 0;
    _wordList = malloc(_maxCount * sizeof(WordHash));
  }
  return self;
}

- (void) dealloc {
  if (_wordList) {
    free(_wordList);
  }
  
  [super dealloc];
}

- (void) encodeWithCoder:(NSCoder*)coder {
  CHECK([coder isKindOfClass:[NSKeyedArchiver class]]);
  [coder encodeInteger:_wordCount forKey:@"wordCount"];
  [coder encodeBytes:_wordList length:(_wordCount * sizeof(WordHash)) forKey:@"wordList"];
}

- (id) initWithCoder:(NSCoder*)coder {
  CHECK([coder isKindOfClass:[NSKeyedUnarchiver class]]);
  if ((self = [super init])) {
    _wordCount = [coder decodeIntegerForKey:@"wordCount"];
    _maxCount = (_wordCount / kInitialListSize + 1) * kInitialListSize;
    _wordList = malloc(_maxCount * sizeof(WordHash));
    NSUInteger length = 0;
    const uint8_t* bytes = [coder decodeBytesForKey:@"wordList" returnedLength:&length];
    CHECK(length == _wordCount * sizeof(WordHash));
    bcopy(bytes, _wordList, _wordCount * sizeof(WordHash));
  }
  return self;
}

- (BOOL) isEmpty {
  return _wordCount == 0;
}

- (void) updateWithString:(NSString*)string {
  [self updateWithString:string minimumWordLength:_minimumWordLength stopWords:_stopWords];
}

- (void) updateWithString:(NSString*)string minimumWordLength:(NSUInteger)minimumWordLength stopWords:(TextIndex*)stopWords {
  if (string.length) {
    CFMutableStringRef normalizedString = CFStringCreateMutable(kCFAllocatorDefault, 0);
    CFStringReplaceAll(normalizedString, (CFStringRef)string);
    CFStringNormalize(normalizedString, kCFStringNormalizationFormD);  // Separate accents from letters
    CFStringInlineBuffer buffer;
    CFStringInitInlineBuffer(normalizedString, &buffer, CFRangeMake(0, CFStringGetLength(normalizedString)));
    
    CFIndex index = 0;
    while (1) {
      // Skip boundary characters
      while (1) {
        UniChar character = CFStringGetCharacterFromInlineBuffer(&buffer, index);
        if (character == 0) {
          goto Done;
        }
        if (!CFCharacterSetIsCharacterMember(_boundaryCharacters, character)) {
          break;
        }
        ++index;
      }
      
      // Scan word until next boundary character
      unsigned char word[kMaxWordLength];
      NSUInteger count = 0;
      while (1) {
        UniChar character = CFStringGetCharacterFromInlineBuffer(&buffer, index++);
        if (character == 0) {
          break;
        }
        if (CFCharacterSetIsCharacterMember(_boundaryCharacters, character)) {
          break;
        } else if ((character < 128) && (count < kMaxWordLength)) {
          if ((character >= 'A') && (character <= 'Z')) {
            character = character - 'A' + 'a';
          }
          word[count] = character;
          count += 1;
        }
      }
      
      // Ignore words longer than the maximum length
      if (count >= kMaxWordLength) {
        continue;
      }
      
      // Ignore words shorter than the minimum length
      if (count < minimumWordLength) {
        continue;
      }
      
      // Add word to list if not a stop word and not already in list
      if (_wordCount >= _maxCount) {
        _maxCount = 2 * _maxCount;
        _wordList = realloc(_wordList, _maxCount * sizeof(WordHash));
      }
      WordHash* hash = &((WordHash*)_wordList)[_wordCount];
      hash->md5 = MD5WithBytes(word, count);
      hash->rehash = _HashFNV1a(&hash->md5, sizeof(MD5));
      if (stopWords && _HashListContainsHash((WordHash*)stopWords->_wordList, stopWords->_wordCount, hash)) {
        // LOG_DEBUG(@"Skipping \"%@\" from TextIndex",
        //           [[[NSString alloc] initWithBytes:word length:count encoding:NSASCIIStringEncoding] autorelease]);
        hash = NULL;
      }
      if (hash && !_HashListContainsHash((WordHash*)_wordList, _wordCount, hash)) {
        // LOG_DEBUG(@"Adding \"%@\" to TextIndex",
        //           [[[NSString alloc] initWithBytes:word length:count encoding:NSASCIIStringEncoding] autorelease]);
        _wordCount += 1;
      }
    }
    
Done:
    CFRelease(normalizedString);
  }
}

- (BOOL) intersectsTextIndex:(TextIndex*)index {
  if (index && index->_wordCount && _wordCount) {
    for (NSUInteger i = 0; i < _wordCount; ++i) {
      WordHash* hash = &((WordHash*)_wordList)[i];
      if (_HashListContainsHash((WordHash*)index->_wordList, index->_wordCount, hash)) {
        return YES;
      }
    }
  }
  return NO;
}

- (BOOL) containsTextIndex:(TextIndex*)index {
  if (index && index->_wordCount && _wordCount) {
    for (NSUInteger i = 0; i < index->_wordCount; ++i) {
      WordHash* hash = &((WordHash*)index->_wordList)[i];
      if (!_HashListContainsHash((WordHash*)_wordList, _wordCount, hash)) {
        return NO;
      }
    }
    return YES;
  }
  return NO;
}

@end

@implementation TextIndex (Serialization)

- (id) initWithDataRepresentation:(NSData*)data {
  CHECK(data.length % sizeof(WordHash) == 0);
  if ((self = [super init])) {
    _wordCount = data.length / sizeof(WordHash);
    _maxCount = (_wordCount / kInitialListSize + 1) * kInitialListSize;
    _wordList = malloc(_maxCount * sizeof(WordHash));
    bcopy(data.bytes, _wordList, _wordCount * sizeof(WordHash));
  }
  return self;
}

- (NSData*) dataRepresentation {
  return [NSData dataWithBytes:_wordList length:(_wordCount * sizeof(WordHash))];
}

@end
