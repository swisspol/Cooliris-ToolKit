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
#import "HTTPURLConnection.h"
#import "SmartDescription.h"
#import "Logging.h"

#define kThreadRunLoopInterval 60.0
#define kTaskMainRunLoopMode CFSTR("TaskMainRunLoopMode")
#define kTaskMainRunLoopInterval 0.5

@interface TaskMessage : NSObject {
@private
  id _target;
  SEL _selector;
  id _argument;
}
- (id) initWithTarget:(id)target selector:(SEL)selector argument:(id)argument;
- (void) perform;
@end

@interface Task ()
@property(nonatomic) TaskStatus status;
@property(nonatomic, getter=isValid) BOOL valid;
@property(nonatomic, retain) NSMutableSet* dependencies;
- (void) _scheduleForExecutionInQueue:(TaskQueue*)queue atBeginning:(BOOL)atBeginning;
- (void) _cancelExecutionFromQueue:(TaskQueue*)queue;
@end

@interface TaskQueue ()
@property(nonatomic, readonly) NSMutableArray* suspendedTasks;
@property(nonatomic, readonly) NSMutableArray* pendingTasks;
@property(nonatomic, readonly) NSMutableSet* executingTasks;
@property(nonatomic, readonly) NSUInteger paused;
- (id) initWithConcurrency:(NSUInteger)concurrency;
- (void) _performSelector:(SEL)aSelector target:(id)target argument:(id)argument;
- (void) _addDependencies:(id)dependencies toTask:(Task*)task;  // NSArray or NSSet
@end

NSString* const TaskQueueDidBecomeBusyNotification = @"TaskQueueDidBecomeBusyNotification";
NSString* const TaskQueueDidBecomeIdleNotification = @"TaskQueueDidBecomeIdleNotification";

static TaskQueue* _sharedQueue = nil;
static NSUInteger _defaultConcurrency = 1;

@implementation TaskMessage

- (id) initWithTarget:(id)target selector:(SEL)selector argument:(id)argument {
  if ((self = [super init])) {
    _target = [target retain];
    _selector = selector;
    _argument = [argument retain];
  }
  return self;
}

- (void) dealloc {
  [_argument release];
  [_target release];
  
  [super dealloc];
}

- (void) perform {
  @try {
    [_target performSelector:_selector withObject:_argument];
  }
  @catch (NSException* exception) {
    LOG_EXCEPTION(exception);
  }
}

@end

@implementation Task

@synthesize status=_status, valid=_valid, delegate=_delegate, didScheduleSelector=_didScheduleSelector,
            didFinishSelector=_didFinishSelector, didCancelSelector=_didCancelSelector, userInfo=_userInfo,
            ignoresInvalidDependencies=_ignoresInvalidDependencies, dependencies=_dependencies;

- (id) init {
  if ((self = [super init])) {
    _status = kTaskStatus_Inactive;
  }
  return self;
}

- (void) dealloc {
  CHECK((_status != kTaskStatus_Scheduled) && (_status != kTaskStatus_Executing));
  [_userInfo release];
  [_dependencies release];
  
  [super dealloc];
}

- (BOOL) isFinished {
  return _status == kTaskStatus_Finished;
}

- (BOOL) isCancelled {
  return _status == kTaskStatus_Cancelled;
}

- (void) addDependency:(Task*)dependency {
  NSSet* set = [[NSSet alloc] initWithObjects:&dependency count:1];
  [[TaskQueue sharedTaskQueue] _addDependencies:set toTask:self];
  [set release];
}

- (void) addDependencies:(NSSet*)dependencies {
  [[TaskQueue sharedTaskQueue] _addDependencies:dependencies toTask:self];
}

// Requires execution lock to be taken
- (void) _scheduleForExecutionInQueue:(TaskQueue*)queue atBeginning:(BOOL)atBeginning {
  CHECK(_status == kTaskStatus_Inactive);
  _status = kTaskStatus_Scheduled;
  if (queue.paused > 0) {
    if (atBeginning) {
      [queue.suspendedTasks insertObject:self atIndex:0];
    } else {
      [queue.suspendedTasks addObject:self];
    }
  } else {
    if (atBeginning) {
      [queue.pendingTasks insertObject:self atIndex:0];
    } else {
      [queue.pendingTasks addObject:self];
    }
  }
  
  if (_delegate && _didScheduleSelector) {
    [queue _performSelector:_didScheduleSelector target:_delegate argument:self];
  }
}

// Requires execution lock to be taken
- (void) _cancelExecutionFromQueue:(TaskQueue*)queue {
  CHECK(_status != kTaskStatus_Inactive);
  if (_status == kTaskStatus_Scheduled) {
    [self retain];  // Removing from task list may consume the last reference to "self" therefore the extra retain in this scope
    
    _status = kTaskStatus_Cancelled;
    [_dependencies release];
    _dependencies = nil;
    [queue.suspendedTasks removeObject:self];
    [queue.pendingTasks removeObject:self];
    
    if (_delegate && _didCancelSelector) {
      [queue _performSelector:_didCancelSelector target:_delegate argument:self];
    }
    
    [self release];
  } else if (_status == kTaskStatus_Executing) {
    _status = kTaskStatus_Cancelled;  // The task delegate will be notified later from the task queue
  }
}

- (NSString*) description {
  return [self smartDescription];
}

@end

@implementation Task (Subclassing)

- (BOOL) execute {
  [self doesNotRecognizeSelector:_cmd];
  return NO;
}

@end

@implementation TaskQueue

@synthesize suspendedTasks=_suspendedTasks, pendingTasks=_pendingTasks, executingTasks=_executingTasks, paused=_paused, idle=_idle;

+ (void) setDefaultConcurrency:(NSUInteger)concurrency {
  _defaultConcurrency = MAX(concurrency, 1);
}

+ (BOOL) wasCreated {
  return _sharedQueue ? YES : NO;
}

+ (TaskQueue*) sharedTaskQueue {
  if (_sharedQueue == nil) {
    _sharedQueue = [[TaskQueue alloc] initWithConcurrency:_defaultConcurrency];
  }
  return _sharedQueue;
}

- (void) _performMessages {
  [_messageLock lock];
  NSArray* array = [NSArray arrayWithArray:_messageQueue];  // Unqueue all the messages at once to avoid taking the lock too long
  [_messageQueue removeAllObjects];
  [_messageLock unlock];
  
  for (TaskMessage* message in array) {
    [message perform];
  }
}

static void __MainSourceCallBack(void* info) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  [(TaskQueue*)info _performMessages];
  [pool release];
}

- (void) _queueDidBecomeBusy:(id)argument {
  _idle = NO;
  [[NSNotificationCenter defaultCenter] postNotificationName:TaskQueueDidBecomeBusyNotification object:self];
}

- (void) _queueDidBecomeIdle:(id)argument {
  _idle = YES;
  [[NSNotificationCenter defaultCenter] postNotificationName:TaskQueueDidBecomeIdleNotification object:self];
}

// Called from queue thread
- (void) _executeTasks {
  [_executionLock lock];
  if (_currentConcurrency == 0) {
    [self _performSelector:@selector(_queueDidBecomeBusy:) target:self argument:nil];
  }
  _currentConcurrency += 1;
  LOG_DEBUG(@"TaskQueue %@ concurrency increased to %i", _conditionLock ? @"thread" : @"GCD", _currentConcurrency);
  
  // Acquire execution lock and continue running until there are no pending tasks left
  while (_pendingTasks.count) {
    Task* activeTask = nil;
    
    // Find the first task ready for execution
    for (Task* task in _pendingTasks) {
      [task retain];
      
      // Check if the task has dependencies
      if (task.dependencies.count) {
        // Update dependency list
        NSSet* set = [[NSSet alloc] initWithSet:task.dependencies];
        for (Task* dependency in set) {
          // Check if dependency is done
          if ((dependency.status == kTaskStatus_Finished) || (dependency.status == kTaskStatus_Cancelled)) {
            // Dependency has succeeded, remove it from the list
            if (dependency.valid || task.ignoresInvalidDependencies) {
              [task.dependencies removeObject:dependency];
            }
            // Dependency has failed, remove all dependencies and abort this task
            else {
              [task.dependencies removeAllObjects];
              [_pendingTasks removeObject:task];
              task.status = kTaskStatus_Finished;
              break;
            }
          }
        }
        [set release];
        
        // Skip this task if it still has dependencies
        if (task.dependencies.count) {
          [task release];
          continue;
        }
      }
      
      activeTask = task;
      break;
    }
    if (activeTask == nil) {
      break;
    }
    
    // Execute task unless it was aborted during dependencies checking above
    if (activeTask.status == kTaskStatus_Scheduled) {
      BOOL valid = NO;
      [_pendingTasks removeObject:activeTask];
      activeTask.status = kTaskStatus_Executing;
      [_executingTasks addObject:activeTask];
      [_executionLock unlock];
      
      // Execute task while execution lock is released
#ifndef NDEBUG
      LOG_DEBUG(@"Started executing <%@ %p>", [activeTask class], activeTask);
      CFAbsoluteTime time = CFAbsoluteTimeGetCurrent();
#endif
      NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
      @try {
        valid = [activeTask execute];
      }
      @catch (NSException* exception) {
        LOG_EXCEPTION(exception);
        LOG_ERROR(@"Execution of %@ aborted because of exception", [activeTask miniDescription]);
      }
      [pool release];
#ifndef NDEBUG
      time = CFAbsoluteTimeGetCurrent() - time;
      LOG_DEBUG(@"Done executing <%@ %p> in %.3f seconds", [activeTask class], activeTask, time);
#endif
      
      [_executionLock lock];
      [_executingTasks removeObject:activeTask];
      if (activeTask.status != kTaskStatus_Cancelled) {
        activeTask.status = kTaskStatus_Finished;
        activeTask.valid = valid;
      }
    }
    
    // Notify task delegate if necessary
    if (activeTask.status == kTaskStatus_Cancelled) {
      if (activeTask.delegate && activeTask.didCancelSelector) {
        [self _performSelector:activeTask.didCancelSelector target:activeTask.delegate argument:activeTask];
      }
    } else if (activeTask.status == kTaskStatus_Finished) {
      if (activeTask.delegate && activeTask.didFinishSelector) {
        [self _performSelector:activeTask.didFinishSelector target:activeTask.delegate argument:activeTask];
      }
    } else {
      NOT_REACHED();
    }
    
    [activeTask release];
  }
  
  _currentConcurrency -= 1;
  if (_currentConcurrency == 0) {
    [self _performSelector:@selector(_queueDidBecomeIdle:) target:self argument:nil];
  }
  LOG_DEBUG(@"TaskQueue %@ concurrency reduced to %i", _conditionLock ? @"thread" : @"GCD", _currentConcurrency);
  [_executionLock unlock];
}

// Called from queue thread
static void __QueueSourceCallBack(void* info) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  [(TaskQueue*)info _executeTasks];
  [pool release];
}

// Called from queue thread
- (void) __queueThread:(NSNumber*)index {
  // Set thread priority, add the queue runloop source to the runloop then signal -init that the queue thread is ready
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  [_conditionLock lockWhenCondition:0];
  [NSThread setThreadPriority:0.0];
  _queueRunLoops[[index integerValue]] = CFRunLoopGetCurrent();
  CFRunLoopAddSource(CFRunLoopGetCurrent(), _queueSources[[index integerValue]], kCFRunLoopCommonModes);
  [_conditionLock unlockWithCondition:1];
  [pool release];
  
  // Run forever
  while (1) {
    NSAutoreleasePool* localPool = [[NSAutoreleasePool alloc] init];
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, kThreadRunLoopInterval, NO);
    [localPool release];
  }
}

- (id) initWithConcurrency:(NSUInteger)concurrency {
  if ((self = [super init])) {
    _executionLock = [[NSLock alloc] init];
    _suspendedTasks = [[NSMutableArray alloc] init];
    _pendingTasks = [[NSMutableArray alloc] init];
    _executingTasks = [[NSMutableSet alloc] init];
    _messageLock = [[NSLock alloc] init];
    _messageQueue = [[NSMutableArray alloc] init];
    _maxConcurrency = concurrency;
    _idle = YES;
    
    // On earlier OSes, use worker threads instead of GCD
#if TARGET_OS_IPHONE
    if (kCFCoreFoundationVersionNumber < kCFCoreFoundationVersionNumber_iOS_4_0)
#else
    if (kCFCoreFoundationVersionNumber < kCFCoreFoundationVersionNumber10_6)
#endif
    {
      _conditionLock = [[NSConditionLock alloc] initWithCondition:0];
    }
    
    // Create a runloop source on the main thread to execute delegate callbacks
    CFRunLoopSourceContext mainContext = {0, self, NULL, NULL, NULL, NULL, NULL, NULL, NULL, __MainSourceCallBack};
    _mainSource = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &mainContext);
    _mainRunLoop = CFRunLoopGetMain();
    CFRunLoopAddSource(CFRunLoopGetMain(), _mainSource, kCFRunLoopCommonModes);
    CFRunLoopAddSource(CFRunLoopGetMain(), _mainSource, kTaskMainRunLoopMode);
    
    // Create threads and matching runloop sources
    _queueSources = malloc(_maxConcurrency * sizeof(void*));
    if (_conditionLock) {
      _queueRunLoops = malloc(_maxConcurrency * sizeof(CFRunLoopRef));
      CFRunLoopSourceContext queueContext = {0, self, NULL, NULL, NULL, NULL, NULL, NULL, NULL, __QueueSourceCallBack};
      for (NSUInteger i = 0; i < _maxConcurrency; ++i) {
        _queueSources[i] = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &queueContext);
        [NSThread detachNewThreadSelector:@selector(__queueThread:) toTarget:self withObject:[NSNumber numberWithInteger:i]];
        [_conditionLock lockWhenCondition:1];
        [_conditionLock unlockWithCondition:0];
      }
    } else {
      for (NSUInteger i = 0; i < _maxConcurrency; ++i) {
        _queueSources[i] = dispatch_source_create(DISPATCH_SOURCE_TYPE_DATA_ADD, 0, 0,
                                                  dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
        dispatch_source_set_event_handler(_queueSources[i], ^{
          NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
          [self _executeTasks];
          [pool release];
        });
        dispatch_resume(_queueSources[i]);
      }
    }
  }
  return self;
}

- (id) init {
  [self doesNotRecognizeSelector:_cmd];
  return nil;
}

- (void) dealloc {
  [self doesNotRecognizeSelector:_cmd];
  
  [super dealloc];
}

- (NSUInteger) numberOfQueuedTasks {
  [_executionLock lock];
  NSUInteger count = _suspendedTasks.count + _pendingTasks.count;
  [_executionLock unlock];
  return count;
}

- (NSUInteger) numberOfExecutingTasks {
  [_executionLock lock];
  NSUInteger count = _executingTasks.count;
  [_executionLock unlock];
  return count;
}

- (void) _addDependencies:(id)dependencies toTask:(Task*)task {
  [_executionLock lock];
  
  CHECK(task.status == kTaskStatus_Inactive);
  if (task.dependencies == nil) {
    task.dependencies = [NSMutableSet set];
  }
  for (Task* dependency in dependencies) {
    CHECK(dependency.status != kTaskStatus_Cancelled);
    DCHECK(![task.dependencies containsObject:dependency]);
    [task.dependencies addObject:dependency];
  }
  
  [_executionLock unlock];
}

- (void) scheduleTaskForExecution:(Task*)task {
  [self scheduleTasksForExecution:(NSSet*)task highPriority:NO];  // Hack
}

- (void) scheduleTaskForExecution:(Task*)task highPriority:(BOOL)highPriority {
  [self scheduleTasksForExecution:(NSSet*)task highPriority:highPriority];  // Hack
}

- (void) scheduleTasksForExecution:(NSSet*)tasks {
  [self scheduleTasksForExecution:tasks highPriority:NO];
}

- (void) scheduleTasksForExecution:(NSSet*)tasks highPriority:(BOOL)highPriority {
  [_executionLock lock];
  
  // Add task(s) to queue
  if ([tasks isKindOfClass:[Task class]]) {
    [(Task*)tasks _scheduleForExecutionInQueue:self atBeginning:highPriority];
  } else if ([tasks isKindOfClass:[NSSet class]]) {
    for (Task* task in tasks) {
      [task _scheduleForExecutionInQueue:self atBeginning:highPriority];
    }
  }
  
  // Signal queue threads if necessary
  if (_paused == 0) {
    for (NSUInteger i = 0; i < _maxConcurrency; ++i) {
      if (_conditionLock) {
        CFRunLoopSourceSignal(_queueSources[i]);
        CFRunLoopWakeUp(_queueRunLoops[i]);
      } else {
        dispatch_source_merge_data(_queueSources[i], 1);
      }
    }
  }
  
  [_executionLock unlock];
}

- (void) cancelTaskExecution:(Task*)task {
  [self cancelTasksExecution:(NSSet*)task];  // Hack
}

- (void) cancelTasksExecution:(NSSet*)tasks {
  [_executionLock lock];
  
  // Remove task(s) from queue
  if ([tasks isKindOfClass:[Task class]]) {
    [(Task*)tasks _cancelExecutionFromQueue:self];
  } else if ([tasks isKindOfClass:[NSSet class]]) {
    for (Task* task in tasks) {
      [task _cancelExecutionFromQueue:self];
    }
  } else if ([tasks isKindOfClass:[NSNull class]]) {
    NSMutableSet* set = [[NSMutableSet alloc] init];
    [set addObjectsFromArray:_suspendedTasks];
    [set addObjectsFromArray:_pendingTasks];
    [set unionSet:_executingTasks];
    for (Task* task in set) {
      [task _cancelExecutionFromQueue:self];
    }
    [set release];
  }
  
  [_executionLock unlock];
}

- (void) cancelAllTasksExecution {
  [self cancelTasksExecution:(NSSet*)[NSNull null]];  // Hack
}

- (void) _performSelector:(SEL)selector target:(id)target argument:(id)argument {
  // Create message and append to queue
  [_messageLock lock];
  TaskMessage* message = [[TaskMessage alloc] initWithTarget:target selector:selector argument:argument];
  [_messageQueue addObject:message];
  [message release];
  [_messageLock unlock];
  
  // Wake up main thread
  CFRunLoopSourceSignal(_mainSource);
  CFRunLoopWakeUp(_mainRunLoop);
}

- (void) performSelectorOnMainThread:(SEL)selector withArgument:(id)argument usingTarget:(id)target {
  CHECK(target && selector);
  [self _performSelector:selector target:target argument:argument];
}

- (BOOL) isSuspended {
  [_executionLock lock];
  NSUInteger paused = _paused;
  [_executionLock unlock];
  return (paused > 0);
}

- (void) suspend {
  [_executionLock lock];
  
  // Suspend scheduled tasks
  if (_paused == 0) {
    [_suspendedTasks addObjectsFromArray:_pendingTasks];
    [_pendingTasks removeAllObjects];
    LOG_VERBOSE(@"TaskQueue did suspend");
  }
  
  // Increment paused counter
  _paused += 1;
  
  [_executionLock unlock];
}

- (void) resume {
  [_executionLock lock];
  
  // Decrement paused counter
  CHECK(_paused);
  _paused -= 1;
  
  // Resume scheduled tasks & signal queue threads if necessary
  if (_paused == 0) {
    [_pendingTasks addObjectsFromArray:_suspendedTasks];
    [_suspendedTasks removeAllObjects];
    if (_pendingTasks.count) {
      for (NSUInteger i = 0; i < _maxConcurrency; ++i) {
        if (_conditionLock) {
          CFRunLoopSourceSignal(_queueSources[i]);
          CFRunLoopWakeUp(_queueRunLoops[i]);
        } else {
          dispatch_source_merge_data(_queueSources[i], 1);
        }
      }
    }
    LOG_VERBOSE(@"TaskQueue did resume");
  }
  
  [_executionLock unlock];
}

- (void) waitUntilIdle {
  CHECK(CFRunLoopGetCurrent() == CFRunLoopGetMain());
  NSUInteger count;
  do {
    [_executionLock lock];
    NSUInteger concurrencyCount = _currentConcurrency;
    [_executionLock unlock];
    if (concurrencyCount > 0) {
      do {
        CFRunLoopRunInMode(kTaskMainRunLoopMode, kTaskMainRunLoopInterval, true);
      } while (_idle == NO);
    }
    [_executionLock lock];
    count = _pendingTasks.count + _executingTasks.count;
    [_executionLock unlock];
  } while (count > 0);
}

- (void) waitUntilFence:(NSUInteger*)fence {
  CHECK(fence);
  CHECK(CFRunLoopGetCurrent() == CFRunLoopGetMain());
  while (*fence > 0) {
    CFRunLoopRunInMode(kTaskMainRunLoopMode, kTaskMainRunLoopInterval, true);
  }
}

- (NSString*) description {
  return [self smartDescription];
}

@end

@implementation TaskGroup

@synthesize tasks=_tasks;

- (id) init {
  return [self initWithTasks:nil];
}

- (id) initWithTasks:(NSArray*)tasks {
  if ((self = [super init])) {
    _tasks = [tasks copy];
    
    [[TaskQueue sharedTaskQueue] _addDependencies:_tasks toTask:self];
  }
  return self;
}

- (void) dealloc {
  [_tasks release];
  
  [super dealloc];
}

- (void) _scheduleForExecutionInQueue:(TaskQueue*)queue atBeginning:(BOOL)atBeginning {
  for (Task* task in _tasks) {
    [task _scheduleForExecutionInQueue:queue atBeginning:atBeginning];
  }
  [super _scheduleForExecutionInQueue:queue atBeginning:atBeginning];
}

- (void) _cancelExecutionFromQueue:(TaskQueue*)queue {
  for (Task* task in _tasks) {
    [task _cancelExecutionFromQueue:queue];
  }
  [super _cancelExecutionFromQueue:queue];
}

- (BOOL) execute {
  for (Task* task in _tasks) {
    if (!task.valid) {
      return NO;
    }
  }
  return YES;
}

@end

@implementation TaskAction

@synthesize target=_target, selector=_selector, argument=_argument, result=_result;

- (id) init {
  return [self initWithTarget:nil selector:NULL argument:nil];
}

- (id) initWithTarget:(id)target selector:(SEL)selector {
  return [self initWithTarget:target selector:selector argument:[TaskAction class]];
}

- (id) initWithTarget:(id)target selector:(SEL)selector argument:(id)argument {
  CHECK(target && selector);
  if ((self = [super init])) {
    _target = [target retain];
    _selector = selector;
    _argument = [argument retain];
  }
  return self;
}

- (void) dealloc {
  [_target release];
  [_argument release];
  [_result release];
  
  [super dealloc];
}

- (BOOL) execute {
  _result = [[_target performSelector:_selector withObject:(_argument == [TaskAction class] ? self : _argument)] retain];
  return _result ? YES : NO;
}

// Override NSObject category implementation
- (NSString*) miniDescription {
  return [NSString stringWithFormat:@"<%@ %p -[%@ %@]>", [self class], self, [_target class], NSStringFromSelector(_selector)];
}

@end

#if NS_BLOCKS_AVAILABLE

@implementation TaskBlock

+ (void) scheduleTaskBlock:(id (^)())taskBlock completionBlock:(void (^)(id result))completionBlock highPriority:(BOOL)highPriority {
  TaskBlock* task = [[TaskBlock alloc] initWithTaskBlock:taskBlock completionBlock:completionBlock];
  [[TaskQueue sharedTaskQueue] scheduleTaskForExecution:task highPriority:highPriority];
  [task release];
}

+ (void) _didComplete:(TaskBlock*)task {
  void (^Block)(id result) = task->_completionBlock;
  Block(task->_result);
}

- (id) init {
  [self doesNotRecognizeSelector:_cmd];
  return nil;
}

- (id) initWithTaskBlock:(id (^)())taskBlock completionBlock:(void (^)(id result))completionBlock {
  if ((self = [super init])) {
    _taskBlock = Block_copy(taskBlock);
    _completionBlock = Block_copy(completionBlock);
    
    [super setDelegate:[TaskBlock class]];
    [super setDidFinishSelector:@selector(_didComplete:)];
    [super setDidCancelSelector:@selector(_didComplete:)];
  }
  return self;
}

- (void) dealloc {
  if (_taskBlock) {
    Block_release(_taskBlock);
  }
  if (_completionBlock) {
    Block_release(_completionBlock);
  }
  [_result release];
  
  [super dealloc];
}

- (BOOL) execute {
  id (^Block)() = _taskBlock;
  _result = [Block() retain];
  return _result ? YES : NO;
}

- (void) setDelegate:(id)delegate {
  [self doesNotRecognizeSelector:_cmd];
}

- (void) setDidScheduleSelector:(SEL)selector {
  [self doesNotRecognizeSelector:_cmd];
}

- (void) setDidFinishSelector:(SEL)selector {
  [self doesNotRecognizeSelector:_cmd];
}

- (void) setDidCancelSelector:(SEL)selector {
  [self doesNotRecognizeSelector:_cmd];
}

@end

#endif

@implementation TaskHTTPDownload

@synthesize request=_request, headerFields=_headerFields, data=_data;

- (id) init {
  return [self initWithURL:nil];
}

- (id) initWithURL:(NSURL*)url {
  return [self initWithURL:url userAgent:nil handleCookies:NO];
}

- (id) initWithURL:(NSURL*)url userAgent:(NSString*)userAgent handleCookies:(BOOL)handleCookies {
  NSURLRequest* request = [HTTPURLConnection HTTPRequestWithURL:url method:@"GET" userAgent:userAgent handleCookies:handleCookies];
  return [self initWithRequest:request];
}

- (id) initWithRequest:(NSURLRequest*)request {
  if ((self = [super init])) {
    _request = [request mutableCopy];
  }
  return self;
}

- (void) dealloc {
  [_request release];
  [_headerFields release];
  [_data release];
  
  [super dealloc];
}

- (BOOL) execute {
  NSDictionary* dictionary;
  _data = [[HTTPURLConnection downloadHTTPRequestToMemory:_request delegate:(id)self headerFields:&dictionary] retain];
  if (_data) {
    _headerFields = [dictionary copy];
  }
  return _data ? YES : NO;
}

@end
