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

#import "HTTPURLConnection.h"
#import "Logging.h"

#define kURLConnectionTimeOut 30.0 // Default is 60.0
#define kTaskURLDownloadRunLoopMode "TaskURLDownloadMode"
#define kTaskURLDownloadRunLoopInterval 0.5

@interface HTTPURLConnection ()
@property(nonatomic, retain) NSOutputStream* stream;
@property(nonatomic) NSInteger status;
@property(nonatomic, retain) NSURL* redirectedURL;
@property(nonatomic, retain) NSHTTPURLResponse* response;
@property(nonatomic, retain) NSError* error;
@property(nonatomic) NSUInteger length;
@end

@implementation HTTPURLConnection

@synthesize stream=_stream, status=_status, redirectedURL=_redirectedURL, response=_response, error=_error, length=_length;

- (void) dealloc {
  [_stream release];
  [_redirectedURL release];
  [_response release];
  [_error release];
  
  [super dealloc];
}

+ (NSMutableURLRequest*) HTTPRequestWithURL:(NSURL*)url
                                     method:(NSString*)method
                                  userAgent:(NSString*)userAgent
                              handleCookies:(BOOL)handleCookies {
  NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:url
                                                         cachePolicy:NSURLRequestReloadIgnoringCacheData
                                                     timeoutInterval:kURLConnectionTimeOut];
  [request setValue:@"gzip" forHTTPHeaderField:@"Accept-Encoding"];
  [request setValue:userAgent forHTTPHeaderField:@"User-Agent"];  // Passing nil is OK
  [request setHTTPShouldHandleCookies:handleCookies];
  [request setHTTPMethod:method];
  return request;
}

+ (NSURLRequest*) connection:(NSURLConnection*)connection willSendRequest:(NSURLRequest*)request redirectResponse:(NSURLResponse*)response {
  if (response) {
    LOG_VERBOSE(@"(REDIRECT) %@ %@", [request HTTPMethod], [request URL]);
    [(HTTPURLConnection*)connection setRedirectedURL:[request URL]];
  }
  return request;
}

+ (void) connection:(NSURLConnection*)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge*)challenge {
  LOG_VERBOSE(@"Ignoring authentication challenge with method \"%@\" for \"%@://%@:%i\" (%@)",
              [[challenge protectionSpace] authenticationMethod], [[challenge protectionSpace] protocol],
              [[challenge protectionSpace] host], [[challenge protectionSpace] port], [[challenge protectionSpace] realm]);
  
  [challenge.sender continueWithoutCredentialForAuthenticationChallenge:challenge];
}

+ (void) connection:(NSURLConnection*)connection didReceiveResponse:(NSURLResponse*)response {
  if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
    [(HTTPURLConnection*)connection setResponse:(NSHTTPURLResponse*)response];
  }
}

+ (NSCachedURLResponse*) connection:(NSURLConnection*)connection willCacheResponse:(NSCachedURLResponse*)cachedResponse {
  return nil;
}

+ (void) connection:(NSURLConnection*)connection didReceiveData:(NSData*)data {
  NSInteger length;
  NSOutputStream* stream = [(HTTPURLConnection*)connection stream];
  if (stream) {
    length = [stream write:data.bytes maxLength:data.length];
    if (length != data.length) {
      [(HTTPURLConnection*)connection cancel];
      [(HTTPURLConnection*)connection setError:[stream streamError]];
      [(HTTPURLConnection*)connection setStatus:(-1)];
    }
  } else {
    length = data.length;
  }
  [(HTTPURLConnection*)connection setLength:([(HTTPURLConnection*)connection length] + length)];
}

+ (void) connectionDidFinishLoading:(NSURLConnection*)connection {
  [(HTTPURLConnection*)connection setStatus:(1)];
}

+ (void) connection:(NSURLConnection*)connection didFailWithError:(NSError*)error {
  [(HTTPURLConnection*)connection setError:error];
  [(HTTPURLConnection*)connection setStatus:(-1)];
}

+ (NSInteger) downloadHTTPRequest:(NSURLRequest*)request
                         toStream:(NSOutputStream*)stream
                         delegate:(id<HTTPURLConnectionDelegate>)delegate
                     headerFields:(NSDictionary**)headerFields {
  NSInteger statusCode = 0;
  if (![delegate isCancelled]) {
    LOG_VERBOSE(@"%@ %@", [request HTTPMethod], [request URL]);
    [stream open];
    HTTPURLConnection* connection = [[HTTPURLConnection alloc] initWithRequest:request delegate:self startImmediately:NO];
    connection.stream = stream;
    [connection scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:@kTaskURLDownloadRunLoopMode];
    [connection start];
#ifndef NDEBUG
    CFTimeInterval time = CFAbsoluteTimeGetCurrent();
#endif
    while (connection.status == 0) {
      CFRunLoopRunInMode(CFSTR(kTaskURLDownloadRunLoopMode), kTaskURLDownloadRunLoopInterval, true);
      if ([delegate isCancelled]) {
        LOG_DEBUG(@"Cancelling download of \"%@\"", request.URL);
        [connection cancel];
        break;
      }
    }
#ifndef NDEBUG
    time = CFAbsoluteTimeGetCurrent() - time;
#endif
    NSHTTPURLResponse* response = connection.response;
    NSDictionary* headers = response.allHeaderFields;
    if (connection.status > 0) {
#ifndef NDEBUG
      NSInteger contentLength = [[headers objectForKey:@"Content-Length"] integerValue];
      if (contentLength > 0) {
        LOG_DEBUG(@"%i bytes downloaded from \"%@\" in %.3f seconds (%.0f%% compression)", contentLength, connection.response.URL,
                  time, (1.0 - [[headers objectForKey:@"Content-Length"] floatValue] / (float)connection.length) * 100.0);
      } else {
        LOG_DEBUG(@"%i bytes downloaded from \"%@\" in %.3f seconds", connection.length, connection.response.URL, time);
      }
#endif
      if (headerFields) {
        *headerFields = [NSMutableDictionary dictionaryWithDictionary:headers];
        [(NSMutableDictionary*)*headerFields setValue:connection.redirectedURL forKey:kHTTPURLConnection_HeaderField_RedirectedURL];
        [(NSMutableDictionary*)*headerFields setValue:[NSString stringWithFormat:@"%i", connection.length]
                                               forKey:kHTTPURLConnection_HeaderField_DataLength];
        [(NSMutableDictionary*)*headerFields setValue:response.MIMEType forKey:kHTTPURLConnection_HeaderField_MIMEType];
        [(NSMutableDictionary*)*headerFields setValue:response.textEncodingName forKey:kHTTPURLConnection_HeaderField_TextEncodingName];
        [(NSMutableDictionary*)*headerFields setValue:response.suggestedFilename forKey:kHTTPURLConnection_HeaderField_SuggestedFilename];
      }
      statusCode = response.statusCode;
    } else if (![delegate isCancelled]) {
      NSError* error = connection.error;
      if ([error.domain isEqualToString:NSURLErrorDomain] && (error.code == NSURLErrorNotConnectedToInternet)) {
        LOG_VERBOSE(@"No Internet connection to download \"%@\"", request.URL);
      } else {
        NSString* description = [error localizedDescription];
        if (description.length) {
          LOG_ERROR(@"Failed downloading \"%@\": %@", request.URL, description);
        } else {
          LOG_ERROR(@"Failed downloading \"%@\" (%i status - %i bytes received)", request.URL, response.statusCode, connection.length);
        }
      }
    }
    [connection release];
    [stream close];
  }
  return statusCode;
}

@end

@implementation HTTPURLConnection (Extensions)

+ (NSDictionary*) downloadHeaderFieldsForHTTPRequest:(NSMutableURLRequest*)request
                                            delegate:(id<HTTPURLConnectionDelegate>)delegate {
  NSDictionary* headerFields = nil;
  NSInteger status = [self downloadHTTPRequest:request toStream:nil delegate:delegate headerFields:&headerFields];
  if (status == 200) { // OK
    return headerFields;
  } else if (status) {
    LOG_WARNING(@"Failed checking \"%@\" (unexpected %i status)", request.URL, status);
  }
  return nil;
}

+ (NSDictionary*) downloadHeaderFieldsFromHTTPURL:(NSURL*)url
                                        userAgent:(NSString*)userAgent
                                    handleCookies:(BOOL)handleCookies
                                         delegate:(id<HTTPURLConnectionDelegate>)delegate {
  NSMutableURLRequest* request = [self HTTPRequestWithURL:url method:@"HEAD" userAgent:userAgent handleCookies:handleCookies];
  return [self downloadHeaderFieldsForHTTPRequest:request delegate:delegate];
}

+ (NSData*) downloadHTTPRequestToMemory:(NSMutableURLRequest*)request
                               delegate:(id<HTTPURLConnectionDelegate>)delegate
                           headerFields:(NSDictionary**)headerFields {
  NSData* data = nil;
  NSOutputStream* stream = [[NSOutputStream alloc] initToMemory];
  NSInteger status = [self downloadHTTPRequest:request toStream:stream delegate:delegate headerFields:headerFields];
  if (status == 200) {  // OK
    data = [[[stream propertyForKey:NSStreamDataWrittenToMemoryStreamKey] retain] autorelease];
    if (data == nil) {
      data = [NSData data];
    }
  } else if (status) {
    LOG_ERROR(@"Failed downloading \"%@\" (unexpected %i status)", request.URL, status);
  }
  [stream release];
  return data;
}

+ (NSData*) downloadContentsToMemoryFromHTTPURL:(NSURL*)url
                                      userAgent:(NSString*)userAgent
                                  handleCookies:(BOOL)handleCookies
                                       delegate:(id<HTTPURLConnectionDelegate>)delegate
                                   headerFields:(NSDictionary**)headerFields {
  NSMutableURLRequest* request = [self HTTPRequestWithURL:url method:@"GET" userAgent:userAgent handleCookies:handleCookies];
  return [self downloadHTTPRequestToMemory:request delegate:delegate headerFields:headerFields];
}

+ (BOOL) downloadHTTPRequest:(NSMutableURLRequest*)request
                toFileAtPath:(NSString*)path
                      resume:(BOOL)resume
                    delegate:(id<HTTPURLConnectionDelegate>)delegate
                headerFields:(NSDictionary**)headerFields {
  BOOL append = NO;
  if (resume) {
    NSUInteger length = [[[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL] fileSize];
    if (length > 0) {
      [request setValue:[NSString stringWithFormat:@"bytes=%i-", length] forHTTPHeaderField:@"Range"];
      append = YES;
    }
  }
  NSOutputStream* stream = [[NSOutputStream alloc] initToFileAtPath:path append:append];
  NSInteger status = [self downloadHTTPRequest:request toStream:stream delegate:delegate headerFields:headerFields];
  [stream release];
  if ((!append && (status == 200)) || (append && (status == 206))) {  // OK - Partial Content
    return YES;
  } else if (status) {
    LOG_ERROR(@"Failed downloading \"%@\" (unexpected %i status)", request.URL, status);
  }
  if (!resume && ![[NSFileManager defaultManager] removeItemAtPath:path error:NULL]) {
    LOG_ERROR(@"Failed deleting download file \"%@\"", path);
  }
  return NO;
}

+ (BOOL) downloadContentsFromHTTPURL:(NSURL*)url
                        toFileAtPath:(NSString*)path
                              resume:(BOOL)resume
                           userAgent:(NSString*)userAgent
                       handleCookies:(BOOL)handleCookies
                            delegate:(id<HTTPURLConnectionDelegate>)delegate
                        headerFields:(NSDictionary**)headerFields {
  NSMutableURLRequest* request = [self HTTPRequestWithURL:url method:@"GET" userAgent:userAgent handleCookies:handleCookies];
  return [self downloadHTTPRequest:request toFileAtPath:path resume:resume delegate:delegate headerFields:headerFields];
}

@end
