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

#import "ZoomView.h"
#import "Logging.h"

#define kAutomaticTolerance 0.1
#define kZoomTolerance 0.01

@interface ZoomView (UIScrollViewDelegate) <UIScrollViewDelegate>
@end

@implementation ZoomView

@synthesize displayView=_displayView, displayMode=_displayMode, doubleTapZoom=_doubleTapZoom, doubleTapRecognizer=_doubleTapRecognizer;

+ (NSTimeInterval) defaultAnimationDuration {
  return (1.0 / 3.0);
}

- (void) _resetFocusPoint {
  _focusPoint.x = self.zoomScale * self.contentSize.width / 2.0;
  _focusPoint.y = self.zoomScale * self.contentSize.height / 2.0;
}

- (void) _saveFocusPoint {
  CGSize boundsSize = self.bounds.size;
  CGPoint offset = self.contentOffset;
  float zoomScale = self.zoomScale;
  _focusPoint.x = (offset.x + boundsSize.width / 2.0) / zoomScale;
  _focusPoint.y = (offset.y + boundsSize.height / 2.0) / zoomScale;
}

- (void) _restoreFocusPoint {
  CGSize contentSize = self.contentSize;
  CGSize boundsSize = self.bounds.size;
  float zoomScale = self.zoomScale;
  CGPoint point = CGPointMake(MIN(MAX(roundf(zoomScale * _focusPoint.x - boundsSize.width / 2.0), 0.0), contentSize.width - boundsSize.width),
                              MIN(MAX(roundf(zoomScale * _focusPoint.y - boundsSize.height / 2.0), 0.0), contentSize.height - boundsSize.height));
  self.contentOffset = point;
}

- (void) _handleDoubleTap:(UIGestureRecognizer*)gestureRecognizer {
  if (self.maximumZoomScale > self.minimumZoomScale) {
    if (self.zoomScale <= self.minimumZoomScale + FLT_EPSILON) {
      CGPoint point = [gestureRecognizer locationInView:_displayView];
      CGRect zoomRect = CGRectMake(point.x - 1.0, point.y - 1.0, 2.0, 2.0);
      [self zoomToRect:zoomRect animated:YES];
    } else {
      BOOL atOrigin = CGPointEqualToPoint(self.contentOffset, CGPointZero);  // Work around a strange behavior where if zooming out while changing contentInset from zero to non-zero at the same time
      if (atOrigin) {
        self.contentOffset = CGPointMake(1.0, 1.0);
      }
      [self setZoomScale:self.minimumZoomScale animated:YES];
      if (atOrigin) {
        self.contentOffset = CGPointMake(0.0, 0.0);
      }
    }
  }
}

- (id) initWithFrame:(CGRect)frame {
  if ((self = [super initWithFrame:frame])) {
    self.showsVerticalScrollIndicator = NO;
    self.showsHorizontalScrollIndicator = NO;
    self.decelerationRate = UIScrollViewDecelerationRateFast;
    self.bouncesZoom = YES;
    self.clipsToBounds = YES;
    self.scrollsToTop = NO;
    self.autoresizesSubviews = NO;
    self.delegate = self;
    
    _displayMode = kZoomViewDisplayMode_Centered;
    _doubleTapZoom = 1.5;
    
    _doubleTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_handleDoubleTap:)];
    [_doubleTapRecognizer setNumberOfTapsRequired:2];
    [self addGestureRecognizer:_doubleTapRecognizer];
  }
  return self;
}

- (void) dealloc {
  [_displayView release];
  [_doubleTapRecognizer release];
  
  [super dealloc];
}

- (void) setDisplayMode:(ZoomViewDisplayMode)mode {
  if (mode != _displayMode) {
    _displayMode = mode;
    
    // Force a layout
    _oldSize = CGSizeZero;
    [self setNeedsLayout];
  }
}

- (void) setDoubleTapZoom:(float)zoom {
  if (zoom != _doubleTapZoom) {
    _doubleTapZoom = zoom;
    
    // Force a layout
    _oldSize = CGSizeZero;
    [self setNeedsLayout];
  }
}

- (void) setDisplayView:(UIView*)view {
  [self setDisplayView:view animated:NO];
}

- (void) setDisplayView:(UIView*)view animated:(BOOL)animated {
  if (view != _displayView) {
    // Replace display view
    UIView* oldDisplayView = [_displayView autorelease];
    _displayView = [view retain];
    _displaySize = view.frame.size;
    if (animated) {
      [UIView transitionWithView:self duration:[[self class] defaultAnimationDuration] options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
        [oldDisplayView removeFromSuperview];
        if (_displayView) {
          [self addSubview:_displayView];
        }
      } completion:NULL];
    } else {
      [oldDisplayView removeFromSuperview];
      if (_displayView) {
        [self addSubview:_displayView];
      }
    }
    
    // Force a layout
    _oldSize = CGSizeZero;
    [self setNeedsLayout];
  }
}

- (void) layoutSubviews {
  [super layoutSubviews];
  
  // Update layout if we have a display view
  if (_displayView) {
    CGSize boundsSize = self.bounds.size;
    
    // Check if zoom values need to be recomputed
    if (!CGSizeEqualToSize(boundsSize, _oldSize)) {
      // Save current zoom factor
      float oldZoomFactor = 0.0;
      if (self.maximumZoomScale > self.minimumZoomScale) {
        oldZoomFactor = (self.zoomScale - self.minimumZoomScale) / (self.maximumZoomScale - self.minimumZoomScale);
      }
      
      // Compute new min and max zoom
      float fitZoomScale = MIN(boundsSize.width / _displaySize.width, boundsSize.height / _displaySize.height);
      float fillZoomScale = MAX(boundsSize.width / _displaySize.width, boundsSize.height / _displaySize.height);
      DCHECK(fillZoomScale >= fitZoomScale);
      switch (_displayMode) {
        
        case kZoomViewDisplayMode_Centered:
          self.minimumZoomScale = 1.0;
          break;
        
        case kZoomViewDisplayMode_Fit:
          self.minimumZoomScale = fitZoomScale;
          break;
        
        case kZoomViewDisplayMode_FitVertically:
          self.minimumZoomScale = boundsSize.height / _displaySize.height;
          break;

        case kZoomViewDisplayMode_FitHorizontally:
          self.minimumZoomScale = boundsSize.width / _displaySize.width;
          break;

        case kZoomViewDisplayMode_Fill:
          self.minimumZoomScale = fillZoomScale;
          break;
        
        case kZoomViewDisplayMode_Automatic: {
          CGFloat ratio = (_displaySize.width / _displaySize.height) / (boundsSize.width / boundsSize.height);
          if ((ratio >= 1.0 - kAutomaticTolerance) && (ratio <= 1.0 + kAutomaticTolerance)) {
            self.minimumZoomScale = fillZoomScale;
          } else {
            self.minimumZoomScale = fitZoomScale;
          }
          break;
        }
        
      }
      float maxZoomScale = MAX(boundsSize.width, boundsSize.height) / MIN(_displaySize.width, _displaySize.height);
      self.maximumZoomScale = _doubleTapZoom * maxZoomScale;
      
      // Update current zoom
      if (CGSizeEqualToSize(_oldSize, CGSizeZero)) {
        self.zoomScale = 1.0;  // Be extra safe by resetting zoom scale before setting content size
        self.contentSize = _displaySize;
        self.zoomScale = self.minimumZoomScale;
        [self _resetFocusPoint];
      } else {
        if (oldZoomFactor <= kZoomTolerance) {
          self.zoomScale = self.minimumZoomScale;
        } else if (oldZoomFactor >= 1.0 - kZoomTolerance) {
          self.zoomScale = self.maximumZoomScale;
        } else {
          self.zoomScale = MIN(MAX(self.zoomScale, self.minimumZoomScale), self.maximumZoomScale);
        }
      }
      
      // Restore last focus point
      [self _restoreFocusPoint];
      
      _oldSize = boundsSize;
    }
    
    // Update padding around display view if necessary
    CGSize contentSize = self.contentSize;  // Content size depends on current zoom scale
    CGFloat paddingX = MAX((boundsSize.width - contentSize.width) / 2.0, 0.0);
    CGFloat paddingY = MAX((boundsSize.height - contentSize.height) / 2.0, 0.0);
    UIEdgeInsets edgeInsets = UIEdgeInsetsMake(paddingY, paddingX, paddingY, paddingX);
    if (!UIEdgeInsetsEqualToEdgeInsets(edgeInsets, self.contentInset)) {
      self.contentInset = edgeInsets;
    }
    
    // Save current focus point
    [self _saveFocusPoint];
  }
  // Otherwise reset everything
  else {
    self.contentInset = UIEdgeInsetsZero;
    self.contentOffset = CGPointZero;
    self.minimumZoomScale = 1.0;
    self.maximumZoomScale = 1.0;
    self.zoomScale = 1.0;
  }
}

@end

@implementation ZoomView (UIScrollViewDelegate)

- (UIView*) viewForZoomingInScrollView:(UIScrollView*)scrollView {
  return _displayView;
}

@end
