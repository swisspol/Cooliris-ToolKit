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
  kServerConnectionState_Offline = 0,  // No internet connection
  kServerConnectionState_Online,  // Internet connection available and checks with exponential delay is server is reachable
  kServerConnectionState_Checking,  // Currently checking if server is available
  kServerConnectionState_Connecting,  // Server reachable and currently attempting to authenticate
  kServerConnectionState_Connected,  // Connected and authenticated with server
  kServerConnectionState_Disconnecting  // Currently disconnecting from server
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
@end

@interface ServerConnection : NSObject <NetReachabilityDelegate> {
@private
  id<ServerConnectionDelegate> _delegate;
  ServerConnectionState _currentState;
  NetReachability* _netReachability;
  NSTimer* _checkTimer;
  NSTimeInterval _checkDelay;
}
@property(nonatomic, assign) id<ServerConnectionDelegate> delegate;
@property(nonatomic, readonly) ServerConnectionState currentState;
+ (ServerConnection*) sharedServerConnection;
- (void) replyToCheckServerReachability:(BOOL)success;
- (void) replyToConnectToServer:(BOOL)success;
- (void) replyToDisconnectFromServer:(BOOL)success;
- (void) forceDisconnect;  // Only call if in connected state
@end
