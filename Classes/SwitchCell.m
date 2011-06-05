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

#import "SwitchCell.h"

#define kMargin 10.0

@implementation SwitchCell

@synthesize control=_control, delegate=_delegate;

- (void) _didChange:(id)sender {
  if ([_delegate respondsToSelector:@selector(switchCellTextDidChange:)]) {
    [_delegate switchCellTextDidChange:self];
  }
}

- (id) initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString*)reuseIdentifier {
  if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
    _control = [[UISwitch alloc] init];
    [self.contentView addSubview:_control];
    
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    
    [_control addTarget:self action:@selector(_didChange:) forControlEvents:UIControlEventValueChanged];
  }
  return self;
}

- (void) dealloc {
  [_control release];
  
  [super dealloc];
}

- (void) layoutSubviews {
  [super layoutSubviews];
  
  CGRect contentBounds = self.contentView.bounds;
  
  CGRect controlFrame = _control.frame;
  controlFrame.origin.x = contentBounds.size.width - controlFrame.size.width - kMargin;
  controlFrame.origin.y = roundf((contentBounds.size.height - controlFrame.size.height) / 2.0);
  _control.frame = controlFrame;
  
  CGRect labelFrame = self.textLabel.frame;
  labelFrame.size.width = controlFrame.origin.x - kMargin - labelFrame.origin.x;
  self.textLabel.frame = labelFrame;
}

@end
