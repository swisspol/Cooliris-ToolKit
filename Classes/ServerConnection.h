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

#import "NetReachability.h"

typedef enum {
  kServerConnectionState_Unknown = 0,  // Initial state (never re-used)
  kServerConnectionState_Offline,  // No internet connection
  kServerConnectionState_Online,  // Internet connection available and checks with exponential delay is server is reachable
  kServerConnectionState_Checking,  // Currently checking if server is available (waiting for delegate)
  kServerConnectionState_Connecting,  // Server reachable and currently attempting to authenticate (waiting for delegate)
#if TARGET_OS_IPHONE
  kServerConnectionState_Connected_WiFi,  // Connected and authenticated with server over WiFi
  kServerConnectionState_Connected_Cell,  // Connected and authenticated with server over cell
#else
  kServerConnectionState_Connected,  // Connected and authenticated with server
#endif
  kServerConnectionState_Disconnecting  // Currently disconnecting from server (waiting for delegate)
} ServerConnectionState;

typedef enum {
  kServerConnectionReply_Failure = -1,
  kServerConnectionReply_Later,
  kServerConnectionReply_Success
} ServerConnectionReply;

@class ServerConnection;

// TODO: Handle disconnection failures
@protocol ServerConnectionDelegate <NSObject>
@optional
- (void) serverConnectionDidChangeState:(ServerConnection*)connection;
- (void) serverConnectionDidConnect:(ServerConnection*)connection;
- (void) serverConnectionWillDisconnect:(ServerConnection*)connection;

- (ServerConnectionReply) serverConnectionCheckReachability:(ServerConnection*)connection;
- (ServerConnectionReply) serverConnectionConnect:(ServerConnection*)connection;
- (ServerConnectionReply) serverConnectionDisconnect:(ServerConnection*)connection;

- (BOOL) serverConnectionShouldAbortCheckReachability:(ServerConnection*)connection;  // Only called if in kServerConnectionState_Checking state - Returning YES is equivalent to calling -replyToCheckServerReachability:NO
- (BOOL) serverConnectionShouldAbortConnect:(ServerConnection*)connection;  // Only called if in kServerConnectionState_Connecting state - Returning YES is equivalent to calling -replyToConnectToServer:NO
@end

@interface ServerConnection : NSObject <NetReachabilityDelegate> {
@private
  id<ServerConnectionDelegate> _delegate;
  ServerConnectionState _currentState;
  NSString* _hostName;
  NetReachability* _netReachability;
  NSTimer* _checkTimer;
  NSTimeInterval _checkDelay;
}
@property(nonatomic, assign) id<ServerConnectionDelegate> delegate;
@property(nonatomic, readonly) ServerConnectionState currentState;
@property(nonatomic, readonly, getter=isConnected) BOOL connected;
@property(nonatomic) NetReachabilityMode reachabilityMode;
+ (ServerConnection*) sharedServerConnection;
- (id) initWithHostName:(NSString*)hostName;
- (void) replyToCheckServerReachability:(BOOL)success;
- (void) replyToConnectToServer:(BOOL)success;
- (void) replyToDisconnectFromServer:(BOOL)success;
- (void) forceDisconnect;  // Only call if in connected state
- (void) resetReachability;  // Forces a recheck of the reachability status
@end
