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
#import "UnitTest.h"

static NSMutableString* _testee;

@interface TaskOne : Task
@end

@implementation TaskOne

- (BOOL) execute {
  [_testee appendFormat:@"1"];
  return YES;
}

@end

@interface TaskTwo : Task
@end

@implementation TaskTwo

- (BOOL) execute {
  [_testee appendFormat:@"2"];
  return YES;
}

@end

@interface TaskThree : Task
@end

@implementation TaskThree

- (BOOL) execute {
  [_testee appendFormat:@"3"];
  return YES;
}

@end

@interface TaskFour : Task
@end

@implementation TaskFour

- (BOOL) execute {
  [_testee appendFormat:@"4"];
  return YES;
}

@end

@interface TaskCancel : Task
@end

@implementation TaskCancel

- (BOOL) execute {
  [[TaskQueue sharedTaskQueue] cancelAllTasksExecution];
  return YES;
}

@end

@interface TaskSuspend : Task
@end

@implementation TaskSuspend

- (BOOL) execute {
  [[TaskQueue sharedTaskQueue] suspend];
  return YES;
}

@end

@interface TaskMainThreadTest : Task
@end

@implementation TaskMainThreadTest

- (BOOL) execute {
  [[TaskQueue sharedTaskQueue] performSelectorOnMainThread:@selector(executeOnMain:)
                                              withArgument:@"main"
                                               usingTarget:self];
  [NSThread sleepForTimeInterval:1.0];
  return YES;
}

- (void) executeOnMain:(NSString*)str {
  [_testee appendString:str];
}

@end

@interface TaskTests : UnitTest {
  TaskOne*   _taskOne;
  TaskTwo*   _taskTwo;
  TaskThree* _taskThree;
  TaskFour*  _taskFour;
}
@end

@implementation TaskTests

+ (void) initialize {
  [TaskQueue setDefaultConcurrency:4];
}

- (void) setUp {
  _testee = [@"" mutableCopy];
  
  _taskOne   = [[[TaskOne alloc] init] autorelease];
  _taskTwo   = [[[TaskTwo alloc] init] autorelease];
  _taskThree = [[[TaskThree alloc] init] autorelease];
  _taskFour  = [[[TaskFour alloc] init] autorelease];
}

- (void) testDependencies {
  [_taskTwo addDependency:_taskOne];
  [_taskThree addDependency:_taskTwo];
  [_taskFour addDependency:_taskThree];
  
  [[TaskQueue sharedTaskQueue] scheduleTasksForExecution:[NSSet setWithObjects:_taskOne, _taskTwo, _taskThree, _taskFour, nil]];
  [[TaskQueue sharedTaskQueue] waitUntilIdle];
  
  AssertEqualObjects(_testee, @"1234");
}

- (void) testCancelling {
  [_taskTwo addDependency:_taskOne];
  [_taskThree addDependency:_taskTwo];
  [_taskFour addDependency:_taskThree];
  
  TaskCancel* cancellerTask = [[[TaskCancel alloc] init] autorelease];
  [_taskThree addDependency:cancellerTask];
  [cancellerTask addDependency:_taskTwo];

  [[TaskQueue sharedTaskQueue] scheduleTasksForExecution:[NSSet setWithObjects:_taskOne, _taskTwo, _taskThree, _taskFour, cancellerTask, nil]];
  [[TaskQueue sharedTaskQueue] waitUntilIdle];
  
  AssertEqualObjects(_testee, @"12");
}

- (void) testSuspending {
  [_taskTwo addDependency:_taskOne];
  [_taskThree addDependency:_taskTwo];
  [_taskFour addDependency:_taskThree];
  
  TaskSuspend* suspenderTask = [[[TaskSuspend alloc] init] autorelease];
  [_taskThree addDependency:suspenderTask];
  [suspenderTask addDependency:_taskTwo];
  
  [[TaskQueue sharedTaskQueue] scheduleTasksForExecution:[NSSet setWithObjects:_taskOne, _taskTwo, _taskThree, _taskFour, suspenderTask, nil]];
  [[TaskQueue sharedTaskQueue] waitUntilIdle];
  
  AssertEqualObjects(_testee, @"12");
  
  [[TaskQueue sharedTaskQueue] resume];
  [[TaskQueue sharedTaskQueue] waitUntilIdle];
  
  AssertEqualObjects(_testee, @"1234");
}

- (void) testMainThreadExecution {
  TaskMainThreadTest* executorTask = [[[TaskMainThreadTest alloc] init] autorelease];
  [[TaskQueue sharedTaskQueue] scheduleTaskForExecution:executorTask];
  [[TaskQueue sharedTaskQueue] waitUntilIdle];
  
  AssertEqualObjects(_testee, @"main");
}
@end
