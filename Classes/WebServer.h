// Copyright 2012 Pierre-Olivier Latour
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

#import "WebServerRequest.h"
#import "WebServerResponse.h"

#define kWebServerDefaultMimeType @"application/octet-stream"

typedef WebServerRequest* (^WebServerMatchBlock)(NSString* requestMethod, NSDictionary* requestHeaders, NSString* urlPath, NSString* urlQuery);
typedef WebServerResponse* (^WebServerProcessBlock)(WebServerRequest* request);

@interface WebServer : NSObject {
@private
  NSString* _name;
  NSMutableArray* _handlers;
  
  NSUInteger _port;
  NSRunLoop* _runLoop;
  CFSocketRef _socket;
  CFNetServiceRef _service;
}
@property(nonatomic, copy) NSString* name;  // Default is class name
@property(nonatomic, readonly, getter=isRunning) BOOL running;
@property(nonatomic, readonly) NSUInteger port;

- (void) addHandlerWithMatchBlock:(WebServerMatchBlock)matchBlock processBlock:(WebServerProcessBlock)processBlock;
- (void) removeAllHandlers;

- (BOOL) start;  // Default is main runloop, 8080 port and computer name
- (BOOL) startWithRunloop:(NSRunLoop*)runloop port:(NSUInteger)port bonjourName:(NSString*)name;  // Pass nil name to disable Bonjour
- (void) stop;
@end

@interface WebServer (Handlers)
- (void) addHandlerForBasePath:(NSString*)basePath localPath:(NSString*)localPath indexFilename:(NSString*)indexFilename cacheAge:(NSUInteger)cacheAge;  // Base path is recursive and case-sensitive
- (void) addHandlerForMethod:(NSString*)method path:(NSString*)path requestClass:(Class)class processBlock:(WebServerProcessBlock)block;  // Path is case-insensitive
- (void) addHandlerForMethod:(NSString*)method pathRegex:(NSString*)regex requestClass:(Class)class processBlock:(WebServerProcessBlock)block;  // Regular expression is case-insensitive
@end
