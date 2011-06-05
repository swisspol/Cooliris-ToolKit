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

#import "WorkerThread.h"
#import "Logging.h"

@implementation WorkerThread

@synthesize running=_running;

- (id) init {
  [self doesNotRecognizeSelector:_cmd];
  return nil;
}

- (void) _thread:(id)argument {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  LOG_DEBUG(@"Started worker thread %@", [NSThread currentThread]);
  
  [NSThread setThreadPriority:0.0];
  [_conditionLock lockWhenCondition:0];
  _running = YES;
  if (_startSelector) {
    NSAutoreleasePool* localPool = [[NSAutoreleasePool alloc] init];
    @try {
      [_target performSelector:_startSelector withObject:argument];
    }
    @catch (NSException* exception) {
      LOG_ERROR(@"Exception while starting worker thread: %@", exception);
    }
    [localPool release];
  }
  [_conditionLock unlockWithCondition:1];
  
  @try {
    [_target performSelector:_runSelector withObject:argument];
  }
  @catch (NSException* exception) {
    LOG_ERROR(@"Exception while running worker thread: %@", exception);
  }
  
  [_conditionLock lockWhenCondition:2];
  if (_endSelector) {
    NSAutoreleasePool* localPool = [[NSAutoreleasePool alloc] init];
    @try {
      [_target performSelector:_endSelector withObject:argument];
    }
    @catch (NSException* exception) {
      LOG_ERROR(@"Exception while ending worker thread: %@", exception);
    }
    [localPool release];
  }
  _running = NO;
  [_conditionLock unlockWithCondition:3];
  
  LOG_DEBUG(@"Terminated worker thread %@", [NSThread currentThread]);
  [pool release];
}

- (id) initWithTarget:(id)target selector:(SEL)selector argument:(id)argument {
  return [self initWithTarget:target startSelector:NULL runSelector:selector endSelector:NULL argument:argument];
}

- (id) initWithTarget:(id)target
        startSelector:(SEL)startSelector
          runSelector:(SEL)runSelector
          endSelector:(SEL)endSelector
             argument:(id)argument {
  if ((self = [super init])) {
    _target = [target retain];
    _startSelector = startSelector;
    _runSelector = runSelector;
    _endSelector = endSelector;
    _conditionLock = [[NSConditionLock alloc] init];
    [NSThread detachNewThreadSelector:@selector(_thread:) toTarget:self withObject:argument];
    [_conditionLock lockWhenCondition:1];
    [_conditionLock unlockWithCondition:2];
  }
  return self;
}

- (void) dealloc {
  [self waitUntilDone];
  
  [super dealloc];
}

- (void) waitUntilDone {
  if (_running) {
    [_conditionLock lockWhenCondition:3];
    [_conditionLock unlockWithCondition:0];
    [_conditionLock release];  // Free immediately otherwise it may happen on the worker thread through -dealloc if NSThead is the last one to release 'self'
    _conditionLock = nil;
  }
  
  [_target release];  // Free memory immediately
  _target = nil;
}

@end
