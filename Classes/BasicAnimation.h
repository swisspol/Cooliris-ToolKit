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

#import <QuartzCore/QuartzCore.h>

@interface BasicAnimation : CABasicAnimation {
@private
  id _delegate;
  SEL _finishSelector;
  SEL _cancelSelector;
  id _argument;
}
- (id) initWithDelegate:(id)delegate didStopSelector:(SEL)stopSelector argument:(id)argument;
- (id) initWithDelegate:(id)delegate didFinishSelector:(SEL)finishSelector didCancelSelector:(SEL)cancelSelector argument:(id)argument;
@end
