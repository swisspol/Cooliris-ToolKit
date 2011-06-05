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

#import "OverlayView.h"
#import "ImageUtilities.h"
#import "Logging.h"

#define kImageContentsSize 140.0
#define kImageContentsMargin 40.0
#define kImageArrowWidth 40.0
#define kImageArrowHeight 24.0
#define kContentMargin (kImageContentsMargin - 10.0)
#define kArrowMargin (kImageContentsMargin + 20.0)

@interface OverlayView ()
+ (CGRect) frameForContentSize:(CGSize)size
                anchorLocation:(CGPoint)point
                arrowDirection:(OverlayViewArrowDirection)direction
                 arrowPosition:(CGFloat)position;
@end

@implementation OverlayView

@synthesize tintColor=_tintColor, contentView=_contentView, arrowDirection=_arrowDirection, arrowPosition=_arrowPosition;

+ (CGSize) minimumContentSize {
  return CGSizeMake(kImageContentsSize - kImageContentsMargin, kImageContentsSize - kImageContentsMargin);
}

+ (CGSize) maximumContentSizeForConstraintRect:(CGRect)rect {
  return CGSizeMake(floorf(rect.size.width - 2.0 * kContentMargin) / 2.0, floorf((rect.size.height - 2.0 * kContentMargin) / 2.0));
}

+ (CGRect) frameForContentSize:(CGSize)size
                anchorLocation:(CGPoint)location
                arrowDirection:(OverlayViewArrowDirection)direction
                 arrowPosition:(CGFloat)position {
  CGRect frame;
  frame.size.width = size.width + 2.0 * kContentMargin;
  frame.size.height = size.height + 2.0 * kContentMargin;
  switch (direction) {
    
    case kOverlayViewArrowDirection_None: {
      frame.origin.x = location.x - frame.size.width / 2.0;
      frame.origin.y = location.y - frame.size.height / 2.0;
      break;
    }
    
    case kOverlayViewArrowDirection_Up: {
      CGFloat offset = roundf(kArrowMargin + (frame.size.width - 2.0 * kArrowMargin) * position);
      frame.origin.x = location.x - offset;
      frame.origin.y = location.y;
      break;
    }
    
    case kOverlayViewArrowDirection_Left: {
      CGFloat offset = roundf(kArrowMargin + (frame.size.height - 2.0 * kArrowMargin) * position);
      frame.origin.x = location.x;
      frame.origin.y = location.y - offset;
      break;
    }
    
    case kOverlayViewArrowDirection_Right: {
      CGFloat offset = roundf(kArrowMargin + (frame.size.height - 2.0 * kArrowMargin) * position);
      frame.origin.x = location.x - frame.size.width;
      frame.origin.y = location.y - offset;
      break;
    }
    
    case kOverlayViewArrowDirection_Down: {
      CGFloat offset = roundf(kArrowMargin + (frame.size.width - 2.0 * kArrowMargin) * position);
      frame.origin.x = location.x - offset;
      frame.origin.y = location.y - frame.size.height;
      break;
    }
    
  }
  return frame;
}

- (void) _setImageWithName:(NSString*)name onView:(UIView*)view {
  NSString* path = [[NSBundle mainBundle] pathForResource:name ofType:@"png"];
  UIImage* image = [[UIImage alloc] initWithContentsOfFile:path];
  DCHECK([image CGImage]);
  if (_tintColor) {
    CGImageRef imageRef = CreateTintedImage([image CGImage], [_tintColor CGColor], NULL);
    view.layer.contents = (id)imageRef;
    CGImageRelease(imageRef);
  } else {
    view.layer.contents = (id)[image CGImage];
  }
  [image release];
}

- (void) _updateImages {
  [self _setImageWithName:@"OverlayView-Contents" onView:_centerView];
  [self _setImageWithName:@"OverlayView-Arrow-Top" onView:_topView];
  [self _setImageWithName:@"OverlayView-Arrow-Left" onView:_leftView];
  [self _setImageWithName:@"OverlayView-Arrow-Right" onView:_rightView];
  [self _setImageWithName:@"OverlayView-Arrow-Bottom" onView:_bottomView];
}

- (id) initWithFrame:(CGRect)frame {
  if ((self = [super initWithFrame:frame])) {
    _arrowPosition = 0.5;
    {
      _centerView = [[UIView alloc] init];
      [self addSubview:_centerView];
      _centerView.layer.contentsCenter = CGRectMake(kImageContentsMargin / kImageContentsSize,
                                               kImageContentsMargin / kImageContentsSize,
                                               (kImageContentsSize - 2.0 * kImageContentsMargin) / kImageContentsSize,
                                               (kImageContentsSize - 2.0 * kImageContentsMargin) / kImageContentsSize);
    }
    {
      _topView = [[UIView alloc] init];
      [self addSubview:_topView];
      _topView.frame = CGRectMake(0.0, 0.0, kImageArrowWidth, kImageArrowHeight);
      _topView.layer.anchorPoint = CGPointMake(0.5, 0.0);
      _topView.hidden = YES;
    }
    {
      _leftView = [[UIView alloc] init];
      [self addSubview:_leftView];
      _leftView.frame = CGRectMake(0.0, 0.0, kImageArrowHeight, kImageArrowWidth);
      _leftView.layer.anchorPoint = CGPointMake(0.0, 0.5);
      _leftView.hidden = YES;
    }
    {
      _rightView = [[UIView alloc] init];
      [self addSubview:_rightView];
      _rightView.frame = CGRectMake(0.0, 0.0, kImageArrowHeight, kImageArrowWidth);
      _rightView.layer.anchorPoint = CGPointMake(1.0, 0.5);
      _rightView.hidden = YES;
    }
    {
      _bottomView = [[UIView alloc] init];
      [self addSubview:_bottomView];
      _bottomView.frame = CGRectMake(0.0, 0.0, kImageArrowWidth, kImageArrowHeight);
      _bottomView.layer.anchorPoint = CGPointMake(0.5, 1.0);
      _bottomView.hidden = YES;
    }
    [self _updateImages];
    
#if 1
    self.layer.shadowOpacity = 0.5;
    self.layer.shadowRadius = 10.0;
    self.layer.shadowOffset = CGSizeMake(0.0, 5.0);
#endif
  }
  return self;
}

- (void) dealloc {
  [_tintColor release];
  [_contentView release];
  [_centerView release];
  [_topView release];
  [_leftView release];
  [_rightView release];
  [_bottomView release];
  
  [super dealloc];
}

- (id) initWithCoder:(NSCoder*)coder {
  [self doesNotRecognizeSelector:_cmd];
  return nil;
}

- (void) encodeWithCoder:(NSCoder*)coder {
  [self doesNotRecognizeSelector:_cmd];
}

- (void) setTintColor:(UIColor*)color {
  if (color != _tintColor) {
    [_tintColor release];
    _tintColor = [color retain];
    
    [self _updateImages];
  }
}

- (void) setContentView:(UIView*)view {
  if (view != _contentView) {
    if (_contentView) {
      [_contentView removeFromSuperview];
    }
    [_contentView release];
    _contentView = [view retain];
    if (_contentView) {
      [self addSubview:_contentView];
    }
    
    [self setNeedsLayout];
  }
}

- (void) setArrowDirection:(OverlayViewArrowDirection)direction {
  if (direction != _arrowDirection) {
    _arrowDirection = direction;
    
    [self setNeedsLayout];
  }
}

- (void) setArrowPosition:(CGFloat)position {
  if (position != _arrowPosition) {
    _arrowPosition = position;
    
    [self setNeedsLayout];
  }
}

- (CGSize) contentSize {
  CGRect frame = self.frame;
  return CGSizeMake(frame.size.width - 2.0 * kContentMargin, frame.size.height - 2.0 * kContentMargin);
}

- (void) setContentSize:(CGSize)size {
  [self setContentSize:size anchorLocation:self.anchorLocation];
}

- (CGPoint) anchorLocation {
  CGRect frame = self.frame;
  CGPoint location;
  switch (_arrowDirection) {
    
    case kOverlayViewArrowDirection_None: {
      location.x = frame.origin.x + frame.size.width / 2.0;
      location.y = frame.origin.y + frame.size.height / 2.0;
      break;
    }
    
    case kOverlayViewArrowDirection_Up: {
      CGFloat offset = roundf(kArrowMargin + (frame.size.width - 2.0 * kArrowMargin) * _arrowPosition);
      location.x = frame.origin.x + offset;
      location.y = frame.origin.y;
      break;
    }
    
    case kOverlayViewArrowDirection_Left: {
      CGFloat offset = roundf(kArrowMargin + (frame.size.height - 2.0 * kArrowMargin) * _arrowPosition);
      location.x = frame.origin.x;
      location.y = frame.origin.y + offset;
      break;
    }
    
    case kOverlayViewArrowDirection_Right: {
      CGFloat offset = roundf(kArrowMargin + (frame.size.height - 2.0 * kArrowMargin) * _arrowPosition);
      location.x = frame.origin.x + frame.size.width;
      location.y = frame.origin.y + offset;
      break;
    }
    
    case kOverlayViewArrowDirection_Down: {
      CGFloat offset = roundf(kArrowMargin + (frame.size.width - 2.0 * kArrowMargin) * _arrowPosition);
      location.x = frame.origin.x + offset;
      location.y = frame.origin.y + frame.size.height;
      break;
    }
    
  }
  return location;
}

- (void) setAnchorLocation:(CGPoint)location {
  [self setContentSize:self.contentSize anchorLocation:location];
}

- (void) setContentSize:(CGSize)size anchorLocation:(CGPoint)location {
  [self setContentSize:size
        anchorLocation:location
        constraintRect:CGRectNull
    preferredDirection:kOverlayViewArrowDirection_None
 adjustableContentSize:NO];
}

- (void) setContentSize:(CGSize)size
         anchorLocation:(CGPoint)location
         constraintRect:(CGRect)rect
     preferredDirection:(OverlayViewArrowDirection)direction
  adjustableContentSize:(BOOL)adjustableContentSize {
  if (!CGRectIsEmpty(rect)) {
    if (adjustableContentSize) {
      size.width = MIN(size.width, MAX(size.width, rect.size.width - 2.0 * kContentMargin - size.width));
      size.height = MIN(size.height, MAX(size.height, rect.size.height - 2.0 * kContentMargin - size.height));
    }
    
    switch (direction) {
    
      case kOverlayViewArrowDirection_None: {
        CGPoint center = CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect));
        CGPoint point = CGPointMake(location.x - center.x, location.y - center.y);
        CGFloat a1 = rect.size.height / rect.size.width;
        CGFloat a2 = -rect.size.height / rect.size.width;
        if (point.y >= a1 * point.x) {
          if (point.y >= a2 * point.x) {
            _arrowDirection = kOverlayViewArrowDirection_Down;
          } else {
            _arrowDirection = kOverlayViewArrowDirection_Left;
          }
        } else {
          if (point.y >= a2 * point.x) {
            _arrowDirection = kOverlayViewArrowDirection_Right;
          } else {
            _arrowDirection = kOverlayViewArrowDirection_Up;
          }
        }
        break;
      }
      
      case kOverlayViewArrowDirection_Up: {
        if (location.x < rect.origin.x + kArrowMargin) {
          _arrowDirection = kOverlayViewArrowDirection_Left;
        } else if (location.x > rect.origin.x + rect.size.width - kArrowMargin) {
          _arrowDirection = kOverlayViewArrowDirection_Right;
        } else if (location.y > rect.origin.y + rect.size.height - size.height - 2.0 * kContentMargin) {
          _arrowDirection = kOverlayViewArrowDirection_Down;
        } else {
          _arrowDirection = kOverlayViewArrowDirection_Up;
        }
        break;
      }
      
      case kOverlayViewArrowDirection_Left: {
        if (location.y < rect.origin.y + kArrowMargin) {
          _arrowDirection = kOverlayViewArrowDirection_Up;
        } else if (location.y > rect.origin.y + rect.size.height - kArrowMargin) {
          _arrowDirection = kOverlayViewArrowDirection_Down;
        } else if (location.x > rect.origin.x + rect.size.width - size.width - 2.0 * kContentMargin) {
          _arrowDirection = kOverlayViewArrowDirection_Right;
        } else {
          _arrowDirection = kOverlayViewArrowDirection_Left;
        }
        break;
      }
      
      case kOverlayViewArrowDirection_Right: {
        if (location.y < rect.origin.y + kArrowMargin) {
          _arrowDirection = kOverlayViewArrowDirection_Up;
        } else if (location.y > rect.origin.y + rect.size.height - kArrowMargin) {
          _arrowDirection = kOverlayViewArrowDirection_Down;
        } else if (location.x < rect.origin.x + size.width + 2.0 * kContentMargin) {
          _arrowDirection = kOverlayViewArrowDirection_Left;
        } else {
          _arrowDirection = kOverlayViewArrowDirection_Right;
        }
        break;
      }
      
      case kOverlayViewArrowDirection_Down: {
        if (location.x < rect.origin.x + kArrowMargin) {
          _arrowDirection = kOverlayViewArrowDirection_Left;
        } else if (location.x > rect.origin.x + rect.size.width - kArrowMargin) {
          _arrowDirection = kOverlayViewArrowDirection_Right;
        } else if (location.y < rect.origin.y + size.height + 2.0 * kContentMargin) {
          _arrowDirection = kOverlayViewArrowDirection_Up;
        } else {
          _arrowDirection = kOverlayViewArrowDirection_Down;
        }
        break;
      }
      
    }
    
    if ((_arrowDirection == kOverlayViewArrowDirection_Up) || (_arrowDirection == kOverlayViewArrowDirection_Down)) {
      location.x = MIN(MAX(location.x, rect.origin.x + kArrowMargin), rect.origin.x + rect.size.width - kArrowMargin);
      location.y = MIN(MAX(location.y, rect.origin.y), rect.origin.y + rect.size.height);
      
      CGFloat width = size.width + 2.0 * kContentMargin;
      CGFloat position = location.x - roundf(kArrowMargin + (width - 2.0 * kArrowMargin) * 0.5);
      if (position < rect.origin.x) {
        _arrowPosition = 0.5 - (rect.origin.x - position) / (width - 2.0 * kArrowMargin);
      } else if (position + width > rect.origin.x + rect.size.width) {
        _arrowPosition = 0.5 + (position + width - rect.origin.x - rect.size.width) / (width - 2.0 * kArrowMargin);
      } else {
        _arrowPosition = 0.5;
      }
    } else {
      location.x = MIN(MAX(location.x, rect.origin.x), rect.origin.x + rect.size.width);
      location.y = MIN(MAX(location.y, rect.origin.y + kArrowMargin), rect.origin.y + rect.size.height - kArrowMargin);
      
      CGFloat height = size.height + 2.0 * kContentMargin;
      CGFloat position = location.y - roundf(kArrowMargin + (height - 2.0 * kArrowMargin) * 0.5);
      if (position < rect.origin.y) {
        _arrowPosition = 0.5 - (rect.origin.y - position) / (height - 2.0 * kArrowMargin);
      } else if (position + height > rect.origin.y + rect.size.height) {
        _arrowPosition = 0.5 + (position + height - rect.origin.y - rect.size.height) / (height - 2.0 * kArrowMargin);
      } else {
        _arrowPosition = 0.5;
      }
    }
    _arrowPosition = MIN(MAX(_arrowPosition, 0.0), 1.0);
    
    [self setNeedsLayout];
  }
  self.frame = [[self class] frameForContentSize:size
                                  anchorLocation:location
                                  arrowDirection:_arrowDirection
                                   arrowPosition:_arrowPosition];
}

- (void) layoutSubviews {
  CGRect bounds = self.bounds;
  _centerView.frame = bounds;
  
  _topView.hidden = YES;
  _leftView.hidden = YES;
  _rightView.hidden = YES;
  _bottomView.hidden = YES;
  switch (_arrowDirection) {
    
    case kOverlayViewArrowDirection_None:
      break;
    
    case kOverlayViewArrowDirection_Up:
      _topView.hidden = NO;
      _topView.center = CGPointMake(roundf(kArrowMargin + (bounds.size.width - 2.0 * kArrowMargin) * _arrowPosition), 0.0);
      break;
    
    case kOverlayViewArrowDirection_Left:
      _leftView.hidden = NO;
      _leftView.center = CGPointMake(0.0, roundf(kArrowMargin + (bounds.size.height - 2.0 * kArrowMargin) * _arrowPosition));
      break;
    
    case kOverlayViewArrowDirection_Right:
      _rightView.hidden = NO;
      _rightView.center = CGPointMake(bounds.size.width,
                                      roundf(kArrowMargin + (bounds.size.height - 2.0 * kArrowMargin) * _arrowPosition));
      break;
    
    case kOverlayViewArrowDirection_Down:
      _bottomView.hidden = NO;
      _bottomView.center = CGPointMake(roundf(kArrowMargin + (bounds.size.width - 2.0 * kArrowMargin) * _arrowPosition),
                                       bounds.size.height);
      break;
    
  }
  
  if (_contentView) {
    _contentView.frame = CGRectInset(bounds, kContentMargin, kContentMargin);
  }
}

@end
