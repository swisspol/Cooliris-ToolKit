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

#import "RichString.h"
#import "Extensions_Foundation.h"
#import "SmartDescription.h"
#import "Logging.h"

#define kDefaultMaxStateRuns 64

typedef struct {
  NSUInteger location;
  NSUInteger state;
} StateRun;

@interface RichAttachment ()
@property(nonatomic) NSUInteger location;
@end

@implementation RichAttachment

@synthesize location=_location;

- (id) init {
  if ((self = [super init])) {
    _location = NSNotFound;
  }
  return self;
}

- (void) encodeWithCoder:(NSCoder*)coder {
  CHECK([coder isKindOfClass:[NSKeyedArchiver class]]);
  [coder encodeInteger:_location forKey:@"location"];
}

- (id) initWithCoder:(NSCoder*)coder {
  CHECK([coder isKindOfClass:[NSKeyedUnarchiver class]]);
  if ((self = [super init])) {
    _location = [coder decodeIntegerForKey:@"location"];
  }
  return self;
}

- (NSString*) description {
  return [self miniDescription];
}

@end

@implementation RichString

@synthesize string=_string, attachments=_attachments;

- (id) init {
  if ((self = [super init])) {
    _string = [[NSMutableString alloc] init];
    _maxStateRuns = kDefaultMaxStateRuns;
    _stateRunCount = 0;
    _stateRunList = malloc(_maxStateRuns * sizeof(StateRun));
    _attachments = [[NSMutableArray alloc] init];
  }
  return self;
}

- (void) dealloc {
  [_attachments release];
  if (_stateRunList) {
    free(_stateRunList);
  }
  [_string release];
  
  [super dealloc];
}

- (void) encodeWithCoder:(NSCoder*)coder {
  CHECK([coder isKindOfClass:[NSKeyedArchiver class]]);
  
  [coder encodeObject:_string forKey:@"string"];
  
  [coder encodeObject:[NSData dataWithBytesNoCopy:_stateRunList length:(_stateRunCount * sizeof(StateRun)) freeWhenDone:NO]
               forKey:@"stateRuns"];
  
  [coder encodeObject:_attachments forKey:@"attachments"];
}

- (id) initWithCoder:(NSCoder*)coder {
  CHECK([coder isKindOfClass:[NSKeyedUnarchiver class]]);
  if ((self = [super init])) {
    _string = [[coder decodeObjectForKey:@"string"] retain];
    
    NSData* stateRuns = [coder decodeObjectForKey:@"stateRuns"];
    CHECK(stateRuns.length % sizeof(StateRun) == 0);
    _stateRunCount = stateRuns.length / sizeof(StateRun);
    _maxStateRuns = MAX(_stateRunCount, kDefaultMaxStateRuns);
    _stateRunList = malloc(_maxStateRuns * sizeof(StateRun));
    bcopy(stateRuns.bytes, _stateRunList, _stateRunCount * sizeof(StateRun));
    
    _attachments = [[coder decodeObjectForKey:@"attachments"] retain];
  }
  return self;
}

- (NSUInteger) length {
  return _string.length;
}

- (NSUInteger) numberOfAttachments {
  return _attachments.count;
}

- (void) trimToLocation:(NSUInteger)location {
  [_string deleteCharactersInRange:NSMakeRange(location, _string.length - location)];
  
  for (NSUInteger i = 0; i < _stateRunCount; ++i) {
    if (((StateRun*)_stateRunList)[i].location >= location) {
      _stateRunCount = i;
      break;
    }
  }
  
  NSUInteger count = _attachments.count;
  for (NSUInteger i = 0; i < count; ++i) {
    if ([(RichAttachment*)[_attachments objectAtIndex:i] location] >= location) {
      [_attachments removeObjectsInRange:NSMakeRange(i, count - i)];
      break;
    }
  }
}

- (void) clearString {
  [_string setString:@""];
  _stateRunCount = 0;
  for (RichAttachment* attachment in _attachments) {
    attachment.location = 0;
  }
}

- (void) appendString:(NSString*)string {
  [_string appendString:string];
}

- (void) setState:(NSUInteger)state {
  if (_stateRunCount > 0) {
    if (((StateRun*)_stateRunList)[_stateRunCount - 1].state == state) {
      return;  // The current state is the same: nothing to do
    }
    if (((StateRun*)_stateRunList)[_stateRunCount - 1].location == _string.length) {
      --_stateRunCount;  // The current state is different but we're still at the same location: replace current state
    }
  }
  if (_stateRunCount == _maxStateRuns) {
    _maxStateRuns *= 2;
    _stateRunList = realloc(_stateRunList, _maxStateRuns * sizeof(StateRun));
  }
  ((StateRun*)_stateRunList)[_stateRunCount].location = _string.length;
  ((StateRun*)_stateRunList)[_stateRunCount].state = state;
  ++_stateRunCount;
}

- (NSUInteger) findFirstState:(NSUInteger*)state {
  if (_stateRunCount) {
    if (state) {
      *state = ((StateRun*)_stateRunList)[0].state;
    }
    return ((StateRun*)_stateRunList)[0].location;
  }
  return NSNotFound;
}

- (NSUInteger) findLastState:(NSUInteger*)state {
  if (_stateRunCount) {
    if (state) {
      *state = ((StateRun*)_stateRunList)[_stateRunCount - 1].state;
    }
    return ((StateRun*)_stateRunList)[_stateRunCount - 1].location;
  }
  return NSNotFound;
}

- (NSUInteger) findPreviousStateFromLocation:(NSUInteger)location state:(NSUInteger*)state {
  if (_stateRunCount) {
    if (((StateRun*)_stateRunList)[_lastStateRunIndex].location < location) {
      _lastStateRunIndex = _stateRunCount - 1;  // Reset cached index to end if invalid
    }
    for (NSInteger i = _lastStateRunIndex; i >= 0; --i) {
      if (((StateRun*)_stateRunList)[i].location <= location) {
        if (state) {
          *state = ((StateRun*)_stateRunList)[i].state;
        }
        _lastStateRunIndex = i;
        return ((StateRun*)_stateRunList)[i].location;
      }
    }
  }
  return NSNotFound;
}

- (NSUInteger) findNextStateFromLocation:(NSUInteger)location state:(NSUInteger*)state {
  if (_stateRunCount) {
    if (((StateRun*)_stateRunList)[_lastStateRunIndex].location > location) {
      _lastStateRunIndex = 0;  // Reset cached index to start if invalid
    }
    for (NSUInteger i = _lastStateRunIndex; i < _stateRunCount; ++i) {
      if (((StateRun*)_stateRunList)[i].location >= location) {
        if (state) {
          *state = ((StateRun*)_stateRunList)[i].state;
        }
        _lastStateRunIndex = i;
        return ((StateRun*)_stateRunList)[i].location;
      }
    }
  }
  return NSNotFound;
}

- (void) insertAttachment:(RichAttachment*)attachment {
  CHECK(attachment.location == NSNotFound);
  attachment.location = _string.length;
  [_attachments addObject:attachment];
}

- (NSUInteger) findFirstAttachment:(RichAttachment**)attachment {
  RichAttachment* object = [_attachments firstObject];
  if (object) {
    if (attachment) {
      *attachment = object;
    }
    return object.location;
  }
  return NSNotFound;
}

- (NSUInteger) findLastAttachment:(RichAttachment**)attachment {
  RichAttachment* object = [_attachments lastObject];
  if (object) {
    if (attachment) {
      *attachment = object;
    }
    return object.location;
  }
  return NSNotFound;
}

- (NSUInteger) findNextAttachmentFromLocation:(NSUInteger)location attachment:(RichAttachment**)attachment {
  for (RichAttachment* object in _attachments) {
    if (object.location >= location) {
      if (attachment) {
        *attachment = object;
      }
      return object.location;
    }
  }
  return NSNotFound;
}

- (NSArray*) findAttachmentsInRange:(NSRange)range {
  if (range.location + range.length == _string.length) {
    range.length += 1;  // Make sure attachments at the very end get returned
  }
  NSMutableArray* array = [NSMutableArray array];
  for (RichAttachment* attachment in _attachments) {
    if (attachment.location < range.location) {
      continue;
    } else if (attachment.location >= range.location + range.length) {
      break;
    }
    [array addObject:attachment];
  }
  return array;
}

- (NSString*) description {
  return [self smartDescription];
}

@end
