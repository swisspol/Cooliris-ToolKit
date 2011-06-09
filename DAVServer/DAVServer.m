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

#import "DAVServer.h"
#import "HTTPServer.h"
#import "DAVConnection.h"

#if 1
#import "../Classes/Logging.h"
#else
#define DCHECK(...)
#define LOG_VERBOSE(...)
#define LOG_ERROR(...) NSLog(__VA_ARGS__)
#endif

// Work around Obj-C files containing only categories not being included into static libraries
#import "cocoahttpserver/Core/Categories/DDData.m"
#import "cocoahttpserver/Core/Categories/DDNumber.m"
#import "cocoahttpserver/Core/Categories/DDRange.m"

@interface HTTPServer (Internal)
- (void) socket:(GCDAsyncSocket*)sock didAcceptNewSocket:(GCDAsyncSocket*)newSocket;
- (void) connectionDidDie:(NSNotification *)notification;
@end

@interface _HTTPServer : HTTPServer {
@private
  DAVServer* _davServer;
}
@property(nonatomic, assign) DAVServer* davServer;
@end

@interface _DAVConnection : DAVConnection
@property(nonatomic, readonly) DAVServer* davServer;
@end

@implementation _HTTPServer

@synthesize davServer=_davServer;

- (void) socket:(GCDAsyncSocket*)sock didAcceptNewSocket:(GCDAsyncSocket*)newSocket {
  [super socket:sock didAcceptNewSocket:newSocket];
  LOG_DEBUG(@"<DAVServer> Added connection");
  
  if ([_davServer.delegate respondsToSelector:@selector(davServerDidUpdateNumberOfConnections:)]) {
    [(id)_davServer.delegate performSelectorOnMainThread:@selector(davServerDidUpdateNumberOfConnections:)
                                              withObject:_davServer
                                           waitUntilDone:NO];
  }
}

- (void) connectionDidDie:(NSNotification*)notification {
  [super connectionDidDie:notification];
  LOG_DEBUG(@"<DAVServer> Removed connection");
  
  if ([_davServer.delegate respondsToSelector:@selector(davServerDidUpdateNumberOfConnections:)]) {
    [(id)_davServer.delegate performSelectorOnMainThread:@selector(davServerDidUpdateNumberOfConnections:)
                                              withObject:_davServer
                                           waitUntilDone:NO];
  }
}

@end

@implementation _DAVConnection

- (DAVServer*) davServer {
  return [(_HTTPServer*)[config server] davServer];
}

- (BOOL) isPasswordProtected:(NSString*)path {
  return self.davServer.password ? YES : NO;
}

- (BOOL) useDigestAccessAuthentication {
  return NO;  // Digest authentication does not work with all WebDAV clients
}

- (NSString*) realm {
  return [self.davServer.rootDirectory lastPathComponent];
}

- (NSString*) passwordForUser:(NSString*)username {
  return self.davServer.password;
}

- (void) _didRespondToMethod:(NSString*)method {
  DAVServer* davServer = self.davServer;
  [davServer.delegate davServer:davServer didRespondToMethod:method];
}

- (NSObject<HTTPResponse>*) httpResponseForMethod:(NSString *)method URI:(NSString *)path {
  LOG_DEBUG(@"<DAVServer> %@: %@", method, path);
  NSObject<HTTPResponse>* response = [super httpResponseForMethod:method URI:path];
  if (response && [self.davServer.delegate respondsToSelector:@selector(davServer:didRespondToMethod:)]) {
    [self performSelectorOnMainThread:@selector(_didRespondToMethod:) withObject:method waitUntilDone:NO];
  }
  return response;
}

@end

@implementation DAVServer

@synthesize rootDirectory=_path, port=_port, password=_password, delegate=_delegate, running=_running;

- (id) init {
  NSString* path = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
  return [self initWithRootDirectory:path];
}

- (id) initWithRootDirectory:(NSString*)path {
  return [self initWithRootDirectory:path port:8080];
}

- (id) initWithRootDirectory:(NSString*)path port:(NSUInteger)port {
  return [self initWithRootDirectory:path port:port password:nil];
}

- (id) initWithRootDirectory:(NSString*)path port:(NSUInteger)port password:(NSString*)password {
  if ((self = [super init])) {
    _path = [path copy];
    _port = port;
    _password = [password copy];
    
    _server = [[_HTTPServer alloc] init];
    [_server setDavServer:self];
    [_server setPort:_port];
    [_server setType:@"_webdav._tcp."];
    [_server setDocumentRoot:_path];
    [_server setConnectionClass:[_DAVConnection class]];
  }
  return self;
}

- (void) dealloc {
  [_server stop];
  [_server release];
  [_path release];
  [_password release];
  
  [super dealloc];
}

- (NSUInteger) numberOfConnections {
  return [_server numberOfHTTPConnections];
}

- (BOOL) start {
  if (_running == NO) {
    NSError* error;
    if ([_server start:&error]) {
      LOG_VERBOSE(@"WebDAV server started on port %i", [(_HTTPServer*)_server port]);
    } else {
      LOG_ERROR(@"Failed starting WebDAV server: %@", [error localizedDescription]);
      return NO;
    }
    _running = YES;
  }
  return YES;
}

- (void) stop:(BOOL)keepConnectionsAlive {
  if (_running == YES) {
    [_server stop:keepConnectionsAlive];
    _running = NO;
    LOG_VERBOSE(@"WebDAV server stopped");
  }
}

- (void) httpServerDidUpdateNumberOfHTTPConnections:(HTTPServer*)server {
  if ([_delegate respondsToSelector:@selector(davServerDidUpdateNumberOfConnections:)]) {
    [_delegate davServerDidUpdateNumberOfConnections:self];
  }
}

@end
