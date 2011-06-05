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

#import "InfiniteView.h"
#import "BasicAnimation.h"
#import "Logging.h"

#define kPaningTolerance 0.04

enum {
  kDirection_Vertical = -1,
  kDirection_Undefined = 0,
  kDirection_Horizontal = 1
};

@implementation InfiniteView

@synthesize delegate=_delegate, hideInvisiblePageViews=_hideInvisibleViews, pageViews=_pageViews,
            horizontalSwipingEnabled=_horizontalSwipingEnabled, verticalSwipingEnabled=_verticalSwipingEnabled,
            swipingDirectionConstraint=_swipingDirectionConstraint, animationDuration=_animationDuration, selectedPageRow=_pageRow,
            selectedPageColumn=_pageColumn, showsOnlySelectedPage=_showSelectedOnly;

- (id) initWithFrame:(CGRect)frame {
  if ((self = [super initWithFrame:frame])) {
    _horizontalSwipingEnabled = YES;
    _verticalSwipingEnabled = YES;
    _swipingDirectionConstraint = 1.0;
    _animationDuration = 0.5;
    
    _contentView = [[UIView alloc] init];
    _contentView.autoresizesSubviews = NO;
    _contentView.layer.anchorPoint = CGPointZero;
    [self addSubview:_contentView];
    
    _overlayView = [[UIView alloc] init];
    _overlayView.backgroundColor = [UIColor blackColor];
    _overlayView.hidden = YES;
    _overlayView.alpha = 0.0;
    [self addSubview:_overlayView];
    
    UIPanGestureRecognizer* panRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panAction:)];
    [self addGestureRecognizer:panRecognizer];
    [panRecognizer release];
    
    _pageRow = NSNotFound;
    _pageColumn = NSNotFound;
  }
  return self;
}

- (void) _updatePageView:(UIView*)pageView visibility:(BOOL)visible {
  BOOL flag = [self isPageViewVisible:pageView];
  if (visible && !flag) {
    if ([_delegate respondsToSelector:@selector(infiniteView:willShowPageView:)]) {
      [_delegate infiniteView:self willShowPageView:pageView];
    }
    [self setPageView:pageView visible:YES];
  } else if (!visible && flag) {
    [self setPageView:pageView visible:NO];
    if ([_delegate respondsToSelector:@selector(infiniteView:didHidePageView:)]) {
      [_delegate infiniteView:self didHidePageView:pageView];
    }
  }
}

- (NSUInteger) _defaultColumnForRow:(NSUInteger)row {
  if ([_delegate respondsToSelector:@selector(infiniteView:defaultColumnForRow:)]) {
    NSUInteger index = [_delegate infiniteView:self defaultColumnForRow:row];
    DCHECK(index < [(NSArray*)[_pageViews objectAtIndex:row] count]);
    return index;
  }
  return _pageColumn % [(NSArray*)[_pageViews objectAtIndex:row] count];
}

- (void) _updatePageViewsVisibility:(NSInteger)direction {
  if (_pageViews) {
    UIView* topPage;
    if (!_showSelectedOnly && (direction != kDirection_Horizontal)) {
      if (_pageViews.count >= 3) {
        NSUInteger topRow = _pageRow > 0 ? _pageRow - 1 : _pageViews.count - 1;
        topPage = [[_pageViews objectAtIndex:topRow] objectAtIndex:[self _defaultColumnForRow:topRow]];
      } else if (_pageRow > 0) {
        topPage = [[_pageViews objectAtIndex:(_pageRow - 1)] objectAtIndex:[self _defaultColumnForRow:(_pageRow - 1)]];
      } else {
        topPage = nil;
      }
      topPage.frame = CGRectMake(0.0, -_pageSize.height, _pageSize.width, _pageSize.height);
    } else {
      topPage = nil;
    }
    
    NSArray* array = [_pageViews objectAtIndex:_pageRow];
    UIView* leftPage;
    if (!_showSelectedOnly && (direction != kDirection_Vertical)) {
      if (array.count >= 3) {
        leftPage = [array objectAtIndex:(_pageColumn > 0 ? _pageColumn - 1 : array.count - 1)];
      } else if (_pageColumn > 0) {
        leftPage = [array objectAtIndex:(_pageColumn - 1)];
      } else {
        leftPage = nil;
      }
      leftPage.frame = CGRectMake(-_pageSize.width, 0.0, _pageSize.width, _pageSize.height);
    } else {
      leftPage = nil;
    }
    UIView* centerPage = [array objectAtIndex:_pageColumn];
    centerPage.frame = CGRectMake(0.0, 0.0, _pageSize.width, _pageSize.height);
    UIView* rightPage;
    if (!_showSelectedOnly && (direction != kDirection_Vertical)) {
      if (array.count >= 3) {
        rightPage = [array objectAtIndex:(_pageColumn < array.count - 1 ? _pageColumn + 1 : 0)];
      } else if (_pageColumn < array.count - 1) {
        rightPage = [array objectAtIndex:(_pageColumn + 1)];
      } else {
        rightPage = nil;
      }
      rightPage.frame = CGRectMake(_pageSize.width, 0.0, _pageSize.width, _pageSize.height);
    } else {
      rightPage = nil;
    }
    
    UIView* bottomPage;
    if (!_showSelectedOnly && (direction != kDirection_Horizontal)) {
      if (_pageViews.count >= 3) {
        NSUInteger bottomRow = _pageRow < _pageViews.count - 1 ? _pageRow + 1 : 0;
        bottomPage = [[_pageViews objectAtIndex:bottomRow] objectAtIndex:[self _defaultColumnForRow:bottomRow]];
      } else if (_pageRow < _pageViews.count - 1) {
        bottomPage = [[_pageViews objectAtIndex:(_pageRow + 1)] objectAtIndex:[self _defaultColumnForRow:(_pageRow + 1)]];
      } else {
        bottomPage = nil;
      }
      bottomPage.frame = CGRectMake(0.0, _pageSize.height, _pageSize.width, _pageSize.height);
    } else {
      bottomPage = nil;
    }
    
    for (NSArray* array in _pageViews) {
      for (UIView* page in array) {
        if ((page == topPage) || (page == leftPage) || (page == centerPage) || (page == rightPage) || (page == bottomPage)) {
          [self _updatePageView:page visibility:YES];
        } else {
          [self _updatePageView:page visibility:NO];
        }
      }
    }
  }
}

- (void) setPageViews:(NSArray*)views {
  [self setPageViews:views initialPageRow:0 initialPageColumn:0];
}

- (void) setPageViews:(NSArray*)views initialPageRow:(NSUInteger)row initialPageColumn:(NSUInteger)column {
  if (views != _pageViews) {
    if ([_delegate respondsToSelector:@selector(infiniteViewWillChangePage:)]) {
      [_delegate infiniteViewWillChangePage:self];
    }
    
    for (NSArray* array in _pageViews) {
      for (UIView* view in array) {
        [self setPageView:view visible:NO];
        if (_hideInvisibleViews) {
          [view removeFromSuperview];
        }
      }
    }
    [_pageViews release];
    _pageViews = views.count ? [views copy] : nil;
    for (NSArray* array in _pageViews) {
      CHECK(array.count);
      for (UIView* view in array) {
        if (_hideInvisibleViews) {
          [_contentView addSubview:view];
        }
        [self setPageView:view visible:NO];
      }
    }
    
    if (_pageViews) {
      _pageRow = MIN(_pageViews.count - 1, row);
      _pageColumn = MIN([(NSArray*)[_pageViews objectAtIndex:_pageRow] count] - 1, column);
    } else {
      _pageRow = NSNotFound;
      _pageColumn = NSNotFound;
    }
    
    [self layoutSubviews];
    
    if ([_delegate respondsToSelector:@selector(infiniteViewDidChangePage:)]) {
      [_delegate infiniteViewDidChangePage:self];
    }
  }
}

- (UIView*) selectedPageView {
  return _pageViews ? [[_pageViews objectAtIndex:_pageRow] objectAtIndex:_pageColumn] : nil;
}

- (void) setSelectedPageView:(UIView*)view {
  [self setSelectedPageView:view animate:NO];
}

- (void) setSelectedPageView:(UIView*)view animate:(BOOL)animate {
  NSUInteger row = NSNotFound;
  NSUInteger column = NSNotFound;
  for (NSUInteger i = 0; i < _pageViews.count; ++i) {
    NSUInteger index = [(NSArray*)[_pageViews objectAtIndex:i] indexOfObject:view];
    if (index != NSNotFound) {
      row = i;
      column = index;
      break;
    }
  }
  [self setSelectedPageRow:row pageColumn:column animate:animate];
}

- (void) layoutSubviews {
  CGRect bounds = self.bounds;
  
  _contentView.frame = bounds;
  _overlayView.frame = bounds;
  
  _pageSize = bounds.size;
  [self _updatePageViewsVisibility:kDirection_Undefined];
}

- (void) setSelectedPageRow:(NSUInteger)row {
  [self setSelectedPageRow:row pageColumn:_pageColumn animate:NO];
}

- (void) setSelectedPageColumn:(NSUInteger)column {
  [self setSelectedPageRow:_pageRow pageColumn:column animate:NO];
}

- (void) setShowsOnlySelectedPage:(BOOL)flag {
  if (flag != _showSelectedOnly) {
    _showSelectedOnly = flag;
    
    [self _updatePageViewsVisibility:kDirection_Undefined];
  }
}

- (void) _didFadeOut:(NSString*)animationID finished:(NSNumber*)finished context:(void*)context {
  _overlayView.hidden = YES;
  
  [[UIApplication sharedApplication] endIgnoringInteractionEvents];
}

- (void) _didFadeIn:(NSString*)animationID finished:(NSNumber*)finished context:(void*)context {
  _pageRow = [(NSIndexPath*)context row];
  _pageColumn = [(NSIndexPath*)context section];
  [(NSIndexPath*)context release];
  [self _updatePageViewsVisibility:kDirection_Undefined];
  
  [self didChangePage];
  
  [UIView beginAnimations:nil context:nil];
  [UIView setAnimationDuration: _animationDuration / 2.0];
  [UIView setAnimationDelegate:self];
  [UIView setAnimationDidStopSelector:@selector(_didFadeOut:finished:context:)];
  _overlayView.alpha = 0.0;
  [UIView commitAnimations];
}

- (void) setSelectedPageRow:(NSUInteger)row pageColumn:(NSUInteger)column animate:(BOOL)animate {
  if ((row != _pageRow) || (column != _pageColumn)) {
    CHECK(row < _pageViews.count);
    CHECK(column < [(NSArray*)[_pageViews objectAtIndex:row] count]);
    
    [self willChangePage];
    
    if (animate) {  // Disables user interaction during the animation
      _overlayView.hidden = NO;
      [UIView beginAnimations:nil context:[[NSIndexPath indexPathForRow:row inSection:column] retain]];
      [UIView setAnimationDuration: _animationDuration / 2.0];
      [UIView setAnimationDelegate:self];
      [UIView setAnimationDidStopSelector:@selector(_didFadeIn:finished:context:)];
      _overlayView.alpha = 1.0;
      [UIView commitAnimations];
     
      [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
    } else {
      _pageRow = row;
      _pageColumn = column;
      [self _updatePageViewsVisibility:kDirection_Undefined];
      
      [self didChangePage];
    }
  }
}

- (void) cancelAnimations {
  DCHECK(_direction == kDirection_Undefined);
  if ([_contentView.layer animationForKey:@"position"]) {
    _contentView.layer.position = CGPointMake(0.0, 0.0);
    [self _updatePageViewsVisibility:kDirection_Undefined];
    [_contentView.layer removeAnimationForKey:@"position"];
  }
}

- (void) animationDidStop:(CAAnimation*)animation finished:(BOOL)finished {
  if (finished) {
    _contentView.layer.position = CGPointMake(0.0, 0.0);
    [self _updatePageViewsVisibility:kDirection_Undefined];
  }
}

- (void) panAction:(UIPanGestureRecognizer*)recognizer {
  switch (recognizer.state) {
    
    // Gesture has started or is updating
    case UIGestureRecognizerStateChanged: {
      CGPoint offset = [recognizer translationInView:recognizer.view];
      
      // Make sure there is a translation and compute its direction
      if (_direction == kDirection_Undefined) {
        CGFloat dx = fabsf(offset.x);
        CGFloat dy = fabsf(offset.y);
        if ((dx < 1.0) && (dy < 1.0)) {
          break;
        }
        if (dy > _swipingDirectionConstraint * dx) {
          if (!_verticalSwipingEnabled) {
            break;
          }
          _direction = kDirection_Vertical;
        } else {
          if (!_horizontalSwipingEnabled) {
            break;
          }
          _direction = kDirection_Horizontal;
        }
        if ([_delegate respondsToSelector:@selector(infiniteViewWillBeginSwiping:)]) {
          [_delegate infiniteViewWillBeginSwiping:self];
        }
        
        // If there is an animation from the previous swipe currently running, cancel it and update pane visibility
        if ([_contentView.layer animationForKey:@"position"]) {
          [self _updatePageViewsVisibility:_direction];
          [_contentView.layer removeAnimationForKey:@"position"];
        }
      }
      
      // Translate content view
      if (_direction == kDirection_Horizontal) {
        _contentView.layer.position = CGPointMake(offset.x, 0.0);
      } else {
        _contentView.layer.position = CGPointMake(0.0, offset.y);
      }
      break;
    }
    
    // Gesture has ended or has been cancelled
    case UIGestureRecognizerStateEnded:
    case UIGestureRecognizerStateCancelled: {
      BOOL cancelled = recognizer.state == UIGestureRecognizerStateCancelled ? YES : NO;
      CGPoint offset = [recognizer translationInView:recognizer.view];
      
      // In case of horizontal translation, animate to newly selected UIView or bounce-back to current one
      if (_direction == kDirection_Horizontal) {
        NSUInteger index = _pageColumn;
        NSUInteger max = [(NSArray*)[_pageViews objectAtIndex:_pageRow] count];
        CGFloat position = 0.0;
        if (offset.x > 0.0) {
          if (!cancelled && (offset.x > _pageSize.width * kPaningTolerance) && ((max >= 3) || (index > 0))) {
            index = index > 0 ? index - 1 : max - 1;
            position = _pageSize.width;
          }
        } else {
          if (!cancelled && (-offset.x > _pageSize.width * kPaningTolerance) && ((max >= 3) || (index < max - 1))) {
            index = index < max - 1 ? index + 1 : 0;
            position = -_pageSize.width;
          }
        }
        if (position) {
          [self willChangePage];
          _pageColumn = index;
        }
        CABasicAnimation* animation = [CABasicAnimation animation];
        animation.delegate = self;
        animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionDefault];
        animation.duration = _animationDuration;
        [_contentView.layer addAnimation:animation forKey:@"position"];
        _contentView.layer.position = CGPointMake(position, 0.0);
        if (position) {
          [self didChangePage];
        }
      }
      
      // In case of vertical translation, animate to newly selected UIView or bounce-back to current one
      else if (_direction == kDirection_Vertical) {
        NSUInteger index = _pageRow;
        NSUInteger max = _pageViews.count;
        CGFloat position = 0.0;
        if (offset.y > 0.0) {
          if (!cancelled && (offset.y > _pageSize.height * kPaningTolerance) && ((max >= 3) || (index > 0))) {
            index = index > 0 ? index - 1 : max - 1;
            position = _pageSize.height;
          }
        } else {
          if (!cancelled && (-offset.y > _pageSize.height * kPaningTolerance) && ((max >= 3) || (index < max - 1))) {
            index = index < max - 1 ? index + 1 : 0;
            position = -_pageSize.height;
          }
        }
        if (position) {
          [self willChangePage];
          _pageColumn = [self _defaultColumnForRow:index];
          _pageRow = index;
        }
        CABasicAnimation* animation = [CABasicAnimation animation];
        animation.delegate = self;
        animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionDefault];
        animation.duration = _animationDuration;
        [_contentView.layer addAnimation:animation forKey:@"position"];
        _contentView.layer.position = CGPointMake(0.0, position);
        if (position) {
          [self didChangePage];
        }
      }
      
      // Reset translation direction
      _direction = kDirection_Undefined;
      if ([_delegate respondsToSelector:@selector(infiniteViewDidEndSwiping:)]) {
        [_delegate infiniteViewDidEndSwiping:self];
      }
      break;
    }
    
    default:
      break;
    
  }
}

@end

@implementation InfiniteView (Subclassing)

- (BOOL) isPageViewVisible:(UIView*)view {
  if (_hideInvisibleViews) {
    return !view.hidden;
  } else {
    return view.superview ? YES : NO;
  }
}

- (void) setPageView:(UIView*)view visible:(BOOL)visible {
  if (_hideInvisibleViews) {
    view.hidden = !visible;
  } else {
    if (visible && !view.superview) {
      [_contentView addSubview:view];
    } else if (!visible && view.superview) {
      [view removeFromSuperview];
    }
  }
}

- (void) willChangePage {
  if ([_delegate respondsToSelector:@selector(infiniteViewWillChangePage:)]) {
    [_delegate infiniteViewWillChangePage:self];
  }
}

- (void) didChangePage {
  if ([_delegate respondsToSelector:@selector(infiniteViewDidChangePage:)]) {
    [_delegate infiniteViewDidChangePage:self];
  }
}

@end
