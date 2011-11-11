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

#import <SystemConfiguration/SCNetworkReachability.h>
#import <netinet/in.h>

#import "NetReachability.h"
#import "SmartDescription.h"
#import "Logging.h"

#if TARGET_OS_IPHONE || (__MAC_OS_X_VERSION_MIN_REQUIRED >= 1060)
#define IS_REACHABLE(__FLAGS__) \
  (((__FLAGS__) & kSCNetworkReachabilityFlagsReachable) && !((__FLAGS__) & kSCNetworkReachabilityFlagsConnectionRequired))
#else
#define IS_REACHABLE(__FLAGS__) \
  (((__FLAGS__) & kSCNetworkFlagsReachable) && !((__FLAGS__) & kSCNetworkFlagsConnectionRequired))
#endif

#if TARGET_OS_IPHONE && !TARGET_IPHONE_SIMULATOR
#define IS_REACHABLE_CELL(__FLAGS__) (IS_REACHABLE(__FLAGS__) && ((__FLAGS__) & kSCNetworkReachabilityFlagsIsWWAN))
#define IS_REACHABLE_WIFI(__FLAGS__) (IS_REACHABLE(__FLAGS__) && !((__FLAGS__) & kSCNetworkReachabilityFlagsIsWWAN))
#else
#define IS_REACHABLE_CELL(__FLAGS__) (0)
#define IS_REACHABLE_WIFI(__FLAGS__) IS_REACHABLE(__FLAGS__)
#endif

@interface NetReachability ()
- (id) initWithAddress:(const struct sockaddr*)address;
@end

@implementation NetReachability

@synthesize reachabilityMode=_mode, delegate=_delegate;

+ (NetReachabilityState) reachabilityStateWithMode:(NetReachabilityMode)mode flags:(SCNetworkConnectionFlags)flags {
  NetReachabilityState state = kNetReachabilityState_NotReachable;
  switch (mode) {
    
    case kNetReachabilityMode_Default:
#if TARGET_OS_IPHONE
      if (IS_REACHABLE_WIFI(flags)) {
        state = kNetReachabilityState_WiFiReachable;
      } else if (IS_REACHABLE_CELL(flags)) {
        state = kNetReachabilityState_CellReachable;
      }
#else
      if (IS_REACHABLE(flags)) {
        state = kNetReachabilityState_Reachable;
      }
#endif
      break;
    
#if TARGET_OS_IPHONE
    case kNetReachabilityMode_WiFiOnly:
      if (IS_REACHABLE_WIFI(flags)) {
        state = kNetReachabilityState_WiFiReachable;
      }
      break;
    
    case kNetReachabilityMode_CellOnly:
      if (IS_REACHABLE_CELL(flags)) {
        state = kNetReachabilityState_CellReachable;
      }
      break;
#endif
    
    case kNetReachabilityMode_AlwaysOn:
#if TARGET_OS_IPHONE
      state = kNetReachabilityState_WiFiReachable;
#else
      state = kNetReachabilityState_Reachable;
#endif
      break;
    
    case kNetReachabilityMode_AlwaysOff:
      break;
    
  }
  return state;
}

static void _ReachabilityCallBack(SCNetworkReachabilityRef target, SCNetworkConnectionFlags flags, void* info) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  NetReachability* self = (NetReachability*)info;
  NetReachabilityState state = [NetReachability reachabilityStateWithMode:self->_mode flags:flags];
  [self->_delegate reachabilityDidUpdate:self state:state];
  [pool release];
}

+ (NetReachability*) sharedNetReachability {
  static NetReachability* reacheability = nil;
  if (reacheability == nil) {
    reacheability = [[NetReachability alloc] init];
    DCHECK(reacheability);
  }
  return reacheability;
}

// This will consume a reference of "reachability"
- (id) _initWithNetworkReachability:(SCNetworkReachabilityRef)reachability {
  if (reachability == NULL) {
    [self release];
    return nil;
  }
  if ((self = [super init])) {
    _runLoop = (CFRunLoopRef)CFRetain(CFRunLoopGetCurrent());
    _netReachability = (void*)reachability;
  }
  return self;
}

- (id) init {
  return [self initWithIPv4Address:INADDR_ANY];
}

- (id) initWithAddress:(const struct sockaddr*)address {
  return [self _initWithNetworkReachability:(address ? SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, address) : NULL)];
}

- (id) initWithIPv4Address:(UInt32)address {
  struct sockaddr_in ipAddress;
  bzero(&ipAddress, sizeof(ipAddress));
  ipAddress.sin_len = sizeof(ipAddress);
  ipAddress.sin_family = AF_INET;
  ipAddress.sin_addr.s_addr = htonl(address);
  return [self initWithAddress:(struct sockaddr*)&ipAddress];
}

- (id) initWithHostName:(NSString*)name {
  return [self _initWithNetworkReachability:([name length] ? SCNetworkReachabilityCreateWithName(kCFAllocatorDefault,
                                                                                                 [name UTF8String]) : NULL)];
}

- (void) dealloc {
  self.delegate = nil;
  
  if (_runLoop) {
    CFRelease(_runLoop);
  }
  if (_netReachability) {
    CFRelease(_netReachability);
  }
  
  [super dealloc];
}

- (NetReachabilityState) state {
  SCNetworkConnectionFlags flags;
  if (SCNetworkReachabilityGetFlags(_netReachability, &flags)) {
    return [NetReachability reachabilityStateWithMode:_mode flags:flags];
  }
  return kNetReachabilityState_NotReachable;
}

- (NetReachabilityState) stateWithMode:(NetReachabilityMode)mode {
  SCNetworkConnectionFlags flags;
  if (SCNetworkReachabilityGetFlags(_netReachability, &flags)) {
    return [NetReachability reachabilityStateWithMode:(_mode < 0 ? _mode : mode) flags:flags];
  }
  return kNetReachabilityState_NotReachable;
}

- (void) setDelegate:(id<NetReachabilityDelegate>)delegate {
  if (delegate && !_delegate) {
    SCNetworkReachabilityContext context = {0, self, NULL, NULL, NULL};
    if (SCNetworkReachabilitySetCallback(_netReachability, _ReachabilityCallBack, &context)) {
      if (!SCNetworkReachabilityScheduleWithRunLoop(_netReachability, _runLoop, kCFRunLoopCommonModes)) {
        SCNetworkReachabilitySetCallback(_netReachability, NULL, NULL);
        delegate = nil;
      }
    }
    else {
      delegate = nil;
    }
    if (delegate == nil) {
      LOG_ERROR(@"Failed installing SCNetworkReachability callback on runloop");
    }
  }
  else if (!delegate && _delegate) {
    SCNetworkReachabilityUnscheduleFromRunLoop(_netReachability, _runLoop, kCFRunLoopCommonModes);
    SCNetworkReachabilitySetCallback(_netReachability, NULL, NULL);
  }
  
  _delegate = delegate;
}

- (NSString*) description {
  return [self smartDescription];
}

@end
