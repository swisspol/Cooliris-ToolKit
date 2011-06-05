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

typedef enum {
  kTaskStatus_Cancelled = -1,
  kTaskStatus_Inactive = 0,
  kTaskStatus_Scheduled = 1,
  kTaskStatus_Executing = 2,
  kTaskStatus_Finished = 3
} TaskStatus;

extern NSString* const TaskQueueDidBecomeBusyNotification;  // Posted on main thread
extern NSString* const TaskQueueDidBecomeIdleNotification;  // Posted on main thread

// Delegate selectors are always called on main thread
// If any dependency becomes invalid, the task will immediately finish and become invalid itself
//  unless "ignoresInvalidDependencies" is YES
@interface Task : NSObject {
@private
  TaskStatus _status;
  BOOL _valid;
  id _delegate;
  SEL _didScheduleSelector;
  SEL _didFinishSelector;
  SEL _didCancelSelector;
  id _userInfo;
  BOOL _ignoresInvalidDependencies;
  NSMutableSet* _dependencies;
}
@property(nonatomic, readonly) TaskStatus status;
@property(nonatomic, readonly, getter=isFinished) BOOL finished;
@property(nonatomic, readonly, getter=isCancelled) BOOL cancelled;
@property(nonatomic, readonly, getter=isValid) BOOL valid;  // Only YES if the task successfully executed
@property(nonatomic, assign) id delegate;
@property(nonatomic) SEL didScheduleSelector;  // -taskDidSchedule:(Task*)task
@property(nonatomic) SEL didFinishSelector;  // -taskDidFinish:(Task*)task
@property(nonatomic) SEL didCancelSelector;  // -taskDidCancel:(Task*)task
@property(nonatomic, retain) id userInfo;
@property(nonatomic) BOOL ignoresInvalidDependencies;  // Default is NO
- (void) addDependency:(Task*)dependency;
- (void) addDependencies:(NSSet*)dependencies;
@end

@interface Task (Subclassing)
- (BOOL) execute;
@end

@interface TaskQueue : NSObject {
@private
  NSLock* _executionLock;
  NSMutableArray* _suspendedTasks;
  NSMutableArray* _pendingTasks;
  NSMutableSet* _executingTasks;
  NSLock* _messageLock;
  NSMutableArray* _messageQueue;
  void* _mainSource;
  CFRunLoopRef _mainRunLoop;
  NSUInteger _maxConcurrency;
  NSUInteger _currentConcurrency;
  void** _queueSources;
  CFRunLoopRef* _queueRunLoops;
  NSConditionLock* _conditionLock;
  NSUInteger _paused;
  BOOL _idle;
}
@property(nonatomic, readonly, getter=isSuspended) BOOL suspended;
@property(nonatomic, readonly, getter=isIdle) BOOL idle;
@property(nonatomic, readonly) NSUInteger numberOfQueuedTasks;
@property(nonatomic, readonly) NSUInteger numberOfExecutingTasks;
+ (void) setDefaultConcurrency:(NSUInteger)concurrency;  // Initial value is 1 - Must be called before any call to +sharedTaskQueue
+ (BOOL) wasCreated;  // Returns YES if +sharedTaskQueue was ever called
+ (TaskQueue*) sharedTaskQueue;
- (void) scheduleTaskForExecution:(Task*)task;  // Normal priority
- (void) scheduleTaskForExecution:(Task*)task highPriority:(BOOL)highPriority;  // Task must be inactive
- (void) scheduleTasksForExecution:(NSSet*)tasks;  // Normal priority
- (void) scheduleTasksForExecution:(NSSet*)tasks highPriority:(BOOL)highPriority;  // Tasks must be inactive
- (void) cancelTaskExecution:(Task*)task;  // Does nothing if task inactive, already executed or cancelled
- (void) cancelTasksExecution:(NSSet*)tasks;  // Does nothing if tasks inactive, already executed or cancelled
- (void) cancelAllTasksExecution;
- (void) performSelectorOnMainThread:(SEL)selector withArgument:(id)argument usingTarget:(id)target;
- (void) suspend;  // Task execution will suspend at next opportunity - Nestable
- (void) resume;
- (void) waitUntilIdle;  // Blocks until the TaskQueue is idle - Use on main thread only
- (void) waitUntilFence:(NSUInteger*)fence;  // Blocks until "fence" becomes zero - Use on main thread only
@end

// Convenience task that manages a group of subtasks as dependencies and schedules / cancels them automatically when the task is cancelled
@interface TaskGroup : Task {
@private
  NSArray* _tasks;
}
@property(nonatomic, readonly) NSArray* tasks;
- (id) initWithTasks:(NSArray*)tasks;
@end

// Convenience task that executes a selector which must take a single id argument and return a non-nil id result on success
@interface TaskAction : Task {
@private
  id _target;
  SEL _selector;
  id _argument;
  id _result;
}
- (id) initWithTarget:(id)target selector:(SEL)selector;  // Argument will be task
- (id) initWithTarget:(id)target selector:(SEL)selector argument:(id)argument;
@property(nonatomic, readonly) id target;
@property(nonatomic, readonly) SEL selector;
@property(nonatomic, readonly) id argument;
@property(nonatomic, readonly) id result;
@end

#if NS_BLOCKS_AVAILABLE

// Convenience task that executes a block which must return a non-nil id result on success
// Instead of a delegate and selectors, a block is called on completion
@interface TaskBlock : Task {
@private
  void* _taskBlock;
  void* _completionBlock;
  id _result;
}
+ (void) scheduleTaskBlock:(id (^)())taskBlock completionBlock:(void (^)(id result))completionBlock highPriority:(BOOL)highPriority;
- (id) initWithTaskBlock:(id (^)())taskBlock completionBlock:(void (^)(id result))completionBlock;
@end

#endif

// Convenience task that performs an HTTP download to memory
@interface TaskHTTPDownload : Task {
@private
  NSMutableURLRequest* _request;
  NSDictionary* _headerFields;
  NSData* _data;
}
@property(nonatomic, readonly) NSURLRequest* request;
@property(nonatomic, readonly) NSDictionary* headerFields;
@property(nonatomic, readonly) NSData* data;
- (id) initWithURL:(NSURL*)url;  // Default user agent is nil and cookies are disabled
- (id) initWithURL:(NSURL*)url userAgent:(NSString*)userAgent handleCookies:(BOOL)handleCookies;
- (id) initWithRequest:(NSURLRequest*)request;
@end
