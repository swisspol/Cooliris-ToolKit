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
  kZoomViewDisplayMode_Centered = 0,
  kZoomViewDisplayMode_Fit,
  kZoomViewDisplayMode_FitVertically,
  kZoomViewDisplayMode_FitHorizontally,
  kZoomViewDisplayMode_Fill,
  kZoomViewDisplayMode_Automatic  // Choose kZoomViewDisplayMode_Fit or kZoomViewDisplayMode_Fill automatically depending on display and view aspect ratio similarity
} ZoomViewDisplayMode;

@interface ZoomView : UIScrollView {
@private
  UIView* _displayView;
  ZoomViewDisplayMode _displayMode;
  float _doubleTapZoom;
  
  UITapGestureRecognizer* _doubleTapRecognizer;
  CGSize _oldSize;
  CGSize _displaySize;
  CGPoint _focusPoint;
}
@property(nonatomic, retain) UIView* displayView;
@property(nonatomic) ZoomViewDisplayMode displayMode;  // Default is kZoomViewDisplayMode_Centered
@property(nonatomic) float doubleTapZoom;  // Default is 1.5
@property(nonatomic, readonly) UITapGestureRecognizer* doubleTapRecognizer;
+ (NSTimeInterval) defaultAnimationDuration;
- (void) setDisplayView:(UIView*)view animated:(BOOL)animated;
@end
