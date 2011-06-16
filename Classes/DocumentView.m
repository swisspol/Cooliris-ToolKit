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

#import "DocumentView.h"
#import "BasicAnimation.h"
#import "Logging.h"

#define kPaningTolerance 0.04
#define kShadowSize 16.0

@implementation DocumentView

@synthesize delegate=_delegate, hideInvisiblePageViews=_hideInvisibleViews, pageViews=_pageViews, swipingEnabled=_swipingEnabled,
            animationDuration=_animationDuration, selectedPageIndex=_pageIndex, showsOnlySelectedPage=_showSelectedOnly;

- (BOOL) gestureRecognizerShouldBegin:(UIGestureRecognizer*)gestureRecognizer {
  return _pageViews && _swipingEnabled ? YES : NO;
}

- (void) _initialize {
  _hideInvisibleViews = YES;
  _swipingEnabled = YES;
  _animationDuration = 0.5;
  
  _contentView = [[UIView alloc] init];
  _contentView.autoresizesSubviews = NO;
  _contentView.layer.anchorPoint = CGPointZero;
  [self addSubview:_contentView];
  
  _leftShadowView = [[UIView alloc] init];
  _leftShadowView.layer.contents = (id)[[UIImage imageNamed:@"DocumentView-Shadow-Left.png"] CGImage];
  _leftShadowView.layer.contentsGravity = kCAGravityResize;
  [_contentView addSubview:_leftShadowView];
  
  _rightShadowView = [[UIView alloc] init];
  _rightShadowView.layer.contents = (id)[[UIImage imageNamed:@"DocumentView-Shadow-Right.png"] CGImage];
  _rightShadowView.layer.contentsGravity = kCAGravityResize;
  [_contentView addSubview:_rightShadowView];
  
  _overlayView = [[UIView alloc] init];
  _overlayView.backgroundColor = [UIColor blackColor];
  _overlayView.hidden = YES;
  _overlayView.alpha = 0.0;
  [self addSubview:_overlayView];
  
  UIPanGestureRecognizer* panRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panAction:)];
  panRecognizer.delegate = self;
  [self addGestureRecognizer:panRecognizer];
  [panRecognizer release];
  
  self.backgroundColor = [UIColor grayColor];
  
  _pageIndex = NSNotFound;
}

- (id) initWithFrame:(CGRect)frame {
  if ((self = [super initWithFrame:frame])) {
    [self _initialize];
  }
  return self;
}

- (void) dealloc {
  [_pageViews release];
  [_contentView release];
  [_leftShadowView release];
  [_rightShadowView release];
  [_overlayView release];
  
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

- (void) _updatePageView:(UIView*)pageView visibility:(BOOL)visible {
  BOOL flag = [self isPageViewVisible:pageView];
  if (visible && !flag) {
    if ([_delegate respondsToSelector:@selector(documentView:willShowPageView:)]) {
      [_delegate documentView:self willShowPageView:pageView];
    }
    [self setPageView:pageView visible:YES];
  } else if (!visible && flag) {
    [self setPageView:pageView visible:NO];
    if ([_delegate respondsToSelector:@selector(documentView:didHidePageView:)]) {
      [_delegate documentView:self didHidePageView:pageView];
    }
  }
}

- (void) _updatePageViewsVisibility {
  if (_showSelectedOnly) {
    for (NSUInteger i = 0; i < _pageViews.count; ++i) {
      if (i == _pageIndex) {
        [self _updatePageView:[_pageViews objectAtIndex:i] visibility:YES];
      } else {
        [self _updatePageView:[_pageViews objectAtIndex:i] visibility:NO];
      }
    }
  } else {
    if (_pageViews.count > 3) {
      for (NSUInteger i = 0; i < _pageViews.count; ++i) {
        if ((i + 1 == _pageIndex) || (i == _pageIndex) || (i == _pageIndex + 1)) {
          [self _updatePageView:[_pageViews objectAtIndex:i] visibility:YES];
        } else {
          [self _updatePageView:[_pageViews objectAtIndex:i] visibility:NO];
        }
      }
    } else {
      for (UIView* pageView in _pageViews) {
        [self _updatePageView:pageView visibility:YES];
      }
    }
  }
}

- (void) setPageViews:(NSArray*)views {
  [self setPageViews:views initialPageIndex:0];
}

- (void) setPageViews:(NSArray*)views initialPageIndex:(NSUInteger)index {
  if (views != _pageViews) {
    if ([_delegate respondsToSelector:@selector(documentViewWillChangePage:)]) {
      [_delegate documentViewWillChangePage:self];
    }
    
    for (UIView* view in _pageViews) {
      [self setPageView:view visible:NO];
      if (_hideInvisibleViews) {
        [view removeFromSuperview];
      }
    }
    [_pageViews release];
    _pageViews = views.count ? [views copy] : nil;
    for (UIView* view in _pageViews) {
      if (_hideInvisibleViews) {
        [_contentView addSubview:view];
      }
      [self setPageView:view visible:NO];
    }
    
    _pageIndex = _pageViews ? MIN(_pageViews.count - 1, index) : NSNotFound;
    
    [self layoutSubviews];  // We cannot use -setNeedsLayout as layout must be already done in -_updatePageViewsVisibility
    
    [self _updatePageViewsVisibility];
    
    if ([_delegate respondsToSelector:@selector(documentViewDidChangePage:)]) {
      [_delegate documentViewDidChangePage:self];
    }
  }
}

- (UIView*) selectedPageView {
  return [_pageViews objectAtIndex:_pageIndex];
}

- (void) setSelectedPageView:(UIView*)view {
  [self setSelectedPageView:view animate:NO];
}

- (void) setSelectedPageView:(UIView*)view animate:(BOOL)animate {
  NSUInteger index = _pageViews ? [_pageViews indexOfObject:view] : NSNotFound;
  [self setSelectedPageIndex:index animate:animate];
}

- (void) layoutSubviews {
  CGRect bounds = self.bounds;
  
  _pageSize = bounds.size;
  
  if (_pageViews) {
    CGFloat totalWidth = (CGFloat)_pageViews.count * _pageSize.width;
    _contentView.frame = CGRectMake(-(CGFloat)_pageIndex * _pageSize.width, 0.0, totalWidth, _pageSize.height);
    for (NSUInteger i = 0; i < _pageViews.count; ++i) {
      UIView* view = [_pageViews objectAtIndex:i];
      view.frame = CGRectMake((CGFloat)i * _pageSize.width, 0.0, _pageSize.width, _pageSize.height);
    }
    
    _leftShadowView.hidden = NO;
    _leftShadowView.frame = CGRectMake(-kShadowSize, 0.0, kShadowSize, _pageSize.height);
    _rightShadowView.hidden = NO;
    _rightShadowView.frame = CGRectMake(totalWidth, 0.0, kShadowSize, _pageSize.height);
  } else {
    _leftShadowView.hidden = YES;
    _rightShadowView.hidden = YES;
  }
  
  _overlayView.frame = bounds;
}

- (void) setSelectedPageIndex:(NSUInteger)index {
  [self setSelectedPageIndex:index animate:NO];
}

- (void) setShowsOnlySelectedPage:(BOOL)flag {
  if (flag != _showSelectedOnly) {
    _showSelectedOnly = flag;
    
    [self _updatePageViewsVisibility];
  }
}

- (void) _didFadeOut:(NSString*)animationID finished:(NSNumber*)finished context:(void*)context {
  _overlayView.hidden = YES;
  
  [[UIApplication sharedApplication] endIgnoringInteractionEvents];
}

- (void) _didFadeIn:(NSString*)animationID finished:(NSNumber*)finished context:(void*)number {
  _pageIndex = [(NSNumber*)number integerValue];
  [(NSNumber*)number release];
  [self _updatePageViewsVisibility];
  _contentView.layer.position = CGPointMake(-(CGFloat)_pageIndex * _pageSize.width, 0.0);
  
  [self didChangePageIndex];
  
  [UIView beginAnimations:nil context:nil];
  [UIView setAnimationDuration:_animationDuration / 2.0];
  [UIView setAnimationDidStopSelector:@selector(_didFadeOut:finished:context:)];
  [UIView setAnimationDelegate:self];
  _overlayView.alpha = 0.0;
  [UIView commitAnimations];
}

- (void) setSelectedPageIndex:(NSUInteger)index animate:(BOOL)animate {
  if (index != _pageIndex) {
    CHECK(index < _pageViews.count);
    
    [self willChangePageIndex];
    
    if (animate) {  // Disables user interaction during the animation
      _overlayView.hidden = NO;
      [UIView beginAnimations:nil context:[[NSNumber alloc] initWithInteger:index]];
      [UIView setAnimationDuration:_animationDuration / 2.0];
      [UIView setAnimationDelegate:self];
      [UIView setAnimationDidStopSelector:@selector(_didFadeIn:finished:context:)];
      _overlayView.alpha = 1.0;
      [UIView commitAnimations];
      
      [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
    } else {
      _pageIndex = index;
      [self _updatePageViewsVisibility];
      _contentView.layer.position = CGPointMake(-(CGFloat)_pageIndex * _pageSize.width, 0.0);
      
      [self didChangePageIndex];
    }
  }
}

- (void) cancelAnimations {
  if ([_contentView.layer animationForKey:@"position"]) {
    [self _updatePageViewsVisibility];
    [_contentView.layer removeAnimationForKey:@"position"];
  }
}

- (void) animationDidStop:(CAAnimation*)animation finished:(BOOL)finished {
  if (finished) {
    [self _updatePageViewsVisibility];
  }
}

- (void) panAction:(UIPanGestureRecognizer*)recognizer {
  switch (recognizer.state) {
    
    // Gesture has started or is updating
    case UIGestureRecognizerStateChanged: {
      CGPoint offset = [recognizer translationInView:self];
      
      // Make sure there is a translation
      if (_swiping == NO) {
        if ((fabsf(offset.x) < 1.0) && (fabsf(offset.y) < 1.0)) {
          break;
        }
        if ([_delegate respondsToSelector:@selector(documentViewWillBeginSwiping:)]) {
          [_delegate documentViewWillBeginSwiping:self];
        }
        _swiping = YES;
        
        // If there is an animation from the previous swipe currently running, cancel it and update pane visibility
        if ([_contentView.layer animationForKey:@"position"]) {
          [self _updatePageViewsVisibility];
          [_contentView.layer removeAnimationForKey:@"position"];
        }
      }
      
      // Translate PKPageViews
      _contentView.layer.position = CGPointMake((CGFloat)_pageIndex * -_pageSize.width + offset.x, 0.0);
      break;
    }
    
    // Gesture has ended or has been cancelled
    case UIGestureRecognizerStateEnded:
    case UIGestureRecognizerStateCancelled: {
      BOOL cancelled = recognizer.state == UIGestureRecognizerStateCancelled ? YES : NO;
      CGPoint offset = [recognizer translationInView:self];
      
      // Animate to newly selected PKPageView or bounce-back to current one
      NSUInteger index = _pageIndex;
      if (offset.x > 0.0) {
        if (!cancelled && (offset.x > _pageSize.width * kPaningTolerance)) {
          if (index > 0) {
            index -= 1;
          } else if ([_delegate respondsToSelector:@selector(documentViewDidReachFirstPage:)]) {
            [(id)_delegate performSelector:@selector(documentViewDidReachFirstPage:) withObject:self afterDelay:0.0];
          }
        }
      } else {
        if (!cancelled && (-offset.x > _pageSize.width * kPaningTolerance)) {
          if (index < _pageViews.count - 1) {
            index += 1;
          } else if ([_delegate respondsToSelector:@selector(documentViewDidReachLastPage:)]) {
            [(id)_delegate performSelector:@selector(documentViewDidReachLastPage:) withObject:self afterDelay:0.0];
          }
        }
      }
      BOOL notify = (index != _pageIndex);
      if (notify) {
        [self willChangePageIndex];
      }
      _pageIndex = index;
      if ([_contentView.layer animationForKey:@"position"]) {
        [self _updatePageViewsVisibility];  // We can't rely on this happening in the delegate as it would be too late
      }
      CABasicAnimation* animation = [CABasicAnimation animation];
      animation.delegate = self;
      animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionDefault];
      animation.duration = _animationDuration;
      [_contentView.layer addAnimation:animation forKey:@"position"];
      _contentView.layer.position = CGPointMake((CGFloat)_pageIndex * -_pageSize.width, 0.0);
      if (notify) {
        [self didChangePageIndex];
      }
      _swiping = NO;
      if ([_delegate respondsToSelector:@selector(documentViewDidEndSwiping:)]) {
        [_delegate documentViewDidEndSwiping:self];
      }
      break;
    }
    
    default:
      break;
    
  }
}

- (void) _setPageIndex:(NSUInteger)index animate:(BOOL)animate {
  [self willChangePageIndex];
  _pageIndex = index;
  if (animate) {
    CABasicAnimation* animation = [CABasicAnimation animation];
    animation.delegate = self;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionDefault];
    animation.duration = _animationDuration;
    [_contentView.layer addAnimation:animation forKey:@"position"];
  }
  _contentView.layer.position = CGPointMake((CGFloat)_pageIndex * -_pageSize.width, 0.0);
  [self didChangePageIndex];
  if (!animate) {
    [self performSelector:@selector(_updatePageViewsVisibility) withObject:nil afterDelay:0.0];
  }
}

- (void) goToPreviousPage:(BOOL)animate {
  if (_pageIndex > 0) {
    [self _setPageIndex:(_pageIndex - 1) animate:animate];
  } else if ([_delegate respondsToSelector:@selector(documentViewDidReachFirstPage:)]) {
    [(id)_delegate performSelector:@selector(documentViewDidReachFirstPage:) withObject:self afterDelay:0.0];
  }
}

- (void) goToNextPage:(BOOL)animate {
  if (_pageIndex + 1 < _pageViews.count) {
    [self _setPageIndex:(_pageIndex + 1) animate:animate];
  } else if ([_delegate respondsToSelector:@selector(documentViewDidReachLastPage:)]) {
    [(id)_delegate performSelector:@selector(documentViewDidReachLastPage:) withObject:self afterDelay:0.0];
  }
}

@end

@implementation DocumentView (Subclassing)

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

- (void) willChangePageIndex {
  if ([_delegate respondsToSelector:@selector(documentViewWillChangePage:)]) {
    [_delegate documentViewWillChangePage:self];
  }
}

- (void) didChangePageIndex {
  if ([_delegate respondsToSelector:@selector(documentViewDidChangePage:)]) {
    [_delegate documentViewDidChangePage:self];
  }
}

@end
