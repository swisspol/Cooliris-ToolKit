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

@interface SliderControl : UIControl {
@private
  float _value;
  float _min;
  float _max;
  BOOL _continuous;
  CGFloat _margin;
  
  UIImageView* _backgroundView;
  UIImageView* _thumbView;
  float _lastValue;
}
@property(nonatomic) float value;  // Clamped
@property(nonatomic) float minimumValue;  // Default is 0.0
@property(nonatomic) float maximumValue;  // Default is 1.0
@property(nonatomic,getter=isContinuous) BOOL continuous;  // Default is YES
@property(nonatomic, retain) UIImage* backgroundImage;  // Default is nil
@property(nonatomic, retain) UIImage* thumbImage;  // Default is nil
@property(nonatomic) CGFloat extraMargin;  // Default is 0.0
@end
