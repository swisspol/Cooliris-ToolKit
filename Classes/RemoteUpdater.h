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

#import "Task.h"

enum {
  kRemoteUpdaterSynchronizationFlag_Add = (1 << 0),
  kRemoteUpdaterSynchronizationFlag_Update = (1 << 1),
  kRemoteUpdaterSynchronizationFlag_Remove = (1 << 2)
};

@class RemoteUpdater;

@protocol RemoteUpdaterDelegate <NSObject>
@optional
- (void) remoteUpdaterDidFinish:(RemoteUpdater*)updater;
- (void) remoteUpdaterDidCancel:(RemoteUpdater*)updater;
- (void) remoteUpdater:(RemoteUpdater*)updater didStartDownloadingRemoteItem:(NSString*)name;
- (void) remoteUpdater:(RemoteUpdater*)updater didStartProcessingRemoteItem:(NSString*)name;
- (void) remoteUpdater:(RemoteUpdater*)updater didFinishUpdatingRemoteItem:(NSString*)name;
- (void) remoteUpdater:(RemoteUpdater*)updater didFailUpdatingRemoteItem:(NSString*)name;
- (void) remoteUpdater:(RemoteUpdater*)updater didSkipUpdatingRemoteItem:(NSString*)name;
@end

// Remote items are assumed to be ZIP archives
@interface RemoteUpdater : NSObject {
@private
  NSString* _localDirectory;
  NSUInteger _synchronizationFlags;
  id<RemoteUpdaterDelegate> _delegate;
  
  TaskAction* _updatingTask;
  CFAbsoluteTime _startTime;
}
@property(nonatomic, readonly) NSString* localDirectory;
@property(nonatomic, readonly) NSUInteger synchronizationFlags;
@property(nonatomic, assign) id<RemoteUpdaterDelegate> delegate;
@property(nonatomic, readonly, getter=isUpdating) BOOL updating;
@property(nonatomic, readonly, getter=areUpdatesPending) BOOL updatesPending;
- (id) initWithLocalDirectory:(NSString*)path synchronizationFlags:(NSUInteger)flags;
- (void) startUpdatingWithRemoteItems:(NSDictionary*)items;  // Dictionary contains item names and URLs
- (void) startUpdatingWithRemoteItems:(NSDictionary*)items forceUpdate:(BOOL)forceUpdate;
- (void) startUpdatingWithRemoteItems:(NSDictionary*)items forceUpdate:(BOOL)forceUpdate extraUpdaters:(NSArray*)updaters;
- (void) cancelUpdating;
- (BOOL) installPendingUpdates;  // Not allowed while updating - Does nothing if no updates are available
- (void) clearPendingUpdates;
- (NSString*) localPathForItem:(NSString*)name;
@end

// Only used by built-in updaters
@interface RemoteUpdater (Subclassing)
- (NSString*) getItem:(NSString*)name remoteVersionForURL:(NSURL*)url;  // Default implementation retrieves "Last-Modified:" header - Called from updating thread
- (BOOL) shouldUpdateItem:(NSString*)name localVersion:(NSString*)localVersion remoteVersion:(NSString*)remoteVersion;  // Default implementation returns YES if remote "Last-Modified:" is more recent - Called from updating thread
- (BOOL) processDownloadedItem:(NSString*)name atTemporaryPath:(NSString*)path;  // Default implementation does nothing - Called from updating thread
@end

// When subclassing, override the specific methods instead of -execute
// Subclasses can either do in-place updating or atomic replace
@interface RemoteUpdaterTask : Task {
@private
  NSString* _item;
  RemoteUpdater* _updater;
}
@property(nonatomic, readonly) NSString* remoteItem;
- (id) initWithRemoteItem:(NSString*)name;
- (BOOL) prepare:(NSString*)localPath;  // Implementation required - Local path may not exist - Return NO on error or if there is nothing to update
- (NSString*) download;  // Implementation required - Return path to install (may be local path) or empty string to indicate continue to processing or nil on failure
- (NSString*) process;  // Implementation required - Return path to install (may be local path) or nil on failure
@end
