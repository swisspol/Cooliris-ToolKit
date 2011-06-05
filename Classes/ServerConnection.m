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

static NSString* _stateNames[] = {
                                  @"Offline",
                                  @"Online",
                                  @"Checking",
                                  @"Connecting",
                                  @"Connected",
                                  @"Disconnecting"
                                };

@implementation ServerConnection

@synthesize delegate=_delegate, currentState=_currentState;

+ (ServerConnection*) sharedServerConnection {
  static ServerConnection* _connection = nil;
  if (_connection == nil) {
    _connection = [[ServerConnection alloc] init];
  }
  return _connection;
}

- (id) init {
  if ((self = [super init])) {
    _currentState = kServerConnectionState_Offline;
    
    _netReachability = [[NetReachability alloc] initWithHostName:@"example.com"];
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

- (void) _setState:(ServerConnectionState)state {
  if (state != _currentState) {
    LOG_VERBOSE(@"Server connection state changed from '%@' to '%@'", _stateNames[_currentState], _stateNames[state]);
    _currentState = state;
    if ([_delegate respondsToSelector:@selector(serverConnectionDidChangeState:)]) {
      [_delegate serverConnectionDidChangeState:self];
    }
  }
}

- (void) _didConnect:(BOOL)success {
  if (success) {
    if (_netReachability.reachable) {
      [self _setState:kServerConnectionState_Connected];
      if ([_delegate respondsToSelector:@selector(serverConnectionDidConnect:)]) {
        [_delegate serverConnectionDidConnect:self];
      }
    } else {
      DNOT_REACHED();
      [self forceDisconnect];
    }
  } else {
    if (_netReachability.reachable) {
      _checkDelay = kCheckInitialDelay;
      [_checkTimer setFireDate:[NSDate dateWithTimeIntervalSinceNow:_checkDelay]];
      [self _setState:kServerConnectionState_Online];
    } else {
      [_checkTimer setFireDate:[NSDate distantFuture]];  // Likely not necessary, but let's be extra-safe
      [self _setState:kServerConnectionState_Offline];
    }
  }
}

- (void) _didCheck:(BOOL)success {
  if (success) {
    ServerConnectionReply reply = kServerConnectionReply_Success;
    if ([_delegate respondsToSelector:@selector(serverConnectionConnect:)]) {
      reply = [_delegate serverConnectionConnect:self];
    }
    switch (reply) {
      
      case kServerConnectionReply_Failure:
        [self _didConnect:NO];
        break;
      
      case kServerConnectionReply_Later:
        [self _setState:kServerConnectionState_Connecting];
        break;
      
      case kServerConnectionReply_Success:
        [self _didConnect:YES];
        break;
      
    }
  } else {
    if (_netReachability.reachable) {
      _checkDelay *= 2.0;
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
      [self _didCheck:NO];
      break;
    
    case kServerConnectionReply_Later:
      [self _setState:kServerConnectionState_Checking];
      break;
    
    case kServerConnectionReply_Success:
      [self _didCheck:YES];
      break;
    
  }
}

- (void) _didDisconnect {
  if (_netReachability.reachable) {
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
    [self _didDisconnect];
  }
}

- (void) reachabilityDidUpdate:(NetReachability*)reachability reachable:(BOOL)reachable {
  LOG_VERBOSE(@"Server connection did become %@", reachable ? @"reachable" : @"unreachable");
  if (reachable) {
    if (_currentState == kServerConnectionState_Offline) {
      _checkDelay = kCheckInitialDelay;
      [_checkTimer setFireDate:[NSDate dateWithTimeIntervalSinceNow:_checkDelay]];
      [self _setState:kServerConnectionState_Online];
    } else if (_currentState == kServerConnectionState_Online) {
      _checkDelay = kCheckInitialDelay;
      [_checkTimer setFireDate:[NSDate dateWithTimeIntervalSinceNow:_checkDelay]];
    } else if (_currentState == kServerConnectionState_Checking) {
      _checkDelay = kCheckInitialDelay;
    }
  } else {
    if (_currentState == kServerConnectionState_Connected) {
      [self _disconnect];
    } else if (_currentState == kServerConnectionState_Online) {
      [_checkTimer setFireDate:[NSDate distantFuture]];
      [self _setState:kServerConnectionState_Offline];
    }
  }
}

- (void) replyToCheckServerReachability:(BOOL)success {
  CHECK(_currentState == kServerConnectionState_Checking);
  [self _didCheck:success];
}

- (void) replyToConnectToServer:(BOOL)success {
  CHECK(_currentState == kServerConnectionState_Connecting);
  [self _didConnect:success];
}

- (void) replyToDisconnectFromServer:(BOOL)success {
  CHECK(_currentState == kServerConnectionState_Disconnecting);
  DCHECK(success);
  [self _didDisconnect];
}

- (void) forceDisconnect {
  CHECK(_currentState == kServerConnectionState_Connected);
  [self _disconnect];
}

@end
