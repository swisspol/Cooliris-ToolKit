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

// Required library: "${SDKROOT}/usr/lib/libxml2.dylib"

#import <Foundation/Foundation.h>

@class DAVServer;

@protocol DAVServerDelegate <NSObject>
@optional
- (void) davServerDidUpdateNumberOfConnections:(DAVServer*)server;
- (void) davServer:(DAVServer*)server didRespondToMethod:(NSString*)method;
@end

@interface DAVServer : NSObject {
  NSString* _path;
  NSUInteger _port;
  NSString* _password;
  id<DAVServerDelegate> _delegate;
  id _server;
  BOOL _running;
}
@property(nonatomic, readonly) NSString* rootDirectory;
@property(nonatomic, readonly) NSUInteger port;
@property(nonatomic, readonly) NSString* password;
@property(nonatomic, assign) id<DAVServerDelegate> delegate;
@property(nonatomic, readonly, getter=isRunning) BOOL running;
@property(nonatomic, readonly) NSUInteger numberOfConnections;
- (id) initWithRootDirectory:(NSString*)path;  // Default is ~/Documents
- (id) initWithRootDirectory:(NSString*)path port:(NSUInteger)port;  // Default port is 8080
- (id) initWithRootDirectory:(NSString*)path port:(NSUInteger)port password:(NSString*)password;  // Default user & password are nil
- (BOOL) start;
- (void) stop:(BOOL)keepConnectionsAlive;
@end
