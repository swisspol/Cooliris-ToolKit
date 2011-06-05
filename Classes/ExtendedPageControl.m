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

#import "ExtendedPageControl.h"

#define kMinDotWidth 8.0
#define kMaxDotWidth 16.0
#define kDotHeight 20.0

@implementation ExtendedPageControl

@synthesize items=_items, selectedItem=_selectedItem, hidesForSinglePage=_autoHides;

- (void) _initialize {
  _autoHides = YES;
}

- (id) initWithFrame:(CGRect)frame {
  if ((self = [super initWithFrame:frame])) {
    [self _initialize];
  }
  return self;
}

- (void) dealloc {
  [_selectedItem release];
  [_items release];
  
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
  [self setItems:items firstItemIsInfo:NO];
}

- (void) setItems:(NSArray*)items firstItemIsInfo:(BOOL)firstItemIsInfo {
  if (items != _items) {
    [_items release];
    _items = items.count ? [items copy] : nil;
    
    for (UIImageView* view in self.subviews) {
      [view removeFromSuperview];
    }
    for (NSUInteger i = 0; i < _items.count; ++i) {
      UIImageView* view;
      if ((i == 0) && firstItemIsInfo) {
        view = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"ExtendedPageControl-Info-Off.png"]
                                 highlightedImage:[UIImage imageNamed:@"ExtendedPageControl-Info-On.png"]];
      } else {
        view = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"ExtendedPageControl-Item-Off.png"]
                                 highlightedImage:[UIImage imageNamed:@"ExtendedPageControl-Item-On.png"]];
      }
      [self addSubview:view];
      [view release];
    }
    [self setNeedsLayout];
    
    [_selectedItem release];
    if (_items) {
      _selectedItem = [[_items objectAtIndex:0] retain];
      [(UIImageView*)[self.subviews objectAtIndex:0] setHighlighted:YES];
    } else {
      _selectedItem = nil;
    }
    
    if (_autoHides) {
      self.hidden = _items.count <= 1 ? YES : NO;
    }
  }
}

- (void) setSelectedItem:(id)item {
  if (item != _selectedItem) {
    NSUInteger oldIndex = _selectedItem ? [_items indexOfObject:_selectedItem] : NSNotFound;
    if (oldIndex != NSNotFound) {
      [(UIImageView*)[self.subviews objectAtIndex:oldIndex] setHighlighted:NO];
    }
    NSUInteger newIndex = item ? [_items indexOfObject:item] : NSNotFound;
    if (newIndex != NSNotFound) {
      [_selectedItem release];
      _selectedItem = [item retain];
      [(UIImageView*)[self.subviews objectAtIndex:newIndex] setHighlighted:YES];
    }
  }
}

- (void) layoutSubviews {
  NSArray* subviews = self.subviews;
  NSUInteger count = subviews.count;
  if (count) {
    CGSize size = self.bounds.size;
    _count = MIN(count, (NSUInteger)(size.width / kMinDotWidth));  // Don't show more items that can fit
    _step = MAX(MIN(floorf(size.width / (CGFloat)_count), kMaxDotWidth), kMinDotWidth);
    _offset = (size.width - (CGFloat)_count * _step) / 2.0;
    NSUInteger i = 0;
    for (; i < _count; ++i) {
      UIView* view = [subviews objectAtIndex:i];
      view.hidden = NO;
      view.frame = CGRectMake(floorf(_offset + (CGFloat)i * _step + (_step - kMinDotWidth) / 2.0), 0.0, kMinDotWidth, kDotHeight);
    }
    for (; i < subviews.count; ++i) {
      [[subviews objectAtIndex:i] setHidden:YES];
    }
  }
}

- (BOOL) beginTrackingWithTouch:(UITouch*)touch withEvent:(UIEvent*)event {
  if (!_items || ![super beginTrackingWithTouch:touch withEvent:event]) {
    return NO;
  }
  
  return YES;
}

// Mirrors behavior of navigation bar at bottom of Springboard:
// - tapping left-half always decreases
// - tapping right-half always increases
- (void) endTrackingWithTouch:(UITouch*)touch withEvent:(UIEvent*)event {
  [super endTrackingWithTouch:touch withEvent:event];
  
  CGPoint point = [touch locationInView:self];
  if (CGRectContainsPoint(self.bounds, point)) {
    NSUInteger index = [_items indexOfObject:_selectedItem];
    if (point.x >= self.bounds.size.width / 2.0) {
      if (index < _items.count - 1) {
        ++index;
      }
    } else {
      if (index > 0) {
        --index;
      }
    }
    id item = [_items objectAtIndex:index];
    if (item != _selectedItem) {
      self.selectedItem = item;
      [self sendActionsForControlEvents:UIControlEventValueChanged];
    }
  }
}

@end
