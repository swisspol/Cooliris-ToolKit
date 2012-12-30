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

#import "GCDWebServerRequest.h"
#import "GCDWebServerResponse.h"

#define kGCDWebServerDefaultMimeType @"application/octet-stream"

typedef GCDWebServerRequest* (^GCDWebServerMatchBlock)(NSString* requestMethod, NSURL* requestURL, NSDictionary* requestHeaders, NSString* urlPath, NSDictionary* urlQuery);
typedef GCDWebServerResponse* (^GCDWebServerProcessBlock)(GCDWebServerRequest* request);

@class GCDWebServer, GCDWebServerHandler;

@interface GCDWebServerConnection : NSObject {
@private
  GCDWebServer* _server;
  NSData* _address;
  CFSocketNativeHandle _socket;
  NSUInteger _bytesRead;
  NSUInteger _bytesWritten;
  
  CFHTTPMessageRef _requestMessage;
  GCDWebServerRequest* _request;
  GCDWebServerHandler* _handler;
  CFHTTPMessageRef _responseMessage;
  GCDWebServerResponse* _response;
}
@property(nonatomic, readonly) GCDWebServer* server;
@property(nonatomic, readonly) NSData* address;  // struct sockaddr
@property(nonatomic, readonly) NSUInteger totalBytesRead;
@property(nonatomic, readonly) NSUInteger totalBytesWritten;
@end

@interface GCDWebServerConnection (Subclassing)
- (void) open;
- (GCDWebServerResponse*) processRequest:(GCDWebServerRequest*)request withBlock:(GCDWebServerProcessBlock)block;
- (void) close;
@end

@interface GCDWebServer : NSObject {
@private
  NSMutableArray* _handlers;
  
  NSUInteger _port;
  NSRunLoop* _runLoop;
  CFSocketRef _socket;
  CFNetServiceRef _service;
}
@property(nonatomic, readonly, getter=isRunning) BOOL running;
@property(nonatomic, readonly) NSUInteger port;
- (void) addHandlerWithMatchBlock:(GCDWebServerMatchBlock)matchBlock processBlock:(GCDWebServerProcessBlock)processBlock;
- (void) removeAllHandlers;

- (BOOL) start;  // Default is main runloop, 8080 port and computer name
- (BOOL) startWithRunloop:(NSRunLoop*)runloop port:(NSUInteger)port bonjourName:(NSString*)name;  // Pass nil name to disable Bonjour or empty string to use computer name
- (void) stop;
@end

@interface GCDWebServer (Subclassing)
+ (Class) connectionClass;
+ (NSString*) serverName;  // Default is class name
@end

@interface GCDWebServer (Extensions)
- (BOOL) runWithPort:(NSUInteger)port;  // Starts then automatically stops on SIGINT i.e. Ctrl-C (use on main thread only)
@end

@interface GCDWebServer (Handlers)
- (void) addDefaultHandlerForMethod:(NSString*)method requestClass:(Class)class processBlock:(GCDWebServerProcessBlock)block;
- (void) addHandlerForBasePath:(NSString*)basePath localPath:(NSString*)localPath indexFilename:(NSString*)indexFilename cacheAge:(NSUInteger)cacheAge;  // Base path is recursive and case-sensitive
- (void) addHandlerForMethod:(NSString*)method path:(NSString*)path requestClass:(Class)class processBlock:(GCDWebServerProcessBlock)block;  // Path is case-insensitive
- (void) addHandlerForMethod:(NSString*)method pathRegex:(NSString*)regex requestClass:(Class)class processBlock:(GCDWebServerProcessBlock)block;  // Regular expression is case-insensitive
@end
