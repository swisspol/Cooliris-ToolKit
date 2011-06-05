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

#import <UIKit/UIKit.h>

@class TextFieldCell;

@protocol TextFieldCellDelegate <NSObject>
@optional
- (void) textFieldCellDidBeginEditing:(TextFieldCell*)cell;
- (void) textFieldCellTextDidChange:(TextFieldCell*)cell;
- (void) textFieldCellDidEndEditing:(TextFieldCell*)cell;
@end

@interface TextFieldCell : UITableViewCell {
@private
  UITextField* _textField;
  CGFloat _labelWidth;
  BOOL _alwaysEditable;
  id<TextFieldCellDelegate> _delegate;
}
@property(nonatomic, assign) id<TextFieldCellDelegate> delegate;
@property(nonatomic, readonly) UITextField* textField;
@property(nonatomic, getter=isAlwaysEditable) BOOL alwaysEditable;  // Causes the text field to be editable even if the table view is not in an editable state
@property(nonatomic) CGFloat labelWidth;
@end
