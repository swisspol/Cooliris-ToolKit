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

@interface ZoomView : UIScrollView <UIScrollViewDelegate> {
@private
  UIView* _displayView;
  BOOL _zoomsToFit;
  CGFloat _maximumScale;

  // Used in layoutSubviews to see if the dimensions have changed
  CGSize _oldSize;
  CGPoint _oldCenterPoint;
}
@property(nonatomic, retain) IBOutlet UIView* displayView;
// When enabled, smaller views will be automatically scaled up to fit the view.
// Also, when the view is rotated while at the minimum zoom level, the zoom level will be translated to the
// minimum level of the new orientation
// Default: YES
@property(nonatomic) BOOL zoomsToFit;
// The maximum level to zoom the display view. When zoomsToFit is YES the scale is treated as a factor multiplying the
// size required to fit to the edges of the zoom view
// When NO it's treated as an absolute value
// Default: 2.0
@property(nonatomic) CGFloat maximumScale;
@end
