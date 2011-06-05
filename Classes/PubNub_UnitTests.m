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

#import "PubNub.h"
#import "UnitTest.h"

// WARNING: DO NOT re-use in your code: these keys are for testing of this PubNub class ONLY and not anything else
#define kPublishKey @"pub-bd7fe85e-67b8-496b-845a-e7adac848db9"  // @"demo"
#define kSubscribeKey @"sub-ee423261-8b38-11e0-8eb3-672e7a5ac8a3"  // @"demo"
#define kSecretKey @"sec-956caa69-7e14-46fa-b3fe-2528661f0358"  // nil

#define kTimeOut 5.0
#define kHistoryLimit 10

@interface PubNubTests : UnitTest <PubNubDelegate> {
@private
  NSString* _channel;
  id _result;
}
@end

@implementation PubNubTests

- (void) setUp {
  CFUUIDRef uuid = CFUUIDCreate(kCFAllocatorDefault);
  _channel = (NSString*)CFUUIDCreateString(kCFAllocatorDefault, uuid);
  CFRelease(uuid);
}

- (void) pubnub:(PubNub*)pubnub didSucceedPublishingMessageToChannel:(NSString*)channel {
  _result = [NSNull null];
}

- (void) pubnub:(PubNub*)pubnub didFailPublishingMessageToChannel:(NSString*)channel error:(NSString*)error {
  _result = [error retain];
}

- (void) pubnub:(PubNub*)pubnub didReceiveMessage:(id)message onChannel:(NSString*)channel {
  _result = [message retain];
}

- (void) pubnub:(PubNub*)pubnub didFetchHistory:(NSArray*)messages forChannel:(NSString*)channel {
  _result = [messages retain];
}

- (void) pubnub:(PubNub*)pubnub didReceiveTime:(NSTimeInterval)time {
  if (!isnan(time)) {
    _result = [[NSNumber alloc] initWithDouble:time];
  }
}

- (void) _waitForResult {
  [_result release];
  _result = nil;
  CFAbsoluteTime time = CFAbsoluteTimeGetCurrent();
  while (1) {
    SInt32 result = CFRunLoopRunInMode(kCFRunLoopDefaultMode, kTimeOut - (CFAbsoluteTimeGetCurrent() - time), true);
    if ((_result != nil) || (result == kCFRunLoopRunTimedOut) || (result == kCFRunLoopRunFinished)) {
      break;
    }
  }
}

- (void) _waitForResult1:(id*)result1 result2:(id*)result2 {
  [self _waitForResult];
  *result1 = [[_result retain] autorelease];
  [self _waitForResult];
  *result2 = [[_result retain] autorelease];
  if (*result2 == [NSNull null]) {
    id temp = *result1;
    *result1 = *result2;
    *result2 = temp;
  }
}

- (void) _testMessaging:(BOOL)useSSL {
  id result1;
  id result2;
  
  PubNub* pubNub = [[PubNub alloc] initWithPublishKey:kPublishKey
                                         subscribeKey:kSubscribeKey
                                            secretKey:(useSSL ? kSecretKey : nil)
                                               useSSL:useSSL];
  AssertNotNil(pubNub);
  pubNub.delegate = self;
  
  AssertFalse([pubNub isSubscribedToChannel:_channel]);
  [pubNub subscribeToChannel:_channel];
  AssertTrue([pubNub isSubscribedToChannel:_channel]);
  
  CFRunLoopRunInMode(kCFRunLoopDefaultMode, 1.0, false);
  
  NSString* string = @"string";
  [pubNub publishMessage:string toChannel:_channel];
  [self _waitForResult1:&result1 result2:&result2];
  AssertEqualObjects(result1, [NSNull null]);
  AssertEqualObjects(result2, string);
  
  NSArray* array = [NSArray arrayWithObjects:@"string", [NSNumber numberWithInt:0], nil];
  [pubNub publishMessage:array toChannel:_channel];
  [self _waitForResult1:&result1 result2:&result2];
  AssertEqualObjects(result1, [NSNull null]);
  AssertEqualObjects(result2, array);
  
  NSDictionary* dictionary = [NSDictionary dictionaryWithObjectsAndKeys:@"string", @"string", [NSNumber numberWithInt:0], @"number", nil];
  [pubNub publishMessage:dictionary toChannel:_channel];
  [self _waitForResult1:&result1 result2:&result2];
  AssertEqualObjects(result1, [NSNull null]);
  AssertEqualObjects(result2, dictionary);
  
  [pubNub unsubscribeFromChannel:_channel];
  AssertFalse([pubNub isSubscribedToChannel:_channel]);
  
  [pubNub fetchHistory:kHistoryLimit forChannel:_channel];
  [self _waitForResult];
  AssertTrue([_result isKindOfClass:[NSArray class]]);
  AssertEqual([_result count], (NSUInteger)3);
  
  [pubNub release];
}

- (void) testMessagingWithSSL {
  [self _testMessaging:YES];
}

- (void) testMessagingWithoutSSL {
  [self _testMessaging:NO];
}

- (void) _testTime:(BOOL)useSSL {
  PubNub* pubNub = [[PubNub alloc] initWithPublishKey:kPublishKey subscribeKey:kSubscribeKey secretKey:nil useSSL:useSSL];
  AssertNotNil(pubNub);
  pubNub.delegate = self;
  
  [pubNub getTime];
  [self _waitForResult];
  AssertTrue([_result isKindOfClass:[NSNumber class]]);
  AssertGreaterThan([_result doubleValue], (double)0.0);
  
  [pubNub release];
}

- (void) testTimeWithSSL {
  [self _testTime:YES];
}

- (void) testTimeWithoutSSL {
  [self _testTime:NO];
}

- (void) cleanUp {
  [_result release];
  [_channel release];
}

@end
