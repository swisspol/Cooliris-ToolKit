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

@interface DiskCache : NSObject {
@private
  NSString* _path;
}
@property(nonatomic, readonly) NSString* path;
- (id) initWithPath:(NSString*)path;  // Path must exist
- (size_t) purgeToMaximumSize:(size_t)maxSize;  // Returns new size or <0 on error
- (NSString*) cacheFileForHash:(NSString*)hash;
- (NSTimeInterval) getCacheFileAccessTimestamp:(NSString*)file;  // Returns 0.0 on failure
- (NSUInteger) getCacheFileContentsVersion:(NSString*)file;  // Returns 0 on failure
- (BOOL) writeCacheFile:(NSString*)file data:(NSData*)data version:(NSUInteger)version;
- (BOOL) writeCacheFile:(NSString*)file contents:(id<NSCoding>)contents version:(NSUInteger)version;
- (NSData*) readCacheFileData:(NSString*)file version:(NSUInteger*)version;
- (id) readCacheFileContents:(NSString*)file version:(NSUInteger*)version;
@end
