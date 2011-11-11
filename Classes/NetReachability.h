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

typedef enum {
  kNetReachabilityMode_AlwaysOff = -2,
  kNetReachabilityMode_AlwaysOn = -1,
  kNetReachabilityMode_Default = 0,
#if TARGET_OS_IPHONE
  kNetReachabilityMode_WiFiOnly = 1,
  kNetReachabilityMode_CellOnly = 2
#endif
} NetReachabilityMode;

typedef enum {
#if TARGET_OS_IPHONE
  kNetReachabilityState_CellReachable = -1,
#endif
  kNetReachabilityState_NotReachable = 0,
#if TARGET_OS_IPHONE
  kNetReachabilityState_WiFiReachable = 1
#else
  kNetReachabilityState_Reachable = 1
#endif
} NetReachabilityState;

@class NetReachability;

@protocol NetReachabilityDelegate <NSObject>
- (void) reachabilityDidUpdate:(NetReachability*)reachability state:(NetReachabilityState)state;  // May be called even if "state" has not changed
@end

// If initializing with a specific host or address (i.e. not with -init) and a delegate is set, it will be called immediately
@interface NetReachability : NSObject {
@private
  NetReachabilityMode _mode;
  id<NetReachabilityDelegate> _delegate;
  void* _netReachability;
  CFRunLoopRef _runLoop;
}
@property(nonatomic) NetReachabilityMode reachabilityMode;
@property(nonatomic, assign) id<NetReachabilityDelegate> delegate;  // Uses the runloop current at the time of creation
@property(nonatomic, readonly) NetReachabilityState state;  // Uses "reachabilityMode"
+ (NetReachability*) sharedNetReachability;
- (id) initWithIPv4Address:(UInt32)address;  // The "address" is assumed to be in host-endian
- (id) initWithHostName:(NSString*)name;
- (NetReachabilityState) stateWithMode:(NetReachabilityMode)mode;  // Cannot override "always" modes
@end
