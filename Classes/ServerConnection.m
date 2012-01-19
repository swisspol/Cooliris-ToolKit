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

#import "ServerConnection.h"
#import "Logging.h"

#define kHugeTimerInterval (365.0 * 24.0 * 3600.0)
#define kCheckInitialDelay 2.0
#define kCheckMaxDelay 3600.0

static NSString* _stateNames[] = {
                                  @"Unknown",
                                  @"Offline",
                                  @"Online",
                                  @"Checking",
                                  @"Connecting",
#if TARGET_OS_IPHONE
                                  @"Connected (WiFi)",
                                  @"Connected (Cell)",
#else
                                  @"Connected",
#endif
                                  @"Disconnecting"
                                };

@implementation ServerConnection

@synthesize delegate=_delegate, currentState=_currentState;
#if TARGET_OS_IPHONE
@synthesize wifiOnly=_wifiOnly;
#endif

+ (ServerConnection*) sharedServerConnection {
  static ServerConnection* _connection = nil;
  if (_connection == nil) {
    _connection = [[ServerConnection alloc] init];
  }
  return _connection;
}

- (id) init {
  if ((self = [super init])) {
    _currentState = kServerConnectionState_Unknown;
    
    _netReachability = [[NetReachability alloc] initWithHostName:@"example.com"];
#if TARGET_OS_IPHONE
    _netReachability.reachabilityMode = kNetReachabilityMode_Default;
#endif
    _netReachability.delegate = self;
    _checkTimer = [[NSTimer alloc] initWithFireDate:[NSDate distantFuture]
                                           interval:kHugeTimerInterval
                                             target:self
                                           selector:@selector(_checkTimer:)
                                           userInfo:nil
                                            repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:_checkTimer forMode:NSRunLoopCommonModes];
  }
  return self;
}

- (void) dealloc {
  [_checkTimer invalidate];
  [_checkTimer release];
  [_netReachability release];
  
  [super dealloc];
}

- (BOOL) isConnected {
#if TARGET_OS_IPHONE
  return (_currentState == kServerConnectionState_Connected_WiFi) || (_currentState == kServerConnectionState_Connected_Cell);
#else
  return (_currentState == kServerConnectionState_Connected);
#endif
}

#if TARGET_OS_IPHONE

- (void) setWifiOnly:(BOOL)flag {
  if (flag != _wifiOnly) {
    _netReachability.reachabilityMode = flag ? kNetReachabilityMode_WiFiOnly : kNetReachabilityMode_Default;
    _wifiOnly = flag;
  }
}

#endif

- (void) _setState:(ServerConnectionState)state {
  if (state != _currentState) {
    LOG_VERBOSE(@"Server connection state changed from '%@' to '%@'", _stateNames[_currentState], _stateNames[state]);
    _currentState = state;
    if ([_delegate respondsToSelector:@selector(serverConnectionDidChangeState:)]) {
      [_delegate serverConnectionDidChangeState:self];
    }
  }
}

- (void) _didConnect:(BOOL)success reachabilityState:(NetReachabilityState)state {
  if (success) {
    if (state) {
#if TARGET_OS_IPHONE
      [self _setState:(state < 0 ? kServerConnectionState_Connected_Cell : kServerConnectionState_Connected_WiFi)];
#else
      [self _setState:kServerConnectionState_Connected];
#endif
      if ([_delegate respondsToSelector:@selector(serverConnectionDidConnect:)]) {
        [_delegate serverConnectionDidConnect:self];
      }
    } else {
      DNOT_REACHED();
      [self forceDisconnect];
    }
  } else {
    if (state) {
      _checkDelay = kCheckInitialDelay;
      [_checkTimer setFireDate:[NSDate dateWithTimeIntervalSinceNow:_checkDelay]];
      [self _setState:kServerConnectionState_Online];
    } else {
      [_checkTimer setFireDate:[NSDate distantFuture]];  // Likely not necessary, but let's be extra-safe
      [self _setState:kServerConnectionState_Offline];
    }
  }
}

- (void) _didCheck:(BOOL)success reachabilityState:(NetReachabilityState)state {
  if (success) {
    ServerConnectionReply reply = kServerConnectionReply_Success;
    if ([_delegate respondsToSelector:@selector(serverConnectionConnect:)]) {
      reply = [_delegate serverConnectionConnect:self];
    }
    switch (reply) {
      
      case kServerConnectionReply_Failure:
        [self _didConnect:NO reachabilityState:state];
        break;
      
      case kServerConnectionReply_Later:
        [self _setState:kServerConnectionState_Connecting];
        break;
      
      case kServerConnectionReply_Success:
        [self _didConnect:YES reachabilityState:state];
        break;
      
    }
  } else {
    if (state) {
      _checkDelay = MIN(_checkDelay * 2.0, kCheckMaxDelay);
      [_checkTimer setFireDate:[NSDate dateWithTimeIntervalSinceNow:_checkDelay]];
      [self _setState:kServerConnectionState_Online];
      LOG_WARNING(@"Server connection is not responding (retrying in %.0f seconds)", _checkDelay);
    } else {
      [_checkTimer setFireDate:[NSDate distantFuture]];  // Likely not necessary, but let's be extra-safe
      [self _setState:kServerConnectionState_Offline];
    }
  }
}

- (void) _checkTimer:(NSTimer*)timer {
  ServerConnectionReply reply = kServerConnectionReply_Success;
  if ([_delegate respondsToSelector:@selector(serverConnectionCheckReachability:)]) {
    reply = [_delegate serverConnectionCheckReachability:self];
  }
  switch (reply) {
    
    case kServerConnectionReply_Failure:
      [self _didCheck:NO reachabilityState:_netReachability.state];
      break;
    
    case kServerConnectionReply_Later:
      [self _setState:kServerConnectionState_Checking];
      break;
    
    case kServerConnectionReply_Success:
      [self _didCheck:YES reachabilityState:_netReachability.state];
      break;
    
  }
}

- (void) _didDisconnect:(NetReachabilityState)state {
  if (state) {
    _checkDelay = kCheckInitialDelay;
    [_checkTimer setFireDate:[NSDate dateWithTimeIntervalSinceNow:_checkDelay]];
    [self _setState:kServerConnectionState_Online];
  } else {
    [_checkTimer setFireDate:[NSDate distantFuture]];  // Likely not necessary, but let's be extra-safe
    [self _setState:kServerConnectionState_Offline];
  }
}

- (void) _disconnect {
  if ([_delegate respondsToSelector:@selector(serverConnectionWillDisconnect:)]) {
    [_delegate serverConnectionWillDisconnect:self];
  }
  ServerConnectionReply reply = kServerConnectionReply_Success;
  if ([_delegate respondsToSelector:@selector(serverConnectionDisconnect:)]) {
    reply = [_delegate serverConnectionDisconnect:self];
    DCHECK(reply != kServerConnectionReply_Failure);
  }
  if (reply == kServerConnectionReply_Later) {
    [self _setState:kServerConnectionState_Disconnecting];
  } else {
    [self _didDisconnect:_netReachability.state];
  }
}

- (void) reachabilityDidUpdate:(NetReachability*)reachability state:(NetReachabilityState)state {
#if TARGET_OS_IPHONE
  LOG_VERBOSE(@"Server connection updated to %@", state ? (state < 0 ? @"cell reachable" : @"wifi reachable") : @"unreachable");
#else
  LOG_VERBOSE(@"Server connection updated to %@", state ? @"reachable" : @"unreachable");
#endif
  
  if (!state) {
    if ((_currentState == kServerConnectionState_Checking) && [_delegate respondsToSelector:@selector(serverConnectionShouldAbortCheckReachability:)]) {
      if ([_delegate serverConnectionShouldAbortCheckReachability:self]) {
        [self _didCheck:NO reachabilityState:state];  // This will update _currentState
      }
    } else if ((_currentState == kServerConnectionState_Connecting) && [_delegate respondsToSelector:@selector(serverConnectionShouldAbortConnect:)]) {
      if ([_delegate serverConnectionShouldAbortConnect:self]) {
        [self _didConnect:NO reachabilityState:state];  // This will update _currentState
      }
    }
  }
  
  if (state) {
    if ((_currentState == kServerConnectionState_Unknown) || (_currentState == kServerConnectionState_Offline)) {
      _checkDelay = kCheckInitialDelay;
      [_checkTimer setFireDate:[NSDate dateWithTimeIntervalSinceNow:_checkDelay]];
      [self _setState:kServerConnectionState_Online];
    } else if (_currentState == kServerConnectionState_Online) {
      _checkDelay = kCheckInitialDelay;
      [_checkTimer setFireDate:[NSDate dateWithTimeIntervalSinceNow:_checkDelay]];
    } else if (_currentState == kServerConnectionState_Checking) {
      _checkDelay = kCheckInitialDelay;  // Reset delay for next check
    }
#if TARGET_OS_IPHONE
    else if ((_currentState == kServerConnectionState_Connected_WiFi) && (state == kNetReachabilityState_CellReachable)) {
      [self _setState:kServerConnectionState_Connected_Cell];
    } else if ((_currentState == kServerConnectionState_Connected_Cell) && (state == kNetReachabilityState_WiFiReachable)) {
      [self _setState:kServerConnectionState_Connected_WiFi];
    }
#endif
  } else {
#if TARGET_OS_IPHONE
    if ((_currentState == kServerConnectionState_Connected_WiFi) || (_currentState == kServerConnectionState_Connected_Cell))
#else
    if (_currentState == kServerConnectionState_Connected)
#endif
    {
      [self _disconnect];
    } else if (_currentState == kServerConnectionState_Online) {
      [_checkTimer setFireDate:[NSDate distantFuture]];
      [self _setState:kServerConnectionState_Offline];
    } else if (_currentState == kServerConnectionState_Unknown) {
      [self _setState:kServerConnectionState_Offline];
    }
  }
}

- (void) replyToCheckServerReachability:(BOOL)success {
  CHECK(_currentState == kServerConnectionState_Checking);
  [self _didCheck:success reachabilityState:_netReachability.state];
}

- (void) replyToConnectToServer:(BOOL)success {
  CHECK(_currentState == kServerConnectionState_Connecting);
  [self _didConnect:success reachabilityState:_netReachability.state];
}

- (void) replyToDisconnectFromServer:(BOOL)success {
  CHECK(_currentState == kServerConnectionState_Disconnecting);
  DCHECK(success);
  [self _didDisconnect:_netReachability.state];
}

- (void) forceDisconnect {
#if TARGET_OS_IPHONE
  CHECK((_currentState == kServerConnectionState_Connected_WiFi) || (_currentState == kServerConnectionState_Connected_Cell));
#else
  CHECK(_currentState == kServerConnectionState_Connected);
#endif
  [self _disconnect];
}

- (void) resetReachability {
  _netReachability.delegate = nil;
  [_netReachability release];
  _netReachability = [[NetReachability alloc] initWithHostName:@"example.com"];
#if TARGET_OS_IPHONE
  _netReachability.reachabilityMode = _wifiOnly ? kNetReachabilityMode_WiFiOnly : kNetReachabilityMode_Default;
#endif
  _netReachability.delegate = self;
}

@end
