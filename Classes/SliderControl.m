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

#import "SliderControl.h"
#import "Logging.h"

@implementation SliderControl

@synthesize value=_value, minimumValue=_min, maximumValue=_max, continuous=_continuous, extraMargin=_margin;

- (void) _initialize {
  _max = 1.0;
  _continuous = YES;
  
  _backgroundView = [[UIImageView alloc] initWithFrame:self.bounds];
  [self addSubview:_backgroundView];
  
  _thumbView = [[UIImageView alloc] init];
  [self addSubview:_thumbView];
  
  self.backgroundColor = nil;
  self.autoresizesSubviews = NO;
}

- (id) initWithFrame:(CGRect)frame {
  if ((self = [super initWithFrame:frame])) {
    [self _initialize];
  }
  return self;
}

- (void) dealloc {
  [_backgroundView release];
  [_thumbView release];
  
  [super dealloc];
}

- (id) initWithCoder:(NSCoder*)coder {
  if ((self = [super initWithCoder:coder])) {
    [self _initialize];
  }
  return self;
}

- (void) encodeWithCoder:(NSCoder*)coder {
  [self doesNotRecognizeSelector:_cmd];
}

- (void) _updateThumb {
  CGRect bounds = self.bounds;
  CGRect frame = _thumbView.frame;
  frame.origin.x = roundf(_margin + (_value - _min) / (_max - _min) * (bounds.size.width - 2.0 * _margin) - frame.size.width / 2.0);
  frame.origin.y = roundf(bounds.size.height / 2.0 - frame.size.height / 2.0);
  _thumbView.frame = frame;
}

- (void) setValue:(float)value {
  _value = MIN(MAX(value, _min), _max);
  [self _updateThumb];
}

- (void) setMinimumValue:(float)min {
  DCHECK(min < _max);
  _min = min;
  [self setValue:_value];
}

- (void) setMaximumValue:(float)max {
  DCHECK(max > _min);
  _max = max;
  [self setValue:_value];
}

- (UIImage*) backgroundImage {
  return _backgroundView.image;
}

- (void) setBackgroundImage:(UIImage*)image {
  _backgroundView.image = image;
}

- (UIImage*) thumbImage {
  return _thumbView.image;
}

- (void) setThumbImage:(UIImage*)image {
  _thumbView.image = image;
  CGSize size = image.size;
  _thumbView.bounds = CGRectMake(0.0, 0.0, size.width, size.height);
}

- (void) setExtraMargin:(CGFloat)margin {
  _margin = margin;
  [self _updateThumb];
}

- (void) layoutSubviews {
  _backgroundView.frame = self.bounds;
  [self _updateThumb];
}

- (void) _updateValueForLocation:(CGPoint)location {
  _value = _min + MIN(MAX((location.x - _margin) / (self.bounds.size.width - 2.0 * _margin), 0.0), 1.0) * (_max - _min);
  [self _updateThumb];
}

- (BOOL) beginTrackingWithTouch:(UITouch*)touch withEvent:(UIEvent*)event {
  if (![super beginTrackingWithTouch:touch withEvent:event]) {
    return NO;
  }
  
  _lastValue = _value;
  
  return YES;
}

- (BOOL) continueTrackingWithTouch:(UITouch*)touch withEvent:(UIEvent*)event {
  if (![super continueTrackingWithTouch:touch withEvent:event]) {
    return NO;
  }
  
  [self _updateValueForLocation:[touch locationInView:self]];
  if (_continuous && (_value != _lastValue)) {
    [self sendActionsForControlEvents:UIControlEventValueChanged];
    _lastValue = _value;
  }
  
  return YES;
}

- (void) endTrackingWithTouch:(UITouch*)touch withEvent:(UIEvent*)event {
  [super endTrackingWithTouch:touch withEvent:event];
  
  [self _updateValueForLocation:[touch locationInView:self]];
  
  if (_value != _lastValue) {
    [self sendActionsForControlEvents:UIControlEventValueChanged];
  }
}

- (void) cancelTrackingWithEvent:(UIEvent*)event {
  [super cancelTrackingWithEvent:event];
  
  ;
}

@end
