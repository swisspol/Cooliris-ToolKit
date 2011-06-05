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

#define kFormTableControllerFieldType_Text @"text"
#define kFormTableControllerFieldType_ASCII @"ascii"
#define kFormTableControllerFieldType_Password @"password"
#define kFormTableControllerFieldType_CheckBox @"checkBox"

@interface FormTableController : UITableViewController <TextFieldCellDelegate> {
@private
  NSMutableArray* _data;
  CGFloat _labelWidth;
}
@property(nonatomic) CGFloat labelWidth;

- (NSUInteger) addSection;
- (NSUInteger) addSectionWithHeader:(NSString*)header footer:(NSString*)footer;  // Returns section index
- (void) removeSectionAtIndex:(NSUInteger)index;

- (NSArray*) fieldsInSection:(NSUInteger)section;  // Returns an array of field identifiers
- (void) addFieldWithLabel:(NSString*)label
               placeholder:(NSString*)placeholder
                     value:(id)value
                identifier:(NSString*)identifier
                      type:(NSString*)type
                 toSection:(NSUInteger)section;
- (void) setValue:(id)value forFieldWithIdentifier:(NSString*)identifier inSection:(NSUInteger)section;
- (id) valueForFieldWithIdentifier:(NSString*)identifier inSection:(NSUInteger)section;
- (void) removeFieldWithIdentifier:(NSString*)identifier inSection:(NSUInteger)section;

- (BOOL) validateFieldWithIdentifier:(NSString*)identifier
                               value:(id)value
                                type:(NSString*)type
                           inSection:(NSUInteger)section;  // For subclasses
- (BOOL) validateFields;
@end
