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

#import "AutoresizingView.h"

@implementation AutoresizingView

@synthesize contentView=_contentView, contentSize=_contentSize, autoresizingMode=_autoresizingMode;

- (id) initWithCoder:(NSCoder*)coder {
  if ((self = [super initWithCoder:coder])) {
    self.autoresizesSubviews = NO;
  }
  return self;
}

- (id) initWithFrame:(CGRect)frame {
  if ((self = [super initWithFrame:frame])) {
    self.autoresizesSubviews = NO;
  }
  return self;
}

- (void) dealloc {
  [_contentView release];
  
  [super dealloc];
}

- (void) setContentView:(UIView*)view {
  if (view != _contentView) {
    [_contentView removeFromSuperview];
    [_contentView release];
    if (view) {
      _contentView = [view retain];
      [self insertSubview:_contentView atIndex:0];
    } else {
      _contentView = nil;
    }
  }
}

- (void) setcontentSize:(CGSize)size {
  if (!CGSizeEqualToSize(size, _contentSize)) {
    _contentSize = size;
    
    [self setNeedsLayout];
  }
}

- (void) setAutoresizingMode:(AutoresizingViewMode)mode {
  if (mode != _autoresizingMode) {
    _autoresizingMode = mode;
    
    [self setNeedsLayout];
  }
}

- (void) layoutSubviews {
  if (_contentView) {
    CGRect bounds = self.bounds;
    CGRect frame = _contentView.frame;
    switch (_autoresizingMode) {
      
      case kAutoresizingViewMode_Center:
        frame.size = _contentSize;
        break;
      
      case kAutoresizingViewMode_Resize: {
        frame = bounds;
        break;
      }
      
      case kAutoresizingViewMode_AspectFill: {
        if (_contentSize.width / bounds.size.width >= _contentSize.height / bounds.size.height) {
          frame.size.width = bounds.size.height * _contentSize.width / _contentSize.height;
          frame.size.height = bounds.size.height;
        } else {
          frame.size.width = bounds.size.width;
          frame.size.height = bounds.size.width * _contentSize.height / _contentSize.width;
        }
        break;
      }
      
      case kAutoresizingViewMode_AspectFit: {
        if (_contentSize.width / bounds.size.width >= _contentSize.height / bounds.size.height) {
          frame.size.width = bounds.size.width;
          frame.size.height = _contentSize.height / (_contentSize.width / bounds.size.width);
        } else {
          frame.size.width = _contentSize.width / (_contentSize.height / bounds.size.height);
          frame.size.height = bounds.size.height;
        }
        break;
      }
      
    }
    frame.origin.x = roundf(bounds.origin.x + bounds.size.width / 2.0 - frame.size.width / 2.0);
    frame.origin.y = roundf(bounds.origin.y + bounds.size.height / 2.0 - frame.size.height / 2.0);
    _contentView.frame = frame;
  }
}

@end
