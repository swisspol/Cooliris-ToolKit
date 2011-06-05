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

typedef enum {
  kOverlayViewArrowDirection_None = 0,
  kOverlayViewArrowDirection_Up,
  kOverlayViewArrowDirection_Left,
  kOverlayViewArrowDirection_Right,
  kOverlayViewArrowDirection_Down
} OverlayViewArrowDirection;

// When using a constraint rectangle, "arrowDirection" and "anchorLocation" will be automatically adjusted so that the entire content fits
@interface OverlayView : UIView {
@private
  UIColor* _tintColor;
  UIView* _contentView;
  OverlayViewArrowDirection _arrowDirection;
  CGFloat _arrowPosition;
  UIView* _centerView;
  UIView* _topView;
  UIView* _leftView;
  UIView* _rightView;
  UIView* _bottomView;
}
@property(nonatomic, retain) UIColor* tintColor;  // Default is nil
@property(nonatomic, retain) UIView* contentView;
@property(nonatomic) OverlayViewArrowDirection arrowDirection;  // Initial value is kOverlayViewArrowDirection_None
@property(nonatomic) CGFloat arrowPosition;  // In [0,1] range - Initial value is 0.5
@property(nonatomic) CGSize contentSize;
@property(nonatomic) CGPoint anchorLocation;  // If there's an arrow, the anchor is the arrow head, otherwise it's the content center
+ (CGSize) minimumContentSize;  // Currently 100x100
+ (CGSize) maximumContentSizeForConstraintRect:(CGRect)rect;  // Maximum content size for which content is guaranteed to fit
- (void) setContentSize:(CGSize)size anchorLocation:(CGPoint)location;
- (void) setContentSize:(CGSize)size
         anchorLocation:(CGPoint)location  // Constrained to rectangle as well
         constraintRect:(CGRect)rect  // Expressed in the superview coordinates
     preferredDirection:(OverlayViewArrowDirection)direction  // Pass kOverlayViewArrowDirection_None for any
  adjustableContentSize:(BOOL)adjustableContentSize;
@end
