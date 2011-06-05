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

#import "BasicAnimation.h"

@implementation BasicAnimation

+ (void) animationDidStop:(BasicAnimation*)animation finished:(BOOL)finished {
  if (finished) {
    if (animation->_finishSelector) {
      [animation->_delegate performSelector:animation->_finishSelector withObject:animation->_argument];
    }
  } else {
    if (animation->_cancelSelector) {
      [animation->_delegate performSelector:animation->_cancelSelector withObject:animation->_argument];
    }
  }
}

- (id) initWithDelegate:(id)delegate didStopSelector:(SEL)stopSelector argument:(id)argument {
  return [self initWithDelegate:delegate didFinishSelector:stopSelector didCancelSelector:stopSelector argument:argument];
}

- (id) initWithDelegate:(id)delegate didFinishSelector:(SEL)finishSelector didCancelSelector:(SEL)cancelSelector argument:(id)argument {
  if ((self = [super init])) {
    _delegate = [delegate retain];
    _finishSelector = finishSelector;
    _cancelSelector = cancelSelector;
    _argument = [argument retain];
    
    self.delegate = [BasicAnimation class];
  }
  return self;
}

- (void) dealloc {
  [_delegate release];
  [_argument release];
  
  [super dealloc];
}

- (id) copyWithZone:(NSZone*)zone {
  BasicAnimation* copy = [super copyWithZone:zone];
  if (copy) {
    copy->_delegate = [_delegate retain];
    copy->_finishSelector = _finishSelector;
    copy->_cancelSelector = _cancelSelector;
    copy->_argument = [_argument retain];
  }
  return copy;
}

@end
