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

@interface ZoomView ()
- (void) _calculateMinimumZoomScale;
- (void) _restoreCenterPoint:(CGPoint)oldCenter scale:(CGFloat)oldScale;
@end

@implementation ZoomView

@synthesize displayView=_displayView, zoomsToFit=_zoomsToFit, maximumScale=_maximumScale;

- (id) initWithFrame:(CGRect)frame {
  if ((self = [super initWithFrame:frame])) {
    self.showsVerticalScrollIndicator = NO;
    self.showsHorizontalScrollIndicator = NO;
    self.bouncesZoom = YES;
    self.alwaysBounceVertical = YES;
    self.alwaysBounceHorizontal = YES;
    self.decelerationRate = UIScrollViewDecelerationRateFast;
    self.clipsToBounds = YES;
    self.autoresizesSubviews = NO;
    self.scrollsToTop = NO;
    self.delegate = self;
    
    _zoomsToFit = YES;
    _maximumScale = 2.0;
        
    UITapGestureRecognizer* recognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_handleDoubleTap:)];
    [recognizer setNumberOfTapsRequired:2];
    [self addGestureRecognizer:recognizer];
    [recognizer release];
  }
  return self;
}

- (void) setDisplayView:(UIView*)view {
  if (view != _displayView) {
    [_displayView removeFromSuperview];
    [_displayView release];
    _displayView = [view retain];
    
    if (_displayView) {
      [self addSubview:_displayView];
      
      self.contentSize = _displayView.bounds.size;
      [self _calculateMinimumZoomScale];
      [self setZoomScale:self.minimumZoomScale];
    }
  }
}

#pragma mark -
#pragma mark Tap zooming
// Zooms in
- (void) _handleDoubleTap:(UIGestureRecognizer*)gestureRecognizer {
  if (self.minimumZoomScale == self.maximumZoomScale) {
    // Do nothing
  } else if (self.zoomScale == self.minimumZoomScale) {
    CGPoint point = [gestureRecognizer locationInView:_displayView];
    CGRect zoomRect = CGRectMake(point.x - 1.0, point.y - 1.0, 2.0, 2.0);
    [self zoomToRect:zoomRect animated:YES];
  } else {
    [self setZoomScale:self.minimumZoomScale animated:YES];
  }
}

#pragma mark -
#pragma mark Positioning/Zooming
- (void) layoutSubviews {
  [super layoutSubviews];
  
  // If the size has changed (most likely because of device rotation) we need to recalculate the zoom levels
  if (!CGSizeEqualToSize(self.bounds.size, _oldSize)) {
    CGFloat restoreScale = self.zoomScale;
    // If we're at the minimum zoom scale, preserve that by returning 0, which will be converted to the minimum
    // allowable scale when the scale is restored.
    if ((restoreScale <= self.minimumZoomScale + FLT_EPSILON)) {
      restoreScale = 0.0;
    }
    
    [self _calculateMinimumZoomScale];
    
    // Restore the center point
    if (!CGPointEqualToPoint(_oldCenterPoint, CGPointZero)) {
      [self _restoreCenterPoint:_oldCenterPoint scale:restoreScale];
    }
    _oldSize = self.bounds.size;
  }
  
  if (_displayView) {
    // When the child view is smaller than the scroll view we center it
    CGSize scrollViewSize = self.bounds.size;
    CGRect childFrame = _displayView.frame;
    
    if (childFrame.size.width < scrollViewSize.width) {
      childFrame.origin.x = floorf((scrollViewSize.width - childFrame.size.width) / 2.0);
    } else {
      childFrame.origin.x = 0.0;
    }
    
    if (childFrame.size.height < scrollViewSize.height) {
      childFrame.origin.y = floorf((scrollViewSize.height - childFrame.size.height) / 2.0);
    } else {
      childFrame.origin.y = 0.0;
    }
    _displayView.frame = childFrame;
  }

  _oldCenterPoint = [self convertPoint:CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds)) toView:_displayView];
}

// Adjusts content offset and scale to try to preserve the old zoomscale and center.
- (void) _restoreCenterPoint:(CGPoint)oldCenter scale:(CGFloat)oldScale {
  // Step 1: restore zoom scale, first making sure it is within the allowable range.
  self.zoomScale = MIN(self.maximumZoomScale, MAX(self.minimumZoomScale, oldScale));
  
  // Step 2: restore center point, first making sure it is within the allowable range.
  // 2a: convert our desired center point back to our own coordinate space
  CGPoint boundsCenter = [self convertPoint:oldCenter fromView:_displayView];
  // 2b: calculate the content offset that would yield that center point
  CGPoint offset = CGPointMake(boundsCenter.x - self.bounds.size.width / 2.0,
                               boundsCenter.y - self.bounds.size.height / 2.0);
  // 2c: restore offset, adjusted to be within the allowable range
  CGSize boundsSize = self.bounds.size;
  CGPoint maxOffset = CGPointMake(self.contentSize.width - boundsSize.width, self.contentSize.height - boundsSize.height);
  CGPoint minOffset = CGPointZero;
  offset.x = MAX(minOffset.x, MIN(maxOffset.x, offset.x));
  offset.y = MAX(minOffset.y, MIN(maxOffset.y, offset.y));
  self.contentOffset = offset;
}

- (void) _calculateMinimumZoomScale {
  CGSize boundsSize = self.bounds.size;
  CGSize imageSize = _displayView.bounds.size;
  
  // Find the scale that makes the subview fit to the edges of the zoom view
  CGFloat xScale = boundsSize.width / imageSize.width;
  CGFloat yScale = boundsSize.height / imageSize.height;
  CGFloat minScale = MIN(xScale, yScale);
  if (!_zoomsToFit) {
    minScale = MIN(1.0, minScale);
  }
  
  self.minimumZoomScale = minScale;
  if (_zoomsToFit) {
    self.maximumZoomScale = ((minScale * _maximumScale) >= 1.0) ?  (minScale * _maximumScale) : 1.0;
  } else {
    self.maximumZoomScale = _maximumScale;
  }
}

#pragma mark -
#pragma mark Scroll view delegate
- (UIView*) viewForZoomingInScrollView:(UIScrollView*)scrollView {
  return _displayView;
}

#pragma mark -
- (void) dealloc {
  [_displayView release];
  
  [super dealloc];
}
@end
