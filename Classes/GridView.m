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

#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

#import "GridView.h"
#import "Extensions_UIKit.h"
#import "Logging.h"

#define kDefaultContentMargin 10.0
#define kDefaultItemSpacing 4.0

@interface GridItem : NSObject {
@private
  id _item;
  UIView* _view;
  NSUInteger _row;
}
@property(nonatomic, readonly) id item;
@property(nonatomic, retain) UIView* view;
@property(nonatomic) NSUInteger row;
- (id) initWithItem:(id)item;
@end

@interface GridView ()
- (void) _updateVisibleRows:(BOOL)force;
@end

static BOOL _showBorders = NO;

@implementation GridItem

@synthesize item=_item, view=_view, row=_row;

- (id) initWithItem:(id)item {
  if ((self = [super init])) {
    _item = [item retain];
  }
  return self;
}

- (void) dealloc {
  [_item release];
  [_view release];
  
  [super dealloc];
}

@end

@implementation GridView

@synthesize delegate=_delegate, items=_items, contentMargins=_contentMargins, itemSpacing=_itemSpacing, itemsJustified=_itemsJustified,
            extraVisibleRows=_extraRows, numberOfRows=_rowCount, visibleRows=_visibleRows, scrollingAmount=_scrolling;

+ (void) load {
  if (getenv("showGridBorders")) {
    _showBorders = YES;
  }
}

- (void) _initialize {
  _contentMargins = UIEdgeInsetsMake(kDefaultContentMargin, kDefaultContentMargin, kDefaultContentMargin, kDefaultContentMargin);
  _itemSpacing = UIEdgeInsetsMake(kDefaultItemSpacing, kDefaultItemSpacing, kDefaultItemSpacing, kDefaultItemSpacing);
  
  _scrollView = [[UIScrollView alloc] init];
  _scrollView.delegate = self;
  _scrollView.alwaysBounceVertical = YES;
  [self addSubview:_scrollView];
  _contentView = [[UIView alloc] init];
  [_scrollView addSubview:_contentView];
  
  [self setContentColor:nil];
  
  if (_showBorders) {
    UIView* view = [[UIView alloc] init];
    view.layer.borderColor = [[UIColor greenColor] CGColor];
    view.layer.borderWidth = 1.0;
    view.userInteractionEnabled = NO;
    [self addSubview:view];
    objc_setAssociatedObject(self, [GridView class], view, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [view release];
  }
}

- (id) initWithFrame:(CGRect)frame {
  if ((self = [super initWithFrame:frame])) {
    [self _initialize];
  }
  return self;
}

- (void) dealloc {
  if (_showBorders) {
    objc_setAssociatedObject(self, [GridView class], nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  }
  
  if (_rowRects) {
    free(_rowRects);
  }
  [_items release];
  [_contentView release];
  [_scrollView release];
  
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

- (void) setItems:(NSArray*)items {
  for (GridItem* item in _items) {
    [item.view removeFromSuperview];
  }
  [_items release];
  if (items.count) {
    _items = [[NSMutableArray alloc] initWithCapacity:items.count];
    for (id object in items) {
      GridItem* item = [[GridItem alloc] initWithItem:object];
      [_items addObject:item];
      [item release];
    }
  } else {
    _items = nil;
  }
  
  [self reloadViews];
}

- (NSArray*) items {
  if (_items) {
    NSMutableArray* array = [NSMutableArray arrayWithCapacity:_items.count];
    for (GridItem* item in _items) {
      [array addObject:item.item];
    }
    return array;
  }
  return nil;
}

- (BOOL) isEmpty {
  return _items ? NO : YES;
}

- (void) setContentColor:(UIColor*)color {
  // Using -[CALayer backgroundColor] uses way less Core Animation memory than -[UIView backgroundColor] (radr://8370398)
  if (color) {
    _contentView.hidden = NO;
    _contentView.layer.backgroundColor = [color CGColor];
    self.layer.backgroundColor = nil;
  } else {
    _contentView.hidden = YES;
    _contentView.layer.backgroundColor = nil;
    self.layer.backgroundColor = [[UIColor backgroundColorWithPatternImage:[UIImage imageNamed:@"GridView-Background.png"]] CGColor];
  }
}

- (UIColor*) contentColor {
  return _contentView.backgroundColor;
}

- (void) setExtraVisibleRows:(NSUInteger)rows {
  if (rows != _extraRows) {
    _extraRows = rows;
    
    [self _updateVisibleRows:YES];
  }
}

- (void) setScrollingAmount:(CGFloat)amount {
  _scrollView.contentOffset = CGPointMake(0.0, amount);
  _scrolling = _scrollView.contentOffset.y;
}

- (void) _updateScrolling {
  _scrolling = _scrollView.contentOffset.y;
  if ([_delegate respondsToSelector:@selector(gridViewDidUpdateScrollingAmount:)]) {
    [_delegate gridViewDidUpdateScrollingAmount:self];
  }
}

- (void) _updateVisibleRows:(BOOL)force {
  if (force) {
    _visibleRows.location = NSNotFound;
    _visibleRows.length = 0;
    _loadedRows.location = NSNotFound;
    _loadedRows.length = 0;
  }
  NSRange oldVisibleRows = _visibleRows;
  
  CGRect bounds = _scrollView.bounds;
  _visibleRows.location = NSNotFound;
  _visibleRows.length = 0;
  for (NSUInteger i = 0; i < _rowCount; ++i) {
    if (_rowRects[i].origin.y + _rowRects[i].size.height >= bounds.origin.y) {
      _visibleRows.location = i;
      _visibleRows.length = 1;
      for (++i; i < _rowCount; ++i) {
        if (_rowRects[i].origin.y >= bounds.origin.y + bounds.size.height) {
          break;
        }
        _visibleRows.length += 1;
      }
      break;
    }
  }
  
  if ((_visibleRows.location != oldVisibleRows.location) || (_visibleRows.length != oldVisibleRows.length)) {
    if ((_loadedRows.location == NSNotFound) || (_extraRows == 0) ||
      (_visibleRows.location + _visibleRows.length + _extraRows / 2 > _loadedRows.location + _loadedRows.length) ||
      (_visibleRows.location < _loadedRows.location + _extraRows / 2)) {
      _loadedRows.location = _visibleRows.location > _extraRows ? _visibleRows.location - _extraRows : 0;
      _loadedRows.length = MIN(_visibleRows.location + _visibleRows.length + _extraRows, _rowCount) - _loadedRows.location;
      if ([_delegate respondsToSelector:@selector(gridViewWillStartUpdatingViewsVisibility:)]) {
        [_delegate gridViewWillStartUpdatingViewsVisibility:self];
      }
      
      BOOL hasShowDelegate = [_delegate respondsToSelector:@selector(gridView:willShowView:forItem:)];
      BOOL hasHideDelegate = [_delegate respondsToSelector:@selector(gridView:didHideView:forItem:)];
      for (GridItem* item in (_visibleRows.location >= oldVisibleRows.location ? [_items objectEnumerator]
                                                                               : [_items reverseObjectEnumerator])) {
        if ((item.row >= _loadedRows.location) && (item.row < _loadedRows.location + _loadedRows.length)) {
          if (item.view.hidden == YES) {
            if (hasShowDelegate) {
              [_delegate gridView:self willShowView:item.view forItem:item.item];
            }
            item.view.hidden = NO;
          }
        } else {
          if (item.view.hidden == NO) {
            if (hasHideDelegate) {
              [_delegate gridView:self didHideView:item.view forItem:item.item];
            }
            item.view.hidden = YES;
          }
        }
      }
      
      if ([_delegate respondsToSelector:@selector(gridViewDidEndUpdatingViewsVisibility:)]) {
        [_delegate gridViewDidEndUpdatingViewsVisibility:self];
      }
      LOG_DEBUG(@"Items = %i | Visible rows = %@ | Loaded rows = %@", _items.count, NSStringFromRange(_visibleRows),
                  NSStringFromRange(_loadedRows));
    }
  }
}

- (void) _updateSubviews {
  CGSize viewportSize = _scrollView.bounds.size;
  
  if (_rowRects) {
    free(_rowRects);
  }
  NSUInteger maxRows = 256;
  _rowRects = malloc(maxRows * sizeof(CGRect));
  _rowCount = 0;
  
  if ((viewportSize.width > 0.0) && (viewportSize.height > 0.0)) {
    CGFloat maxWidth = viewportSize.width - _contentMargins.left - _contentMargins.right;
    CGFloat totalHeight = 0.0;
    CGRect rect = CGRectMake(_contentMargins.left, _contentMargins.top + _itemSpacing.top, 0.0, 0.0);
    NSMutableArray* currentRow = [[NSMutableArray alloc] init];
    for (GridItem* item in _items) {
      UIView* view = item.view;
      rect.size = view.frame.size;
      if (view && (rect.size.width > 0.0) && (rect.size.height > 0.0) && (rect.size.width <= maxWidth)) {
        if (_rowCount == 0) {
          _rowRects[_rowCount].origin.x = rect.origin.x;
          _rowRects[_rowCount].origin.y = rect.origin.y;
          _rowRects[_rowCount].size.width = viewportSize.width;
          _rowRects[_rowCount].size.height = 0.0;
          _rowCount = 1;
        }
        
        if (rect.origin.x + rect.size.width + _contentMargins.right > viewportSize.width) {
          if (_itemsJustified) {
            CGFloat totalWidth = rect.origin.x - _itemSpacing.right;
            CGFloat spacing = floorf((maxWidth - totalWidth) / (CGFloat)(currentRow.count - 1));
            if (spacing > 0.0) {
              CGFloat offset = 0.0;
              for (GridItem* item in currentRow) {
                item.view.frame = CGRectOffset(item.view.frame, offset, 0.0);
                offset += spacing;
              }
            }
          }
          
          rect.origin.x = _contentMargins.left;
          rect.origin.y += _rowRects[_rowCount - 1].size.height + _itemSpacing.bottom + _itemSpacing.top;
          
          if (_rowCount + 1 >= maxRows) {
            maxRows *= 2;
            _rowRects = realloc(_rowRects, maxRows * sizeof(CGRect));
          }
          _rowRects[_rowCount].origin.x = rect.origin.x;
          _rowRects[_rowCount].origin.y = rect.origin.y;
          _rowRects[_rowCount].size.width = viewportSize.width;
          _rowRects[_rowCount].size.height = 0.0;
          _rowCount += 1;
          
          [currentRow removeAllObjects];
        }
        rect.origin.x += _itemSpacing.left;
        view.frame = rect;
        rect.origin.x += rect.size.width + _itemSpacing.right;
        if (rect.size.height > _rowRects[_rowCount - 1].size.height) {
          _rowRects[_rowCount - 1].size.height = rect.size.height;
        }
        totalHeight = rect.origin.y + _rowRects[_rowCount - 1].size.height + _itemSpacing.bottom + _contentMargins.bottom;
        
        [currentRow addObject:item];
        item.row = _rowCount - 1;
        
        if (_showBorders) {
          view.layer.borderColor = [[UIColor redColor] CGColor];
          view.layer.borderWidth = 1.0;
        }
      } else {
        item.row = NSNotFound;
      }
    }
    [currentRow release];
    _contentView.frame = CGRectMake(0.0, -viewportSize.height, viewportSize.width,
                                    2.0 * viewportSize.height + MAX(viewportSize.height, totalHeight));
    _scrollView.contentSize = CGSizeMake(viewportSize.width, MAX(viewportSize.height, totalHeight));
    _scrollView.contentOffset = CGPointMake(0.0, MAX(MIN(_scrolling, _scrollView.contentSize.height - viewportSize.height), 0.0));
    [self _updateScrolling];
  }
  
  [self _updateVisibleRows:YES];
  
  if (_showBorders) {
    UIView* view = (UIView*)objc_getAssociatedObject(self, [GridView class]);
    view.frame = CGRectMake(_contentMargins.left, _contentMargins.top,
                            viewportSize.width - _contentMargins.left - _contentMargins.right,
                            viewportSize.height - _contentMargins.top - _contentMargins.bottom);
  }
}

- (void) reloadViews {
  for (GridItem* item in _items) {
    if (item.view) {
      [item.view removeFromSuperview];
      item.view = nil;
    }
  }
  
  BOOL hasDelegate = [_delegate respondsToSelector:@selector(gridView:viewForItem:)];
  for (GridItem* item in _items) {
    UIView* view = hasDelegate ? [_delegate gridView:self viewForItem:item.item] : nil;
    if (view == nil) {
      view = [self defaultViewForItem:item.item];
    }
    if (view) {
      view.hidden = YES;
      item.view = view;
      [_scrollView addSubview:view];
    }
  }
  
  [self _updateSubviews];
}

- (void) unloadViews {
  for (GridItem* item in _items) {
    if (item.view) {
      [item.view removeFromSuperview];
      item.view = nil;
    }
  }
  
  [self _updateSubviews];
}

- (id) itemForItem:(id)item {
  for (GridItem* gridItem in _items) {
    if ([gridItem.item isEqual:item]) {
      return gridItem.item;
    }
  }
  return nil;
}

- (UIView*) viewForItem:(id)item {
  for (GridItem* gridItem in _items) {
    if ([gridItem.item isEqual:item]) {
      return gridItem.view;
    }
  }
  return nil;
}

- (id) itemAtLocation:(CGPoint)location view:(UIView**)view {
  location = [self convertPoint:location toView:_scrollView];
  for (GridItem* item in _items) {
    UIView* aView = item.view;
    if (aView && CGRectContainsPoint(aView.frame, location)) {
      if (view) {
        *view = aView;
      }
      return item.item;
    }
  }
  return nil;
}

- (void) layoutSubviews {
  if (!CGRectEqualToRect(_scrollView.frame, self.bounds)) {
    _scrollView.frame = self.bounds;
    [self _updateSubviews];
  }
}

- (void) scrollViewDidScroll:(UIScrollView*)scrollView {
  [self _updateVisibleRows:NO];
}

- (void) scrollViewDidEndDragging:(UIScrollView*)scrollView willDecelerate:(BOOL)decelerate {
  if (decelerate == NO) {
    [self _updateScrolling];
  }
}

- (void) scrollViewDidEndDecelerating:(UIScrollView*)scrollView {
  [self _updateScrolling];
}

@end

@implementation GridView (Subclassing)

- (UIView*) defaultViewForItem:(id)item {
  return nil;
}

@end
