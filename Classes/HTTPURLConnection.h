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

#import <Foundation/Foundation.h>

#define kHTTPURLConnection_HeaderField_RedirectedURL @".RedirectedURL"  // In case of multiple redirects, this will be the last one
#define kHTTPURLConnection_HeaderField_DataLength @".DataLength"
#define kHTTPURLConnection_HeaderField_MIMEType @".MIMEType"
#define kHTTPURLConnection_HeaderField_TextEncodingName @".TextEncodingName"
#define kHTTPURLConnection_HeaderField_SuggestedFilename @".SuggestedFilename"

@protocol HTTPURLConnectionDelegate <NSObject>
- (BOOL) isCancelled;
@end

// Caching is completely disabled
@interface HTTPURLConnection : NSURLConnection {
@private
  NSOutputStream* _stream;
  NSInteger _status;
  NSURL* _redirectedURL;
  NSHTTPURLResponse* _response;
  NSError* _error;
  NSUInteger _length;
}
+ (NSMutableURLRequest*) HTTPRequestWithURL:(NSURL*)url
                                     method:(NSString*)method
                                  userAgent:(NSString*)userAgent
                              handleCookies:(BOOL)handleCookies;
+ (NSInteger) downloadHTTPRequest:(NSURLRequest*)request
                         toStream:(NSOutputStream*)stream
                         delegate:(id<HTTPURLConnectionDelegate>)delegate
                     headerFields:(NSDictionary**)headerFields;  // Follows redirects - Delegate can be nil - Returns HTTP status code
@end

@interface HTTPURLConnection (Extensions)
+ (NSDictionary*) downloadHeaderFieldsForHTTPRequest:(NSMutableURLRequest*)request
                                            delegate:(id<HTTPURLConnectionDelegate>)delegate;
+ (NSDictionary*) downloadHeaderFieldsFromHTTPURL:(NSURL*)url
                                        userAgent:(NSString*)userAgent
                                    handleCookies:(BOOL)handleCookies
                                         delegate:(id<HTTPURLConnectionDelegate>)delegate;
+ (NSData*) downloadHTTPRequestToMemory:(NSMutableURLRequest*)request
                               delegate:(id<HTTPURLConnectionDelegate>)delegate
                           headerFields:(NSDictionary**)headerFields;
+ (NSData*) downloadContentsToMemoryFromHTTPURL:(NSURL*)url
                                      userAgent:(NSString*)userAgent
                                  handleCookies:(BOOL)handleCookies
                                       delegate:(id<HTTPURLConnectionDelegate>)delegate
                                   headerFields:(NSDictionary**)headerFields;
+ (BOOL) downloadHTTPRequest:(NSMutableURLRequest*)request
                toFileAtPath:(NSString*)path
                      resume:(BOOL)resume
                    delegate:(id<HTTPURLConnectionDelegate>)delegate
                headerFields:(NSDictionary**)headerFields;
+ (BOOL) downloadContentsFromHTTPURL:(NSURL*)url
                        toFileAtPath:(NSString*)path
                              resume:(BOOL)resume
                           userAgent:(NSString*)userAgent
                       handleCookies:(BOOL)handleCookies
                            delegate:(id<HTTPURLConnectionDelegate>)delegate
                        headerFields:(NSDictionary**)headerFields;
@end
