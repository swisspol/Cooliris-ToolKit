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

#import <TargetConditionals.h>
#if TARGET_OS_IPHONE
#import <CFNetwork/CFNetwork.h>
#import <MobileCoreServices/MobileCoreServices.h>
#else
#import <ApplicationServices/ApplicationServices.h>
#import <CoreServices/CoreServices.h>
#endif
#import <sys/fcntl.h>
#import <sys/stat.h>
#import <netinet/in.h>

#import "GCDWebServer.h"
#import "Extensions_Foundation.h"
#import "Logging.h"

#define kReadWriteQueue dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
#define kHeadersReadBuffer 1024
#define kBodyWriteBufferSize (32 * 1024)

typedef void (^ReadBufferCompletionBlock)(dispatch_data_t buffer);
typedef void (^ReadDataCompletionBlock)(NSData* data);
typedef void (^ReadHeadersCompletionBlock)(NSData* extraData);
typedef void (^ReadBodyCompletionBlock)(BOOL success);

typedef void (^WriteBufferCompletionBlock)(BOOL success);
typedef void (^WriteDataCompletionBlock)(BOOL success);
typedef void (^WriteHeadersCompletionBlock)(BOOL success);
typedef void (^WriteBodyCompletionBlock)(BOOL success);

@interface GCDWebServerHandler : NSObject {
@private
  GCDWebServerMatchBlock _matchBlock;
  GCDWebServerProcessBlock _processBlock;
}
@property(nonatomic, readonly) GCDWebServerMatchBlock matchBlock;
@property(nonatomic, readonly) GCDWebServerProcessBlock processBlock;
- (id) initWithMatchBlock:(GCDWebServerMatchBlock)matchBlock processBlock:(GCDWebServerProcessBlock)processBlock;
@end

@interface GCDWebServerConnection ()
- (id) initWithServer:(GCDWebServer*)server address:(NSData*)address socket:(CFSocketNativeHandle)socket;
@end

@interface GCDWebServer ()
@property(nonatomic, readonly) NSArray* handlers;
@end

static NSData* _separatorData = nil;
static NSData* _continueData = nil;
static NSDateFormatter* _dateFormatter = nil;
static dispatch_queue_t _formatterQueue = NULL;
static BOOL _run;

static void _SignalHandler(int signal) {
  _run = NO;
  printf("\n");
}

@implementation GCDWebServerHandler

@synthesize matchBlock=_matchBlock, processBlock=_processBlock;

- (id) initWithMatchBlock:(GCDWebServerMatchBlock)matchBlock processBlock:(GCDWebServerProcessBlock)processBlock {
  if ((self = [super init])) {
    _matchBlock = Block_copy(matchBlock);
    _processBlock = Block_copy(processBlock);
  }
  return self;
}

- (void) dealloc {
  Block_release(_matchBlock);
  Block_release(_processBlock);
  
  [super dealloc];
}

@end

@implementation GCDWebServerConnection (Read)

- (void) _readBufferWithLength:(NSUInteger)length completionBlock:(ReadBufferCompletionBlock)block {
  dispatch_read(_socket, length, kReadWriteQueue, ^(dispatch_data_t buffer, int error) {
    
    @autoreleasepool {
      if (error == 0) {
        size_t size = dispatch_data_get_size(buffer);
        if (size > 0) {
          LOG_DEBUG(@"Connection received %i bytes on socket %i", size, _socket);
          _bytesRead += size;
          block(buffer);
        } else {
          if (_bytesRead > 0) {
            LOG_ERROR(@"No more data available on socket %i", _socket);
          } else {
            LOG_WARNING(@"No data received from socket %i", _socket);
          }
          block(NULL);
        }
      } else {
        LOG_ERROR(@"Error while reading from socket %i: %s (%i)", _socket, strerror(error), error);
        block(NULL);
      }
    }
    
  });
}

- (void) _readDataWithCompletionBlock:(ReadDataCompletionBlock)block {
  [self _readBufferWithLength:SIZE_T_MAX completionBlock:^(dispatch_data_t buffer) {
    
    if (buffer) {
      NSMutableData* data = [[NSMutableData alloc] initWithCapacity:dispatch_data_get_size(buffer)];
      dispatch_data_apply(buffer, ^bool(dispatch_data_t region, size_t offset, const void* buffer, size_t size) {
        [data appendBytes:buffer length:size];
        return true;
      });
      block(data);
      [data release];
    } else {
      block(nil);
    }
    
  }];
}

- (void) _readHeadersWithCompletionBlock:(ReadHeadersCompletionBlock)block {
  DCHECK(_requestMessage);
  NSMutableData* data = [NSMutableData dataWithCapacity:kHeadersReadBuffer];
  [self _readBufferWithLength:SIZE_T_MAX completionBlock:^(dispatch_data_t buffer) {
    
    if (buffer) {
      dispatch_data_apply(buffer, ^bool(dispatch_data_t region, size_t offset, const void* buffer, size_t size) {
        [data appendBytes:buffer length:size];
        return true;
      });
      NSRange range = [data rangeOfData:_separatorData options:0 range:NSMakeRange(0, data.length)];
      if (range.location == NSNotFound) {
        [self _readHeadersWithCompletionBlock:block];
      } else {
        NSUInteger length = range.location + range.length;
        if (CFHTTPMessageAppendBytes(_requestMessage, data.bytes, length)) {
          if (CFHTTPMessageIsHeaderComplete(_requestMessage)) {
            block([data subdataWithRange:NSMakeRange(length, data.length - length)]);
          } else {
            LOG_ERROR(@"Failed parsing request headers from socket %i", _socket);
            block(nil);
          }
        } else {
          LOG_ERROR(@"Failed appending request headers data from socket %i", _socket);
          block(nil);
        }
      }
    } else {
      block(nil);
    }
    
  }];
}

- (void) _readBodyWithRemainingLength:(NSUInteger)length completionBlock:(ReadBodyCompletionBlock)block {
  DCHECK([_request hasBody]);
  [self _readBufferWithLength:length completionBlock:^(dispatch_data_t buffer) {
    
    if (buffer) {
      NSInteger remainingLength = length - dispatch_data_get_size(buffer);
      if (remainingLength >= 0) {
        bool success = dispatch_data_apply(buffer, ^bool(dispatch_data_t region, size_t offset, const void* buffer, size_t size) {
          NSInteger result = [_request write:buffer maxLength:size];
          if (result != size) {
            LOG_ERROR(@"Failed writing request body on socket %i (error %i)", _socket, result);
            return false;
          }
          return true;
        });
        if (success) {
          if (remainingLength > 0) {
            [self _readBodyWithRemainingLength:remainingLength completionBlock:block];
          } else {
            block(YES);
          }
        } else {
          block(NO);
        }
      } else {
        DNOT_REACHED();
        block(NO);
      }
    } else {
      block(NO);
    }
    
  }];
}

@end

@implementation GCDWebServerConnection (Write)

- (void) _writeBuffer:(dispatch_data_t)buffer withCompletionBlock:(WriteBufferCompletionBlock)block {
  size_t size = dispatch_data_get_size(buffer);
  dispatch_write(_socket, buffer, kReadWriteQueue, ^(dispatch_data_t data, int error) {
    
    @autoreleasepool {
      if (error == 0) {
        DCHECK(data == NULL);
        LOG_DEBUG(@"Connection sent %i bytes on socket %i", size, _socket);
        _bytesWritten += size;
        block(YES);
      } else {
        LOG_ERROR(@"Error while writing to socket %i: %s (%i)", _socket, strerror(error), error);
        block(NO);
      }
    }
    
  });
}

- (void) _writeData:(NSData*)data withCompletionBlock:(WriteDataCompletionBlock)block {
  [data retain];
  dispatch_data_t buffer = dispatch_data_create(data.bytes, data.length, dispatch_get_current_queue(), ^{
    [data release];
  });
  [self _writeBuffer:buffer withCompletionBlock:block];
  dispatch_release(buffer);
}

- (void) _writeHeadersWithCompletionBlock:(WriteHeadersCompletionBlock)block {
  DCHECK(_responseMessage);
  CFDataRef message = CFHTTPMessageCopySerializedMessage(_responseMessage);
  [self _writeData:(NSData*)message withCompletionBlock:block];
  CFRelease(message);
}

- (void) _writeBodyWithCompletionBlock:(WriteBodyCompletionBlock)block {
  DCHECK([_response hasBody]);
  void* buffer = malloc(kBodyWriteBufferSize);
  NSInteger result = [_response read:buffer maxLength:kBodyWriteBufferSize];
  if (result > 0) {
    dispatch_data_t wrapper = dispatch_data_create(buffer, result, NULL, DISPATCH_DATA_DESTRUCTOR_FREE);
    [self _writeBuffer:wrapper withCompletionBlock:^(BOOL success) {
      
      if (success) {
        [self _writeBodyWithCompletionBlock:block];
      } else {
        block(NO);
      }
      
    }];
    dispatch_release(wrapper);
  } else if (result < 0) {
    LOG_ERROR(@"Failed reading response body on socket %i (error %i)", _socket, result);
    block(NO);
    free(buffer);
  } else {
    block(YES);
    free(buffer);
  }
}

@end

@implementation GCDWebServerConnection

@synthesize server=_server, address=_address, totalBytesRead=_bytesRead, totalBytesWritten=_bytesWritten;

- (void) _initializeResponseHeadersWithStatusCode:(NSInteger)statusCode {
  _responseMessage = CFHTTPMessageCreateResponse(kCFAllocatorDefault, statusCode, NULL, kCFHTTPVersion1_1);
  CFHTTPMessageSetHeaderFieldValue(_responseMessage, CFSTR("Connection"), CFSTR("Close"));
  CFHTTPMessageSetHeaderFieldValue(_responseMessage, CFSTR("Server"), (CFStringRef)[[_server class] serverName]);
  dispatch_sync(_formatterQueue, ^{
    NSString* date = [_dateFormatter stringFromDate:[NSDate date]];
    CFHTTPMessageSetHeaderFieldValue(_responseMessage, CFSTR("Date"), (CFStringRef)date);
  });
}

- (void) _abortWithStatusCode:(NSUInteger)statusCode {
  DCHECK(_responseMessage == NULL);
  DCHECK((statusCode >= 400) && (statusCode < 600));
  [self _initializeResponseHeadersWithStatusCode:statusCode];
  [self _writeHeadersWithCompletionBlock:^(BOOL success) {
    ;  // Nothing more to do
  }];
  LOG_DEBUG(@"Connection aborted with status code %i on socket %i", statusCode, _socket);
}

// http://www.w3.org/Protocols/rfc2616/rfc2616-sec10.html
- (void) _processRequest {
  DCHECK(_responseMessage == NULL);
  
  GCDWebServerResponse* response = [self processRequest:_request withBlock:_handler.processBlock];
  if (![response hasBody] || [response open]) {
    _response = [response retain];
  }
  
  if (_response) {
    [self _initializeResponseHeadersWithStatusCode:_response.statusCode];
    NSUInteger maxAge = _response.cacheControlMaxAge;
    if (maxAge > 0) {
      CFHTTPMessageSetHeaderFieldValue(_responseMessage, CFSTR("Cache-Control"), (CFStringRef)[NSString stringWithFormat:@"max-age=%i, public", (int)maxAge]);
    } else {
      CFHTTPMessageSetHeaderFieldValue(_responseMessage, CFSTR("Cache-Control"), CFSTR("no-cache"));
    }
    [_response.additionalHeaders enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL* stop) {
      CFHTTPMessageSetHeaderFieldValue(_responseMessage, (CFStringRef)key, (CFStringRef)obj);
    }];
    if ([_response hasBody]) {
      CFHTTPMessageSetHeaderFieldValue(_responseMessage, CFSTR("Content-Type"), (CFStringRef)_response.contentType);
      CFHTTPMessageSetHeaderFieldValue(_responseMessage, CFSTR("Content-Length"), (CFStringRef)[NSString stringWithFormat:@"%i", (int)_response.contentLength]);
    }
    [self _writeHeadersWithCompletionBlock:^(BOOL success) {
      
      if (success) {
        if ([_response hasBody]) {
          [self _writeBodyWithCompletionBlock:^(BOOL success) {
            
            [_response close];  // Can't do anything with result anyway
            
          }];
        }
      } else if ([_response hasBody]) {
        [_response close];  // Can't do anything with result anyway
      }
      
    }];
  } else {
    [self _abortWithStatusCode:500];
  }
  
}

- (void) _readRequestBody:(NSData*)initialData {
  if ([_request open]) {
    NSInteger length = _request.contentLength;
    if (initialData.length) {
      NSInteger result = [_request write:initialData.bytes maxLength:initialData.length];
      if (result == initialData.length) {
        length -= initialData.length;
        DCHECK(length >= 0);
      } else {
        LOG_ERROR(@"Failed writing request body on socket %i (error %i)", _socket, result);
        length = -1;
      }
    }
    if (length > 0) {
      [self _readBodyWithRemainingLength:length completionBlock:^(BOOL success) {
        
        if (![_request close]) {
          success = NO;
        }
        if (success) {
          [self _processRequest];
        } else {
          [self _abortWithStatusCode:500];
        }
        
      }];
    } else if (length == 0) {
      if ([_request close]) {
        [self _processRequest];
      } else {
        [self _abortWithStatusCode:500];
      }
    } else {
      [_request close];  // Can't do anything with result anyway
      [self _abortWithStatusCode:500];
    }
  } else {
    [self _abortWithStatusCode:500];
  }
}

- (void) _readRequestHeaders {
  _requestMessage = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, true);
  [self _readHeadersWithCompletionBlock:^(NSData* extraData) {
    
    if (extraData) {
      NSString* requestMethod = [[(id)CFHTTPMessageCopyRequestMethod(_requestMessage) autorelease] uppercaseString];
      DCHECK(requestMethod);
      NSURL* requestURL = [(id)CFHTTPMessageCopyRequestURL(_requestMessage) autorelease];
      DCHECK(requestURL);
      NSString* requestPath = [[(id)CFURLCopyPath((CFURLRef)requestURL) autorelease] unescapeURLString];  // Don't use -[NSURL path] which strips the ending slash
      DCHECK(requestPath);
      NSDictionary* requestQuery = nil;
      NSString* queryString = [(id)CFURLCopyQueryString((CFURLRef)requestURL, NULL) autorelease];  // Don't use -[NSURL query] to make sure query is not unescaped;
      if (queryString.length) {
        requestQuery = [NSURL parseURLEncodedForm:queryString unescapeKeysAndValues:YES];
        DCHECK(requestQuery);
      }
      NSDictionary* requestHeaders = [(id)CFHTTPMessageCopyAllHeaderFields(_requestMessage) autorelease];
      DCHECK(requestHeaders);
      for (_handler in _server.handlers) {
        _request = [_handler.matchBlock(requestMethod, requestURL, requestHeaders, requestPath, requestQuery) retain];
        if (_request) {
          break;
        }
      }
      if (_request) {
        if (_request.hasBody) {
          if (extraData.length <= _request.contentLength) {
            NSString* expectHeader = [(id)CFHTTPMessageCopyHeaderFieldValue(_requestMessage, CFSTR("Expect")) autorelease];
            if (expectHeader) {
              if ([expectHeader caseInsensitiveCompare:@"100-continue"] == NSOrderedSame) {
                [self _writeData:_continueData withCompletionBlock:^(BOOL success) {
                  
                  if (success) {
                    [self _readRequestBody:extraData];
                  }
                  
                }];
              } else {
                LOG_ERROR(@"Unsupported 'Expect' / 'Content-Length' header combination on socket %i", _socket);
                [self _abortWithStatusCode:417];
              }
            } else {
              [self _readRequestBody:extraData];
            }
          } else {
            LOG_ERROR(@"Unexpected 'Content-Length' header value on socket %i", _socket);
            [self _abortWithStatusCode:400];
          }
        } else {
          [self _processRequest];
        }
      } else {
        [self _abortWithStatusCode:405];
      }
    } else {
      [self _abortWithStatusCode:500];
    }
    
  }];
}

- (id) initWithServer:(GCDWebServer*)server address:(NSData*)address socket:(CFSocketNativeHandle)socket {
  if ((self = [super init])) {
    _server = [server retain];
    _address = [address retain];
    _socket = socket;
    
    [self open];
  }
  return self;
}

- (void) dealloc {
  [self close];
  
  [_server release];
  [_address release];
  
  if (_requestMessage) {
    CFRelease(_requestMessage);
  }
  [_request release];
  
  if (_responseMessage) {
    CFRelease(_responseMessage);
  }
  [_response release];
  
  [super dealloc];
}

@end

@implementation GCDWebServerConnection (Subclassing)

- (void) open {
  LOG_DEBUG(@"Did open connection on socket %i", _socket);
  [self _readRequestHeaders];
}

- (GCDWebServerResponse*) processRequest:(GCDWebServerRequest*)request withBlock:(GCDWebServerProcessBlock)block {
  LOG_DEBUG(@"Connection on socket %i processing %@ request for \"%@\" (%i bytes body)", _socket, _request.method, _request.path, _request.contentLength);
  GCDWebServerResponse* response = nil;
  @try {
    response = block(request);
  }
  @catch (NSException* exception) {
    LOG_EXCEPTION(exception);
  }
  return response;
}

- (void) close {
  close(_socket);
  LOG_DEBUG(@"Did close connection on socket %i", _socket);
}

@end

@implementation GCDWebServer

@synthesize handlers=_handlers, port=_port;

+ (void) initialize {
  DCHECK([NSThread isMainThread]);  // NSDateFormatter should be initialized on main thread
  if (_separatorData == nil) {
    _separatorData = [[NSData alloc] initWithBytes:"\r\n\r\n" length:4];
    DCHECK(_separatorData);
  }
  if (_continueData == nil) {
    CFHTTPMessageRef message = CFHTTPMessageCreateResponse(kCFAllocatorDefault, 100, NULL, kCFHTTPVersion1_1);
    _continueData = (NSData*)CFHTTPMessageCopySerializedMessage(message);
    CFRelease(message);
    DCHECK(_continueData);
  }
  if (_dateFormatter == nil) {
    _dateFormatter = [[NSDateFormatter alloc] init];
    _dateFormatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"GMT"];
    _dateFormatter.dateFormat = @"EEE',' dd MMM yyyy HH':'mm':'ss 'GMT'";
    _dateFormatter.locale = [[[NSLocale alloc] initWithLocaleIdentifier:@"en_US"] autorelease];
    DCHECK(_dateFormatter);
  }
  if (_formatterQueue == NULL) {
    _formatterQueue = dispatch_queue_create(NULL, DISPATCH_QUEUE_SERIAL);
    DCHECK(_formatterQueue);
  }
}

- (id) init {
  if ((self = [super init])) {
    _handlers = [[NSMutableArray alloc] init];
  }
  return self;
}

- (void) dealloc {
  if (_runLoop) {
    [self stop];
  }
  
  [_handlers release];
  
  [super dealloc];
}

- (void) addHandlerWithMatchBlock:(GCDWebServerMatchBlock)matchBlock processBlock:(GCDWebServerProcessBlock)handlerBlock {
  CHECK(_runLoop == nil);
  GCDWebServerHandler* handler = [[GCDWebServerHandler alloc] initWithMatchBlock:matchBlock processBlock:handlerBlock];
  [_handlers insertObject:handler atIndex:0];
  [handler release];
}

- (void) removeAllHandlers {
  CHECK(_runLoop == nil);
  [_handlers removeAllObjects];
}

- (BOOL) start {
  return [self startWithRunloop:[NSRunLoop mainRunLoop] port:8080 bonjourName:@""];
}

static void _NetServiceClientCallBack(CFNetServiceRef service, CFStreamError* error, void* info) {
  @autoreleasepool {
    if (error->error) {
      LOG_ERROR(@"Bonjour error %i (domain %i)", error->error, error->domain);
    } else {
      LOG_VERBOSE(@"Registered Bonjour service \"%@\" with type '%@' on port %i", CFNetServiceGetName(service), CFNetServiceGetType(service), CFNetServiceGetPortNumber(service));
    }
  }
}

static void _SocketCallBack(CFSocketRef socket, CFSocketCallBackType type, CFDataRef address, const void* data, void* info) {
  if (type == kCFSocketAcceptCallBack) {
    CFSocketNativeHandle handle = *(CFSocketNativeHandle*)data;
    int set = 1;
    setsockopt(handle, SOL_SOCKET, SO_NOSIGPIPE, (void *)&set, sizeof(int));  // Make sure this socket cannot generate SIG_PIPE
    @autoreleasepool {
      Class class = [[(GCDWebServer*)info class] connectionClass];
      GCDWebServerConnection* connection = [[class alloc] initWithServer:(GCDWebServer*)info address:(NSData*)address socket:handle];
      [connection release];  // Connection will automatically retain itself while opened
    }
  } else {
    DNOT_REACHED();
  }
}

- (BOOL) startWithRunloop:(NSRunLoop*)runloop port:(NSUInteger)port bonjourName:(NSString*)name {
  DCHECK(runloop);
  DCHECK(port);
  CHECK(_runLoop == nil);
  CFSocketContext context = {0, self, NULL, NULL, NULL};
  _socket = CFSocketCreate(kCFAllocatorDefault, PF_INET, SOCK_STREAM, IPPROTO_TCP, kCFSocketAcceptCallBack, _SocketCallBack, &context);
  if (_socket) {
    int yes = 1;
    setsockopt(CFSocketGetNative(_socket), SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    
    struct sockaddr_in addr4;
    bzero(&addr4, sizeof(addr4));
    addr4.sin_len = sizeof(addr4);
    addr4.sin_family = AF_INET;
    addr4.sin_port = htons(port);
    addr4.sin_addr.s_addr = htonl(INADDR_ANY);
    if (CFSocketSetAddress(_socket, (CFDataRef)[NSData dataWithBytes:&addr4 length:sizeof(addr4)]) == kCFSocketSuccess) {
      CFRunLoopSourceRef source = CFSocketCreateRunLoopSource(kCFAllocatorDefault, _socket, 0);
      CFRunLoopAddSource([runloop getCFRunLoop], source, kCFRunLoopCommonModes);
      CFRelease(source);
      
      if (name) {
        _service = CFNetServiceCreate(kCFAllocatorDefault, CFSTR("local."), CFSTR("_http._tcp"), (CFStringRef)name, port);
        if (_service) {
          CFNetServiceClientContext context = {0, self, NULL, NULL, NULL};
          CFNetServiceSetClient(_service, _NetServiceClientCallBack, &context);
          CFNetServiceScheduleWithRunLoop(_service, [runloop getCFRunLoop], kCFRunLoopCommonModes);
          CFStreamError error = {0};
          CFNetServiceRegisterWithOptions(_service, 0, &error);
        } else {
          LOG_ERROR(@"Failed creating CFNetService");
        }
      }
      
      _port = port;
      _runLoop = [runloop retain];
      LOG_VERBOSE(@"%@ started on port %i", [self class], port);
    } else {
      LOG_ERROR(@"Failed binding socket");
      CFRelease(_socket);
      _socket = NULL;
    }
  } else {
    LOG_ERROR(@"Failed creating CFSocket");
  }
  return (_runLoop != nil ? YES : NO);
}

- (BOOL) isRunning {
  return (_runLoop != nil ? YES : NO);
}

- (void) stop {
  CHECK(_runLoop != nil);
  if (_socket) {
    if (_service) {
      CFNetServiceUnscheduleFromRunLoop(_service, [_runLoop getCFRunLoop], kCFRunLoopCommonModes);
      CFNetServiceSetClient(_service, NULL, NULL);
      CFRelease(_service);
    }
    
    CFSocketInvalidate(_socket);
    CFRelease(_socket);
    _socket = NULL;
    LOG_VERBOSE(@"%@ stopped", [self class]);
  }
  [_runLoop release];
  _runLoop = nil;
  _port = 0;
}

@end

@implementation GCDWebServer (Subclassing)

+ (Class) connectionClass {
  return [GCDWebServerConnection class];
}

+ (NSString*) serverName {
  return NSStringFromClass(self);
}

@end

@implementation GCDWebServer (Extensions)

- (BOOL) runWithPort:(NSUInteger)port {
  BOOL success = NO;
  _run = YES;
  void* handler = signal(SIGINT, _SignalHandler);
  if (handler != SIG_ERR) {
    if ([self startWithRunloop:[NSRunLoop currentRunLoop] port:port bonjourName:@""]) {
      while (_run) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
      }
      [self stop];
      success = YES;
    }
    signal(SIGINT, handler);
  }
  return success;
}

@end

@implementation GCDWebServer (Handlers)

- (void) addDefaultHandlerForMethod:(NSString*)method requestClass:(Class)class processBlock:(GCDWebServerProcessBlock)block {
  [self addHandlerWithMatchBlock:^GCDWebServerRequest *(NSString* requestMethod, NSURL* requestURL, NSDictionary* requestHeaders, NSString* urlPath, NSDictionary* urlQuery) {
    
    return [[[class alloc] initWithMethod:requestMethod url:requestURL headers:requestHeaders path:urlPath query:urlQuery] autorelease];
    
  } processBlock:block];
}

- (GCDWebServerResponse*) _responseWithContentsOfFile:(NSString*)path {
  return [GCDWebServerFileResponse responseWithFile:path];
}

- (GCDWebServerResponse*) _responseWithContentsOfDirectory:(NSString*)path {
  NSDirectoryEnumerator* enumerator = [[NSFileManager defaultManager] enumeratorAtPath:path];
  if (enumerator == nil) {
    return nil;
  }
  NSMutableString* html = [NSMutableString string];
  [html appendString:@"<html><body>\n"];
  [html appendString:@"<ul>\n"];
  for (NSString* file in enumerator) {
    if (![file hasPrefix:@"."]) {
      NSString* type = [[enumerator fileAttributes] objectForKey:NSFileType];
      NSString* escapedFile = [file stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
      DCHECK(escapedFile);
      if ([type isEqualToString:NSFileTypeRegular]) {
        [html appendFormat:@"<li><a href=\"%@\">%@</a></li>\n", escapedFile, file];
      } else if ([type isEqualToString:NSFileTypeDirectory]) {
        [html appendFormat:@"<li><a href=\"%@/\">%@/</a></li>\n", escapedFile, file];
      }
    }
    [enumerator skipDescendents];
  }
  [html appendString:@"</ul>\n"];
  [html appendString:@"</body></html>\n"];
  return [GCDWebServerDataResponse responseWithHTML:html];
}

- (void) addHandlerForBasePath:(NSString*)basePath localPath:(NSString*)localPath indexFilename:(NSString*)indexFilename cacheAge:(NSUInteger)cacheAge {
  if ([basePath hasPrefix:@"/"] && [basePath hasSuffix:@"/"]) {
    [self addHandlerWithMatchBlock:^GCDWebServerRequest *(NSString* requestMethod, NSURL* requestURL, NSDictionary* requestHeaders, NSString* urlPath, NSDictionary* urlQuery) {
      
      if (![requestMethod isEqualToString:@"GET"]) {
        return nil;
      }
      if (![urlPath hasPrefix:basePath]) {
        return nil;
      }
      return [[[GCDWebServerRequest alloc] initWithMethod:requestMethod url:requestURL headers:requestHeaders path:urlPath query:urlQuery] autorelease];
      
    } processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
      
      GCDWebServerResponse* response = nil;
      NSString* filePath = [localPath stringByAppendingPathComponent:[request.path substringFromIndex:basePath.length]];
      BOOL isDirectory;
      if ([[NSFileManager defaultManager] fileExistsAtPath:filePath isDirectory:&isDirectory]) {
        if (isDirectory) {
          if (indexFilename) {
            NSString* indexPath = [filePath stringByAppendingPathComponent:indexFilename];
            if ([[NSFileManager defaultManager] fileExistsAtPath:indexPath isDirectory:&isDirectory] && !isDirectory) {
              return [self _responseWithContentsOfFile:indexPath];
            }
          }
          response = [self _responseWithContentsOfDirectory:filePath];
        } else {
          response = [self _responseWithContentsOfFile:filePath];
        }
      }
      if (response) {
        response.cacheControlMaxAge = cacheAge;
      } else {
        response = [GCDWebServerResponse responseWithStatusCode:404];
      }
      return response;
      
    }];
  } else {
    DNOT_REACHED();
  }
}

- (void) addHandlerForMethod:(NSString*)method path:(NSString*)path requestClass:(Class)class processBlock:(GCDWebServerProcessBlock)block {
  if ([path hasPrefix:@"/"] && [class isSubclassOfClass:[GCDWebServerRequest class]]) {
    [self addHandlerWithMatchBlock:^GCDWebServerRequest *(NSString* requestMethod, NSURL* requestURL, NSDictionary* requestHeaders, NSString* urlPath, NSDictionary* urlQuery) {
      
      if (![requestMethod isEqualToString:method]) {
        return nil;
      }
      if ([urlPath caseInsensitiveCompare:path] != NSOrderedSame) {
        return nil;
      }
      return [[[class alloc] initWithMethod:requestMethod url:requestURL headers:requestHeaders path:urlPath query:urlQuery] autorelease];
      
    } processBlock:block];
  } else {
    DNOT_REACHED();
  }
}

- (void) addHandlerForMethod:(NSString*)method pathRegex:(NSString*)regex requestClass:(Class)class processBlock:(GCDWebServerProcessBlock)block {
  NSRegularExpression* expression = [NSRegularExpression regularExpressionWithPattern:regex options:NSRegularExpressionCaseInsensitive error:NULL];
  if (expression && [class isSubclassOfClass:[GCDWebServerRequest class]]) {
    [self addHandlerWithMatchBlock:^GCDWebServerRequest *(NSString* requestMethod, NSURL* requestURL, NSDictionary* requestHeaders, NSString* urlPath, NSDictionary* urlQuery) {
      
      if (![requestMethod isEqualToString:method]) {
        return nil;
      }
      if ([expression firstMatchInString:urlPath options:0 range:NSMakeRange(0, urlPath.length)] == nil) {
        return nil;
      }
      return [[[class alloc] initWithMethod:requestMethod url:requestURL headers:requestHeaders path:urlPath query:urlQuery] autorelease];
      
    } processBlock:block];
  } else {
    DNOT_REACHED();
  }
}

@end
