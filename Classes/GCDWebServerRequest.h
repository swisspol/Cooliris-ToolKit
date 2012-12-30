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

@interface GCDWebServerRequest : NSObject {
@private
  NSString* _method;
  NSURL* _url;
  NSDictionary* _headers;
  NSString* _path;
  NSDictionary* _query;
  NSString* _type;
  NSUInteger _length;
}
@property(nonatomic, readonly) NSString* method;
@property(nonatomic, readonly) NSURL* URL;
@property(nonatomic, readonly) NSDictionary* headers;
@property(nonatomic, readonly) NSString* path;
@property(nonatomic, readonly) NSDictionary* query;  // May be nil
@property(nonatomic, readonly) NSString* contentType;  // Automatically parsed from headers (nil if request has no body)
@property(nonatomic, readonly) NSUInteger contentLength;  // Automatically parsed from headers
- (id) initWithMethod:(NSString*)method url:(NSURL*)url headers:(NSDictionary*)headers path:(NSString*)path query:(NSDictionary*)query;
- (BOOL) hasBody;  // Convenience method
@end

@interface GCDWebServerRequest (Subclassing)
- (BOOL) open;  // Implementation required
- (NSInteger) write:(const void*)buffer maxLength:(NSUInteger)length;  // Implementation required
- (BOOL) close;  // Implementation required
@end

@interface GCDWebServerDataRequest : GCDWebServerRequest {
@private
  NSMutableData* _data;
}
@property(nonatomic, readonly) NSData* data;  // Only valid after open / write / close sequence
@end

@interface GCDWebServerFileRequest : GCDWebServerRequest {
@private
  NSString* _filePath;
  int _file;
}
@property(nonatomic, readonly) NSString* filePath;  // Only valid after open / write / close sequence
@end

@interface GCDWebServerURLEncodedFormRequest : GCDWebServerDataRequest {
@private
  NSDictionary* _arguments;
}
@property(nonatomic, readonly) NSDictionary* arguments;  // Only valid after open / write / close sequence
+ (NSString*) mimeType;
@end

@interface GCDWebServerMultiPart : NSObject {
@private
  NSString* _contentType;
  NSString* _mimeType;
}
@property(nonatomic, readonly) NSString* contentType;  // May be nil
@property(nonatomic, readonly) NSString* mimeType;  // Defaults to "text/plain" per specifications if undefined
@end

@interface GCDWebServerMultiPartArgument : GCDWebServerMultiPart {
@private
  NSData* _data;
  NSString* _string;
}
@property(nonatomic, readonly) NSData* data;
@property(nonatomic, readonly) NSString* string;  // May be nil (only valid for text mime types
@end

@interface GCDWebServerMultiPartFile : GCDWebServerMultiPart {
@private
  NSString* _fileName;
  NSString* _temporaryPath;
}
@property(nonatomic, readonly) NSString* fileName;  // May be nil
@property(nonatomic, readonly) NSString* temporaryPath;
@end

@interface GCDWebServerMultiPartFormRequest : GCDWebServerRequest {
@private
  NSData* _boundary;
  
  NSUInteger _parserState;
  NSMutableData* _parserData;
  NSString* _controlName;
  NSString* _fileName;
  NSString* _contentType;
  NSString* _tmpPath;
  int _tmpFile;
  
  NSMutableDictionary* _arguments;
  NSMutableDictionary* _files;
}
@property(nonatomic, readonly) NSDictionary* arguments;  // Only valid after open / write / close sequence
@property(nonatomic, readonly) NSDictionary* files;  // Only valid after open / write / close sequence
+ (NSString*) mimeType;
@end
