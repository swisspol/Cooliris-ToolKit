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

@interface GCDWebServerResponse : NSObject {
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
+ (GCDWebServerResponse*) response;
- (id) init;
- (id) initWithContentType:(NSString*)type contentLength:(NSUInteger)length;  // Pass nil contentType to indicate empty body
- (void) setValue:(NSString*)value forAdditionalHeader:(NSString*)header;
- (BOOL) hasBody;  // Convenience method
@end

@interface GCDWebServerResponse (Subclassing)
- (BOOL) open;  // Implementation required
- (NSInteger) read:(void*)buffer maxLength:(NSUInteger)length;  // Implementation required
- (BOOL) close;  // Implementation required
@end

@interface GCDWebServerResponse (Extensions)
+ (GCDWebServerResponse*) responseWithStatusCode:(NSInteger)statusCode;
+ (GCDWebServerResponse*) responseWithRedirect:(NSURL*)location permanent:(BOOL)permanent;
- (id) initWithStatusCode:(NSInteger)statusCode;
- (id) initWithRedirect:(NSURL*)location permanent:(BOOL)permanent;
@end

@interface GCDWebServerDataResponse : GCDWebServerResponse {
@private
  NSData* _data;
  NSInteger _offset;
}
+ (GCDWebServerDataResponse*) responseWithData:(NSData*)data contentType:(NSString*)type;
- (id) initWithData:(NSData*)data contentType:(NSString*)type;
@end

@interface GCDWebServerDataResponse (Extensions)
+ (GCDWebServerDataResponse*) responseWithText:(NSString*)text;
+ (GCDWebServerDataResponse*) responseWithHTML:(NSString*)html;
+ (GCDWebServerDataResponse*) responseWithHTMLTemplate:(NSString*)path variables:(NSDictionary*)variables;  // Simple template system that replaces all occurences of "%variable%" with corresponding value (encodes using UTF-8)
- (id) initWithText:(NSString*)text;  // Encodes using UTF-8
- (id) initWithHTML:(NSString*)html;  // Encodes using UTF-8
- (id) initWithHTMLTemplate:(NSString*)path variables:(NSDictionary*)variables;
@end

@interface GCDWebServerFileResponse : GCDWebServerResponse {
@private
  NSString* _path;
  int _file;
}
+ (GCDWebServerFileResponse*) responseWithFile:(NSString*)path;
+ (GCDWebServerFileResponse*) responseWithFile:(NSString*)path isAttachment:(BOOL)attachment;
- (id) initWithFile:(NSString*)path;
- (id) initWithFile:(NSString*)path isAttachment:(BOOL)attachment;
@end
