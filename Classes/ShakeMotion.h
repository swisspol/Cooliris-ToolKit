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

#import <UIKit/UIKit.h>

@interface ShakeMotion : NSObject <UIAccelerometerDelegate> {
@private
  id _target;
  SEL _action;
  BOOL _enabled;
  UIAccelerationValue* _accelerationHistory;
  UIAccelerationValue _currentAcceleration;
  BOOL _shaking;
}
@property(nonatomic, readonly) id target;
@property(nonatomic, readonly) SEL action;
@property(nonatomic, getter=isEnabled) BOOL enabled;  // YES by default
- (id) initWithTarget:(id)target action:(SEL)action;
@end
