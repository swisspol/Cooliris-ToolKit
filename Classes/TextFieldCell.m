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

#import "TextFieldCell.h"

#define kMargin 10.0
#define kOffset 1.0

@implementation TextFieldCell

@synthesize textField=_textField, alwaysEditable=_alwaysEditable, delegate=_delegate, labelWidth=_labelWidth;

- (id) initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString*)reuseIdentifier {
  if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
    _textField = [[UITextField alloc] init];
    _textField.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    _textField.adjustsFontSizeToFitWidth = YES;
    [self.contentView addSubview:_textField];
    
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didBeginEditing:)
                                                 name:UITextFieldTextDidBeginEditingNotification
                                               object:_textField];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(textDidChange:)
                                                 name:UITextFieldTextDidChangeNotification
                                               object:_textField];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didEndEditing:)
                                                 name:UITextFieldTextDidEndEditingNotification
                                               object:_textField];
  }
  return self;
}

- (void) dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self name:UITextFieldTextDidBeginEditingNotification object:_textField];
  [[NSNotificationCenter defaultCenter] removeObserver:self name:UITextFieldTextDidChangeNotification object:_textField];
  [[NSNotificationCenter defaultCenter] removeObserver:self name:UITextFieldTextDidEndEditingNotification object:_textField];
  
  [_textField release];
  
  [super dealloc];
}

- (void) layoutSubviews {
  [super layoutSubviews];
  
  CGRect contentBounds = self.contentView.bounds;
  
  CGRect labelFrame = self.textLabel.frame;
  if (_labelWidth > 0.0) {
    labelFrame.size.width = _labelWidth;
  } else {
    CGSize size = [self.textLabel sizeThatFits:contentBounds.size];
    labelFrame.size.width = size.width;
  }
  self.textLabel.frame = labelFrame;
  
  CGRect fieldFrame;
  fieldFrame.origin.x = labelFrame.origin.x + labelFrame.size.width + kMargin;
  fieldFrame.origin.y = kOffset;
  fieldFrame.size.width = contentBounds.size.width - fieldFrame.origin.x - kMargin;
  fieldFrame.size.height = contentBounds.size.height - kOffset;
  _textField.frame = fieldFrame;
}

- (void) setSelected:(BOOL)selected animated:(BOOL)animated {
  [super setSelected:selected animated:animated];
  
  if (selected) {
    [_textField becomeFirstResponder];
  }
}

- (void) setEditing:(BOOL)editing animated:(BOOL)animated {
  [super setEditing:editing animated:animated];
  
  if (!_alwaysEditable) {
    _textField.enabled = editing;
  }
}

- (void) textDidChange:(NSNotification*)notification {
  if ([_delegate respondsToSelector:@selector(textFieldCellTextDidChange:)]) {
    [_delegate textFieldCellTextDidChange:self];
  }
}

- (void) didBeginEditing:(NSNotification*)notification {
  // The text field intercepts the touch event so we need to select the row manually
  // This does not trigger the -didSelectRow delegate method though
  UITableView* tableView = (UITableView*)self.superview;
  [tableView selectRowAtIndexPath:[tableView indexPathForCell:self]
                         animated:YES
                   scrollPosition:UITableViewScrollPositionNone];
  
  if ([_delegate respondsToSelector:@selector(textFieldCellDidBeginEditing:)]) {
    [_delegate textFieldCellDidBeginEditing:self];
  }
}

- (void) didEndEditing:(NSNotification*)notification {
  if ([_delegate respondsToSelector:@selector(textFieldCellDidEndEditing:)]) {
    [_delegate textFieldCellDidEndEditing:self];
  }
}

- (void) setAlwaysEditable:(BOOL)flag {
  _alwaysEditable = flag;
  if (_alwaysEditable) {
    _textField.enabled = YES;  // Makes sure that setting the flag takes immediate effect
  }
}

- (void) setLabelWidth:(CGFloat)width {
  _labelWidth = width;
  [self setNeedsLayout];
}

@end
