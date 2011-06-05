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

@class InfiniteView;

@protocol InfiniteViewDelegate <NSObject>
@optional
- (void) infiniteViewWillChangePage:(InfiniteView*)infiniteView;
- (void) infiniteViewDidChangePage:(InfiniteView*)infiniteView;
- (NSUInteger) infiniteView:(InfiniteView*)infiniteView defaultColumnForRow:(NSUInteger)row;  // Use "selectedPageRow" and "selectedPageColumn" properties
- (void) infiniteViewWillBeginSwiping:(InfiniteView*)infiniteView;
- (void) infiniteViewDidEndSwiping:(InfiniteView*)infiniteView;
- (void) infiniteView:(InfiniteView*)infiniteView willShowPageView:(UIView*)view;
- (void) infiniteView:(InfiniteView*)infiniteView didHidePageView:(UIView*)view;
@end

// Horizontal looping will be disabled if there are less than 3 columns in current row
// Vertical looping will be disabled if there are less than 3 rows
@interface InfiniteView : UIView <UIGestureRecognizerDelegate> {
@private
  id<InfiniteViewDelegate> _delegate;
  NSArray* _pageViews;
  BOOL _horizontalSwipingEnabled;
  BOOL _verticalSwipingEnabled;
  CGFloat _swipingDirectionConstraint;
  NSTimeInterval _animationDuration;
  BOOL _showSelectedOnly;
  
  UIView* _contentView;
  UIView* _overlayView;
  NSUInteger _pageRow;
  NSUInteger _pageColumn;
  CGSize _pageSize;
  NSInteger _direction;
}
@property(nonatomic, assign) id<InfiniteViewDelegate> delegate;
@property(nonatomic) BOOL hideInvisiblePageViews;  // Use "hidden" view property instead of adding / removing views dynamically - Default is NO
@property(nonatomic, copy) NSArray* pageViews;  // NSArray of NSArrays - Initial row and column are 0
@property(nonatomic) NSUInteger selectedPageRow;
@property(nonatomic) NSUInteger selectedPageColumn;
@property(nonatomic, assign) UIView* selectedPageView;
@property(nonatomic, getter=isHorizontalSwipingEnabled) BOOL horizontalSwipingEnabled;  // Default is YES
@property(nonatomic, getter=isVerticalSwipingEnabled) BOOL verticalSwipingEnabled;  // Default is YES
@property(nonatomic) CGFloat swipingDirectionConstraint;  // Affects if one direction is easier to snap to than another when swiping - Default is 1.0
@property(nonatomic) NSTimeInterval animationDuration;  // Default is 0.5
@property(nonatomic) BOOL showsOnlySelectedPage;  // Default is NO
- (void) setPageViews:(NSArray*)views initialPageRow:(NSUInteger)row initialPageColumn:(NSUInteger)column;
- (void) setSelectedPageRow:(NSUInteger)row pageColumn:(NSUInteger)column animate:(BOOL)animate;
- (void) setSelectedPageView:(UIView*)view animate:(BOOL)animate;
- (void) cancelAnimations;

// For additional gesture recognizers
- (void) panAction:(UIPanGestureRecognizer*)recognizer;
@end

@interface InfiniteView (Subclassing)
- (BOOL) isPageViewVisible:(UIView*)view;
- (void) setPageView:(UIView*)view visible:(BOOL)visible;
- (void) willChangePage;
- (void) didChangePage;
@end
