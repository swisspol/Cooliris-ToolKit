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

#import "FormTableController.h"
#import "Logging.h"

#define kPlaceholderKey @"placeholder"  // NSString
#define kLabelKey @"label"  // NSString
#define kValueKey @"value"  // NSString
#define kIdentifierKey @"identifier"  // NSString
#define kTypeKey @"type"  // NSString
#define kSection_FieldsKey @"fields"  // NSArray of NSStrings
#define kSection_HeaderKey @"header"  // NSString
#define kSection_FooterKey @"footer"  // NSString

@interface FormTableController ()
- (NSDictionary*) _fieldWithIdentifier:(NSString*)identifier inSection:(NSUInteger)section;
@end

@implementation FormTableController

@synthesize labelWidth=_labelWidth;

- (id) init {
  return [self initWithStyle:UITableViewStyleGrouped];
}

- (id) initWithStyle:(UITableViewStyle)style {
  if ((self = [super initWithStyle:style])) {
    _data = [[NSMutableArray alloc] init];
    _labelWidth = 0.0;
  }
  return self;
}

- (void) dealloc {
  [_data release];
  
  [super dealloc];
}

- (void) viewDidLoad {
  [super viewDidLoad];
  
  self.tableView.alwaysBounceVertical = NO;
  self.tableView.alwaysBounceHorizontal = NO;
  self.tableView.allowsSelectionDuringEditing = YES;
}

- (BOOL) validateFields {
  NSUInteger currentSection = 0;
  for (NSDictionary* section in _data) {
    for (NSDictionary* field in [section objectForKey:kSection_FieldsKey]) {
      BOOL result = [self validateFieldWithIdentifier:[field objectForKey:kIdentifierKey]
                                                value:[field objectForKey:kValueKey]
                                                 type:[field objectForKey:kTypeKey]
                                            inSection:currentSection];
      if (!result) {
        return NO;
      }
    }
    ++currentSection;
  }
  return YES;
}

- (BOOL) validateFieldWithIdentifier:(NSString*)identifier
                               value:(id)value
                                type:(NSString*)type
                           inSection:(NSUInteger)section {
  return YES;
}

- (NSUInteger) addSection {
  return [self addSectionWithHeader:nil footer:nil];
}

- (NSUInteger) addSectionWithHeader:(NSString*)header footer:(NSString*)footer {
  NSMutableDictionary* section = [NSMutableDictionary dictionaryWithObject:[NSMutableArray array] forKey:kSection_FieldsKey];
  [section setValue:header forKey:kSection_HeaderKey];
  [section setValue:footer forKey:kSection_FooterKey];
  [_data addObject:section];
  return _data.count - 1;
}

- (void) removeSectionAtIndex:(NSUInteger)index {
  if (index <= [_data count]) {
    [_data removeObjectAtIndex:index];
  }
}

- (void) addFieldWithLabel:(NSString*)label
               placeholder:(NSString*)placeholder
                     value:(id)value
                identifier:(NSString*)identifier
                      type:(NSString*)type
                   toSection:(NSUInteger)section {
  CHECK(section <= _data.count);
  
  NSMutableDictionary* field = [[NSMutableDictionary alloc] init];
  [field setValue:label forKey:kLabelKey];
  [field setValue:placeholder forKey:kPlaceholderKey];
  [field setValue:value forKey:kValueKey];
  [field setValue:identifier forKey:kIdentifierKey];
  [field setValue:(type ? type : kFormTableControllerFieldType_Text) forKey:kTypeKey];
  if (section == _data.count) {
    [self addSection];
  }
  [[[_data objectAtIndex:section] objectForKey:kSection_FieldsKey] addObject:field];
  [field release];
}

- (NSArray*) fieldsInSection:(NSUInteger)section {
  CHECK(section <= _data.count);
  NSMutableArray* identifiers = [NSMutableArray array];
  for (NSDictionary* field in [[_data objectAtIndex:section] objectForKey:kSection_FieldsKey]) {
    [identifiers addObject:[field objectForKey:kIdentifierKey]];
  }
  return identifiers;
}

- (NSDictionary*) _fieldWithIdentifier:(NSString*)identifier inSection:(NSUInteger)section {
  CHECK(section < _data.count);
  NSArray* fields = [[_data objectAtIndex:section] objectForKey:kSection_FieldsKey];
  NSUInteger index = [fields indexOfObjectPassingTest:^(id obj, NSUInteger idx, BOOL* stop) {
    return [[obj objectForKey:kIdentifierKey] isEqualToString:identifier];
  }];
  return (index != NSNotFound) ? [fields objectAtIndex:index] : nil;
}

- (id) valueForFieldWithIdentifier:(NSString*)identifier inSection:(NSUInteger)section {
  return [[self _fieldWithIdentifier:identifier inSection:section] objectForKey:kValueKey];
}

- (void) setValue:(id)value forFieldWithIdentifier:(NSString*)identifier inSection:(NSUInteger)section {
  [[self _fieldWithIdentifier:identifier inSection:section] setValue:value forKey:kValueKey];
}

- (void) removeFieldWithIdentifier:(NSString*)identifier inSection:(NSUInteger)section {
  NSMutableArray* fields = [[_data objectAtIndex:section] objectForKey:kSection_FieldsKey];
  id objectToDelete = nil;
  for (NSDictionary* field in fields) {
    if ([[field valueForKey:kIdentifierKey] isEqualToString:identifier]) {
      objectToDelete = field;
      break;
    }
  }
  if (objectToDelete) {
    [fields removeObject:objectToDelete];
  }
}

- (BOOL) shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation {
  if (([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) &&
      (toInterfaceOrientation == UIInterfaceOrientationPortraitUpsideDown)) {
    return NO;
  }
  return YES;
}

- (void) viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  
  TextFieldCell* cell = (TextFieldCell*)[self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
  if ([cell isKindOfClass:[TextFieldCell class]]) {
    [cell.textField becomeFirstResponder];
  }
}

- (void) viewWillDisappear:(BOOL)animated {
  [super viewWillDisappear:animated];
  
  [self.tableView endEditing:YES];
}

- (void) textFieldCellTextDidChange:(TextFieldCell*)cell {
  NSIndexPath* cellPath = [self.tableView indexPathForCell:cell];
  [[[[_data objectAtIndex:cellPath.section] objectForKey:kSection_FieldsKey] objectAtIndex:cellPath.row] setObject:cell.textField.text
                                                                                                            forKey:kValueKey];
}

- (NSInteger) numberOfSectionsInTableView:(UITableView*)tableView {
  return _data.count;
}

- (NSInteger) tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
  return [[[_data objectAtIndex:section] objectForKey:kSection_FieldsKey] count];
}

- (UITableViewCell*) tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath {
  NSDictionary* fieldInfo = [[[_data objectAtIndex:indexPath.section] objectForKey:kSection_FieldsKey] objectAtIndex:indexPath.row];
  NSString* fieldType = [fieldInfo objectForKey:kTypeKey];
  if ([fieldType isEqualToString:kFormTableControllerFieldType_Text] ||
    [fieldType  isEqualToString:kFormTableControllerFieldType_ASCII] ||
    [fieldType isEqualToString:kFormTableControllerFieldType_Password]) {
    TextFieldCell* cell = (TextFieldCell*)[tableView dequeueReusableCellWithIdentifier:kFormTableControllerFieldType_Text];
    if (cell == nil) {
      cell = [[[TextFieldCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kFormTableControllerFieldType_Text] autorelease];
      cell.delegate = self;
      cell.alwaysEditable = YES;
    }
    if ([fieldType isEqualToString:kFormTableControllerFieldType_ASCII]) {
      cell.textField.keyboardType = UIKeyboardTypeASCIICapable;
      cell.textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
      cell.textField.autocorrectionType = UITextAutocorrectionTypeNo;
    } else {
      cell.textField.keyboardType = UIKeyboardTypeDefault;
      cell.textField.autocapitalizationType = UITextAutocapitalizationTypeSentences;
      cell.textField.autocorrectionType = UITextAutocorrectionTypeDefault;
    }
    if ([fieldType isEqualToString:kFormTableControllerFieldType_Password]) {
      cell.textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
      cell.textField.autocorrectionType = UITextAutocorrectionTypeNo;
      cell.textField.secureTextEntry = YES;
    }
    cell.textLabel.text = [fieldInfo objectForKey:kLabelKey];
    cell.textField.text = [fieldInfo objectForKey:kValueKey];
    cell.textField.placeholder = [fieldInfo objectForKey:kPlaceholderKey];
    cell.labelWidth = _labelWidth;
    
    return cell;
  } else if ([fieldType isEqualToString:kFormTableControllerFieldType_CheckBox]) {
    UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:kFormTableControllerFieldType_CheckBox];
    if (cell == nil) {
      cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kFormTableControllerFieldType_CheckBox] autorelease];
    }
    cell.textLabel.text = [fieldInfo objectForKey:@"label"];
    cell.accessoryType = UITableViewCellAccessoryNone;
    if ([[fieldInfo objectForKey:@"value"] isEqual:[NSNumber numberWithBool:YES]]) {
      cell.accessoryType = UITableViewCellAccessoryCheckmark;
    }
    
    return cell;
  } else {
    NOT_REACHED();
  }
  return nil;
}
       
- (void) tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
  UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
  NSMutableDictionary* fieldInfo = [[[_data objectAtIndex:indexPath.section] objectForKey:@"fields"] objectAtIndex:indexPath.row];
  if ([[fieldInfo objectForKey:@"type"] isEqualToString:kFormTableControllerFieldType_CheckBox]) {
    if (cell.accessoryType == UITableViewCellAccessoryCheckmark) {
      cell.accessoryType = UITableViewCellAccessoryNone;
      [fieldInfo setObject:[NSNumber numberWithBool:NO] forKey:@"value"];
    } else {
      cell.accessoryType = UITableViewCellAccessoryCheckmark;
      [fieldInfo setObject:[NSNumber numberWithBool:YES] forKey:@"value"];
    }
    [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
  }
}

- (NSString*) tableView:(UITableView*)tableView titleForHeaderInSection:(NSInteger)section {
  return [[_data objectAtIndex:section] objectForKey:kSection_HeaderKey];
}

- (NSString*) tableView:(UITableView*)tableView titleForFooterInSection:(NSInteger)section {
  return [[_data objectAtIndex:section] objectForKey:kSection_FooterKey];
}

@end
