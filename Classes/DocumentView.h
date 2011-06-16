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

@class DocumentView;

@protocol DocumentViewDelegate <NSObject>
@optional
- (void) documentViewWillBeginSwiping:(DocumentView*)infiniteView;
- (void) documentViewDidEndSwiping:(DocumentView*)infiniteView;
- (void) documentViewWillChangePage:(DocumentView*)documentView;
- (void) documentViewDidChangePage:(DocumentView*)documentView;
- (void) documentView:(DocumentView*)documentView willShowPageView:(UIView*)view;
- (void) documentView:(DocumentView*)documentView didHidePageView:(UIView*)view;
- (void) documentViewDidReachFirstPage:(DocumentView*)documentView;  // Called when the user tries to go before first page
- (void) documentViewDidReachLastPage:(DocumentView*)documentView;  // Called when the user tries to go past last page
@end

@interface DocumentView : UIView <UIGestureRecognizerDelegate> {
@private
  id<DocumentViewDelegate> _delegate;
  BOOL _hideInvisibleViews;
  NSArray* _pageViews;
  BOOL _swipingEnabled;
  NSTimeInterval _animationDuration;
  BOOL _showSelectedOnly;
  
  UIView* _contentView;
  UIView* _leftShadowView;
  UIView* _rightShadowView;
  UIView* _overlayView;
  NSUInteger _pageIndex;
  CGSize _pageSize;
  BOOL _swiping;
}
@property(nonatomic, assign) id<DocumentViewDelegate> delegate;
@property(nonatomic) BOOL hideInvisiblePageViews;  // Use "hidden" view property instead of adding / removing views dynamically - Default is YES
@property(nonatomic, copy) NSArray* pageViews;  // Initial index is 0
@property(nonatomic) NSUInteger selectedPageIndex;
@property(nonatomic, assign) UIView* selectedPageView;
@property(nonatomic, getter=isSwipingEnabled) BOOL swipingEnabled;  // Default is YES
@property(nonatomic) NSTimeInterval animationDuration;  // Default is 0.5
@property(nonatomic) BOOL showsOnlySelectedPage;  // Default is NO
- (void) setPageViews:(NSArray*)views initialPageIndex:(NSUInteger)index;
- (void) setSelectedPageIndex:(NSUInteger)index animate:(BOOL)animate;
- (void) setSelectedPageView:(UIView*)view animate:(BOOL)animate;
- (void) goToPreviousPage:(BOOL)animate;
- (void) goToNextPage:(BOOL)animate;
- (void) cancelAnimations;

// For additional gesture recognizers
- (void) panAction:(UIPanGestureRecognizer*)recognizer;
@end

@interface DocumentView (Subclassing)
- (BOOL) isPageViewVisible:(UIView*)view;
- (void) setPageView:(UIView*)view visible:(BOOL)visible;
- (void) willChangePageIndex;
- (void) didChangePageIndex;
@end
