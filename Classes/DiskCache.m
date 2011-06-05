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

#import <dirent.h>
#import <sys/stat.h>
#import <sys/time.h>
#import <sys/xattr.h>
#import <unistd.h>

#import "DiskCache.h"
#import "Crypto.h"
#import "SmartDescription.h"
#import "Logging.h"

#define kVersionExtendedAttributeName "diskcache.version"

typedef struct {
  const char* path;
  double modification;
  size_t size;
} CacheFileInfo;

@implementation DiskCache

@synthesize path=_path;

- (id) initWithPath:(NSString*)path {
  if ((self = [super init])) {
    _path = [path copy];
  }
  return self;
}

- (void) dealloc {
  [_path release];
  
  [super dealloc];
}

static CFComparisonResult _ComparatorFunction(const void* value1, const void* value2, void* context) {
  const CacheFileInfo* info1 = (const CacheFileInfo*)value1;
  const CacheFileInfo* info2 = (const CacheFileInfo*)value2;
  if (info1->modification < info2->modification) {
    return kCFCompareLessThan;
  } else if (info1->modification > info2->modification) {
    return kCFCompareGreaterThan;
  }
  return kCFCompareEqualTo;
}

static void _ArrayReleaseCallBack(CFAllocatorRef allocator, const void* value) {
  const CacheFileInfo* info = (const CacheFileInfo*)value;
  free((void*)info->path);
  free((void*)info);
}

- (size_t) purgeToMaximumSize:(size_t)maxSize {
  const char* path = [_path UTF8String];
  
  // Open cache directory
  DIR* directory;
  if ((directory = opendir(path))) {
    size_t baseLength = strlen(path);
    size_t totalSize = 0;
    CFArrayCallBacks callbacks = {0, NULL, _ArrayReleaseCallBack, NULL, NULL};
    CFMutableArrayRef files = CFArrayCreateMutable(kCFAllocatorDefault, 0, &callbacks);
    
    // Scan cache directory
    struct dirent storage;
    struct dirent* entry;
    while(1) {
      if ((readdir_r(directory, &storage, &entry) != 0) || !entry) {
        break;
      }
      if (entry->d_name[0] == '.') {
        continue;
      }
      
      // Compute absolute file path
      size_t length = entry->d_namlen;
      char* buffer = malloc(baseLength + 1 + length + 1);
      bcopy(path, buffer, baseLength);
      buffer[baseLength] = '/';
      bcopy(entry->d_name, &buffer[baseLength + 1], length + 1);
      
      // Retrieve file information and update total cache size
      struct stat fileInfo;
      if (lstat(buffer, &fileInfo) == 0) {
        if (S_ISREG(fileInfo.st_mode)) {
          CacheFileInfo* cacheInfo = malloc(sizeof(CacheFileInfo));
          cacheInfo->path = buffer;
          cacheInfo->modification = (double)fileInfo.st_mtimespec.tv_sec + (double)fileInfo.st_mtimespec.tv_nsec / 1000000000.0
                                    - kCFAbsoluteTimeIntervalSince1970;
          cacheInfo->size = fileInfo.st_size;
          CFArrayAppendValue(files, cacheInfo);
          
          totalSize += fileInfo.st_size;
        } else {
          free(buffer);
        }
      } else {
        LOG_ERROR(@"Failed getting info for \"%s\" (%s)", buffer, strerror(errno));
        free(buffer);
      }
    }
    
    // If total size is above threshold, sort files by least recently used and delete the oldest ones as needed
    if (totalSize > maxSize) {
      LOG_INFO(@"%@ is %i Kb over limit and requires purging", self, (totalSize - maxSize) / 1024);
      CFIndex count = CFArrayGetCount(files);
      CFArraySortValues(files, CFRangeMake(0, count), _ComparatorFunction, NULL);
      for (CFIndex index = 0; index < count; ++index) {
        const CacheFileInfo* cacheInfo = (const CacheFileInfo*)CFArrayGetValueAtIndex(files, index);
        if (unlink(cacheInfo->path) == 0) {
          totalSize -= cacheInfo->size;
          if (totalSize <= maxSize) {
            break;
          }
        }
      }
    }
    
    CFRelease(files);
    closedir(directory);
    return totalSize;
  } else {
    LOG_ERROR(@"Failed reading cache directory (%s)", strerror(errno));
  }
  
  return -1;
}

- (NSString*) cacheFileForHash:(NSString*)hash {
  unichar buffer[hash.length];
  [hash getCharacters:buffer];
  MD5 md5 = MD5WithBytes(buffer, sizeof(buffer));
  return MD5ToString(&md5);
}

- (NSTimeInterval) getCacheFileAccessTimestamp:(NSString*)file {
  const char* utf8Path = [[_path stringByAppendingPathComponent:file] UTF8String];
  if (utf8Path) {
    struct stat fileInfo;
    if ((lstat(utf8Path, &fileInfo) == 0) && (S_ISREG(fileInfo.st_mode))) {  // Retrieve file modification date
      CFAbsoluteTime time = (CFAbsoluteTime)fileInfo.st_ctimespec.tv_sec +
                            (CFAbsoluteTime)fileInfo.st_ctimespec.tv_nsec / 1000000000.0;
      return time - kCFAbsoluteTimeIntervalSince1970;
    }
    if (errno != ENOENT) {
      LOG_ERROR(@"Failed retrieving access timestamp for \"%@\" (%s)", file, strerror(errno));
    }
  }
  return 0.0;
}

- (NSUInteger) getCacheFileContentsVersion:(NSString*)file {
  const char* utf8Path = [[_path stringByAppendingPathComponent:file] UTF8String];
  if (utf8Path) {
    NSUInteger version;
    ssize_t result = getxattr(utf8Path, kVersionExtendedAttributeName, &version, sizeof(NSUInteger), 0, XATTR_NOFOLLOW);
    if (result == sizeof(NSUInteger)) {
      return version;
    }
    if (errno != ENOENT) {
      LOG_ERROR(@"Failed retrieving version for \"%@\" (%s)", file, strerror(errno));
    }
  }
  return 0;
}

- (BOOL) _writeCacheFile:(NSString*)file contents:(id)contents version:(NSUInteger)version useArchiver:(BOOL)useArchiver {
  NSString* path = [_path stringByAppendingPathComponent:file];
  BOOL result;
  @try {
    if (useArchiver) {
      result = [NSKeyedArchiver archiveRootObject:contents toFile:path];
    } else {
      result = [(NSData*)contents writeToFile:path atomically:YES];
    }
  }
  @catch (NSException* exception) {
    LOG_EXCEPTION(exception);
    result = NO;
  }
  if (result) {
    const char* utf8Path = [path UTF8String];
    if (setxattr(utf8Path, kVersionExtendedAttributeName, &version, sizeof(NSUInteger), 0, XATTR_NOFOLLOW)) {
      LOG_ERROR(@"Failed setting version for \"%@\" (%s)", file, strerror(errno));
      result = NO;  // TODO: Delete the cache file
    }
  } else {
    LOG_ERROR(@"Failed writing \"%@\"", file);
  }
  return result;
}

- (BOOL) writeCacheFile:(NSString*)file data:(NSData*)data version:(NSUInteger)version {
  return [self _writeCacheFile:file contents:data version:version useArchiver:NO];
}

- (BOOL) writeCacheFile:(NSString*)file contents:(id<NSCoding>)contents version:(NSUInteger)version {
  return [self _writeCacheFile:file contents:contents version:version useArchiver:YES];
}

- (id) _readCacheFileContents:(NSString*)file version:(NSUInteger*)version useArchiver:(BOOL)useArchiver {
  NSString* path = [_path stringByAppendingPathComponent:file];
  id contents = nil;
  struct stat fileInfo;
  const char* utf8Path = [path UTF8String];
  if (utf8Path && (lstat(utf8Path, &fileInfo) == 0) && (S_ISREG(fileInfo.st_mode))) {
    @try {
      if (useArchiver) {
        contents = [NSKeyedUnarchiver unarchiveObjectWithFile:path];
      } else {
        contents = [NSData dataWithContentsOfFile:path];
      }
    }
    @catch (NSException* exception) {
      LOG_EXCEPTION(exception);
      contents = nil;
    }
    if (contents) {
      if (version) {
        ssize_t result = getxattr(utf8Path, kVersionExtendedAttributeName, version, sizeof(NSUInteger), 0, XATTR_NOFOLLOW);
        if (result != sizeof(NSUInteger)) {
          LOG_ERROR(@"Failed retrieving version for \"%s\" (%s)", utf8Path, strerror(errno));
          return nil;
        }
      }
      if (utimes(utf8Path, NULL)) {  // Update file modification date to mark it recently used
        LOG_ERROR(@"Failed touching \"%@\" (%s)", file, strerror(errno));
      }
    } else {
      LOG_ERROR(@"Failed reading \"%@\"", file);
    }
  }
  return contents;
}

- (NSData*) readCacheFileData:(NSString*)file version:(NSUInteger*)version {
  return [self _readCacheFileContents:file version:version useArchiver:NO];
}

- (id) readCacheFileContents:(NSString*)file version:(NSUInteger*)version {
  return [self _readCacheFileContents:file version:version useArchiver:YES];
}

- (NSString*) description {
  return [self smartDescription];
}

@end
