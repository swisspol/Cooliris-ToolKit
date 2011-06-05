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

@class GridView;

@protocol GridViewDelegate <NSObject>
@optional
- (UIView*) gridView:(GridView*)gridView viewForItem:(id)item;  // Return nil to use default view
- (void) gridViewWillStartUpdatingViewsVisibility:(GridView*)gridView;
- (void) gridView:(GridView*)gridView willShowView:(UIView*)view forItem:(id)item;
- (void) gridView:(GridView*)gridView didHideView:(UIView*)view forItem:(id)item;
- (void) gridViewDidEndUpdatingViewsVisibility:(GridView*)gridView;
- (void) gridViewDidUpdateScrollingAmount:(GridView*)gridView;
@end

// Views returned for items must have fixed dimensions
// If any item view is bigger than the GridView itself, it will be skipped
@interface GridView : UIView <UIScrollViewDelegate> {
  id<GridViewDelegate> _delegate;
  NSMutableArray* _items;
  UIEdgeInsets _contentMargins;
  UIEdgeInsets _itemSpacing;
  BOOL _itemsJustified;
  NSUInteger _extraRows;
  
  UIScrollView* _scrollView;
  UIView* _contentView;
  CGFloat _scrolling;
  NSUInteger _rowCount;
  CGRect* _rowRects;
  NSRange _visibleRows;
  NSRange _loadedRows;
}
@property(nonatomic, assign) id<GridViewDelegate> delegate;
@property(nonatomic, copy) NSArray* items;
@property(nonatomic, readonly, getter=isEmpty) BOOL empty;
@property(nonatomic, retain) UIColor* contentColor;  // Default is nil
@property(nonatomic) UIEdgeInsets contentMargins;  // Default is (10,10,10,10)
@property(nonatomic) UIEdgeInsets itemSpacing;  // Default is (4,4,4,4)
@property(nonatomic) BOOL itemsJustified;  // Default is NO
@property(nonatomic) NSUInteger extraVisibleRows;  // Default is 0
@property(nonatomic) CGFloat scrollingAmount;  // Does not call delegate when setting
@property(nonatomic, readonly) NSUInteger numberOfRows;
@property(nonatomic, readonly) NSRange visibleRows;
- (void) reloadViews;
- (void) unloadViews;
- (id) itemForItem:(id)item;  // Uses -isEqual:
- (UIView*) viewForItem:(id)item;  // Uses -isEqual:
- (id) itemAtLocation:(CGPoint)location view:(UIView**)view;
@end

@interface GridView (Subclassing)
- (UIView*) defaultViewForItem:(id)item;  // Default implementation returns nil
@end
