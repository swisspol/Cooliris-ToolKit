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

#import "ShakeMotion.h"
#import "Logging.h"

#define kAccelerometerFrequency 20.0  // In Hz - UIAccelerometer default is 10.0
#define kAccelerationHistorySize 6
#define kAccelerationDampingFactor 0.8
#define kAccelerationShakingThreshold 4.0

@implementation ShakeMotion

@synthesize target=_target, action=_action, enabled=_enabled;

- (id) initWithTarget:(id)target action:(SEL)action {
  CHECK(target && action);
  if ((self = [super init])) {
    _target = [target retain];
    _action = action;
    _enabled = YES;
    
    _accelerationHistory = malloc(kAccelerationHistorySize * sizeof(UIAccelerationValue));
    for (NSUInteger i = 0; i < kAccelerationHistorySize; ++i) {
      _accelerationHistory[i] = NAN;
    }
    [[UIAccelerometer sharedAccelerometer] setDelegate:self];
    [[UIAccelerometer sharedAccelerometer] setUpdateInterval:(1.0 / kAccelerometerFrequency)];
  }
  return self;
}

- (void) dealloc {
  [[UIAccelerometer sharedAccelerometer] setDelegate:nil];
  if (_accelerationHistory) {
    free(_accelerationHistory);
  }
  [_target release];
  
  [super dealloc];
}

- (void) setEnabled:(BOOL)flag {
  if (flag != _enabled) {
    _enabled = flag;
    
    _shaking = NO;
  }
}

- (void) accelerometer:(UIAccelerometer*)accelerometer didAccelerate:(UIAcceleration*)acceleration {
  // Apply simple low-pass filter
  _currentAcceleration = kAccelerationDampingFactor * _currentAcceleration + (1.0 - kAccelerationDampingFactor) * acceleration.z;
  for (NSUInteger i = kAccelerationHistorySize - 1; i > 0; --i) {
    _accelerationHistory[i] = _accelerationHistory[i - 1];
  }
  _accelerationHistory[0] = acceleration.z;
  
  // There's a shake motion if accumulated acceleration is above a threshold
  UIAccelerationValue sum = 0.0;
  for (NSUInteger i = 0; i < kAccelerationHistorySize; ++i) {
    UIAccelerationValue value = _accelerationHistory[i] - _currentAcceleration;
    sum += value >= 0.0 ? value : -value;
  }
  BOOL shaking = sum >= kAccelerationShakingThreshold;
  
  // Update shake motion state
  if (_enabled) {
    if (shaking && !_shaking) {
      _shaking = YES;
    } else if (!shaking && _shaking) {
      _shaking = NO;
      
      [_target performSelector:_action withObject:self];
    }
  }
}

@end
