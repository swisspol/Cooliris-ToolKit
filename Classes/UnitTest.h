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
#import <libgen.h>

#define LOG_FAILURE(__MESSAGE__) [self logMessage:@"[FAILURE @ %s:%i] %@", basename(__FILE__), __LINE__, __MESSAGE__]; \

#define AssertNotReached() \
do { \
  LOG_FAILURE(@"<REACHED>"); \
  [self reportResult:NO]; \
} while(0)

#define AssertTrue(__EXPRESSION__) \
do { \
  BOOL __bool = (__EXPRESSION__); \
  if (!__bool) { \
    NSString* __message = [NSString stringWithFormat:@"(%@) != TRUE", [NSString stringWithUTF8String: #__EXPRESSION__]]; \
    LOG_FAILURE(__message); \
    [self reportResult:NO]; \
  } else { \
    [self reportResult:YES]; \
  } \
} while(0)

#define AssertFalse(__EXPRESSION__) \
do { \
  BOOL __bool = (__EXPRESSION__); \
  if (__bool) { \
    NSString* __message = [NSString stringWithFormat:@"(%@) != FALSE", [NSString stringWithUTF8String: #__EXPRESSION__]]; \
    LOG_FAILURE(__message); \
    [self reportResult:NO]; \
  } else { \
    [self reportResult:YES]; \
  } \
} while(0)

#define AssertNil(__OBJECT__) \
do { \
  id __object = (__OBJECT__); \
  if (__object != nil) { \
    NSString* __message = [NSString stringWithFormat:@"(%@) != nil", [NSString stringWithUTF8String: #__OBJECT__]]; \
    LOG_FAILURE(__message); \
    [self reportResult:NO]; \
  } else { \
    [self reportResult:YES]; \
  } \
} while(0)

#define AssertNotNil(__OBJECT__) \
do { \
  id __object = (__OBJECT__); \
  if (__object == nil) { \
    NSString* __message = [NSString stringWithFormat:@"(%@) == nil", [NSString stringWithUTF8String: #__OBJECT__]]; \
    LOG_FAILURE(__message); \
    [self reportResult:NO]; \
  } else { \
    [self reportResult:YES]; \
  } \
} while(0)

#define AssertEqual(__VALUE1__, __VALUE2__) \
do { \
  __typeof__(__VALUE1__) __value1 = (__VALUE1__); \
  __typeof__(__VALUE2__) __value2 = (__VALUE2__); \
  if (strcmp(@encode(__typeof__(__value1)), @encode(__typeof__(__value2))) || (__value1 != __value2)) { \
    NSString* __message = [NSString stringWithFormat:@"(%@) != (%@)", [NSString stringWithUTF8String: #__VALUE1__], \
                                                    [NSString stringWithUTF8String: #__VALUE2__]]; \
    LOG_FAILURE(__message); \
    [self reportResult:NO]; \
  } else { \
    [self reportResult:YES]; \
  } \
} while(0)

#define AssertNotEqual(__VALUE1__, __VALUE2__) \
do { \
  __typeof__(__VALUE1__) __value1 = (__VALUE1__); \
  __typeof__(__VALUE2__) __value2 = (__VALUE2__); \
  if (!strcmp(@encode(__typeof__(__value1)), @encode(__typeof__(__value2))) && (__value1 == __value2)) { \
    NSString* __message = [NSString stringWithFormat:@"(%@) == (%@)", [NSString stringWithUTF8String: #__VALUE1__], \
                                                    [NSString stringWithUTF8String: #__VALUE2__]]; \
    LOG_FAILURE(__message); \
    [self reportResult:NO]; \
  } else { \
    [self reportResult:YES]; \
  } \
} while(0)

#define AssertLowerThan(__VALUE1__, __VALUE2__) \
do { \
  __typeof__(__VALUE1__) __value1 = (__VALUE1__); \
  __typeof__(__VALUE2__) __value2 = (__VALUE2__); \
  if (strcmp(@encode(__typeof__(__value1)), @encode(__typeof__(__value2))) || (__value1 >= __value2)) { \
    NSString* __message = [NSString stringWithFormat:@"(%@) >= (%@)", [NSString stringWithUTF8String: #__VALUE1__], \
                                                    [NSString stringWithUTF8String: #__VALUE2__]]; \
    LOG_FAILURE(__message); \
    [self reportResult:NO]; \
  } else { \
    [self reportResult:YES]; \
  } \
} while(0)

#define AssertGreaterThan(__VALUE1__, __VALUE2__) \
do { \
  __typeof__(__VALUE1__) __value1 = (__VALUE1__); \
  __typeof__(__VALUE2__) __value2 = (__VALUE2__); \
  if (strcmp(@encode(__typeof__(__value1)), @encode(__typeof__(__value2))) || (__value1 <= __value2)) { \
    NSString* __message = [NSString stringWithFormat:@"(%@) <= (%@)", [NSString stringWithUTF8String: #__VALUE1__], \
                                                    [NSString stringWithUTF8String: #__VALUE2__]]; \
    LOG_FAILURE(__message); \
    [self reportResult:NO]; \
  } else { \
    [self reportResult:YES]; \
  } \
} while(0)

#define AssertEqualObjects(__OBJECT1__, __OBJECT2__) \
do { \
  id __object1 = (__OBJECT1__); \
  id __object2 = (__OBJECT2__); \
  if ((__object1 == __object2) || [__object1 isEqual:__object2]) { \
    [self reportResult:YES]; \
  } else { \
    NSString* __message = [NSString stringWithFormat:@"(%@) != (%@)", [NSString stringWithUTF8String: #__OBJECT1__], \
                                                    [NSString stringWithUTF8String: #__OBJECT2__]]; \
    LOG_FAILURE(__message); \
    [self reportResult:NO]; \
  } \
} while(0)

// A new instance of UnitTest is created for each test
@interface UnitTest : NSObject {
@private
  BOOL _abortOnFailure;
  NSUInteger _successes;
  NSUInteger _failures;
}

// For subclasses - Default implementation does nothing
// -setUp and -cleanUp are always called, but if any assertions fail in -setUp, the test itself is bypassed
- (void) setUp;
- (void) cleanUp;

// Do not call these methods directly
- (void) logMessage:(NSString*)message, ...;
- (void) reportResult:(BOOL)success;
@end

// Supported environment variables by the executable:
// - "AbortOnFailure": if defined, abort() will be called if any assertion fails
