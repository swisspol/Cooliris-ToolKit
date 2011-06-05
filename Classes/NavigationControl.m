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

#import "NavigationControl.h"
#import "OverlayView.h"
#import "ImageUtilities.h"

@implementation NavigationControl

@synthesize delegate=_delegate, numberOfPages=_pageCount, numberOfMarkers=_markerCount, currentPage=_pageIndex,
            continuous=_continuous, margins=_margins, maximumSpacing=_maximumSpacing, thumbImage=_thumbImage,
            thumbTintColor=_thumbColor, markerImage=_markerImage, markerTintColor=_markerColor,
            thumbMarkerImage=_thumbMarkerImage, thumbMarkerTintColor=_thumbMarkerTintColor,
            constrainOverlayToSuperview=_constrainOverlay, overlayArrowOffset=_overlayArrowOffset;

- (void) _initialize {
  _pageIndex = NSNotFound;
  _continuous = YES;
  
  _overlayView = [[OverlayView alloc] init];
  _thumbView = [[UIImageView alloc] init];
  [self addSubview:_thumbView];
  _markerView = [[UIImageView alloc] init];
  [self addSubview:_markerView];
  _markerViews = [[NSMutableArray alloc] init];
  
  _markerImage = [[UIImage imageWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"NavigationControl-Marker"
                                                                                   ofType:@"png"]] retain];
  _thumbImage = [[UIImage imageWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"NavigationControl-Thumb"
                                                                                  ofType:@"png"]] retain];
}

- (id) initWithFrame:(CGRect)frame {
  if ((self = [super initWithFrame:frame])) {
    [self _initialize];
  }
  return self;
}

- (void) dealloc {
  [_thumbImage release];
  [_thumbColor release];
  [_markerImage release];
  [_markerColor release];
  [_thumbMarkerImage release];
  [_thumbMarkerColor release];
  [_overlayView release];
  [_thumbView release];
  [_markerView release];
  [_markerViews release];
  
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

- (void) _reloadThumbImage:(BOOL)force {
  UIImage* image = nil;
  if ([_delegate respondsToSelector:@selector(navigationControlThumbImageForCurrentPage:)]) {
    image = [_delegate navigationControlThumbImageForCurrentPage:self];
  }
  if (image == nil) {
    image = _thumbImage;
  }
  if (force || (image != _thumbView.highlightedImage)) {
    _thumbView.highlightedImage = image;

    if (_thumbColor) {
      CGImageRef imageRef = CreateTintedImage([image CGImage], [_thumbColor CGColor], NULL);
      image = [UIImage imageWithCGImage:imageRef];
      CGImageRelease(imageRef);
    }

    _thumbView.image = image;
    CGSize size = image.size;
    _thumbView.bounds = CGRectMake(0.0, 0.0, size.width, size.height);
  }
}
  
- (void) _reloadMarkerImages:(BOOL)force onlyIndex:(NSUInteger)onlyIndex {
  UIImage* lastMarkerImage = nil;
  UIImage* cachedMarkerImage = nil;
  
  BOOL hasDelegate = [_delegate respondsToSelector:@selector(navigationControl:markerImageForPageAtIndex:)];
  NSUInteger index = 0;
  for (UIImageView* view in _markerViews) {
    if ((onlyIndex == NSNotFound) || (index == onlyIndex)) {
      UIImage* image = nil;
      if (hasDelegate) {
        image = [_delegate navigationControl:self markerImageForPageAtIndex:index];
      }
      if (image == nil) {
        image = _markerImage;
      }
      if (force || (image != view.highlightedImage)) {
        view.highlightedImage = image;
        
        if (image != lastMarkerImage) {
          if (_markerColor) {
            CGImageRef imageRef = CreateTintedImage([image CGImage], [_markerColor CGColor], NULL);
            cachedMarkerImage = [UIImage imageWithCGImage:imageRef];
            CGImageRelease(imageRef);
          } else {
            cachedMarkerImage = image;
          }
          lastMarkerImage = image;
        }
        
        view.image = cachedMarkerImage;
        CGSize size = cachedMarkerImage.size;
        view.bounds = CGRectMake(0.0, 0.0, size.width, size.height);
      }
    }
    ++index;
  }
}

- (void) _reloadThumbMarkerImage:(BOOL)force {
  UIImage* image = nil;
  if ([_delegate respondsToSelector:@selector(navigationControlThumbMarkerImageForCurrentPage:)]) {
    image = [_delegate navigationControlThumbMarkerImageForCurrentPage:self];
  }
  if (image == nil) {
    image = _thumbMarkerImage;
  }
  if (image == nil) {
    image = _markerImage;
  }
  if (force || (image != _markerView.highlightedImage)) {
    _markerView.highlightedImage = image;
    
    if (_thumbMarkerColor) {
      CGImageRef imageRef = CreateTintedImage([image CGImage], [_thumbMarkerColor CGColor], NULL);
      image = [UIImage imageWithCGImage:imageRef];
      CGImageRelease(imageRef);
    }
    
    _markerView.image = image;
    CGSize size = image.size;
    _markerView.bounds = CGRectMake(0.0, 0.0, size.width, size.height);
  }
}

- (void) _reloadMarkerViews {
  for (UIImageView* view in _markerViews) {
    [view removeFromSuperview];
  }
  [_markerViews removeAllObjects];
  for (NSUInteger i = 0; i < _markerCount; ++i) {
    UIImageView* view = [[UIImageView alloc] init];
    [_markerViews addObject:view];
    [self insertSubview:view belowSubview:_thumbView];
    [view release];
  }
  
  [self _reloadMarkerImages:NO onlyIndex:NSNotFound];
  [self _reloadThumbMarkerImage:NO];
}

- (CGRect) _getLayoutBounds {
  CGRect bounds = UIEdgeInsetsInsetRect(self.bounds, _margins);
  if (_maximumSpacing > 0.0) {
    CGFloat maxWidth = (CGFloat)_pageCount * _maximumSpacing;
    if (bounds.size.width > maxWidth) {
      bounds.origin.x = floorf(bounds.origin.x + bounds.size.width / 2.0 - maxWidth / 2.0);
      bounds.size.width = maxWidth;
    }
  }
  return bounds;
}

- (void) setNumberOfPages:(NSUInteger)count {
  if (count != _pageCount) {
    _pageCount = count;
    
    self.currentPage = _pageCount > 0 ? (_pageIndex != NSNotFound ? MIN(_pageIndex, _pageCount - 1) : 0) : NSNotFound;
  }
}

- (void) setNumberOfMarkers:(NSUInteger)count {
  if (count != _markerCount) {
    _markerCount = count;
    
    [self _reloadMarkerViews];
    
    [self setNeedsLayout];
  }
}

- (void) setCurrentPage:(NSUInteger)index {
  if (index != _pageIndex) {
    _pageIndex = _pageCount > 0 ? MIN(index, _pageCount - 1) : NSNotFound;
    
    if (_pageIndex != NSNotFound) {
      [self _reloadThumbImage:NO];
      [self _reloadThumbMarkerImage:NO];
      
      CGRect bounds = [self _getLayoutBounds];
      CGFloat dX = bounds.size.width / (CGFloat)_pageCount;
      CGFloat x = bounds.origin.x + roundf(dX / 2.0 + _pageIndex * dX);
      CGFloat y = bounds.origin.y + roundf(bounds.size.height / 2.0);
      _thumbView.center = CGPointMake(x, y);
      _markerView.center = CGPointMake(x, y);
      
      if (_overlayView.superview && [_delegate respondsToSelector:@selector(navigationControlOverlayViewForCurrentPage:)]) {
        UIView* view = [_delegate navigationControlOverlayViewForCurrentPage:self];
        if (view != _overlayView.contentView) {
          if (view) {
            _overlayView.contentView = view;
            _overlayView.hidden = NO;
          } else {
            _overlayView.contentView = nil;
            _overlayView.hidden = YES;
          }
        }
        if (_overlayView.hidden == NO) {
          if (_constrainOverlay) {
            [_overlayView setContentSize:view.bounds.size
                          anchorLocation:CGPointMake(x, bounds.origin.y + _overlayArrowOffset)
                          constraintRect:[self convertRect:[self.superview bounds] fromView:self.superview]
                      preferredDirection:kOverlayViewArrowDirection_Down
                   adjustableContentSize:NO];
          } else {
            _overlayView.arrowDirection = kOverlayViewArrowDirection_Down;
            [_overlayView setContentSize:view.bounds.size anchorLocation:CGPointMake(x, bounds.origin.y + _overlayArrowOffset)];
          }
        }
      }
    } else {
      [_overlayView removeFromSuperview];
      _overlayView.contentView = nil;
    }
  }
}

- (BOOL) thumbMarkerImageVisible {
  return !_markerView.hidden;
}

- (void) setThumbMarkerImageVisible:(BOOL)flag {
  _markerView.hidden = !flag;
}

- (void) setThumbTintColor:(UIColor*)color {
  if (color != _thumbColor) {
    [_thumbColor release];
    _thumbColor = [color retain];
    
    [self _reloadThumbImage:YES];
  }
}

- (void) setMarkerTintColor:(UIColor*)color {
  if (color != _markerColor) {
    [_markerColor release];
    _markerColor = [color retain];
    
    [self _reloadMarkerImages:YES onlyIndex:NSNotFound];
  }
}

- (void) setThumbMarkerTintColor:(UIColor*)color {
  if (color != _thumbMarkerColor) {
    [_thumbMarkerColor release];
    _thumbMarkerColor = [color retain];
    
    [self _reloadThumbMarkerImage:YES];
  }
}

- (void) setThumbImage:(UIImage*)image {
  if (image != _thumbImage) {
    [_thumbImage release];
    if (image) {
      _thumbImage = [image retain];
    } else {
      _thumbImage = [[UIImage imageWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"NavigationControl-Thumb"
                                                                                      ofType:@"png"]] retain];
    }
    
    [self _reloadThumbImage:YES];
  }
}

- (void) setMarkerImage:(UIImage*)image {
  if (image != _markerImage) {
    [_markerImage release];
    if (image) {
      _markerImage = [image retain];
    } else {
      _markerImage = [[UIImage imageWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"NavigationControl-Marker"
                                                                                       ofType:@"png"]] retain];
    }
    
    [self _reloadMarkerImages:YES onlyIndex:NSNotFound];
  }
}

- (void) setThumbMarkerImage:(UIImage*)image {
  if (image != _thumbMarkerImage) {
    [_thumbMarkerImage release];
    _thumbMarkerImage = [image retain];
    
    [self _reloadThumbMarkerImage:YES];
  }
}

- (void) setOverlayTintColor:(UIColor*)color {
  _overlayView.tintColor = color;
}

- (UIColor*) overlayTintColor {
  return _overlayView.tintColor;
}

- (void) layoutSubviews {
  CGRect bounds = [self _getLayoutBounds];
  CGFloat y = bounds.origin.y + roundf(bounds.size.height / 2.0);
  if (_markerViews.count) {
    CGFloat dx = bounds.size.width / (CGFloat)_pageCount;
    CGFloat dX = (bounds.size.width - dx) / (CGFloat)(_markerViews.count - 1);
    CGFloat x = bounds.origin.x + dx / 2.0;
    for (UIImageView* view in _markerViews) {
      view.center = CGPointMake(roundf(x), y);
      x += dX;
    }
  }
  if (_pageIndex != NSNotFound) {
    CGFloat dX = bounds.size.width / (CGFloat)_pageCount;
    CGFloat x = bounds.origin.x + roundf(dX / 2.0 + _pageIndex * dX);
    _thumbView.center = CGPointMake(x, y);
    _markerView.center = CGPointMake(x, y);
  }
}

- (void) _updateCurrentPageForLocation:(CGPoint)location {
  CGRect bounds = [self _getLayoutBounds];
  CGFloat dX = bounds.size.width / (CGFloat)_pageCount;
  NSInteger index = (location.x - bounds.origin.x) / dX;
  if (index < 0) {
    index = 0;
  } else if (index >= _pageCount) {
    index = _pageCount - 1;
  }
  self.currentPage = index;
}

- (BOOL) beginTrackingWithTouch:(UITouch*)touch withEvent:(UIEvent*)event {
  if (!_pageCount || ![super beginTrackingWithTouch:touch withEvent:event]) {
    return NO;
  }
  
  _overlayView.hidden = YES;
  [self addSubview:_overlayView];
  
  _lastIndex = _pageIndex;
  
  return YES;
}

- (BOOL) continueTrackingWithTouch:(UITouch*)touch withEvent:(UIEvent*)event {
  if (![super continueTrackingWithTouch:touch withEvent:event]) {
    return NO;
  }
  
  [self _updateCurrentPageForLocation:[touch locationInView:self]];
  if (_continuous && (_pageIndex != _lastIndex)) {
    [self sendActionsForControlEvents:UIControlEventValueChanged];
    _lastIndex = _pageIndex;
  }
  
  return YES;
}

- (void) endTrackingWithTouch:(UITouch*)touch withEvent:(UIEvent*)event {
  [super endTrackingWithTouch:touch withEvent:event];
  
  [_overlayView removeFromSuperview];
  _overlayView.contentView = nil;
  
  [self _updateCurrentPageForLocation:[touch locationInView:self]];
  
  if (_pageIndex != _lastIndex) {
    [self sendActionsForControlEvents:UIControlEventValueChanged];
  }
}

- (void) cancelTrackingWithEvent:(UIEvent*)event {
  [super cancelTrackingWithEvent:event];
  
  [_overlayView removeFromSuperview];
  _overlayView.contentView = nil;
}

- (void) reloadAllMarkerImages {
  [self _reloadMarkerImages:NO onlyIndex:NSNotFound];
  [self _reloadThumbMarkerImage:NO];
}

- (void) reloadMarkerImageAtIndex:(NSUInteger)index {
  [self _reloadMarkerImages:NO onlyIndex:index];
  if (index == _pageIndex) {
    [self _reloadThumbMarkerImage:NO];
  }
}

@end
