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

#import <Foundation/Foundation.h>

@interface WebServerResponse : NSObject {
@private
  NSString* _type;
  NSUInteger _length;
  NSInteger _status;
  NSUInteger _maxAge;
  NSMutableDictionary* _headers;
}
@property(nonatomic, readonly) NSString* contentType;
@property(nonatomic, readonly) NSUInteger contentLength;
@property(nonatomic) NSInteger statusCode;  // Default is 200
@property(nonatomic) NSUInteger cacheControlMaxAge;  // Default is 0 seconds i.e. "no-cache"
@property(nonatomic, readonly) NSDictionary* additionalHeaders;
+ (WebServerResponse*) response;
- (id) init;
- (id) initWithContentType:(NSString*)type contentLength:(NSUInteger)length;  // Pass nil contentType to indicate empty body
- (void) setValue:(NSString*)value forAdditionalHeader:(NSString*)header;
- (BOOL) hasBody;  // Convenience method
@end

@interface WebServerResponse (Subclassing)
- (BOOL) open;
- (NSInteger) read:(void*)buffer maxLength:(NSUInteger)length;
- (BOOL) close;
@end

@interface WebServerResponse (Extensions)
+ (WebServerResponse*) responseWithStatusCode:(NSInteger)statusCode;
- (id) initWithStatusCode:(NSInteger)statusCode;  // Convenience method
@end

@interface WebServerDataResponse : WebServerResponse {
@private
  NSData* _data;
  NSInteger _offset;
}
+ (WebServerDataResponse*) responseWithData:(NSData*)data contentType:(NSString*)type;
- (id) initWithData:(NSData*)data contentType:(NSString*)type;
@end

@interface WebServerDataResponse (Extensions)
+ (WebServerDataResponse*) responseWithText:(NSString*)text;
+ (WebServerDataResponse*) responseWithHTML:(NSString*)html;
- (id) initWithText:(NSString*)text;  // Encodes using UTF-8
- (id) initWithHTML:(NSString*)html;  // Encodes using UTF-8
@end

@interface WebServerFileResponse : WebServerResponse {
@private
  NSString* _path;
  int _file;
}
+ (WebServerFileResponse*) responseWithFile:(NSString*)path;
- (id) initWithFile:(NSString*)path;
@end
