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

@class NavigationControl, OverlayView;

@protocol NavigationControlDelegate <NSObject>
@optional
- (UIImage*) navigationControl:(NavigationControl*)control markerImageForPageAtIndex:(NSUInteger)index;  // If not implemented, "markerImage" is used
- (UIImage*) navigationControlThumbImageForCurrentPage:(NavigationControl*)control;  // If not implemented "thumbImage" is used
- (UIImage*) navigationControlThumbMarkerImageForCurrentPage:(NavigationControl*)control;  // If not implemented "thumbMarkerImage" is used
- (UIView*) navigationControlOverlayViewForCurrentPage:(NavigationControl*)control;  // If not implemented, no overlay is shown - Called only during dragging
@end

// All image dimensions are expected to be even
@interface NavigationControl : UIControl {
@private
  id<NavigationControlDelegate> _delegate;
  NSUInteger _pageCount;
  NSUInteger _markerCount;
  NSUInteger _pageIndex;
  BOOL _continuous;
  UIEdgeInsets _margins;
  CGFloat _maximumSpacing;
  UIImage* _thumbImage;
  UIColor* _thumbColor;
  UIImage* _markerImage;
  UIColor* _markerColor;
  UIImage* _thumbMarkerImage;
  UIColor* _thumbMarkerColor;
  BOOL _constrainOverlay;
  CGFloat _overlayArrowOffset;
  
  OverlayView* _overlayView;
  UIImageView* _thumbView;
  UIImageView* _markerView;
  NSMutableArray* _markerViews;
  NSUInteger _lastIndex;
}
@property(nonatomic, assign) id<NavigationControlDelegate> delegate;
@property(nonatomic) NSUInteger numberOfPages;
@property(nonatomic) NSUInteger numberOfMarkers;
@property(nonatomic) NSUInteger currentPage;  // Clamped to [0, numberOfPages - 1]
@property(nonatomic,getter=isContinuous) BOOL continuous;  // Default is YES
@property(nonatomic) UIEdgeInsets margins;  // Default is {0,0,0,0}
@property(nonatomic) CGFloat maximumSpacing;  // Default is 0 which means infinite
@property(nonatomic, retain) UIImage* thumbImage;  // If nil, default image is used
@property(nonatomic, retain) UIColor* thumbTintColor;  // Default is nil
@property(nonatomic, retain) UIImage* markerImage;  // If nil, default image is used
@property(nonatomic, retain) UIColor* markerTintColor;  // Default is nil
@property(nonatomic) BOOL thumbMarkerImageVisible;  // Default is YES
@property(nonatomic, retain) UIImage* thumbMarkerImage;  // If nil, "markerImage" is used
@property(nonatomic, retain) UIColor* thumbMarkerTintColor;  // Default is nil
@property(nonatomic, retain) UIColor* overlayTintColor;  // Default is nil
@property(nonatomic) BOOL constrainOverlayToSuperview;  // Default is NO
@property(nonatomic) CGFloat overlayArrowOffset;  // Default is 0.0
- (void) reloadAllMarkerImages;
- (void) reloadMarkerImageAtIndex:(NSUInteger)index;
@end
