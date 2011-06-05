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

#import "RemoteUpdater.h"
#import "HTTPURLConnection.h"
#import "MiniZip.h"
#import "Extensions_Foundation.h"
#import "Logging.h"

#define __FORCE_SYNCHRONIZE__ 1

#define kUserDefaultKey @"__RemoteUpdater__"
#define kExtendedAttributeName @"remoteUpdaterVersion"

@interface RemoteUpdaterTask ()
@property(nonatomic, retain) RemoteUpdater* updater;
@end

@interface VersionedUpdaterTask : RemoteUpdaterTask {
@private
  NSURL* _url;
  BOOL _forceUpdate;
  
  // All these objects are on not retained, but just put on the autorelease pool during -execute
  NSString* _cachesPath;
  NSString* _archivePath;
  NSString* _remoteVersion;
  NSInteger _contentLength;
}
- (id) initWithRemoteItem:(NSString*)name url:(NSURL*)url forceUpdate:(BOOL)forceUpdate;
@end

@implementation VersionedUpdaterTask

- (id) initWithRemoteItem:(NSString*)name url:(NSURL*)url forceUpdate:(BOOL)forceUpdate {
  if ((self = [super initWithRemoteItem:name])) {
    _url = [url retain];
    _forceUpdate = forceUpdate;
  }
  return self;
}

- (void) dealloc {
  [_url release];
  
  [super dealloc];
}

- (BOOL) prepare:(NSString*)localPath {
  // Generate paths
  _cachesPath = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject];
  _archivePath = [_cachesPath stringByAppendingPathComponent:self.remoteItem];
  
  // Get remote version
  _remoteVersion = [self.updater getItem:self.remoteItem remoteVersionForURL:_url];
  if (_remoteVersion == nil) {
    LOG_ERROR(@"Remote item \"%@\" at \"%@\" has no valid version", self.remoteItem, [_url absoluteString]);
    return NO;
  }
  LOG_VERBOSE(@"Remote item \"%@\" at \"%@\" has version '%@'", self.remoteItem, [_url absoluteString], _remoteVersion);
  
  // Retrieve local version and check if an update is needed
  if ([[NSFileManager defaultManager] fileExistsAtPath:localPath]) {
    NSString* localVersion = _forceUpdate ? nil : [[NSFileManager defaultManager] extendedAttributeStringWithName:kExtendedAttributeName
                                                                                                    forFileAtPath:localPath];
    if (localVersion && ![self.updater shouldUpdateItem:self.remoteItem localVersion:localVersion remoteVersion:_remoteVersion]) {
      LOG_VERBOSE(@"Item \"%@\" is locally up-to-date at version '%@'", self.remoteItem, localVersion);
      return NO;
    } else {
      if (!(self.updater.synchronizationFlags & kRemoteUpdaterSynchronizationFlag_Update)) {
        return NO;
      }
      if (_forceUpdate) {
        LOG_VERBOSE(@"Force updating item \"%@\"", self.remoteItem);
      } else {
        LOG_VERBOSE(@"Item \"%@\" is locally out-of-date at version '%@'", self.remoteItem, localVersion);
      }
    }
  } else {
    if (!(self.updater.synchronizationFlags & kRemoteUpdaterSynchronizationFlag_Add)) {
      return NO;
    }
    LOG_VERBOSE(@"Item \"%@\" does not exist locally", self.remoteItem);
  }
  
  // Check for cancellation
  if (self.cancelled) {
    return NO;
  }
  
  // Download headers for URL and make sure they are valid
  NSDictionary* headers = [HTTPURLConnection downloadHeaderFieldsFromHTTPURL:_url userAgent:nil handleCookies:NO delegate:(id)self];
  if (headers == nil) {
    return NO;
  }
  _contentLength = [[headers objectForKey:@"Content-Length"] integerValue];
  if (_contentLength <= 0) {
    LOG_ERROR(@"Invalid \"Content-Length\" header for item archive at \"%@\"", [_url absoluteString]);
    return NO;
  }
  BOOL supportsRanges = [[headers objectForKey:@"Accept-Ranges"] isEqualToString:@"bytes"];
  if (!supportsRanges) {
    LOG_WARNING(@"Server \"%@\" does not seem to accept range requests", [_url host]);
  }
  
  // Check for cancellation
  if (self.cancelled) {
    return NO;
  }
  
  // Check if there's already a partially downloaded item and if its version is still valid
  if ([[NSFileManager defaultManager] fileExistsAtPath:_archivePath]) {
    NSString* itemVersion = [[NSFileManager defaultManager] extendedAttributeStringWithName:kExtendedAttributeName
                                                                              forFileAtPath:_archivePath];
    if (!supportsRanges || ![itemVersion isEqualToString:_remoteVersion]) {
      if (![[NSFileManager defaultManager] removeItemAtPath:_archivePath error:NULL]) {
        LOG_ERROR(@"Failed deleting partial archive for item \"%@\"", self.remoteItem);
        return NO;
      }
    } else {
      LOG_INFO(@"Resuming archive download for item \"%@\"", self.remoteItem);
    }
  }
  
  return YES;
}

- (NSString*) download {
  // Download item
  if (![HTTPURLConnection downloadContentsFromHTTPURL:_url
                                         toFileAtPath:_archivePath
                                               resume:YES
                                            userAgent:nil
                                        handleCookies:NO
                                             delegate:(id)self
                                         headerFields:NULL]) {
    if ([[NSFileManager defaultManager] setExtendedAttributeString:_remoteVersion
                                                          withName:kExtendedAttributeName
                                                     forFileAtPath:_archivePath]) {
      LOG_INFO(@"Archive download interrupted for item \"%@\"", self.remoteItem);
    }
    return nil;
  }
  
  // Check archive size - TODO: Should we do a checksum?
  if ([[[NSFileManager defaultManager] attributesOfItemAtPath:_archivePath error:NULL] fileSize] != _contentLength) {
    LOG_ERROR(@"Unexpected archive size for item \"%@\"", self.remoteItem);
    [[NSFileManager defaultManager] removeItemAtPath:_archivePath error:NULL];
    return nil;
  }
  
  return @"";
}

- (NSString*) process {
  // Extract archive
  NSString* tempPath = [_cachesPath stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
  BOOL success = [[NSFileManager defaultManager] createDirectoryAtPath:tempPath
                                           withIntermediateDirectories:NO
                                                            attributes:nil
                                                                 error:NULL];
  if (success) {
    success = [MiniZip extractZipArchiveAtPath:_archivePath toPath:tempPath];
  }
  [[NSFileManager defaultManager] removeItemAtPath:_archivePath error:NULL];
  if (!success) {
    LOG_ERROR(@"Failed extracting archive for item \"%@\"", self.remoteItem);
    return nil;
  }
  
  // Check for cancellation
  if (self.cancelled) {
    return nil;
  }
  
  // Process package
  success = [self.updater processDownloadedItem:self.remoteItem atTemporaryPath:tempPath];
  if (!success) {
    LOG_ERROR(@"Failed processing item \"%@\"", self.remoteItem);
    [[NSFileManager defaultManager] removeItemAtPath:tempPath error:NULL];
    return nil;
  }
  
  // Item is ready for installation
  [[NSFileManager defaultManager] setExtendedAttributeString:_remoteVersion
                                                    withName:kExtendedAttributeName
                                               forFileAtPath:tempPath];
  
  return tempPath;
}

@end

@implementation RemoteUpdater

@synthesize localDirectory=_localDirectory, synchronizationFlags=_synchronizationFlags, delegate=_delegate;

- (id) init {
  return [self initWithLocalDirectory:nil synchronizationFlags:0];
}

- (id) initWithLocalDirectory:(NSString*)path synchronizationFlags:(NSUInteger)flags {
  if (![[NSFileManager defaultManager] fileExistsAtPath:path] || !flags) {
    [self release];
    return nil;
  }
  if ((self = [super init])) {
    _localDirectory = [path copy];
    _synchronizationFlags = flags;
  }
  return self;
}

- (void) dealloc {
  CHECK(_updatingTask == nil);
  
  [_localDirectory release];
  
  [super dealloc];
}

- (BOOL) isUpdating {
  return _updatingTask ? YES : NO;
}

- (BOOL) areUpdatesPending {
  return [[NSUserDefaults standardUserDefaults] objectForKey:kUserDefaultKey] ? YES : NO;
}

- (void) _didFinishUpdating:(TaskAction*)task {
  BOOL cancelled = _updatingTask.userInfo ? NO : YES;
  
  if (!cancelled && (_synchronizationFlags & kRemoteUpdaterSynchronizationFlag_Remove)) {
    NSMutableDictionary* dictionary = [[NSMutableDictionary alloc] initWithDictionary:
      [[NSUserDefaults standardUserDefaults] objectForKey:kUserDefaultKey]];
    for (NSString* name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:_localDirectory error:NULL]) {
      if (![name hasPrefix:@"."] && ![(NSSet*)_updatingTask.userInfo containsObject:name]) {
        [dictionary setObject:@"" forKey:name];
        LOG_VERBOSE(@"Item \"%@\" is pending removal", name);
      }
    }
    if (dictionary.count) {
      [[NSUserDefaults standardUserDefaults] setObject:dictionary forKey:kUserDefaultKey];
#if __FORCE_SYNCHRONIZE__
      [[NSUserDefaults standardUserDefaults] synchronize];
#endif
    }
    [dictionary release];
  }
  
  [_updatingTask release];
  _updatingTask = nil;
  
  if (cancelled) {
    if ([_delegate respondsToSelector:@selector(remoteUpdaterDidCancel:)]) {
      [_delegate remoteUpdaterDidCancel:self];
    }
  } else {
    if ([_delegate respondsToSelector:@selector(remoteUpdaterDidFinish:)]) {
      [_delegate remoteUpdaterDidFinish:self];
    }
  }
  
  LOG_VERBOSE(@"Item updating completed in %.1f seconds", CFAbsoluteTimeGetCurrent() - _startTime);
}

- (void) startUpdatingWithRemoteItems:(NSDictionary*)items {
  [self startUpdatingWithRemoteItems:items forceUpdate:NO extraUpdaters:nil];
}

- (void) startUpdatingWithRemoteItems:(NSDictionary*)items forceUpdate:(BOOL)forceUpdate {
  [self startUpdatingWithRemoteItems:items forceUpdate:forceUpdate extraUpdaters:nil];
}

// Called from TaskQueue thread
- (id) _updateTask:(id)argument {
  return [NSNull null];
}

// Use a sequence of dependent tasks instead of a task group to ensure updaters don't run concurrently
- (void) _startUpdating:(NSArray*)updaters {
  NSDictionary* updates = [[NSUserDefaults standardUserDefaults] objectForKey:kUserDefaultKey];
  NSMutableSet* set = [[NSMutableSet alloc] init];
  NSMutableSet* items = [[NSMutableSet alloc] init];
  Task* dependentTask = nil;
  for (RemoteUpdaterTask* updater in updaters) {
    DCHECK([updater isKindOfClass:[RemoteUpdaterTask class]]);
    NSString* item = updater.remoteItem;
    if (![updates objectForKey:item]) {
      updater.updater = self;
      [set addObject:updater];
      if (dependentTask) {
        updater.ignoresInvalidDependencies = YES;
        [updater addDependency:dependentTask];
      }
      dependentTask = updater;
    } else {
      LOG_VERBOSE(@"Item \"%@\" is already pending installation", item);
    }
    [items addObject:item];
  }
  _updatingTask = [[TaskAction alloc] initWithTarget:self selector:@selector(_updateTask:) argument:set];
  if (dependentTask) {
    _updatingTask.ignoresInvalidDependencies = YES;
    [_updatingTask addDependency:dependentTask];
  }
  _updatingTask.delegate = self;
  _updatingTask.didFinishSelector = @selector(_didFinishUpdating:);
  _updatingTask.userInfo = items;
  [[TaskQueue sharedTaskQueue] scheduleTasksForExecution:_updatingTask.argument];
  [[TaskQueue sharedTaskQueue] scheduleTaskForExecution:_updatingTask];
  [items release];
  [set release];
  LOG_VERBOSE(@"Item updating started");
  _startTime = CFAbsoluteTimeGetCurrent();
}

- (void) startUpdatingWithRemoteItems:(NSDictionary*)items forceUpdate:(BOOL)forceUpdate extraUpdaters:(NSArray*)updaters {
  CHECK(_updatingTask == nil);
  NSMutableArray* array = [[NSMutableArray alloc] initWithArray:updaters];
  for (NSString* name in [[items allKeys] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)]) {
    VersionedUpdaterTask* updater = [[VersionedUpdaterTask alloc] initWithRemoteItem:name
                                                                                 url:[items objectForKey:name]
                                                                         forceUpdate:forceUpdate];
    [array addObject:updater];
    [updater release];
  }
  [self _startUpdating:array];
  [array release];
}

- (void) cancelUpdating {
  if (_updatingTask.userInfo) {
    [[TaskQueue sharedTaskQueue] cancelTasksExecution:_updatingTask.argument];  // Only cancel the dependent tasks so that the main one still runs
    _updatingTask.userInfo = nil;
  }
}

- (BOOL) installPendingUpdates {
  CHECK(_updatingTask == nil);
  BOOL success = YES;
  NSDictionary* updates = [[NSUserDefaults standardUserDefaults] objectForKey:kUserDefaultKey];
  for (NSString* name in updates) {
    NSString* fromPath = [updates objectForKey:name];
    NSString* toPath = [_localDirectory stringByAppendingPathComponent:name];
    if (fromPath.length) {
      if ([[NSFileManager defaultManager] fileExistsAtPath:fromPath]) {
        if (![[NSFileManager defaultManager] removeItemAtPathIfExists:toPath] ||
          ![[NSFileManager defaultManager] moveItemAtPath:fromPath toPath:toPath error:NULL]) {
          LOG_ERROR(@"Failed installing item \"%@\"", name);
        } else {
          LOG_INFO(@"Item \"%@\" has been installed", name);
        }
      }
    } else {
      if (![[NSFileManager defaultManager] removeItemAtPath:toPath error:NULL]) {
        LOG_ERROR(@"Failed removing item \"%@\"", name);
      } else {
        LOG_INFO(@"Item \"%@\" has been removed", name);
      }
    }
  }
  [[NSUserDefaults standardUserDefaults] removeObjectForKey:kUserDefaultKey];
#if __FORCE_SYNCHRONIZE__
  [[NSUserDefaults standardUserDefaults] synchronize];
#endif
  return success;
}

- (void) clearPendingUpdates {
  CHECK(_updatingTask == nil);
  NSDictionary* updates = [[NSUserDefaults standardUserDefaults] objectForKey:kUserDefaultKey];
  for (NSString* name in updates) {
    [[NSFileManager defaultManager] removeItemAtPath:[updates objectForKey:name] error:NULL];
  }
  [[NSUserDefaults standardUserDefaults] removeObjectForKey:kUserDefaultKey];
#if __FORCE_SYNCHRONIZE__
  [[NSUserDefaults standardUserDefaults] synchronize];
#endif
}

- (NSString*) localPathForItem:(NSString*)name {
  return [_localDirectory stringByAppendingPathComponent:name];
}

@end

@implementation RemoteUpdater (Subclassing)

- (NSString*) getItem:(NSString*)name remoteVersionForURL:(NSURL*)url {
  NSDictionary* headers = [HTTPURLConnection downloadHeaderFieldsFromHTTPURL:url userAgent:nil handleCookies:NO delegate:nil];
  return [headers objectForKey:@"Last-Modified"];
}

- (BOOL) shouldUpdateItem:(NSString*)name localVersion:(NSString*)localVersion remoteVersion:(NSString*)remoteVersion {
  if (localVersion && remoteVersion) {
    NSDate* localDate = [NSDate dateWithString:localVersion
                                  cachedFormat:@"EEE', 'd' 'MMM' 'yyyy' 'HH:mm:ss' 'z"
                               localIdentifier:@"en_US"];
    NSDate* remoteDate = [NSDate dateWithString:remoteVersion
                                   cachedFormat:@"EEE', 'd' 'MMM' 'yyyy' 'HH:mm:ss' 'z"
                                localIdentifier:@"en_US"];
    if (localDate && remoteDate) {
      return ([remoteDate compare:localDate] == NSOrderedDescending);
    } else {
      LOG_WARNING(@"Failed comparing \"Last-Modified\" header fields:\n%@\n%@", localDate, remoteDate);
    }
  }
  return NO;
}

- (BOOL) processDownloadedItem:(NSString*)name atTemporaryPath:(NSString*)path {
  return YES;
}

@end

@implementation RemoteUpdaterTask

@synthesize remoteItem=_item, updater=_updater;

- (id) initWithRemoteItem:(NSString*)name {
  CHECK(name);
  if ((self = [super init])) {
    _item = [name copy];
  }
  return self;
}

- (void) dealloc {
  [_item release];
  [_updater release];
  
  [super dealloc];
}

- (BOOL) prepare:(NSString*)localPath {
  [self doesNotRecognizeSelector:_cmd];
  return NO;
}

- (NSString*) download {
  [self doesNotRecognizeSelector:_cmd];
  return nil;
}

- (NSString*) process {
  [self doesNotRecognizeSelector:_cmd];
  return nil;
}

- (void) _didSkipUpdating:(id)argument {
  [_updater.delegate remoteUpdater:_updater didSkipUpdatingRemoteItem:_item];
}

- (void) _didStartDownloading:(id)argument {
  [_updater.delegate remoteUpdater:_updater didStartDownloadingRemoteItem:_item];
}

- (void) _didStartProcessing:(id)argument {
  [_updater.delegate remoteUpdater:_updater didStartProcessingRemoteItem:_item];
}

- (void) _didFinishUpdating:(id)argument {
  [_updater.delegate remoteUpdater:_updater didFinishUpdatingRemoteItem:_item];
}

- (void) _didFailUpdating:(id)argument {
  [_updater.delegate remoteUpdater:_updater didFailUpdatingRemoteItem:_item];
}

- (BOOL) execute {
  NSString* result = nil;
  
  // Prepare
  NSString* localPath = [_updater localPathForItem:_item];
  BOOL success = [self prepare:localPath];
  if (self.cancelled) {
    return NO;
  }
  
  // Check if skipping update and notify delegate
  if (success == NO) {
    if ([_updater.delegate respondsToSelector:@selector(remoteUpdater:didSkipUpdatingRemoteItem:)]) {
      [[TaskQueue sharedTaskQueue] performSelectorOnMainThread:@selector(_didSkipUpdating:) withArgument:nil usingTarget:self];
    }
    return NO;
  }
  
  // Notify delegate
  if ([_updater.delegate respondsToSelector:@selector(remoteUpdater:didStartDownloadingRemoteItem:)]) {
    [[TaskQueue sharedTaskQueue] performSelectorOnMainThread:@selector(_didStartDownloading:) withArgument:nil usingTarget:self];
  }
  
  // Download
  result = [self download];
  if (result == nil) {
    goto End;
  }
  if (self.cancelled) {
    return NO;
  }
  
  // Notify delegate if necessary
  if (!result.length && [_updater.delegate respondsToSelector:@selector(remoteUpdater:didStartProcessingRemoteItem:)]) {
    [[TaskQueue sharedTaskQueue] performSelectorOnMainThread:@selector(_didStartProcessing:) withArgument:nil usingTarget:self];
  }
  
  // Process if necessary
  if (!result.length) {
    result = [self process];
    if (result == nil) {
      goto End;
    }
    if (self.cancelled) {
      return NO;
    }
  }
  
  // Install result if needed - There should be no race-conditions relative to NSUserDefaults as updaters are not concurrent
  if (![result isEqualToString:localPath]) {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary* dictionary = [[NSMutableDictionary alloc] initWithDictionary:[defaults objectForKey:kUserDefaultKey]];
    [dictionary setObject:result forKey:_item];
    [defaults setObject:dictionary forKey:kUserDefaultKey];
#if __FORCE_SYNCHRONIZE__
    [defaults synchronize];
#endif
    [dictionary release];
    LOG_VERBOSE(@"Item \"%@\" is pending installation", _item);
  }
  
End:
  // Notify delegate
  if (result && [_updater.delegate respondsToSelector:@selector(remoteUpdater:didFinishUpdatingRemoteItem:)]) {
    [[TaskQueue sharedTaskQueue] performSelectorOnMainThread:@selector(_didFinishUpdating:) withArgument:nil usingTarget:self];
  } else if (!result && [_updater.delegate respondsToSelector:@selector(remoteUpdater:didFailUpdatingRemoteItem:)]) {
    [[TaskQueue sharedTaskQueue] performSelectorOnMainThread:@selector(_didFailUpdating:) withArgument:nil usingTarget:self];
  }
  
  return result ? YES : NO;
}

@end
