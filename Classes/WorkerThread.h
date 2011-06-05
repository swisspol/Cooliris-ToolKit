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

@interface WorkerThread : NSObject {
@private
  id _target;
  SEL _startSelector;
  SEL _runSelector;
  SEL _endSelector;
  NSConditionLock* _conditionLock;
  BOOL _running;
}
@property(nonatomic, readonly, getter=isRunning) BOOL running;
- (id) initWithTarget:(id)target selector:(SEL)selector argument:(id)argument;  // Blocks until the worker thread has started
- (id) initWithTarget:(id)target
        startSelector:(SEL)startSelector
          runSelector:(SEL)runSelector
          endSelector:(SEL)endSelector
             argument:(id)argument;
- (void) waitUntilDone;  // Blocks until the worker thread has exited (called automatically on -dealloc)
@end
